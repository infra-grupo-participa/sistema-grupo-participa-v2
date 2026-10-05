-- 20261005m: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql).
--   Todo resultado vai para a tabela temporária _z_out; o penúltimo comando mostra tudo.
--   Se o cliente só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia, e rode
--   o "rollback;" em seguida. NÃO deixe a transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261005m_mkt_base_compartilhada.sql; se a
-- migration mudar, gerar de novo). Depois dele, os testes chamam as funções como a tela chamaria (JWT simulado, role
-- authenticated): como o Victor (admin), como um uid qualquer sem perfil (não-admin) e como anon. Projeto e página de
-- TESTE usam a sigla ZZENSAIO99 e o domínio exemplo.invalid, e somem no rollback.
--
-- Esperados (conferir no _z_out):
--   1.schemas              = mkt,mkt_web
--   1.seed                 = projetos=4 paginas=4 gestores=3 objetivos=5
--   1.mkt_web_vazio        = 0
--   2.projetos             = BF26 etq=black-friday-2026-10 sub=interno pag=0 ; HT33 etq=null sub=interno pag=0 ;
--                            PB26 etq=seminario-conjunto-2026-11 sub=interno pag=4 ; SEMSET26 etq=sem-set-2026 sub=null pag=0
--   2.paginas_pb           = ak1 …/ak1/ captura ak1 ; - …/obrigado/ obrigado ak1 ; - …/pesquisa/ pesquisa recuperacao ;
--                            - …/quase-la/ pesquisa bl2   (domínio patrimoniobrasil.com.br)
--   2.sigla_invalida       = ok false "Sigla inválida…"      2.sigla_so_letras = ok false "Sigla inválida…"
--   2.criar                = ok true "Projeto ZZENSAIO99 criado." (minúsculas viram maiúsculas)
--   2.duplicata_sigla      = ok false "Já existe projeto com a sigla PB26."
--   2.duplicata_etiqueta   = ok false "Já existe projeto com esta etiqueta do ClickUp."
--   2.etiqueta_invalida    = ok false "Etiqueta do ClickUp inválida…"
--   2.datas_invertidas     = ok false "O fim não pode ser antes do início."
--   2.editar               = ok true "Projeto ZZENSAIO99 salvo."
--   3.codigo_invalido      = ok false "Código fora do padrão da casa…"
--   3.criar_url            = ok true "Página /zz9-b/ criada."     3.pagina_gravada = zz9-b exemplo.invalid/zz9-b/ nome=ZZ9-B
--   3.duplicata_codigo     = ok false "…já tem uma página com o código ak1."
--   3.duplicata_caminho    = ok false "…já tem a página patrimoniobrasil.com.br/obrigado/."
--   3.funcao_invalida      = ok false "Função inválida."
--   4.traduzir (11 linhas, nesta ordem):
--     RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1   padrao=true  avisos=[]  pagina_id preenchido
--     cf|ht33|vendas|aula ao vivo                     padrao=true  avisos=["minusculas","espacos_extras"]
--     EF  |  BF26 | DISTRIBUICAO |  Oferta   final   padrao=true  avisos=["sem_acento","minusculas","espacos_extras"]
--                                                     canon=EF | BF26 | DISTRIBUIÇÃO | OFERTA FINAL
--     XX | PB26 | LEADS | TESTE                       padrao=false erros=["gestor_desconhecido"]
--     RS | P26X | LEADS | TESTE                       padrao=false erros=["sigla_invalida"]
--     RS | ZZ99 | LEADS | TESTE                       padrao=false erros=["projeto_nao_cadastrado"]
--     RS | PB26 | TOPO | TESTE                        padrao=false erros=["objetivo_desconhecido"]
--     RS | PB26 | LEADS                               padrao=false erros=["numero_de_campos"]
--     RS | PB26 | LEADS | TESTE | A1                  padrao=false erros=["pagina_invalida"]
--     RS | PB26 | LEADS | TESTE | BL2                 padrao=true  avisos=["pagina_nao_cadastrada"]
--     RS | ZZENSAIO99 | LEADS | TESTE                 padrao=true  avisos=["projeto_inativo"]
--   4.listas               = gestores CF, EF, RS; objetivos DISTRIBUIÇÃO, LEADS, LEMBRETE, REMARKETING, VENDAS;
--                            projetos BF26, HT33, PB26, SEMSET26, ZZENSAIO99
--   5.check_sigla          = 23514 ok      5.check_codigo = 23514 ok   (a tabela recusa formato errado mesmo sem a RPC)
--   6.grants               = tabela=false nas 8 linhas      6.schema = mkt=false mkt_web=false para anon e authenticated
--   6.grants_funcoes       = anon=false em todas; auth=true só nas 6 public.mkt_*; definer=true nas 6 e em mkt.pode_ver
--   7.authenticated / 7.anon = "42501 ok" nas 6 funções (uid sem perfil = não-admin)
--   7.*_select_direto      = 42501 ok
--   Qualquer ERRO no meio = a migration não serve como está: não aplicar.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;

-- ═══ CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regnamespace('mkt') is not null or to_regnamespace('mkt_web') is not null then
    raise exception '20261005m: schema mkt ou mkt_web já existe (migration já aplicada?)';
  end if;
  if to_regprocedure('public.gp_is_admin()') is null then
    raise exception '20261005m: public.gp_is_admin() ausente';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_%') then
    raise exception '20261005m: já existem funções public.mkt_*';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'perfis' and column_name = 'id') then
    raise exception '20261005m: public.perfis.id ausente';
  end if;
end
$guarda$;

