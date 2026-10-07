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
--      mesmo cargo: os mesmos que a rota deixa entrar), grava p_autor na transação (set_config local
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
     and (select prosrc from pg_proc where oid = to_regprocedure('acesso.tg_perfis_guarda()')) !~ '20261007y' then
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
  if (select prosrc from pg_proc where oid = 'acesso.tg_perfis_guarda()'::regprocedure) !~ '20261007y' then
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
