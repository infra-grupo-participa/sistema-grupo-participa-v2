-- APLICADA EM PRODUÇÃO 2026-08-19 — este arquivo é o registro do que rodou.
--
-- BUG DE DINHEIRO: o "já pago" de um card somava pagamentos de OUTRO produto.
--
-- ── Como apareceu ────────────────────────────────────────────────────────────
-- O Marcio viu a tela e mandou print. Na print, "Vania Claudie Thomaz" aparecia
-- em duas colunas (Aurum em "Sem tratativa", HM em "Quitado") — o que está
-- CERTO: desde a migration 0163 a mesma pessoa tem um card por produto. Mas os
-- dois cards exibiam `pago` idêntico (R$ 2.623,52), o que não podia estar certo.
--
-- Razão dela (cs.hm_pagamentos):
--   z391kxd9  sinal        R$   300,00  → HM
--   2mxcjw8t  mensalidade  R$ 1.323,52  → HM
--   qm4lu7py  sinal        R$ 1.000,00  → AURUM
-- O card do Aurum estava exibindo o sinal e a mensalidade do HM como se fossem
-- dele.
--
-- ── A causa ──────────────────────────────────────────────────────────────────
-- A CTE `pg` agregava cs.hm_pagamentos só por comprador_id, sem filtrar por
-- produto. Todas as CTEs derivadas (total, sinal, saldo) herdavam o razão
-- INTEIRO da pessoa e o entregavam a CADA card dela.
--
-- Curiosamente, `saldo_a_pagar` estava CERTO (58.700 vs 13.376) — porque vem de
-- cs.vw_hm_financeiro, que já usa cs.fn_hm_pagamento_do_produto. O roteamento
-- existia e funcionava; só esta view não o usava.
--
-- ── Tamanho do erro (medido antes da correção) ───────────────────────────────
--   33 de 305 cards contaminados
--   R$ 131.095,83 contados a mais
--   EM CASA exibido no rodapé:  R$ 1.593.522,72
--   Razão inteiro (fonte da verdade):  R$ 1.475.426,91
--   → o board mostrava R$ 118 mil A MAIS do que existe no razão.
--
-- ── Depois da correção (conferido) ───────────────────────────────────────────
--   Vania AURUM: R$ 1.000,00 (só o sinal dela)
--   Vania HM:    R$ 1.623,52 (sinal 300 + mensalidade 1.323,52)
--   EM CASA:     R$ 1.462.426,89
--   Razão:       R$ 1.475.426,91
--   Diferença:   R$ 13.000,02 = 2 lançamentos SEM card correspondente
--                (pagamento órfão, achado pré-existente do health-check).
--   A contabilidade fecha exatamente: 1.475.426,91 − 13.000,02 = 1.462.426,89
--
-- ── O que mudou ──────────────────────────────────────────────────────────────
-- `pg` passa a fazer JOIN com cs.contatos_hm e filtrar por
-- cs.fn_hm_pagamento_do_produto(p.oferta_codigo, ch.produto). As CTEs derivadas
-- (total, sinal, saldo) ganham `produto` na chave de agrupamento, e os LEFT JOIN
-- do SELECT final passam a casar por (comprador_id, produto).
--
-- `reembolso` NÃO muda: lê public.compras por status, não o razão, e não tem
-- oferta_codigo confiável para rotear. Limitação herdada já documentada
-- (compras.preco é a PARCELA em compra parcelada — invariante I-1).
--
-- ── Custo ────────────────────────────────────────────────────────────────────
-- EXPLAIN (ANALYZE, BUFFERS) de cs.vw_fin_board:
--   antes: ~165 ms / 27.530 buffers
--   depois: ~204 ms / 29.604 buffers   (+39 ms, +2.074 buffers)
-- O join extra por produto custa isso. Aceito: 39 ms para não exibir R$ 131 mil
-- de dinheiro que não existe. O gargalo dominante segue sendo fn_hm_prorata
-- (16 SubPlans herdados de cs.vw_hm_financeiro), não este join.

