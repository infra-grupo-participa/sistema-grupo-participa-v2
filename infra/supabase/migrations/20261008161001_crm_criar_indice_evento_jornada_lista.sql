-- 20261008161001: índices em crm.evento_jornada para a leitura por lista do ActiveCampaign e por campanha do SendFlow
--
-- STATUS: ESCRITA, NÃO APLICADA. Arquivo próprio e FORA DE TRANSAÇÃO (create index concurrently não roda dentro de
-- begin/commit; não usar o modo "aplicar" do aplica_sql.py, que embrulha em transação: rodar cada comando avulso).
-- Opcional: hoje a tabela tem 24.374 linhas (13 MB, dois dias de webhook) e o seq scan custa pouco; vira necessário
-- quando ela crescer (cresce ~10 mil linhas por dia, quase tudo 'update' do AC).
--
-- POR QUE: dados.pre_checkout (presencial) e dados.leads_todos (ATM) filtram por lista; dados.v_grupo_eventos filtra
--   por fonte 'sendflow' e tag. Nenhum índice existente cobre essas colunas.
-- PARA VOLTAR: drop index concurrently if exists crm.evento_jornada_lista_idx;
--              drop index concurrently if exists crm.evento_jornada_sendflow_tag_idx;

create index concurrently if not exists evento_jornada_lista_idx
  on crm.evento_jornada (lista, ocorreu_em) where lista is not null;

create index concurrently if not exists evento_jornada_sendflow_tag_idx
  on crm.evento_jornada (tag, ocorreu_em) where fonte = 'sendflow';
