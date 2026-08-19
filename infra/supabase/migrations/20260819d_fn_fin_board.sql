-- Financeiro: public.fn_fin_board(p_turma, p_produto) — RPC do board novo.
--
-- APLICADA EM PRODUÇÃO em 2026-08-19 — este arquivo é o registro. A versão
-- aplicada difere da minha proposta original: ao aplicar, foram acrescentadas
-- 6 colunas que a view já calculava e eu tinha deixado de fora por engano
-- (faixa, entrou_estagio_em, dias_no_estagio, aurum_excecao,
-- aurum_excecao_motivo, aurum_rotulo_operador) — sem elas o front teria que
-- reimplementar a regra de faixa em JS, duplicando o que já está no SQL, e
-- NULL silencioso no Aurum é exatamente o modo de falha que já custou caro
-- (ver "duas funções públicas" nas notas de segurança do CNHF). Também
-- corrigido acao_data para timestamptz (cs.hm_evento_janela.inicio é
-- timestamptz; date truncaria) e o revoke endurecido para from public, anon
-- explicitamente (não só from public).
--
-- Wrapper de cs.vw_fin_board (20260819c_fin_board_view.sql). Mesmo padrão de
-- fn_fin_saude (0113): função em public, security definer, search_path
-- 'public','cs', revoke all from public, anon, grant só a authenticated. Gate
-- gp_pode_ver_financeiro() dentro do corpo (não é RLS — cs não é exposto ao
-- PostgREST, é function-level).
--
-- Validado em produção: anon_pode=false, auth_pode=true; select como anon
-- devolve 0 linhas (guard corta, não vaza). EXPLAIN da RPC: 24,8ms/3.681
-- buffers — baixo porque o guard corta antes de varrer; o custo real é o da
-- view (165ms/27.530 buffers, já medido e aceito no comment on view).
--
-- p_turma default NULL = todas. Decisão explícita (não é omissão): são 305
-- cards, a view roda em ~165ms. Filtrar turma por padrão esconderia a
-- carteira inteira sem ganho real de performance — 249 dos 305 cards não têm
-- vencimento e é isso que o financeiro precisa enxergar junto. Reavaliar
-- default quando a base passar de ~1.500 cards.
--
-- p_produto filtra por ORIGEM (chave 'HM'/'AURUM'), nunca por rótulo — é a
-- coluna que se filtra, produto é só exibição.
--
-- NÃO leva ultima_cobranca_em / cobrancas_total / remarcacoes. Essas subqueries
-- correlacionadas em thb_system_events são 28% do custo medido da RPC legada
-- (5.795 de 20.921 buffers, Seq Scan × 305). Ficam só em fn_fin_ficha (chamada
-- 1x por card aberto, não 1x por card LISTADO) — mesmo raciocínio de
-- dias_sem_pagar/inadimplente abaixo: contrato ausente > contrato hardcoded.
--
-- NÃO leva dias_sem_pagar / inadimplente. São colunas REAIS em
-- cs.vw_hm_financeiro (não hipótese), mas cs.vw_fin_contas_receber (fonte de
-- cs.vw_fin_board) não as expõe hoje — trazê-las exigiria JOIN adicional
-- direto em cs.vw_hm_financeiro, o que duplicaria a avaliação dessa view
-- (e os 16 SubPlans de cs.fn_hm_prorata junto, ~13.400 buffers). Fora de
-- escopo aqui: contrato ausente é melhor que contrato com NULL/false
-- hardcoded que nunca muda. Ficam para fn_fin_ficha (1 card por vez, custo
-- irrelevante).
--
-- NÃO leva tags[] nem obs_comercial — o card novo não usa.

drop function if exists public.fn_fin_board(text, text);

create function public.fn_fin_board(p_turma text default null, p_produto text default null)
returns table (
  origem text,
  contato_hm_id uuid,
  comprador_id uuid,
  aluno_id uuid,
  nome character varying,
  email character varying,
  telefone character varying,
  documento character varying,
  turma text,
  turma_origem text,
  canal text,
  publico text,
  produto text,
  estagio_chave text,
  estagio_nome text,
  estagio_aba text,
  vendedor text,
  status_financeiro text,
  faixa text,
  pacote numeric,
  total_pago_bruto numeric,
  total_pago_liquido numeric,
  saldo_a_pagar numeric,
  credito numeric,
  pago_pct numeric,
  vencimento date,
  dias_atraso integer,
  entrou_estagio_em timestamptz,
  dias_no_estagio integer,
  solicitou_cancelamento boolean,
  cancelamento_em timestamptz,
  cancelamento_efetivado_em timestamptz,
  quitado_em timestamptz,
  reembolso_em timestamptz,
  reembolso_valor numeric,
  oferta_codigo text,
  oferta_enviada_em timestamptz,
  ultimo_pagamento_em timestamptz,
  aurum_excecao boolean,
  aurum_excecao_motivo text,
  aurum_rotulo_operador text,
  acao_nome text,
  acao_data timestamptz
)
language sql stable security definer set search_path to 'public', 'cs'
as $$
  select
    b.origem,
    b.contato_hm_id,
    b.comprador_id,
    b.aluno_id,
    b.nome,
    b.email,
    b.telefone,
    b.documento,
    b.turma,
    b.turma_origem,
    b.canal,
    b.publico,
    b.produto,
    -- estagio_chave: não vinha em cs.vw_fin_board (que expõe estagio_id) —
    -- resolvido aqui via cs.estagios para o front não precisar de outra RPC.
    e.chave as estagio_chave,
    b.estagio_nome,
    b.estagio_aba,
    b.vendedor,
    b.status_financeiro,
    b.faixa,
    b.pacote,
    b.total_pago_bruto,
    b.total_pago_liquido,
    b.saldo_a_pagar,
    b.credito,
    b.pago_pct,
    b.vencimento,
    b.dias_atraso,
    b.entrou_estagio_em,
    b.dias_no_estagio,
    b.solicitou_cancelamento,
    b.cancelamento_em,
    b.cancelamento_efetivado_em,
    b.quitado_em,
    b.reembolso_em,
    b.reembolso_valor,
    b.oferta_codigo,
    b.oferta_enviada_em,
    b.ultimo_pagamento_em,
    b.aurum_excecao,
    b.aurum_excecao_motivo,
    b.aurum_rotulo_operador,
    b.acao_nome,
    b.acao_data
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  where public.gp_pode_ver_financeiro()
    and (p_turma is null or b.turma = p_turma)
    and (p_produto is null or b.origem = p_produto)
  order by b.saldo_a_pagar desc nulls last, b.nome;
$$;

revoke all on function public.fn_fin_board(text, text) from public, anon;
grant execute on function public.fn_fin_board(text, text) to authenticated;
