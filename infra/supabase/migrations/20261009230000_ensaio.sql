-- Ensaio de 20261009230000 (transação desfeita). Lê como pessoa da equipe; dados de tráfego simulados com os valores
-- que a API do Meta devolveu em 09/10 para a campanha 8441 (sem dado pessoal).
begin;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '1 antes resumo', (select jsonb_build_object('leads', leads, 'custo_disparo', custo_disparo_centavos, 'completo', custo_completo, 'cpl', cpl_centavos, 'cac', cac_centavos, 'roas', roas) from public.dados_atm_resumo('atm-elaine-1-2026-10'))::text;
insert into pg_temp._z_out (passo, linha) select '1 antes md5 resumo sem investimento', md5((select jsonb_agg(to_jsonb(r) - array['cpl_centavos','cac_centavos','roas','roas_liquido','custo_completo','custo_trafego_centavos','investimento_total_centavos','atualizado_em']) from public.dados_atm_resumo('atm-elaine-1-2026-10') r)::text);
insert into pg_temp._z_out (passo, linha) select '1 antes md5 trafego_projeto 75', md5(coalesce((select public.trafego_projeto(75))::text, 'null'));
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== MIGRATION =====
-- 20261009230000: tráfego do ATM (campanha de distribuição), métricas de distribuição na coleta Meta e investimento total
--
-- STATUS: ver 20261009230000.explain.md.
-- POR QUE: pedido do Victor (09/10/2026, card 17tya50fugc). A ATM OUT/26 tem tráfego pago de distribuição de conteúdo
--   (campanha 8441 "CF | ATM1OUT26 | DISTRIBUIÇÃO | BY THE WAY | META | PQ | ABO | ALCANCE", conta 43 "Seminários - Leads")
--   sem projeto. Decisão do Victor: CPL = (tráfego + disparo) ÷ leads, nas duas abas.
-- O QUE FAZ:
--   1. mkt_trafego.desempenho_dia ganha colunas NULÁVEIS de distribuição (alcance, frequencia, cliques_saida,
--      landing_page_views, engajamento, video_plays, video_thruplay, video_p25/p50/p75/p100). As existentes não mudam.
--   2. mkt_trafego.desempenho_total: alcance e frequência do período INTEIRO de cada campanha (alcance não soma por dia),
--      com public.trafego_desempenho_total_receber (só service_role/postgres, como trafego_desempenho_receber).
--   3. public.trafego_desempenho_receber (corpo vivo + colunas novas, opcionais; sem elas grava null como antes).
--   4. Campanha 8441 ligada ao projeto 75 (ATMEL126) pelo caminho do módulo: projeto_id + projeto_manual = true (o mesmo
--      que trafego_campanha_ajustar faz; a coleta não sobrescreve projeto manual).
--   5. public.dados_atm_trafego(p_chave, p_de, p_ate) jsonb: dia a dia, total e campanhas ligadas (gate das dados_atm_*).
--   6. public.dados_atm_resumo: + custo_trafego_centavos e investimento_total_centavos (no fim); CPL, CAC e ROAS sobre o
--      investimento total. Recriada (o tipo de retorno muda) com os MESMOS grants de hoje: authenticated e service_role
--      (o service_role é da TV, migration 20261009120000).
-- AS 5 PERGUNTAS: escala: 11 colunas nulas numa tabela de ~10 mil linhas, 1 tabela pequena; índice: PK; frequência: a
--   coleta diária e a leitura do dashboard; repetição: upsert idempotente; reversão: 20261009230000_reversao.sql.


do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.trafego_desempenho_receber(jsonb)'::regprocedure) <> '6d0b8fbecaa6f5f57681e9a397e52a4d'
     and (select prosrc from pg_proc where oid = 'public.trafego_desempenho_receber(jsonb)'::regprocedure) !~ '20261009230000' then
    raise exception '20261009230000: corpo vivo de trafego_desempenho_receber mudou. Reler.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_atm_resumo(text,date,date)'::regprocedure) <> '8583789a435e0c38f91e812911ea660a'
     and (select prosrc from pg_proc where oid = 'public.dados_atm_resumo(text,date,date)'::regprocedure) !~ '20261009230000' then
    raise exception '20261009230000: corpo vivo de dados_atm_resumo mudou. Reler.';
  end if;
end
$g$;

-- 1. colunas novas (nuláveis)
alter table mkt_trafego.desempenho_dia
  add column if not exists alcance bigint check (alcance >= 0),
  add column if not exists frequencia numeric(12,4) check (frequencia >= 0),
  add column if not exists cliques_saida bigint check (cliques_saida >= 0),
  add column if not exists landing_page_views bigint check (landing_page_views >= 0),
  add column if not exists engajamento bigint check (engajamento >= 0),
  add column if not exists video_plays bigint check (video_plays >= 0),
  add column if not exists video_thruplay bigint check (video_thruplay >= 0),
  add column if not exists video_p25 bigint check (video_p25 >= 0),
  add column if not exists video_p50 bigint check (video_p50 >= 0),
  add column if not exists video_p75 bigint check (video_p75 >= 0),
  add column if not exists video_p100 bigint check (video_p100 >= 0);

