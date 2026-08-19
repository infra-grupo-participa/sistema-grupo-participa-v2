-- APLICADA EM PRODUÇÃO em 2026-08-19 — este arquivo é o registro.
--
-- Índice de apoio ao LATERAL de entrou_estagio_em em cs.vw_fin_board
-- (20260819c_fin_board_view.sql). O índice existente
-- cs_interacoes_contato_hm_idx (contato_hm_id) where contato_hm_id is not null
-- não cobre `tipo` nem ordena por `criado_em` — o plano fazia Bitmap Heap Scan
-- com 1.795 heap blocks (2.405 buffers) para achar, por card, a última
-- interação tipo='mudanca_estagio'.
--
-- Medido: aplicar este índice virou Index Only Scan.
--   ANTES: Bitmap Heap Scan ... Heap Blocks: exact=1795 ... Buffers: shared hit=2405
--   DEPOIS: Index Only Scan using cs_interacoes_mudanca_estagio_ix ...
--           Heap Fetches: 91 ... Buffers: shared hit=696 read=6
-- −1.700 buffers, −27 ms no custo total de cs.vw_fin_board.
--
-- Parcial (where tipo='mudanca_estagio') porque só essa fatia importa para o
-- LATERAL — cobre 942 de 6.486 linhas de cs.interacoes (14,5% da tabela).
-- (contato_hm_id, criado_em desc) porque a query busca "a mais recente por
-- contato_hm_id" — Index Only Scan não precisa mais ordenar nem tocar o heap
-- na maioria dos casos.
create index if not exists cs_interacoes_mudanca_estagio_ix
  on cs.interacoes (contato_hm_id, criado_em desc)
  where contato_hm_id is not null and tipo = 'mudanca_estagio';
