-- APLICADA EM PRODUÇÃO 2026-08-19 — este arquivo é o registro do que rodou.
-- SUCEDE 20260819d_fn_fin_board.sql (que ficou defasado; esta é a versão vigente).
--
-- Duas correções de LGPD vindas da auditoria de segurança do redesign.
--
-- ═══ 1. gp_pode_ver_cpf(): a máscara desce para o SQL ═══════════════════════
--
-- Até aqui, mascararDoc() vivia SÓ na UI (shared/domain/auth/gp-user.ts:53 —
-- podeVerCpf = perfis.pode_ver_cpf_completo OR cargo in ('dev','admin')). O
-- payload da RPC trafegava o documento EM CLARO para quem não tem direito de
-- vê-lo: a máscara era cosmética, contornável por devtools → Network → Preview.
--
-- Existiam gp_pode_ver_financeiro, gp_pode_operar_financeiro, gp_is_admin e
-- gp_pode_editar — mas NENHUM guard de CPF no banco. Esta função fecha a lacuna,
-- espelhando exatamente a regra do front.
--
-- ═══ 2. fn_fin_board deixa de trafegar documento e telefone ═════════════════
--
-- A auditoria apontou o que o EXPLAIN não pega: `documento` (CPF/CNPJ) e
-- `telefone` iam no payload de TODA abertura do board — 305 registros — sem que
-- ui/CardBoard.tsx renderizasse nenhum dos dois. Dado pessoal sem consumidor na
-- tela é custo e risco sem benefício (LGPD Art. 6º, princípio da necessidade).
--
-- Mascarar não bastava: o dado que não é exibido não deve sair do banco.
--
-- Medido em produção: dos 19 perfis ativos com acesso ao financeiro, 15 são
-- admin, 3 dev e 1 gestora. Hoje só 1 pessoa não tem pode_ver_cpf_completo —
-- risco pequeno AGORA. Mas criar um operador com a área 'financeiro' é operação
-- rotineira, e ninguém vai lembrar dessa nuance no dia. A exposição seria de 305
-- CPFs por chamada, extraíveis com um JSON.parse, sem abrir uma única ficha.
--
-- nome e email PERMANECEM: são exibidos no card (CardBoard.tsx:31-33) e o
-- financeiro precisa deles para saber de quem é a dívida.
-- documento/telefone vivem na FICHA (1 card, sob clique, consumidor real em
-- FichaDrawer.tsx:81) e passam por mascararDoc()/gp_pode_ver_cpf().
--
-- Efeito colateral assumido: a coluna "Documento" saiu do relatório
-- (application/montar-relatorio.ts) — o relatório é montado sobre as contas do
-- board, então a coluna sairia sempre vazia. Coluna que mente é pior que coluna
-- ausente. Se o financeiro precisar de documento em massa, o caminho é uma RPC
-- de export própria, com gp_pode_ver_cpf() aplicado no SQL.

create or replace function public.gp_pode_ver_cpf()
returns boolean
language sql stable security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid())
      and p.status = 'ativo'
      and (p.cargo in ('dev','admin') or p.pode_ver_cpf_completo is true)
  );
$$;

revoke all on function public.gp_pode_ver_cpf() from public, anon;
grant execute on function public.gp_pode_ver_cpf() to authenticated;

comment on function public.gp_pode_ver_cpf() is
  'Espelha podeVerCpf de shared/domain/auth/gp-user.ts:53. Existe para mascarar '
  'documento no SQL — a máscara da UI é cosmética e contornável por devtools.';

-- drop necessário: o retorno mudou (documento/telefone saíram).
-- CREATE OR REPLACE não altera tipo/estrutura de retorno (erro 42P13).
drop function if exists public.fn_fin_board(text, text);

