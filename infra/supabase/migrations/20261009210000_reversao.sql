-- Reversão de 20261009210000: volta dados_atm_resumo e dados_atm_serie_diaria aos corpos de antes
-- (md5 9c7b68b3ec83b304bdd2fb6ba7dd0bd6 e d7a96edb700fc15f50c8ae9b5977c96b). Grants não mudam (create or replace).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

CREATE OR REPLACE FUNCTION public.dados_atm_resumo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
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
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo, sum(x.tamanho_lista)::int as enviados
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

CREATE OR REPLACE FUNCTION public.dados_atm_serie_diaria(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(dia date, leads integer, grupo_entradas integer, grupo_saidas integer, pre_checkout integer, vendas integer, receita_bruta numeric, custo_disparo_centavos bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  if v_de is not null and least(coalesce(v_ate, v_hoje), v_hoje) - v_de > 400 then
    raise exception 'período longo demais para a série (máximo 400 dias)' using errcode = '22023';
  end if;
  return query
  with ld as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_leads(d.chave) x
               where not x.teste and x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ge as (select (g.entrou_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em >= v_ini and g.entrou_em < v_fim),
  gs as (select (g.saiu_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null and g.saiu_em >= g.entrou_em
            and g.saiu_em >= v_ini and g.saiu_em < v_fim),
  pc as (select (y.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_pre_checkout(d.chave) y
          where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select v.dia_aprovado as dia, v.valor_bruto, v.moeda
           from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ds as (select (coalesce(x.enviado_em, x.criado_em) at time zone 'America/Sao_Paulo')::date as dia, x.custo_centavos
           from mkt_mensageria.disparos x
          where x.projeto_id = d.projeto_id and x.arquivado_em is null
            and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim),
  lim as (
    select coalesce(v_de, least((select min(dia) from ld), (select min(dia) from ge), (select min(dia) from pc),
                                (select min(dia) from tx), (select min(dia) from ds))) as de,
           least(coalesce(v_ate, v_hoje), v_hoje) as ate
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
    cross join lateral generate_series(lim.de, lim.ate, interval '1 day') s
   where lim.de is not null and lim.de <= lim.ate
   order by 1;
end
$function$;
