-- Ensaio de 20261008161000 (modelo seminario-atm) + 20261008161100 (cadastro do ATM 1, com sigla FICTÍCIA ZZENSAIO99
-- só nesta transação). Foto do presencial antes; 2 passadas; bateria vazia; dados simulados (grupo, listas, sessões,
-- oferta de setembro só para exercitar vendas); recusas; foto do presencial depois; reversão e foto de novo.
-- Saída só com contagens e md5: nenhum dado pessoal. Transação desfeita: nada persiste.
-- Montado a partir dos 3 arquivos (migration, cadastro com a sigla trocada, reversão): ao mudar um deles, refazer o ensaio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '240s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '01 presencial antes', (jsonb_build_object(
  'resumo', (select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.email), '')) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'vendas', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.transacao), '')) from public.dados_presencial_vendas('clinica-miami-2026-12') x),
  'serie', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.dia), '')) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') x),
  'disparos', (select count(*) from public.dados_presencial_disparos('clinica-miami-2026-12'))))::text;
select set_config('request.jwt.claims', '{}', true);

-- passada 1
-- 20261008161000: modelo de dashboard "seminario-atm" no schema dados (Seminário ATM, padrão para todos os ATMs)
--
-- STATUS: ESCRITA, NÃO APLICADA. Aplicar só com aval do JP (dono do banco desde 08/10/2026) e do Victor Hugo, depois do
-- pentester (cria RPC com GRANT para authenticated e devolve dado pessoal de lead: e-mail, nome, telefone).
-- Ensaio: 20261008161000_ensaio.sql. Relatório: 20261008161000.explain.md. Reversão: 20261008161000_reversao.sql.
-- Contrato com a tela: docs/dashboard-atm/MODELO-DE-DADOS.md. Mudar coluna, tipo ou ordem quebra a tela.
--
-- PARA VOLTAR: rodar 20261008161000_reversao.sql (drop das 6 funções públicas, dos ajudantes, das 2 views, das 5 tabelas
--   novas, das 3 colunas novas de dados.dashboards; devolve o NOT NULL de oferta_codigo e o check de modelo). Só volta
--   limpo se nenhum dashboard 'seminario-atm' estiver cadastrado (a reversão aborta e avisa).
--
-- POR QUE
--   Card 86aktf11y (dashboard do ATM 1 da Dra. Elaine, chave atm-elaine-1-2026-10). Regra do briefing: nada lê
--   planilha, tudo vem do banco, e o modelo vale para os próximos ATMs (27/10, 17/11) só com cadastro pela chave.
--   Reaproveita o modelo presencial (20261007161809): dados.dashboards, dados.cadastro (gate), dados.transacoes (Hotmart
--   na forma da trava), dados.pre_checkout, dados.perfil, mkt_mensageria.disparos. Só cria o que não existe no banco.
--
-- O QUE JÁ EXISTE E É LIDO (levantamento só leitura em 08/10/2026)
--   leads ........ crm.evento_jornada da lista do ActiveCampaign da edição (lista 615 "Seminário ATM Outubro 2026 -
--                  Leads", página atm.guardioesdolegado.com.br/ak1; webhook do AC grava desde 07/10) + pessoas.eventos
--                  tipo 'lead' do projeto (rota /api/captura/lead, se a página passar a chamar).
--   pré-checkout . dados.pre_checkout (o mesmo do presencial): evento pre_checkout do projeto + lista do AC (lista_ac).
--   vendas ....... dados.transacoes(conta, oferta) = fin.hotmart_transacoes (sync de hora em hora; o webhook em tempo
--                  real só cobre a conta academy, e a Sessão de Viabilidade é da conta escritorio).
--   disparos ..... mkt_mensageria.disparos do projeto (canal whatsapp_api, grupo, sms, ligacao, email; custo_centavos).
--   aluno ........ public.thb_alunos (instrução) e public.thb_turmas, via dados.perfil.
--   grupo ........ crm.evento_jornada fonte 'sendflow' (Edge crm-integracao-webhook /sendflow: tipo entrada/saida,
--                  fone_key, tag = nome da campanha no SendFlow). HOJE DESLIGADO (crm.config.sendflow_ligado = false) e
--                  sem nenhum evento: ligar é decisão do JP/Victor (proposta no explain), não desta migration.
--
-- O QUE FAZ (só o mínimo que falta)
--   1. public.tg_carimbar_atualizado_em(): o gatilho padrão do PADRAO-DE-BANCO (não existia no banco). Criado só se
--      não existir.
--   2. dados.dashboards: modelo 'seminario-atm' no check; oferta_codigo aceita nulo (oferta ainda não configurada =
--      vendas "sem dado ainda"); colunas novas lista_ac_leads, vendas_desde, ciclo_fecha_em.
--   3. Tabelas novas (RLS ligada, sem policy, sem grant; criado_em/atualizado_em com o gatilho padrão):
--      dados.ddd_uf ............ DDD -> UF (copiado de sal_uf, dashboard-ht api/sem-atm2-leads.php)
--      dados.dashboard_grupos .. campanha(s) do SendFlow de cada dashboard (casa com crm.evento_jornada.tag)
--      dados.lista_membros ..... Lista 1 / Lista 2 e seminário de origem (Marcio, Elaine) de cada edição, por chave
--                                normalizada de e-mail e telefone (sem nome, sem payload)
--      dados.sessoes ........... live, replay e triplay da edição: início, fim, pico de audiência, equipe na sala
--      dados.sessao_presencas .. quem esteve em cada sessão (relatório do Zoom), por chave de e-mail/telefone
--   4. Views internas (security_invoker = true, sem grant): dados.v_grupo_eventos e dados.v_grupo_pessoas.
--   5. Ajudantes internos (sem grant): dados.leads_todos, dados.atm_leads, dados.atm_vendas, dados.atm_cadastro.
--   6. RPCs da tela (security definer, search_path '', execute só authenticated): dados_atm_resumo, dados_atm_leads,
--      dados_atm_serie_diaria, dados_atm_disparos_canais, dados_atm_comparecimento, dados_atm_pos_live.
--      Detalhe por disparo e lista de vendas: as do presencial servem como estão (dados_presencial_disparos,
--      dados_presencial_vendas; não olham o modelo).
--
-- POR QUE RPC E NÃO VIEW PARA A TELA
--   O pedido falava em views com security_invoker. As views existem (item 4), mas a tela não pode lê-las direto:
--   authenticated não tem grant nem policy em pessoas, crm, fin e mkt_mensageria (fechados por decisão), e o dado é por
--   chave (view não recebe parâmetro). PADRAO-DE-BANCO 6.4: "View que precisa furar RLS vira função com guarda". É o
--   mesmo desenho do dashboard presencial.
--
-- AS 5 PERGUNTAS
--   escala: hoje 46 leads na lista 615, 0 evento de grupo, 0 venda da oferta (oferta ainda não definida). Um ATM tem na
--     ordem de mil leads (setembro: 911). Tudo agrega por 1 chave, 1 lista, 1 oferta, 1 projeto.
--   índice: as tabelas novas nascem com índice nas FK e nas chaves de casamento. crm.evento_jornada é lida por lista
--     e por fonte/tag sem índice hoje (24.374 linhas em 08/10); os dois índices estão em arquivo próprio,
--     20261008161001_crm_criar_indice_evento_jornada_lista.sql (concurrently, fora de transação).
--   frequência: a tela chama resumo e série ao abrir e a cada 60 s com a aba visível (como o presencial); leads,
--     comparecimento e pós-live sob demanda.
--   repetição: cada RPC monta os leads uma vez (dados.atm_leads) e agrega em cima.
--   reversão: 20261008161000_reversao.sql.
--
-- IDEMPOTENTE: create … if not exists / create or replace / on conflict do nothing / drop constraint if exists.
-- Guarda aborta se a base do presencial mudou (colunas de dados.dashboards, funções de apoio).

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v_cols text;
begin
  foreach v_cols in array array['public.gp_eh_equipe()', 'dados.cadastro(text)', 'dados.transacoes(text,text)',
                                'dados.pre_checkout(text,bigint,text)', 'dados.perfil(text)', 'pessoas.atual(uuid)',
                                'pessoas.norm_email(text)', 'controle.fone_key(text)'] loop
    if to_regprocedure(v_cols) is null then
      raise exception '20261008161000: % não existe', v_cols;
    end if;
  end loop;
  select string_agg(column_name, ',' order by ordinal_position) into v_cols
    from information_schema.columns where table_schema = 'dados' and table_name = 'dashboards';
  if v_cols not in ('chave,modelo,projeto_id,conta_hotmart,oferta_codigo,lista_ac,ativo,criado_em,ofertas_extra',
                    'chave,modelo,projeto_id,conta_hotmart,oferta_codigo,lista_ac,ativo,criado_em,ofertas_extra,lista_ac_leads,vendas_desde,ciclo_fecha_em') then
    raise exception '20261008161000: dados.dashboards com colunas inesperadas (%). Conferir.', v_cols;
  end if;
  if to_regclass('crm.evento_jornada') is null
     or (select count(*) from information_schema.columns where table_schema = 'crm' and table_name = 'evento_jornada'
          and column_name in ('fonte', 'tipo', 'ocorreu_em', 'email_norm', 'fone_key', 'nome', 'lista', 'tag', 'pessoa_id')) <> 9 then
    raise exception '20261008161000: crm.evento_jornada sem as colunas esperadas';
  end if;
  if to_regprocedure('public.tg_carimbar_atualizado_em()') is not null
     and (select prorettype from pg_proc where oid = to_regprocedure('public.tg_carimbar_atualizado_em()')) <> 'trigger'::regtype then
    raise exception '20261008161000: public.tg_carimbar_atualizado_em() existe e não é função de gatilho';
  end if;
end
$g$;

-- 1. Gatilho padrão de atualizado_em (PADRAO-DE-BANCO 5.6). Só cria se não existir.
do $t$
begin
  if to_regprocedure('public.tg_carimbar_atualizado_em()') is null then
    execute $f$
      create function public.tg_carimbar_atualizado_em() returns trigger
      language plpgsql set search_path = '' as $b$
      begin
        new.atualizado_em := now();
        return new;
      end
      $b$
    $f$;
    execute 'revoke all on function public.tg_carimbar_atualizado_em() from public, anon, authenticated';
    execute $c$comment on function public.tg_carimbar_atualizado_em() is
      'Gatilho padrão (PADRAO-DE-BANCO 5.6): carimba atualizado_em = now() em todo UPDATE. 20261008161000.'$c$;
  end if;
end
$t$;

-- 2. dados.dashboards: modelo novo e colunas do ATM
alter table dados.dashboards drop constraint if exists dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check check (modelo in ('presencial-base', 'seminario-atm'));
alter table dados.dashboards alter column oferta_codigo drop not null;
alter table dados.dashboards add column if not exists lista_ac_leads text
  check (lista_ac_leads is null or lista_ac_leads ~ '^[0-9]{1,10}$');
alter table dados.dashboards add column if not exists vendas_desde timestamptz;
alter table dados.dashboards add column if not exists ciclo_fecha_em timestamptz;
comment on column dados.dashboards.oferta_codigo is
  'Oferta principal na Hotmart. Nulo = oferta ainda não configurada: vendas, receita, CAC e ROAS saem nulos ("sem dado ainda"). 20261008161000.';
comment on column dados.dashboards.lista_ac_leads is
  'Modelo seminario-atm: id da lista do ActiveCampaign onde a página de inscrição grava o lead (crm.evento_jornada.lista). 20261008161000.';
comment on column dados.dashboards.vendas_desde is
  'Modelo seminario-atm: só contam transações com pedido a partir daqui (a oferta pode ser a mesma de outros eventos). Nulo = sem corte. 20261008161000.';
comment on column dados.dashboards.ciclo_fecha_em is
  'Modelo seminario-atm: fim do ciclo fechado (live, replay e triplay). Vendas aprovadas até aqui = ciclo fechado; até agora = ciclo aberto. Nulo = ciclo ainda sem data de fechamento. 20261008161000.';

-- 3. Tabelas novas
-- 3.1 DDD -> UF (fonte: sal_uf do dashboard-ht, api/sem-atm2-leads.php; DDD fora da tabela = 'Outros' na leitura)
create table if not exists dados.ddd_uf (
  ddd           text primary key check (ddd ~ '^[1-9][0-9]$'),
  uf            text not null check (uf ~ '^[A-Z]{2}$'),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
comment on table dados.ddd_uf is 'DDD -> UF para a coluna estado dos leads (o formulário não pede UF). Copiado de sal_uf (dashboard-ht). 20261008161000.';
insert into dados.ddd_uf (ddd, uf) values
  ('11','SP'),('12','SP'),('13','SP'),('14','SP'),('15','SP'),('16','SP'),('17','SP'),('18','SP'),('19','SP'),
  ('21','RJ'),('22','RJ'),('24','RJ'),('27','ES'),('28','ES'),
  ('31','MG'),('32','MG'),('33','MG'),('34','MG'),('35','MG'),('37','MG'),('38','MG'),
  ('41','PR'),('42','PR'),('43','PR'),('44','PR'),('45','PR'),('46','PR'),
  ('47','SC'),('48','SC'),('49','SC'),('51','RS'),('53','RS'),('54','RS'),('55','RS'),
  ('61','DF'),('62','GO'),('64','GO'),('63','TO'),('65','MT'),('66','MT'),('67','MS'),
  ('68','AC'),('69','RO'),('71','BA'),('73','BA'),('74','BA'),('75','BA'),('77','BA'),('79','SE'),
  ('81','PE'),('87','PE'),('82','AL'),('83','PB'),('84','RN'),('85','CE'),('88','CE'),('86','PI'),('89','PI'),
  ('91','PA'),('93','PA'),('94','PA'),('92','AM'),('97','AM'),('95','RR'),('96','AP'),('98','MA'),('99','MA')
on conflict (ddd) do nothing;

-- 3.2 Campanhas do SendFlow de cada dashboard
create table if not exists dados.dashboard_grupos (
  id                 uuid primary key default gen_random_uuid(),
  chave              text not null references dados.dashboards(chave) on delete restrict,
  sendflow_campanha  text not null check (length(btrim(sendflow_campanha)) between 1 and 200),
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  unique (chave, sendflow_campanha)
);
comment on table dados.dashboard_grupos is
  'Campanha(s) do SendFlow do dashboard. sendflow_campanha = nome EXATO da campanha (o webhook grava em crm.evento_jornada.tag). Sem linha = grupo "sem fonte" (nulo na tela). 20261008161000.';

-- 3.3 Lista 1 / Lista 2 e seminário de origem de cada edição
create table if not exists dados.lista_membros (
  id                bigint generated always as identity primary key,
  chave             text not null references dados.dashboards(chave) on delete restrict,
  lista             text not null check (lista in ('lista_1', 'lista_2')),
  seminario_origem  text check (seminario_origem in ('marcio', 'elaine', 'marcio_e_elaine')),
  email_norm        text check (email_norm is null or email_norm = pessoas.norm_email(email_norm)),
  fone_key          text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  importacao        text not null check (length(btrim(importacao)) between 3 and 120),
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  check (email_norm is not null or fone_key is not null)
);
create unique index if not exists lista_membros_unico
  on dados.lista_membros (chave, lista, coalesce(email_norm, ''), coalesce(fone_key, ''));
create index if not exists lista_membros_email_idx on dados.lista_membros (chave, email_norm) where email_norm is not null;
create index if not exists lista_membros_fone8_idx on dados.lista_membros (chave, right(fone_key, 8)) where fone_key is not null;
comment on table dados.lista_membros is
  'Quem está na Lista 1 (geral/e-mail) e na Lista 2 (passou pelo pré-checkout da SV, menos quem reagiu ao último ATM) de cada edição, e de qual seminário veio. Só chave normalizada (e-mail minúsculo, telefone DDD+8), sem nome. importacao = rótulo do lote (sem dado pessoal). Carga por service_role. 20261008161000.';

-- 3.4 Sessões ao vivo (live, replay, triplay)
create table if not exists dados.sessoes (
  id               uuid primary key default gen_random_uuid(),
  chave            text not null references dados.dashboards(chave) on delete restrict,
  tipo             text not null check (tipo in ('live', 'replay', 'triplay')),
  inicio           timestamptz not null,
  fim              timestamptz check (fim is null or fim > inicio),
  pico_audiencia   integer check (pico_audiencia is null or pico_audiencia >= 0),
  equipe_na_sala   integer check (equipe_na_sala is null or equipe_na_sala >= 0),
  obs              text check (obs is null or length(obs) <= 500),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (chave, tipo, inicio)
);
comment on table dados.sessoes is
  'Live, replay e triplay de cada dashboard. pico_audiencia e equipe_na_sala: lançados do Zoom (nulo = não lançado, nunca 0). 20261008161000.';

-- 3.5 Presença por pessoa em cada sessão
create table if not exists dados.sessao_presencas (
  id                bigint generated always as identity primary key,
  sessao_id         uuid not null references dados.sessoes(id) on delete restrict,
  email_norm        text check (email_norm is null or email_norm = pessoas.norm_email(email_norm)),
  fone_key          text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  eh_equipe         boolean not null default false,
  minutos           integer check (minutos is null or minutos >= 0),
  primeira_entrada  timestamptz,
  fonte             text not null check (fonte in ('zoom_relatorio', 'manual')),
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  check (email_norm is not null or fone_key is not null)
);
create unique index if not exists sessao_presencas_unico
  on dados.sessao_presencas (sessao_id, coalesce(email_norm, ''), coalesce(fone_key, ''));
comment on table dados.sessao_presencas is
  'Quem esteve na sessão (relatório de participantes do Zoom), por chave normalizada. Sem nome. eh_equipe = pessoa da casa (não conta como lead presente). 20261008161000.';

do $r$
declare v text;
begin
  foreach v in array array['ddd_uf', 'dashboard_grupos', 'lista_membros', 'sessoes', 'sessao_presencas'] loop
    execute format('alter table dados.%I enable row level security', v);
    execute format('revoke all on dados.%I from public, anon, authenticated', v);
    execute format('drop trigger if exists carimbar_atualizado_em on dados.%I', v);
    execute format('create trigger carimbar_atualizado_em before update on dados.%I '
                   'for each row execute function public.tg_carimbar_atualizado_em()', v);
  end loop;
end
$r$;

-- 4. Views internas (security_invoker; sem grant: só o dono e as funções leem)
create or replace view dados.v_grupo_eventos with (security_invoker = true) as
  select g.chave, j.id as evento_id, j.tipo, j.fone_key, right(j.fone_key, 8) as fone8, j.ocorreu_em, j.pessoa_id
    from crm.evento_jornada j
    join dados.dashboard_grupos g on g.sendflow_campanha = j.tag
   where j.fonte = 'sendflow' and j.tipo in ('entrada', 'saida') and j.fone_key is not null;
comment on view dados.v_grupo_eventos is
  'Entradas e saídas do grupo de WhatsApp por dashboard (crm.evento_jornada fonte sendflow, tag = campanha cadastrada em dados.dashboard_grupos). 20261008161000.';

create or replace view dados.v_grupo_pessoas with (security_invoker = true) as
  select e.chave, e.fone8,
         min(e.ocorreu_em) filter (where e.tipo = 'entrada') as entrou_em,
         max(e.ocorreu_em) filter (where e.tipo = 'saida') as saiu_em,
         (array_agg(e.tipo order by e.ocorreu_em desc, e.evento_id desc))[1] = 'entrada' as no_grupo,
         (array_agg(e.pessoa_id order by e.ocorreu_em desc) filter (where e.pessoa_id is not null))[1] as pessoa_id
    from dados.v_grupo_eventos e
   group by e.chave, e.fone8;
comment on view dados.v_grupo_pessoas is
  'Uma linha por pessoa (telefone DDD+8 -> últimos 8) por dashboard: primeira entrada, última saída e se ainda está no grupo. Saída só conta para quem entrou (regra do debriefing ATM SET/26). 20261008161000.';

revoke all on dados.v_grupo_eventos, dados.v_grupo_pessoas from public, anon, authenticated;

-- 5. Ajudantes internos
-- 5.1 Leads: lista do AC da edição + evento 'lead' do projeto (mesma forma do pre_checkout_todos, 20261007te)
create or replace function dados.leads_todos(p_chave text, p_projeto_id bigint, p_lista text)
returns table (email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, pessoa_id uuid, teste boolean)
language sql stable set search_path = '' as $$
  -- 20261008161000
  with passagens as (
    -- sistema (rota /api/captura/lead -> pessoas.registrar, tipo lead)
    select em.chave as email, p.nome, tel.valor as telefone, e.quando, 'sistema'::text as fonte,
           o.utm_source, o.utm_medium, o.utm_campaign, o.utm_content, o.utm_term,
           p.id as pessoa_id, coalesce(p.teste, false) as teste
      from pessoas.eventos e
      join pessoas.pessoas p on p.id = pessoas.atual(e.pessoa_id)
      cross join lateral (select i.chave from pessoas.identificadores i
                           where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'email' order by i.criado_em desc limit 1) em
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
      left join pessoas.origens o on o.id = e.origem_id
     where e.tipo = 'lead'
       and (e.projeto_id = p_projeto_id or e.detalhe ->> 'chave_evento' = p_chave)
    union all
    -- ActiveCampaign (entrada na lista de leads da edição)
    select j.email_norm, nullif(btrim(j.nome), ''), tel.valor, j.ocorreu_em, 'activecampaign',
           null, null, null, null, null,
           p.id, coalesce(p.teste, false)
      from crm.evento_jornada j
      left join pessoas.pessoas p on p.id = pessoas.atual(j.pessoa_id)
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (j.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
     where p_lista is not null and j.fonte = 'activecampaign' and j.lista = p_lista and j.email_norm is not null
  ), limpo as (
    select lower(btrim(x.email)) as email, nullif(btrim(x.nome), '') as nome, nullif(btrim(x.telefone), '') as telefone,
           x.quando, x.fonte, x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content, x.utm_term, x.pessoa_id, x.teste
      from passagens x
     where nullif(btrim(x.email), '') is not null and lower(btrim(x.email)) not like '%@exemplo.invalid'
  )
  select l.email,
         (select y.nome from limpo y where y.email = l.email and y.nome is not null order by y.quando desc limit 1),
         (select y.telefone from limpo y where y.email = l.email and y.telefone is not null order by y.quando desc limit 1),
         min(l.quando),
         case when bool_and(l.fonte = 'sistema') then 'sistema'
              when bool_and(l.fonte = 'activecampaign') then 'activecampaign' else 'ambos' end,
         u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term,
         (select y.pessoa_id from limpo y where y.email = l.email and y.pessoa_id is not null
           order by y.teste desc, y.quando desc limit 1),
         bool_or(l.teste)
    from limpo l
    left join lateral (select y.utm_source, y.utm_medium, y.utm_campaign, y.utm_content, y.utm_term
                         from limpo y where y.email = l.email and y.fonte = 'sistema'
                        order by y.quando limit 1) u on true
   group by l.email, u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term
$$;

-- 5.2 Gate do modelo: o mesmo dados.cadastro (equipe, chave ativa) + modelo certo
create or replace function dados.atm_cadastro(p_chave text)
returns dados.dashboards
language plpgsql stable set search_path = '' as $$
declare
  r dados.dashboards := dados.cadastro(p_chave);   -- 42501 sem acesso, P0002 chave fora do cadastro
begin
  if r.modelo is distinct from 'seminario-atm' then
    raise exception 'dashboard de outro modelo' using errcode = 'P0002';
  end if;
  return r;
end
$$;

-- 5.3 Vendas da edição: pagas, 1ª cobrança, pedido a partir de vendas_desde
create or replace function dados.atm_vendas(p_chave text)
returns table (transacao text, pedido_em timestamptz, aprovado_em timestamptz, dia_aprovado date, moeda text,
               valor_bruto numeric, valor_liquido numeric, email text)
language sql stable set search_path = '' as $$
  -- 20261008161000
  select t.transacao, t.pedido_em, t.aprovado_em, t.dia_aprovado, t.moeda, t.valor_bruto, t.valor_liquido, t.email
    from dados.dashboards d
    cross join lateral dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
   where d.chave = p_chave and d.oferta_codigo is not null
     and t.pago and t.primeira
     and (d.vendas_desde is null or coalesce(t.pedido_em, t.aprovado_em) >= d.vendas_desde)
$$;

-- 5.4 Leads enriquecidos (fonte única do modal e dos números)
create or replace function dados.atm_leads(p_chave text)
returns table (email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
               entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text,
               lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean,
               pessoa_id uuid, teste boolean)
language sql stable set search_path = '' as $$
  -- 20261008161000
  with d as (select * from dados.dashboards where chave = p_chave),
  l as (
    select t.*, controle.fone_key(t.telefone) as fk
      from d cross join lateral dados.leads_todos(d.chave, d.projeto_id, d.lista_ac_leads) t
  ),
  tem as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = p_chave) as grupo,
           exists (select 1 from dados.lista_membros m where m.chave = p_chave) as listas
  ),
  pc as (select y.email from d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  vd as (select distinct v.email from dados.atm_vendas(p_chave) v where v.email is not null)
  select l.email, l.nome, l.telefone, l.primeiro_em, l.fonte, l.utm_source, l.utm_medium, l.utm_campaign,
         l.utm_content, l.utm_term,
         left(l.fk, 2),
         case when l.fk is null then null else coalesce((select u.uf from dados.ddd_uf u where u.ddd = left(l.fk, 2)), 'Outros') end,
         case when tem.grupo then coalesce(gp.entrou_em is not null, false) end,
         case when tem.grupo then coalesce(gp.entrou_em is not null and gp.saiu_em > gp.entrou_em, false) end,
         pf.instrucao is not null, pf.instrucao, pf.turma,
         case when not tem.listas then null
              when lm.l1 and lm.l2 then 'lista_1_e_2'
              when lm.l1 then 'lista_1' when lm.l2 then 'lista_2'
              else 'fora_das_listas' end,
         case when lm.marcio and lm.elaine then 'marcio_e_elaine'
              when lm.marcio then 'marcio' when lm.elaine then 'elaine' end,
         exists (select 1 from pc where pc.email = l.email),
         case when (select oferta_codigo from d) is null then null else exists (select 1 from vd where vd.email = l.email) end,
         l.pessoa_id, l.teste
    from l cross join tem
    left join lateral (select g.entrou_em, g.saiu_em from dados.v_grupo_pessoas g
                        where g.chave = p_chave and g.entrou_em is not null
                          and ((l.fk is not null and g.fone8 = right(l.fk, 8)) or (l.pessoa_id is not null and g.pessoa_id = l.pessoa_id))
                        order by g.entrou_em limit 1) gp on true
    left join lateral (select bool_or(m.lista = 'lista_1') as l1, bool_or(m.lista = 'lista_2') as l2,
                              bool_or(m.seminario_origem in ('marcio', 'marcio_e_elaine')) as marcio,
                              bool_or(m.seminario_origem in ('elaine', 'marcio_e_elaine')) as elaine
                         from dados.lista_membros m
                        where m.chave = p_chave
                          and (m.email_norm = l.email or (l.fk is not null and right(m.fone_key, 8) = right(l.fk, 8)))) lm on true
    left join lateral (select x.instrucao, x.turma from dados.perfil(l.email) x) pf on true
$$;

revoke all on function dados.leads_todos(text, bigint, text), dados.atm_cadastro(text), dados.atm_vendas(text),
                       dados.atm_leads(text) from public, anon, authenticated;

-- 6. RPCs da tela
-- 6.1 Resumo: os 14 cards da visão geral, na ordem do briefing
create or replace function public.dados_atm_resumo(p_chave text)
returns table (chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text,
               disparos_qtd integer, disparos_enviados integer, leads integer,
               grupo_tem_fonte boolean, grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric,
               custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint,
               pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer,
               compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint,
               receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric,
               atualizado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  with disp as (
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo, sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
  ),
  ld as (select * from dados.atm_leads(d.chave) where not teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em is not null)::int as entradas,
           count(*) filter (where g.entrou_em is not null and g.saiu_em > g.entrou_em)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  pc as (select y.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select * from dados.atm_vendas(d.chave)),
  ag as (
    select (select count(*)::int from ld) as leads,
           (select count(*)::int from pc) as pc,
           (select count(*)::int from tx) as vendas,
           (select count(*)::int from tx where tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  ),
  k as (select (disp.qtd > 0 and disp.sem = 0) as completo, d.oferta_codigo is not null as tem_oferta from disp)
  select d.chave, pr.id, pr.sigla, pr.nome, d.oferta_codigo,
         disp.qtd, disp.enviados, ag.leads,
         gr.fonte,
         case when gr.fonte then gr.entradas end,
         case when gr.fonte then gr.saidas end,
         case when gr.fonte and ag.leads > 0 then round(gr.entradas::numeric * 100 / ag.leads, 2)::numeric(7,2) end,
         case when gr.fonte and gr.entradas > 0 then round(gr.saidas::numeric * 100 / gr.entradas, 2)::numeric(7,2) end,
         disp.custo, disp.sem, k.completo,
         case when k.completo and ag.leads > 0 then round(disp.custo::numeric / ag.leads)::bigint end,
         ag.pc,
         case when k.tem_oferta then ag.vendas end,
         case when k.tem_oferta then ag.fora end,
         case when k.tem_oferta then ag.comp end,
         case when k.tem_oferta then ag.comp_pc end,
         case when k.tem_oferta and ag.pc > 0 then round(ag.comp::numeric * 100 / ag.pc, 2)::numeric(7,2) end,
         case when k.tem_oferta and k.completo and ag.vendas > 0 then round(disp.custo::numeric / ag.vendas)::bigint end,
         case when k.tem_oferta then ag.bruta end,
         case when k.tem_oferta then ag.liq end,
         case when k.tem_oferta and k.completo and disp.custo > 0 then round(ag.bruta * 100 / disp.custo, 2)::numeric(10,2) end,
         case when k.tem_oferta and k.completo and disp.custo > 0 then round(ag.liq * 100 / disp.custo, 2)::numeric(10,2) end,
         now()
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join k
   where pr.id = d.projeto_id;
end
$$;

-- 6.2 Leads (modal): todos, inclusive teste (coluna teste no fim); os números não contam teste
create or replace function public.dados_atm_leads(p_chave text)
returns table (email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
               entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text,
               lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean,
               pessoa_id uuid, teste boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query select * from dados.atm_leads(d.chave) x order by x.primeiro_em desc, x.email;
end
$$;

-- 6.3 Série diária (dia em São Paulo, sem buraco, do 1º dia com dado até hoje)
create or replace function public.dados_atm_serie_diaria(p_chave text)
returns table (dia date, leads integer, grupo_entradas integer, grupo_saidas integer, pre_checkout integer,
               vendas integer, receita_bruta numeric, custo_disparo_centavos bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_leads(d.chave) x where not x.teste),
  ge as (select (g.entrou_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null),
  gs as (select (g.saiu_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null and g.saiu_em > g.entrou_em),
  pc as (select (y.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
           from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select v.dia_aprovado as dia, v.valor_bruto, v.moeda from dados.atm_vendas(d.chave) v),
  ds as (select (x.enviado_em at time zone 'America/Sao_Paulo')::date as dia, x.custo_centavos
           from mkt_mensageria.disparos x where x.projeto_id = d.projeto_id and x.arquivado_em is null),
  lim as (
    select least((select min(dia) from ld), (select min(dia) from ge), (select min(dia) from pc),
                 (select min(dia) from tx), (select min(dia) from ds)) as de
  )
  select s::date,
         (select count(*)::int from ld where ld.dia = s::date),
         case when v_tem_grupo then (select count(*)::int from ge where ge.dia = s::date) end,
         case when v_tem_grupo then (select count(*)::int from gs where gs.dia = s::date) end,
         (select count(*)::int from pc where pc.dia = s::date),
         case when d.oferta_codigo is not null then (select count(*)::int from tx where tx.dia = s::date) end,
         case when d.oferta_codigo is not null then
           (select coalesce(sum(tx.valor_bruto), 0)::numeric(14,2) from tx where tx.dia = s::date and tx.moeda = 'BRL') end,
         (select case when count(*) filter (where ds.custo_centavos is null) = 0 then sum(ds.custo_centavos)::bigint end
            from ds where ds.dia = s::date having count(*) > 0)
    from lim
    cross join lateral generate_series(lim.de, (now() at time zone 'America/Sao_Paulo')::date, interval '1 day') s
   where lim.de is not null
   order by 1;
end
$$;

-- 6.4 Disparos por canal: sempre 5 linhas, na ordem das abas (API, Grupo, SMS, Ligação, E-mail)
create or replace function public.dados_atm_disparos_canais(p_chave text)
returns table (canal text, disparos integer, enviados integer, entregues integer, lidas integer, cliques integer,
               falhas integer, custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  select c.canal, count(x.id)::int, sum(x.tamanho_lista)::int, sum(x.entregues)::int, sum(x.lidas)::int,
         sum(x.cliques)::int, sum(x.falhas)::int,
         sum(x.custo_centavos)::bigint,
         count(x.id) filter (where x.custo_centavos is null)::int,
         count(x.id) > 0 and count(x.id) filter (where x.custo_centavos is null) = 0
    from (values (1, 'whatsapp_api'), (2, 'grupo'), (3, 'sms'), (4, 'ligacao'), (5, 'email')) c(ordem, canal)
    left join mkt_mensageria.disparos x
           on x.canal = c.canal and x.projeto_id = d.projeto_id and x.arquivado_em is null
   group by c.ordem, c.canal
   order by c.ordem;
end
$$;

-- 6.5 Comparecimento: 1 linha por sessão cadastrada
create or replace function public.dados_atm_comparecimento(p_chave text)
returns table (sessao_id uuid, tipo text, inicio timestamptz, fim timestamptz, pico_audiencia integer,
               equipe_na_sala integer, total_leads integer, total_grupo integer, presentes integer,
               presentes_leads integer, presentes_grupo integer, pico_sobre_leads_pct numeric,
               pico_sobre_grupo_pct numeric, presentes_leads_pct numeric, presentes_grupo_pct numeric,
               vendas integer, conversao_pct numeric, conversao_grupo_pct numeric, conversao_pico_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select x.email, controle.fone_key(x.telefone) as fk from dados.atm_leads(d.chave) x where not x.teste),
  gp as (select g.fone8 from dados.v_grupo_pessoas g where g.chave = d.chave and g.entrou_em is not null),
  tot as (select (select count(*)::int from ld) as leads,
                 case when v_tem_grupo then (select count(*)::int from gp) end as grupo),
  ss as (
    select s.*, lead(s.inicio) over (order by s.inicio) as proxima
      from dados.sessoes s where s.chave = d.chave
  ),
  pr as (
    -- presente = pessoa fora da equipe; é lead se casa por e-mail ou telefone; é do grupo se o telefone (dele ou do
    -- lead casado pelo e-mail) entrou no grupo
    select p.sessao_id,
           count(*)::int as presentes,
           count(*) filter (where m.eh_lead)::int as p_leads,
           count(*) filter (where exists (select 1 from gp where gp.fone8 = coalesce(right(p.fone_key, 8), m.fk8)))::int as p_grupo
      from dados.sessao_presencas p
      left join lateral (select true as eh_lead, right(ld.fk, 8) as fk8 from ld
                          where ld.email = p.email_norm
                             or (p.fone_key is not null and right(ld.fk, 8) = right(p.fone_key, 8))
                          order by (ld.email = p.email_norm) desc nulls last limit 1) m on true
     where p.sessao_id in (select id from ss) and not p.eh_equipe
     group by p.sessao_id
  ),
  tx as (select v.aprovado_em from dados.atm_vendas(d.chave) v)
  select ss.id, ss.tipo, ss.inicio, ss.fim, ss.pico_audiencia, ss.equipe_na_sala, tot.leads, tot.grupo,
         pr.presentes, pr.p_leads, case when v_tem_grupo then pr.p_grupo end,
         case when tot.leads > 0 then round(ss.pico_audiencia::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when tot.grupo > 0 then round(ss.pico_audiencia::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         case when tot.leads > 0 then round(pr.p_leads::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when v_tem_grupo and tot.grupo > 0 then round(pr.p_grupo::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         vs.n,
         case when tot.leads > 0 then round(vs.n::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when tot.grupo > 0 then round(vs.n::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         case when ss.pico_audiencia > 0 then round(vs.n::numeric * 100 / ss.pico_audiencia, 2)::numeric(7,2) end
    from ss cross join tot
    left join pr on pr.sessao_id = ss.id
    cross join lateral (
      select case when d.oferta_codigo is null then null
                  else (select count(*)::int from tx
                         where tx.aprovado_em >= ss.inicio
                           and tx.aprovado_em < coalesce(ss.proxima, d.ciclo_fecha_em, now())) end as n
    ) vs
   order by ss.inicio;
end
$$;

-- 6.6 Pós-live: ciclo fechado (até ciclo_fecha_em) e ciclo aberto (até agora)
create or replace function public.dados_atm_pos_live(p_chave text)
returns table (ciclo text, ate timestamptz, vendas integer, compradores integer, receita_bruta numeric,
               receita_liquida numeric, conversao_pct numeric, conversao_grupo_pct numeric,
               conversao_pre_checkout_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select count(*)::int as n from dados.atm_leads(d.chave) x where not x.teste),
  gp as (select case when v_tem_grupo then count(*)::int end as n
           from dados.v_grupo_pessoas g where g.chave = d.chave and g.entrou_em is not null),
  pc as (select count(*)::int as n from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select * from dados.atm_vendas(d.chave)),
  c as (select 'fechado'::text as ciclo, 1 as ordem, d.ciclo_fecha_em as ate
        union all select 'aberto', 2, now())
  select c.ciclo, c.ate, a.vendas, a.comp, a.bruta, a.liq,
         case when ld.n > 0 then round(a.comp::numeric * 100 / ld.n, 2)::numeric(7,2) end,
         case when gp.n > 0 then round(a.comp::numeric * 100 / gp.n, 2)::numeric(7,2) end,
         case when pc.n > 0 then round(a.comp::numeric * 100 / pc.n, 2)::numeric(7,2) end
    from c cross join ld cross join gp cross join pc
    cross join lateral (
      select case when d.oferta_codigo is null or c.ate is null then null else count(*)::int end as vendas,
             case when d.oferta_codigo is null or c.ate is null then null else count(distinct tx.email)::int end as comp,
             case when d.oferta_codigo is null or c.ate is null then null
                  else coalesce(sum(tx.valor_bruto) filter (where tx.moeda = 'BRL'), 0)::numeric(14,2) end as bruta,
             case when d.oferta_codigo is null or c.ate is null then null
                  else coalesce(sum(tx.valor_liquido) filter (where tx.moeda = 'BRL'), 0)::numeric(14,2) end as liq
        from tx where c.ate is not null and tx.aprovado_em <= c.ate
    ) a
   order by c.ordem;
end
$$;

revoke all on function public.dados_atm_resumo(text), public.dados_atm_leads(text), public.dados_atm_serie_diaria(text),
                       public.dados_atm_disparos_canais(text), public.dados_atm_comparecimento(text),
                       public.dados_atm_pos_live(text) from public, anon;
grant execute on function public.dados_atm_resumo(text), public.dados_atm_leads(text), public.dados_atm_serie_diaria(text),
                          public.dados_atm_disparos_canais(text), public.dados_atm_comparecimento(text),
                          public.dados_atm_pos_live(text) to authenticated;

-- 20261008161100: cadastro do ATM 1 da Dra. Elaine (atm-elaine-1-2026-10) no modelo seminario-atm
--
-- STATUS: ESCRITA, NÃO APLICADA. Depende da 20261008161000. TRAVADA DE PROPÓSITO até alguém preencher a SIGLA (v_sigla
-- abaixo): a guarda aborta enquanto ela for nula. A sigla é decisão do Victor (dono do padrão de nomenclatura) e tem de
-- casar com '^[A-Z]{2,10}[0-9]{2,4}$' (check de mkt.projetos). Ela é o que liga os disparos da Mensageria ao projeto
-- ([SIGLA] no nome da campanha). Observado em 08/10: o disparo de e-mail "SEMATMOUT - BYTHEWAY" (sem colchete e sem
-- número, então não casa com o check; não usei).
-- Ensaio: dentro de 20261008161000_ensaio.sql (com sigla fictícia só na transação).
--
-- PARA VOLTAR: rodar o bloco REVERSÃO de 20261008161000_reversao.sql (parte "cadastro da edição"): apaga sessões, grupos
--   e listas da chave, a linha de dados.dashboards e o projeto (só se nenhum disparo, página ou lead apontar para ele).
--
-- O QUE CADASTRA (cada valor com a fonte)
--   mkt.projetos ......... etiqueta atm-elaine-1-2026-10 (briefing e CONTEXT.md do projeto no gp-operacoes); nome
--                          "ATM 1 da Dra. Elaine, outubro de 2026" (título da concepção); linha 'Seminário' (a mesma do
--                          SEMSET26); tipo interno, unidade escritorio (iguais ao SEMSET26); especialista 2 = Elaine
--                          Montenegro (mkt.especialistas); evento 13/10 a 15/10/2026 (live, replay, triplay: concepção).
--   dados.dashboards ..... modelo seminario-atm; conta escritorio (a oferta é a de 3.000 da Sessão de Viabilidade, produto
--                          5238525, conta escritorio em fin.hotmart_transacoes); oferta_codigo NULO (tarefa 86aktf1c3 do
--                          Arthur, "Configurar o checkout da oferta de 3.000", prazo 09/10: código ainda não existe);
--                          lista_ac_leads 615 ("Seminário ATM Outubro 2026 - Leads", criada 07/10, página ak1);
--                          lista_ac (pré-checkout) NULA (lista do gateway Guardiões do Legado não identificada);
--                          vendas_desde 07/10/2026 00:00 de São Paulo (início da reativação, concepção);
--                          ciclo_fecha_em NULO (hora do triplay em aberto na concepção, seção 7).
--   dados.sessoes ........ live 13/10/2026 19:30 de São Paulo (concepção). Replay e triplay: sem hora definida, não
--                          cadastrados.
--   dados.dashboard_grupos  nada: o nome da campanha do SendFlow do ATM não está no banco nem no CONTEXT.md
--                          (whatsapp_grupos: nao-encontrado).
--
-- Para preencher depois (cada um é um update/insert de 1 linha; exemplos em docs/dashboard-atm/MODELO-DE-DADOS.md §4):
--   oferta_codigo, lista_ac, ciclo_fecha_em, campanha do SendFlow, replay e triplay, pico e equipe de cada sessão.

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $c$
declare
  v_sigla   text := 'ZZENSAIO99';   -- <<< PREENCHER (decisão do Victor). Ex. de formato: 'XXXX26'
  v_chave   text := 'atm-elaine-1-2026-10';
  v_proj    bigint;
begin
  if v_sigla is null then
    raise exception '20261008161100: sigla do projeto não definida. Preencher v_sigla com a sigla aprovada pelo Victor.';
  end if;
  if v_sigla !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    raise exception '20261008161100: sigla % fora do padrão de mkt.projetos', v_sigla;
  end if;
  if to_regclass('dados.sessoes') is null then
    raise exception '20261008161100: aplicar antes a 20261008161000';
  end if;
  if exists (select 1 from mkt.projetos where sigla = v_sigla and etiqueta_clickup is distinct from v_chave) then
    raise exception '20261008161100: a sigla % já existe com outra etiqueta', v_sigla;
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave and sigla <> v_sigla) then
    raise exception '20261008161100: % já cadastrada com outra sigla', v_chave;
  end if;
  if (select nome from mkt.especialistas where id = 2) is distinct from 'Elaine Montenegro' then
    raise exception '20261008161100: especialista 2 não é mais Elaine Montenegro';
  end if;

  insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, tipo, unidade, especialista_id,
                            evento_inicio, evento_fim, obs)
  select v_sigla, 'ATM 1 da Dra. Elaine, outubro de 2026', 'Seminário', 2026, v_chave, 'interno', 'escritorio', 2,
         date '2026-10-13', date '2026-10-15', 'Seminário ATM, live 13/10 19h30. Card 86aktf11y. 20261008161100.'
   where not exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave);
  select id into v_proj from mkt.projetos where etiqueta_clickup = v_chave;

  insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, oferta_codigo, lista_ac, lista_ac_leads,
                                vendas_desde, ciclo_fecha_em)
  values (v_chave, 'seminario-atm', v_proj, 'escritorio', null, null, '615',
          timestamptz '2026-10-07 00:00:00-03', null)
  on conflict (chave) do nothing;

  insert into dados.sessoes (chave, tipo, inicio)
  values (v_chave, 'live', timestamptz '2026-10-13 19:30:00-03')
  on conflict (chave, tipo, inicio) do nothing;
end
$c$;

-- passada 2 (idempotência)
-- 20261008161000: modelo de dashboard "seminario-atm" no schema dados (Seminário ATM, padrão para todos os ATMs)
--
-- STATUS: ESCRITA, NÃO APLICADA. Aplicar só com aval do JP (dono do banco desde 08/10/2026) e do Victor Hugo, depois do
-- pentester (cria RPC com GRANT para authenticated e devolve dado pessoal de lead: e-mail, nome, telefone).
-- Ensaio: 20261008161000_ensaio.sql. Relatório: 20261008161000.explain.md. Reversão: 20261008161000_reversao.sql.
-- Contrato com a tela: docs/dashboard-atm/MODELO-DE-DADOS.md. Mudar coluna, tipo ou ordem quebra a tela.
--
-- PARA VOLTAR: rodar 20261008161000_reversao.sql (drop das 6 funções públicas, dos ajudantes, das 2 views, das 5 tabelas
--   novas, das 3 colunas novas de dados.dashboards; devolve o NOT NULL de oferta_codigo e o check de modelo). Só volta
--   limpo se nenhum dashboard 'seminario-atm' estiver cadastrado (a reversão aborta e avisa).
--
-- POR QUE
--   Card 86aktf11y (dashboard do ATM 1 da Dra. Elaine, chave atm-elaine-1-2026-10). Regra do briefing: nada lê
--   planilha, tudo vem do banco, e o modelo vale para os próximos ATMs (27/10, 17/11) só com cadastro pela chave.
--   Reaproveita o modelo presencial (20261007161809): dados.dashboards, dados.cadastro (gate), dados.transacoes (Hotmart
--   na forma da trava), dados.pre_checkout, dados.perfil, mkt_mensageria.disparos. Só cria o que não existe no banco.
--
-- O QUE JÁ EXISTE E É LIDO (levantamento só leitura em 08/10/2026)
--   leads ........ crm.evento_jornada da lista do ActiveCampaign da edição (lista 615 "Seminário ATM Outubro 2026 -
--                  Leads", página atm.guardioesdolegado.com.br/ak1; webhook do AC grava desde 07/10) + pessoas.eventos
--                  tipo 'lead' do projeto (rota /api/captura/lead, se a página passar a chamar).
--   pré-checkout . dados.pre_checkout (o mesmo do presencial): evento pre_checkout do projeto + lista do AC (lista_ac).
--   vendas ....... dados.transacoes(conta, oferta) = fin.hotmart_transacoes (sync de hora em hora; o webhook em tempo
--                  real só cobre a conta academy, e a Sessão de Viabilidade é da conta escritorio).
--   disparos ..... mkt_mensageria.disparos do projeto (canal whatsapp_api, grupo, sms, ligacao, email; custo_centavos).
--   aluno ........ public.thb_alunos (instrução) e public.thb_turmas, via dados.perfil.
--   grupo ........ crm.evento_jornada fonte 'sendflow' (Edge crm-integracao-webhook /sendflow: tipo entrada/saida,
--                  fone_key, tag = nome da campanha no SendFlow). HOJE DESLIGADO (crm.config.sendflow_ligado = false) e
--                  sem nenhum evento: ligar é decisão do JP/Victor (proposta no explain), não desta migration.
--
-- O QUE FAZ (só o mínimo que falta)
--   1. public.tg_carimbar_atualizado_em(): o gatilho padrão do PADRAO-DE-BANCO (não existia no banco). Criado só se
--      não existir.
--   2. dados.dashboards: modelo 'seminario-atm' no check; oferta_codigo aceita nulo (oferta ainda não configurada =
--      vendas "sem dado ainda"); colunas novas lista_ac_leads, vendas_desde, ciclo_fecha_em.
--   3. Tabelas novas (RLS ligada, sem policy, sem grant; criado_em/atualizado_em com o gatilho padrão):
--      dados.ddd_uf ............ DDD -> UF (copiado de sal_uf, dashboard-ht api/sem-atm2-leads.php)
--      dados.dashboard_grupos .. campanha(s) do SendFlow de cada dashboard (casa com crm.evento_jornada.tag)
--      dados.lista_membros ..... Lista 1 / Lista 2 e seminário de origem (Marcio, Elaine) de cada edição, por chave
--                                normalizada de e-mail e telefone (sem nome, sem payload)
--      dados.sessoes ........... live, replay e triplay da edição: início, fim, pico de audiência, equipe na sala
--      dados.sessao_presencas .. quem esteve em cada sessão (relatório do Zoom), por chave de e-mail/telefone
--   4. Views internas (security_invoker = true, sem grant): dados.v_grupo_eventos e dados.v_grupo_pessoas.
--   5. Ajudantes internos (sem grant): dados.leads_todos, dados.atm_leads, dados.atm_vendas, dados.atm_cadastro.
--   6. RPCs da tela (security definer, search_path '', execute só authenticated): dados_atm_resumo, dados_atm_leads,
--      dados_atm_serie_diaria, dados_atm_disparos_canais, dados_atm_comparecimento, dados_atm_pos_live.
--      Detalhe por disparo e lista de vendas: as do presencial servem como estão (dados_presencial_disparos,
--      dados_presencial_vendas; não olham o modelo).
--
-- POR QUE RPC E NÃO VIEW PARA A TELA
--   O pedido falava em views com security_invoker. As views existem (item 4), mas a tela não pode lê-las direto:
--   authenticated não tem grant nem policy em pessoas, crm, fin e mkt_mensageria (fechados por decisão), e o dado é por
--   chave (view não recebe parâmetro). PADRAO-DE-BANCO 6.4: "View que precisa furar RLS vira função com guarda". É o
--   mesmo desenho do dashboard presencial.
--
-- AS 5 PERGUNTAS
--   escala: hoje 46 leads na lista 615, 0 evento de grupo, 0 venda da oferta (oferta ainda não definida). Um ATM tem na
--     ordem de mil leads (setembro: 911). Tudo agrega por 1 chave, 1 lista, 1 oferta, 1 projeto.
--   índice: as tabelas novas nascem com índice nas FK e nas chaves de casamento. crm.evento_jornada é lida por lista
--     e por fonte/tag sem índice hoje (24.374 linhas em 08/10); os dois índices estão em arquivo próprio,
--     20261008161001_crm_criar_indice_evento_jornada_lista.sql (concurrently, fora de transação).
--   frequência: a tela chama resumo e série ao abrir e a cada 60 s com a aba visível (como o presencial); leads,
--     comparecimento e pós-live sob demanda.
--   repetição: cada RPC monta os leads uma vez (dados.atm_leads) e agrega em cima.
--   reversão: 20261008161000_reversao.sql.
--
-- IDEMPOTENTE: create … if not exists / create or replace / on conflict do nothing / drop constraint if exists.
-- Guarda aborta se a base do presencial mudou (colunas de dados.dashboards, funções de apoio).

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v_cols text;
begin
  foreach v_cols in array array['public.gp_eh_equipe()', 'dados.cadastro(text)', 'dados.transacoes(text,text)',
                                'dados.pre_checkout(text,bigint,text)', 'dados.perfil(text)', 'pessoas.atual(uuid)',
                                'pessoas.norm_email(text)', 'controle.fone_key(text)'] loop
    if to_regprocedure(v_cols) is null then
      raise exception '20261008161000: % não existe', v_cols;
    end if;
  end loop;
  select string_agg(column_name, ',' order by ordinal_position) into v_cols
    from information_schema.columns where table_schema = 'dados' and table_name = 'dashboards';
  if v_cols not in ('chave,modelo,projeto_id,conta_hotmart,oferta_codigo,lista_ac,ativo,criado_em,ofertas_extra',
                    'chave,modelo,projeto_id,conta_hotmart,oferta_codigo,lista_ac,ativo,criado_em,ofertas_extra,lista_ac_leads,vendas_desde,ciclo_fecha_em') then
    raise exception '20261008161000: dados.dashboards com colunas inesperadas (%). Conferir.', v_cols;
  end if;
  if to_regclass('crm.evento_jornada') is null
     or (select count(*) from information_schema.columns where table_schema = 'crm' and table_name = 'evento_jornada'
          and column_name in ('fonte', 'tipo', 'ocorreu_em', 'email_norm', 'fone_key', 'nome', 'lista', 'tag', 'pessoa_id')) <> 9 then
    raise exception '20261008161000: crm.evento_jornada sem as colunas esperadas';
  end if;
  if to_regprocedure('public.tg_carimbar_atualizado_em()') is not null
     and (select prorettype from pg_proc where oid = to_regprocedure('public.tg_carimbar_atualizado_em()')) <> 'trigger'::regtype then
    raise exception '20261008161000: public.tg_carimbar_atualizado_em() existe e não é função de gatilho';
  end if;
end
$g$;

-- 1. Gatilho padrão de atualizado_em (PADRAO-DE-BANCO 5.6). Só cria se não existir.
do $t$
begin
  if to_regprocedure('public.tg_carimbar_atualizado_em()') is null then
    execute $f$
      create function public.tg_carimbar_atualizado_em() returns trigger
      language plpgsql set search_path = '' as $b$
      begin
        new.atualizado_em := now();
        return new;
      end
      $b$
    $f$;
    execute 'revoke all on function public.tg_carimbar_atualizado_em() from public, anon, authenticated';
    execute $c$comment on function public.tg_carimbar_atualizado_em() is
      'Gatilho padrão (PADRAO-DE-BANCO 5.6): carimba atualizado_em = now() em todo UPDATE. 20261008161000.'$c$;
  end if;
end
$t$;

-- 2. dados.dashboards: modelo novo e colunas do ATM
alter table dados.dashboards drop constraint if exists dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check check (modelo in ('presencial-base', 'seminario-atm'));
alter table dados.dashboards alter column oferta_codigo drop not null;
alter table dados.dashboards add column if not exists lista_ac_leads text
  check (lista_ac_leads is null or lista_ac_leads ~ '^[0-9]{1,10}$');
alter table dados.dashboards add column if not exists vendas_desde timestamptz;
alter table dados.dashboards add column if not exists ciclo_fecha_em timestamptz;
comment on column dados.dashboards.oferta_codigo is
  'Oferta principal na Hotmart. Nulo = oferta ainda não configurada: vendas, receita, CAC e ROAS saem nulos ("sem dado ainda"). 20261008161000.';
comment on column dados.dashboards.lista_ac_leads is
  'Modelo seminario-atm: id da lista do ActiveCampaign onde a página de inscrição grava o lead (crm.evento_jornada.lista). 20261008161000.';
comment on column dados.dashboards.vendas_desde is
  'Modelo seminario-atm: só contam transações com pedido a partir daqui (a oferta pode ser a mesma de outros eventos). Nulo = sem corte. 20261008161000.';
comment on column dados.dashboards.ciclo_fecha_em is
  'Modelo seminario-atm: fim do ciclo fechado (live, replay e triplay). Vendas aprovadas até aqui = ciclo fechado; até agora = ciclo aberto. Nulo = ciclo ainda sem data de fechamento. 20261008161000.';

-- 3. Tabelas novas
-- 3.1 DDD -> UF (fonte: sal_uf do dashboard-ht, api/sem-atm2-leads.php; DDD fora da tabela = 'Outros' na leitura)
create table if not exists dados.ddd_uf (
  ddd           text primary key check (ddd ~ '^[1-9][0-9]$'),
  uf            text not null check (uf ~ '^[A-Z]{2}$'),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
comment on table dados.ddd_uf is 'DDD -> UF para a coluna estado dos leads (o formulário não pede UF). Copiado de sal_uf (dashboard-ht). 20261008161000.';
insert into dados.ddd_uf (ddd, uf) values
  ('11','SP'),('12','SP'),('13','SP'),('14','SP'),('15','SP'),('16','SP'),('17','SP'),('18','SP'),('19','SP'),
  ('21','RJ'),('22','RJ'),('24','RJ'),('27','ES'),('28','ES'),
  ('31','MG'),('32','MG'),('33','MG'),('34','MG'),('35','MG'),('37','MG'),('38','MG'),
  ('41','PR'),('42','PR'),('43','PR'),('44','PR'),('45','PR'),('46','PR'),
  ('47','SC'),('48','SC'),('49','SC'),('51','RS'),('53','RS'),('54','RS'),('55','RS'),
  ('61','DF'),('62','GO'),('64','GO'),('63','TO'),('65','MT'),('66','MT'),('67','MS'),
  ('68','AC'),('69','RO'),('71','BA'),('73','BA'),('74','BA'),('75','BA'),('77','BA'),('79','SE'),
  ('81','PE'),('87','PE'),('82','AL'),('83','PB'),('84','RN'),('85','CE'),('88','CE'),('86','PI'),('89','PI'),
  ('91','PA'),('93','PA'),('94','PA'),('92','AM'),('97','AM'),('95','RR'),('96','AP'),('98','MA'),('99','MA')
on conflict (ddd) do nothing;

-- 3.2 Campanhas do SendFlow de cada dashboard
create table if not exists dados.dashboard_grupos (
  id                 uuid primary key default gen_random_uuid(),
  chave              text not null references dados.dashboards(chave) on delete restrict,
  sendflow_campanha  text not null check (length(btrim(sendflow_campanha)) between 1 and 200),
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  unique (chave, sendflow_campanha)
);
comment on table dados.dashboard_grupos is
  'Campanha(s) do SendFlow do dashboard. sendflow_campanha = nome EXATO da campanha (o webhook grava em crm.evento_jornada.tag). Sem linha = grupo "sem fonte" (nulo na tela). 20261008161000.';

-- 3.3 Lista 1 / Lista 2 e seminário de origem de cada edição
create table if not exists dados.lista_membros (
  id                bigint generated always as identity primary key,
  chave             text not null references dados.dashboards(chave) on delete restrict,
  lista             text not null check (lista in ('lista_1', 'lista_2')),
  seminario_origem  text check (seminario_origem in ('marcio', 'elaine', 'marcio_e_elaine')),
  email_norm        text check (email_norm is null or email_norm = pessoas.norm_email(email_norm)),
  fone_key          text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  importacao        text not null check (length(btrim(importacao)) between 3 and 120),
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  check (email_norm is not null or fone_key is not null)
);
create unique index if not exists lista_membros_unico
  on dados.lista_membros (chave, lista, coalesce(email_norm, ''), coalesce(fone_key, ''));
create index if not exists lista_membros_email_idx on dados.lista_membros (chave, email_norm) where email_norm is not null;
create index if not exists lista_membros_fone8_idx on dados.lista_membros (chave, right(fone_key, 8)) where fone_key is not null;
comment on table dados.lista_membros is
  'Quem está na Lista 1 (geral/e-mail) e na Lista 2 (passou pelo pré-checkout da SV, menos quem reagiu ao último ATM) de cada edição, e de qual seminário veio. Só chave normalizada (e-mail minúsculo, telefone DDD+8), sem nome. importacao = rótulo do lote (sem dado pessoal). Carga por service_role. 20261008161000.';

-- 3.4 Sessões ao vivo (live, replay, triplay)
create table if not exists dados.sessoes (
  id               uuid primary key default gen_random_uuid(),
  chave            text not null references dados.dashboards(chave) on delete restrict,
  tipo             text not null check (tipo in ('live', 'replay', 'triplay')),
  inicio           timestamptz not null,
  fim              timestamptz check (fim is null or fim > inicio),
  pico_audiencia   integer check (pico_audiencia is null or pico_audiencia >= 0),
  equipe_na_sala   integer check (equipe_na_sala is null or equipe_na_sala >= 0),
  obs              text check (obs is null or length(obs) <= 500),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (chave, tipo, inicio)
);
comment on table dados.sessoes is
  'Live, replay e triplay de cada dashboard. pico_audiencia e equipe_na_sala: lançados do Zoom (nulo = não lançado, nunca 0). 20261008161000.';

-- 3.5 Presença por pessoa em cada sessão
create table if not exists dados.sessao_presencas (
  id                bigint generated always as identity primary key,
  sessao_id         uuid not null references dados.sessoes(id) on delete restrict,
  email_norm        text check (email_norm is null or email_norm = pessoas.norm_email(email_norm)),
  fone_key          text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  eh_equipe         boolean not null default false,
  minutos           integer check (minutos is null or minutos >= 0),
  primeira_entrada  timestamptz,
  fonte             text not null check (fonte in ('zoom_relatorio', 'manual')),
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  check (email_norm is not null or fone_key is not null)
);
create unique index if not exists sessao_presencas_unico
  on dados.sessao_presencas (sessao_id, coalesce(email_norm, ''), coalesce(fone_key, ''));
comment on table dados.sessao_presencas is
  'Quem esteve na sessão (relatório de participantes do Zoom), por chave normalizada. Sem nome. eh_equipe = pessoa da casa (não conta como lead presente). 20261008161000.';

do $r$
declare v text;
begin
  foreach v in array array['ddd_uf', 'dashboard_grupos', 'lista_membros', 'sessoes', 'sessao_presencas'] loop
    execute format('alter table dados.%I enable row level security', v);
    execute format('revoke all on dados.%I from public, anon, authenticated', v);
    execute format('drop trigger if exists carimbar_atualizado_em on dados.%I', v);
    execute format('create trigger carimbar_atualizado_em before update on dados.%I '
                   'for each row execute function public.tg_carimbar_atualizado_em()', v);
  end loop;
end
$r$;

-- 4. Views internas (security_invoker; sem grant: só o dono e as funções leem)
create or replace view dados.v_grupo_eventos with (security_invoker = true) as
  select g.chave, j.id as evento_id, j.tipo, j.fone_key, right(j.fone_key, 8) as fone8, j.ocorreu_em, j.pessoa_id
    from crm.evento_jornada j
    join dados.dashboard_grupos g on g.sendflow_campanha = j.tag
   where j.fonte = 'sendflow' and j.tipo in ('entrada', 'saida') and j.fone_key is not null;
comment on view dados.v_grupo_eventos is
  'Entradas e saídas do grupo de WhatsApp por dashboard (crm.evento_jornada fonte sendflow, tag = campanha cadastrada em dados.dashboard_grupos). 20261008161000.';

create or replace view dados.v_grupo_pessoas with (security_invoker = true) as
  select e.chave, e.fone8,
         min(e.ocorreu_em) filter (where e.tipo = 'entrada') as entrou_em,
         max(e.ocorreu_em) filter (where e.tipo = 'saida') as saiu_em,
         (array_agg(e.tipo order by e.ocorreu_em desc, e.evento_id desc))[1] = 'entrada' as no_grupo,
         (array_agg(e.pessoa_id order by e.ocorreu_em desc) filter (where e.pessoa_id is not null))[1] as pessoa_id
    from dados.v_grupo_eventos e
   group by e.chave, e.fone8;
comment on view dados.v_grupo_pessoas is
  'Uma linha por pessoa (telefone DDD+8 -> últimos 8) por dashboard: primeira entrada, última saída e se ainda está no grupo. Saída só conta para quem entrou (regra do debriefing ATM SET/26). 20261008161000.';

revoke all on dados.v_grupo_eventos, dados.v_grupo_pessoas from public, anon, authenticated;

-- 5. Ajudantes internos
-- 5.1 Leads: lista do AC da edição + evento 'lead' do projeto (mesma forma do pre_checkout_todos, 20261007te)
create or replace function dados.leads_todos(p_chave text, p_projeto_id bigint, p_lista text)
returns table (email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, pessoa_id uuid, teste boolean)
language sql stable set search_path = '' as $$
  -- 20261008161000
  with passagens as (
    -- sistema (rota /api/captura/lead -> pessoas.registrar, tipo lead)
    select em.chave as email, p.nome, tel.valor as telefone, e.quando, 'sistema'::text as fonte,
           o.utm_source, o.utm_medium, o.utm_campaign, o.utm_content, o.utm_term,
           p.id as pessoa_id, coalesce(p.teste, false) as teste
      from pessoas.eventos e
      join pessoas.pessoas p on p.id = pessoas.atual(e.pessoa_id)
      cross join lateral (select i.chave from pessoas.identificadores i
                           where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'email' order by i.criado_em desc limit 1) em
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
      left join pessoas.origens o on o.id = e.origem_id
     where e.tipo = 'lead'
       and (e.projeto_id = p_projeto_id or e.detalhe ->> 'chave_evento' = p_chave)
    union all
    -- ActiveCampaign (entrada na lista de leads da edição)
    select j.email_norm, nullif(btrim(j.nome), ''), tel.valor, j.ocorreu_em, 'activecampaign',
           null, null, null, null, null,
           p.id, coalesce(p.teste, false)
      from crm.evento_jornada j
      left join pessoas.pessoas p on p.id = pessoas.atual(j.pessoa_id)
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (j.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
     where p_lista is not null and j.fonte = 'activecampaign' and j.lista = p_lista and j.email_norm is not null
  ), limpo as (
    select lower(btrim(x.email)) as email, nullif(btrim(x.nome), '') as nome, nullif(btrim(x.telefone), '') as telefone,
           x.quando, x.fonte, x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content, x.utm_term, x.pessoa_id, x.teste
      from passagens x
     where nullif(btrim(x.email), '') is not null and lower(btrim(x.email)) not like '%@exemplo.invalid'
  )
  select l.email,
         (select y.nome from limpo y where y.email = l.email and y.nome is not null order by y.quando desc limit 1),
         (select y.telefone from limpo y where y.email = l.email and y.telefone is not null order by y.quando desc limit 1),
         min(l.quando),
         case when bool_and(l.fonte = 'sistema') then 'sistema'
              when bool_and(l.fonte = 'activecampaign') then 'activecampaign' else 'ambos' end,
         u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term,
         (select y.pessoa_id from limpo y where y.email = l.email and y.pessoa_id is not null
           order by y.teste desc, y.quando desc limit 1),
         bool_or(l.teste)
    from limpo l
    left join lateral (select y.utm_source, y.utm_medium, y.utm_campaign, y.utm_content, y.utm_term
                         from limpo y where y.email = l.email and y.fonte = 'sistema'
                        order by y.quando limit 1) u on true
   group by l.email, u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term
$$;

-- 5.2 Gate do modelo: o mesmo dados.cadastro (equipe, chave ativa) + modelo certo
create or replace function dados.atm_cadastro(p_chave text)
returns dados.dashboards
language plpgsql stable set search_path = '' as $$
declare
  r dados.dashboards := dados.cadastro(p_chave);   -- 42501 sem acesso, P0002 chave fora do cadastro
begin
  if r.modelo is distinct from 'seminario-atm' then
    raise exception 'dashboard de outro modelo' using errcode = 'P0002';
  end if;
  return r;
end
$$;

-- 5.3 Vendas da edição: pagas, 1ª cobrança, pedido a partir de vendas_desde
create or replace function dados.atm_vendas(p_chave text)
returns table (transacao text, pedido_em timestamptz, aprovado_em timestamptz, dia_aprovado date, moeda text,
               valor_bruto numeric, valor_liquido numeric, email text)
language sql stable set search_path = '' as $$
  -- 20261008161000
  select t.transacao, t.pedido_em, t.aprovado_em, t.dia_aprovado, t.moeda, t.valor_bruto, t.valor_liquido, t.email
    from dados.dashboards d
    cross join lateral dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
   where d.chave = p_chave and d.oferta_codigo is not null
     and t.pago and t.primeira
     and (d.vendas_desde is null or coalesce(t.pedido_em, t.aprovado_em) >= d.vendas_desde)
$$;

-- 5.4 Leads enriquecidos (fonte única do modal e dos números)
create or replace function dados.atm_leads(p_chave text)
returns table (email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
               entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text,
               lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean,
               pessoa_id uuid, teste boolean)
language sql stable set search_path = '' as $$
  -- 20261008161000
  with d as (select * from dados.dashboards where chave = p_chave),
  l as (
    select t.*, controle.fone_key(t.telefone) as fk
      from d cross join lateral dados.leads_todos(d.chave, d.projeto_id, d.lista_ac_leads) t
  ),
  tem as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = p_chave) as grupo,
           exists (select 1 from dados.lista_membros m where m.chave = p_chave) as listas
  ),
  pc as (select y.email from d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  vd as (select distinct v.email from dados.atm_vendas(p_chave) v where v.email is not null)
  select l.email, l.nome, l.telefone, l.primeiro_em, l.fonte, l.utm_source, l.utm_medium, l.utm_campaign,
         l.utm_content, l.utm_term,
         left(l.fk, 2),
         case when l.fk is null then null else coalesce((select u.uf from dados.ddd_uf u where u.ddd = left(l.fk, 2)), 'Outros') end,
         case when tem.grupo then coalesce(gp.entrou_em is not null, false) end,
         case when tem.grupo then coalesce(gp.entrou_em is not null and gp.saiu_em > gp.entrou_em, false) end,
         pf.instrucao is not null, pf.instrucao, pf.turma,
         case when not tem.listas then null
              when lm.l1 and lm.l2 then 'lista_1_e_2'
              when lm.l1 then 'lista_1' when lm.l2 then 'lista_2'
              else 'fora_das_listas' end,
         case when lm.marcio and lm.elaine then 'marcio_e_elaine'
              when lm.marcio then 'marcio' when lm.elaine then 'elaine' end,
         exists (select 1 from pc where pc.email = l.email),
         case when (select oferta_codigo from d) is null then null else exists (select 1 from vd where vd.email = l.email) end,
         l.pessoa_id, l.teste
    from l cross join tem
    left join lateral (select g.entrou_em, g.saiu_em from dados.v_grupo_pessoas g
                        where g.chave = p_chave and g.entrou_em is not null
                          and ((l.fk is not null and g.fone8 = right(l.fk, 8)) or (l.pessoa_id is not null and g.pessoa_id = l.pessoa_id))
                        order by g.entrou_em limit 1) gp on true
    left join lateral (select bool_or(m.lista = 'lista_1') as l1, bool_or(m.lista = 'lista_2') as l2,
                              bool_or(m.seminario_origem in ('marcio', 'marcio_e_elaine')) as marcio,
                              bool_or(m.seminario_origem in ('elaine', 'marcio_e_elaine')) as elaine
                         from dados.lista_membros m
                        where m.chave = p_chave
                          and (m.email_norm = l.email or (l.fk is not null and right(m.fone_key, 8) = right(l.fk, 8)))) lm on true
    left join lateral (select x.instrucao, x.turma from dados.perfil(l.email) x) pf on true
$$;

revoke all on function dados.leads_todos(text, bigint, text), dados.atm_cadastro(text), dados.atm_vendas(text),
                       dados.atm_leads(text) from public, anon, authenticated;

-- 6. RPCs da tela
-- 6.1 Resumo: os 14 cards da visão geral, na ordem do briefing
create or replace function public.dados_atm_resumo(p_chave text)
returns table (chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text,
               disparos_qtd integer, disparos_enviados integer, leads integer,
               grupo_tem_fonte boolean, grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric,
               custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint,
               pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer,
               compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint,
               receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric,
               atualizado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  with disp as (
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo, sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
  ),
  ld as (select * from dados.atm_leads(d.chave) where not teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em is not null)::int as entradas,
           count(*) filter (where g.entrou_em is not null and g.saiu_em > g.entrou_em)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  pc as (select y.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select * from dados.atm_vendas(d.chave)),
  ag as (
    select (select count(*)::int from ld) as leads,
           (select count(*)::int from pc) as pc,
           (select count(*)::int from tx) as vendas,
           (select count(*)::int from tx where tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  ),
  k as (select (disp.qtd > 0 and disp.sem = 0) as completo, d.oferta_codigo is not null as tem_oferta from disp)
  select d.chave, pr.id, pr.sigla, pr.nome, d.oferta_codigo,
         disp.qtd, disp.enviados, ag.leads,
         gr.fonte,
         case when gr.fonte then gr.entradas end,
         case when gr.fonte then gr.saidas end,
         case when gr.fonte and ag.leads > 0 then round(gr.entradas::numeric * 100 / ag.leads, 2)::numeric(7,2) end,
         case when gr.fonte and gr.entradas > 0 then round(gr.saidas::numeric * 100 / gr.entradas, 2)::numeric(7,2) end,
         disp.custo, disp.sem, k.completo,
         case when k.completo and ag.leads > 0 then round(disp.custo::numeric / ag.leads)::bigint end,
         ag.pc,
         case when k.tem_oferta then ag.vendas end,
         case when k.tem_oferta then ag.fora end,
         case when k.tem_oferta then ag.comp end,
         case when k.tem_oferta then ag.comp_pc end,
         case when k.tem_oferta and ag.pc > 0 then round(ag.comp::numeric * 100 / ag.pc, 2)::numeric(7,2) end,
         case when k.tem_oferta and k.completo and ag.vendas > 0 then round(disp.custo::numeric / ag.vendas)::bigint end,
         case when k.tem_oferta then ag.bruta end,
         case when k.tem_oferta then ag.liq end,
         case when k.tem_oferta and k.completo and disp.custo > 0 then round(ag.bruta * 100 / disp.custo, 2)::numeric(10,2) end,
         case when k.tem_oferta and k.completo and disp.custo > 0 then round(ag.liq * 100 / disp.custo, 2)::numeric(10,2) end,
         now()
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join k
   where pr.id = d.projeto_id;
end
$$;

-- 6.2 Leads (modal): todos, inclusive teste (coluna teste no fim); os números não contam teste
create or replace function public.dados_atm_leads(p_chave text)
returns table (email text, nome text, telefone text, primeiro_em timestamptz, fonte text, utm_source text,
               utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
               entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text,
               lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean,
               pessoa_id uuid, teste boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query select * from dados.atm_leads(d.chave) x order by x.primeiro_em desc, x.email;
end
$$;

-- 6.3 Série diária (dia em São Paulo, sem buraco, do 1º dia com dado até hoje)
create or replace function public.dados_atm_serie_diaria(p_chave text)
returns table (dia date, leads integer, grupo_entradas integer, grupo_saidas integer, pre_checkout integer,
               vendas integer, receita_bruta numeric, custo_disparo_centavos bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_leads(d.chave) x where not x.teste),
  ge as (select (g.entrou_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null),
  gs as (select (g.saiu_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null and g.saiu_em > g.entrou_em),
  pc as (select (y.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
           from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select v.dia_aprovado as dia, v.valor_bruto, v.moeda from dados.atm_vendas(d.chave) v),
  ds as (select (x.enviado_em at time zone 'America/Sao_Paulo')::date as dia, x.custo_centavos
           from mkt_mensageria.disparos x where x.projeto_id = d.projeto_id and x.arquivado_em is null),
  lim as (
    select least((select min(dia) from ld), (select min(dia) from ge), (select min(dia) from pc),
                 (select min(dia) from tx), (select min(dia) from ds)) as de
  )
  select s::date,
         (select count(*)::int from ld where ld.dia = s::date),
         case when v_tem_grupo then (select count(*)::int from ge where ge.dia = s::date) end,
         case when v_tem_grupo then (select count(*)::int from gs where gs.dia = s::date) end,
         (select count(*)::int from pc where pc.dia = s::date),
         case when d.oferta_codigo is not null then (select count(*)::int from tx where tx.dia = s::date) end,
         case when d.oferta_codigo is not null then
           (select coalesce(sum(tx.valor_bruto), 0)::numeric(14,2) from tx where tx.dia = s::date and tx.moeda = 'BRL') end,
         (select case when count(*) filter (where ds.custo_centavos is null) = 0 then sum(ds.custo_centavos)::bigint end
            from ds where ds.dia = s::date having count(*) > 0)
    from lim
    cross join lateral generate_series(lim.de, (now() at time zone 'America/Sao_Paulo')::date, interval '1 day') s
   where lim.de is not null
   order by 1;
end
$$;

-- 6.4 Disparos por canal: sempre 5 linhas, na ordem das abas (API, Grupo, SMS, Ligação, E-mail)
create or replace function public.dados_atm_disparos_canais(p_chave text)
returns table (canal text, disparos integer, enviados integer, entregues integer, lidas integer, cliques integer,
               falhas integer, custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  select c.canal, count(x.id)::int, sum(x.tamanho_lista)::int, sum(x.entregues)::int, sum(x.lidas)::int,
         sum(x.cliques)::int, sum(x.falhas)::int,
         sum(x.custo_centavos)::bigint,
         count(x.id) filter (where x.custo_centavos is null)::int,
         count(x.id) > 0 and count(x.id) filter (where x.custo_centavos is null) = 0
    from (values (1, 'whatsapp_api'), (2, 'grupo'), (3, 'sms'), (4, 'ligacao'), (5, 'email')) c(ordem, canal)
    left join mkt_mensageria.disparos x
           on x.canal = c.canal and x.projeto_id = d.projeto_id and x.arquivado_em is null
   group by c.ordem, c.canal
   order by c.ordem;
end
$$;

-- 6.5 Comparecimento: 1 linha por sessão cadastrada
create or replace function public.dados_atm_comparecimento(p_chave text)
returns table (sessao_id uuid, tipo text, inicio timestamptz, fim timestamptz, pico_audiencia integer,
               equipe_na_sala integer, total_leads integer, total_grupo integer, presentes integer,
               presentes_leads integer, presentes_grupo integer, pico_sobre_leads_pct numeric,
               pico_sobre_grupo_pct numeric, presentes_leads_pct numeric, presentes_grupo_pct numeric,
               vendas integer, conversao_pct numeric, conversao_grupo_pct numeric, conversao_pico_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select x.email, controle.fone_key(x.telefone) as fk from dados.atm_leads(d.chave) x where not x.teste),
  gp as (select g.fone8 from dados.v_grupo_pessoas g where g.chave = d.chave and g.entrou_em is not null),
  tot as (select (select count(*)::int from ld) as leads,
                 case when v_tem_grupo then (select count(*)::int from gp) end as grupo),
  ss as (
    select s.*, lead(s.inicio) over (order by s.inicio) as proxima
      from dados.sessoes s where s.chave = d.chave
  ),
  pr as (
    -- presente = pessoa fora da equipe; é lead se casa por e-mail ou telefone; é do grupo se o telefone (dele ou do
    -- lead casado pelo e-mail) entrou no grupo
    select p.sessao_id,
           count(*)::int as presentes,
           count(*) filter (where m.eh_lead)::int as p_leads,
           count(*) filter (where exists (select 1 from gp where gp.fone8 = coalesce(right(p.fone_key, 8), m.fk8)))::int as p_grupo
      from dados.sessao_presencas p
      left join lateral (select true as eh_lead, right(ld.fk, 8) as fk8 from ld
                          where ld.email = p.email_norm
                             or (p.fone_key is not null and right(ld.fk, 8) = right(p.fone_key, 8))
                          order by (ld.email = p.email_norm) desc nulls last limit 1) m on true
     where p.sessao_id in (select id from ss) and not p.eh_equipe
     group by p.sessao_id
  ),
  tx as (select v.aprovado_em from dados.atm_vendas(d.chave) v)
  select ss.id, ss.tipo, ss.inicio, ss.fim, ss.pico_audiencia, ss.equipe_na_sala, tot.leads, tot.grupo,
         pr.presentes, pr.p_leads, case when v_tem_grupo then pr.p_grupo end,
         case when tot.leads > 0 then round(ss.pico_audiencia::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when tot.grupo > 0 then round(ss.pico_audiencia::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         case when tot.leads > 0 then round(pr.p_leads::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when v_tem_grupo and tot.grupo > 0 then round(pr.p_grupo::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         vs.n,
         case when tot.leads > 0 then round(vs.n::numeric * 100 / tot.leads, 2)::numeric(7,2) end,
         case when tot.grupo > 0 then round(vs.n::numeric * 100 / tot.grupo, 2)::numeric(7,2) end,
         case when ss.pico_audiencia > 0 then round(vs.n::numeric * 100 / ss.pico_audiencia, 2)::numeric(7,2) end
    from ss cross join tot
    left join pr on pr.sessao_id = ss.id
    cross join lateral (
      select case when d.oferta_codigo is null then null
                  else (select count(*)::int from tx
                         where tx.aprovado_em >= ss.inicio
                           and tx.aprovado_em < coalesce(ss.proxima, d.ciclo_fecha_em, now())) end as n
    ) vs
   order by ss.inicio;
end
$$;

-- 6.6 Pós-live: ciclo fechado (até ciclo_fecha_em) e ciclo aberto (até agora)
create or replace function public.dados_atm_pos_live(p_chave text)
returns table (ciclo text, ate timestamptz, vendas integer, compradores integer, receita_bruta numeric,
               receita_liquida numeric, conversao_pct numeric, conversao_grupo_pct numeric,
               conversao_pre_checkout_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
begin
  return query
  with ld as (select count(*)::int as n from dados.atm_leads(d.chave) x where not x.teste),
  gp as (select case when v_tem_grupo then count(*)::int end as n
           from dados.v_grupo_pessoas g where g.chave = d.chave and g.entrou_em is not null),
  pc as (select count(*)::int as n from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  tx as (select * from dados.atm_vendas(d.chave)),
  c as (select 'fechado'::text as ciclo, 1 as ordem, d.ciclo_fecha_em as ate
        union all select 'aberto', 2, now())
  select c.ciclo, c.ate, a.vendas, a.comp, a.bruta, a.liq,
         case when ld.n > 0 then round(a.comp::numeric * 100 / ld.n, 2)::numeric(7,2) end,
         case when gp.n > 0 then round(a.comp::numeric * 100 / gp.n, 2)::numeric(7,2) end,
         case when pc.n > 0 then round(a.comp::numeric * 100 / pc.n, 2)::numeric(7,2) end
    from c cross join ld cross join gp cross join pc
    cross join lateral (
      select case when d.oferta_codigo is null or c.ate is null then null else count(*)::int end as vendas,
             case when d.oferta_codigo is null or c.ate is null then null else count(distinct tx.email)::int end as comp,
             case when d.oferta_codigo is null or c.ate is null then null
                  else coalesce(sum(tx.valor_bruto) filter (where tx.moeda = 'BRL'), 0)::numeric(14,2) end as bruta,
             case when d.oferta_codigo is null or c.ate is null then null
                  else coalesce(sum(tx.valor_liquido) filter (where tx.moeda = 'BRL'), 0)::numeric(14,2) end as liq
        from tx where c.ate is not null and tx.aprovado_em <= c.ate
    ) a
   order by c.ordem;
end
$$;

revoke all on function public.dados_atm_resumo(text), public.dados_atm_leads(text), public.dados_atm_serie_diaria(text),
                       public.dados_atm_disparos_canais(text), public.dados_atm_comparecimento(text),
                       public.dados_atm_pos_live(text) from public, anon;
grant execute on function public.dados_atm_resumo(text), public.dados_atm_leads(text), public.dados_atm_serie_diaria(text),
                          public.dados_atm_disparos_canais(text), public.dados_atm_comparecimento(text),
                          public.dados_atm_pos_live(text) to authenticated;

-- 20261008161100: cadastro do ATM 1 da Dra. Elaine (atm-elaine-1-2026-10) no modelo seminario-atm
--
-- STATUS: ESCRITA, NÃO APLICADA. Depende da 20261008161000. TRAVADA DE PROPÓSITO até alguém preencher a SIGLA (v_sigla
-- abaixo): a guarda aborta enquanto ela for nula. A sigla é decisão do Victor (dono do padrão de nomenclatura) e tem de
-- casar com '^[A-Z]{2,10}[0-9]{2,4}$' (check de mkt.projetos). Ela é o que liga os disparos da Mensageria ao projeto
-- ([SIGLA] no nome da campanha). Observado em 08/10: o disparo de e-mail "SEMATMOUT - BYTHEWAY" (sem colchete e sem
-- número, então não casa com o check; não usei).
-- Ensaio: dentro de 20261008161000_ensaio.sql (com sigla fictícia só na transação).
--
-- PARA VOLTAR: rodar o bloco REVERSÃO de 20261008161000_reversao.sql (parte "cadastro da edição"): apaga sessões, grupos
--   e listas da chave, a linha de dados.dashboards e o projeto (só se nenhum disparo, página ou lead apontar para ele).
--
-- O QUE CADASTRA (cada valor com a fonte)
--   mkt.projetos ......... etiqueta atm-elaine-1-2026-10 (briefing e CONTEXT.md do projeto no gp-operacoes); nome
--                          "ATM 1 da Dra. Elaine, outubro de 2026" (título da concepção); linha 'Seminário' (a mesma do
--                          SEMSET26); tipo interno, unidade escritorio (iguais ao SEMSET26); especialista 2 = Elaine
--                          Montenegro (mkt.especialistas); evento 13/10 a 15/10/2026 (live, replay, triplay: concepção).
--   dados.dashboards ..... modelo seminario-atm; conta escritorio (a oferta é a de 3.000 da Sessão de Viabilidade, produto
--                          5238525, conta escritorio em fin.hotmart_transacoes); oferta_codigo NULO (tarefa 86aktf1c3 do
--                          Arthur, "Configurar o checkout da oferta de 3.000", prazo 09/10: código ainda não existe);
--                          lista_ac_leads 615 ("Seminário ATM Outubro 2026 - Leads", criada 07/10, página ak1);
--                          lista_ac (pré-checkout) NULA (lista do gateway Guardiões do Legado não identificada);
--                          vendas_desde 07/10/2026 00:00 de São Paulo (início da reativação, concepção);
--                          ciclo_fecha_em NULO (hora do triplay em aberto na concepção, seção 7).
--   dados.sessoes ........ live 13/10/2026 19:30 de São Paulo (concepção). Replay e triplay: sem hora definida, não
--                          cadastrados.
--   dados.dashboard_grupos  nada: o nome da campanha do SendFlow do ATM não está no banco nem no CONTEXT.md
--                          (whatsapp_grupos: nao-encontrado).
--
-- Para preencher depois (cada um é um update/insert de 1 linha; exemplos em docs/dashboard-atm/MODELO-DE-DADOS.md §4):
--   oferta_codigo, lista_ac, ciclo_fecha_em, campanha do SendFlow, replay e triplay, pico e equipe de cada sessão.

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $c$
declare
  v_sigla   text := 'ZZENSAIO99';   -- <<< PREENCHER (decisão do Victor). Ex. de formato: 'XXXX26'
  v_chave   text := 'atm-elaine-1-2026-10';
  v_proj    bigint;
begin
  if v_sigla is null then
    raise exception '20261008161100: sigla do projeto não definida. Preencher v_sigla com a sigla aprovada pelo Victor.';
  end if;
  if v_sigla !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    raise exception '20261008161100: sigla % fora do padrão de mkt.projetos', v_sigla;
  end if;
  if to_regclass('dados.sessoes') is null then
    raise exception '20261008161100: aplicar antes a 20261008161000';
  end if;
  if exists (select 1 from mkt.projetos where sigla = v_sigla and etiqueta_clickup is distinct from v_chave) then
    raise exception '20261008161100: a sigla % já existe com outra etiqueta', v_sigla;
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave and sigla <> v_sigla) then
    raise exception '20261008161100: % já cadastrada com outra sigla', v_chave;
  end if;
  if (select nome from mkt.especialistas where id = 2) is distinct from 'Elaine Montenegro' then
    raise exception '20261008161100: especialista 2 não é mais Elaine Montenegro';
  end if;

  insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, tipo, unidade, especialista_id,
                            evento_inicio, evento_fim, obs)
  select v_sigla, 'ATM 1 da Dra. Elaine, outubro de 2026', 'Seminário', 2026, v_chave, 'interno', 'escritorio', 2,
         date '2026-10-13', date '2026-10-15', 'Seminário ATM, live 13/10 19h30. Card 86aktf11y. 20261008161100.'
   where not exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave);
  select id into v_proj from mkt.projetos where etiqueta_clickup = v_chave;

  insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, oferta_codigo, lista_ac, lista_ac_leads,
                                vendas_desde, ciclo_fecha_em)
  values (v_chave, 'seminario-atm', v_proj, 'escritorio', null, null, '615',
          timestamptz '2026-10-07 00:00:00-03', null)
  on conflict (chave) do nothing;

  insert into dados.sessoes (chave, tipo, inicio)
  values (v_chave, 'live', timestamptz '2026-10-13 19:30:00-03')
  on conflict (chave, tipo, inicio) do nothing;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '02 objetos', (jsonb_build_object('tabelas', (select count(*) from pg_class where relnamespace = 'dados'::regnamespace and relkind = 'r'), 'rls', (select bool_and(relrowsecurity) from pg_class where relnamespace = 'dados'::regnamespace and relkind = 'r'), 'ddd', (select count(*) from dados.ddd_uf), 'views_invoker', (select count(*) from pg_class where relnamespace = 'dados'::regnamespace and relkind = 'v' and reloptions @> array['security_invoker=true']), 'grants_auth_dados', (select count(*) from information_schema.role_table_grants where table_schema = 'dados' and grantee in ('authenticated','anon')), 'exec_anon', (select count(*) from pg_proc p where p.proname like 'dados_atm%' and has_function_privilege('anon', p.oid, 'execute')), 'exec_auth', (select count(*) from pg_proc p where p.proname like 'dados_atm%' and has_function_privilege('authenticated', p.oid, 'execute')), 'dashboards', (select count(*) from dados.dashboards), 'sessoes', (select count(*) from dados.sessoes)))::text;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '03 vazio resumo', ((select jsonb_build_object('leads', r.leads, 'disparos', r.disparos_qtd, 'enviados', r.disparos_enviados,
   'grupo_fonte', r.grupo_tem_fonte, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct,
   'evasao_pct', r.evasao_pct, 'custo', r.custo_disparo_centavos, 'sem_custo', r.disparos_sem_custo, 'completo', r.custo_completo,
   'cpl', r.cpl_centavos, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'compradores', r.compradores,
   'conv_pc', r.conversao_pre_checkout_pct, 'cac', r.cac_centavos, 'bruta', r.receita_bruta, 'liq', r.receita_liquida,
   'roas', r.roas, 'sigla', r.projeto_sigla) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;
insert into pg_temp._z_out (passo, linha) select '03 vazio leads', ((select jsonb_build_object('linhas', count(*), 'teste', count(*) filter (where teste),
   'com_tel', count(telefone), 'estados', count(estado), 'outros', count(*) filter (where estado = 'Outros'),
   'grupo_true', count(*) filter (where entrou_grupo), 'grupo_null', count(*) filter (where entrou_grupo is null),
   'saiu', count(*) filter (where saiu_grupo),
   'l1', count(*) filter (where lista_origem = 'lista_1'), 'l2', count(*) filter (where lista_origem = 'lista_2'),
   'l12', count(*) filter (where lista_origem = 'lista_1_e_2'), 'fora', count(*) filter (where lista_origem = 'fora_das_listas'),
   'lnull', count(*) filter (where lista_origem is null),
   'marcio', count(*) filter (where seminario_origem = 'marcio'), 'elaine', count(*) filter (where seminario_origem = 'elaine'),
   'aluno', count(*) filter (where eh_aluno), 'pc', count(*) filter (where no_pre_checkout),
   'comprou_t', count(*) filter (where comprou), 'comprou_null', count(*) filter (where comprou is null)) from public.dados_atm_leads('atm-elaine-1-2026-10')))::text;
insert into pg_temp._z_out (passo, linha) select '03 vazio serie', ((select jsonb_build_object('dias', count(*), 'leads', sum(leads), 'entradas', sum(grupo_entradas), 'saidas', sum(grupo_saidas),
   'pc', sum(pre_checkout), 'vendas', sum(vendas), 'bruta', sum(receita_bruta), 'min', min(dia), 'max', max(dia),
   'buraco', count(*) <> (max(dia) - min(dia) + 1)) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10')))::text;
insert into pg_temp._z_out (passo, linha) select '03 vazio canais', ((select jsonb_agg(canal || ':' || disparos || ':' || coalesce(custo_centavos::text, 'null') || ':' || custo_completo) from public.dados_atm_disparos_canais('atm-elaine-1-2026-10')))::text;
insert into pg_temp._z_out (passo, linha) select '03 vazio comparecimento', ((select jsonb_agg(jsonb_build_object('tipo', tipo, 'pico', pico_audiencia, 'equipe', equipe_na_sala, 'leads', total_leads,
   'grupo', total_grupo, 'presentes', presentes, 'p_leads', presentes_leads, 'p_grupo', presentes_grupo,
   'pico_leads', pico_sobre_leads_pct, 'pico_grupo', pico_sobre_grupo_pct, 'pl_pct', presentes_leads_pct, 'pg_pct', presentes_grupo_pct,
   'vendas', vendas, 'conv', conversao_pct, 'conv_g', conversao_grupo_pct, 'conv_pico', conversao_pico_pct) order by inicio)
   from public.dados_atm_comparecimento('atm-elaine-1-2026-10')))::text;
insert into pg_temp._z_out (passo, linha) select '03 vazio pos_live', ((select jsonb_agg(jsonb_build_object('ciclo', ciclo, 'tem_ate', ate is not null, 'vendas', vendas, 'comp', compradores,
   'bruta', receita_bruta, 'conv', conversao_pct, 'conv_g', conversao_grupo_pct, 'conv_pc', conversao_pre_checkout_pct))
   from public.dados_atm_pos_live('atm-elaine-1-2026-10')))::text;
select set_config('request.jwt.claims', '{}', true);

-- dados simulados (só nesta transação)
insert into dados.dashboard_grupos (chave, sendflow_campanha) values ('atm-elaine-1-2026-10', 'ENSAIO ATM CAMPANHA');
create temp table _z_l on commit drop as
  select row_number() over (order by x.primeiro_em, x.email) as n, x.email, controle.fone_key(x.telefone) as fk
    from dados.atm_leads('atm-elaine-1-2026-10') x where not x.teste and x.telefone is not null and controle.fone_key(x.telefone) is not null;
insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, fone_key, tag, resultado, dados)
  select 'sendflow', 'ensaio-e-' || n, 'entrada', timestamptz '2026-10-12 10:00-03' + n * interval '1 hour', fk, 'ENSAIO ATM CAMPANHA', 'sem_pessoa', '{}'::jsonb
    from pg_temp._z_l where n <= 3
  union all
  select 'sendflow', 'ensaio-s-1', 'saida', timestamptz '2026-10-13 09:00-03', fk, 'ENSAIO ATM CAMPANHA', 'sem_pessoa', '{}'::jsonb
    from pg_temp._z_l where n = 1
  union all
  select 'sendflow', 'ensaio-e-x', 'entrada', timestamptz '2026-10-12 11:00-03', '1100000001', 'ENSAIO ATM CAMPANHA', 'sem_pessoa', '{}'::jsonb
  union all
  select 'sendflow', 'ensaio-e-outra', 'entrada', timestamptz '2026-10-12 11:00-03', '1100000002', 'OUTRA CAMPANHA', 'sem_pessoa', '{}'::jsonb;
insert into dados.lista_membros (chave, lista, seminario_origem, email_norm, importacao)
  select 'atm-elaine-1-2026-10', 'lista_1', 'marcio', email, 'ensaio' from pg_temp._z_l where n in (1, 2)
  union all select 'atm-elaine-1-2026-10', 'lista_2', 'elaine', email, 'ensaio' from pg_temp._z_l where n in (2, 3);
update dados.sessoes set pico_audiencia = 10, equipe_na_sala = 2 where chave = 'atm-elaine-1-2026-10' and tipo = 'live';
insert into dados.sessoes (chave, tipo, inicio, pico_audiencia) values ('atm-elaine-1-2026-10', 'replay', timestamptz '2026-09-23 19:30-03', 5);
insert into dados.sessao_presencas (sessao_id, email_norm, fonte)
  select s.id, l.email, 'zoom_relatorio' from dados.sessoes s, pg_temp._z_l l where s.chave = 'atm-elaine-1-2026-10' and s.tipo = 'live' and l.n in (1, 4);
insert into dados.sessao_presencas (sessao_id, email_norm, eh_equipe, fonte)
  select s.id, 'equipe.ficticia@exemplo.invalid', true, 'manual' from dados.sessoes s where s.chave = 'atm-elaine-1-2026-10' and s.tipo = 'live';
update dados.dashboards set oferta_codigo = '7pyzqj0x', vendas_desde = timestamptz '2026-09-01 00:00-03',
       ciclo_fecha_em = timestamptz '2026-09-25 23:59-03' where chave = 'atm-elaine-1-2026-10';
insert into pg_temp._z_out (passo, linha) select '04 conferencia vendas direto', (jsonb_build_object('vendas', (select count(*) from (select * from fin.hotmart_transacoes where conta = 'escritorio') t where t.oferta_codigo = '7pyzqj0x' and t.status in ('APPROVED','COMPLETE') and coalesce(t.recorrencia,1) = 1 and coalesce(t.pedido_em, t.aprovado_em) >= timestamptz '2026-09-01 00:00-03'), 'ate_ciclo', (select count(*) from (select * from fin.hotmart_transacoes where conta = 'escritorio') t where t.oferta_codigo = '7pyzqj0x' and t.status in ('APPROVED','COMPLETE') and coalesce(t.recorrencia,1) = 1 and coalesce(t.pedido_em, t.aprovado_em) >= timestamptz '2026-09-01 00:00-03' and t.aprovado_em <= timestamptz '2026-09-25 23:59-03'), 'leads_com_tel', (select count(*) from pg_temp._z_l)))::text;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '05 simulado resumo', ((select jsonb_build_object('leads', r.leads, 'disparos', r.disparos_qtd, 'enviados', r.disparos_enviados,
   'grupo_fonte', r.grupo_tem_fonte, 'entradas', r.grupo_entradas, 'saidas', r.grupo_saidas, 'grupo_pct', r.grupo_pct,
   'evasao_pct', r.evasao_pct, 'custo', r.custo_disparo_centavos, 'sem_custo', r.disparos_sem_custo, 'completo', r.custo_completo,
   'cpl', r.cpl_centavos, 'pc', r.pre_checkout_pessoas, 'vendas', r.vendas, 'compradores', r.compradores,
   'conv_pc', r.conversao_pre_checkout_pct, 'cac', r.cac_centavos, 'bruta', r.receita_bruta, 'liq', r.receita_liquida,
   'roas', r.roas, 'sigla', r.projeto_sigla) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;
insert into pg_temp._z_out (passo, linha) select '05 simulado leads', ((select jsonb_build_object('linhas', count(*), 'teste', count(*) filter (where teste),
   'com_tel', count(telefone), 'estados', count(estado), 'outros', count(*) filter (where estado = 'Outros'),
   'grupo_true', count(*) filter (where entrou_grupo), 'grupo_null', count(*) filter (where entrou_grupo is null),
   'saiu', count(*) filter (where saiu_grupo),
   'l1', count(*) filter (where lista_origem = 'lista_1'), 'l2', count(*) filter (where lista_origem = 'lista_2'),
   'l12', count(*) filter (where lista_origem = 'lista_1_e_2'), 'fora', count(*) filter (where lista_origem = 'fora_das_listas'),
   'lnull', count(*) filter (where lista_origem is null),
   'marcio', count(*) filter (where seminario_origem = 'marcio'), 'elaine', count(*) filter (where seminario_origem = 'elaine'),
   'aluno', count(*) filter (where eh_aluno), 'pc', count(*) filter (where no_pre_checkout),
   'comprou_t', count(*) filter (where comprou), 'comprou_null', count(*) filter (where comprou is null)) from public.dados_atm_leads('atm-elaine-1-2026-10')))::text;
insert into pg_temp._z_out (passo, linha) select '05 simulado serie', ((select jsonb_build_object('dias', count(*), 'leads', sum(leads), 'entradas', sum(grupo_entradas), 'saidas', sum(grupo_saidas),
   'pc', sum(pre_checkout), 'vendas', sum(vendas), 'bruta', sum(receita_bruta), 'min', min(dia), 'max', max(dia),
   'buraco', count(*) <> (max(dia) - min(dia) + 1)) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10')))::text;
insert into pg_temp._z_out (passo, linha) select '05 simulado canais', ((select jsonb_agg(canal || ':' || disparos || ':' || coalesce(custo_centavos::text, 'null') || ':' || custo_completo) from public.dados_atm_disparos_canais('atm-elaine-1-2026-10')))::text;
insert into pg_temp._z_out (passo, linha) select '05 simulado comparecimento', ((select jsonb_agg(jsonb_build_object('tipo', tipo, 'pico', pico_audiencia, 'equipe', equipe_na_sala, 'leads', total_leads,
   'grupo', total_grupo, 'presentes', presentes, 'p_leads', presentes_leads, 'p_grupo', presentes_grupo,
   'pico_leads', pico_sobre_leads_pct, 'pico_grupo', pico_sobre_grupo_pct, 'pl_pct', presentes_leads_pct, 'pg_pct', presentes_grupo_pct,
   'vendas', vendas, 'conv', conversao_pct, 'conv_g', conversao_grupo_pct, 'conv_pico', conversao_pico_pct) order by inicio)
   from public.dados_atm_comparecimento('atm-elaine-1-2026-10')))::text;
insert into pg_temp._z_out (passo, linha) select '05 simulado pos_live', ((select jsonb_agg(jsonb_build_object('ciclo', ciclo, 'tem_ate', ate is not null, 'vendas', vendas, 'comp', compradores,
   'bruta', receita_bruta, 'conv', conversao_pct, 'conv_g', conversao_grupo_pct, 'conv_pc', conversao_pre_checkout_pct))
   from public.dados_atm_pos_live('atm-elaine-1-2026-10')))::text;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '05 tempo ms', (jsonb_build_object('dados_atm_resumo', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_resumo('atm-elaine-1-2026-10')) c), 'dados_atm_leads', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_leads('atm-elaine-1-2026-10')) c), 'dados_atm_serie_diaria', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_serie_diaria('atm-elaine-1-2026-10')) c), 'dados_atm_disparos_canais', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_disparos_canais('atm-elaine-1-2026-10')) c), 'dados_atm_comparecimento', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_comparecimento('atm-elaine-1-2026-10')) c), 'dados_atm_pos_live', (select round(extract(epoch from (clock_timestamp() - t0)) * 1000) from (select clock_timestamp() as t0) z, lateral (select count(*) from public.dados_atm_pos_live('atm-elaine-1-2026-10')) c)))::text;
select set_config('request.jwt.claims', '{}', true);

-- recusas
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000e0510","role":"authenticated"}', true);
do $rc$ declare r text := ''; begin
  begin perform * from public.dados_atm_resumo('atm-elaine-1-2026-10'); r := r || 'dados_atm_resumo=ok '; exception when others then r := r || 'dados_atm_resumo=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_leads('atm-elaine-1-2026-10'); r := r || 'dados_atm_leads=ok '; exception when others then r := r || 'dados_atm_leads=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_serie_diaria('atm-elaine-1-2026-10'); r := r || 'dados_atm_serie_diaria=ok '; exception when others then r := r || 'dados_atm_serie_diaria=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_disparos_canais('atm-elaine-1-2026-10'); r := r || 'dados_atm_disparos_canais=ok '; exception when others then r := r || 'dados_atm_disparos_canais=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_comparecimento('atm-elaine-1-2026-10'); r := r || 'dados_atm_comparecimento=ok '; exception when others then r := r || 'dados_atm_comparecimento=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_pos_live('atm-elaine-1-2026-10'); r := r || 'dados_atm_pos_live=ok '; exception when others then r := r || 'dados_atm_pos_live=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('06 nao equipe', r);
end $rc$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $rc$ declare r text := ''; begin
  begin perform * from public.dados_atm_resumo('clinica-miami-2026-12'); r := r || 'dados_atm_resumo=ok '; exception when others then r := r || 'dados_atm_resumo=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_leads('clinica-miami-2026-12'); r := r || 'dados_atm_leads=ok '; exception when others then r := r || 'dados_atm_leads=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_serie_diaria('clinica-miami-2026-12'); r := r || 'dados_atm_serie_diaria=ok '; exception when others then r := r || 'dados_atm_serie_diaria=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_disparos_canais('clinica-miami-2026-12'); r := r || 'dados_atm_disparos_canais=ok '; exception when others then r := r || 'dados_atm_disparos_canais=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_comparecimento('clinica-miami-2026-12'); r := r || 'dados_atm_comparecimento=ok '; exception when others then r := r || 'dados_atm_comparecimento=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_pos_live('clinica-miami-2026-12'); r := r || 'dados_atm_pos_live=ok '; exception when others then r := r || 'dados_atm_pos_live=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('07 chave presencial', r);
end $rc$;
do $rc$ declare r text := ''; begin
  begin perform * from public.dados_atm_resumo('nao-existe-2026-01'); r := r || 'dados_atm_resumo=ok '; exception when others then r := r || 'dados_atm_resumo=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_leads('nao-existe-2026-01'); r := r || 'dados_atm_leads=ok '; exception when others then r := r || 'dados_atm_leads=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_serie_diaria('nao-existe-2026-01'); r := r || 'dados_atm_serie_diaria=ok '; exception when others then r := r || 'dados_atm_serie_diaria=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_disparos_canais('nao-existe-2026-01'); r := r || 'dados_atm_disparos_canais=ok '; exception when others then r := r || 'dados_atm_disparos_canais=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_comparecimento('nao-existe-2026-01'); r := r || 'dados_atm_comparecimento=ok '; exception when others then r := r || 'dados_atm_comparecimento=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_pos_live('nao-existe-2026-01'); r := r || 'dados_atm_pos_live=ok '; exception when others then r := r || 'dados_atm_pos_live=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('08 chave inexistente', r);
end $rc$;
select set_config('request.jwt.claims', '{}', true);

set local role anon;
do $rc$ declare r text := ''; begin
  begin perform * from public.dados_atm_resumo('atm-elaine-1-2026-10'); r := r || 'dados_atm_resumo=ok '; exception when others then r := r || 'dados_atm_resumo=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_leads('atm-elaine-1-2026-10'); r := r || 'dados_atm_leads=ok '; exception when others then r := r || 'dados_atm_leads=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_serie_diaria('atm-elaine-1-2026-10'); r := r || 'dados_atm_serie_diaria=ok '; exception when others then r := r || 'dados_atm_serie_diaria=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_disparos_canais('atm-elaine-1-2026-10'); r := r || 'dados_atm_disparos_canais=ok '; exception when others then r := r || 'dados_atm_disparos_canais=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_comparecimento('atm-elaine-1-2026-10'); r := r || 'dados_atm_comparecimento=ok '; exception when others then r := r || 'dados_atm_comparecimento=' || sqlstate || ' '; end;
  begin perform * from public.dados_atm_pos_live('atm-elaine-1-2026-10'); r := r || 'dados_atm_pos_live=ok '; exception when others then r := r || 'dados_atm_pos_live=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('09 anon', r);
end $rc$;

reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '10 presencial depois', (jsonb_build_object(
  'resumo', (select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.email), '')) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'vendas', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.transacao), '')) from public.dados_presencial_vendas('clinica-miami-2026-12') x),
  'serie', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.dia), '')) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') x),
  'disparos', (select count(*) from public.dados_presencial_disparos('clinica-miami-2026-12'))))::text;
select set_config('request.jwt.claims', '{}', true);

-- reversão (tira também os dados simulados da chave)
delete from crm.evento_jornada where fonte_evento_id like 'ensaio-%';
-- Reversão de 20261008161000 (modelo seminario-atm) e de 20261008161100 (cadastro do ATM 1 da Dra. Elaine).
--
-- STATUS: ESCRITA, NÃO APLICADA (nenhuma das duas migrations foi aplicada). Rodada dentro do ensaio
-- 20261008161000_ensaio.sql: volta dados.dashboards às colunas e checks de antes e as funções do presencial seguem iguais.
--
-- Ordem: primeiro o cadastro da edição (se existir), depois o modelo. Aborta se houver outro dashboard 'seminario-atm'
-- cadastrado (cadastro de outra edição tem de sair antes, com o mesmo bloco trocando a chave).
-- O gatilho public.tg_carimbar_atualizado_em() NÃO é apagado se outra tabela fora destas o usar.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 1. Cadastro da edição atm-elaine-1-2026-10
do $c$
declare v_chave text := 'atm-elaine-1-2026-10'; v_proj bigint;
begin
  if to_regclass('dados.sessoes') is null then
    return;
  end if;
  select projeto_id into v_proj from dados.dashboards where chave = v_chave;
  delete from dados.sessao_presencas where sessao_id in (select id from dados.sessoes where chave = v_chave);
  delete from dados.sessoes where chave = v_chave;
  delete from dados.dashboard_grupos where chave = v_chave;
  delete from dados.lista_membros where chave = v_chave;
  delete from dados.dashboards where chave = v_chave;
  if v_proj is not null
     and not exists (select 1 from mkt_mensageria.disparos where projeto_id = v_proj)
     and not exists (select 1 from pessoas.eventos where projeto_id = v_proj)
     and not exists (select 1 from pessoas.origens where projeto_id = v_proj)
     and not exists (select 1 from dados.dashboards where projeto_id = v_proj) then
    delete from mkt.projetos where id = v_proj and etiqueta_clickup = v_chave;
  elsif v_proj is not null then
    raise notice 'reversão: projeto % mantido em mkt.projetos (há disparo, evento ou origem apontando para ele)', v_proj;
  end if;
end
$c$;

-- 2. Modelo seminario-atm
do $g$
begin
  if exists (select 1 from dados.dashboards where modelo = 'seminario-atm') then
    raise exception 'reversão: ainda há dashboard seminario-atm cadastrado. Tirar o cadastro antes.';
  end if;
  if exists (select 1 from dados.dashboards where oferta_codigo is null) then
    raise exception 'reversão: há dashboard sem oferta; o NOT NULL de oferta_codigo não volta.';
  end if;
end
$g$;

drop function if exists public.dados_atm_resumo(text), public.dados_atm_leads(text), public.dados_atm_serie_diaria(text),
                        public.dados_atm_disparos_canais(text), public.dados_atm_comparecimento(text),
                        public.dados_atm_pos_live(text);
drop function if exists dados.atm_leads(text), dados.atm_vendas(text), dados.atm_cadastro(text),
                        dados.leads_todos(text, bigint, text);
drop view if exists dados.v_grupo_pessoas;
drop view if exists dados.v_grupo_eventos;
drop table if exists dados.sessao_presencas;
drop table if exists dados.sessoes;
drop table if exists dados.lista_membros;
drop table if exists dados.dashboard_grupos;
drop table if exists dados.ddd_uf;

alter table dados.dashboards drop column if exists ciclo_fecha_em;
alter table dados.dashboards drop column if exists vendas_desde;
alter table dados.dashboards drop column if exists lista_ac_leads;
alter table dados.dashboards alter column oferta_codigo set not null;
comment on column dados.dashboards.oferta_codigo is null;
alter table dados.dashboards drop constraint if exists dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check check (modelo = 'presencial-base');

do $t$
begin
  if to_regprocedure('public.tg_carimbar_atualizado_em()') is not null
     and not exists (select 1 from pg_trigger where tgfoid = to_regprocedure('public.tg_carimbar_atualizado_em()')) then
    drop function public.tg_carimbar_atualizado_em();
  end if;
end
$t$;

insert into pg_temp._z_out (passo, linha) select '11 depois da reversao', (jsonb_build_object('cols', (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'dados' and table_name = 'dashboards'), 'oferta_notnull', (select attnotnull from pg_attribute where attrelid = 'dados.dashboards'::regclass and attname = 'oferta_codigo'), 'check_modelo', (select pg_get_constraintdef(oid) from pg_constraint where conname = 'dashboards_modelo_check'), 'fns_atm', (select count(*) from pg_proc where proname like 'dados_atm%' or (pronamespace = 'dados'::regnamespace and proname in ('atm_leads','atm_vendas','atm_cadastro','leads_todos'))), 'tabelas', (select count(*) from pg_class where relnamespace = 'dados'::regnamespace and relkind in ('r','v')), 'projeto', (select count(*) from mkt.projetos where etiqueta_clickup = 'atm-elaine-1-2026-10'), 'gatilho', to_regprocedure('public.tg_carimbar_atualizado_em()') is not null))::text;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '12 presencial depois da reversao', (jsonb_build_object(
  'resumo', (select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'leads', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.email), '')) from public.dados_presencial_leads('clinica-miami-2026-12') x),
  'vendas', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.transacao), '')) from public.dados_presencial_vendas('clinica-miami-2026-12') x),
  'serie', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.dia), '')) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') x),
  'disparos', (select count(*) from public.dados_presencial_disparos('clinica-miami-2026-12'))))::text;
select set_config('request.jwt.claims', '{}', true);

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
