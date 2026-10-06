-- 20261005p: Marketing > Tráfego, etapa 1 (dados e cadastro da Central do Tráfego)
--
-- O QUE FAZ
--   Cria o schema mkt_trafego com o que o Tráfego tem de próprio: contas de anúncio, campanhas (com a leitura do nome
--   pelo padrão da casa), gasto e desempenho por campanha e dia (vazio: a coleta Meta/Google é a etapa 2) e o
--   planejamento do projeto (status, verba, fases e metas, marcados à mão). Mais as funções public.trafego_* da tela
--   /marketing/trafego e um resumo por projeto com as colunas da Central do Tráfego. Decisões (Victor, 05/10/2026):
--     - O mesmo dado não se duplica: projeto e página ficam em mkt (20261005m), lead em pessoas (20261005o), visita em
--       mkt_web (20261005n), venda na Hotmart. Aqui só o que é do Tráfego.
--     - Status do projeto MARCADO À MÃO; verba, fases e metas preenchidas por Arthur, Victor e Caio (admin/dev).
--     - KPIs da tabela: CPL, leads, CTR, CPM, connect rate, conversão da página, % MQL. O lead que conta é o DA NOSSA
--       BASE (pessoas.eventos). Receita gerada = receita (Hotmart), ainda sem ligação: volta nula.
--     - CTR e CPC usam CLIQUES NO LINK (guardados separados dos cliques totais). Connect rate = page views ÷ cliques no
--       link; conversão da página = leads ÷ page views. Page view = a MESMA da Web fase 2 (public.mkt_web_connect,
--       20261005q): entrada na página vinda da campanha, uma por visita (mkt_web.sessoes), casada com a campanha do
--       Tráfego por campaign_id = id da campanha ou utm_campaign = nome exato ou id. Sem a 20261005q: nulos.
--     - Um projeto pode ter VÁRIOS gestores (projeto_gestores, das listas de mkt.campanha_gestores).
--     - Fases: aquecimento, captação, lembrete, remarketing, abertura de carrinho. A fase da campanha sai do OBJETIVO do
--       nome (tabela objetivo_fase, configurável); a correção à mão por campanha (fase_manual) prevalece. Sem regra e
--       sem correção = "sem fase". Mapa: LEADS → captação, VENDAS → captação (lançamento pago: vende o ingresso em vez
--       de captar lead), LEMBRETE → lembrete, REMARKETING → remarketing, CARRINHO → abertura de carrinho, AQUECIMENTO →
--       aquecimento. DISTRIBUIÇÃO (de conteúdo) NÃO tem fase automática: pode ou não ser aquecimento; fica "sem fase"
--       até alguém marcar à mão na campanha.
--     - Objetivos novos no padrão de nome: CARRINHO (anuncia o produto principal na abertura de carrinho, em lançamento
--       pago ou gratuito) e AQUECIMENTO. Entram em mkt.campanha_objetivos (lista da 20261005m) por insert idempotente, e
--       mkt.campanha_traduzir passa a reconhecer (ela lê a lista). Lista final: LEADS, VENDAS, REMARKETING, LEMBRETE,
--       DISTRIBUIÇÃO, CARRINHO, AQUECIMENTO.
--     - Atividades do ClickUp ficam na tela (lugar reservado nesta etapa, sem integrar).
--   Fontes: Projetos/sistema-unico/central-de-dados/{plano-trafego.md, area-de-trafego.md} no cérebro do Victor.
--
--   Padrão do repo (igual 20261005m/o): tabelas fechadas (RLS ligada, sem policy, revoke de anon/authenticated), schema
--   sem USAGE para anon/authenticated, todo acesso por função public.trafego_* SECURITY DEFINER com search_path '' e a
--   trava dentro (mkt.pode_ver('mkt_trafego'): hoje só admin/dev). A entrada da coleta futura
--   (trafego_campanhas_receber, trafego_desempenho_receber) é só de service_role.
--
-- O QUE CRIA
--   schema mkt_trafego  plataformas, status_projeto, fases (listas configuráveis), contas, campanhas, desempenho_dia,
--                       planejamento, projeto_gestores (projeto × gestor, N:N), projeto_fases, objetivo_fase
--                       conta_normalizar(text,text), campanha_aplicar_leitura(bigint), ontem(), resumo(bigint),
--                       fase_efetiva(text,text)
--   public.trafego_*    config, contas_listar, conta_salvar, planejamento_salvar, fase_salvar, fase_apagar,
--                       campanhas_listar, campanha_ajustar, campanhas_reler, resumo, projeto (authenticated)
--                       campanhas_receber, desempenho_receber (service_role)
--
-- AS 5 PERGUNTAS
--   escala: dezenas de projetos e contas, centenas de campanhas por ano; desempenho_dia = campanhas × dias, na ordem de
--     dezenas de milhares de linhas por ano.
--   índice: PK (campanha_id, dia) em desempenho_dia; PK (projeto_id, gestor) em projeto_gestores; únicos (plataforma, conta_externa) e (plataforma, campanha_externa);
--     campanhas(projeto_id), campanhas(conta_id); projeto_fases único (projeto_id, fase).
--   frequência: a tela chama trafego_resumo ao abrir e trafego_projeto ao clicar; a coleta (etapa 2) chama os receber
--     uma vez por dia (mais algumas leituras do dia corrente).
--   repetição: o resumo agrega desempenho_dia uma vez (group by projeto), sem query por linha. A leitura de leads da
--     base de pessoas é uma query só, agrupada por projeto.
--   reversão: bloco REVERSÃO no fim.
--
-- ENSAIO: infra/supabase/migrations/20261005p_ensaio.sql (begin … rollback). Explicação: 20261005p.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regnamespace('mkt_trafego') is not null then
    raise exception '20261005p: schema mkt_trafego já existe (migration já aplicada?)';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') then
    raise exception '20261005p: já existem funções public.trafego_*';
  end if;
  if to_regclass('mkt.projetos') is null or to_regclass('mkt.paginas') is null
     or to_regclass('mkt.campanha_gestores') is null
     or to_regprocedure('mkt.campanha_traduzir(text)') is null or to_regprocedure('mkt.pode_ver(text)') is null then
    raise exception '20261005p: falta a 20261005m (mkt.projetos, mkt.paginas, mkt.campanha_gestores, mkt.campanha_traduzir, mkt.pode_ver)';
  end if;
  if to_regclass('mkt.campanha_objetivos') is null then
    raise exception '20261005p: mkt.campanha_objetivos ausente (20261005m)';
  end if;
  if to_regprocedure('public.gp_is_admin()') is null then
    raise exception '20261005p: public.gp_is_admin() ausente';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception '20261005p: papel service_role ausente';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'perfis' and column_name = 'id') then
    raise exception '20261005p: public.perfis.id ausente';
  end if;
end
$guarda$;

-- ─── 1. Schema ───────────────────────────────────────────────────────────────────────────────────────────────────────
create schema mkt_trafego;
revoke all on schema mkt_trafego from public, anon, authenticated;
comment on schema mkt_trafego is
  'Marketing > Tráfego: contas de anúncio, campanhas (leitura do nome pelo padrão da casa), gasto e desempenho diário e '
  'planejamento do projeto (status, verba, fases, metas; à mão). Projeto e página em mkt, lead em pessoas, visita em '
  'mkt_web: nada disso é copiado aqui. Fechado: acesso só pelas funções public.trafego_*. 20261005p.';

-- ─── 2. Listas configuráveis (alteradas por SQL; a tela só lê) ────────────────────────────────────────────────────────
create table mkt_trafego.plataformas (
  codigo text primary key check (codigo ~ '^[a-z][a-z_]{1,19}$'),
  nome   text not null check (length(btrim(nome)) between 2 and 40),
  ativa  boolean not null default true
);
comment on table mkt_trafego.plataformas is 'Plataformas de anúncio. Extensível: plataforma nova = uma linha aqui (e a coleta dela).';

