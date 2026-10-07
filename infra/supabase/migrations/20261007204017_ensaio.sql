-- Ensaio de 20261007y_acesso_autor_da_rota.sql: sonda de 32 guardas antes, 2 passadas, sonda depois, provas, ROLLBACK e sonda de novo.
-- Transação desfeita: nada persiste.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to service_role, authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to service_role, authenticated, anon;
create function pg_temp.sonda(p_id uuid) returns jsonb language plpgsql as $s$
declare j jsonb; k text; a record;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  j := jsonb_build_object(
    'equipe', public.gp_eh_equipe(), 'admin', public.gp_is_admin(),
    'fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro(), 'cpf', public.gp_pode_ver_cpf(),
    'crm_gestor', crm.eh_gestor(), 'crm_comercial', crm.eh_comercial(), 'crm_catalogar', crm.pode_catalogar(),
    'remocao', public.ra_pode_ver(), 'pedidos', public.pa_pode_pedir(), 'placas', public.gp_pode_editar('placas'),
    'base_pessoas', pessoas.pode_ver(), 'gps_eh_equipe', gps.eh_equipe(), 'pa_pode_ver_doc', public.pa_pode_ver_doc(), 'alunos_ver_sensivel', public.tem_permissao(p_id, 'alunos.ver_sensivel'),
    'mkt_ver', mkt.pode_ver('mkt_trafego'), 'ed_trafego', mkt.pode_editar('mkt_trafego'), 'ed_web', mkt.pode_editar('mkt_web'),
    'ed_mensageria', mkt.pode_editar('mkt_mensageria'),
    'gps', public.gp_is_admin() or coalesce(public.gp_acesso_pode_editar('educacional', null), false),
    'ver_financeiro', public.gp_acesso_pode_ver('financeiro', null));
  for a in select d.key as dep, null::text as ar from acesso.departamento d union all select ar2.departamento, ar2.key from acesso.area ar2 loop
    j := j || jsonb_build_object('ed:' || a.dep || coalesce('/' || a.ar, ''), public.gp_acesso_pode_editar(a.dep, a.ar));
  end loop;
  return j;
end $s$;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 100);
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.sonda(uuid), pg_temp.tenta(uuid, text) to authenticated;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '1 antes', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';

-- ===== PASSADA 1 =====
-- 20261007y: níveis de acesso, B2 do pentester (card 17tya50fkgx): mudança de acesso feita pela rota /api/admin/usuarios
-- (service_role) passa a gravar em acesso.log QUAL master fez, e a rota não consegue mais mudar acesso sem dizer o autor.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007y_ensaio.sql (2 passadas, sonda de 32 guardas, rollback). Relatório: 20261007y.explain.md.
--
-- POR QUE
--   A rota de Usuários grava em public.perfis com a chave service_role (createAdminSupabase): auth.uid() é nulo, e o
--   gatilho acesso_guarda (fase 3, 20261007195738) grava o log com autor nulo e via service_role. O pentester (rodada 2,
--   B2) pediu o autor.
--
-- O QUE FAZ
--   1. public.acesso_perfil_atualizar_como(p_autor uuid, p_id uuid, p_patch jsonb): RPC só para service_role (a rota).
--      Confere que p_autor é perfil ativo da equipe com direito de gerir usuários hoje (master, ou exceção nominal com o
--      mesmo cargo: os mesmos que a rota deixa entrar); perfil de master só muda por autor master (pentester, rodada 4), grava p_autor na transação (set_config local
--      'acesso.autor') e faz o update dos campos que vierem em p_patch (nome, status, time, cargo, areas, funcoes,
--      pode_ver_cpf_completo). As travas do gatilho continuam valendo (cargo admin/dev, CPF pela coluna).
--   2. acesso.tg_perfis_guarda (corpo vivo + 2 mudanças):
--      - o autor do log é auth.uid() ou, sem ele, o 'acesso.autor' da transação;
--      - grava 'via' (service_role, authenticated, postgres).
--   A RECUSA de mudança sem autor pela service_role fica na 20261007y2, que só pode subir DEPOIS que a rota
--   (web/app/api/admin/usuarios/route.ts) usar esta RPC em produção (main): a rota que está no ar faz update direto.
--
-- AS 5 PERGUNTAS
--   escala: 1 função, 1 gatilho recriado (sem mudança de comportamento: só passa a saber o autor). índice: PK de perfis e acesso.master. frequência: cada edição de usuário
--   (raro). repetição: 1 chamada por edição. reversão: bloco REVERSÃO no fim (corpo anterior de acesso.corpo_antes).
--
-- IDEMPOTENTE: create or replace; corpo anterior guardado uma vez (on conflict do nothing); a guarda aceita o corpo
--   vivo da fase 3 (md5 c4373344…) ou o desta migration.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $bl$
begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('níveis de acesso, B2 (20261007y): autor do master na rota de usuários');
  end if;
