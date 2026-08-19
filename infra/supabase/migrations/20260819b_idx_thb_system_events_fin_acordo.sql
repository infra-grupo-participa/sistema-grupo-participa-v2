-- Indice parcial + por expressao para as remarcacoes de acordo financeiro.
--
-- Contexto: a RPC legada public.fn_fin_contas_receber (20260715_financeiro_
-- comercial_cancelamento_produto.sql) tem uma subquery correlacionada que conta,
-- por card, quantas vezes o vencimento foi trocado em "Acordo de pagamento
-- registrado". Medido: Seq Scan em public.thb_system_events 305 vezes,
-- 5.795 buffers = 28% do custo total da RPC (116 ms / 20.921 buffers).
--
-- fn_fin_board (B3, nova) NAO leva essa coluna -- fica so em fn_fin_ficha (B4),
-- chamada 1x por card aberto, nao 1x por card LISTADO. Este indice cobre as duas
-- rotas (legada e nova) pelo mesmo predicado.
--
-- CONCURRENTLY: nao pode rodar dentro de bloco de transacao implicito do
-- migration runner. Se o runner envolver isto em BEGIN/COMMIT automatico,
-- aplicar via mcp apply_migration com a query isolada (sem wrapper).
--
-- Hoje (2026-08-19) o predicado filtra 0 linhas -- cs.fin_cobrancas/thb_system_events
-- nao tem nenhum evento de "Acordo de pagamento registrado" ainda. O indice parcial
-- cobre o predicado (fonte + titulo), nao o valor -- fica pronto para quando a
-- regua/registro de acordo comecar a gravar.
create index concurrently if not exists thb_system_events_fin_acordo_ix
  on public.thb_system_events ((detalhe->>'contato_hm_id'))
  where fonte = 'financeiro' and titulo = 'Acordo de pagamento registrado';
