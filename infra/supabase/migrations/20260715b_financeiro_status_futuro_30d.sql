-- Financeiro: janela de 30 dias para "A vencer" + novo status "Futuro".
--
-- Motivação: até aqui, QUALQUER vencimento futuro (mesmo daqui a 6 meses) caía
-- em 'a_vencer'. O negócio quer "A vencer" = o que vence nos próximos 30 dias;
-- vencimentos além disso passam a ser 'futuro' (horizonte programado), sem sumir
-- da base. Nada de vencido/quitado/cancelado muda.
--
-- Único ponto alterado no CASE de status_financeiro (as demais colunas são idênticas
-- à definição vigente — CREATE OR REPLACE VIEW não permite reordenar/renomear):
--   vencido    : pagamento_previsto_em < hoje                     (inalterado)
--   a_vencer   : hoje <= pagamento_previsto_em <= hoje + 30 dias  (NOVO: janela 30d)
--   futuro     : pagamento_previsto_em > hoje + 30 dias           (NOVO bucket)
--
-- status_financeiro é coluna text derivada (sem enum/CHECK), então 'futuro' não
-- exige migração de tipo. A RPC public.fn_fin_contas_receber seleciona por nome e
-- não muda.

CREATE OR REPLACE VIEW cs.vw_fin_contas_receber AS
 WITH pg AS (
         SELECT p.comprador_id,
            p.categoria,
            p.valor AS bruto,
            COALESCE(c.valor_liquido, p.valor) AS liquido,
            p.valor - COALESCE(c.valor_liquido, p.valor) AS taxas,
            p.pago_em,
            p.metodo_pagamento,
            p.transacao,
            p.parcela
           FROM cs.hm_pagamentos p
             LEFT JOIN compras c ON c.hotmart_transaction::text = p.transacao
        ), total AS (
         SELECT pg.comprador_id,
            sum(pg.bruto) AS bruto,
            sum(pg.liquido) AS liquido,
            sum(pg.taxas) AS taxas
           FROM pg
          GROUP BY pg.comprador_id
        ), sinal AS (
         SELECT DISTINCT ON (pg.comprador_id) pg.comprador_id,
            pg.bruto,
            pg.liquido,
            pg.taxas,
            pg.pago_em,
            pg.metodo_pagamento,
            pg.transacao
           FROM pg
          WHERE pg.categoria = 'sinal'::text
          ORDER BY pg.comprador_id, pg.pago_em
        ), saldo AS (
         SELECT pg.comprador_id,
            sum(pg.bruto) AS bruto,
            sum(pg.liquido) AS liquido,
            sum(pg.taxas) AS taxas,
            max(pg.pago_em) AS ultimo_pago_em,
            count(*)::integer AS lancamentos,
            max(pg.metodo_pagamento) AS metodo_pagamento
           FROM pg
          WHERE pg.categoria = ANY (ARRAY['saldo'::text, 'compra_cheia'::text, 'mensalidade'::text, 'ajuste'::text])
          GROUP BY pg.comprador_id
        ), reembolso AS (
         SELECT c.comprador_id,
            max(c.atualizado_em) AS em,
            string_agg(DISTINCT c.status::text, ', '::text) AS status,
            sum(COALESCE(c.preco, 0::numeric)) AS valor
           FROM compras c
          WHERE c.status::text = ANY (ARRAY['REFUNDED'::character varying::text, 'CHARGEBACK'::character varying::text, 'PROTEST'::character varying::text])
          GROUP BY c.comprador_id
        )
 SELECT f.contato_hm_id,
    f.comprador_id,
    ch.aluno_id,
    cp.nome,
    cp.email,
    cp.telefone,
    cp.documento,
    f.turma,
    f.turma_origem,
    cs.fn_hm_canal(ch.tags) AS canal,
    f.publico,
    ch.tags,
    e.nome AS estagio_nome,
    e.aba AS estagio_aba,
    s.bruto AS sinal_bruto,
    s.liquido AS sinal_liquido,
    s.taxas AS sinal_taxas,
    s.pago_em AS sinal_pago_em,
    s.metodo_pagamento AS sinal_metodo,
    s.transacao AS sinal_transacao,
    COALESCE(sd.bruto, 0::numeric) AS saldo_pago_bruto,
    COALESCE(sd.liquido, 0::numeric) AS saldo_pago_liquido,
    COALESCE(sd.taxas, 0::numeric) AS saldo_taxas,
    sd.ultimo_pago_em AS saldo_pago_em,
    sd.metodo_pagamento AS saldo_metodo,
    COALESCE(sd.lancamentos, 0) AS saldo_lancamentos,
    COALESCE(t.bruto, 0::numeric) AS total_pago_bruto,
    COALESCE(t.liquido, 0::numeric) AS total_pago_liquido,
    COALESCE(f.pacote_cravado, f.pacote_regra) AS pacote,
    f.credito,
    f.saldo_a_perseguir AS saldo_a_pagar,
    f.pago_pct,
    ch.pagamento_previsto_em AS vencimento,
    ch.acordo,
    ch.pagamento_meio,
    ch.pagamento_forma,
    ch.pagamento_parcelas,
    f.parcelas_pagas,
    f.parcelas_contratadas,
    f.valor_parcela,
        CASE
            WHEN ch.pagamento_previsto_em IS NOT NULL AND COALESCE(f.saldo_a_perseguir, 0::numeric) > 0::numeric THEN CURRENT_DATE - ch.pagamento_previsto_em
            ELSE NULL::integer
        END AS dias_atraso,
    f.oferta_saldo_codigo AS oferta_codigo,
    o.valor AS oferta_valor,
    o.link AS oferta_link,
    o.recorrente AS oferta_recorrente,
    ch.link_saldo_enviado_em AS oferta_enviada_em,
    ch.cancelamento_em,
    ch.cancelamento_motivo,
    ch.cancelamento_efetivado_em,
    ch.quitado_em,
    rb.em AS reembolso_em,
    rb.status AS reembolso_status,
    rb.valor AS reembolso_valor,
    f.ultimo_pagamento_em,
    f.situacao AS situacao_ativacao,
        CASE
            WHEN rb.em IS NOT NULL THEN 'reembolsado'::text
            WHEN ch.cancelamento_efetivado_em IS NOT NULL THEN 'cancelado'::text
            WHEN ch.cancelamento_em IS NOT NULL OR ch.estagio_id = 28 THEN 'cancelamento_solicitado'::text
            WHEN ch.quitado_em IS NOT NULL OR COALESCE(f.saldo_a_perseguir, 1::numeric) <= 0::numeric THEN 'quitado'::text
            WHEN COALESCE(f.parcelas_pagas, 0) > 0 THEN 'em_pagamento'::text
            WHEN ch.pagamento_previsto_em IS NOT NULL AND ch.pagamento_previsto_em < CURRENT_DATE THEN 'vencido'::text
            WHEN ch.pagamento_previsto_em IS NOT NULL AND ch.pagamento_previsto_em <= CURRENT_DATE + 30 THEN 'a_vencer'::text
            WHEN ch.pagamento_previsto_em IS NOT NULL THEN 'futuro'::text
            WHEN f.situacao = 'incalculavel'::text THEN 'incalculavel'::text
            WHEN ch.link_saldo_enviado_em IS NOT NULL THEN 'oferta_enviada'::text
            ELSE 'sem_acordo'::text
        END AS status_financeiro,
    f.pacote_regra,
    f.divergencia_regra,
    ch.estagio_id,
    'Holding Masters'::text AS produto,
    ch.responsavel AS vendedor,
    ch.reuniao_em,
    ch.reuniao_resultado,
    ch.entrevista_em,
    ch.entrevista_resultado,
    ch.observacoes AS obs_comercial,
    ch.estagio_id = 28 OR ch.cancelamento_em IS NOT NULL AS solicitou_cancelamento
   FROM cs.vw_hm_financeiro f
     JOIN cs.contatos_hm ch ON ch.id = f.contato_hm_id
     JOIN compradores cp ON cp.id = f.comprador_id
     LEFT JOIN cs.estagios e ON e.id = ch.estagio_id
     LEFT JOIN total t ON t.comprador_id = f.comprador_id
     LEFT JOIN sinal s ON s.comprador_id = f.comprador_id
     LEFT JOIN saldo sd ON sd.comprador_id = f.comprador_id
     LEFT JOIN reembolso rb ON rb.comprador_id = f.comprador_id
     LEFT JOIN cs.hm_ofertas_saldo o ON o.codigo = f.oferta_saldo_codigo;
