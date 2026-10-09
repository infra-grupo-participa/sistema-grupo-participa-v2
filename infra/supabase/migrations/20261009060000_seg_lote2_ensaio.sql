-- Ensaio de 20261009060000_seg_lote2_thb_alunos_perfis. UMA transação, desfeita.
-- Roda como postgres (MCP execute_sql ou psql). Termina em raise exception 'ENSAIO_OK {...}' → desfaz tudo;
-- o rollback do fim é redundante, de segurança.
--
-- ORDEM: I (inventário, como postgres) → T0 (antes, com JWT) → migration (corpo literal, sem begin/commit)
--        → G2 (guarda de novo: TEM de abortar) → T1 (depois, com JWT) → OK (comparações).
--
-- PERFIS DE JWT (escolhidos no próprio banco; ausente = null na saída, não falha):
--   equipe          perfil ativo @advmais.com (o porteiro gp_eh_equipe)
--   gps_titular     gps.membros titular, fora da equipe e de gps.admins (de preferência com sócio)
--   gps_socio       gps.membros sócio, fora da equipe e de gps.admins
--   sem_vinculo     auth.users sem perfis, sem gps.membros/admins/operadores, fora de @advmais.com (outro sistema)
--   gps_admin_fora  gps.admins ativo que NÃO passa em gp_eh_equipe (pode não existir)
--   perfil_pendente perfil com status <> 'ativo' (login do v1/v2 lendo a própria linha)
--
-- ESPERADO (N = total de thb_alunos, P = total de perfis, A = ids do ambiente GPS que existem em thb_alunos):
--   T0  equipe thb=N perfis=P │ sem_vinculo thb=N (o buraco) │ gps_* thb=N (ou 0 se houver RESTRICTIVE
--       de aluno em thb_alunos — ver I.policies) perfis=0 (gps_block_aluno)
--   T1  equipe          thb=N perfis=P  proprio_perfil=1  update_proprio_nome=1
--       gps_titular     thb=A perfis=0  ambiente=A  (igual a T0.ambiente: nada que o GPS lê some)
--       gps_socio       thb=A perfis=0  ambiente=A
--       sem_vinculo     thb=0 perfis=0
--       gps_admin_fora  thb=N perfis=P
--       perfil_pendente thb=0 perfis=1 proprio_perfil=1   (escolhido fora de gps.membros/gps.admins)
--   G2  'seg_lote2: esperava 2 policies abertas ... achei 0 e 0'   (guarda aborta na 2ª passada)
--   OK  ok_geral = true
-- REVISAR À MÃO na saída I (a migration não decide por você):
--   I.invoker   funções NÃO-DEFINER que leem thb_alunos/perfis: cada uma, quem chama com sessão de não-equipe?
--               (gatilho invoker roda com o papel de quem escreve: aluno GPS gravando → passa a ver só o ambiente)
--   I.views     view com security_invoker=true (passa a filtrar) ou com SELECT de authenticated/anon e
--               security_invoker=false (vazamento paralelo que esta migration NÃO fecha)
--   I.pgss      consultas de authenticated nas duas tabelas (pg_stat_statements): toda forma tem de cair
--               num leitor da lista do .explain.md; forma desconhecida = leitor não mapeado → NÃO aplicar.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

create temp table _z_out (ordem int, chave text, valor jsonb) on commit drop;
create temp table _z_ids (rot text primary key, uid uuid, amb uuid[]) on commit drop;

-- ═══ escolha dos perfis ═══
create function pg_temp.z_interno(p uuid) returns boolean language sql stable as $f$
  select exists (select 1 from public.perfis x where x.id = p and x.status = 'ativo' and x.email ilike '%@advmais.com')
      or exists (select 1 from gps.admins a where a.user_id = p and a.ativo)
$f$;

create function pg_temp.z_amb(p uuid) returns uuid[] language sql stable as $f$
  select coalesce(array_agg(distinct t.x), '{}'::uuid[])
    from (select m.aluno_id as x from gps.membros m
           where m.aluno_id in (select aluno_id from gps.membros where user_id = p)
          union all
          select m.pessoa_aluno_id from gps.membros m
           where m.aluno_id in (select aluno_id from gps.membros where user_id = p)) t
   where t.x is not null and exists (select 1 from public.thb_alunos a where a.id = t.x)
$f$;