-- ─── 1. Schemas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create schema mkt;
revoke all on schema mkt from public, anon, authenticated;
comment on schema mkt is
  'Marketing, base compartilhada: projetos (projeto = edição, sigla do nome de campanha) e páginas. Lida por Web, '
  'Tráfego e Mensageria; o mesmo dado não se duplica. Fechado: acesso só pelas funções public.mkt_*. 20261005m.';

create schema mkt_web;
revoke all on schema mkt_web from public, anon, authenticated;
comment on schema mkt_web is
  'Marketing > Web (o Radar do Luiz dentro da central). VAZIO na 20261005m. Fase 2 (coleta): visitantes, sessoes, '
  'visualizacoes, eventos_funil, erros, cliques, captacao, paginas_mapa, velocidade_lab, publicacoes e as de '
  'operação (pacotes, recusas, falhas, espaco_diario, tempos_api), mais funis (o contrato do funil: etapas, eventos '
  'de lead, régua de MQL). Tudo aponta para mkt.projetos e mkt.paginas; sem dado pessoal (o lead mora na base de '
  'pessoas). Gravações (replay) e CRM do Luiz ficam para depois. RLS desde a criação; acesso por função.';

-- ─── 2. Funções auxiliares (internas, sem grant para ninguém) ────────────────────────────────────────────────────────
-- Maiúsculas que não dependem do locale do banco (upper() em locale C não mexe em letra acentuada).
create function mkt.maiusculas(p text) returns text
language sql immutable set search_path = '' as $$
  select translate(upper(p), 'áàâãäéèêëíìîïóòôõöúùûüç', 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ');
$$;

-- Chave de comparação sem acento (DISTRIBUIÇÃO = DISTRIBUICAO).
create function mkt.sem_acento(p text) returns text
language sql immutable set search_path = '' as $$
  select translate(mkt.maiusculas(p), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC');
$$;

-- Quem vê/gere a base do Marketing. HOJE: só admin e dev (regra do Marketing, 05/10/2026), qualquer área.
-- DEPOIS (área mkt_web para o Luiz e o Iromar): acrescentar aqui, para p_area = 'mkt_web', gestor/operador ativo
-- com 'mkt_web' = any(perfis.areas), e negar o visualizador geral. NÃO liberado nesta migration.
create function mkt.pode_ver(p_area text default null) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false);
$$;

-- ─── 3. Tabelas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create table mkt.projetos (
  id               bigint generated always as identity primary key,
  sigla            text not null unique
                     check (sigla ~ '^[A-Z]{2,10}[0-9]{2,4}$'),          -- PB26, HT33, SEMSET26, BF26
  nome             text not null check (length(btrim(nome)) between 2 and 120),
  linha            text not null check (length(btrim(linha)) between 2 and 60),  -- Patrimônio Brasil, Holding Total…
  edicao           text check (edicao is null or length(btrim(edicao)) between 1 and 20),
  ano              smallint check (ano is null or ano between 2015 and 2100),
  etiqueta_clickup text unique
                     check (etiqueta_clickup is null or etiqueta_clickup ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  subarea_trafego  text check (subarea_trafego is null or subarea_trafego in ('interno', 'aurum', 'diamante')),
  inicio           date,
  fim              date,
  ativo            boolean not null default true,
  obs              text check (obs is null or length(obs) <= 1000),
  criado_em        timestamptz not null default now(),
  criado_por       uuid references public.perfis(id) on delete set null,
  atualizado_em    timestamptz not null default now(),
  atualizado_por   uuid references public.perfis(id) on delete set null,
  constraint projetos_datas_check check (fim is null or inicio is null or fim >= inicio)
);
comment on table mkt.projetos is 'Tabela de projetos ÚNICA do Marketing. Projeto = edição. sigla = campo 2 do nome de campanha.';
comment on column mkt.projetos.sigla is 'Sigla do nome de campanha (GESTOR | PROJETO | …): letras maiúsculas + dígitos. Ex.: PB26, HT33, SEMSET26.';
comment on column mkt.projetos.linha is 'Tipo/linha do projeto (Patrimônio Brasil, Holding Total, Seminário, Black Friday…). Texto livre curto.';
comment on column mkt.projetos.etiqueta_clickup is 'Etiqueta de projeto do ClickUp, texto exato (minúsculo com hífen). Nulo = não conhecida.';
comment on column mkt.projetos.subarea_trafego is 'Subárea do Tráfego: interno, aurum, diamante. Nulo = não se aplica ou não confirmada.';

create table mkt.paginas (
  id             bigint generated always as identity primary key,
  projeto_id     bigint not null references mkt.projetos(id) on delete restrict,
  codigo         text check (codigo is null or codigo ~ '^[a-z]{2}[0-9]{1,3}(-[a-z])?$'),   -- ak1, bl2, ak1-b, ak21
  nome           text not null check (length(btrim(nome)) between 1 and 80),
  dominio        text not null check (dominio ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'),
  caminho        text not null check (caminho ~ '^/([a-z0-9._~-]+/)*$'),                      -- /, /ak1/, /a/b/
  funcao         text not null check (funcao in ('captura', 'obrigado', 'quase_la', 'pesquisa', 'venda', 'outra')),
  funil          text check (funil is null or (length(btrim(funil)) between 1 and 40)),
  ativa          boolean not null default true,
  obs            text check (obs is null or length(obs) <= 1000),
  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.perfis(id) on delete set null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null,
  constraint paginas_endereco_unico unique (projeto_id, dominio, caminho)
);
create unique index paginas_codigo_unico on mkt.paginas (projeto_id, codigo) where codigo is not null;
create index paginas_projeto_idx on mkt.paginas (projeto_id);
comment on table mkt.paginas is 'Páginas de cada projeto (edição). A mesma URL em outra edição é outra linha, no projeto dela.';
comment on column mkt.paginas.codigo is 'Código da casa (paginas/padrao-slugs-variantes.md): 2 letras + número, sufixo -b… Só página de variante; obrigado, pesquisa etc. ficam sem código. Campo 5 do nome de campanha, em minúsculas.';
comment on column mkt.paginas.funil is 'Funil dentro do projeto, texto curto (no PB, os ids do Radar: ak1, bl2, recuperacao).';

create table mkt.campanha_gestores (
  sigla  text primary key check (sigla ~ '^[A-Z]{2,3}$'),
  nome   text not null,
  ativo  boolean not null default true
);
comment on table mkt.campanha_gestores is 'Lista fechada do campo 1 do nome de campanha (iniciais do gestor de tráfego).';

create table mkt.campanha_objetivos (
  codigo text primary key check (codigo = mkt.maiusculas(codigo)),
  ativo  boolean not null default true
);
comment on table mkt.campanha_objetivos is 'Lista fechada do campo 3 do nome de campanha.';

alter table mkt.projetos enable row level security;
alter table mkt.paginas enable row level security;
alter table mkt.campanha_gestores enable row level security;
alter table mkt.campanha_objetivos enable row level security;
revoke all on mkt.projetos, mkt.paginas, mkt.campanha_gestores, mkt.campanha_objetivos from public, anon, authenticated;

-- ─── 4. Seeds (só o que está nas fontes; o resto fica nulo) ──────────────────────────────────────────────────────────
-- Listas: area-de-trafego.md, "Listas (Victor, 05/10/2026)".
insert into mkt.campanha_gestores (sigla, nome) values
  ('CF', 'Caio Fábio'), ('RS', 'Renan Schwarz'), ('EF', 'Emmanuel Fernandes');
insert into mkt.campanha_objetivos (codigo) values
  ('LEADS'), ('VENDAS'), ('REMARKETING'), ('LEMBRETE'), ('DISTRIBUIÇÃO');

-- Projetos confirmados (05/10/2026). Datas desconhecidas = nulas (o PB tem duas datas nas fontes: 9 a 11/11 no
-- Radar e 03 a 08/11 no cérebro; não escolhi). HT33 sem etiqueta conhecida. Subárea: "Interno" da recapitulação
-- do Arthur (HTs, Patrimônio Brasil, Black Friday); Seminário da Elaine sem subárea confirmada.
insert into mkt.projetos (sigla, nome, linha, edicao, ano, etiqueta_clickup, subarea_trafego, obs) values
  ('PB26', 'Patrimônio Brasil 2026', 'Patrimônio Brasil', null, 2026, 'seminario-conjunto-2026-11', 'interno',
   'Seminário Conjunto (dos Diamantes). Domínio patrimoniobrasil.com.br.'),
  ('HT33', 'Holding Total 33', 'Holding Total', '33', null, null, 'interno',
   'Etiqueta do ClickUp não conhecida em 05/10/2026.'),
  ('SEMSET26', 'Seminário setembro 2026', 'Seminário', null, 2026, 'sem-set-2026', null,
   'Seminário da Elaine de setembro/2026. Etiqueta atual do ClickUp; a chave futura proposta é seminario-elaine-2026-09.'),
  ('BF26', 'Black Friday 2026', 'Black Friday', null, 2026, 'black-friday-2026-10', 'interno', null);

-- Páginas do PB: caminhos, nomes, tipos e funis exatamente como em sistemas/radar/projetos/patrimonio-brasil.json.
insert into mkt.paginas (projeto_id, codigo, nome, dominio, caminho, funcao, funil)
select p.id, v.codigo, v.nome, 'patrimoniobrasil.com.br', v.caminho, v.funcao, v.funil
  from mkt.projetos p,
       (values ('ak1', 'AK1', '/ak1/', 'captura', 'ak1'),
               (null, 'Obrigado', '/obrigado/', 'obrigado', 'ak1'),
               (null, 'Pesquisa da BL2', '/quase-la/', 'pesquisa', 'bl2'),
               (null, 'Pesquisa pelo link', '/pesquisa/', 'pesquisa', 'recuperacao')
       ) v(codigo, nome, caminho, funcao, funil)
 where p.sigla = 'PB26';

-- ─── 5. Tradução do nome de campanha (pura; lê só as 3 listas) ───────────────────────────────────────────────────────
-- Mesma regra de web/modules/marketing/projetos/domain/campanha.ts (testes em campanha.test.ts).
-- padrao = true só sem erro. Erros: vazio, numero_de_campos, gestor_desconhecido, sigla_invalida,
--   projeto_nao_cadastrado, objetivo_desconhecido, descricao_vazia, pagina_invalida.
-- Avisos (não tiram do padrão): minusculas, espacos_extras, sem_acento, projeto_inativo, pagina_nao_cadastrada.
create function mkt.campanha_traduzir(p_nome text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_bruto text := coalesce(p_nome, '');
  v_partes text[];
  v_n int;
  v_gestor text; v_projeto text; v_objetivo text; v_descricao text; v_pagina text;
  v_obj_canon text;
  v_proj mkt.projetos%rowtype;
  v_pagina_id bigint;
  v_erros text[] := '{}';
  v_avisos text[] := '{}';
  v_canonico text;
  i int;
begin
  if btrim(v_bruto) = '' then
    return jsonb_build_object('padrao', false, 'erros', jsonb_build_array('vazio'), 'avisos', '[]'::jsonb,
                              'gestor', null, 'projeto', null, 'objetivo', null, 'descricao', null, 'pagina', null,
                              'projeto_id', null, 'pagina_id', null, 'nome_canonico', null);
  end if;

  v_partes := string_to_array(v_bruto, '|');
  v_n := coalesce(array_length(v_partes, 1), 0);
  for i in 1..v_n loop
    v_partes[i] := btrim(regexp_replace(v_partes[i], '\s+', ' ', 'g'));
  end loop;

  if v_n not in (4, 5) then
    return jsonb_build_object('padrao', false, 'erros', jsonb_build_array('numero_de_campos'), 'avisos', '[]'::jsonb,
                              'gestor', null, 'projeto', null, 'objetivo', null, 'descricao', null, 'pagina', null,
                              'projeto_id', null, 'pagina_id', null, 'nome_canonico', null, 'campos', v_n);
  end if;

  v_gestor    := mkt.maiusculas(v_partes[1]);
  v_projeto   := mkt.maiusculas(v_partes[2]);
  v_objetivo  := mkt.maiusculas(v_partes[3]);
  v_descricao := mkt.maiusculas(v_partes[4]);
  v_pagina    := case when v_n = 5 then lower(v_partes[5]) end;

  if not exists (select 1 from mkt.campanha_gestores g where g.sigla = v_gestor and g.ativo) then
    v_erros := array_append(v_erros, 'gestor_desconhecido');
  end if;

  if v_projeto !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    v_erros := array_append(v_erros, 'sigla_invalida');
  else
    select * into v_proj from mkt.projetos p where p.sigla = v_projeto;
    if not found then
      v_erros := array_append(v_erros, 'projeto_nao_cadastrado');
    elsif not v_proj.ativo then
      v_avisos := array_append(v_avisos, 'projeto_inativo');
    end if;
  end if;

  select o.codigo into v_obj_canon from mkt.campanha_objetivos o
   where o.ativo and mkt.sem_acento(o.codigo) = mkt.sem_acento(v_objetivo);
  if v_obj_canon is null then
    v_erros := array_append(v_erros, 'objetivo_desconhecido');
  else
    if v_obj_canon <> v_objetivo then v_avisos := array_append(v_avisos, 'sem_acento'); end if;
    v_objetivo := v_obj_canon;
  end if;

  if v_descricao = '' then v_erros := array_append(v_erros, 'descricao_vazia'); end if;

  if v_n = 5 then
    if v_pagina !~ '^[a-z]{2}[0-9]{1,3}(-[a-z])?$' then
      v_erros := array_append(v_erros, 'pagina_invalida');
    elsif v_proj.id is not null then
      select pg.id into v_pagina_id from mkt.paginas pg where pg.projeto_id = v_proj.id and pg.codigo = v_pagina;
      if v_pagina_id is null then v_avisos := array_append(v_avisos, 'pagina_nao_cadastrada'); end if;
    end if;
  end if;

  v_canonico := v_gestor || ' | ' || v_projeto || ' | ' || v_objetivo || ' | ' || v_descricao
                || case when v_n = 5 then ' | ' || upper(v_pagina) else '' end;
  if v_bruto <> mkt.maiusculas(v_bruto) then v_avisos := array_append(v_avisos, 'minusculas'); end if;
  if mkt.sem_acento(v_bruto) <> mkt.sem_acento(v_canonico) then v_avisos := array_append(v_avisos, 'espacos_extras'); end if;

  return jsonb_build_object(
    'padrao', cardinality(v_erros) = 0,
    'gestor', v_gestor, 'projeto', v_projeto, 'objetivo', v_objetivo, 'descricao', v_descricao, 'pagina', v_pagina,
    'projeto_id', v_proj.id, 'pagina_id', v_pagina_id,
    'erros', to_jsonb(v_erros), 'avisos', to_jsonb(v_avisos), 'nome_canonico', v_canonico);
end
$$;

-- ─── 6. Funções públicas (RPC) ───────────────────────────────────────────────────────────────────────────────────────
create function public.mkt_projetos_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', p.id, 'sigla', p.sigla, 'nome', p.nome, 'linha', p.linha, 'edicao', p.edicao, 'ano', p.ano,
            'etiqueta_clickup', p.etiqueta_clickup, 'subarea_trafego', p.subarea_trafego,
            'inicio', p.inicio, 'fim', p.fim, 'ativo', p.ativo, 'obs', p.obs, 'atualizado_em', p.atualizado_em,
            'paginas', (select count(*) from mkt.paginas pg where pg.projeto_id = p.id))
          order by p.ativo desc, p.sigla), '[]'::jsonb)
            from mkt.projetos p);
