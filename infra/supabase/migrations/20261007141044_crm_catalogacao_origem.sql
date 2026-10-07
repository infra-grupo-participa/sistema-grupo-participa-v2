-- 20261007141044 (ex-20261007g): Comercial — CATALOGAÇÃO DE ORIGEM dos contatos (de onde cada um veio e de qual projeto).
--
-- STATUS: APLICADA em 07/10/2026, versão gravada 20261007141044 (crm_catalogacao_origem), uma apply_migration.
-- Statement gravado = este arquivo sem as linhas só de comentário e sem os comentários de fim de linha (md5 ae21cdc6…).
-- Ensaio: 20261007141044_ensaio.sql (begin … rollback). Números, decisões e relatório: 20261007141044.explain.md.
-- DEPENDE da 20261007e_crm_ativacao_padrao (cria a versão mínima de crm.projeto_do_evento, que esta SUBSTITUI com a
-- mesma assinatura). Ordem: 20261007e, depois esta. A guarda aborta se a 20261007e não estiver aplicada.
--
-- O QUE ENTRA
--   1. crm.pessoa_origem (1:1 com crm.pessoa_comercial): canal_entrada, entrou_em, origem_detalhe (estruturado:
--      produto/oferta Hotmart, funil Clint/CRM, lista/tag/UTM do AC, todas as chaves vistas), projeto (CHAVE do projeto,
--      a mesma string do utm_campaign, da etiqueta do ClickUp e de crm.funil.projeto), linha, motivo quando não há
--      projeto. Sem grant para a API: só pelas RPCs.
--   2. crm.catalogo_regra: regras editáveis pelo gestor (campo + operador + padrão [+ janela de datas] → projeto ou
--      "sem projeto"). Campos: utm_campaign, ac_lista (id OU nome da lista), ac_tag, hotmart_oferta, funil,
--      hotmart_produto, respondi_form, sck (pista fraca, por último). Semente = proposta (ver explain).
--      crm.ac_lista: id → nome das listas do ActiveCampaign (lido da API em 07/10/2026, 157 listas; o webhook só manda id).
--   3. crm.projeto_do_evento(fonte, dados) → chave do projeto ou null (CONTRATO com a Ativação, 20261007e; mesma
--      assinatura). Implícitas: utm_campaign igual a uma chave conhecida; sck de crm.link_rastreavel; funil com projeto.
--   4. Daqui para frente, SEM alterar as funções que criam contato (hotmart_processar e anexar_integracao estão sendo
--      reescritas pela 20261007e e pela F4; mexer nelas daria conflito): todo contato nasce por crm.garantir_pc
--      (md5 conferido) ou por public.crm_criar_contato ("Novo contato", 20261007133345) → gatilho AFTER INSERT em
--      crm.pessoa_comercial grava a origem com a dica de
--      crm.canal (hotmart, clint_import, activecampaign, whatsapp; sem canal: manual/mcp pela sessão, ou sistema) e
--      cataloga pelas evidências. Evidência que chega depois (hotmart_processado e evento_jornada ganham pessoa,
--      negócio novo) recataloga a pessoa. Gatilhos nunca derrubam a gravação principal (exception → warning).
--   5. Backfill dos contatos existentes (canal = evidência MAIS ANTIGA; empate Clint > AC > Hotmart; projeto = primeira
--      evidência, em ordem de data, que uma regra liga a projeto).
--   5b. MQL (Arthur, 07/10/2026): regra tipo 'mql' (tag ou lista do AC → projeto + MQL). crm.mql_do_evento(fonte, dados)
--      → boolean, contrato com a Ativação (substitui o corpo mínimo da 20261007e). pessoa_origem.mql_desde/mql_projeto.
--      Semente: só "PB MQL" → seminario-conjunto-2026-11 ("PB NAO MQL" não é MQL).
--   5c. Permissão: regras e listas = área de Dados (Victor Hugo): crm.pode_catalogar() = cargo admin/dev OU função
--      'dados.catalogar' em public.perfis.funcoes. O gestor comercial vê, reaplica aos sem projeto e classifica contato a
--      contato (crm_contato_origem_definir); não edita regra. Projeto só da lista de gp-operacoes/projetos.
--   6. Front: crm_contatos_pagina ganha p_canal e p_projeto (drop + create, mesmos grants); crm.contatos_itens devolve
--      'origem'; crm_contatos_resumo devolve canais e projetos; RPCs novas: crm_catalogo, crm_catalogo_regra_salvar,
--      crm_catalogo_lista_salvar, crm_catalogo_reaplicar, crm_contato_origem, crm_contato_origem_definir.
--
-- AS 5 PERGUNTAS (números medidos no explain)
--   escala: catalogar 1 pessoa = 3 leituras indexadas (hotmart_processado ganha índice por pessoa) + 1 resolver por
--     evidência até achar projeto; regras são dezenas de linhas. Reaplicar todos: medido no ensaio.
--   índice: hotmart_processado (pessoa_id, quando) novo; evento_jornada e negocio já têm por pessoa.
--   frequência: 1 catalogação por contato novo, por compra Hotmart ligada, por evento do AC ligado e por negócio novo.
--   repetição: a lista lê origem por join (1 query); nomes de projeto só para a página (≤ 200).
--   reversão: alter table … disable trigger zz_origem_* (para de catalogar em ~segundos); bloco REVERSÃO no fim.

-- ─── Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $g$
declare r record;
begin
  if to_regclass('crm.pessoa_origem') is not null then raise exception '20261007g: já aplicada (crm.pessoa_origem existe)'; end if;
  if to_regprocedure('public.crm_ativacao_garantir(text)') is null then
    raise exception '20261007g: a 20261007e (Ativação) ainda não foi aplicada (falta crm_ativacao_garantir). Aplique antes.';
  end if;
  if to_regprocedure('crm.projeto_do_evento(text,jsonb)') is null then
    raise exception '20261007g: falta a 20261007e (crm.projeto_do_evento). Aplique a 20261007e antes.';
  end if;
  if to_regprocedure('crm.mql_do_evento(text,jsonb)') is not null
     and pg_get_function_result('crm.mql_do_evento(text,jsonb)'::regprocedure) <> 'boolean' then
    raise exception '20261007g: crm.mql_do_evento não devolve boolean (contrato mudou)';
  end if;
  if pg_get_function_result('crm.projeto_do_evento(text,jsonb)'::regprocedure) <> 'text' then
    raise exception '20261007g: crm.projeto_do_evento não devolve text (contrato mudou)';
  end if;
  if position('select null::text' in (select prosrc from pg_proc where oid = 'crm.projeto_do_evento(text,jsonb)'::regprocedure)) = 0 then
    raise exception '20261007g: crm.projeto_do_evento não é a versão mínima da 20261007e; reler antes de substituir';
  end if;
  -- corpos VIVOS lidos em 07/10/2026 (md5 do prosrc)
  for r in select * from (values
      ('crm.garantir_pc(uuid)', '9563837f8ad7d4094c74903a75a1415c'),
      ('crm.contatos_base(uuid[],boolean,uuid,text,text,text[],boolean,boolean,boolean)', 'a7b3bd46c147d38134bb82e30bdd2443'),
      ('crm.contatos_itens(uuid[],boolean)', 'c7c17a0ca425a04946d2f043733d8b06'),
      ('public.crm_contatos_pagina(text,text,text,text,text[],boolean,boolean,text,text,integer,integer)', 'f2fded7910d886eac20cb209de9b8d22'),
      ('public.crm_contatos_resumo()', '5637d27bbffdab119512b1b5b33bf056')) v(sig, esperado)
  loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(r.sig)) is distinct from r.esperado then
      raise exception '20261007g: corpo vivo de % mudou (md5 esperado %). Releia pg_get_functiondef antes de aplicar.', r.sig, r.esperado;
    end if;
  end loop;
  -- quem insere em crm.pessoa_comercial: crm.garantir_pc e public.crm_criar_contato (20261007133345, "Novo contato" da
  -- tela, sessão de usuário → dica 'manual'). Qualquer outro escritor: reler antes (o gatilho de origem cobre todos, mas a
  -- dica de canal precisa ser conferida)
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('crm', 'public', 'pessoas')
                and p.oid <> 'crm.garantir_pc(uuid)'::regprocedure
                and p.oid is distinct from to_regprocedure('public.crm_criar_contato(jsonb)')
                and p.prosrc ~* 'insert\s+into\s+crm\.pessoa_comercial') then
    raise exception '20261007g: há outro insert em crm.pessoa_comercial além de garantir_pc/crm_criar_contato; reler';
  end if;
  if to_regprocedure('public.crm_criar_contato(jsonb)') is not null
     and (select md5(prosrc) from pg_proc where oid = 'public.crm_criar_contato(jsonb)'::regprocedure) <> '09f87f05c25513bd941bc9df39ff05e4' then
    raise exception '20261007g: corpo vivo de crm_criar_contato mudou (md5 esperado 09f87f05…); reler';
  end if;
  -- as dicas de canal que o gatilho usa (set_config('crm.canal', …) antes de garantir_pc)
  if position('''crm.canal'', ''hotmart''' in (select prosrc from pg_proc where oid = 'crm.hotmart_processar(jsonb)'::regprocedure)) = 0
     or position('''crm.canal'', ''activecampaign''' in (select prosrc from pg_proc where oid = 'crm.anexar_integracao(bigint,text)'::regprocedure)) = 0
     or position('''crm.canal'', ''clint_import''' in (select prosrc from pg_proc where oid = 'crm._clint_carregar(integer,jsonb)'::regprocedure)) = 0 then
    raise exception '20261007g: dica crm.canal mudou em hotmart_processar/anexar_integracao/_clint_carregar; reler';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'mkt' and table_name = 'projetos'
                  and column_name = 'etiqueta_clickup') then
    raise exception '20261007g: mkt.projetos.etiqueta_clickup não existe';
  end if;
  if (select count(*) from crm.pessoa_comercial) not between 2500 and 6000 then
    raise exception '20261007g: massa de contatos fora do esperado (% linhas); conferir antes do backfill', (select count(*) from crm.pessoa_comercial);
  end if;
end
$g$;

-- ─── 1. Tabelas ───────────────────────────────────────────────────────────────────────────────────────────────────
create table crm.ac_lista (
  id            text primary key check (id ~ '^[0-9]{1,10}$'),
  nome          text not null check (length(btrim(nome)) between 1 and 200),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);
comment on table crm.ac_lista is
  '20261007g: nome das listas do ActiveCampaign (o webhook só manda o id). Semente: GET /api/3/lists em 07/10/2026. Editável pelo gestor.';

create table crm.catalogo_regra (
  id             bigint generated always as identity primary key,
  -- 'projeto': o valor liga ao projeto. 'mql': o valor (tag ou lista) liga ao projeto E marca MQL (decisão do Arthur,
  -- 07/10/2026: MQL pela tag do AC, com a lista de tags/listas que valem controlada pela área de Dados)
  tipo           text not null default 'projeto' check (tipo in ('projeto', 'mql')),
  campo          text not null check (campo in ('utm_campaign', 'ac_lista', 'ac_tag', 'hotmart_oferta', 'funil',
                                                'hotmart_produto', 'respondi_form', 'sck')),
  operador       text not null default 'igual' check (operador in ('igual', 'comeca', 'contem')),
  padrao         text not null check (length(btrim(padrao)) between 1 and 200),
  -- null = "conhecido, sem projeto" (ex.: lista geral do produto): sai das pendências sem inventar projeto
  projeto        text check (projeto is null or projeto ~ '^[a-z0-9][a-z0-9-]{1,79}$'),
  vale_de        date,
  vale_ate       date,
  prioridade     smallint not null default 100 check (prioridade between 0 and 1000),
  ativo          boolean not null default true,
  nota           text check (nota is null or length(nota) <= 300),
  criado_por     uuid,
  criado_em      timestamptz not null default now(),
  atualizado_por uuid,
  atualizado_em  timestamptz not null default now(),
  check (vale_de is null or vale_ate is null or vale_ate >= vale_de),
  check (tipo = 'projeto' or (projeto is not null and campo in ('ac_tag', 'ac_lista', 'respondi_form')))
);
create unique index catalogo_regra_uidx on crm.catalogo_regra
  (tipo, campo, operador, lower(btrim(padrao)), coalesce(vale_de, '-infinity'::date), coalesce(vale_ate, 'infinity'::date)) where ativo;
