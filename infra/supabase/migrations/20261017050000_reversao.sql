-- Reversão da 20261017050000. Só desfaz se a linha ainda estiver como a migration deixou (não pisa em ajuste posterior).
update dados.dashboards
   set oferta_codigo = null, ofertas_extra = '{}'
 where chave = 'black-thb-2026-10' and oferta_codigo = 'nv5f10zq' and ofertas_extra = array['wftji6dl'];
delete from supabase_migrations.schema_migrations where version = '20261017050000';
