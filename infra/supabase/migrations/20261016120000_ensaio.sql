-- ENSAIO de 20261016120000 e 20261016120100 (ESCRITO em 16/10/2026 e refeito no mesmo dia depois do pentester; rodado com rollback, ver 20261016120000.explain.md). Transação DESFEITA.
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>   (banco em produção: fora do :47-:52 e de 05:35-05:45 UTC)
-- A PROCEDURE carga_incremental_rodar NÃO roda aqui: COMMIT não vale dentro de BEGIN. Ela se prova com o CALL manual do roteiro (explain.md).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '150s';
create temp table _z_out (em serial, passo text, linha text);
insert into pg_temp._z_out(passo, linha) select '00 antes', (select jsonb_build_object('pessoas', (select count(*) from pessoas.pessoas), 'eventos', (select count(*) from pessoas.eventos), 'execucoes', (select count(*) from pessoas.carga_execucao))::text);
-- ===== 20261016120000 =====
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

-- 20261016120100: pessoas.carga_respondi e pessoas.carga_aluno_historico no modo "só novos" não ficam presas em linha que nunca vira evento
--
-- STATUS: ESCRITA, NÃO APLICADA (16/10/2026, back-end-sr; refeita no mesmo dia depois do achado 1 do pentester). Independente de 20261016120000
--   (a procedure funciona sem esta), mas sem ela as fontes 'respondi' e 'aluno_historico' relêem para sempre as linhas descartadas.
--   Ensaio: 20261016120000_ensaio.sql (traz as duas migrations). Reversão: 20261016120100_reversao.sql. Detalhe: 20261016120100.explain.md.
--
-- POR QUE: no modo p_novos a função lê as 200 primeiras linhas sem evento. Quem não tem e-mail válido nunca vira pessoa
--   (pessoas._casar_email_seguro devolve pessoa nula e a linha é só contada como pulada), logo nunca ganha evento e fica na janela para sempre.
--   Medido em 16/10/2026: respondi tem 3.505 respostas sem evento e 3.496 delas não têm e-mail válido (a 1ª versão desta migration filtrava por
--   "8 dígitos no telefone" e deixava passar 853 dessas); aluno_historico tem 29 linhas sem evento, todas com e-mail inválido.
-- O QUE MUDA (só o WHERE/ORDER BY do modo p_novos; carga inicial e cursor idênticos):
--   1. respondi, p_novos: só considera resposta com e-mail normalizado válido e de até 320 caracteres, o MESMO critério do descarte
--      (length(pessoas.norm_email(left(coalesce(email, dados->>'email'), 1000))) <= 320). Ordena pelas mais recentes (respondido_em).
--   2. aluno_historico, p_novos: o mesmo critério sobre email_norm. As 29 linhas deixam de ser relidas e nunca geram 'sem_avanco' falso.
--   Assinaturas, search_path, acl e retorno iguais. Corpos anteriores (md5 cc382c4c995d9d475c2e984f8203b4fd e 65ab8c104745e404dc33a1d5d943e79f) estão na reversão.
-- AS 5 PERGUNTAS: escala = 23 mil respostas e 7,6 mil linhas de histórico, 200 por execução; índice = eventos_fonte_unico no anti-join (sem índice
--   novo; o filtro roda sobre as ~3,5 mil respostas sem evento); frequência = 1×/hora, só pelo job pessoas-incremental (desligado); repetição =
--   idempotente (on conflict do nothing); reversão = 20261016120100_reversao.sql.


do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure) <> 'cc382c4c995d9d475c2e984f8203b4fd' then
    raise exception '20261016120100: o corpo de pessoas.carga_respondi não é o esperado (md5 cc382c4c995d9d475c2e984f8203b4fd). Reler antes de aplicar.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_aluno_historico(bigint,integer,boolean)'::regprocedure) <> '65ab8c104745e404dc33a1d5d943e79f' then
    raise exception '20261016120100: o corpo de pessoas.carga_aluno_historico não é o esperado (md5 65ab8c104745e404dc33a1d5d943e79f). Reler antes de aplicar.';
  end if;
end
$g$;

