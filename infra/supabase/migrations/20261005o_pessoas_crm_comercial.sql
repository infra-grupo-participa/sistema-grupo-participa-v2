-- 20261005o: Comercial, base única de pessoas (schema pessoas) e CRM (schema crm)
--
-- STATUS: NÃO APLICADA. Proposta da branch victor (05/10/2026). Depende da 20261005m (mkt.projetos, mkt.paginas), já
-- aplicada. Conversa com a 20261005n (mkt_web.visitantes.lead_ref) se ela estiver aplicada, sem depender dela.
--
-- O QUE FAZ
--   1. pessoas: UMA pessoa por identidade, para a central inteira (regra do Victor, 05/10/2026: "o mesmo dado não se
--      duplica; se o aluno já existe, tudo se liga a ele"). O lead do Marketing mora aqui (decisão da Web: a Web guarda só
--      a referência opaca pessoas.pessoas.ref em mkt_web.visitantes.lead_ref, nunca e-mail ou telefone).
--      - Aluno e comprador NÃO são copiados: a pessoa aponta para public.thb_alunos(id) e public.compradores(id) e a ficha
--        lê nome, e-mail, telefone, turma e compras de lá, na hora. Hierarquia de fonte da verdade do disparos-thb:
--        Hotmart (public.compras) manda no dinheiro, thb_alunos manda na matrícula. Esta base não grava valor nenhum.
--      - Dado PRÓPRIO só do que não existe em lugar nenhum: o que o lead digitou no formulário (identificadores
--        normalizados), a origem (projeto, página, campanha, UTMs) e o histórico de eventos.
--      - Cascata de identidade da casa (Central-de-Alunos/CLAUDE.md): documento → telefone (DDD + 8 últimos) → e-mail →
--        nome + CEP. Documento ou telefone que batem com NOME diferente não fundem (vão para revisão). Só o nome bate →
--        pessoa nova marcada para revisão. Nada é fundido sozinho quando há dúvida: quem decide é uma pessoa
--        (public.pessoas_revisao_decidir), e a mescla leva origens, eventos e negócios para a pessoa que fica.
--   2. crm: o CRM do Comercial, com 4 pipelines separados (ativação, vendas, recuperação de carrinho, recuperação de
--      venda), etapas configuráveis, responsável, próximo passo, motivo de perda, projeto e pessoa. Ativação = contato
--      SEM intenção de vender (ensinar a entrar na área de membros ou no evento), explicação do Victor de 05/10/2026.
--      As etapas semeadas são PROPOSTA (nomes genéricos, configuráveis pela RPC crm_etapa_salvar); motivos de perda
--      nascem vazios (não inventar regra comercial). Não toca no schema cs (disparos-thb): o card do HM continua lá.
--      crm.negocios.externo_tipo/externo_id deixam o gancho para apontar um card do cs.contatos_hm, sem cópia.
--
-- ACESSO (LGPD)
--   - Tabelas fechadas (RLS ligada, sem policy, sem USAGE nos schemas para anon/authenticated). Só funções public.*.
--   - Quem vê: admin e dev (mesma regra do Marketing). Gancho pronto: pessoas.config 'areas_leitura', 'areas_edicao' e
--     'areas_contato' (listas de perfis.areas, vazias) liberam gestor/operador ativo de uma área sem mexer em função.
--   - Documento sem máscara só com public.gp_pode_ver_cpf() (padrão podeVerCpf, 20260819g). E-mail e telefone completos
--     só para admin/dev ou 'areas_contato'; os outros veem mascarado. A máscara é feita no SQL, não na tela.
--   - pessoas.acessos registra quem buscou, abriu ficha, cadastrou, revisou e mexeu no CRM (sem gravar o termo buscado).
--   - Gravar lead de formulário: public.pessoas_registrar_lead só para service_role (servidor), nunca do navegador.
--
-- O QUE CRIA
--   schema pessoas: config, pessoas, identificadores, origens, eventos, revisao, acessos
--                   funções internas (sem grant): normalização, casar, resolver, registrar, mesclar, máscaras, permissões
--   schema crm:     pipelines, etapas, motivos_perda, negocios, historico; crm.validar_movimento (pura)
--   public.pessoas_meu_acesso, pessoas_buscar, pessoas_ficha, pessoas_cadastrar, pessoas_revisao_listar,
--          pessoas_revisao_decidir                                                  → authenticated + permissão no corpo
--   public.pessoas_registrar_lead                                                    → só service_role
--   public.crm_config, crm_negocios_listar, crm_negocio_criar, crm_negocio_mover, crm_negocio_editar,
--          crm_negocio_historico, crm_etapa_salvar, crm_motivo_salvar               → authenticated + permissão no corpo
--
-- AS 5 PERGUNTAS
--   escala: milhares de leads por projeto (o PB teve ~10% de 1.500 visitas/dia virando lead); ~2 mil alunos; negócios
--     abertos na casa das centenas por pipeline.
--   índice: identificadores (tipo, chave) com único parcial para documento e e-mail; pessoas (aluno_id), (comprador_id)
--     únicos; origens (pessoa_id), (projeto_id, quando); eventos (pessoa_id, quando); negocios (pipeline_id, status,
--     etapa_id), (pessoa_id), (responsavel_id), único parcial de negócio aberto por pessoa+pipeline+projeto.
--   frequência: 1 resolução por lead (a cascata lê thb_alunos inteira, ~2 mil linhas, e compradores por documento e
--     telefone, sem índice de expressão: medir no banco real); as telas leem ao abrir.
--   repetição: por lead, até 4 consultas de casamento e poucos inserts; nada por linha nas telas.
--   reversão: bloco REVERSÃO no fim (apaga as duas bases; exportar antes se houver dado real).
--
-- ENSAIO: infra/supabase/migrations/20261005o_ensaio.sql (begin … rollback). Explicação: 20261005o.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_falta text;
begin
  if to_regnamespace('pessoas') is not null or to_regnamespace('crm') is not null then
    raise exception '20261005o: schema pessoas ou crm já existe (migration já aplicada?)';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and (p.proname like 'pessoas\_%' or p.proname like 'crm\_%')) then
    raise exception '20261005o: já existem funções public.pessoas_* ou public.crm_*';
  end if;
  if to_regclass('mkt.projetos') is null or to_regclass('mkt.paginas') is null
     or to_regprocedure('mkt.campanha_traduzir(text)') is null or to_regprocedure('mkt.sem_acento(text)') is null then
    raise exception '20261005o: falta a 20261005m (mkt.projetos, mkt.paginas, mkt.campanha_traduzir, mkt.sem_acento)';
  end if;
  if to_regprocedure('public.gp_is_admin()') is null or to_regprocedure('public.gp_pode_ver_cpf()') is null then
    raise exception '20261005o: public.gp_is_admin() ou public.gp_pode_ver_cpf() ausente';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception '20261005o: papel service_role ausente';
  end if;
  select string_agg(x.t || '.' || x.c, ', ') into v_falta
    from (values
      ('perfis','id'), ('perfis','nome'), ('perfis','cargo'), ('perfis','status'), ('perfis','areas'),
      ('thb_alunos','id'), ('thb_alunos','nome'), ('thb_alunos','email'), ('thb_alunos','telefone'),
      ('thb_alunos','documento'), ('thb_alunos','cep'), ('thb_alunos','comprador_id'), ('thb_alunos','turma_id'),
      ('thb_alunos','cancelado_em'), ('thb_turmas','id'), ('thb_turmas','codigo'),
      ('compradores','id'), ('compradores','nome'), ('compradores','email'), ('compradores','telefone'),
      ('compradores','documento'),
      ('compras','id'), ('compras','comprador_id'), ('compras','status'), ('compras','produto_nome'),
      ('compras','data_compra'), ('compras','preco')
    ) x(t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = 'public' and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then
    raise exception '20261005o: colunas ausentes: %', v_falta;
  end if;
end
$guarda$;

-- ─── 1. Schemas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create schema pessoas;
revoke all on schema pessoas from public, anon, authenticated;
comment on schema pessoas is
  'Base única de pessoas da central (lead, aluno, comprador = a mesma pessoa). Aluno e comprador por referência; dado '
  'próprio só o que o lead informou, a origem e os eventos. Fechado: acesso só pelas funções public.pessoas_*. 20261005o.';

create schema crm;
revoke all on schema crm from public, anon, authenticated;
comment on schema crm is
  'CRM do Comercial: pipelines ativação, vendas, recuperação de carrinho e recuperação de venda. Cada negócio aponta '
  'para uma pessoa (pessoas.pessoas) e um projeto (mkt.projetos). Fechado: acesso só pelas funções public.crm_*. 20261005o.';

-- ─── 2. Configuração e permissões ────────────────────────────────────────────────────────────────────────────────────
create table pessoas.config (
  chave text primary key,
  valor jsonb not null,
  obs   text
);
alter table pessoas.config enable row level security;
insert into pessoas.config (chave, valor, obs) values
  ('areas_leitura', '[]', 'Áreas de perfis.areas cujo gestor/operador ATIVO lê a base de pessoas e o CRM, além de admin e '
                          'dev. Vazio = só admin e dev (regra do Marketing, 05/10/2026). Gancho dos níveis de acesso.'),
  ('areas_edicao',  '[]', 'Áreas que cadastram pessoa, decidem revisão e mexem no CRM, além de admin e dev. Vazio = só '
                          'admin e dev.'),
  ('areas_contato', '[]', 'Áreas que veem e-mail e telefone completos, além de admin e dev. Os outros veem mascarado.');

create function pessoas.areas_config(p_chave text) returns text[]
language sql stable set search_path = '' as $$
  select coalesce((select array_agg(e) from pessoas.config c, jsonb_array_elements_text(c.valor) e
                    where c.chave = p_chave), '{}'::text[]);
$$;

-- gestor/operador ativo com alguma das áreas configuradas
create function pessoas.tem_area(p_chave text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfis p
                  where p.id = (select auth.uid()) and p.status = 'ativo' and p.cargo in ('gestor', 'operador')
                    and coalesce(p.areas, '{}') && pessoas.areas_config(p_chave));
$$;

create function pessoas.pode_ver() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false) or pessoas.tem_area('areas_leitura');
$$;

create function pessoas.pode_editar() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false) or pessoas.tem_area('areas_edicao');
$$;

create function pessoas.pode_ver_contato() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false) or (pessoas.pode_ver() and pessoas.tem_area('areas_contato'));
$$;

-- documento sem máscara: quem lê a base E tem podeVerCpf (public.gp_pode_ver_cpf, 20260819g)
create function pessoas.pode_ver_doc() returns boolean
language sql stable security definer set search_path = '' as $$
  select pessoas.pode_ver() and coalesce(public.gp_pode_ver_cpf(), false);
$$;

