-- 20261007y2: níveis de acesso, B2 parte 2: a service_role não muda acesso em public.perfis sem dizer o autor.
--
-- STATUS: APLICADA em produção em 08/10/2026 às 20:57 UTC, versão 20261008205705 (nome acesso_autor_obrigatorio), pelo
--   aplica_sql.py aplicar + insert em supabase_migrations.schema_migrations na mesma transação; md5 gravado =
--   e257bfc9b5defd692338d40749d92164 = este arquivo antes desta troca de STATUS. Pré-requisito cumprido: a rota
--   web/app/api/admin/usuarios/route.ts usa public.acesso_perfil_atualizar_como na main (264928b, no ar desde 08/10 17:51 BRT).
--   Ensaio: 20261007y2_ensaio.sql (rodado de novo em 08/10 antes de aplicar). Relatório: 20261007204017.explain.md §2 e §7.
--
-- O QUE FAZ: recria acesso.tg_perfis_guarda (corpo da 20261007y) acrescentando a recusa: mudança de cargo, status,
--   áreas, funções ou CPF com papel service_role e sem autor (nem auth.uid() nem 'acesso.autor') → 42501. O cadastro
--   (handle_new_user, papel do Auth) e quem está logado não são afetados.
--
-- AS 5 PERGUNTAS: escala 1 gatilho; frequência rara; reversão: recriar o corpo da 20261007y (acesso.corpo_antes, 20261007y2).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $bl$
begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('níveis de acesso, B2 parte 2 (20261007y2): recusa sem autor pela service_role');
  end if;
end
$bl$;

do $g$
begin
  if to_regprocedure('public.acesso_perfil_atualizar_como(uuid,uuid,jsonb)') is null then
    raise exception '20261007y2: falta a 20261007y (RPC acesso_perfil_atualizar_como)';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007y2'
  from pg_proc p where p.oid = 'acesso.tg_perfis_guarda()'::regprocedure
on conflict do nothing;

create or replace function acesso.tg_perfis_guarda()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261007y (20261007204017): o autor é o usuário logado ou, pela rota (service_role), o master que a RPC acesso_perfil_atualizar_como gravou
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
    -- 20261007y2 (B2): pela service_role, mudança de acesso sem autor é recusada (a rota usa acesso_perfil_atualizar_como)
    if v_uid is null and v_papel = 'service_role' then
      raise exception 'Mudança de acesso pela rota exige o autor: use acesso_perfil_atualizar_como.' using errcode = '42501';
    end if;
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
  if (select prosrc from pg_proc where oid = 'acesso.tg_perfis_guarda()'::regprocedure) !~ '20261007y2' then
    raise exception '20261007y2: a recusa não entrou no gatilho';
  end if;
end
$c$;

-- REVERSÃO: do $v$ declare r record; begin
--   perform blindagem.autorizar_guarda('rollback do B2 parte 2 (20261007y2)');
--   for r in select * from acesso.corpo_antes where migration = '20261007y2' and tipo = 'funcao' loop execute r.definicao; end loop;
-- end $v$;