create or replace function pessoas.carga_respondi(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_s uuid; v_turma smallint;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'respondi'), '');
  for r in select x.uuid, x.form_slug, x.respondido_em, x.email, x.telefone, x.dados, f.familia, f.turma_codigo f_turma
             from respondi.respostas x left join respondi.formularios f on f.slug = x.form_slug
            where (not p_novos and x.uuid::text > v_cur)
               or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'respondi.respostas' and e.fonte_id = x.uuid::text and e.tipo = 'resposta')
                   -- mesmo descarte de pessoas._casar_email_seguro: e-mail normalizado válido e de até 320 caracteres. Quem não passa aqui nunca vira
                   -- pessoa nem evento e travaria a janela de 200 (medido em 16/10/2026: 3.505 sem evento, 3.496 delas não passam)
                   and length(pessoas.norm_email(left(coalesce(x.email, x.dados->>'email'), 1000))) <= 320)
            -- só novos: as mais recentes primeiro, para uma linha antiga que não casa nunca tapar a janela; carga inicial: pelo uuid, como antes
            order by case when p_novos then -extract(epoch from coalesce(x.respondido_em, timestamptz 'epoch')) end, x.uuid::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.uuid::text); v_ate := r.uuid::text;
    v := pessoas._casar_email_seguro(r.dados->>'nome', coalesce(r.email, r.dados->>'email'), coalesce(r.telefone, r.dados->>'telefone'), 'respondi');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_turma := (select t.id from public.thb_turmas t where t.codigo = coalesce(r.f_turma, r.dados->>'turma_codigo'));
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'resposta', 'respondi', v_turma, 'respondi.respostas', r.uuid::text, coalesce(r.respondido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('formulario', left(r.form_slug, 40), 'familia', left(r.familia, 40),
                                                 'parcial', case when r.dados->>'parcial' = 'true' then true end)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    -- formulário de sócio: o sócio vira pessoa (por e-mail) e "sócio de" quem respondeu (o titular)
    if pessoas.norm_email(r.dados->>'socio_email') is not null then
      v := pessoas._casar_email_seguro(r.dados->>'socio_nome', r.dados->>'socio_email', r.dados->>'socio_telefone', 'respondi');
      v_s := (v->>'pessoa_id')::uuid;
      if v_s is not null and v_s <> v_p then
        if (v->>'nova')::boolean then n_n := n_n + 1; end if;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
        values (v_s, 'vinculo', 'respondi', v_turma, 'respondi.respostas', r.uuid::text || ':socio', coalesce(r.respondido_em, now()),
                jsonb_build_object('relacao', 'socio_de', 'formulario', left(r.form_slug, 40)))
        on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
        get diagnostics n_x = row_count; n_e := n_e + n_x;
        insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
        values ('socio_de', v_s, v_p, v_turma, 'respondi.respostas', r.uuid::text)
        on conflict on constraint relacoes_unica do nothing;
        get diagnostics n_x = row_count; n_r := n_r + n_x;
      end if;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, n_r, v_t0);
end $f$;

