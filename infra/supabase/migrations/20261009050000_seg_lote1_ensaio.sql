-- ENSAIO do 20261009050000 — termina em ROLLBACK.
-- Esperado: retrato > 0; anon_close=false; svc_close=true; trig_anon=0; bkp=false; rls=true.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- Retrato do ACL antes de mexer: a reversão restaura daqui (exato, sem reabrir nada a mais).
create table if not exists arquivo.acl_retrato_seg_lote1 (
  objeto text not null, grantee text not null, privilegio text not null,
  gravado_em timestamptz not null default now()
);
revoke all on arquivo.acl_retrato_seg_lote1 from public, anon, authenticated;
insert into arquivo.acl_retrato_seg_lote1 (objeto, grantee, privilegio)
select p.oid::regprocedure::text,
       case when a.grantee = 0 then 'public' else a.grantee::regrole::text end,
       a.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
where a.grantee <> p.proowner
  and (
    p.oid in (
      'sip.upsert_ig_daily_activity(uuid, date, integer, integer, integer, integer, integer)'::regprocedure,
      'sip.log_audit_event(uuid, text, text, text, jsonb)'::regprocedure,
      'sip.close_ciclo(uuid)'::regprocedure,
      'sip.fn_recomecar_ciclo(uuid, date, jsonb, text)'::regprocedure,
      'sip.check_login_rate_limit(text, text)'::regprocedure,
      'sip.record_login_attempt(text, text, boolean)'::regprocedure,
      'sip.set_actor(uuid)'::regprocedure,
      'sip.calculate_streak(uuid)'::regprocedure,
      'sip.validate_date_change(uuid, date, text)'::regprocedure,
      'central.abrir_participacao(uuid, text)'::regprocedure,
      'central.encerrar_participacao(uuid, text, text)'::regprocedure)
    or (p.prosecdef and p.prorettype = 'trigger'::regtype
        and n.nspname in ('public','sip','gps','central','rede','metodo','workbook','kpi')
        and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'))
  );

-- 1 + 2: só service_role (e o dono) executam
revoke execute on function
  sip.upsert_ig_daily_activity(uuid, date, integer, integer, integer, integer, integer),
  sip.log_audit_event(uuid, text, text, text, jsonb),
  sip.close_ciclo(uuid),
  sip.fn_recomecar_ciclo(uuid, date, jsonb, text),
  sip.check_login_rate_limit(text, text),
  sip.record_login_attempt(text, text, boolean),
  sip.set_actor(uuid),
  sip.calculate_streak(uuid),
  sip.validate_date_change(uuid, date, text),
  central.abrir_participacao(uuid, text),
  central.encerrar_participacao(uuid, text, text)
from public, anon, authenticated;

grant execute on function
  sip.upsert_ig_daily_activity(uuid, date, integer, integer, integer, integer, integer),
  sip.log_audit_event(uuid, text, text, text, jsonb),
  sip.close_ciclo(uuid),
  sip.fn_recomecar_ciclo(uuid, date, jsonb, text),
  sip.check_login_rate_limit(text, text),
  sip.record_login_attempt(text, text, boolean),
  sip.set_actor(uuid),
  sip.calculate_streak(uuid),
  sip.validate_date_change(uuid, date, text),
  central.abrir_participacao(uuid, text),
  central.encerrar_participacao(uuid, text, text)
to service_role;

-- 3: funções de gatilho DEFINER nos schemas expostos
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.prosecdef
      and p.prorettype = 'trigger'::regtype
      and n.nspname in ('public','sip','gps','central','rede','metodo','workbook','kpi')
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.f);
  end loop;
end $$;

-- 4: cópias de auth.users
revoke all on table workbook.bkp_auth_users_20260810 from public, anon, authenticated;
revoke all on table arquivo.auth_bkp_joao_20260803 from public, anon, authenticated;

-- 5: indicação do Workbook
alter table workbook.indicacao enable row level security;
alter table workbook.indicacao_evento enable row level security;

select json_build_object(
 'retrato', (select count(*) from arquivo.acl_retrato_seg_lote1),
 'retrato_anon', (select count(*) from arquivo.acl_retrato_seg_lote1 where grantee='anon'),
 'anon_close', has_function_privilege('anon','sip.close_ciclo(uuid)','execute'),
 'svc_close', has_function_privilege('service_role','sip.close_ciclo(uuid)','execute'),
 'trig_anon', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prosecdef and p.prorettype='trigger'::regtype and n.nspname in ('public','sip','gps','central','rede','metodo','workbook','kpi') and has_function_privilege('anon',p.oid,'execute')),
 'bkp', has_table_privilege('authenticated','workbook.bkp_auth_users_20260810','select'),
 'rls', (select relrowsecurity from pg_class where oid='workbook.indicacao'::regclass)) r;
rollback;
