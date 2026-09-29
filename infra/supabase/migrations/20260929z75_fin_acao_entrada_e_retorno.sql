-- 20260929z75 — Card do board mostra a ação de ENTRADA e a ação em que a pessoa VOLTOU
--
-- Por quê: o card tinha um campo de ação só (fin.vw_acao_card.acao_nome = ação de
-- entrada). Caso real: aluno entrou no HT30 com sinal R$ 697 (11/08) e em 28/09 gerou
-- boleto HM cheio R$ 15.000 pelo link da Imersão HT32. O card dizia só "HT30" e a
-- recompra ficava invisível. Agora: "Entrou por HT30" (acao_*) + "Voltou em Imersão
-- HT32" (voltou_*).
--
-- Regra do "voltou": a transação MAIS RECENTE da pessoa (mesmos e-mails via
-- fin.identidade), da família do card (HM: produto 5064314), grupo pago/em_aberto/
-- atrasado, categoria sinal/compra_cheia/diferenca (hm_product_catalog), não recorrente
-- (recorrencia 1), oferta_modo <> SUBSCRIPTION, dos últimos 90 dias, que não é a
-- transação de entrada e é posterior a ela. Sobre data e sck dessa transação roda a
-- MESMA regra de ação (link de venda > dia do evento > comercial > janela). voltou_*
-- só vem preenchido quando o nome resultante difere de acao_nome.
-- fin.acao_card_manual continua valendo só para a ENTRADA (acao_*), como na z74.
--
-- Forma: as transações candidatas são lidas UMA vez (CTE cand, serve entrada e
-- retorno); os 3 LATERAL da regra rodam UMA vez sobre as duas linhas (papel
-- entrada/retorno) e são pivotados no SELECT final. Colunas antigas da view: mesmas,
-- mesma ordem, mesmas expressões; as 4 novas vão no fim.
--
-- fn_fin_board: RETURNS TABLE ganha voltou_nome, voltou_data, voltou_regra no fim.
-- Tipo de retorno muda => drop + create (corpo copiado do VIVO de 29/09, com o filtro
-- de gêmeos em array() intacto) + revoke/grant na mesma migration.
--
-- Reversão (migration de volta, numa transação):
--   1. drop function public.fn_fin_board(text,text);
--   2. drop view fin.vw_acao_card;  -- create or replace NÃO remove colunas
--      create view fin.vw_acao_card as <texto integral da z74>;
--      (antes do drop: conferir em pg_depend/pg_rewrite se outra view lê fin.vw_acao_card;
--       o GRANT da view some com o drop — reaplicar o que pg_class.relacl mostrar hoje)
--   3. create function public.fn_fin_board(...) com o corpo vivo de 29/09 (sem voltou_*)
--      + revoke all ... from public, anon; grant execute ... to authenticated, service_role.
-- Nenhum dado é gravado por esta migration: reverter não perde nada.
--
-- Escala: ~384 cards. cand = transações da família para os e-mails desses cards
-- (antes a mesma leitura era feita dentro de primeira); regra passa de ~384 para
-- ~384 + nº de cards com retorno (dezenas) execuções dos 3 LATERAL.
-- Meta: explain (analyze) de select * from fin.vw_acao_card <= ~135 ms (base 122 ms).