create or replace function pessoas.carga_aluno_historico(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_chave text; v_quando timestamptz;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'aluno_historico'), '');
  -- cursor = md5(e-mail):turma (o espelho é regravado todo dia e os ids mudam)
  for r in select md5(h.email_norm) || ':' || coalesce(h.turma, '') k, h.*
             from controle.aluno_historico h
            where h.email_norm is not null
              and ((not p_novos and md5(h.email_norm) || ':' || coalesce(h.turma, '') > v_cur)
                   -- mesmo descarte de pessoas._casar_email_seguro (e-mail normalizado válido, até 320): as 29 linhas de e-mail inválido da carga
                   -- inicial nunca viram evento e eram relidas toda hora (medido em 16/10/2026)
                   or (p_novos and length(pessoas.norm_email(left(h.email_norm, 1000))) <= 320
                       and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'controle.aluno_historico'
                                                 and e.fonte_id = md5(h.email_norm) || ':' || coalesce(h.turma, '') and e.tipo = 'ativacao')))
            order by 1 limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.k); v_ate := r.k;
    v := pessoas._casar_email_seguro(r.nome, r.email_norm, null, 'importacao');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_quando := case when r.primeira_compra ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                          and pg_input_is_valid(substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2), 'date')
                     then (substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2))::date::timestamp at time zone 'America/Sao_Paulo' end;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'ativacao', 'importacao',
            (select t.id from public.thb_turmas t where t.codigo = replace(r.turma, '.R', 'R')),
            'controle.aluno_historico', r.k, coalesce(v_quando, now()),
            jsonb_strip_nulls(jsonb_build_object('programa', 'thb', 'turma_fonte', left(r.turma, 20), 'data_estimada', v_quando is null)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if nullif(btrim(r.turma_aurum), '') is not null then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'ativacao', 'importacao', (select t.id from public.thb_turmas t where t.codigo = btrim(r.turma_aurum)),
              'controle.aluno_historico', md5(r.email_norm) || ':' || left(btrim(r.turma_aurum), 20), coalesce(v_quando, now()),
              jsonb_build_object('programa', 'aurum', 'turma_fonte', left(btrim(r.turma_aurum), 20)))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure) <> '149b00e7a0d02de0b7b4a402c9e84ed7' then
    raise exception '20261016120100: o corpo gravado de carga_respondi não bate com o esperado (md5 149b00e7a0d02de0b7b4a402c9e84ed7).';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_aluno_historico(bigint,integer,boolean)'::regprocedure) <> 'cae0c7825b3ff8c98291a91c755804df' then
    raise exception '20261016120100: o corpo gravado de carga_aluno_historico não bate com o esperado (md5 cae0c7825b3ff8c98291a91c755804df).';
  end if;
  if has_function_privilege('anon', 'pessoas.carga_respondi(bigint,integer,boolean)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_respondi(bigint,integer,boolean)', 'execute')
     or has_function_privilege('service_role', 'pessoas.carga_respondi(bigint,integer,boolean)', 'execute')
     or has_function_privilege('anon', 'pessoas.carga_aluno_historico(bigint,integer,boolean)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_aluno_historico(bigint,integer,boolean)', 'execute')
     or has_function_privilege('service_role', 'pessoas.carga_aluno_historico(bigint,integer,boolean)', 'execute') then
    raise exception '20261016120100: carga_respondi ou carga_aluno_historico executável por anon/authenticated/service_role.';
  end if;
end
$g$;

-- ===== provas =====
insert into pg_temp._z_out(passo, linha) select '10 job / chaves', (select command from cron.job where jobname = 'pessoas-incremental') || ' | ativo=' || (select active from cron.job where jobname = 'pessoas-incremental')
  || ' | ' || (select string_agg(fonte || '=' || ligada || ' ate ' || coalesce(ate::text, 'null'), ', ') from pessoas.carga_chave where fonte in ('incremental', 'activecampaign_delta'));
-- cada fonte, limite 20 (grava no estado desfeito): estado, lidas, eventos, ms
-- candidatas do modo só novos de respondi: antes (filtro do 1º rascunho, 8 dígitos no telefone) x depois (mesmo descarte da casar_email)
insert into pg_temp._z_out(passo, linha) select '19 respondi candidatas', jsonb_build_object(
  'sem_evento', count(*),
  'passa_filtro_antigo_telefone', count(*) filter (where coalesce(x.email, x.dados->>'email', '') ~ '@' or coalesce(x.telefone, x.dados->>'telefone', '') ~ '[0-9]{8}'),
  'passa_filtro_novo_email', count(*) filter (where length(pessoas.norm_email(left(coalesce(x.email, x.dados->>'email'), 1000))) <= 320))::text
  from respondi.respostas x
 where not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'respondi.respostas' and e.fonte_id = x.uuid::text and e.tipo = 'resposta');