end
$$;

create function public.mkt_paginas_listar(p_projeto bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', pg.id, 'projeto_id', pg.projeto_id, 'projeto_sigla', p.sigla, 'codigo', pg.codigo, 'nome', pg.nome,
            'dominio', pg.dominio, 'caminho', pg.caminho, 'url', 'https://' || pg.dominio || pg.caminho,
            'funcao', pg.funcao, 'funil', pg.funil, 'ativa', pg.ativa, 'obs', pg.obs)
          order by p.sigla, pg.funil nulls last, pg.caminho), '[]'::jsonb)
            from mkt.paginas pg join mkt.projetos p on p.id = pg.projeto_id
           where p_projeto is null or pg.projeto_id = p_projeto);
end
$$;

-- Cria (sem "id") ou edita (com "id"). Campos: sigla, nome, linha, edicao, ano, etiqueta_clickup, subarea_trafego,
-- inicio, fim, ativo, obs. Texto vazio vira nulo. Retorna {ok, msg, id}.
create function public.mkt_projeto_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_sigla text := upper(btrim(coalesce(p ->> 'sigla', '')));
  v_nome text := btrim(coalesce(p ->> 'nome', ''));
  v_linha text := btrim(coalesce(p ->> 'linha', ''));
  v_edicao text := nullif(btrim(coalesce(p ->> 'edicao', '')), '');
  v_ano smallint;
  v_etq text := nullif(btrim(coalesce(p ->> 'etiqueta_clickup', '')), '');
  v_sub text := nullif(lower(btrim(coalesce(p ->> 'subarea_trafego', ''))), '');
  v_inicio date;
  v_fim date;
  v_ativo boolean := coalesce((p ->> 'ativo')::boolean, true);
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_con text;
begin
  if not mkt.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if v_sigla !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    return jsonb_build_object('ok', false, 'msg', 'Sigla inválida: letras maiúsculas seguidas de 2 a 4 dígitos (ex.: PB26, HT33, SEMSET26).');
  end if;
  if length(v_nome) < 2 then return jsonb_build_object('ok', false, 'msg', 'Informe o nome do projeto.'); end if;
  if length(v_linha) < 2 then return jsonb_build_object('ok', false, 'msg', 'Informe o tipo/linha (ex.: Patrimônio Brasil).'); end if;
  if v_etq is not null and v_etq !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    return jsonb_build_object('ok', false, 'msg', 'Etiqueta do ClickUp inválida: minúsculas, números e hífen, exatamente como no ClickUp.');
  end if;
  if v_sub is not null and v_sub not in ('interno', 'aurum', 'diamante') then
    return jsonb_build_object('ok', false, 'msg', 'Subárea do Tráfego: interno, aurum ou diamante (ou vazio).');
  end if;
  begin
    v_ano := nullif(btrim(coalesce(p ->> 'ano', '')), '')::smallint;
    v_inicio := nullif(btrim(coalesce(p ->> 'inicio', '')), '')::date;
    v_fim := nullif(btrim(coalesce(p ->> 'fim', '')), '')::date;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Ano ou data em formato inválido.');
  end;

  begin
    if v_id is null then
      insert into mkt.projetos (sigla, nome, linha, edicao, ano, etiqueta_clickup, subarea_trafego, inicio, fim, ativo, obs,
                                criado_por, atualizado_por)
      values (v_sigla, v_nome, v_linha, v_edicao, v_ano, v_etq, v_sub, v_inicio, v_fim, v_ativo, v_obs, v_uid, v_uid)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Projeto ' || v_sigla || ' criado.', 'id', v_id);
    end if;
    update mkt.projetos
       set sigla = v_sigla, nome = v_nome, linha = v_linha, edicao = v_edicao, ano = v_ano, etiqueta_clickup = v_etq,
           subarea_trafego = v_sub, inicio = v_inicio, fim = v_fim, ativo = v_ativo, obs = v_obs,
           atualizado_em = now(), atualizado_por = v_uid
     where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.'); end if;
    return jsonb_build_object('ok', true, 'msg', 'Projeto ' || v_sigla || ' salvo.', 'id', v_id);
  exception
    when unique_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', case when v_con like '%etiqueta%'
        then 'Já existe projeto com esta etiqueta do ClickUp.' else 'Já existe projeto com a sigla ' || v_sigla || '.' end);
    when check_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', case when v_con = 'projetos_datas_check'
        then 'O fim não pode ser antes do início.' else 'Valor fora da regra (' || v_con || ').' end);
  end;