-- 2. total do período inteiro por campanha
create table if not exists mkt_trafego.desempenho_total (
  campanha_id bigint primary key references mkt_trafego.campanhas (id) on delete cascade,
  de date not null,
  ate date not null check (ate >= de),
  gasto numeric(14,2) check (gasto >= 0),
  impressoes bigint check (impressoes >= 0),
  alcance bigint check (alcance >= 0),
  frequencia numeric(12,4) check (frequencia >= 0),
  coletado_em timestamptz not null default now()
);
alter table mkt_trafego.desempenho_total enable row level security;
revoke all on mkt_trafego.desempenho_total from public, anon, authenticated;

create or replace function public.trafego_desempenho_total_receber(p jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  e jsonb; v_camp bigint; v_de date; v_ate date; v_gasto numeric; v_imp bigint; v_alc bigint; v_freq numeric;
  v_n int := 0; v_recusas jsonb := '[]'::jsonb;
begin
  -- 20261009230000: alcance e frequência do período inteiro (date_preset=maximum) de cada campanha que gastou
  if jsonb_typeof(p) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava uma lista.');
  end if;
  if jsonb_array_length(p) > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000 por chamada).');
  end if;
  for e in select * from jsonb_array_elements(p) loop
    select c.id into v_camp from mkt_trafego.campanhas c
     where c.plataforma = lower(btrim(coalesce(e ->> 'plataforma', ''))) and c.campanha_externa = btrim(coalesce(e ->> 'campanha', ''));
    if v_camp is null then
      v_recusas := v_recusas || jsonb_build_object('campanha', e ->> 'campanha', 'motivo', 'campanha_desconhecida');
      continue;
    end if;
    begin
      v_de := (e ->> 'de')::date; v_ate := (e ->> 'ate')::date;
      v_gasto := (e ->> 'gasto')::numeric; v_imp := (e ->> 'impressoes')::bigint;
      v_alc := (e ->> 'alcance')::bigint; v_freq := (e ->> 'frequencia')::numeric;
    exception when others then
      v_recusas := v_recusas || jsonb_build_object('campanha', e ->> 'campanha', 'motivo', 'formato_invalido');
      continue;
    end;
    if v_de is null or v_ate is null or v_ate < v_de or v_ate > mkt_trafego.ontem() + 1 or v_gasto < 0 or v_gasto >= 1e12
       or v_imp < 0 or v_alc < 0 or v_freq < 0 or v_freq >= 1e6 then
      v_recusas := v_recusas || jsonb_build_object('campanha', e ->> 'campanha', 'motivo', 'valor_invalido');
      continue;
    end if;
    insert into mkt_trafego.desempenho_total (campanha_id, de, ate, gasto, impressoes, alcance, frequencia, coletado_em)
    values (v_camp, v_de, v_ate, round(v_gasto, 2), v_imp, v_alc, round(v_freq, 4), now())
    on conflict (campanha_id) do update
       set de = excluded.de, ate = excluded.ate, gasto = excluded.gasto, impressoes = excluded.impressoes,
           alcance = excluded.alcance, frequencia = excluded.frequencia, coletado_em = now();
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'gravadas', v_n, 'recusas', v_recusas);
end
$function$;
revoke all on function public.trafego_desempenho_total_receber(jsonb) from public, anon, authenticated;
grant execute on function public.trafego_desempenho_total_receber(jsonb) to service_role;

