-- 20261005p: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql).
--   Todo resultado vai para a tabela temporária _z_out; o penúltimo comando mostra tudo.
--   Se o cliente só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia, e rode
--   o "rollback;" em seguida. NÃO deixe a transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261005p_mkt_trafego.sql; se a migration
-- mudar, gerar de novo). Depois dele, os testes criam DADOS FICTÍCIOS (contas "Conta Ensaio …", campanhas com ids
-- 900000000000001…, um projeto ZZ27 "Projeto Ensaio", pessoas "… Ensaio Trafego") e chamam as funções como a tela e a
-- coleta chamariam (JWT simulado; role authenticated com o perfil admin do Victor, service_role e anon). Nenhum dado real
-- é lido para a saída. Tudo some no rollback.
--
-- Esperado: NENHUMA linha começando com "ERRADO". Cada linha diz o que conferiu. O passo 6.base só roda com a 20261005o
-- aplicada e o 6.web só com a 20261005q (Web fase 2) (senão "PULADO", e o 6 confere que leads, CPL, % MQL, page views,
-- connect rate e conversão ficam nulos).
--   1  estrutura: 10 tabelas, 13 funções; sementes (meta/google; ativo, pausado, inativo, encerrado; aquecimento,
--      captação, lembrete, remarketing, abertura de carrinho; objetivo→fase LEADS e VENDAS → captação,
--      LEMBRETE, REMARKETING, CARRINHO, AQUECIMENTO; DISTRIBUIÇÃO sem fase); objetivos CARRINHO e AQUECIMENTO novos na
--      lista de mkt e reconhecidos por mkt.campanha_traduzir; resto vazio
--   2  id da conta normalizado (Meta sem act_, Google só dígitos)
--   3  contas: criar, duplicada (com e sem act_) recusada, dono/plataforma/id inválidos recusados, listar
--   4  coleta (service_role): 5 campanhas novas, conta não cadastrada recusada, leitura do nome (projeto, gestor,
--      página), minúsculas = aviso, fora do padrão; reenvio idempotente; renomear muda o projeto; desempenho com 4
--      recusas (campanha desconhecida, formato, negativo, futuro); mesmo dia reenviado sobrescreve
--   5  planejamento (vários gestores; lista nova substitui; sem a chave não mexe), fases (aviso de soma acima da verba, duplicada e datas recusadas), fase da campanha
--      pelo objetivo (DISTRIBUIÇÃO sem fase), correção à mão prevalece e volta, planejado × gasto,
--      ligar à mão e voltar ao nome, reler depois de cadastrar projeto, apagar o planejamento da fase
--   6  resumo: números conferidos à mão (investido 250, 25,0% da verba, CTR 1,40% e CPC 0,71 com cliques no link, CPM
--      10,00, ritmo 150,5%), sem fonte = nulo (receita, leads sem base, page views sem Web), projeto sem dado = nulo e
--      não zero; 6.base leads e MQL da base; 6.web page views da Web fase 2 (visita vinda da campanha), connect rate e
--      conversão da página, conferidos contra public.mkt_web_connect (o mesmo número); UTM no formato nome|id do
--      gp-operacoes casa pelo id (nome só na falta de id), formato antigo (só id ou só nome) continua casando
--   7  o banco recusa sozinho: gasto negativo (23514), fase fora da lista (23503), conta de outra plataforma (23503)
--   8  grants: tabelas e schema fechados; anon nada; authenticated só as 11 da tela; receber só service_role
--   9  sem perfil, operador (mesmo com a área), visualizador e anon: 14 recusas 42501 cada (13 funções + select direto)
--   Qualquer ERRO no meio = a migration não serve como está: não aplicar.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;

-- ═══ CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════════════
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
--     (mkt_web.sessoes, sem teste) do projeto cuja campanha casa com uma campanha do Tráfego do projeto: pelo ID
--     (campaign_id da URL ou o id do utm_campaign no formato nome|id do gp-operacoes = campanha_externa); sem id na
--     visita, pelo NOME exato (a parte do nome do utm_campaign = nome); leitura de mkt_web.origem_ids (20261005n),
--     a mesma da Web. Uma por visita. leads da
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
                join (select x.id, x.projeto_id, x.lead, oi.campanha_id, oi.campanha_nome
                        from mkt_web.sessoes x
                        cross join lateral mkt_web.origem_ids(x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content,
                                                              x.campaign_id, x.adset_id, x.ad_id) oi
                       where not x.teste and ($1 is null or x.projeto_id = $1)) s
                  on s.projeto_id = c.projeto_id
                 and (s.campanha_id = c.campanha_externa or (s.campanha_id is null and s.campanha_nome = c.nome))
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