end
$$;

-- Cria (sem "id") ou edita (com "id"). Campos: projeto_id, codigo, nome, dominio, caminho, funcao, funil, ativa, obs.
-- Aceita a URL inteira em "caminho" (https://dominio/caminho/): separa domínio e caminho. Retorna {ok, msg, id}.
create function public.mkt_pagina_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_projeto bigint := nullif(p ->> 'projeto_id', '')::bigint;
  v_codigo text := nullif(lower(btrim(coalesce(p ->> 'codigo', ''))), '');
  v_nome text := btrim(coalesce(p ->> 'nome', ''));
  v_dominio text := lower(btrim(coalesce(p ->> 'dominio', '')));
  v_caminho text := lower(btrim(coalesce(p ->> 'caminho', '')));
  v_funcao text := lower(btrim(coalesce(p ->> 'funcao', '')));
  v_funil text := nullif(btrim(coalesce(p ->> 'funil', '')), '');
  v_ativa boolean := coalesce((p ->> 'ativa')::boolean, true);
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_m text[];
  v_con text;
begin
  if not mkt.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  if v_projeto is null or not exists (select 1 from mkt.projetos where id = v_projeto) then
    return jsonb_build_object('ok', false, 'msg', 'Escolha o projeto.');
  end if;
  v_m := regexp_match(v_caminho, '^https?://([^/?#]+)(/[^?#]*)?');
  if v_m is not null then
    v_dominio := v_m[1];
    v_caminho := coalesce(v_m[2], '/');
  end if;
  v_dominio := regexp_replace(v_dominio, '^www\.', '');
  if v_caminho = '' then v_caminho := '/'; end if;
  if left(v_caminho, 1) <> '/' then v_caminho := '/' || v_caminho; end if;
  if right(v_caminho, 1) <> '/' then v_caminho := v_caminho || '/'; end if;

  if v_dominio !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' then
    return jsonb_build_object('ok', false, 'msg', 'Domínio inválido (ex.: patrimoniobrasil.com.br).');
  end if;
  if v_caminho !~ '^/([a-z0-9._~-]+/)*$' then
    return jsonb_build_object('ok', false, 'msg', 'Caminho inválido (ex.: /ak1/).');
  end if;
  if v_codigo is not null and v_codigo !~ '^[a-z]{2}[0-9]{1,3}(-[a-z])?$' then
    return jsonb_build_object('ok', false, 'msg', 'Código fora do padrão da casa: 2 letras + número, com sufixo opcional (ak1, bl2, ak1-b).');
  end if;
  if v_funcao not in ('captura', 'obrigado', 'quase_la', 'pesquisa', 'venda', 'outra') then
    return jsonb_build_object('ok', false, 'msg', 'Função inválida.');
  end if;
  if v_nome = '' then v_nome := coalesce(upper(v_codigo), v_caminho); end if;

  begin
    if v_id is null then
      insert into mkt.paginas (projeto_id, codigo, nome, dominio, caminho, funcao, funil, ativa, obs, criado_por, atualizado_por)
      values (v_projeto, v_codigo, v_nome, v_dominio, v_caminho, v_funcao, v_funil, v_ativa, v_obs, v_uid, v_uid)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Página ' || v_caminho || ' criada.', 'id', v_id);
    end if;
    update mkt.paginas
       set projeto_id = v_projeto, codigo = v_codigo, nome = v_nome, dominio = v_dominio, caminho = v_caminho,
           funcao = v_funcao, funil = v_funil, ativa = v_ativa, obs = v_obs, atualizado_em = now(), atualizado_por = v_uid
     where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Página não encontrada.'); end if;
    return jsonb_build_object('ok', true, 'msg', 'Página ' || v_caminho || ' salva.', 'id', v_id);
  exception
    when unique_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', case when v_con = 'paginas_codigo_unico'
        then 'Este projeto já tem uma página com o código ' || v_codigo || '.'
        else 'Este projeto já tem a página ' || v_dominio || v_caminho || '.' end);
    when check_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Valor fora da regra (' || v_con || ').');
  end;
