-- 20261006i: Marketing > Tráfego, fase 2 (resumo do dia, receita da Hotmart, atividades do ClickUp, coleta Meta Ads)
--
-- O QUE FAZ
--   Adianta o que não depende de decisão em aberto (05/10/2026, branch victor). Depende da 20261006g (NÃO aplicada).
--     1. Resumo do dia ("o que está pegando fogo"): public.trafego_alertas() lê o resumo da Central e devolve os alertas
--        de hoje (sobre o último dia completo, São Paulo): acima da verba diária, ritmo da fase acima/abaixo do
--        planejado, abaixo da meta de leads para a data, CPL acima da meta, % da verba perto do fim, campanhas fora do
--        padrão e campanhas sem fase. Os limiares ficam na tabela mkt_trafego.alerta_regras (nada de número mágico no
--        código); os valores iniciais são PROPOSTA, para o Victor confirmar. Projetos desativados em mkt.projetos ou
--        com status que não entra no resumo (em planejamento, inativo, encerrado: coluna status_projeto.entra_no_resumo_dia)
--        ficam fora.
--     2. Receita gerada (Hotmart): vínculo produto Hotmart → projeto (mkt_trafego.produtos_hotmart), CADASTRO À MÃO
--        (nada pré-preenchido). O resumo do projeto soma public.compras.preco das compras APROVADAS desses produtos no
--        período do projeto. "Aprovada" = a regra que o repo já usa em public.compras: status APPROVED, COMPLETE ou
--        COMPLETED (20260916_remocao_acessos_webhook, 20260928z28, 20260928z53). Data da compra =
--        coalesce(data_aprovacao, data_compra), dia de São Paulo. Período = de/até do vínculo, senão início/fim do
--        projeto (fim vazio = até hoje); sem início = o vínculo não soma. Sem vínculo = receita nula ("sem dado").
--        Só soma moeda BRL; compra em outra moeda é contada à parte. Reembolso e chargeback: a Hotmart troca o status
--        da própria compra (REFUNDED, CHARGEBACK, CANCELLED), então ela sai da soma (inclusive de dias passados).
--        Pergunta aberta ao Victor (bruto × líquido, reembolso). Nada de valor é copiado: lido de public.compras na hora.
--     3. Atividades do ClickUp na vida do projeto: espelho mínimo (mkt_trafego.clickup_tarefas: id, nome, status,
--        datas, responsáveis, etiquetas, url) gravado pela rotina trafego-clickup (Edge), que LÊ a API do ClickUp pela
--        etiqueta do projeto (mkt.projetos.etiqueta_clickup). Só leitura no ClickUp. Token no Vault
--        (clickup_api_token, a cadastrar: decisão do Victor); id do workspace em mkt_trafego.coleta_config.
--     4. Coleta Meta Ads: rotina trafego-meta (Edge) lê os insights por campanha e dia das contas Meta ativas de
--        mkt_trafego.contas e grava pelas funções de entrada da 20261006g (upsert idempotente; cliques_link =
--        inline_link_clicks, separado de cliques totais; leads da plataforma). Token no Vault: meta_ads_token (conta
--        centralizadora) OU um segredo por conta (coluna contas.token_vault): a decisão está em aberto e as duas formas
--        funcionam. AS ROTINAS NÃO SÃO AGENDADAS AQUI (ficam desligadas até o Victor decidir): ver o bloco LIGAR no fim.
--     5. Google Ads: só desenho (docs/central-de-dados.md) e esqueleto da leitura em infra/supabase/functions/trafego-google.
--   Fontes: plano-trafego.md e area-de-trafego.md no cérebro do Victor; docs/central-de-dados.md (seção Tráfego).
--
--   Padrão do repo (igual 20261005m/o/p/q): tabelas fechadas (RLS ligada, sem policy, revoke de anon/authenticated),
--   schema sem USAGE, acesso só por função public.trafego_* SECURITY DEFINER com search_path '' e a trava dentro
--   (mkt.pode_ver('mkt_trafego'): hoje só admin/dev). trafego_clickup_receber é só de service_role. As funções que leem
--   o Vault (credenciais das rotinas) não têm grant para ninguém: só o postgres (a Edge entra com SUPABASE_DB_URL).
--
-- O QUE CRIA
--   tabelas   mkt_trafego.alerta_regras, produtos_hotmart, clickup_tarefas, coleta_config, coletas
--   colunas   mkt_trafego.status_projeto.entra_no_resumo_dia, mkt_trafego.contas.token_vault
--   internas  mkt_trafego.resumo(bigint) NOVA (a da 20261006g vira resumo_base e esta acrescenta a receita),
--             receita(bigint), periodo_padrao(bigint), periodo_receita(bigint), hotmart_disponivel(), alertas(), coleta_chave(), meta_contas(), clickup_credenciais(),
--             clickup_etiquetas(), coleta_parametros(), coleta_registrar(text,boolean,jsonb,text)
--   public    trafego_alertas, trafego_produtos_listar, trafego_produto_salvar, trafego_produto_apagar,
--             trafego_hotmart_produtos, trafego_clickup (authenticated); trafego_clickup_receber (service_role)
--   Vault     trafego_coleta_chave (header x-sync-chave das rotinas; aleatório, criado aqui se houver Vault)
--
-- AS 5 PERGUNTAS
--   escala: alertas = dezenas de projetos; produtos_hotmart = poucos por projeto; clickup_tarefas = centenas a poucos
--     milhares por ano; coletas = 200 por fonte (o resto é apagado).
--   índice: produtos_hotmart único (projeto, produto, oferta) e (produto_id); clickup_tarefas gin(etiquetas);
--     coletas (fonte, id desc). A receita lê public.compras por produto_id: conferir no banco real se há índice em
--     compras(produto_id) (não sei: o schema de compras não está nas migrations do repo). Sem índice, é um seq scan de
--     compras a cada abertura da Central.
--   frequência: trafego_alertas ao abrir a Central; trafego_clickup ao abrir a vida do projeto; coleta Meta 1x/dia (mais
--     leituras do dia corrente, se ligar); ClickUp 1x/dia.
--   repetição: o resumo do dia chama mkt_trafego.resumo uma vez; a receita é uma query só, agrupada por projeto.
--   reversão: bloco REVERSÃO no fim.
--
-- ENSAIO: infra/supabase/migrations/20261006i_ensaio.sql (begin … rollback). Explicação: 20261006i.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regclass('mkt_trafego.alerta_regras') is not null or to_regprocedure('mkt_trafego.resumo_base(bigint)') is not null then
    raise exception '20261006i: já aplicada (mkt_trafego.alerta_regras ou mkt_trafego.resumo_base existe)';
  end if;
  if to_regnamespace('mkt_trafego') is null or to_regprocedure('mkt_trafego.resumo(bigint)') is null
     or to_regprocedure('public.trafego_campanhas_receber(jsonb)') is null
     or to_regprocedure('public.trafego_desempenho_receber(jsonb)') is null
     or to_regprocedure('mkt_trafego.fase_efetiva(text,text)') is null then
    raise exception '20261006i: falta a 20261006g (schema mkt_trafego, resumo, funções de entrada)';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('trafego_alertas', 'trafego_produtos_listar', 'trafego_produto_salvar', 'trafego_produto_apagar',
                                'trafego_hotmart_produtos', 'trafego_clickup', 'trafego_clickup_receber')) then
    raise exception '20261006i: já existem funções public.trafego_* desta migration';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'mkt' and table_name = 'projetos' and column_name = 'etiqueta_clickup') then
    raise exception '20261006i: mkt.projetos.etiqueta_clickup ausente (20261005m)';
  end if;