create function public.fn_fin_board(p_turma text default null, p_produto text default null)
returns table (
  origem text, contato_hm_id uuid, comprador_id uuid, aluno_id uuid,
  nome character varying, email character varying,
  turma text, turma_origem text, canal text, publico text, produto text,
  estagio_chave text, estagio_nome text, estagio_aba text, vendedor text,
  status_financeiro text, faixa text,
  pacote numeric, total_pago_bruto numeric, total_pago_liquido numeric,
  sinal_bruto numeric, saldo_pago_bruto numeric,
  saldo_a_pagar numeric, credito numeric, pago_pct numeric,
  vencimento date, dias_atraso integer,
  entrou_estagio_em timestamptz, dias_no_estagio integer,
  solicitou_cancelamento boolean, cancelamento_em timestamptz,
  cancelamento_efetivado_em timestamptz, quitado_em timestamptz,
  reembolso_em timestamptz, reembolso_valor numeric,
  oferta_codigo text, oferta_enviada_em timestamptz, ultimo_pagamento_em timestamptz,
  aurum_excecao boolean, aurum_excecao_motivo text, aurum_rotulo_operador text,
  acao_nome text, acao_data timestamptz
)
language sql stable security definer set search_path to 'public', 'cs'
as $$
  select
    b.origem, b.contato_hm_id, b.comprador_id, b.aluno_id,
    -- nome/email ficam: exibidos no card, identificam a dívida.
    -- documento/telefone NÃO saem daqui — só na ficha e sob gp_pode_ver_cpf().
    b.nome, b.email,
    b.turma, b.turma_origem, b.canal, b.publico, b.produto,
    -- estagio_chave: cs.vw_fin_board expõe estagio_id; resolvido aqui para o
    -- front não precisar de outra RPC só para traduzir o id.
    e.chave as estagio_chave,
    b.estagio_nome, b.estagio_aba, b.vendedor,
    b.status_financeiro, b.faixa,
    b.pacote, b.total_pago_bruto, b.total_pago_liquido,
    -- insumos de domain/financeiro.ts::ehReserva() — 177 dos 305 cards são
    -- reserva-só-sinal (R$ 3.296.496,27); sem eles o rodapé diria "0 reservas".
    b.sinal_bruto, b.saldo_pago_bruto,
    b.saldo_a_pagar, b.credito, b.pago_pct,
    b.vencimento, b.dias_atraso,
    b.entrou_estagio_em, b.dias_no_estagio,
    b.solicitou_cancelamento, b.cancelamento_em, b.cancelamento_efetivado_em,
    b.quitado_em, b.reembolso_em, b.reembolso_valor,
    b.oferta_codigo, b.oferta_enviada_em, b.ultimo_pagamento_em,
    -- AURUM: distingue "não cobrar" (excecao, decisão declarada) de "a calcular"
    -- (sem linha em aurum_pagamento_aluno). NULL silencioso é o modo de falha
    -- que esta entrega existe para eliminar.
    b.aurum_excecao, b.aurum_excecao_motivo, b.aurum_rotulo_operador,
    b.acao_nome, b.acao_data
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  where public.gp_pode_ver_financeiro()
    and (p_turma is null or b.turma = p_turma)
    and (p_produto is null or b.origem = p_produto)
  order by b.saldo_a_pagar desc nulls last, b.nome;
$$;

revoke all on function public.fn_fin_board(text, text) from public, anon;
grant execute on function public.fn_fin_board(text, text) to authenticated;

comment on function public.fn_fin_board(text, text) is
  'Board financeiro: 1 chamada traz os cards (HM+AURUM) com faixa, ação de vendas '
  'e tempo no estágio resolvidos. NÃO devolve documento nem telefone — dado '
  'pessoal sem consumidor na tela do board não deve trafegar (LGPD, necessidade); '
  'ambos vivem na ficha (1 card, sob clique) sob gp_pode_ver_cpf(). Agregado por '
  'faixa e os 4 totais do rodapé são calculados no cliente (domain/board.ts, '
  'domain/totais.ts) — filtrar por canal/faixa NÃO dispara query nova. Não leva '
  'ultima_cobranca_em/cobrancas_total/remarcacoes/dias_sem_pagar/inadimplente: '
  'custariam subquery correlacionada por card (28% dos buffers) para exibir zero. '
  'Custo medido: ~165 ms / 27.5k buffers para 305 cards, dominado por '
  'fn_hm_prorata (16 SubPlans herdados de cs.vw_hm_financeiro). Reavaliar acima '
  'de ~1.500 cards.';
