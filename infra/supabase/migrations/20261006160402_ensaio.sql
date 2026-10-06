-- 20261006160402: ENSAIO (não aplica nada: termina em ROLLBACK)
--
-- Como rodar: python3 aplica_sql.py ensaio infra/supabase/migrations/20261006160402_ensaio.sql
--   (o script troca o select final por um RAISE: a transação aborta e a saída volta na mensagem).
--   No SQL editor: rodar até o "select … from _z_out" (inclusive), ler e rodar o "rollback;". Não deixar aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado de 20261006160402_pa_slack_dm.sql; se a migration
-- mudar, gerar de novo). Depois do corpo: aluno ZZ com "<", ">" e "&" no nome e três pedidos (consome 3 números da
-- sequência de pa_pedidos). As funções do n8n são chamadas COMO ANON (o caminho do PostgREST). O segredo nunca é impresso.
--   p1 Victor pede (alterar profissão)           -> 1 DM reservada para U0AQ4H2GZ0T, texto escapado, não repete
--   p2 Isabela pede ("outro") e é recusado antes  -> nenhuma DM
--   p3 insert com pa_config renomeada (gatilho falha por dentro) -> o insert passa
-- A URL do webhook no ensaio é https://exemplo.invalid/… e a fila do pg_net é desfeita no rollback.
--
-- Esperado: nenhuma linha começando com "ERRADO".
-- ═══ Conferência depois do ensaio (chamada separada): nada persistiu ═══
-- select to_regclass('public.pa_config') is null sem_config, to_regclass('public.pa_avisos') is null sem_avisos,
--        (select count(*) from public.thb_alunos where fonte = 'ensaio_20261006160402') alunos_zz,
--        (select max(id) from public.pa_pedidos) max_pedido,
--        (select count(*) from net.http_request_queue where url like 'https://exemplo.invalid/%') fila_pg_net;

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || coalesce(p_det, ''));
$$;
create function pg_temp.chamar(p_perfil uuid, p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;
-- Como anon (sem JWT): o caminho do n8n pelo PostgREST.
create function pg_temp.anon(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  execute 'set local role anon';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;
-- Plano medido: cada linha do explain (analyze) vira uma linha da saída.
create function pg_temp.plano(p_passo text, p_sql text) returns void language plpgsql as $$
declare l text;
begin
  for l in execute 'explain (analyze, buffers, costs off) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, 'PLANO   ' || l);
  end loop;
end $$;

-- ═══ CORPO DA MIGRATION 20261006160402_pa_slack_dm.sql (cópia sem mudança) ═══
-- 20261006160402: Pedidos de alteração (etapa 2), aviso de pedido novo por DM no Slack (só para o Victor)
--
-- STATUS: APLICADA em 06/10/2026 (pentester aprovou). Ensaio: 20261006160402_ensaio.sql (begin … rollback). Notas: 20261006160402.explain.md.
-- Pré-requisito de: 20261006160403 (planilha usa pa_config e pa_n8n_valido). Independente da 160401 e da 160404.
--
-- DECISÃO DO VICTOR (06/10/2026, noite): aviso de pedido novo SÓ para o Victor, por DM (chat.postMessage com
-- channel = U0AQ4H2GZ0T, bot remocaoacessos). Ninguém mais. Destinatário configurável em tabela fechada, não "todo
-- aprovador". Texto:
--   :memo: Solicitaram uma alteração do aluno *<nome>*: <tipo>, pedido por <nome de quem pediu>. <https://grupoparticipa.app.br/educacional/pedidos-alteracao|Abrir a fila>
--   (nomes escapados com ra_slack_esc).
--
-- O QUE FAZ (padrão da Remoção de Acessos: ra_config, ra_slack_reservar/confirmar, ra_fn_avisar_n8n)
--   1. pa_config: UMA linha, fechada (RLS sem policy, revoke de anon/authenticated). Colunas:
--        segredo         gerado aqui (64 hex), lido pelo Victor no banco e guardado na credencial do n8n;
--        n8n_webhook_url NULO: o gatilho não chama ninguém até o workflow existir e alguém gravar a URL;
--        planilha_id     NULO: a 20261006160403 não devolve nada até alguém gravar o id (primeiro o da CÓPIA);
--        slack_destinos  {U0AQ4H2GZ0T} (Victor);
--        ligado_em       NULO: desligado. Ligar = update pa_config set ligado_em = now(). Só pedido criado depois disso
--                        vira aviso (os pedidos antigos, como o nº 9 e o nº 10, não geram DM retroativa).
--   2. pa_avisos (pedido_id, slack_id, reservado_em, enviado_em, slack_ts), pk (pedido_id, slack_id): 1 aviso por
--      pedido e destino, nunca repete depois de enviado.
--   3. pa_slack_reservar(p_segredo): pedidos `pendente` criados depois de ligado_em, 1 mensagem por destino, até 20 por
--      chamada. A reserva vale 2 minutos (igual ra_slack_reservas): se o n8n não confirmar (Slack falhou), volta à fila.
--      Pedido que já foi decidido antes de o aviso sair não gera DM. Sem segredo válido: {"ok": false} e nada mais.
--   4. pa_slack_confirmar(p_segredo, p_pedido, p_slack_id, p_ts): marca enviado_em e slack_ts.
--   5. Gatilho AFTER INSERT em pa_pedidos: chama o webhook do n8n via pg_net (a chamada só sai depois do commit) e
--      NUNCA derruba o insert (exception → warning), como ra_fn_avisar_n8n. Corpo: {"pedido": <nº>}. Sem segredo.
--   Funções com segredo: execute para anon e authenticated (o n8n chama pelo PostgREST), como ra_slack_*. A comparação
--   do segredo é igual à do ra_slack_valido (texto = texto, sem tempo constante, que o padrão existente não faz).
--
-- AS 5 PERGUNTAS
--   escala: dezenas de pedidos por mês; pa_avisos cresce 1 linha por pedido criado depois de ligado_em.
--   índice: a reserva filtra pa_pedidos por status = 'pendente' (pa_pedidos_status_idx (status, id), já existe) e
--     cruza com pa_avisos pela pk. Nenhum índice novo.
--   frequência: a cada pedido novo (gatilho → n8n) e na rodada de 15 min do n8n (garantia).
--   repetição: pk (pedido_id, slack_id) + "on conflict do update … where enviado_em is null and reserva vencida":
--     duas chamadas ao mesmo tempo não reservam o mesmo aviso; enviado não volta.
--   reversão: bloco REVERSÃO no fim (drop do gatilho, das funções e das tabelas). Nada existente é alterado.
--
-- Quem lê fora do v2: ninguém (objetos novos).

set local lock_timeout = '5s';

-- ═══ 0. Guarda ═══
do $guarda$
begin
  if to_regclass('public.pa_config') is not null or to_regclass('public.pa_avisos') is not null then
    raise exception '20261006160402: pa_config ou pa_avisos já existe (migration já aplicada?)';
  end if;
  if to_regprocedure('public.ra_slack_esc(text)') is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    raise exception '20261006160402: ra_slack_esc(text) ou net.http_post ausente';
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.pa_pedidos'::regclass and not tgisinternal) then
    raise exception '20261006160402: pa_pedidos já tem gatilho (esperado nenhum em 06/10/2026)';
  end if;
end
$guarda$;

-- ═══ 1. Configuração fechada (uma linha) ═══
create table public.pa_config (
  id boolean primary key default true check (id),
  segredo text not null default (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
    check (length(segredo) >= 32),
  n8n_webhook_url text check (n8n_webhook_url is null or n8n_webhook_url ~ '^https://\S+$'),
  planilha_id text check (planilha_id is null or planilha_id ~ '^[A-Za-z0-9_-]{20,}$'),
  slack_destinos text[] not null default array['U0AQ4H2GZ0T']::text[]
    check (cardinality(slack_destinos) <= 5 and array_position(slack_destinos, null) is null),
  ligado_em timestamptz,
  atualizado_em timestamptz not null default now()
);
insert into public.pa_config default values;

comment on table public.pa_config is
  '20261006160402: configuração do n8n dos pedidos de alteração (segredo, webhook, planilha, destinatários do DM, '
  'ligado_em). Fechada. Ligar o aviso: update public.pa_config set ligado_em = now().';

-- ═══ 2. Avisos (1 por pedido e destino) ═══
create table public.pa_avisos (
  pedido_id bigint not null references public.pa_pedidos(id) on delete cascade,
  slack_id text not null,
  reservado_em timestamptz not null default now(),
  enviado_em timestamptz,
  slack_ts text,
  primary key (pedido_id, slack_id)
);

alter table public.pa_config enable row level security;
alter table public.pa_avisos enable row level security;
revoke all on table public.pa_config, public.pa_avisos from public, anon, authenticated;

-- ═══ 3. Segredo ═══
create function public.pa_n8n_valido(p_segredo text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(p_segredo, '') <> ''
     -- Compara os hashes (tamanho fixo) e não o texto: não vaza por tempo de resposta quantos caracteres batem.
     and exists (select 1 from public.pa_config c
                  where c.id and extensions.digest(c.segredo, 'sha256') = extensions.digest(p_segredo, 'sha256'));
$$;

-- Rótulo do tipo (espelho de ROTULO_TIPO em web/modules/alunos/domain/pedidos-alteracao.ts).
create function public.pa_rotulo_tipo(p_tipo text)
returns text language sql immutable set search_path = '' as $$
  select case p_tipo when 'alterar_dado' then 'Alterar dado' when 'trocar_socio' then 'Trocar sócio'
                     when 'outro' then 'Outro' else p_tipo end;
$$;

-- ═══ 4. Reserva e confirmação (n8n) ═══
create function public.pa_slack_reservar(p_segredo text)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  c public.pa_config%rowtype;
  v_out jsonb := '[]'::jsonb;
  m record;
begin
  if not public.pa_n8n_valido(p_segredo) then return json_build_object('ok', false); end if;
  select * into c from public.pa_config where id;
  if c.ligado_em is null or coalesce(cardinality(c.slack_destinos), 0) = 0 then
    return json_build_object('ok', true, 'mensagens', '[]'::json);
  end if;

  for m in
    select x.id, d.slack_id,
           ':memo: Solicitaram uma alteração do aluno *'
           || public.ra_slack_esc(coalesce((select a.nome from public.thb_alunos a where a.id = x.aluno_id), x.aluno_nome))
           || '*: ' || public.pa_rotulo_tipo(x.tipo)
           || ', pedido por ' || public.ra_slack_esc(coalesce((select p.nome from public.perfis p where p.id = x.solicitado_por), '(sem nome)'))
           || '. <https://grupoparticipa.app.br/educacional/pedidos-alteracao|Abrir a fila>' as texto
      from public.pa_pedidos x
     cross join lateral (select distinct u as slack_id from unnest(c.slack_destinos) u) d
     where x.status = 'pendente' and x.solicitado_em >= c.ligado_em
       and not exists (select 1 from public.pa_avisos a
                        where a.pedido_id = x.id and a.slack_id = d.slack_id
                          and (a.enviado_em is not null or a.reservado_em >= now() - interval '2 minutes'))
     order by x.id
     limit 20
  loop
    insert into public.pa_avisos as a (pedido_id, slack_id) values (m.id, m.slack_id)
    on conflict (pedido_id, slack_id) do update set reservado_em = now()
     where a.enviado_em is null and a.reservado_em < now() - interval '2 minutes';
    if found then
      v_out := v_out || jsonb_build_array(jsonb_build_object('pedido', m.id, 'slack_id', m.slack_id, 'texto', m.texto));
    end if;
  end loop;
  return json_build_object('ok', true, 'mensagens', v_out);
end
$$;

create function public.pa_slack_confirmar(p_segredo text, p_pedido bigint, p_slack_id text, p_ts text default null)
returns json language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.pa_n8n_valido(p_segredo) then return json_build_object('ok', false); end if;
  update public.pa_avisos
     set enviado_em = now(), slack_ts = left(p_ts, 64)
   where pedido_id = p_pedido and slack_id = p_slack_id and enviado_em is null;
  return json_build_object('ok', found);
end
$$;

-- ═══ 5. Gatilho: chama o n8n na hora (nunca derruba o insert) ═══
create function public.pa_fn_avisar_n8n()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_ligado timestamptz;
begin
  begin
    select c.n8n_webhook_url, c.ligado_em into v_url, v_ligado from public.pa_config c where c.id;
    if v_url is null or v_ligado is null or new.status <> 'pendente' then return new; end if;
    perform net.http_post(url := v_url,
                          body := jsonb_build_object('pedido', new.id),
                          headers := '{"Content-Type": "application/json"}'::jsonb,
                          timeout_milliseconds := 10000);
  exception when others then
    raise warning 'pa_fn_avisar_n8n: %', sqlerrm;
  end;
  return new;
end
$$;

create trigger trg_pa_avisar_n8n
  after insert on public.pa_pedidos
  for each row execute function public.pa_fn_avisar_n8n();

-- ═══ 6. Grants ═══
revoke all on function public.pa_n8n_valido(text) from public, anon, authenticated;
revoke all on function public.pa_rotulo_tipo(text) from public, anon, authenticated;
revoke all on function public.pa_fn_avisar_n8n() from public, anon, authenticated;
revoke all on function public.pa_slack_reservar(text) from public;
revoke all on function public.pa_slack_confirmar(text, bigint, text, text) from public;
grant execute on function public.pa_slack_reservar(text), public.pa_slack_confirmar(text, bigint, text, text)
  to anon, authenticated;

-- ═══ 7. Conferência ═══
do $confere$
begin
  if (select count(*) from public.pa_config) <> 1
     or (select slack_destinos from public.pa_config) <> array['U0AQ4H2GZ0T']::text[]
     or (select ligado_em is not null or n8n_webhook_url is not null or planilha_id is not null from public.pa_config) then
    raise exception '20261006160402: pa_config diferente do esperado';
  end if;
  if has_table_privilege('anon', 'public.pa_config', 'select') or has_table_privilege('authenticated', 'public.pa_config', 'select')
     or has_table_privilege('anon', 'public.pa_avisos', 'select') or has_table_privilege('authenticated', 'public.pa_avisos', 'select') then
    raise exception '20261006160402: pa_config/pa_avisos legíveis por anon/authenticated';
  end if;
  if has_function_privilege('anon', 'public.pa_n8n_valido(text)', 'execute')
     or has_function_privilege('authenticated', 'public.pa_n8n_valido(text)', 'execute') then
    raise exception '20261006160402: pa_n8n_valido exposta';
  end if;
end
$confere$;

-- ═══ REVERSÃO (não rodar junto com a migration) ═══
-- Tira o gatilho, as funções e as tabelas novas. Nada existente foi alterado. Rodar ANTES a reversão da 20261006160403
-- se ela tiver sido aplicada (ela usa pa_config e pa_n8n_valido). Desligar antes o workflow do n8n.
-- Para reverter: tirar o "-- " das linhas abaixo e rodar.
--
-- drop trigger if exists trg_pa_avisar_n8n on public.pa_pedidos;
-- drop function if exists public.pa_fn_avisar_n8n();
-- drop function if exists public.pa_slack_confirmar(text, bigint, text, text);
-- drop function if exists public.pa_slack_reservar(text);
-- drop function if exists public.pa_rotulo_tipo(text);
-- drop function if exists public.pa_n8n_valido(text);
-- drop table if exists public.pa_avisos;
-- drop table if exists public.pa_config;

-- ═══ ENSAIO: testes ═══════════════════════════════════════════════════════════════════════════

create temp table _s on commit drop as select segredo as s from public.pa_config;
create function pg_temp.seg() returns text language sql as $$ select s from pg_temp._s $$;
create function pg_temp.fila() returns int language sql as $$
  select count(*)::int from net.http_request_queue where url = 'https://exemplo.invalid/webhook/pa-ensaio' $$;

-- 0. Configuração nasce desligada
select pg_temp.ok('0.config',
  c.slack_destinos = array['U0AQ4H2GZ0T']::text[] and c.ligado_em is null and c.n8n_webhook_url is null
  and c.planilha_id is null and length(c.segredo) = 64,
  'slack_destinos=' || array_to_string(c.slack_destinos, ',') || ' ligado_em=' || coalesce(c.ligado_em::text, 'nulo')
  || ' webhook=' || coalesce(c.n8n_webhook_url, 'nulo') || ' planilha_id=' || coalesce(c.planilha_id, 'nulo')
  || ' segredo=' || length(c.segredo) || ' caracteres (não impresso)')
  from public.pa_config c;

-- 1. Sem segredo / segredo errado: só {"ok": false}
select pg_temp.ok('1.sem_segredo_' || k, v = '{"ok": false}'::jsonb, k || ' -> ' || v::text)
  from (values ('reservar_nulo', pg_temp.anon('select public.pa_slack_reservar(null)::jsonb')),
               ('reservar_vazio', pg_temp.anon('select public.pa_slack_reservar('''')::jsonb')),
               ('reservar_errado', pg_temp.anon('select public.pa_slack_reservar(''errado'')::jsonb')),
               ('confirmar_errado', pg_temp.anon('select public.pa_slack_confirmar(''errado'', 9, ''U0AQ4H2GZ0T'', ''1.2'')::jsonb'))) x(k, v);

-- 2. Desligado (ligado_em nulo): nada, mesmo com os pendentes reais nº 9 e nº 10
select pg_temp.ok('2.desligado', v = '{"ok": true, "mensagens": []}'::jsonb, 'reservar com ligado_em nulo -> ' || v::text)
  from (select pg_temp.anon(format('select public.pa_slack_reservar(%L)::jsonb', pg_temp.seg())) v) x;

-- 3. Liga e cria p1 (o gatilho põe 1 chamada na fila do pg_net)
update public.pa_config set ligado_em = now(), n8n_webhook_url = 'https://exemplo.invalid/webhook/pa-ensaio';
insert into public.thb_alunos (id, nome, email, instrucao, espaco_instrucao, profissao, fonte)
values ('e0000000-0000-4000-8000-000000160402', 'ZZ Ensaio 160402 <b>Aluno</b> & Cia', 'zz.160402.aluno@exemplo.invalid',
        'THB', 'holding_masters', 'Advogada', 'ensaio_20261006160402');
create temp table _p (k text primary key, n bigint, r jsonb) on commit drop;
create temp table _f (k text primary key, v int) on commit drop;
insert into _f values ('antes_p1', pg_temp.fila());
insert into _p (k, r) values ('p1', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-000000160402","campo":"profissao","valor_novo":"Contadora",
   "motivo":"ensaio da migration 20261006160402"}''::jsonb)::jsonb'));
update _p set n = (r ->> 'numero')::bigint;
select pg_temp.ok('3.gatilho_p1',
  (select r ->> 'ok' from _p where k = 'p1') = 'true' and pg_temp.fila() = (select v from _f where k = 'antes_p1') + 1
  and exists (select 1 from net.http_request_queue q where q.url = 'https://exemplo.invalid/webhook/pa-ensaio'
                 and convert_from(q.body, 'UTF8')::jsonb = jsonb_build_object('pedido', (select n from _p where k = 'p1'))),
  'pedido nº ' || (select coalesce(n::text, r::text) from _p where k = 'p1') || ' criado; fila pg_net +'
  || (pg_temp.fila() - (select v from _f where k = 'antes_p1')) || ' com corpo {"pedido": nº}');

-- 4. Reserva: 1 DM, só para o Victor, texto escapado
create temp table _r (k text primary key, v jsonb) on commit drop;
insert into _r values ('r1', pg_temp.anon(format('select public.pa_slack_reservar(%L)::jsonb', pg_temp.seg())));
select pg_temp.ok('4.reserva_uma',
  jsonb_array_length(v -> 'mensagens') = 1
  and (v #>> '{mensagens,0,pedido}')::bigint = (select n from _p where k = 'p1')
  and v #>> '{mensagens,0,slack_id}' = 'U0AQ4H2GZ0T',
  'mensagens=' || coalesce(jsonb_array_length(v -> 'mensagens')::text, v::text) || ' pedido=' || coalesce(v #>> '{mensagens,0,pedido}', '?')
  || ' slack_id=' || coalesce(v #>> '{mensagens,0,slack_id}', '?') || ' (nº 9 e 10, anteriores a ligado_em, fora)')
  from _r where k = 'r1';
select pg_temp.ok('4.texto',
  v #>> '{mensagens,0,texto}' = ':memo: Solicitaram uma alteração do aluno *ZZ Ensaio 160402 &lt;b&gt;Aluno&lt;/b&gt; &amp; Cia*: Alterar dado, pedido por Victor Hugo. <https://grupoparticipa.app.br/educacional/pedidos-alteracao|Abrir a fila>',
  coalesce(v #>> '{mensagens,0,texto}', 'sem texto')) from _r where k = 'r1';

-- 5. Reservado: a segunda chamada não devolve de novo
select pg_temp.ok('5.nao_repete_reservado', v = '{"ok": true, "mensagens": []}'::jsonb, 'segunda reserva -> ' || v::text)
  from (select pg_temp.anon(format('select public.pa_slack_reservar(%L)::jsonb', pg_temp.seg())) v) x;

-- 6. Slack falhou (n8n não confirmou): reserva vence em 2 min e volta à fila
update public.pa_avisos set reservado_em = now() - interval '3 minutes' where pedido_id = (select n from _p where k = 'p1');
select pg_temp.ok('6.volta_se_falhou', jsonb_array_length(v -> 'mensagens') = 1 and (v #>> '{mensagens,0,pedido}')::bigint = (select n from _p where k = 'p1'),
  'reserva vencida -> ' || coalesce(jsonb_array_length(v -> 'mensagens')::text, v::text) || ' mensagem de novo')
  from (select pg_temp.anon(format('select public.pa_slack_reservar(%L)::jsonb', pg_temp.seg())) v) x;

-- 7. Confirmado: nunca mais (nem com a reserva vencida); confirmar de novo = ok false
select pg_temp.ok('7.confirmar', v = '{"ok": true}'::jsonb, 'confirmar -> ' || v::text)
  from (select pg_temp.anon(format('select public.pa_slack_confirmar(%L, %s, ''U0AQ4H2GZ0T'', ''1700000000.000100'')::jsonb',
                                   pg_temp.seg(), (select n from _p where k = 'p1'))) v) x;
update public.pa_avisos set reservado_em = now() - interval '3 minutes' where pedido_id = (select n from _p where k = 'p1');
select pg_temp.ok('7.enviado_nao_repete', v = '{"ok": true, "mensagens": []}'::jsonb, 'depois de enviado -> ' || v::text)
  from (select pg_temp.anon(format('select public.pa_slack_reservar(%L)::jsonb', pg_temp.seg())) v) x;
select pg_temp.ok('7.confirmar_de_novo', v = '{"ok": false}'::jsonb, 'segunda confirmação -> ' || v::text)
  from (select pg_temp.anon(format('select public.pa_slack_confirmar(%L, %s, ''U0AQ4H2GZ0T'', ''x'')::jsonb',
                                   pg_temp.seg(), (select n from _p where k = 'p1'))) v) x;

-- 8. Pedido decidido antes de o aviso sair: nenhuma DM
insert into _p (k, r) values ('p2', pg_temp.chamar('e1d2863d-c975-46bd-b35f-45b1039328e3', 'select public.pa_criar(''{"tipo":"outro",
   "aluno_id":"e0000000-0000-4000-8000-000000160402","descricao":"ensaio 160402: pedido recusado antes do aviso",
   "motivo":"ensaio da migration 20261006160402"}''::jsonb)::jsonb'));
update _p set n = (r ->> 'numero')::bigint where k = 'p2';
insert into _r values ('recusa_p2', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
  format('select public.pa_decidir(%s, ''recusar'', ''ensaio 160402'')::jsonb', (select n from _p where k = 'p2'))));
select pg_temp.ok('8.decidido_sem_dm',
  (select v ->> 'ok' from _r where k = 'recusa_p2') = 'true' and v = '{"ok": true, "mensagens": []}'::jsonb,
  'p2 nº ' || (select coalesce(n::text, r::text) from _p where k = 'p2') || ' recusado antes da rodada -> ' || v::text)
  from (select pg_temp.anon(format('select public.pa_slack_reservar(%L)::jsonb', pg_temp.seg())) v) x;

-- 9. Avisos: 1 por pedido, só U0AQ4H2GZ0T, enviado com o ts
select pg_temp.ok('9.avisos',
  (select count(*) from public.pa_avisos) = 1
  and (select bool_and(slack_id = 'U0AQ4H2GZ0T' and enviado_em is not null and slack_ts = '1700000000.000100') from public.pa_avisos),
  (select string_agg('pedido ' || pedido_id || ' -> ' || slack_id || ' enviado=' || (enviado_em is not null) || ' ts=' || coalesce(slack_ts, 'nulo'), '; ')
     from public.pa_avisos));

-- 10. O gatilho nunca derruba o insert (pa_config some no meio: o select do gatilho falha por dentro)
insert into _f values ('antes_p3', pg_temp.fila());
alter table public.pa_config rename to pa_config_ensaio;
insert into _p (k, r) values ('p3', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"outro",
   "aluno_id":"e0000000-0000-4000-8000-000000160402","descricao":"ensaio 160402: gatilho com falha",
   "motivo":"ensaio da migration 20261006160402"}''::jsonb)::jsonb'));
alter table public.pa_config_ensaio rename to pa_config;
select pg_temp.ok('10.gatilho_nao_derruba',
  r ->> 'ok' = 'true' and pg_temp.fila() = (select v from _f where k = 'antes_p3'),
  'insert com gatilho falhando -> ' || coalesce(r ->> 'msg', r ->> 'erro', r::text) || ' (fila pg_net sem chamada nova)')
  from _p where k = 'p3';

-- 11. Grants e tabelas fechadas
select pg_temp.ok('11.grants',
  has_function_privilege('anon', 'public.pa_slack_reservar(text)', 'execute')
  and has_function_privilege('anon', 'public.pa_slack_confirmar(text,bigint,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.pa_n8n_valido(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.pa_n8n_valido(text)', 'execute')
  and not has_function_privilege('anon', 'public.pa_fn_avisar_n8n()', 'execute')
  and not has_function_privilege('anon', 'public.pa_rotulo_tipo(text)', 'execute'),
  'reservar/confirmar: anon e authenticated; pa_n8n_valido, pa_rotulo_tipo e o gatilho fechados');
select pg_temp.ok('11.config_fechada', v ->> 'estado' = '42501', 'anon lendo pa_config -> ' || coalesce(v ->> 'erro', v::text))
  from (select pg_temp.anon('select to_jsonb(c) from public.pa_config c') v) x;
select pg_temp.ok('11.avisos_fechada', v ->> 'estado' = '42501', 'authenticated lendo pa_avisos -> ' || coalesce(v ->> 'erro', v::text))
  from (select pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select to_jsonb(a) from public.pa_avisos a limit 1') v) x;

-- 12. Plano da consulta da reserva
select pg_temp.plano('12.explain_reserva', $q$
select x.id, d.slack_id
  from public.pa_pedidos x
 cross join lateral (select distinct u as slack_id from unnest((select slack_destinos from public.pa_config)) u) d
 where x.status = 'pendente' and x.solicitado_em >= (select ligado_em from public.pa_config)
   and not exists (select 1 from public.pa_avisos a
                    where a.pedido_id = x.id and a.slack_id = d.slack_id
                      and (a.enviado_em is not null or a.reservado_em >= now() - interval '2 minutes'))
 order by x.id limit 20 $q$);

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