create table mkt_trafego.status_projeto (
  codigo text primary key check (codigo ~ '^[a-z][a-z_]{1,19}$'),
  nome   text not null check (length(btrim(nome)) between 2 and 40),
  ordem  smallint not null,
  ativo  boolean not null default true
);
comment on table mkt_trafego.status_projeto is
  'Status do projeto na Central do Tráfego, marcado à mão (Victor, 05/10/2026). Semente = as palavras da conversa '
  'Caio × Arthur ("ativo, pausado ou inativo. Ou encerrado"); a lista final é pergunta em aberto.';

create table mkt_trafego.fases (
  codigo text primary key check (codigo ~ '^[a-z][a-z_]{1,29}$'),
  nome   text not null check (length(btrim(nome)) between 2 and 40),
  ordem  smallint not null,
  ativa  boolean not null default true
);
comment on table mkt_trafego.fases is 'Fases da verba de um projeto (aquecimento, captação, lembrete, remarketing, abertura de carrinho). Lista configurável.';

create table mkt_trafego.objetivo_fase (
  objetivo text primary key references mkt.campanha_objetivos(codigo) on delete cascade,
  fase     text not null references mkt_trafego.fases(codigo) on delete restrict
);
comment on table mkt_trafego.objetivo_fase is
  'Fase de uma campanha pelo OBJETIVO do nome (campo 3). Configurável por SQL. Objetivo sem linha aqui = campanha sem fase '
  '(a não ser que alguém marque à mão). Sementes só as óbvias (Victor, 05/10/2026).';

-- ─── 3. Contas, campanhas e desempenho ───────────────────────────────────────────────────────────────────────────────
create table mkt_trafego.contas (
  id             bigint generated always as identity primary key,
  plataforma     text not null references mkt_trafego.plataformas(codigo) on delete restrict,
  conta_externa  text not null check (conta_externa ~ '^[A-Za-z0-9_-]{1,40}$'),
  nome           text not null check (length(btrim(nome)) between 2 and 120),
  dono           text not null check (dono in ('grupo', 'diamante', 'aurum')),
  cliente        text check (cliente is null or length(btrim(cliente)) between 2 and 120),
  moeda          text not null default 'BRL' check (moeda ~ '^[A-Z]{3}$'),
  ativa          boolean not null default true,
  obs            text check (obs is null or length(obs) <= 1000),
  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.perfis(id) on delete set null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null,
  constraint contas_externa_unica unique (plataforma, conta_externa),
  constraint contas_id_plataforma unique (id, plataforma)
);
comment on table mkt_trafego.contas is 'Contas de anúncio (gerenciador Meta, conta Google Ads). Cadastro à mão.';
comment on column mkt_trafego.contas.conta_externa is
  'Id da conta na plataforma, normalizado: Meta sem o prefixo act_, Google só os dígitos (sem os hífens).';
comment on column mkt_trafego.contas.dono is
  'De quem é a conta: grupo (Grupo Participa; subárea interno), diamante, aurum. Alinha com mkt.projetos.subarea_trafego.';
comment on column mkt_trafego.contas.cliente is 'Quando a conta é de um Diamante ou aluno Aurum: o nome dele, como no cadastro. Nulo = não informado.';

create table mkt_trafego.projeto_fases (
  id             bigint generated always as identity primary key,
  projeto_id     bigint not null references mkt.projetos(id) on delete restrict,
  fase           text not null references mkt_trafego.fases(codigo) on delete restrict,
  verba          numeric(14,2) check (verba is null or verba >= 0),
  inicio         date,
  fim            date,
  obs            text check (obs is null or length(obs) <= 1000),
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null,
  constraint projeto_fases_unica unique (projeto_id, fase),
  constraint projeto_fases_datas_check check (fim is null or inicio is null or fim >= inicio)
);
create index projeto_fases_projeto_idx on mkt_trafego.projeto_fases (projeto_id);
comment on table mkt_trafego.projeto_fases is 'Verba planejada por fase do projeto e o período dela. À mão (Arthur, Victor, Caio).';

create table mkt_trafego.campanhas (
  id                bigint generated always as identity primary key,
  plataforma        text not null,
  conta_id          bigint not null,
  campanha_externa  text not null check (campanha_externa ~ '^[A-Za-z0-9_-]{1,60}$'),
  nome              text not null check (length(nome) between 1 and 400),
  status_plataforma text check (status_plataforma is null or length(status_plataforma) <= 40),
  leitura           jsonb not null,
  fora_padrao       boolean not null,
  gestor            text,
  objetivo          text,
  pagina_id         bigint references mkt.paginas(id) on delete set null,
  projeto_id        bigint references mkt.projetos(id) on delete restrict,
  projeto_manual    boolean not null default false,
  fase_manual       text references mkt_trafego.fases(codigo) on delete restrict,
  primeira_coleta   timestamptz not null default now(),
  ultima_coleta     timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  atualizado_por    uuid references public.perfis(id) on delete set null,
  constraint campanhas_externa_unica unique (plataforma, campanha_externa),
  constraint campanhas_conta_fk foreign key (conta_id, plataforma) references mkt_trafego.contas(id, plataforma) on delete restrict,
  constraint campanhas_manual_check check (not projeto_manual or projeto_id is not null)
);
create index campanhas_projeto_idx on mkt_trafego.campanhas (projeto_id);
create index campanhas_conta_idx on mkt_trafego.campanhas (conta_id);
comment on table mkt_trafego.campanhas is
  'Campanhas como estão na plataforma (nome EXATO). leitura = mkt.campanha_traduzir(nome); projeto, gestor, objetivo e '
  'página saem dela. projeto_manual = alguém ligou o projeto à mão (nome fora do padrão). Upsert por (plataforma, id).';
comment on column mkt_trafego.campanhas.fase_manual is
  'Correção à mão da fase. Nulo = vale a fase do objetivo (objetivo_fase). Fase efetiva = mkt_trafego.fase_efetiva(objetivo, fase_manual).';

create table mkt_trafego.desempenho_dia (
  campanha_id      bigint not null references mkt_trafego.campanhas(id) on delete cascade,
  dia              date not null,
  gasto            numeric(14,2) not null check (gasto >= 0),
  impressoes       bigint not null check (impressoes >= 0),
  cliques_link     bigint not null check (cliques_link >= 0),
  cliques_total    bigint check (cliques_total is null or cliques_total >= 0),
  leads_plataforma integer check (leads_plataforma is null or leads_plataforma >= 0),
  coletado_em      timestamptz not null default now(),
  primary key (campanha_id, dia)
);
comment on table mkt_trafego.desempenho_dia is
  'Gasto e desempenho por campanha e dia, como a plataforma informa. VAZIA até a coleta (etapa 2). Reenvio do mesmo dia '
  'sobrescreve (idempotente). Moeda = a da conta.';
comment on column mkt_trafego.desempenho_dia.cliques_link is 'Cliques no link (Meta: inline_link_clicks). É o clique do CTR, do CPC e do connect rate (Victor, 05/10/2026).';
comment on column mkt_trafego.desempenho_dia.cliques_total is 'Todos os cliques (Meta: clicks). Só informação; nenhum KPI usa. Nulo = a plataforma não informou.';
comment on column mkt_trafego.desempenho_dia.leads_plataforma is 'Leads que a plataforma atribui. NÃO é o lead da Central (o da nossa base).';

create table mkt_trafego.planejamento (
  projeto_id     bigint primary key references mkt.projetos(id) on delete restrict,
  status         text references mkt_trafego.status_projeto(codigo) on delete restrict,
  verba_maxima   numeric(14,2) check (verba_maxima is null or verba_maxima > 0),
  verba_diaria   numeric(14,2) check (verba_diaria is null or verba_diaria > 0),
  meta_leads     integer check (meta_leads is null or meta_leads > 0),
  meta_receita   numeric(14,2) check (meta_receita is null or meta_receita > 0),
  meta_cpl       numeric(14,2) check (meta_cpl is null or meta_cpl > 0),
  meta_pct_mql   numeric(5,2) check (meta_pct_mql is null or meta_pct_mql between 0 and 100),
  obs            text check (obs is null or length(obs) <= 1000),
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null
);
comment on table mkt_trafego.planejamento is
  'Planejamento do projeto no Tráfego, à mão: status, verba máxima e diária, metas. Uma linha por projeto de '
  'mkt.projetos (criada quando alguém salva). Os gestores ficam em projeto_gestores (vários por projeto).';

