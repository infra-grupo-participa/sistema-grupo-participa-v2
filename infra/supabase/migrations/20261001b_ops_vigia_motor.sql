-- 20261001b — Vigia das rotinas (2/5): seed de ops.rotina e o motor ops.vigiar().
--
-- REGRAS (N = falhas seguidas que abrem incidente · janela = tempo máximo sem sucesso · K = ok seguidos que fecham)
--   intervalo ≤ 15 min  → N=3, janela = máx(3×intervalo, 30 min), K=3
--   intervalo ≤ 1 h     → N=2, janela = 3 h,                      K=3
--   intervalo < 20 h    → N=2, janela = 2×intervalo + 1 h,        K=2   (2 h → 5 h · 6 h → 13 h)   [decisão do executor]
--   diário ou mais      → N=1, janela = intervalo + 2 h,          K=1   (diário → 26 h · semanal → 7 d 2 h)
--   Intervalo = mediana medida em 7 dias (≥ 3 amostras); sem amostra suficiente, o do schedule.
--
-- CLASSES DE EVENTO
--   ok               2xx e o corpo não traz "ok": false  (ou: execução SQL succeeded)
--   falha_http       não-2xx, 2xx com "ok": false, ou erro de rede que não é timeout
--   timeout_cliente  o pg_net desistiu (timeout_milliseconds) — a edge pode ter terminado, mas ninguém soube
--   sem_resposta     passaram 30 min e não há linha em net._http_response
--   perdida          passou o TTL do pg_net (6 h) sem o vigia reconciliar — NEUTRA (culpa do vigia, não da rotina)
--   falha_sql        cron.job_run_details = failed (inclui o wrapper não achar a função)
--   travada          execução em starting/running há mais de 1 h
--
-- CUSTO (medido no ensaio, ver 20261001.explain.md)
--   cron.job_run_details: só runid > cursor (pkey). Nunca varre a tabela (75.100 linhas / 28 MB, sem expurgo).
--   net._http_response: TTL 6 h (~140 linhas). ops.rotina_chamada: índice parcial dos pendentes.
--   Frequência: 144 ciclos/dia. Expurgo de 14 dias com limit 5000 por ciclo.
--
-- ENVIO
--   ops.config.enviar = false (padrão): só grava em ops.rotina_alerta.
--   true: net.http_post para a URL do Vault 'slack_webhook_rotinas' (NÃO existe em 30/09 — criar antes de ligar).
--   Uma mensagem por ciclo, só quando algo mudou; a primeira é o estado inicial; resumo diário às 11 UTC.
--
-- CRON (preferir criar no apply, fora do arquivo, depois de conferir o ensaio):
--   select cron.schedule('ops-vigia-10min', '2-59/10 * * * *', 'select ops.vigiar()');
--   minuto 2: as respostas das rotinas de :00 (timeout 5 s) já chegaram.
--   Desligar: select cron.unschedule('ops-vigia-10min');  ·  Silenciar uma rotina:
--   update ops.rotina set silenciado_ate = now() + interval '1 day' where jobname = '...';

set local lock_timeout = '3s';
set local statement_timeout = '20s';

create function ops.intervalo_do_schedule(p text) returns interval
language plpgsql immutable set search_path = '' as $f$
declare
  f text[] := regexp_split_to_array(btrim(p), '\s+');
  m text; h text;
begin
  if coalesce(array_length(f, 1), 0) <> 5 or f[3] <> '*' or f[4] <> '*' then return null; end if;
  m := f[1]; h := f[2];
  if f[5] <> '*' then
    return case when m ~ '^\d+$' and h ~ '^\d+$' then interval '7 days' end;
  end if;
  if m = '*' then return interval '1 minute'; end if;
  if m ~ '^\*/\d+$' and h = '*' then return make_interval(mins => substr(m, 3)::int); end if;
  if m ~ '^\d+$' then
    if h = '*' then return interval '1 hour'; end if;
    if h ~ '^\*/\d+$' then return make_interval(hours => substr(h, 3)::int); end if;
    if h ~ '^\d+(,\d+)+$' then return interval '24 hours' / array_length(string_to_array(h, ','), 1); end if;
    if h ~ '^\d+$' then return interval '24 hours'; end if;
  end if;
  return null;
