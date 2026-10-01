-- 20261005f — Resumo diário de Placas para a equipe (+ cutucada ao candidato, DESLIGADA por flag).
-- pg_cron → ops.cron_post → POST /api/cron/placas-resumo, 11:00 UTC (08h BRT), seg–sex.
--
-- Rota: web/app/api/cron/placas-resumo/route.ts — mesma autenticação do lembrete (20261005b):
--   Bearer = env CRON_SECRET OU a chave 'placas_cron_secret' do Vault, conferida por
--   public.fn_placas_cron_chave_ok (service_role). Esta migration NÃO cria chave: reaproveita a da 20261005b
--   (aplicar a 20261005b antes; sem a chave o command devolve 0 linhas e nada é chamado).
--
-- Duas funções novas, só service_role executa (Supabase concede EXECUTE a anon/authenticated por default
-- privileges em public; revogado explicitamente + conferido no fim):
--   fn_placas_resumo_contagens(p_horas_novos)   — UMA query agregada (count(*) filter) em 191 linhas.
--   fn_placas_cutucada_reivindicar(p_limite, p_max_dias) — UPDATE ... RETURNING idempotente
--     (cutucada_agendar_at is null → now()). Só é chamada se thb_placas_config.cutucada_ativa = true.
--     VOLATILE (grava). Exige a 20261005i: sem ela o trigger de updated_at move updated_at/admin_attention_at
--     no carimbo (zera o "parado" e acende "nova atividade" para a equipe).
-- Ambas SECURITY INVOKER: quem chama é o service_role (bypass de RLS), nada de definer.

-- Tipos medidos em prod (01/10): entrevista_data date, email text, token uuid; auditoria_step ∈ {-1,0,1,3,4,5,6}.
-- Explain medido do resumo: Seq Scan 191 linhas, 0,67 ms — sem índice.

-- 1) Contagens do resumo (só números; nenhuma coluna de PII sai daqui).
create or replace function public.fn_placas_resumo_contagens(p_horas_novos integer default 24)
returns table (
  aguardando_analise        bigint,
  docs_aprovados_sem_entrevista bigint,
  entrevistas_hoje          bigint,
  entrevistas_sem_desfecho  bigint,
  parados_enviado           bigint,
  parados_em_auditoria      bigint,
  parados_docs_aprovados    bigint,
  parados_placa_postada     bigint,
  parados_rascunho          bigint,
  novos                     bigint
)
language sql
stable
security invoker
set search_path = ''
as $fn$
  with p as (
    select (now() at time zone 'America/Sao_Paulo')::date as hoje,
           now() - interval '3 days' as corte_parado,
           now() - make_interval(hours => least(greatest(coalesce(p_horas_novos, 24), 1), 168)) as corte_novos
  )
  select
    count(*) filter (where s.status in ('enviado', 'em_auditoria')
                       and (not coalesce(s.regularizacao_pendente, false)
                            or (s.proof_url is not null and s.declaracao_url is not null))),
    count(*) filter (where s.status = 'docs_aprovados' and s.auditoria_step = 1),
    count(*) filter (where s.status = 'docs_aprovados' and s.auditoria_step = 2
                       and s.entrevista_data = p.hoje),
    count(*) filter (where s.status = 'docs_aprovados' and s.auditoria_step = 2
                       and s.entrevista_data is not null and s.entrevista_data < p.hoje),
    count(*) filter (where s.status = 'enviado' and s.updated_at < p.corte_parado
                       and not (coalesce(s.regularizacao_pendente, false) and (s.proof_url is null or s.declaracao_url is null))),
    count(*) filter (where s.status = 'em_auditoria' and s.updated_at < p.corte_parado
                       and not (coalesce(s.regularizacao_pendente, false) and (s.proof_url is null or s.declaracao_url is null))),
    count(*) filter (where s.status = 'docs_aprovados' and s.updated_at < p.corte_parado
                       and not (coalesce(s.regularizacao_pendente, false) and (s.proof_url is null or s.declaracao_url is null))),
    count(*) filter (where s.status = 'placa_postada' and s.updated_at < p.corte_parado),
    count(*) filter (where s.status = 'rascunho' and s.updated_at < p.corte_parado),
    count(*) filter (where s.status in ('enviado', 'em_auditoria') and s.admin_attention_at >= p.corte_novos)
  from public.thb_placas_solicitacoes s
  cross join p
