-- Reversão de 20261015210000_dados_atm_grupo_leads_criar.sql: apaga a RPC nova. Nenhuma outra função muda.
-- Depois: delete da versão 20261015210000 em supabase_migrations.schema_migrations.
set local lock_timeout = '3s';
set local statement_timeout = '10s';
drop function if exists public.dados_atm_grupo_leads(text, date, date);