end
$bl$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('acesso.tg_perfis_guarda()')) is distinct from 'c4373344c650f5573d5c475ca705881d'
     and (select prosrc from pg_proc where oid = to_regprocedure('acesso.tg_perfis_guarda()')) !~ '20261007y([^0-9a-z]|$)' then
    raise exception '20261007y: corpo vivo de acesso.tg_perfis_guarda mudou (nem o da fase 3 nem o desta migration). Reler.';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007y'
  from pg_proc p where p.oid = 'acesso.tg_perfis_guarda()'::regprocedure
on conflict do nothing;

-- 1. RPC da rota
create or replace function public.acesso_perfil_atualizar_como(p_autor uuid, p_id uuid, p_patch jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_status text := p_patch ->> 'status';
begin
  if p_autor is null or not exists (
       select 1 from public.perfis a
        where a.id = p_autor and a.status = 'ativo' and a.email ilike '%@advmais.com'
          and (exists (select 1 from acesso.master m where m.perfil_id = a.id)
               or exists (select 1 from acesso.excecao_admin e where e.perfil_id = a.id and e.cargo = a.cargo))) then
    raise exception 'Autor sem direito de gerir usuários.' using errcode = '42501';
  end if;
  -- pentester rodada 4 (MÉDIO): perfil de master só muda por autor master (a exceção nominal não mexe em master)
  if exists (select 1 from acesso.master m where m.perfil_id = p_id)
     and not exists (select 1 from acesso.master m where m.perfil_id = p_autor) then
    raise exception 'Só um master altera o perfil de outro master.' using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Alteração inválida.' using errcode = '22023';
  end if;
  if v_status is not null and v_status not in ('ativo', 'pendente', 'negado') then
    raise exception 'Status inválido.' using errcode = '22023';
  end if;
  perform set_config('acesso.autor', p_autor::text, true);
  update public.perfis p set
    nome    = case when p_patch ? 'nome' then nullif(btrim(p_patch ->> 'nome'), '') else p.nome end,
    status  = coalesce(v_status, p.status),
    "time"  = case when p_patch ? 'time' then nullif(btrim(p_patch ->> 'time'), '') else p."time" end,
    cargo   = case when p_patch ? 'cargo' then p_patch ->> 'cargo' else p.cargo end,
    areas   = case when p_patch ? 'areas' then array(select jsonb_array_elements_text(p_patch -> 'areas')) else p.areas end,
    funcoes = case when p_patch ? 'funcoes' then array(select jsonb_array_elements_text(p_patch -> 'funcoes')) else p.funcoes end,
    pode_ver_cpf_completo = case when p_patch ? 'pode_ver_cpf_completo' then (p_patch ->> 'pode_ver_cpf_completo')::boolean
                                 else p.pode_ver_cpf_completo end,
    atualizado_em = now()
   where p.id = p_id;
  if not found then
    raise exception 'Usuário não encontrado.' using errcode = 'P0002';
  end if;
  perform set_config('acesso.autor', '', true);
  return jsonb_build_object('ok', true, 'id', p_id);
end
$f$;
revoke all on function public.acesso_perfil_atualizar_como(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.acesso_perfil_atualizar_como(uuid, uuid, jsonb) to service_role;

-- 2. Gatilho: autor da transação e recusa sem autor pela service_role
create or replace function acesso.tg_perfis_guarda()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261007y: o autor é o usuário logado ou, pela rota (service_role), o master que a RPC acesso_perfil_atualizar_como gravou
  v_uid uuid := coalesce((select auth.uid()), nullif(current_setting('acesso.autor', true), '')::uuid);
  v_papel text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', current_user);
begin
  -- B1: confere também quando só o status muda (pendente/negado com admin voltando a ativo)
  if new.cargo in ('admin', 'dev')
     and (tg_op = 'INSERT' or old.cargo is distinct from new.cargo or old.status is distinct from new.status)
     and not exists (select 1 from acesso.master m where m.perfil_id = new.id)
     and not exists (select 1 from acesso.excecao_admin e where e.perfil_id = new.id and e.cargo = new.cargo) then
    raise exception 'Cargo % é só de master (acesso.master) ou da exceção nominal. Dê acesso por departamento/área (acesso_vincular).', new.cargo
      using errcode = '42501';
  end if;
  if coalesce(new.pode_ver_cpf_completo, false)
     and (tg_op = 'INSERT' or not coalesce(old.pode_ver_cpf_completo, false)) then
    raise exception 'CPF completo agora é a capacidade cpf.ver (acesso_capacidade_definir, só master).' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.nome is distinct from old.nome and v_uid is not null and v_uid = new.id
     and not exists (select 1 from acesso.master m where m.perfil_id = v_uid) then
    raise exception 'O nome só muda pela gestão de usuários.' using errcode = '42501';
  end if;
  if tg_op = 'INSERT'
     or (old.cargo, old.status, old.areas, old.funcoes, old.pode_ver_cpf_completo)
        is distinct from (new.cargo, new.status, new.areas, new.funcoes, new.pode_ver_cpf_completo) then
    insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
    values (v_uid, 'perfis', lower(tg_op), new.id,
            case when tg_op = 'UPDATE' then jsonb_build_object('cargo', old.cargo, 'status', old.status, 'areas', old.areas,
                                                               'funcoes', old.funcoes, 'cpf', old.pode_ver_cpf_completo) end,
            jsonb_build_object('cargo', new.cargo, 'status', new.status, 'areas', new.areas, 'funcoes', new.funcoes,
                               'cpf', new.pode_ver_cpf_completo, 'via', v_papel));
  end if;
  return new;
end
$function$;
revoke all on function acesso.tg_perfis_guarda() from public, anon, authenticated;

do $c$
begin
  if has_function_privilege('authenticated', 'public.acesso_perfil_atualizar_como(uuid,uuid,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.acesso_perfil_atualizar_como(uuid,uuid,jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.acesso_perfil_atualizar_como(uuid,uuid,jsonb)', 'execute') then
    raise exception '20261007y: permissão errada em acesso_perfil_atualizar_como';
  end if;
  if (select prosrc from pg_proc where oid = 'acesso.tg_perfis_guarda()'::regprocedure) !~ '20261007y([^0-9a-z]|$)' then
    raise exception '20261007y: gatilho não foi recriado';
  end if;
end
$c$;

-- REVERSÃO (numa transação; se a rota já usa a RPC, reverter a rota junto): script pronto em
-- .maestri/entregas/niveis-de-acesso/rollback-b2.sql (cérebro), ensaiado em 20261007y_ensaio.sql.
-- select blindagem.autorizar_guarda('rollback do B2 (20261007y)');
-- do $v$ declare r record; begin
--   for r in select * from acesso.corpo_antes where migration = '20261007y' and tipo = 'funcao' loop execute r.definicao; end loop;
-- end $v$;
-- drop function if exists public.acesso_perfil_atualizar_como(uuid, uuid, jsonb);

-- ===== PASSADA 2 =====
-- 20261007y: níveis de acesso, B2 do pentester (card 17tya50fkgx): mudança de acesso feita pela rota /api/admin/usuarios
-- (service_role) passa a gravar em acesso.log QUAL master fez, e a rota não consegue mais mudar acesso sem dizer o autor.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007y_ensaio.sql (2 passadas, sonda de 32 guardas, rollback). Relatório: 20261007y.explain.md.
--
-- POR QUE
--   A rota de Usuários grava em public.perfis com a chave service_role (createAdminSupabase): auth.uid() é nulo, e o
--   gatilho acesso_guarda (fase 3, 20261007195738) grava o log com autor nulo e via service_role. O pentester (rodada 2,
--   B2) pediu o autor.
--
-- O QUE FAZ
--   1. public.acesso_perfil_atualizar_como(p_autor uuid, p_id uuid, p_patch jsonb): RPC só para service_role (a rota).
--      Confere que p_autor é perfil ativo da equipe com direito de gerir usuários hoje (master, ou exceção nominal com o
--      mesmo cargo: os mesmos que a rota deixa entrar); perfil de master só muda por autor master (pentester, rodada 4), grava p_autor na transação (set_config local
--      'acesso.autor') e faz o update dos campos que vierem em p_patch (nome, status, time, cargo, areas, funcoes,
--      pode_ver_cpf_completo). As travas do gatilho continuam valendo (cargo admin/dev, CPF pela coluna).
--   2. acesso.tg_perfis_guarda (corpo vivo + 2 mudanças):
--      - o autor do log é auth.uid() ou, sem ele, o 'acesso.autor' da transação;
--      - grava 'via' (service_role, authenticated, postgres).
--   A RECUSA de mudança sem autor pela service_role fica na 20261007y2, que só pode subir DEPOIS que a rota
--   (web/app/api/admin/usuarios/route.ts) usar esta RPC em produção (main): a rota que está no ar faz update direto.
--
-- AS 5 PERGUNTAS
--   escala: 1 função, 1 gatilho recriado (sem mudança de comportamento: só passa a saber o autor). índice: PK de perfis e acesso.master. frequência: cada edição de usuário
--   (raro). repetição: 1 chamada por edição. reversão: bloco REVERSÃO no fim (corpo anterior de acesso.corpo_antes).
--
-- IDEMPOTENTE: create or replace; corpo anterior guardado uma vez (on conflict do nothing); a guarda aceita o corpo
--   vivo da fase 3 (md5 c4373344…) ou o desta migration.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $bl$
begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('níveis de acesso, B2 (20261007y): autor do master na rota de usuários');
  end if;
end
$bl$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('acesso.tg_perfis_guarda()')) is distinct from 'c4373344c650f5573d5c475ca705881d'
     and (select prosrc from pg_proc where oid = to_regprocedure('acesso.tg_perfis_guarda()')) !~ '20261007y([^0-9a-z]|$)' then
    raise exception '20261007y: corpo vivo de acesso.tg_perfis_guarda mudou (nem o da fase 3 nem o desta migration). Reler.';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007y'
  from pg_proc p where p.oid = 'acesso.tg_perfis_guarda()'::regprocedure
on conflict do nothing;

-- 1. RPC da rota
create or replace function public.acesso_perfil_atualizar_como(p_autor uuid, p_id uuid, p_patch jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_status text := p_patch ->> 'status';
begin
  if p_autor is null or not exists (
       select 1 from public.perfis a
        where a.id = p_autor and a.status = 'ativo' and a.email ilike '%@advmais.com'
          and (exists (select 1 from acesso.master m where m.perfil_id = a.id)
               or exists (select 1 from acesso.excecao_admin e where e.perfil_id = a.id and e.cargo = a.cargo))) then
    raise exception 'Autor sem direito de gerir usuários.' using errcode = '42501';
  end if;
  -- pentester rodada 4 (MÉDIO): perfil de master só muda por autor master (a exceção nominal não mexe em master)
  if exists (select 1 from acesso.master m where m.perfil_id = p_id)
     and not exists (select 1 from acesso.master m where m.perfil_id = p_autor) then
    raise exception 'Só um master altera o perfil de outro master.' using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Alteração inválida.' using errcode = '22023';
  end if;
  if v_status is not null and v_status not in ('ativo', 'pendente', 'negado') then
    raise exception 'Status inválido.' using errcode = '22023';
  end if;
  perform set_config('acesso.autor', p_autor::text, true);
  update public.perfis p set
    nome    = case when p_patch ? 'nome' then nullif(btrim(p_patch ->> 'nome'), '') else p.nome end,
    status  = coalesce(v_status, p.status),
    "time"  = case when p_patch ? 'time' then nullif(btrim(p_patch ->> 'time'), '') else p."time" end,
    cargo   = case when p_patch ? 'cargo' then p_patch ->> 'cargo' else p.cargo end,
    areas   = case when p_patch ? 'areas' then array(select jsonb_array_elements_text(p_patch -> 'areas')) else p.areas end,
    funcoes = case when p_patch ? 'funcoes' then array(select jsonb_array_elements_text(p_patch -> 'funcoes')) else p.funcoes end,
    pode_ver_cpf_completo = case when p_patch ? 'pode_ver_cpf_completo' then (p_patch ->> 'pode_ver_cpf_completo')::boolean
                                 else p.pode_ver_cpf_completo end,
    atualizado_em = now()
   where p.id = p_id;
  if not found then
    raise exception 'Usuário não encontrado.' using errcode = 'P0002';
  end if;
  perform set_config('acesso.autor', '', true);
  return jsonb_build_object('ok', true, 'id', p_id);
end
$f$;
revoke all on function public.acesso_perfil_atualizar_como(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.acesso_perfil_atualizar_como(uuid, uuid, jsonb) to service_role;

-- 2. Gatilho: autor da transação e recusa sem autor pela service_role
create or replace function acesso.tg_perfis_guarda()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261007y: o autor é o usuário logado ou, pela rota (service_role), o master que a RPC acesso_perfil_atualizar_como gravou
  v_uid uuid := coalesce((select auth.uid()), nullif(current_setting('acesso.autor', true), '')::uuid);
  v_papel text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', current_user);
begin
  -- B1: confere também quando só o status muda (pendente/negado com admin voltando a ativo)
  if new.cargo in ('admin', 'dev')
     and (tg_op = 'INSERT' or old.cargo is distinct from new.cargo or old.status is distinct from new.status)
     and not exists (select 1 from acesso.master m where m.perfil_id = new.id)
     and not exists (select 1 from acesso.excecao_admin e where e.perfil_id = new.id and e.cargo = new.cargo) then
    raise exception 'Cargo % é só de master (acesso.master) ou da exceção nominal. Dê acesso por departamento/área (acesso_vincular).', new.cargo
      using errcode = '42501';
  end if;
  if coalesce(new.pode_ver_cpf_completo, false)
     and (tg_op = 'INSERT' or not coalesce(old.pode_ver_cpf_completo, false)) then
    raise exception 'CPF completo agora é a capacidade cpf.ver (acesso_capacidade_definir, só master).' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.nome is distinct from old.nome and v_uid is not null and v_uid = new.id
     and not exists (select 1 from acesso.master m where m.perfil_id = v_uid) then
    raise exception 'O nome só muda pela gestão de usuários.' using errcode = '42501';
  end if;
  if tg_op = 'INSERT'
     or (old.cargo, old.status, old.areas, old.funcoes, old.pode_ver_cpf_completo)
        is distinct from (new.cargo, new.status, new.areas, new.funcoes, new.pode_ver_cpf_completo) then
    insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
    values (v_uid, 'perfis', lower(tg_op), new.id,
            case when tg_op = 'UPDATE' then jsonb_build_object('cargo', old.cargo, 'status', old.status, 'areas', old.areas,
                                                               'funcoes', old.funcoes, 'cpf', old.pode_ver_cpf_completo) end,
            jsonb_build_object('cargo', new.cargo, 'status', new.status, 'areas', new.areas, 'funcoes', new.funcoes,
                               'cpf', new.pode_ver_cpf_completo, 'via', v_papel));
  end if;
  return new;
end
$function$;
revoke all on function acesso.tg_perfis_guarda() from public, anon, authenticated;

do $c$
begin
  if has_function_privilege('authenticated', 'public.acesso_perfil_atualizar_como(uuid,uuid,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.acesso_perfil_atualizar_como(uuid,uuid,jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.acesso_perfil_atualizar_como(uuid,uuid,jsonb)', 'execute') then
    raise exception '20261007y: permissão errada em acesso_perfil_atualizar_como';
  end if;
  if (select prosrc from pg_proc where oid = 'acesso.tg_perfis_guarda()'::regprocedure) !~ '20261007y([^0-9a-z]|$)' then
    raise exception '20261007y: gatilho não foi recriado';
  end if;
end
$c$;

-- REVERSÃO (numa transação; se a rota já usa a RPC, reverter a rota junto): script pronto em
-- .maestri/entregas/niveis-de-acesso/rollback-b2.sql (cérebro), ensaiado em 20261007y_ensaio.sql.
-- select blindagem.autorizar_guarda('rollback do B2 (20261007y)');
-- do $v$ declare r record; begin
--   for r in select * from acesso.corpo_antes where migration = '20261007y' and tipo = 'funcao' loop execute r.definicao; end loop;
-- end $v$;
-- drop function if exists public.acesso_perfil_atualizar_como(uuid, uuid, jsonb);

select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '2 depois', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha) select 'diferencas', coalesce((select jsonb_agg(jsonb_build_object('perfil', x.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> x.key -> g.key)) from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') xa cross join lateral jsonb_each(xa.j) x cross join lateral jsonb_each(x.value) g cross join (select linha::jsonb j from pg_temp._z_out where passo = '2 depois') y where (y.j -> x.key -> g.key) is distinct from g.value), '[]')::text;

-- ===== PROVAS =====
-- service_role sem autor muda acesso direto → recusado
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $t$ begin update public.perfis set areas = coalesce(areas, '{}') || '{ensaio}'::text[] where id = '9d5fb8e7-f61e-459d-be04-d103ec783c08';
  insert into pg_temp._z_out (passo, linha) values ('b2 service_role sem autor muda áreas', 'passou (esperado na y; a recusa é da y2)');
exception when others then insert into pg_temp._z_out (passo, linha) values ('b2 service_role sem autor muda áreas', sqlstate || ' ' || sqlerrm); end $t$;
do $t$ begin update public.perfis set avatar_url = avatar_url, atualizado_em = now() where id = '9d5fb8e7-f61e-459d-be04-d103ec783c08';
  insert into pg_temp._z_out (passo, linha) values ('b2 service_role sem autor só atualizado_em', 'passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('b2 service_role sem autor só atualizado_em', sqlstate || ' ' || sqlerrm); end $t$;
-- pela RPC, com autor master → passa e o log grava o autor
insert into pg_temp._z_out (passo, linha) select 'b2 RPC autor Victor muda áreas do Luis', public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', '9d5fb8e7-f61e-459d-be04-d103ec783c08', '{"areas":["ativacao","social_media","ensaio2"]}')::text;
insert into pg_temp._z_out (passo, linha) select 'b2 log: autor é o Victor', (select jsonb_build_object('autor_victor', autor = '81d2eaee-cce1-4058-8714-439b0fc6f970', 'via', depois ->> 'via') from acesso.log where tabela = 'perfis' and perfil_id = '9d5fb8e7-f61e-459d-be04-d103ec783c08' order by id desc limit 1)::text;
insert into pg_temp._z_out (passo, linha) select 'b2 RPC autor Isabela (exceção) muda status do guilherme', public.acesso_perfil_atualizar_como('e1d2863d-c975-46bd-b35f-45b1039328e3', '46b36c51-06a6-4062-9e8f-41d2579b50c8', '{"status":"ativo","time":"Audiovisual"}')::text;
do $t$ begin perform public.acesso_perfil_atualizar_como('e1d2863d-c975-46bd-b35f-45b1039328e3', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '{"time":"Ensaio"}');
  insert into pg_temp._z_out (passo, linha) values ('b2 RPC autor Isabela (exceção) muda perfil do Arthur (master)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('b2 RPC autor Isabela (exceção) muda perfil do Arthur (master)', sqlstate || ' ' || sqlerrm); end $t$;
insert into pg_temp._z_out (passo, linha) select 'b2 RPC autor Victor (master) muda perfil do Arthur (master)', public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', jsonb_build_object('time', (select "time" from public.perfis where id = '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975')))::text;
do $t$ begin perform public.acesso_perfil_atualizar_como('9d5fb8e7-f61e-459d-be04-d103ec783c08', '46b36c51-06a6-4062-9e8f-41d2579b50c8', '{"status":"negado"}');
  insert into pg_temp._z_out (passo, linha) values ('b2 RPC autor Luis (não master)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('b2 RPC autor Luis (não master)', sqlstate || ' ' || sqlerrm); end $t$;
do $t$ begin perform public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', 'b65dc9c1-8edb-4e7a-ae07-681555523093', '{"cargo":"admin"}');
  insert into pg_temp._z_out (passo, linha) values ('b2 RPC autor Victor dá admin ao Iromar', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('b2 RPC autor Victor dá admin ao Iromar', sqlstate || ' ' || sqlerrm); end $t$;
do $t$ begin update public.perfis set status = 'ativo' where id = '9d5fb8e7-f61e-459d-be04-d103ec783c08' and false;
  insert into pg_temp._z_out (passo, linha) values ('b2 depois da RPC o autor não fica na transação (update vazio)', 'passou');
end $t$;
insert into pg_temp._z_out (passo, linha) select 'b2 acesso.autor depois da RPC', coalesce(nullif(current_setting('acesso.autor', true), ''), '(vazio)');
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
do $t$ begin perform public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', '46b36c51-06a6-4062-9e8f-41d2579b50c8', '{"status":"ativo"}');
  insert into pg_temp._z_out (passo, linha) values ('b2 authenticated chama a RPC', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('b2 authenticated chama a RPC', sqlstate || ' ' || sqlerrm); end $t$;
reset role;
-- logado (master) mudando acesso direto continua com autor = auth.uid()
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
update public.perfis set areas = areas where id = '9d5fb8e7-f61e-459d-be04-d103ec783c08';
-- volta o Luis
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', '9d5fb8e7-f61e-459d-be04-d103ec783c08', '{"areas":["ativacao","social_media"]}');
select set_config('request.jwt.claims', '{}', true);

-- ===== ROLLBACK =====
-- Rollback do B2 parte 1 (migration 20261007y_acesso_autor_da_rota). Numa transação (aplica_sql.py aplicar).
-- Se a 20261007y2 (recusa sem autor) estiver aplicada, rodar antes o rollback-b2-parte2.sql. Se a rota de Usuários já
-- usa a RPC acesso_perfil_atualizar_como em produção, reverter a rota junto (sem a RPC, a rota nova falha).
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $bl$ begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('rollback do B2 de níveis de acesso (20261007y)');
  end if;
end $bl$;
do $v$ declare r record; begin
  for r in select * from acesso.corpo_antes where migration = '20261007y' and tipo = 'funcao' loop execute r.definicao; end loop;
end $v$;
drop function if exists public.acesso_perfil_atualizar_como(uuid, uuid, jsonb);
do $c$ begin
  if (select prosrc from pg_proc where oid = 'acesso.tg_perfis_guarda()'::regprocedure) ~ '20261007y' then
    raise exception 'rollback B2: gatilho não voltou';
  end if;
end $c$;

select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '3 depois do rollback', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha) select 'diferencas depois do rollback', coalesce((select jsonb_agg(jsonb_build_object('perfil', x.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> x.key -> g.key)) from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') xa cross join lateral jsonb_each(xa.j) x cross join lateral jsonb_each(x.value) g cross join (select linha::jsonb j from pg_temp._z_out where passo = '3 depois do rollback') y where (y.j -> x.key -> g.key) is distinct from g.value), '[]')::text;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