$fn$;

revoke all on function public.fn_placas_resumo_contagens(integer) from public, anon, authenticated;
grant execute on function public.fn_placas_resumo_contagens(integer) to service_role;

-- 2) Cutucada: reivindica até 30 candidatos parados (bola com o candidato) e devolve o necessário p/ o e-mail.
--    "Bola com o candidato": rascunho; documentação aprovada sem agendar (step 1); correção pedida e não reenviada.
--    Parado = updated_at entre p_max_dias e 3 dias atrás. Uma vez só: cutucada_agendar_at fica carimbado.
--    FOR UPDATE SKIP LOCKED + "is null" no UPDATE: execuções sobrepostas não reivindicam a mesma linha.
create or replace function public.fn_placas_cutucada_reivindicar(p_limite integer default 30, p_max_dias integer default 30)
returns table (id text, token text, nome text, email text, carimbo timestamptz)
language sql
volatile
security invoker
set search_path = ''
as $fn$
  with alvo as (
    select s.id
      from public.thb_placas_solicitacoes s
     where s.cutucada_agendar_at is null
       and s.status not in ('concluido', 'rejeitado', 'cadastro_concluido')
       and (   (s.status = 'rascunho' and not coalesce(s.regularizacao_pendente, false))
            or (s.status = 'docs_aprovados' and s.auditoria_step = 1)
            or (coalesce(s.regularizacao_pendente, false) and (s.proof_url is null or s.declaracao_url is null)))
       and s.updated_at < now() - interval '3 days'
       and s.updated_at >= now() - make_interval(days => greatest(coalesce(p_max_dias, 30), 3))
       and nullif(btrim(s.email), '') is not null
       and s.token is not null
     order by s.updated_at
     limit least(greatest(coalesce(p_limite, 30), 1), 30)
     for update of s skip locked
  )
  update public.thb_placas_solicitacoes u
     set cutucada_agendar_at = now()
    from alvo
   where u.id = alvo.id
     and u.cutucada_agendar_at is null
  returning u.id::text, u.token::text, u.nome::text, btrim(u.email), u.cutucada_agendar_at
$fn$;

revoke all on function public.fn_placas_cutucada_reivindicar(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_placas_cutucada_reivindicar(integer, integer) to service_role;

-- 3) Pós-condição: nenhuma das duas executável por anon/authenticated (nem via PUBLIC).
do $mig$
begin
  if has_function_privilege('anon', 'public.fn_placas_resumo_contagens(integer)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_placas_resumo_contagens(integer)', 'execute')
     or has_function_privilege('anon', 'public.fn_placas_cutucada_reivindicar(integer, integer)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_placas_cutucada_reivindicar(integer, integer)', 'execute') then
    raise exception '20261005f: função de resumo/cutucada executável por anon/authenticated';
  end if;
end
$mig$;

-- 4) Agendamento (idempotente). Chave lida do Vault no command, nunca literal.
do $mig$
begin
  if exists (select 1 from cron.job where jobname = 'placas-resumo-diario') then
    perform cron.unschedule('placas-resumo-diario');
  end if;

  perform cron.schedule('placas-resumo-diario', '0 11 * * 1-5', $cron$
    select ops.cron_post(
      'placas-resumo-diario',
      url := 'https://grupoparticipa.app.br/api/cron/placas-resumo',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'Authorization', 'Bearer ' || s.decrypted_secret),
      timeout_milliseconds := 120000)
    from vault.decrypted_secrets s
    where s.name = 'placas_cron_secret'
  $cron$);
end
$mig$;

-- REVERSÃO:
--   select cron.unschedule('placas-resumo-diario');
--   drop function if exists public.fn_placas_cutucada_reivindicar(integer, integer);
--   drop function if exists public.fn_placas_resumo_contagens(integer);
--   -- cutucadas já carimbadas (só existem se a flag foi ligada):
--   --   select count(*) from public.thb_placas_solicitacoes where cutucada_agendar_at is not null;
--   -- (opcional) delete from ops.rotina where jobname = 'placas-resumo-diario';
--   -- A chave 'placas_cron_secret' é da 20261005b — não apagar aqui.