end
$f$;

create function ops.rotina_padrao(p interval, out n_falhas int, out janela interval, out k_ok int)
language sql immutable set search_path = '' as $f$
  select case when p <= interval '15 minutes' then 3 when p <= interval '1 hour' then 2
              when p < interval '20 hours' then 2 else 1 end,
         case when p <= interval '15 minutes' then greatest(3 * p, interval '30 minutes')
              when p <= interval '1 hour' then interval '3 hours'
              when p < interval '20 hours' then 2 * p + interval '1 hour'
              else p + interval '2 hours' end,
         case when p <= interval '1 hour' then 3 when p < interval '20 hours' then 2 else 1 end
$f$;

-- Rotina nova no cron.job entra sozinha (pelo schedule). O vigia não vigia a si mesmo.
create function ops.semear() returns int
language plpgsql set search_path = '' as $f$
declare v int;
begin
  with novos as (
    select j.jobname, coalesce(ops.intervalo_do_schedule(j.schedule), interval '24 hours') i
      from cron.job j
     where j.jobname <> 'ops-vigia-10min'
       and not exists (select 1 from ops.rotina r where r.jobname = j.jobname)
  )
  insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
  select n.jobname, p.n_falhas, p.janela, p.k_ok, n.i, 'schedule'
    from novos n cross join lateral ops.rotina_padrao(n.i) p
  on conflict do nothing;
  get diagnostics v = row_count;
  insert into ops.rotina_estado (jobname)
  select r.jobname from ops.rotina r
   where not exists (select 1 from ops.rotina_estado e where e.jobname = r.jobname)
  on conflict do nothing;
  return v;
end
$f$;

create function ops.classificar(p_status int, p_timed_out boolean, p_erro text, p_corpo text) returns text
language sql immutable set search_path = '' as $f$
  select case
    when p_status between 200 and 299 then
      case when coalesce(p_corpo, '') ~ '"ok"\s*:\s*false' then 'falha_http' else 'ok' end
    when p_status is not null then 'falha_http'
    when coalesce(p_timed_out, false) or coalesce(p_erro, '') ilike 'timeout%' then 'timeout_cliente'
    else 'falha_http'
  end
$f$;

-- Redação: JWT, Bearer, e-mail, CPF, telefone, sequência com cara de token (>= 20).
-- Também pega o que JÁ CHEGA cortado da origem: qualquer fragmento com '@' e CPF formatado parcial
-- ('123.456.78'). Custo: IP/versão no formato nnn.nnn.n também vira [cpf] — aceitável (só banco).
create function ops.redigir(p text) returns text
language sql immutable set search_path = '' as $f$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
         regexp_replace(regexp_replace(
           coalesce(p, ''),
           'eyJ[A-Za-z0-9_\-\.]+', '[jwt]', 'g'),
           'bearer\s+\S+', 'Bearer [redigido]', 'gi'),
           '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[email]', 'g'),
           '[A-Za-z0-9._%+\-]*@[A-Za-z0-9.\-]*', '[email]', 'g'),
           '\d{3}\.?\d{3}\.?\d{3}-?\d{2}', '[cpf]', 'g'),
           '\d{3}\.\d{3}\.\d{1,3}(-\d{0,2})?', '[cpf]', 'g'),
           '(\+?55\s?)?\(?\d{2}\)?\s?9?\d{4}[\-\s]?\d{4}', '[tel]', 'g'),
           '[A-Za-z0-9_\-]{20,}', '[token]', 'g')
$f$;