-- 3. receber o desempenho diário com as colunas novas
CREATE OR REPLACE FUNCTION public.trafego_desempenho_receber(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e jsonb;
  v_camp bigint; v_dia date; v_gasto numeric; v_imp bigint; v_cli bigint; v_tot bigint; v_leads integer;
  -- 20261009230000: métricas de distribuição (opcionais; null = a API não mandou)
  v_alc bigint; v_freq numeric; v_sai bigint; v_lpv bigint; v_eng bigint; v_vpl bigint; v_vth bigint;
  v_v25 bigint; v_v50 bigint; v_v75 bigint; v_v100 bigint;
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
      v_alc := (e ->> 'alcance')::bigint; v_freq := (e ->> 'frequencia')::numeric; v_sai := (e ->> 'cliques_saida')::bigint;
      v_lpv := (e ->> 'landing_page_views')::bigint; v_eng := (e ->> 'engajamento')::bigint;
      v_vpl := (e ->> 'video_plays')::bigint; v_vth := (e ->> 'video_thruplay')::bigint;
      v_v25 := (e ->> 'video_p25')::bigint; v_v50 := (e ->> 'video_p50')::bigint;
      v_v75 := (e ->> 'video_p75')::bigint; v_v100 := (e ->> 'video_p100')::bigint;
    exception when others then
      v_recusas := v_recusas || jsonb_build_object('campanha', e ->> 'campanha', 'dia', e ->> 'dia', 'motivo', 'formato_invalido');
      continue;
    end;
    if v_dia is null or v_dia > mkt_trafego.ontem() + 1 or v_gasto < 0 or v_imp < 0 or v_cli < 0 or v_tot < 0 or v_leads < 0
       or v_gasto >= 1e12
       or v_alc < 0 or v_freq < 0 or v_freq >= 1e6 or v_sai < 0 or v_lpv < 0 or v_eng < 0 or v_vpl < 0 or v_vth < 0
       or v_v25 < 0 or v_v50 < 0 or v_v75 < 0 or v_v100 < 0 then
      v_recusas := v_recusas || jsonb_build_object('campanha', e ->> 'campanha', 'dia', e ->> 'dia', 'motivo', 'valor_invalido');
      continue;
    end if;
    insert into mkt_trafego.desempenho_dia (campanha_id, dia, gasto, impressoes, cliques_link, cliques_total, leads_plataforma, coletado_em,
                                            alcance, frequencia, cliques_saida, landing_page_views, engajamento,
                                            video_plays, video_thruplay, video_p25, video_p50, video_p75, video_p100)
    values (v_camp, v_dia, round(v_gasto, 2), v_imp, v_cli, v_tot, v_leads, now(),
            v_alc, round(v_freq, 4), v_sai, v_lpv, v_eng, v_vpl, v_vth, v_v25, v_v50, v_v75, v_v100)
    on conflict (campanha_id, dia) do update
       set gasto = excluded.gasto, impressoes = excluded.impressoes, cliques_link = excluded.cliques_link,
           cliques_total = excluded.cliques_total,
           leads_plataforma = excluded.leads_plataforma, coletado_em = now(),
           alcance = excluded.alcance, frequencia = excluded.frequencia, cliques_saida = excluded.cliques_saida,
           landing_page_views = excluded.landing_page_views, engajamento = excluded.engajamento,
           video_plays = excluded.video_plays, video_thruplay = excluded.video_thruplay, video_p25 = excluded.video_p25,
           video_p50 = excluded.video_p50, video_p75 = excluded.video_p75, video_p100 = excluded.video_p100;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'gravadas', v_n, 'recusas', v_recusas);
end
$function$;

-- 4. campanha de distribuição da ATM OUT/26 no projeto 75 (pedido do Victor, 09/10/2026)
do $v$
begin
  update mkt_trafego.campanhas
     set projeto_id = 75, projeto_manual = true, atualizado_em = now()
   where id = 8441 and campanha_externa = '120249566833800372' and plataforma = 'meta'
     and (projeto_id is null or projeto_id = 75)
     and exists (select 1 from mkt.projetos where id = 75 and sigla = 'ATMEL126');
  if not exists (select 1 from mkt_trafego.campanhas where id = 8441 and projeto_id = 75 and projeto_manual) then
    raise exception '20261009230000: campanha 8441 não ficou ligada ao projeto 75 (conferir antes).';
  end if;
end
$v$;