end
$guarda$;

-- ─── 1. Resumo do dia: regras e limiares (configuráveis por SQL) ─────────────────────────────────────────────────────
create table mkt_trafego.alerta_regras (
  codigo     text primary key check (codigo ~ '^[a-z][a-z_]{1,39}$'),
  nome       text not null check (length(btrim(nome)) between 2 and 80),
  ordem      smallint not null,
  ligada     boolean not null default true,
  limiar     numeric(10,2) not null check (limiar >= 0),
  unidade    text not null check (unidade in ('pct', 'dias')),
  gravidade  text not null check (gravidade in ('alta', 'media')),
  descricao  text not null check (length(descricao) <= 600),
  atualizado_em timestamptz not null default now()
);
comment on table mkt_trafego.alerta_regras is
  'Resumo do dia da Central do Tráfego ("o que está pegando fogo"): uma linha por regra, com o limiar. Muda por SQL '
  '(update … set limiar = …). Valores iniciais = PROPOSTA da 20261006i, a confirmar com o Victor. 20261006i.';

insert into mkt_trafego.alerta_regras (codigo, nome, ordem, limiar, unidade, gravidade, descricao) values
  ('acima_verba_diaria', 'Acima da verba diária', 1, 0, 'pct', 'alta',
   'Gasto de ontem acima da verba diária + limiar %. 0 = qualquer real acima (a mesma regra do cartão "Ontem acima da verba diária" da 20261006g).'),
  ('cpl_acima_meta', 'CPL acima da meta', 2, 0, 'pct', 'alta',
   'CPL do projeto (investido ÷ leads da base) acima da meta de CPL + limiar %.'),
  ('leads_abaixo_meta', 'Abaixo da meta de leads para a data', 3, 20, 'pct', 'alta',
   'Leads da base abaixo do esperado para ontem em mais de limiar %. Esperado = meta de leads × dias passados ÷ dias do período; '
   'período = a fase de captação planejada (com início e fim), senão início e fim do projeto; sem período, não avalia.'),
  ('ritmo_fase', 'Ritmo da fase fora do planejado', 4, 20, 'pct', 'media',
   'Fase em andamento (início ≤ ontem ≤ fim, com verba): gasto das campanhas da fase desde o início acima ou abaixo do '
   'esperado em mais de limiar %. Esperado = verba da fase × dias passados ÷ dias da fase (a mesma conta do "deveria ter gasto" da tela).'),
  ('verba_perto_fim', '% da verba perto do fim', 5, 90, 'pct', 'media',
   '% da verba máxima já investido maior ou igual ao limiar.'),
  ('fora_padrao', 'Campanhas fora do padrão', 6, 7, 'dias', 'media',
   'Campanhas com nome fora do padrão que gastaram nos últimos limiar dias (inclui as sem projeto).'),
  ('sem_fase', 'Campanhas sem fase', 7, 7, 'dias', 'media',
   'Campanhas do projeto sem fase (sem regra pelo objetivo e sem correção à mão) que gastaram nos últimos limiar dias.');

alter table mkt_trafego.status_projeto add column entra_no_resumo_dia boolean not null default true;
comment on column mkt_trafego.status_projeto.entra_no_resumo_dia is
  'false = projeto com este status não aparece no resumo do dia. Semente da 20261006i: em planejamento (Victor, 06/10/2026), '
  'inativo e encerrado ficam fora (proposta).';
update mkt_trafego.status_projeto set entra_no_resumo_dia = false where codigo in ('em_planejamento', 'inativo', 'encerrado');

-- ─── 2. Receita: vínculo produto Hotmart → projeto (cadastro à mão) ─────────────────────────────────────────────────
create table mkt_trafego.produtos_hotmart (
  id             bigint generated always as identity primary key,
  projeto_id     bigint not null references mkt.projetos(id) on delete restrict,
  produto_id     text not null check (produto_id ~ '^[A-Za-z0-9_-]{1,40}$'),
  oferta_codigo  text check (oferta_codigo is null or oferta_codigo ~ '^[A-Za-z0-9_-]{1,40}$'),
  de             date,
  ate            date,
  obs            text check (obs is null or length(obs) <= 1000),
  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.perfis(id) on delete set null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references public.perfis(id) on delete set null,
  constraint produtos_hotmart_datas_check check (ate is null or de is null or ate >= de)
);
create unique index produtos_hotmart_unico on mkt_trafego.produtos_hotmart (projeto_id, produto_id, coalesce(oferta_codigo, ''));
create index produtos_hotmart_produto_idx on mkt_trafego.produtos_hotmart (produto_id);
comment on table mkt_trafego.produtos_hotmart is
  'Produto (e, se quiser, oferta) da Hotmart que gera receita para o projeto. CADASTRO À MÃO na tela (nada pré-preenchido). '
  'A receita é lida de public.compras na hora (a Hotmart manda no dinheiro); aqui só o vínculo. 20261006i.';
comment on column mkt_trafego.produtos_hotmart.produto_id is 'Id do produto na Hotmart, como em public.compras.produto_id (texto).';
comment on column mkt_trafego.produtos_hotmart.oferta_codigo is 'Código da oferta (public.compras.oferta_codigo). Nulo = todas as ofertas do produto.';
comment on column mkt_trafego.produtos_hotmart.de is 'Início do período que conta para este projeto. Nulo = início do projeto (mkt.projetos.inicio).';
comment on column mkt_trafego.produtos_hotmart.ate is 'Fim do período. Nulo = fim do projeto (mkt.projetos.fim), e sem fim = até hoje.';

-- ─── 3. ClickUp: espelho mínimo das tarefas pela etiqueta do projeto ─────────────────────────────────────────────────
create table mkt_trafego.clickup_tarefas (
  tarefa_id     text primary key check (tarefa_id ~ '^[A-Za-z0-9_-]{1,40}$'),
  nome          text not null check (length(nome) between 1 and 500),
  status        text check (status is null or length(status) <= 60),
  criada_em     timestamptz,
  atualizada_em timestamptz,
  inicio        timestamptz,
  prazo         timestamptz,
  concluida_em  timestamptz,
  responsaveis  text[] not null default '{}',
  etiquetas     text[] not null check (cardinality(etiquetas) between 1 and 50),
  url           text check (url is null or url ~ '^https://app\.clickup\.com/'),
  coletado_em   timestamptz not null default now()
);
create index clickup_tarefas_etiquetas_idx on mkt_trafego.clickup_tarefas using gin (etiquetas);
comment on table mkt_trafego.clickup_tarefas is
  'Espelho MÍNIMO das tarefas do ClickUp que têm a etiqueta de algum projeto (mkt.projetos.etiqueta_clickup). Gravado pela '
  'rotina trafego-clickup (só leitura no ClickUp). Sem descrição, sem comentário, sem anexo. 20261006i.';
comment on column mkt_trafego.clickup_tarefas.responsaveis is 'Nome de usuário dos responsáveis no ClickUp (sem e-mail).';

