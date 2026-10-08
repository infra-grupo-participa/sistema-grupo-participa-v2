-- 20261005r: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: o arquivo inteiro de uma vez (SQL editor do Supabase, psql ou execute_sql do MCP), como postgres.
--   Todo resultado vai para a temp _z_out; o "select" antes do "rollback" mostra tudo. Se o cliente só mostrar o
--   resultado do último comando, rode até o select (inclusive), leia e rode o rollback em seguida. NÃO deixe aberta.
--   lock_timeout 3s / statement_timeout 20s (manual §4). Medido no MCP: cabe numa chamada só.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado de 20261005r_pessoas_e_crm_fundacao.sql; mudou a
-- migration, gerar de novo). Depois dele, DADOS FICTÍCIOS (e-mails @exemplo.com.br, telefones DDD 99 9 3210-000x,
-- conferidos sem nenhum aluno/comprador real com a mesma chave) e as provas. Nenhum dado real vai para a saída:
-- os perfis admin/visualizador são escolhidos por SELECT e só o resultado booleano aparece.
--
-- Esperado: NENHUMA linha começando com "ERRADO".
--   1  estrutura: schemas, config (3), crm.config 1 linha (escrita desligada), vendedor 0, log 1 (criação da config)
--   2  e-mail com espaço/maiúscula → mesma pessoa; pessoa nova
--   3  aluno existente vira REFERÊNCIA (aluno_id), sem cópia de nome/e-mail
--   4  telefone igual + e-mail diferente → pessoa nova + revisão, não funde
--   5  sem e-mail + telefone de 1 candidato com nome compatível → casa; nome diferente → revisão; 2 candidatos → revisão
--   6  só nome igual → pessoa nova + revisão (nunca casa)
--   7  mescla = alias (nada movido), e-mail do alias resolve para a pessoa que ficou; desfazer volta
--   8  busca e ficha (admin), sem "documento"/CPF em nenhuma saída
--   9  crm.log recusa UPDATE/DELETE/TRUNCATE
--   10 crm.tg_log grava diff ao alterar crm.config/crm.vendedor; UPDATE sem mudança não grava; resumo lido e limpo
--   11 helpers com role authenticated + JWT: admin real = gestor; visualizador real = nada; sem JWT = nada
--   12 permissões: anon sem execute em nada novo; visualizador recusado (42501); authenticated sem tabela

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, ''));
$$;