-- Resumo curto do erro, redigido. Fica SÓ no banco (ops.rotina_estado.ultimo_erro); o Slack não recebe.
-- Ordem: redige o texto INTEIRO primeiro, só depois extrai e corta. Cortar antes deixaria e-mail/CPF pela
-- metade, que o padrão não reconhece mais (achado do pentest, 30/09).
create function ops.resumo_erro(p_status int, p_erro text, p_corpo text) returns text
language sql immutable set search_path = '' as $f$
  select left(concat_ws(' · ',
           case when p_status is not null then 'HTTP ' || p_status end,
           case when p_status is null then split_part(ops.redigir(coalesce(p_erro, 'sem resposta')), '(', 1) end,
           substring(r.corpo from '"error"\s*:\s*"([^"]{1,60})"'),
           substring(r.corpo from '"message"\s*:\s*"([^"]{1,90})"')), 200)
    from (select ops.redigir(coalesce(p_corpo, '')) as corpo) r
$f$;

create function ops.vigiar() returns jsonb
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
begin
  if not pg_try_advisory_xact_lock(hashtext('ops.vigiar')) then
    return jsonb_build_object('pulado', 'outro ciclo em andamento');
  end if;
  select * into c from ops.config where id for update;
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
        update ops.rotina_alerta set enviado = true, request_id = v_req where id = v_alerta;
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

  return jsonb_build_object('reconciliadas', v_reconc, 'rotinas_com_evento', v_eventos,
                            'mudancas', v_mud, 'alerta', v_alerta, 'tipo', v_tipo, 'expurgadas', v_purga,
                            'ms', round(extract(epoch from clock_timestamp() - v_agora) * 1000));
end
$f$;

create function ops.fmt_intervalo(p interval) returns text
language sql immutable set search_path = '' as $f$
  select case when p >= interval '1 day' and extract(hour from p) = 0 and extract(minute from p) = 0
                then extract(day from p)::int || ' dia(s)'
              when p >= interval '1 hour'
                then (extract(epoch from p) / 3600)::numeric(10,1)::text || ' h'
              else (extract(epoch from p) / 60)::int || ' min' end
$f$;

-- Seed: intervalo medido em 7 dias (≥ 3 amostras); senão, o do schedule.
-- Única varredura de cron.job_run_details (75 mil linhas) — só aqui, uma vez.
with med as (
  select d.jobid,
         percentile_cont(0.5) within group (order by extract(epoch from d.gap)) as seg,
         count(*) as amostras
    from (select jobid, start_time - lag(start_time) over (partition by jobid order by start_time) as gap
            from cron.job_run_details where start_time > now() - interval '7 days') d
   where d.gap is not null
   group by d.jobid
), base as (
  select j.jobname,
         case when m.amostras >= 3 then make_interval(mins => round(m.seg / 60)::int)
              else coalesce(ops.intervalo_do_schedule(j.schedule), interval '24 hours') end as i,
         case when m.amostras >= 3 then 'medido_7d' else 'schedule' end as fonte
    from cron.job j left join med m on m.jobid = j.jobid
   where j.jobname <> 'ops-vigia-10min'
)
insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
select b.jobname, p.n_falhas, p.janela, p.k_ok, b.i, b.fonte
  from base b cross join lateral ops.rotina_padrao(b.i) p;

-- Timeout por rotina: só onde o dado justifica. ingest-mensageria mede 3,0–5,6 s na edge (function_edge_logs
-- 29/09 18:40 → 30/09 01:00, 7×200); com 5 s o pg_net cortou 2 respostas 200 (23:50 e 00:50) → falso positivo.
update ops.rotina set timeout_ms = 15000 where jobname = 'ingest-mensageria-hourly';

-- Primeiro ciclo olha as últimas 6 h (mesma janela do TTL do pg_net).
insert into ops.rotina_estado (jobname, observado_desde, ativo, http, rastreio)
select r.jobname, now() - interval '6 hours', j.active,
       j.command ~ '(net\.http_post|ops\.cron_post)\(',
       case when j.command ~ 'ops\.cron_post\(' then 'wrapper'
            when j.command ~ 'net\.http_post\(' then 'sem_rastreio' else 'sql' end
  from ops.rotina r join cron.job j on j.jobname = r.jobname;
update ops.config
   set cursor_runid = (select max(runid) from cron.job_run_details where start_time < now() - interval '6 hours')
 where id;

revoke all on all tables in schema ops from public, anon, authenticated;
revoke execute on all functions in schema ops from public, anon, authenticated;
