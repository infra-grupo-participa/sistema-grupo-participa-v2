-- Reversão do lote 3 (20261009080000): restaura o EXECUTE exatamente como estava, do retrato.
begin;
set local lock_timeout = '3s';
do $$
declare r record;
begin
  for r in select distinct objeto from arquivo.acl_retrato_seg_lote3 loop
    execute format('revoke execute on function %s from public, anon, authenticated, service_role', r.objeto);
  end loop;
  for r in select objeto, grantee from arquivo.acl_retrato_seg_lote3 where privilegio = 'EXECUTE' loop
    execute format('grant execute on function %s to %s', r.objeto,
                   case when r.grantee = 'public' then 'public' else quote_ident(r.grantee) end);
  end loop;
end $$;
commit;
