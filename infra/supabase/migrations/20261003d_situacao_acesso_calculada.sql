-- 20261003d — Situação de acesso calculada numa função só (desenho 1.5)
--
-- DONO DA REGRA: sistema-disparos-participa/db/migrations/0045_situacao_acesso_derivada.sql criou
--   public.fn_recalcular_situacao_acesso() (create or replace). REAPLICAR A 0045 DESFAZ ESTA MIGRATION. Avisar a Ativação.
--
-- O QUE FAZ
--   1. public.fn_aluno_situacao_calculada() → (aluno_id, situacao, status, preservado, motivo_preserva)
--      Só alunos ativos (cancelado_em is null). situacao/status = regra da 0045, sem mudança:
--        sócio (eh_socio ou regra_acesso = 'Acompanha titular') → acompanha_titular (status preservado);
--        sem data_expiracao → preserva situação e status; < hoje → vencido; ≤ hoje+30 → a_vencer; senão em_dia;
--        status: gratuidade fica; vencido; renovado fica; senão vigente.
--      preservado = a rotina NÃO grava; motivo_preserva = o primeiro que bate:
--        'sem_acesso' (situacao_acesso = 'sem_acesso') · 'acessos_revogados' (acessos_revogados_em not null)
--        · 'tratamento_manual' (tratamento_manual preenchido).
--      language sql, stable, SECURITY INVOKER, sem SET (inlinável). Sem EXECUTE para public/anon/authenticated:
--      leitores são funções SECURITY DEFINER do owner (a rotina abaixo e fn_aluno_conciliacao).
--   2. public.fn_recalcular_situacao_acesso() reescrita: update … from fn_aluno_situacao_calculada() where not preservado.
--      Mesma assinatura (returns integer), SECURITY DEFINER, search_path public, pg_temp, mesmo evento em
--      thb_system_events, mesmo ACL (só service_role, 20260928z58; a conferência prova antes = depois).
--      Mudança de comportamento: não toca aluno cancelado nem preservado (a 0045 tocava).
--   NÃO executa a rotina. O job do cron (command com fn_recalcular_situacao_acesso) segue active=false: a guarda ABORTA
--   se ele estiver ativo. Religar é decisão à parte.
--
-- AS 5 PERGUNTAS
--   escala: 1 passada em thb_alunos (~2 mil ativos); 10x = 20 mil, seq scan linear, 1x/dia.
--   índice: nenhum (varredura total é o caso de uso); update por PK.
--   frequência: rotina 1x/dia quando religada; a conciliação lê a função 1x por abertura da página.
--   repetição: a regra existe em 1 lugar (esta função); conciliação e rotina leem a mesma.
--   reversão: bloco REVERSÃO no fim (corpo vivo da 0045, conferido pela guarda) + drop da função calculada.
--
-- ENSAIO: infra/supabase/migrations/20261003d_ensaio.sql (regra antiga × nova, rotina dentro do rollback, 2ª rodada 0).

set local lock_timeout = '3s';

-- ─── 0. Guardas ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_src   text;
  v_n     int;
  v_falta text;