-- ─── 3. Normalização (pura; a mesma regra em web/modules/comercial/domain/identidade.ts, com testes) ─────────────────
create function pessoas.so_digitos(p text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g');
$$;

-- CPF (11) ou CNPJ (14) com dígito verificador certo; sequência repetida é inválida
create function pessoas.doc_valido(d text) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  s int; r int; i int;
  p1 int[] := array[5,4,3,2,9,8,7,6,5,4,3,2];
  p2 int[] := array[6,5,4,3,2,9,8,7,6,5,4,3,2];
begin
  if d is null or d !~ '^[0-9]+$' or d ~ '^(.)\1*$' then return false; end if;
  if length(d) = 11 then
    s := 0; for i in 1..9 loop s := s + substr(d, i, 1)::int * (11 - i); end loop;
    r := (s * 10) % 11; if r = 10 then r := 0; end if;
    if r <> substr(d, 10, 1)::int then return false; end if;
    s := 0; for i in 1..10 loop s := s + substr(d, i, 1)::int * (12 - i); end loop;
    r := (s * 10) % 11; if r = 10 then r := 0; end if;
    return r = substr(d, 11, 1)::int;
  elsif length(d) = 14 then
    s := 0; for i in 1..12 loop s := s + substr(d, i, 1)::int * p1[i]; end loop;
    r := s % 11; r := case when r < 2 then 0 else 11 - r end;
    if r <> substr(d, 13, 1)::int then return false; end if;
    s := 0; for i in 1..13 loop s := s + substr(d, i, 1)::int * p2[i]; end loop;
    r := s % 11; r := case when r < 2 then 0 else 11 - r end;
    return r = substr(d, 14, 1)::int;
  end if;
  return false;
end
$$;

-- só dígitos, zeros à esquerda devolvidos (CPF 9 a 11 dígitos → 11; CNPJ 12 a 14 → 14); inválido = null (não casa)
create function pessoas.norm_documento(p text) returns text
language plpgsql immutable set search_path = '' as $$
declare d text := pessoas.so_digitos(p);
begin
  if length(d) between 9 and 11 then d := lpad(d, 11, '0');
  elsif length(d) between 12 and 14 then d := lpad(d, 14, '0');
  else return null; end if;
  return case when pessoas.doc_valido(d) then d end;
end
$$;

-- telefone BR: tira 55 e o 0 de longa distância; sobra DDD (11 a 99, sem zero) + 8 ou 9 dígitos (9 dígitos começa com 9)
create function pessoas.norm_telefone(p text) returns text
language plpgsql immutable set search_path = '' as $$
declare d text := pessoas.so_digitos(p);
begin
  if length(d) in (12, 13) and left(d, 2) = '55' then d := substr(d, 3); end if;
  if length(d) in (11, 12) and left(d, 1) = '0' then d := substr(d, 2); end if;
  if length(d) not in (10, 11) then return null; end if;
  if substr(d, 1, 1) = '0' or substr(d, 2, 1) = '0' then return null; end if;
  if length(d) = 11 and substr(d, 3, 1) <> '9' then return null; end if;
  return d;
end
$$;

-- chave de casamento do telefone: DDD + 8 últimos (o 9 a mais do celular não separa a mesma pessoa)
create function pessoas.chave_telefone(p_norm text) returns text
language sql immutable set search_path = '' as $$
  select case when p_norm is not null then left(p_norm, 2) || right(p_norm, 8) end;
$$;

create function pessoas.norm_email(p text) returns text
language sql immutable set search_path = '' as $$
  select case when lower(btrim(p)) ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then lower(btrim(p)) end;
$$;

-- nome para comparar: maiúsculas, sem acento, só letras e um espaço entre palavras
create function pessoas.norm_nome(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(btrim(regexp_replace(regexp_replace(mkt.sem_acento(coalesce(p, '')), '[^A-Z ]', ' ', 'g'), ' +', ' ', 'g')), '');
$$;

create function pessoas.norm_cep(p text) returns text
language sql immutable set search_path = '' as $$
  select case when length(pessoas.so_digitos(p)) = 8 and pessoas.so_digitos(p) !~ '^0+$' then pessoas.so_digitos(p) end;
$$;

-- nome + CEP só vale com nome de 2 palavras ou mais
create function pessoas.chave_nome_cep(p_nome text, p_cep text) returns text
language sql immutable set search_path = '' as $$
  select case when pessoas.norm_nome(p_nome) like '% %' and pessoas.norm_cep(p_cep) is not null
              then pessoas.norm_nome(p_nome) || '|' || pessoas.norm_cep(p_cep) end;
$$;

-- nomes compatíveis = mesmo primeiro nome (sem informação de um dos lados = não contradiz)
create function pessoas.nomes_compativeis(a text, b text) returns boolean
language sql immutable set search_path = '' as $$
  select pessoas.norm_nome(a) is null or pessoas.norm_nome(b) is null
      or split_part(pessoas.norm_nome(a), ' ', 1) = split_part(pessoas.norm_nome(b), ' ', 1);
$$;

-- máscaras (mesma regra do mascarar() da tela: só os 4 últimos)
create function pessoas.mascara_fim(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p is null or p = '' then p else repeat('*', greatest(length(p) - 4, 0)) || right(p, 4) end;
$$;

create function pessoas.mascara_email(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p is null or position('@' in p) = 0 then p
              else left(split_part(p, '@', 1), 1) || '***@' || split_part(p, '@', 2) end;
$$;

-- ─── 4. Tabelas da base de pessoas ───────────────────────────────────────────────────────────────────────────────────
create table pessoas.pessoas (
  id            uuid primary key default gen_random_uuid(),
  -- referência OPACA (aleatória, não deriva de e-mail/telefone): é o que a Web e outros sistemas guardam
  ref           text not null unique default ('pe_' || replace(gen_random_uuid()::text, '-', ''))
                  check (ref ~ '^pe_[0-9a-f]{32}$'),
  nome          text check (nome is null or length(btrim(nome)) between 2 and 160),   -- só de quem não é aluno/comprador
  aluno_id      uuid unique references public.thb_alunos(id) on delete set null,      -- referência, nunca cópia
  comprador_id  uuid unique references public.compradores(id) on delete set null,     -- referência, nunca cópia
  situacao      text not null default 'ativa' check (situacao in ('ativa', 'revisar', 'mesclada')),
  mesclada_em   uuid references pessoas.pessoas(id),
  teste         boolean not null default false,
  criado_em     timestamptz not null default now(),
  criado_por    uuid references public.perfis(id) on delete set null,
  atualizado_em timestamptz not null default now(),
  constraint pessoas_mescla_check check ((situacao = 'mesclada') = (mesclada_em is not null)),
  constraint pessoas_mesclada_solta_check check (situacao <> 'mesclada' or (aluno_id is null and comprador_id is null))
);
alter table pessoas.pessoas enable row level security;
create index pessoas_mesclada_idx on pessoas.pessoas (mesclada_em) where mesclada_em is not null;
comment on table pessoas.pessoas is 'Uma linha por pessoa. ref = referência opaca para outros sistemas (mkt_web.visitantes.lead_ref). '
  'Aluno e comprador por referência. situacao revisar = pessoa nova que pode ser alguém que já existe (ver pessoas.revisao).';

-- o que a pessoa informou (normalizado). Valor de aluno/comprador ligado NÃO entra aqui (é lido de lá).
create table pessoas.identificadores (
  id        bigint generated always as identity primary key,
  pessoa_id uuid not null references pessoas.pessoas(id) on delete cascade,
  tipo      text not null check (tipo in ('documento', 'telefone', 'email', 'nome_cep')),
  valor     text not null check (length(valor) between 1 and 200),
  chave     text not null check (length(chave) between 1 and 200),
  origem    text not null check (origem in ('formulario', 'crm', 'importacao')),
  criado_em timestamptz not null default now(),
  unique (pessoa_id, tipo, chave)
);
alter table pessoas.identificadores enable row level security;
-- documento e e-mail são de UMA pessoa só (telefone e nome+CEP podem ser divididos: família, sócio)
create unique index identificadores_forte_unico on pessoas.identificadores (tipo, chave) where tipo in ('documento', 'email');
create index identificadores_chave_idx on pessoas.identificadores (tipo, chave);

-- de onde o lead veio (uma linha por entrada): projeto, página, campanha no padrão da casa e UTMs
create table pessoas.origens (
  id              bigint generated always as identity primary key,
  pessoa_id       uuid not null references pessoas.pessoas(id) on delete cascade,
  projeto_id      bigint references mkt.projetos(id) on delete restrict,
  pagina_id       bigint references mkt.paginas(id) on delete set null,
  campanha        text check (campanha is null or length(campanha) <= 300),
  campanha_padrao boolean,
  utm_source      text check (utm_source is null or length(utm_source) <= 300),
  utm_medium      text check (utm_medium is null or length(utm_medium) <= 300),
  utm_campaign    text check (utm_campaign is null or length(utm_campaign) <= 300),
  utm_content     text check (utm_content is null or length(utm_content) <= 300),
  utm_term        text check (utm_term is null or length(utm_term) <= 300),
  de_anuncio      boolean not null default false,
  fonte           text not null check (fonte in ('formulario', 'crm', 'importacao')),
  quando          timestamptz not null default now()
);
alter table pessoas.origens enable row level security;
create index origens_pessoa_idx on pessoas.origens (pessoa_id, quando);
create index origens_projeto_idx on pessoas.origens (projeto_id, quando);

-- histórico: entrou como lead, virou MQL, foi ativado, mexeu no CRM, foi ligada a aluno, foi mesclada…
create table pessoas.eventos (
  id         bigint generated always as identity primary key,
  pessoa_id  uuid not null references pessoas.pessoas(id) on delete cascade,
  tipo       text not null check (tipo in ('lead', 'mql', 'nao_mql', 'cadastro', 'compra', 'ativacao', 'crm', 'vinculo',
                                           'mescla', 'revisao')),
  projeto_id bigint references mkt.projetos(id) on delete restrict,
  origem_id  bigint references pessoas.origens(id) on delete set null,
  fonte      text not null check (fonte in ('formulario', 'crm', 'importacao', 'sistema')),
  ref_tipo   text check (ref_tipo is null or ref_tipo in ('crm.negocios', 'public.compras', 'public.thb_alunos',
                                                         'public.compradores', 'pessoas.pessoas', 'pessoas.revisao')),
  ref_id     text check (ref_id is null or length(ref_id) <= 80),
  detalhe    jsonb not null default '{}' check (jsonb_typeof(detalhe) = 'object' and length(detalhe::text) <= 2000),
  quando     timestamptz not null default now(),
  por        uuid references public.perfis(id) on delete set null
);
alter table pessoas.eventos enable row level security;
create index eventos_pessoa_idx on pessoas.eventos (pessoa_id, quando);
create index eventos_projeto_idx on pessoas.eventos (projeto_id, tipo, quando) where projeto_id is not null;

-- dúvida de identidade para uma pessoa decidir (nunca o valor do identificador: só o tipo que bateu)
create table pessoas.revisao (
  id           bigint generated always as identity primary key,
  pessoa_id    uuid not null references pessoas.pessoas(id) on delete cascade,
  motivo       text not null check (motivo in ('so_nome', 'documento_nome_diferente', 'telefone_nome_diferente', 'conflito')),
  candidatos   uuid[] not null default '{}',
  detalhe      jsonb not null default '{}' check (jsonb_typeof(detalhe) = 'object'),
  status       text not null default 'pendente' check (status in ('pendente', 'mesma', 'diferente')),
  decidido_por uuid references public.perfis(id) on delete set null,
  decidido_em  timestamptz,
  criado_em    timestamptz not null default now()
);
alter table pessoas.revisao enable row level security;
create index revisao_pendente_idx on pessoas.revisao (criado_em) where status = 'pendente';
create index revisao_pessoa_idx on pessoas.revisao (pessoa_id);

-- quem consultou e quem alterou (LGPD). Sem FK na pessoa: o registro fica mesmo se a pessoa sair.
create table pessoas.acessos (
  id        bigint generated always as identity primary key,
  quando    timestamptz not null default now(),
  por       uuid,
  acao      text not null check (acao in ('buscar', 'ver_ficha', 'cadastrar', 'revisar', 'crm_criar', 'crm_mover',
                                          'crm_editar', 'crm_config')),
  pessoa_id uuid,
  detalhe   jsonb not null default '{}' check (jsonb_typeof(detalhe) = 'object' and length(detalhe::text) <= 2000)
);
alter table pessoas.acessos enable row level security;
create index acessos_pessoa_idx on pessoas.acessos (pessoa_id, quando);
create index acessos_por_idx on pessoas.acessos (por, quando);

create function pessoas.registrar_acesso(p_acao text, p_pessoa uuid, p_detalhe jsonb default '{}') returns void
language sql security definer set search_path = '' as $$
  insert into pessoas.acessos (por, acao, pessoa_id, detalhe) values ((select auth.uid()), p_acao, p_pessoa, coalesce(p_detalhe, '{}'));
$$;

-- ─── 5. Ligação com aluno e comprador (referência) ───────────────────────────────────────────────────────────────────
-- pessoa que fica no fim de uma mescla
create function pessoas.atual(p_pessoa uuid) returns uuid
language plpgsql stable set search_path = '' as $$
declare v uuid := p_pessoa; n uuid; i int := 0;
begin
  loop
    select mesclada_em into n from pessoas.pessoas where id = v;
    exit when n is null or i > 20;
    v := n; i := i + 1;
  end loop;
  return v;
end
$$;

create function pessoas.pessoa_do_aluno(p_aluno uuid) returns uuid
language plpgsql set search_path = '' as $$
declare v uuid; v_comprador uuid;
begin
  select id into v from pessoas.pessoas where aluno_id = p_aluno;
  if found then return v; end if;
  select comprador_id into v_comprador from public.thb_alunos where id = p_aluno;
  if not found then return null; end if;
  -- o comprador do aluno já é pessoa (sem aluno)? é a mesma pessoa: liga nela
  if v_comprador is not null then
    select id into v from pessoas.pessoas where comprador_id = v_comprador and aluno_id is null and situacao <> 'mesclada';
    if found then
      update pessoas.pessoas set aluno_id = p_aluno, atualizado_em = now() where id = v;
      insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v, 'vinculo', 'sistema', 'public.thb_alunos', p_aluno::text);
      return v;
    end if;
  end if;
  insert into pessoas.pessoas (aluno_id, comprador_id)
  values (p_aluno, case when v_comprador is not null
                         and not exists (select 1 from pessoas.pessoas x where x.comprador_id = v_comprador) then v_comprador end)
  on conflict (aluno_id) do nothing
  returning id into v;
  if v is null then select id into v from pessoas.pessoas where aluno_id = p_aluno; return v; end if;
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v, 'vinculo', 'sistema', 'public.thb_alunos', p_aluno::text);
  return v;
end
$$;

create function pessoas.pessoa_do_comprador(p_comprador uuid) returns uuid
language plpgsql set search_path = '' as $$
declare v uuid; v_aluno uuid;
begin
  select id into v from pessoas.pessoas where comprador_id = p_comprador;
  if found then return v; end if;
  if not exists (select 1 from public.compradores where id = p_comprador) then return null; end if;
  -- comprador de um aluno só → a pessoa é a do aluno
  select (array_agg(a.id))[1] into v_aluno from public.thb_alunos a where a.comprador_id = p_comprador having count(*) = 1;
  if v_aluno is not null then
    v := pessoas.pessoa_do_aluno(v_aluno);
    update pessoas.pessoas set comprador_id = p_comprador, atualizado_em = now()
     where id = v and comprador_id is null and not exists (select 1 from pessoas.pessoas x where x.comprador_id = p_comprador);
    return v;
  end if;
  insert into pessoas.pessoas (comprador_id) values (p_comprador) on conflict (comprador_id) do nothing returning id into v;
  if v is null then select id into v from pessoas.pessoas where comprador_id = p_comprador; return v; end if;
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v, 'vinculo', 'sistema', 'public.compradores', p_comprador::text);
  return v;
end
$$;

-- dados para exibir: aluno e comprador lidos na hora (fonte da verdade), o resto do que a pessoa informou
create function pessoas.dados(p_pessoa uuid)
returns table (nome text, email text, telefone text, documento text, aluno_nome text, turma text, aluno_cancelado boolean)
language sql stable set search_path = '' as $$
  select coalesce(a.nome, c.nome, p.nome),
         coalesce(pessoas.norm_email(a.email), pessoas.norm_email(c.email),
                  (select i.valor from pessoas.identificadores i where i.pessoa_id = p.id and i.tipo = 'email' order by i.id desc limit 1)),
         coalesce(pessoas.norm_telefone(a.telefone), pessoas.norm_telefone(c.telefone),
                  (select i.valor from pessoas.identificadores i where i.pessoa_id = p.id and i.tipo = 'telefone' order by i.id desc limit 1)),
         coalesce(pessoas.norm_documento(a.documento), nullif(pessoas.so_digitos(a.documento), ''),
                  pessoas.norm_documento(c.documento),
                  (select i.valor from pessoas.identificadores i where i.pessoa_id = p.id and i.tipo = 'documento' order by i.id desc limit 1)),
         a.nome, t.codigo, a.cancelado_em is not null
    from pessoas.pessoas p
    left join public.thb_alunos a on a.id = p.aluno_id
    left join public.thb_turmas t on t.id = a.turma_id
    left join public.compradores c on c.id = p.comprador_id
   where p.id = p_pessoa;
$$;

-- ─── 6. Cascata de identidade ────────────────────────────────────────────────────────────────────────────────────────
-- Quem bate com um identificador. entidade: 'p:<pessoa>' (já é pessoa), 'a:<aluno>' (aluno sem pessoa), 'c:<comprador>'.
create function pessoas.casar(p_tipo text, p_chave text)
returns table (entidade text, pessoa_id uuid, aluno_id uuid, comprador_id uuid, nome text)
language plpgsql stable set search_path = '' as $$
begin
  if p_chave is null then return; end if;
  -- o que já está na base de pessoas
  return query
    select 'p:' || p.id, p.id, p.aluno_id, p.comprador_id, coalesce(a.nome, c.nome, p.nome)
      from pessoas.identificadores i
      join pessoas.pessoas p on p.id = i.pessoa_id and p.situacao <> 'mesclada'
      left join public.thb_alunos a on a.id = p.aluno_id
      left join public.compradores c on c.id = p.comprador_id
     where i.tipo = p_tipo and i.chave = p_chave;
  -- alunos (lidos na hora)
  return query
    select coalesce('p:' || pa.id, 'a:' || a.id), pa.id, a.id, coalesce(pa.comprador_id, a.comprador_id), a.nome
      from public.thb_alunos a
      left join pessoas.pessoas pa on pa.aluno_id = a.id
     where case p_tipo
             when 'documento' then pessoas.norm_documento(a.documento) = p_chave
             when 'telefone'  then pessoas.chave_telefone(pessoas.norm_telefone(a.telefone)) = p_chave
             when 'email'     then pessoas.norm_email(a.email) = p_chave
             when 'nome_cep'  then pessoas.chave_nome_cep(a.nome, a.cep) = p_chave
             else false
           end;
  -- compradores da Hotmart (lidos na hora; nome + CEP não: o endereço do comprador não entra na cascata)
  if p_tipo in ('documento', 'telefone', 'email') then
    return query
      select coalesce('p:' || coalesce(pc.id, pa.id), 'a:' || al.id, 'c:' || c.id), coalesce(pc.id, pa.id), al.id, c.id,
             coalesce(al.nome, c.nome)
        from public.compradores c
        left join pessoas.pessoas pc on pc.comprador_id = c.id
        left join lateral (select (array_agg(a2.id))[1] id, (array_agg(a2.nome))[1] nome
                             from public.thb_alunos a2 where a2.comprador_id = c.id having count(*) = 1) al on true
        left join pessoas.pessoas pa on pa.aluno_id = al.id
       where case p_tipo
               when 'documento' then pessoas.norm_documento(c.documento) = p_chave
               when 'telefone'  then pessoas.chave_telefone(pessoas.norm_telefone(c.telefone)) = p_chave
               else pessoas.norm_email(c.email) = p_chave
             end;
  end if;
end
$$;

-- garante pessoa para cada entidade (aluno/comprador sem pessoa ganham uma linha de referência)
create function pessoas.garantir(p_ents text[]) returns uuid[]
language plpgsql set search_path = '' as $$
declare e text; v uuid[] := '{}'; x uuid;
begin
  foreach e in array coalesce(p_ents, '{}') loop
    x := case left(e, 2)
           when 'p:' then substr(e, 3)::uuid
           when 'a:' then pessoas.pessoa_do_aluno(substr(e, 3)::uuid)
           when 'c:' then pessoas.pessoa_do_comprador(substr(e, 3)::uuid)
         end;
    if x is not null and not x = any(v) then v := v || x; end if;
  end loop;
  return v;
end
$$;

-- várias entidades viram UMA pessoa? Só em dois casos sem dúvida: lead sem aluno + o aluno (ou comprador) que tem o
-- mesmo identificador (o lead que virou aluno). Fora isso: null (conflito, vai para revisão).
create function pessoas.unir(p_ents text[]) returns uuid
language plpgsql set search_path = '' as $$
declare
  v_p text[]; v_a text[]; v_c text[]; v_pessoa uuid; r record;
begin
  if cardinality(p_ents) = 1 then return (pessoas.garantir(p_ents))[1]; end if;
  select array_agg(e) filter (where e like 'p:%'), array_agg(e) filter (where e like 'a:%'), array_agg(e) filter (where e like 'c:%')
    into v_p, v_a, v_c from unnest(p_ents) e;
  if coalesce(cardinality(v_p), 0) <> 1 or coalesce(cardinality(v_a), 0) + coalesce(cardinality(v_c), 0) <> 1 then return null; end if;
  v_pessoa := substr(v_p[1], 3)::uuid;
  select * into r from pessoas.pessoas where id = v_pessoa;
  if v_a is not null then
    if r.aluno_id is not null then return null; end if;
    update pessoas.pessoas
       set aluno_id = substr(v_a[1], 3)::uuid,
           comprador_id = coalesce(comprador_id,
             (select a.comprador_id from public.thb_alunos a where a.id = substr(v_a[1], 3)::uuid
                 and not exists (select 1 from pessoas.pessoas x where x.comprador_id = a.comprador_id))),
           atualizado_em = now()
     where id = v_pessoa;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.thb_alunos', substr(v_a[1], 3));
  else
    if r.comprador_id is not null then return null; end if;
    update pessoas.pessoas set comprador_id = substr(v_c[1], 3)::uuid, atualizado_em = now() where id = v_pessoa;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.compradores', substr(v_c[1], 3));
  end if;
  return v_pessoa;
end
$$;

-- A cascata: documento → telefone → e-mail → nome + CEP. Devolve a pessoa (existente ou nova) e, se houver dúvida, abre
-- a revisão. Documento/telefone com nome diferente não casam. Só nome igual → pessoa nova em revisão.
create function pessoas.resolver(p_nome text, p_email text, p_telefone text, p_documento text, p_cep text,
                                 p_teste boolean default false, p_por uuid default null)
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_passos text[] := array['documento', 'telefone', 'email', 'nome_cep'];
  v_chaves text[] := array[pessoas.norm_documento(p_documento), pessoas.chave_telefone(pessoas.norm_telefone(p_telefone)),
                           pessoas.norm_email(p_email), pessoas.chave_nome_cep(p_nome, p_cep)];
  v_nome text := pessoas.norm_nome(p_nome);
  i int;
  v_ents text[]; v_filtradas text[];
  v_pessoa uuid; v_como text;
  v_suspeitas uuid[] := '{}'; v_motivo text; v_tipos_suspeitos text[] := '{}';
  v_nomes uuid[];
begin
  for i in 1..4 loop
    continue when v_chaves[i] is null;
    select array_agg(distinct c.entidade) into v_ents from pessoas.casar(v_passos[i], v_chaves[i]) c;
    continue when v_ents is null;
    select array_agg(distinct c.entidade) into v_filtradas from pessoas.casar(v_passos[i], v_chaves[i]) c
     where pessoas.nomes_compativeis(p_nome, c.nome);
    if v_passos[i] in ('documento', 'telefone') then
      if v_filtradas is null then        -- bateu, mas o nome é de outra pessoa: não funde
        v_suspeitas := v_suspeitas || pessoas.garantir(v_ents);
        v_motivo := coalesce(v_motivo, v_passos[i] || '_nome_diferente');
        v_tipos_suspeitos := v_tipos_suspeitos || v_passos[i];
        continue;
      end if;
      v_ents := v_filtradas;
    elsif cardinality(v_ents) > 1 and v_filtradas is not null then
      v_ents := v_filtradas;
    end if;
    v_pessoa := pessoas.unir(v_ents);
    if v_pessoa is null then             -- mais de uma pessoa possível: ninguém escolhe sozinho
      v_suspeitas := v_suspeitas || pessoas.garantir(v_ents);
      v_motivo := 'conflito';
      v_tipos_suspeitos := v_tipos_suspeitos || v_passos[i];
      continue;
    end if;
    v_como := v_passos[i];
    exit;
  end loop;

  if v_pessoa is not null then
    v_pessoa := pessoas.atual(v_pessoa);
    v_suspeitas := array(select distinct s from unnest(v_suspeitas) s where s <> v_pessoa);
    if cardinality(v_suspeitas) > 0 then
      insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
      values (v_pessoa, v_motivo, v_suspeitas, jsonb_build_object('casou_por', v_como, 'tipos', to_jsonb(v_tipos_suspeitos)));
    end if;
    return jsonb_build_object('pessoa_id', v_pessoa, 'como', v_como, 'nova', false,
                              'revisao', case when cardinality(v_suspeitas) > 0 then v_motivo end,
                              'tipos_suspeitos', to_jsonb(v_tipos_suspeitos));
  end if;

  -- ninguém casou: pessoa nova. Só o nome bate com alguém? vai para revisão.
  if cardinality(v_suspeitas) = 0 and v_nome like '% %' then
    select array_agg(distinct x) into v_nomes from (
      select p.id x from pessoas.pessoas p
       where p.situacao <> 'mesclada' and p.aluno_id is null and pessoas.norm_nome(p.nome) = v_nome
      union
      select pessoas.pessoa_do_aluno(a.id) from public.thb_alunos a where pessoas.norm_nome(a.nome) = v_nome
    ) s where x is not null;
    if v_nomes is not null then v_suspeitas := v_nomes; v_motivo := 'so_nome'; end if;
  end if;
  v_suspeitas := array(select distinct s from unnest(v_suspeitas) s);

  insert into pessoas.pessoas (nome, situacao, teste, criado_por)
  values (case when length(btrim(coalesce(p_nome, ''))) >= 2 then left(btrim(p_nome), 160) end,
          case when cardinality(v_suspeitas) > 0 then 'revisar' else 'ativa' end, coalesce(p_teste, false), p_por)
  returning id into v_pessoa;
  if cardinality(v_suspeitas) > 0 then
    insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
    values (v_pessoa, v_motivo, v_suspeitas, jsonb_build_object('casou_por', null, 'tipos', to_jsonb(v_tipos_suspeitos)));
  end if;
  return jsonb_build_object('pessoa_id', v_pessoa, 'como', 'nova', 'nova', true,
                            'revisao', case when cardinality(v_suspeitas) > 0 then v_motivo end,
                            'tipos_suspeitos', to_jsonb(v_tipos_suspeitos));
end
$$;

-- guarda um identificador informado, a não ser que já seja o do aluno/comprador ligado (lá é a fonte) ou de outra pessoa
create function pessoas.anexar(p_pessoa uuid, p_tipo text, p_valor text, p_chave text, p_origem text) returns void
language plpgsql set search_path = '' as $$
declare v_dono uuid; r record;
begin
  if p_chave is null then return; end if;
  select p.aluno_id, p.comprador_id, a.documento, a.telefone, a.email, a.nome, a.cep, c.email c_email,
         c.documento c_documento, c.telefone c_telefone
    into r
    from pessoas.pessoas p
    left join public.thb_alunos a on a.id = p.aluno_id
    left join public.compradores c on c.id = p.comprador_id
   where p.id = p_pessoa;
  if (p_tipo = 'documento' and p_chave in (pessoas.norm_documento(r.documento), pessoas.norm_documento(r.c_documento)))
     or (p_tipo = 'telefone' and p_chave in (pessoas.chave_telefone(pessoas.norm_telefone(r.telefone)),
                                             pessoas.chave_telefone(pessoas.norm_telefone(r.c_telefone))))
     or (p_tipo = 'email' and p_chave in (pessoas.norm_email(r.email), pessoas.norm_email(r.c_email)))
     or (p_tipo = 'nome_cep' and pessoas.chave_nome_cep(r.nome, r.cep) = p_chave) then
    return;   -- referência basta
  end if;
  if p_tipo in ('documento', 'email') then
    select pessoa_id into v_dono from pessoas.identificadores where tipo = p_tipo and chave = p_chave and pessoa_id <> p_pessoa;
    if found then
      if not exists (select 1 from pessoas.revisao where status = 'pendente' and pessoa_id = p_pessoa and v_dono = any(candidatos)) then
        insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
        values (p_pessoa, 'conflito', array[v_dono], jsonb_build_object('tipos', jsonb_build_array(p_tipo)));
      end if;
      return;
    end if;
  end if;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem)
  values (p_pessoa, p_tipo, p_valor, p_chave, p_origem)
  on conflict do nothing;
