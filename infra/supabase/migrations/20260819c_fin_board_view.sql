-- Financeiro: cs.vw_fin_board — base única para o dashboard/kanban financeiro novo.
--
-- NÃO é UNION HM+AURUM. Medido em produção (2026-08-19): cs.vw_fin_contas_receber
-- já tem as 305 linhas com os 41 cards AURUM incluídos, porque cs.vw_hm_financeiro
-- ramifica por ch.produto='AURUM' internamente (CASE em aurum_saldo/pacote_regra/
-- saldo_a_perseguir). O que enganava era o literal 'Holding Masters'::text AS produto
-- na view legada — o dado está certo, só o rótulo mentia. UNION seria trabalho
-- redundante e mais arriscado (duplicaria a lógica que cs.vw_hm_financeiro já tem).
--
-- Herda a correção da 20260819_fix_cancelamento_estagio_hardcoded.sql (estágio de
-- cancelamento resolvido por chave, não por id 28 hardcoded) — esta view lê de
-- cs.vw_fin_contas_receber, então nasce já corrigida.
--
-- Legado cs.vw_fin_contas_receber e a RPC fn_fin_contas_receber(text) continuam
-- de pé, servindo a rota antiga durante a transição (rota de reversão). Corte
-- só depois de 30 dias sem incidente, em migration própria e futura.
--
-- ── Fontes do AURUM (regra dura: nunca em LATERAL por card) ──────────────────
-- saldo_a_pagar já vem correto de v (cs.vw_fin_contas_receber), herdado de
-- cs.vw_hm_financeiro. Esta view NÃO chama fn_aurum_saldo nem cs.vw_aurum_saldo
-- de novo — leria a função pela 2ª vez, é o padrão que derrubou a 0304. Para
-- excecao/excecao_motivo/rotulo_operador/valor_pago/credito (que a view legada
-- não expõe), fazemos LEFT JOIN direto em cs.aurum_pagamento_aluno (TABELA,
-- 35 linhas, sem função embutida) — sem repassar saldo por essa via.
--
-- ── Faixas (precedência 5 → 4 → 3 → 2 → 1, primeira que casa vence) ──────────
-- 1. Sem tratativa    : hm_boleto_gerado, hm_aguardando_pagamento, hm_comprou,
--                       hm_aguardando_retorno
-- 2. Em negociação     : hm_reuniao_agendada, hm_reuniao_finalizada
-- 3. Acordo em curso   : TRANSVERSAL — qualquer estágio COM vencimento não nulo
--                        OU parcelas_pagas > 0 (tem precedência sobre 1 e 2: o
--                        que importa é a promessa datada, não a etapa do pitch)
-- 4. Quitado           : estágios da aba 'ativacao' (cs.estagios.aba)
-- 5. Em risco/perdido  : hm_solicitou_cancelamento, hm_cancelamento, hm_reembolsado
--
-- hm_pagamento_realizado e hm_pagamento_parcelado são espelhos (chave 'derivada'
-- na coluna calculo_situacao — ver 0290/0293) e hoje têm 0 cards; não aparecem
-- em nenhuma lista de chave abaixo de propósito — não são etapa navegável do
-- funil comercial, então não definem faixa própria; caem na regra 3 (têm
-- vencimento/parcelas) ou na 1 por exclusão, como qualquer outro estágio.
--
-- Todas as comparações de estágio são por CHAVE (cs.estagios.chave), nunca por
-- id — é exatamente o bug que o B0 corrigiu (id 28 mudou de dono no renumbering
-- de 18/08). Resolvidas 1x via CTE, não repetidas por linha.
--
-- ── entrou_estagio_em / dias_no_estagio ───────────────────────────────────────
-- Mesmo padrão já usado pelo kanban da ativação (app/api/hm/kanban/route.ts):
-- LATERAL sobre cs.interacoes filtrando tipo='mudanca_estagio', pegando o mais
-- recente por contato_hm_id. cs.interacoes já tem
-- cs_interacoes_contato_hm_idx (contato_hm_id) where contato_hm_id is not null.
-- Esse índice não cobre `tipo` nem ordena por criado_em — o LATERAL faz Index
-- Scan por contato_hm_id + filtro + sort por card (305 execuções). Isolado aqui
-- como LEFT JOIN LATERAL próprio para poder medir o custo incremental no EXPLAIN
-- do B3 separado do resto. Se o custo for alto, é candidato a sair da view (ficar
-- só em fn_fin_ficha, 1 card por vez) — decisão pendente do EXPLAIN.
--
-- ── acao_nome / acao_data (eixo da timeline) ──────────────────────────────────
-- cs.hm_evento_janela é tabela pequena (4 linhas hoje: id, canal, inicio, fim,
-- turma, nota, criado_em). Cruza com a data do pagamento do SINAL
-- (cs.hm_pagamentos categoria='sinal') caindo dentro de [inicio, fim]. nota é o
-- rótulo (mais descritivo que canal), inicio é a data de ordenação. Sem janela
-- correspondente → NULL (não inventa rótulo). Resolvida via CTE (4 linhas,
-- JOIN por intervalo, não por linha do card).

