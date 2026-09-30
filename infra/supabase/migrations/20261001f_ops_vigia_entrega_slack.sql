-- 20261001f — Vigia das rotinas (6): entrega ao Slack confirmada pela resposta, com 1 reenvio.
--
-- POR QUÊ
--   Na b, ops.vigiar() marcava rotina_alerta.enviado = true no momento em que enfileirava o net.http_post.
--   net.http_post é assíncrono: webhook revogado (404), payload recusado (400), timeout ou 5xx do Slack
--   deixariam o alerta "enviado" sem ninguém ter recebido — o mesmo defeito que o vigia existe para pegar.
--
-- O QUE MUDA
--   ops.rotina_alerta ganha: entrega ('nao_enviar' | 'pendente' | 'ok' | 'falhou'), tentativas, erro,
--   enviado_em, entregue_em. enviado = true SÓ com 2xx.
--   ops.reconciliar_envios(p_enviar, p_prazo), chamado no começo de cada ciclo:
--     pendente + 2xx                         → enviado = true, entrega = 'ok'
--     pendente + não-2xx / timeout / sem resposta após p_prazo (30 min)
--        tentativas < 2 e enviar = true      → reenvia o MESMO texto (novo request_id), tentativas = 2
--        senão                               → enviado = false, entrega = 'falhou', erro (status/classe,
--                                               + até 60 chars do corpo do Slack, redigido ANTES do corte)
--   ops.vigiar(): igual à b, só troca o bloco de envio (não marca enviado) e chama o reconciliador.
--
-- ORDEM: aplicar ANTES de update ops.config set enviar = true. Com enviar = false nada é enviado e a f
--   não muda comportamento (os alertas ficam 'nao_enviar').
--
-- CUSTO: 1 select por ciclo em rotina_alerta where entrega = 'pendente' (índice parcial; 0–2 linhas).
--
-- REVERSÃO: reaplicar a definição de ops.vigiar() da 20261001b; as colunas novas podem ficar.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

alter table ops.rotina_alerta
  add column entrega     text not null default 'nao_enviar'
                         check (entrega in ('nao_enviar', 'pendente', 'ok', 'falhou')),
  add column tentativas  int not null default 0,
  add column erro        text,
  add column enviado_em  timestamptz,
  add column entregue_em timestamptz;
create index rotina_alerta_pendente_idx on ops.rotina_alerta (id) where entrega = 'pendente';

create function ops.reconciliar_envios(p_enviar boolean, p_prazo interval) returns jsonb
language plpgsql set search_path = '' as $f$
declare
  r       record;
  v_url   text;
  v_req   bigint;
  v_ok    int := 0;
  v_reenv int := 0;
  v_falha int := 0;
begin
  for r in
    select a.id, a.texto, a.tentativas, a.enviado_em, h.id as hid, h.status_code, h.timed_out, h.error_msg, h.content
      from ops.rotina_alerta a
      left join net._http_response h on h.id = a.request_id
     where a.entrega = 'pendente'
     order by a.id
     for update of a
  loop
    if r.hid is null and r.enviado_em > clock_timestamp() - p_prazo then
      continue;  -- ainda sem resposta, dentro do prazo
    end if;
    if r.status_code between 200 and 299 then
      update ops.rotina_alerta set enviado = true, entrega = 'ok', entregue_em = clock_timestamp(), erro = null
       where id = r.id;
      v_ok := v_ok + 1;
      continue;
    end if;
    v_url := null;
    if p_enviar and r.tentativas < 2 then
      select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'slack_webhook_rotinas';
    end if;
    if v_url is not null then
      v_req := net.http_post(url := v_url, body := jsonb_build_object('text', r.texto), timeout_milliseconds := 10000);
      update ops.rotina_alerta
         set request_id = v_req, tentativas = r.tentativas + 1, enviado_em = clock_timestamp(),
             erro = left(coalesce('HTTP ' || r.status_code, case when r.hid is null then 'sem_resposta'
                                                                 else ops.classificar(r.status_code, r.timed_out, r.error_msg, null) end)
                         || coalesce(' · ' || left(nullif(ops.redigir(r.content), ''), 60), ''), 120) || ' (reenviado)'
       where id = r.id;
      v_reenv := v_reenv + 1;
    else
      update ops.rotina_alerta
         set enviado = false, entrega = 'falhou',
             erro = left(coalesce('HTTP ' || r.status_code, case when r.hid is null then 'sem_resposta'
                                                                 else ops.classificar(r.status_code, r.timed_out, r.error_msg, null) end)
                         || coalesce(' · ' || left(nullif(ops.redigir(r.content), ''), 60), ''), 120)
       where id = r.id;
      v_falha := v_falha + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', v_ok, 'reenviados', v_reenv, 'falharam', v_falha);
