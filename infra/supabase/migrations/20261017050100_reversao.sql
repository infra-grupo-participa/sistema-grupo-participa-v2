-- Reversão da 20261017050100. Tira só a linha do de-para.
delete from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10';
delete from supabase_migrations.schema_migrations where version = '20261017050100';
