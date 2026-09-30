-- 20261002c — fn_sync_placa_nivel: o nível gravado vem da placa concluída MAIS RECENTE do aluno
--
-- PROBLEMA (definição viva, md5(prosrc) = f7769ff747e1c86bd93fa59d3895b9bd):
--   SELECT nivel ... WHERE aluno_id = NEW.aluno_id AND status = 'concluido' LIMIT 1   -- sem ORDER BY
--   Aluno com mais de uma solicitação concluída recebe um nível arbitrário (ordem física/índice).
--   17 gravações do trigger em thb_alunos_audit_log (campo='nivel_resultado', origem='trigger_placas'),
--   2026-07-03 a 2026-08-17. Esta migration NÃO regrava nenhuma delas: o Marcio decide uma a uma
--   (diagnóstico no ensaio, passo 1).
--
-- REGRA NOVA (decisão do Marcio): nível da solicitação concluída mais recente do aluno.
--   * "Concluída" = status IN ('concluido', 'placa_postada').
--       concluido     : PRD docs/projetos/placas/prd.md §10.1 "processo finalizado com entrega ou encerramento positivo";
--       placa_postada : status legado (web/modules/placas/domain/solicitacao.ts:11), etapa 5 "Placa Enviada"
--                       (auditoria.ts statusForAuditStep). O nível já passou por documentação + entrevista.
--       Contagem viva (defs-vivas §5.2): concluido 37, placa_postada 13, de 191.
--   * Solicitação com nivel NULL é ignorada (antes: se a linha sorteada tivesse nivel NULL, o trigger saía sem gravar).
--   * Ordenação: updated_at DESC, id DESC.
--       thb_placas_solicitacoes NÃO tem coluna de data de conclusão (defs-vivas §3.2: só created_at e updated_at).
--       updated_at é a coluna de "última alteração" da tabela (o equivalente ao atualizado_em pedido).
--       id DESC só desempata (uuid, sem significado temporal): deixa o resultado determinístico.
--       Limitação: o app (placas-admin-data.ts avancarEtapa/setAuditStep) NÃO manda updated_at no PATCH; se não
--       houver trigger mantendo updated_at, a data reflete a última escrita que o setou (fn_placas_refazer seta).
--       O ensaio (passo 0) lista os triggers da tabela e mede quantas concluídas têm updated_at = created_at.
--   * thb_placas_ciclos fica FORA do trigger, de propósito:
--       fn_placas_refazer grava o snapshot em thb_placas_ciclos e devolve a solicitação a 'rascunho' (nivel NULL,
--       auditoria encerrado=false). O trigger só dispara na transição encerrado false -> true, que no app acontece
--       logo DEPOIS de a solicitação atual virar 'concluido' (placas-admin-data.ts: solicitação primeiro, auditoria
--       depois). Então, no encerramento, a solicitação atual concluída é sempre a comprovação mais recente; um ciclo
--       é snapshot de um estado anterior da mesma solicitação. Ler ciclos aqui só abriria a chance de regravar o
--       nível antigo quando o encerramento não vem de conclusão (ex.: rejeitar(), que também põe encerrado=true).
--
-- PRESERVADO: assinatura (trigger, sem argumento), SECURITY DEFINER, search_path 'public','pg_temp', a condição de
--   disparo, o UPDATE em thb_alunos só quando muda, o registro em public.thb_alunos_audit_log (origem='trigger_placas')
--   e o evento em public.thb_system_events. Trigger trg_sync_placa_nivel (AFTER UPDATE ON thb_placas_auditoria) intocado.
--
-- AS 5 PERGUNTAS
--   escala: 1 SELECT por encerramento de auditoria (37 encerrados na vida toda); por aluno, poucas linhas.
--   índice: idx_placas_sol_aluno_id (aluno_id) já existe (defs-vivas §4); o sort é sobre as linhas de 1 aluno.
--   frequência: só na transição encerrado false -> true.
--   repetição: nenhuma; 1 query por disparo, como antes.
--   reversão: bloco REVERSÃO no fim (definição antiga inteira).
--
-- ENSAIO: infra/supabase/migrations/20261002c_ensaio.sql (begin … rollback).

-- ─── 0. Guarda: só aplica sobre a definição conhecida ─────────────────────────────────────────────────────────────────
do $guarda$
declare v_md5 text;
begin
  select md5(p.prosrc) into v_md5
    from pg_proc p
   where p.oid = 'public.fn_sync_placa_nivel()'::regprocedure;
  if v_md5 is distinct from 'f7769ff747e1c86bd93fa59d3895b9bd' then
    raise exception '20261002c: public.fn_sync_placa_nivel() mudou em produção (md5 %, esperado f7769ff747e1c86bd93fa59d3895b9bd). Abortado.', v_md5;
  end if;
end $guarda$;

select set_config('lock_timeout', '3s', true);

-- ─── 1. Função corrigida ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sync_placa_nivel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_nivel          text;
  v_nivel_anterior text;
