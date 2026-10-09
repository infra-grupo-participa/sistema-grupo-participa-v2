-- Ensaio de 20261009200000 (histórico por edição). Transação desfeita: nada persiste.
-- Saída só com contagens, números agregados e sqlstate: nenhum dado pessoal. Montado a partir da migration, do passo de
-- registro do .explain.md (seção 4) e da reversão. Rodar: aplica_sql.py ensaio 20261009200000_ensaio.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '240s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon, service_role; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon, service_role;

insert into pg_temp._z_out (passo, linha) select '01 antes', (jsonb_build_object(
  'tabela', to_regclass('dados.edicoes_historico') is not null,
  'rpc', to_regprocedure('public.dados_historico_edicoes(text)') is not null))::text;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '01 antes resumo ATM OUT md5',
  ((select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;
select set_config('request.jwt.claims', '{}', true);

-- passada 1
-- 20261009200000: histórico por edição (genérico, primeiro uso: aba "Histórico" do dashboard do Seminário ATM)
--
-- STATUS: ver 20261009200000.explain.md (situação, ensaio, contrato, como registrar a próxima edição).
-- Ensaio: 20261009200000_ensaio.sql. Reversão: 20261009200000_reversao.sql. Contrato: docs/dashboard-atm/MODELO-DE-DADOS.md.
--
-- POR QUE (pedido do Victor de 09/10/2026, .maestri/entregas/pedido-atm-historico-construcao.md, card 17tya50ftxn)
--   As edições antigas do ATM (JUL/26 e SET/26) não estão no banco: os números vivem nos debriefs e nas planilhas.
--   A aba "Histórico" precisa de uma linha por edição, com a fonte de cada número. A tabela é genérica (família de
--   evento + chave da edição), para servir a outros eventos depois. Números confirmados pelo Victor em 09/10.
--
-- O QUE FAZ
--   a. dados.edicoes_historico (RLS ligada, sem policy, sem grant): uma linha por edição. Métricas nulas = sem dado
--      (ex.: pico do dia 3 do ATM JUL/26, que não teve dia 3). Dinheiro em centavos (bigint).
--      fontes: jsonb {métrica: texto da fonte}; provisorio: nomes das métricas ainda não confirmadas (vazio = todas
--      confirmadas). Só se lê pela RPC.
--   b. Carga dos ATMs JUL/26 e SET/26 (idempotente: on conflict (chave) do update, só grava o que mudou).
--   c. public.dados_historico_edicoes(p_familia): todas as colunas, ordenadas por ordem. Gate igual ao das
--      dados_atm_* (o 1º passo de dados.cadastro, copiado de pg_get_functiondef em 09/10/2026: equipe ou
--      service_role; aqui não há chave de dashboard, então não há o passo do dashboard ativo). Família inexistente ou
--      nula = 0 linhas. EXECUTE só para authenticated.
--   A próxima edição (atm-elaine-1-2026-10) entra pelo passo SQL documentado no .explain.md (seção 4), depois do ciclo
--   fechado. Esta migration NÃO cria a linha da OUT/26.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha por edição (2 hoje; dezenas em anos).
--   índice: PK (chave) e único (familia, ordem), que cobre o filtro e a ordem da RPC.
--   frequência: leitura a cada abertura da aba Histórico; escrita 1 vez por edição fechada.
--   repetição: nenhuma; a RPC é um select de poucas linhas.
--   reversão: 20261009200000_reversao.sql (apaga a RPC e a tabela; a carga está neste arquivo).
--
-- IDEMPOTENTE: if not exists / create or replace / drop ... if exists / on conflict.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v text;
begin
  foreach v in array array['public.gp_eh_equipe()', 'public.tg_carimbar_atualizado_em()', 'auth.role()'] loop
    if to_regprocedure(v) is null then
      raise exception 'premissa: falta %', v;
    end if;
  end loop;
  if to_regnamespace('dados') is null then
    raise exception 'premissa: falta o schema dados';
  end if;
end
$g$;

-- a. Tabela
create table if not exists dados.edicoes_historico (
  chave                     text primary key,
  familia                   text not null,
  rotulo                    text not null,
  ordem                     integer not null,
  data_inicio               date,
  data_fim                  date,
  leads                     integer,
  invest_trafego_centavos   bigint,
  invest_disparo_centavos   bigint,
  grupo                     integer,
  pico_d1                   integer,
  pico_d2                   integer,
  pico_d3                   integer,
  vendas                    integer,
  receita_liquida_centavos  bigint,
  pre_checkout              integer,
  fontes                    jsonb not null default '{}'::jsonb,
  provisorio                text[] not null default '{}',
  criado_em                 timestamptz not null default now(),
  atualizado_em             timestamptz not null default now(),
  constraint edicoes_historico_chave_check check (chave ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint edicoes_historico_familia_check check (familia ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint edicoes_historico_rotulo_check check (btrim(rotulo) <> ''),
  constraint edicoes_historico_ordem_check check (ordem > 0),
  constraint edicoes_historico_datas_check check (data_inicio is null or data_fim is null or data_inicio <= data_fim),
  constraint edicoes_historico_nao_negativo_check check (
        coalesce(leads, 0) >= 0 and coalesce(invest_trafego_centavos, 0) >= 0
    and coalesce(invest_disparo_centavos, 0) >= 0 and coalesce(grupo, 0) >= 0
    and coalesce(pico_d1, 0) >= 0 and coalesce(pico_d2, 0) >= 0 and coalesce(pico_d3, 0) >= 0
    and coalesce(vendas, 0) >= 0 and coalesce(receita_liquida_centavos, 0) >= 0 and coalesce(pre_checkout, 0) >= 0),
  constraint edicoes_historico_fontes_check check (jsonb_typeof(fontes) = 'object'),
  constraint edicoes_historico_provisorio_check check (provisorio <@ array['leads', 'invest_trafego', 'invest_disparo',
    'grupo', 'pico_d1', 'pico_d2', 'pico_d3', 'vendas', 'receita_liquida', 'pre_checkout']::text[])
);
create unique index if not exists edicoes_historico_familia_ordem_uk on dados.edicoes_historico (familia, ordem);

comment on table dados.edicoes_historico is
  'Histórico por edição de evento (uma linha por edição), com a fonte de cada número. Genérica por família (ex.: seminario-atm). Leitura só por public.dados_historico_edicoes. 20261009200000.';
comment on column dados.edicoes_historico.chave is 'Chave da edição, nome-curto-aaaa-mm (ex.: atm-1-2026-07).';
comment on column dados.edicoes_historico.familia is 'Família de evento que a tela pede (ex.: seminario-atm).';
comment on column dados.edicoes_historico.rotulo is 'Rótulo da coluna na tela (ex.: ATM JUL/26).';
comment on column dados.edicoes_historico.ordem is 'Ordem da edição dentro da família (1 = mais antiga). Única por família.';
comment on column dados.edicoes_historico.data_inicio is 'Primeiro dia da edição. Nulo = não registrado.';
comment on column dados.edicoes_historico.data_fim is 'Último dia da edição. Nulo = não registrado.';
comment on column dados.edicoes_historico.invest_trafego_centavos is 'Investimento em tráfego pago, em centavos. Nulo = sem dado.';
comment on column dados.edicoes_historico.invest_disparo_centavos is 'Custo de disparo (mensageria), em centavos. Nulo = sem dado.';
comment on column dados.edicoes_historico.grupo is 'Ingressos no grupo de WhatsApp.';
comment on column dados.edicoes_historico.pico_d1 is 'Pico ao vivo do dia 1, sem a equipe. Nulo = sem dado ou sem dia.';
comment on column dados.edicoes_historico.pico_d2 is 'Pico ao vivo do dia 2 (replay/repeteco), sem a equipe. Nulo = sem dado ou sem dia.';
comment on column dados.edicoes_historico.pico_d3 is 'Pico ao vivo do dia 3 (triplay), sem a equipe. Nulo = sem dado ou sem dia.';
comment on column dados.edicoes_historico.receita_liquida_centavos is 'Receita líquida das vendas, em centavos.';
comment on column dados.edicoes_historico.pre_checkout is 'Pessoas no pré-checkout.';
comment on column dados.edicoes_historico.fontes is
  'jsonb {métrica: texto da fonte}. Chaves: leads, invest_trafego, invest_disparo, grupo, pico_d1, pico_d2, pico_d3, vendas, receita_liquida, pre_checkout. Sem dado pessoal.';
comment on column dados.edicoes_historico.provisorio is 'Métricas ainda não confirmadas (mesmos nomes das chaves de fontes). Vazio = todas confirmadas.';

alter table dados.edicoes_historico enable row level security;
revoke all on dados.edicoes_historico from public, anon, authenticated;
drop trigger if exists edicoes_historico_carimbar on dados.edicoes_historico;
create trigger edicoes_historico_carimbar before update on dados.edicoes_historico
  for each row execute function public.tg_carimbar_atualizado_em();

-- b. Carga dos ATMs JUL/26 e SET/26 (valores confirmados pelo Victor em 09/10/2026; vendas = só Sessão de Viabilidade,
--    sem Croqui; disparo de JUL = soma da planilha de mensageria, não o valor do DRE)
insert into dados.edicoes_historico as h
  (chave, familia, rotulo, ordem, data_inicio, data_fim, leads, invest_trafego_centavos, invest_disparo_centavos, grupo,
   pico_d1, pico_d2, pico_d3, vendas, receita_liquida_centavos, pre_checkout, fontes, provisorio)
values
  ('atm-1-2026-07', 'seminario-atm', 'ATM JUL/26', 1, null, null,
   424, 0, 203993, 345, 74, 21, null, 7, 991907, 26,
   jsonb_build_object(
     'leads',           'debrief oficial ATM JUL/26',
     'invest_trafego',  'sem tráfego na fonte (debrief JUL)',
     'invest_disparo',  'planilha SEM ATM - JUL26 - MENSAGERIA, soma linha a linha (API 1.658,33 + Ligação 381,60)',
     'grupo',           'debrief oficial ATM JUL/26',
     'pico_d1',         'aba Comparecimento da planilha de vendas do ATM JUL/26, pico menos equipe',
     'pico_d2',         'aba Comparecimento - Repeteco 17-07, pico menos equipe',
     'pico_d3',         'julho não teve dia 3 (debrief SET)',
     'vendas',          'aba Vendas Aprovadas (Sessão de Viabilidade, sem Croqui), conferido na Hotmart',
     'receita_liquida', 'debrief oficial ATM JUL/26 (7 x R$ 1.417,01)',
     'pre_checkout',    'aba Abertura de Checkout, e-mails únicos'),
   '{}'),
  ('atm-2-2026-09', 'seminario-atm', 'ATM SET/26', 2, null, null,
   911, 0, 211948, 743, 127, 62, 40, 9, 1275291, 33,
   jsonb_build_object(
     'leads',           'debrief oficial ATM SET/26 (apurado 14/09)',
     'invest_trafego',  'sem tráfego pago (debrief SET)',
     'invest_disparo',  'planilha Custos do Seminário ATM - SET/26, aba Custos de mensageria, B44',
     'grupo',           'debrief oficial ATM SET/26',
     'pico_d1',         'aba Comparecimento da planilha de vendas do ATM SET/26, pico menos equipe',
     'pico_d2',         'aba Comparecimento repeteco, pico menos equipe',
     'pico_d3',         'aba Comparecimento triplay, pico menos equipe',
     'vendas',          'aba Vendas Aprovadas (Sessão de Viabilidade), conferido na Hotmart',
     'receita_liquida', 'debrief oficial ATM SET/26',
     'pre_checkout',    'debrief oficial ATM SET/26'),
   '{}')
on conflict (chave) do update
   set familia = excluded.familia, rotulo = excluded.rotulo, ordem = excluded.ordem,
       data_inicio = excluded.data_inicio, data_fim = excluded.data_fim, leads = excluded.leads,
       invest_trafego_centavos = excluded.invest_trafego_centavos, invest_disparo_centavos = excluded.invest_disparo_centavos,
       grupo = excluded.grupo, pico_d1 = excluded.pico_d1, pico_d2 = excluded.pico_d2, pico_d3 = excluded.pico_d3,
       vendas = excluded.vendas, receita_liquida_centavos = excluded.receita_liquida_centavos,
       pre_checkout = excluded.pre_checkout, fontes = excluded.fontes, provisorio = excluded.provisorio
 where (h.familia, h.rotulo, h.ordem, h.data_inicio, h.data_fim, h.leads, h.invest_trafego_centavos,
        h.invest_disparo_centavos, h.grupo, h.pico_d1, h.pico_d2, h.pico_d3, h.vendas, h.receita_liquida_centavos,
        h.pre_checkout, h.fontes, h.provisorio)
       is distinct from
       (excluded.familia, excluded.rotulo, excluded.ordem, excluded.data_inicio, excluded.data_fim, excluded.leads,
        excluded.invest_trafego_centavos, excluded.invest_disparo_centavos, excluded.grupo, excluded.pico_d1,
        excluded.pico_d2, excluded.pico_d3, excluded.vendas, excluded.receita_liquida_centavos, excluded.pre_checkout,
        excluded.fontes, excluded.provisorio);

-- c. RPC
create or replace function public.dados_historico_edicoes(p_familia text)
returns table(chave text, familia text, rotulo text, ordem integer, data_inicio date, data_fim date, leads integer,
              invest_trafego_centavos bigint, invest_disparo_centavos bigint, grupo integer, pico_d1 integer,
              pico_d2 integer, pico_d3 integer, vendas integer, receita_liquida_centavos bigint, pre_checkout integer,
              fontes jsonb, provisorio text[], criado_em timestamp with time zone, atualizado_em timestamp with time zone)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_servico boolean := coalesce((select auth.role()), '') = 'service_role';
begin
  -- 20261009200000. Gate = 1º passo de dados.cadastro (o das dados_atm_*), copiado do banco em 09/10/2026.
  -- service_role não tem EXECUTE nesta função; o ramo fica para o gate continuar idêntico ao de dados.cadastro.
  if not v_servico and not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  return query
  select h.chave, h.familia, h.rotulo, h.ordem, h.data_inicio, h.data_fim, h.leads, h.invest_trafego_centavos,
         h.invest_disparo_centavos, h.grupo, h.pico_d1, h.pico_d2, h.pico_d3, h.vendas, h.receita_liquida_centavos,
         h.pre_checkout, h.fontes, h.provisorio, h.criado_em, h.atualizado_em
    from dados.edicoes_historico h
   where h.familia = p_familia
   order by h.ordem;
end
$$;
comment on function public.dados_historico_edicoes(text) is
  'Histórico por edição da família (ex.: seminario-atm), ordenado por ordem. Só equipe (gate de dados.cadastro). Família inexistente = 0 linhas. 20261009200000.';

revoke all on function public.dados_historico_edicoes(text) from public, anon, service_role;
grant execute on function public.dados_historico_edicoes(text) to authenticated;

-- pós-condição: authenticated executa, anon e service_role não; ninguém lê a tabela direto
do $p$
begin
  if not has_function_privilege('authenticated', 'public.dados_historico_edicoes(text)', 'execute')
     or has_function_privilege('anon', 'public.dados_historico_edicoes(text)', 'execute')
     or has_function_privilege('service_role', 'public.dados_historico_edicoes(text)', 'execute') then
    raise exception 'pós-condição: grant errado em public.dados_historico_edicoes(text)';
  end if;
  if has_table_privilege('authenticated', 'dados.edicoes_historico', 'select')
     or has_table_privilege('anon', 'dados.edicoes_historico', 'select') then
    raise exception 'pós-condição: anon/authenticated lê dados.edicoes_historico';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'dados.edicoes_historico'::regclass) then
    raise exception 'pós-condição: RLS desligada em dados.edicoes_historico';
  end if;
end
$p$;

notify pgrst, 'reload schema';

create temp table _z_ctid on commit drop as select chave, ctid::text as c from dados.edicoes_historico;

-- passada 2 (idempotência: nenhuma linha regravada)
-- 20261009200000: histórico por edição (genérico, primeiro uso: aba "Histórico" do dashboard do Seminário ATM)
--
-- STATUS: ver 20261009200000.explain.md (situação, ensaio, contrato, como registrar a próxima edição).
-- Ensaio: 20261009200000_ensaio.sql. Reversão: 20261009200000_reversao.sql. Contrato: docs/dashboard-atm/MODELO-DE-DADOS.md.
--
-- POR QUE (pedido do Victor de 09/10/2026, .maestri/entregas/pedido-atm-historico-construcao.md, card 17tya50ftxn)
--   As edições antigas do ATM (JUL/26 e SET/26) não estão no banco: os números vivem nos debriefs e nas planilhas.
--   A aba "Histórico" precisa de uma linha por edição, com a fonte de cada número. A tabela é genérica (família de
--   evento + chave da edição), para servir a outros eventos depois. Números confirmados pelo Victor em 09/10.
--
-- O QUE FAZ
--   a. dados.edicoes_historico (RLS ligada, sem policy, sem grant): uma linha por edição. Métricas nulas = sem dado
--      (ex.: pico do dia 3 do ATM JUL/26, que não teve dia 3). Dinheiro em centavos (bigint).
--      fontes: jsonb {métrica: texto da fonte}; provisorio: nomes das métricas ainda não confirmadas (vazio = todas
--      confirmadas). Só se lê pela RPC.
--   b. Carga dos ATMs JUL/26 e SET/26 (idempotente: on conflict (chave) do update, só grava o que mudou).
--   c. public.dados_historico_edicoes(p_familia): todas as colunas, ordenadas por ordem. Gate igual ao das
--      dados_atm_* (o 1º passo de dados.cadastro, copiado de pg_get_functiondef em 09/10/2026: equipe ou
--      service_role; aqui não há chave de dashboard, então não há o passo do dashboard ativo). Família inexistente ou
--      nula = 0 linhas. EXECUTE só para authenticated.
--   A próxima edição (atm-elaine-1-2026-10) entra pelo passo SQL documentado no .explain.md (seção 4), depois do ciclo
--   fechado. Esta migration NÃO cria a linha da OUT/26.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha por edição (2 hoje; dezenas em anos).
--   índice: PK (chave) e único (familia, ordem), que cobre o filtro e a ordem da RPC.
--   frequência: leitura a cada abertura da aba Histórico; escrita 1 vez por edição fechada.
--   repetição: nenhuma; a RPC é um select de poucas linhas.
--   reversão: 20261009200000_reversao.sql (apaga a RPC e a tabela; a carga está neste arquivo).
--
-- IDEMPOTENTE: if not exists / create or replace / drop ... if exists / on conflict.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v text;
begin
  foreach v in array array['public.gp_eh_equipe()', 'public.tg_carimbar_atualizado_em()', 'auth.role()'] loop
    if to_regprocedure(v) is null then
      raise exception 'premissa: falta %', v;
    end if;
  end loop;
  if to_regnamespace('dados') is null then
    raise exception 'premissa: falta o schema dados';
  end if;
end
$g$;

-- a. Tabela
create table if not exists dados.edicoes_historico (
  chave                     text primary key,
  familia                   text not null,
  rotulo                    text not null,
  ordem                     integer not null,
  data_inicio               date,
  data_fim                  date,
  leads                     integer,
  invest_trafego_centavos   bigint,
  invest_disparo_centavos   bigint,
  grupo                     integer,
  pico_d1                   integer,
  pico_d2                   integer,
  pico_d3                   integer,
  vendas                    integer,
  receita_liquida_centavos  bigint,
  pre_checkout              integer,
  fontes                    jsonb not null default '{}'::jsonb,
  provisorio                text[] not null default '{}',
  criado_em                 timestamptz not null default now(),
  atualizado_em             timestamptz not null default now(),
  constraint edicoes_historico_chave_check check (chave ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint edicoes_historico_familia_check check (familia ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint edicoes_historico_rotulo_check check (btrim(rotulo) <> ''),
  constraint edicoes_historico_ordem_check check (ordem > 0),
  constraint edicoes_historico_datas_check check (data_inicio is null or data_fim is null or data_inicio <= data_fim),
  constraint edicoes_historico_nao_negativo_check check (
        coalesce(leads, 0) >= 0 and coalesce(invest_trafego_centavos, 0) >= 0
    and coalesce(invest_disparo_centavos, 0) >= 0 and coalesce(grupo, 0) >= 0
    and coalesce(pico_d1, 0) >= 0 and coalesce(pico_d2, 0) >= 0 and coalesce(pico_d3, 0) >= 0
    and coalesce(vendas, 0) >= 0 and coalesce(receita_liquida_centavos, 0) >= 0 and coalesce(pre_checkout, 0) >= 0),
  constraint edicoes_historico_fontes_check check (jsonb_typeof(fontes) = 'object'),
  constraint edicoes_historico_provisorio_check check (provisorio <@ array['leads', 'invest_trafego', 'invest_disparo',
    'grupo', 'pico_d1', 'pico_d2', 'pico_d3', 'vendas', 'receita_liquida', 'pre_checkout']::text[])
);
create unique index if not exists edicoes_historico_familia_ordem_uk on dados.edicoes_historico (familia, ordem);

comment on table dados.edicoes_historico is
  'Histórico por edição de evento (uma linha por edição), com a fonte de cada número. Genérica por família (ex.: seminario-atm). Leitura só por public.dados_historico_edicoes. 20261009200000.';
comment on column dados.edicoes_historico.chave is 'Chave da edição, nome-curto-aaaa-mm (ex.: atm-1-2026-07).';
comment on column dados.edicoes_historico.familia is 'Família de evento que a tela pede (ex.: seminario-atm).';
comment on column dados.edicoes_historico.rotulo is 'Rótulo da coluna na tela (ex.: ATM JUL/26).';
comment on column dados.edicoes_historico.ordem is 'Ordem da edição dentro da família (1 = mais antiga). Única por família.';
comment on column dados.edicoes_historico.data_inicio is 'Primeiro dia da edição. Nulo = não registrado.';
comment on column dados.edicoes_historico.data_fim is 'Último dia da edição. Nulo = não registrado.';
comment on column dados.edicoes_historico.invest_trafego_centavos is 'Investimento em tráfego pago, em centavos. Nulo = sem dado.';
comment on column dados.edicoes_historico.invest_disparo_centavos is 'Custo de disparo (mensageria), em centavos. Nulo = sem dado.';
comment on column dados.edicoes_historico.grupo is 'Ingressos no grupo de WhatsApp.';
comment on column dados.edicoes_historico.pico_d1 is 'Pico ao vivo do dia 1, sem a equipe. Nulo = sem dado ou sem dia.';
comment on column dados.edicoes_historico.pico_d2 is 'Pico ao vivo do dia 2 (replay/repeteco), sem a equipe. Nulo = sem dado ou sem dia.';
comment on column dados.edicoes_historico.pico_d3 is 'Pico ao vivo do dia 3 (triplay), sem a equipe. Nulo = sem dado ou sem dia.';
comment on column dados.edicoes_historico.receita_liquida_centavos is 'Receita líquida das vendas, em centavos.';
comment on column dados.edicoes_historico.pre_checkout is 'Pessoas no pré-checkout.';
comment on column dados.edicoes_historico.fontes is
  'jsonb {métrica: texto da fonte}. Chaves: leads, invest_trafego, invest_disparo, grupo, pico_d1, pico_d2, pico_d3, vendas, receita_liquida, pre_checkout. Sem dado pessoal.';
comment on column dados.edicoes_historico.provisorio is 'Métricas ainda não confirmadas (mesmos nomes das chaves de fontes). Vazio = todas confirmadas.';

alter table dados.edicoes_historico enable row level security;
revoke all on dados.edicoes_historico from public, anon, authenticated;
drop trigger if exists edicoes_historico_carimbar on dados.edicoes_historico;
create trigger edicoes_historico_carimbar before update on dados.edicoes_historico
  for each row execute function public.tg_carimbar_atualizado_em();

-- b. Carga dos ATMs JUL/26 e SET/26 (valores confirmados pelo Victor em 09/10/2026; vendas = só Sessão de Viabilidade,
--    sem Croqui; disparo de JUL = soma da planilha de mensageria, não o valor do DRE)
insert into dados.edicoes_historico as h
  (chave, familia, rotulo, ordem, data_inicio, data_fim, leads, invest_trafego_centavos, invest_disparo_centavos, grupo,
   pico_d1, pico_d2, pico_d3, vendas, receita_liquida_centavos, pre_checkout, fontes, provisorio)
values
  ('atm-1-2026-07', 'seminario-atm', 'ATM JUL/26', 1, null, null,
   424, 0, 203993, 345, 74, 21, null, 7, 991907, 26,
   jsonb_build_object(
     'leads',           'debrief oficial ATM JUL/26',
     'invest_trafego',  'sem tráfego na fonte (debrief JUL)',
     'invest_disparo',  'planilha SEM ATM - JUL26 - MENSAGERIA, soma linha a linha (API 1.658,33 + Ligação 381,60)',
     'grupo',           'debrief oficial ATM JUL/26',
     'pico_d1',         'aba Comparecimento da planilha de vendas do ATM JUL/26, pico menos equipe',
     'pico_d2',         'aba Comparecimento - Repeteco 17-07, pico menos equipe',
     'pico_d3',         'julho não teve dia 3 (debrief SET)',
     'vendas',          'aba Vendas Aprovadas (Sessão de Viabilidade, sem Croqui), conferido na Hotmart',
     'receita_liquida', 'debrief oficial ATM JUL/26 (7 x R$ 1.417,01)',
     'pre_checkout',    'aba Abertura de Checkout, e-mails únicos'),
   '{}'),
  ('atm-2-2026-09', 'seminario-atm', 'ATM SET/26', 2, null, null,
   911, 0, 211948, 743, 127, 62, 40, 9, 1275291, 33,
   jsonb_build_object(
     'leads',           'debrief oficial ATM SET/26 (apurado 14/09)',
     'invest_trafego',  'sem tráfego pago (debrief SET)',
     'invest_disparo',  'planilha Custos do Seminário ATM - SET/26, aba Custos de mensageria, B44',
     'grupo',           'debrief oficial ATM SET/26',
     'pico_d1',         'aba Comparecimento da planilha de vendas do ATM SET/26, pico menos equipe',
     'pico_d2',         'aba Comparecimento repeteco, pico menos equipe',
     'pico_d3',         'aba Comparecimento triplay, pico menos equipe',
     'vendas',          'aba Vendas Aprovadas (Sessão de Viabilidade), conferido na Hotmart',
     'receita_liquida', 'debrief oficial ATM SET/26',
     'pre_checkout',    'debrief oficial ATM SET/26'),
   '{}')
on conflict (chave) do update
   set familia = excluded.familia, rotulo = excluded.rotulo, ordem = excluded.ordem,
       data_inicio = excluded.data_inicio, data_fim = excluded.data_fim, leads = excluded.leads,
       invest_trafego_centavos = excluded.invest_trafego_centavos, invest_disparo_centavos = excluded.invest_disparo_centavos,
       grupo = excluded.grupo, pico_d1 = excluded.pico_d1, pico_d2 = excluded.pico_d2, pico_d3 = excluded.pico_d3,
       vendas = excluded.vendas, receita_liquida_centavos = excluded.receita_liquida_centavos,
       pre_checkout = excluded.pre_checkout, fontes = excluded.fontes, provisorio = excluded.provisorio
 where (h.familia, h.rotulo, h.ordem, h.data_inicio, h.data_fim, h.leads, h.invest_trafego_centavos,
        h.invest_disparo_centavos, h.grupo, h.pico_d1, h.pico_d2, h.pico_d3, h.vendas, h.receita_liquida_centavos,
        h.pre_checkout, h.fontes, h.provisorio)
       is distinct from
       (excluded.familia, excluded.rotulo, excluded.ordem, excluded.data_inicio, excluded.data_fim, excluded.leads,
        excluded.invest_trafego_centavos, excluded.invest_disparo_centavos, excluded.grupo, excluded.pico_d1,
        excluded.pico_d2, excluded.pico_d3, excluded.vendas, excluded.receita_liquida_centavos, excluded.pre_checkout,
        excluded.fontes, excluded.provisorio);

-- c. RPC
create or replace function public.dados_historico_edicoes(p_familia text)
returns table(chave text, familia text, rotulo text, ordem integer, data_inicio date, data_fim date, leads integer,
              invest_trafego_centavos bigint, invest_disparo_centavos bigint, grupo integer, pico_d1 integer,
              pico_d2 integer, pico_d3 integer, vendas integer, receita_liquida_centavos bigint, pre_checkout integer,
              fontes jsonb, provisorio text[], criado_em timestamp with time zone, atualizado_em timestamp with time zone)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_servico boolean := coalesce((select auth.role()), '') = 'service_role';
begin
  -- 20261009200000. Gate = 1º passo de dados.cadastro (o das dados_atm_*), copiado do banco em 09/10/2026.
  -- service_role não tem EXECUTE nesta função; o ramo fica para o gate continuar idêntico ao de dados.cadastro.
  if not v_servico and not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  return query
  select h.chave, h.familia, h.rotulo, h.ordem, h.data_inicio, h.data_fim, h.leads, h.invest_trafego_centavos,
         h.invest_disparo_centavos, h.grupo, h.pico_d1, h.pico_d2, h.pico_d3, h.vendas, h.receita_liquida_centavos,
         h.pre_checkout, h.fontes, h.provisorio, h.criado_em, h.atualizado_em
    from dados.edicoes_historico h
   where h.familia = p_familia
   order by h.ordem;
end
$$;
comment on function public.dados_historico_edicoes(text) is
  'Histórico por edição da família (ex.: seminario-atm), ordenado por ordem. Só equipe (gate de dados.cadastro). Família inexistente = 0 linhas. 20261009200000.';

revoke all on function public.dados_historico_edicoes(text) from public, anon, service_role;
grant execute on function public.dados_historico_edicoes(text) to authenticated;

-- pós-condição: authenticated executa, anon e service_role não; ninguém lê a tabela direto
do $p$
begin
  if not has_function_privilege('authenticated', 'public.dados_historico_edicoes(text)', 'execute')
     or has_function_privilege('anon', 'public.dados_historico_edicoes(text)', 'execute')
     or has_function_privilege('service_role', 'public.dados_historico_edicoes(text)', 'execute') then
    raise exception 'pós-condição: grant errado em public.dados_historico_edicoes(text)';
  end if;
  if has_table_privilege('authenticated', 'dados.edicoes_historico', 'select')
     or has_table_privilege('anon', 'dados.edicoes_historico', 'select') then
    raise exception 'pós-condição: anon/authenticated lê dados.edicoes_historico';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'dados.edicoes_historico'::regclass) then
    raise exception 'pós-condição: RLS desligada em dados.edicoes_historico';
  end if;
end
$p$;

notify pgrst, 'reload schema';

insert into pg_temp._z_out (passo, linha) select '02 idempotente (linhas regravadas na 2a passada)',
  ((select count(*) from dados.edicoes_historico h join pg_temp._z_ctid z on z.chave = h.chave where h.ctid::text <> z.c))::text;

insert into pg_temp._z_out (passo, linha) select '02 objetos', (jsonb_build_object(
  'rls', (select relrowsecurity from pg_class where oid = 'dados.edicoes_historico'::regclass),
  'policies', (select count(*) from pg_policies where schemaname = 'dados' and tablename = 'edicoes_historico'),
  'grants_tabela_anon_auth', (select count(*) from information_schema.role_table_grants
                               where table_schema = 'dados' and table_name = 'edicoes_historico' and grantee in ('anon','authenticated')),
  'trigger', (select count(*) from pg_trigger where tgrelid = 'dados.edicoes_historico'::regclass and not tgisinternal),
  'checks', (select count(*) from pg_constraint where conrelid = 'dados.edicoes_historico'::regclass and contype = 'c'),
  'exec_auth', has_function_privilege('authenticated', 'public.dados_historico_edicoes(text)', 'execute'),
  'exec_anon', has_function_privilege('anon', 'public.dados_historico_edicoes(text)', 'execute'),
  'exec_public', (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = 'public.dados_historico_edicoes(text)'::regprocedure and a.grantee = 0),
  'exec_service', has_function_privilege('service_role', 'public.dados_historico_edicoes(text)', 'execute'),
  'definer', (select prosecdef from pg_proc where oid = 'public.dados_historico_edicoes(text)'::regprocedure),
  'search_path', (select proconfig from pg_proc where oid = 'public.dados_historico_edicoes(text)'::regprocedure)))::text;

-- carga: confere com os valores do pedido (09/10/2026)
insert into pg_temp._z_out (passo, linha) select '03 carga', ((select jsonb_agg(jsonb_build_object(
  'chave', chave, 'rotulo', rotulo, 'ordem', ordem, 'datas_nulas', data_inicio is null and data_fim is null,
  'leads', leads, 'traf', invest_trafego_centavos, 'disp', invest_disparo_centavos, 'grupo', grupo,
  'picos', array[pico_d1, pico_d2, pico_d3], 'vendas', vendas, 'receita', receita_liquida_centavos, 'pc', pre_checkout,
  'fontes', (select count(*) from jsonb_object_keys(fontes)), 'prov', provisorio) order by ordem) from dados.edicoes_historico))::text;
insert into pg_temp._z_out (passo, linha) select '03 confere com o pedido', ((select
  count(*) filter (where (chave, familia, rotulo, ordem, leads, invest_trafego_centavos, invest_disparo_centavos, grupo, pico_d1, pico_d2, pico_d3, vendas, receita_liquida_centavos, pre_checkout)
                         is not distinct from ('atm-1-2026-07', 'seminario-atm', 'ATM JUL/26', 1, 424, 0::bigint, 203993::bigint, 345, 74, 21, null::int, 7, 991907::bigint, 26))
  || '/1 JUL, ' ||
  count(*) filter (where (chave, familia, rotulo, ordem, leads, invest_trafego_centavos, invest_disparo_centavos, grupo, pico_d1, pico_d2, pico_d3, vendas, receita_liquida_centavos, pre_checkout)
                         is not distinct from ('atm-2-2026-09', 'seminario-atm', 'ATM SET/26', 2, 911, 0::bigint, 211948::bigint, 743, 127, 62, 40, 9, 1275291::bigint, 33))
  || '/1 SET, total ' || count(*)
  from dados.edicoes_historico))::text;
insert into pg_temp._z_out (passo, linha) select '03 chaves das fontes', ((select string_agg(distinct k, ',' order by k)
  from dados.edicoes_historico, jsonb_object_keys(fontes) k))::text;

-- recusas de check
do $rc$ declare r text := ''; begin
  begin update dados.edicoes_historico set leads = -1 where chave = 'atm-1-2026-07'; r := r || 'negativo=ok '; exception when others then r := r || 'negativo=' || sqlstate || ' '; end;
  begin update dados.edicoes_historico set provisorio = array['inventada'] where chave = 'atm-1-2026-07'; r := r || 'provisorio_invalido=ok '; exception when others then r := r || 'provisorio_invalido=' || sqlstate || ' '; end;
  begin update dados.edicoes_historico set ordem = 1 where chave = 'atm-2-2026-09'; r := r || 'ordem_repetida=ok '; exception when others then r := r || 'ordem_repetida=' || sqlstate || ' '; end;
  begin update dados.edicoes_historico set data_inicio = date '2026-07-10', data_fim = date '2026-07-01' where chave = 'atm-1-2026-07'; r := r || 'datas_invertidas=ok '; exception when others then r := r || 'datas_invertidas=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('03 recusas de check', r);
end $rc$;

-- equipe, como authenticated
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '04 equipe seminario-atm', ((select jsonb_build_object(
  'linhas', count(*), 'ordem', string_agg(x.chave, ',' order by x.ordem), 'colunas', (select count(*) from jsonb_object_keys((select to_jsonb(y) from public.dados_historico_edicoes('seminario-atm') y limit 1))),
  'd3_jul_nulo', bool_or(x.chave = 'atm-1-2026-07' and x.pico_d3 is null))
  from public.dados_historico_edicoes('seminario-atm') x))::text;
insert into pg_temp._z_out (passo, linha) select '04 equipe familia inexistente', ((select count(*) from public.dados_historico_edicoes('nao-existe')))::text;
insert into pg_temp._z_out (passo, linha) select '04 equipe familia nula', ((select count(*) from public.dados_historico_edicoes(null)))::text;
do $rc$ declare r text := ''; begin
  begin perform * from dados.edicoes_historico; r := r || 'tabela_direto=ok '; exception when others then r := r || 'tabela_direto=' || sqlstate || ' '; end;
  begin insert into dados.edicoes_historico (chave, familia, rotulo, ordem) values ('zz-x', 'zz', 'zz', 9); r := r || 'insert_direto=ok '; exception when others then r := r || 'insert_direto=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('04 equipe direto na tabela', r);
end $rc$;
do $ex$ declare l text; t text := ''; begin
  for l in execute 'explain (analyze, costs off, summary on) select * from public.dados_historico_edicoes(''seminario-atm'')' loop t := t || l || ' | '; end loop;
  insert into pg_temp._z_out (passo, linha) values ('07 explain rpc (authenticated)', t);
end $ex$;
reset role;

-- authenticated sem acesso (não é equipe)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000e0510","role":"authenticated"}', true);
do $rc$ declare r text := ''; begin
  begin perform * from public.dados_historico_edicoes('seminario-atm'); r := r || 'rpc=ok '; exception when others then r := r || 'rpc=' || sqlstate || ' ' || sqlerrm || ' '; end;
  begin perform * from public.dados_historico_edicoes('nao-existe'); r := r || 'rpc_inexistente=ok '; exception when others then r := r || 'rpc_inexistente=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('05 nao equipe', r);
end $rc$;
reset role;

-- anon
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $rc$ declare r text := ''; begin
  begin perform * from public.dados_historico_edicoes('seminario-atm'); r := r || 'rpc=ok '; exception when others then r := r || 'rpc=' || sqlstate || ' '; end;
  begin perform * from dados.edicoes_historico; r := r || 'tabela=ok '; exception when others then r := r || 'tabela=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('06 anon', r);
end $rc$;
reset role;

-- service_role (sem EXECUTE)
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
do $rc$ declare r text := ''; begin
  begin perform * from public.dados_historico_edicoes('seminario-atm'); r := r || 'rpc=ok '; exception when others then r := r || 'rpc=' || sqlstate || ' '; end;
  insert into pg_temp._z_out (passo, linha) values ('06 service_role', r);
end $rc$;
reset role;
select set_config('request.jwt.claims', '{}', true);

do $ex$ declare l text; t text := ''; begin
  for l in execute 'explain (analyze, costs off, summary on) select * from dados.edicoes_historico h where h.familia = ''seminario-atm'' order by h.ordem' loop t := t || l || ' | '; end loop;
  insert into pg_temp._z_out (passo, linha) values ('07 explain consulta interna', t);
end $ex$;

-- 08 passo de registro da próxima edição (.explain.md seção 4), contra o dashboard vivo, em chave de ensaio
do $rc$ declare r text := ''; begin
  begin
    select set_config('request.jwt.claims', '{"role":"service_role"}', true) into r;
    r := '';
    execute $q$do $registrar$
declare
  c_dash   constant text := 'atm-elaine-1-2026-10';     -- chave do dashboard (dados.dashboards)
  c_chave  constant text := 'zz-ensaio-registro';    -- chave da edição no histórico
  c_rotulo constant text := 'zz ensaio';   -- rótulo da coluna na tela
  c_ordem  constant int  := 99;      -- próxima ordem da família
  r record; p record; s record; v_prov text[] := '{}';
begin
  select x.* into r from public.dados_atm_resumo(c_dash) x;                        -- período do evento (padrão)
  select x.* into p from public.dados_atm_pos_live(c_dash) x where x.ciclo = 'fechado';
  if p.ate is null then
    raise exception 'ciclo não fechado: cadastrar dados.dashboards.ciclo_fecha_em antes' using errcode = '22023';
  end if;
  select max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'live')    as d1,
         max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'replay')  as d2,
         max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'triplay') as d3,
         array_remove(array[
           case when bool_or(x.tipo = 'live'    and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d1' end,
           case when bool_or(x.tipo = 'replay'  and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d2' end,
           case when bool_or(x.tipo = 'triplay' and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d3' end
         ], null) as sem_equipe
    into s from public.dados_atm_comparecimento(c_dash) x;
  v_prov := array['invest_trafego'] || coalesce(s.sem_equipe, '{}'::text[])
            || case when r.custo_completo then '{}'::text[] else array['invest_disparo'] end;
  insert into dados.edicoes_historico as h
    (chave, familia, rotulo, ordem, data_inicio, data_fim, leads, invest_trafego_centavos, invest_disparo_centavos, grupo,
     pico_d1, pico_d2, pico_d3, vendas, receita_liquida_centavos, pre_checkout, fontes, provisorio)
  values (c_chave, 'seminario-atm', c_rotulo, c_ordem, r.periodo_de, r.periodo_ate, r.leads, null,
          r.custo_disparo_centavos, r.grupo_entradas, s.d1, s.d2, s.d3, p.vendas, round(p.receita_liquida * 100)::bigint,
          r.pre_checkout_pessoas,
          jsonb_build_object(
            'leads',           'banco: dados_atm_resumo, período do evento, sem teste',
            'invest_trafego',  'sem fonte no banco: preencher à mão',
            'invest_disparo',  'banco: dados_atm_resumo.custo_disparo_centavos (mkt_mensageria.disparos)',
            'grupo',           'banco: dados_atm_resumo.grupo_entradas, período do evento',
            'pico_d1',         'banco: dados_atm_comparecimento, live, pico menos equipe',
            'pico_d2',         'banco: dados_atm_comparecimento, replay, pico menos equipe',
            'pico_d3',         'banco: dados_atm_comparecimento, triplay, pico menos equipe',
            'vendas',          'banco: dados_atm_pos_live, ciclo fechado',
            'receita_liquida', 'banco: dados_atm_pos_live, ciclo fechado, líquido BRL',
            'pre_checkout',    'banco: dados_atm_resumo.pre_checkout_pessoas, período do evento'),
          v_prov)
  on conflict (chave) do update
     set familia = excluded.familia, rotulo = excluded.rotulo, ordem = excluded.ordem,
         data_inicio = excluded.data_inicio, data_fim = excluded.data_fim, leads = excluded.leads,
         invest_trafego_centavos = excluded.invest_trafego_centavos, invest_disparo_centavos = excluded.invest_disparo_centavos,
         grupo = excluded.grupo, pico_d1 = excluded.pico_d1, pico_d2 = excluded.pico_d2, pico_d3 = excluded.pico_d3,
         vendas = excluded.vendas, receita_liquida_centavos = excluded.receita_liquida_centavos,
         pre_checkout = excluded.pre_checkout, fontes = excluded.fontes, provisorio = excluded.provisorio;
end
$registrar$$q$;
    r := r || 'ciclo_aberto=ok ';
  exception when others then r := r || 'ciclo_aberto=' || sqlstate || ' ';
  end;
  insert into pg_temp._z_out (passo, linha) values ('08 passo com ciclo nao fechado (espera 22023)', r);
end $rc$;

-- fecha o ciclo SÓ dentro do ensaio (rollback no fim) para exercitar o caminho inteiro
update dados.dashboards set ciclo_fecha_em = now() where chave = 'atm-elaine-1-2026-10';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $rc$ begin
  execute $q$do $registrar$
declare
  c_dash   constant text := 'atm-elaine-1-2026-10';     -- chave do dashboard (dados.dashboards)
  c_chave  constant text := 'zz-ensaio-registro';    -- chave da edição no histórico
  c_rotulo constant text := 'zz ensaio';   -- rótulo da coluna na tela
  c_ordem  constant int  := 99;      -- próxima ordem da família
  r record; p record; s record; v_prov text[] := '{}';
begin
  select x.* into r from public.dados_atm_resumo(c_dash) x;                        -- período do evento (padrão)
  select x.* into p from public.dados_atm_pos_live(c_dash) x where x.ciclo = 'fechado';
  if p.ate is null then
    raise exception 'ciclo não fechado: cadastrar dados.dashboards.ciclo_fecha_em antes' using errcode = '22023';
  end if;
  select max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'live')    as d1,
         max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'replay')  as d2,
         max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'triplay') as d3,
         array_remove(array[
           case when bool_or(x.tipo = 'live'    and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d1' end,
           case when bool_or(x.tipo = 'replay'  and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d2' end,
           case when bool_or(x.tipo = 'triplay' and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d3' end
         ], null) as sem_equipe
    into s from public.dados_atm_comparecimento(c_dash) x;
  v_prov := array['invest_trafego'] || coalesce(s.sem_equipe, '{}'::text[])
            || case when r.custo_completo then '{}'::text[] else array['invest_disparo'] end;
  insert into dados.edicoes_historico as h
    (chave, familia, rotulo, ordem, data_inicio, data_fim, leads, invest_trafego_centavos, invest_disparo_centavos, grupo,
     pico_d1, pico_d2, pico_d3, vendas, receita_liquida_centavos, pre_checkout, fontes, provisorio)
  values (c_chave, 'seminario-atm', c_rotulo, c_ordem, r.periodo_de, r.periodo_ate, r.leads, null,
          r.custo_disparo_centavos, r.grupo_entradas, s.d1, s.d2, s.d3, p.vendas, round(p.receita_liquida * 100)::bigint,
          r.pre_checkout_pessoas,
          jsonb_build_object(
            'leads',           'banco: dados_atm_resumo, período do evento, sem teste',
            'invest_trafego',  'sem fonte no banco: preencher à mão',
            'invest_disparo',  'banco: dados_atm_resumo.custo_disparo_centavos (mkt_mensageria.disparos)',
            'grupo',           'banco: dados_atm_resumo.grupo_entradas, período do evento',
            'pico_d1',         'banco: dados_atm_comparecimento, live, pico menos equipe',
            'pico_d2',         'banco: dados_atm_comparecimento, replay, pico menos equipe',
            'pico_d3',         'banco: dados_atm_comparecimento, triplay, pico menos equipe',
            'vendas',          'banco: dados_atm_pos_live, ciclo fechado',
            'receita_liquida', 'banco: dados_atm_pos_live, ciclo fechado, líquido BRL',
            'pre_checkout',    'banco: dados_atm_resumo.pre_checkout_pessoas, período do evento'),
          v_prov)
  on conflict (chave) do update
     set familia = excluded.familia, rotulo = excluded.rotulo, ordem = excluded.ordem,
         data_inicio = excluded.data_inicio, data_fim = excluded.data_fim, leads = excluded.leads,
         invest_trafego_centavos = excluded.invest_trafego_centavos, invest_disparo_centavos = excluded.invest_disparo_centavos,
         grupo = excluded.grupo, pico_d1 = excluded.pico_d1, pico_d2 = excluded.pico_d2, pico_d3 = excluded.pico_d3,
         vendas = excluded.vendas, receita_liquida_centavos = excluded.receita_liquida_centavos,
         pre_checkout = excluded.pre_checkout, fontes = excluded.fontes, provisorio = excluded.provisorio;
end
$registrar$$q$;
  execute $q$do $registrar$
declare
  c_dash   constant text := 'atm-elaine-1-2026-10';     -- chave do dashboard (dados.dashboards)
  c_chave  constant text := 'zz-ensaio-registro';    -- chave da edição no histórico
  c_rotulo constant text := 'zz ensaio';   -- rótulo da coluna na tela
  c_ordem  constant int  := 99;      -- próxima ordem da família
  r record; p record; s record; v_prov text[] := '{}';
begin
  select x.* into r from public.dados_atm_resumo(c_dash) x;                        -- período do evento (padrão)
  select x.* into p from public.dados_atm_pos_live(c_dash) x where x.ciclo = 'fechado';
  if p.ate is null then
    raise exception 'ciclo não fechado: cadastrar dados.dashboards.ciclo_fecha_em antes' using errcode = '22023';
  end if;
  select max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'live')    as d1,
         max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'replay')  as d2,
         max(x.pico_audiencia - coalesce(x.equipe_na_sala, 0)) filter (where x.tipo = 'triplay') as d3,
         array_remove(array[
           case when bool_or(x.tipo = 'live'    and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d1' end,
           case when bool_or(x.tipo = 'replay'  and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d2' end,
           case when bool_or(x.tipo = 'triplay' and x.pico_audiencia is not null and x.equipe_na_sala is null) then 'pico_d3' end
         ], null) as sem_equipe
    into s from public.dados_atm_comparecimento(c_dash) x;
  v_prov := array['invest_trafego'] || coalesce(s.sem_equipe, '{}'::text[])
            || case when r.custo_completo then '{}'::text[] else array['invest_disparo'] end;
  insert into dados.edicoes_historico as h
    (chave, familia, rotulo, ordem, data_inicio, data_fim, leads, invest_trafego_centavos, invest_disparo_centavos, grupo,
     pico_d1, pico_d2, pico_d3, vendas, receita_liquida_centavos, pre_checkout, fontes, provisorio)
  values (c_chave, 'seminario-atm', c_rotulo, c_ordem, r.periodo_de, r.periodo_ate, r.leads, null,
          r.custo_disparo_centavos, r.grupo_entradas, s.d1, s.d2, s.d3, p.vendas, round(p.receita_liquida * 100)::bigint,
          r.pre_checkout_pessoas,
          jsonb_build_object(
            'leads',           'banco: dados_atm_resumo, período do evento, sem teste',
            'invest_trafego',  'sem fonte no banco: preencher à mão',
            'invest_disparo',  'banco: dados_atm_resumo.custo_disparo_centavos (mkt_mensageria.disparos)',
            'grupo',           'banco: dados_atm_resumo.grupo_entradas, período do evento',
            'pico_d1',         'banco: dados_atm_comparecimento, live, pico menos equipe',
            'pico_d2',         'banco: dados_atm_comparecimento, replay, pico menos equipe',
            'pico_d3',         'banco: dados_atm_comparecimento, triplay, pico menos equipe',
            'vendas',          'banco: dados_atm_pos_live, ciclo fechado',
            'receita_liquida', 'banco: dados_atm_pos_live, ciclo fechado, líquido BRL',
            'pre_checkout',    'banco: dados_atm_resumo.pre_checkout_pessoas, período do evento'),
          v_prov)
  on conflict (chave) do update
     set familia = excluded.familia, rotulo = excluded.rotulo, ordem = excluded.ordem,
         data_inicio = excluded.data_inicio, data_fim = excluded.data_fim, leads = excluded.leads,
         invest_trafego_centavos = excluded.invest_trafego_centavos, invest_disparo_centavos = excluded.invest_disparo_centavos,
         grupo = excluded.grupo, pico_d1 = excluded.pico_d1, pico_d2 = excluded.pico_d2, pico_d3 = excluded.pico_d3,
         vendas = excluded.vendas, receita_liquida_centavos = excluded.receita_liquida_centavos,
         pre_checkout = excluded.pre_checkout, fontes = excluded.fontes, provisorio = excluded.provisorio;
end
$registrar$$q$;   -- 2a vez: on conflict, continua 1 linha
end $rc$;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '08 passo registrado (ensaio)', ((select jsonb_build_object(
  'linhas', (select count(*) from dados.edicoes_historico where chave = 'zz-ensaio-registro'),
  'nulas', (select string_agg(k, ',' order by k) from jsonb_each(to_jsonb(h)) e(k, v) where v = 'null'::jsonb),
  'provisorio', h.provisorio, 'fontes', (select count(*) from jsonb_object_keys(h.fontes)),
  'bate_resumo', (h.leads, h.grupo, h.pre_checkout, h.invest_disparo_centavos, h.data_inicio, h.data_fim) is not distinct from
                 (select (r.leads, r.grupo_entradas, r.pre_checkout_pessoas, r.custo_disparo_centavos, r.periodo_de, r.periodo_ate) from public.dados_atm_resumo('atm-elaine-1-2026-10') r),
  'bate_pos_live', (h.vendas, h.receita_liquida_centavos) is not distinct from
                 (select (p.vendas, round(p.receita_liquida * 100)::bigint) from public.dados_atm_pos_live('atm-elaine-1-2026-10') p where p.ciclo = 'fechado'),
  'na_rpc', (select count(*) from public.dados_historico_edicoes('seminario-atm')))
  from dados.edicoes_historico h where h.chave = 'zz-ensaio-registro'))::text;
select set_config('request.jwt.claims', '{}', true);

-- reversão
-- Reversão de 20261009200000 (histórico por edição). Apaga a RPC e a tabela, com a carga dos ATMs JUL/26 e SET/26 e
-- qualquer edição registrada depois pelo passo do .explain.md (seção 4). A carga dos dois ATMs volta rodando a migration
-- de novo; uma edição registrada depois NÃO volta: exportar dados.edicoes_historico antes de rodar.
-- Rodada dentro do ensaio 20261009200000_ensaio.sql.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

drop function if exists public.dados_historico_edicoes(text);
drop table if exists dados.edicoes_historico;

notify pgrst, 'reload schema';

insert into pg_temp._z_out (passo, linha) select '09 revertido', (jsonb_build_object(
  'tabela', to_regclass('dados.edicoes_historico') is not null,
  'rpc', to_regprocedure('public.dados_historico_edicoes(text)') is not null,
  'funcoes_historico', (select count(*) from pg_proc where proname like '%historico_edicoes%')))::text;
update dados.dashboards set ciclo_fecha_em = null where chave = 'atm-elaine-1-2026-10';
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '09 depois resumo ATM OUT md5 (igual ao 01?)',
  ((select md5((to_jsonb(r) - 'atualizado_em')::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') r))::text;
select set_config('request.jwt.claims', '{}', true);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