insert into pg_temp._z_out(passo, linha) select '19 aluno_historico candidatas', jsonb_build_object(
  'sem_evento', count(*),
  'passa_filtro_novo_email', count(*) filter (where length(pessoas.norm_email(left(h.email_norm, 1000))) <= 320))::text
  from controle.aluno_historico h
 where h.email_norm is not null
   and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'controle.aluno_historico' and e.fonte_id = md5(h.email_norm) || ':' || coalesce(h.turma, '') and e.tipo = 'ativacao');
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('hotmart_academy', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte hotmart_academy', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('hotmart_escritorio', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte hotmart_escritorio', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('thb_alunos', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte thb_alunos', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('aluno_historico', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte aluno_historico', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('contatos_hm', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte contatos_hm', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('hm_socios', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte hm_socios', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('respondi', 1000);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte respondi (limite 1000)', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
insert into pg_temp._z_out(passo, linha) select '21 respondi sem evento depois', count(*)::text from respondi.respostas x
 where not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'respondi.respostas' and e.fonte_id = x.uuid::text and e.tipo = 'resposta');
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('leads_cnhf', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte leads_cnhf', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('leads_workbook', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte leads_workbook', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('leads_black', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte leads_black', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
do $t$ declare t0 timestamptz := clock_timestamp(); r jsonb; begin
  r := pessoas.carga_incremental_fonte('crm_negocio', 20);
  insert into pg_temp._z_out(passo, linha) values ('20 fonte crm_negocio', (r - 'fonte')::text || ' ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
end $t$;
-- timeout: 50 ms numa fonte que leva mais (respondi: ~130 ms a quente). Esperado: estado erro, sqlstate 57014, e uma linha 'incremental: 57014' em carga_execucao
set local statement_timeout = '50ms';
do $t$ declare r jsonb; begin
  r := pessoas.carga_incremental_fonte('respondi', 200);
  insert into pg_temp._z_out(passo, linha) values ('30 timeout 50ms', r::text);
end $t$;
set local statement_timeout = '150s';
insert into pg_temp._z_out(passo, linha) select '31 linhas de erro 57014', count(*)::text from pessoas.carga_execucao where por = 'incremental' and erro = 'incremental: 57014';
-- desligada / fonte inválida
update pessoas.carga_chave set ligada = false where fonte = 'leads_black';
insert into pg_temp._z_out(passo, linha) select '40 desligada', (pessoas.carga_incremental_fonte('leads_black', 20))::text;
do $t$ begin perform pessoas.carga_incremental_fonte('fonte_que_nao_existe', 20); exception when others then
  insert into pg_temp._z_out(passo, linha) values ('41 fonte inválida', 'sqlstate ' || sqlstate); end $t$;
-- parâmetros nulos falham fechado (achado 3): esperado sqlstate 22023 nos dois
do $t$ begin perform pessoas.carga_incremental_fonte('respondi', null); exception when others then
  insert into pg_temp._z_out(passo, linha) values ('42 limite nulo', 'sqlstate ' || sqlstate); end $t$;
do $t$ begin perform pessoas.carga_incremental_fonte(null, 20); exception when others then
  insert into pg_temp._z_out(passo, linha) values ('43 fonte nula', 'sqlstate ' || sqlstate); end $t$;
-- a procedure recusa parâmetro nulo ANTES de qualquer COMMIT (por isso dá para chamar aqui, dentro do BEGIN): esperado 22023 nos três casos
do $t$ begin call pessoas.carga_incremental_rodar(null, 60, 1500); exception when others then
  insert into pg_temp._z_out(passo, linha) values ('44 procedure limite nulo', 'sqlstate ' || sqlstate); end $t$;
do $t$ begin call pessoas.carga_incremental_rodar(200, null, 1500); exception when others then
  insert into pg_temp._z_out(passo, linha) values ('44 procedure orçamento nulo', 'sqlstate ' || sqlstate); end $t$;
do $t$ begin call pessoas.carga_incremental_rodar(200, 60, null); exception when others then
  insert into pg_temp._z_out(passo, linha) values ('44 procedure teto nulo', 'sqlstate ' || sqlstate); end $t$;
-- cópia da expressão da linha de saúde (problema + parada + fontes puladas): só confere tipos e o texto; a procedure em si só roda no CALL real
insert into pg_temp._z_out(passo, linha) select '45 linha de saúde (expressão)', left(nullif(array_to_string(array['respondi: erro 57014']::text[]
    || case when 'teto de linhas' is not null then array['parou: ' || 'teto de linhas'] else '{}'::text[] end
    || case when cardinality(array['hotmart_academy (carga_aberta)', 'hotmart_escritorio (carga_aberta)']) > 0
            then array['puladas: ' || array_to_string(array['hotmart_academy (carga_aberta)', 'hotmart_escritorio (carga_aberta)'], ', ')] else '{}'::text[] end,
    '; '), ''), 2000);
-- explain (analyze) do SELECT do modo só novos de respondi, antes e depois (o plano completo vai para o .explain.md)
-- (rodar à parte, em autocommit: python3 ... explain; ver 20261016120100.explain.md)
insert into pg_temp._z_out(passo, linha) select '90 execuções criadas no ensaio', count(*)::text from pessoas.carga_execucao where por = 'incremental';
-- ===== reversões ensaiadas =====
-- Reversão de 20261016120100: volta pessoas.carga_respondi (md5 cc382c4c995d9d475c2e984f8203b4fd) e pessoas.carga_aluno_historico (md5 65ab8c104745e404dc33a1d5d943e79f) aos corpos anteriores.
-- Rodar com o job pessoas-incremental desligado ou numa janela em que ele não esteja executando.

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure) <> '149b00e7a0d02de0b7b4a402c9e84ed7' then
    raise exception 'reversão 20261016120100: o corpo atual de carga_respondi não é o desta migration (md5 149b00e7a0d02de0b7b4a402c9e84ed7); não sobrescrever.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_aluno_historico(bigint,integer,boolean)'::regprocedure) <> 'cae0c7825b3ff8c98291a91c755804df' then
    raise exception 'reversão 20261016120100: o corpo atual de carga_aluno_historico não é o desta migration (md5 cae0c7825b3ff8c98291a91c755804df); não sobrescrever.';
  end if;
end
$g$;

create or replace function pessoas.carga_respondi(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_s uuid; v_turma smallint;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'respondi'), '');
  for r in select x.uuid, x.form_slug, x.respondido_em, x.email, x.telefone, x.dados, f.familia, f.turma_codigo f_turma
             from respondi.respostas x left join respondi.formularios f on f.slug = x.form_slug
            where (not p_novos and x.uuid::text > v_cur)
               or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'respondi.respostas' and e.fonte_id = x.uuid::text and e.tipo = 'resposta'))
            order by x.uuid::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.uuid::text); v_ate := r.uuid::text;
    v := pessoas._casar_email_seguro(r.dados->>'nome', coalesce(r.email, r.dados->>'email'), coalesce(r.telefone, r.dados->>'telefone'), 'respondi');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_turma := (select t.id from public.thb_turmas t where t.codigo = coalesce(r.f_turma, r.dados->>'turma_codigo'));
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'resposta', 'respondi', v_turma, 'respondi.respostas', r.uuid::text, coalesce(r.respondido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('formulario', left(r.form_slug, 40), 'familia', left(r.familia, 40),
                                                 'parcial', case when r.dados->>'parcial' = 'true' then true end)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    -- formulário de sócio: o sócio vira pessoa (por e-mail) e "sócio de" quem respondeu (o titular)
    if pessoas.norm_email(r.dados->>'socio_email') is not null then
      v := pessoas._casar_email_seguro(r.dados->>'socio_nome', r.dados->>'socio_email', r.dados->>'socio_telefone', 'respondi');
      v_s := (v->>'pessoa_id')::uuid;
      if v_s is not null and v_s <> v_p then
        if (v->>'nova')::boolean then n_n := n_n + 1; end if;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
        values (v_s, 'vinculo', 'respondi', v_turma, 'respondi.respostas', r.uuid::text || ':socio', coalesce(r.respondido_em, now()),
                jsonb_build_object('relacao', 'socio_de', 'formulario', left(r.form_slug, 40)))
        on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
        get diagnostics n_x = row_count; n_e := n_e + n_x;
        insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
        values ('socio_de', v_s, v_p, v_turma, 'respondi.respostas', r.uuid::text)
        on conflict on constraint relacoes_unica do nothing;
        get diagnostics n_x = row_count; n_r := n_r + n_x;
      end if;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, n_r, v_t0);