begin
  -- 0.1 o job da rotina tem que estar DESLIGADO (religar é decisão à parte)
  select count(*) into v_n from cron.job j where j.command ilike '%fn_recalcular_situacao_acesso%' and j.active;
  if v_n > 0 then
    raise exception '20261003d: job do cron com fn_recalcular_situacao_acesso está ATIVO (%): desligar ou decidir antes', v_n;
  end if;
  -- 0.2 corpo vivo = 0045 (md5 sem comentários e sem espaços) ou já esta versão
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.fn_recalcular_situacao_acesso()');
  if v_src is null then
    raise exception '20261003d: public.fn_recalcular_situacao_acesso() não existe';
  end if;
  if md5(regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s', '', 'g')) <> '1193539e1d62e23a5ee8f64f8d75c7dd'
     and position('fn_aluno_situacao_calculada' in v_src) = 0 then
    raise exception '20261003d: corpo vivo de fn_recalcular_situacao_acesso difere da 0045 (md5 normalizado %) — parar e comparar',
      md5(regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s', '', 'g'));
  end if;
  if pg_get_function_result('public.fn_recalcular_situacao_acesso()'::regprocedure) <> 'integer' then
    raise exception '20261003d: fn_recalcular_situacao_acesso não devolve integer';
  end if;
  -- 0.3 colunas
  select string_agg(x.c, ', ') into v_falta
    from unnest(array['id','eh_socio','regra_acesso','data_expiracao','situacao_acesso','status_acesso','atualizado_em',
                      'acessos_revogados_em','tratamento_manual','cancelado_em']) x(c)
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema = 'public' and c.table_name = 'thb_alunos' and c.column_name = x.c);
  if v_falta is not null then
    raise exception '20261003d: thb_alunos sem coluna(s): %', v_falta;
  end if;
  -- 0.4 ACL da rotina, para a conferência
  perform set_config('z20261003d.acl',
    (select coalesce(array_to_string(array(select x::text from unnest(p.proacl) x order by 1), ','), '<null>')
       from pg_proc p where p.oid = 'public.fn_recalcular_situacao_acesso()'::regprocedure), false);
end $guarda$;

-- ─── 1. Regra pura ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_situacao_calculada()
returns table (aluno_id uuid, situacao text, status text, preservado boolean, motivo_preserva text)
language sql
stable
as $fn$
  select a.id,
         (case
            when a.eh_socio or coalesce(a.regra_acesso, '') = 'Acompanha titular' then 'acompanha_titular'
            when a.data_expiracao is null                     then a.situacao_acesso  -- sem base: preserva
            when a.data_expiracao <  current_date             then 'vencido'
            when a.data_expiracao <= current_date + 30        then 'a_vencer'
            else 'em_dia'
          end)::text,
         (case
            when a.status_acesso = 'gratuidade'               then 'gratuidade'
            when a.eh_socio or coalesce(a.regra_acesso, '') = 'Acompanha titular' then a.status_acesso
            when a.data_expiracao is null                     then a.status_acesso
            when a.data_expiracao <  current_date             then 'vencido'
            when a.status_acesso = 'renovado'                 then 'renovado'
            else 'vigente'
          end)::text,
         (m.motivo is not null),
         m.motivo
    from public.thb_alunos a
   cross join lateral (
     select case when a.situacao_acesso = 'sem_acesso'                     then 'sem_acesso'
                 when a.acessos_revogados_em is not null                   then 'acessos_revogados'
                 when nullif(btrim(a.tratamento_manual::text), '') is not null then 'tratamento_manual'
            end as motivo) m
   where a.cancelado_em is null
$fn$;

comment on function public.fn_aluno_situacao_calculada() is
  '20261003d: situação/status de acesso calculados (regra da 0045) para alunos ativos, com preservado/motivo '
  '(sem_acesso, acessos_revogados, tratamento_manual). Interna: sem EXECUTE para public/anon/authenticated.';

revoke all on function public.fn_aluno_situacao_calculada() from public, anon, authenticated;

-- ─── 2. Rotina lê a regra pura ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_recalcular_situacao_acesso()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_mudados integer;
begin
  -- guarda: rotina de sistema (cron como postgres, ou service_role). Nunca pela API pública.
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    raise exception 'fn_recalcular_situacao_acesso: rotina de sistema' using errcode = '42501';
  end if;

  -- regra em public.fn_aluno_situacao_calculada() (20261003d): só ativos; preserva sem_acesso/revogado/manual
  update public.thb_alunos a
     set situacao_acesso = c.situacao,
         status_acesso   = c.status,
         atualizado_em   = now()
    from public.fn_aluno_situacao_calculada() c
   where a.id = c.aluno_id
     and not c.preservado
     and (a.situacao_acesso is distinct from c.situacao
       or a.status_acesso   is distinct from c.status);

  get diagnostics v_mudados = row_count;

  if v_mudados > 0 then
    insert into public.thb_system_events (tipo, fonte, titulo, detalhe)
    values ('info', 'cron', 'Situação de acesso recalculada',
            jsonb_build_object('alunos_atualizados', v_mudados));
  end if;

  return v_mudados;
end
$fn$;

-- ─── 3. Conferência ─────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
declare v_acl text;
begin
  select coalesce(array_to_string(array(select x::text from unnest(p.proacl) x order by 1), ','), '<null>') into v_acl
    from pg_proc p where p.oid = 'public.fn_recalcular_situacao_acesso()'::regprocedure;
  if v_acl is distinct from current_setting('z20261003d.acl', true) then
    raise exception '20261003d: ACL da rotina mudou: antes % / depois %', current_setting('z20261003d.acl', true), v_acl;
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'public.fn_recalcular_situacao_acesso()'::regprocedure
                    and p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']) then
    raise exception '20261003d: rotina sem SECURITY DEFINER/search_path';
  end if;
  if exists (select 1 from pg_proc p where p.oid = 'public.fn_aluno_situacao_calculada()'::regprocedure
                and (p.prosecdef or p.proconfig is not null or p.provolatile <> 's'
                     or p.prolang <> (select oid from pg_language where lanname = 'sql'))) then
    raise exception '20261003d: fn_aluno_situacao_calculada deixou de ser inlinável';
  end if;
  if exists (select 1 from unnest(array['public.fn_aluno_situacao_calculada()', 'public.fn_recalcular_situacao_acesso()']) f
              where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
                 or exists (select 1 from pg_proc p where p.oid = f::regprocedure
                              and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) g
                                                                where g.grantee = 0 and g.privilege_type = 'EXECUTE')))) then
    raise exception '20261003d: função executável por PUBLIC/anon/authenticated';
  end if;
  if exists (select 1 from cron.job j where j.command ilike '%fn_recalcular_situacao_acesso%' and j.active) then
    raise exception '20261003d: job ficou ativo';
  end if;