insert into _z_ids (rot, uid)
select 'equipe', (select p.id from public.perfis p join auth.users u on u.id = p.id
                   where p.status = 'ativo' and p.email ilike '%@advmais.com' order by p.email limit 1)
union all
select 'gps_titular', (select m.user_id from gps.membros m
                        where m.papel = 'titular' and m.user_id is not null and not pg_temp.z_interno(m.user_id)
                        order by exists (select 1 from gps.membros s where s.aluno_id = m.aluno_id and s.papel = 'socio') desc,
                                 m.criado_em desc limit 1)
union all
select 'gps_socio', (select m.user_id from gps.membros m
                      where m.papel = 'socio' and m.user_id is not null and not pg_temp.z_interno(m.user_id)
                      order by m.criado_em desc limit 1)
union all
select 'sem_vinculo', (select u.id from auth.users u
                        where u.email not ilike '%@advmais.com'
                          and not exists (select 1 from public.perfis p where p.id = u.id)
                          and not exists (select 1 from gps.membros m where m.user_id = u.id)
                          and not exists (select 1 from gps.admins a where a.user_id = u.id)
                          and not exists (select 1 from gps.operadores o where o.user_id = u.id)
                        order by u.created_at desc limit 1)
union all
select 'gps_admin_fora', (select a.user_id from gps.admins a
                           where a.ativo and not exists (select 1 from public.perfis p where p.id = a.user_id
                                                          and p.status = 'ativo' and p.email ilike '%@advmais.com')
                           limit 1)
union all
select 'perfil_pendente', (select p.id from public.perfis p join auth.users u on u.id = p.id
                            where p.status <> 'ativo'
                              and not exists (select 1 from gps.membros m where m.user_id = p.id)
                              and not exists (select 1 from gps.admins a where a.user_id = p.id and a.ativo)
                            order by p.criado_em desc limit 1);

update _z_ids set amb = pg_temp.z_amb(uid) where uid is not null;

-- ═══ medidor: troca de papel + JWT dentro da função, conta, volta para o papel da sessão ═══
create function pg_temp.z_medir(p_uid uuid, p_amb uuid[], p_upd boolean) returns jsonb language plpgsql as $f$
declare
  n_thb bigint; n_perf bigint; n_prop bigint; n_amb bigint; n_upd text := null;
begin
  if p_uid is null then return null; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  execute 'select count(*) from public.thb_alunos' into n_thb;
  execute 'select count(*) from public.perfis' into n_perf;
  execute 'select count(*) from public.perfis where id = $1' into n_prop using p_uid;
  execute 'select count(*) from public.thb_alunos where id = any($1)' into n_amb using coalesce(p_amb, '{}'::uuid[]);
  if p_upd then
    begin
      execute 'update public.perfis set nome = nome where id = $1' using p_uid;
      get diagnostics n_prop = row_count;  -- reaproveita: linhas atualizadas
      n_upd := n_prop::text;
      execute 'select count(*) from public.perfis where id = $1' into n_prop using p_uid;
    exception when others then n_upd := sqlstate || ': ' || sqlerrm;
    end;
  end if;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return jsonb_build_object('thb', n_thb, 'perfis', n_perf, 'proprio_perfil', n_prop,
                            'ambiente', n_amb, 'ambiente_esperado', coalesce(cardinality(p_amb), 0),
                            'update_proprio_nome', n_upd);
end
$f$;

-- ═══ I — inventário (como postgres) ═══
insert into _z_out
select 1, 'I.totais', jsonb_build_object(
  'N_thb_alunos', (select count(*) from public.thb_alunos),
  'P_perfis', (select count(*) from public.perfis),
  'escolhidos', (select jsonb_object_agg(rot, jsonb_build_object('uid_ok', uid is not null, 'A', coalesce(cardinality(amb), 0))) from _z_ids),
  'gps_admins_fora_do_porteiro', (select count(*) from gps.admins a where a.ativo and not exists (
       select 1 from public.perfis p where p.id = a.user_id and p.status = 'ativo' and p.email ilike '%@advmais.com')),
  'membros_com_login', (select count(*) from gps.membros where user_id is not null));

insert into _z_out
select 2, 'I.policies', jsonb_agg(jsonb_build_object('t', schemaname || '.' || tablename, 'p', policyname, 'perm', permissive,
                                                     'cmd', cmd, 'roles', roles, 'qual', qual, 'check', with_check)
                                  order by schemaname, tablename, permissive, policyname)
  from pg_policies
 where (schemaname = 'public' and tablename in ('thb_alunos', 'perfis')) or (schemaname = 'gps' and tablename = 'membros');

