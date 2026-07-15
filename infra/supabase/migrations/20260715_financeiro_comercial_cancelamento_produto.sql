-- Financeiro: comercial visível, cancelamento por kanban e identificador de produto.
--
-- Motivação (medido no banco em 2026-07-15):
--   1. Comercial invisível: responsável/reunião/entrevista/observações já vivem em
--      cs.contatos_hm mas não subiam para o financeiro.
--   2. Cancelamento cego ao kanban: o comercial move a pessoa para o estágio 28
--      "Solicitou Cancelamento" (aba comercial) sem carimbar cancelamento_em.
--      Havia 13 pessoas no estágio 28 e só 1 aparecia como cancelada no financeiro.
--   3. Produto não identificado: tudo é Holding Masters implicitamente; faltava um
--      identificador para diferenciar futuras fontes de receita.
--
-- Nenhuma coluna nova de tabela — tudo derivado. Mesmo padrão das migrations 20260714*:
-- view em cs + RPC SECURITY DEFINER em public com guard gp_pode_ver_financeiro().
--
-- Colunas novas da view entram NO FINAL do SELECT (exigência do CREATE OR REPLACE VIEW,
-- que não permite reordenar/renomear colunas existentes). A RPC seleciona por nome,
-- então a ordem na view é irrelevante para ela.

-- ── View: acrescenta comercial, produto, estágio e flag de cancelamento ──────
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
          WHERE c.status::text = ANY (ARRAY['REFUNDED'::character varying, 'CHARGEBACK'::character varying, 'PROTEST'::character varying]::text[])
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
            -- Passou a disparar pelo kanban (estágio 28), não só pelo timestamp.
            WHEN ch.cancelamento_em IS NOT NULL OR ch.estagio_id = 28 THEN 'cancelamento_solicitado'::text
            WHEN ch.quitado_em IS NOT NULL OR COALESCE(f.saldo_a_perseguir, 1::numeric) <= 0::numeric THEN 'quitado'::text
            WHEN COALESCE(f.parcelas_pagas, 0) > 0 THEN 'em_pagamento'::text
            WHEN ch.pagamento_previsto_em IS NOT NULL AND ch.pagamento_previsto_em < CURRENT_DATE THEN 'vencido'::text
            WHEN ch.pagamento_previsto_em IS NOT NULL THEN 'a_vencer'::text
            WHEN f.situacao = 'incalculavel'::text THEN 'incalculavel'::text
            WHEN ch.link_saldo_enviado_em IS NOT NULL THEN 'oferta_enviada'::text
            ELSE 'sem_acordo'::text
        END AS status_financeiro,
    f.pacote_regra,
    f.divergencia_regra,
    -- ── Colunas novas (ao final, exigência do CREATE OR REPLACE VIEW) ─────────
    ch.estagio_id,
    -- Identificador de produto. Hoje todo o financeiro é Holding Masters; quando
    -- existirem outras fontes de receita, a lógica de atribuição entra aqui.
    'Holding Masters'::text AS produto,
    -- Comercial: espelhado do card da ativação (cs.contatos_hm), sem duplicar dados.
    ch.responsavel AS vendedor,
    ch.reuniao_em,
    ch.reuniao_resultado,
    ch.entrevista_em,
    ch.entrevista_resultado,
    ch.observacoes AS obs_comercial,
    -- Fonte da verdade do "pediu cancelamento": o kanban (estágio 28) OU o timestamp.
    (ch.estagio_id = 28 OR ch.cancelamento_em IS NOT NULL) AS solicitou_cancelamento
   FROM cs.vw_hm_financeiro f
     JOIN cs.contatos_hm ch ON ch.id = f.contato_hm_id
     JOIN compradores cp ON cp.id = f.comprador_id
     LEFT JOIN cs.estagios e ON e.id = ch.estagio_id
     LEFT JOIN total t ON t.comprador_id = f.comprador_id
     LEFT JOIN sinal s ON s.comprador_id = f.comprador_id
     LEFT JOIN saldo sd ON sd.comprador_id = f.comprador_id
     LEFT JOIN reembolso rb ON rb.comprador_id = f.comprador_id
     LEFT JOIN cs.hm_ofertas_saldo o ON o.codigo = f.oferta_saldo_codigo;

