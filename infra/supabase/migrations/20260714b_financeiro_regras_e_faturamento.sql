-- Financeiro HM — 2ª leva (sobre 20260714_financeiro_hm.sql).
-- Fidelidade às regras de produto da ativação + aba de Faturamento Diário.
--
-- Aplicada em produção em 2026-07-14.
--
-- Mudanças de regra (auditadas contra o schema `cs` da ativação):
--  1. Categoria 'ajuste' passa a contar no saldo pago (é caixa, antes só entrava no total).
--  2. Estado 'incalculavel' ganha status próprio — aluno da base sem insumo p/ calcular o
--     crédito pró-rata: saldo é DESCONHECIDO, não zero. Antes sumia em 'sem_acordo'.
--  3. Expõe divergencia_regra (cravado − régua: + cobrando a mais, − dinheiro na mesa) e
--     pacote_regra (o que a régua manda).

create or replace view cs.vw_fin_contas_receber as
with pg as (
  select p.comprador_id, p.categoria,
         p.valor                                      as bruto,
         coalesce(c.valor_liquido, p.valor)           as liquido,
         p.valor - coalesce(c.valor_liquido, p.valor) as taxas,
         p.pago_em, p.metodo_pagamento, p.transacao, p.parcela
  from cs.hm_pagamentos p
  left join public.compras c on c.hotmart_transaction = p.transacao
),
total as (
  select comprador_id, sum(bruto) as bruto, sum(liquido) as liquido, sum(taxas) as taxas
  from pg group by comprador_id
),
sinal as (
  select distinct on (comprador_id)
         comprador_id, bruto, liquido, taxas, pago_em, metodo_pagamento, transacao
  from pg where categoria = 'sinal'
  order by comprador_id, pago_em
),
saldo as (
  -- inclui 'ajuste' — acerto sem lastro na Hotmart, mas é caixa que entrou
  select comprador_id,
         sum(bruto) as bruto, sum(liquido) as liquido, sum(taxas) as taxas,
         max(pago_em) as ultimo_pago_em, count(*)::int as lancamentos,
         max(metodo_pagamento) as metodo_pagamento
  from pg where categoria in ('saldo','compra_cheia','mensalidade','ajuste')
  group by comprador_id
),
reembolso as (
  select c.comprador_id, max(c.atualizado_em) as em,
         string_agg(distinct c.status::text, ', ') as status,
         sum(coalesce(c.preco,0)) as valor
  from public.compras c
  where c.status in ('REFUNDED','CHARGEBACK','PROTEST')
  group by c.comprador_id
)
select
  f.contato_hm_id, f.comprador_id, ch.aluno_id,
  cp.nome, cp.email, cp.telefone, cp.documento,
  f.turma, f.turma_origem, cs.fn_hm_canal(ch.tags) as canal, f.publico, ch.tags,
  e.nome as estagio_nome, e.aba as estagio_aba,

  s.bruto as sinal_bruto, s.liquido as sinal_liquido, s.taxas as sinal_taxas,
  s.pago_em as sinal_pago_em, s.metodo_pagamento as sinal_metodo, s.transacao as sinal_transacao,

  coalesce(sd.bruto, 0)   as saldo_pago_bruto,
  coalesce(sd.liquido, 0) as saldo_pago_liquido,
  coalesce(sd.taxas, 0)   as saldo_taxas,
  sd.ultimo_pago_em       as saldo_pago_em,
  sd.metodo_pagamento     as saldo_metodo,
  coalesce(sd.lancamentos, 0) as saldo_lancamentos,

  coalesce(t.bruto, 0)   as total_pago_bruto,
  coalesce(t.liquido, 0) as total_pago_liquido,
  coalesce(f.pacote_cravado, f.pacote_regra) as pacote,
  f.credito, f.saldo_a_perseguir as saldo_a_pagar, f.pago_pct,

  ch.pagamento_previsto_em as vencimento,
  ch.acordo, ch.pagamento_meio, ch.pagamento_forma, ch.pagamento_parcelas,
  f.parcelas_pagas, f.parcelas_contratadas, f.valor_parcela,
  case when ch.pagamento_previsto_em is not null and coalesce(f.saldo_a_perseguir,0) > 0
       then (current_date - ch.pagamento_previsto_em) end as dias_atraso,

  f.oferta_saldo_codigo as oferta_codigo,
  o.valor as oferta_valor, o.link as oferta_link, o.recorrente as oferta_recorrente,
  ch.link_saldo_enviado_em as oferta_enviada_em,

  ch.cancelamento_em, ch.cancelamento_motivo, ch.cancelamento_efetivado_em, ch.quitado_em,
  rb.em as reembolso_em, rb.status as reembolso_status, rb.valor as reembolso_valor,

  f.ultimo_pagamento_em, f.situacao as situacao_ativacao,

  case
    when rb.em is not null                        then 'reembolsado'
    when ch.cancelamento_efetivado_em is not null then 'cancelado'
    when ch.cancelamento_em is not null           then 'cancelamento_solicitado'
    when ch.quitado_em is not null
      or coalesce(f.saldo_a_perseguir, 1) <= 0    then 'quitado'
    when coalesce(f.parcelas_pagas,0) > 0         then 'em_pagamento'
    when ch.pagamento_previsto_em is not null
     and ch.pagamento_previsto_em < current_date  then 'vencido'
    when ch.pagamento_previsto_em is not null     then 'a_vencer'
    -- aluno da base sem insumo p/ calcular o crédito: saldo é DESCONHECIDO, não zero
    when f.situacao = 'incalculavel'              then 'incalculavel'
    when ch.link_saldo_enviado_em is not null     then 'oferta_enviada'
    else 'sem_acordo'
  end as status_financeiro,

  f.pacote_regra,
  f.divergencia_regra

