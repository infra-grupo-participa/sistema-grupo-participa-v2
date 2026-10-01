-- 20261005e — Ficha do aluno ganha o funil da placa (entrevista, sala, lembrete, ciclo, dias parado).
-- Padrão z57: a definição da view/função NÃO existe completa no repo; o patch é aplicado sobre o
-- corpo VIVO (pg_get_viewdef / pg_get_functiondef), com conferência da âncora antes de trocar.
-- Sem DROP: create or replace só ACRESCENTA colunas no fim da view (cs.vw_central_alunos depende dela).
-- fn_aluno_360 (setof vw_aluno_360) absorve as colunas sozinha; fn_aluno_360_safe lista colunas → patch.
-- reloptions da view = NULL (medido 01/10): create or replace sem WITH não perde security_invoker/barrier.
-- O SELECT direto de authenticated na view foi fechado na 20261005h (aplicada antes desta).

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $mig$
declare
  v_def text := pg_get_viewdef('public.vw_aluno_360'::regclass, true);
  v_ancora text := E'hm.contato_hm_id IS NOT NULL AS tem_esteira_hm\n   FROM';
begin
  if position('placa_dias_parado' in v_def) > 0 then
    raise notice 'vw_aluno_360 já tem as colunas do funil — nada a fazer';
  elsif position(v_ancora in v_def) = 0 then
    raise exception 'vw_aluno_360 mudou: âncora tem_esteira_hm não encontrada — revisar a migration';
  else
    v_def := replace(v_def, v_ancora,
      E'hm.contato_hm_id IS NOT NULL AS tem_esteira_hm,\n'
      || E'    ps.entrevista_hora AS placa_entrevista_hora,\n'
      || E'    ps.entrevista_link IS NOT NULL AS placa_tem_link_zoom,\n'
      || E'    ps.reminder_sent_at AS placa_lembrete_em,\n'
      || E'    ps.ciclo AS placa_ciclo,\n'
      || E'    ps.nivel AS placa_nivel_declarado,\n'
      || E'    CASE WHEN ps.status IN (''concluido'', ''rejeitado'', ''cadastro_concluido'') THEN NULL\n'
      || E'         ELSE CURRENT_DATE - ps.updated_at::date END AS placa_dias_parado\n   FROM');
    execute 'create or replace view public.vw_aluno_360 as ' || v_def;
  end if;
end
$mig$;

do $mig$
declare
  v_def text := pg_get_functiondef('public.fn_aluno_360_safe(uuid)'::regprocedure);
  v_ancora text := 'v.placa_rastreio, v.placa_entrevista_data, v.placa_regularizacao_pendente,';
begin
  if position('v.placa_dias_parado' in v_def) > 0 then
    raise notice 'fn_aluno_360_safe já expõe o funil — nada a fazer';
  elsif position(v_ancora in v_def) = 0 then
    raise exception 'fn_aluno_360_safe mudou: âncora placa_regularizacao_pendente não encontrada';
  elsif position('gp_eh_equipe' in v_def) = 0 then
    raise exception 'fn_aluno_360_safe perdeu a guarda gp_eh_equipe — não recriar sem ela';
  else
    execute replace(v_def, v_ancora, v_ancora
      || E'\n        v.placa_entrevista_hora, v.placa_tem_link_zoom, v.placa_lembrete_em,'
      || E'\n        v.placa_ciclo, v.placa_nivel_declarado, v.placa_dias_parado,');
  end if;
end
$mig$;

-- Trava LGPD (incidente 28/09): só equipe. A guarda no corpo continua; a ACL é reafirmada.
revoke all on function public.fn_aluno_360(uuid), public.fn_aluno_360_safe(uuid) from public, anon;
grant execute on function public.fn_aluno_360(uuid), public.fn_aluno_360_safe(uuid) to authenticated, service_role;

-- REVERSÃO: colunas de view não saem com create or replace. Para desfazer:
--   1) recriar fn_aluno_360_safe sem a linha das 6 colunas novas (pg_get_functiondef + replace inverso);
--   2) drop view cs.vw_central_alunos; drop view public.vw_aluno_360 (cascade derruba fn_aluno_360);
--      recriar os três a partir do pg_get_viewdef/functiondef salvo antes desta migration, refazendo revoke/grant.
--   As colunas novas são inofensivas para quem não as lê — reverter só se houver motivo.
