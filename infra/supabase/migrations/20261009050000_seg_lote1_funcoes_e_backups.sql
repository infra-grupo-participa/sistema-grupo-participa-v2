-- Segurança do banco principal — lote 1 (08/10/2026, card ClickUp 17tya50fqb1)
-- Status: APLICADA em 08/10/2026 via apply_migration "seg_lote1_funcoes_e_backups" (ver 20261009050000_seg_lote1.explain.md)
--
-- O que fecha (só o que nenhum site chama sem login — conferido em código, logs e catálogo):
--   1. Funções SECURITY DEFINER do SIP chamadas só pelo servidor (service_role) ou por ninguém:
--      qualquer pessoa sem login conseguia, p.ex., fechar ciclo ou recomeçar o ciclo de um aluno.
--   2. central.abrir_participacao / encerrar_participacao: só o gatilho de central.alunos chama
--      (gatilho é DEFINER do postgres, não depende deste grant).
--   3. Funções de gatilho DEFINER em schemas expostos: não são chamáveis por RPC; tirar o
--      EXECUTE é limpeza sem efeito (gatilho não confere EXECUTE ao disparar).
--   4. Cópias de auth.users dentro de schemas de aplicação: sem acesso pela API.
--   5. workbook.indicacao / indicacao_evento: RLS ligado (sem policy); quem usa são RPCs DEFINER
--      e o controle-de-eventos com service_role, que não passam por RLS.
--
-- NÃO mexe: funções públicas por desenho (token, segredo, formulários, plantão GPS), funções
-- usadas em policies/views (anon precisa delas para ler), thb_alunos/perfis (lote 2).
-- Reversão: 20261009050000_seg_lote1_reversao.sql

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

commit;
