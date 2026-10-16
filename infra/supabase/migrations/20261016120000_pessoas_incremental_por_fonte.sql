-- 20261016120000: pessoas-incremental por fonte (COMMIT entre fontes), com teto, data de fim e falha visível
--
-- STATUS: ESCRITA, NÃO APLICADA (16/10/2026, back-end-sr, frente "manter a pessoa única viva"). Depende de 20261014152242 (aplicada).
--   Ensaio: 20261016120000_ensaio.sql. Reversão: 20261016120000_reversao.sql. Detalhe: 20261016120000.explain.md.
--   O job 'pessoas-incremental' (jobid 319) continua DESLIGADO depois desta migration; ligar é decisão do Victor, depois do pentester.
--
-- POR QUE (achado 7 do pentester, 14/10/2026): pessoas.carga_incremental(200) roda as 11 fontes numa chamada só. Se passar dos 120 s do
--   statement_timeout, a hora inteira é desfeita e NADA fica registrado em pessoas.carga_execucao. O erro de uma fonte também só virava
--   texto num retorno que ninguém lê: o job terminava "succeeded". Duas fontes ainda gastavam ~2 s por execução em carga_contagem()
--   (count de ac_contato com 508 mil linhas) abrindo/fechando a execução. E uma fonte cuja janela de "só novos" fica presa em linhas que
--   nunca viram evento (medido: respondi, 2.643 respostas sem e-mail nem telefone) repetia a mesma janela para sempre sem avisar.
-- O QUE FAZ:
--   1. pessoas.carga_incremental_fonte(fonte, limite): UMA fonte, numa subtransação. Abre a execução sem contagem (leve), roda a carga
--      "só novos", fecha. Erro (inclusive timeout, SQLSTATE 57014) volta como estado 'erro' e fica numa linha de pessoas.carga_execucao
--      FORA da subtransação desfeita. Janela cheia sem nenhum evento novo = estado 'sem_avanco' (execução 'erro'). Execução que não leu
--      nada é apagada na hora (não enche a tabela: 24×11 linhas vazias por dia).
--   2. pessoas.carga_incremental_rodar(limite, orcamento_s, teto_linhas): PROCEDURE chamada por 'call' (um comando só, para o COMMIT
--      valer no pg_cron). Faz COMMIT depois de cada fonte: o que uma fonte gravou não se perde se outra falhar ou estourar o tempo.
--      Começa por uma fonte diferente a cada hora (rodízio), para o teto nunca deixar a mesma fonte sempre por último.
--      Teto: p_teto_linhas lidas por execução (padrão 1.500) e p_orcamento_s segundos (padrão 60) sem iniciar fonte nova depois disso.
--      Grava 1 linha de saúde por execução em pessoas.carga_execucao (fonte 'incremental') e, se houve erro, sem_avanco ou orçamento
--      estourado, termina com RAISE EXCEPTION: o job fica 'failed' em cron.job_run_details e o vigia (ops.vigiar) abre incidente.
--      Chave 'incremental' ligada mas com data de fim vencida também falha (revisão), em vez de calar.
--      Fonte com chave ligada que NÃO rodou (carga_aberta, sem_carga_inicial) fica nomeada na linha de saúde ('puladas: ...'), sem derrubar o job.
--      Parâmetros nulos são recusados (is null or not between), não só os fora da faixa.
--   3. Chave 'incremental' ganha data de fim 2026-11-15 (revisão em 30 dias; estava sem fim). Ao ligar, o comando do roteiro grava
--      current_date + 30. Chave 'activecampaign_delta' passa de 2026-12-31 para 2026-11-15 pelo mesmo motivo.
--   4. O job 'pessoas-incremental' passa a chamar a procedure (cron.alter_job só do command; continua desligado, mesmo minuto :50).
--      A função pessoas.carga_incremental(integer) fica no banco, sem uso (a reversão religa o job nela).
-- AS 5 PERGUNTAS: escala = tabelas de origem de ~23 mil (respondi) a ~58 mil (Hotmart) linhas, 200 novas por fonte por hora;
--   índice = eventos_fonte_unico (anti-join), nenhum novo; frequência = 24×/dia, minuto :50 (só os 7 jobs de todo minuto rodam nele;
--   fin-identidade-recalcular :47 dura 12 s em média, 24 s no máximo); repetição = cada fonte lê no máximo 200 linhas sem evento e não
--   conta tabela inteira (sem carga_contagem); reversão = 20261016120000_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('pessoas.carga_incremental(integer)') is null then
    raise exception '20261016120000: falta 20261014152242 (pessoas.carga_incremental).';
  end if;
  if (select count(*) from cron.job where jobname = 'pessoas-incremental') <> 1 then
    raise exception '20261016120000: job pessoas-incremental não existe (ou há mais de um).';
  end if;
  if to_regprocedure('pessoas.carga_incremental_fonte(text,integer)') is not null
     or to_regprocedure('pessoas.carga_incremental_rodar(integer,integer,integer)') is not null then
    raise exception '20261016120000: já aplicada.';
  end if;
