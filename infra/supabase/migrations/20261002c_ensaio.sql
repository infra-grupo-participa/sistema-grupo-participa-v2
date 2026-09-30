-- 20261002c — ENSAIO (não aplica nada: tudo termina em ROLLBACK)
-- ═══ RODADO 30/09/2026 em produção (transação desfeita por raise ZOUT) — saída literal ═══
-- 0.md5 | (f7769ff747e1c86bd93fa59d3895b9bd,t)                 -> guarda bate
-- 0.grants_fn | anon t · authenticated t                        -> ANTES: abertos
-- 0.triggers_solicitacao | trg_log_entrevista_change, trg_solicitacoes_sync, trg_sync_rastreio_to_aluno, trg_thb_placas_solicitacoes_updated_at (todos O)
-- 0.updated_at_parado | concluido 37/0 · placa_postada 13/0      -> updated_at mantido por trigger
-- 0.alunos_multi | 0
-- 1.diag_17_resumo | total 17 · regra nova ≠ gravado 4 · atual ≠ gravado 2 · regra nova ≠ atual 4
-- 2.antigo_resultado (função VIVA) | A=platina (errado, esperado diamante) · B=platina (errado, esperado ouro) · B2=ouro (errado, esperado platina)
-- 3.grants_fn | anon f · authenticated f                         -> DEPOIS: fechados
-- 4.novo_resultado | A diamante t · B ouro t · B2 platina t
-- 4.audit_log_n | 6 (3 da função velha + 3 da nova, dentro do ensaio)
-- 4b.rejeitado_nao_grava | ok t · audit 0
-- 5.explain_real | Limit -> Sort (updated_at DESC, id DESC) -> Index Scan using idx_placas_sol_aluno_id
--                  Filter: nivel IS NOT NULL AND status = ANY ('{concluido,placa_postada}') · Buffers shared hit=2
--                  Planning 0.120 ms · Execution 0.028 ms
-- Aplicar DENTRO de transação (set_config lock_timeout é local; apply_migration já envolve em transação).
--
-- Como rodar: arquivo inteiro, de uma vez, como postgres (SQL editor / psql).
--   Todo resultado vai para a temp _z_out; o penúltimo comando (select … from _z_out) mostra tudo.
--   Se o cliente só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia e
--   rode o "rollback;" em seguida. NÃO deixe a transação aberta (segura lock de linha em thb_alunos de teste e
--   o create or replace da função).
--
-- Grava só DENTRO da transação: 4 alunos fictícios (nome 'ZZ ENSAIO 20261002c …', ids 00000000-0000-4000-8000-00000000c0xx),
--   7 solicitações e 4 auditorias deles. O diagnóstico dos 17 (passo 1) é só leitura.
-- CONFERIR: triggers de INSERT/UPDATE em thb_alunos / thb_placas_solicitacoes / thb_placas_auditoria disparam com os
--   fictícios (0.triggers_* lista). Se algum chamar rede (pg_net) ou e-mail, a fila também é desfeita no rollback,
--   mas conferir antes de rodar.
--
-- Esperados (conferir no _z_out):
--   2.antigo_resultado     = função viva; audit_log/system_events dessa rodada ficam (não apago trilha): em
--                            4.novo_audit_log as linhas de id MENOR são da função viva, as de id MAIOR da nova
--   0.md5                  = f7769ff747e1c86bd93fa59d3895b9bd
--   0.triggers_solicitacao = CONFERIR: existe trigger BEFORE UPDATE mantendo updated_at? (define se "mais recente"
--                            por updated_at é confiável; ver 0.updated_at_parado)
--   0.updated_at_parado    = concluídas/postadas com updated_at = created_at (se alto, updated_at não é mantido)
--   0.alunos_multi         = alunos com >1 solicitação concluída/postada (é onde a regra nova muda algo)
--   0.sem_aluno_id         = concluídas/postadas com aluno_id nulo (o trigger não as enxerga, antes nem depois)
--   1.diag_17              = 17 linhas: aluno_id | nivel_gravado | nivel_atual | regra_nova | … (só ids, sem nome)
--   1.diag_17_resumo       = quantos dos 17 a regra nova daria diferente do gravado
--   2.antigo_*             = resultado da função VIVA no caso de teste (pode acertar ou errar: LIMIT 1 sem ordem)
--   4.novo_A               = nivel_resultado 'diamante' (mais recente por updated_at, apesar do id menor e de ter
--                            sido inserida depois); audit_log 1 linha origem trigger_placas profissional -> diamante;
--                            system_events 1 linha
--   4.novo_B               = empate de updated_at: vence o id maior ('ffff…' = 'ouro'); a placa_postada mais
--                            recente que a concluída também é considerada (caso B2)
--   5.explain_*            = Index Scan em idx_placas_sol_aluno_id (ou seq scan barato: 191 linhas) + Sort

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;