comment on table crm.catalogo_regra is
  '20261007g: regras de catalogação (o que leva ao projeto). Ordem dos campos: utm_campaign, ac_lista, ac_tag, '
  'hotmart_oferta, funil, hotmart_produto, respondi_form, sck; no campo, menor prioridade, depois igual > começa > contém.';

create table crm.pessoa_origem (
  pessoa_id        uuid primary key references crm.pessoa_comercial (pessoa_id) on delete cascade,
  canal_entrada    text not null check (canal_entrada in ('hotmart', 'clint', 'activecampaign', 'whatsapp', 'sendflow',
                                                          'unnichat', 'respondi', 'manual', 'mcp', 'sistema')),
  entrou_em        timestamptz not null,
  origem_detalhe   jsonb not null default '{}'::jsonb
                   check (jsonb_typeof(origem_detalhe) = 'object' and length(origem_detalhe::text) <= 12000),
  projeto          text check (projeto is null or projeto ~ '^[a-z0-9][a-z0-9-]{1,79}$'),
  projeto_regra_id bigint references crm.catalogo_regra (id) on delete set null,
  projeto_motivo   text not null default 'sem_dado'
                   check (projeto_motivo in ('regra', 'utm', 'sck', 'funil', 'manual', 'regra_sem_projeto', 'sem_regra', 'sem_dado')),
  projeto_manual   boolean not null default false,
  linha            text,
  -- MQL: primeira evidência que uma regra 'mql' casou (tag/lista do AC); null = não é MQL
  mql_desde        timestamptz,
  mql_projeto      text check (mql_projeto is null or mql_projeto ~ '^[a-z0-9][a-z0-9-]{1,79}$'),
  mql_regra_id     bigint references crm.catalogo_regra (id) on delete set null,
  canal_dica       text,
  catalogado_em    timestamptz not null default now(),
  check ((projeto_motivo in ('regra', 'utm', 'sck', 'funil', 'manual')) = (projeto is not null)),
  check (not projeto_manual or projeto_motivo = 'manual'),
  check ((mql_desde is null) = (mql_projeto is null))
);
create index pessoa_origem_canal_idx on crm.pessoa_origem (canal_entrada);
create index pessoa_origem_projeto_idx on crm.pessoa_origem (projeto) where projeto is not null;
create index pessoa_origem_sem_projeto_idx on crm.pessoa_origem (projeto_motivo) where projeto is null;
comment on table crm.pessoa_origem is
  '20261007g: como cada contato entrou (canal, quando, detalhe) e de qual projeto (chave). Gravada por gatilho em '
  'crm.pessoa_comercial e recatalogada quando chega evidência (Hotmart, AC, negócio).';

create index if not exists hotmart_processado_pessoa_idx on crm.hotmart_processado (pessoa_id, quando) where pessoa_id is not null;

alter table crm.ac_lista enable row level security;
alter table crm.catalogo_regra enable row level security;
alter table crm.pessoa_origem enable row level security;
-- como crm.evento_jornada: RLS ligada, sem policy e sem grant para a API; só as funções (definer) leem e gravam
revoke all on crm.ac_lista, crm.catalogo_regra, crm.pessoa_origem from public, anon, authenticated, service_role;

-- ─── 2. Regras: comparação e resolução ────────────────────────────────────────────────────────────────────────────
-- texto comparável: minúsculo, sem acento, espaços colapsados. p_fim = false mantém o espaço do fim (padrão "PB "
-- de "começa com" não pode casar "PBX")
create function crm.catalogo_norm(p text, p_fim boolean default true) returns text
language sql immutable set search_path = '' as $f$
  select nullif(case when p_fim then btrim(x.t) else ltrim(x.t) end, '')
    from (select regexp_replace(translate(lower(coalesce(p, '')),
                   'áàâãäåéèêëíìîïóòôõöúùûüçñý', 'aaaaaaeeeeiiiiooooouuuucny'), '\s+', ' ', 'g') t) x;
$f$;

create function crm.catalogo_casa(p_operador text, p_padrao text, p_valor text) returns boolean
language sql immutable set search_path = '' as $f$
  select coalesce(case p_operador
           when 'igual'  then crm.catalogo_norm(p_valor) = crm.catalogo_norm(p_padrao)
           when 'comeca' then left(crm.catalogo_norm(p_valor) || ' ', length(crm.catalogo_norm(p_padrao, false))) = crm.catalogo_norm(p_padrao, false)
           when 'contem' then strpos(crm.catalogo_norm(p_valor), crm.catalogo_norm(p_padrao)) > 0
         end, false);
$f$;

-- Quem mexe nas regras de catalogação: a área de Dados (Victor Hugo). Admin/dev pelo cargo, ou função 'dados.catalogar'
-- em public.perfis.funcoes (07/10/2026: o Victor é admin, sem área de dados cadastrada). O gestor comercial NÃO edita regra:
-- só classifica contato a contato (crm_contato_origem_definir).
create function crm.pode_catalogar() returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce((
    select p.status = 'ativo' and (p.cargo in ('dev', 'admin') or 'dados.catalogar' = any(coalesce(p.funcoes, '{}')))
      from public.perfis p where p.id = (select auth.uid())
  ), false);
$f$;

-- chave já conhecida em algum cadastro: projeto do Marketing (etiqueta = chave), funil do CRM, regra ou link
create function crm.projeto_conhecido(p_chave text) returns boolean
language sql stable set search_path = '' as $f$
  select p_chave is not null and p_chave ~ '^[a-z0-9][a-z0-9-]{1,79}$' and (
       exists (select 1 from mkt.projetos mp where mp.etiqueta_clickup = p_chave)
    or exists (select 1 from crm.funil f where f.projeto = p_chave)
    or exists (select 1 from crm.catalogo_regra r where r.projeto = p_chave and r.ativo)
    or exists (select 1 from crm.link_rastreavel l where l.projeto = p_chave));
$f$;

-- nome legível da chave: cadastro do Marketing (etiqueta ou sigla), senão o funil do CRM; null = a tela mostra a chave
create function crm.projeto_nome(p_chave text) returns text
language sql stable set search_path = '' as $f$
  select coalesce(
    (select mp.nome from mkt.projetos mp where mp.etiqueta_clickup = p_chave or lower(mp.sigla) = p_chave
      order by mp.ativo desc, mp.id desc limit 1),
    (select regexp_replace(f.nome, '\s*·\s*[^·]*$', '') from crm.funil f where f.projeto = p_chave order by f.criado_em limit 1));
$f$;

-- Resolve UM evento: p_campos = {utm_campaign, ac_lista, ac_lista_nome, ac_tag, hotmart_oferta, funil, funil_projeto,
-- hotmart_produto, respondi_form, sck}. Devolve 1 linha: projeto (ou null), regra, motivo, campo e valor que decidiram.
create function crm.catalogo_resolver(p_campos jsonb, p_quando timestamptz default null)
returns table (r_projeto text, r_regra bigint, r_motivo text, r_campo text, r_valor text)
language plpgsql stable set search_path = '' as $f$
declare
  c text; v text; v_nome text; g record; v_proj text;
  v_d date := (coalesce(p_quando, now()) at time zone 'America/Sao_Paulo')::date;
  v_tinha boolean := false; s_regra bigint; s_campo text; s_valor text;
begin
  if p_campos is null or jsonb_typeof(p_campos) <> 'object' then
    return query select null::text, null::bigint, 'sem_dado'::text, null::text, null::text; return;
  end if;
  foreach c in array array['utm_campaign', 'ac_lista', 'ac_tag', 'hotmart_oferta', 'funil', 'hotmart_produto', 'respondi_form', 'sck'] loop
    v := nullif(btrim(coalesce(p_campos ->> c, '')), '');
    if c = 'ac_lista' and v = '0' then v := null; end if;   -- 0 = evento do AC sem lista
    continue when v is null;
    v_tinha := true;
    -- implícitas: utm_campaign = chave de projeto conhecida; funil com projeto; link rastreável do CRM
    if c = 'utm_campaign' and crm.projeto_conhecido(lower(v)) then
      return query select lower(v), null::bigint, 'utm'::text, c, v; return;
    end if;
    if c = 'funil' and crm.projeto_conhecido(nullif(p_campos ->> 'funil_projeto', '')) then
      return query select p_campos ->> 'funil_projeto', null::bigint, 'funil'::text, c, v; return;
    end if;
    if c = 'sck' then
      select l.projeto into v_proj from crm.link_rastreavel l where l.sck = v and l.projeto ~ '^[a-z0-9][a-z0-9-]{1,79}$';
      if v_proj is not null then return query select v_proj, null::bigint, 'sck'::text, c, v; return; end if;
    end if;
    v_nome := case when c = 'ac_lista'
                   then coalesce(nullif(btrim(coalesce(p_campos ->> 'ac_lista_nome', '')), ''), (select l.nome from crm.ac_lista l where l.id = v)) end;
    select x.id, x.projeto into g from crm.catalogo_regra x
     where x.ativo and x.campo = c
       and (x.vale_de is null or v_d >= x.vale_de) and (x.vale_ate is null or v_d <= x.vale_ate)
       and (crm.catalogo_casa(x.operador, x.padrao, v) or (v_nome is not null and crm.catalogo_casa(x.operador, x.padrao, v_nome)))
     order by x.prioridade, case x.operador when 'igual' then 0 when 'comeca' then 1 else 2 end, length(x.padrao) desc, x.id
     limit 1;
    if found then
      if g.projeto is not null then return query select g.projeto, g.id, 'regra'::text, c, v; return; end if;
      if s_regra is null then s_regra := g.id; s_campo := c; s_valor := v; end if;   -- "sem projeto": tenta o próximo campo
    end if;
  end loop;
  if s_regra is not null then return query select null::text, s_regra, 'regra_sem_projeto'::text, s_campo, s_valor; return; end if;
  return query select null::text, null::bigint, case when v_tinha then 'sem_regra' else 'sem_dado' end, null::text, null::text;
end
$f$;