create or replace view cs.vw_fin_board as
with sinal_pago as (
  -- 1 linha por comprador: data do pagamento do sinal (mesmo critério de
  -- cs.vw_fin_contas_receber/sinal, mas só a data, para casar com a janela).
  select distinct on (p.comprador_id)
         p.comprador_id, p.pago_em
    from cs.hm_pagamentos p
   where p.categoria = 'sinal'
   order by p.comprador_id, p.pago_em
), acao as (
  select sp.comprador_id, ev.nota as acao_nome, ev.inicio as acao_data
    from sinal_pago sp
    join cs.hm_evento_janela ev
      on sp.pago_em::date between ev.inicio and ev.fim
), faixa_estagios as (
  -- Resolve as chaves de faixa 1x (não por linha). aba vem de cs.estagios.
  select e.id, e.chave, e.aba
    from cs.estagios e
   where e.evento = 'HM'
)
select
  v.contato_hm_id,
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
  ch.produto as origem,                              -- 'HM' | 'AURUM' (chave, para filtrar)
  case ch.produto when 'AURUM' then 'Aurum' else 'Holding Masters' end as produto,  -- rótulo, para exibir
  v.estagio_id,
  v.estagio_nome,
  v.estagio_aba,
  v.vendedor,
  v.status_financeiro,
  v.pacote,
  v.total_pago_bruto,
  v.total_pago_liquido,
  -- AURUM com excecao=true tem saldo NULL por decisão ("não cobrar"), não por
  -- falta de dado — v.saldo_a_pagar já vem NULL nesse caso via cs.vw_hm_financeiro
  -- / cs.fn_aurum_saldo. Não recalculamos aqui, só repassamos.
  v.saldo_a_pagar,
  v.credito,
  v.pago_pct,
  v.vencimento,
  v.dias_atraso,
  fe5.chave is not null as solicitou_cancelamento_faixa,  -- estágio de risco (faixa 5), distinto de cancelamento_em avulso
  v.solicitou_cancelamento,
  v.cancelamento_em,
  v.cancelamento_efetivado_em,
  v.quitado_em,
  v.reembolso_em,
  v.reembolso_valor,
  v.oferta_codigo,
  v.oferta_enviada_em,
  v.ultimo_pagamento_em,
  -- AURUM: distingue as 2 causas de saldo NULL. HM não tem essas colunas (NULL).
  apa.excecao        as aurum_excecao,
  apa.excecao_motivo as aurum_excecao_motivo,
  apa.situacao        as aurum_situacao,
  case
    when apa.excecao then 'nao_cobrar - ' || coalesce(apa.excecao_motivo, apa.situacao)
    else null
  end as aurum_rotulo_operador,
  apa.valor_pago as aurum_valor_pago,
  apa.credito    as aurum_credito,
  -- Faixa por precedência 5 > 4 > 3 > 2 > 1.
  case
    when fe5.chave is not null then 'em_risco'
    when fe4.aba is not null then 'quitado'
    when v.vencimento is not null or coalesce(v.parcelas_pagas, 0) > 0 then 'acordo_em_curso'
    when fe2.chave is not null then 'em_negociacao'
    else 'sem_tratativa'
  end as faixa,
  me.criado_em as entrou_estagio_em,
  case when me.criado_em is not null
       then (extract(epoch from now() - me.criado_em) / 86400)::int
       else null
  end as dias_no_estagio,
  ac.acao_nome,
  ac.acao_data
from cs.vw_fin_contas_receber v
join cs.contatos_hm ch on ch.id = v.contato_hm_id
left join cs.aurum_pagamento_aluno apa on apa.comprador_id = v.comprador_id and ch.produto = 'AURUM'
left join faixa_estagios fe5 on fe5.id = v.estagio_id and fe5.chave in ('hm_solicitou_cancelamento', 'hm_cancelamento', 'hm_reembolsado')
left join faixa_estagios fe4 on fe4.id = v.estagio_id and fe4.aba = 'ativacao'
left join faixa_estagios fe2 on fe2.id = v.estagio_id and fe2.chave in ('hm_reuniao_agendada', 'hm_reuniao_finalizada')
left join lateral (
  select i.criado_em
    from cs.interacoes i
   where i.contato_hm_id = v.contato_hm_id and i.tipo = 'mudanca_estagio'
   order by i.criado_em desc
   limit 1
) me on true
left join acao ac on ac.comprador_id = v.comprador_id;

comment on view cs.vw_fin_board is
  'Board financeiro unificado HM+AURUM (sem UNION — cs.vw_fin_contas_receber já '
  'traz as duas origens). origem=chave para filtro, produto=rótulo para exibir. '
  'faixa resolvida por chave de estágio (cs.estagios), nunca por id. '
  'Turma default é null=todas (305 cards; filtrar por padrão esconderia a '
  'carteira sem ganho real). '
  'CUSTO MEDIDO (2026-08-19): 165ms / 27.530 buffers para 305 linhas (baseline '
  'da RPC legada era 116ms / 20.921 buffers). Gargalo dominante NÃO é desta '
  'view: cs.vw_hm_financeiro (fonte de v.saldo_a_pagar/credito/etc via '
  'cs.vw_fin_contas_receber) chama cs.fn_hm_prorata em 16 SubPlans distintos '
  'por linha — uma chamada isolada custa ~20ms/4.071 buffers, e os 16 SubPlans '
  'somam ~13.400 dos 27.530 buffers totais (quase metade). É HERDADO, não '
  'introduzido por esta view — não mexer em cs.vw_hm_financeiro para consertar '
  '(é a mesma função que a 0304 mexeu e derrubou o board da ativação com '
  'HTTP 500; GPS e kanban da ativação dependem dela hoje). '
  'Caminho de correção (fora do escopo desta entrega): materializar o pró-rata '
  '(tabela/cache) ou colapsar os 16 SubPlans de fn_hm_prorata num único cálculo '
  'dentro de cs.vw_hm_financeiro. '
  'LIMIAR DE REAVALIAÇÃO: acima de ~1.500 cards isso vira problema real de '
  'verdade e precisa de ação — hoje (305 cards) 165ms numa tela que carrega '
  '1x por abertura (sem polling) é aceitável, e o board substitui 3 chamadas '
  'antigas por 1 só.';