end
$g$;

-- ===================== 1. uma fonte, numa subtransação =====================
create function pessoas.carga_incremental_fonte(p_fonte text, p_limite integer) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_e bigint; r jsonb; v_lidas int; v_eventos int; v_sem_avanco boolean := false; v_sqlstate text;
begin
  -- nulo falha FECHADO: 'not between' com NULL não dispara (achado 3 do pentester), então o nulo é recusado de forma explícita
  if p_limite is null or p_limite not between 1 and 1000 then raise exception 'limite entre 1 e 1.000' using errcode = '22023'; end if;
  if p_fonte is null or p_fonte <> all (array['hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios',
                           'respondi', 'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio']) then
    raise exception 'fonte inválida' using errcode = '22023';
  end if;
  if not pessoas.carga_ligada(p_fonte) then return jsonb_build_object('fonte', p_fonte, 'estado', 'desligada'); end if;
  if exists (select 1 from pessoas.carga_execucao where fonte = p_fonte and status in ('rodando', 'parada')) then
    return jsonb_build_object('fonte', p_fonte, 'estado', 'carga_aberta');
  end if;
  if not exists (select 1 from pessoas.carga_execucao where fonte = p_fonte and fase = 'pessoas' and status = 'ok' and coalesce(por, '') <> 'incremental') then
    return jsonb_build_object('fonte', p_fonte, 'estado', 'sem_carga_inicial');
  end if;
  begin
    -- abertura leve: o mesmo que carga_abrir, sem carga_contagem() (que conta ac_contato inteiro: ~2 s)
    insert into pessoas.carga_execucao (fonte, fase, por) values (p_fonte, 'pessoas', 'incremental') returning id into v_e;
    r := case p_fonte
           when 'hotmart_academy'    then pessoas.carga_fin_hotmart(v_e, 'academy', p_limite, true)
           when 'hotmart_escritorio' then pessoas.carga_fin_hotmart(v_e, 'escritorio', p_limite, true)
           when 'thb_alunos'         then pessoas.carga_thb_alunos(v_e, p_limite, true)
           when 'aluno_historico'    then pessoas.carga_aluno_historico(v_e, p_limite, true)
           when 'contatos_hm'        then pessoas.carga_contatos_hm(v_e, p_limite, true)
           when 'hm_socios'          then pessoas.carga_hm_socios(v_e, p_limite, true)
           when 'respondi'           then pessoas.carga_respondi(v_e, p_limite, true)
           when 'crm_negocio'        then pessoas.carga_crm_negocio(v_e, p_limite, true)
           else pessoas.carga_leads(v_e, p_fonte, p_limite, true) end;
    v_lidas := (r->>'lidas')::int;
    v_eventos := (r->>'eventos')::int;
    v_sem_avanco := v_lidas >= p_limite and v_eventos = 0;   -- janela cheia e nada virou evento: a próxima hora lê as mesmas linhas
    if v_lidas = 0 then
      delete from pessoas.carga_lote where execucao_id = v_e;
      delete from pessoas.carga_execucao where id = v_e;
    else
      update pessoas.carga_execucao
         set status = case when v_sem_avanco then 'erro' else 'ok' end,
             erro = case when v_sem_avanco then 'incremental: janela sem avanço (' || v_lidas || ' lidas, 0 eventos)' end,
             terminada_em = now(), atualizada_em = now()
       where id = v_e;
    end if;
    return jsonb_build_object('fonte', p_fonte, 'estado', case when v_sem_avanco then 'sem_avanco' else 'ok' end,
                              'lidas', v_lidas, 'eventos', v_eventos, 'pessoas_novas', (r->>'pessoas_novas')::int,
                              'puladas', (r->>'puladas')::int, 'ms', (r->>'ms')::int);
  exception
    -- when others NÃO pega query_canceled (57014, timeout); tem de ser nomeado. Só o código sai, nunca a mensagem (pode ter dado).
    when query_canceled then v_sqlstate := '57014';
    when others then v_sqlstate := sqlstate;
  end;
  -- a subtransação desfez o lote E a execução aberta nele; o registro do erro nasce aqui, fora dela
  insert into pessoas.carga_execucao (fonte, fase, status, erro, por, terminada_em)
  values (p_fonte, 'pessoas', 'erro', 'incremental: ' || v_sqlstate, 'incremental', now());
  return jsonb_build_object('fonte', p_fonte, 'estado', 'erro', 'sqlstate', v_sqlstate);
