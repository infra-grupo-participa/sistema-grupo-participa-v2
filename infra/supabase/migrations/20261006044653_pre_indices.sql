-- 20261006c (pré): índices das fontes da jornada que a F5 lê por pessoa. Tabelas de OUTRAS equipes (controle, respondi):
-- combinar com o dono antes. Rodar ANTES da 20261006c_crm_f5_integracoes.sql, FORA de transação (create index
-- concurrently não trava a escrita). Mesmo padrão da 20261005r_pre_indice_compradores.sql.
--
-- STATUS: APLICADO em 06/10/2026 antes da migration 20261006044653 (um create index concurrently por chamada, fora de
-- transação; os dois conferidos com indisvalid = true). O 3º (origem_sck) NÃO foi criado. A guarda da 20261006c confere os dois primeiros (expressão exata) e aborta se faltarem.
--
-- Medido em 06/10/2026 (só SELECT):
--   controle.unnichat_evento: 7.728 linhas, 7.727 com e-mail em payload->contact->email, nenhum índice de pessoa
--     (só recebido_em). Último evento 08/09: tabela parada, o índice não pesa em escrita.
--   respondi.respostas: 22.103 linhas, 3.369 sem e-mail, 796 delas com telefone que gera controle.fone_key.
--     Escrita: respondi-sync 1×/dia (09:10) + respondi-hm-webhook. Índice parcial pequeno (só sem e-mail).
--   fin.hotmart_transacoes.origem_sck (OPCIONAL, decisão do Arthur + dono do fin): sem índice, a atribuição de venda
--     por SCK (crm_links com p_vendas) faz 2 Seq Scans de 57.872 linhas = 1,6 s frio. A F5 NÃO exige este índice:
--     crm_links só calcula vendas sob pedido (p_vendas = true).

create index concurrently if not exists ix_unnichat_evento_email
  on controle.unnichat_evento (lower(btrim((payload -> 'contact') ->> 'email')));

create index concurrently if not exists ix_respostas_fone_sem_email
  on respondi.respostas (controle.fone_key(telefone))
  where email is null and telefone is not null;

-- OPCIONAL (ver acima):
-- create index concurrently if not exists ix_hotmart_transacoes_origem_sck
--   on fin.hotmart_transacoes (origem_sck) where origem_sck is not null;

-- Conferir depois (indisvalid = true; se false, drop index concurrently e rodar de novo):
-- select c.relname, x.indisvalid, pg_get_indexdef(c.oid) from pg_index x join pg_class c on c.oid = x.indexrelid
--  where c.relname in ('ix_unnichat_evento_email', 'ix_respostas_fone_sem_email', 'ix_hotmart_transacoes_origem_sck');