end $f$;

create or replace function pessoas.carga_aluno_historico(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_chave text; v_quando timestamptz;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'aluno_historico'), '');
  -- cursor = md5(e-mail):turma (o espelho é regravado todo dia e os ids mudam)
  for r in select md5(h.email_norm) || ':' || coalesce(h.turma, '') k, h.*
             from controle.aluno_historico h
            where h.email_norm is not null
              and ((not p_novos and md5(h.email_norm) || ':' || coalesce(h.turma, '') > v_cur)
                   or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'controle.aluno_historico'
                                                 and e.fonte_id = md5(h.email_norm) || ':' || coalesce(h.turma, '') and e.tipo = 'ativacao')))
            order by 1 limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.k); v_ate := r.k;
    v := pessoas._casar_email_seguro(r.nome, r.email_norm, null, 'importacao');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_quando := case when r.primeira_compra ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                          and pg_input_is_valid(substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2), 'date')
                     then (substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2))::date::timestamp at time zone 'America/Sao_Paulo' end;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'ativacao', 'importacao',
            (select t.id from public.thb_turmas t where t.codigo = replace(r.turma, '.R', 'R')),
            'controle.aluno_historico', r.k, coalesce(v_quando, now()),
            jsonb_strip_nulls(jsonb_build_object('programa', 'thb', 'turma_fonte', left(r.turma, 20), 'data_estimada', v_quando is null)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if nullif(btrim(r.turma_aurum), '') is not null then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'ativacao', 'importacao', (select t.id from public.thb_turmas t where t.codigo = btrim(r.turma_aurum)),
              'controle.aluno_historico', md5(r.email_norm) || ':' || left(btrim(r.turma_aurum), 20), coalesce(v_quando, now()),
              jsonb_build_object('programa', 'aurum', 'turma_fonte', left(btrim(r.turma_aurum), 20)))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure) <> 'cc382c4c995d9d475c2e984f8203b4fd' then
    raise exception 'reversão 20261016120100: carga_respondi não voltou ao anterior (md5 cc382c4c995d9d475c2e984f8203b4fd).';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_aluno_historico(bigint,integer,boolean)'::regprocedure) <> '65ab8c104745e404dc33a1d5d943e79f' then
    raise exception 'reversão 20261016120100: carga_aluno_historico não voltou ao anterior (md5 65ab8c104745e404dc33a1d5d943e79f).';
  end if;