-- ── RPC: expõe as novas colunas mantendo o guard de permissão ────────────────
-- DROP necessário: mudar o RETURNS TABLE não é permitido por CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.fn_fin_contas_receber(text);

CREATE FUNCTION public.fn_fin_contas_receber(p_turma text DEFAULT NULL::text)
 RETURNS TABLE(contato_hm_id uuid, comprador_id uuid, aluno_id uuid, nome character varying, email character varying, telefone character varying, documento character varying, turma text, turma_origem text, canal text, publico text, tags text[], estagio_nome text, estagio_aba text, estagio_id smallint, produto text, vendedor text, reuniao_em timestamp with time zone, reuniao_resultado text, entrevista_em timestamp with time zone, entrevista_resultado text, obs_comercial text, solicitou_cancelamento boolean, sinal_bruto numeric, sinal_liquido numeric, sinal_taxas numeric, sinal_pago_em timestamp with time zone, sinal_metodo text, sinal_transacao text, saldo_pago_bruto numeric, saldo_pago_liquido numeric, saldo_taxas numeric, saldo_pago_em timestamp with time zone, saldo_metodo text, saldo_lancamentos integer, total_pago_bruto numeric, total_pago_liquido numeric, pacote numeric, credito numeric, saldo_a_pagar numeric, pago_pct numeric, vencimento date, acordo text, pagamento_meio text, pagamento_forma text, pagamento_parcelas integer, parcelas_pagas integer, parcelas_contratadas integer, valor_parcela numeric, dias_atraso integer, oferta_codigo text, oferta_valor numeric, oferta_link text, oferta_recorrente boolean, oferta_enviada_em timestamp with time zone, cancelamento_em timestamp with time zone, cancelamento_motivo text, cancelamento_efetivado_em timestamp with time zone, quitado_em timestamp with time zone, reembolso_em timestamp with time zone, reembolso_status text, reembolso_valor numeric, ultimo_pagamento_em timestamp with time zone, situacao_ativacao text, status_financeiro text, pacote_regra numeric, divergencia_regra numeric, ultima_cobranca_em timestamp with time zone, cobrancas_total integer, remarcacoes integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'cs'
AS $function$
  select v.contato_hm_id, v.comprador_id, v.aluno_id,
         v.nome, v.email, v.telefone, v.documento,
         v.turma, v.turma_origem, v.canal, v.publico, v.tags,
         v.estagio_nome, v.estagio_aba, v.estagio_id,
         v.produto, v.vendedor, v.reuniao_em, v.reuniao_resultado,
         v.entrevista_em, v.entrevista_resultado, v.obs_comercial,
         v.solicitou_cancelamento,
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
         v.pacote_regra, v.divergencia_regra,
         (select max(fc.quando) from cs.fin_cobrancas fc where fc.contato_hm_id = v.contato_hm_id),
         (select count(*) from cs.fin_cobrancas fc where fc.contato_hm_id = v.contato_hm_id)::int,
         -- remarcações: vezes que o vencimento foi trocado por outro (promessa quebrada/remanejada)
         (select count(*) from public.thb_system_events ev
            where ev.fonte = 'financeiro' and ev.titulo = 'Acordo de pagamento registrado'
              and ev.detalhe->>'contato_hm_id' = v.contato_hm_id::text
              and nullif(ev.detalhe->'antes'->>'vencimento','') is not null
              and coalesce(ev.detalhe->'antes'->>'vencimento','') <> coalesce(ev.detalhe->'depois'->>'vencimento',''))::int
  from cs.vw_fin_contas_receber v
  where public.gp_pode_ver_financeiro()
    and (p_turma is null or v.turma = p_turma)
  order by v.saldo_a_pagar desc nulls last, v.nome;
$function$;

REVOKE ALL ON FUNCTION public.fn_fin_contas_receber(text) FROM public;
GRANT EXECUTE ON FUNCTION public.fn_fin_contas_receber(text) TO authenticated;