create table mkt_trafego.projeto_gestores (
  projeto_id     bigint not null references mkt.projetos(id) on delete restrict,
  gestor         text not null references mkt.campanha_gestores(sigla) on delete restrict,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null,
  primary key (projeto_id, gestor)
);
comment on table mkt_trafego.projeto_gestores is
  'Gestores do projeto (Victor, 05/10/2026: um projeto pode ter vários). Sigla da lista mkt.campanha_gestores (CF, RS, EF). À mão.';

alter table mkt_trafego.plataformas enable row level security;
alter table mkt_trafego.status_projeto enable row level security;
alter table mkt_trafego.fases enable row level security;
alter table mkt_trafego.objetivo_fase enable row level security;
alter table mkt_trafego.contas enable row level security;
alter table mkt_trafego.projeto_fases enable row level security;
alter table mkt_trafego.campanhas enable row level security;
alter table mkt_trafego.desempenho_dia enable row level security;
alter table mkt_trafego.planejamento enable row level security;
alter table mkt_trafego.projeto_gestores enable row level security;
revoke all on all tables in schema mkt_trafego from public, anon, authenticated;

-- ─── 4. Sementes (só o que está nas fontes) ──────────────────────────────────────────────────────────────────────────
-- Plataformas: Meta Ads e Google Ads (area-de-trafego.md, 3.2). ChatGPT Ads está "pendente" lá: não entra.
insert into mkt_trafego.plataformas (codigo, nome) values ('meta', 'Meta Ads'), ('google', 'Google Ads');
-- Status: as palavras da conversa (area-de-trafego.md, 2.1).
insert into mkt_trafego.status_projeto (codigo, nome, ordem) values
  ('ativo', 'Ativo', 1), ('pausado', 'Pausado', 2), ('inativo', 'Inativo', 3), ('encerrado', 'Encerrado', 4);
-- Fases: Victor, 05/10/2026 ("aquecimento, captação, lembrete, remarketing e abertura de carrinho").
insert into mkt_trafego.fases (codigo, nome, ordem) values
  ('aquecimento', 'Aquecimento', 1), ('captacao', 'Captação', 2), ('lembrete', 'Lembrete', 3),
  ('remarketing', 'Remarketing', 4), ('abertura_carrinho', 'Abertura de carrinho', 5);
-- Objetivos CARRINHO e AQUECIMENTO no padrão de nome (Victor, 05/10/2026). A lista é da 20261005m; insert idempotente.
insert into mkt.campanha_objetivos (codigo) values ('CARRINHO'), ('AQUECIMENTO') on conflict (codigo) do nothing;
-- Objetivo → fase (Victor, 05/10/2026). DISTRIBUIÇÃO de propósito sem fase automática (marca-se à mão na campanha).
insert into mkt_trafego.objetivo_fase (objetivo, fase)
select o, f from (values ('LEADS', 'captacao'), ('VENDAS', 'captacao'), ('LEMBRETE', 'lembrete'),
                         ('REMARKETING', 'remarketing'), ('CARRINHO', 'abertura_carrinho'), ('AQUECIMENTO', 'aquecimento')) v(o, f)
 where exists (select 1 from mkt.campanha_objetivos co where co.codigo = v.o);

-- ─── 5. Funções internas (sem grant para ninguém) ────────────────────────────────────────────────────────────────────
-- Id da conta normalizado: Meta sem "act_", Google só dígitos. Nulo se fora do formato.
create function mkt_trafego.conta_normalizar(p_plataforma text, p_id text) returns text
language sql immutable set search_path = '' as $$
  select case
           when v is null or v = '' then null
           when v !~ '^[A-Za-z0-9_-]{1,40}$' then null
           else v end
    from (select case p_plataforma
                   when 'meta' then regexp_replace(btrim(coalesce(p_id, '')), '^act_', '', 'i')
                   when 'google' then regexp_replace(btrim(coalesce(p_id, '')), '[^0-9]', '', 'g')
                   else btrim(coalesce(p_id, '')) end as v) x;
$$;

-- Fase efetiva da campanha: a correção à mão prevalece; senão a do objetivo; senão nula ("sem fase").
create function mkt_trafego.fase_efetiva(p_objetivo text, p_manual text) returns text
language sql stable set search_path = '' as $$
  select coalesce(p_manual, (select o.fase from mkt_trafego.objetivo_fase o where o.objetivo = p_objetivo));
$$;

-- "Ontem" no fuso de São Paulo: último dia completo (o dia corrente ainda está acontecendo na plataforma).
create function mkt_trafego.ontem() returns date
language sql stable set search_path = '' as $$
  select ((now() at time zone 'America/Sao_Paulo')::date - 1);
$$;

-- Relê o nome da campanha pelo padrão da casa e aplica: projeto (se não foi ligado à mão), gestor, objetivo, página.
create function mkt_trafego.campanha_aplicar_leitura(p_campanha bigint) returns boolean
language plpgsql set search_path = '' as $$
declare
  c mkt_trafego.campanhas%rowtype;
  v_l jsonb;
  v_proj bigint;
begin
  select * into c from mkt_trafego.campanhas where id = p_campanha for update;
  if not found then return false; end if;
  v_l := mkt.campanha_traduzir(c.nome);
  v_proj := case when c.projeto_manual then c.projeto_id else nullif(v_l ->> 'projeto_id', '')::bigint end;
  if v_l is not distinct from c.leitura and v_proj is not distinct from c.projeto_id then return false; end if;
  update mkt_trafego.campanhas
     set leitura = v_l,
         fora_padrao = not coalesce((v_l ->> 'padrao')::boolean, false),
         gestor = v_l ->> 'gestor',
         objetivo = v_l ->> 'objetivo',
         pagina_id = nullif(v_l ->> 'pagina_id', '')::bigint,
         projeto_id = v_proj,
         atualizado_em = now()
   where id = p_campanha;
  return true;
end
$$;

-- Resumo por projeto: as colunas da Central do Tráfego. p_projeto nulo = todos os projetos de mkt.projetos.
-- O que ainda não tem fonte volta NULO (nunca zero inventado):
--   investido etc.: nulo enquanto não houver nenhuma linha de desempenho das campanhas do projeto (antes da coleta).
--   leads e mql: da base de pessoas (pessoas.eventos, 20261005o); nulos se a base não existir. Pessoa de teste e
--     pessoa mesclada não contam.
--   receita: nula (Hotmart ainda não ligada ao projeto).
--   page views e leads da página: a MESMA regra de public.mkt_web_connect (20261005q; mudou lá, muda aqui): visitas
--     (mkt_web.sessoes, sem teste) do projeto cuja campanha casa com uma campanha do Tráfego do projeto (campaign_id =
--     campanha_externa, ou utm_campaign = nome exato, ou utm_campaign = campanha_externa); uma por visita. leads da
--     página = dessas visitas, as que viraram lead (sessoes.lead), o mesmo numerador da conversão da Web.
--     connect rate = page views ÷ cliques no link; conversão da página = leads da página ÷ page views.
--     Nulos se a 20261005q não estiver aplicada ou se o projeto não tiver campanha no Tráfego.
-- As fórmulas são as mesmas de web/modules/marketing/trafego/domain/kpis.ts (testes em kpis.test.ts).
create function mkt_trafego.resumo(p_projeto bigint default null) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_ontem date := mkt_trafego.ontem();
  v_leads jsonb;
  v_pv jsonb;
  v_res jsonb;
