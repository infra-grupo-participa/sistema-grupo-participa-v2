-- APLICADA em 14/10/2026 com a versão gravada 20261014150138 (o arquivo se chamava 20261014160100; renomeado conforme o guia 6.3).
-- Reversão de 20261014160100 (vínculos com fin.eventos e chave das turmas). Reverter antes de 20261014160000.
set local lock_timeout = '5s';
alter table mkt.projetos      drop column if exists evento_id;
alter table public.ht_editions drop column if exists evento_id;
alter table controle.evento   drop column if exists evento_id;
alter table ht.cohorts        drop column if exists evento_id;
drop index if exists public.thb_turmas_chave_key;
alter table public.thb_turmas drop column if exists chave;
