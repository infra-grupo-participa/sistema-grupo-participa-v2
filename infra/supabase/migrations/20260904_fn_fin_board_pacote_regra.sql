-- 20260904: expõe pacote_regra e divergencia_regra no board HM.
--
-- Contexto: cs.vw_hm_financeiro já calcula os dois campos (desde 20260714b).
-- cs.vw_fin_contas_receber já os projeta (desde 20260819h). Só cs.vw_fin_board
-- e fn_fin_board descartavam a coluna no caminho até o frontend — pura
-- projeção ausente, nenhum cálculo novo. Sem isto o card do financeiro não
-- tem como sinalizar quando o valor travado manualmente (pacote_cravado)
-- diverge do calculado por pró-rata (pacote_regra): medido em 2026-09-04,
-- 49 de 309 contas ativas (1 cravado cobrando a mais, 48 com dinheiro na
-- mesa), tolerância de R$ 1 para não confundir com resíduo de arredondamento.
--
-- O cravado SEMPRE prevalece (decisão preexistente, não muda). Este campo é
-- só informativo — mesmo espírito da extensão de 20260820 (reuniao_resultado
-- etc.), que já provou custo zero (81,8 ms / 14.335 buffers, 1 buffer A
-- MENOS que antes).

create or replace view cs.vw_fin_board as
with sinal_pago as (
  select distinct on (p.comprador_id, ch_1.produto) p.comprador_id,
    ch_1.produto,
    p.pago_em
  from cs.hm_pagamentos p
    join cs.contatos_hm ch_1 on ch_1.comprador_id = p.comprador_id
  where p.categoria = 'sinal'::text and cs.fn_hm_pagamento_do_produto(p.oferta_codigo, ch_1.produto)
  order by p.comprador_id, ch_1.produto, p.pago_em
), acao as (
  select sp.comprador_id,
    sp.produto,
    ev.nota as acao_nome,
    ev.inicio as acao_data
  from sinal_pago sp
    join cs.hm_evento_janela ev on ev.produto = sp.produto and sp.pago_em >= ev.inicio and sp.pago_em <= ev.fim
), faixa_estagios as (
  select e.id,
    e.chave,
    e.aba
  from cs.estagios e
  where e.evento = 'HM'::text
)
select v.contato_hm_id,
  v.comprador_id,
  v.aluno_id,
  v.nome,
  v.email,
  v.telefone,
  v.documento,
  v.turma,
  v.turma_origem,
  v.canal,
  v.publico,
  ch.produto as origem,
  case ch.produto
    when 'AURUM'::text then 'Aurum'::text
    else 'Holding Masters'::text
  end as produto,
  v.estagio_id,
  v.estagio_nome,
  v.estagio_aba,
  v.vendedor,
  v.status_financeiro,
  v.pacote,
  v.total_pago_bruto,
  v.total_pago_liquido,
  v.saldo_a_pagar,
  v.credito,
  v.pago_pct,
  v.vencimento,
  v.dias_atraso,
  fe5.chave is not null as solicitou_cancelamento_faixa,
  v.solicitou_cancelamento,
  v.cancelamento_em,
  v.cancelamento_efetivado_em,
  v.quitado_em,
  v.reembolso_em,
  v.reembolso_valor,
  v.oferta_codigo,
  v.oferta_enviada_em,
  v.ultimo_pagamento_em,
  apa.excecao as aurum_excecao,
  apa.excecao_motivo as aurum_excecao_motivo,
  apa.situacao as aurum_situacao,
  case
    when apa.excecao then 'nao_cobrar - '::text || coalesce(apa.excecao_motivo, apa.situacao)
    else null::text
  end as aurum_rotulo_operador,
  apa.valor_pago as aurum_valor_pago,
  apa.credito as aurum_credito,
  case
    when fe5.chave is not null then 'em_risco'::text
    when fe4.aba is not null then 'quitado'::text
    when v.vencimento is not null or coalesce(v.parcelas_pagas, 0) > 0 then 'acordo_em_curso'::text
    when fe2.chave is not null then 'em_negociacao'::text
    else 'sem_tratativa'::text
  end as faixa,
  me.criado_em as entrou_estagio_em,
  case
    when me.criado_em is not null then (extract(epoch from now() - me.criado_em) / 86400::numeric)::integer
    else null::integer
  end as dias_no_estagio,
  ac.acao_nome,
  ac.acao_data,
  v.sinal_bruto,
  v.saldo_pago_bruto,
  ch.reuniao_resultado,
  ch.intencao_pagamento,
  ch.intencao_pagamento_obs,
  ch.reuniao_motivo_tipo,
  ch.reuniao_retomar_em,
  -- 20260904: valor calculado por pró-rata e a diferença contra o cravado.
  -- Só informativo — o cravado (v.pacote acima) continua sendo o que vale.
  v.pacote_regra,
  v.divergencia_regra
