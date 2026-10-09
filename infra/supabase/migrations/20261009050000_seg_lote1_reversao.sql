-- Reversão do lote 1 de segurança (20261009050000).
-- Restaura o EXECUTE das funções exatamente como estava, a partir de arquivo.acl_retrato_seg_lote1.
-- De propósito NÃO reabre as cópias de auth.users (já estavam fechadas desde 20261003j) e NÃO desliga
-- o RLS de workbook.indicacao* (só funções DEFINER do dono postgres usam; RLS não as afeta).
-- Se precisar mesmo: alter table workbook.indicacao disable row level security; (idem _evento)
begin;
set local lock_timeout = '3s';
do $$
declare r record;
begin
  for r in select distinct objeto from arquivo.acl_retrato_seg_lote1 loop
    execute format('revoke execute on function %s from public, anon, authenticated, service_role', r.objeto);
  end loop;
  for r in select objeto, grantee from arquivo.acl_retrato_seg_lote1 where privilegio = 'EXECUTE' loop
    execute format('grant execute on function %s to %s', r.objeto,
                   case when r.grantee = 'public' then 'public' else quote_ident(r.grantee) end);
  end loop;
end $$;
commit;