-- 5. RPC do bloco/aba Tráfego
create or replace function public.dados_atm_trafego(p_chave text, p_de date default null, p_ate date default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_de date; v_ate date;
  r jsonb;
begin
  select x.de, x.ate into v_de, v_ate from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  with c as (
    select c.id, c.nome, c.status_plataforma, c.objetivo, c.campanha_externa, ct.nome as conta, ct.moeda
      from mkt_trafego.campanhas c join mkt_trafego.contas ct on ct.id = c.conta_id
     where c.projeto_id = d.projeto_id and ct.moeda = 'BRL'
  ),
  dd as (
    select x.* from mkt_trafego.desempenho_dia x join c on c.id = x.campanha_id
     where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date)
  ),
  -- soma só quando TODAS as linhas têm o dado (senão null: a API não mandou para alguma campanha/dia)
  dia as (
    select dd.dia,
           round(sum(dd.gasto) * 100)::bigint as gasto_centavos, sum(dd.impressoes)::bigint as impressoes,
           -- alcance e frequência não somam entre campanhas: só quando há uma campanha no dia
           case when count(*) = 1 then max(dd.alcance) end as alcance,
           case when count(*) = 1 then max(dd.frequencia) end as frequencia,
           sum(dd.cliques_link)::bigint as cliques_link,
           case when count(dd.cliques_total) = count(*) then sum(dd.cliques_total) end::bigint as cliques_total,
           case when count(dd.cliques_saida) = count(*) then sum(dd.cliques_saida) end::bigint as cliques_saida,
           case when count(dd.landing_page_views) = count(*) then sum(dd.landing_page_views) end::bigint as landing_page_views,
           case when count(dd.engajamento) = count(*) then sum(dd.engajamento) end::bigint as engajamento,
           case when count(dd.video_plays) = count(*) then sum(dd.video_plays) end::bigint as video_plays,
           case when count(dd.video_thruplay) = count(*) then sum(dd.video_thruplay) end::bigint as video_thruplay,
           case when count(dd.video_p25) = count(*) then sum(dd.video_p25) end::bigint as video_p25,
           case when count(dd.video_p50) = count(*) then sum(dd.video_p50) end::bigint as video_p50,
           case when count(dd.video_p75) = count(*) then sum(dd.video_p75) end::bigint as video_p75,
           case when count(dd.video_p100) = count(*) then sum(dd.video_p100) end::bigint as video_p100
      from dd group by dd.dia
  ),
  tot as (
    select round(coalesce(sum(dd.gasto), 0) * 100)::bigint as gasto_centavos, coalesce(sum(dd.impressoes), 0)::bigint as impressoes,
           coalesce(sum(dd.cliques_link), 0)::bigint as cliques_link,
           case when count(dd.cliques_total) = count(*) then sum(dd.cliques_total) end::bigint as cliques_total,
           case when count(dd.cliques_saida) = count(*) then sum(dd.cliques_saida) end::bigint as cliques_saida,
           case when count(dd.landing_page_views) = count(*) then sum(dd.landing_page_views) end::bigint as landing_page_views,
           case when count(dd.engajamento) = count(*) then sum(dd.engajamento) end::bigint as engajamento,
           case when count(dd.video_plays) = count(*) then sum(dd.video_plays) end::bigint as video_plays,
           case when count(dd.video_thruplay) = count(*) then sum(dd.video_thruplay) end::bigint as video_thruplay,
           case when count(dd.video_p25) = count(*) then sum(dd.video_p25) end::bigint as video_p25,
           case when count(dd.video_p50) = count(*) then sum(dd.video_p50) end::bigint as video_p50,
           case when count(dd.video_p75) = count(*) then sum(dd.video_p75) end::bigint as video_p75,
           case when count(dd.video_p100) = count(*) then sum(dd.video_p100) end::bigint as video_p100,
           count(distinct dd.campanha_id) as n_camp, min(dd.dia) as primeiro, max(dd.dia) as ultimo,
           max(dd.coletado_em) as coletado_em
      from dd
  ),
  -- alcance do período: o total do período inteiro da campanha (API), só se for 1 campanha e o período pedido cobrir
  -- todo o período dela; nunca soma de alcance diário
  alc as (
    select case
             when t.n_camp = 0 then null
             when t.n_camp > 1 then 'varias_campanhas'
             when dt.campanha_id is null then 'sem_total'
             when dt.de < coalesce(v_de, '-infinity'::date) or dt.ate > coalesce(v_ate, 'infinity'::date) then 'periodo_parcial'
           end as motivo,
           dt.alcance, dt.frequencia, dt.de, dt.ate
      from tot t
      left join lateral (select x.* from mkt_trafego.desempenho_total x
                          where t.n_camp = 1 and x.campanha_id = (select min(campanha_id) from dd)) dt on true
  )
  select jsonb_build_object(
    'periodo_de', v_de, 'periodo_ate', v_ate, 'moeda', 'BRL', 'coletado_em', t.coletado_em,
    'calculados', jsonb_build_array('cpm_centavos', 'ctr_pct', 'cpc_centavos'),
    'total', jsonb_build_object(
      'gasto_centavos', t.gasto_centavos, 'impressoes', t.impressoes,
      'alcance', case when a.motivo is null then a.alcance end,
      'frequencia', case when a.motivo is null then a.frequencia end,
      'alcance_motivo', a.motivo, 'alcance_de', a.de, 'alcance_ate', a.ate,
      'cliques_link', t.cliques_link, 'cliques_total', t.cliques_total, 'cliques_saida', t.cliques_saida,
      'landing_page_views', t.landing_page_views, 'engajamento', t.engajamento,
      'video_plays', t.video_plays, 'video_thruplay', t.video_thruplay,
      'video_p25', t.video_p25, 'video_p50', t.video_p50, 'video_p75', t.video_p75, 'video_p100', t.video_p100,
      'cpm_centavos', case when t.impressoes > 0 then round(t.gasto_centavos::numeric * 1000 / t.impressoes)::bigint end,
      'ctr_pct', case when t.impressoes > 0 then round(t.cliques_link::numeric * 100 / t.impressoes, 2) end,
      'cpc_centavos', case when t.cliques_link > 0 then round(t.gasto_centavos::numeric / t.cliques_link)::bigint end,
      'dias', (select count(*) from dia), 'primeiro_dia', t.primeiro, 'ultimo_dia', t.ultimo),
    'dias', coalesce((select jsonb_agg(jsonb_build_object(
      'dia', x.dia, 'gasto_centavos', x.gasto_centavos, 'impressoes', x.impressoes, 'alcance', x.alcance, 'frequencia', x.frequencia,
      'cliques_link', x.cliques_link, 'cliques_total', x.cliques_total, 'cliques_saida', x.cliques_saida,
      'landing_page_views', x.landing_page_views, 'engajamento', x.engajamento,
      'video_plays', x.video_plays, 'video_thruplay', x.video_thruplay,
      'video_p25', x.video_p25, 'video_p50', x.video_p50, 'video_p75', x.video_p75, 'video_p100', x.video_p100,
      'cpm_centavos', case when x.impressoes > 0 then round(x.gasto_centavos::numeric * 1000 / x.impressoes)::bigint end,
      'ctr_pct', case when x.impressoes > 0 then round(x.cliques_link::numeric * 100 / x.impressoes, 2) end,
      'cpc_centavos', case when x.cliques_link > 0 then round(x.gasto_centavos::numeric / x.cliques_link)::bigint end
    ) order by x.dia) from dia x), '[]'::jsonb),
    'campanhas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'nome', c.nome, 'status', c.status_plataforma, 'objetivo', c.objetivo, 'conta', c.conta,
      'gasto_centavos', (select round(coalesce(sum(y.gasto), 0) * 100)::bigint from dd y where y.campanha_id = c.id),
      'primeiro_dia', (select min(y.dia) from dd y where y.campanha_id = c.id),
      'ultimo_dia', (select max(y.dia) from dd y where y.campanha_id = c.id)
    ) order by c.nome) from c), '[]'::jsonb)
  ) into r
  from tot t cross join alc a;
  return r;