create function pg_temp.z_q(p_passo text, p_sql text) returns void language plpgsql as $f$
declare r record;
begin
  for r in execute p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, r::text);
  end loop;
end $f$;

create function pg_temp.z_explain(p_passo text, p_sql text) returns void language plpgsql as $f$
declare l text;
begin
  for l in execute 'explain (analyze, buffers) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, l);
  end loop;
end $f$;

-- ─── 0. Fatos do banco ───────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('0.now', 'select now()');
select pg_temp.z_q('0.md5', $q$select md5(prosrc), proconfig, prosecdef from pg_proc where oid = 'public.fn_sync_placa_nivel()'::regprocedure$q$);
select pg_temp.z_q('0.grants_fn', $q$
  select r, has_function_privilege(r, 'public.fn_sync_placa_nivel()', 'execute')
    from unnest(array['anon','authenticated','service_role']) r$q$);
-- CONFERIR: quem mantém updated_at em thb_placas_solicitacoes (o app não manda no PATCH de conclusão)
select pg_temp.z_q('0.triggers_solicitacao', $q$
  select t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) from pg_trigger t
   where t.tgrelid = 'public.thb_placas_solicitacoes'::regclass and not t.tgisinternal order by 1$q$);
select pg_temp.z_q('0.triggers_auditoria', $q$
  select t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) from pg_trigger t
   where t.tgrelid = 'public.thb_placas_auditoria'::regclass and not t.tgisinternal order by 1$q$);
select pg_temp.z_q('0.updated_at_parado', $q$
  select status, count(*) total, count(*) filter (where updated_at = created_at) updated_igual_created
    from public.thb_placas_solicitacoes where status in ('concluido','placa_postada') group by 1$q$);
select pg_temp.z_q('0.alunos_multi', $q$
  select count(*) alunos_com_mais_de_uma, coalesce(sum(n), 0) solicitacoes
    from (select aluno_id, count(*) n from public.thb_placas_solicitacoes
           where status in ('concluido','placa_postada') and aluno_id is not null
           group by 1 having count(*) > 1) x$q$);
select pg_temp.z_q('0.sem_aluno_id', $q$
  select status, count(*) from public.thb_placas_solicitacoes
   where status in ('concluido','placa_postada') and aluno_id is null group by 1$q$);
select pg_temp.z_q('0.system_events_colunas', $q$
  select column_name, is_nullable, column_default from information_schema.columns
   where table_schema = 'public' and table_name = 'thb_system_events' order by ordinal_position$q$);