end
$$;

create function public.mkt_campanha_listas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object(
    'gestores', (select coalesce(jsonb_agg(jsonb_build_object('sigla', g.sigla, 'nome', g.nome) order by g.sigla), '[]'::jsonb)
                   from mkt.campanha_gestores g where g.ativo),
    'objetivos', (select coalesce(jsonb_agg(o.codigo order by o.codigo), '[]'::jsonb) from mkt.campanha_objetivos o where o.ativo),
    'projetos', (select coalesce(jsonb_agg(p.sigla order by p.sigla), '[]'::jsonb) from mkt.projetos p));
end
$$;

create function public.mkt_campanha_traduzir(p_nome text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return mkt.campanha_traduzir(p_nome);
end
$$;

-- ─── 7. Quem executa o quê ───────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace in ('mkt'::regnamespace, 'mkt_web'::regnamespace)
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end
$grants$;
grant execute on function
  public.mkt_projetos_listar(), public.mkt_paginas_listar(bigint), public.mkt_projeto_salvar(jsonb),
  public.mkt_pagina_salvar(jsonb), public.mkt_campanha_listas(), public.mkt_campanha_traduzir(text)
  to authenticated;

-- ─── 8. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t text;
  f record;
  v_publicas text[] := array['mkt_projetos_listar', 'mkt_paginas_listar', 'mkt_projeto_salvar', 'mkt_pagina_salvar',
                             'mkt_campanha_listas', 'mkt_campanha_traduzir'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt', 'usage') or has_schema_privilege(r, 'mkt_web', 'usage')
       or has_schema_privilege(r, 'mkt', 'create') or has_schema_privilege(r, 'mkt_web', 'create') then
      raise exception '20261005m: % tem acesso a schema mkt/mkt_web', r;
    end if;
  end loop;

  foreach t in array array['mkt.projetos', 'mkt.paginas', 'mkt.campanha_gestores', 'mkt.campanha_objetivos'] loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005m: % tem privilégio em %', r, t;
      end if;
    end loop;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261005m: RLS desligada em %', t;
    end if;
  end loop;

  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where p.pronamespace in ('mkt'::regnamespace, 'mkt_web'::regnamespace)
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_%') loop
    if not (f.proconfig @> array['search_path=""']) then
      raise exception '20261005m: % sem search_path vazio', f.sig;
    end if;
    if has_function_privilege('anon', f.sig, 'execute') then
      raise exception '20261005m: anon executa %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005m: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any(v_publicas))
       <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261005m: grant de authenticated errado em %', f.sig;
    end if;
    if f.proname = any(v_publicas) and not f.prosecdef then
      raise exception '20261005m: % deveria ser SECURITY DEFINER', f.sig;
    end if;
  end loop;

  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_publicas)) <> 6 then
    raise exception '20261005m: esperava 6 funções públicas mkt_*';
  end if;
  if (select count(*) from mkt.projetos) <> 4 or (select count(*) from mkt.paginas) <> 4
     or (select count(*) from mkt.campanha_gestores) <> 3 or (select count(*) from mkt.campanha_objetivos) <> 5 then
    raise exception '20261005m: seed diferente do esperado (4 projetos, 4 páginas, 3 gestores, 5 objetivos)';
  end if;
  if exists (select 1 from pg_class c where c.relnamespace = 'mkt_web'::regnamespace) then
    raise exception '20261005m: mkt_web deveria nascer vazio';
  end if;