create or replace view cs.vw_fin_contas_receber as
 WITH pg AS (
         SELECT p.comprador_id,
            ch.produto,
            p.categoria,
            p.valor AS bruto,
            COALESCE(c.valor_liquido, p.valor) AS liquido,
            p.valor - COALESCE(c.valor_liquido, p.valor) AS taxas,
            p.pago_em,
            p.metodo_pagamento,
            p.transacao,
            p.parcela
           FROM cs.hm_pagamentos p
             JOIN cs.contatos_hm ch ON ch.comprador_id = p.comprador_id
             LEFT JOIN compras c ON c.hotmart_transaction::text = p.transacao
          -- ESTE filtro é a correção: o pagamento só entra no card do produto a
          -- que pertence. Sem ele, o razão inteiro vazava para todos os cards.
          WHERE cs.fn_hm_pagamento_do_produto(p.oferta_codigo, ch.produto)
        ), total AS (
         SELECT pg.comprador_id, pg.produto,
            sum(pg.bruto) AS bruto,
            sum(pg.liquido) AS liquido,
            sum(pg.taxas) AS taxas
           FROM pg
          GROUP BY pg.comprador_id, pg.produto
        ), sinal AS (
         SELECT DISTINCT ON (pg.comprador_id, pg.produto) pg.comprador_id, pg.produto,
            pg.bruto, pg.liquido, pg.taxas, pg.pago_em, pg.metodo_pagamento, pg.transacao
           FROM pg
          WHERE pg.categoria = 'sinal'::text
          ORDER BY pg.comprador_id, pg.produto, pg.pago_em
        ), saldo AS (
         SELECT pg.comprador_id, pg.produto,
            sum(pg.bruto) AS bruto,
            sum(pg.liquido) AS liquido,
            sum(pg.taxas) AS taxas,
            max(pg.pago_em) AS ultimo_pago_em,
            count(*)::integer AS lancamentos,
            max(pg.metodo_pagamento) AS metodo_pagamento
           FROM pg
          WHERE pg.categoria = ANY (ARRAY['saldo'::text, 'compra_cheia'::text, 'mensalidade'::text, 'ajuste'::text])
          GROUP BY pg.comprador_id, pg.produto
        ), reembolso AS (
         SELECT c.comprador_id,
            max(c.atualizado_em) AS em,
            string_agg(DISTINCT c.status::text, ', '::text) AS status,
            sum(COALESCE(c.preco, 0::numeric)) AS valor
           FROM compras c
          WHERE c.status::text = ANY (ARRAY['REFUNDED'::character varying::text, 'CHARGEBACK'::character varying::text, 'PROTEST'::character varying::text])
          GROUP BY c.comprador_id
        ), estagio_cancelamento AS (
         SELECT e.id FROM cs.estagios e
          WHERE e.evento = 'HM'::text AND e.chave = 'hm_solicitou_cancelamento'::text
          LIMIT 1
        )
 SELECT f.contato_hm_id, f.comprador_id, ch.aluno_id,
    cp.nome, cp.email, cp.telefone, cp.documento,
    f.turma, f.turma_origem,
    cs.fn_hm_canal(ch.tags) AS canal,
    f.publico, ch.tags,
    e.nome AS estagio_nome, e.aba AS estagio_aba,
    s.bruto AS sinal_bruto, s.liquido AS sinal_liquido, s.taxas AS sinal_taxas,
    s.pago_em AS sinal_pago_em, s.metodo_pagamento AS sinal_metodo, s.transacao AS sinal_transacao,
    COALESCE(sd.bruto, 0::numeric) AS saldo_pago_bruto,
    COALESCE(sd.liquido, 0::numeric) AS saldo_pago_liquido,
    COALESCE(sd.taxas, 0::numeric) AS saldo_taxas,
    sd.ultimo_pago_em AS saldo_pago_em, sd.metodo_pagamento AS saldo_metodo,
    COALESCE(sd.lancamentos, 0) AS saldo_lancamentos,
    COALESCE(t.bruto, 0::numeric) AS total_pago_bruto,
    COALESCE(t.liquido, 0::numeric) AS total_pago_liquido,
    COALESCE(f.pacote_cravado, f.pacote_regra) AS pacote,
    f.credito, f.saldo_a_perseguir AS saldo_a_pagar, f.pago_pct,
    ch.pagamento_previsto_em AS vencimento,
    ch.acordo, ch.pagamento_meio, ch.pagamento_forma, ch.pagamento_parcelas,
    f.parcelas_pagas, f.parcelas_contratadas, f.valor_parcela,
        CASE
            WHEN ch.pagamento_previsto_em IS NOT NULL AND COALESCE(f.saldo_a_perseguir, 0::numeric) > 0::numeric
            THEN CURRENT_DATE - ch.pagamento_previsto_em
            ELSE NULL::integer
        END AS dias_atraso,
    f.oferta_saldo_codigo AS oferta_codigo,
    o.valor AS oferta_valor, o.link AS oferta_link, o.recorrente AS oferta_recorrente,
    ch.link_saldo_enviado_em AS oferta_enviada_em,
    ch.cancelamento_em, ch.cancelamento_motivo, ch.cancelamento_efetivado_em, ch.quitado_em,
    rb.em AS reembolso_em, rb.status AS reembolso_status, rb.valor AS reembolso_valor,
    f.ultimo_pagamento_em, f.situacao AS situacao_ativacao,
        CASE
            WHEN rb.em IS NOT NULL THEN 'reembolsado'::text
            WHEN ch.cancelamento_efetivado_em IS NOT NULL THEN 'cancelado'::text
            WHEN ch.cancelamento_em IS NOT NULL OR ch.estagio_id = ec.id THEN 'cancelamento_solicitado'::text
            WHEN ch.quitado_em IS NOT NULL OR COALESCE(f.saldo_a_perseguir, 1::numeric) <= 0::numeric THEN 'quitado'::text
            WHEN COALESCE(f.parcelas_pagas, 0) > 0 THEN 'em_pagamento'::text
            WHEN ch.pagamento_previsto_em IS NOT NULL AND ch.pagamento_previsto_em < CURRENT_DATE THEN 'vencido'::text
            WHEN ch.pagamento_previsto_em IS NOT NULL AND ch.pagamento_previsto_em <= (CURRENT_DATE + 30) THEN 'a_vencer'::text
            WHEN ch.pagamento_previsto_em IS NOT NULL THEN 'futuro'::text
            WHEN f.situacao = 'incalculavel'::text THEN 'incalculavel'::text
            WHEN ch.link_saldo_enviado_em IS NOT NULL THEN 'oferta_enviada'::text
            ELSE 'sem_acordo'::text
        END AS status_financeiro,
    f.pacote_regra, f.divergencia_regra, ch.estagio_id,
    'Holding Masters'::text AS produto,
    ch.responsavel AS vendedor,
    ch.reuniao_em, ch.reuniao_resultado, ch.entrevista_em, ch.entrevista_resultado,
    ch.observacoes AS obs_comercial,
    ch.estagio_id = ec.id OR ch.cancelamento_em IS NOT NULL AS solicitou_cancelamento
   FROM cs.vw_hm_financeiro f
     JOIN cs.contatos_hm ch ON ch.id = f.contato_hm_id
     JOIN compradores cp ON cp.id = f.comprador_id
     LEFT JOIN cs.estagios e ON e.id = ch.estagio_id
     -- joins casam TAMBÉM por produto: cada card recebe só o seu dinheiro.
     LEFT JOIN total t ON t.comprador_id = f.comprador_id AND t.produto = ch.produto
     LEFT JOIN sinal s ON s.comprador_id = f.comprador_id AND s.produto = ch.produto
     LEFT JOIN saldo sd ON sd.comprador_id = f.comprador_id AND sd.produto = ch.produto
     LEFT JOIN reembolso rb ON rb.comprador_id = f.comprador_id
     LEFT JOIN cs.hm_ofertas_saldo o ON o.codigo = f.oferta_saldo_codigo
     LEFT JOIN estagio_cancelamento ec ON true;