insert into _z_out
select 3, 'I.invoker', coalesce(jsonb_agg(jsonb_build_object(
         'fn', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         'gatilho', p.prorettype = 'trigger'::regtype,
         'em_tabelas', (select string_agg(distinct t.tgrelid::regclass::text, ',') from pg_trigger t where t.tgfoid = p.oid),
         'auth_exec', has_function_privilege('authenticated', p.oid, 'execute'))), '[]'::jsonb)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where not p.prosecdef and p.prokind in ('f', 'p')
   and n.nspname not in ('pg_catalog', 'information_schema', 'extensions', 'graphql', 'graphql_public', 'pgsodium',
                         'vault', 'realtime', 'storage', 'net', 'cron', 'supabase_functions', 'auth', 'pgbouncer', 'pg_temp')
   and n.nspname not like 'pg_temp%'
   and (p.prosrc ~* '\mthb_alunos\M' or p.prosrc ~* 'public\.perfis\M' or p.prosrc ~* '(^|[^.[:alnum:]_])perfis\M');

insert into _z_out
select 4, 'I.views', coalesce(jsonb_agg(jsonb_build_object(
         'v', c.oid::regclass::text, 'tipo', c.relkind,
         'security_invoker', coalesce((select option_value from pg_options_to_table(c.reloptions) where option_name = 'security_invoker'), 'false'),
         'auth_select', has_table_privilege('authenticated', c.oid, 'select'),
         'anon_select', has_table_privilege('anon', c.oid, 'select'))), '[]'::jsonb)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
   and (pg_get_viewdef(c.oid) ~* '\mthb_alunos\M' or pg_get_viewdef(c.oid) ~* 'public\.perfis\M'
        or pg_get_viewdef(c.oid) ~* '(^|[^.[:alnum:]_])perfis\M');

do $pgss$
begin
  if to_regclass('extensions.pg_stat_statements') is null then
    insert into _z_out values (5, 'I.pgss', '"pg_stat_statements ausente"'::jsonb);
    return;
  end if;
  execute $q$
    insert into _z_out
    select 5, 'I.pgss', coalesce(jsonb_agg(jsonb_build_object('calls', s.calls,
             'q', left(regexp_replace(s.query, '\s+', ' ', 'g'), 240)) order by s.calls desc), '[]'::jsonb)
      from (select s.* from extensions.pg_stat_statements s join pg_roles r on r.oid = s.userid
             where r.rolname = 'authenticated'
               and (s.query ~* '\mthb_alunos\M' or s.query ~* '"public"\."perfis"' or s.query ~* 'public\.perfis\M')
             order by s.calls desc limit 40) s
  $q$;
end
$pgss$;

-- ═══ T0 — antes ═══
do $t0$
declare r record;
begin
  for r in select * from _z_ids loop
    insert into _z_out values (10, 'T0.' || r.rot, pg_temp.z_medir(r.uid, r.amb, false));
  end loop;
end
$t0$;

-- ═══ MIGRATION (corpo literal de 20261009060000_seg_lote2_thb_alunos_perfis.sql, sem begin/commit/set local) ═══
do $pre$
declare
  v_thb   int;
  v_perf  int;
  v_lista text;