-- ═══ TESTES ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Ajudantes (temporários, somem no fim da sessão)
create function pg_temp.ok(p_passo text, p_cond boolean, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, case when coalesce(p_cond, false) then 'ok: ' else 'ERRADO: ' end || p_info);
$$;
create function pg_temp.diz(p_passo text, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_info);
$$;
-- chama uma função como o ADMIN (perfil do Victor) e devolve o jsonb
create function pg_temp.adm(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  set local role authenticated;
  execute p_sql into v;
  reset role;
  return v;
end $$;
-- chama como a rotina do servidor (service_role)
create function pg_temp.srv(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
  execute p_sql into v;
  reset role;
  return v;
end $$;
grant execute on function pg_temp.ok(text, boolean, text), pg_temp.diz(text, text) to public;
create function pg_temp.camp(p_ext text) returns mkt_trafego.campanhas language sql stable as $$
  select * from mkt_trafego.campanhas where campanha_externa = p_ext $$;
create function pg_temp.proj(p_sigla text) returns bigint language sql stable as $$ select id from mkt.projetos where sigla = p_sigla $$;
create function pg_temp.linha(p_sigla text) returns jsonb language sql stable as $$
  select e from jsonb_array_elements(mkt_trafego.resumo(null)) e where e ->> 'sigla' = p_sigla $$;

-- ─── 1. Estrutura e semente ──────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('1.estrutura',
  (select count(*) from pg_class c where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r') = 10
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') = 13,
  '10 tabelas em mkt_trafego, 13 funções public.trafego_*');
select pg_temp.ok('1.semente',
  (select string_agg(codigo, ',' order by codigo) from mkt_trafego.plataformas) = 'google,meta'
  and (select string_agg(codigo, ',' order by ordem) from mkt_trafego.status_projeto) = 'ativo,pausado,inativo,encerrado'
  and (select string_agg(codigo, ',' order by ordem) from mkt_trafego.fases) = 'aquecimento,captacao,lembrete,remarketing,abertura_carrinho'
  and (select string_agg(objetivo || '>' || fase, ',' order by objetivo) from mkt_trafego.objetivo_fase) = 'AQUECIMENTO>aquecimento,CARRINHO>abertura_carrinho,LEADS>captacao,LEMBRETE>lembrete,REMARKETING>remarketing,VENDAS>captacao'
  and (select count(*) from mkt_trafego.contas) + (select count(*) from mkt_trafego.campanhas)
      + (select count(*) from mkt_trafego.desempenho_dia) + (select count(*) from mkt_trafego.planejamento)
      + (select count(*) from mkt_trafego.projeto_gestores) = 0,
  'plataformas meta/google; status ativo,pausado,inativo,encerrado; fases aquecimento,captacao,lembrete,remarketing,abertura_carrinho; objetivo→fase LEADS e VENDAS → captação, LEMBRETE, REMARKETING, CARRINHO, AQUECIMENTO; DISTRIBUIÇÃO sem fase; resto vazio');

select pg_temp.ok('1.objetivos', (select string_agg(codigo, ',' order by codigo) from mkt.campanha_objetivos where ativo)
                    = 'AQUECIMENTO,CARRINHO,DISTRIBUIÇÃO,LEADS,LEMBRETE,REMARKETING,VENDAS'
                  and (mkt.campanha_traduzir('CF | PB26 | aquecimento | VIDEO 1') ->> 'padrao')::boolean
                  and (mkt.campanha_traduzir('RS | PB26 | carrinho | ABERTURA DO CARRINHO') ->> 'padrao')::boolean
                  and mkt.campanha_traduzir('RS | PB26 | carrinho | ABERTURA DO CARRINHO') ->> 'objetivo' = 'CARRINHO'
                  and mkt_trafego.fase_efetiva('CARRINHO', null) = 'abertura_carrinho'
                  and mkt_trafego.fase_efetiva('AQUECIMENTO', null) = 'aquecimento' and mkt_trafego.fase_efetiva('VENDAS', null) = 'captacao'
                  and mkt_trafego.fase_efetiva('DISTRIBUIÇÃO', null) is null and mkt_trafego.fase_efetiva('DISTRIBUIÇÃO', 'aquecimento') = 'aquecimento',
                  '7 objetivos (CARRINHO e AQUECIMENTO novos, reconhecidos pelo tradutor); CARRINHO → abertura de carrinho, AQUECIMENTO → aquecimento, VENDAS → captação; DISTRIBUIÇÃO sem fase até marcar à mão');

-- ─── 2. Normalização do id da conta ──────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('2.conta', mkt_trafego.conta_normalizar('meta', ' act_000111 ') = '000111', 'Meta: tira act_ e espaços');
select pg_temp.ok('2.conta', mkt_trafego.conta_normalizar('google', '000-222-3333') = '0002223333', 'Google: só dígitos');
select pg_temp.ok('2.conta', mkt_trafego.conta_normalizar('meta', 'a b') is null and mkt_trafego.conta_normalizar('meta', '') is null
                  and mkt_trafego.conta_normalizar('google', null) is null, 'fora do formato, vazio e nulo = nulo');

-- ─── 3. Cadastro de contas (admin) ───────────────────────────────────────────────────────────────────────────────────
do $t$
declare v jsonb;
begin
  v := pg_temp.adm('select public.trafego_config()');
  perform pg_temp.ok('3.config', jsonb_array_length(v -> 'plataformas') = 2 and jsonb_array_length(v -> 'status') = 4
                     and jsonb_array_length(v -> 'fases') = 5 and (v -> 'objetivo_fase' ->> 'LEADS') = 'captacao' and jsonb_array_length(v -> 'gestores') = 3
                     and (v ->> 'dia_ontem')::date = mkt_trafego.ontem(),
                     'config: 2 plataformas, 4 status, 5 fases, objetivo→fase, 3 gestores (de mkt), ontem; base_pessoas=' || (v ->> 'base_pessoas') || ' base_web=' || (v ->> 'base_web'));
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"meta","conta_externa":"act_000111","nome":"Conta Ensaio Grupo","dono":"grupo"}')$$);
  perform pg_temp.ok('3.conta meta', (v ->> 'ok')::boolean and exists (select 1 from mkt_trafego.contas where conta_externa = '000111'
                     and criado_por = '81d2eaee-cce1-4058-8714-439b0fc6f970'), 'criada, id sem act_, criado_por = quem salvou');
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"meta","conta_externa":"000111","nome":"Outra","dono":"grupo"}')$$);
  perform pg_temp.ok('3.duplicada', not (v ->> 'ok')::boolean and v ->> 'msg' like '%já está cadastrada%', 'mesma conta com e sem act_: ' || (v ->> 'msg'));
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"google","conta_externa":"000-222-3333","nome":"Conta Ensaio Diamante","dono":"diamante","cliente":"Cliente Ensaio"}')$$);
  perform pg_temp.ok('3.conta google', (v ->> 'ok')::boolean, 'Google de um diamante, com cliente');
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"meta","conta_externa":"999","nome":"X Ensaio","dono":"cliente"}')$$);
  perform pg_temp.ok('3.dono', not (v ->> 'ok')::boolean, 'dono fora de grupo/diamante/aurum recusado: ' || (v ->> 'msg'));
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"tiktok","conta_externa":"999","nome":"X Ensaio","dono":"grupo"}')$$);
  perform pg_temp.ok('3.plataforma', not (v ->> 'ok')::boolean, 'plataforma fora da lista recusada');
  v := pg_temp.adm($$select public.trafego_conta_salvar('{"plataforma":"meta","conta_externa":"12 34","nome":"X Ensaio","dono":"grupo"}')$$);
  perform pg_temp.ok('3.id', not (v ->> 'ok')::boolean, 'id da conta fora do formato recusado');
  v := pg_temp.adm('select public.trafego_contas_listar()');
  perform pg_temp.ok('3.listar', jsonb_array_length(v) = 2, 'contas_listar = 2');