end $confere$;

-- ─── REVERSÃO (NÃO executar junto). Corpo vivo = 0045 (a guarda 0.2 provou md5 igual antes de aplicar) ──────────
-- create or replace function public.fn_recalcular_situacao_acesso()
-- returns integer
-- language plpgsql
-- security definer
-- set search_path = public, pg_temp
-- as $fn$
-- declare
--   v_mudados integer;
-- begin
--   with alvo as (
--     select a.id,
--            case
--              when a.eh_socio or coalesce(a.regra_acesso,'') = 'Acompanha titular' then 'acompanha_titular'
--              when a.data_expiracao is null                     then a.situacao_acesso  -- sem base: preserva
--              when a.data_expiracao <  current_date             then 'vencido'
--              when a.data_expiracao <= current_date + 30        then 'a_vencer'
--              else 'em_dia'
--            end as nova_situacao,
--            case
--              when a.status_acesso = 'gratuidade'               then 'gratuidade'
--              when a.eh_socio or coalesce(a.regra_acesso,'') = 'Acompanha titular' then a.status_acesso
--              when a.data_expiracao is null                     then a.status_acesso
--              when a.data_expiracao <  current_date             then 'vencido'
--              when a.status_acesso = 'renovado'                 then 'renovado'
--              else 'vigente'
--            end as novo_status
--       from public.thb_alunos a
--   )
--   update public.thb_alunos a
--      set situacao_acesso = alvo.nova_situacao,
--          status_acesso   = alvo.novo_status,
--          atualizado_em   = now()
--     from alvo
--    where a.id = alvo.id
--      and (a.situacao_acesso is distinct from alvo.nova_situacao
--        or a.status_acesso   is distinct from alvo.novo_status);
--
--   get diagnostics v_mudados = row_count;
--
--   if v_mudados > 0 then
--     insert into public.thb_system_events (tipo, fonte, titulo, detalhe)
--     values ('info', 'cron', 'Situação de acesso recalculada',
--             jsonb_build_object('alunos_atualizados', v_mudados));
--   end if;
--
--   return v_mudados;
-- end$fn$;
-- -- (grants: create or replace preserva o ACL — só service_role, 20260928z58)
-- drop function if exists public.fn_aluno_situacao_calculada();   -- só depois de reverter a 20261003e, que a lê