from cs.vw_fin_contas_receber v
  join cs.contatos_hm ch on ch.id = v.contato_hm_id
  left join cs.aurum_pagamento_aluno apa on apa.comprador_id = v.comprador_id and ch.produto = 'AURUM'::text
  left join faixa_estagios fe5 on fe5.id = v.estagio_id and (fe5.chave = any (array['hm_solicitou_cancelamento'::text, 'hm_cancelamento'::text, 'hm_reembolsado'::text]))
  left join faixa_estagios fe4 on fe4.id = v.estagio_id and fe4.aba = 'ativacao'::text
  left join faixa_estagios fe2 on fe2.id = v.estagio_id and (fe2.chave = any (array['hm_reuniao_agendada'::text, 'hm_reuniao_finalizada'::text]))
  left join lateral (
    select i.criado_em
    from cs.interacoes i
    where i.contato_hm_id = v.contato_hm_id and i.tipo = 'mudanca_estagio'::text
    order by i.criado_em desc
    limit 1
  ) me on true
  left join acao ac on ac.comprador_id = v.comprador_id and ac.produto = ch.produto;

-- fn_fin_board muda de RETURNS TABLE (2 colunas a mais) — Postgres não
-- permite CREATE OR REPLACE mudar o tipo de retorno, precisa DROP + CREATE.
-- O DROP derruba os grants: reaplicados logo abaixo, idênticos aos
-- originais (só authenticated + service_role, nunca anon/public).
drop function if exists public.fn_fin_board(text, text);

create function public.fn_fin_board(p_turma text default null::text, p_produto text default null::text)
 returns table(origem text, contato_hm_id uuid, comprador_id uuid, aluno_id uuid, nome character varying, email character varying, turma text, turma_origem text, canal text, publico text, produto text, estagio_chave text, estagio_nome text, estagio_aba text, vendedor text, status_financeiro text, faixa text, pacote numeric, total_pago_bruto numeric, total_pago_liquido numeric, sinal_bruto numeric, saldo_pago_bruto numeric, saldo_a_pagar numeric, credito numeric, pago_pct numeric, vencimento date, dias_atraso integer, entrou_estagio_em timestamp with time zone, dias_no_estagio integer, solicitou_cancelamento boolean, cancelamento_em timestamp with time zone, cancelamento_efetivado_em timestamp with time zone, quitado_em timestamp with time zone, reembolso_em timestamp with time zone, reembolso_valor numeric, oferta_codigo text, oferta_enviada_em timestamp with time zone, ultimo_pagamento_em timestamp with time zone, aurum_excecao boolean, aurum_excecao_motivo text, aurum_rotulo_operador text, acao_nome text, acao_data timestamp with time zone, reuniao_resultado text, intencao_pagamento text, intencao_pagamento_obs text, reuniao_motivo_tipo text, reuniao_retomar_em date, pacote_regra numeric, divergencia_regra numeric)
 language sql
 stable security definer
 set search_path to 'public', 'cs'
as $function$
  select
    b.origem, b.contato_hm_id, b.comprador_id, b.aluno_id,
    -- nome/email ficam: são exibidos no card e identificam a dívida.
    -- documento/telefone NÃO saem daqui — só na ficha e no relatório.
    b.nome, b.email,
    b.turma, b.turma_origem, b.canal, b.publico, b.produto,
    e.chave as estagio_chave,
    b.estagio_nome, b.estagio_aba, b.vendedor,
    b.status_financeiro, b.faixa,
    b.pacote, b.total_pago_bruto, b.total_pago_liquido,
    b.sinal_bruto, b.saldo_pago_bruto,
    b.saldo_a_pagar, b.credito, b.pago_pct,
    b.vencimento, b.dias_atraso,
    b.entrou_estagio_em, b.dias_no_estagio,
    b.solicitou_cancelamento, b.cancelamento_em, b.cancelamento_efetivado_em,
    b.quitado_em, b.reembolso_em, b.reembolso_valor,
    b.oferta_codigo, b.oferta_enviada_em, b.ultimo_pagamento_em,
    b.aurum_excecao, b.aurum_excecao_motivo, b.aurum_rotulo_operador,
    b.acao_nome, b.acao_data,
    -- 20260820: o desfecho da reunião (0307/0308 da esteira). Sem isto o card do
    -- financeiro mostra "sem data" e não diz POR QUE — que é a pergunta que o
    -- financeiro faz ao comercial hoje por WhatsApp. Texto do que foi combinado,
    -- NÃO dado de pagamento: nenhuma destas colunas é transação.
    b.reuniao_resultado, b.intencao_pagamento, b.intencao_pagamento_obs,
    b.reuniao_motivo_tipo, b.reuniao_retomar_em,
    -- 20260904: pacote calculado pela régua e a diferença contra o cravado
    -- (b.pacote). Informativo — o cravado continua sendo o que vale para
    -- cobrança. Front decide se mostra sinal, com tolerância de R$ 1.
    b.pacote_regra, b.divergencia_regra
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  where public.gp_pode_ver_financeiro()
    and (p_turma is null or b.turma = p_turma)
    and (p_produto is null or b.origem = p_produto)
  order by b.saldo_a_pagar desc nulls last, b.nome;
$function$;

revoke all on function public.fn_fin_board(text, text) from public;
revoke all on function public.fn_fin_board(text, text) from anon;
grant execute on function public.fn_fin_board(text, text) to authenticated;