-- ─── 1. Diagnóstico dos 17 (só leitura; a migration NÃO regrava) ──────────────────────────────────────────────────────
select pg_temp.z_q('1.diag_17', $q$
  select l.aluno_id,
         l.criado_em                                   as gravado_em,
         l.valor_anterior                              as nivel_antes_do_trigger,
         l.valor_novo                                  as nivel_gravado,
         a.nivel_resultado                             as nivel_atual,
         (select s.nivel from public.thb_placas_solicitacoes s
           where s.aluno_id = l.aluno_id and s.status in ('concluido','placa_postada') and s.nivel is not null
           order by s.updated_at desc, s.id desc limit 1) as regra_nova,
         (select count(*) from public.thb_placas_solicitacoes s
           where s.aluno_id = l.aluno_id and s.status in ('concluido','placa_postada')) as n_concluidas,
         (select string_agg(s.status || ':' || coalesce(s.nivel, 'null') || '@' || s.updated_at::date, ' ; '
                            order by s.updated_at desc, s.id desc)
            from public.thb_placas_solicitacoes s where s.aluno_id = l.aluno_id) as solicitacoes,
         (select string_agg(c.tipo || ':' || coalesce(c.nivel, 'null') || '@' || c.concluido_em::date, ' ; '
                            order by c.concluido_em desc)
            from public.thb_placas_ciclos c where c.aluno_id = l.aluno_id) as ciclos,
         a.cancelado_em is not null                    as cancelado
    from public.thb_alunos_audit_log l
    left join public.thb_alunos a on a.id = l.aluno_id
   where l.campo = 'nivel_resultado' and l.origem = 'trigger_placas'
   order by l.criado_em$q$);
select pg_temp.z_q('1.diag_17_resumo', $q$
  with d as (
    select l.valor_novo gravado, a.nivel_resultado atual,
           (select s.nivel from public.thb_placas_solicitacoes s
             where s.aluno_id = l.aluno_id and s.status in ('concluido','placa_postada') and s.nivel is not null
             order by s.updated_at desc, s.id desc limit 1) nova
      from public.thb_alunos_audit_log l left join public.thb_alunos a on a.id = l.aluno_id
     where l.campo = 'nivel_resultado' and l.origem = 'trigger_placas')
  select count(*) total,
         count(*) filter (where nova is distinct from gravado) nova_diferente_do_gravado,
         count(*) filter (where atual is distinct from gravado) atual_diferente_do_gravado,
         count(*) filter (where nova is distinct from atual)   nova_diferente_do_atual
    from d$q$);

-- ─── 2. Casos de teste (alunos fictícios) — primeiro com a função VIVA ────────────────────────────────────────────────
-- A: 2 concluídas. A mais antiga (platina, id 'ffff…', updated_at -10 d) é inserida PRIMEIRO, para o LIMIT 1 sem
--    ordem da função viva tender a pegá-la. A mais recente (diamante, id '0000…', updated_at -1 d) tem id menor:
--    se a regra nova ordenasse por id, erraria.
-- B: empate de updated_at entre 2 concluídas (id maior vence) + B2: placa_postada mais recente que a concluída.
-- CONFERIR: se houver trigger BEFORE INSERT/UPDATE que sobrescreve updated_at, o passo 3.dados mostra; aí o teste
--   A perde o sentido (as duas ficam com o mesmo updated_at).
insert into public.thb_alunos (id, nome, nivel_resultado) values
  ('00000000-0000-4000-8000-00000000c0a1', 'ZZ ENSAIO 20261002c A', 'profissional'),
  ('00000000-0000-4000-8000-00000000c0b1', 'ZZ ENSAIO 20261002c B', 'profissional'),
  ('00000000-0000-4000-8000-00000000c0b2', 'ZZ ENSAIO 20261002c B2', 'profissional');

insert into public.thb_placas_solicitacoes (id, aluno_id, nome, status, nivel, created_at, updated_at) values
  ('ffffffff-0000-4000-8000-00000000c0a1', '00000000-0000-4000-8000-00000000c0a1', 'ZZ ENSAIO A velha',
   'concluido', 'platina', now() - interval '40 days', now() - interval '10 days');