create table mkt_trafego.coleta_config (
  chave     text primary key check (chave ~ '^[a-z][a-z_]{1,39}$'),
  valor     text check (valor is null or length(valor) <= 200),
  descricao text not null check (length(descricao) <= 600)
);
comment on table mkt_trafego.coleta_config is 'Parâmetros das rotinas de coleta do Tráfego (não secretos). Segredos ficam no Vault. 20261006i.';
insert into mkt_trafego.coleta_config (chave, valor, descricao) values
  ('meta_dias', '3', 'Quantos dias completos para trás a coleta Meta relê a cada rodada (o Meta ainda ajusta os números dos últimos dias), além de hoje.'),
  ('meta_api_versao', null, 'Versão da Graph API (ex.: v23.0). Nulo = a versão padrão escrita na Edge trafego-meta. Conferir a vigente antes de ligar.'),
  ('clickup_team_id', null, 'Id do workspace (team) do ClickUp de onde ler as tarefas. Nulo = a rotina não roda. Victor informa.');

create table mkt_trafego.coletas (
  id        bigint generated always as identity primary key,
  fonte     text not null check (fonte in ('meta', 'google', 'clickup')),
  em        timestamptz not null default now(),
  ok        boolean not null,
  resultado jsonb,
  erro      text check (erro is null or length(erro) <= 500)
);
create index coletas_fonte_idx on mkt_trafego.coletas (fonte, id desc);
comment on table mkt_trafego.coletas is 'Registro de cada rodada das rotinas de coleta (contagens e falhas, nunca token nem URL). 200 por fonte. 20261006i.';

alter table mkt_trafego.contas add column token_vault text
  check (token_vault is null or token_vault ~ '^[a-z][a-z0-9_]{2,59}$');
comment on column mkt_trafego.contas.token_vault is
  'Nome do segredo no Vault com o token desta conta (token por conta). Nulo = usa o token da conta centralizadora '
  '(Vault meta_ads_token). Muda só por SQL. Decisão em aberto (Victor): as duas formas funcionam. 20261006i.';

alter table mkt_trafego.alerta_regras enable row level security;
alter table mkt_trafego.produtos_hotmart enable row level security;
alter table mkt_trafego.clickup_tarefas enable row level security;
alter table mkt_trafego.coleta_config enable row level security;
alter table mkt_trafego.coletas enable row level security;
revoke all on mkt_trafego.alerta_regras, mkt_trafego.produtos_hotmart, mkt_trafego.clickup_tarefas,
              mkt_trafego.coleta_config, mkt_trafego.coletas from public, anon, authenticated;

-- ─── 4. Receita (internas) ───────────────────────────────────────────────────────────────────────────────────────────
-- public.compras tem as colunas que a receita usa? (o schema de compras não está nas migrations; vem do webhook da Hotmart)
create function mkt_trafego.hotmart_disponivel() returns boolean
language sql stable set search_path = '' as $$
  select count(*) = 7 from information_schema.columns
   where table_schema = 'public' and table_name = 'compras'
     and column_name in ('produto_id', 'oferta_codigo', 'status', 'preco', 'moeda', 'data_compra', 'data_aprovacao');
$$;

-- Período padrão do projeto para a meta de leads (sem fase de captação planejada com datas). Aqui: início e fim do
-- projeto. A 20261006j troca para o período de captação (Victor, 06/10/2026). Mudar a regra = só esta função.
create function mkt_trafego.periodo_padrao(p_projeto bigint, out inicio date, out fim date)
language sql stable set search_path = '' as $$
  select p.inicio, p.fim from mkt.projetos p where p.id = p_projeto;
$$;

-- Período padrão da RECEITA (vínculo de produto sem "de"/"até"). Aqui: início e fim do projeto. A 20261006j troca para
-- início da captação até o fim do evento (Victor, 06/10/2026, PROVISÓRIO). Mudar a regra = só esta função.
create function mkt_trafego.periodo_receita(p_projeto bigint, out inicio date, out fim date)
language sql stable set search_path = '' as $$
  select p.inicio, p.fim from mkt.projetos p where p.id = p_projeto;
$$;

-- Receita por projeto: {"<projeto_id>": {receita, receita_compras, receita_outras_moedas, receita_sem_valor,
-- receita_vinculos, receita_sem_periodo}}. Projeto sem vínculo não aparece (a tela mostra "sem dado").
--   receita nula = sem vínculo com período, ou public.compras sem as colunas (banco local).
create function mkt_trafego.receita(p_projeto bigint default null) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_vin jsonb;
  v_som jsonb := '{}'::jsonb;
  v_fonte boolean := mkt_trafego.hotmart_disponivel();
begin
  select coalesce(jsonb_object_agg(x.projeto_id::text, jsonb_build_object('vinculos', x.vinculos, 'sem_periodo', x.sem_periodo)), '{}'::jsonb)
    into v_vin
    from (select v.projeto_id, count(*) as vinculos, count(*) filter (where coalesce(v.de, pp.inicio) is null) as sem_periodo
            from mkt_trafego.produtos_hotmart v cross join lateral mkt_trafego.periodo_receita(v.projeto_id) pp
           where p_projeto is null or v.projeto_id = p_projeto
           group by v.projeto_id) x;
  if v_vin = '{}'::jsonb then return '{}'::jsonb; end if;

  if v_fonte then
    -- SQL dinâmico: public.compras pode não ter as colunas num banco local (a função compila mesmo assim).
    execute $q$
      with vv as (
        select v.projeto_id, v.produto_id, v.oferta_codigo, coalesce(v.de, pp.inicio) as de,
               coalesce(v.ate, pp.fim, (now() at time zone 'America/Sao_Paulo')::date) as ate
          from mkt_trafego.produtos_hotmart v cross join lateral mkt_trafego.periodo_receita(v.projeto_id) pp
         where coalesce(v.de, pp.inicio) is not null and ($1 is null or v.projeto_id = $1)
      ), m as (
        select distinct vv.projeto_id, c.id, c.preco, coalesce(c.moeda, 'BRL') as moeda
          from public.compras c
          join vv on c.produto_id::text = vv.produto_id
                 and (vv.oferta_codigo is null or c.oferta_codigo::text = vv.oferta_codigo)
                 and (coalesce(c.data_aprovacao, c.data_compra) at time zone 'America/Sao_Paulo')::date between vv.de and vv.ate
         where c.status in ('APPROVED', 'COMPLETE', 'COMPLETED')
      )
      select coalesce(jsonb_object_agg(x.projeto_id::text, jsonb_build_object(
               'receita', x.receita, 'compras', x.compras, 'outras', x.outras, 'sem_valor', x.sem_valor)), '{}'::jsonb)
        from (select m.projeto_id, coalesce(sum(m.preco) filter (where m.moeda = 'BRL'), 0) as receita, count(*) as compras,
                     count(*) filter (where m.moeda <> 'BRL') as outras, count(*) filter (where m.preco is null) as sem_valor
                from m group by m.projeto_id) x
    $q$ into v_som using p_projeto;
  end if;

  return (select jsonb_object_agg(k, jsonb_build_object(
            'receita', case when not v_fonte or (v_vin -> k ->> 'vinculos')::int = (v_vin -> k ->> 'sem_periodo')::int then null
                            else round(coalesce((v_som -> k ->> 'receita')::numeric, 0), 2) end,
            'receita_compras', case when v_fonte then coalesce((v_som -> k ->> 'compras')::int, 0) end,
            'receita_outras_moedas', case when v_fonte then coalesce((v_som -> k ->> 'outras')::int, 0) end,
            'receita_sem_valor', case when v_fonte then coalesce((v_som -> k ->> 'sem_valor')::int, 0) end,
            'receita_vinculos', (v_vin -> k ->> 'vinculos')::int,
            'receita_sem_periodo', (v_vin -> k ->> 'sem_periodo')::int))
            from jsonb_object_keys(v_vin) k);