end
$$;

-- Entrada única de pessoa (formulário, CRM, importação). p: nome, email, telefone, documento, cep, aluno_id, projeto
-- (sigla), pagina_id ou dominio+caminho, campanha, utm_*, fbclid/gclid (só viram "de anúncio"), visitante (mkt_web),
-- evento (lead | mql | nao_mql | cadastro), teste.
create function pessoas.registrar(p jsonb, p_fonte text, p_por uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_doc text := pessoas.norm_documento(p->>'documento');
  v_tel text := pessoas.norm_telefone(p->>'telefone');
  v_email text := pessoas.norm_email(p->>'email');
  v_nome text := nullif(left(btrim(coalesce(p->>'nome', '')), 160), '');
  v_res jsonb; v_pessoa uuid; v_suspeitos text[];
  v_projeto bigint; v_pagina bigint; v_campanha text; v_trad jsonb; v_origem bigint; v_evento text;
  v_ref text; v_aluno uuid; v_tem_origem boolean;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados inválidos.'); end if;
  v_evento := coalesce(nullif(p->>'evento', ''), case when p_fonte = 'formulario' then 'lead' else 'cadastro' end);
  if v_evento not in ('lead', 'mql', 'nao_mql', 'cadastro') then
    return jsonb_build_object('ok', false, 'msg', 'Evento inválido (lead, mql, nao_mql ou cadastro).');
  end if;

  if nullif(p->>'aluno_id', '') is not null then
    -- trazer um aluno que já existe para a base (ex.: ativação): só a referência
    begin v_aluno := (p->>'aluno_id')::uuid; exception when others then return jsonb_build_object('ok', false, 'msg', 'Aluno inválido.'); end;
    v_pessoa := pessoas.pessoa_do_aluno(v_aluno);
    if v_pessoa is null then return jsonb_build_object('ok', false, 'msg', 'Aluno não encontrado.'); end if;
    v_pessoa := pessoas.atual(v_pessoa);
    v_res := jsonb_build_object('pessoa_id', v_pessoa, 'como', 'aluno', 'nova', false, 'revisao', null);
  else
    if v_doc is null and v_tel is null and v_email is null then
      return jsonb_build_object('ok', false, 'msg', 'Informe um e-mail, telefone (com DDD) ou documento válido.');
    end if;
    v_res := pessoas.resolver(v_nome, v_email, p->>'telefone', p->>'documento', p->>'cep', coalesce((p->>'teste')::boolean, false), p_por);
    v_pessoa := (v_res->>'pessoa_id')::uuid;
    select coalesce(array_agg(x), '{}') into v_suspeitos from jsonb_array_elements_text(coalesce(v_res->'tipos_suspeitos', '[]')) x;

    -- nome próprio só para quem não é aluno/comprador (desses o nome vem da fonte)
    update pessoas.pessoas set nome = v_nome, atualizado_em = now()
     where id = v_pessoa and nome is null and aluno_id is null and comprador_id is null and length(coalesce(v_nome, '')) >= 2;

    if not 'documento' = any(v_suspeitos) then perform pessoas.anexar(v_pessoa, 'documento', v_doc, v_doc, p_fonte); end if;
    if not 'telefone' = any(v_suspeitos) then perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), p_fonte); end if;
    if not 'email' = any(v_suspeitos) then perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, p_fonte); end if;
    if not 'nome_cep' = any(v_suspeitos) then
      perform pessoas.anexar(v_pessoa, 'nome_cep', pessoas.chave_nome_cep(v_nome, p->>'cep'), pessoas.chave_nome_cep(v_nome, p->>'cep'), p_fonte);
    end if;
  end if;

  -- origem: projeto pela sigla, ou pelo nome de campanha (padrão GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA)
  v_campanha := nullif(left(btrim(coalesce(p->>'campanha', '')), 300), '');
  if v_campanha is not null then v_trad := mkt.campanha_traduzir(v_campanha); end if;
  select id into v_projeto from mkt.projetos where sigla = upper(btrim(coalesce(p->>'projeto', '')));
  v_projeto := coalesce(v_projeto, (v_trad->>'projeto_id')::bigint);
  if nullif(p->>'pagina_id', '') is not null then
    select id into v_pagina from mkt.paginas where id = (p->>'pagina_id')::bigint and (v_projeto is null or projeto_id = v_projeto);
  elsif nullif(p->>'caminho', '') is not null and v_projeto is not null then
    select id into v_pagina from mkt.paginas
     where projeto_id = v_projeto and dominio = regexp_replace(lower(coalesce(p->>'dominio', '')), '^www\.', '')
       and caminho = p->>'caminho';
  end if;
  v_pagina := coalesce(v_pagina, (v_trad->>'pagina_id')::bigint);
  if v_pagina is not null and v_projeto is null then select projeto_id into v_projeto from mkt.paginas where id = v_pagina; end if;

  v_tem_origem := v_projeto is not null or v_campanha is not null
                  or coalesce(p->>'utm_source', p->>'utm_medium', p->>'utm_campaign', p->>'utm_content', p->>'utm_term') is not null;
  if v_tem_origem then
    insert into pessoas.origens (pessoa_id, projeto_id, pagina_id, campanha, campanha_padrao, utm_source, utm_medium,
                                 utm_campaign, utm_content, utm_term, de_anuncio, fonte)
    values (v_pessoa, v_projeto, v_pagina, v_campanha, (v_trad->>'padrao')::boolean,
            nullif(left(p->>'utm_source', 300), ''), nullif(left(p->>'utm_medium', 300), ''),
            nullif(left(p->>'utm_campaign', 300), ''), nullif(left(p->>'utm_content', 300), ''),
            nullif(left(p->>'utm_term', 300), ''),
            coalesce(nullif(p->>'fbclid', ''), nullif(p->>'gclid', '')) is not null, p_fonte)
    returning id into v_origem;
  end if;

  insert into pessoas.eventos (pessoa_id, tipo, projeto_id, origem_id, fonte, detalhe, por)
  values (v_pessoa, v_evento, v_projeto, v_origem, p_fonte,
          jsonb_build_object('como', v_res->>'como') || case when v_res->>'revisao' is not null
                                                              then jsonb_build_object('revisao', v_res->>'revisao') else '{}' end,
          p_por);

  select ref into v_ref from pessoas.pessoas where id = v_pessoa;

  -- a Web guarda só a referência opaca (se a coleta da Web, 20261005n, estiver aplicada)
  if nullif(p->>'visitante', '') is not null and v_projeto is not null and to_regclass('mkt_web.visitantes') is not null
     and p->>'visitante' ~ '^[A-Za-z0-9]{8,40}$' then
    execute 'update mkt_web.visitantes set lead_ref = $1 where projeto_id = $2 and id = $3 and lead_ref is null'
      using v_ref, v_projeto, p->>'visitante';
  end if;

  return jsonb_build_object('ok', true, 'pessoa_id', v_pessoa, 'ref', v_ref, 'como', v_res->>'como',
                            'nova', coalesce((v_res->>'nova')::boolean, false), 'revisao', v_res->>'revisao',
                            'situacao', (select situacao from pessoas.pessoas where id = v_pessoa),
                            'projeto_id', v_projeto, 'origem_id', v_origem);