end
$confere$;

-- ═══ ENSAIO: testes (como a tela chamaria, com JWT simulado) ════════════════════════════════════════════════════════
-- 1. Criou e semeou
insert into pg_temp._z_out (passo, linha) values ('1.schemas',
  (select string_agg(nspname, ',' order by nspname) from pg_namespace where nspname in ('mkt', 'mkt_web')));
insert into pg_temp._z_out (passo, linha) values ('1.seed',
  'projetos=' || (select count(*) from mkt.projetos) || ' paginas=' || (select count(*) from mkt.paginas)
  || ' gestores=' || (select count(*) from mkt.campanha_gestores) || ' objetivos=' || (select count(*) from mkt.campanha_objetivos));
insert into pg_temp._z_out (passo, linha) values ('1.mkt_web_vazio',
  (select count(*)::text from pg_class c where c.relnamespace = 'mkt_web'::regnamespace));

-- ids lidos como postgres (authenticated não tem USAGE no schema mkt)
create temp table _z_ids on commit drop as select sigla, id from mkt.projetos;
grant all on _z_ids to public;

-- 2. Como o Victor (admin): listar, criar, validar formato, duplicata
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '2.projetos',
  string_agg(x ->> 'sigla' || ' etq=' || coalesce(x ->> 'etiqueta_clickup', 'null') || ' sub=' || coalesce(x ->> 'subarea_trafego', 'null')
             || ' pag=' || (x ->> 'paginas'), ' ; ' order by x ->> 'sigla')
  from jsonb_array_elements(public.mkt_projetos_listar()) x;