insert into public.thb_placas_solicitacoes (id, aluno_id, nome, status, nivel, created_at, updated_at) values
  ('00000000-0000-4000-8000-00000000c0a2', '00000000-0000-4000-8000-00000000c0a1', 'ZZ ENSAIO A nova',
   'concluido', 'diamante', now() - interval '20 days', now() - interval '1 day'),
  ('00000000-0000-4000-8000-00000000c0b1', '00000000-0000-4000-8000-00000000c0b1', 'ZZ ENSAIO B id menor',
   'concluido', 'platina', now() - interval '20 days', timestamptz '2026-09-01 12:00:00+00'),
  ('ffffffff-0000-4000-8000-00000000c0b1', '00000000-0000-4000-8000-00000000c0b1', 'ZZ ENSAIO B id maior',
   'concluido', 'ouro', now() - interval '20 days', timestamptz '2026-09-01 12:00:00+00'),
  ('00000000-0000-4000-8000-00000000c0b3', '00000000-0000-4000-8000-00000000c0b2', 'ZZ ENSAIO B2 concluida',
   'concluido', 'ouro', now() - interval '20 days', now() - interval '5 days'),
  ('00000000-0000-4000-8000-00000000c0b4', '00000000-0000-4000-8000-00000000c0b2', 'ZZ ENSAIO B2 postada',
   'placa_postada', 'platina', now() - interval '20 days', now() - interval '2 days');

insert into public.thb_placas_auditoria (aluno_id, encerrado, step_index) values
  ('00000000-0000-4000-8000-00000000c0a1', false, 5),
  ('00000000-0000-4000-8000-00000000c0b1', false, 5),
  ('00000000-0000-4000-8000-00000000c0b2', false, 5);

select pg_temp.z_q('2.dados', $q$
  select aluno_id, id, status, nivel, updated_at from public.thb_placas_solicitacoes
   where aluno_id::text like '00000000-0000-4000-8000-00000000c0%' order by aluno_id, updated_at desc, id desc$q$);

update public.thb_placas_auditoria set encerrado = true, step_index = 6
 where aluno_id in ('00000000-0000-4000-8000-00000000c0a1', '00000000-0000-4000-8000-00000000c0b1',
                    '00000000-0000-4000-8000-00000000c0b2');
select pg_temp.z_q('2.antigo_resultado', $q$
  select id, nivel_resultado from public.thb_alunos
   where id::text like '00000000-0000-4000-8000-00000000c0%' order by id$q$);

-- volta ao estado inicial para rodar com a função nova
update public.thb_placas_auditoria set encerrado = false, step_index = 5
 where aluno_id::text like '00000000-0000-4000-8000-00000000c0%';
update public.thb_alunos set nivel_resultado = 'profissional'
 where id::text like '00000000-0000-4000-8000-00000000c0%';

-- ─── 3. MIGRATION 20261002c (cópia literal do arquivo, sem os comentários de cabeçalho e de reversão) ─────────────────
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

revoke all on function public.fn_sync_placa_nivel() from public, anon, authenticated;

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
-- ─── fim da cópia da migration ───────────────────────────────────────────────────────────────────────────────────────

select pg_temp.z_q('3.md5_novo', $q$select md5(prosrc), proconfig from pg_proc where oid = 'public.fn_sync_placa_nivel()'::regprocedure$q$);
select pg_temp.z_q('3.grants_fn', $q$
  select r, has_function_privilege(r, 'public.fn_sync_placa_nivel()', 'execute')
    from unnest(array['anon','authenticated','service_role']) r$q$);

-- ─── 4. Encerramento com a função nova ───────────────────────────────────────────────────────────────────────────────
update public.thb_placas_auditoria set encerrado = true, step_index = 6
 where aluno_id in ('00000000-0000-4000-8000-00000000c0a1', '00000000-0000-4000-8000-00000000c0b1',
                    '00000000-0000-4000-8000-00000000c0b2');
