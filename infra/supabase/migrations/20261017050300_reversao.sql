-- Reversão da 20261017050300. Apaga só a função nova; dados_renov_thb(boolean) (20261016173552) não foi tocada.
drop function if exists public.dados_renov_thb(text, boolean);
delete from supabase_migrations.schema_migrations where version = '20261017050300';