end
$$;

-- O resumo da 20261006g continua igual (vira resumo_base); o novo acrescenta a receita a cada linha. As funções da tela
-- (trafego_resumo, trafego_projeto) chamam mkt_trafego.resumo pelo nome e passam a ver a receita sem mudar.
alter function mkt_trafego.resumo(bigint) rename to resumo_base;
create function mkt_trafego.resumo(p_projeto bigint default null) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_base jsonb := mkt_trafego.resumo_base(p_projeto);
  v_rec jsonb := mkt_trafego.receita(p_projeto);
  v_fonte boolean := mkt_trafego.hotmart_disponivel();
begin
  return (select coalesce(jsonb_agg(x.e || coalesce(v_rec -> (x.e ->> 'projeto_id'), jsonb_build_object(
                    'receita', null, 'receita_compras', null, 'receita_outras_moedas', null, 'receita_sem_valor', null,
                    'receita_vinculos', 0, 'receita_sem_periodo', 0)) || jsonb_build_object('receita_fonte', v_fonte)
                  order by x.o), '[]'::jsonb)
            from jsonb_array_elements(v_base) with ordinality x(e, o));
end
$$;

-- ─── 5. Resumo do dia (interna) ──────────────────────────────────────────────────────────────────────────────────────
create function mkt_trafego.alertas() returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_ontem date := mkt_trafego.ontem();
  v_res jsonb := mkt_trafego.resumo(null);
  v_alertas jsonb;
begin
  with rg as (
    select * from mkt_trafego.alerta_regras where ligada
  ), r as (
    select x.* from jsonb_to_recordset(v_res) as x(
      projeto_id bigint, sigla text, nome text, projeto_ativo boolean, status text, investido numeric, verba_maxima numeric,
      verba_diaria numeric, gasto_ontem numeric, ritmo_ontem numeric, pct_verba numeric, leads bigint, meta_leads integer,
      cpl numeric, meta_cpl numeric, inicio date, fim date)
  ), alvo as (
    select r.* from r left join mkt_trafego.status_projeto s on s.codigo = r.status
     where r.projeto_ativo and coalesce(s.entra_no_resumo_dia, true)
  ), lim as (
    select codigo, limiar from rg
  ),
  -- 1. acima da verba diária (ontem)
  a1 as (
    select 'acima_verba_diaria'::text as regra, a.projeto_id, a.gasto_ontem as valor, a.verba_diaria as referencia,
           jsonb_build_object('pct', a.ritmo_ontem) as detalhe
      from alvo a join lim l on l.codigo = 'acima_verba_diaria'
     where a.investido is not null and a.verba_diaria > 0 and a.gasto_ontem > a.verba_diaria * (1 + l.limiar / 100)
  ),
  -- 2. CPL acima da meta
  a2 as (
    select 'cpl_acima_meta'::text, a.projeto_id, a.cpl, a.meta_cpl::numeric,
           jsonb_build_object('pct', round(a.cpl / a.meta_cpl * 100, 1))
      from alvo a join lim l on l.codigo = 'cpl_acima_meta'
     where a.cpl is not null and a.meta_cpl > 0 and a.cpl > a.meta_cpl * (1 + l.limiar / 100)
  ),
  -- 3. abaixo da meta de leads para a data
  pl as (
    select a.projeto_id, a.leads, a.meta_leads,
           case when cap.inicio is not null and cap.fim is not null then cap.inicio else pp.inicio end as ini,
           case when cap.inicio is not null and cap.fim is not null then cap.fim else pp.fim end as fim,
           case when cap.inicio is not null and cap.fim is not null then 'captacao' else 'projeto' end as periodo
      from alvo a
      cross join lateral mkt_trafego.periodo_padrao(a.projeto_id) pp
      left join mkt_trafego.projeto_fases cap on cap.projeto_id = a.projeto_id and cap.fase = 'captacao'
     where a.leads is not null and a.meta_leads > 0
  ), pl2 as (
    select pl.*, round(pl.meta_leads * least(1, (v_ontem - pl.ini + 1)::numeric / (pl.fim - pl.ini + 1))) as esperado
      from pl where pl.ini is not null and pl.fim is not null and pl.ini <= v_ontem
  ), a3 as (
    select 'leads_abaixo_meta'::text, p.projeto_id, p.leads::numeric, p.esperado,
           jsonb_build_object('meta', p.meta_leads, 'periodo', p.periodo, 'inicio', p.ini, 'fim', p.fim,
                              'pct', case when p.esperado > 0 then round(p.leads / p.esperado * 100, 1) end)
      from pl2 p join lim l on l.codigo = 'leads_abaixo_meta'
     where p.esperado > 0 and p.leads < p.esperado * (1 - l.limiar / 100)
  ),
  -- 4. ritmo da fase em andamento
  fz as (
    select f.projeto_id, f.fase, fs.nome, f.verba, f.inicio, f.fim,
           round(f.verba * (v_ontem - f.inicio + 1)::numeric / (f.fim - f.inicio + 1), 2) as esperado,
           (select coalesce(sum(d.gasto), 0) from mkt_trafego.desempenho_dia d
              join mkt_trafego.campanhas c on c.id = d.campanha_id
             where c.projeto_id = f.projeto_id and mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) = f.fase
               and d.dia between f.inicio and v_ontem) as gasto
      from mkt_trafego.projeto_fases f
      join mkt_trafego.fases fs on fs.codigo = f.fase
      join alvo a on a.projeto_id = f.projeto_id
     where f.verba > 0 and f.inicio <= v_ontem and f.fim >= v_ontem and a.investido is not null
  ), a4 as (
    select 'ritmo_fase'::text, z.projeto_id, z.gasto, z.esperado,
           jsonb_build_object('fase', z.fase, 'fase_nome', z.nome, 'verba', z.verba, 'inicio', z.inicio, 'fim', z.fim,
                              'direcao', case when z.gasto > z.esperado then 'acima' else 'abaixo' end,
                              'pct', round(z.gasto / z.esperado * 100, 1))
      from fz z join lim l on l.codigo = 'ritmo_fase'
     where z.esperado > 0
       and (z.gasto > z.esperado * (1 + l.limiar / 100) or z.gasto < z.esperado * (1 - l.limiar / 100))
  ),
  -- 5. % da verba perto do fim
  a5 as (
    select 'verba_perto_fim'::text, a.projeto_id, a.pct_verba, l.limiar,
           jsonb_build_object('investido', a.investido, 'verba_maxima', a.verba_maxima)
      from alvo a join lim l on l.codigo = 'verba_perto_fim'
     where a.pct_verba is not null and a.pct_verba >= l.limiar
  ),
  -- 6 e 7. campanhas fora do padrão / sem fase que gastaram nos últimos N dias
  recentes as (
    select c.id, c.projeto_id, c.fora_padrao, mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) as fase,
           (select max(d.dia) from mkt_trafego.desempenho_dia d where d.campanha_id = c.id and d.gasto > 0) as ultimo_gasto
      from mkt_trafego.campanhas c
  ), a6 as (
    select 'fora_padrao'::text, x.projeto_id, count(*)::numeric, null::numeric,
           jsonb_build_object('dias', l.limiar)
      from recentes x join lim l on l.codigo = 'fora_padrao'
     where x.fora_padrao and x.ultimo_gasto > v_ontem - l.limiar::int
       and (x.projeto_id is null or x.projeto_id in (select projeto_id from alvo))
     group by x.projeto_id, l.limiar
  ), a7 as (
    select 'sem_fase'::text, x.projeto_id, count(*)::numeric, null::numeric,
           jsonb_build_object('dias', l.limiar)
      from recentes x join lim l on l.codigo = 'sem_fase'
     where x.fase is null and x.projeto_id in (select projeto_id from alvo) and x.ultimo_gasto > v_ontem - l.limiar::int
     group by x.projeto_id, l.limiar
  ), todos as (
    select * from a1 union all select * from a2 union all select * from a3 union all select * from a4
    union all select * from a5 union all select * from a6 union all select * from a7
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'regra', t.regra, 'nome', rg.nome, 'gravidade', rg.gravidade, 'limiar', rg.limiar, 'unidade', rg.unidade,
           'projeto_id', t.projeto_id, 'sigla', r.sigla, 'projeto_nome', r.nome,
           'valor', t.valor, 'referencia', t.referencia, 'detalhe', t.detalhe)
         order by case rg.gravidade when 'alta' then 0 else 1 end, rg.ordem, r.sigla nulls last), '[]'::jsonb)
    into v_alertas
    from todos t(regra, projeto_id, valor, referencia, detalhe)
    join rg on rg.codigo = t.regra
    left join r on r.projeto_id = t.projeto_id;

  return jsonb_build_object(
    'dia', v_ontem,
    'sem_coleta', not exists (select 1 from mkt_trafego.desempenho_dia),
    'base_pessoas', to_regclass('pessoas.eventos') is not null,
    'projetos_avaliados', (select count(*) from jsonb_to_recordset(v_res) as x(projeto_id bigint, projeto_ativo boolean, status text)
                             left join mkt_trafego.status_projeto s on s.codigo = x.status
                            where x.projeto_ativo and coalesce(s.entra_no_resumo_dia, true)),
    'alertas', v_alertas,
    'regras', (select coalesce(jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nome', g.nome, 'ligada', g.ligada,
                 'limiar', g.limiar, 'unidade', g.unidade, 'gravidade', g.gravidade, 'descricao', g.descricao) order by g.ordem), '[]'::jsonb)
                 from mkt_trafego.alerta_regras g),
    'coletas', (select coalesce(jsonb_object_agg(k.fonte, jsonb_build_object('em', k.em, 'ok', k.ok, 'erro', k.erro)), '{}'::jsonb)
                  from (select distinct on (c.fonte) c.fonte, c.em, c.ok, c.erro from mkt_trafego.coletas c
                         order by c.fonte, c.id desc) k));
