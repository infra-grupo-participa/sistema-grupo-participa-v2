-- APLICADA em 14/10/2026 com a versão gravada 20261014150003 (o arquivo se chamava 20261014160200; renomeado conforme o guia 6.3).
-- Reversão de 20261014160200. Só depois de desfeita a carga que usa as colunas (linhas com fonte_tabela).
-- Os CHECKs voltam ao texto vivo de 14/10/2026; se já houver linha com tipo 'resposta' ou fonte/origem 'respondi',
-- o add constraint falha: apagar ou reclassificar essas linhas é decisão do Maestro, não desta reversão.
set local lock_timeout = '5s';
drop view if exists pessoas.vw_oferta;
drop table if exists pessoas.relacoes;
drop index if exists pessoas.eventos_fonte_unico;
drop index if exists pessoas.eventos_evento_idx;
drop index if exists pessoas.eventos_turma_idx;
alter table pessoas.eventos drop constraint if exists eventos_fonte_par_check;
alter table pessoas.eventos drop column if exists evento_id, drop column if exists turma_id,
  drop column if exists fonte_tabela, drop column if exists fonte_id;
alter table pessoas.eventos drop constraint eventos_tipo_check;
alter table pessoas.eventos add constraint eventos_tipo_check check (tipo = any (array['lead', 'mql', 'nao_mql', 'cadastro',
  'compra', 'ativacao', 'crm', 'vinculo', 'mescla', 'mescla_desfeita', 'revisao', 'checkout', 'reembolso', 'pre_checkout']));
alter table pessoas.eventos drop constraint eventos_fonte_check;
alter table pessoas.eventos add constraint eventos_fonte_check check (fonte = any (array['formulario', 'crm', 'importacao',
  'sistema', 'hotmart', 'activecampaign']));
alter table pessoas.identificadores drop constraint identificadores_origem_check;
alter table pessoas.identificadores add constraint identificadores_origem_check check (origem = any (array['formulario', 'crm',
  'importacao', 'hotmart', 'activecampaign']));