begin
  if to_regprocedure('public.mkt_web_connect(bigint,date,date)') is not null then
    execute $q$
      select coalesce(jsonb_object_agg(x.projeto_id::text, jsonb_build_object('pv', x.pv, 'leads', x.leads)), '{}'::jsonb)
        from (select c.projeto_id, count(distinct s.id) as pv, count(distinct s.id) filter (where s.lead) as leads
                from mkt_trafego.campanhas c
                join mkt_web.sessoes s
                  on s.projeto_id = c.projeto_id and not s.teste
                 and (s.campaign_id = c.campanha_externa or s.utm_campaign = c.nome or s.utm_campaign = c.campanha_externa)
               where c.projeto_id is not null and ($1 is null or c.projeto_id = $1)
               group by c.projeto_id) x
    $q$ into v_pv using p_projeto;
  end if;

  if to_regclass('pessoas.eventos') is not null and to_regclass('pessoas.pessoas') is not null then
    execute $q$
      select coalesce(jsonb_object_agg(x.projeto_id::text, jsonb_build_object('leads', x.leads, 'mql', x.mql)), '{}'::jsonb)
        from (select e.projeto_id,
                     count(distinct e.pessoa_id) filter (where e.tipo = 'lead') as leads,
                     count(distinct e.pessoa_id) filter (where e.tipo = 'mql') as mql
                from pessoas.eventos e
                join pessoas.pessoas p on p.id = e.pessoa_id
               where e.projeto_id is not null and e.tipo in ('lead', 'mql')
                 and not p.teste and p.situacao <> 'mesclada'
                 and ($1 is null or e.projeto_id = $1)
               group by e.projeto_id) x
    $q$ into v_leads using p_projeto;
  end if;

  with d as (
    select c.projeto_id, c.plataforma,
           sum(dd.gasto) as gasto, sum(dd.impressoes) as impressoes, sum(dd.cliques_link) as cliques_link,
           sum(dd.cliques_total) as cliques_total,
           sum(dd.leads_plataforma) as leads_plataforma,
           sum(dd.gasto) filter (where dd.dia = v_ontem) as gasto_ontem,
           max(dd.dia) as ultimo_dia
      from mkt_trafego.desempenho_dia dd
      join mkt_trafego.campanhas c on c.id = dd.campanha_id
     where c.projeto_id is not null and (p_projeto is null or c.projeto_id = p_projeto)
     group by c.projeto_id, c.plataforma
  ), g as (
    select d.projeto_id, sum(d.gasto) as gasto, sum(d.impressoes) as impressoes, sum(d.cliques_link) as cliques_link,
           sum(d.cliques_total) as cliques_total,
           sum(d.leads_plataforma) as leads_plataforma, coalesce(sum(d.gasto_ontem), 0) as gasto_ontem,
           max(d.ultimo_dia) as ultimo_dia,
           jsonb_object_agg(d.plataforma, d.gasto) as por_plataforma
      from d group by d.projeto_id
  ), cp as (
    select c.projeto_id, count(*) as campanhas, count(*) filter (where c.fora_padrao) as fora_padrao,
           array_agg(distinct c.gestor) filter (where c.gestor is not null) as gestores,
           array_agg(distinct ct.moeda) as moedas
      from mkt_trafego.campanhas c
      join mkt_trafego.contas ct on ct.id = c.conta_id
     where c.projeto_id is not null and (p_projeto is null or c.projeto_id = p_projeto)
     group by c.projeto_id
  ), base as (
    select p.id, p.sigla, p.nome, p.subarea_trafego, p.ativo, p.etiqueta_clickup, p.inicio, p.fim,
           pl.status, sp.nome as status_nome, pl.verba_maxima, pl.verba_diaria,
           coalesce((select array_agg(pgs.gestor order by pgs.gestor) from mkt_trafego.projeto_gestores pgs
                      where pgs.projeto_id = p.id), '{}') as gestores_projeto,
           pl.meta_leads, pl.meta_receita, pl.meta_cpl, pl.meta_pct_mql, pl.obs,
           g.gasto, g.impressoes, g.cliques_link, g.cliques_total, g.leads_plataforma,
           case when v_pv is null or cp.campanhas is null then null
                else coalesce((v_pv -> p.id::text ->> 'pv')::bigint, 0) end as page_views,
           case when v_pv is null or cp.campanhas is null then null
                else coalesce((v_pv -> p.id::text ->> 'leads')::bigint, 0) end as leads_pagina, g.gasto_ontem, g.ultimo_dia, g.por_plataforma,
           coalesce(cp.campanhas, 0) as campanhas, coalesce(cp.fora_padrao, 0) as fora_padrao,
           coalesce(cp.gestores, '{}') as gestores, coalesce(cp.moedas, '{}') as moedas,
           case when v_leads is null then null else coalesce((v_leads -> p.id::text ->> 'leads')::bigint, 0) end as leads,
           case when v_leads is null then null else coalesce((v_leads -> p.id::text ->> 'mql')::bigint, 0) end as mql,
           (select coalesce(sum(f.verba), 0) from mkt_trafego.projeto_fases f where f.projeto_id = p.id) as verba_fases,
           (select count(*) from mkt_trafego.projeto_fases f where f.projeto_id = p.id) as fases
      from mkt.projetos p
      left join mkt_trafego.planejamento pl on pl.projeto_id = p.id
      left join mkt_trafego.status_projeto sp on sp.codigo = pl.status
      left join g on g.projeto_id = p.id
      left join cp on cp.projeto_id = p.id
     where p_projeto is null or p.id = p_projeto
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'projeto_id', b.id, 'sigla', b.sigla, 'nome', b.nome, 'subarea', b.subarea_trafego,
           'tipo', case when b.subarea_trafego is null then null when b.subarea_trafego = 'interno' then 'interno' else 'externo' end,
           'projeto_ativo', b.ativo, 'etiqueta_clickup', b.etiqueta_clickup, 'inicio', b.inicio, 'fim', b.fim,
           'status', b.status, 'status_nome', b.status_nome, 'gestores', to_jsonb(b.gestores_projeto),
           'gestores_campanhas', to_jsonb(b.gestores),
           'receita', null,
           'investido', b.gasto, 'por_plataforma', b.por_plataforma, 'moedas', to_jsonb(b.moedas),
           'verba_maxima', b.verba_maxima, 'verba_diaria', b.verba_diaria, 'verba_fases', b.verba_fases, 'fases', b.fases,
           'pct_verba', case when b.gasto is not null and b.verba_maxima > 0 then round(b.gasto / b.verba_maxima * 100, 1) end,
           'impressoes', b.impressoes, 'cliques_link', b.cliques_link, 'cliques_total', b.cliques_total,
           'leads_plataforma', b.leads_plataforma, 'page_views', b.page_views, 'leads_pagina', b.leads_pagina,
           'leads', b.leads, 'mql', b.mql,
           'cpl', case when b.gasto is not null and b.leads > 0 then round(b.gasto / b.leads, 2) end,
           'ctr', case when b.impressoes > 0 then round(b.cliques_link::numeric / b.impressoes * 100, 2) end,
           'cpc', case when b.cliques_link > 0 then round(b.gasto / b.cliques_link, 2) end,
           'cpm', case when b.impressoes > 0 then round(b.gasto / b.impressoes * 1000, 2) end,
           'pct_mql', case when b.leads > 0 then round(b.mql::numeric / b.leads * 100, 1) end,
           'connect_rate', case when b.page_views is not null and b.cliques_link > 0
                                then round(b.page_views::numeric / b.cliques_link * 100, 1) end,
           'conversao_pagina', case when b.page_views > 0 then round(b.leads_pagina::numeric / b.page_views * 100, 1) end,
           'gasto_ontem', case when b.gasto is not null then b.gasto_ontem end, 'dia_ontem', v_ontem,
           'ritmo_ontem', case when b.gasto is not null and b.verba_diaria > 0 then round(b.gasto_ontem / b.verba_diaria * 100, 1) end,
           'ultimo_dia', b.ultimo_dia,
           'meta_leads', b.meta_leads, 'meta_receita', b.meta_receita, 'meta_cpl', b.meta_cpl, 'meta_pct_mql', b.meta_pct_mql,
           'obs', b.obs, 'campanhas', b.campanhas, 'campanhas_fora_padrao', b.fora_padrao)
         order by b.ativo desc, b.sigla), '[]'::jsonb)
    into v_res
    from base b;
  return v_res;
