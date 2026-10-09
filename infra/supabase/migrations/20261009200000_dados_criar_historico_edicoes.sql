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