end
$$;

-- ─── 6. Coleta: credenciais e parâmetros (internas, SEM grant: só o postgres, isto é, a Edge com SUPABASE_DB_URL) ────
-- Lê um segredo do Vault pelo nome. Sem Vault (banco local): nulo.
create function mkt_trafego.segredo(p_nome text) returns text
language plpgsql stable set search_path = '' as $$
declare v text;
begin
  if p_nome is null or to_regclass('vault.decrypted_secrets') is null then return null; end if;
  execute 'select s.decrypted_secret from vault.decrypted_secrets s where s.name = $1' into v using p_nome;
  return v;
end
$$;

create function mkt_trafego.coleta_chave() returns text
language sql stable set search_path = '' as $$ select mkt_trafego.segredo('trafego_coleta_chave') $$;

-- Contas Meta ativas e o token de cada uma: o segredo da própria conta (token_vault) ou, sem ele, o da conta
-- centralizadora (meta_ads_token). token nulo = segredo não cadastrado (a rotina registra "sem_token" para a conta).
create function mkt_trafego.meta_contas() returns table (conta_id bigint, conta_externa text, nome text, moeda text,
                                                         token_origem text, token text)
language sql stable set search_path = '' as $$
  select c.id, c.conta_externa, c.nome, c.moeda, coalesce(c.token_vault, 'meta_ads_token'),
         mkt_trafego.segredo(coalesce(c.token_vault, 'meta_ads_token'))
    from mkt_trafego.contas c
   where c.plataforma = 'meta' and c.ativa
   order by c.id
$$;

create function mkt_trafego.clickup_credenciais() returns table (token text, team_id text)
language sql stable set search_path = '' as $$
  select mkt_trafego.segredo('clickup_api_token'),
         (select nullif(btrim(k.valor), '') from mkt_trafego.coleta_config k where k.chave = 'clickup_team_id')
$$;

-- Etiquetas que a rotina do ClickUp lê: as dos projetos ATIVOS de mkt.projetos.
create function mkt_trafego.clickup_etiquetas() returns setof text
language sql stable set search_path = '' as $$
  select p.etiqueta_clickup from mkt.projetos p where p.ativo and p.etiqueta_clickup is not null order by p.etiqueta_clickup
$$;

create function mkt_trafego.coleta_parametros() returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_object_agg(k.chave, k.valor), '{}'::jsonb) from mkt_trafego.coleta_config k
$$;

-- Registra uma rodada (contagens e falhas; a Edge nunca manda token nem URL). Mantém 200 por fonte.
create function mkt_trafego.coleta_registrar(p_fonte text, p_ok boolean, p_resultado jsonb, p_erro text) returns void
language plpgsql set search_path = '' as $$
begin
  insert into mkt_trafego.coletas (fonte, ok, resultado, erro) values (p_fonte, p_ok, p_resultado, left(p_erro, 500));
  delete from mkt_trafego.coletas c
   where c.fonte = p_fonte and c.id in (select x.id from mkt_trafego.coletas x where x.fonte = p_fonte order by x.id desc offset 200);
end
$$;

-- ─── 7. Funções públicas da tela (authenticated + mkt.pode_ver('mkt_trafego')) ───────────────────────────────────────
create function public.trafego_alertas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return mkt_trafego.alertas();
end
$$;

create function public.trafego_produtos_listar(p_projeto bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', v.id, 'projeto_id', v.projeto_id, 'projeto_sigla', p.sigla, 'produto_id', v.produto_id,
            'oferta_codigo', v.oferta_codigo, 'de', v.de, 'ate', v.ate, 'obs', v.obs,
            'de_efetivo', coalesce(v.de, (mkt_trafego.periodo_receita(p.id)).inicio),
            'ate_efetivo', coalesce(v.ate, (mkt_trafego.periodo_receita(p.id)).fim),
            'atualizado_em', v.atualizado_em)
          order by p.sigla, v.produto_id, v.oferta_codigo nulls first), '[]'::jsonb)
            from mkt_trafego.produtos_hotmart v join mkt.projetos p on p.id = v.projeto_id
           where p_projeto is null or v.projeto_id = p_projeto);
end
$$;