end
$$;

-- ─── 6. Funções públicas da tela (authenticated + mkt.pode_ver('mkt_trafego')) ───────────────────────────────────────
create function public.trafego_config() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object(
    'plataformas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nome', x.nome) order by x.codigo desc), '[]'::jsonb)
                      from mkt_trafego.plataformas x where x.ativa),
    'status', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nome', x.nome) order by x.ordem), '[]'::jsonb)
                 from mkt_trafego.status_projeto x where x.ativo),
    'fases', (select coalesce(jsonb_agg(jsonb_build_object('codigo', x.codigo, 'nome', x.nome) order by x.ordem), '[]'::jsonb)
                from mkt_trafego.fases x where x.ativa),
    'objetivo_fase', (select coalesce(jsonb_object_agg(o.objetivo, o.fase), '{}'::jsonb) from mkt_trafego.objetivo_fase o),
    'gestores', (select coalesce(jsonb_agg(jsonb_build_object('sigla', g.sigla, 'nome', g.nome) order by g.sigla), '[]'::jsonb)
                   from mkt.campanha_gestores g where g.ativo),
    'base_pessoas', to_regclass('pessoas.eventos') is not null,
    'base_web', to_regprocedure('public.mkt_web_connect(bigint,date,date)') is not null,
    'dia_ontem', mkt_trafego.ontem());
end
$$;

create function public.trafego_contas_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', c.id, 'plataforma', c.plataforma, 'conta_externa', c.conta_externa, 'nome', c.nome, 'dono', c.dono,
            'cliente', c.cliente, 'moeda', c.moeda, 'ativa', c.ativa, 'obs', c.obs, 'atualizado_em', c.atualizado_em,
            'campanhas', (select count(*) from mkt_trafego.campanhas k where k.conta_id = c.id))
          order by c.ativa desc, c.plataforma, c.nome), '[]'::jsonb)
            from mkt_trafego.contas c);
end
$$;

-- Cria (sem "id") ou edita (com "id"). Campos: plataforma, conta_externa, nome, dono, cliente, moeda, ativa, obs.
-- A plataforma de uma conta com campanhas não muda. Retorna {ok, msg, id}.
create function public.trafego_conta_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint;
  v_plat text := lower(btrim(coalesce(p ->> 'plataforma', '')));
  v_ext text;
  v_nome text := btrim(coalesce(p ->> 'nome', ''));
  v_dono text := lower(btrim(coalesce(p ->> 'dono', '')));
  v_cliente text := nullif(btrim(coalesce(p ->> 'cliente', '')), '');
  v_moeda text := upper(coalesce(nullif(btrim(coalesce(p ->> 'moeda', '')), ''), 'BRL'));
  v_ativa boolean;
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_atual mkt_trafego.contas%rowtype;
  v_con text;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_ativa := coalesce((p ->> 'ativa')::boolean, true);
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo em formato inválido.');
  end;
  if not exists (select 1 from mkt_trafego.plataformas where codigo = v_plat) then
    return jsonb_build_object('ok', false, 'msg', 'Escolha a plataforma.');
  end if;
  v_ext := mkt_trafego.conta_normalizar(v_plat, p ->> 'conta_externa');
  if v_ext is null then
    return jsonb_build_object('ok', false, 'msg', 'Id da conta inválido (Meta: números, com ou sem act_; Google: 123-456-7890).');
  end if;
  if length(v_nome) < 2 then return jsonb_build_object('ok', false, 'msg', 'Informe o nome da conta.'); end if;
  if v_dono not in ('grupo', 'diamante', 'aurum') then
    return jsonb_build_object('ok', false, 'msg', 'De quem é a conta: grupo, diamante ou aurum.');
  end if;
  if v_moeda !~ '^[A-Z]{3}$' then return jsonb_build_object('ok', false, 'msg', 'Moeda: 3 letras (ex.: BRL).'); end if;

  begin
    if v_id is null then
      insert into mkt_trafego.contas (plataforma, conta_externa, nome, dono, cliente, moeda, ativa, obs, criado_por, atualizado_por)
      values (v_plat, v_ext, v_nome, v_dono, v_cliente, v_moeda, v_ativa, v_obs, v_uid, v_uid)
      returning id into v_id;
      return jsonb_build_object('ok', true, 'msg', 'Conta ' || v_nome || ' criada.', 'id', v_id);
    end if;
    select * into v_atual from mkt_trafego.contas where id = v_id for update;
    if not found then return jsonb_build_object('ok', false, 'msg', 'Conta não encontrada.'); end if;
    if v_atual.plataforma <> v_plat and exists (select 1 from mkt_trafego.campanhas where conta_id = v_id) then
      return jsonb_build_object('ok', false, 'msg', 'A conta já tem campanhas: a plataforma não muda.');
    end if;
    update mkt_trafego.contas
       set plataforma = v_plat, conta_externa = v_ext, nome = v_nome, dono = v_dono, cliente = v_cliente, moeda = v_moeda,
           ativa = v_ativa, obs = v_obs, atualizado_em = now(), atualizado_por = v_uid
     where id = v_id;
    return jsonb_build_object('ok', true, 'msg', 'Conta ' || v_nome || ' salva.', 'id', v_id);
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'msg', 'Esta conta (' || v_plat || ' ' || v_ext || ') já está cadastrada.');
    when check_violation then
      get stacked diagnostics v_con = constraint_name;
      return jsonb_build_object('ok', false, 'msg', 'Valor fora da regra (' || v_con || ').');
  end;
end
$$;