end
$t$;

-- ─── 4. Entrada da coleta (service_role): campanhas e desempenho, idempotente ────────────────────────────────────────
do $t$
declare v jsonb; v_lote text; v_ontem date := mkt_trafego.ontem(); v_n int;
begin
  v_lote := $j$[
    {"plataforma":"meta","conta":"act_000111","id":"900000000000001","nome":"RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1","status":"ACTIVE"},
    {"plataforma":"meta","conta":"000111","id":"900000000000002","nome":"cf | pb26 | lembrete | aviso","status":"PAUSED"},
    {"plataforma":"meta","conta":"000111","id":"900000000000003","nome":"Campanha antiga sem padrão"},
    {"plataforma":"meta","conta":"act_777","id":"900000000000009","nome":"RS | PB26 | LEADS | X"},
    {"plataforma":"google","conta":"0002223333","id":"800000001","nome":"EF | HT33 | DISTRIBUIÇÃO | AULA"},
    {"plataforma":"meta","conta":"000111","id":"900000000000004","nome":"RS | ZZ27 | LEADS | PROJETO QUE AINDA NÃO EXISTE"}
  ]$j$;
  v := pg_temp.srv(format('select public.trafego_campanhas_receber(%L::jsonb)', v_lote));
  perform pg_temp.ok('4.receber', (v ->> 'novas')::int = 5 and (v ->> 'atualizadas')::int = 0
                     and v -> 'recusas' = '[{"id": "900000000000009", "motivo": "conta_nao_cadastrada"}]'::jsonb,
                     '5 novas, a da conta não cadastrada recusada: ' || v::text);
  perform pg_temp.ok('4.leitura', (pg_temp.camp('900000000000001')).projeto_id = pg_temp.proj('PB26')
                     and (pg_temp.camp('900000000000001')).gestor = 'RS' and not (pg_temp.camp('900000000000001')).fora_padrao
                     and (pg_temp.camp('900000000000001')).pagina_id = (select id from mkt.paginas where codigo = 'ak1')
                     and (pg_temp.camp('900000000000001')).nome = 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1',
                     'nome no padrão: PB26, RS, página ak1, nome guardado exato');
  perform pg_temp.ok('4.minusculas', not (pg_temp.camp('900000000000002')).fora_padrao
                     and (pg_temp.camp('900000000000002')).leitura -> 'avisos' ? 'minusculas'
                     and (pg_temp.camp('900000000000002')).objetivo = 'LEMBRETE', 'minúsculas: no padrão, com aviso');
  perform pg_temp.ok('4.fora do padrão', (pg_temp.camp('900000000000003')).fora_padrao and (pg_temp.camp('900000000000003')).projeto_id is null
                     and (pg_temp.camp('900000000000004')).fora_padrao
                     and (pg_temp.camp('900000000000004')).leitura -> 'erros' ? 'projeto_nao_cadastrado',
                     'nome livre e projeto não cadastrado = fora do padrão, sem projeto');

  -- de novo, igual: nada duplica
  v := pg_temp.srv(format('select public.trafego_campanhas_receber(%L::jsonb)', v_lote));
  perform pg_temp.ok('4.idempotente', (v ->> 'novas')::int = 0 and (v ->> 'atualizadas')::int = 5
                     and (select count(*) from mkt_trafego.campanhas) = 5, 'reenvio: 0 novas, 5 atualizadas, continuam 5 linhas');
  -- nome mudou na plataforma: a leitura acompanha
  v := pg_temp.srv($$select public.trafego_campanhas_receber('[{"plataforma":"meta","conta":"000111","id":"900000000000003","nome":"RS | BF26 | LEADS | NOVO NOME"}]')$$);
  perform pg_temp.ok('4.renomeada', (pg_temp.camp('900000000000003')).projeto_id = pg_temp.proj('BF26')
                     and not (pg_temp.camp('900000000000003')).fora_padrao, 'renomeada no padrão: passa para BF26');

  -- desempenho
  v := pg_temp.srv(format('select public.trafego_desempenho_receber(%L::jsonb)', jsonb_build_array(
    jsonb_build_object('plataforma','meta','campanha','900000000000001','dia',v_ontem,'gasto',100.50,'impressoes',10000,'cliques_link',200,'cliques_total',260,'leads',10),
    jsonb_build_object('plataforma','meta','campanha','900000000000001','dia',v_ontem - 1,'gasto',99.50,'impressoes',10000,'cliques_link',100,'cliques_total',140,'leads',5),
    jsonb_build_object('plataforma','meta','campanha','900000000000002','dia',v_ontem,'gasto',60,'impressoes',5000,'cliques_link',50),
    jsonb_build_object('plataforma','google','campanha','800000001','dia',v_ontem,'gasto',30,'impressoes',0,'cliques_link',0),
    jsonb_build_object('plataforma','meta','campanha','123','dia',v_ontem,'gasto',1),
    jsonb_build_object('plataforma','meta','campanha','900000000000001','dia',v_ontem - 2,'gasto',-1),
    jsonb_build_object('plataforma','meta','campanha','900000000000001','dia','ontem','gasto',1),
    jsonb_build_object('plataforma','meta','campanha','900000000000001','dia',v_ontem + 30,'gasto',1))));
  perform pg_temp.ok('4.desempenho', (v ->> 'gravadas')::int = 4 and jsonb_array_length(v -> 'recusas') = 4
                     and (select string_agg(r ->> 'motivo', ',' order by r ->> 'motivo') from jsonb_array_elements(v -> 'recusas') r)
                         = 'campanha_desconhecida,formato_invalido,valor_invalido,valor_invalido',
                     '4 gravadas; recusas: campanha desconhecida, formato, gasto negativo, dia no futuro');
  -- reenviar o mesmo dia sobrescreve (corrige 60 → 50) sem duplicar
  v := pg_temp.srv(format('select public.trafego_desempenho_receber(%L::jsonb)', jsonb_build_array(
    jsonb_build_object('plataforma','meta','campanha','900000000000002','dia',v_ontem,'gasto',50,'impressoes',5000,'cliques_link',50))));
  select count(*) into v_n from mkt_trafego.desempenho_dia;
  perform pg_temp.ok('4.sobrescreve', v_n = 4 and (select gasto from mkt_trafego.desempenho_dia d join mkt_trafego.campanhas c on c.id = d.campanha_id
                                                     where c.campanha_externa = '900000000000002') = 50,
                     'mesmo dia reenviado: 4 linhas, gasto 60 virou 50');