-- Cria (sem "id") ou edita (com "id"). Campos: projeto_id, produto_id, oferta_codigo, de, ate, obs. Retorna
-- {ok, msg, id, avisos}. Avisos: produto_em_outro_projeto (o mesmo produto ligado a outro projeto com período que se
-- cruza: a compra conta nos dois), produto_sem_compras (nenhuma compra deste produto em public.compras), sem_periodo
-- (sem "de" e o projeto sem início: não soma até ter data).
create function public.trafego_produto_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint; v_proj bigint; v_de date; v_ate date;
  v_prod text := btrim(coalesce(p ->> 'produto_id', ''));
  v_oferta text := nullif(btrim(coalesce(p ->> 'oferta_codigo', '')), '');
  v_obs text := nullif(btrim(coalesce(p ->> 'obs', '')), '');
  v_pr mkt.projetos%rowtype;
  v_atual mkt_trafego.produtos_hotmart%rowtype;
  v_pp record;
  v_avisos text[] := '{}';
  v_tem boolean;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  begin
    v_id := nullif(p ->> 'id', '')::bigint;
    v_proj := nullif(p ->> 'projeto_id', '')::bigint;
    v_de := nullif(btrim(coalesce(p ->> 'de', '')), '')::date;
    v_ate := nullif(btrim(coalesce(p ->> 'ate', '')), '')::date;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Campo em formato inválido (datas AAAA-MM-DD).');
  end;
  select * into v_pr from mkt.projetos where id = v_proj;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.'); end if;
  if v_prod !~ '^[A-Za-z0-9_-]{1,40}$' then
    return jsonb_build_object('ok', false, 'msg', 'Id do produto na Hotmart inválido (só letras, números, - e _).');
  end if;
  if v_oferta is not null and v_oferta !~ '^[A-Za-z0-9_-]{1,40}$' then
    return jsonb_build_object('ok', false, 'msg', 'Código da oferta inválido.');
  end if;
  if v_de is not null and v_ate is not null and v_ate < v_de then
    return jsonb_build_object('ok', false, 'msg', 'O fim não pode ser antes do início.');
  end if;

  begin
    if v_id is null then
      insert into mkt_trafego.produtos_hotmart (projeto_id, produto_id, oferta_codigo, de, ate, obs, criado_por, atualizado_por)
      values (v_proj, v_prod, v_oferta, v_de, v_ate, v_obs, v_uid, v_uid) returning id into v_id;
    else
      select * into v_atual from mkt_trafego.produtos_hotmart where id = v_id for update;
      if not found then return jsonb_build_object('ok', false, 'msg', 'Vínculo não encontrado.'); end if;
      if v_atual.projeto_id <> v_proj then return jsonb_build_object('ok', false, 'msg', 'O vínculo é de outro projeto.'); end if;
      update mkt_trafego.produtos_hotmart
         set produto_id = v_prod, oferta_codigo = v_oferta, de = v_de, ate = v_ate, obs = v_obs,
             atualizado_em = now(), atualizado_por = v_uid
       where id = v_id;
    end if;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'Este produto (e oferta) já está ligado a este projeto.');
  end;

  select * into v_pp from mkt_trafego.periodo_receita(v_proj);
  if exists (select 1 from mkt_trafego.produtos_hotmart o cross join lateral mkt_trafego.periodo_receita(o.projeto_id) op
              where o.produto_id = v_prod and o.projeto_id <> v_proj
                and (o.oferta_codigo is null or v_oferta is null or o.oferta_codigo = v_oferta)
                and coalesce(o.de, op.inicio, '-infinity'::date) <= coalesce(v_ate, v_pp.fim, 'infinity'::date)
                and coalesce(v_de, v_pp.inicio, '-infinity'::date) <= coalesce(o.ate, op.fim, 'infinity'::date)) then
    v_avisos := array_append(v_avisos, 'produto_em_outro_projeto');
  end if;
  if coalesce(v_de, v_pp.inicio) is null then v_avisos := array_append(v_avisos, 'sem_periodo'); end if;
  if mkt_trafego.hotmart_disponivel() then
    execute 'select exists (select 1 from public.compras c where c.produto_id::text = $1)' into v_tem using v_prod;
    if not v_tem then v_avisos := array_append(v_avisos, 'produto_sem_compras'); end if;
  end if;
  return jsonb_build_object('ok', true, 'msg', 'Produto ' || v_prod || ' ligado a ' || v_pr.sigla || '.', 'id', v_id,
                            'avisos', to_jsonb(v_avisos));
end
$$;

create function public.trafego_produto_apagar(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not exists (select 1 from mkt_trafego.produtos_hotmart where id = p_id) then
    return jsonb_build_object('ok', false, 'msg', 'Vínculo não encontrado.');
  end if;
  delete from mkt_trafego.produtos_hotmart where id = p_id;
  return jsonb_build_object('ok', true, 'msg', 'Vínculo apagado. A receita do projeto deixa de contar este produto.');
end
$$;

-- Produtos que já apareceram em public.compras (para escolher no cadastro; nada é ligado sozinho). Sem dado pessoal.
create function public.trafego_hotmart_produtos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not mkt_trafego.hotmart_disponivel() or not exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'compras' and column_name = 'produto_nome') then
    return '[]'::jsonb;
  end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object('produto_id', x.produto_id, 'nome', x.nome, 'aprovadas', x.aprovadas,
                                                 'primeira', x.primeira, 'ultima', x.ultima) order by x.ultima desc nulls last), '[]'::jsonb)
      from (select c.produto_id::text as produto_id,
                   (array_agg(c.produto_nome order by coalesce(c.data_aprovacao, c.data_compra) desc nulls last))[1] as nome,
                   count(*) filter (where c.status in ('APPROVED', 'COMPLETE', 'COMPLETED')) as aprovadas,
                   (min(coalesce(c.data_aprovacao, c.data_compra)) at time zone 'America/Sao_Paulo')::date as primeira,
                   (max(coalesce(c.data_aprovacao, c.data_compra)) at time zone 'America/Sao_Paulo')::date as ultima
              from public.compras c
             where coalesce(c.produto_id::text, '') <> ''
             group by c.produto_id::text
             order by 5 desc nulls last
             limit 300) x
  $q$ into v;
  return v;
end
$$;

-- Atividades do ClickUp do projeto (pela etiqueta), as mais recentes primeiro (até 300).
create function public.trafego_clickup(p_projeto bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_etq text;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  if not exists (select 1 from mkt.projetos where id = p_projeto) then return null; end if;
  select etiqueta_clickup into v_etq from mkt.projetos where id = p_projeto;
  return jsonb_build_object(
    'etiqueta', v_etq,
    'configurado', exists (select 1 from mkt_trafego.coleta_config where chave = 'clickup_team_id' and nullif(btrim(valor), '') is not null),
    'ultima_coleta', (select jsonb_build_object('em', c.em, 'ok', c.ok, 'erro', c.erro) from mkt_trafego.coletas c
                       where c.fonte = 'clickup' order by c.id desc limit 1),
    'tarefas', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', t.tarefa_id, 'nome', t.nome, 'status', t.status, 'criada_em', t.criada_em, 'atualizada_em', t.atualizada_em,
                  'inicio', t.inicio, 'prazo', t.prazo, 'concluida_em', t.concluida_em, 'responsaveis', to_jsonb(t.responsaveis),
                  'url', t.url) order by t.ref desc nulls last, t.tarefa_id), '[]'::jsonb)
                  from (select x.*, coalesce(x.concluida_em, x.prazo, x.inicio, x.criada_em) as ref
                          from mkt_trafego.clickup_tarefas x
                         where v_etq is not null and x.etiquetas @> array[v_etq]
                         order by ref desc nulls last limit 300) t));