-- Planejamento do projeto (upsert por projeto_id). Campos: projeto_id, status, gestores (lista de siglas; a lista
-- inteira substitui a anterior; ausente = não mexe), verba_maxima, verba_diaria, meta_leads, meta_receita, meta_cpl,
-- meta_pct_mql, obs. Vazio vira nulo. Retorna {ok, msg, avisos}.
create function public.trafego_planejamento_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_proj bigint;
  v_sigla text;
  v_status text := nullif(lower(btrim(coalesce(p ->> 'status', ''))), '');
  v_gestores text[];
  v_vmax numeric; v_vdia numeric; v_mleads integer; v_mrec numeric; v_mcpl numeric; v_mmql numeric;
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_fases numeric;
  v_avisos text[] := '{}';
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_proj := nullif(p ->> 'projeto_id', '')::bigint;
    v_vmax := nullif(btrim(coalesce(p ->> 'verba_maxima', '')), '')::numeric;
    v_vdia := nullif(btrim(coalesce(p ->> 'verba_diaria', '')), '')::numeric;
    v_mleads := nullif(btrim(coalesce(p ->> 'meta_leads', '')), '')::integer;
    v_mrec := nullif(btrim(coalesce(p ->> 'meta_receita', '')), '')::numeric;
    v_mcpl := nullif(btrim(coalesce(p ->> 'meta_cpl', '')), '')::numeric;
    v_mmql := nullif(btrim(coalesce(p ->> 'meta_pct_mql', '')), '')::numeric;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Número em formato inválido (use ponto para decimais).');
  end;
  select sigla into v_sigla from mkt.projetos where id = v_proj;
  if v_sigla is null then return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.'); end if;
  if v_status is not null and not exists (select 1 from mkt_trafego.status_projeto where codigo = v_status and ativo) then
    return jsonb_build_object('ok', false, 'msg', 'Status fora da lista.');
  end if;
  if p ? 'gestores' then
    if jsonb_typeof(p -> 'gestores') is distinct from 'array' then
      return jsonb_build_object('ok', false, 'msg', 'Gestores: uma lista de siglas.');
    end if;
    select coalesce(array_agg(distinct upper(btrim(x))), '{}') into v_gestores
      from jsonb_array_elements_text(p -> 'gestores') x where btrim(x) <> '';
    if exists (select 1 from unnest(v_gestores) g
                where not exists (select 1 from mkt.campanha_gestores cg where cg.sigla = g and cg.ativo)) then
      return jsonb_build_object('ok', false, 'msg', 'Gestor fora da lista.');
    end if;
  end if;
  if coalesce(v_vmax, 1) <= 0 or coalesce(v_vdia, 1) <= 0 or coalesce(v_mleads, 1) <= 0 or coalesce(v_mrec, 1) <= 0
     or coalesce(v_mcpl, 1) <= 0 then
    return jsonb_build_object('ok', false, 'msg', 'Verba e metas precisam ser maiores que zero (ou vazias).');
  end if;
  if v_mmql is not null and (v_mmql < 0 or v_mmql > 100) then
    return jsonb_build_object('ok', false, 'msg', 'Meta de % MQL entre 0 e 100.');
  end if;
  if v_vmax >= 1e12 or v_vdia >= 1e12 or v_mrec >= 1e12 or v_mcpl >= 1e12 then
    return jsonb_build_object('ok', false, 'msg', 'Valor grande demais.');
  end if;

  insert into mkt_trafego.planejamento as pl (projeto_id, status, verba_maxima, verba_diaria, meta_leads, meta_receita,
                                              meta_cpl, meta_pct_mql, obs, atualizado_por)
  values (v_proj, v_status, v_vmax, v_vdia, v_mleads, v_mrec, v_mcpl, v_mmql, v_obs, v_uid)
  on conflict (projeto_id) do update
     set status = excluded.status, verba_maxima = excluded.verba_maxima,
         verba_diaria = excluded.verba_diaria, meta_leads = excluded.meta_leads, meta_receita = excluded.meta_receita,
         meta_cpl = excluded.meta_cpl, meta_pct_mql = excluded.meta_pct_mql, obs = excluded.obs,
         atualizado_em = now(), atualizado_por = excluded.atualizado_por;

  if v_gestores is not null then
    delete from mkt_trafego.projeto_gestores where projeto_id = v_proj and gestor <> all (v_gestores);
    insert into mkt_trafego.projeto_gestores (projeto_id, gestor, atualizado_por)
    select v_proj, g, v_uid from unnest(v_gestores) g
    on conflict (projeto_id, gestor) do nothing;
  end if;

  select sum(verba) into v_fases from mkt_trafego.projeto_fases where projeto_id = v_proj;
  if v_vmax is not null and v_fases > v_vmax then v_avisos := array_append(v_avisos, 'fases_acima_da_verba'); end if;
  if v_vmax is not null and v_vdia > v_vmax then v_avisos := array_append(v_avisos, 'diaria_acima_da_maxima'); end if;
  return jsonb_build_object('ok', true, 'msg', 'Planejamento de ' || v_sigla || ' salvo.', 'avisos', to_jsonb(v_avisos));
end
$$;

-- Fase do projeto: cria (sem "id") ou edita (com "id"). Campos: projeto_id, fase, verba, inicio, fim, obs.
create function public.trafego_fase_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint; v_proj bigint; v_verba numeric; v_inicio date; v_fim date;
  v_fase text := lower(btrim(coalesce(p ->> 'fase', '')));
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_atual mkt_trafego.projeto_fases%rowtype;
  v_vmax numeric; v_soma numeric;
  v_avisos text[] := '{}';
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_proj := nullif(p ->> 'projeto_id', '')::bigint;
    v_verba := nullif(btrim(coalesce(p ->> 'verba', '')), '')::numeric;
    v_inicio := nullif(btrim(coalesce(p ->> 'inicio', '')), '')::date;
    v_fim := nullif(btrim(coalesce(p ->> 'fim', '')), '')::date;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Verba ou data em formato inválido.');
  end;
  if not exists (select 1 from mkt.projetos where id = v_proj) then
    return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.');
  end if;
  if not exists (select 1 from mkt_trafego.fases where codigo = v_fase and ativa) then
    return jsonb_build_object('ok', false, 'msg', 'Fase fora da lista.');
  end if;
  if v_verba is not null and (v_verba < 0 or v_verba >= 1e12) then
    return jsonb_build_object('ok', false, 'msg', 'Verba da fase inválida.');
  end if;
  if v_inicio is not null and v_fim is not null and v_fim < v_inicio then
    return jsonb_build_object('ok', false, 'msg', 'O fim não pode ser antes do início.');
  end if;

  begin
    if v_id is null then
      insert into mkt_trafego.projeto_fases (projeto_id, fase, verba, inicio, fim, obs, atualizado_por)
      values (v_proj, v_fase, v_verba, v_inicio, v_fim, v_obs, v_uid) returning id into v_id;
    else
      select * into v_atual from mkt_trafego.projeto_fases where id = v_id for update;
      if not found then return jsonb_build_object('ok', false, 'msg', 'Fase não encontrada.'); end if;
      if v_atual.projeto_id <> v_proj then
        return jsonb_build_object('ok', false, 'msg', 'A fase é de outro projeto.');
      end if;
      update mkt_trafego.projeto_fases
         set fase = v_fase, verba = v_verba, inicio = v_inicio, fim = v_fim, obs = v_obs,
             atualizado_em = now(), atualizado_por = v_uid
       where id = v_id;
    end if;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'Este projeto já tem esta fase.');
  end;

  select verba_maxima into v_vmax from mkt_trafego.planejamento where projeto_id = v_proj;
  select sum(verba) into v_soma from mkt_trafego.projeto_fases where projeto_id = v_proj;
  if v_vmax is not null and v_soma > v_vmax then v_avisos := array_append(v_avisos, 'fases_acima_da_verba'); end if;
  return jsonb_build_object('ok', true, 'msg', 'Fase salva.', 'id', v_id, 'avisos', to_jsonb(v_avisos));
end
$$;

-- Apaga o planejamento de uma fase do projeto. As campanhas continuam na fase delas (pelo objetivo ou à mão): o gasto
-- aparece na fase, sem verba planejada.
create function public.trafego_fase_apagar(p_fase bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not exists (select 1 from mkt_trafego.projeto_fases where id = p_fase) then
    return jsonb_build_object('ok', false, 'msg', 'Fase não encontrada.');
  end if;
  delete from mkt_trafego.projeto_fases where id = p_fase;
  return jsonb_build_object('ok', true, 'msg', 'Planejamento da fase apagado. As campanhas dela continuam contando nela, sem verba planejada.');
end
$$;

-- Campanhas. p_projeto = só as do projeto; p_sem_projeto = só as que não têm projeto; p_fora_padrao = só fora do padrão.
create function public.trafego_campanhas_listar(p_projeto bigint default null, p_sem_projeto boolean default false,
                                                p_fora_padrao boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', c.id, 'plataforma', c.plataforma, 'conta_id', c.conta_id, 'conta', ct.nome, 'moeda', ct.moeda,
            'campanha_externa', c.campanha_externa, 'nome', c.nome, 'status_plataforma', c.status_plataforma,
            'fora_padrao', c.fora_padrao, 'erros', coalesce(c.leitura -> 'erros', '[]'::jsonb),
            'avisos', coalesce(c.leitura -> 'avisos', '[]'::jsonb),
            'gestor', c.gestor, 'objetivo', c.objetivo, 'descricao', c.leitura ->> 'descricao', 'pagina', c.leitura ->> 'pagina',
            'pagina_id', c.pagina_id, 'projeto_id', c.projeto_id, 'projeto_sigla', pr.sigla, 'projeto_manual', c.projeto_manual,
            'fase', mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual), 'fase_manual', c.fase_manual,
            'fase_objetivo', (select o.fase from mkt_trafego.objetivo_fase o where o.objetivo = c.objetivo),
            'gasto', s.gasto, 'impressoes', s.impressoes, 'cliques_link', s.cliques_link, 'cliques_total', s.cliques_total,
            'leads_plataforma', s.leads_plataforma,
            'ultimo_dia', s.ultimo_dia, 'ultima_coleta', c.ultima_coleta)
          order by c.fora_padrao desc, s.gasto desc nulls last, c.nome), '[]'::jsonb)
            from mkt_trafego.campanhas c
            join mkt_trafego.contas ct on ct.id = c.conta_id
            left join mkt.projetos pr on pr.id = c.projeto_id
            left join lateral (select sum(d.gasto) as gasto, sum(d.impressoes) as impressoes, sum(d.cliques_link) as cliques_link,
                                      sum(d.cliques_total) as cliques_total,
                                      sum(d.leads_plataforma) as leads_plataforma, max(d.dia) as ultimo_dia
                                 from mkt_trafego.desempenho_dia d where d.campanha_id = c.id) s on true
           where (p_projeto is null or c.projeto_id = p_projeto)
             and (not coalesce(p_sem_projeto, false) or c.projeto_id is null)
             and (not coalesce(p_fora_padrao, false) or c.fora_padrao));