end
$$;

-- junta "de" em "para" (decisão humana na revisão). Leva identificadores, origens, eventos e negócios.
create function pessoas.mesclar(p_de uuid, p_para uuid, p_por uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare d record; q record;
begin
  select * into d from pessoas.pessoas where id = p_de for update;
  select * into q from pessoas.pessoas where id = p_para for update;
  if d.id is null or q.id is null or d.id = q.id then return jsonb_build_object('ok', false, 'msg', 'Pessoas inválidas.'); end if;
  if d.situacao = 'mesclada' or q.situacao = 'mesclada' then return jsonb_build_object('ok', false, 'msg', 'Uma das pessoas já foi mesclada.'); end if;
  if d.aluno_id is not null and q.aluno_id is not null then
    return jsonb_build_object('ok', false, 'msg', 'As duas pessoas são alunos diferentes: não dá para juntar aqui (conferir na Central de Alunos).');
  end if;
  if d.comprador_id is not null and q.comprador_id is not null then
    return jsonb_build_object('ok', false, 'msg', 'As duas pessoas são compradores diferentes na Hotmart: não dá para juntar aqui.');
  end if;
  if exists (select 1 from crm.negocios a join crm.negocios b
                on b.pipeline_id = a.pipeline_id and coalesce(b.projeto_id, 0) = coalesce(a.projeto_id, 0)
             where a.pessoa_id = p_de and b.pessoa_id = p_para and a.status = 'aberto' and b.status = 'aberto') then
    return jsonb_build_object('ok', false, 'msg', 'As duas têm negócio aberto no mesmo pipeline e projeto: feche um antes de juntar.');
  end if;

  update pessoas.pessoas set aluno_id = null, comprador_id = null where id = p_de;
  update pessoas.pessoas
     set aluno_id = coalesce(q.aluno_id, d.aluno_id), comprador_id = coalesce(q.comprador_id, d.comprador_id),
         nome = coalesce(q.nome, d.nome), teste = q.teste and d.teste, atualizado_em = now()
   where id = p_para;
  delete from pessoas.identificadores i
   where i.pessoa_id = p_de and exists (select 1 from pessoas.identificadores j where j.pessoa_id = p_para and j.tipo = i.tipo and j.chave = i.chave);
  update pessoas.identificadores set pessoa_id = p_para where pessoa_id = p_de;
  update pessoas.origens set pessoa_id = p_para where pessoa_id = p_de;
  update pessoas.eventos set pessoa_id = p_para where pessoa_id = p_de;
  update crm.negocios set pessoa_id = p_para where pessoa_id = p_de;
  update pessoas.revisao set candidatos = array_replace(candidatos, p_de, p_para) where status = 'pendente' and p_de = any(candidatos);
  update pessoas.revisao set candidatos = array_remove(candidatos, pessoa_id) where status = 'pendente' and pessoa_id = any(candidatos);
  update pessoas.pessoas set situacao = 'mesclada', mesclada_em = p_para, atualizado_em = now() where id = p_de;
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, por)
  values (p_para, 'mescla', 'sistema', 'pessoas.pessoas', p_de::text, p_por);
  return jsonb_build_object('ok', true, 'msg', 'Pessoas juntadas.', 'pessoa_id', p_para);