from cs.vw_hm_financeiro f
join cs.contatos_hm ch     on ch.id = f.contato_hm_id
join public.compradores cp on cp.id = f.comprador_id
left join cs.estagios e    on e.id = ch.estagio_id
left join total t          on t.comprador_id = f.comprador_id
left join sinal s          on s.comprador_id = f.comprador_id
left join saldo sd         on sd.comprador_id = f.comprador_id
left join reembolso rb     on rb.comprador_id = f.comprador_id
left join cs.hm_ofertas_saldo o on o.codigo = f.oferta_saldo_codigo;

-- RPC de contas a receber: +pacote_regra, +divergencia_regra
drop function if exists public.fn_fin_contas_receber(text);
create function public.fn_fin_contas_receber(p_turma text default null)
returns table (
  contato_hm_id uuid, comprador_id uuid, aluno_id uuid,
  nome varchar, email varchar, telefone varchar, documento varchar,
  turma text, turma_origem text, canal text, publico text, tags text[],
  estagio_nome text, estagio_aba text,
  sinal_bruto numeric, sinal_liquido numeric, sinal_taxas numeric,
  sinal_pago_em timestamptz, sinal_metodo text, sinal_transacao text,
  saldo_pago_bruto numeric, saldo_pago_liquido numeric, saldo_taxas numeric,
  saldo_pago_em timestamptz, saldo_metodo text, saldo_lancamentos int,
  total_pago_bruto numeric, total_pago_liquido numeric,
  pacote numeric, credito numeric, saldo_a_pagar numeric, pago_pct numeric,
  vencimento date, acordo text, pagamento_meio text, pagamento_forma text,
  pagamento_parcelas int, parcelas_pagas int, parcelas_contratadas int,
  valor_parcela numeric, dias_atraso int,
  oferta_codigo text, oferta_valor numeric, oferta_link text,
  oferta_recorrente boolean, oferta_enviada_em timestamptz,
  cancelamento_em timestamptz, cancelamento_motivo text,
  cancelamento_efetivado_em timestamptz, quitado_em timestamptz,
  reembolso_em timestamptz, reembolso_status text, reembolso_valor numeric,
  ultimo_pagamento_em timestamptz, situacao_ativacao text, status_financeiro text,
  pacote_regra numeric, divergencia_regra numeric
)
language sql stable security definer set search_path to 'public','cs'
as $$
  select v.contato_hm_id, v.comprador_id, v.aluno_id,
         v.nome, v.email, v.telefone, v.documento,
         v.turma, v.turma_origem, v.canal, v.publico, v.tags,
         v.estagio_nome, v.estagio_aba,
         v.sinal_bruto, v.sinal_liquido, v.sinal_taxas,
         v.sinal_pago_em, v.sinal_metodo, v.sinal_transacao,
         v.saldo_pago_bruto, v.saldo_pago_liquido, v.saldo_taxas,
         v.saldo_pago_em, v.saldo_metodo, v.saldo_lancamentos,
         v.total_pago_bruto, v.total_pago_liquido,
         v.pacote, v.credito, v.saldo_a_pagar, v.pago_pct,
         v.vencimento, v.acordo, v.pagamento_meio, v.pagamento_forma,
         v.pagamento_parcelas, v.parcelas_pagas, v.parcelas_contratadas,
         v.valor_parcela, v.dias_atraso,
         v.oferta_codigo, v.oferta_valor, v.oferta_link,
         v.oferta_recorrente, v.oferta_enviada_em,
         v.cancelamento_em, v.cancelamento_motivo,
         v.cancelamento_efetivado_em, v.quitado_em,
         v.reembolso_em, v.reembolso_status, v.reembolso_valor,
         v.ultimo_pagamento_em, v.situacao_ativacao, v.status_financeiro,
         v.pacote_regra, v.divergencia_regra
  from cs.vw_fin_contas_receber v
  where public.gp_pode_ver_financeiro()
    and (p_turma is null or v.turma = p_turma)
  order by v.saldo_a_pagar desc nulls last, v.nome;