insert into pg_temp._z_out (passo, linha) select '2.paginas_pb',
  string_agg(coalesce(x ->> 'codigo', '-') || ' ' || (x ->> 'url') || ' ' || (x ->> 'funcao') || ' ' || coalesce(x ->> 'funil', '-'), ' ; '
             order by x ->> 'caminho')
  from jsonb_array_elements(public.mkt_paginas_listar((select id from pg_temp._z_ids where sigla = 'PB26'))) x;
insert into pg_temp._z_out (passo, linha) values ('2.sigla_invalida',
  public.mkt_projeto_salvar('{"sigla":"PB-26","nome":"ZZ Ensaio","linha":"ZZ Ensaio"}')::text);
insert into pg_temp._z_out (passo, linha) values ('2.sigla_so_letras',
  public.mkt_projeto_salvar('{"sigla":"ZZENSAIO","nome":"ZZ Ensaio","linha":"ZZ Ensaio"}')::text);
insert into pg_temp._z_out (passo, linha) values ('2.criar',
  public.mkt_projeto_salvar('{"sigla":"zzensaio99","nome":"ZZ Ensaio 99","linha":"ZZ Ensaio","ano":"2026","subarea_trafego":"aurum"}')::text);
insert into pg_temp._z_out (passo, linha) values ('2.duplicata_sigla',
  public.mkt_projeto_salvar('{"sigla":"PB26","nome":"ZZ Ensaio","linha":"ZZ Ensaio"}')::text);
insert into pg_temp._z_out (passo, linha) values ('2.duplicata_etiqueta',
  public.mkt_projeto_salvar('{"sigla":"ZZENSAIO98","nome":"ZZ Ensaio","linha":"ZZ Ensaio","etiqueta_clickup":"black-friday-2026-10"}')::text);
insert into pg_temp._z_out (passo, linha) values ('2.etiqueta_invalida',
  public.mkt_projeto_salvar('{"sigla":"ZZENSAIO98","nome":"ZZ Ensaio","linha":"ZZ Ensaio","etiqueta_clickup":"Black Friday"}')::text);
insert into pg_temp._z_out (passo, linha) values ('2.datas_invertidas',
  public.mkt_projeto_salvar('{"sigla":"ZZENSAIO98","nome":"ZZ Ensaio","linha":"ZZ Ensaio","inicio":"2026-11-10","fim":"2026-11-01"}')::text);
insert into pg_temp._z_out (passo, linha) values ('2.editar',
  public.mkt_projeto_salvar(jsonb_build_object('id', (select (linha::json ->> 'id')::bigint from pg_temp._z_out where passo = '2.criar'), 'sigla', 'ZZENSAIO99',
    'nome', 'ZZ Ensaio 99 editado', 'linha', 'ZZ Ensaio', 'ativo', false))::text);

-- 3. Páginas: formato do código, URL inteira, duplicata
insert into pg_temp._z_out (passo, linha) values ('3.codigo_invalido',
  public.mkt_pagina_salvar(jsonb_build_object('projeto_id', (select (linha::json ->> 'id')::bigint from pg_temp._z_out where passo = '2.criar'),
    'codigo', 'a1', 'dominio', 'exemplo.invalid', 'caminho', '/zz/', 'funcao', 'captura'))::text);
insert into pg_temp._z_out (passo, linha) values ('3.criar_url',
  public.mkt_pagina_salvar(jsonb_build_object('projeto_id', (select (linha::json ->> 'id')::bigint from pg_temp._z_out where passo = '2.criar'),
    'codigo', 'ZZ9-B', 'caminho', 'https://www.exemplo.invalid/zz9-b', 'funcao', 'captura', 'funil', 'zz'))::text);
reset role;
insert into pg_temp._z_out (passo, linha) select '3.pagina_gravada', codigo || ' ' || dominio || caminho || ' nome=' || nome
  from mkt.paginas where caminho = '/zz9-b/';
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('3.duplicata_codigo',
  public.mkt_pagina_salvar(jsonb_build_object('projeto_id', (select id from pg_temp._z_ids where sigla = 'PB26'),
    'codigo', 'ak1', 'dominio', 'patrimoniobrasil.com.br', 'caminho', '/zz-outro/', 'funcao', 'captura'))::text);
insert into pg_temp._z_out (passo, linha) values ('3.duplicata_caminho',
  public.mkt_pagina_salvar(jsonb_build_object('projeto_id', (select id from pg_temp._z_ids where sigla = 'PB26'),
    'dominio', 'patrimoniobrasil.com.br', 'caminho', '/obrigado/', 'funcao', 'obrigado'))::text);