begin
  if to_regprocedure('public.gp_eh_equipe()') is null then
    raise exception 'seg_lote2: public.gp_eh_equipe() não existe';
  end if;
  if to_regprocedure('gps.eh_admin()') is null then
    raise exception 'seg_lote2: gps.eh_admin() não existe (GPS 20261008000366 não aplicada?)';
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'gps' and table_name = 'membros'
         and column_name in ('user_id', 'aluno_id', 'pessoa_aluno_id')) <> 3 then
    raise exception 'seg_lote2: gps.membros sem user_id/aluno_id/pessoa_aluno_id';
  end if;
  if (select relforcerowsecurity from pg_class where oid = 'gps.membros'::regclass) then
    raise exception 'seg_lote2: gps.membros com FORCE RLS — o helper DEFINER deixaria de enxergar';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.thb_alunos'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.perfis'::regclass) then
    raise exception 'seg_lote2: RLS desligada em thb_alunos ou perfis';
  end if;

  -- o vínculo que dá acesso não pode ser gravável pelo próprio aluno
  select string_agg(policyname, ', ') into v_lista
    from pg_policies
   where schemaname = 'gps' and tablename = 'membros' and permissive = 'PERMISSIVE'
     and cmd in ('INSERT', 'UPDATE', 'ALL')
     and coalesce(with_check, qual, 'true') = 'true';
  if v_lista is not null then
    raise exception 'seg_lote2: gps.membros tem escrita aberta (%): o aluno criaria o próprio vínculo', v_lista;
  end if;

  -- as policies abertas: contagem e forma exatas
  select count(*) filter (where tablename = 'thb_alunos'),
         count(*) filter (where tablename = 'perfis')
    into v_thb, v_perf
    from pg_policies
   where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
     and permissive = 'PERMISSIVE' and cmd in ('SELECT', 'ALL')
     and coalesce(qual, 'true') = 'true';
  if v_thb <> 2 or v_perf <> 1 then
    raise exception 'seg_lote2: esperava 2 policies abertas em thb_alunos e 1 em perfis, achei % e %', v_thb, v_perf;
  end if;

  select string_agg(tablename || '.' || policyname || ' cmd=' || cmd || ' roles=' || roles::text, '; ') into v_lista
    from pg_policies
   where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
     and permissive = 'PERMISSIVE' and cmd in ('SELECT', 'ALL')
     and coalesce(qual, 'true') = 'true'
     and (cmd <> 'SELECT' or roles <> array['authenticated']::name[]);
  if v_lista is not null then
    raise exception 'seg_lote2: policy aberta fora do formato SELECT TO authenticated: %', v_lista;
  end if;

  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and policyname in ('thb_alunos_select_escopo', 'perfis_select_escopo')) then
    raise exception 'seg_lote2: policy nova já existe (migration já aplicada?)';
  end if;
end
$pre$;

create function public.gp_le_cadastro_interno()
returns boolean
language sql
stable
security definer
set search_path = ''
as $f$
  select coalesce(public.gp_eh_equipe(), false) or coalesce(gps.eh_admin(), false)
$f$;

comment on function public.gp_le_cadastro_interno() is
  'seg_lote2 20261009060000: lê thb_alunos/perfis inteiros = gp_eh_equipe() (perfil ativo @advmais.com) OU '
  'gps.eh_admin() (gps.admins ativo). Usada pelas policies thb_alunos_select_escopo e perfis_select_escopo.';

create function public.gp_thb_alunos_do_ambiente()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $f$
  select coalesce(array_agg(distinct v.id) filter (where v.id is not null), '{}'::uuid[])
    from gps.membros eu
    join gps.membros m on m.aluno_id = eu.aluno_id
    cross join lateral (values (m.aluno_id), (m.pessoa_aluno_id)) v(id)
   where eu.user_id = (select auth.uid())
$f$;

comment on function public.gp_thb_alunos_do_ambiente() is
  'seg_lote2 20261009060000: ids de public.thb_alunos que o login alcança pelo GPS — o ambiente (gps.membros.aluno_id) '
  'e a pessoa de cada membro do MESMO ambiente (pessoa_aluno_id). Sem vínculo = vazio. Não casa por e-mail.';

revoke all on function public.gp_le_cadastro_interno()    from public, anon;
revoke all on function public.gp_thb_alunos_do_ambiente() from public, anon;
grant execute on function public.gp_le_cadastro_interno()    to authenticated, service_role;
grant execute on function public.gp_thb_alunos_do_ambiente() to authenticated, service_role;

create policy thb_alunos_select_escopo on public.thb_alunos
  for select to authenticated
  using (
    (select public.gp_le_cadastro_interno())
    or id = any ((select public.gp_thb_alunos_do_ambiente())::uuid[])
  );

create policy perfis_select_escopo on public.perfis
  for select to authenticated
  using (
    (select public.gp_le_cadastro_interno())
    or id = (select auth.uid())
  );

do $neutro$
declare
  r record;
begin
  for r in
    select tablename, policyname
      from pg_policies
     where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
       and permissive = 'PERMISSIVE' and cmd = 'SELECT'
       and roles = array['authenticated']::name[]
       and qual = 'true'
  loop
    execute format('alter policy %I on public.%I using (false)', r.policyname, r.tablename);
    execute format('comment on policy %I on public.%I is %L', r.policyname, r.tablename,
      'seg_lote2 20261009060000: era USING (true); neutralizada. Reverter: 20261009060000_seg_lote2_reversao.sql');
  end loop;