end
$$;

-- Ajuste à mão da campanha. Campos: id; projeto_id (só se a chave vier: número = liga à mão; nulo = volta a valer o
-- nome); fase (só se a chave vier: código = correção à mão; nulo ou vazio = volta a valer o objetivo).
create function public.trafego_campanha_ajustar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint; v_proj bigint;
  v_fase text := nullif(lower(btrim(coalesce(p ->> 'fase', ''))), '');
  c mkt_trafego.campanhas%rowtype;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_proj := nullif(p ->> 'projeto_id', '')::bigint;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo em formato inválido.');
  end;
  select * into c from mkt_trafego.campanhas where id = v_id for update;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Campanha não encontrada.'); end if;
  if v_proj is not null and not exists (select 1 from mkt.projetos where id = v_proj) then
    return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.');
  end if;
  if p ? 'fase' and v_fase is not null and not exists (select 1 from mkt_trafego.fases where codigo = v_fase and ativa) then
    return jsonb_build_object('ok', false, 'msg', 'Fase fora da lista.');
  end if;

  if p ? 'projeto_id' then
    if v_proj is not null then
      update mkt_trafego.campanhas
         set projeto_id = v_proj, projeto_manual = true, atualizado_em = now(), atualizado_por = (select auth.uid())
       where id = v_id;
    else
      update mkt_trafego.campanhas set projeto_manual = false, atualizado_por = (select auth.uid()) where id = v_id;
      perform mkt_trafego.campanha_aplicar_leitura(v_id);
    end if;
  end if;
  if p ? 'fase' then
    update mkt_trafego.campanhas set fase_manual = v_fase, atualizado_em = now(), atualizado_por = (select auth.uid())
     where id = v_id;
  end if;
  select * into c from mkt_trafego.campanhas where id = v_id;
  return jsonb_build_object('ok', true, 'msg', 'Campanha ajustada.', 'projeto_id', c.projeto_id,
                            'fase', mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual));
end
$$;

-- Relê o nome de todas as campanhas (depois de cadastrar um projeto, uma página ou um gestor novo).
create function public.trafego_campanhas_reler() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_n int := 0;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  for v_id in select id from mkt_trafego.campanhas order by id loop
    if mkt_trafego.campanha_aplicar_leitura(v_id) then v_n := v_n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'msg', v_n || ' campanha(s) mudaram com a nova leitura.', 'mudaram', v_n);
end
$$;

create function public.trafego_resumo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return mkt_trafego.resumo(null);
end
$$;

-- "A vida do projeto": resumo (as mesmas colunas da tabela), fases planejado × gasto, gasto sem fase, série diária
-- (últimos 120 dias com dado), campanhas do projeto.
create function public.trafego_projeto(p_projeto bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_r jsonb;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not exists (select 1 from mkt.projetos where id = p_projeto) then return null; end if;
  v_r := mkt_trafego.resumo(p_projeto) -> 0;
  return jsonb_build_object(
    'resumo', v_r,
    -- uma linha por fase planejada OU com campanha do projeto nela (pelo objetivo ou à mão); id nulo = sem planejamento
    'fases', (with cf as (select c.id, mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) as fase
                            from mkt_trafego.campanhas c where c.projeto_id = p_projeto),
                   g as (select cf.fase, count(*) as campanhas,
                                (select sum(d.gasto) from mkt_trafego.desempenho_dia d
                                  where d.campanha_id in (select x.id from cf x where x.fase = cf.fase)) as gasto
                           from cf where cf.fase is not null group by cf.fase)
              select coalesce(jsonb_agg(jsonb_build_object(
                       'id', f.id, 'fase', fs.codigo, 'nome', fs.nome, 'verba', f.verba, 'inicio', f.inicio, 'fim', f.fim,
                       'obs', f.obs, 'gasto', g.gasto, 'campanhas', coalesce(g.campanhas, 0))
                     order by fs.ordem), '[]'::jsonb)
                from mkt_trafego.fases fs
                left join mkt_trafego.projeto_fases f on f.fase = fs.codigo and f.projeto_id = p_projeto
                left join g on g.fase = fs.codigo
               where f.id is not null or g.fase is not null),
    'campanhas_sem_fase', (select count(*) from mkt_trafego.campanhas c
                            where c.projeto_id = p_projeto and mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) is null),
    'gasto_sem_fase', (select sum(d.gasto) from mkt_trafego.desempenho_dia d join mkt_trafego.campanhas c on c.id = d.campanha_id
                        where c.projeto_id = p_projeto and mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) is null),
    'serie', (select coalesce(jsonb_agg(jsonb_build_object('dia', x.dia, 'gasto', x.gasto, 'impressoes', x.impressoes,
                                                           'cliques_link', x.cliques_link, 'leads_plataforma', x.leads_plataforma)
                                        order by x.dia), '[]'::jsonb)
                from (select d.dia, sum(d.gasto) as gasto, sum(d.impressoes) as impressoes, sum(d.cliques_link) as cliques_link,
                             sum(d.leads_plataforma) as leads_plataforma
                        from mkt_trafego.desempenho_dia d join mkt_trafego.campanhas c on c.id = d.campanha_id
                       where c.projeto_id = p_projeto
                       group by d.dia order by d.dia desc limit 120) x),
    'campanhas', public.trafego_campanhas_listar(p_projeto, false, false));
end
$$;

-- ─── 7. Entrada da coleta (etapa 2). Só service_role (a rotina do servidor) ──────────────────────────────────────────
-- p = lista de {plataforma, conta, id, nome, status}. Upsert idempotente por (plataforma, id). A conta precisa estar
-- cadastrada (o cadastro é à mão). Nome mudou na plataforma → nome e leitura atualizados. Retorna contagens e recusas.
create function public.trafego_campanhas_receber(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e jsonb;
  v_plat text; v_conta bigint; v_ext text; v_nome text; v_status text; v_id bigint; v_novo boolean;
  v_novas int := 0; v_atual int := 0;
  v_recusas jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava uma lista.');
  end if;
  if jsonb_array_length(p) > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000 por chamada).');
  end if;
  for e in select * from jsonb_array_elements(p) loop
    v_plat := lower(btrim(coalesce(e ->> 'plataforma', '')));
    v_ext := nullif(btrim(coalesce(e ->> 'id', '')), '');
    v_nome := coalesce(e ->> 'nome', '');
    v_status := nullif(left(btrim(coalesce(e ->> 'status', '')), 40), '');
    select c.id into v_conta from mkt_trafego.contas c
     where c.plataforma = v_plat and c.conta_externa = mkt_trafego.conta_normalizar(v_plat, e ->> 'conta');
    if v_conta is null then
      v_recusas := v_recusas || jsonb_build_object('id', v_ext, 'motivo', 'conta_nao_cadastrada');
      continue;
    end if;
    if v_ext is null or v_ext !~ '^[A-Za-z0-9_-]{1,60}$' then
      v_recusas := v_recusas || jsonb_build_object('id', v_ext, 'motivo', 'id_invalido');
      continue;
    end if;
    if length(v_nome) < 1 or length(v_nome) > 400 then
      v_recusas := v_recusas || jsonb_build_object('id', v_ext, 'motivo', 'nome_invalido');
      continue;
    end if;
    insert into mkt_trafego.campanhas as c (plataforma, conta_id, campanha_externa, nome, status_plataforma, leitura, fora_padrao)
    values (v_plat, v_conta, v_ext, v_nome, v_status, '{}'::jsonb, true)
    on conflict (plataforma, campanha_externa) do update
       set nome = excluded.nome, status_plataforma = excluded.status_plataforma, conta_id = excluded.conta_id,
           ultima_coleta = now()
    returning c.id, (xmax = 0) into v_id, v_novo;
    perform mkt_trafego.campanha_aplicar_leitura(v_id);
    if v_novo then v_novas := v_novas + 1; else v_atual := v_atual + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'novas', v_novas, 'atualizadas', v_atual, 'recusas', v_recusas);