end
$$;

-- ─── 8. Entrada da rotina do ClickUp (só service_role; a Edge entra como postgres) ──────────────────────────────────
-- p = {"etiqueta": "<etiqueta do projeto>", "tarefas": [{id, nome, status, criada_em, atualizada_em, inicio, prazo,
-- concluida_em, responsaveis: [..], etiquetas: [..], url}]} com TODAS as tarefas que têm a etiqueta hoje (a rotina só
-- chama depois de ler todas as páginas). Upsert por id; quem tinha a etiqueta e não veio perde a etiqueta (e some se
-- ficar sem nenhuma). Datas em ISO 8601. Retorna {ok, gravadas, removidas, recusas}.
create function public.trafego_clickup_receber(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_etq text := btrim(coalesce(p ->> 'etiqueta', ''));
  e jsonb;
  v_ids text[] := '{}';
  v_id text; v_nome text; v_etqs text[]; v_resp text[];
  v_cri timestamptz; v_atu timestamptz; v_ini timestamptz; v_prazo timestamptz; v_fim timestamptz;
  v_url text;
  v_n int := 0; v_rem int := 0;
  v_recusas jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from mkt.projetos where etiqueta_clickup = v_etq) then
    return jsonb_build_object('ok', false, 'msg', 'Etiqueta de nenhum projeto.');
  end if;
  if jsonb_typeof(p -> 'tarefas') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava a lista "tarefas".');
  end if;
  if jsonb_array_length(p -> 'tarefas') > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000 por etiqueta).');
  end if;
  for e in select * from jsonb_array_elements(p -> 'tarefas') loop
    v_id := btrim(coalesce(e ->> 'id', ''));
    v_nome := left(btrim(coalesce(e ->> 'nome', '')), 500);
    if v_id !~ '^[A-Za-z0-9_-]{1,40}$' then
      v_recusas := v_recusas || jsonb_build_object('id', v_id, 'motivo', 'id_invalido'); continue;
    end if;
    if v_nome = '' then
      v_recusas := v_recusas || jsonb_build_object('id', v_id, 'motivo', 'nome_vazio'); continue;
    end if;
    begin
      v_cri := nullif(e ->> 'criada_em', '')::timestamptz;
      v_atu := nullif(e ->> 'atualizada_em', '')::timestamptz;
      v_ini := nullif(e ->> 'inicio', '')::timestamptz;
      v_prazo := nullif(e ->> 'prazo', '')::timestamptz;
      v_fim := nullif(e ->> 'concluida_em', '')::timestamptz;
      select coalesce(array_agg(distinct lower(btrim(x))) filter (where btrim(x) <> ''), '{}') into v_etqs
        from jsonb_array_elements_text(case when jsonb_typeof(e -> 'etiquetas') = 'array' then e -> 'etiquetas' else '[]'::jsonb end) x;
      select coalesce(array_agg(left(btrim(x), 80)) filter (where btrim(x) <> ''), '{}') into v_resp
        from (select x from jsonb_array_elements_text(case when jsonb_typeof(e -> 'responsaveis') = 'array' then e -> 'responsaveis' else '[]'::jsonb end) x limit 20) y;
    exception when others then
      v_recusas := v_recusas || jsonb_build_object('id', v_id, 'motivo', 'formato_invalido'); continue;
    end;
    if not (v_etq = any (v_etqs)) then v_etqs := array_append(v_etqs, v_etq); end if;
    v_etqs := v_etqs[1:50];
    v_url := case when coalesce(e ->> 'url', '') ~ '^https://app\.clickup\.com/' then left(e ->> 'url', 300) end;
    insert into mkt_trafego.clickup_tarefas as t (tarefa_id, nome, status, criada_em, atualizada_em, inicio, prazo, concluida_em,
                                                   responsaveis, etiquetas, url, coletado_em)
    values (v_id, v_nome, nullif(left(btrim(coalesce(e ->> 'status', '')), 60), ''), v_cri, v_atu, v_ini, v_prazo, v_fim,
            v_resp, v_etqs, v_url, now())
    on conflict (tarefa_id) do update
       set nome = excluded.nome, status = excluded.status, criada_em = excluded.criada_em, atualizada_em = excluded.atualizada_em,
           inicio = excluded.inicio, prazo = excluded.prazo, concluida_em = excluded.concluida_em,
           responsaveis = excluded.responsaveis, etiquetas = excluded.etiquetas, url = excluded.url, coletado_em = now();
    v_ids := array_append(v_ids, v_id);
    v_n := v_n + 1;
  end loop;

  -- quem tinha a etiqueta e não veio: tira a etiqueta; sem nenhuma, sai do espelho
  with tirar as (
    update mkt_trafego.clickup_tarefas t set etiquetas = array_remove(t.etiquetas, v_etq), coletado_em = now()
     where t.etiquetas @> array[v_etq] and not (t.tarefa_id = any (v_ids)) and cardinality(t.etiquetas) > 1
    returning 1
  ) select count(*) into v_rem from tirar;
  with apagar as (
    delete from mkt_trafego.clickup_tarefas t
     where t.etiquetas = array[v_etq] and not (t.tarefa_id = any (v_ids))
    returning 1
  ) select v_rem + count(*) into v_rem from apagar;
  return jsonb_build_object('ok', true, 'gravadas', v_n, 'removidas', v_rem, 'recusas', v_recusas);
end
$$;

-- ─── 9. Quem executa o quê ───────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'mkt_trafego'::regnamespace
                   and p.proname in ('resumo', 'receita', 'hotmart_disponivel', 'alertas', 'segredo', 'coleta_chave', 'meta_contas',
                                     'clickup_credenciais', 'clickup_etiquetas', 'coleta_parametros', 'coleta_registrar', 'periodo_padrao', 'periodo_receita'))
               or (p.pronamespace = 'public'::regnamespace
                   and p.proname in ('trafego_alertas', 'trafego_produtos_listar', 'trafego_produto_salvar', 'trafego_produto_apagar',
                                     'trafego_hotmart_produtos', 'trafego_clickup', 'trafego_clickup_receber')) loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end
$grants$;
grant execute on function
  public.trafego_alertas(), public.trafego_produtos_listar(bigint), public.trafego_produto_salvar(jsonb),
  public.trafego_produto_apagar(bigint), public.trafego_hotmart_produtos(), public.trafego_clickup(bigint)
  to authenticated;
grant execute on function public.trafego_clickup_receber(jsonb) to service_role;

-- ─── 10. Header das rotinas no Vault (aleatório). Sem Vault (banco local): aviso. As rotinas NÃO são agendadas ──────
do $vault$
begin
  if to_regclass('vault.decrypted_secrets') is null then
    raise notice '20261006i: Vault ausente; segredo trafego_coleta_chave NÃO criado';
    return;
  end if;
  if not exists (select 1 from vault.secrets where name = 'trafego_coleta_chave') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
      'trafego_coleta_chave', 'Header x-sync-chave das rotinas trafego-meta e trafego-clickup (as Edges conferem). 20261006i.');
  end if;
end
$vault$;