select pg_temp.z_q('4.novo_resultado', $q$
  select a.id, a.nivel_resultado,
         case a.id::text
           when '00000000-0000-4000-8000-00000000c0a1' then 'diamante'
           when '00000000-0000-4000-8000-00000000c0b1' then 'ouro'
           when '00000000-0000-4000-8000-00000000c0b2' then 'platina' end esperado,
         a.nivel_resultado = case a.id::text
           when '00000000-0000-4000-8000-00000000c0a1' then 'diamante'
           when '00000000-0000-4000-8000-00000000c0b1' then 'ouro'
           when '00000000-0000-4000-8000-00000000c0b2' then 'platina' end ok
    from public.thb_alunos a where a.id::text like '00000000-0000-4000-8000-00000000c0%' order by a.id$q$);
select pg_temp.z_q('4.novo_audit_log', $q$
  select id, aluno_id, campo, valor_anterior, valor_novo, origem from public.thb_alunos_audit_log
   where aluno_id in ('00000000-0000-4000-8000-00000000c0a1','00000000-0000-4000-8000-00000000c0b1','00000000-0000-4000-8000-00000000c0b2') order by id$q$);
select pg_temp.z_q('4.novo_system_events', $q$
  select ctid::text, aluno_id, tipo, fonte, titulo, detalhe from public.thb_system_events
   where aluno_id in ('00000000-0000-4000-8000-00000000c0a1','00000000-0000-4000-8000-00000000c0b1','00000000-0000-4000-8000-00000000c0b2') order by aluno_id$q$);

-- 4b. Encerramento sem conclusão (como rejeitar(): status 'rejeitado' + encerrado=true) num aluno SEM outra
--     concluída: não pode gravar nada.
insert into public.thb_alunos (id, nome, nivel_resultado) values
  ('00000000-0000-4000-8000-00000000c0c1', 'ZZ ENSAIO 20261002c C', 'ouro');
insert into public.thb_placas_solicitacoes (id, aluno_id, nome, status, nivel) values
  ('00000000-0000-4000-8000-00000000c0c1', '00000000-0000-4000-8000-00000000c0c1', 'ZZ ENSAIO C', 'rejeitado', 'diamante');
insert into public.thb_placas_auditoria (aluno_id, encerrado, step_index) values
  ('00000000-0000-4000-8000-00000000c0c1', false, 2);
update public.thb_placas_auditoria set encerrado = true where aluno_id = '00000000-0000-4000-8000-00000000c0c1';
select pg_temp.z_q('4b.rejeitado_nao_grava', $q$
  select a.nivel_resultado = 'ouro' ok, a.nivel_resultado,
         (select count(*) from public.thb_alunos_audit_log l where l.aluno_id = a.id) audit
    from public.thb_alunos a where a.id = '00000000-0000-4000-8000-00000000c0c1'$q$);

-- ─── 5. Plano do SELECT do trigger (aluno real com mais solicitações; e o fictício A) ─────────────────────────────────
select set_config('z.real', coalesce((
  select aluno_id::text from public.thb_placas_solicitacoes where aluno_id is not null
   and aluno_id::text not like '00000000-0000-4000-8000-00000000c0%'
   group by 1 order by count(*) desc, 1 limit 1), '00000000-0000-0000-0000-000000000000'), true);
select pg_temp.z_explain('5.explain_real', $q$
  select s.nivel from public.thb_placas_solicitacoes s
   where s.aluno_id = current_setting('z.real')::uuid
     and s.status in ('concluido', 'placa_postada') and s.nivel is not null
   order by s.updated_at desc, s.id desc limit 1$q$);
select pg_temp.z_explain('5.explain_ficticio_A', $q$
  select s.nivel from public.thb_placas_solicitacoes s
   where s.aluno_id = '00000000-0000-4000-8000-00000000c0a1'
     and s.status in ('concluido', 'placa_postada') and s.nivel is not null
   order by s.updated_at desc, s.id desc limit 1$q$);

-- ─── Resultado ───────────────────────────────────────────────────────────────────────────────────────────────────────
select passo, linha from _z_out order by em;

rollback;
