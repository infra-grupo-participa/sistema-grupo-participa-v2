-- 20261006160402: Pedidos de alteração (etapa 2), aviso de pedido novo por DM no Slack (só para o Victor)
--
-- STATUS: NÃO APLICADA. Ensaio: 20261006160402_ensaio.sql (begin … rollback). Notas: 20261006160402.explain.md.
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
     and exists (select 1 from public.pa_config c where c.id and c.segredo = p_segredo);
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