end
$g$;
-- depois: delete from supabase_migrations.schema_migrations where version = '20261016120100';

-- Reversão de 20261016120000 (pessoas-incremental por fonte). Não apaga dado carregado nem as linhas de pessoas.carga_execucao.
-- Rodar com o job pessoas-incremental desligado ou fora do :50.

-- o job volta a chamar a função antiga (que continua no banco)
select cron.alter_job(j.jobid, command := $c$ set statement_timeout = '120s'; select pessoas.carga_incremental(200) $c$)
  from cron.job j where j.jobname = 'pessoas-incremental';
drop procedure if exists pessoas.carga_incremental_rodar(integer, integer, integer);
drop function if exists pessoas.carga_incremental_fonte(text, integer);
-- datas de fim como estavam (incremental sem fim; delta em 2026-12-31)
update pessoas.carga_chave set ate = null, por = 'reversão de 20261016120000', em = now() where fonte = 'incremental';
update pessoas.carga_chave set ate = date '2026-12-31', por = 'reversão de 20261016120000', em = now() where fonte = 'activecampaign_delta';

do $g$
begin
  if to_regprocedure('pessoas.carga_incremental(integer)') is null then
    raise exception 'reversão 20261016120000: a função antiga pessoas.carga_incremental sumiu.';
  end if;
  if (select command from cron.job where jobname = 'pessoas-incremental') not like '%pessoas.carga_incremental(200)%' then
    raise exception 'reversão 20261016120000: o job não voltou ao comando antigo.';
  end if;
end
$g$;
-- depois: delete from supabase_migrations.schema_migrations where version = '20261016120000';
-- as linhas de saúde (fonte 'incremental') e de erro por fonte ficam em pessoas.carga_execucao como histórico.

insert into pg_temp._z_out(passo, linha) select '95 depois das reversões', coalesce(to_regprocedure('pessoas.carga_incremental_rodar(integer,integer,integer)')::text, 'procedure removida') || ' | ' || (select command from cron.job where jobname = 'pessoas-incremental')
  || ' | respondi md5 ' || (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure)
  || ' | aluno_historico md5 ' || (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_aluno_historico(bigint,integer,boolean)'::regprocedure);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