$$;
revoke execute on function public.fn_fin_contas_receber(text) from public;
grant execute on function public.fn_fin_contas_receber(text) to authenticated;

-- Faturamento diário do HM: uma linha por dia (regime de caixa — pago_em da razão).
-- Bruto = pago; líquido = caiu na conta; quebra por categoria. Base da aba "planilha
-- que se atualiza dia após dia".
create or replace function public.fn_fin_faturamento_diario(p_turma text default null)
returns table (
  dia date, lancamentos int, bruto numeric, liquido numeric, taxas numeric,
  sinal numeric, saldo numeric, mensalidade numeric, compra_cheia numeric,
  ajuste numeric, alunos int
)
language sql stable security definer set search_path to 'public','cs'
as $$
  select
    p.pago_em::date,
    count(*)::int,
    round(sum(p.valor), 2),
    round(sum(coalesce(c.valor_liquido, p.valor)), 2),
    round(sum(p.valor - coalesce(c.valor_liquido, p.valor)), 2),
    round(sum(p.valor) filter (where p.categoria = 'sinal'), 2),
    round(sum(p.valor) filter (where p.categoria = 'saldo'), 2),
    round(sum(p.valor) filter (where p.categoria = 'mensalidade'), 2),
    round(sum(p.valor) filter (where p.categoria = 'compra_cheia'), 2),
    round(sum(p.valor) filter (where p.categoria = 'ajuste'), 2),
    count(distinct p.comprador_id)::int
  from cs.hm_pagamentos p
  left join public.compras c   on c.hotmart_transaction = p.transacao
  left join cs.contatos_hm ch  on ch.comprador_id = p.comprador_id
  where public.gp_pode_ver_financeiro()
    and (p_turma is null or ch.turma = p_turma)
  group by p.pago_em::date
  order by p.pago_em::date desc;
$$;
revoke execute on function public.fn_fin_faturamento_diario(text) from public;
grant execute on function public.fn_fin_faturamento_diario(text) to authenticated;