create or replace view fin.vw_acao_card as
 WITH card AS (
         SELECT b_1.contato_hm_id,
            b_1.origem,
            lower(TRIM(BOTH FROM b_1.email)) AS email,
            ch.criado_em AS entrada
           FROM cs.vw_fin_board b_1
             JOIN cs.contatos_hm ch ON ch.id = b_1.contato_hm_id
        ), emails AS (
         SELECT c.contato_hm_id,
            COALESCE(substr(i2.no, 3), c.email) AS email
           FROM card c
             LEFT JOIN fin.identidade i ON i.no = ('e:'::text || c.email)
             LEFT JOIN fin.identidade i2 ON i2.pessoa_chave = i.pessoa_chave AND i2.no ~~ 'e:%'::text
        ), cand AS (
         -- uma leitura de fin.vw_transacoes por (card, e-mail); marca se a transação
         -- serve de entrada (critério idêntico ao da z74) e/ou de retorno.
         SELECT c.contato_hm_id,
            c.origem,
            t.transacao,
            t.aprovado_em,
            t.dia_aprovado,
            t.origem_sck,
            t.migrado,
            t.categoria,
            t.grupo,
            t.entrada_ok,
            t.retorno_ok
           FROM card c
             JOIN emails e ON e.contato_hm_id = c.contato_hm_id
             JOIN LATERAL ( SELECT x.transacao,
                    COALESCE(x.aprovado_em, x.pedido_em) AS aprovado_em,
                    COALESCE(x.dia_aprovado, x.dia_pedido) AS dia_aprovado,
                    x.origem_sck,
                    c.origem = 'HM'::text AND COALESCE(x.dia_aprovado, x.dia_pedido) < '2026-06-25'::date AS migrado,
                    cat.categoria,
                    x.grupo,
                        CASE
                            WHEN c.origem = 'HM'::text THEN x.produto_id = '5064314'::text AND (COALESCE(cat.categoria, ''::text) <> ALL (ARRAY['renovacao'::text, 'reserva'::text])) AND (COALESCE(x.dia_aprovado, x.dia_pedido) >= '2026-06-25'::date OR x.grupo = 'pago'::text)
                            ELSE x.grupo = 'pago'::text
                        END AS entrada_ok,
                    COALESCE((c.origem <> 'HM'::text OR x.produto_id = '5064314'::text)
                        AND (x.grupo = ANY (ARRAY['pago'::text, 'em_aberto'::text, 'atrasado'::text]))
                        AND (cat.categoria = ANY (ARRAY['sinal'::text, 'compra_cheia'::text, 'diferenca'::text]))
                        AND COALESCE(x.recorrencia, 1) = 1
                        AND x.oferta_modo IS DISTINCT FROM 'SUBSCRIPTION'::text
                        AND COALESCE(x.aprovado_em, x.pedido_em) >= (now() - '90 days'::interval), false) AS retorno_ok
                   FROM fin.vw_transacoes x
                     LEFT JOIN public.hm_product_catalog cat ON cat.offer_code = x.oferta_codigo
                  WHERE x.email = e.email AND x.familia = c.origem) t ON true
          WHERE t.entrada_ok OR t.retorno_ok
        ), primeira AS (
         SELECT DISTINCT ON (t.contato_hm_id) t.contato_hm_id,
            t.transacao,
            t.aprovado_em,
            t.dia_aprovado,
            t.origem_sck,
            t.migrado
           FROM cand t
          WHERE t.entrada_ok
          ORDER BY t.contato_hm_id, (COALESCE(t.origem = 'HM'::text AND NOT t.migrado, false)) DESC, (t.grupo = ANY (ARRAY['pago'::text, 'estornado'::text, 'em_aberto'::text, 'atrasado'::text])) DESC, (COALESCE(t.origem <> 'HM'::text AND (t.categoria = ANY (ARRAY['sinal'::text, 'compra_cheia'::text])), false)) DESC, (t.dia_aprovado >= '2026-01-01'::date) DESC, t.aprovado_em
        ), base AS (
         SELECT c.contato_hm_id,
            c.origem,
            c.email,
            c.entrada,
            p.transacao,
            p.aprovado_em,
            p.dia_aprovado,
            p.origem_sck,
            COALESCE(p.migrado, false) AS migrado,
            COALESCE(p.aprovado_em, c.entrada) AS quando,
            COALESCE(p.origem_sck ~~* '%comercial%'::text OR p.origem_sck ~~* '%jonathan%'::text, false) AS comercial
           FROM card c
             LEFT JOIN primeira p ON p.contato_hm_id = c.contato_hm_id
        ), retorno AS (
         SELECT DISTINCT ON (b.contato_hm_id) b.contato_hm_id,
            b.origem,
            t.transacao,
            t.aprovado_em AS quando,
            t.origem_sck
           FROM base b
             JOIN cand t ON t.contato_hm_id = b.contato_hm_id
          WHERE t.retorno_ok AND t.transacao IS DISTINCT FROM b.transacao AND (b.aprovado_em IS NULL OR t.aprovado_em > b.aprovado_em)
          ORDER BY b.contato_hm_id, t.aprovado_em DESC, t.transacao DESC
        ), evento AS (
         SELECT 'entrada'::text AS papel,
            b.contato_hm_id,
            b.origem,
            b.quando,
            b.origem_sck,
            b.comercial,
            b.transacao
           FROM base b
        UNION ALL
         SELECT 'retorno'::text AS papel,
            r.contato_hm_id,
            r.origem,
            r.quando,
            r.origem_sck,
            COALESCE(r.origem_sck ~~* '%comercial%'::text OR r.origem_sck ~~* '%jonathan%'::text, false) AS comercial,
            r.transacao
           FROM retorno r
        ), regra AS (
         SELECT ev.papel,
            ev.contato_hm_id,
            ev.quando,
            ev.comercial,
            ev.transacao,
            s.nome AS s_nome,
            s.inicio AS s_inicio,
            s.canal AS s_canal,
            j.nome AS j_nome,
            j.inicio AS j_inicio,
            j.canal AS j_canal,
            d.nome AS d_nome,
            d.inicio AS d_inicio,
            d.canal AS d_canal
           FROM evento ev
             LEFT JOIN LATERAL ( SELECT a.nome,
                    a.inicio,
                    a.canal
                   FROM fin.acoes a
                  WHERE a.produto = ev.origem AND a.sck_regex IS NOT NULL AND ev.origem_sck ~* a.sck_regex
                  ORDER BY a.prioridade, a.id
                 LIMIT 1) s ON true
             LEFT JOIN LATERAL ( SELECT a.nome,
                    a.inicio,
                    a.canal,
                    a.turma
                   FROM fin.acoes a
                  WHERE a.produto = ev.origem AND a.inicio IS NOT NULL AND a.fim IS NOT NULL AND ev.quando >= a.inicio AND ev.quando < a.fim
                  ORDER BY a.prioridade, a.id
                 LIMIT 1) j ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(ae.nome, e.nome) AS nome,
                    (COALESCE(e.carrinho_inicio, e.inicio)::timestamp without time zone AT TIME ZONE 'America/Sao_Paulo'::text) AS inicio,
                    COALESCE(ae.canal,
                        CASE e.categoria
                            WHEN 'jornada'::text THEN 'Jornada'::text
                            WHEN 'holding_total'::text THEN 'Holding Total'::text
                            WHEN 'certificacao'::text THEN 'Holding Total'::text
                            WHEN 'live_hm'::text THEN 'Live Direto ao Ponto'::text
                            WHEN 'clinica'::text THEN 'Clínica'::text
                            WHEN 'imersao'::text THEN 'Imersão'::text
                            WHEN 'encontro_thb'::text THEN 'Encontro THB'::text
                            WHEN 'aurum_plus'::text THEN 'Aurum+'::text
                            WHEN 'congresso'::text THEN 'Congresso'::text
                            WHEN 'diamantes'::text THEN 'Diamantes'::text
                            WHEN 'residencia'::text THEN 'Residência'::text
                            WHEN 'workshop'::text THEN 'Residência'::text
                            WHEN 'lancamento_cnhf'::text THEN 'CNHF'::text
                            ELSE e.categoria
                        END) AS canal
                   FROM fin.eventos e
                     LEFT JOIN LATERAL ( SELECT a.nome,
                            a.canal
                           FROM fin.acoes a
                          WHERE a.evento_id = e.id AND a.produto = ev.origem
                          ORDER BY a.prioridade, a.id
                         LIMIT 1) ae ON true
                  WHERE e.setor = 'educacao'::text AND NOT (ev.origem = 'HM'::text AND (e.categoria = ANY (ARRAY['aurum_plus'::text, 'diamantes'::text]))) AND (e.venda_ate - COALESCE(e.carrinho_inicio, e.inicio)) <= 10 AND (ev.quando AT TIME ZONE 'America/Sao_Paulo'::text)::date >= COALESCE(e.carrinho_inicio, e.inicio) AND (ev.quando AT TIME ZONE 'America/Sao_Paulo'::text)::date <= e.venda_ate
                  ORDER BY (e.venda_ate - COALESCE(e.carrinho_inicio, e.inicio)), e.inicio DESC
                 LIMIT 1) d ON true
        ), saida AS (
         SELECT b.contato_hm_id,
                CASE
                    WHEN am.nome IS NOT NULL THEN am.nome
                    WHEN b.migrado THEN 'Migrados (HM R$ 15 mil antes de 25/06/2026)'::text
                    ELSE COALESCE(ra.s_nome, ra.d_nome,
                    CASE
                        WHEN b.comercial THEN 'Comercial (venda direta)'::text
                        ELSE NULL::text
                    END, ra.j_nome, 'Base (fora de evento)'::text)
                END AS acao_nome,
            COALESCE(am.inicio, ra.s_inicio, ra.d_inicio,
                CASE
                    WHEN b.comercial THEN b.quando
                    ELSE NULL::timestamp with time zone
                END, ra.j_inicio, b.quando) AS acao_data,
                CASE
                    WHEN am.nome IS NOT NULL THEN 'ajuste manual: '::text || m.motivo
                    WHEN b.migrado THEN ('migrado: comprou o HM R$ 15 mil antes do Programa ('::text || COALESCE(ra.s_nome, ra.d_nome, ra.j_nome, 'fora de evento'::text)) || ')'::text
                    WHEN ra.s_nome IS NOT NULL THEN 'link de venda'::text
                    WHEN ra.d_nome IS NOT NULL AND b.aprovado_em IS NULL THEN 'data de entrada no board (dia do evento)'::text
                    WHEN ra.d_nome IS NOT NULL THEN 'dia do evento'::text
                    WHEN b.comercial THEN 'link do comercial'::text
                    WHEN ra.j_nome IS NOT NULL AND b.aprovado_em IS NULL THEN 'data de entrada no board'::text
                    WHEN ra.j_nome IS NOT NULL THEN 'depois do evento (turma)'::text
                    WHEN b.aprovado_em IS NULL THEN 'sem compra paga'::text
                    ELSE 'fora de evento'::text
                END AS acao_regra,
            COALESCE(am.canal, ra.s_canal, ra.d_canal,
                CASE
                    WHEN b.comercial THEN 'Comercial'::text
                    ELSE NULL::text
                END, ra.j_canal, 'Base (fora de evento)'::text) AS acao_canal,
            b.dia_aprovado AS captado_em,
            b.origem_sck AS captado_sck,
                CASE
                    WHEN rr.contato_hm_id IS NOT NULL THEN COALESCE(rr.s_nome, rr.d_nome,
                    CASE
                        WHEN rr.comercial THEN 'Comercial (venda direta)'::text
                        ELSE NULL::text
                    END, rr.j_nome, 'Base (fora de evento)'::text)
                    ELSE NULL::text
                END AS r_nome,
            COALESCE(rr.s_inicio, rr.d_inicio,
                CASE
                    WHEN rr.comercial THEN rr.quando
                    ELSE NULL::timestamp with time zone
                END, rr.j_inicio, rr.quando) AS r_data,
                CASE
                    WHEN rr.contato_hm_id IS NULL THEN NULL::text
                    WHEN rr.s_nome IS NOT NULL THEN 'link de venda'::text
                    WHEN rr.d_nome IS NOT NULL THEN 'dia do evento'::text
                    WHEN rr.comercial THEN 'link do comercial'::text
                    WHEN rr.j_nome IS NOT NULL THEN 'depois do evento (turma)'::text
                    ELSE 'fora de evento'::text
                END AS r_regra,
            rr.transacao AS r_transacao
           FROM base b
             LEFT JOIN fin.acao_card_manual m ON m.contato_hm_id = b.contato_hm_id
             LEFT JOIN fin.acoes am ON am.id = m.acao_id
             LEFT JOIN regra ra ON ra.contato_hm_id = b.contato_hm_id AND ra.papel = 'entrada'::text
             LEFT JOIN regra rr ON rr.contato_hm_id = b.contato_hm_id AND rr.papel = 'retorno'::text
        )
 SELECT o.contato_hm_id,
    o.acao_nome,
    o.acao_data,
    o.acao_regra,
    o.acao_canal,
    o.captado_em,
    o.captado_sck,
        CASE
            WHEN o.r_nome IS DISTINCT FROM o.acao_nome THEN o.r_nome
            ELSE NULL::text
        END AS voltou_nome,
        CASE
            WHEN o.r_nome IS DISTINCT FROM o.acao_nome THEN o.r_data
            ELSE NULL::timestamp with time zone
        END AS voltou_data,
        CASE
            WHEN o.r_nome IS DISTINCT FROM o.acao_nome THEN o.r_regra
            ELSE NULL::text
        END AS voltou_regra,
        CASE
            WHEN o.r_nome IS DISTINCT FROM o.acao_nome THEN o.r_transacao
            ELSE NULL::text
        END AS voltou_transacao
   FROM saida o;