end
$neutro$;

do $pos$
begin
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
         and permissive = 'PERMISSIVE' and cmd in ('SELECT', 'ALL')
         and coalesce(qual, 'true') = 'true') <> 0 then
    raise exception 'seg_lote2: ainda há policy aberta depois da troca';
  end if;
  if exists (select 1
               from pg_proc p, unnest(coalesce(p.proacl, '{}')) a
              where p.oid in ('public.gp_le_cadastro_interno()'::regprocedure,
                              'public.gp_thb_alunos_do_ambiente()'::regprocedure)
                and (a::text like '=%' or a::text like 'anon=%')) then
    raise exception 'seg_lote2: helper executável por PUBLIC/anon';
  end if;
end
$pos$;
-- ═══ fim da cópia da migration ═══

-- ═══ G2 — a guarda na 2ª passada TEM de abortar (só a contagem; o resto da guarda já passou acima) ═══
do $g2$
declare v_thb int; v_perf int;
begin
  begin
    select count(*) filter (where tablename = 'thb_alunos'), count(*) filter (where tablename = 'perfis')
      into v_thb, v_perf
      from pg_policies
     where schemaname = 'public' and tablename in ('thb_alunos', 'perfis')
       and permissive = 'PERMISSIVE' and cmd in ('SELECT', 'ALL') and coalesce(qual, 'true') = 'true';
    if v_thb <> 2 or v_perf <> 1 then
      raise exception 'seg_lote2: esperava 2 policies abertas em thb_alunos e 1 em perfis, achei % e %', v_thb, v_perf;
    end if;
    insert into _z_out values (20, 'G2', '"FALHA: a guarda NÃO abortou na 2ª passada"'::jsonb);
  exception when raise_exception then
    insert into _z_out values (20, 'G2', to_jsonb(sqlerrm));
  end;
end
$g2$;

insert into _z_out
select 21, 'G2.acl_helpers', jsonb_object_agg(p.proname, p.proacl::text)
  from pg_proc p where p.oid in ('public.gp_le_cadastro_interno()'::regprocedure, 'public.gp_thb_alunos_do_ambiente()'::regprocedure);

-- ═══ T1 — depois ═══
do $t1$
declare r record;
begin
  for r in select * from _z_ids loop
    insert into _z_out values (30, 'T1.' || r.rot, pg_temp.z_medir(r.uid, r.amb, r.rot = 'equipe'));
  end loop;
end
$t1$;

-- ═══ OK — comparações ═══
with t as (select replace(chave, 'T1.', '') rot, valor v from _z_out where chave like 'T1.%' and valor is not null),
     tot as (select (select count(*) from public.thb_alunos) n, (select count(*) from public.perfis) p),
     chk as (
  select t.rot,
         case t.rot
           when 'equipe'          then (v->>'thb')::bigint = tot.n and (v->>'perfis')::bigint = tot.p and v->>'update_proprio_nome' = '1'
           when 'gps_titular'     then (v->>'thb')::bigint = (v->>'ambiente_esperado')::bigint and (v->>'ambiente') = (v->>'ambiente_esperado') and (v->>'perfis')::bigint = 0
           when 'gps_socio'       then (v->>'thb')::bigint = (v->>'ambiente_esperado')::bigint and (v->>'ambiente') = (v->>'ambiente_esperado') and (v->>'perfis')::bigint = 0
           when 'sem_vinculo'     then (v->>'thb')::bigint = 0 and (v->>'perfis')::bigint = 0
           when 'gps_admin_fora'  then (v->>'thb')::bigint = tot.n and (v->>'perfis')::bigint = tot.p
           when 'perfil_pendente' then (v->>'proprio_perfil')::bigint = 1 and (v->>'perfis')::bigint = 1
         end as ok
    from t, tot)
insert into _z_out
select 40, 'OK', jsonb_build_object('por_perfil', jsonb_object_agg(rot, ok), 'ok_geral', bool_and(coalesce(ok, false))
                                    and (select valor::text like '%esperava 2 policies abertas%' from _z_out where chave = 'G2'))
  from chk;

do $fim$
begin
  raise exception 'ENSAIO_OK %', (select jsonb_object_agg(chave, valor order by ordem) from _z_out);
end
$fim$;

rollback;
