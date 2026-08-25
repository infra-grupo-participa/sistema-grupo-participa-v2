-- =====================================================================
-- 20260820_board_mostra_o_combinado_na_reuniao
--
-- ⚠️ APLICADA EM PRODUCAO 20/08/2026 — este arquivo versiona o que já rodou.
--    Não reaplicar manualmente sem ler a nota de ACL no fim.
--
-- ── O pedido (Marcio, 20/08) ───────────────────────────────────────────────
-- "o financeiro comunica o comercial, que responde informando que já realizou
--  a reunião, mas a data da promessa de pagamento não está no sistema".
-- Contra-lado da trava 0307/0308 do repo da esteira (sistema-disparos-
-- participa, mesmo banco, schema cs): lá o comercial passa a ser OBRIGADO a
-- registrar o desfecho da reunião; aqui o financeiro passa a VER esse
-- desfecho sem precisar perguntar por WhatsApp.
--
-- ── Por que a UI sozinha não bastava ──────────────────────────────────────
-- `application/carregar-board.ts` fixava reuniao_resultado/obs_comercial como
-- `null` porque fn_fin_board nunca trafegou esses campos. A tela do
-- financeiro dizia "sem data" sem dizer POR QUE — que é exatamente a
-- pergunta que gera o telefonema para o comercial.
--
-- ── Custo: zero ───────────────────────────────────────────────────────────
-- O join `cs.contatos_hm ch` JÁ EXISTIA na vw_fin_board (é dele que saem
-- origem/produto). As 5 colunas são projeção pura: sem subquery, sem função
-- nova, sem join novo. Medido com explain (analyze, buffers):
--   antes   81,8 ms / 14.336 buffers
--   depois  81,8 ms / 14.335 buffers
-- As 49 colunas existentes NÃO mudaram de posição — as 5 entram no FIM.
-- (Contrato posicional de `returns table` é frágil: a 0300 já derrubou o
--  board por causa de envelope em view.)
--
-- 🔑 Nenhuma coluna nova é dado de pagamento — são TEXTO do que foi
-- combinado (declaração comercial). A trava `pagamento_so_hotmart` do lado
-- da esteira segue intacta: este board LÊ, não escreve.
-- =====================================================================

-- ── 1) A view expõe o desfecho da reunião ────────────────────────────────
create or replace view cs.vw_fin_board as
 WITH sinal_pago AS (
         SELECT DISTINCT ON (p.comprador_id, ch_1.produto) p.comprador_id,
            ch_1.produto,
            p.pago_em
           FROM cs.hm_pagamentos p
             JOIN cs.contatos_hm ch_1 ON ch_1.comprador_id = p.comprador_id
          WHERE p.categoria = 'sinal'::text AND cs.fn_hm_pagamento_do_produto(p.oferta_codigo, ch_1.produto)
          ORDER BY p.comprador_id, ch_1.produto, p.pago_em
        ), acao AS (
         SELECT sp.comprador_id,
            sp.produto,
            ev.nota AS acao_nome,
            ev.inicio AS acao_data
           FROM sinal_pago sp
             JOIN cs.hm_evento_janela ev ON ev.produto = sp.produto AND sp.pago_em >= ev.inicio AND sp.pago_em <= ev.fim
        ), faixa_estagios AS (
         SELECT e.id,
            e.chave,
            e.aba
           FROM cs.estagios e
          WHERE e.evento = 'HM'::text
        )
 SELECT v.contato_hm_id,
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
    ch.produto AS origem,
        CASE ch.produto
            WHEN 'AURUM'::text THEN 'Aurum'::text
            ELSE 'Holding Masters'::text
        END AS produto,
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
    fe5.chave IS NOT NULL AS solicitou_cancelamento_faixa,
    v.solicitou_cancelamento,
    v.cancelamento_em,
    v.cancelamento_efetivado_em,
    v.quitado_em,
    v.reembolso_em,
    v.reembolso_valor,
    v.oferta_codigo,
    v.oferta_enviada_em,
    v.ultimo_pagamento_em,
    apa.excecao AS aurum_excecao,
    apa.excecao_motivo AS aurum_excecao_motivo,
    apa.situacao AS aurum_situacao,
        CASE
            WHEN apa.excecao THEN 'nao_cobrar - '::text || COALESCE(apa.excecao_motivo, apa.situacao)
            ELSE NULL::text
        END AS aurum_rotulo_operador,
    apa.valor_pago AS aurum_valor_pago,
    apa.credito AS aurum_credito,
        CASE
            WHEN fe5.chave IS NOT NULL THEN 'em_risco'::text
            WHEN fe4.aba IS NOT NULL THEN 'quitado'::text
            WHEN v.vencimento IS NOT NULL OR COALESCE(v.parcelas_pagas, 0) > 0 THEN 'acordo_em_curso'::text
            WHEN fe2.chave IS NOT NULL THEN 'em_negociacao'::text
            ELSE 'sem_tratativa'::text
        END AS faixa,
    me.criado_em AS entrou_estagio_em,
        CASE
            WHEN me.criado_em IS NOT NULL THEN (EXTRACT(epoch FROM now() - me.criado_em) / 86400::numeric)::integer
            ELSE NULL::integer
        END AS dias_no_estagio,
    ac.acao_nome,
    ac.acao_data,
    v.sinal_bruto,
    v.saldo_pago_bruto,
    -- 20260820: o desfecho da reunião (0307/0308 da esteira). Leitura pura do
    -- ch que já estava no FROM — o financeiro precisa VER o que o comercial
    -- combinou para saber se cobra, o que cobra e de quem cobrar.
    ch.reuniao_resultado,
    ch.intencao_pagamento,
    ch.intencao_pagamento_obs,
    ch.reuniao_motivo_tipo,
    ch.reuniao_retomar_em
   FROM cs.vw_fin_contas_receber v
     JOIN cs.contatos_hm ch ON ch.id = v.contato_hm_id
     LEFT JOIN cs.aurum_pagamento_aluno apa ON apa.comprador_id = v.comprador_id AND ch.produto = 'AURUM'::text
     LEFT JOIN faixa_estagios fe5 ON fe5.id = v.estagio_id AND (fe5.chave = ANY (ARRAY['hm_solicitou_cancelamento'::text, 'hm_cancelamento'::text, 'hm_reembolsado'::text]))
     LEFT JOIN faixa_estagios fe4 ON fe4.id = v.estagio_id AND fe4.aba = 'ativacao'::text
     LEFT JOIN faixa_estagios fe2 ON fe2.id = v.estagio_id AND (fe2.chave = ANY (ARRAY['hm_reuniao_agendada'::text, 'hm_reuniao_finalizada'::text]))
     LEFT JOIN LATERAL ( SELECT i.criado_em
           FROM cs.interacoes i
          WHERE i.contato_hm_id = v.contato_hm_id AND i.tipo = 'mudanca_estagio'::text
          ORDER BY i.criado_em DESC
         LIMIT 1) me ON true
     LEFT JOIN acao ac ON ac.comprador_id = v.comprador_id AND ac.produto = ch.produto;