end $f$;
revoke all on function pessoas.carga_incremental_fonte(text, integer) from public, anon, authenticated, service_role;
comment on function pessoas.carga_incremental_fonte(text, integer) is
  'Uma fonte da rotina horária da pessoa única, em subtransação. Estados: ok, desligada, carga_aberta, sem_carga_inicial, sem_avanco, erro. Chamada só por pessoas.carga_incremental_rodar.';

-- ===================== 2. a rotina: uma fonte por vez, COMMIT entre elas =====================
create procedure pessoas.carga_incremental_rodar(p_limite integer default 200, p_orcamento_s integer default 60, p_teto_linhas integer default 1500)
language plpgsql as $f$
declare
  v_fontes text[] := array['hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios',
                           'respondi', 'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio'];
  v_n int := 11; v_ini int; i int; f text; r jsonb;
  v_t0 timestamptz := clock_timestamp(); v_total int := 0; v_rodadas int := 0;
  v_problemas text[] := '{}'; v_puladas text[] := '{}'; v_motivo_parada text; v_sp text := current_setting('search_path');
  v_ligada boolean; v_ate date;
begin
  -- Procedure com cláusula SET roda atômica e não pode fazer COMMIT; por isso o search_path é posto aqui (e devolvido no fim).
  perform pg_catalog.set_config('search_path', '', false);
  perform pg_catalog.set_config('lock_timeout', '5s', false);
  if p_limite is null or p_limite not between 1 and 1000 or p_orcamento_s is null or p_orcamento_s not between 5 and 100
     or p_teto_linhas is null or p_teto_linhas not between 1 and 11000 then
    raise exception 'parâmetros fora da faixa (limite 1-1000, orçamento 5-100 s, teto 1-11000)' using errcode = '22023';
  end if;
  select ligada, ate into v_ligada, v_ate from pessoas.carga_chave where fonte = 'incremental';
  if not coalesce(v_ligada, false) then
    perform pg_catalog.set_config('search_path', v_sp, false);
    return;                                              -- desligada de propósito: não é falha
  end if;
  if v_ate is not null and current_date > v_ate then      -- ligada, mas a revisão venceu: falha visível, não silêncio
    raise exception 'pessoas-incremental: chave com data de fim vencida em % (revisar e renovar pessoas.carga_chave)', v_ate using errcode = 'P0001';
  end if;

  v_ini := (extract(hour from now() at time zone 'utc'))::int % v_n;     -- rodízio: cada hora começa por uma fonte
  for i in 0 .. v_n - 1 loop
    if v_total >= p_teto_linhas then v_motivo_parada := 'teto de linhas'; exit; end if;
    if extract(epoch from clock_timestamp() - v_t0) > p_orcamento_s then
      v_problemas := v_problemas || ('orçamento de ' || p_orcamento_s || ' s estourado antes de ' || (v_n - i) || ' fonte(s)');
      exit;
    end if;
    f := v_fontes[1 + (v_ini + i) % v_n];
    r := pessoas.carga_incremental_fonte(f, p_limite);
    v_rodadas := v_rodadas + case when r->>'estado' in ('ok', 'sem_avanco', 'erro') then 1 else 0 end;
    v_total := v_total + coalesce((r->>'lidas')::int, 0);
    if r->>'estado' in ('erro', 'sem_avanco') then
      v_problemas := v_problemas || (f || ': ' || (r->>'estado') || coalesce(' ' || (r->>'sqlstate'), ''));
    end if;
    -- chave ligada mas a fonte não rodou (carga da fonte aberta ou sem carga inicial): não falha o job, mas fica NOMEADA na linha de saúde
    if r->>'estado' in ('carga_aberta', 'sem_carga_inicial') then v_puladas := v_puladas || (f || ' (' || (r->>'estado') || ')'); end if;
    commit;                                               -- a fonte que terminou fica gravada, aconteça o que acontecer depois
  end loop;

  -- uma linha de saúde por hora (fonte 'incremental'): consulta direta mostra a última rodada e o motivo de qualquer parada
  insert into pessoas.carga_execucao (fonte, fase, status, lotes, lidas, erro, por, terminada_em)
  values ('incremental', 'pessoas', case when cardinality(v_problemas) > 0 then 'erro' else 'ok' end, v_rodadas, v_total,
          left(nullif(array_to_string(v_problemas
                                      || case when v_motivo_parada is not null then array['parou: ' || v_motivo_parada] else '{}'::text[] end
                                      || case when cardinality(v_puladas) > 0 then array['puladas: ' || array_to_string(v_puladas, ', ')] else '{}'::text[] end,
                                      '; '), ''), 2000), 'incremental', now());
  commit;
  perform pg_catalog.set_config('search_path', v_sp, false);
  if cardinality(v_problemas) > 0 then
    -- o job termina 'failed' em cron.job_run_details; ops.vigiar() abre o incidente. Só nomes de fonte, estados e SQLSTATE.
    raise exception 'pessoas-incremental: %', array_to_string(v_problemas, '; ') using errcode = 'P0001';
  end if;