end
$t$;

-- ─── 5. Planejamento, fases e ajuste de campanha (admin) ─────────────────────────────────────────────────────────────
do $t$
declare v jsonb; v_pb bigint := pg_temp.proj('PB26'); v_bf bigint := pg_temp.proj('BF26'); v_cap bigint; v_aq bigint; v_fbf bigint;
begin
  v := pg_temp.adm(format($$select public.trafego_planejamento_salvar('{"projeto_id":%s,"status":"ativo","gestores":["rs","CF","RS"],"verba_maxima":"1000","verba_diaria":"100","meta_leads":"50","meta_cpl":"20"}')$$, v_pb));
  perform pg_temp.ok('5.planejamento', (v ->> 'ok')::boolean and (select status || '/' || verba_maxima from mkt_trafego.planejamento
                                                                    where projeto_id = v_pb) = 'ativo/1000.00'
                     and (select string_agg(gestor, ',' order by gestor) from mkt_trafego.projeto_gestores where projeto_id = v_pb) = 'CF,RS',
                     'PB26: ativo, verba 1000, gestores CF e RS (vários; repetido e minúscula normalizados)');
  v := pg_temp.adm(format($$select public.trafego_planejamento_salvar('{"projeto_id":%s,"status":"ativo","verba_maxima":"1000","verba_diaria":"100","meta_leads":"50","meta_cpl":"20"}')$$, v_pb));
  perform pg_temp.ok('5.gestores sem chave', (select count(*) from mkt_trafego.projeto_gestores where projeto_id = v_pb) = 2,
                     'salvar sem a chave gestores não mexe nos gestores');
  v := pg_temp.adm(format($$select public.trafego_planejamento_salvar('{"projeto_id":%s,"status":"ativo","gestores":["RS"],"verba_maxima":"1000","verba_diaria":"100","meta_leads":"50","meta_cpl":"20"}')$$, v_pb));
  perform pg_temp.ok('5.gestores troca', (select string_agg(gestor, ',') from mkt_trafego.projeto_gestores where projeto_id = v_pb) = 'RS',
                     'lista nova substitui a anterior: só RS');
  v := pg_temp.adm(format($$select public.trafego_planejamento_salvar('{"projeto_id":%s,"status":"rolando"}')$$, v_pb));
  perform pg_temp.ok('5.status', not (v ->> 'ok')::boolean, 'status fora da lista recusado');
  v := pg_temp.adm(format($$select public.trafego_planejamento_salvar('{"projeto_id":%s,"verba_maxima":"-1"}')$$, v_pb));
  perform pg_temp.ok('5.verba', not (v ->> 'ok')::boolean, 'verba negativa recusada');
  v := pg_temp.adm(format($$select public.trafego_planejamento_salvar('{"projeto_id":%s,"gestores":["RS","ZZ"]}')$$, v_pb));
  perform pg_temp.ok('5.gestor', not (v ->> 'ok')::boolean
                     and (select string_agg(gestor, ',') from mkt_trafego.projeto_gestores where projeto_id = v_pb) = 'RS',
                     'gestor fora da lista recusado (a lista inteira; nada muda)');
  v := pg_temp.adm(format($$select public.trafego_planejamento_salvar('{"projeto_id":%s,"meta_pct_mql":"150"}')$$, v_pb));
  perform pg_temp.ok('5.mql', not (v ->> 'ok')::boolean, '% MQL acima de 100 recusado');
  v := pg_temp.adm($$select public.trafego_planejamento_salvar('{"projeto_id":"abc"}')$$);
  perform pg_temp.ok('5.formato', not (v ->> 'ok')::boolean, 'projeto em formato inválido recusado sem erro');
  perform pg_temp.ok('5.intacto', (select verba_maxima from mkt_trafego.planejamento where projeto_id = v_pb) = 1000, 'recusas não mexeram no planejamento');

  v := pg_temp.adm(format($$select public.trafego_fase_salvar('{"projeto_id":%s,"fase":"aquecimento","verba":"400","inicio":"2026-10-01","fim":"2026-10-15"}')$$, v_pb));
  v_aq := (v ->> 'id')::bigint;
  v := pg_temp.adm(format($$select public.trafego_fase_salvar('{"projeto_id":%s,"fase":"captacao","verba":"700"}')$$, v_pb));
  v_cap := (v ->> 'id')::bigint;
  perform pg_temp.ok('5.fases', v_aq is not null and v_cap is not null and v -> 'avisos' ? 'fases_acima_da_verba',
                     'aquecimento 400 + captação 700 salvas; aviso de fases acima da verba (1100 > 1000)');
  v := pg_temp.adm(format($$select public.trafego_fase_salvar('{"projeto_id":%s,"fase":"aquecimento","verba":"1"}')$$, v_pb));
  perform pg_temp.ok('5.fase dupla', not (v ->> 'ok')::boolean, 'a mesma fase duas vezes no projeto recusada');
  v := pg_temp.adm(format($$select public.trafego_fase_salvar('{"projeto_id":%s,"fase":"lembrete","inicio":"2026-10-10","fim":"2026-10-01"}')$$, v_pb));
  perform pg_temp.ok('5.datas', not (v ->> 'ok')::boolean, 'fim antes do início recusado');
  v := pg_temp.adm(format($$select public.trafego_fase_salvar('{"projeto_id":%s,"fase":"lembrete","verba":"10"}')$$, v_bf));
  v_fbf := (v ->> 'id')::bigint;

  -- fase pelo OBJETIVO do nome; correção à mão prevalece
  perform pg_temp.ok('5.fase pelo objetivo',
    mkt_trafego.fase_efetiva((pg_temp.camp('900000000000001')).objetivo, (pg_temp.camp('900000000000001')).fase_manual) = 'captacao'
    and mkt_trafego.fase_efetiva((pg_temp.camp('900000000000002')).objetivo, (pg_temp.camp('900000000000002')).fase_manual) = 'lembrete'
    and mkt_trafego.fase_efetiva((pg_temp.camp('800000001')).objetivo, (pg_temp.camp('800000001')).fase_manual) is null,
    'LEADS → captação, LEMBRETE → lembrete, DISTRIBUIÇÃO → sem fase');
  v := pg_temp.adm(format($$select public.trafego_campanha_ajustar('{"id":%s,"fase":"aquecimento"}')$$, (pg_temp.camp('900000000000001')).id));
  perform pg_temp.ok('5.fase à mão', (v ->> 'fase') = 'aquecimento' and (pg_temp.camp('900000000000001')).fase_manual = 'aquecimento'
                     and (pg_temp.camp('900000000000001')).projeto_id = v_pb and not (pg_temp.camp('900000000000001')).projeto_manual,
                     'correção à mão (aquecimento) prevalece sobre o objetivo; projeto não mexe sem a chave projeto_id');
  v := pg_temp.adm(format($$select public.trafego_campanha_ajustar('{"id":%s,"fase":"xyz"}')$$, (pg_temp.camp('900000000000002')).id));
  perform pg_temp.ok('5.fase fora', not (v ->> 'ok')::boolean and (pg_temp.camp('900000000000002')).fase_manual is null, 'fase fora da lista recusada');

  v := pg_temp.adm(format('select public.trafego_projeto(%s)', v_pb));
  perform pg_temp.ok('5.vida', (select (f ->> 'gasto') || '/' || (f ->> 'verba') from jsonb_array_elements(v -> 'fases') f where f ->> 'fase' = 'aquecimento') = '200.00/400.00'
                     and (select coalesce(f ->> 'gasto', 'nulo') || '/' || (f ->> 'verba') from jsonb_array_elements(v -> 'fases') f where f ->> 'fase' = 'captacao') = 'nulo/700.00'
                     and (select (f ->> 'gasto') || '/' || coalesce(f ->> 'id', 'sem plano') from jsonb_array_elements(v -> 'fases') f where f ->> 'fase' = 'lembrete') = '50.00/sem plano'
                     and jsonb_array_length(v -> 'fases') = 3
                     and v -> 'gasto_sem_fase' = 'null'::jsonb and (v ->> 'campanhas_sem_fase')::int = 0
                     and jsonb_array_length(v -> 'serie') = 2 and jsonb_array_length(v -> 'campanhas') = 2 and (v -> 'resumo' ->> 'sigla') = 'PB26',
                     'PB26: aquecimento 200 de 400 (à mão), captação sem gasto de 700, lembrete 50 sem planejamento (pelo objetivo), nada sem fase');
  v := pg_temp.adm(format($$select public.trafego_campanha_ajustar('{"id":%s,"fase":null}')$$, (pg_temp.camp('900000000000001')).id));
  perform pg_temp.ok('5.fase volta', (v ->> 'fase') = 'captacao' and (pg_temp.camp('900000000000001')).fase_manual is null,
                     'fase nula: volta a valer o objetivo (captação)');
  v := pg_temp.adm(format('select public.trafego_projeto(%s)', pg_temp.proj('HT33')));
  perform pg_temp.ok('5.sem fase', (v ->> 'gasto_sem_fase')::numeric = 30 and (v ->> 'campanhas_sem_fase')::int = 1
                     and jsonb_array_length(v -> 'fases') = 0, 'HT33: campanha DISTRIBUIÇÃO fica sem fase (30 em "sem fase")');

  -- ligar à mão (nome fora do padrão) e voltar ao nome
  v := pg_temp.adm(format($$select public.trafego_campanha_ajustar('{"id":%s,"projeto_id":%s}')$$, (pg_temp.camp('900000000000004')).id, v_bf));
  perform pg_temp.ok('5.manual', (pg_temp.camp('900000000000004')).projeto_id = v_bf and (pg_temp.camp('900000000000004')).projeto_manual
                     and (pg_temp.camp('900000000000004')).fora_padrao, 'ligada à mão ao BF26 (continua marcada fora do padrão)');
  v := pg_temp.adm('select public.trafego_campanhas_reler()');
  perform pg_temp.ok('5.reler mantém', (pg_temp.camp('900000000000004')).projeto_id = v_bf, 'reler não desfaz a ligação à mão');
  v := pg_temp.adm(format($$select public.trafego_campanha_ajustar('{"id":%s,"projeto_id":null}')$$, (pg_temp.camp('900000000000004')).id));
  perform pg_temp.ok('5.volta ao nome', (pg_temp.camp('900000000000004')).projeto_id is null and not (pg_temp.camp('900000000000004')).projeto_manual,
                     'projeto nulo: volta a valer o nome (ZZ27 não existe = sem projeto)');
  -- projeto novo cadastrado → reler liga
  insert into mkt.projetos (sigla, nome, linha) values ('ZZ27', 'Projeto Ensaio', 'Ensaio');
  v := pg_temp.adm('select public.trafego_campanhas_reler()');
  perform pg_temp.ok('5.reler liga', (v ->> 'mudaram')::int = 1 and (pg_temp.camp('900000000000004')).projeto_id = pg_temp.proj('ZZ27')
                     and not (pg_temp.camp('900000000000004')).fora_padrao, 'ZZ27 cadastrado: reler liga 1 campanha e tira do fora do padrão');

  -- apagar o planejamento da fase: a campanha continua na fase, sem verba planejada
  v := pg_temp.adm(format('select public.trafego_fase_apagar(%s)', v_cap));
  perform pg_temp.ok('5.apagar fase', (v ->> 'ok')::boolean and not exists (select 1 from mkt_trafego.projeto_fases where id = v_cap)
                     and (select (f ->> 'gasto') || '/' || coalesce(f ->> 'verba', 'sem verba')
                            from jsonb_array_elements(pg_temp.adm(format('select public.trafego_projeto(%s)', v_pb)) -> 'fases') f
                           where f ->> 'fase' = 'captacao') = '200.00/sem verba', (v ->> 'msg'));