end
$f$;

create or replace function ops.vigiar() returns jsonb
language plpgsql set search_path = '' as $f$
declare
  c          ops.config%rowtype;
  v_agora    timestamptz := clock_timestamp();
  v_limite   bigint;
  v_max      bigint;
  v_corte    bigint;
  v_eventos  int := 0;
  v_reconc   int := 0;
  v_mud      jsonb := '[]'::jsonb;
  v_tipo     text;
  v_texto    text;
  v_url      text;
  v_req      bigint;
  v_alerta   bigint;
  v_resumo   boolean;
  v_purga    int := 0;
  v_envios   jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('ops.vigiar')) then
    return jsonb_build_object('pulado', 'outro ciclo em andamento');
  end if;
  select * into c from ops.config where id for update;
  v_envios := ops.reconciliar_envios(c.enviar, c.prazo_sem_resposta);
  perform ops.semear();

  -- 0. Situação de cada rotina. Mudou o rastreio ou religou → recomeça a observação e zera as sequências
  --    (ex.: ingest-aquecimento desligada com 13 falhas não pode abrir incidente no minuto em que religar).
  update ops.rotina_estado e
     set ativo = j.active,
         http = j.command ~ '(net\.http_post|ops\.cron_post)\(',
         rastreio = x.rastreio,
         observado_desde = case when x.rastreio is distinct from e.rastreio
                                  or (j.active and e.ativo is distinct from true) then v_agora else e.observado_desde end,
         consec_falhas = case when x.rastreio is distinct from e.rastreio
                                   or (j.active and e.ativo is distinct from true) then 0 else e.consec_falhas end,
         consec_ok     = case when x.rastreio is distinct from e.rastreio
                                   or (j.active and e.ativo is distinct from true) then 0 else e.consec_ok end,
         ultimo_ok_em  = case when x.rastreio is distinct from e.rastreio then null else e.ultimo_ok_em end
    from cron.job j
   cross join lateral (select case when j.command ~ 'ops\.cron_post\(' then 'wrapper'
                                   when j.command ~ 'net\.http_post\(' then 'sem_rastreio'
                                   else 'sql' end as rastreio) x
   where j.jobname = e.jobname
     and (e.ativo is distinct from j.active or e.rastreio is distinct from x.rastreio
          or e.http is distinct from (j.command ~ '(net\.http_post|ops\.cron_post)\('));
  update ops.rotina_estado e set rastreio = 'removido', ativo = false
   where e.rastreio <> 'removido' and not exists (select 1 from cron.job j where j.jobname = e.jobname);

  -- 1. Reconcilia as chamadas pendentes com net._http_response (pelo id).
  with p as (
    select ch.request_id, ch.enviado_em, h.id as hid, h.status_code, h.timed_out, h.error_msg, h.content
      from ops.rotina_chamada ch
      left join net._http_response h on h.id = ch.request_id
     where ch.reconciliado_em is null
  ), cl as (
    select p.*, case when p.hid is not null then ops.classificar(p.status_code, p.timed_out, p.error_msg, p.content)
                     when p.enviado_em < v_agora - c.ttl_resposta then 'perdida'
                     else 'sem_resposta' end as classe
      from p
     where p.hid is not null or p.enviado_em < v_agora - c.prazo_sem_resposta
  )
  update ops.rotina_chamada ch
     set reconciliado_em = v_agora, status = cl.status_code, classe = cl.classe,
         erro = case when cl.classe <> 'ok' then ops.resumo_erro(cl.status_code,
                       case when cl.hid is null then cl.classe else cl.error_msg end, cl.content) end
    from cl where ch.request_id = cl.request_id;
  get diagnostics v_reconc = row_count;

  -- 2. Execuções novas do pg_cron: cursor em runid. Para na 1ª execução ainda em andamento (< 1 h)
  --    para não pular o resultado dela; a que passou de 1 h vira 'travada'.
  --    'connecting'/'starting' pode ter start_time NULL: é jovem se houver execução mais nova que 1 h atrás.
  select max(d.runid) filter (where d.start_time < v_agora - interval '1 hour'), max(d.runid)
    into v_corte, v_max
    from cron.job_run_details d where d.runid > coalesce(c.cursor_runid, 0);
  select min(d.runid) into v_limite
    from cron.job_run_details d
   where d.runid > coalesce(c.cursor_runid, 0)
     and d.status not in ('succeeded', 'failed')
     and (d.start_time > v_agora - interval '1 hour'
          or (d.start_time is null and d.runid > coalesce(v_corte, c.cursor_runid, 0)));

  -- 3. Eventos → estado (conjunto, não linha a linha)
  with ev as (
    select j.jobname, coalesce(d.end_time, d.start_time) as em,
           case d.status when 'succeeded' then 'ok' when 'failed' then 'falha_sql' else 'travada' end as classe,
           left(ops.redigir(split_part(coalesce(d.return_message, d.status), E'\n', 1)), 160) as erro,  -- redige e DEPOIS corta
           case d.status when 'failed' then 'falha_sql' else 'travada' end as falha
      from cron.job_run_details d
      join cron.job j on j.jobid = d.jobid
      join ops.rotina_estado e on e.jobname = j.jobname
     where d.runid > coalesce(c.cursor_runid, 0)
       and (v_limite is null or d.runid < v_limite)
       and not (d.status = 'succeeded' and e.rastreio = 'wrapper')
    union all
    select ch.jobname, ch.enviado_em, ch.classe, ch.erro,
           concat_ws(' · ', 'HTTP ' || ch.status, ch.classe)
      from ops.rotina_chamada ch
     where ch.reconciliado_em = v_agora and ch.classe <> 'perdida'
  ), ag as (
    select ev.jobname, count(*) as n,
           max(em) filter (where classe = 'ok') as u_ok,
           max(em) filter (where classe <> 'ok') as u_falha,
           max(em) as u_ev
      from ev group by ev.jobname
  ), ag2 as (
    select ag.*,
           (select count(*) from ev where ev.jobname = ag.jobname and ev.classe <> 'ok'
                                      and ev.em > coalesce(ag.u_ok, '-infinity')) as falhas_apos_ok,
           (select count(*) from ev where ev.jobname = ag.jobname and ev.classe = 'ok'
                                      and ev.em > coalesce(ag.u_falha, '-infinity')) as oks_apos_falha,
           (select ev.classe from ev where ev.jobname = ag.jobname order by ev.em desc, (ev.classe = 'ok') limit 1) as classe_final,
           (select ev.erro from ev where ev.jobname = ag.jobname and ev.classe <> 'ok' order by ev.em desc limit 1) as erro_final,
           (select ev.falha from ev where ev.jobname = ag.jobname and ev.classe <> 'ok' order by ev.em desc limit 1) as falha_final
      from ag
  )
  update ops.rotina_estado e
     set consec_falhas = case when ag2.u_ok is null then e.consec_falhas + ag2.falhas_apos_ok else ag2.falhas_apos_ok end,
         consec_ok     = case when ag2.u_falha is null then e.consec_ok + ag2.oks_apos_falha else ag2.oks_apos_falha end,
         ultimo_ok_em  = greatest(e.ultimo_ok_em, ag2.u_ok),
         ultimo_evento_em = greatest(e.ultimo_evento_em, ag2.u_ev),
         ultima_classe = ag2.classe_final,
         ultimo_erro   = coalesce(ag2.erro_final, e.ultimo_erro),
         ultima_falha  = coalesce(ag2.falha_final, e.ultima_falha),
         atualizado_em = v_agora
    from ag2 where ag2.jobname = e.jobname;
  get diagnostics v_eventos = row_count;

  -- 4. Fecha: K ok seguidos, ou a rotina foi desligada/removida.
  with f as (
    update ops.rotina_estado e
       set incidente_aberto_em = null, incidente_motivo = null
      from ops.rotina r
     where r.jobname = e.jobname and e.incidente_aberto_em is not null
       and (e.consec_ok >= r.k_ok or e.ativo is not true or e.rastreio = 'removido')
    returning e.jobname, e.ativo, e.rastreio, e.consec_ok
  )
  select v_mud || coalesce(jsonb_agg(jsonb_build_object(
           'jobname', f.jobname,
           'acao', case when f.ativo is true and f.rastreio <> 'removido' then 'voltou' else 'desligada' end,
           'oks', f.consec_ok)), '[]'::jsonb)
    into v_mud from f;
  -- a abertura do incidente fechado não volta no RETURNING (já é null): pega do histórico de alertas
  v_mud := (select coalesce(jsonb_agg(m || jsonb_build_object('desde', (
                select max(a.criado_em) from ops.rotina_alerta a, jsonb_array_elements(a.mudancas) x
                 where x->>'jobname' = m->>'jobname' and x->>'acao' = 'abriu'))), '[]'::jsonb)
              from jsonb_array_elements(v_mud) m);

  -- 5. Abre: N falhas seguidas OU sem sucesso dentro da janela. Silenciada não abre.
  with a as (
    update ops.rotina_estado e
       set incidente_aberto_em = v_agora,
           incidente_motivo = case when e.consec_falhas >= r.n_falhas
                                   then e.consec_falhas || ' falhas seguidas'
                                   else 'nenhum sucesso em ' || ops.fmt_intervalo(r.janela) end
      from ops.rotina r
     where r.jobname = e.jobname and e.incidente_aberto_em is null
       and e.ativo is true and e.rastreio <> 'removido'
       and (r.silenciado_ate is null or r.silenciado_ate < v_agora)
       and (e.consec_falhas >= r.n_falhas
            or greatest(e.ultimo_ok_em, e.observado_desde) < v_agora - r.janela)  -- religada: conta da religação
    returning e.jobname, e.incidente_motivo, e.ultima_falha, e.ultimo_ok_em, e.ultima_classe
  )
  select v_mud || coalesce(jsonb_agg(jsonb_build_object(
           'jobname', a.jobname, 'acao', 'abriu', 'motivo', a.incidente_motivo, 'falha', a.ultima_falha,
           'ultimo_ok', a.ultimo_ok_em, 'classe', a.ultima_classe)), '[]'::jsonb)
    into v_mud from a;

  -- 6. Uma mensagem por ciclo, só se algo mudou (a primeira é o estado inicial; às 11 UTC, o resumo).
  v_resumo := c.inicializado and extract(hour from v_agora at time zone 'UTC') = c.hora_resumo_utc
              and c.ultimo_resumo_dia is distinct from (v_agora at time zone 'UTC')::date;
  if not c.inicializado then
    v_tipo := 'inicial';
  elsif v_resumo then
    v_tipo := 'resumo';
  elsif jsonb_array_length(v_mud) > 0 then
    v_tipo := 'ciclo';
  end if;

  if v_tipo is not null then
    v_texto := ops.montar_mensagem(v_tipo, v_mud);
    insert into ops.rotina_alerta (tipo, mudancas, texto) values (v_tipo, v_mud, v_texto)
    returning id into v_alerta;
    if c.enviar then
      select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'slack_webhook_rotinas';
      if v_url is not null then
        v_req := net.http_post(url := v_url, body := jsonb_build_object('text', v_texto),
                               timeout_milliseconds := 10000);
        -- enviado só vira true quando o Slack responder 2xx (ops.reconciliar_envios, no ciclo seguinte)
        update ops.rotina_alerta
           set request_id = v_req, entrega = 'pendente', tentativas = 1, enviado_em = v_agora
         where id = v_alerta;
      else
        update ops.rotina_alerta set entrega = 'falhou', erro = 'sem slack_webhook_rotinas no Vault' where id = v_alerta;
      end if;
    end if;
  end if;

  -- 7. Expurgo (limitado por ciclo)
  delete from ops.rotina_chamada ch
   where ch.request_id in (select x.request_id from ops.rotina_chamada x
                            where x.enviado_em < v_agora - c.retencao_chamada
                            order by x.enviado_em limit 5000);
  get diagnostics v_purga = row_count;
  delete from ops.rotina_alerta al
   where al.id in (select x.id from ops.rotina_alerta x where x.criado_em < v_agora - interval '90 days'
                    order by x.criado_em limit 5000);

  update ops.config
     set cursor_runid = case when v_limite is not null then v_limite - 1 else coalesce(v_max, cursor_runid) end,
         inicializado = true,
         ultimo_resumo_dia = case when v_tipo = 'resumo' or (v_tipo = 'inicial'
                                    and extract(hour from v_agora at time zone 'UTC') >= c.hora_resumo_utc)
                                  then (v_agora at time zone 'UTC')::date else ultimo_resumo_dia end,
         atualizado_em = v_agora
   where id;

  return jsonb_build_object('envios', v_envios, 'reconciliadas', v_reconc, 'rotinas_com_evento', v_eventos,
                            'mudancas', v_mud, 'alerta', v_alerta, 'tipo', v_tipo, 'expurgadas', v_purga,
                            'ms', round(extract(epoch from clock_timestamp() - v_agora) * 1000));
end
$f$;

revoke execute on all functions in schema ops from public, anon, authenticated;