end $f$;
revoke all on procedure pessoas.carga_incremental_rodar(integer, integer, integer) from public, anon, authenticated, service_role;
comment on procedure pessoas.carga_incremental_rodar(integer, integer, integer) is
  'Rotina horária da pessoa única (job pessoas-incremental): uma fonte por vez com COMMIT entre elas, teto de linhas e de segundos, linha de saúde em carga_execucao (fonte incremental) e falha visível. Chamar SÓ com um CALL num comando único.';

-- ===================== 3. chave com data de fim =====================
update pessoas.carga_chave
   set ate = date '2026-11-15', por = 'migration 20261016120000: revisão em 30 dias (ligar: current_date + 30)', em = now()
 where fonte = 'incremental' and ate is null;
update pessoas.carga_chave
   set ate = date '2026-11-15', por = 'migration 20261016120000: revisão em 30 dias (ligar: current_date + 30)', em = now()
 where fonte = 'activecampaign_delta' and ate = date '2026-12-31';

-- ===================== 4. o job chama a procedure (continua desligado) =====================
select cron.alter_job(j.jobid, command := $c$call pessoas.carga_incremental_rodar(200, 60, 1500)$c$)
  from cron.job j where j.jobname = 'pessoas-incremental';

do $g$
declare v_job record;
begin
  select * into v_job from cron.job where jobname = 'pessoas-incremental';
  if v_job.command not like 'call pessoas.carga_incremental_rodar(%' then
    raise exception '20261016120000: o job não ficou chamando a procedure.';
  end if;
  if v_job.active then
    raise warning '20261016120000: o job pessoas-incremental já estava ligado antes desta migration (agora chama a procedure).';
  end if;
  if v_job.schedule <> '50 * * * *' then raise exception '20261016120000: schedule do job mudou.'; end if;
  if has_function_privilege('anon', 'pessoas.carga_incremental_fonte(text,integer)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_incremental_fonte(text,integer)', 'execute')
     or has_function_privilege('service_role', 'pessoas.carga_incremental_fonte(text,integer)', 'execute')
     or has_function_privilege('anon', 'pessoas.carga_incremental_rodar(integer,integer,integer)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_incremental_rodar(integer,integer,integer)', 'execute')
     or has_function_privilege('service_role', 'pessoas.carga_incremental_rodar(integer,integer,integer)', 'execute') then
    raise exception '20261016120000: função executável por anon/authenticated/service_role.';
  end if;
  if (select count(*) from pessoas.carga_chave where fonte in ('incremental', 'activecampaign_delta') and ate = date '2026-11-15') <> 2 then
    raise exception '20261016120000: as duas chaves deviam ficar com fim em 2026-11-15.';
  end if;
end
$g$;