-- ─── 11. Conferência (aborta se algo nasceu aberto ou fora do padrão) ────────────────────────────────────────────────
do $confere$
declare
  r text;
  t record;
  f record;
  v_tela text[] := array['trafego_alertas', 'trafego_produtos_listar', 'trafego_produto_salvar', 'trafego_produto_apagar',
                         'trafego_hotmart_produtos', 'trafego_clickup'];
  v_novas text[] := v_tela || array['trafego_clickup_receber'];
  v_internas text[] := array['resumo', 'resumo_base', 'receita', 'hotmart_disponivel', 'alertas', 'segredo', 'coleta_chave',
                             'meta_contas', 'clickup_credenciais', 'clickup_etiquetas', 'coleta_parametros', 'coleta_registrar',
                             'periodo_padrao', 'periodo_receita'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_trafego', 'usage') then raise exception '20261006i: % tem acesso ao schema mkt_trafego', r; end if;
  end loop;
  for t in select c.oid, c.relname, c.relrowsecurity from pg_class c
            where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r' loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t.oid, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261006i: % tem privilégio em mkt_trafego.%', r, t.relname;
      end if;
    end loop;
    if not t.relrowsecurity then raise exception '20261006i: RLS desligada em mkt_trafego.%', t.relname; end if;
  end loop;
  if (select count(*) from pg_class c where c.relnamespace = 'mkt_trafego'::regnamespace and c.relkind = 'r') <> 15 then
    raise exception '20261006i: esperava 15 tabelas em mkt_trafego (10 da 20261006g + 5)';
  end if;
  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where (p.pronamespace = 'public'::regnamespace and p.proname = any (v_novas))
               or (p.pronamespace = 'mkt_trafego'::regnamespace and p.proname = any (v_internas)) loop
    if not (f.proconfig @> array['search_path=""']) then raise exception '20261006i: % sem search_path vazio', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') then raise exception '20261006i: anon executa %', f.sig; end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261006i: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any (v_tela)) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261006i: grant de authenticated errado em %', f.sig;
    end if;
    if f.pronamespace = 'mkt_trafego'::regnamespace and has_function_privilege('service_role', f.sig, 'execute') then
      raise exception '20261006i: service_role executa a interna %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> f.prosecdef then
      raise exception '20261006i: SECURITY DEFINER errado em % (públicas sim, internas não)', f.sig;
    end if;
  end loop;
  if not has_function_privilege('service_role', 'public.trafego_clickup_receber(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.trafego_clickup_receber(jsonb)', 'execute') then
    raise exception '20261006i: grant de trafego_clickup_receber errado';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'trafego\_%') <> 20 then
    raise exception '20261006i: esperava 20 funções public.trafego_* (13 da 20261006g + 7)';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'mkt_trafego'::regnamespace and p.proname = any (v_internas)) <> 14 then
    raise exception '20261006i: esperava 14 funções internas novas ou renomeadas';
  end if;
  if (select count(*) from mkt_trafego.alerta_regras) <> 7 or (select count(*) from mkt_trafego.produtos_hotmart) <> 0
     or (select count(*) from mkt_trafego.clickup_tarefas) <> 0
     or (select count(*) from mkt_trafego.status_projeto where not entra_no_resumo_dia) <> 3 then
    raise exception '20261006i: semente diferente do esperado (7 regras, 3 status fora do resumo, vínculos e tarefas vazios)';
  end if;
  -- sem pg_cron (banco local) a checagem da rotina não se aplica
  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname in ('trafego-meta', 'trafego-meta-hoje', 'trafego-clickup')) then
      raise exception '20261006i: rotina do Tráfego agendada (deveria nascer desligada)';
    end if;
  end if;
end
$confere$;


-- ═══ LIGAR AS ROTINAS (NÃO rodar agora: decisão do Victor). Horário do cron em UTC ══════════════════════════════════════
-- Antes: publicar as Edges (supabase functions deploy trafego-meta / trafego-clickup; verify_jwt = false está no
-- config.toml), cadastrar o token no Vault e as contas em Marketing > Tráfego > Contas de anúncio.
--   Meta, conta centralizadora:  select vault.create_secret('<token>', 'meta_ads_token', 'Token Meta Ads (leitura de insights).');
--   Meta, token por conta:        select vault.create_secret('<token>', 'meta_ads_token_<nome>', '…');
--                                 update mkt_trafego.contas set token_vault = 'meta_ads_token_<nome>' where id = <id>;
--   ClickUp:                      select vault.create_secret('<token>', 'clickup_api_token', 'Token ClickUp (só leitura de tarefas).');
--                                 update mkt_trafego.coleta_config set valor = '<id do workspace>' where chave = 'clickup_team_id';
-- select cron.schedule('trafego-meta', '30 9 * * *', $c$
--   select ops.cron_post('trafego-meta',
--     url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/trafego-meta',
--     body := '{}'::jsonb,
--     headers := jsonb_build_object('Content-Type', 'application/json',
--       'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'trafego_coleta_chave')),
--     timeout_milliseconds := 150000)
-- $c$);
-- -- (opcional) leitura do dia corrente para o ritmo, de 3 em 3 horas das 09h às 21h SP: mesmo comando com '0 12-23/3 * * *'
-- --   e o job 'trafego-meta-hoje' (body '{"so_hoje": true}').
-- select cron.schedule('trafego-clickup', '0 10 * * *', $c$
--   select ops.cron_post('trafego-clickup',
--     url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/trafego-clickup',
--     body := '{}'::jsonb,
--     headers := jsonb_build_object('Content-Type', 'application/json',
--       'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'trafego_coleta_chave')),
--     timeout_milliseconds := 150000)
-- $c$);
-- Desligar: select cron.unschedule('trafego-meta'); select cron.unschedule('trafego-clickup');


-- ═══ REVERSÃO (numa transação; apaga vínculos de produto, espelho do ClickUp, regras e registro das coletas) ═══════════
-- begin;
-- select cron.unschedule(j) from unnest(array['trafego-meta', 'trafego-meta-hoje', 'trafego-clickup']) j
--  where exists (select 1 from cron.job where jobname = j);
-- do $$ declare f regprocedure; begin
--   for f in select p.oid::regprocedure from pg_proc p
--             where (p.pronamespace = 'public'::regnamespace and p.proname in ('trafego_alertas', 'trafego_produtos_listar',
--                    'trafego_produto_salvar', 'trafego_produto_apagar', 'trafego_hotmart_produtos', 'trafego_clickup',
--                    'trafego_clickup_receber'))
--                or (p.pronamespace = 'mkt_trafego'::regnamespace and p.proname in ('resumo', 'receita', 'hotmart_disponivel',
--                    'alertas', 'segredo', 'coleta_chave', 'meta_contas', 'clickup_credenciais', 'clickup_etiquetas',
--                    'coleta_parametros', 'coleta_registrar', 'periodo_padrao', 'periodo_receita'))
--   loop execute format('drop function %s', f); end loop; end $$;
-- alter function mkt_trafego.resumo_base(bigint) rename to resumo;
-- drop table mkt_trafego.alerta_regras, mkt_trafego.produtos_hotmart, mkt_trafego.clickup_tarefas, mkt_trafego.coleta_config,
--            mkt_trafego.coletas;
-- alter table mkt_trafego.status_projeto drop column entra_no_resumo_dia;
-- alter table mkt_trafego.contas drop column token_vault;
-- -- os segredos ficam no Vault (inofensivos sem as rotinas); para apagar:
-- -- delete from vault.secrets where name in ('trafego_coleta_chave', 'meta_ads_token', 'clickup_api_token');
-- commit;