-- ── 2) A RPC repassa as 5 colunas ao frontend ────────────────────────────
-- ⚠️ drop + create (e não create-or-replace): o Postgres recusa
-- create-or-replace que muda o tipo de retorno ("cannot change return type
-- of existing function"). O drop APAGA a ACL — por isso ela é restaurada
-- logo abaixo, com os mesmos grants que existiam antes (capturados de
-- pg_proc.proacl ANTES do drop): authenticated + service_role, e NADA para
-- public/anon (a 20260819f revogou de propósito; um drop sem o revoke
-- explícito devolveria o default aberto do Postgres).
drop function if exists public.fn_fin_board(text, text);

create function public.fn_fin_board(p_turma text default null::text, p_produto text default null::text)
 returns table(origem text, contato_hm_id uuid, comprador_id uuid, aluno_id uuid, nome character varying, email character varying, turma text, turma_origem text, canal text, publico text, produto text, estagio_chave text, estagio_nome text, estagio_aba text, vendedor text, status_financeiro text, faixa text, pacote numeric, total_pago_bruto numeric, total_pago_liquido numeric, sinal_bruto numeric, saldo_pago_bruto numeric, saldo_a_pagar numeric, credito numeric, pago_pct numeric, vencimento date, dias_atraso integer, entrou_estagio_em timestamp with time zone, dias_no_estagio integer, solicitou_cancelamento boolean, cancelamento_em timestamp with time zone, cancelamento_efetivado_em timestamp with time zone, quitado_em timestamp with time zone, reembolso_em timestamp with time zone, reembolso_valor numeric, oferta_codigo text, oferta_enviada_em timestamp with time zone, ultimo_pagamento_em timestamp with time zone, aurum_excecao boolean, aurum_excecao_motivo text, aurum_rotulo_operador text, acao_nome text, acao_data timestamp with time zone, reuniao_resultado text, intencao_pagamento text, intencao_pagamento_obs text, reuniao_motivo_tipo text, reuniao_retomar_em date)
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
    -- 20260820: o desfecho da reunião (0307/0308 da esteira). Sem isto o card
    -- do financeiro mostra "sem data" e não diz POR QUE — que é a pergunta
    -- que o financeiro faz ao comercial hoje por WhatsApp. Texto do que foi
    -- combinado, NÃO dado de pagamento: nenhuma destas colunas é transação.
    b.reuniao_resultado, b.intencao_pagamento, b.intencao_pagamento_obs,
    b.reuniao_motivo_tipo, b.reuniao_retomar_em
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  where public.gp_pode_ver_financeiro()
    and (p_turma is null or b.turma = p_turma)
    and (p_produto is null or b.origem = p_produto)
  order by b.saldo_a_pagar desc nulls last, b.nome;
$function$;

-- ACL idêntica à que existia antes do drop (conferida em pg_proc.proacl).
revoke all on function public.fn_fin_board(text, text) from public;
revoke all on function public.fn_fin_board(text, text) from anon;
grant execute on function public.fn_fin_board(text, text) to authenticated;
grant execute on function public.fn_fin_board(text, text) to service_role;

-- ── Verificação rodada em 20/08 após aplicar ─────────────────────────────
--   cs.vw_fin_board .............. 49 → 54 colunas, 305 linhas (inalterado)
--   ACL de fn_fin_board .......... postgres=X, authenticated=X, service_role=X
--                                  (idêntica à anterior; anon/public ausentes)
--   165 cards trazem reuniao_resultado · 20 trazem a observação do combinado
--   explain(analyze,buffers) ..... 81,8 ms / 14.335 buffers (era 14.336)