end
$function$;
revoke all on function public.dados_atm_trafego(text, date, date) from public, anon, service_role;
grant execute on function public.dados_atm_trafego(text, date, date) to authenticated;

-- 6. resumo com tráfego e investimento total (o tipo de retorno muda: drop + create, mesmos grants de hoje)
drop function public.dados_atm_resumo(text, date, date);
CREATE FUNCTION public.dados_atm_resumo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text, disparos_qtd integer, disparos_enviados integer, leads integer, grupo_tem_fonte boolean, grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric, custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint, pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint, receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric, atualizado_em timestamp with time zone, periodo_de date, periodo_ate date, leads_teste integer, grupo_teste integer, vendas_teste integer, receita_teste_bruta numeric, grupo_entradas_aproximadas integer, grupo_foto_em timestamp with time zone, grupo_no_grupo integer, custo_trafego_centavos bigint, investimento_total_centavos bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with disp as (
    -- 20261009210000: e-mail e grupo não têm custo por disparo (custo nulo = sem custo, não falta); só canal pago
    -- (whatsapp_api, sms, ligacao) sem custo deixa o custo incompleto
    select count(*)::int as qtd,
           count(*) filter (where x.custo_centavos is null and x.canal not in ('email', 'grupo'))::int as sem,
           case when count(*) > 0 then coalesce(sum(x.custo_centavos), 0) end::bigint as custo,
           sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
       and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
  ),
  -- 20261009230000: tráfego pago das campanhas ligadas ao projeto (mkt_trafego, conta em BRL), por dia de veiculação
  tf as (
    select round(coalesce(sum(dd.gasto), 0) * 100)::bigint as custo
      from mkt_trafego.desempenho_dia dd
      join mkt_trafego.campanhas c on c.id = dd.campanha_id
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
     where c.projeto_id = d.projeto_id
       and dd.dia >= coalesce(v_de, '-infinity'::date) and dd.dia <= coalesce(v_ate, 'infinity'::date)
  ),
  inv as (select coalesce(disp.custo, 0) + tf.custo as total from disp cross join tf),
  lt as (select * from dados.atm_leads(d.chave) x where x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ld as (select * from lt where not lt.teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim)::int as entradas,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.entrada_aproximada)::int as aprox,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.no_grupo)::int as no_agora,
           (select max(f.concluido_em) from dados.grupo_fotos f join dados.dashboard_grupos dg on dg.id = f.grupo_id
             where dg.chave = d.chave and f.etapa = 'feito') as foto_em,
           count(*) filter (where g.entrou_em is not null and g.saiu_em >= g.entrou_em
                              and g.saiu_em >= v_ini and g.saiu_em < v_fim)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  gt as (
    select count(*)::int as n from dados.v_grupo_pessoas_todos e
     where e.chave = d.chave and e.teste and e.entrou_em >= v_ini and e.entrou_em < v_fim
  ),
  pc as (select y.email from dados.atm_pre_checkout(d.chave) y where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select * from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  txt as (select count(*)::int as n, coalesce(sum(v.valor_bruto) filter (where v.moeda = 'BRL'), 0)::numeric(14,2) as bruta
            from dados.atm_vendas_todas(d.chave) v
           where v.teste and v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ag as (
    select (select count(*)::int from ld) as leads,
           (select count(*)::int from lt where lt.teste) as leads_teste,
           (select count(*)::int from pc) as pc,
           (select count(*)::int from tx) as vendas,
           (select count(*)::int from tx where tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  ),
  -- 20261009230000: completo = há investimento (disparo ou tráfego) e nenhum disparo pago sem custo
  k as (select ((disp.qtd > 0 or tf.custo > 0) and disp.sem = 0) as completo, d.oferta_codigo is not null as tem_oferta
          from disp cross join tf)
  select d.chave, pr.id, pr.sigla, pr.nome, d.oferta_codigo,
         disp.qtd, disp.enviados, ag.leads,
         gr.fonte,
         case when gr.fonte then gr.entradas end,
         case when gr.fonte then gr.saidas end,
         case when gr.fonte and ag.leads > 0 then round(gr.entradas::numeric * 100 / ag.leads, 2)::numeric(7,2) end,
         case when gr.fonte and gr.entradas > 0 then round(gr.saidas::numeric * 100 / gr.entradas, 2)::numeric(7,2) end,
         disp.custo, disp.sem, k.completo,
         -- 20261009230000 (decisão do Victor): CPL, CAC e ROAS sobre o investimento total (tráfego + disparo)
         case when k.completo and ag.leads > 0 then round(inv.total::numeric / ag.leads)::bigint end,
         ag.pc,
         case when k.tem_oferta then ag.vendas end,
         case when k.tem_oferta then ag.fora end,
         case when k.tem_oferta then ag.comp end,
         case when k.tem_oferta then ag.comp_pc end,
         case when k.tem_oferta and ag.pc > 0 then round(ag.comp::numeric * 100 / ag.pc, 2)::numeric(7,2) end,
         case when k.tem_oferta and k.completo and ag.vendas > 0 then round(inv.total::numeric / ag.vendas)::bigint end,
         case when k.tem_oferta then ag.bruta end,
         case when k.tem_oferta then ag.liq end,
         case when k.tem_oferta and k.completo and inv.total > 0 then round(ag.bruta * 100 / inv.total, 2)::numeric(10,2) end,
         case when k.tem_oferta and k.completo and inv.total > 0 then round(ag.liq * 100 / inv.total, 2)::numeric(10,2) end,
         now(),
         v_de, v_ate, ag.leads_teste, case when gr.fonte then gt.n end,
         case when k.tem_oferta then txt.n end, case when k.tem_oferta then txt.bruta end,
         case when gr.fonte then gr.aprox end, gr.foto_em, case when gr.fonte then gr.no_agora end,
         tf.custo, inv.total
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join gt cross join txt cross join k
         cross join tf cross join inv
   where pr.id = d.projeto_id;
end
$function$;
revoke all on function public.dados_atm_resumo(text, date, date) from public, anon;
grant execute on function public.dados_atm_resumo(text, date, date) to authenticated, service_role;

do $c$
begin
  if not has_function_privilege('authenticated', 'public.dados_atm_resumo(text,date,date)', 'execute')
     or not has_function_privilege('service_role', 'public.dados_atm_resumo(text,date,date)', 'execute')
     or has_function_privilege('anon', 'public.dados_atm_resumo(text,date,date)', 'execute')
     or has_function_privilege('anon', 'public.dados_atm_trafego(text,date,date)', 'execute')
     or has_function_privilege('service_role', 'public.dados_atm_trafego(text,date,date)', 'execute')
     or has_function_privilege('authenticated', 'public.trafego_desempenho_total_receber(jsonb)', 'execute')
     or has_table_privilege('authenticated', 'mkt_trafego.desempenho_total', 'select') then
    raise exception '20261009230000: permissões erradas';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '2 campanha 8441', (select jsonb_build_object('projeto', projeto_id, 'manual', projeto_manual) from mkt_trafego.campanhas where id = 8441)::text;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '2 depois, antes da recoleta resumo', (select jsonb_build_object('leads', leads, 'custo_disparo', custo_disparo_centavos, 'completo', custo_completo, 'cpl', cpl_centavos, 'cac', cac_centavos, 'roas', roas) from public.dados_atm_resumo('atm-elaine-1-2026-10'))::text;
insert into pg_temp._z_out (passo, linha) select '2 depois, antes da recoleta md5 resumo sem investimento', md5((select jsonb_agg(to_jsonb(r) - array['cpl_centavos','cac_centavos','roas','roas_liquido','custo_completo','custo_trafego_centavos','investimento_total_centavos','atualizado_em']) from public.dados_atm_resumo('atm-elaine-1-2026-10') r)::text);
insert into pg_temp._z_out (passo, linha) select '2 depois, antes da recoleta md5 trafego_projeto 75', md5(coalesce((select public.trafego_projeto(75))::text, 'null'));
reset role;
select set_config('request.jwt.claims', '{}', true);

-- recoleta simulada (formato da Edge nova)
insert into pg_temp._z_out (passo, linha) select '3 receber dia', public.trafego_desempenho_receber('[
  {"plataforma":"meta","campanha":"120249566833800372","dia":"2026-10-08","gasto":50.06,"impressoes":886,"cliques_link":0,"cliques_total":12,"leads":null,
   "alcance":772,"frequencia":1.1477,"cliques_saida":null,"landing_page_views":null,"engajamento":363,"video_plays":811,"video_thruplay":92,"video_p25":11,"video_p50":6,"video_p75":4,"video_p100":4},
  {"plataforma":"meta","campanha":"120249566833800372","dia":"2026-10-09","gasto":37.2,"impressoes":548,"cliques_link":0,"cliques_total":7,"leads":null,
   "alcance":464,"frequencia":1.181,"cliques_saida":null,"landing_page_views":null,"engajamento":196,"video_plays":485,"video_thruplay":54,"video_p25":7,"video_p50":1,"video_p75":2,"video_p100":2},
  {"plataforma":"meta","campanha":"120249566833800372","dia":"2026-10-07","gasto":1,"impressoes":1,"cliques_link":0,"alcance":-1}]'::jsonb)::text;
insert into pg_temp._z_out (passo, linha) select '3 receber total', public.trafego_desempenho_total_receber('[
  {"plataforma":"meta","campanha":"120249566833800372","de":"2026-10-08","ate":"2026-10-09","gasto":87.26,"impressoes":1434,"alcance":985,"frequencia":1.4558},
  {"plataforma":"meta","campanha":"nao-existe","de":"2026-10-08","ate":"2026-10-09"}]'::jsonb)::text;
-- formato antigo (Edge de antes): continua aceito, colunas novas ficam nulas
insert into pg_temp._z_out (passo, linha) select '3 formato antigo', public.trafego_desempenho_receber((select jsonb_build_array(jsonb_build_object('plataforma','meta','campanha',c.campanha_externa,'dia',x.dia,'gasto',x.gasto,'impressoes',x.impressoes,'cliques_link',x.cliques_link,'cliques_total',x.cliques_total,'leads',x.leads_plataforma)) from mkt_trafego.desempenho_dia x join mkt_trafego.campanhas c on c.id = x.campanha_id where x.campanha_id <> 8441 order by x.dia desc limit 1))::text;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '4 resumo com trafego', (select jsonb_build_object('leads', leads, 'custo_disparo', custo_disparo_centavos, 'custo_trafego', custo_trafego_centavos, 'investimento', investimento_total_centavos, 'completo', custo_completo, 'cpl', cpl_centavos, 'cac', cac_centavos, 'roas', roas) from public.dados_atm_resumo('atm-elaine-1-2026-10'))::text;
insert into pg_temp._z_out (passo, linha) select '4 trafego total', (public.dados_atm_trafego('atm-elaine-1-2026-10') -> 'total')::text;
insert into pg_temp._z_out (passo, linha) select '4 trafego dias', (public.dados_atm_trafego('atm-elaine-1-2026-10') -> 'dias')::text;
insert into pg_temp._z_out (passo, linha) select '4 trafego campanhas', (public.dados_atm_trafego('atm-elaine-1-2026-10') -> 'campanhas')::text;
insert into pg_temp._z_out (passo, linha) select '4 so 09/10 (periodo parcial)', ((public.dados_atm_trafego('atm-elaine-1-2026-10', '2026-10-09', '2026-10-09') -> 'total') - array['video_p25','video_p50','video_p75','video_p100','cliques_total','cliques_saida','landing_page_views'])::text;
do $t$ begin perform public.dados_atm_trafego('nao-existe');
  insert into pg_temp._z_out (passo, linha) values ('5 chave inexistente', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('5 chave inexistente', sqlstate); end $t$;
do $t$ begin perform * from mkt_trafego.desempenho_total;
  insert into pg_temp._z_out (passo, linha) values ('5 equipe lê desempenho_total', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('5 equipe lê desempenho_total', sqlstate); end $t$;
do $t$ begin perform public.trafego_desempenho_total_receber('[]');
  insert into pg_temp._z_out (passo, linha) values ('5 equipe chama total_receber', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('5 equipe chama total_receber', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000abcd","role":"authenticated"}', true);
set local role authenticated;
do $t$ begin perform public.dados_atm_trafego('atm-elaine-1-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('5 fora da equipe', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('5 fora da equipe', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $t$ begin perform public.dados_atm_trafego('atm-elaine-1-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('5 anon', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('5 anon', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '5 grants', (select string_agg(p.proname || '=' || coalesce(p.proacl::text,'null'), ' ; ' order by 1) from pg_proc p where p.proname in ('dados_atm_resumo','dados_atm_trafego','trafego_desempenho_total_receber','trafego_desempenho_receber'));
-- ===== REVERSÃO =====
-- Reversão de 20261009230000. Numa transação. ANTES: publicar a trafego-meta anterior (sem as colunas novas e sem
-- receberTotais), senão a coleta passa a falhar ao chamar trafego_desempenho_total_receber (a conta não cai: vira totais_erro).
-- A campanha 8441 volta sem projeto. As colunas novas e mkt_trafego.desempenho_total são removidas (dados de alcance/vídeo somem).

drop function if exists public.dados_atm_trafego(text, date, date);
drop function public.dados_atm_resumo(text, date, date);
CREATE FUNCTION public.dados_atm_resumo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text, disparos_qtd integer, disparos_enviados integer, leads integer, grupo_tem_fonte boolean, grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric, custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint, pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint, receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric, atualizado_em timestamp with time zone, periodo_de date, periodo_ate date, leads_teste integer, grupo_teste integer, vendas_teste integer, receita_teste_bruta numeric, grupo_entradas_aproximadas integer, grupo_foto_em timestamp with time zone, grupo_no_grupo integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with disp as (
    -- 20261009210000: e-mail e grupo não têm custo por disparo (custo nulo = sem custo, não falta); só canal pago
    -- (whatsapp_api, sms, ligacao) sem custo deixa o custo incompleto
    select count(*)::int as qtd,
           count(*) filter (where x.custo_centavos is null and x.canal not in ('email', 'grupo'))::int as sem,
           case when count(*) > 0 then coalesce(sum(x.custo_centavos), 0) end::bigint as custo,
           sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
       and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
  ),
  lt as (select * from dados.atm_leads(d.chave) x where x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ld as (select * from lt where not lt.teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim)::int as entradas,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.entrada_aproximada)::int as aprox,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.no_grupo)::int as no_agora,
           (select max(f.concluido_em) from dados.grupo_fotos f join dados.dashboard_grupos dg on dg.id = f.grupo_id
             where dg.chave = d.chave and f.etapa = 'feito') as foto_em,
           count(*) filter (where g.entrou_em is not null and g.saiu_em >= g.entrou_em
                              and g.saiu_em >= v_ini and g.saiu_em < v_fim)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  gt as (
    select count(*)::int as n from dados.v_grupo_pessoas_todos e
     where e.chave = d.chave and e.teste and e.entrou_em >= v_ini and e.entrou_em < v_fim
  ),
  pc as (select y.email from dados.atm_pre_checkout(d.chave) y where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select * from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  txt as (select count(*)::int as n, coalesce(sum(v.valor_bruto) filter (where v.moeda = 'BRL'), 0)::numeric(14,2) as bruta
            from dados.atm_vendas_todas(d.chave) v
           where v.teste and v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ag as (
    select (select count(*)::int from ld) as leads,
           (select count(*)::int from lt where lt.teste) as leads_teste,
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
         now(),
         v_de, v_ate, ag.leads_teste, case when gr.fonte then gt.n end,
         case when k.tem_oferta then txt.n end, case when k.tem_oferta then txt.bruta end,
         case when gr.fonte then gr.aprox end, gr.foto_em, case when gr.fonte then gr.no_agora end
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join gt cross join txt cross join k
   where pr.id = d.projeto_id;
end
$function$;
revoke all on function public.dados_atm_resumo(text, date, date) from public, anon;
grant execute on function public.dados_atm_resumo(text, date, date) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trafego_desempenho_receber(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

update mkt_trafego.campanhas set projeto_id = null, projeto_manual = false, atualizado_em = now()
 where id = 8441 and projeto_id = 75 and projeto_manual;
drop function if exists public.trafego_desempenho_total_receber(jsonb);
drop table if exists mkt_trafego.desempenho_total;
alter table mkt_trafego.desempenho_dia
  drop column if exists alcance, drop column if exists frequencia, drop column if exists cliques_saida,
  drop column if exists landing_page_views, drop column if exists engajamento, drop column if exists video_plays,
  drop column if exists video_thruplay, drop column if exists video_p25, drop column if exists video_p50,
  drop column if exists video_p75, drop column if exists video_p100;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '6 reversao resumo', (select jsonb_build_object('leads', leads, 'custo_disparo', custo_disparo_centavos, 'completo', custo_completo, 'cpl', cpl_centavos, 'cac', cac_centavos, 'roas', roas) from public.dados_atm_resumo('atm-elaine-1-2026-10'))::text;
insert into pg_temp._z_out (passo, linha) select '6 reversao md5 resumo sem investimento', md5((select jsonb_agg(to_jsonb(r) - array['cpl_centavos','cac_centavos','roas','roas_liquido','custo_completo','custo_trafego_centavos','investimento_total_centavos','atualizado_em']) from public.dados_atm_resumo('atm-elaine-1-2026-10') r)::text);
insert into pg_temp._z_out (passo, linha) select '6 reversao md5 trafego_projeto 75', md5(coalesce((select public.trafego_projeto(75))::text, 'null'));
reset role;
select set_config('request.jwt.claims', '{}', true);

insert into pg_temp._z_out (passo, linha) select '6 depois da reversao', jsonb_build_object('trafego', to_regprocedure('public.dados_atm_trafego(text,date,date)') is null, 'total', to_regclass('mkt_trafego.desempenho_total') is null,
  'coluna', not exists (select 1 from information_schema.columns where table_schema='mkt_trafego' and table_name='desempenho_dia' and column_name='alcance'),
  'campanha', (select projeto_id from mkt_trafego.campanhas where id = 8441))::text;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