-- MQL de UM evento: regra tipo 'mql' que casa a tag ou a lista (ou o formulário). Devolve a regra e o projeto.
create function crm.catalogo_mql(p_campos jsonb, p_quando timestamptz default null)
returns table (r_regra bigint, r_projeto text)
language sql stable set search_path = '' as $f$
  select x.id, x.projeto
    from crm.catalogo_regra x
    cross join lateral (select p_campos ->> x.campo v,
                               case when x.campo = 'ac_lista'
                                    then coalesce(p_campos ->> 'ac_lista_nome', (select l.nome from crm.ac_lista l where l.id = p_campos ->> 'ac_lista')) end n) c
   where x.ativo and x.tipo = 'mql' and p_campos is not null and jsonb_typeof(p_campos) = 'object'
     and nullif(nullif(btrim(coalesce(c.v, '')), ''), '0') is not null
     and (x.vale_de is null or (coalesce(p_quando, now()) at time zone 'America/Sao_Paulo')::date >= x.vale_de)
     and (x.vale_ate is null or (coalesce(p_quando, now()) at time zone 'America/Sao_Paulo')::date <= x.vale_ate)
     and (crm.catalogo_casa(x.operador, x.padrao, c.v) or (c.n is not null and crm.catalogo_casa(x.operador, x.padrao, c.n)))
   order by x.prioridade, case x.operador when 'igual' then 0 when 'comeca' then 1 else 2 end, length(x.padrao) desc, x.id
   limit 1;
$f$;