end
$t$;

-- ─── 6. Resumo por projeto (as colunas da Central do Tráfego) ────────────────────────────────────────────────────────
do $t$
declare r jsonb; v_tem_base boolean := to_regclass('pessoas.eventos') is not null;
begin
  r := pg_temp.linha('PB26');
  perform pg_temp.ok('6.PB26 gasto', (r ->> 'investido')::numeric = 250 and (r ->> 'pct_verba')::numeric = 25.0
                     and (r ->> 'impressoes')::bigint = 25000 and (r ->> 'cliques_link')::bigint = 350
                     and (r ->> 'cliques_total')::bigint = 400
                     and (r ->> 'ctr')::numeric = 1.40 and (r ->> 'cpm')::numeric = 10.00 and (r ->> 'cpc')::numeric = 0.71
                     and (r ->> 'gasto_ontem')::numeric = 150.5 and (r ->> 'ritmo_ontem')::numeric = 150.5
                     and (r -> 'por_plataforma' ->> 'meta')::numeric = 250 and (r ->> 'leads_plataforma')::int = 15,
                     'investido 250 (25,0% de 1000), CTR 1,40% e CPC 0,71 com cliques no link (350; totais 400), CPM 10,00, ontem 150,50 (150,5% da diária), leads da plataforma 15');
  perform pg_temp.ok('6.PB26 cadastro', r ->> 'status' = 'ativo' and r -> 'gestores' = '["RS"]'::jsonb and r ->> 'tipo' = 'interno'
                     and r -> 'gestores_campanhas' = '["CF", "RS"]'::jsonb and (r ->> 'campanhas')::int = 2
                     and (r ->> 'campanhas_fora_padrao')::int = 0, 'status ativo, gestores do projeto [RS], interno, gestores das campanhas CF e RS');
  if to_regprocedure('public.mkt_web_connect(bigint,date,date)') is null then
    perform pg_temp.ok('6.sem fonte', r -> 'receita' = 'null'::jsonb and r -> 'page_views' = 'null'::jsonb
                       and r -> 'connect_rate' = 'null'::jsonb and r -> 'conversao_pagina' = 'null'::jsonb,
                       'receita nula; sem a Web fase 2 (20261005q): page views, connect rate e conversão da página = nulo');
  else
    perform pg_temp.ok('6.sem fonte', r -> 'receita' = 'null'::jsonb and (r ->> 'page_views')::int = 0
                       and (r ->> 'connect_rate')::numeric = 0 and r -> 'conversao_pagina' = 'null'::jsonb,
                       'receita nula; Web fase 2 aplicada e nenhuma visita de campanha: 0 page views, connect rate 0,0%, conversão nula');
  end if;
  if v_tem_base then
    perform pg_temp.ok('6.leads base vazia', (r ->> 'leads')::int = 0 and r -> 'cpl' = 'null'::jsonb and r -> 'pct_mql' = 'null'::jsonb,
                       'base de pessoas existe e não tem lead do PB26: leads 0, CPL e % MQL nulos (sem divisão por zero)');
  else
    perform pg_temp.ok('6.leads sem base', r -> 'leads' = 'null'::jsonb and r -> 'cpl' = 'null'::jsonb and r -> 'pct_mql' = 'null'::jsonb,
                       'sem a base de pessoas (20261005o): leads, CPL e % MQL nulos');
  end if;
  r := pg_temp.linha('SEMSET26');
  perform pg_temp.ok('6.sem dado', r -> 'investido' = 'null'::jsonb and r -> 'pct_verba' = 'null'::jsonb and r -> 'ctr' = 'null'::jsonb
                     and r -> 'status' = 'null'::jsonb and r -> 'gestores' = '[]'::jsonb and (r ->> 'campanhas')::int = 0,
                     'SEMSET26 sem campanha nem planejamento: investido nulo (não zero), % e KPIs nulos');
  r := pg_temp.linha('HT33');
  perform pg_temp.ok('6.sem impressão', (r ->> 'investido')::numeric = 30 and r -> 'ctr' = 'null'::jsonb and r -> 'cpm' = 'null'::jsonb
                     and r -> 'pct_verba' = 'null'::jsonb and r -> 'por_plataforma' = '{"google": 30.00}'::jsonb,
                     'HT33: 30 no Google, 0 impressão = CTR e CPM nulos; sem verba = % nulo');
  perform pg_temp.ok('6.todos', jsonb_array_length(mkt_trafego.resumo(null)) = (select count(*) from mkt.projetos),
                     'uma linha por projeto de mkt.projetos');
