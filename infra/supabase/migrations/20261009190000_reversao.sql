-- Reversão de 20261009190000 (Clínica Miami: webhook do Respondi e RPCs Diamantes/Interesse). Numa transação.
-- ANTES: tirar a URL do webhook no Respondi (senão ele recebe 401/500) e despublicar a Edge respondi-webhook
--   (npx supabase functions delete respondi-webhook). As respostas que o webhook gravou ficam em respondi.respostas
--   (mesma tabela do sync diário, que continua igual); só a Lista Diamantes e os logs são apagados aqui.
-- O segredo do Vault sai à parte: delete from vault.secrets where name = 'respondi_webhook_chave';
set local lock_timeout = '5s';
set local statement_timeout = '30s';

drop function if exists public.dados_miami_diamantes(text);
drop function if exists public.dados_miami_interesse(text);
drop function if exists dados.data_br(text);
drop function if exists dados.respondi_valor(jsonb, text);
drop function if exists dados.nome_casa(text[], text[]);
drop function if exists dados.nome_tokens(text);
drop function if exists respondi.webhook_chave();
drop table if exists respondi.webhook_log;
drop table if exists dados.dashboard_lista_pessoas;
drop table if exists dados.dashboard_formularios;
