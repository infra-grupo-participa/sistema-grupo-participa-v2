-- 20260928p — Aba "Análise" do Faturamento (pedido do João, 27/09/2026: "lógicas de econometria… soluções inteligentes
-- que façam sentido para auxiliar o financeiro"). Escolhidas por ele: dinheiro já contratado, previsão com faixa,
-- dependência de eventos e crescimento real. Previsão e crescimento são calculados na tela sobre fn_fin_hotmart_faturamento;
-- aqui ficam as duas contas que precisam do banco. Só leitura.
--
-- 1) fn_fin_contratado(familia): dinheiro que JÁ ESTÁ VENDIDO e ainda vai entrar, por mês (próximos 12), por fonte:
--    * 'parcelado'  — parcelamento da Hotmart (HOTMART_INSTALLMENTS): contrato = e-mail × oferta; faltam
--                     (parcelas − maior parcela paga); valor = a última parcela paga; uma por mês a partir da última.
--                     "em_risco" = contrato com parcela atrasada/em aberto posterior à última paga, ou sem pagar há 45+ dias
--                     (medido 27/09: 40 contratos em curso; 17 com parcela aberta de fato; 9 atrasos já quitados NÃO contam).
--                     Parcela vencida e não paga entra no mês corrente.
--    * 'assinatura' — assinatura com mensalidade paga nos últimos 35 dias e sem atraso: a última mensalidade, nos
--                     próximos 3 meses (recorrente, pode ser cancelada — a tela diz isso).
--    * 'combinado'  — saldo do board com vencimento futuro combinado (acordo), de quem NÃO tem parcelado Hotmart em
--                     curso (senão o mesmo dinheiro contaria duas vezes). Só HM/AURUM.
-- 2) fn_fin_faturamento_por_acao(familia): faturamento dentro da janela de cada ação de fin.acoes (20260928n).

create or replace function public.fn_fin_contratado(p_familia text default 'HM')
returns table (mes date, fonte text, valor numeric, pessoas int, em_risco numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with plano as (
    select t.email, t.oferta_codigo,
           max(t.parcelas) parcelas,
           max(t.recorrencia) filter (where t.grupo = 'pago') paga,
           max(t.dia_aprovado) filter (where t.grupo = 'pago') ult,
           (array_agg(t.valor_oferta order by t.recorrencia desc) filter (where t.grupo = 'pago'))[1] valor,
           max(t.recorrencia) filter (where t.grupo in ('atrasado','em_aberto')) rec_aberta
      from fin.vw_transacoes t
     where t.familia = p_familia and t.oferta_modo like 'HOTMART_INSTALLMENTS%' and t.recorrencia is not null
     group by t.email, t.oferta_codigo
  ), parc as (
    -- parcela vencida e não paga não some: a fila começa no mês corrente (o dinheiro ainda é devido).
    select (greatest(date_trunc('month', p.ult), date_trunc('month', v_hoje::timestamp) - interval '1 month')
            + make_interval(months => g))::date mes, p.valor, p.email,
           -- risco = parcela em aberto/atrasada DEPOIS da última paga, ou plano sem pagamento há 45+ dias
           (coalesce(p.rec_aberta > p.paga, false) or p.ult < v_hoje - 45) risco
      from plano p
      cross join lateral generate_series(1, greatest(p.parcelas - p.paga, 0)) g
     where p.paga is not null and p.parcelas > p.paga and not exists (
       select 1 from fin.vw_transacoes x where x.email = p.email and x.oferta_codigo = p.oferta_codigo and x.grupo = 'estornado')
  ), ass as (
    select t.email, (array_agg(t.valor_oferta order by t.aprovado_em desc))[1] valor, max(t.dia_aprovado) ult
      from fin.vw_transacoes t
     where t.familia = p_familia and t.oferta_modo = 'SUBSCRIPTION' and t.grupo = 'pago'
     group by t.email
    having max(t.dia_aprovado) >= v_hoje - 35
  ), ass_ok as (
    select a.* from ass a
     where not exists (select 1 from fin.vw_transacoes x where x.email = a.email and x.familia = p_familia
                        and x.oferta_modo = 'SUBSCRIPTION' and x.grupo = 'atrasado' and x.dia_pedido >= v_hoje - 60)
  ), assm as (
    select (date_trunc('month', v_hoje) + make_interval(months => g))::date mes, a.valor, a.email
      from ass_ok a cross join generate_series(1, 3) g
  ), comb as (
    select date_trunc('month', b.vencimento)::date mes, b.saldo_a_pagar valor, lower(trim(b.email)) email
      from cs.vw_fin_board b
     where b.origem = p_familia and b.vencimento >= v_hoje and coalesce(b.saldo_a_pagar, 0) > 0.5
       and b.status_financeiro not in ('cancelado','reembolsado','quitado')
       and not exists (select 1 from plano p where p.email = lower(trim(b.email)) and p.parcelas > coalesce(p.paga, 0))
  ), tudo as (
    select x.mes, 'parcelado'::text fonte, x.valor, x.email, x.risco from parc x
    union all select y.mes, 'assinatura', y.valor, y.email, false from assm y
    union all select z.mes, 'combinado', z.valor, z.email, false from comb z
  )
  select t.mes, t.fonte, round(sum(t.valor), 2), count(distinct t.email)::int,
         round(coalesce(sum(t.valor) filter (where t.risco), 0), 2)
    from tudo t
   where t.mes >= date_trunc('month', v_hoje)::date and t.mes < (date_trunc('month', v_hoje) + interval '12 months')::date
   group by t.mes, t.fonte
   order by t.mes, t.fonte;
end $$;
revoke all on function public.fn_fin_contratado(text) from public, anon;
grant execute on function public.fn_fin_contratado(text) to authenticated;

create or replace function public.fn_fin_faturamento_por_acao(p_familia text default 'HM')
returns table (acao text, canal text, inicio date, fim date, dias int, vendas int, compradores int, bruto numeric, liquido numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select a.nome, a.canal, (a.inicio at time zone 'America/Sao_Paulo')::date,
         (least(a.fim, now()) at time zone 'America/Sao_Paulo')::date,
         greatest(1, ceil(extract(epoch from (least(a.fim, now()) - a.inicio)) / 86400)::int),
         count(t.transacao)::int, count(distinct t.email)::int,
         coalesce(sum(t.valor_oferta), 0), coalesce(sum(t.liquido), 0)
    from fin.acoes a
    left join fin.vw_transacoes t
      on t.familia = p_familia and t.grupo = 'pago'
     and t.aprovado_em >= a.inicio and t.aprovado_em < least(a.fim, now())
   where a.produto = case when p_familia = 'AURUM' then 'AURUM' else 'HM' end
     and a.inicio is not null and a.fim is not null
   group by a.id, a.nome, a.canal, a.inicio, a.fim
   order by a.inicio;
end $$;
revoke all on function public.fn_fin_faturamento_por_acao(text) from public, anon;
grant execute on function public.fn_fin_faturamento_por_acao(text) to authenticated;