end
$t$;

-- 6.base: leads e MQL da base de pessoas (só com a 20261005o aplicada; senão PULADO)
do $t$
declare r jsonb; v_a uuid; v_b uuid; v_t uuid; v_pb bigint := pg_temp.proj('PB26');
begin
  if to_regclass('pessoas.eventos') is null then
    perform pg_temp.diz('6.base', 'PULADO (20261005o não aplicada: leads da base ficam nulos)');
    return;
  end if;
  execute 'insert into pessoas.pessoas (nome) values (''Ana Ensaio Trafego'') returning id' into v_a;
  execute 'insert into pessoas.pessoas (nome) values (''Bruno Ensaio Trafego'') returning id' into v_b;
  execute 'insert into pessoas.pessoas (nome, teste) values (''Teste Ensaio Trafego'', true) returning id' into v_t;
  execute 'insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte) values ($1,''lead'',$4,''formulario''), ($1,''lead'',$4,''formulario''),
             ($1,''mql'',$4,''formulario''), ($2,''lead'',$4,''formulario''), ($3,''lead'',$4,''formulario''), ($3,''mql'',$4,''formulario'')'
    using v_a, v_b, v_t, v_pb;
  r := pg_temp.linha('PB26');
  perform pg_temp.ok('6.base', (r ->> 'leads')::int = 2 and (r ->> 'mql')::int = 1 and (r ->> 'pct_mql')::numeric = 50.0
                     and (r ->> 'cpl')::numeric = 125.00,
                     'PB26: 2 leads (pessoa repetida conta 1, pessoa de teste fora), 1 MQL (50,0%), CPL 250/2 = 125,00');
