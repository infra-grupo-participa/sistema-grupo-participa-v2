-- 20261007u: níveis de acesso, fase 3 (limpar). Tira o "velho" das guardas: gp_is_admin() passa a ser só o master
-- (acesso.master) e as guardas de financeiro, CPF, Marketing e Comercial deixam de aceitar o cargo admin/dev.
--
-- STATUS: NÃO APLICADA. SÓ DEPOIS DA FASE 2 (20261007t) APLICADA E VALIDADA PELO VICTOR HUGO. Ensaio junto com a fase
--   2 em 20261007t_ensaio.sql (rollback). Relatório: 20261007u.explain.md.
--
-- POR QUE
--   Depois da fase 2 só os 3 masters têm cargo admin/dev, então o "velho" já não abre nada a mais; esta fase tira o
--   atalho para que um cargo admin dado por engano (tela de Usuários, cadastro) não volte a abrir o sistema inteiro.
--
-- O QUE FAZ (corpo anterior de cada função guardado em acesso.corpo_antes, migration 20261007u)
--   - gp_is_admin()               = acesso.eh_master()
--   - gp_pode_ver_financeiro()    = acesso.tem('financeiro.ver')
--   - gp_pode_operar_financeiro() = acesso.tem('financeiro.operar')
--   - gp_pode_ver_cpf()           = acesso.tem('cpf.ver') ou perfis.pode_ver_cpf_completo
--   - gp_pode_editar(setor)       = gestor/operador com setor (e função, no operador), como antes, sem o ramo admin/dev,
--                                   OR a regra de acesso.* da fase 1
--   - crm.eh_gestor()             = master ou responsável do comercial, ou gestor com a área comercial (sem admin/dev)
--   - ra_pode_ver(), pa_pode_pedir(): sem o ramo admin/dev
--   - mkt.pode_ver/pode_editar    = só acesso.pode_ver/pode_editar
--   Ficam como estão (já valem só para master depois da fase 2, porque leem cargo admin/dev): crm.pode_catalogar,
--   pessoas.pode_*, e todas as funções/policies que a fase 1 deixou com "(gp_is_admin() OR editar <depto>)".
--
-- AS 5 PERGUNTAS
--   escala: 10 funções. índice: o de acesso.* (fase 0). frequência: toda RPC. repetição: nenhuma.
--   reversão: recriar os corpos de acesso.corpo_antes (migration 20261007u).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('acesso.perfis_antes_20261007') is null then
    raise exception '20261007u: a fase 2 (20261007t) não foi aplicada';
  end if;
  if (select count(*) from public.perfis where status = 'ativo' and cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007u: tem perfil admin/dev além dos 3 masters. Conferir antes de limpar.';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007u'
  from pg_proc p
 where p.oid in ('public.gp_is_admin()'::regprocedure, 'public.gp_pode_ver_financeiro()'::regprocedure,
                 'public.gp_pode_operar_financeiro()'::regprocedure, 'public.gp_pode_ver_cpf()'::regprocedure,
                 'public.gp_pode_editar(text)'::regprocedure, 'crm.eh_gestor()'::regprocedure,
                 'public.ra_pode_ver()'::regprocedure, 'public.pa_pode_pedir()'::regprocedure,
                 'mkt.pode_ver(text)'::regprocedure, 'mkt.pode_editar(text)'::regprocedure)
on conflict do nothing;

create or replace function public.gp_is_admin()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.eh_master(), false);  -- 20261007u: admin do sistema = master
$function$;

create or replace function public.gp_pode_ver_financeiro()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('financeiro.ver'), false);  -- 20261007u
$function$;

create or replace function public.gp_pode_operar_financeiro()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('financeiro.operar'), false);  -- 20261007u
$function$;

create or replace function public.gp_pode_ver_cpf()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('cpf.ver'), false)
      or exists (select 1 from public.perfis p where p.id = (select auth.uid()) and p.status = 'ativo'
                   and p.email ilike '%@advmais.com' and p.pode_ver_cpf_completo is true);  -- 20261007u
$function$;

create or replace function public.gp_pode_editar(p_setor text)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
  SELECT EXISTS (
    SELECT 1 FROM public.perfis p
    WHERE p.id = auth.uid()
      AND p.status = 'ativo'
      AND (
        (p.cargo = 'gestor' AND p_setor = ANY(coalesce(p.areas,'{}')))
        OR (p.cargo = 'operador' AND p_setor = ANY(coalesce(p.areas,'{}'))
            AND EXISTS (SELECT 1 FROM unnest(coalesce(p.funcoes,'{}')) f WHERE f LIKE p_setor || '.%'))
      )
  ) OR coalesce(acesso.eh_master(), false) OR coalesce(case  -- 20261007u
         when p_setor in ('ativacao', 'placas', 'depoimentos', 'centro_controle', 'remocao_acessos', 'pedidos_alteracao')
           then acesso.pode_editar('educacional')
         when p_setor = 'social_media' then acesso.pode_editar('marketing', 'social-media')
         when p_setor = 'comercial' then acesso.pode_editar('comercial')
         when p_setor = 'financeiro' then acesso.tem('financeiro.operar')
       end, false);
$function$;

create or replace function crm.eh_gestor()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.eh_master(), false)  -- 20261007u
      or exists (select 1 from acesso.vinculo v where v.perfil_id = acesso.eu() and v.vigente_ate is null
                   and v.departamento = 'comercial' and v.area is null and v.papel = 'responsavel')
      or coalesce((select p.status = 'ativo' and p.cargo = 'gestor' and 'comercial' = any(coalesce(p.areas, '{}'))
                     from public.perfis p where p.id = (select auth.uid())), false);
$function$;

create or replace function public.ra_pode_ver()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid()) and p.status = 'ativo'
      and p.cargo in ('gestor', 'operador') and 'remocao_acessos' = any(coalesce(p.areas, '{}'))
  ) or coalesce(acesso.pode_editar('educacional'), false);  -- 20261007u
$function$;

create or replace function public.pa_pode_pedir()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(public.gp_eh_equipe(), false) and (exists (
    select 1 from public.perfis p
     where p.id = (select auth.uid()) and p.status = 'ativo'
       and p.cargo in ('gestor', 'operador') and 'pedidos_alteracao' = any(coalesce(p.areas, '{}')))
    or coalesce(acesso.pode_editar('educacional'), false));  -- 20261007u
$function$;

create or replace function mkt.pode_ver(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.pode_ver('marketing', acesso.area_mkt(p_area)), false);  -- 20261007u
$function$;

create or replace function mkt.pode_editar(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.pode_editar('marketing', acesso.area_mkt(p_area)), false);  -- 20261007u
$function$;

do $c$
begin
  if (select prosrc from pg_proc where oid = 'public.gp_is_admin()'::regprocedure) !~ 'acesso\.eh_master' then
    raise exception '20261007u: gp_is_admin não virou master';
  end if;
end
$c$;

-- REVERSÃO (numa transação):
-- do $v$ declare r record; begin
--   for r in select * from acesso.corpo_antes where migration = '20261007u' and tipo = 'funcao' loop execute r.definicao; end loop;
-- end $v$;
