-- 20261001d — Vigia das rotinas (4/5): visão de saúde + RPC só para admin.
--
-- ops.vw_saude_rotinas   uma linha por cron.job (menos o próprio vigia), com a situação calculada.
-- public.ops_saude_rotinas()  jsonb; SECURITY DEFINER, search_path '', guarda public.gp_is_admin()
--   (perfis.cargo in ('dev','admin') e status 'ativo'). Não-admin → 42501. anon/PUBLIC sem EXECUTE.
--   Não devolve command nem command_antes (mesmo sem segredo, é detalhe de infra que a tela não usa).
--   Retorna jsonb e não setof ops.* porque authenticated não tem USAGE no schema ops.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

create view ops.vw_saude_rotinas as
select j.jobid, j.jobname, j.schedule, j.active as ativa,
       case when not j.active then 'desligada'
            when e.incidente_aberto_em is not null then 'com_problema'
            when r.silenciado_ate > now() then 'silenciada'
            when e.ultimo_evento_em is null then 'sem_dados'
            when e.consec_falhas > 0 then 'oscilando'
            else 'ok' end as situacao,
       e.rastreio, e.consec_falhas, e.consec_ok, e.ultimo_ok_em, e.ultimo_evento_em, e.ultima_classe, e.ultimo_erro,
       e.incidente_aberto_em, e.incidente_motivo, e.observado_desde,
       r.n_falhas, r.janela, r.k_ok, r.intervalo, r.intervalo_fonte, r.silenciado_ate,
       (select c.atualizado_em from ops.config c where c.id) as vigia_ultimo_ciclo,
       (select c.enviar from ops.config c where c.id) as vigia_envia_slack
  from cron.job j
  left join ops.rotina r on r.jobname = j.jobname
  left join ops.rotina_estado e on e.jobname = j.jobname
 where j.jobname <> 'ops-vigia-10min';

create function public.ops_saude_rotinas() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not coalesce(public.gp_is_admin(), false) then
    raise exception 'acesso negado' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(v) order by
                   case v.situacao when 'com_problema' then 0 when 'oscilando' then 1 when 'sem_dados' then 2
                                   when 'silenciada' then 3 when 'ok' then 4 else 5 end, v.jobname), '[]'::jsonb)
            from ops.vw_saude_rotinas v);
end
$f$;
comment on function public.ops_saude_rotinas() is 'Saúde das rotinas pg_cron/pg_net para a tela de admin. Só gp_is_admin(). ADR 0001.';

revoke all on ops.vw_saude_rotinas from public, anon, authenticated;
revoke execute on function public.ops_saude_rotinas() from public, anon;
grant execute on function public.ops_saude_rotinas() to authenticated;

do $pos$
begin
  if has_function_privilege('anon', 'public.ops_saude_rotinas()', 'execute') then
    raise exception '20261001d: anon executa ops_saude_rotinas';
  end if;
  if (select prosecdef from pg_proc where oid = 'public.ops_saude_rotinas()'::regprocedure) is not true
     or (select proconfig from pg_proc where oid = 'public.ops_saude_rotinas()'::regprocedure) is distinct from array['search_path=""'] then
    raise exception '20261001d: RPC sem SECURITY DEFINER/search_path vazio';
  end if;
end
$pos$;