end
$t$;

-- 6.web: page views da Web fase 2 (só com a 20261005q aplicada; senão PULADO). A mesma regra de public.mkt_web_connect.
do $t$
declare r jsonb; v_web jsonb; v_pb bigint := pg_temp.proj('PB26'); v_pv_web int; v_leads_web int;
begin
  if to_regprocedure('public.mkt_web_connect(bigint,date,date)') is null then
    perform pg_temp.diz('6.web', 'PULADO (20261005q não aplicada: page views, connect rate e conversão ficam nulos)');
    return;
  end if;
  execute $q$
    insert into mkt_web.sessoes (id, projeto_id, visitante, dia, inicio, fim, dispositivo, teste, utm_campaign, utm_content,
                                 campaign_id, entrada_caminho, saida_caminho, lead)
    select x.id, $1, 'visitanteEnsaio1', current_date, now(), now(), 'mobile', x.teste, x.utm, x.anuncio, x.cid, '/ak1/', '/ak1/', x.lead
      from (values
        ('ensaioSessao01', false, null::text, '000000000000001', '900000000000001', true),
        ('ensaioSessao02', false, 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1', '000000000000001', null, false),
        ('ensaioSessao03', false, '900000000000002', null, null, false),
        ('ensaioSessao04', false, 'outra campanha qualquer', null, null, false),
        ('ensaioSessao05', false, null, null, null, false),
        ('ensaioSessao06', true, null, null, '900000000000001', true),
        ('ensaioSessao07', false, 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1', null, '900000000000001', false),
        -- UTM no padrão do gp-operacoes (nome|id): casa pelo id; nome antigo com id certo casa; nome certo com id de
        -- outra campanha NÃO casa (o id manda, nome só na falta de id)
        ('ensaioSessao08', false, 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1|900000000000001', 'CRIATIVO 01|120200000000001', null, true),
        ('ensaioSessao09', false, 'NOME ANTIGO DA CAMPANHA|900000000000002', null, null, false),
        ('ensaioSessao10', false, 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1|900000000009999', null, null, false)
      ) x(id, teste, utm, anuncio, cid, lead)
  $q$ using v_pb;
  r := pg_temp.linha('PB26');
  perform pg_temp.ok('6.web', (r ->> 'page_views')::int = 6 and (r ->> 'leads_pagina')::int = 2
                     and (r ->> 'connect_rate')::numeric = 1.7 and (r ->> 'conversao_pagina')::numeric = 33.3,
                     'page views = visitas vindas das campanhas do PB26 (pelo id: campaign_id, só id ou nome|id; sem id, pelo '
                     || 'nome exato; uma por visita): 6 (fora: outra campanha, orgânica, teste, nome certo com id de outra '
                     || 'campanha); connect rate 6 ÷ 350 = 1,7%; conversão 2 leads ÷ 6 = 33,3%');
  v_web := pg_temp.adm(format('select public.mkt_web_connect(%s, current_date - 30, current_date)', v_pb));
  select sum((c ->> 'page_views')::int), sum((c ->> 'leads')::int) into v_pv_web, v_leads_web
    from jsonb_array_elements(v_web -> 'campanhas') c;
  perform pg_temp.ok('6.web = Web', v_pv_web = (r ->> 'page_views')::int and v_leads_web = (r ->> 'leads_pagina')::int
                     and (v_web ->> 'cliques_link')::boolean,
                     'mesmo número da Web: public.mkt_web_connect soma ' || v_pv_web || ' page views e ' || v_leads_web
                     || ' lead(s) nas campanhas do PB26, e acha a coluna cliques_link');
  r := pg_temp.linha('HT33');
  perform pg_temp.ok('6.web sem visita', (r ->> 'page_views')::int = 0 and r -> 'connect_rate' = 'null'::jsonb
                     and r -> 'conversao_pagina' = 'null'::jsonb,
                     'HT33 sem visita de campanha e sem clique no link: 0 page views, connect rate e conversão nulos (sem divisão por zero)');
  r := pg_temp.linha('SEMSET26');
  perform pg_temp.ok('6.web sem campanha', r -> 'page_views' = 'null'::jsonb, 'SEMSET26 sem campanha no Tráfego: page views nulas');
end
$t$;

-- ─── 7. O banco recusa sozinho (sem passar pela função) ──────────────────────────────────────────────────────────────
do $t$
declare v_c text;
begin
  begin
    insert into mkt_trafego.desempenho_dia (campanha_id, dia, gasto, impressoes, cliques_link)
    values ((pg_temp.camp('900000000000001')).id, '2020-01-01', -5, 0, 0);
    v_c := 'passou';
  exception when check_violation then v_c := '23514'; end;
  perform pg_temp.ok('7.gasto negativo', v_c = '23514', 'gasto negativo: ' || v_c);
  begin
    update mkt_trafego.campanhas set fase_manual = 'nao_existe' where campanha_externa = '900000000000002';
    v_c := 'passou';
  exception when foreign_key_violation then v_c := '23503'; end;
  perform pg_temp.ok('7.fase fora da lista', v_c = '23503', 'fase fora da lista direto na tabela: ' || v_c);
  begin
    insert into mkt_trafego.campanhas (plataforma, conta_id, campanha_externa, nome, leitura, fora_padrao)
    values ('google', (select id from mkt_trafego.contas where plataforma = 'meta'), '1', 'x', '{}', true);
    v_c := 'passou';
  exception when foreign_key_violation then v_c := '23503'; end;
  perform pg_temp.ok('7.conta de outra plataforma', v_c = '23503', 'campanha Google numa conta Meta: ' || v_c);
end
$t$;

-- ─── 8. Grants ───────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('8.tabelas', not exists (select 1 from information_schema.role_table_grants
                                            where table_schema = 'mkt_trafego' and grantee in ('anon', 'authenticated', 'PUBLIC')),
                  'nenhuma tabela de mkt_trafego com grant para anon/authenticated');
select pg_temp.ok('8.schema', not has_schema_privilege('anon', 'mkt_trafego', 'usage')
                              and not has_schema_privilege('authenticated', 'mkt_trafego', 'usage'), 'sem USAGE no schema');
select pg_temp.ok('8.funcoes',
  (select bool_and(not has_function_privilege('anon', p.oid, 'execute')) from pg_proc p
    where (p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') or p.pronamespace = 'mkt_trafego'::regnamespace)
  and (select bool_and(has_function_privilege('authenticated', p.oid, 'execute')
                       = (p.proname not in ('trafego_campanhas_receber', 'trafego_desempenho_receber')))
         from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%')
  and (select bool_and(not has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p
        where p.pronamespace = 'mkt_trafego'::regnamespace)
  and has_function_privilege('service_role', 'public.trafego_campanhas_receber(jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.trafego_desempenho_receber(jsonb)', 'execute'),
  'anon nada; authenticated só as 11 da tela; internas fechadas; os 2 receber só service_role');

-- ─── 9. Não-admin recusado (uid sem perfil, operador com a área, visualizador, anon) ─────────────────────────────────
do $t$
declare
  c text; u text; v_papel text;
  v_chamadas text[] := array[
    'select public.trafego_config()',
    'select public.trafego_contas_listar()',
    'select public.trafego_conta_salvar(''{}'')',
    'select public.trafego_planejamento_salvar(''{}'')',
    'select public.trafego_fase_salvar(''{}'')',
    'select public.trafego_fase_apagar(1)',
    'select public.trafego_campanhas_listar()',
    'select public.trafego_campanha_ajustar(''{}'')',
    'select public.trafego_campanhas_reler()',
    'select public.trafego_resumo()',
    'select public.trafego_projeto(1)',
    'select public.trafego_campanhas_receber(''[]'')',
    'select public.trafego_desempenho_receber(''[]'')'];
  v_ok int; v_errado text;
begin
  foreach u in array array['00000000-0000-4000-8000-0000000000ff:authenticated', '22222222-2222-4222-8222-222222222222:authenticated',
                           '33333333-3333-4333-8333-333333333333:authenticated', '00000000-0000-4000-8000-0000000000ff:anon'] loop
    v_papel := split_part(u, ':', 2);
    perform set_config('request.jwt.claims', '{"sub":"' || split_part(u, ':', 1) || '","role":"' || v_papel || '"}', true);
    v_ok := 0; v_errado := null;
    foreach c in array v_chamadas loop
      begin
        execute format('set local role %I', v_papel);
        execute c;
        reset role;
        v_errado := concat_ws(', ', v_errado, split_part(split_part(c, '(', 1), '.', 2));
      exception when insufficient_privilege then
        reset role;
        v_ok := v_ok + 1;
      end;
    end loop;
    begin
      execute format('set local role %I', v_papel);
      perform 1 from mkt_trafego.planejamento limit 1;
      reset role;
      v_errado := concat_ws(', ', v_errado, 'select direto');
    exception when insufficient_privilege then
      reset role;
      v_ok := v_ok + 1;
    end;
    perform pg_temp.ok('9.' || case split_part(u, ':', 1) when '33333333-3333-4333-8333-333333333333' then 'visualizador'
                                 when '22222222-2222-4222-8222-222222222222' then 'operador'
                                 else 'sem perfil' end || ' ' || v_papel,
                       v_errado is null, v_ok || ' recusas 42501' || coalesce(' / PASSOU: ' || v_errado, ''));
  end loop;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