end
$$;

-- p = lista de {plataforma, campanha, dia, gasto, impressoes, cliques_link, cliques_total, leads}. cliques_link = cliques
-- no link (Meta inline_link_clicks), o do CTR; cliques_total = todos (opcional). Upsert por (campanha, dia): reenviar o
-- mesmo dia sobrescreve (idempotente). Campanha desconhecida → recusa (receber a campanha antes).
create function public.trafego_desempenho_receber(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e jsonb;
  v_camp bigint; v_dia date; v_gasto numeric; v_imp bigint; v_cli bigint; v_tot bigint; v_leads integer;
  v_n int := 0;
  v_recusas jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava uma lista.');
  end if;
  if jsonb_array_length(p) > 20000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 20000 por chamada).');
  end if;
  for e in select * from jsonb_array_elements(p) loop
    select c.id into v_camp from mkt_trafego.campanhas c
     where c.plataforma = lower(btrim(coalesce(e ->> 'plataforma', ''))) and c.campanha_externa = btrim(coalesce(e ->> 'campanha', ''));
    if v_camp is null then
      v_recusas := v_recusas || jsonb_build_object('campanha', e ->> 'campanha', 'dia', e ->> 'dia', 'motivo', 'campanha_desconhecida');
      continue;
    end if;
    begin
      v_dia := (e ->> 'dia')::date;
      v_gasto := coalesce((e ->> 'gasto')::numeric, 0);
      v_imp := coalesce((e ->> 'impressoes')::bigint, 0);
      v_cli := coalesce((e ->> 'cliques_link')::bigint, 0);
      v_tot := (e ->> 'cliques_total')::bigint;
      v_leads := (e ->> 'leads')::integer;
    exception when others then
      v_recusas := v_recusas || jsonb_build_object('campanha', e ->> 'campanha', 'dia', e ->> 'dia', 'motivo', 'formato_invalido');
      continue;
    end;
    if v_dia is null or v_dia > mkt_trafego.ontem() + 1 or v_gasto < 0 or v_imp < 0 or v_cli < 0 or v_tot < 0 or v_leads < 0
       or v_gasto >= 1e12 then
      v_recusas := v_recusas || jsonb_build_object('campanha', e ->> 'campanha', 'dia', e ->> 'dia', 'motivo', 'valor_invalido');
      continue;
    end if;
    insert into mkt_trafego.desempenho_dia (campanha_id, dia, gasto, impressoes, cliques_link, cliques_total, leads_plataforma, coletado_em)
    values (v_camp, v_dia, round(v_gasto, 2), v_imp, v_cli, v_tot, v_leads, now())
    on conflict (campanha_id, dia) do update
       set gasto = excluded.gasto, impressoes = excluded.impressoes, cliques_link = excluded.cliques_link,
           cliques_total = excluded.cliques_total,
           leads_plataforma = excluded.leads_plataforma, coletado_em = now();
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'gravadas', v_n, 'recusas', v_recusas);
end
$$;

-- ─── 8. Quem executa o quê ───────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'mkt_trafego'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end
$grants$;
grant execute on function
  public.trafego_config(), public.trafego_contas_listar(), public.trafego_conta_salvar(jsonb),
  public.trafego_planejamento_salvar(jsonb), public.trafego_fase_salvar(jsonb), public.trafego_fase_apagar(bigint),
  public.trafego_campanhas_listar(bigint, boolean, boolean), public.trafego_campanha_ajustar(jsonb),
  public.trafego_campanhas_reler(), public.trafego_resumo(), public.trafego_projeto(bigint)
  to authenticated;
grant execute on function public.trafego_campanhas_receber(jsonb), public.trafego_desempenho_receber(jsonb) to service_role;

-- ─── 9. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t record;
  f record;
  v_tela text[] := array['trafego_config', 'trafego_contas_listar', 'trafego_conta_salvar', 'trafego_planejamento_salvar',
                         'trafego_fase_salvar', 'trafego_fase_apagar', 'trafego_campanhas_listar', 'trafego_campanha_ajustar',
                         'trafego_campanhas_reler', 'trafego_resumo', 'trafego_projeto'];
  v_coleta text[] := array['trafego_campanhas_receber', 'trafego_desempenho_receber'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_trafego', 'usage') or has_schema_privilege(r, 'mkt_trafego', 'create') then
      raise exception '20261005p: % tem acesso ao schema mkt_trafego', r;
    end if;
  end loop;

  for t in select c.oid, c.relname, c.relrowsecurity from pg_class c
            where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t.oid, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005p: % tem privilégio em mkt_trafego.%', r, t.relname;
      end if;
    end loop;
    if not t.relrowsecurity then raise exception '20261005p: RLS desligada em mkt_trafego.%', t.relname; end if;
  end loop;
  if (select count(*) from pg_class c where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r') <> 10 then
    raise exception '20261005p: esperava 10 tabelas em mkt_trafego';
  end if;

  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where p.pronamespace = 'mkt_trafego'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') loop
    if not (f.proconfig @> array['search_path=""']) then
      raise exception '20261005p: % sem search_path vazio', f.sig;
    end if;
    if has_function_privilege('anon', f.sig, 'execute') then
      raise exception '20261005p: anon executa %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005p: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any(v_tela))
       <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261005p: grant de authenticated errado em %', f.sig;
    end if;
    if f.pronamespace = 'public'::regnamespace and f.proname = any(v_coleta)
       and (not has_function_privilege('service_role', f.sig, 'execute') or has_function_privilege('authenticated', f.sig, 'execute')) then
      raise exception '20261005p: grant da coleta errado em %', f.sig;
    end if;
    if f.pronamespace = 'public'::regnamespace and not f.prosecdef then
      raise exception '20261005p: % deveria ser SECURITY DEFINER', f.sig;
    end if;
  end loop;

  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') <> 13 then
    raise exception '20261005p: esperava 13 funções públicas trafego_*';
  end if;
  if not coalesce((mkt.campanha_traduzir('RS | PB26 | CARRINHO | ABERTURA') ->> 'objetivo') = 'CARRINHO'
                  and (mkt.campanha_traduzir('RS | PB26 | AQUECIMENTO | X') ->> 'objetivo') = 'AQUECIMENTO', false) then
    raise exception '20261005p: mkt.campanha_traduzir não reconhece CARRINHO ou AQUECIMENTO';
  end if;
  if (select count(*) from mkt_trafego.plataformas) <> 2 or (select count(*) from mkt_trafego.status_projeto) <> 4
     or (select count(*) from mkt_trafego.fases) <> 5 or (select count(*) from mkt_trafego.objetivo_fase) <> 6 or (select count(*) from mkt_trafego.contas) <> 0
     or (select count(*) from mkt_trafego.campanhas) <> 0 or (select count(*) from mkt_trafego.desempenho_dia) <> 0
     or (select count(*) from mkt_trafego.planejamento) <> 0 or (select count(*) from mkt_trafego.projeto_gestores) <> 0 then
    raise exception '20261005p: semente diferente do esperado (2 plataformas, 4 status, 5 fases, 6 objetivo→fase, resto vazio)';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação; apaga contas, campanhas, desempenho e planejamento: exportar antes se houver dado) ═══
-- begin;
-- do $$ declare f regprocedure; begin
--   for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%'
--   loop execute format('drop function %s', f); end loop; end $$;
-- drop schema mkt_trafego cascade;
-- delete from mkt.campanha_objetivos where codigo in ('CARRINHO', 'AQUECIMENTO');  -- só se nenhuma campanha os usa
-- commit;