-- CONTRATO com a Ativação (20261007e): mesma assinatura e retorno. Dados de cada fonte como a 20261007e monta:
--   activecampaign {tipo, lista, tag, utm{…}, eventoId} · hotmart {classe, produtoId, ofertaCodigo, transacao, sck, chave}
--   respondi {formSlug, respostaId} · clint/crm {funil, funilProjeto, utm, sck}. Opcional em todas: quando (timestamptz).
create function crm.campos_do_evento(p_fonte text, p_dados jsonb) returns jsonb
language sql immutable set search_path = '' as $f$
  select case when p_dados is null or jsonb_typeof(p_dados) <> 'object' then null else jsonb_strip_nulls(jsonb_build_object(
    'utm_campaign', coalesce(p_dados #>> '{utm,campaign}', p_dados ->> 'utmCampaign'),
    'sck', coalesce(p_dados ->> 'sck', p_dados #>> '{utm,sck}')))
    || case p_fonte
         when 'activecampaign' then jsonb_strip_nulls(jsonb_build_object('ac_lista', p_dados ->> 'lista', 'ac_tag', p_dados ->> 'tag'))
         when 'hotmart' then jsonb_strip_nulls(jsonb_build_object(
                               'hotmart_produto', coalesce(p_dados ->> 'produtoId', p_dados ->> 'produto_id'),
                               'hotmart_oferta', coalesce(p_dados ->> 'ofertaCodigo', p_dados ->> 'oferta_codigo')))
         when 'respondi' then jsonb_strip_nulls(jsonb_build_object('respondi_form', p_dados ->> 'formSlug'))
         when 'clint' then jsonb_strip_nulls(jsonb_build_object('funil', p_dados ->> 'funil', 'funil_projeto', p_dados ->> 'funilProjeto'))
         when 'crm' then jsonb_strip_nulls(jsonb_build_object('funil', p_dados ->> 'funil', 'funil_projeto', p_dados ->> 'funilProjeto'))
         else '{}'::jsonb end end;
$f$;

create function crm.quando_do_evento(p_dados jsonb) returns timestamptz
language plpgsql stable set search_path = '' as $f$
begin
  return nullif(p_dados ->> 'quando', '')::timestamptz;
exception when others then return null;
end
$f$;

create or replace function crm.projeto_do_evento(p_fonte text, p_dados jsonb) returns text
language sql stable set search_path = '' as $f$
  select r.r_projeto from crm.catalogo_resolver(crm.campos_do_evento(p_fonte, p_dados), crm.quando_do_evento(p_dados)) r
   where r.r_motivo in ('regra', 'utm', 'sck', 'funil');
$f$;

-- CONTRATO com a Ativação: o evento conta como MQL? Só por regra 'mql' (tag/lista que o Victor cadastrou).
create or replace function crm.mql_do_evento(p_fonte text, p_dados jsonb) returns boolean
language sql stable set search_path = '' as $f$
  select exists (select 1 from crm.catalogo_mql(crm.campos_do_evento(p_fonte, p_dados), crm.quando_do_evento(p_dados)));
$f$;
comment on function crm.mql_do_evento(text, jsonb) is
  '20261007g: MQL pelas regras tipo mql de crm.catalogo_regra (ex.: tag "PB MQL"; "PB NAO MQL" não é).';

comment on function crm.projeto_do_evento(text, jsonb) is
  '20261007g: catalogação de origem (regras de crm.catalogo_regra + utm_campaign/sck/funil implícitos). Devolve a CHAVE do projeto ou null.';

-- ─── 3. Origem de um contato ──────────────────────────────────────────────────────────────────────────────────────
create function crm.origem_canal_de_dica(p text) returns text
language sql immutable set search_path = '' as $f$
  select case when p = 'clint_import' then 'clint'
              when p in ('hotmart', 'clint', 'activecampaign', 'whatsapp', 'sendflow', 'unnichat', 'respondi', 'manual', 'mcp') then p
              else 'sistema' end;
$f$;

-- canal que a sessão que está criando o contato declarou (mesma leitura de crm.tg_log)
create function crm.origem_dica() returns text
language sql stable set search_path = '' as $f$
  select coalesce(nullif(current_setting('crm.canal', true), ''),
                  case when auth.uid() is not null and (auth.jwt() ->> 'gp_canal') = 'mcp' then 'mcp' end,
                  case when auth.uid() is null then 'sistema' else 'manual' end);
$f$;

-- Recalcula a origem de UM contato (linha de crm.pessoa_origem) a partir das evidências do grupo da pessoa.
--   canal  = evidência mais antiga (empate: Clint > AC > Hotmart); sem evidência, a dica gravada na criação.
--   projeto = primeira evidência, em ordem de data, que uma regra liga a projeto (projeto_manual não é tocado).
create function crm.origem_catalogar(p_pid uuid) returns void
language plpgsql set search_path = '' as $f$
declare
  o crm.pessoa_origem%rowtype; g uuid[]; x record; r record;
  v_canal text; v_em timestamptz; v_linha text; v_det jsonb := '{}'::jsonb; v_chaves jsonb := '[]'::jsonb; k text; kv text;
  v_proj text; v_regra bigint; v_motivo text; v_veio jsonb; v_sem boolean := false; v_semregra boolean := false;
  v_pc_criado timestamptz; v_mql_em timestamptz; v_mql_proj text; v_mql_regra bigint; v_mq record;
begin
  select * into o from crm.pessoa_origem po where po.pessoa_id = p_pid for update;
  if not found then return; end if;
  select pc.criado_em into v_pc_criado from crm.pessoa_comercial pc where pc.pessoa_id = p_pid;
  g := pessoas.grupo(pessoas.atual(p_pid));
  if g is null or cardinality(g) = 0 then g := array[p_pid]; end if;

  for x in
    with ev as (
      select h.quando em, 'hotmart'::text fonte, 3 pri, pcm.linha,
             jsonb_strip_nulls(jsonb_build_object('hotmart_produto', h.produto_id, 'hotmart_oferta', h.oferta_codigo)) campos,
             jsonb_strip_nulls(jsonb_build_object('em', h.quando, 'produtoId', h.produto_id, 'produto', pcm.nome_comercial,
                                                  'ofertaCodigo', h.oferta_codigo, 'classe', h.classe, 'conta', h.conta,
                                                  'linha', pcm.linha)) resumo
        from crm.hotmart_processado h
        left join crm.produto_comercial pcm on pcm.produto_id = h.produto_id
       where h.pessoa_id = any(g) and h.quando is not null
         and coalesce(h.resultado, '') not like 'jornada: recorr%'   -- recorrência não é entrada
      union all
      select e.ocorreu_em, 'activecampaign', 2, null::text,
             jsonb_strip_nulls(jsonb_build_object('ac_lista', nullif(nullif(btrim(e.lista), ''), '0'), 'ac_lista_nome', l.nome,
                                                  'ac_tag', nullif(btrim(e.tag), ''), 'utm_campaign', e.dados #>> '{utm,campaign}')),
             jsonb_strip_nulls(jsonb_build_object('em', e.ocorreu_em, 'tipo', e.tipo, 'lista', nullif(nullif(btrim(e.lista), ''), '0'),
                                                  'listaNome', l.nome, 'tag', nullif(btrim(e.tag), ''),
                                                  'utm', case when e.dados -> 'utm' <> '{}'::jsonb then e.dados -> 'utm' end))
        from crm.evento_jornada e
        left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '')
       where e.pessoa_id = any(g) and e.fonte = 'activecampaign'
      union all
      select n.criado_em, case when cm.eh then 'clint' else 'crm' end, case when cm.eh then 1 else 4 end, f.linha,
             jsonb_strip_nulls(jsonb_build_object('funil', f.nome, 'funil_projeto', f.projeto,
                                                  'utm_campaign', n.utm ->> 'campaign', 'sck', n.utm ->> 'sck')),
             jsonb_strip_nulls(jsonb_build_object('em', n.criado_em, 'funil', f.nome, 'funilId', f.id, 'linha', f.linha,
                                                  'projetoDoFunil', f.projeto, 'origem', n.origem))
        from crm.negocio n
        join crm.funil f on f.id = n.funil_id
       cross join lateral (select exists (select 1 from arquivo.clint_mapa_funil m where m.funil_id = f.id) eh) cm
       where n.pessoa_id = any(g)
      union all
      -- a dica (canal que criou o contato) só conta como evidência quando a fonte não deixa rastro próprio
      select v_pc_criado, crm.origem_canal_de_dica(o.canal_dica), 5, null::text, '{}'::jsonb,
             jsonb_build_object('em', v_pc_criado)
       where crm.origem_canal_de_dica(o.canal_dica) not in ('hotmart', 'clint', 'activecampaign', 'sistema')
    )
    select * from ev order by ev.em, ev.pri
  loop
    -- canal de entrada: a evidência mais antiga (negócio criado no CRM não é canal: é o que veio depois)
    if v_canal is null and x.fonte <> 'crm' then
      v_canal := x.fonte; v_em := x.em; v_linha := x.linha;
    end if;
    if v_linha is null and x.linha is not null then v_linha := x.linha; end if;
    -- resumo por fonte: a primeira; no AC, a primeira com lista ou tag (a 1ª qualquer fica em primeiraEm)
    if not v_det ? x.fonte then
      v_det := v_det || jsonb_build_object(x.fonte, x.resumo || jsonb_build_object('primeiraEm', x.em));
    elsif x.fonte = 'activecampaign' and not (v_det -> 'activecampaign' ? 'lista' or v_det -> 'activecampaign' ? 'tag')
          and (x.resumo ? 'lista' or x.resumo ? 'tag') then
      v_det := jsonb_set(v_det, '{activecampaign}', x.resumo || jsonb_build_object('primeiraEm', v_det #> '{activecampaign,primeiraEm}'));
    end if;
    -- todas as chaves vistas (para a tela "sem projeto"); até 40
    for k, kv in select j.key, j.value #>> '{}' from jsonb_each(x.campos) j where j.key not in ('funil_projeto', 'ac_lista_nome') loop
      if jsonb_array_length(v_chaves) < 40 and not v_chaves @> jsonb_build_array(jsonb_build_object('campo', k, 'valor', kv)) then
        v_chaves := v_chaves || jsonb_build_array(jsonb_build_object('campo', k, 'valor', kv));
      end if;
    end loop;
    -- MQL: a primeira evidência que uma regra 'mql' casa
    if v_mql_em is null and x.campos <> '{}'::jsonb then
      select * into v_mq from crm.catalogo_mql(x.campos, x.em);
      if v_mq.r_regra is not null then v_mql_em := x.em; v_mql_proj := v_mq.r_projeto; v_mql_regra := v_mq.r_regra; end if;
    end if;
    -- projeto: a primeira evidência que resolve
    if v_proj is null and x.campos <> '{}'::jsonb then
      select * into r from crm.catalogo_resolver(x.campos, x.em);
      if r.r_motivo in ('regra', 'utm', 'sck', 'funil') then
        v_proj := r.r_projeto; v_regra := r.r_regra; v_motivo := r.r_motivo;
        v_veio := jsonb_build_object('fonte', x.fonte, 'campo', r.r_campo, 'valor', r.r_valor, 'em', x.em);
      elsif r.r_motivo = 'regra_sem_projeto' then v_sem := true; if v_regra is null then v_regra := r.r_regra; end if;
      elsif r.r_motivo = 'sem_regra' then v_semregra := true;
      end if;
    end if;
  end loop;

  if v_canal is null then
    v_canal := crm.origem_canal_de_dica(o.canal_dica); v_em := coalesce(v_pc_criado, o.entrou_em);
  end if;
  if v_proj is null then
    v_motivo := case when v_sem then 'regra_sem_projeto' when v_semregra then 'sem_regra' else 'sem_dado' end;
  end if;
  v_det := v_det || jsonb_build_object('chaves', v_chaves) || case when v_veio is not null then jsonb_build_object('projetoVeioDe', v_veio) else '{}'::jsonb end;

  update crm.pessoa_origem po
     set canal_entrada = v_canal, entrou_em = v_em, origem_detalhe = v_det, linha = v_linha, catalogado_em = now(),
         projeto = case when po.projeto_manual then po.projeto else v_proj end,
         projeto_motivo = case when po.projeto_manual then 'manual' else v_motivo end,
         projeto_regra_id = case when po.projeto_manual then null else v_regra end,
         mql_desde = v_mql_em, mql_projeto = v_mql_proj, mql_regra_id = v_mql_regra
   where po.pessoa_id = p_pid
     and (po.canal_entrada, po.entrou_em, po.origem_detalhe, po.linha, po.mql_desde, po.mql_projeto, po.mql_regra_id,
          po.projeto, po.projeto_motivo, po.projeto_regra_id)
         is distinct from
         (v_canal, v_em, v_det, v_linha, v_mql_em, v_mql_proj, v_mql_regra,
          case when po.projeto_manual then po.projeto else v_proj end,
          case when po.projeto_manual then 'manual' else v_motivo end,
          case when po.projeto_manual then null else v_regra end);
end
$f$;

-- recataloga os contatos do grupo da pessoa (evidência nova chegou)
create function crm.origem_recatalogar_pessoa(p uuid) returns void
language plpgsql set search_path = '' as $f$
declare v uuid;
begin
  if p is null then return; end if;
  for v in select po.pessoa_id from crm.pessoa_origem po where po.pessoa_id = any(pessoas.grupo(pessoas.atual(p))) loop
    perform crm.origem_catalogar(v);
  end loop;
end
$f$;

-- ─── 4. Gatilhos (nunca derrubam a gravação principal) ────────────────────────────────────────────────────────────
create function crm.tg_origem_pc() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_dica text;
begin
  begin
    v_dica := crm.origem_dica();
    insert into crm.pessoa_origem (pessoa_id, canal_entrada, entrou_em, canal_dica)
    values (new.pessoa_id, crm.origem_canal_de_dica(v_dica), coalesce(new.criado_em, now()), left(v_dica, 40))
    on conflict (pessoa_id) do nothing;
    perform crm.origem_catalogar(new.pessoa_id);
  exception when others then
    raise warning 'crm.tg_origem_pc: % (%: %)', new.pessoa_id, sqlstate, sqlerrm;
  end;
  return null;
end
$f$;

create function crm.tg_origem_evidencia() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  begin
    perform crm.origem_recatalogar_pessoa(new.pessoa_id);
  exception when others then
    raise warning 'crm.tg_origem_evidencia (%): % (%: %)', tg_table_name, new.pessoa_id, sqlstate, sqlerrm;
  end;
  return null;
end
$f$;

create trigger zz_origem_ins after insert on crm.pessoa_comercial for each row execute function crm.tg_origem_pc();
create trigger zz_origem_hotmart_ins after insert on crm.hotmart_processado for each row
  when (new.pessoa_id is not null) execute function crm.tg_origem_evidencia();
create trigger zz_origem_hotmart_upd after update on crm.hotmart_processado for each row
  when (old.pessoa_id is distinct from new.pessoa_id and new.pessoa_id is not null) execute function crm.tg_origem_evidencia();
create trigger zz_origem_ac_ins after insert on crm.evento_jornada for each row
  when (new.pessoa_id is not null and new.fonte = 'activecampaign') execute function crm.tg_origem_evidencia();
create trigger zz_origem_ac_upd after update on crm.evento_jornada for each row
  when (old.pessoa_id is distinct from new.pessoa_id and new.pessoa_id is not null and new.fonte = 'activecampaign')
  execute function crm.tg_origem_evidencia();
create trigger zz_origem_negocio after insert on crm.negocio for each row
  when (new.pessoa_id is not null) execute function crm.tg_origem_evidencia();

-- ─── 5. Lista de contatos: origem no item, filtro por canal/projeto, números no resumo ───────────────────────────
-- crm.contatos_itens: corpo VIVO (md5 c7c17a0c…) + 'origem' (left join; contato sem linha de origem = null)
create or replace function crm.contatos_itens(p_pids uuid[], p_metricas boolean)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_meus uuid[]; v_atuais uuid[]; v jsonb;
begin
  if not coalesce(crm.eh_comercial(), false) or p_pids is null or cardinality(p_pids) = 0 then return '[]'::jsonb; end if;
  v_meus := case when v_gestor then '{}'::uuid[] else array(select crm.pessoas_negocio_meu()) end;
  v_atuais := array(select distinct case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end
                      from unnest(p_pids) u join pessoas.pessoas pp on pp.id = u);
  select coalesce(jsonb_agg(x.j order by x.o), '[]'::jsonb) into v from (
    select u.o, jsonb_build_object(
             'id', a.atual, 'nome', coalesce(d.d_nome, '(sem nome)'),
             'email', case when c.completo then d.d_email else pessoas.mascara_email(d.d_email) end,
             'telefone', case when c.completo then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,
             'cidade', coalesce(al.cidade, cp.endereco_cidade::text),
             'uf', case when upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) ~ '^[A-Z]{2}$'
                        then upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) end,
             'perfil', pc.perfil, 'atuaComHolding', pc.atua_com_holding, 'donoId', pc.dono_id, 'tags', to_jsonb(pc.tags),
             'utm', jsonb_build_object('source', pc.utm_primeira->>'source', 'medium', pc.utm_primeira->>'medium',
                                       'campaign', pc.utm_primeira->>'campaign', 'content', pc.utm_primeira->>'content',
                                       'sck', pc.utm_primeira->>'sck'),
             'score', pc.score, 'ehAluno', d.d_aluno_id is not null, 'optOut', pc.opt_out, 'criadoEm', pc.criado_em,
             -- 20261007g: como entrou
             'origem', case when po.pessoa_id is null then null
                            else jsonb_build_object('canal', po.canal_entrada, 'entrouEm', po.entrou_em, 'projeto', po.projeto,
                                                    'projetoNome', crm.projeto_nome(po.projeto), 'linha', po.linha,
                                                    'mqlDesde', po.mql_desde) end)
           || case when p_metricas
                   then jsonb_build_object('lancamentos', coalesce(m.m_lancamentos, 0), 'ultimaInteracaoEm', m.m_ultima,
                                           'abertos', coalesce(m.m_abertos, '[]'::jsonb))
                   else '{}'::jsonb end j
      from unnest(p_pids) with ordinality u(pid, o)
      join crm.pessoa_comercial pc on pc.pessoa_id = u.pid
      join pessoas.pessoas pp on pp.id = pc.pessoa_id
      left join crm.pessoa_origem po on po.pessoa_id = pc.pessoa_id
     cross join lateral (select case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end atual) a
     cross join lateral (select coalesce(v_gestor or pc.dono_id = v_eu or pc.pessoa_id = any(v_meus), false) completo) c
      left join crm.dados_lote(v_atuais) d on d.d_pessoa = a.atual
      left join public.thb_alunos al on al.id = d.d_aluno_id
      left join public.compradores cp on cp.id = d.d_comprador_id
      left join crm.contatos_metricas(case when p_metricas then v_atuais else '{}'::uuid[] end) m on m.m_id = a.atual
  ) x;
  return v;
end
$function$;

-- crm_contatos_pagina: corpo VIVO (md5 f2fded79…) + p_canal e p_projeto no fim (assinatura muda: drop + create).
-- Chamadas antigas (sem os 2 parâmetros) continuam valendo pelos defaults.
drop function public.crm_contatos_pagina(text, text, text, text, text[], boolean, boolean, text, text, integer, integer);
create function public.crm_contatos_pagina(p_busca text DEFAULT NULL::text, p_dono text DEFAULT NULL::text, p_perfil text DEFAULT NULL::text, p_uf text DEFAULT NULL::text, p_tags text[] DEFAULT NULL::text[], p_opt_out boolean DEFAULT false, p_so_alunos boolean DEFAULT false, p_ordem text DEFAULT 'criado'::text, p_dir text DEFAULT 'desc'::text, p_limite integer DEFAULT 50, p_offset integer DEFAULT 0, p_canal text DEFAULT NULL::text, p_projeto text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lim int := least(greatest(coalesce(p_limite, 50), 1), 200);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_t text := nullif(btrim(coalesce(p_busca, '')), '');
  v_ordem text := coalesce(nullif(btrim(coalesce(p_ordem, '')), ''), 'criado');
  v_dir text := lower(coalesce(nullif(btrim(coalesce(p_dir, '')), ''), 'desc'));
  v_dono text := nullif(nullif(btrim(coalesce(p_dono, '')), ''), 'todos');
  v_perfil text := nullif(nullif(btrim(coalesce(p_perfil, '')), ''), 'todos');
  v_uf text := nullif(nullif(upper(btrim(coalesce(p_uf, ''))), ''), 'TODAS');
  v_canal text := nullif(nullif(lower(btrim(coalesce(p_canal, ''))), ''), 'todos');
  v_projeto text := nullif(nullif(lower(btrim(coalesce(p_projeto, ''))), ''), 'todos');
  v_asc boolean; v_dono_id uuid; v_ids uuid[]; v_total int; v_pids uuid[]; v_com_dados boolean;
begin
  perform crm.exige_comercial();
  if v_ordem not in ('criado', 'nome', 'dono', 'negocios', 'lancamentos', 'ultima') then
    raise exception 'Ordem inválida.' using errcode = '22023';
  end if;
  if v_dir not in ('asc', 'desc') then raise exception 'Direção inválida.' using errcode = '22023'; end if;
  if v_canal is not null and v_canal not in ('hotmart', 'clint', 'activecampaign', 'whatsapp', 'sendflow', 'unnichat', 'respondi', 'manual', 'mcp', 'sistema') then
    raise exception 'Canal inválido.' using errcode = '22023';
  end if;
  if v_projeto is not null and v_projeto <> 'sem' and v_projeto !~ '^[a-z0-9][a-z0-9-]{1,79}$' then
    raise exception 'Projeto inválido.' using errcode = '22023';
  end if;
  v_asc := v_dir = 'asc';
  -- nome/aluno/UF de toda a lista só quando a ordem ou o filtro precisa (ordem por criação: só a página)
  v_com_dados := v_ordem <> 'criado';
  if v_dono is not null and v_dono <> 'sem_dono' then
    begin
      v_dono_id := v_dono::uuid;
    exception when invalid_text_representation then
      raise exception 'Dono inválido.' using errcode = '22023';
    end;
  end if;
  if v_t is not null then
    if length(v_t) < 3 then return jsonb_build_object('itens', '[]'::jsonb, 'total', 0); end if;
    v_ids := crm.contatos_candidatos(v_t);
  end if;

  if v_ordem in ('negocios', 'lancamentos', 'ultima') then
    -- ordem por métrica: calcula as métricas de todos os que passam no filtro (em lote) e pagina
    with b as (select b0.* from crm.contatos_base(v_ids, v_dono = 'sem_dono', v_dono_id, v_perfil, v_uf, p_tags, p_opt_out, p_so_alunos, v_com_dados) b0
                 left join crm.pessoa_origem po on po.pessoa_id = b0.b_pid
                where (v_canal is null or po.canal_entrada = v_canal)
                  and (v_projeto is null or (v_projeto = 'sem' and po.projeto is null) or po.projeto = v_projeto)),
    m as (select * from crm.contatos_metricas(array(select distinct b.b_atual from b)))
    select count(*)::int,
           (array_agg(b.b_pid order by
              case when v_asc then k.chave end asc nulls last,
              case when not v_asc then k.chave end desc nulls last,
              b.b_nome collate "pt-BR-x-icu", b.b_pid))[v_off + 1 : v_off + v_lim]
      into v_total, v_pids
      from b
      left join m on m.m_id = b.b_atual
     cross join lateral (select case v_ordem when 'negocios' then coalesce(m.m_qtd_abertos, 0)::numeric
                                             when 'lancamentos' then coalesce(m.m_lancamentos, 0)::numeric
                                             else extract(epoch from m.m_ultima)::numeric end chave) k;
  else
    select count(*)::int,
           (array_agg(b.b_pid order by
              case when v_ordem = 'criado' and v_asc then b.b_criado end asc,
              case when v_ordem = 'criado' and not v_asc then b.b_criado end desc,
              case when v_ordem = 'nome' and v_asc then b.b_nome end collate "pt-BR-x-icu" asc,
              case when v_ordem = 'nome' and not v_asc then b.b_nome end collate "pt-BR-x-icu" desc,
              case when v_ordem = 'dono' and v_asc then b.b_dono end collate "pt-BR-x-icu" asc,
              case when v_ordem = 'dono' and not v_asc then b.b_dono end collate "pt-BR-x-icu" desc,
              case when v_ordem = 'criado' then b.b_pid end,
              b.b_nome collate "pt-BR-x-icu", b.b_pid))[v_off + 1 : v_off + v_lim]
      into v_total, v_pids
      from crm.contatos_base(v_ids, v_dono = 'sem_dono', v_dono_id, v_perfil, v_uf, p_tags, p_opt_out, p_so_alunos, v_com_dados) b
      left join crm.pessoa_origem po on po.pessoa_id = b.b_pid
     where (v_canal is null or po.canal_entrada = v_canal)
       and (v_projeto is null or (v_projeto = 'sem' and po.projeto is null) or po.projeto = v_projeto);
  end if;

  return jsonb_build_object('itens', crm.contatos_itens(coalesce(v_pids, '{}'::uuid[]), true), 'total', coalesce(v_total, 0));
end
$function$;

-- crm_contatos_resumo: corpo VIVO (md5 5637d27b…) + canais, projetos e semProjeto (mesma visibilidade da lista)
create or replace function public.crm_contatos_resumo()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  perform crm.exige_comercial();
  with b as (select b0.*, po.canal_entrada o_canal, po.projeto o_projeto
               from crm.contatos_base(null, false, null, null, null, null, false, false, true) b0
               left join crm.pessoa_origem po on po.pessoa_id = b0.b_pid)
  select jsonb_build_object(
           'total', count(*), 'semDono', count(*) filter (where b.b_dono_nulo),
           'optOut', count(*) filter (where b.b_opt_out), 'alunos', count(*) filter (where b.b_aluno),
           'ufs', coalesce((select jsonb_agg(s.uf order by s.uf) from (select distinct b2.b_uf uf from b b2 where b2.b_uf is not null) s), '[]'::jsonb),
           'tags', coalesce((select jsonb_agg(s.t order by s.t collate "pt-BR-x-icu")
                               from (select distinct t from b b3, unnest(b3.b_tags) t where t is not null and t <> '') s), '[]'::jsonb),
           'canais', coalesce((select jsonb_agg(jsonb_build_object('canal', s.c, 'total', s.n) order by s.n desc, s.c)
                                 from (select coalesce(b4.o_canal, 'sistema') c, count(*) n from b b4 group by 1) s), '[]'::jsonb),
           'projetos', coalesce((select jsonb_agg(jsonb_build_object('chave', s.p, 'nome', crm.projeto_nome(s.p), 'total', s.n) order by s.n desc, s.p)
                                   from (select b5.o_projeto p, count(*) n from b b5 where b5.o_projeto is not null group by 1) s), '[]'::jsonb),
           'semProjeto', count(*) filter (where b.o_projeto is null))
    into v
    from b;
  return v;
end
$function$;

-- ─── 6. RPCs da catalogação ───────────────────────────────────────────────────────────────────────────────────────
-- Tela do Configurações: regras, listas do AC, projetos conhecidos, números e pendências (valores sem regra).
create function public.crm_catalogo() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb;
begin
  if not (coalesce(crm.eh_comercial(), false) or coalesce(crm.pode_catalogar(), false)) then
    raise exception 'Sem acesso ao Comercial.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    -- regras: só Dados (Victor) / admin / dev. Classificar contato a contato: também o gestor comercial
    'podeEditar', coalesce(crm.pode_catalogar(), false),
    'podeClassificar', coalesce(crm.pode_catalogar(), false) or coalesce(crm.eh_gestor(), false),
    'regras', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', r.id, 'tipo', r.tipo, 'campo', r.campo, 'operador', r.operador, 'padrao', r.padrao, 'projeto', r.projeto,
                 'projetoNome', crm.projeto_nome(r.projeto), 'valeDe', r.vale_de, 'valeAte', r.vale_ate,
                 'prioridade', r.prioridade, 'ativo', r.ativo, 'nota', r.nota, 'atualizadoEm', r.atualizado_em,
                 'contatos', (select count(*) from crm.pessoa_origem po where po.projeto_regra_id = r.id))
               order by r.ativo desc, r.campo, r.prioridade, r.padrao) from crm.catalogo_regra r), '[]'::jsonb),
    'listasAc', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'nome', l.nome) order by l.id::bigint desc)
                            from crm.ac_lista l), '[]'::jsonb),
    'projetos', coalesce((select jsonb_agg(jsonb_build_object('chave', s.chave, 'nome', crm.projeto_nome(s.chave),
                                                              'contatos', (select count(*) from crm.pessoa_origem po where po.projeto = s.chave))
                                           order by s.chave)
                            from (select mp.etiqueta_clickup chave from mkt.projetos mp where mp.etiqueta_clickup ~ '^[a-z0-9][a-z0-9-]{1,79}$'
                                  union select f.projeto from crm.funil f where f.projeto ~ '^[a-z0-9][a-z0-9-]{1,79}$'
                                  union select r.projeto from crm.catalogo_regra r where r.projeto is not null
                                  union select po.projeto from crm.pessoa_origem po where po.projeto is not null) s), '[]'::jsonb),
    'resumo', (select jsonb_build_object(
                 'total', count(*), 'comProjeto', count(*) filter (where po.projeto is not null),
                 'mql', count(*) filter (where po.mql_desde is not null),
                 'produtoSemProjeto', count(*) filter (where po.projeto is null and po.linha is not null),
                 'semNada', count(*) filter (where po.projeto is null and po.linha is null),
                 'motivos', jsonb_build_object(
                    'regra_sem_projeto', count(*) filter (where po.projeto_motivo = 'regra_sem_projeto'),
                    'sem_regra', count(*) filter (where po.projeto_motivo = 'sem_regra'),
                    'sem_dado', count(*) filter (where po.projeto_motivo = 'sem_dado')),
                 'porCanal', coalesce((select jsonb_agg(jsonb_build_object('canal', s.c, 'total', s.n, 'comProjeto', s.cp) order by s.n desc)
                                         from (select po2.canal_entrada c, count(*) n, count(*) filter (where po2.projeto is not null) cp
                                                 from crm.pessoa_origem po2 group by 1) s), '[]'::jsonb),
                 'semProjetoPorLinha', coalesce((select jsonb_agg(jsonb_build_object('linha', s.l, 'total', s.n) order by s.n desc)
                                                   from (select coalesce(po3.linha, '-') l, count(*) n from crm.pessoa_origem po3
                                                          where po3.projeto is null group by 1) s), '[]'::jsonb))
                 from crm.pessoa_origem po),
    'pendencias', coalesce((select jsonb_agg(jsonb_build_object('campo', s.campo, 'valor', s.valor, 'contatos', s.n,
                              'nome', case s.campo when 'ac_lista' then (select l.nome from crm.ac_lista l where l.id = s.valor)
                                                   when 'hotmart_produto' then (select pcm.nome_comercial from crm.produto_comercial pcm where pcm.produto_id = s.valor)
                                      end) order by s.n desc, s.campo, s.valor)
                              from (select x ->> 'campo' campo, x ->> 'valor' valor, count(distinct po.pessoa_id) n
                                      from crm.pessoa_origem po, jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) x
                                     where po.projeto is null and not po.projeto_manual and po.projeto_motivo = 'sem_regra'
                                     group by 1, 2 order by 3 desc limit 150) s), '[]'::jsonb))
    into v;
  return v;