BEGIN
  IF NOT (NEW.encerrado = true AND OLD.encerrado = false) THEN RETURN NEW; END IF;

  -- 20261002c: placa concluída MAIS RECENTE do aluno (antes: LIMIT 1 sem ORDER BY, só 'concluido').
  SELECT s.nivel INTO v_nivel
    FROM public.thb_placas_solicitacoes s
   WHERE s.aluno_id = NEW.aluno_id
     AND s.status IN ('concluido', 'placa_postada')
     AND s.nivel IS NOT NULL
   ORDER BY s.updated_at DESC, s.id DESC
   LIMIT 1;
  IF v_nivel IS NULL THEN RETURN NEW; END IF;

  SELECT nivel_resultado INTO v_nivel_anterior FROM public.thb_alunos WHERE id = NEW.aluno_id LIMIT 1;

  IF v_nivel_anterior IS DISTINCT FROM v_nivel THEN
    UPDATE public.thb_alunos SET nivel_resultado = v_nivel, atualizado_em = now() WHERE id = NEW.aluno_id;
    INSERT INTO public.thb_alunos_audit_log (aluno_id, campo, valor_anterior, valor_novo, origem)
    VALUES (NEW.aluno_id, 'nivel_resultado', v_nivel_anterior, v_nivel, 'trigger_placas');
    INSERT INTO public.thb_system_events (tipo, fonte, titulo, detalhe, aluno_id)
    VALUES ('business', 'trigger', 'Nível atualizado via placa aprovada',
      jsonb_build_object('aluno_id', NEW.aluno_id, 'nivel_anterior', v_nivel_anterior, 'nivel_novo', v_nivel),
      NEW.aluno_id);
  END IF;
  RETURN NEW;
END;
$function$;

-- Função de trigger: ninguém da API precisa executá-la direto (o trigger roda independente de EXECUTE).
-- CREATE OR REPLACE mantém os grants que já existiam; o revoke fecha o que vier de PUBLIC/anon/authenticated.
revoke all on function public.fn_sync_placa_nivel() from public, anon, authenticated;

-- ─── 2. Conferência pós-aplicação ─────────────────────────────────────────────────────────────────────────────────────
do $confere$
begin
  if not exists (select 1 from pg_proc p
                  where p.oid = 'public.fn_sync_placa_nivel()'::regprocedure
                    and p.prosecdef
                    and p.proconfig @> array['search_path=public, pg_temp']) then
    raise exception '20261002c: fn_sync_placa_nivel perdeu SECURITY DEFINER ou search_path';
  end if;
  if not exists (select 1 from pg_trigger t
                  where t.tgname = 'trg_sync_placa_nivel'
                    and t.tgrelid = 'public.thb_placas_auditoria'::regclass
                    and t.tgfoid = 'public.fn_sync_placa_nivel()'::regprocedure
                    and t.tgenabled = 'O') then
    raise exception '20261002c: trg_sync_placa_nivel ausente ou desabilitado';
  end if;
  if has_function_privilege('anon', 'public.fn_sync_placa_nivel()', 'execute') then
    raise exception '20261002c: anon executa public.fn_sync_placa_nivel()';
  end if;
end $confere$;


-- ═══ REVERSÃO (definição viva anterior, md5(prosrc) f7769ff747e1c86bd93fa59d3895b9bd, inteira) ═══════════════════════
-- Obs.: o revoke acima não é desfeito pela reversão; se algum papel precisava de EXECUTE direto, regrantar à parte.
--
-- CREATE OR REPLACE FUNCTION public.fn_sync_placa_nivel()
--  RETURNS trigger
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public', 'pg_temp'
-- AS $function$
-- DECLARE
--   v_nivel          text;
--   v_nivel_anterior text;
-- BEGIN
--   IF NOT (NEW.encerrado = true AND OLD.encerrado = false) THEN RETURN NEW; END IF;
--
--   SELECT nivel INTO v_nivel FROM public.thb_placas_solicitacoes
--   WHERE aluno_id = NEW.aluno_id AND status = 'concluido' LIMIT 1;
--   IF v_nivel IS NULL THEN RETURN NEW; END IF;
--
--   SELECT nivel_resultado INTO v_nivel_anterior FROM public.thb_alunos WHERE id = NEW.aluno_id LIMIT 1;
--
--   IF v_nivel_anterior IS DISTINCT FROM v_nivel THEN
--     UPDATE public.thb_alunos SET nivel_resultado = v_nivel, atualizado_em = now() WHERE id = NEW.aluno_id;
--     INSERT INTO public.thb_alunos_audit_log (aluno_id, campo, valor_anterior, valor_novo, origem)
--     VALUES (NEW.aluno_id, 'nivel_resultado', v_nivel_anterior, v_nivel, 'trigger_placas');
--     INSERT INTO public.thb_system_events (tipo, fonte, titulo, detalhe, aluno_id)
--     VALUES ('business', 'trigger', 'Nível atualizado via placa aprovada',
--       jsonb_build_object('aluno_id', NEW.aluno_id, 'nivel_anterior', v_nivel_anterior, 'nivel_novo', v_nivel),
--       NEW.aluno_id);
--   END IF;
--   RETURN NEW;
-- END;
-- $function$;