end
$$;

-- ─── 7. CRM ──────────────────────────────────────────────────────────────────────────────────────────────────────────
create table crm.pipelines (
  id        smallint generated always as identity primary key,
  tipo      text not null unique check (tipo in ('ativacao', 'vendas', 'recuperacao_carrinho', 'recuperacao_venda')),
  nome      text not null check (length(btrim(nome)) between 2 and 60),
  descricao text check (descricao is null or length(descricao) <= 500),
  ordem     smallint not null,
  ativo     boolean not null default true
);
alter table crm.pipelines enable row level security;

create table crm.etapas (
  id          int generated always as identity primary key,
  pipeline_id smallint not null references crm.pipelines(id) on delete restrict,
  nome        text not null check (length(btrim(nome)) between 1 and 60),
  ordem       smallint not null,
  tipo        text not null default 'aberta' check (tipo in ('aberta', 'ganho', 'perdido')),
  ativa       boolean not null default true,
  unique (pipeline_id, nome),
  unique (id, pipeline_id)
);
alter table crm.etapas enable row level security;

create table crm.motivos_perda (
  id          int generated always as identity primary key,
  pipeline_id smallint references crm.pipelines(id) on delete restrict,   -- null = vale para todos
  nome        text not null check (length(btrim(nome)) between 2 and 80),
  ativo       boolean not null default true
);
alter table crm.motivos_perda enable row level security;
create unique index motivos_perda_nome_unico on crm.motivos_perda (coalesce(pipeline_id, 0), lower(nome));

create table crm.negocios (
  id               uuid primary key default gen_random_uuid(),
  pipeline_id      smallint not null references crm.pipelines(id) on delete restrict,
  etapa_id         int not null,
  pessoa_id        uuid not null references pessoas.pessoas(id) on delete restrict,
  projeto_id       bigint references mkt.projetos(id) on delete restrict,
  responsavel_id   uuid references public.perfis(id) on delete set null,
  status           text not null default 'aberto' check (status in ('aberto', 'ganho', 'perdido')),
  proximo_passo    text check (proximo_passo is null or length(proximo_passo) <= 500),
  proximo_passo_em date,
  motivo_perda_id  int references crm.motivos_perda(id) on delete restrict,
  motivo_perda_obs text check (motivo_perda_obs is null or length(motivo_perda_obs) <= 500),
  -- gancho para o card do HM no disparos-thb (referência, nada é copiado). Decisão pendente com o Victor.
  externo_tipo     text check (externo_tipo is null or externo_tipo in ('cs.contatos_hm')),
  externo_id       text check (externo_id is null or length(externo_id) <= 80),
  entrou_etapa_em  timestamptz not null default now(),
  fechado_em       timestamptz,
  criado_em        timestamptz not null default now(),
  criado_por       uuid references public.perfis(id) on delete set null,
  atualizado_em    timestamptz not null default now(),
  atualizado_por   uuid references public.perfis(id) on delete set null,
  constraint negocios_etapa_do_pipeline foreign key (etapa_id, pipeline_id) references crm.etapas(id, pipeline_id),
  constraint negocios_fechado_check check ((status = 'aberto') = (fechado_em is null)),
  constraint negocios_perda_check check (status = 'perdido' or (motivo_perda_id is null and motivo_perda_obs is null)),
  constraint negocios_perda_motivo_check check (status <> 'perdido' or motivo_perda_id is not null or motivo_perda_obs is not null),
  constraint negocios_externo_check check ((externo_tipo is null) = (externo_id is null))
);
alter table crm.negocios enable row level security;
-- um negócio aberto por pessoa, pipeline e projeto (não duplica card)
create unique index negocios_um_aberto on crm.negocios (pessoa_id, pipeline_id, coalesce(projeto_id, 0)) where status = 'aberto';
create index negocios_quadro_idx on crm.negocios (pipeline_id, status, etapa_id);
create index negocios_pessoa_idx on crm.negocios (pessoa_id);
create index negocios_responsavel_idx on crm.negocios (responsavel_id) where responsavel_id is not null;
create index negocios_projeto_idx on crm.negocios (projeto_id) where projeto_id is not null;

create table crm.historico (
  id         bigint generated always as identity primary key,
  negocio_id uuid not null references crm.negocios(id) on delete cascade,
  quando     timestamptz not null default now(),
  por        uuid references public.perfis(id) on delete set null,
  acao       text not null check (acao in ('criado', 'etapa', 'responsavel', 'proximo_passo', 'projeto', 'reaberto')),
  de         text,
  para       text,
  detalhe    jsonb not null default '{}' check (jsonb_typeof(detalhe) = 'object')
);
alter table crm.historico enable row level security;
create index historico_negocio_idx on crm.historico (negocio_id, quando);

-- Semente: 4 pipelines (Victor, 05/10/2026). Etapas = PROPOSTA genérica (configurável); motivos de perda vazios.
insert into crm.pipelines (tipo, nome, descricao, ordem) values
  ('ativacao', 'Ativação', 'Contato sem intenção de vender: ajudar a pessoa a entrar no evento ou na área de membros '
                           '(ex.: ingresso do HT).', 1),
  ('vendas', 'Vendas', null, 2),
  ('recuperacao_carrinho', 'Recuperação de carrinho', null, 3),
  ('recuperacao_venda', 'Recuperação de venda', null, 4);

insert into crm.etapas (pipeline_id, nome, ordem, tipo)
select p.id, e.nome, e.ordem, e.tipo_etapa
  from (values
    ('ativacao', 'A contatar', 1, 'aberta'), ('ativacao', 'Em contato', 2, 'aberta'),
    ('ativacao', 'Ativado', 3, 'ganho'), ('ativacao', 'Não ativado', 4, 'perdido'),
    ('vendas', 'Novo', 1, 'aberta'), ('vendas', 'Em contato', 2, 'aberta'), ('vendas', 'Negociação', 3, 'aberta'),
    ('vendas', 'Ganho', 4, 'ganho'), ('vendas', 'Perdido', 5, 'perdido'),
    ('recuperacao_carrinho', 'A contatar', 1, 'aberta'), ('recuperacao_carrinho', 'Em contato', 2, 'aberta'),
    ('recuperacao_carrinho', 'Recuperado', 3, 'ganho'), ('recuperacao_carrinho', 'Não recuperado', 4, 'perdido'),
    ('recuperacao_venda', 'A contatar', 1, 'aberta'), ('recuperacao_venda', 'Em contato', 2, 'aberta'),
    ('recuperacao_venda', 'Recuperado', 3, 'ganho'), ('recuperacao_venda', 'Não recuperado', 4, 'perdido')
  ) e(tipo, nome, ordem, tipo_etapa)
  join crm.pipelines p on p.tipo = e.tipo;

-- Regra de movimento (pura; a mesma em web/modules/comercial/domain/crm.ts, com testes). null = pode.
--   mesma etapa → 'mesma_etapa'; etapa inativa → 'etapa_inativa'; fechado (ganho/perdido) só volta para etapa aberta
--   (reabrir) → 'reabrir_antes'; perdido sem motivo → 'motivo_obrigatorio'.
create function crm.validar_movimento(p_de_id int, p_de_tipo text, p_para_id int, p_para_tipo text, p_para_ativa boolean,
                                      p_tem_motivo boolean) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_de_id = p_para_id then 'mesma_etapa'
    when not p_para_ativa then 'etapa_inativa'
    when p_de_tipo in ('ganho', 'perdido') and p_para_tipo <> 'aberta' then 'reabrir_antes'
    when p_para_tipo = 'perdido' and not p_tem_motivo then 'motivo_obrigatorio'
  end;
$$;

create function crm.msg_movimento(p_cod text) returns text
language sql immutable set search_path = '' as $$
  select case p_cod
    when 'mesma_etapa' then 'O negócio já está nesta etapa.'
    when 'etapa_inativa' then 'Etapa desativada.'
    when 'reabrir_antes' then 'Negócio fechado: reabra (volte para uma etapa aberta) antes de fechar de novo.'
    when 'motivo_obrigatorio' then 'Informe o motivo da perda.'
    else p_cod end;
$$;

