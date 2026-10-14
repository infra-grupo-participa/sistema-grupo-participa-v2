-- Reversão da 20261014200100. Só tira a linha do de-para; inscrições já gravadas mantêm a etiqueta.
delete from metodo.origem_etiqueta where origem = 'renovacao-thb-vencidos';
delete from supabase_migrations.schema_migrations where version = '20261014200100';
