-- Reversão de 20261014170000 (estrutura da carga do ActiveCampaign).
-- ANTES de rodar, se a carga já tiver rodado, decidir o que fazer com o que ela gravou FORA do estágio (a reversão NÃO
-- apaga pessoa: pessoa nunca se apaga, regra I-03). Para medir:
--   select count(*) from pessoas.ac_contato where pessoa_nova;                       -- pessoas criadas pela carga
--   select count(*) from pessoas.eventos where fonte_tabela = 'pessoas.ac_contato';  -- linhas do tempo da carga
--   select count(*) from pessoas.identificadores where origem = 'activecampaign';    -- (inclui as do webhook de antes)
-- Os eventos da carga apontam para pessoas.ac_contato por texto (fonte_tabela/fonte_id), sem FK: a reversão não os toca.
set local lock_timeout = '5s';
drop function if exists pessoas.carga_ac_pessoas(bigint, integer);
drop function if exists pessoas.casar_email(text, text, text, text);
drop function if exists pessoas.carga_ac_estagio(bigint, jsonb, text);
drop function if exists pessoas.carga_ac_catalogo(jsonb);
drop function if exists pessoas.carga_fechar(bigint, text, text);
drop function if exists pessoas.carga_abrir(text, text, text);
drop function if exists pessoas.carga_contagem();
drop function if exists pessoas.carga_ligada(text);
drop table if exists pessoas.ac_contato;
drop table if exists pessoas.ac_lista_papel;
drop table if exists pessoas.ac_campo_carga;
drop table if exists pessoas.ac_catalogo;
drop table if exists pessoas.carga_lote;
drop table if exists pessoas.carga_execucao;
drop table if exists pessoas.carga_chave;
