-- Migração: rede de segurança contra perda de entrevista de placa
-- Aplicada em produção (mbvybujpkwuorhtdzcde) via Supabase MCP em 2026-07-06.
--
-- Contexto: em 2026-07-03 um UPDATE em massa ad-hoc (fora do código) reescreveu 47 linhas de
-- thb_placas_auditoria e, como a entrevista vivia só em thb_placas_solicitacoes.entrevista_data
-- (campo mutável) sem trilha durável, várias entrevistas sumiram sem rastro recuperável
-- (ex.: caso Rochele, agendada por fora, ficou sem qualquer registro).
--
-- Esta trigger registra em thb_placas_agendamento_logs TODA remoção/remarcação de uma entrevista
-- já existente, independente da origem (app, SQL manual, script), vinculada a aluno/solicitação/token.
-- A partir dela, qualquer perda futura é sempre recuperável.

CREATE OR REPLACE FUNCTION public.fn_log_entrevista_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Só interessa quando havia entrevista e ela foi apagada ou movida.
  IF OLD.entrevista_data IS NOT NULL
     AND OLD.entrevista_data IS DISTINCT FROM NEW.entrevista_data THEN
    INSERT INTO public.thb_placas_agendamento_logs
      (solicitacao_id, aluno_id, token, origem, evento, status, detalhe, slot_data, slot_hora, payload)
    VALUES (
      OLD.id,
      OLD.aluno_id,
      OLD.token,
      'trigger:solicitacao',
      'entrevista_alterada',
      CASE WHEN NEW.entrevista_data IS NULL THEN 'entrevista_removida' ELSE 'entrevista_remarcada' END,
      'Entrevista alterada — valor anterior preservado para recuperação.',
      OLD.entrevista_data,
      OLD.entrevista_hora,
      jsonb_build_object(
        'de',   jsonb_build_object('data', OLD.entrevista_data, 'hora', OLD.entrevista_hora,
                                   'link', OLD.entrevista_link, 'step_index', OLD.step_index,
                                   'auditoria_step', OLD.auditoria_step, 'status', OLD.status),
        'para', jsonb_build_object('data', NEW.entrevista_data, 'hora', NEW.entrevista_hora,
                                   'link', NEW.entrevista_link, 'step_index', NEW.step_index,
                                   'auditoria_step', NEW.auditoria_step, 'status', NEW.status)
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_entrevista_change ON public.thb_placas_solicitacoes;
CREATE TRIGGER trg_log_entrevista_change
  AFTER UPDATE OF entrevista_data, entrevista_hora ON public.thb_placas_solicitacoes
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_log_entrevista_change();