-- create or replace preserva o ACL; reafirma o padrão de n/z7/z11/n2 (view só via funções definer).
revoke all on fin.vw_acao_card from public, anon, authenticated;

-- ─── fn_fin_board: 3 colunas novas no fim (corpo VIVO de 29/09) ─────────────────
drop function if exists public.fn_fin_board(text, text);

create function public.fn_fin_board(p_turma text default null::text, p_produto text default null::text)
 RETURNS TABLE(origem text, contato_hm_id uuid, comprador_id uuid, aluno_id uuid, nome character varying, email character varying, turma text, turma_origem text, canal text, publico text, produto text, estagio_chave text, estagio_nome text, estagio_aba text, vendedor text, status_financeiro text, faixa text, pacote numeric, total_pago_bruto numeric, total_pago_liquido numeric, sinal_bruto numeric, saldo_pago_bruto numeric, saldo_a_pagar numeric, credito numeric, pago_pct numeric, vencimento date, dias_atraso integer, entrou_estagio_em timestamp with time zone, dias_no_estagio integer, solicitou_cancelamento boolean, cancelamento_em timestamp with time zone, cancelamento_efetivado_em timestamp with time zone, quitado_em timestamp with time zone, reembolso_em timestamp with time zone, reembolso_valor numeric, oferta_codigo text, oferta_enviada_em timestamp with time zone, ultimo_pagamento_em timestamp with time zone, aurum_excecao boolean, aurum_excecao_motivo text, aurum_rotulo_operador text, acao_nome text, acao_data timestamp with time zone, reuniao_resultado text, intencao_pagamento text, intencao_pagamento_obs text, reuniao_motivo_tipo text, reuniao_retomar_em date, pacote_regra numeric, divergencia_regra numeric, acao_regra text, captado_em date, captado_sck text, voltou_nome text, voltou_data timestamp with time zone, voltou_regra text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'cs'
AS $function$
  select
    b.origem, b.contato_hm_id, b.comprador_id, b.aluno_id,
    fin.nome_do_card(b.nome, b.email, alu.nome)::character varying, b.email,
    coalesce(tu.turma, b.turma), b.turma_origem,
    case when b.canal is null or b.canal = 'Não classificado' then coalesce(a.acao_canal, b.canal) else b.canal end,
    b.publico, b.produto,
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
    a.acao_nome, a.acao_data,
    b.reuniao_resultado, b.intencao_pagamento, b.intencao_pagamento_obs,
    b.reuniao_motivo_tipo, b.reuniao_retomar_em,
    b.pacote_regra, b.divergencia_regra,
    a.acao_regra, a.captado_em, a.captado_sck,
    a.voltou_nome, a.voltou_data, a.voltou_regra
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  left join fin.vw_acao_card a on a.contato_hm_id = b.contato_hm_id
  left join fin.vw_turma_origem_card tu on tu.contato_hm_id = b.contato_hm_id
  left join public.thb_alunos alu on alu.id = b.aluno_id
  where coalesce(public.gp_pode_ver_financeiro(), false)
    and (p_turma is null or coalesce(tu.turma, b.turma) = p_turma)
    and (p_produto is null or b.origem = p_produto)
    -- card gêmeo (z37/z49): cadastro com alias para outro cadastro que já tem card do mesmo produto.
    -- Array de propósito (InitPlan): subconsulta aqui reavalia a view linha a linha (15 s medidos).
    and not (b.contato_hm_id = any (array(
      select cx.id from cs.hm_comprador_alias al
        join cs.contatos_hm cx on cx.comprador_id = al.comprador_id
        join cs.contatos_hm cc on cc.comprador_id = al.canonico_id and cc.produto = cx.produto)))
  order by b.saldo_a_pagar desc nulls last, b.nome;
$function$;

revoke all on function public.fn_fin_board(text, text) from public, anon;
grant execute on function public.fn_fin_board(text, text) to authenticated, service_role;