-- ─── 8. Funções da tela: pessoas ─────────────────────────────────────────────────────────────────────────────────────
create function public.pessoas_meu_acesso() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('pode_ver', pessoas.pode_ver(), 'pode_editar', pessoas.pode_editar(),
                            'pode_ver_doc', pessoas.pode_ver_doc(), 'pode_ver_contato', pessoas.pode_ver_contato());
$$;

create function public.pessoas_buscar(p_termo text default null, p_projeto bigint default null, p_limite int default 30)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t text := nullif(btrim(coalesce(p_termo, '')), '');
  v_nome text; v_email text; v_doc text; v_tel text;
  v_lim int := least(greatest(coalesce(p_limite, 30), 1), 100);
  v_contato boolean := pessoas.pode_ver_contato();
  v jsonb;
begin
  if not pessoas.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if (v_t is null or length(v_t) < 3) and p_projeto is null then return '[]'::jsonb; end if;
  v_nome := pessoas.norm_nome(v_t);
  v_email := pessoas.norm_email(v_t);
  v_doc := pessoas.norm_documento(v_t);
  v_tel := pessoas.chave_telefone(pessoas.norm_telefone(v_t));

  with achadas as (
    select p.id, p.ref, p.situacao, p.aluno_id, p.comprador_id, p.criado_em, p.teste
      from pessoas.pessoas p
      left join public.thb_alunos a on a.id = p.aluno_id
      left join public.compradores c on c.id = p.comprador_id
     where p.situacao <> 'mesclada'
       and (v_t is null
            or exists (select 1 from pessoas.identificadores i where i.pessoa_id = p.id
                         and ((i.tipo = 'email' and i.chave = v_email) or (i.tipo = 'documento' and i.chave = v_doc)
                              or (i.tipo = 'telefone' and i.chave = v_tel)))
            or (v_nome is not null and length(v_nome) >= 3 and pessoas.norm_nome(coalesce(a.nome, c.nome, p.nome)) like '%' || v_nome || '%')
            or (v_email is not null and (pessoas.norm_email(a.email) = v_email or pessoas.norm_email(c.email) = v_email))
            or (v_doc is not null and (pessoas.norm_documento(a.documento) = v_doc or pessoas.norm_documento(c.documento) = v_doc))
            or (v_tel is not null and (pessoas.chave_telefone(pessoas.norm_telefone(a.telefone)) = v_tel
                                       or pessoas.chave_telefone(pessoas.norm_telefone(c.telefone)) = v_tel)))
       and (p_projeto is null
            or exists (select 1 from pessoas.origens o where o.pessoa_id = p.id and o.projeto_id = p_projeto)
            or exists (select 1 from crm.negocios n where n.pessoa_id = p.id and n.projeto_id = p_projeto))
     order by p.criado_em desc
     limit v_lim
  ), so_alunos as (    -- aluno que ainda não está na base de pessoas (pode ser trazido pela ficha: pessoas_cadastrar)
    select a.id aluno_id, a.nome, a.email, a.telefone, t.codigo turma
      from public.thb_alunos a
      left join public.thb_turmas t on t.id = a.turma_id
     where v_t is not null and p_projeto is null
       and not exists (select 1 from pessoas.pessoas p where p.aluno_id = a.id)
       and ((v_nome is not null and length(v_nome) >= 3 and pessoas.norm_nome(a.nome) like '%' || v_nome || '%')
            or (v_email is not null and pessoas.norm_email(a.email) = v_email)
            or (v_doc is not null and pessoas.norm_documento(a.documento) = v_doc)
            or (v_tel is not null and pessoas.chave_telefone(pessoas.norm_telefone(a.telefone)) = v_tel))
     order by a.nome
     limit v_lim
  )
  select coalesce(jsonb_agg(x order by x->>'tipo', x->>'nome'), '[]'::jsonb) into v from (
    select jsonb_build_object(
             'tipo', 'pessoa', 'id', ac.id, 'ref', ac.ref, 'nome', d.nome, 'situacao', ac.situacao, 'teste', ac.teste,
             'email', case when v_contato then d.email else pessoas.mascara_email(d.email) end,
             'telefone', case when v_contato then d.telefone else pessoas.mascara_fim(d.telefone) end,
             'eh_aluno', ac.aluno_id is not null, 'eh_comprador', ac.comprador_id is not null, 'turma', d.turma,
             'projetos', (select coalesce(jsonb_agg(distinct pr.sigla), '[]'::jsonb) from pessoas.origens o
                            join mkt.projetos pr on pr.id = o.projeto_id where o.pessoa_id = ac.id),
             'negocios_abertos', (select count(*) from crm.negocios n where n.pessoa_id = ac.id and n.status = 'aberto'),
             'criado_em', ac.criado_em) x
      from achadas ac cross join lateral pessoas.dados(ac.id) d
    union all
    select jsonb_build_object(
             'tipo', 'aluno', 'id', null, 'aluno_id', sa.aluno_id, 'nome', sa.nome, 'situacao', null, 'teste', false,
             'email', case when v_contato then pessoas.norm_email(sa.email) else pessoas.mascara_email(pessoas.norm_email(sa.email)) end,
             'telefone', case when v_contato then pessoas.norm_telefone(sa.telefone) else pessoas.mascara_fim(pessoas.norm_telefone(sa.telefone)) end,
             'eh_aluno', true, 'eh_comprador', false, 'turma', sa.turma, 'projetos', '[]'::jsonb, 'negocios_abertos', 0,
             'criado_em', null)
      from so_alunos sa
  ) s;

  perform pessoas.registrar_acesso('buscar', null,
    jsonb_build_object('tamanho_termo', length(coalesce(v_t, '')), 'projeto', p_projeto, 'resultados', jsonb_array_length(v)));
  return v;
end
$$;

create function public.pessoas_ficha(p_pessoa uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; p record; d record;
  v_doc boolean := pessoas.pode_ver_doc();
  v_contato boolean := pessoas.pode_ver_contato();
  v_comprador uuid;
  v jsonb;
begin
  if not pessoas.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  v_id := pessoas.atual(p_pessoa);
  select * into p from pessoas.pessoas where id = v_id;
  if not found then return null; end if;
  select * into d from pessoas.dados(v_id);
  select coalesce(p.comprador_id, a.comprador_id) into v_comprador from public.thb_alunos a where a.id = p.aluno_id;
  v_comprador := coalesce(v_comprador, p.comprador_id);

  v := jsonb_build_object(
    'pessoa', jsonb_build_object(
      'id', p.id, 'ref', p.ref, 'nome', d.nome, 'situacao', p.situacao, 'teste', p.teste, 'criado_em', p.criado_em,
      'mesclada_de', case when p_pessoa <> v_id then p_pessoa end,
      'email', case when v_contato then d.email else pessoas.mascara_email(d.email) end,
      'telefone', case when v_contato then d.telefone else pessoas.mascara_fim(d.telefone) end,
      'documento', case when v_doc then d.documento else pessoas.mascara_fim(d.documento) end),
    'aluno', case when p.aluno_id is not null then jsonb_build_object(
      'id', p.aluno_id, 'nome', d.aluno_nome, 'turma', d.turma, 'cancelado', d.aluno_cancelado) end,
    'comprador_id', v_comprador,
    'identificadores', (select coalesce(jsonb_agg(jsonb_build_object(
        'tipo', i.tipo, 'origem', i.origem, 'criado_em', i.criado_em,
        'valor', case
                   when i.tipo = 'documento' then case when v_doc then i.valor else pessoas.mascara_fim(i.valor) end
                   when i.tipo = 'email' then case when v_contato then i.valor else pessoas.mascara_email(i.valor) end
                   when i.tipo = 'telefone' then case when v_contato then i.valor else pessoas.mascara_fim(i.valor) end
                   else case when v_contato then i.valor else split_part(i.valor, '|', 1) || '|*****' || right(i.valor, 3) end
                 end) order by i.id), '[]'::jsonb)
        from pessoas.identificadores i where i.pessoa_id = v_id),
    'origens', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'quando', o.quando, 'projeto_id', o.projeto_id, 'projeto', pr.sigla, 'pagina_id', o.pagina_id,
        'pagina', case when pg.id is not null then pg.dominio || pg.caminho end, 'campanha', o.campanha,
        'campanha_padrao', o.campanha_padrao, 'utm_source', o.utm_source, 'utm_medium', o.utm_medium,
        'utm_campaign', o.utm_campaign, 'utm_content', o.utm_content, 'utm_term', o.utm_term,
        'de_anuncio', o.de_anuncio, 'fonte', o.fonte) order by o.quando desc), '[]'::jsonb)
        from pessoas.origens o left join mkt.projetos pr on pr.id = o.projeto_id left join mkt.paginas pg on pg.id = o.pagina_id
       where o.pessoa_id = v_id),
    'eventos', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', e.id, 'tipo', e.tipo, 'quando', e.quando, 'projeto', pr.sigla, 'fonte', e.fonte, 'ref_tipo', e.ref_tipo,
        'ref_id', e.ref_id, 'detalhe', e.detalhe, 'por', pf.nome) order by e.quando desc, e.id desc), '[]'::jsonb)
        from pessoas.eventos e left join mkt.projetos pr on pr.id = e.projeto_id left join public.perfis pf on pf.id = e.por
       where e.pessoa_id = v_id),
    -- compras: lidas da Hotmart (public.compras) pela referência ao comprador; nada é copiado
    'compras', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'produto', c.produto_nome, 'status', c.status, 'data', c.data_compra, 'preco', c.preco)
        order by c.data_compra desc nulls last), '[]'::jsonb)
        from public.compras c where v_comprador is not null and c.comprador_id = v_comprador),
    'negocios', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', n.id, 'pipeline_id', n.pipeline_id, 'pipeline', pl.nome, 'pipeline_tipo', pl.tipo, 'etapa_id', n.etapa_id,
        'etapa', et.nome, 'etapa_tipo', et.tipo, 'status', n.status, 'projeto', pr.sigla, 'projeto_id', n.projeto_id,
        'responsavel_id', n.responsavel_id, 'responsavel', pf.nome, 'proximo_passo', n.proximo_passo,
        'proximo_passo_em', n.proximo_passo_em, 'motivo_perda', coalesce(mp.nome, n.motivo_perda_obs),
        'criado_em', n.criado_em, 'fechado_em', n.fechado_em) order by n.status = 'aberto' desc, n.criado_em desc), '[]'::jsonb)
        from crm.negocios n join crm.pipelines pl on pl.id = n.pipeline_id join crm.etapas et on et.id = n.etapa_id
        left join mkt.projetos pr on pr.id = n.projeto_id left join public.perfis pf on pf.id = n.responsavel_id
        left join crm.motivos_perda mp on mp.id = n.motivo_perda_id
       where n.pessoa_id = v_id),
    'revisoes', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'motivo', r.motivo, 'criado_em', r.criado_em)), '[]'::jsonb)
        from pessoas.revisao r where r.status = 'pendente' and (r.pessoa_id = v_id or v_id = any(r.candidatos))),
    'permissoes', jsonb_build_object('pode_editar', pessoas.pode_editar(), 'pode_ver_doc', v_doc, 'pode_ver_contato', v_contato));

  perform pessoas.registrar_acesso('ver_ficha', v_id, '{}'::jsonb);
  return v;
end
$$;

create function public.pessoas_cadastrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  if not pessoas.pode_editar() then raise exception 'acesso negado' using errcode = '42501'; end if;
  v := pessoas.registrar(p - 'visitante', 'crm', (select auth.uid()));
  if (v->>'ok')::boolean then
    perform pessoas.registrar_acesso('cadastrar', (v->>'pessoa_id')::uuid, jsonb_build_object('como', v->>'como', 'revisao', v->>'revisao'));
    v := v || jsonb_build_object('msg', case
      when v->>'revisao' is not null then 'Cadastrado. Pode ser alguém que já existe: ficou para revisão.'
      when (v->>'nova')::boolean then 'Pessoa nova cadastrada.'
      else 'Esta pessoa já existia: o registro foi ligado a ela.' end);
  end if;
  return v;