end
$f$;

-- Cria/edita regra (id vazio = nova). Desativar = ativo false (nada se apaga). Só o gestor.
create function public.crm_catalogo_regra_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_r jsonb; v_id bigint; v_campo text := btrim(coalesce(p ->> 'campo', '')); v_op text := coalesce(nullif(btrim(coalesce(p ->> 'operador', '')), ''), 'igual');
  v_padrao text := btrim(coalesce(p ->> 'padrao', '')); v_proj text := nullif(lower(btrim(coalesce(p ->> 'projeto', ''))), '');
  v_tipo text := coalesce(nullif(btrim(coalesce(p ->> 'tipo', '')), ''), 'projeto'); v_s text; v_c text; v_m text;
begin
  perform set_config('crm.resumo', '', true);
  if not coalesce((select c.escrita_ligada from crm.config c), false) then return crm.res(false, 'CRM em manutenção: escrita desligada.'); end if;
  if not coalesce(crm.pode_catalogar(), false) then
    return crm.res(false, 'As regras de catalogação são da área de Dados (Victor Hugo). Peça a ele.');
  end if;
  if jsonb_typeof(p) is distinct from 'object' then return crm.res(false, 'Regra inválida.'); end if;
  if v_campo not in ('utm_campaign', 'ac_lista', 'ac_tag', 'hotmart_oferta', 'funil', 'hotmart_produto', 'respondi_form', 'sck') then
    return crm.res(false, 'Escolha o campo da regra.');
  end if;
  if v_op not in ('igual', 'comeca', 'contem') then return crm.res(false, 'Operador inválido.'); end if;
  if v_tipo not in ('projeto', 'mql') then return crm.res(false, 'Tipo de regra inválido.'); end if;
  if v_tipo = 'mql' and (v_proj is null or v_campo not in ('ac_tag', 'ac_lista', 'respondi_form')) then
    return crm.res(false, 'Regra de MQL: tag ou lista do AC (ou formulário) e o projeto.');
  end if;
  if v_padrao = '' then return crm.res(false, 'Escreva o valor ou o pedaço do nome.'); end if;
  if v_proj is not null and v_proj !~ '^[a-z0-9][a-z0-9-]{1,79}$' then
    return crm.res(false, 'Chave do projeto inválida: minúsculas, números e hífen (ex.: seminario-conjunto-2026-11).');
  end if;
  v_id := nullif(p ->> 'id', '')::bigint;
  if v_id is null then
    insert into crm.catalogo_regra (tipo, campo, operador, padrao, projeto, vale_de, vale_ate, prioridade, ativo, nota, criado_por, atualizado_por)
    values (v_tipo, v_campo, v_op, v_padrao, v_proj, nullif(p ->> 'valeDe', '')::date, nullif(p ->> 'valeAte', '')::date,
            coalesce(nullif(p ->> 'prioridade', '')::smallint, 100), coalesce((p ->> 'ativo')::boolean, true),
            nullif(btrim(coalesce(p ->> 'nota', '')), ''), auth.uid(), auth.uid())
    returning id into v_id;
    return crm.res(true, 'Regra criada.', jsonb_build_object('id', v_id));
  end if;
  update crm.catalogo_regra r
     set tipo = v_tipo, campo = v_campo, operador = v_op, padrao = v_padrao, projeto = v_proj,
         vale_de = nullif(p ->> 'valeDe', '')::date, vale_ate = nullif(p ->> 'valeAte', '')::date,
         prioridade = coalesce(nullif(p ->> 'prioridade', '')::smallint, r.prioridade), ativo = coalesce((p ->> 'ativo')::boolean, r.ativo),
         nota = nullif(btrim(coalesce(p ->> 'nota', '')), ''), atualizado_por = auth.uid(), atualizado_em = now()
   where r.id = v_id;
  if not found then return crm.res(false, 'Regra não encontrada.'); end if;
  return crm.res(true, 'Regra atualizada.', jsonb_build_object('id', v_id));