-- ═══ CORPO DA MIGRATION ══════════════════════════════════════════════════════════════════════════════════════════════
-- 20261005r: F0 do Comercial — base única de pessoas (schema pessoas) + fundação do CRM (schema crm)
--
-- STATUS: NÃO APLICADA — aguardando ok do Arthur. Ensaio: 20261005r_ensaio.sql (begin … rollback). Medidas e planos:
-- 20261005r.explain.md. Converge duas propostas: o schema `pessoas` da branch victor (20261005o, nunca aplicada) e o
-- modelo `crm` de docs/projetos/comercial/backend-arquitetura.md (seções 2, 3.1, 3.2, 4, 6). Registro do que foi
-- aproveitado/descartado: docs/projetos/comercial/convergencia-pessoas-crm.md.
--
-- O QUE FAZ
--   1. pessoas: UMA pessoa por identidade, para a central inteira. Aluno e comprador por REFERÊNCIA (aluno_id,
--      comprador_id), nunca cópia. Dado próprio só o que o lead informou (e-mail, telefone, nome+CEP normalizados),
--      a origem (mkt.projetos, mkt.paginas, campanha no padrão da casa, UTMs) e os eventos.
--      Casamento (manual §7 "casar pessoa por e-mail, nunca por nome ou CPF"; D1 e D2 aprovadas):
--        a) E-MAIL primeiro: pessoas.identificadores, thb_alunos e compradores, cada um pelo SEU índice de expressão.
--        b) TELEFONE (chave = controle.fone_key, DDD + 8 últimos) só casa sozinho quando a entrada NÃO tem e-mail e há
--           exatamente 1 candidato, com nome compatível. Telefone igual com e-mail diferente → revisão, nunca funde.
--        c) Nome + CEP e "só nome" nunca casam: no máximo abrem revisão (sugestão para uma pessoa decidir).
--        d) CPF/documento NÃO entra: nem identificador, nem cascata, nem retorno de função.
--      Mescla = ALIAS reversível: situacao='mesclada' + mesclada_em (pessoa que fica). Nada é apagado nem movido;
--      leituras resolvem a pessoa atual (pessoas.atual) e juntam o grupo (pessoas.grupo). Desfazer = limpar.
--   2. crm (só a fundação F0): crm.config (kill-switches, 1 linha), crm.vendedor (sobre public.perfis), crm.log
--      append-only (UPDATE/DELETE/TRUNCATE barrados por trigger), crm.tg_log() genérica (ligada em vendedor e config
--      para ser provada), helpers crm.eh_gestor/eh_vendedor/eh_comercial. Funis, negócios etc. = F1.
--   3. Índice novo public.ix_compradores_fone_key (medido: a busca por fone_key em compradores fazia Seq Scan de
--      26.851 linhas, 420 ms). Mesma expressão que a cascata usa: controle.fone_key((telefone)::text).
--
-- ACESSO (LGPD)
--   - Schemas pessoas e crm NÃO expostos no PostgREST. Tabelas com RLS ligada, sem policy e sem grant.
--   - pessoas: só funções public.pessoas_* (SECURITY DEFINER, permissão no corpo, 42501). Quem vê: admin/dev
--     (gp_is_admin) + áreas de pessoas.config. E-mail/telefone completos só admin/dev ou 'areas_contato'.
--   - public.pessoas_registrar_lead: só service_role (servidor do formulário), nunca o navegador.
--   - crm: authenticated tem USAGE no schema só para executar os helpers (base das policies da F1). Tabelas fechadas.
--   - Toda função: revoke de PUBLIC/anon; conferência no fim aborta se algo novo ficar executável por anon.
--
-- O QUE CRIA
--   schema pessoas: config, pessoas, identificadores, origens, eventos, revisao, acessos + funções internas
--   schema crm:     config, vendedor, log + tg_log, tg_log_imutavel, eh_gestor, eh_vendedor, eh_comercial
--   public.pessoas_meu_acesso, pessoas_buscar, pessoas_ficha, pessoas_cadastrar, pessoas_revisao_listar,
--          pessoas_revisao_decidir, pessoas_mescla_desfazer                 → authenticated + permissão no corpo
--   public.pessoas_registrar_lead                                            → só service_role
--   public.ix_compradores_fone_key (índice)
--
-- AS 5 PERGUNTAS (medido em 05/10/2026, ver .explain.md)
--   escala: base nasce vazia (sem backfill). Fontes: thb_alunos 1.896 (1.875 com e-mail, 1.841 ativos com fone_key),
--     compradores 26.851 (26.851 com e-mail, 26.535 com fone_key). Resolver = custo por lead, não pela base: só
--     Index Scan nas fontes; com 10× de compradores o custo continua log(n).
--   índice: thb_alunos_email_uidx lower(TRIM(BOTH FROM email)) parcial (predicado repetido literal);
--     ix_compradores_email_lower_all lower(btrim((email)::text)); ix_thb_alunos_fone_key_ativo
--     controle.fone_key(COALESCE(telefone_e164, telefone)) WHERE cancelado_em IS NULL; ix_compradores_fone_key (novo);
--     idx_thb_alunos_nome_trgm (sugestão por nome); pessoas.identificadores (tipo, chave).
--   frequência: 1 resolução por lead de formulário/cadastro (dezenas a poucas centenas/dia); telas leem ao abrir.
--   repetição: por lead, ≤ 3 lookups de e-mail + ≤ 3 de telefone, todos por índice; nada por linha nas telas.
--   reversão: nada lê os schemas ainda; bloco REVERSÃO no fim (F0 vazia: drop). crm.config.escrita_ligada nasce false.
--
-- PREMISSAS (guarda aborta se faltar): schemas pessoas/crm não existem; nenhuma public.pessoas_*/crm_*;
--   20261005m aplicada (mkt.projetos, mkt.paginas, mkt.campanha_traduzir, mkt.sem_acento); controle.fone_key(text)
--   IMMUTABLE; public.gp_is_admin(); pg_trgm em public; colunas de perfis/thb_alunos/compradores/compras; os índices
--   de e-mail/telefone acima com a expressão exata; ix_compradores_fone_key JÁ existe e é válido (criado antes por
--   20261005r_pre_indice_compradores.sql, com create index concurrently, sem travar a escrita do webhook Hotmart).

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_falta text;
begin
  if to_regnamespace('pessoas') is not null or to_regnamespace('crm') is not null then
    raise exception '20261005r: schema pessoas ou crm já existe (migration já aplicada?)';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and (p.proname like 'pessoas\_%' or p.proname like 'crm\_%')) then
    raise exception '20261005r: já existem funções public.pessoas_* ou public.crm_*';
  end if;
  if to_regclass('mkt.projetos') is null or to_regclass('mkt.paginas') is null
     or to_regprocedure('mkt.campanha_traduzir(text)') is null or to_regprocedure('mkt.sem_acento(text)') is null then
    raise exception '20261005r: falta a 20261005m (mkt.projetos, mkt.paginas, mkt.campanha_traduzir, mkt.sem_acento)';
  end if;
  if to_regprocedure('controle.fone_key(text)') is null
     or (select provolatile from pg_proc where oid = to_regprocedure('controle.fone_key(text)')) <> 'i' then
    raise exception '20261005r: controle.fone_key(text) ausente ou não IMMUTABLE';
  end if;
  if to_regprocedure('public.gp_is_admin()') is null then
    raise exception '20261005r: public.gp_is_admin() ausente';
  end if;
  if not exists (select 1 from pg_extension where extname = 'pg_trgm' and extnamespace = 'public'::regnamespace) then
    raise exception '20261005r: pg_trgm não está no schema public';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception '20261005r: papel service_role ausente';
  end if;
  select string_agg(x.t || '.' || x.c, ', ') into v_falta
    from (values
      ('perfis','id'), ('perfis','nome'), ('perfis','cargo'), ('perfis','status'), ('perfis','areas'), ('perfis','funcoes'),
      ('thb_alunos','id'), ('thb_alunos','nome'), ('thb_alunos','email'), ('thb_alunos','telefone'),
      ('thb_alunos','telefone_e164'), ('thb_alunos','cep'), ('thb_alunos','comprador_id'), ('thb_alunos','turma_id'),
      ('thb_alunos','cancelado_em'), ('thb_turmas','id'), ('thb_turmas','codigo'),
      ('compradores','id'), ('compradores','nome'), ('compradores','email'), ('compradores','telefone'),
      ('compras','id'), ('compras','comprador_id'), ('compras','status'), ('compras','produto_nome'),
      ('compras','data_compra'), ('compras','preco')
    ) x(t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = 'public' and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then
    raise exception '20261005r: colunas ausentes: %', v_falta;
  end if;
  -- índices que a cascata usa, com a expressão EXATA (manual §5)
  select string_agg(x.i, ', ') into v_falta
    from (values
      ('thb_alunos_email_uidx',        'lower(TRIM(BOTH FROM email))) WHERE ((email IS NOT NULL) AND (email <> ''''::text))'),
      ('ix_compradores_email_lower_all','(lower(btrim((email)::text)))'),
      ('ix_thb_alunos_fone_key_ativo', '(controle.fone_key(COALESCE(telefone_e164, telefone))) WHERE (cancelado_em IS NULL)'),
      ('idx_thb_alunos_nome_trgm',     'gin (nome gin_trgm_ops)'),
      ('thb_alunos_comprador_uidx',    '(comprador_id) WHERE (comprador_id IS NOT NULL)')
    ) x(i, trecho)
   where not exists (select 1 from pg_indexes pi where pi.schemaname = 'public' and pi.indexname = x.i
                        and position(x.trecho in pi.indexdef) > 0);
  if v_falta is not null then
    raise exception '20261005r: índice ausente ou com expressão diferente: %', v_falta;
  end if;
  if not exists (select 1 from pg_index x join pg_class c on c.oid = x.indexrelid
                  where c.oid = to_regclass('public.ix_compradores_fone_key') and x.indisvalid
                    and pg_get_indexdef(c.oid) like '%controle.fone_key((telefone)::text)%WHERE (telefone IS NOT NULL)%') then
    raise exception '20261005r: public.ix_compradores_fone_key ausente ou inválido (rodar 20261005r_pre_indice_compradores.sql antes)';
  end if;
end
$guarda$;

-- ─── 1. Schemas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create schema pessoas;
revoke all on schema pessoas from public, anon, authenticated;
comment on schema pessoas is
  'Base única de pessoas da central (lead, aluno, comprador = a mesma pessoa). Aluno e comprador por referência. Casa por '
  'e-mail; telefone só sem e-mail e com 1 candidato; nome nunca casa (revisão). Sem CPF. Mescla = alias. Fechado: só '
  'funções public.pessoas_*. 20261005r.';

create schema crm;
revoke all on schema crm from public, anon, authenticated;
grant usage on schema crm to authenticated;   -- só para executar os helpers (policies da F1); tabelas sem grant
comment on schema crm is
  'CRM do Comercial (docs/projetos/comercial/backend-arquitetura.md). F0: config, vendedor, log, helpers de papel. '
  'Não exposto no PostgREST: o front fala só com RPCs public.crm_* (F1+). 20261005r.';

-- ─── 2. pessoas: configuração e permissões ───────────────────────────────────────────────────────────────────────────
create table pessoas.config (
  chave text primary key,
  valor jsonb not null check (jsonb_typeof(valor) = 'array'),
  obs   text
);
alter table pessoas.config enable row level security;
insert into pessoas.config (chave, valor, obs) values
  ('areas_leitura', '[]', 'Áreas de perfis.areas cujo gestor/operador ATIVO lê a base de pessoas, além de admin/dev. Vazio = só admin e dev.'),
  ('areas_edicao',  '[]', 'Áreas que cadastram pessoa, decidem revisão e desfazem mescla, além de admin/dev. Vazio = só admin e dev.'),
  ('areas_contato', '[]', 'Áreas que veem e-mail e telefone completos, além de admin/dev. Os outros veem mascarado.');

create function pessoas.areas_config(p_chave text) returns text[]
language sql stable set search_path = '' as $$
  select coalesce((select array_agg(e) from pessoas.config c, jsonb_array_elements_text(c.valor) e
                    where c.chave = p_chave), '{}'::text[]);
$$;

create function pessoas.tem_area(p_chave text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(exists (select 1 from public.perfis p
                           where p.id = (select auth.uid()) and p.status = 'ativo' and p.cargo in ('gestor', 'operador')
                             and coalesce(p.areas, '{}') && pessoas.areas_config(p_chave)), false);
$$;

create function pessoas.pode_ver() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false) or coalesce(pessoas.tem_area('areas_leitura'), false);
$$;

create function pessoas.pode_editar() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false) or coalesce(pessoas.tem_area('areas_edicao'), false);
$$;

create function pessoas.pode_ver_contato() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false)
      or (coalesce(pessoas.pode_ver(), false) and coalesce(pessoas.tem_area('areas_contato'), false));
$$;

-- ─── 3. Normalização (pura) ──────────────────────────────────────────────────────────────────────────────────────────
create function pessoas.so_digitos(p text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g');
$$;

-- telefone BR: tira 55 e o 0 de longa distância; sobra DDD (sem zero) + 8 ou 9 dígitos (9 dígitos começa com 9)
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

-- chave de casamento do telefone = controle.fone_key (D2: a MESMA função dos índices de thb_alunos/compradores/controle)
create function pessoas.chave_telefone(p text) returns text
language sql immutable set search_path = '' as $$
  select case when pessoas.norm_telefone(p) is not null then controle.fone_key(pessoas.norm_telefone(p)) end;
$$;

-- e-mail: mesma ordem dos índices lower(btrim(...)); formato mínimo
create function pessoas.norm_email(p text) returns text
language sql immutable set search_path = '' as $$
  select case when lower(btrim(p)) ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then lower(btrim(p)) end;
$$;

create function pessoas.norm_nome(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(btrim(regexp_replace(regexp_replace(mkt.sem_acento(coalesce(p, '')), '[^A-Z ]', ' ', 'g'), ' +', ' ', 'g')), '');
$$;

create function pessoas.norm_cep(p text) returns text
language sql immutable set search_path = '' as $$
  select case when length(pessoas.so_digitos(p)) = 8 and pessoas.so_digitos(p) !~ '^0+$' then pessoas.so_digitos(p) end;
$$;

create function pessoas.chave_nome_cep(p_nome text, p_cep text) returns text
language sql immutable set search_path = '' as $$
  select case when pessoas.norm_nome(p_nome) like '% %' and pessoas.norm_cep(p_cep) is not null
              then pessoas.norm_nome(p_nome) || '|' || pessoas.norm_cep(p_cep) end;
$$;

-- nomes compatíveis = mesmo primeiro nome (sem informação de um lado = não contradiz)
create function pessoas.nomes_compativeis(a text, b text) returns boolean
language sql immutable set search_path = '' as $$
  select pessoas.norm_nome(a) is null or pessoas.norm_nome(b) is null
      or split_part(pessoas.norm_nome(a), ' ', 1) = split_part(pessoas.norm_nome(b), ' ', 1);
$$;

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
  ref           text not null unique default ('pe_' || replace(gen_random_uuid()::text, '-', ''))
                  check (ref ~ '^pe_[0-9a-f]{32}$'),                                   -- referência opaca p/ outros sistemas
  nome          text check (nome is null or length(btrim(nome)) between 2 and 160),   -- só de quem não é aluno/comprador
  aluno_id      uuid unique references public.thb_alunos(id) on delete set null,      -- referência, nunca cópia
  comprador_id  uuid unique references public.compradores(id) on delete set null,     -- referência, nunca cópia
  situacao      text not null default 'ativa' check (situacao in ('ativa', 'revisar', 'mesclada')),
  mesclada_em   uuid references pessoas.pessoas(id) on delete restrict,               -- alias: pessoa que fica
  teste         boolean not null default false,
  criado_em     timestamptz not null default now(),
  criado_por    uuid references public.perfis(id) on delete set null,
  atualizado_em timestamptz not null default now(),
  constraint pessoas_mescla_check check ((situacao = 'mesclada') = (mesclada_em is not null)),
  constraint pessoas_mescla_propria_check check (mesclada_em is null or mesclada_em <> id)
);
alter table pessoas.pessoas enable row level security;
create index pessoas_mesclada_idx on pessoas.pessoas (mesclada_em) where mesclada_em is not null;
create index pessoas_nome_norm_idx on pessoas.pessoas (pessoas.norm_nome(nome)) where nome is not null;
create index pessoas_nome_trgm_idx on pessoas.pessoas using gin (nome public.gin_trgm_ops) where nome is not null;
comment on table pessoas.pessoas is 'Uma linha por pessoa. Aluno/comprador por referência. situacao=mesclada + mesclada_em = '
  'alias reversível (nada é movido). Leituras: pessoas.atual(id) e pessoas.grupo(atual).';

-- o que a pessoa informou (normalizado). Sem documento/CPF. Valor igual ao do aluno/comprador ligado NÃO entra.
create table pessoas.identificadores (
  id        bigint generated always as identity primary key,
  pessoa_id uuid not null references pessoas.pessoas(id) on delete restrict,
  tipo      text not null check (tipo in ('email', 'telefone', 'nome_cep')),
  valor     text not null check (length(valor) between 1 and 320),
  chave     text not null check (length(chave) between 1 and 320),
  origem    text not null check (origem in ('formulario', 'crm', 'importacao')),
  criado_em timestamptz not null default now(),
  unique (pessoa_id, tipo, chave)
);
alter table pessoas.identificadores enable row level security;
create unique index identificadores_email_unico on pessoas.identificadores (tipo, chave) where tipo = 'email';
create index identificadores_chave_idx on pessoas.identificadores (tipo, chave);

create table pessoas.origens (
  id              bigint generated always as identity primary key,
  pessoa_id       uuid not null references pessoas.pessoas(id) on delete restrict,
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

create table pessoas.eventos (
  id         bigint generated always as identity primary key,
  pessoa_id  uuid not null references pessoas.pessoas(id) on delete restrict,
  tipo       text not null check (tipo in ('lead', 'mql', 'nao_mql', 'cadastro', 'compra', 'ativacao', 'crm', 'vinculo',
                                           'mescla', 'mescla_desfeita', 'revisao')),
  projeto_id bigint references mkt.projetos(id) on delete restrict,
  origem_id  bigint references pessoas.origens(id) on delete set null,
  fonte      text not null check (fonte in ('formulario', 'crm', 'importacao', 'sistema')),
  ref_tipo   text check (ref_tipo is null or ref_tipo in ('crm.negocio', 'public.compras', 'public.thb_alunos',
                                                         'public.compradores', 'pessoas.pessoas', 'pessoas.revisao')),
  ref_id     text check (ref_id is null or length(ref_id) <= 80),
  detalhe    jsonb not null default '{}' check (jsonb_typeof(detalhe) = 'object' and length(detalhe::text) <= 2000),
  quando     timestamptz not null default now(),
  por        uuid references public.perfis(id) on delete set null
);
alter table pessoas.eventos enable row level security;
create index eventos_pessoa_idx on pessoas.eventos (pessoa_id, quando);
create index eventos_projeto_idx on pessoas.eventos (projeto_id, tipo, quando) where projeto_id is not null;

-- dúvida de identidade para uma pessoa decidir (guarda só o motivo, nunca o valor do identificador)
create table pessoas.revisao (
  id           bigint generated always as identity primary key,
  pessoa_id    uuid not null references pessoas.pessoas(id) on delete restrict,
  motivo       text not null check (motivo in ('email_conflito', 'telefone_email_diferente', 'telefone_nome_diferente',
                                               'telefone_varios', 'nome_cep', 'so_nome')),
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

-- quem consultou e quem alterou (LGPD). Sem FK na pessoa: o registro fica.
create table pessoas.acessos (
  id        bigint generated always as identity primary key,
  quando    timestamptz not null default now(),
  por       uuid,
  acao      text not null check (acao in ('buscar', 'ver_ficha', 'cadastrar', 'revisar', 'desfazer_mescla')),
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

-- ─── 5. Índice de telefone em compradores (medido: Seq Scan 26.851 linhas, 420 ms) ──────────────────────────────────
-- (índice criado antes, à parte: 20261005r_pre_indice_compradores.sql)
comment on index public.ix_compradores_fone_key is 'Casamento por telefone da base pessoas (20261005r). Consultar com a MESMA '
  'expressão controle.fone_key((telefone)::text) e repetir "telefone is not null".';

-- ─── 6. Alias e referência ───────────────────────────────────────────────────────────────────────────────────────────
-- pessoa que fica no fim da cadeia de alias
create function pessoas.atual(p_pessoa uuid) returns uuid
language plpgsql stable set search_path = '' as $$
declare v uuid := p_pessoa; n uuid; i int := 0;
begin
  if p_pessoa is null then return null; end if;
  loop
    select mesclada_em into n from pessoas.pessoas where id = v;
    exit when n is null or i > 20;
    v := n; i := i + 1;
  end loop;
  return v;
end
$$;

-- a pessoa atual + todas as que apontam para ela (direta ou indiretamente)
create function pessoas.grupo(p_atual uuid) returns uuid[]
language sql stable set search_path = '' as $$
  with recursive g(id) as (
    select p_atual
    union
    select p.id from pessoas.pessoas p join g on p.mesclada_em = g.id
  )
  select coalesce(array_agg(id), '{}') from g where id is not null;
$$;

create function pessoas.pessoa_do_aluno(p_aluno uuid) returns uuid
language plpgsql set search_path = '' as $$
declare v uuid; v_comprador uuid;
begin
  select id into v from pessoas.pessoas where aluno_id = p_aluno;
  if found then return pessoas.atual(v); end if;
  select a.comprador_id into v_comprador from public.thb_alunos a where a.id = p_aluno;
  if not found then return null; end if;
  -- o comprador do aluno já é pessoa (sem aluno)? é a mesma pessoa: liga nela
  if v_comprador is not null then
    select id into v from pessoas.pessoas where comprador_id = v_comprador and aluno_id is null;
    if found then
      update pessoas.pessoas set aluno_id = p_aluno, atualizado_em = now() where id = v;
      insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v, 'vinculo', 'sistema', 'public.thb_alunos', p_aluno::text);
      return pessoas.atual(v);
    end if;
  end if;
  insert into pessoas.pessoas (aluno_id, comprador_id)
  values (p_aluno, case when v_comprador is not null
                         and not exists (select 1 from pessoas.pessoas x where x.comprador_id = v_comprador) then v_comprador end)
  on conflict (aluno_id) do nothing
  returning id into v;
  if v is null then select id into v from pessoas.pessoas where aluno_id = p_aluno; return pessoas.atual(v); end if;
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v, 'vinculo', 'sistema', 'public.thb_alunos', p_aluno::text);
  return v;
end
$$;

create function pessoas.pessoa_do_comprador(p_comprador uuid) returns uuid
language plpgsql set search_path = '' as $$
declare v uuid; v_aluno uuid;
begin
  select id into v from pessoas.pessoas where comprador_id = p_comprador;
  if found then return pessoas.atual(v); end if;
  if not exists (select 1 from public.compradores where id = p_comprador) then return null; end if;
  select a.id into v_aluno from public.thb_alunos a where a.comprador_id = p_comprador;   -- thb_alunos_comprador_uidx
  if v_aluno is not null then
    v := pessoas.pessoa_do_aluno(v_aluno);
    update pessoas.pessoas set comprador_id = p_comprador, atualizado_em = now()
     where id = v and comprador_id is null and not exists (select 1 from pessoas.pessoas x where x.comprador_id = p_comprador);
    return v;
  end if;
  insert into pessoas.pessoas (comprador_id) values (p_comprador) on conflict (comprador_id) do nothing returning id into v;
  if v is null then select id into v from pessoas.pessoas where comprador_id = p_comprador; return pessoas.atual(v); end if;
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v, 'vinculo', 'sistema', 'public.compradores', p_comprador::text);
  return v;
end
$$;

-- 'p:<pessoa>' | 'a:<aluno>' | 'c:<comprador>' → pessoa atual (cria a linha de referência se faltar)
create function pessoas.garantir(p_ents text[]) returns uuid[]
language plpgsql set search_path = '' as $$
declare e text; v uuid[] := '{}'; x uuid;
begin
  foreach e in array coalesce(p_ents, '{}') loop
    x := case left(e, 2)
           when 'p:' then pessoas.atual(substr(e, 3)::uuid)
           when 'a:' then pessoas.pessoa_do_aluno(substr(e, 3)::uuid)
           when 'c:' then pessoas.pessoa_do_comprador(substr(e, 3)::uuid)
         end;
    if x is not null and not x = any(v) then v := v || x; end if;
  end loop;
  return v;
end
$$;

-- dados para exibir, do GRUPO da pessoa: aluno e comprador lidos na hora (fonte da verdade). Sem documento.
create function pessoas.dados(p_pessoa uuid)
returns table (d_nome text, d_email text, d_telefone text, d_aluno_id uuid, d_aluno_nome text, d_turma text,
               d_aluno_cancelado boolean, d_comprador_id uuid)
language sql stable set search_path = '' as $$
  with g as (select p.* from pessoas.pessoas p where p.id = any(pessoas.grupo(p_pessoa))),
  r as (
    select (array_agg(g.aluno_id order by g.id = p_pessoa desc, g.criado_em) filter (where g.aluno_id is not null))[1] aluno_id,
           (array_agg(g.comprador_id order by g.id = p_pessoa desc, g.criado_em) filter (where g.comprador_id is not null))[1] comprador_id,
           (array_agg(g.nome order by g.id = p_pessoa desc, g.criado_em) filter (where g.nome is not null))[1] nome
      from g
  )
  select coalesce(a.nome, c.nome::text, r.nome),
         coalesce(pessoas.norm_email(a.email), pessoas.norm_email(c.email::text),
                  (select i.valor from pessoas.identificadores i
                    where i.pessoa_id = any(pessoas.grupo(p_pessoa)) and i.tipo = 'email' order by i.id desc limit 1)),
         coalesce(pessoas.norm_telefone(coalesce(a.telefone_e164, a.telefone)), pessoas.norm_telefone(c.telefone::text),
                  (select i.valor from pessoas.identificadores i
                    where i.pessoa_id = any(pessoas.grupo(p_pessoa)) and i.tipo = 'telefone' order by i.id desc limit 1)),
         r.aluno_id, a.nome, t.codigo, a.cancelado_em is not null, coalesce(r.comprador_id, a.comprador_id)
    from r
    left join public.thb_alunos a on a.id = r.aluno_id
    left join public.thb_turmas t on t.id = a.turma_id
    left join public.compradores c on c.id = coalesce(r.comprador_id, a.comprador_id);
$$;

-- ─── 7. Casamento ────────────────────────────────────────────────────────────────────────────────────────────────────
-- Quem tem esta chave de telefone (pessoas, alunos ATIVOS, compradores). Tudo por índice: identificadores (tipo,chave),
-- ix_thb_alunos_fone_key_ativo, ix_compradores_fone_key. Máximo 20 entidades.
create function pessoas.candidatos_telefone(p_fk text)
returns table (ent text, nome_ent text)
language sql stable set search_path = '' as $$
  with c as (
    select pessoas.atual(i.pessoa_id) pessoa, null::uuid aluno, null::uuid comprador
      from pessoas.identificadores i where i.tipo = 'telefone' and i.chave = p_fk
    union
    select null::uuid, a.id, a.comprador_id from public.thb_alunos a
     where controle.fone_key(coalesce(a.telefone_e164, a.telefone)) = p_fk and a.cancelado_em is null
    union
    select null::uuid, a2.id, c.id from public.compradores c
      left join public.thb_alunos a2 on a2.comprador_id = c.id
     where controle.fone_key((c.telefone)::text) = p_fk and c.telefone is not null
  ), r as (
    select coalesce(c.pessoa,
                    (select pessoas.atual(p.id) from pessoas.pessoas p where c.aluno is not null and p.aluno_id = c.aluno),
                    (select pessoas.atual(p.id) from pessoas.pessoas p where c.comprador is not null and p.comprador_id = c.comprador)) pessoa,
           c.aluno, c.comprador
      from c
  )
  select distinct on (1) coalesce('p:' || r.pessoa, 'a:' || r.aluno, 'c:' || r.comprador),
         coalesce((select d.d_nome from pessoas.dados(r.pessoa) d where r.pessoa is not null),
                  (select a.nome from public.thb_alunos a where a.id = r.aluno),
                  (select c.nome::text from public.compradores c where c.id = r.comprador))
    from r
   order by 1
   limit 20;
$$;

-- Sugestão por nome (NUNCA casa sozinho): nome+CEP igual ou nome completo igual. Alunos pelo índice trigram.
create function pessoas.candidatos_nome(p_nome text, p_cep text)
returns table (ent text, motivo text)
language sql stable set search_path = '' as $$
  select distinct on (s.ent) s.ent, s.motivo from (
    select 'p:' || pessoas.atual(i.pessoa_id) ent, 'nome_cep' motivo
      from pessoas.identificadores i
     where i.tipo = 'nome_cep' and i.chave = pessoas.chave_nome_cep(p_nome, p_cep)
    union all
    select coalesce('p:' || (select pessoas.atual(p.id) from pessoas.pessoas p where p.aluno_id = a.id), 'a:' || a.id),
           case when pessoas.chave_nome_cep(a.nome, a.cep) = pessoas.chave_nome_cep(p_nome, p_cep) then 'nome_cep' else 'so_nome' end
      from public.thb_alunos a
     where a.nome operator(public.%) p_nome and pessoas.norm_nome(a.nome) = pessoas.norm_nome(p_nome)
    union all
    select 'p:' || pessoas.atual(p.id), 'so_nome'
      from pessoas.pessoas p
     where p.nome is not null and pessoas.norm_nome(p.nome) = pessoas.norm_nome(p_nome) and p.situacao <> 'mesclada'
  ) s
  where pessoas.norm_nome(p_nome) like '% %'
  order by s.ent, s.motivo   -- 'nome_cep' antes de 'so_nome'
  limit 20;
$$;

-- A cascata. E-mail → (sem e-mail) telefone com 1 candidato e nome compatível → pessoa nova. Dúvida = revisão.
create function pessoas.resolver(p_nome text, p_email text, p_telefone text, p_cep text,
                                 p_teste boolean default false, p_por uuid default null)
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_email text := pessoas.norm_email(p_email);
  v_fk    text := pessoas.chave_telefone(p_telefone);
  v_pessoa uuid; v_como text; v_motivo text; v_nova boolean := false;
  v_cands uuid[] := '{}';
  v_lead uuid; v_aluno uuid; v_comprador uuid; v_pa uuid; v_pc uuid; v_x uuid;
  v_ents text[] := '{}'; v_compat text[] := '{}';
  r record;
begin
  -- concorrência: o mesmo lead chegando 2× ao mesmo tempo não vira 2 pessoas
  perform pg_advisory_xact_lock(hashtext('pessoas.resolver:' || coalesce(v_email, v_fk, pessoas.norm_nome(p_nome), '')));

  -- 1. E-MAIL (cada fonte pelo seu índice; valor normalizado na variável)
  if v_email is not null then
    select pessoas.atual(i.pessoa_id) into v_lead from pessoas.identificadores i where i.tipo = 'email' and i.chave = v_email;
    select a.id into v_aluno from public.thb_alunos a
     where lower(btrim(a.email)) = v_email and a.email is not null and a.email <> '';
    select c.id into v_comprador from public.compradores c where lower(btrim((c.email)::text)) = v_email limit 1;

    v_pa := (select pessoas.atual(p.id) from pessoas.pessoas p where v_aluno is not null and p.aluno_id = v_aluno);
    v_pc := (select pessoas.atual(p.id) from pessoas.pessoas p where v_comprador is not null and p.comprador_id = v_comprador);
    v_pessoa := coalesce(v_pa, v_pc, v_lead);
    v_cands := array(select distinct x from unnest(array[v_pa, v_pc, v_lead]) x where x is not null and x <> v_pessoa);
    if cardinality(v_cands) > 0 then v_motivo := 'email_conflito'; end if;   -- duplicata antiga: humano decide

    if v_pessoa is null then
      if v_aluno is not null then v_pessoa := pessoas.pessoa_do_aluno(v_aluno);
      elsif v_comprador is not null then v_pessoa := pessoas.pessoa_do_comprador(v_comprador); end if;
    end if;

    if v_pessoa is not null and v_motivo is null then
      -- o lead que virou aluno/comprador: liga a referência que ainda não tem pessoa
      if v_aluno is not null and v_pa is null then
        select p.aluno_id into v_x from pessoas.pessoas p
         where p.id = any(pessoas.grupo(v_pessoa)) and p.aluno_id is not null limit 1;
        if v_x is null then
          update pessoas.pessoas set aluno_id = v_aluno, atualizado_em = now() where id = v_pessoa;
          insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.thb_alunos', v_aluno::text);
        elsif v_x <> v_aluno then
          v_cands := v_cands || pessoas.pessoa_do_aluno(v_aluno); v_motivo := 'email_conflito';
        end if;
      end if;
      if v_comprador is not null and v_pc is null and v_motivo is null then
        v_x := null;
        select p.comprador_id into v_x from pessoas.pessoas p
         where p.id = any(pessoas.grupo(v_pessoa)) and p.comprador_id is not null limit 1;
        if v_x is null then
          update pessoas.pessoas set comprador_id = v_comprador, atualizado_em = now() where id = v_pessoa;
          insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id) values (v_pessoa, 'vinculo', 'sistema', 'public.compradores', v_comprador::text);
        elsif v_x <> v_comprador then
          v_cands := v_cands || pessoas.pessoa_do_comprador(v_comprador); v_motivo := 'email_conflito';
        end if;
      end if;
    end if;
    if v_pessoa is not null then v_como := 'email'; end if;
  end if;

  -- 2. TELEFONE: só sem e-mail, só com exatamente 1 candidato e nome compatível
  if v_pessoa is null and v_email is null and v_fk is not null then
    for r in select * from pessoas.candidatos_telefone(v_fk) loop
      v_ents := v_ents || r.ent;
      if pessoas.nomes_compativeis(p_nome, r.nome_ent) then v_compat := v_compat || r.ent; end if;
    end loop;
    if cardinality(v_ents) = 1 and cardinality(v_compat) = 1 then
      v_pessoa := (pessoas.garantir(v_compat))[1];
      v_como := 'telefone';
    elsif cardinality(v_ents) > 0 then
      v_cands := pessoas.garantir(v_ents);
      v_motivo := case when cardinality(v_compat) = 0 then 'telefone_nome_diferente' else 'telefone_varios' end;
    end if;
  end if;

  -- 3. Ninguém casou: pessoa nova. Telefone de outra pessoa (com e-mail diferente) ou nome igual → revisão.
  if v_pessoa is null then
    if v_motivo is null and v_email is not null and v_fk is not null then
      select coalesce(array_agg(t.ent), '{}') into v_ents from pessoas.candidatos_telefone(v_fk) t;
      if cardinality(v_ents) > 0 then
        v_cands := pessoas.garantir(v_ents);
        v_motivo := 'telefone_email_diferente';
      end if;
    end if;
    if v_motivo is null then
      select coalesce(array_agg(t.ent), '{}'), min(t.motivo) into v_ents, v_motivo from pessoas.candidatos_nome(p_nome, p_cep) t;
      if cardinality(v_ents) > 0 then v_cands := pessoas.garantir(v_ents); else v_motivo := null; end if;
    end if;
    v_cands := array(select distinct s from unnest(v_cands) s where s is not null);
    insert into pessoas.pessoas (nome, situacao, teste, criado_por)
    values (case when length(btrim(coalesce(p_nome, ''))) >= 2 then left(btrim(p_nome), 160) end,
            case when cardinality(v_cands) > 0 then 'revisar' else 'ativa' end, coalesce(p_teste, false), p_por)
    returning id into v_pessoa;
    v_como := 'nova'; v_nova := true;
  end if;

  v_pessoa := pessoas.atual(v_pessoa);
  v_cands := array(select distinct s from unnest(v_cands) s where s is not null and pessoas.atual(s) <> v_pessoa);
  if cardinality(v_cands) > 0 then
    insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
    values (v_pessoa, v_motivo, v_cands, jsonb_build_object('casou_por', v_como));
  else
    v_motivo := null;
  end if;
  return jsonb_build_object('pessoa_id', v_pessoa, 'como', v_como, 'nova', v_nova, 'revisao', v_motivo);
end
$$;

-- guarda um identificador informado, a não ser que já seja o do aluno/comprador ligado (lá é a fonte)
create function pessoas.anexar(p_pessoa uuid, p_tipo text, p_valor text, p_chave text, p_origem text) returns void
language plpgsql set search_path = '' as $$
declare v_dono uuid; r record;
begin
  if p_chave is null then return; end if;
  select a.email a_email, controle.fone_key(coalesce(a.telefone_e164, a.telefone)) a_fk, a.nome a_nome, a.cep a_cep,
         c.email::text c_email, controle.fone_key((c.telefone)::text) c_fk
    into r
    from pessoas.pessoas p
    left join public.thb_alunos a on a.id = p.aluno_id
    left join public.compradores c on c.id = p.comprador_id
   where p.id = p_pessoa;
  if (p_tipo = 'email' and p_chave in (lower(btrim(r.a_email)), lower(btrim(r.c_email))))
     or (p_tipo = 'telefone' and p_chave in (r.a_fk, r.c_fk))
     or (p_tipo = 'nome_cep' and pessoas.chave_nome_cep(r.a_nome, r.a_cep) = p_chave) then
    return;   -- referência basta
  end if;
  if p_tipo = 'email' then
    select pessoa_id into v_dono from pessoas.identificadores where tipo = 'email' and chave = p_chave;
    if found then
      if pessoas.atual(v_dono) <> pessoas.atual(p_pessoa)
         and not exists (select 1 from pessoas.revisao where status = 'pendente' and pessoa_id = p_pessoa and v_dono = any(candidatos)) then
        insert into pessoas.revisao (pessoa_id, motivo, candidatos, detalhe)
        values (p_pessoa, 'email_conflito', array[v_dono], jsonb_build_object('casou_por', 'anexar'));
      end if;
      return;
    end if;
  end if;
  insert into pessoas.identificadores (pessoa_id, tipo, valor, chave, origem)
  values (p_pessoa, p_tipo, p_valor, p_chave, p_origem)
  on conflict do nothing;
end
$$;

-- Entrada única de pessoa (formulário, CRM, importação). p: nome, email, telefone, cep, aluno_id, projeto (sigla),
-- pagina_id ou dominio+caminho, campanha, utm_*, fbclid/gclid, visitante (mkt_web), evento (lead|mql|nao_mql|cadastro), teste.
create function pessoas.registrar(p jsonb, p_fonte text, p_por uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_tel text := pessoas.norm_telefone(p->>'telefone');
  v_email text := pessoas.norm_email(p->>'email');
  v_nome text := nullif(left(btrim(coalesce(p->>'nome', '')), 160), '');
  v_res jsonb; v_pessoa uuid;
  v_projeto bigint; v_pagina bigint; v_campanha text; v_trad jsonb; v_origem bigint; v_evento text;
  v_ref text; v_aluno uuid; v_tem_origem boolean;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'msg', 'Dados inválidos.'); end if;
  v_evento := coalesce(nullif(p->>'evento', ''), case when p_fonte = 'formulario' then 'lead' else 'cadastro' end);
  if v_evento not in ('lead', 'mql', 'nao_mql', 'cadastro') then
    return jsonb_build_object('ok', false, 'msg', 'Evento inválido (lead, mql, nao_mql ou cadastro).');
  end if;

  if nullif(p->>'aluno_id', '') is not null then
    begin v_aluno := (p->>'aluno_id')::uuid; exception when others then return jsonb_build_object('ok', false, 'msg', 'Aluno inválido.'); end;
    v_pessoa := pessoas.pessoa_do_aluno(v_aluno);
    if v_pessoa is null then return jsonb_build_object('ok', false, 'msg', 'Aluno não encontrado.'); end if;
    v_res := jsonb_build_object('pessoa_id', v_pessoa, 'como', 'aluno', 'nova', false, 'revisao', null);
  else
    if v_tel is null and v_email is null then
      return jsonb_build_object('ok', false, 'msg', 'Informe um e-mail ou um telefone (com DDD) válido.');
    end if;
    v_res := pessoas.resolver(v_nome, v_email, v_tel, p->>'cep', coalesce((p->>'teste')::boolean, false), p_por);
    v_pessoa := (v_res->>'pessoa_id')::uuid;

    update pessoas.pessoas set nome = v_nome, atualizado_em = now()
     where id = v_pessoa and nome is null and aluno_id is null and comprador_id is null and length(coalesce(v_nome, '')) >= 2;

    perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, p_fonte);
    perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), p_fonte);
    perform pessoas.anexar(v_pessoa, 'nome_cep', pessoas.chave_nome_cep(v_nome, p->>'cep'), pessoas.chave_nome_cep(v_nome, p->>'cep'), p_fonte);
  end if;

  -- origem: projeto pela sigla, ou pelo nome de campanha (GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA)
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

-- MESCLA = ALIAS: "de" passa a apontar para "para". Nada é apagado nem movido (identificadores, origens, eventos e
-- referências ficam na linha de origem; as leituras juntam o grupo). Desfazer: pessoas.desfazer_mescla.
create function pessoas.mesclar(p_de uuid, p_para uuid, p_por uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare d record; q record; v_alunos int;
begin
  select * into d from pessoas.pessoas where id = p_de for update;
  select * into q from pessoas.pessoas where id = p_para for update;
  if d.id is null or q.id is null or d.id = q.id then return jsonb_build_object('ok', false, 'msg', 'Pessoas inválidas.'); end if;
  if d.situacao = 'mesclada' or q.situacao = 'mesclada' then
    return jsonb_build_object('ok', false, 'msg', 'Uma das pessoas já está mesclada: use a pessoa atual.');
  end if;
  select count(distinct p.aluno_id) into v_alunos from pessoas.pessoas p
   where p.id = any(pessoas.grupo(p_de) || pessoas.grupo(p_para)) and p.aluno_id is not null;
  if v_alunos > 1 then
    return jsonb_build_object('ok', false, 'msg', 'As duas pessoas são alunos diferentes: não dá para juntar aqui (conferir na Central de Alunos).');
  end if;
  update pessoas.pessoas set situacao = 'mesclada', mesclada_em = p_para, atualizado_em = now() where id = p_de;
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, por)
  values (p_para, 'mescla', 'sistema', 'pessoas.pessoas', p_de::text, p_por),
         (p_de,   'mescla', 'sistema', 'pessoas.pessoas', p_para::text, p_por);
  return jsonb_build_object('ok', true, 'msg', 'Pessoas juntadas (alias; dá para desfazer).', 'pessoa_id', p_para);
end
$$;

create function pessoas.desfazer_mescla(p_pessoa uuid, p_por uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare d record;
begin
  select * into d from pessoas.pessoas where id = p_pessoa for update;
  if d.id is null or d.situacao <> 'mesclada' then
    return jsonb_build_object('ok', false, 'msg', 'Esta pessoa não está mesclada.');
  end if;
  update pessoas.pessoas set situacao = 'ativa', mesclada_em = null, atualizado_em = now() where id = p_pessoa;
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, por)
  values (p_pessoa,      'mescla_desfeita', 'sistema', 'pessoas.pessoas', d.mesclada_em::text, p_por),
         (d.mesclada_em, 'mescla_desfeita', 'sistema', 'pessoas.pessoas', p_pessoa::text, p_por);
  return jsonb_build_object('ok', true, 'msg', 'Mescla desfeita.', 'pessoa_id', p_pessoa);
end
$$;

-- ─── 8. Funções da tela: pessoas ─────────────────────────────────────────────────────────────────────────────────────
create function public.pessoas_meu_acesso() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('pode_ver', coalesce(pessoas.pode_ver(), false), 'pode_editar', coalesce(pessoas.pode_editar(), false),
                            'pode_ver_contato', coalesce(pessoas.pode_ver_contato(), false));
$$;

-- Busca por e-mail exato, telefone (fone_key) ou trecho de nome (≥ 3). Cada ramo por índice (union, nunca OR).
create function public.pessoas_buscar(p_termo text default null, p_projeto bigint default null, p_limite int default 30)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t text := nullif(btrim(coalesce(p_termo, '')), '');
  v_email text; v_fk text; v_like text;
  v_lim int := least(greatest(coalesce(p_limite, 30), 1), 100);
  v_contato boolean := coalesce(pessoas.pode_ver_contato(), false);
  v_alunos uuid[]; v_compr uuid[]; v_pess uuid[];
  v jsonb;
begin
  if not coalesce(pessoas.pode_ver(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  if (v_t is null or length(v_t) < 3) and p_projeto is null then return '[]'::jsonb; end if;
  v_email := pessoas.norm_email(v_t);
  v_fk := pessoas.chave_telefone(v_t);
  v_like := case when v_t is not null and length(v_t) >= 3 and v_email is null and v_fk is null
                 then '%' || replace(replace(replace(v_t, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;

  if v_t is not null then
    v_alunos := array(
      select a.id from public.thb_alunos a where v_email is not null and lower(btrim(a.email)) = v_email and a.email is not null and a.email <> ''
      union select a.id from public.thb_alunos a where v_fk is not null and controle.fone_key(coalesce(a.telefone_e164, a.telefone)) = v_fk and a.cancelado_em is null
      union (select a.id from public.thb_alunos a where v_like is not null and a.nome ilike v_like limit 200));
    v_compr := array(
      select c.id from public.compradores c where v_email is not null and lower(btrim((c.email)::text)) = v_email
      union (select c.id from public.compradores c where v_fk is not null and controle.fone_key((c.telefone)::text) = v_fk and c.telefone is not null limit 50));
    v_pess := array(
      select distinct pessoas.atual(x) from (
        select i.pessoa_id x from pessoas.identificadores i where v_email is not null and i.tipo = 'email' and i.chave = v_email
        union select i.pessoa_id from pessoas.identificadores i where v_fk is not null and i.tipo = 'telefone' and i.chave = v_fk
        union (select p.id from pessoas.pessoas p where v_like is not null and p.nome is not null and p.nome ilike v_like limit 200)
        union select p.id from pessoas.pessoas p where p.aluno_id = any(v_alunos)
        union select p.id from pessoas.pessoas p where p.comprador_id = any(v_compr)
      ) s);
  else
    v_pess := array(select distinct pessoas.atual(o.pessoa_id) from pessoas.origens o where o.projeto_id = p_projeto);
  end if;
  if p_projeto is not null and v_t is not null then
    v_pess := array(select x from unnest(v_pess) x
                     where exists (select 1 from pessoas.origens o where o.projeto_id = p_projeto and o.pessoa_id = any(pessoas.grupo(x))));
  end if;

  select coalesce(jsonb_agg(x order by x->>'tipo', x->>'nome'), '[]'::jsonb) into v from (
    (select jsonb_build_object(
             'tipo', 'pessoa', 'id', p.id, 'ref', p.ref, 'nome', d.d_nome, 'situacao', p.situacao, 'teste', p.teste,
             'email', case when v_contato then d.d_email else pessoas.mascara_email(d.d_email) end,
             'telefone', case when v_contato then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,
             'eh_aluno', d.d_aluno_id is not null, 'eh_comprador', d.d_comprador_id is not null, 'turma', d.d_turma,
             'projetos', (select coalesce(jsonb_agg(distinct pr.sigla), '[]'::jsonb) from pessoas.origens o
                            join mkt.projetos pr on pr.id = o.projeto_id where o.pessoa_id = any(pessoas.grupo(p.id))),
             'criado_em', p.criado_em) x
       from pessoas.pessoas p cross join lateral pessoas.dados(p.id) d
      where p.id = any(v_pess)
      order by p.criado_em desc limit v_lim)
    union all
    (select jsonb_build_object(
             'tipo', 'aluno', 'id', null, 'aluno_id', a.id, 'nome', a.nome, 'situacao', null, 'teste', false,
             'email', case when v_contato then pessoas.norm_email(a.email) else pessoas.mascara_email(pessoas.norm_email(a.email)) end,
             'telefone', case when v_contato then pessoas.norm_telefone(coalesce(a.telefone_e164, a.telefone))
                              else pessoas.mascara_fim(pessoas.norm_telefone(coalesce(a.telefone_e164, a.telefone))) end,
             'eh_aluno', true, 'eh_comprador', a.comprador_id is not null, 'turma', t.codigo, 'projetos', '[]'::jsonb,
             'criado_em', null)
       from public.thb_alunos a left join public.thb_turmas t on t.id = a.turma_id
      where p_projeto is null and a.id = any(v_alunos)
        and not exists (select 1 from pessoas.pessoas p where p.aluno_id = a.id)
      order by a.nome limit v_lim)
  ) s;

  perform pessoas.registrar_acesso('buscar', null,
    jsonb_build_object('tamanho_termo', length(coalesce(v_t, '')), 'projeto', p_projeto, 'resultados', jsonb_array_length(v)));
  return v;
end
$$;

create function public.pessoas_ficha(p_pessoa uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_grupo uuid[]; p record; d record;
  v_contato boolean := coalesce(pessoas.pode_ver_contato(), false);
  v_compradores uuid[];
  v jsonb;
begin
  if not coalesce(pessoas.pode_ver(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  v_id := pessoas.atual(p_pessoa);
  select * into p from pessoas.pessoas where id = v_id;
  if not found then return null; end if;
  v_grupo := pessoas.grupo(v_id);
  select * into d from pessoas.dados(v_id);
  v_compradores := array(
    select x.comprador_id from pessoas.pessoas x where x.id = any(v_grupo) and x.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas x join public.thb_alunos a on a.id = x.aluno_id
           where x.id = any(v_grupo) and a.comprador_id is not null);

  v := jsonb_build_object(
    'pessoa', jsonb_build_object(
      'id', p.id, 'ref', p.ref, 'nome', d.d_nome, 'situacao', p.situacao, 'teste', p.teste, 'criado_em', p.criado_em,
      'pedida', case when p_pessoa <> v_id then p_pessoa end,
      'aliases', (select coalesce(jsonb_agg(x.id), '[]'::jsonb) from unnest(v_grupo) x(id) where x.id <> v_id),
      'email', case when v_contato then d.d_email else pessoas.mascara_email(d.d_email) end,
      'telefone', case when v_contato then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end),
    'aluno', case when d.d_aluno_id is not null then jsonb_build_object(
      'id', d.d_aluno_id, 'nome', d.d_aluno_nome, 'turma', d.d_turma, 'cancelado', d.d_aluno_cancelado) end,
    'comprador_ids', to_jsonb(v_compradores),
    'identificadores', (select coalesce(jsonb_agg(jsonb_build_object(
        'tipo', i.tipo, 'origem', i.origem, 'criado_em', i.criado_em,
        'valor', case
                   when v_contato then i.valor
                   when i.tipo = 'email' then pessoas.mascara_email(i.valor)
                   when i.tipo = 'telefone' then pessoas.mascara_fim(i.valor)
                   else split_part(i.valor, '|', 1) || '|*****' || right(i.valor, 3)
                 end) order by i.id), '[]'::jsonb)
        from pessoas.identificadores i where i.pessoa_id = any(v_grupo)),
    'origens', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'quando', o.quando, 'projeto_id', o.projeto_id, 'projeto', pr.sigla, 'pagina_id', o.pagina_id,
        'pagina', case when pg.id is not null then pg.dominio || pg.caminho end, 'campanha', o.campanha,
        'campanha_padrao', o.campanha_padrao, 'utm_source', o.utm_source, 'utm_medium', o.utm_medium,
        'utm_campaign', o.utm_campaign, 'utm_content', o.utm_content, 'utm_term', o.utm_term,
        'de_anuncio', o.de_anuncio, 'fonte', o.fonte) order by o.quando desc), '[]'::jsonb)
        from pessoas.origens o left join mkt.projetos pr on pr.id = o.projeto_id left join mkt.paginas pg on pg.id = o.pagina_id
       where o.pessoa_id = any(v_grupo)),
    'eventos', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', e.id, 'tipo', e.tipo, 'quando', e.quando, 'projeto', pr.sigla, 'fonte', e.fonte, 'ref_tipo', e.ref_tipo,
        'ref_id', e.ref_id, 'detalhe', e.detalhe, 'por', pf.nome) order by e.quando desc, e.id desc), '[]'::jsonb)
        from pessoas.eventos e left join mkt.projetos pr on pr.id = e.projeto_id left join public.perfis pf on pf.id = e.por
       where e.pessoa_id = any(v_grupo)),
    -- compras: lidas na hora pela referência ao comprador; nada é copiado
    'compras', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'produto', c.produto_nome, 'status', c.status, 'data', c.data_compra, 'preco', c.preco)
        order by c.data_compra desc nulls last), '[]'::jsonb)
        from public.compras c where c.comprador_id = any(v_compradores)),
    'revisoes', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'motivo', r.motivo, 'criado_em', r.criado_em)), '[]'::jsonb)
        from pessoas.revisao r where r.status = 'pendente' and (r.pessoa_id = any(v_grupo) or r.candidatos && v_grupo)),
    'permissoes', jsonb_build_object('pode_editar', coalesce(pessoas.pode_editar(), false), 'pode_ver_contato', v_contato));

  perform pessoas.registrar_acesso('ver_ficha', v_id, '{}'::jsonb);
  return v;
end
$$;

create function public.pessoas_cadastrar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  if not coalesce(pessoas.pode_editar(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
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
  if not coalesce(pessoas.pode_ver(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'motivo', r.motivo, 'criado_em', r.criado_em, 'detalhe', r.detalhe,
      'pessoa', (select jsonb_build_object('id', p.id, 'nome', d.d_nome, 'situacao', p.situacao, 'eh_aluno', d.d_aluno_id is not null,
                                           'turma', d.d_turma, 'criado_em', p.criado_em)
                   from pessoas.pessoas p cross join lateral pessoas.dados(p.id) d where p.id = pessoas.atual(r.pessoa_id)),
      'candidatos', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nome', d.d_nome, 'eh_aluno', d.d_aluno_id is not null,
                                                                    'turma', d.d_turma, 'situacao', p.situacao)), '[]'::jsonb)
                       from (select distinct pessoas.atual(cid) cid from unnest(r.candidatos) cid) u
                       join pessoas.pessoas p on p.id = u.cid cross join lateral pessoas.dados(p.id) d
                      where u.cid <> pessoas.atual(r.pessoa_id)))
    order by r.criado_em), '[]'::jsonb)
    from pessoas.revisao r where r.status = 'pendente');
end
$$;

-- decisão humana: 'mesma' (alias da pessoa da revisão no candidato escolhido) ou 'diferente'
create function public.pessoas_revisao_decidir(p_revisao bigint, p_decisao text, p_alvo uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; v jsonb; v_de uuid; v_para uuid;
begin
  if not coalesce(pessoas.pode_editar(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  select * into r from pessoas.revisao where id = p_revisao for update;
  if not found or r.status <> 'pendente' then return jsonb_build_object('ok', false, 'msg', 'Revisão não encontrada ou já decidida.'); end if;
  if p_decisao = 'mesma' then
    if p_alvo is null or not exists (select 1 from unnest(r.candidatos) c where pessoas.atual(c) = pessoas.atual(p_alvo)) then
      return jsonb_build_object('ok', false, 'msg', 'Escolha uma das pessoas candidatas.');
    end if;
    v_de := pessoas.atual(r.pessoa_id); v_para := pessoas.atual(p_alvo);
    if v_de = v_para then
      v := jsonb_build_object('ok', true, 'msg', 'Já são a mesma pessoa.', 'pessoa_id', v_para);
    else
      v := pessoas.mesclar(v_de, v_para, (select auth.uid()));
      if not (v->>'ok')::boolean then return v; end if;
    end if;
  elsif p_decisao = 'diferente' then
    v := jsonb_build_object('ok', true, 'msg', 'Marcadas como pessoas diferentes.', 'pessoa_id', r.pessoa_id);
  else
    return jsonb_build_object('ok', false, 'msg', 'Decisão inválida (mesma ou diferente).');
  end if;
  update pessoas.revisao set status = p_decisao, decidido_por = (select auth.uid()), decidido_em = now() where id = p_revisao;
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

create function public.pessoas_mescla_desfazer(p_pessoa uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  if not coalesce(pessoas.pode_editar(), false) then raise exception 'acesso negado' using errcode = '42501'; end if;
  v := pessoas.desfazer_mescla(p_pessoa, (select auth.uid()));
  if (v->>'ok')::boolean then perform pessoas.registrar_acesso('desfazer_mescla', p_pessoa, '{}'::jsonb); end if;
  return v;
end
$$;

-- ─── 9. crm: fundação (backend-arquitetura.md §3.1, §3.2, §4.1) ──────────────────────────────────────────────────────
-- Log append-only. Imutável: nem o dono do banco altera sem desligar o trigger numa migration explícita.
create table crm.log (
  id          bigint generated always as identity primary key,
  em          timestamptz not null default clock_timestamp(),
  autor_id    uuid,                         -- null = sistema
  autor_tipo  text not null check (autor_tipo in ('pessoa','sistema','integracao','mcp')),
  canal       text not null default 'tela',
  acao        text not null check (acao in ('criou','editou','moveu_etapa','trocou_dono','marcou_perdido','marcou_ganho',
                 'arquivou','excluiu','concluiu','agendou','atribuiu','enviou','aprovou','reprovou','vinculou',
                 'desvinculou','importou','reembolsou','uniu','separou')),
  entidade    text not null check (entidade in ('negocio','contato','atividade','mensagem','nota','funil','etapa',
                 'campanha','agrupador','projeto','motivo','ficha','fila','produto','oferta','distribuicao','link',
                 'dashboard','painel','preferencias','vendedor','config')),
  entidade_id text not null,
  pessoa_id   uuid,                         -- pessoas.pessoas, sem FK: o log sobrevive a alias
  resumo      text not null,
  mudancas    jsonb not null default '[]' check (jsonb_typeof(mudancas) = 'array'),
  dados       jsonb not null default '{}' check (jsonb_typeof(dados) = 'object'),
  txid        bigint not null default txid_current()
);
alter table crm.log enable row level security;
create index log_em_idx     on crm.log (em desc);
create index log_ent_idx    on crm.log (entidade, entidade_id, em desc);
create index log_pessoa_idx on crm.log (pessoa_id, em desc) where pessoa_id is not null;
create index log_autor_idx  on crm.log (autor_id, em desc);
create index log_etapa_idx  on crm.log (em) where acao = 'moveu_etapa';

create function crm.tg_log_imutavel() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'crm.log é append-only (%).', tg_op using errcode = '42501';
end
$$;
create trigger log_sem_update before update or delete on crm.log for each row execute function crm.tg_log_imutavel();
create trigger log_sem_truncate before truncate on crm.log for each statement execute function crm.tg_log_imutavel();

-- Trigger genérico de log: AFTER INSERT/UPDATE/DELETE, for each row. TG_ARGV[0] = entidade, TG_ARGV[1] = coluna id.
-- No UPDATE: ligar com WHEN (old.* is distinct from new.*) e SEM "OF" (manual §7). Falha no log ABORTA o write.
-- Autor: auth.uid() ou set_config('crm.autor'); canal: set_config('crm.canal'); resumo: set_config('crm.resumo') (lido e limpo).
create function crm.tg_log() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_ent    text := tg_argv[0];
  v_col_id text := coalesce(tg_argv[1], 'id');
  v_old    jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new    jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row    jsonb;
  v_ign    text[] := array['atualizado_em', 'etapa_desde', 'ultima_interacao_em'];
  v_mud    jsonb := '[]';
  v_acao   text;
  v_autor  uuid;
  v_canal  text;
  v_resumo text;
  k        text;
begin
  v_row := coalesce(v_new, v_old);
  v_ign := v_ign || coalesce((select array_agg(a.attname::text) from pg_catalog.pg_attribute a
                               where a.attrelid = tg_relid and a.attgenerated <> ''), '{}');
  if tg_op = 'UPDATE' then
    for k in select jsonb_object_keys(v_new) loop
      continue when k = any(v_ign);
      if (v_new -> k) is distinct from (v_old -> k) then
        v_mud := v_mud || jsonb_build_array(jsonb_build_object('campo', k, 'de', v_old -> k, 'para', v_new -> k));
      end if;
    end loop;
    if jsonb_array_length(v_mud) = 0 then return null; end if;   -- só coluna ignorada mudou
  end if;
  v_acao := case
    when tg_op = 'INSERT' then 'criou'
    when tg_op = 'DELETE' then 'excluiu'
    when (v_new ->> 'status') is distinct from (v_old ->> 'status') and v_new ->> 'status' = 'perdido' then 'marcou_perdido'
    when (v_new ->> 'status') is distinct from (v_old ->> 'status') and v_new ->> 'status' = 'ganho' then 'marcou_ganho'
    when v_new ? 'etapa_id' and (v_new -> 'etapa_id') is distinct from (v_old -> 'etapa_id') then 'moveu_etapa'
    when v_new ? 'dono_id' and (v_new -> 'dono_id') is distinct from (v_old -> 'dono_id') then 'trocou_dono'
    when v_new ? 'arquivado_em' and v_old ->> 'arquivado_em' is null and v_new ->> 'arquivado_em' is not null then 'arquivou'
    when v_new ? 'concluida_em' and v_old ->> 'concluida_em' is null and v_new ->> 'concluida_em' is not null then 'concluiu'
    else 'editou' end;
  v_autor  := coalesce(auth.uid(), nullif(current_setting('crm.autor', true), '')::uuid);
  v_canal  := coalesce(nullif(current_setting('crm.canal', true), ''), case when auth.uid() is null then 'sistema' else 'tela' end);
  v_resumo := nullif(current_setting('crm.resumo', true), '');
  if v_resumo is not null then perform set_config('crm.resumo', '', true); end if;
  insert into crm.log (autor_id, autor_tipo, canal, acao, entidade, entidade_id, pessoa_id, resumo, mudancas, dados)
  values (v_autor,
          case when v_canal = 'mcp' then 'mcp'
               when v_autor is not null then 'pessoa'
               when v_canal in ('hotmart', 'whatsapp', 'activecampaign', 'sendflow', 'respondi', 'clint_import') then 'integracao'
               else 'sistema' end,
          v_canal, v_acao, v_ent, coalesce(v_row ->> v_col_id, '?'),
          case when v_row ? 'pessoa_id' then nullif(v_row ->> 'pessoa_id', '')::uuid end,
          coalesce(v_resumo, initcap(v_acao) || ' ' || v_ent || ' ' || coalesce(v_row ->> v_col_id, '?')),
          v_mud,
          case when v_acao = 'moveu_etapa' then jsonb_build_object('etapa_de', v_old -> 'etapa_id', 'etapa_para', v_new -> 'etapa_id')
               else '{}'::jsonb end);
  return null;
end
$$;

-- Kill-switches e parâmetros (1 linha). escrita_ligada nasce FALSE: só liga na F2, quando houver RPC de escrita.
create table crm.config (
  id                       boolean primary key default true check (id),
  escrita_ligada           boolean not null default false,
  hotmart_ligado           boolean not null default false,
  whatsapp_ligado          boolean not null default false,
  activecampaign_ligado    boolean not null default false,
  sendflow_ligado          boolean not null default false,
  respondi_ligado          boolean not null default false,
  clint_import_ligado      boolean not null default false,
  mcp_ligado               boolean not null default false,
  notificacao_cron_ligado  boolean not null default false,
  horario_contato          text,
  limite_negocios_abertos  int check (limite_negocios_abertos > 0),
  ciclo_distribuicao_desde timestamptz not null default date_trunc('month', now())
);
alter table crm.config enable row level security;
create trigger config_log_ins_del after insert or delete on crm.config for each row execute function crm.tg_log('config', 'id');
create trigger config_log_upd after update on crm.config for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('config', 'id');

-- Equipe comercial: atributos do comercial sobre public.perfis. Papel NÃO mora aqui (vem de perfis). Nenhum cadastrado.
create table crm.vendedor (
  perfil_id   uuid primary key references public.perfis(id) on delete restrict,
  sigla       text not null unique check (sigla ~ '^[a-z0-9]{2,6}$'),
  ativo       boolean not null default true,       -- inativar, nunca apagar
  dispara_api boolean not null default false,
  criado_em   timestamptz not null default now()
);
alter table crm.vendedor enable row level security;
create trigger vendedor_log_ins_del after insert or delete on crm.vendedor for each row execute function crm.tg_log('vendedor', 'perfil_id');
create trigger vendedor_log_upd after update on crm.vendedor for each row when (old.* is distinct from new.*)
  execute function crm.tg_log('vendedor', 'perfil_id');

select set_config('crm.canal', 'migracao', true);
insert into crm.config (id) values (true);
select set_config('crm.canal', '', true);

-- Papéis (D5: dev/admin = gestor; D6: vendedor não vê leads de colegas — aplicado nas policies da F1)
create function crm.eh_gestor() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.status = 'ativo'
       and (p.cargo in ('dev', 'admin') or (p.cargo = 'gestor' and 'comercial' = any(coalesce(p.areas, '{}'))))
      from public.perfis p where p.id = (select auth.uid())
  ), false);
$$;

create function crm.eh_vendedor() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.status = 'ativo' and v.ativo
       and 'comercial' = any(coalesce(p.areas, '{}'))
       and 'comercial.vender' = any(coalesce(p.funcoes, '{}'))
      from public.perfis p join crm.vendedor v on v.perfil_id = p.id
     where p.id = (select auth.uid())
  ), false);
$$;

create function crm.eh_comercial() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false);
$$;

-- ─── 10. Grants e conferência ────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace in ('pessoas'::regnamespace, 'crm'::regnamespace) loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  grant execute on function crm.eh_gestor(), crm.eh_vendedor(), crm.eh_comercial() to authenticated;
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname like 'pessoas\_%' loop
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
revoke all on all sequences in schema pessoas from public, anon, authenticated;
revoke all on all sequences in schema crm from public, anon, authenticated;

do $confere$
declare v_aberto text;
begin
  -- nenhuma função nova executável por anon (inclui public.pessoas_*)
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where (p.pronamespace in ('pessoas'::regnamespace, 'crm'::regnamespace)
          or (p.pronamespace = 'public'::regnamespace and (p.proname like 'pessoas\_%' or p.proname like 'crm\_%')))
     and has_function_privilege('anon', p.oid, 'execute');
  if v_aberto is not null then raise exception '20261005r: executável por anon: %', v_aberto; end if;
  if exists (select 1 from information_schema.role_table_grants
              where table_schema in ('pessoas', 'crm') and grantee in ('anon', 'authenticated', 'PUBLIC')) then
    raise exception '20261005r: tabela de pessoas/crm com grant para anon/authenticated';
  end if;
  if has_schema_privilege('anon', 'pessoas', 'usage') or has_schema_privilege('authenticated', 'pessoas', 'usage')
     or has_schema_privilege('anon', 'crm', 'usage') then
    raise exception '20261005r: USAGE indevido nos schemas';
  end if;
  if has_function_privilege('authenticated', 'public.pessoas_registrar_lead(jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.pessoas_registrar_lead(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.pessoas_ficha(uuid)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.registrar(jsonb,text,uuid)', 'execute')
     or has_function_privilege('authenticated', 'crm.tg_log()', 'execute')
     or not has_function_privilege('authenticated', 'crm.eh_gestor()', 'execute') then
    raise exception '20261005r: grants das funções fora do esperado';
  end if;
  if (select count(*) from crm.config) <> 1 or (select count(*) from crm.vendedor) <> 0 then
    raise exception '20261005r: crm.config deveria ter 1 linha e crm.vendedor 0';
  end if;
end
$confere$;

-- ═══ REVERSÃO (numa transação; F0 sem dado real = drop. Com dado: exportar pessoas.* e crm.log antes) ═══════════════
-- begin;
-- set local lock_timeout = '3s';
-- do $$ declare f regprocedure; begin
--   for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
--             and (p.proname like 'pessoas\_%' or p.proname like 'crm\_%')
--   loop execute format('drop function %s', f); end loop; end $$;
-- drop schema crm cascade;        -- crm.log tem trigger contra TRUNCATE, não contra DROP: drop da fase F0 é permitido
-- drop schema pessoas cascade;
-- drop index concurrently if exists public.ix_compradores_fone_key;  -- fora de transação, à parte
-- update mkt_web.visitantes set lead_ref = null where lead_ref like 'pe\_%';   -- só se a 20261005n estiver aplicada
-- commit;

-- ═══ PROVAS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
do $t$
declare
  v_admin uuid; v_visu uuid;
  v_aluno uuid; v_compr uuid;
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; r6 jsonb; r7 jsonb; r8 jsonb; r9 jsonb; r10 jsonb;
  p_lia uuid; p_ana uuid; p_z1 uuid; p_z2 uuid;
  v_rev bigint; v jsonb; v_txt text; v_n int; v_n2 int; v_b boolean; v_b2 boolean; v_b3 boolean; v_err text;
begin
  select id into v_admin from public.perfis where cargo = 'admin' and status = 'ativo' order by criado_em limit 1;
  select id into v_visu  from public.perfis where cargo = 'visualizador' order by criado_em limit 1;

  -- 1. estrutura
  perform pg_temp.ok('1.schemas', to_regnamespace('pessoas') is not null and to_regnamespace('crm') is not null, 'pessoas e crm criados');
  perform pg_temp.ok('1.config', (select count(*) from pessoas.config) = 3, 'pessoas.config com 3 chaves vazias');
  perform pg_temp.ok('1.crm_config', (select count(*) from crm.config) = 1 and not (select escrita_ligada from crm.config),
                     'crm.config 1 linha, escrita_ligada=false');
  perform pg_temp.ok('1.vendedor', (select count(*) from crm.vendedor) = 0, 'nenhum vendedor cadastrado');
  perform pg_temp.ok('1.log_inicial', (select count(*) from crm.log where entidade = 'config' and acao = 'criou' and canal = 'migracao') = 1,
                     'tg_log registrou a criação da config (canal migracao)');
  perform pg_temp.ok('1.indice', to_regclass('public.ix_compradores_fone_key') is not null, 'ix_compradores_fone_key criado');

  -- dados fictícios
  insert into public.thb_alunos (nome, email, telefone, cep)
  values ('Ana Ensaio Silva', 'ana.ensaio@exemplo.com.br', '5599932100001', '01001000') returning id into v_aluno;
  insert into public.compradores (nome, email, telefone)
  values ('Carlos Ensaio', 'carlos.ensaio@exemplo.com.br', '99932100003') returning id into v_compr;

  -- 2. e-mail com espaço/maiúscula
  r1 := pessoas.registrar('{"nome":"Lia Ensaio","email":"  Lia.Ensaio@Exemplo.COM.br "}', 'formulario', null);
  r2 := pessoas.registrar('{"email":"lia.ensaio@exemplo.com.br"}', 'formulario', null);
  p_lia := (r1->>'pessoa_id')::uuid;
  perform pg_temp.ok('2.nova', (r1->>'ok')::boolean and (r1->>'nova')::boolean and r1->>'como' = 'nova', 'primeiro contato = pessoa nova');
  perform pg_temp.ok('2.mesma', (r2->>'pessoa_id')::uuid = p_lia and not (r2->>'nova')::boolean and r2->>'como' = 'email',
                     'e-mail com espaço/maiúscula resolve para a mesma pessoa');
  perform pg_temp.ok('2.um_identificador', (select count(*) from pessoas.identificadores where pessoa_id = p_lia and tipo = 'email') = 1,
                     'e-mail guardado 1 vez, normalizado');

  -- 3. aluno existente vira referência
  r3 := pessoas.registrar('{"nome":"Ana","email":"ANA.ENSAIO@exemplo.com.br"}', 'formulario', null);
  p_ana := (r3->>'pessoa_id')::uuid;
  perform pg_temp.ok('3.referencia', (select aluno_id from pessoas.pessoas where id = p_ana) = v_aluno and r3->>'como' = 'email',
                     'pessoa aponta para o aluno (aluno_id)');
  perform pg_temp.ok('3.sem_copia', (select nome from pessoas.pessoas where id = p_ana) is null
                     and not exists (select 1 from pessoas.identificadores where pessoa_id = p_ana and tipo = 'email'),
                     'nome e e-mail do aluno NÃO copiados (lidos de thb_alunos)');
  perform pg_temp.ok('3.dados', (select d_nome = 'Ana Ensaio Silva' from pessoas.dados(p_ana)), 'ficha lê o nome do aluno na hora');

  -- 4. telefone igual + e-mail diferente → revisão, não funde
  r4 := pessoas.registrar('{"nome":"Ana Ensaio Silva","email":"outra.ensaio@exemplo.com.br","telefone":"(99) 93210-0001"}', 'formulario', null);
  perform pg_temp.ok('4.nao_funde', (r4->>'nova')::boolean and (r4->>'pessoa_id')::uuid <> p_ana
                     and (select situacao from pessoas.pessoas where id = p_ana) = 'ativa',
                     'pessoa nova; a do aluno segue intacta');
  perform pg_temp.ok('4.revisao', r4->>'revisao' = 'telefone_email_diferente'
                     and exists (select 1 from pessoas.revisao where pessoa_id = (r4->>'pessoa_id')::uuid and p_ana = any(candidatos)),
                     'revisão telefone_email_diferente com a pessoa do aluno como candidata');

  -- 5. sem e-mail + telefone
  r5 := pessoas.registrar('{"nome":"Carlos Souza","telefone":"+55 99 93210-0003"}', 'formulario', null);
  perform pg_temp.ok('5.casa_telefone', r5->>'como' = 'telefone' and r5->>'revisao' is null
                     and (select comprador_id from pessoas.pessoas where id = (r5->>'pessoa_id')::uuid) = v_compr,
                     'sem e-mail, 1 candidato (comprador) com nome compatível: casa por referência');
  r6 := pessoas.registrar('{"nome":"Pedro Outro","telefone":"99 932100003"}', 'formulario', null);
  perform pg_temp.ok('5.nome_diferente', (r6->>'nova')::boolean and r6->>'revisao' = 'telefone_nome_diferente',
                     'mesmo telefone, nome diferente: pessoa nova + revisão');
  r7 := pessoas.registrar('{"nome":"Ana","telefone":"99932100001"}', 'formulario', null);
  perform pg_temp.ok('5.varios', (r7->>'nova')::boolean and r7->>'revisao' = 'telefone_varios',
                     'telefone com 2 candidatos (aluno + pessoa do passo 4): ninguém escolhe sozinho');

  -- 6. só nome
  r8 := pessoas.registrar('{"nome":"Zuleica Ensaiadora Teste","email":"z1.ensaio@exemplo.com.br"}', 'formulario', null);
  r9 := pessoas.registrar('{"nome":"Zuleica Ensaiadora Teste","email":"z2.ensaio@exemplo.com.br"}', 'formulario', null);
  p_z1 := (r8->>'pessoa_id')::uuid; p_z2 := (r9->>'pessoa_id')::uuid;
  perform pg_temp.ok('6.so_nome', (r9->>'nova')::boolean and p_z2 <> p_z1 and r9->>'revisao' = 'so_nome'
                     and (select situacao from pessoas.pessoas where id = p_z2) = 'revisar',
                     'nome igual NÃO casa: pessoa nova em revisão (so_nome)');

  -- 7. mescla = alias, decidida por um admin real (role authenticated + JWT)
  select id into v_rev from pessoas.revisao where pessoa_id = p_z2 and status = 'pendente';
  select count(*) into v_n from pessoas.identificadores where pessoa_id = p_z2;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v := public.pessoas_revisao_decidir(v_rev, 'mesma', p_z1);
  reset role;
  perform pg_temp.ok('7.mescla_ok', (v->>'ok')::boolean, coalesce(v->>'msg', ''));
  perform pg_temp.ok('7.alias', (select situacao = 'mesclada' and mesclada_em = p_z1 from pessoas.pessoas where id = p_z2)
                     and pessoas.atual(p_z2) = p_z1, 'situacao=mesclada, mesclada_em = pessoa que fica, atual() resolve');
  perform pg_temp.ok('7.nada_movido', (select count(*) from pessoas.identificadores where pessoa_id = p_z2) = v_n and v_n > 0
                     and exists (select 1 from pessoas.eventos where pessoa_id = p_z2 and tipo = 'lead'),
                     'identificadores e eventos continuam na linha do alias (nada apagado/movido)');
  r10 := pessoas.registrar('{"email":"Z2.ENSAIO@exemplo.com.br"}', 'formulario', null);
  perform pg_temp.ok('7.resolve_atual', (r10->>'pessoa_id')::uuid = p_z1, 'e-mail do alias resolve para a pessoa que ficou');
  set local role authenticated;
  v := public.pessoas_ficha(p_z2);
  reset role;
  perform pg_temp.ok('7.ficha_grupo', (v->'pessoa'->>'id')::uuid = p_z1 and jsonb_array_length(v->'identificadores') >= 2
                     and v->'pessoa'->'aliases' ? p_z2::text, 'ficha pedida pelo alias mostra a atual com o grupo inteiro');
  set local role authenticated;
  v := public.pessoas_mescla_desfazer(p_z2);
  reset role;
  perform pg_temp.ok('7.desfazer', (v->>'ok')::boolean and pessoas.atual(p_z2) = p_z2
                     and (select situacao = 'ativa' and mesclada_em is null from pessoas.pessoas where id = p_z2),
                     'desfazer = limpar: cada uma volta a ser ela mesma');

  -- 8. busca e ficha sem documento
  set local role authenticated;
  v := public.pessoas_buscar('Lia.Ensaio@exemplo.com.br');
  v_txt := public.pessoas_ficha(p_ana)::text || public.pessoas_buscar('99932100001')::text || public.pessoas_meu_acesso()::text;
  reset role;
  perform pg_temp.ok('8.busca_email', jsonb_array_length(v) = 1 and (v->0->>'id')::uuid = p_lia, 'busca por e-mail acha 1 pessoa');
  perform pg_temp.ok('8.sem_documento', v_txt !~* '(documento|cpf)', 'nenhuma saída de ficha/busca/meu_acesso traz documento/CPF');
  perform pg_temp.ok('8.acessos', (select count(*) from pessoas.acessos where por = v_admin) >= 4, 'acessos registrados (LGPD)');

  -- 9. crm.log append-only
  v_n := 0;
  begin update crm.log set resumo = 'x'; exception when insufficient_privilege then v_n := v_n + 1; end;
  begin delete from crm.log; exception when insufficient_privilege then v_n := v_n + 1; end;
  begin truncate crm.log; exception when insufficient_privilege then v_n := v_n + 1; end;
  perform pg_temp.ok('9.log_imutavel', v_n = 3, v_n || '/3 recusas (update, delete, truncate) mesmo como postgres');

  -- 10. tg_log
  select count(*) into v_n from crm.log;
  perform set_config('crm.resumo', 'Ensaio: ligou hotmart', true);
  update crm.config set hotmart_ligado = true;
  perform pg_temp.ok('10.config_diff', (select acao = 'editou' and resumo = 'Ensaio: ligou hotmart'
                                               and mudancas @> '[{"campo":"hotmart_ligado","de":false,"para":true}]'
                                          from crm.log order by id desc limit 1)
                     and current_setting('crm.resumo', true) = '', 'diff campo a campo + resumo lido e limpo');
  update crm.config set hotmart_ligado = true;
  perform pg_temp.ok('10.sem_noop', (select count(*) from crm.log) = v_n + 1, 'UPDATE sem mudança não grava log');
  insert into crm.vendedor (perfil_id, sigla) values (v_admin, 'ens');
  update crm.vendedor set ativo = false where perfil_id = v_admin;
  perform pg_temp.ok('10.vendedor', (select count(*) from crm.log where entidade = 'vendedor' and entidade_id = v_admin::text
                                       and ((acao = 'criou' and mudancas = '[]') or (acao = 'editou' and mudancas @> '[{"campo":"ativo"}]'))) = 2,
                     'vendedor: criou + editou(ativo) com entidade_id = perfil');
  delete from crm.vendedor where perfil_id = v_admin;
  perform pg_temp.ok('10.excluiu', exists (select 1 from crm.log where entidade = 'vendedor' and acao = 'excluiu'), 'DELETE vira "excluiu"');

  -- 11. helpers com role authenticated + JWT real
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_b := crm.eh_gestor(); v_b2 := crm.eh_comercial(); v_b3 := crm.eh_vendedor();
  reset role;
  perform pg_temp.ok('11.admin', v_b and v_b2 and not v_b3, 'admin real: gestor sim, comercial sim, vendedor não (D5)');
  perform set_config('request.jwt.claims', json_build_object('sub', v_visu, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_b := crm.eh_gestor(); v_b2 := crm.eh_comercial(); v_b3 := crm.eh_vendedor();
  reset role;
  perform pg_temp.ok('11.visualizador', v_visu is not null and not v_b and not v_b2 and not v_b3, 'visualizador real: nada');
  perform set_config('request.jwt.claims', '', true);
  set local role authenticated;
  v_b := crm.eh_gestor(); v_b2 := crm.eh_comercial();
  reset role;
  perform pg_temp.ok('11.sem_jwt', v_b is false and v_b2 is false, 'sem JWT: false (coalesce, não NULL)');

  -- 12. permissões
  select count(*), count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) into v_n, v_n2
    from pg_proc p
   where p.pronamespace in ('pessoas'::regnamespace, 'crm'::regnamespace)
      or (p.pronamespace = 'public'::regnamespace and p.proname like 'pessoas\_%');
  perform pg_temp.ok('12.anon', v_n2 = 0 and v_n > 30, v_n || ' funções novas, ' || v_n2 || ' executáveis por anon');
  perform pg_temp.ok('12.registrar_lead', not has_function_privilege('authenticated', 'public.pessoas_registrar_lead(jsonb)', 'execute')
                     and has_function_privilege('service_role', 'public.pessoas_registrar_lead(jsonb)', 'execute'),
                     'registrar_lead só service_role');
  perform pg_temp.ok('12.tabelas', not has_table_privilege('authenticated', 'crm.log', 'select')
                     and not has_table_privilege('authenticated', 'crm.log', 'insert')
                     and not has_table_privilege('anon', 'crm.config', 'select')
                     and not has_schema_privilege('authenticated', 'pessoas', 'usage'),
                     'authenticated/anon sem tabela e sem schema pessoas');
  perform set_config('request.jwt.claims', json_build_object('sub', v_visu, 'role', 'authenticated')::text, true);
  v_n := 0; v_err := null;
  set local role authenticated;
  begin perform public.pessoas_ficha(p_ana); v_err := concat_ws(',', v_err, 'ficha'); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin perform public.pessoas_buscar('ana.ensaio@exemplo.com.br'); v_err := concat_ws(',', v_err, 'buscar'); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin perform public.pessoas_cadastrar('{"email":"x.ensaio@exemplo.com.br"}'); v_err := concat_ws(',', v_err, 'cadastrar'); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin perform public.pessoas_revisao_listar(); v_err := concat_ws(',', v_err, 'listar'); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin perform 1 from crm.log limit 1; v_err := concat_ws(',', v_err, 'select crm.log'); exception when insufficient_privilege then v_n := v_n + 1; end;
  reset role;
  perform pg_temp.ok('12.visualizador', v_n = 5, v_n || '/5 recusas 42501' || coalesce(' / PASSOU: ' || v_err, ''));
  perform set_config('request.jwt.claims', '', true);
  v_n := 0;
  set local role anon;
  begin perform public.pessoas_ficha(p_ana); exception when insufficient_privilege then v_n := v_n + 1; end;
  begin perform crm.eh_gestor(); exception when insufficient_privilege then v_n := v_n + 1; end;
  reset role;
  perform pg_temp.ok('12.anon_chama', v_n = 2, v_n || '/2 recusas ao chamar como anon');
end
$t$;

select linha from pg_temp._z_out order by n;
rollback;