end
$$;

-- só o servidor (formulário de captura) grava lead: a chave de serviço nunca vai ao navegador
create function public.pessoas_registrar_lead(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  v := pessoas.registrar(p, 'formulario', null);
  return case when (v->>'ok')::boolean
              then jsonb_build_object('ok', true, 'ref', v->>'ref', 'como', v->>'como', 'revisao', v->>'revisao')
              else v end;
end
$$;

create function public.pessoas_revisao_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not pessoas.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'motivo', r.motivo, 'criado_em', r.criado_em, 'detalhe', r.detalhe,
      'pessoa', (select jsonb_build_object('id', p.id, 'nome', d.nome, 'situacao', p.situacao, 'eh_aluno', p.aluno_id is not null,
                                           'turma', d.turma, 'criado_em', p.criado_em)
                   from pessoas.pessoas p cross join lateral pessoas.dados(p.id) d where p.id = r.pessoa_id),
      'candidatos', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nome', d.nome, 'eh_aluno', p.aluno_id is not null,
                                                                    'turma', d.turma, 'situacao', p.situacao)), '[]'::jsonb)
                       from unnest(r.candidatos) cid join pessoas.pessoas p on p.id = cid cross join lateral pessoas.dados(p.id) d))
    order by r.criado_em), '[]'::jsonb)
    from pessoas.revisao r where r.status = 'pendente');
end
$$;

-- decisão humana: 'mesma' (junta a pessoa da revisão no candidato escolhido) ou 'diferente' (são pessoas distintas)
create function public.pessoas_revisao_decidir(p_revisao bigint, p_decisao text, p_alvo uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; v jsonb;
begin
  if not pessoas.pode_editar() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into r from pessoas.revisao where id = p_revisao for update;
  if not found or r.status <> 'pendente' then return jsonb_build_object('ok', false, 'msg', 'Revisão não encontrada ou já decidida.'); end if;
  if p_decisao = 'mesma' then
    if p_alvo is null or not p_alvo = any(r.candidatos) then
      return jsonb_build_object('ok', false, 'msg', 'Escolha uma das pessoas candidatas.');
    end if;
    v := pessoas.mesclar(r.pessoa_id, p_alvo, (select auth.uid()));
    if not (v->>'ok')::boolean then return v; end if;
  elsif p_decisao = 'diferente' then
    v := jsonb_build_object('ok', true, 'msg', 'Marcadas como pessoas diferentes.', 'pessoa_id', r.pessoa_id);
  else
    return jsonb_build_object('ok', false, 'msg', 'Decisão inválida (mesma ou diferente).');
  end if;
  update pessoas.revisao set status = p_decisao, decidido_por = (select auth.uid()), decidido_em = now() where id = p_revisao;
  -- sem outra dúvida pendente, a pessoa da revisão sai de "revisar"
  update pessoas.pessoas set situacao = 'ativa', atualizado_em = now()
   where id = r.pessoa_id and situacao = 'revisar'
     and not exists (select 1 from pessoas.revisao x where x.pessoa_id = r.pessoa_id and x.status = 'pendente');
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe, por)
  values (pessoas.atual(r.pessoa_id), 'revisao', 'crm', 'pessoas.revisao', p_revisao::text,
          jsonb_build_object('decisao', p_decisao, 'motivo', r.motivo), (select auth.uid()));
  perform pessoas.registrar_acesso('revisar', r.pessoa_id, jsonb_build_object('revisao', p_revisao, 'decisao', p_decisao, 'alvo', p_alvo));
  return v;
end
$$;

-- ─── 9. Funções da tela: CRM ─────────────────────────────────────────────────────────────────────────────────────────
create function public.crm_config() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not pessoas.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object(
    'pipelines', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'tipo', p.tipo, 'nome', p.nome, 'descricao', p.descricao, 'ativo', p.ativo,
        'etapas', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nome', e.nome, 'ordem', e.ordem, 'tipo', e.tipo,
                                                                 'ativa', e.ativa) order by e.ordem, e.id), '[]'::jsonb)
                     from crm.etapas e where e.pipeline_id = p.id)) order by p.ordem), '[]'::jsonb)
        from crm.pipelines p),
    'motivos', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'pipeline_id', m.pipeline_id, 'nome', m.nome,
                                                             'ativo', m.ativo) order by m.nome), '[]'::jsonb) from crm.motivos_perda m),
    -- quem pode ser responsável: equipe ativa que entra no Comercial (hoje admin/dev; depois as áreas liberadas)
    'responsaveis', (select coalesce(jsonb_agg(jsonb_build_object('id', pf.id, 'nome', pf.nome) order by pf.nome), '[]'::jsonb)
        from public.perfis pf
       where pf.status = 'ativo'
         and (pf.cargo in ('dev', 'admin')
              or (pf.cargo in ('gestor', 'operador') and coalesce(pf.areas, '{}') && pessoas.areas_config('areas_edicao')))),
    'projetos', (select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'sigla', pr.sigla, 'nome', pr.nome, 'ativo', pr.ativo)
                                           order by pr.ativo desc, pr.sigla), '[]'::jsonb) from mkt.projetos pr),
    'permissoes', public.pessoas_meu_acesso());
end
$$;

create function public.crm_negocios_listar(p_pipeline smallint, p_projeto bigint default null, p_responsavel uuid default null,
                                           p_status text default 'aberto') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not pessoas.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if p_status is not null and p_status not in ('aberto', 'ganho', 'perdido') then
    raise exception 'status inválido' using errcode = '22023';
  end if;
  -- sem contato na lista (minimização): e-mail e telefone só na ficha
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id, 'pipeline_id', n.pipeline_id, 'etapa_id', n.etapa_id, 'status', n.status,
      'pessoa_id', n.pessoa_id, 'pessoa', coalesce(a.nome, c.nome, p.nome), 'eh_aluno', p.aluno_id is not null,
      'situacao_pessoa', p.situacao, 'projeto_id', n.projeto_id, 'projeto', pr.sigla,
      'responsavel_id', n.responsavel_id, 'responsavel', pf.nome, 'proximo_passo', n.proximo_passo,
      'proximo_passo_em', n.proximo_passo_em, 'entrou_etapa_em', n.entrou_etapa_em, 'criado_em', n.criado_em,
      'fechado_em', n.fechado_em, 'motivo_perda', coalesce(mp.nome, n.motivo_perda_obs), 'externo_tipo', n.externo_tipo)
      order by n.proximo_passo_em nulls last, n.entrou_etapa_em), '[]'::jsonb)
    from (select * from crm.negocios x
           where x.pipeline_id = p_pipeline and (p_status is null or x.status = p_status)
             and (p_projeto is null or x.projeto_id = p_projeto)
             and (p_responsavel is null or x.responsavel_id = p_responsavel)
           order by x.atualizado_em desc limit 1000) n
    join pessoas.pessoas p on p.id = n.pessoa_id
    left join public.thb_alunos a on a.id = p.aluno_id
    left join public.compradores c on c.id = p.comprador_id
    left join mkt.projetos pr on pr.id = n.projeto_id
    left join public.perfis pf on pf.id = n.responsavel_id
    left join crm.motivos_perda mp on mp.id = n.motivo_perda_id);
end
$$;

create function public.crm_negocio_criar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_pipeline smallint; v_pessoa uuid; v_projeto bigint; v_resp uuid; v_etapa int; v_id uuid; v_tipo_etapa text;
  v_ext_tipo text := nullif(p->>'externo_tipo', ''); v_ext_id text := nullif(p->>'externo_id', '');
begin
  if not pessoas.pode_editar() then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_pipeline := (p->>'pipeline_id')::smallint;
    v_pessoa := (p->>'pessoa_id')::uuid;
    v_projeto := nullif(p->>'projeto_id', '')::bigint;
    v_resp := nullif(p->>'responsavel_id', '')::uuid;
    v_etapa := nullif(p->>'etapa_id', '')::int;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Dados inválidos.');
  end;
  if not exists (select 1 from crm.pipelines where id = v_pipeline and ativo) then return jsonb_build_object('ok', false, 'msg', 'Pipeline inválido.'); end if;
  v_pessoa := pessoas.atual(v_pessoa);
  if v_pessoa is null or not exists (select 1 from pessoas.pessoas where id = v_pessoa) then
    return jsonb_build_object('ok', false, 'msg', 'Pessoa não encontrada.');
  end if;
  if v_projeto is not null and not exists (select 1 from mkt.projetos where id = v_projeto) then
    return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.');
  end if;
  if v_resp is not null and not exists (select 1 from public.perfis where id = v_resp and status = 'ativo') then
    return jsonb_build_object('ok', false, 'msg', 'Responsável precisa ser alguém ativo da equipe.');
  end if;
  if v_etapa is null then
    select id into v_etapa from crm.etapas where pipeline_id = v_pipeline and ativa and tipo = 'aberta' order by ordem, id limit 1;
  end if;
  select tipo into v_tipo_etapa from crm.etapas where id = v_etapa and pipeline_id = v_pipeline and ativa;
  if v_tipo_etapa is distinct from 'aberta' then return jsonb_build_object('ok', false, 'msg', 'O negócio nasce numa etapa aberta deste pipeline.'); end if;
  if (v_ext_tipo is null) <> (v_ext_id is null) or (v_ext_tipo is not null and v_ext_tipo <> 'cs.contatos_hm') then
    return jsonb_build_object('ok', false, 'msg', 'Referência externa inválida.');
  end if;

  begin
    insert into crm.negocios (pipeline_id, etapa_id, pessoa_id, projeto_id, responsavel_id, proximo_passo, proximo_passo_em,
                              externo_tipo, externo_id, criado_por, atualizado_por)
    values (v_pipeline, v_etapa, v_pessoa, v_projeto, v_resp, nullif(left(btrim(coalesce(p->>'proximo_passo', '')), 500), ''),
            nullif(p->>'proximo_passo_em', '')::date, v_ext_tipo, v_ext_id, v_uid, v_uid)
    returning id into v_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'Esta pessoa já tem um negócio aberto neste pipeline e projeto.');
  end;
  insert into crm.historico (negocio_id, por, acao, para) values (v_id, v_uid, 'criado', (select nome from crm.etapas where id = v_etapa));
  insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte, ref_tipo, ref_id, detalhe, por)
  values (v_pessoa, 'crm', v_projeto, 'crm', 'crm.negocios', v_id::text,
          jsonb_build_object('acao', 'criado', 'pipeline', (select tipo from crm.pipelines where id = v_pipeline)), v_uid);
  perform pessoas.registrar_acesso('crm_criar', v_pessoa, jsonb_build_object('negocio', v_id));
  return jsonb_build_object('ok', true, 'msg', 'Negócio criado.', 'id', v_id);
end
$$;