insert into pg_temp._z_out (passo, linha) values ('3.funcao_invalida',
  public.mkt_pagina_salvar(jsonb_build_object('projeto_id', (select id from pg_temp._z_ids where sigla = 'PB26'),
    'dominio', 'patrimoniobrasil.com.br', 'caminho', '/zz-x/', 'funcao', 'blog'))::text);

-- 4. Tradução do nome de campanha
insert into pg_temp._z_out (passo, linha)
select '4.traduzir', n || ' => padrao=' || (t ->> 'padrao') || ' erros=' || (t -> 'erros')::text || ' avisos=' || (t -> 'avisos')::text
       || coalesce(' canon=' || (t ->> 'nome_canonico'), '') || ' pagina_id=' || coalesce(t ->> 'pagina_id', 'null')
  from unnest(array[
    'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1',
    'cf|ht33|vendas|aula ao vivo',
    'EF  |  BF26 | DISTRIBUICAO |  Oferta   final',
    'XX | PB26 | LEADS | TESTE',
    'RS | P26X | LEADS | TESTE',
    'RS | ZZ99 | LEADS | TESTE',
    'RS | PB26 | TOPO | TESTE',
    'RS | PB26 | LEADS',
    'RS | PB26 | LEADS | TESTE | A1',
    'RS | PB26 | LEADS | TESTE | BL2',
    'RS | ZZENSAIO99 | LEADS | TESTE'
  ]) with ordinality u(n, o), lateral (select public.mkt_campanha_traduzir(u.n) t) z
 order by o;
insert into pg_temp._z_out (passo, linha) values ('4.listas', public.mkt_campanha_listas()::text);
reset role;

-- 5. Formato garantido também na tabela (insert direto como postgres)
do $t$
begin
  begin
    insert into mkt.projetos (sigla, nome, linha) values ('pb26x', 'ZZ', 'ZZ');
    insert into pg_temp._z_out (passo, linha) values ('5.check_sigla', 'ACEITOU (ERRADO)');
  exception when check_violation then
    insert into pg_temp._z_out (passo, linha) values ('5.check_sigla', '23514 ok');
  end;
  begin
    insert into mkt.paginas (projeto_id, codigo, nome, dominio, caminho, funcao)
    values ((select id from pg_temp._z_ids where sigla = 'PB26'), 'AK1', 'ZZ', 'exemplo.invalid', '/zz/', 'captura');
    insert into pg_temp._z_out (passo, linha) values ('5.check_codigo', 'ACEITOU (ERRADO)');
  exception when check_violation then
    insert into pg_temp._z_out (passo, linha) values ('5.check_codigo', '23514 ok');
  end;
end
$t$;

-- 6. Permissões
insert into pg_temp._z_out (passo, linha)
select '6.grants', r || ' ' || t || ' tabela=' || has_table_privilege(r, t, 'select,insert,update,delete')
  from unnest(array['anon','authenticated']) r,
       unnest(array['mkt.projetos','mkt.paginas','mkt.campanha_gestores','mkt.campanha_objetivos']) t;
insert into pg_temp._z_out (passo, linha)
select '6.schema', r || ' mkt=' || has_schema_privilege(r, 'mkt', 'usage') || ' mkt_web=' || has_schema_privilege(r, 'mkt_web', 'usage')
  from unnest(array['anon','authenticated']) r;
insert into pg_temp._z_out (passo, linha)
select '6.grants_funcoes', n.nspname || '.' || p.proname || ' anon=' || has_function_privilege('anon', p.oid, 'execute')
       || ' auth=' || has_function_privilege('authenticated', p.oid, 'execute') || ' definer=' || p.prosecdef
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('mkt', 'mkt_web') or (n.nspname = 'public' and p.proname like 'mkt\_%')
 order by n.nspname, p.proname;

-- 7. Não-admin (uid aleatório) e anon: toda RPC recusada; leitura direta recusada
do $t$
declare
  c text;
  v_r text;
  v_chamadas text[] := array[
    'select public.mkt_projetos_listar()',
    'select public.mkt_paginas_listar(null)',
    'select public.mkt_projeto_salvar(''{"sigla":"ZZENSAIO97","nome":"ZZ","linha":"ZZ"}'')',
    'select public.mkt_pagina_salvar(''{}'')',
    'select public.mkt_campanha_listas()',
    'select public.mkt_campanha_traduzir(''RS | PB26 | LEADS | X'')'];
begin
  foreach v_r in array array['authenticated', 'anon'] loop
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000ff","role":"' || v_r || '"}', true);
    foreach c in array v_chamadas loop
      execute format('set local role %I', v_r);
      begin
        execute c;
        reset role;
        insert into pg_temp._z_out (passo, linha) values ('7.' || v_r, 'PASSOU (ERRADO): ' || c);
      exception when insufficient_privilege then
        reset role;
        insert into pg_temp._z_out (passo, linha) values ('7.' || v_r, '42501 ok: ' || split_part(split_part(c, '(', 1), '.', 2));
      end;
    end loop;
    execute format('set local role %I', v_r);
    begin
      perform 1 from mkt.projetos limit 1;
      reset role;
      insert into pg_temp._z_out (passo, linha) values ('7.' || v_r || '_select_direto', 'LEU (ERRADO)');
    exception when insufficient_privilege then
      reset role;
      insert into pg_temp._z_out (passo, linha) values ('7.' || v_r || '_select_direto', '42501 ok');
    end;
  end loop;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