exception when check_violation or unique_violation or not_null_violation or invalid_text_representation
             or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range
             or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  if v_s = '23505' then return crm.res(false, 'Já existe uma regra ativa igual (tipo, campo, operador, valor e datas).'); end if;
  return crm.erro_dados(v_s, v_m, v_c);
end
$f$;

-- Nome de lista do AC (o webhook só manda o id). Só o gestor.
create function public.crm_catalogo_lista_salvar(p_id text, p_nome text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r jsonb; v_id text := btrim(coalesce(p_id, '')); v_nome text := btrim(coalesce(p_nome, ''));
begin
  perform set_config('crm.resumo', '', true);
  if not coalesce((select c.escrita_ligada from crm.config c), false) then return crm.res(false, 'CRM em manutenção: escrita desligada.'); end if;
  if not coalesce(crm.pode_catalogar(), false) then
    return crm.res(false, 'As regras de catalogação são da área de Dados (Victor Hugo). Peça a ele.');
  end if;
  if v_id !~ '^[0-9]{1,10}$' then return crm.res(false, 'Id da lista inválido (só números).'); end if;
  if v_nome = '' or length(v_nome) > 200 then return crm.res(false, 'Escreva o nome da lista (até 200 letras).'); end if;
  insert into crm.ac_lista (id, nome, atualizado_por) values (v_id, v_nome, auth.uid())
  on conflict (id) do update set nome = excluded.nome, atualizado_em = now(), atualizado_por = excluded.atualizado_por;
  return crm.res(true, 'Lista salva.');
end
$f$;

-- Reaplica as regras: sem projeto (padrão) ou todos (p_todos). Projeto definido à mão não muda. Só o gestor.
create function public.crm_catalogo_reaplicar(p_todos boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r jsonb; v uuid; v_n int := 0; v_antes int; v_depois int;
begin
  perform set_config('crm.resumo', '', true);
  if not coalesce((select c.escrita_ligada from crm.config c), false) then return crm.res(false, 'CRM em manutenção: escrita desligada.'); end if;
  -- sem projeto: gestor comercial ou Dados; todos: só Dados (refaz o que já estava catalogado)
  if not (coalesce(crm.pode_catalogar(), false) or (not coalesce(p_todos, false) and coalesce(crm.eh_gestor(), false))) then
    return crm.res(false, 'Sem permissão para reaplicar as regras.');
  end if;
  select count(*) into v_antes from crm.pessoa_origem where projeto is not null;
  for v in select po.pessoa_id from crm.pessoa_origem po
            where (coalesce(p_todos, false) or po.projeto is null) and not po.projeto_manual loop
    perform crm.origem_catalogar(v);
    v_n := v_n + 1;
  end loop;
  select count(*) into v_depois from crm.pessoa_origem where projeto is not null;
  return crm.res(true, format('%s contatos recatalogados; com projeto: %s → %s.', v_n, v_antes, v_depois),
                 jsonb_build_object('catalogados', v_n, 'comProjetoAntes', v_antes, 'comProjetoDepois', v_depois));
end
$f$;

-- "Como entrou" da ficha. Mesma visibilidade da ficha (crm.pode_ver_pessoa).
create function public.crm_contato_origem(p_pessoa uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare po crm.pessoa_origem%rowtype; g crm.catalogo_regra%rowtype; v_atual uuid;
begin
  perform crm.exige_comercial();
  if not coalesce(crm.pode_ver_pessoa(p_pessoa), false) then
    raise exception 'Sem acesso a este contato.' using errcode = '42501';
  end if;
  v_atual := pessoas.atual(p_pessoa);
  select * into po from crm.pessoa_origem x where x.pessoa_id = any(pessoas.grupo(v_atual))
   order by x.pessoa_id = v_atual desc, x.entrou_em limit 1;
  if not found then return null; end if;
  if po.projeto_regra_id is not null then select * into g from crm.catalogo_regra r where r.id = po.projeto_regra_id; end if;
  return jsonb_build_object(
    'canal', po.canal_entrada, 'entrouEm', po.entrou_em, 'projeto', po.projeto, 'projetoNome', crm.projeto_nome(po.projeto),
    'motivo', po.projeto_motivo, 'manual', po.projeto_manual, 'linha', po.linha, 'detalhe', po.origem_detalhe - 'chaves',
    'mqlDesde', po.mql_desde, 'mqlProjeto', po.mql_projeto, 'mqlProjetoNome', crm.projeto_nome(po.mql_projeto),
    'regra', case when g.id is null then null
                  else jsonb_build_object('id', g.id, 'campo', g.campo, 'operador', g.operador, 'padrao', g.padrao) end,
    'podeDefinir', coalesce(crm.eh_gestor(), false) or coalesce(crm.pode_catalogar(), false));
end
$f$;

-- Gestor define o projeto de um contato à mão (vale sobre as regras); vazio = volta para as regras.
create function public.crm_contato_origem_definir(p_pessoa uuid, p_projeto text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r jsonb; v_proj text := nullif(lower(btrim(coalesce(p_projeto, ''))), ''); v_pid uuid; v_atual uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not (coalesce(crm.eh_gestor(), false) or coalesce(crm.pode_catalogar(), false)) then
    return crm.res(false, 'Só o gestor (ou a área de Dados) define o projeto do contato.');
  end if;
  if v_proj is not null and v_proj !~ '^[a-z0-9][a-z0-9-]{1,79}$' then return crm.res(false, 'Chave do projeto inválida.'); end if;
  v_atual := pessoas.atual(p_pessoa);
  select x.pessoa_id into v_pid from crm.pessoa_origem x where x.pessoa_id = any(pessoas.grupo(v_atual))
   order by x.pessoa_id = v_atual desc, x.entrou_em limit 1;
  if v_pid is null then return crm.res(false, 'Contato sem origem registrada.'); end if;
  if v_proj is null then
    update crm.pessoa_origem set projeto_manual = false, projeto = null, projeto_motivo = 'sem_dado', projeto_regra_id = null
     where pessoa_id = v_pid;
    perform crm.origem_catalogar(v_pid);
    return crm.res(true, 'Projeto volta a seguir as regras.');
  end if;
  update crm.pessoa_origem set projeto_manual = true, projeto = v_proj, projeto_motivo = 'manual', projeto_regra_id = null,
                               catalogado_em = now()
   where pessoa_id = v_pid;
  return crm.res(true, 'Projeto do contato definido.');
end
$f$;

-- ─── 7. Sementes ──────────────────────────────────────────────────────────────────────────────────────────────────
-- 7a. Listas do ActiveCampaign (GET /api/3/lists, só leitura, 07/10/2026: 157 listas; só id e nome)
insert into crm.ac_lista (id, nome) values
('403','Holding Total'), ('408','Aurum'), ('409','Holding Masters'), ('410','Encontro Time Holding Brasil'),
('412','Sessão de Viabilidade'), ('424','Seminário de Planejamento Patrimonial Familiar'),
('425','Segredos Holding Familiar'), ('426','Holding +'), ('429','Outros leads'), ('435','Pró Aurum'),
('436','Jornada Holding Familiar'), ('441','Lista de Espera - Nivel Ouro'),
('442','Curso Online de Holding Familiar'), ('445','01 - [PDF] Lead'), ('447','Newsletter'),
('448','Clínica de Holding Familiar'), ('450','Holding Total Sócio'), ('452','Porta de entrada'),
('453','Holding PRO Acelerado'), ('454','Máquina da Sessão de Viabilidade'),
('455','Congresso do Time Holding Brasil'), ('456','[ELAINE] Seminário de PPF'),
('457','Webinário Holding Total'), ('458','PRO AURUM AGOSTO 2025'), ('459','Residência em Holding Familiar'),
('460','Alunos'), ('461','Black Friday 2025'), ('462','Holding Total Jan/26'),
('463','Reunião de Empresários'), ('464','[SEMINÁRIO] Marcio'), ('465','Holding Total Fev/26'),
('466','[HT 19] LEADS'), ('467','Holding Total Mar/26'), ('469','Clínica de Holding Familiar 2026 - Goiânia'),
('470','Holding Masters - T38'), ('471','Holding Total Abr/26'),
('472','Seminário de Planejamento Patrimonial - Elaine - Abril/26'), ('473','Base Holding'),
('474','[HT 21] [TEMPORÁRIA] Comunicado sobre novo formato'), ('475','IMERSÃO EM HOLDING FAMILIAR'),
('476','IMERSÃO EM HOLDING FAMILIAR - abr/26'), ('477','[AG] Aula Gratuita - Elaine ABR/26'),
('479','[HT] ATIVACÃO NOVA DATA'), ('480','IMERSÃO EM HOLDING FAMILIAR - abr/26 - Leads Holding Masters'),
('481','Clínica de Holding Familiar 2026 - Leads AURUM'), ('482','20H'),
('484','Imersão em Holding Familiar Jun/26'), ('485','Clínica de Holding Familiar Jun/26'),
('486','Sessão de Viabilidade - Abr 2026'), ('487','Encontro do Time Holding Brasil Agosto - São Paulo'),
('490','[SEM-ABRL26]zoom_fechado_principal'), ('491','teste mp'),
('492','Base 1: Clicou ou abriu e-mail nos últimos meses'),
('493','Base 2: Compradores antigos do Holding Total que não compraram o Holding Masters'),
('494','Base 3: Leads de páginas e eventos anteriores'), ('495','RECUPERAÇÃO - HT'),
('496','Seminário de Planejamento Patrimonial - Elaine Montenegro - Junho de 2026'),
('502','[HOLDING MASTERS] IMERSÃO PORTO ALEGRE'),
('503','Encontro do Time Holding Brasil Agosto - São Paulo - Programa de indicação'),
('504','Sessão de Viabilidade - JUN26'),
('505','Seminário de Planejamento Patrimonial - Dra. Elaine - Julho de 2026'), ('506','Implementação HM'),
('507','Base 0: ALUNOS HM'), ('508','Base 2: Holding Total (não comprou HM)'),
('509','Live Direto ao Ponto - Seminário Julho 2026'),
('510','Encontro do Time Holding Brasil Agosto - São Paulo - Aberto Ao Público Externo'),
('512','ATM - Marcio'), ('513','ATM - Elaine'), ('514','HT-ATM'), ('515','Ex alunos - HT'),
('516','HT ATM - LEADS'), ('524','SEM JUL26 - 030726'), ('525','SEM JUL26 - 030726'),
('526','SEM JUL26 - 030726'), ('527','SEM JUL26 - 030726'), ('532','[ LDP - MARCIO ] 13/07/2026'),
('533','ATM - Marcio - 13/07'), ('534','EX ALUNOS HM ATM - DISPAROS'), ('535','EX HM | JUL26 - DISPARO LIVE'),
('536','Encontro do Time Holding Brasil Agosto - São Paulo - Aberto Ao Público Externo - Interessados WPP'),
('537','SEM ATM - BY THE WAY'), ('538','SEM ATM JUL26 | REATIVAÇÃO'),
('539','[SEMINÁRIO ATM] SESSÃO DE VIABILIDADE'), ('540','ETHB - HMS ATIVOS'),
('541','CURSO NACIONAL DE FORMAÇÃO EM HOLDING FAMILIAR'), ('542','SEMAJUL26 - 1907'),
('543','1 - HT Alunos que não compraram'), ('544','2. PARTICIPANTES DO HT QUE NÃO SÃO ALUNOS 1'),
('545','2. PARTICIPANTES DO HT QUE NÃO SÃO ALUNOS 2'), ('546','ETHB LDP - SP 01'),
('547','ETHB Convite Live_Direto_ao_Ponto'), ('548','SEM JUL26 - RECUPERAÇÃO 2407'),
('549','[SEMINÁRIO JUL/26] Leads Quentes p/ Disparo #110901'),
('550','[SEMINÁRIO JUL/26] Leads Frios p/ Disparo #110902'),
('551','[SEMINÁRIO JUL/26] Leads Frios p/ Disparo #110903'),
('552','[SEMINÁRIO JUL/26] Leads Frios p/ Disparo #110904'),
('553','[SEMINÁRIO JUL/26] Leads Frios p/ Disparo #110905'), ('555','Sessão de Viabilidade - JUL26'),
('556','Seminário SET26'), ('557','[SEMINÁRIO 2026] LISTA DE INTERESSADOS'), ('558','LIVE HOLDING TOTAL'),
('559','Seminário de Planejamento Patrimonial Setembro 2026 - Dra. Elaine Montenegro'),
('560','CARTA DE VENDAS ELAINE MONTENEGRO'), ('561','BASE 170k'),
('562','Seminário de Planejamento Patrimonial - Dra. Elaine - Setembro 2026'), ('563','HT31-ANTIGOS'),
('564','Fora do grupo - Outros [CNHF]'), ('565','Fora do grupo - Advogados [CNHF]'),
('566','Fora do grupo - Contador [CNHF]'), ('567','ACELERA HOLDING'), ('568','CNHF ANTIGOS LOTE 1'),
('569','CNHF LEADS ANTIGOS LOTE 2'), ('570','CNHF ANTIGOS LOTE 3'), ('571','CNHF ANTIGOS LOTE 4'),
('572','CNHF ANTIGOS LOTE 5'), ('573','Sem_Set01.09'), ('574','[ATM - SEMINÁRIO SETEMBRO] LEADS'),
('575','INFORMATIVO HOLDING FAMILIAR'), ('576','SEMSET_'), ('577','Leads ATM - BASE'),
('578','SEMSET26 - bytheway'), ('579','SEMSET26_rec06.09'), ('580','SEMSET26_rec08.09'),
('581','SEMATM_REC09.09'), ('582','[ESCOLHIDOS - SETEMBRO] PRÉ-CHECKOUT'), ('583','Holding Total Set/26'),
('584','Imersão Presencial Holding Sem Improviso - Nov/26 - Leads Pré-Checkout'), ('585','Carrinho ATM 11.09'),
('586','HT 32 - Leads Lançamento Meteórico'), ('587','SEMSET26_aquecimento14.09'),
('588','IMERSÃO - HT -SET26'), ('589','IMERSÃO - HT -SET26 - COMPRADORES'),
('590','IMERSÃO - HT -SET26 - précheckout'), ('591','Holding Total - 14/SET/26'), ('592','imersao_ht_set_d3'),
('593','HT 32 - SET26 - METEÓRICO - Leads pré-checkout'), ('594','ATM - HT - Setembro/2026 | Dias 20 e 23'),
('595','[LEADS] HOLDING TOTAL EDIÇÃO 32'), ('596','ATM - HT - Setembro/2026 | Qualificação'),
('597','Holding Total - Lista compilada - 18/set/26'), ('598','SEMSET26_FALTAM2DIAS'), ('599','SEMSET26-HOJE'),
('600','HT-IMERSÃO-22/09'), ('601','HT-FORADOGRUPO-22/09'), ('602','HT-SEM INSRIÇÃO'),
('603','Patrimônio Brasil - Geral'), ('604','HT 33 - Imersão Holding Total (qualificação)'),
('605','[HT 32] AÇÃO FINAL'), ('606','[HT] Qualificação - set/26'), ('607','Sessão de Viabilidade [SEMSET26]'),
('608','[HOLDING MASTERS] PRÉ-CHECKOUTS'), ('609','Patrimônio Brasil - AK1'),
('610','Patrimônio Brasil - BL2 MQL'), ('611','Patrimônio Brasil - BL2 Não MQL'),
('612','Patrimônio Brasil - BL2 Profissional'), ('613','Black Friday 2026'),
('614','Clínica Internacional Diamante Dez/26 - Leads Pré-Checkout');

-- 7b. Regras: PROPOSTA para o Arthur confirmar (explain, seção "Regras propostas"). Chave do projeto = a de
--     gp-operacoes/projetos (= utm_campaign = etiqueta do ClickUp). O AC não tem convenção de nome: casar por pedaço do
--     nome é aproximação; o que não casar fica "sem projeto" para o gestor classificar na tela.
insert into crm.catalogo_regra (campo, operador, padrao, projeto, prioridade, nota) values
-- Patrimônio Brasil (Seminário Conjunto dos Diamantes Vermelhos, nov/26)
('ac_lista', 'comeca', 'Patrimônio Brasil', 'seminario-conjunto-2026-11', 100, 'Listas 603, 609–612'),
('ac_tag',   'igual',  'LEAD PB',           'seminario-conjunto-2026-11', 100, 'PB = Patrimônio Brasil'),
('ac_tag',   'comeca', 'PB ',               'seminario-conjunto-2026-11', 100, 'PB MQL, PB NAO MQL, PB PESQUISA WHATSAPP…'),
-- Black Friday 2026
('ac_lista', 'igual',  'Black Friday 2026', 'black-friday-2026-10', 100, 'Lista 613'),
('ac_tag',   'contem', 'BLACK FRIDAY',      'black-friday-2026-10', 110, 'LISTA DE ESPERA BLACK FRIDAY (sem ano: conferir em 2027)'),
-- Imersão Holding Total set/26 (HT32), inclusive o ATM do HT
('ac_lista', 'contem', 'HT 32',                   'imersao-holding-total-2026-09', 100, 'HT 32 - Leads Lançamento Meteórico, [HT 32] AÇÃO FINAL…'),
('ac_lista', 'contem', 'EDIÇÃO 32',               'imersao-holding-total-2026-09', 100, '[LEADS] HOLDING TOTAL EDIÇÃO 32'),
('ac_lista', 'contem', 'HT -SET26',               'imersao-holding-total-2026-09', 100, 'IMERSÃO - HT -SET26 (+ précheckout, compradores)'),
('ac_lista', 'comeca', 'imersao_ht_set',          'imersao-holding-total-2026-09', 100, 'imersao_ht_set_d3'),
('ac_lista', 'igual',  'Holding Total Set/26',    'imersao-holding-total-2026-09', 100, 'Lista 583'),
('ac_lista', 'contem', '/SET/26',                 'imersao-holding-total-2026-09', 110, 'Holding Total - 14/SET/26; - Lista compilada - 18/set/26'),
('ac_lista', 'comeca', 'HT-IMERSÃO',              'imersao-holding-total-2026-09', 100, 'HT-IMERSÃO-22/09'),
('ac_lista', 'comeca', 'HT-FORADOGRUPO',          'imersao-holding-total-2026-09', 100, 'HT-FORADOGRUPO-22/09'),
('ac_lista', 'comeca', 'HT-SEM INS',              'imersao-holding-total-2026-09', 100, 'HT-SEM INSRIÇÃO (22/09)'),
('ac_lista', 'igual',  '[HT] Qualificação - set/26', 'imersao-holding-total-2026-09', 100, 'Lista 606'),
('ac_lista', 'contem', 'ATM - HT - Setembro/2026', 'imersao-holding-total-2026-09', 100, 'ATM do HT (dias 20 e 23/09): projeto pai = imersão (confirmado 07/10)'),
('hotmart_oferta', 'igual', 'jqigl9li', 'imersao-holding-total-2026-09', 100, 'HT32: ingresso'),
('hotmart_oferta', 'igual', 'hdxree3v', 'imersao-holding-total-2026-09', 100, 'HT32'),
('hotmart_oferta', 'igual', '6fceg8ye', 'imersao-holding-total-2026-09', 100, 'HM R$ 15 mil vendido no HT32 (confirmado 07/10)'),
-- Seminário da Dra. Elaine, setembro/26 (SEMSET26)
('ac_lista', 'contem', 'SEMSET',                       'seminario-elaine-2026-09', 100, 'SEMSET26_*, Sessão de Viabilidade [SEMSET26]'),
('ac_lista', 'comeca', 'Sem_Set',                      'seminario-elaine-2026-09', 100, 'Sem_Set01.09'),
('ac_lista', 'igual',  'Seminário SET26',              'seminario-elaine-2026-09', 100, 'Lista 556'),
('ac_lista', 'contem', 'Elaine - Setembro 2026',       'seminario-elaine-2026-09', 100, 'Lista 562'),
('ac_lista', 'contem', 'Setembro 2026 - Dra. Elaine',  'seminario-elaine-2026-09', 100, 'Lista 559'),
('funil',    'igual',  'Clint · SESSÃO 22/09',         'seminario-elaine-2026-09', 100, 'Sessão de Viabilidade do seminário (CPLs 21–23/09)'),
('funil',    'igual',  'Clint · Interessados',         'seminario-elaine-2026-09', 100, 'Tag da Clint sem-set-interessados nos 102 (confirmado 07/10)'),
('funil',    'igual',  'Clint · MQLS',                 'seminario-elaine-2026-09', 100, 'Criados em 23/09, linha SV (confirmado 07/10)'),
('funil',    'igual',  'Clint · RSVP - MQL',           'seminario-elaine-2026-09', 100, 'Criados em 15/09, linha SV (confirmado 07/10)'),
-- Seminário ATM, setembro/26
('ac_lista', 'contem', 'ATM - SEMINÁRIO SETEMBRO', 'seminario-atm-2026-09', 100, '[ATM - SEMINÁRIO SETEMBRO] LEADS'),
('ac_lista', 'comeca', 'SEMATM',                   'seminario-atm-2026-09', 100, 'SEMATM_REC09.09'),
('ac_lista', 'igual',  'Carrinho ATM 11.09',       'seminario-atm-2026-09', 100, 'Lista 585'),
('ac_lista', 'igual',  'Leads ATM - BASE',         'seminario-atm-2026-09', 100, 'Lista 577'),
-- CNHF (Curso Nacional de Formação em Holding Familiar, ago/26)
('ac_lista', 'contem', 'CNHF',                     'cnhf-2026-08', 100, 'Fora do grupo [CNHF], CNHF ANTIGOS LOTE n'),
('ac_lista', 'igual',  'CURSO NACIONAL DE FORMAÇÃO EM HOLDING FAMILIAR', 'cnhf-2026-08', 100, 'Lista 541'),
('ac_tag',   'comeca', '[CNHF - AGO/2026]',        'cnhf-2026-08', 100, '[CNHF - AGO/2026] LEAD, OUTROS, WHATSAPP PREENCHIDO'),
('funil',    'igual',  'Clint · Curso Nacional de Holding Familiar', 'cnhf-2026-08', 100, null),
-- Acelera Holding (ago/26)
('ac_lista', 'igual',  'ACELERA HOLDING',          'acelera-holding-2026-08', 100, 'Lista 567 (26/08)'),
-- ETHB São Paulo (ago/26)
('ac_lista', 'comeca', 'Encontro do Time Holding Brasil Agosto - São Paulo', 'ethb-sao-paulo-2026-08', 100, 'Listas 503, 510, 536'),
('ac_lista', 'comeca', 'ETHB',                     'ethb-sao-paulo-2026-08', 110, 'ETHB LDP - SP 01, ETHB Convite…, ETHB - HMS ATIVOS (confirmado 07/10)'),
-- Seminário da Dra. Elaine, junho/26
('ac_lista', 'contem', 'Elaine Montenegro - Junho de 2026', 'seminario-elaine-2026-06', 100, 'Lista do seminário de junho'),
('ac_lista', 'igual',  'Sessão de Viabilidade - JUN26',     'seminario-elaine-2026-06', 100, null),
-- Clínica Internacional dez/26
('ac_lista', 'contem', 'Clínica Internacional Diamante Dez/26', 'miami-2026-12', 100, 'Lista 614 (confirmado 07/10)'),
-- Conhecidas, SEM projeto (lista ou funil geral do produto): saem das pendências sem inventar projeto
('ac_lista', 'igual', '403', null, 200, 'Lista geral "Holding Total"'),
('ac_lista', 'igual', '409', null, 200, 'Lista geral "Holding Masters"'),
('funil', 'igual', 'Clint · Evento', null, 200, 'Compradores de edições do HT (produto, sem projeto)'),
('funil', 'contem', 'Saldo Implementação Assistida', null, 200, 'Recuperação de saldo HM'),
('funil', 'igual', 'Clint · Recuperacao _HM', null, 200, 'Recuperação HM'),
('funil', 'igual', 'Clint · HT Recuperação de Venda', null, 200, 'Recuperação HT'),
('funil', 'igual', 'Clint · Leads recuperação', null, 200, 'Recuperação'),
('funil', 'comeca', 'Checkout e recuperação ·', null, 200, 'Funis automáticos da Hotmart (produto, sem projeto)');
-- oferta padrão do ingresso do HT (usada de mar a ago/26 em outras edições): só vale para o HT32 dentro de set/26
insert into crm.catalogo_regra (campo, operador, padrao, projeto, vale_de, vale_ate, prioridade, nota) values
('hotmart_oferta', 'igual', '3mcmh0eu', 'imersao-holding-total-2026-09', '2026-09-01', '2026-09-30', 100,
 'Ingresso padrão do HT (mar–ago em outras edições): só set/26 é HT32 (confirmado 07/10)');

-- 7c. MQL (decisão do Arthur, 07/10/2026): só a tag "PB MQL" vale como MQL do Patrimônio Brasil. "PB NAO MQL" não
--     (operador "é igual"). Novas tags/listas de MQL: o Victor cadastra na tela.
insert into crm.catalogo_regra (tipo, campo, operador, padrao, projeto, prioridade, nota) values
('mql', 'ac_tag', 'igual', 'PB MQL', 'seminario-conjunto-2026-11', 100, 'MQL do Patrimônio Brasil (PB NAO MQL não é MQL)');

-- ─── 8. Permissões ────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function crm.catalogo_norm(text, boolean), crm.catalogo_casa(text, text, text), crm.projeto_conhecido(text),
  crm.projeto_nome(text), crm.catalogo_resolver(jsonb, timestamptz), crm.projeto_do_evento(text, jsonb),
  crm.origem_canal_de_dica(text), crm.origem_dica(), crm.origem_catalogar(uuid), crm.origem_recatalogar_pessoa(uuid),
  crm.tg_origem_pc(), crm.tg_origem_evidencia(), crm.contatos_itens(uuid[], boolean),
  crm.pode_catalogar(), crm.catalogo_mql(jsonb, timestamptz), crm.campos_do_evento(text, jsonb), crm.quando_do_evento(jsonb),
  crm.mql_do_evento(text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.crm_contatos_pagina(text, text, text, text, text[], boolean, boolean, text, text, integer, integer, text, text),
  public.crm_contatos_resumo(), public.crm_catalogo(), public.crm_catalogo_regra_salvar(jsonb),
  public.crm_catalogo_lista_salvar(text, text), public.crm_catalogo_reaplicar(boolean), public.crm_contato_origem(uuid),
  public.crm_contato_origem_definir(uuid, text) from public, anon;
grant execute on function public.crm_contatos_pagina(text, text, text, text, text[], boolean, boolean, text, text, integer, integer, text, text),
  public.crm_contatos_resumo(), public.crm_catalogo(), public.crm_catalogo_regra_salvar(jsonb),
  public.crm_catalogo_lista_salvar(text, text), public.crm_catalogo_reaplicar(boolean), public.crm_contato_origem(uuid),
  public.crm_contato_origem_definir(uuid, text) to authenticated, service_role;

-- ─── 9. Backfill dos contatos existentes ──────────────────────────────────────────────────────────────────────────
-- dica de canal = o canal que o registro do CRM gravou quando criou o contato (crm.log 'criou' 'contato')
insert into crm.pessoa_origem (pessoa_id, canal_entrada, entrou_em, canal_dica)
select pc.pessoa_id, crm.origem_canal_de_dica(l.canal), pc.criado_em, l.canal
  from crm.pessoa_comercial pc
  left join (select distinct on (lg.entidade_id) lg.entidade_id, lg.canal
               from crm.log lg where lg.entidade = 'contato' and lg.acao = 'criou'
              order by lg.entidade_id, lg.em) l on l.entidade_id = pc.pessoa_id::text
on conflict (pessoa_id) do nothing;

do $b$
declare v uuid;
begin
  for v in select po.pessoa_id from crm.pessoa_origem po order by po.pessoa_id loop
    perform crm.origem_catalogar(v);
  end loop;
end
$b$;

-- ─── 10. Conferência ──────────────────────────────────────────────────────────────────────────────────────────────
do $c$
declare v text;
begin
  if (select count(*) from crm.pessoa_origem) <> (select count(*) from crm.pessoa_comercial) then
    raise exception '20261007g: backfill incompleto (% origens para % contatos)',
      (select count(*) from crm.pessoa_origem), (select count(*) from crm.pessoa_comercial);
  end if;
  if (select count(*) from pg_proc where proname = 'crm_contatos_pagina') <> 1 then raise exception '20261007g: sobrecarga de crm_contatos_pagina'; end if;
  select proacl::text into v from pg_proc where oid = 'public.crm_contatos_pagina(text,text,text,text,text[],boolean,boolean,text,text,integer,integer,text,text)'::regprocedure;
  if v <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then raise exception '20261007g: acl de crm_contatos_pagina: %', v; end if;
  select proacl::text into v from pg_proc where oid = 'public.crm_contatos_resumo()'::regprocedure;
  if v <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then raise exception '20261007g: acl de crm_contatos_resumo: %', v; end if;
  if exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
              where s.nspname = 'crm'
                and p.proname in ('catalogo_norm', 'catalogo_casa', 'projeto_conhecido', 'projeto_nome', 'catalogo_resolver',
                                  'projeto_do_evento', 'origem_canal_de_dica', 'origem_dica', 'origem_catalogar',
                                  'origem_recatalogar_pessoa', 'tg_origem_pc', 'tg_origem_evidencia', 'contatos_itens',
                                  'pode_catalogar', 'catalogo_mql', 'campos_do_evento', 'quando_do_evento', 'mql_do_evento')
                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))) then
    raise exception '20261007g: função interna executável por anon/authenticated';
  end if;
  if exists (select 1 from pg_proc p where p.proname in ('crm_catalogo', 'crm_catalogo_regra_salvar', 'crm_catalogo_lista_salvar',
                                                         'crm_catalogo_reaplicar', 'crm_contato_origem', 'crm_contato_origem_definir',
                                                         'crm_contatos_pagina', 'crm_contatos_resumo')
                                    and has_function_privilege('anon', p.oid, 'execute')) then
    raise exception '20261007g: RPC executável por anon';
  end if;
  if has_table_privilege('authenticated', 'crm.pessoa_origem', 'select') or has_table_privilege('anon', 'crm.catalogo_regra', 'select') then
    raise exception '20261007g: tabela nova legível pela API';
  end if;
end
$c$;

-- ─── REVERSÃO (manual, nesta ordem) ───────────────────────────────────────────────────────────────────────────────
-- Desligar sem desfazer (para de catalogar; a origem já gravada fica):
--   alter table crm.pessoa_comercial disable trigger zz_origem_ins;
--   alter table crm.hotmart_processado disable trigger zz_origem_hotmart_ins; … disable trigger zz_origem_hotmart_upd;
--   alter table crm.evento_jornada disable trigger zz_origem_ac_ins; … disable trigger zz_origem_ac_upd;
--   alter table crm.negocio disable trigger zz_origem_negocio;
-- Desfazer:
--   drop trigger zz_origem_ins on crm.pessoa_comercial; drop trigger zz_origem_hotmart_ins on crm.hotmart_processado;
--   drop trigger zz_origem_hotmart_upd on crm.hotmart_processado; drop trigger zz_origem_ac_ins on crm.evento_jornada;
--   drop trigger zz_origem_ac_upd on crm.evento_jornada; drop trigger zz_origem_negocio on crm.negocio;
--   crm.projeto_do_evento: voltar à versão mínima da 20261007e ("select null::text"; mesma assinatura e acl).
--   crm_contatos_pagina: drop da de 13 parâmetros e recriar o corpo de 20261007114310 (11 parâmetros, mesmos grants).
--   crm.contatos_itens e crm_contatos_resumo: recriar o corpo de 20261007114310 (md5 c7c17a0c… / 5637d27b…).
--   drop das RPCs crm_catalogo*, crm_contato_origem*; drop das funções crm.origem_*, crm.catalogo_*, crm.projeto_nome,
--   crm.projeto_conhecido; tabelas: renomear para arquivo.* em vez de apagar (crm.pessoa_origem, crm.catalogo_regra,
--   crm.ac_lista). O índice hotmart_processado_pessoa_idx pode ficar.