create function public.crm_negocio_mover(p_negocio uuid, p_etapa int, p_motivo int default null, p_motivo_obs text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  n record; de record; para record; v_cod text; v_obs text := nullif(left(btrim(coalesce(p_motivo_obs, '')), 500), '');
  v_status text; v_tipo_pipeline text;
begin
  if not pessoas.pode_editar() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into n from crm.negocios where id = p_negocio for update;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Negócio não encontrado.'); end if;
  select * into de from crm.etapas where id = n.etapa_id;
  select * into para from crm.etapas where id = p_etapa and pipeline_id = n.pipeline_id;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Etapa não é deste pipeline.'); end if;
  if p_motivo is not null and not exists (select 1 from crm.motivos_perda where id = p_motivo and ativo
                                            and (pipeline_id is null or pipeline_id = n.pipeline_id)) then
    return jsonb_build_object('ok', false, 'msg', 'Motivo de perda inválido.');
  end if;
  v_cod := crm.validar_movimento(de.id, de.tipo, para.id, para.tipo, para.ativa, p_motivo is not null or v_obs is not null);
  if v_cod is not null then return jsonb_build_object('ok', false, 'msg', crm.msg_movimento(v_cod), 'codigo', v_cod); end if;

  v_status := case para.tipo when 'aberta' then 'aberto' else para.tipo end;
  begin
    update crm.negocios
       set etapa_id = para.id, status = v_status, entrou_etapa_em = now(),
           fechado_em = case when v_status = 'aberto' then null else now() end,
           motivo_perda_id = case when v_status = 'perdido' then p_motivo end,
           motivo_perda_obs = case when v_status = 'perdido' then v_obs end,
           atualizado_em = now(), atualizado_por = v_uid
     where id = n.id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'Já existe outro negócio aberto desta pessoa neste pipeline e projeto.');
  end;
  insert into crm.historico (negocio_id, por, acao, de, para, detalhe)
  values (n.id, v_uid, case when de.tipo <> 'aberta' and para.tipo = 'aberta' then 'reaberto' else 'etapa' end, de.nome, para.nome,
          case when v_status = 'perdido' then jsonb_build_object('motivo_id', p_motivo, 'motivo_obs', v_obs) else '{}' end);
  if v_status <> 'aberto' then
    select tipo into v_tipo_pipeline from crm.pipelines where id = n.pipeline_id;
    insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte, ref_tipo, ref_id, detalhe, por)
    values (n.pessoa_id, case when v_tipo_pipeline = 'ativacao' and v_status = 'ganho' then 'ativacao' else 'crm' end,
            n.projeto_id, 'crm', 'crm.negocios', n.id::text,
            jsonb_build_object('acao', v_status, 'pipeline', v_tipo_pipeline, 'etapa', para.nome), v_uid);
  end if;
  perform pessoas.registrar_acesso('crm_mover', n.pessoa_id, jsonb_build_object('negocio', n.id, 'de', de.id, 'para', para.id));
  return jsonb_build_object('ok', true, 'msg', 'Movido para ' || para.nome || '.', 'status', v_status);
end
$$;

create function public.crm_negocio_editar(p_negocio uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  n record; v_resp uuid; v_passo text; v_passo_em date; v_projeto bigint; v_mudou int := 0;
begin
  if not pessoas.pode_editar() then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into n from crm.negocios where id = p_negocio for update;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Negócio não encontrado.'); end if;
  begin
    v_resp := case when p ? 'responsavel_id' then nullif(p->>'responsavel_id', '')::uuid else n.responsavel_id end;
    v_passo := case when p ? 'proximo_passo' then nullif(left(btrim(coalesce(p->>'proximo_passo', '')), 500), '') else n.proximo_passo end;
    v_passo_em := case when p ? 'proximo_passo_em' then nullif(p->>'proximo_passo_em', '')::date else n.proximo_passo_em end;
    v_projeto := case when p ? 'projeto_id' then nullif(p->>'projeto_id', '')::bigint else n.projeto_id end;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Dados inválidos.');
  end;
  if v_resp is not null and v_resp is distinct from n.responsavel_id
     and not exists (select 1 from public.perfis where id = v_resp and status = 'ativo') then
    return jsonb_build_object('ok', false, 'msg', 'Responsável precisa ser alguém ativo da equipe.');
  end if;
  if v_projeto is not null and not exists (select 1 from mkt.projetos where id = v_projeto) then
    return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.');
  end if;
  begin
    update crm.negocios set responsavel_id = v_resp, proximo_passo = v_passo, proximo_passo_em = v_passo_em, projeto_id = v_projeto,
                            atualizado_em = now(), atualizado_por = v_uid
     where id = n.id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'Esta pessoa já tem um negócio aberto neste pipeline e projeto.');
  end;
  if v_resp is distinct from n.responsavel_id then
    insert into crm.historico (negocio_id, por, acao, de, para) values (n.id, v_uid, 'responsavel',
      (select nome from public.perfis where id = n.responsavel_id), (select nome from public.perfis where id = v_resp));
    v_mudou := v_mudou + 1;
  end if;
  if v_passo is distinct from n.proximo_passo or v_passo_em is distinct from n.proximo_passo_em then
    insert into crm.historico (negocio_id, por, acao, de, para)
    values (n.id, v_uid, 'proximo_passo', concat_ws(' · ', n.proximo_passo, n.proximo_passo_em::text), concat_ws(' · ', v_passo, v_passo_em::text));
    v_mudou := v_mudou + 1;
  end if;
  if v_projeto is distinct from n.projeto_id then
    insert into crm.historico (negocio_id, por, acao, de, para) values (n.id, v_uid, 'projeto',
      (select sigla from mkt.projetos where id = n.projeto_id), (select sigla from mkt.projetos where id = v_projeto));
    v_mudou := v_mudou + 1;
  end if;
  if v_mudou > 0 then
    perform pessoas.registrar_acesso('crm_editar', n.pessoa_id, jsonb_build_object('negocio', n.id, 'campos', v_mudou));
  end if;
  return jsonb_build_object('ok', true, 'msg', case when v_mudou = 0 then 'Nada mudou.' else 'Salvo.' end);
end
$$;

create function public.crm_negocio_historico(p_negocio uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not pessoas.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('quando', h.quando, 'acao', h.acao, 'de', h.de, 'para', h.para,
                                                       'detalhe', h.detalhe, 'por', pf.nome) order by h.quando desc, h.id desc), '[]'::jsonb)
            from crm.historico h left join public.perfis pf on pf.id = h.por where h.negocio_id = p_negocio);
end
$$;

-- configuração das etapas e motivos: só admin/dev (mexe na regra do Comercial)
create function public.crm_etapa_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id int; v_pipeline smallint; v_nome text := btrim(coalesce(p->>'nome', '')); v_tipo text := coalesce(p->>'tipo', 'aberta');
        v_ordem smallint; v_ativa boolean := coalesce((p->>'ativa')::boolean, true); e record;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  v_id := nullif(p->>'id', '')::int;
  if length(v_nome) not between 1 and 60 then return jsonb_build_object('ok', false, 'msg', 'Nome da etapa: 1 a 60 caracteres.'); end if;
  if v_tipo not in ('aberta', 'ganho', 'perdido') then return jsonb_build_object('ok', false, 'msg', 'Tipo inválido.'); end if;
  if v_id is null then
    v_pipeline := (p->>'pipeline_id')::smallint;
    if not exists (select 1 from crm.pipelines where id = v_pipeline) then return jsonb_build_object('ok', false, 'msg', 'Pipeline inválido.'); end if;
    v_ordem := coalesce(nullif(p->>'ordem', '')::smallint, (select coalesce(max(ordem), 0) + 1 from crm.etapas where pipeline_id = v_pipeline));
    begin
      insert into crm.etapas (pipeline_id, nome, ordem, tipo, ativa) values (v_pipeline, v_nome, v_ordem, v_tipo, v_ativa) returning id into v_id;
    exception when unique_violation then return jsonb_build_object('ok', false, 'msg', 'Já existe etapa com este nome no pipeline.');
    end;
  else
    select * into e from crm.etapas where id = v_id for update;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Etapa não encontrada.'); end if;
    if exists (select 1 from crm.negocios where etapa_id = v_id) and (v_tipo <> e.tipo) then
      return jsonb_build_object('ok', false, 'msg', 'A etapa tem negócios: não dá para trocar o tipo.');
    end if;
    if not v_ativa and exists (select 1 from crm.negocios where etapa_id = v_id and status = 'aberto') then
      return jsonb_build_object('ok', false, 'msg', 'A etapa tem negócios abertos: mova-os antes de desativar.');
    end if;
    begin
      update crm.etapas set nome = v_nome, tipo = v_tipo, ativa = v_ativa, ordem = coalesce(nullif(p->>'ordem', '')::smallint, ordem)
       where id = v_id;
    exception when unique_violation then return jsonb_build_object('ok', false, 'msg', 'Já existe etapa com este nome no pipeline.');
    end;
    v_pipeline := e.pipeline_id;
  end if;
  if not exists (select 1 from crm.etapas where pipeline_id = v_pipeline and ativa and tipo = 'aberta') then
    raise exception 'o pipeline precisa de ao menos uma etapa aberta ativa' using errcode = '23514';
  end if;
  perform pessoas.registrar_acesso('crm_config', null, jsonb_build_object('etapa', v_id));
  return jsonb_build_object('ok', true, 'msg', 'Etapa salva.', 'id', v_id);
end
$$;

create function public.crm_motivo_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id int := nullif(p->>'id', '')::int; v_nome text := btrim(coalesce(p->>'nome', '')); v_pipeline smallint := nullif(p->>'pipeline_id', '')::smallint;
begin
  if not coalesce(public.gp_is_admin(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if length(v_nome) not between 2 and 80 then return jsonb_build_object('ok', false, 'msg', 'Motivo: 2 a 80 caracteres.'); end if;
  if v_pipeline is not null and not exists (select 1 from crm.pipelines where id = v_pipeline) then
    return jsonb_build_object('ok', false, 'msg', 'Pipeline inválido.');
  end if;
  begin
    if v_id is null then
      insert into crm.motivos_perda (pipeline_id, nome) values (v_pipeline, v_nome) returning id into v_id;
    else
      update crm.motivos_perda set nome = v_nome, pipeline_id = v_pipeline, ativo = coalesce((p->>'ativo')::boolean, ativo) where id = v_id;
      if not found then return jsonb_build_object('ok', false, 'msg', 'Motivo não encontrado.'); end if;
    end if;
  exception when unique_violation then return jsonb_build_object('ok', false, 'msg', 'Este motivo já existe.');
  end;
  perform pessoas.registrar_acesso('crm_config', null, jsonb_build_object('motivo', v_id));
  return jsonb_build_object('ok', true, 'msg', 'Motivo salvo.', 'id', v_id);
end
$$;

-- ─── 10. Grants ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  -- internas: ninguém executa de fora (funções nascem com EXECUTE para PUBLIC)
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace in ('pessoas'::regnamespace, 'crm'::regnamespace) loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'public'::regnamespace and (p.proname like 'pessoas\_%' or p.proname like 'crm\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    if f::text like 'pessoas_registrar_lead(%' then
      execute format('grant execute on function %s to service_role', f);
    else
      execute format('grant execute on function %s to authenticated', f);
    end if;
  end loop;
end
$grants$;
revoke all on all tables in schema pessoas from public, anon, authenticated;
revoke all on all tables in schema crm from public, anon, authenticated;

-- conferência: nenhuma tabela nova aberta, só as funções certas com execute
do $confere$
begin
  if exists (select 1 from information_schema.role_table_grants
              where table_schema in ('pessoas', 'crm') and grantee in ('anon', 'authenticated', 'PUBLIC')) then
    raise exception '20261005o: tabela de pessoas/crm com grant para anon/authenticated';
  end if;
  if has_function_privilege('anon', 'public.pessoas_ficha(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.pessoas_registrar_lead(jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.pessoas_registrar_lead(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_negocios_listar(smallint,bigint,uuid,text)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.registrar(jsonb,text,uuid)', 'execute') then
    raise exception '20261005o: grants das funções fora do esperado';
  end if;
end
$confere$;

-- ═══ REVERSÃO (numa transação; apaga a base de pessoas e o CRM: exportar antes se houver dado real) ════════════════
-- begin;
-- do $$ declare f regprocedure; begin
--   for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
--             and (p.proname like 'pessoas\_%' or p.proname like 'crm\_%')
--   loop execute format('drop function %s', f); end loop; end $$;
-- drop schema crm cascade;
-- drop schema pessoas cascade;
-- update mkt_web.visitantes set lead_ref = null where lead_ref is not null;   -- só se a 20261005n estiver aplicada
-- commit;
