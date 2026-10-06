-- 20261006160403: ENSAIO (não aplica nada: termina em ROLLBACK)
--
-- Como rodar: python3 aplica_sql.py ensaio infra/supabase/migrations/20261006160403_ensaio.sql
--   (o script troca o select final por um RAISE: a transação aborta e a saída volta na mensagem).
--   No SQL editor: rodar até o "select … from _z_out" (inclusive), ler e rodar o "rollback;". Não deixar aberta.
--
-- Os corpos das migrations 20261006160402 (pré-requisito: pa_config, pa_n8n_valido) e 20261006160403 estão copiados
-- abaixo SEM mudança. Depois dos corpos: alunos ZZ e seis pedidos aplicados pelo Victor (consome 6 números da sequência
-- de pa_pedidos):
--   p1 aluno A: e-mail              p4 aluno A: telefone profissional (sem coluna)
--   p2 titular 1: troca, quem entra já existe     p5 aluno A: turma
--   p3 titular 2: troca, pessoa nova (titular 2 sem turma e sem entrada no THB)     p6 aluno A: nome
-- p3 é gravado direto em pa_pedidos (como no ensaio 20261006144913): o CPF do sócio novo, 484.621.880-58, FALHA no
-- dígito verificador, para nunca usar CPF que possa ser de alguém. O documento do aluno A é 111.111.111-11 (inválido).
-- As funções do n8n são chamadas COMO ANON (o caminho do PostgREST). O segredo nunca é impresso. O planilha_id do ensaio
-- é um texto inventado no formato da coluna (não é planilha nenhuma) e some no rollback.
--
-- Esperado: nenhuma linha começando com "ERRADO".
-- ═══ Conferência depois do ensaio (chamada separada): nada persistiu ═══
-- select to_regclass('public.pa_config') is null sem_config, to_regclass('public.pa_planilha_reservas') is null sem_reservas,
--        (select count(*) from public.thb_alunos where fonte in ('ensaio_20261006160403', 'pedido_alteracao')) alunos_zz,
--        (select max(id) from public.pa_pedidos) max_pedido;

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

-- ═══ CORPO DA MIGRATION 20261006160403_pa_planilha.sql (cópia sem mudança) ═══
-- 20261006160403: Pedidos de alteração (etapa 2), o n8n leva o pedido aplicado para a planilha da Central
--
-- STATUS: APLICADA em 06/10/2026 (pentester aprovou). Ensaio: 20261006160403_ensaio.sql (begin … rollback). Notas: 20261006160403.explain.md.
-- Depende da 20261006160402 (pa_config, pa_n8n_valido). Independente da 160401 e da 160404.
--
-- O banco NÃO escreve na planilha. Ele entrega ao n8n, com segredo, o que escrever e onde achar a linha; o n8n escreve
-- (credencial Google do Victor) e devolve o resultado. Primeiro numa CÓPIA da planilha: pa_config.planilha_id nasce
-- NULO e, enquanto for nulo, a reserva não devolve nenhum pedido.
--
-- DECISÕES DO VICTOR (06/10/2026, noite) que esta migration traduz
--   • Casar a linha só por e-mail (as duas partes de "novo / antigo") ou documento; nunca por nome. 0 ou mais de 1
--     linha, ou célula diferente do esperado = erro, não escreve (regra aplicada pelo n8n com as chaves daqui).
--   • Alterar dado: nome→Nome (A), email→Email (C) no formato "novo / antigo", telefone→Telefone (D),
--     documento→Documento (B), endereço→CEP..Complemento (E..L), profissao→Profissão (M), turma→Turma (P, código),
--     instrucao→Instrução (O), obs_central→Obs (AM). telefone_profissional e espaco_instrucao não têm coluna: nada a
--     escrever, o n8n confirma ok com o detalhe.
--   • Troca de sócio: a linha de quem sai vai para "Removidos — Histórico" (J Motivo, K Transação de origem,
--     M Tinha acesso antigo?, N Quem determinou com os textos decididos). Se quem entra NÃO tem linha: a linha de
--     quem sai é sobrescrita (A..M do cadastro, O instrução, P/AI/W do titular, N/Q/R copiados da linha do titular,
--     S/T/U/Y/AE/BM/BN/BO com os padrões de sócio, AF nome do titular, demais colunas vazias). Se quem entra JÁ tem
--     linha: a linha de quem sai é APAGADA e na de quem entra só O, U, W, Y, AF. Titular: AG = sócios atuais
--     separados por "; " e AH = num_socios.
--   • Sem coluna nova de trilha na planilha.
--   Os nomes de aba e de cabeçalho abaixo são as strings EXATAS lidas da planilha 15ugo5… em 06/10/2026 (linha 1).
--
-- O QUE FAZ
--   1. pa_planilha_reservas (pedido_id, reservado_em): reserva de 10 minutos, fechada. Tabela própria em vez de
--      coluna nova em pa_pedidos: nada que a tela lê muda.
--   2. pa_planilha_reservar(p_segredo): até 5 pedidos `aplicado` com planilha_status = 'pendente' (alterar_dado e
--      trocar_socio), em ordem de nº, sem reserva viva; reserva e devolve, por pedido, as chaves e os valores por NOME
--      de cabeçalho (datas dd/mm/aaaa, turma pelo código, nulo vira ""). Sem segredo válido: {"ok": false} e nada mais.
--   3. pa_planilha_confirmar(p_segredo, p_pedido, p_ok, p_erro, p_detalhe): só para pedido reservado e pendente;
--      grava planilha_status ok/erro, planilha_em, planilha_erro e uma linha em pa_historico ('planilha_ok' ou
--      'planilha_erro', por = nulo, detalhe limitado a 8000 caracteres). Tira a reserva.
--   Funções com segredo: execute para anon e authenticated (o n8n chama pelo PostgREST), como ra_slack_*.
--
-- AS 5 PERGUNTAS
--   escala: dezenas de pedidos por mês; a reserva lê só os aplicados com planilha pendente (hoje 0) e no máximo 5.
--   índice: já existem pa_pedidos_planilha_idx (id) where planilha_status = 'pendente' e pa_pedidos_status_idx
--     (status, id); reservas pela pk. Nenhum índice novo (com a tabela pequena o planejador lê a tabela inteira, ver
--     o explain no .explain.md).
--   frequência: rodada de 15 min do n8n (desligado até o Victor ligar).
--   repetição: "for update skip locked" + reserva de 10 min + "on conflict … where reserva vencida": duas rodadas ao
--     mesmo tempo não pegam o mesmo pedido; confirmar exige reserva e planilha pendente (não confirma duas vezes).
--   reversão: bloco REVERSÃO no fim (drop das funções e da tabela nova). Nada existente é alterado.
--
-- Quem lê fora do v2: ninguém (objetos novos; pa_pedidos só é lido pelo v2).

set local lock_timeout = '5s';

-- ═══ 0. Guarda ═══
do $guarda$
begin
  if to_regclass('public.pa_config') is null or to_regprocedure('public.pa_n8n_valido(text)') is null then
    raise exception '20261006160403: aplicar antes a 20261006160402 (pa_config, pa_n8n_valido)';
  end if;
  if to_regclass('public.pa_planilha_reservas') is not null then
    raise exception '20261006160403: pa_planilha_reservas já existe (migration já aplicada?)';
  end if;
  if to_regprocedure('public.pa_contar_socios(uuid)') is null or to_regprocedure('public.pa_chave_nome(text)') is null
     or to_regprocedure('public.pa_txt(jsonb)') is null then
    raise exception '20261006160403: pa_contar_socios, pa_chave_nome ou pa_txt ausente';
  end if;
end
$guarda$;

-- ═══ 1. Reserva (fechada) ═══
create table public.pa_planilha_reservas (
  pedido_id    bigint primary key references public.pa_pedidos(id) on delete cascade,
  reservado_em timestamptz not null default now()
);
alter table public.pa_planilha_reservas enable row level security;
revoke all on table public.pa_planilha_reservas from public, anon, authenticated;

-- ═══ 2. Auxiliares internas ═══
-- Texto para a célula: nulo vira "" (escrever "" limpa a célula).
create function public.pa_planilha_cel(p text)
returns text language sql immutable set search_path = '' as $$
  select coalesce(btrim(p), '');
$$;

-- Chaves para achar a linha: e-mails (minúsculo, sem espaço) e documentos (só dígitos, 11 ou mais) do aluno no banco
-- mais os extras (valor antigo de uma alteração). Aluno apagado (nulo): listas vazias, o n8n acha 0 linhas = erro.
create function public.pa_planilha_chaves(p_aluno uuid, p_emails text[] default '{}', p_docs text[] default '{}')
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'emails', coalesce((select jsonb_agg(distinct e order by e) from (
                 select lower(btrim(x)) e from unnest(array[(select a.email from public.thb_alunos a where a.id = p_aluno)]
                                                      || coalesce(p_emails, '{}')) x) s
                where e is not null and e <> ''), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(distinct d order by d) from (
                 select regexp_replace(coalesce(x, ''), '\D', '', 'g') d
                   from unnest(array[(select a.documento from public.thb_alunos a where a.id = p_aluno)]
                               || coalesce(p_docs, '{}')) x) s
                where length(d) >= 11), '[]'::jsonb));
$$;

-- Os cabeçalhos usados, com a coluna em que estavam em 06/10/2026: o n8n confere a linha 1 antes de escrever.
create function public.pa_planilha_cabecalhos()
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'Central de Acessos 2026', jsonb_build_object(
      'Nome', 'A', 'Documento', 'B', 'Email', 'C', 'Telefone', 'D', 'CEP', 'E', 'Cidade', 'F', 'Estado', 'G',
      'Bairro', 'H', 'País', 'I', 'Endereço', 'J', 'Número', 'K', 'Complemento', 'L', 'Profissão', 'M',
      'Produto', 'N', 'Instrução', 'O', 'Turma', 'P', 'Turma Aurum', 'Q', 'Nível', 'R', 'Oferta', 'S',
      'Tipo de oferta', 'T', 'Regra de acesso', 'U', 'Data de expiração', 'W', 'Status do acesso', 'Y',
      'Origem do acesso', 'AE', 'Sócio de (titular)', 'AF', 'Sócio', 'AG', 'Nº de sócios', 'AH',
      'Data de entrada no THB', 'AI', 'Obs', 'AM', 'Canal de aquisição', 'BM', 'Tipo de entrada', 'BN',
      'Origem do canal (como foi atribuído)', 'BO'),
    'Removidos — Histórico', jsonb_build_object(
      'Data da saída', 'A', 'Nome', 'B', 'Documento', 'C', 'E-mail', 'D', 'Telefone', 'E', 'Linha na Central', 'F',
      'Instrução que tinha', 'G', 'Turma que tinha', 'H', 'Expiração que tinha', 'I', 'Motivo', 'J',
      'Transação de origem', 'K', 'Valor', 'L', 'Tinha acesso antigo?', 'M', 'Quem determinou', 'N'));
$$;

-- O que o n8n faz com UM pedido. Interna (chamada só por pa_planilha_reservar).
create function public.pa_planilha_pedido(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r public.pa_pedidos%rowtype;
  t public.thb_alunos%rowtype;
  e public.thb_alunos%rowtype;
  v_entra uuid;
  v_aprov text;
  v_dia text;
  v_turma text;
  v_ant jsonb;
  v_nov jsonb;
  v_esc jsonb := '{}'::jsonb;
  v_antes jsonb := '{}'::jsonb;
  v_socios text;
  v_copiar text[];
  v_end_cols constant jsonb := jsonb_build_object(
    'cep', 'CEP', 'cidade', 'Cidade', 'estado', 'Estado', 'bairro', 'Bairro', 'pais', 'País',
    'endereco_logradouro', 'Endereço', 'endereco_numero', 'Número', 'endereco_complemento', 'Complemento');
  v_cab text;
  v_k text;
begin
  select * into r from public.pa_pedidos where id = p_id;
  v_aprov := coalesce((select p.nome from public.perfis p where p.id = r.decidido_por), '(aprovador não encontrado)');
  v_dia := to_char(r.decidido_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');

  if r.tipo = 'alterar_dado' then
    v_ant := r.valor_atual;
    v_nov := coalesce(r.valor_aplicado, r.valor_novo);
    if r.campo in ('telefone_profissional', 'espaco_instrucao') then
      return jsonb_build_object('pedido', r.id, 'tipo', r.tipo, 'campo', r.campo,
        'aluno', jsonb_build_object('nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
                                    'chaves', public.pa_planilha_chaves(r.aluno_id)),
        'escrever', '{}'::jsonb, 'esperado_antes', '{}'::jsonb, 'sem_coluna', true,
        'detalhe', case r.campo when 'telefone_profissional' then 'Telefone profissional' else 'Espaço de instrução' end
                   || ' não tem coluna na Central: nada a escrever.');
    end if;
    if r.campo = 'endereco' then
      for v_k, v_cab in select key, value from jsonb_each_text(v_end_cols) loop
        v_esc := v_esc || jsonb_build_object(v_cab, public.pa_planilha_cel(public.pa_txt(v_nov -> v_k)));
        v_antes := v_antes || jsonb_build_object(v_cab, public.pa_planilha_cel(public.pa_txt(v_ant -> v_k)));
      end loop;
    elsif r.campo = 'turma_id' then
      v_esc := jsonb_build_object('Turma', public.pa_planilha_cel(
                 (select tu.codigo from public.thb_turmas tu where tu.id = (public.pa_txt(v_nov))::int)));
      v_antes := jsonb_build_object('Turma', public.pa_planilha_cel(
                 (select tu.codigo from public.thb_turmas tu where tu.id = (public.pa_txt(v_ant))::int)));
    elsif r.campo = 'email' then
      v_esc := jsonb_build_object('Email', public.pa_txt(v_nov) || coalesce(' / ' || public.pa_txt(v_ant), ''));
      v_antes := jsonb_build_object('Email', public.pa_planilha_cel(public.pa_txt(v_ant)));
    else
      v_cab := case r.campo when 'nome' then 'Nome' when 'telefone' then 'Telefone' when 'documento' then 'Documento'
                            when 'profissao' then 'Profissão' when 'instrucao' then 'Instrução' when 'obs_central' then 'Obs' end;
      if v_cab is null then
        -- Campo novo sem mapeamento: não derruba a rodada; o n8n confirma como erro com esta mensagem.
        return jsonb_build_object('pedido', r.id, 'tipo', r.tipo, 'campo', r.campo,
          'erro', 'Campo ' || coalesce(r.campo, '(nulo)') || ' sem coluna mapeada no banco: confirmar como erro.');
      end if;
      v_esc := jsonb_build_object(v_cab, public.pa_planilha_cel(public.pa_txt(v_nov)));
      v_antes := jsonb_build_object(v_cab, public.pa_planilha_cel(public.pa_txt(v_ant)));
    end if;
    return jsonb_build_object('pedido', r.id, 'tipo', r.tipo, 'campo', r.campo,
      'aluno', jsonb_build_object(
         'nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
         'chaves', public.pa_planilha_chaves(r.aluno_id,
                     case when r.campo = 'email' then array[public.pa_txt(v_ant), public.pa_txt(v_nov)] else '{}'::text[] end,
                     case when r.campo = 'documento' then array[public.pa_txt(v_ant), public.pa_txt(v_nov)] else '{}'::text[] end)),
      'escrever', v_esc, 'esperado_antes', v_antes, 'sem_coluna', false, 'detalhe', null);
  end if;

  -- trocar_socio
  select * into t from public.thb_alunos where id = r.aluno_id;
  v_entra := coalesce(r.socio_entra_id, (r.valor_aplicado ->> 'socio_entra_id')::uuid);
  select * into e from public.thb_alunos where id = v_entra;
  v_turma := (select tu.codigo from public.thb_turmas tu where tu.id = t.turma_id);
  -- Sócios atuais do titular, pela mesma regra de pa_contar_socios.
  select string_agg(s.nome, '; ' order by s.nome) into v_socios
    from public.thb_alunos s
   where t.id is not null and s.id <> t.id and s.cancelado_em is null
     and (s.socio_de_aluno_id = t.id
          or (s.socio_de_aluno_id is null and coalesce(s.eh_socio, false)
              and public.pa_chave_nome(s.socio_de_nome) = public.pa_chave_nome(t.nome)));
  -- O que não está no banco do titular sai da linha dele na planilha.
  v_copiar := array['Produto', 'Turma Aurum', 'Nível']
              || case when v_turma is null then array['Turma'] else '{}'::text[] end
              || case when t.data_entrada_thb is null then array['Data de entrada no THB'] else '{}'::text[] end
              || case when t.data_expiracao is null then array['Data de expiração'] else '{}'::text[] end;

  return jsonb_build_object('pedido', r.id, 'tipo', r.tipo,
    'titular', jsonb_build_object(
       'nome', coalesce(t.nome, r.aluno_nome),
       'chaves', public.pa_planilha_chaves(r.aluno_id),
       'escrever', jsonb_build_object('Sócio', coalesce(v_socios, ''), 'Nº de sócios', coalesce(t.num_socios::text, ''))),
    'sai', jsonb_build_object(
       'nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.socio_sai_id), r.socio_sai_nome),
       'chaves', public.pa_planilha_chaves(r.socio_sai_id)),
    'entra', jsonb_build_object(
       'nome', coalesce(e.nome, r.socio_entra_nome, r.socio_entra_novo ->> 'nome'),
       'chaves', public.pa_planilha_chaves(v_entra),
       'socio_novo', coalesce((r.valor_aplicado ->> 'socio_novo')::boolean, r.socio_entra_id is null)),
    -- Linha nova em "Removidos — Histórico": estes valores fixos + os copiados da linha de quem sai + "Linha na Central"
    -- (número da linha de quem sai, achado pelo n8n).
    'removidos', jsonb_build_object(
       'Data da saída', coalesce(v_dia, ''),
       'Motivo', 'Troca de sócio: saiu como sócio de ' || coalesce(t.nome, r.aluno_nome) || ' (pedido nº ' || r.id || ')',
       'Transação de origem', 'PEDIDO-ALTERACAO-' || r.id,
       'Valor', '',
       'Tinha acesso antigo?', 'ver caso de Remoção de Acessos',
       'Quem determinou', 'Pedido nº ' || r.id || ', aprovado por ' || v_aprov || ', ' || coalesce(v_dia, '')),
    'copiar_para_removidos', jsonb_build_object(
       'Nome', 'Nome', 'Documento', 'Documento', 'E-mail', 'Email', 'Telefone', 'Telefone',
       'Instrução que tinha', 'Instrução', 'Turma que tinha', 'Turma', 'Expiração que tinha', 'Data de expiração'),
    -- Quem entra NÃO tem linha: sobrescreve a linha de quem sai (depois de copiá-la para Removidos).
    'se_entra_sem_linha', jsonb_build_object(
       'acao', 'sobrescrever a linha de quem sai',
       'escrever', jsonb_strip_nulls(jsonb_build_object(
          'Nome', public.pa_planilha_cel(e.nome), 'Documento', public.pa_planilha_cel(e.documento),
          'Email', public.pa_planilha_cel(e.email), 'Telefone', public.pa_planilha_cel(e.telefone),
          'CEP', public.pa_planilha_cel(e.cep), 'Cidade', public.pa_planilha_cel(e.cidade),
          'Estado', public.pa_planilha_cel(e.estado), 'Bairro', public.pa_planilha_cel(e.bairro),
          'País', public.pa_planilha_cel(e.pais), 'Endereço', public.pa_planilha_cel(e.endereco_logradouro),
          'Número', public.pa_planilha_cel(e.endereco_numero), 'Complemento', public.pa_planilha_cel(e.endereco_complemento),
          'Profissão', public.pa_planilha_cel(e.profissao),
          'Instrução', public.pa_planilha_cel(coalesce(r.valor_aplicado ->> 'instrucao', e.instrucao)),
          'Turma', v_turma,
          'Data de entrada no THB', to_char(t.data_entrada_thb, 'DD/MM/YYYY'),
          'Data de expiração', to_char(t.data_expiracao, 'DD/MM/YYYY'),
          'Oferta', '(convite/cadastro manual)', 'Tipo de oferta', 'Sócio', 'Regra de acesso', 'Acompanha titular',
          'Status do acesso', 'Acompanha titular', 'Origem do acesso', 'Sócio/Convite',
          'Canal de aquisição', 'Sócio', 'Tipo de entrada', 'Sócio',
          'Origem do canal (como foi atribuído)', 'É sócio — acompanha o titular',
          'Sócio de (titular)', public.pa_planilha_cel(t.nome))),
       'copiar_do_titular', to_jsonb(v_copiar),
       'limpar_demais', true),
    -- Quem entra JÁ tem linha: apaga a linha de quem sai (depois de copiá-la) e escreve só estas 5 na de quem entra.
    'se_entra_com_linha', jsonb_build_object(
       'acao', 'apagar a linha de quem sai',
       'escrever', jsonb_strip_nulls(jsonb_build_object(
          'Instrução', public.pa_planilha_cel(coalesce(r.valor_aplicado ->> 'instrucao', e.instrucao)),
          'Regra de acesso', 'Acompanha titular',
          'Data de expiração', to_char(t.data_expiracao, 'DD/MM/YYYY'),
          'Status do acesso', 'Acompanha titular',
          'Sócio de (titular)', public.pa_planilha_cel(t.nome))),
       'copiar_do_titular', case when t.data_expiracao is null then '["Data de expiração"]'::jsonb else '[]'::jsonb end));
end
$$;

-- ═══ 3. Reserva para o n8n ═══
create function public.pa_planilha_reservar(p_segredo text)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_planilha text;
  v_ids bigint[];
begin
  if not public.pa_n8n_valido(p_segredo) then return json_build_object('ok', false); end if;
  select c.planilha_id into v_planilha from public.pa_config c;
  if v_planilha is null then return json_build_object('ok', true, 'planilha_id', null, 'pedidos', '[]'::json); end if;

  with alvo as (
    select x.id from public.pa_pedidos x
     where x.status = 'aplicado' and x.planilha_status = 'pendente' and x.tipo in ('alterar_dado', 'trocar_socio')
       and not exists (select 1 from public.pa_planilha_reservas pr
                        where pr.pedido_id = x.id and pr.reservado_em >= now() - interval '10 minutes')
     order by x.id
     limit 5
     for update of x skip locked
  ), res as (
    insert into public.pa_planilha_reservas as pr (pedido_id, reservado_em)
    select id, now() from alvo
    on conflict (pedido_id) do update set reservado_em = excluded.reservado_em
      where pr.reservado_em < now() - interval '10 minutes'
    returning pr.pedido_id
  )
  select array_agg(pedido_id order by pedido_id) into v_ids from res;

  return json_build_object('ok', true, 'planilha_id', v_planilha,
    'abas', json_build_object('central', 'Central de Acessos 2026', 'removidos', 'Removidos — Histórico'),
    'cabecalhos', public.pa_planilha_cabecalhos(),
    'reserva_minutos', 10,
    'pedidos', coalesce((select json_agg(public.pa_planilha_pedido(i) order by i) from unnest(v_ids) i), '[]'::json));
end
$$;

-- ═══ 4. Resultado do n8n ═══
create function public.pa_planilha_confirmar(p_segredo text, p_pedido bigint, p_ok boolean, p_erro text default null,
                                             p_detalhe jsonb default null)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_det jsonb := coalesce(p_detalhe, '{}'::jsonb);
  v_erro text;
begin
  if not public.pa_n8n_valido(p_segredo) then return json_build_object('ok', false); end if;
  if p_ok is null then return json_build_object('ok', false, 'msg', 'p_ok é obrigatório.'); end if;
  if length(v_det::text) > 8000 then
    v_det := jsonb_build_object('truncado', true, 'inicio', left(v_det::text, 8000));
  end if;
  v_erro := case when p_ok then null else left(coalesce(nullif(btrim(p_erro), ''), 'erro sem mensagem do n8n'), 500) end;

  update public.pa_pedidos x
     set planilha_status = case when p_ok then 'ok' else 'erro' end, planilha_em = now(), planilha_erro = v_erro
   where x.id = p_pedido and x.status = 'aplicado' and x.planilha_status = 'pendente'
     and exists (select 1 from public.pa_planilha_reservas pr where pr.pedido_id = x.id);
  if not found then
    return json_build_object('ok', false, 'msg', 'Pedido sem reserva ou com a planilha já resolvida.');
  end if;
  delete from public.pa_planilha_reservas where pedido_id = p_pedido;
  insert into public.pa_historico (pedido_id, acao, por, detalhe)
  values (p_pedido, case when p_ok then 'planilha_ok' else 'planilha_erro' end, null,
          v_det || case when p_ok then '{}'::jsonb else jsonb_build_object('erro', v_erro) end);
  return json_build_object('ok', true);
end
$$;

-- ═══ 5. Permissões ═══
revoke all on function public.pa_planilha_cel(text) from public, anon, authenticated;
revoke all on function public.pa_planilha_chaves(uuid, text[], text[]) from public, anon, authenticated;
revoke all on function public.pa_planilha_cabecalhos() from public, anon, authenticated;
revoke all on function public.pa_planilha_pedido(bigint) from public, anon, authenticated;
revoke all on function public.pa_planilha_reservar(text) from public;
revoke all on function public.pa_planilha_confirmar(text, bigint, boolean, text, jsonb) from public;
grant execute on function public.pa_planilha_reservar(text) to anon, authenticated;
grant execute on function public.pa_planilha_confirmar(text, bigint, boolean, text, jsonb) to anon, authenticated;

-- ═══ 6. Conferência ═══
do $confere$
begin
  if has_table_privilege('anon', 'public.pa_planilha_reservas', 'select')
     or has_table_privilege('authenticated', 'public.pa_planilha_reservas', 'select') then
    raise exception '20261006160403: pa_planilha_reservas legível por anon/authenticated';
  end if;
  if has_function_privilege('anon', 'public.pa_planilha_pedido(bigint)', 'execute')
     or has_function_privilege('authenticated', 'public.pa_planilha_pedido(bigint)', 'execute')
     or has_function_privilege('anon', 'public.pa_planilha_chaves(uuid,text[],text[])', 'execute') then
    raise exception '20261006160403: função interna exposta';
  end if;
  if not has_function_privilege('anon', 'public.pa_planilha_reservar(text)', 'execute') then
    raise exception '20261006160403: pa_planilha_reservar sem execute para anon';
  end if;
end
$confere$;

-- ═══ REVERSÃO (não rodar junto com a migration) ═══
-- Tira as funções e a tabela de reservas. Nada existente foi alterado; pedidos já marcados ok/erro e as linhas
-- 'planilha_ok'/'planilha_erro' de pa_historico ficam (são registro do que aconteceu). Desligar antes o workflow do n8n.
-- Para reverter: tirar o "-- " das linhas abaixo e rodar.
--
-- drop function if exists public.pa_planilha_confirmar(text, bigint, boolean, text, jsonb);
-- drop function if exists public.pa_planilha_reservar(text);
-- drop function if exists public.pa_planilha_pedido(bigint);
-- drop function if exists public.pa_planilha_cabecalhos();
-- drop function if exists public.pa_planilha_chaves(uuid, text[], text[]);
-- drop function if exists public.pa_planilha_cel(text);
-- drop table if exists public.pa_planilha_reservas;

-- ═══ ENSAIO: testes ═══════════════════════════════════════════════════════════════════════════

create temp table _s on commit drop as select segredo as s from public.pa_config;
create function pg_temp.seg() returns text language sql as $$ select s from pg_temp._s $$;
create function pg_temp.reservar() returns jsonb language sql as $$
  select pg_temp.anon(format('select public.pa_planilha_reservar(%L)::jsonb', pg_temp.seg())) $$;
create function pg_temp.ids(j jsonb) returns text language sql as $$
  select coalesce((select string_agg(x ->> 'pedido', ',' order by (x ->> 'pedido')::bigint)
                     from jsonb_array_elements(j -> 'pedidos') x), '') $$;
create temp table _p (k text primary key, n bigint, criar jsonb, decidir jsonb) on commit drop;
create function pg_temp.n(p_k text) returns bigint language sql as $$ select n from pg_temp._p where k = p_k $$;
create temp table _r (k text primary key, v jsonb) on commit drop;
create function pg_temp.ped(p_k text) returns jsonb language sql as $$
  select x from pg_temp._r r, jsonb_array_elements(r.v -> 'pedidos') x
   where r.k in ('r1', 'r2') and (x ->> 'pedido')::bigint = pg_temp.n(p_k) $$;
create temp table _dia on commit drop as select to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') d;

-- 1. Sem segredo / segredo errado: só {"ok": false}
select pg_temp.ok('1.sem_segredo_' || k, v = '{"ok": false}'::jsonb, k || ' -> ' || v::text)
  from (values ('reservar_nulo', pg_temp.anon('select public.pa_planilha_reservar(null)::jsonb')),
               ('reservar_errado', pg_temp.anon('select public.pa_planilha_reservar(''errado'')::jsonb')),
               ('confirmar_errado', pg_temp.anon('select public.pa_planilha_confirmar(''errado'', 9, true)::jsonb'))) x(k, v);

-- Alunos ZZ
insert into public.thb_alunos (id, nome, email, documento, instrucao, espaco_instrucao, data_expiracao, mes_expiracao,
                               ano_expiracao, num_socios, fonte, data_entrada_thb, turma_id)
values ('e0000000-0000-4000-8000-0000001604a0', 'ZZ Ensaio 160403 Aluno A', 'zz.160403.a@exemplo.invalid', '11111111111',
        'THB', 'holding_masters', '2027-01-31', 1, 2027, null, 'ensaio_20261006160403', '2024-02-02', 55),
       ('e0000000-0000-4000-8000-0000001604b0', 'ZZ Ensaio 160403 Titular Um', 'zz.160403.t1@exemplo.invalid', null,
        'THB', 'holding_masters', '2027-03-31', 3, 2027, 2, 'ensaio_20261006160403', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000001604b1', 'ZZ Ensaio 160403 Sai Um', 'zz.160403.sai1@exemplo.invalid', null,
        'THB - SÓCIO', 'holding_masters', '2027-03-31', 3, 2027, null, 'ensaio_20261006160403', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000001604b2', 'ZZ Ensaio 160403 Fica', 'zz.160403.fica@exemplo.invalid', null,
        'THB - SÓCIO', 'holding_masters', '2027-03-31', 3, 2027, null, 'ensaio_20261006160403', '2025-01-10', 54),
       ('e0000000-0000-4000-8000-0000001604b3', 'ZZ Ensaio 160403 Entra Existente', 'zz.160403.entra@exemplo.invalid', null,
        'THB', 'holding_masters', null, null, null, null, 'ensaio_20261006160403', '2024-05-05', 55),
       ('e0000000-0000-4000-8000-0000001604c0', 'ZZ Ensaio 160403 Titular Dois', 'zz.160403.t2@exemplo.invalid', null,
        'AURUM', 'aurum', '2026-12-31', 12, 2026, 1, 'ensaio_20261006160403', null, null),
       ('e0000000-0000-4000-8000-0000001604c1', 'ZZ Ensaio 160403 Sai Dois', 'zz.160403.sai2@exemplo.invalid', null,
        'AURUM - SÓCIO', 'aurum', '2026-12-31', 12, 2026, null, 'ensaio_20261006160403', null, null);
update public.thb_alunos set eh_socio = true, socio_de_aluno_id = 'e0000000-0000-4000-8000-0000001604b0',
       socio_de_nome = 'ZZ Ensaio 160403 Titular Um'
 where id in ('e0000000-0000-4000-8000-0000001604b1', 'e0000000-0000-4000-8000-0000001604b2');
update public.thb_alunos set eh_socio = true, socio_de_aluno_id = 'e0000000-0000-4000-8000-0000001604c0',
       socio_de_nome = 'ZZ Ensaio 160403 Titular Dois'
 where id = 'e0000000-0000-4000-8000-0000001604c1';

-- Pedidos p1..p6, na ordem (o nº cresce na ordem de criação)
insert into _p (k, criar) values ('p1', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-0000001604a0","campo":"email","valor_novo":"zz.160403.a.novo@exemplo.invalid",
   "motivo":"ensaio da migration 20261006160403"}''::jsonb)::jsonb'));
insert into _p (k, criar) values ('p2', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"trocar_socio",
   "aluno_id":"e0000000-0000-4000-8000-0000001604b0","socio_sai_id":"e0000000-0000-4000-8000-0000001604b1",
   "socio_entra_id":"e0000000-0000-4000-8000-0000001604b3","motivo":"ensaio da migration 20261006160403"}''::jsonb)::jsonb'));
with ins as (
  insert into public.pa_pedidos (tipo, aluno_id, aluno_nome, campo, valor_atual, valor_novo, socio_sai_id, socio_sai_nome,
                                 socio_entra_id, socio_entra_nome, socio_entra_novo, descricao, motivo, evidencia, solicitado_por)
  select 'trocar_socio', t.id, t.nome, null, jsonb_build_object('socio_sai_vinculado', true, 'num_socios', t.num_socios), null,
         s.id, s.nome, null, 'ZZ Ensaio 160403 Novo',
         jsonb_build_object('nome', 'ZZ Ensaio 160403 Novo', 'email', 'zz.160403.novo@exemplo.invalid',
           'telefone', public.pa_telefone_pessoa('(21) 97777-0013', true), 'documento', '48462188058', 'tipo_documento', 'CPF',
           'profissao', 'Contadora', 'endereco_mantido', false,
           'endereco', public.pa_endereco('{"pais":"Brasil","cep":"20040-020","endereco_logradouro":"Av. Ensaio",
             "endereco_numero":"1","bairro":"Centro","cidade":"Rio de Janeiro","estado":"RJ"}'::jsonb, true)),
         null, 'ensaio da migration 20261006160403', null, '81d2eaee-cce1-4058-8714-439b0fc6f970'
    from public.thb_alunos t, public.thb_alunos s
   where t.id = 'e0000000-0000-4000-8000-0000001604c0' and s.id = 'e0000000-0000-4000-8000-0000001604c1'
  returning id),
hist as (
  insert into public.pa_historico (pedido_id, acao, por, detalhe)
  select id, 'criado', '81d2eaee-cce1-4058-8714-439b0fc6f970', '{"tipo":"trocar_socio","campo":null}'::jsonb from ins)
insert into _p (k, criar) select 'p3', jsonb_build_object('ok', true, 'numero', id) from ins;
insert into _p (k, criar) values ('p4', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-0000001604a0","campo":"telefone_profissional","valor_novo":"(21) 3333-4444",
   "motivo":"ensaio da migration 20261006160403"}''::jsonb)::jsonb'));
insert into _p (k, criar) values ('p5', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-0000001604a0","campo":"turma_id","valor_novo":56,
   "motivo":"ensaio da migration 20261006160403"}''::jsonb)::jsonb'));
insert into _p (k, criar) values ('p6', pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970', 'select public.pa_criar(''{"tipo":"alterar_dado",
   "aluno_id":"e0000000-0000-4000-8000-0000001604a0","campo":"nome","valor_novo":"ZZ Ensaio 160403 Aluno A Renomeado",
   "motivo":"ensaio da migration 20261006160403"}''::jsonb)::jsonb'));
update _p set n = (criar ->> 'numero')::bigint;
-- Decide um por vez, na ordem (p1 antes de p6: o nome muda por último).
do $$ declare v_k text; begin
  for v_k in select x.k from pg_temp._p x order by x.n loop
    update pg_temp._p set decidir = pg_temp.chamar('81d2eaee-cce1-4058-8714-439b0fc6f970',
           format('select public.pa_decidir(%s, ''aprovar'')::jsonb', n)) where _p.k = v_k;
  end loop; end $$;
select pg_temp.ok('2.aplicado_' || k, (decidir ->> 'ok')::boolean and decidir ->> 'status' = 'aplicado'
  and (select planilha_status from public.pa_pedidos where id = n) = 'pendente',
  coalesce(decidir ->> 'msg', decidir ->> 'erro', criar ->> 'msg', criar ->> 'erro', 'sem retorno')) from _p order by k;

-- 3. planilha_id nulo: nada sai
select pg_temp.ok('3.sem_planilha', v = '{"ok": true, "pedidos": [], "planilha_id": null}'::jsonb, 'planilha_id nulo -> ' || v::text)
  from (select pg_temp.reservar() v) x;

-- 4. Com planilha_id: 5 por vez, em ordem de nº; depois o 6º; depois nada
update public.pa_config set planilha_id = 'ensaioCopiaDaPlanilha160403zz';
insert into _r values ('r1', pg_temp.reservar());
insert into _r values ('r2', pg_temp.reservar());
insert into _r values ('r3', pg_temp.reservar());
select pg_temp.ok('4.limite_e_ordem',
  pg_temp.ids((select v from _r where k = 'r1')) = (select string_agg(n::text, ',' order by n) from _p where k <> 'p6')
  and pg_temp.ids((select v from _r where k = 'r2')) = pg_temp.n('p6')::text
  and pg_temp.ids((select v from _r where k = 'r3')) = ''
  and (select v ->> 'planilha_id' from _r where k = 'r1') = 'ensaioCopiaDaPlanilha160403zz',
  '1ª reserva: [' || pg_temp.ids((select v from _r where k = 'r1')) || '] 2ª: [' || pg_temp.ids((select v from _r where k = 'r2'))
  || '] 3ª: [' || pg_temp.ids((select v from _r where k = 'r3')) || '] (nº 9 e 10 pendentes de decisão: fora)');

-- 5. Alterar e-mail: "novo / antigo", chaves com os dois
select pg_temp.ok('5.email', j -> 'escrever' = '{"Email": "zz.160403.a.novo@exemplo.invalid / zz.160403.a@exemplo.invalid"}'::jsonb
  and j -> 'esperado_antes' = '{"Email": "zz.160403.a@exemplo.invalid"}'::jsonb
  and j #> '{aluno,chaves,emails}' = '["zz.160403.a.novo@exemplo.invalid", "zz.160403.a@exemplo.invalid"]'::jsonb
  and j #> '{aluno,chaves,documentos}' = '["11111111111"]'::jsonb,
  'escrever=' || (j -> 'escrever')::text || ' | chaves: ' || jsonb_array_length(j #> '{aluno,chaves,emails}') || ' e-mails, '
  || jsonb_array_length(j #> '{aluno,chaves,documentos}') || ' documento')
  from (select pg_temp.ped('p1') j) x;

-- 6. Troca com quem já existe
select pg_temp.ok('6.troca_titular', j #> '{titular,escrever}'
     = '{"Sócio": "ZZ Ensaio 160403 Entra Existente; ZZ Ensaio 160403 Fica", "Nº de sócios": "2"}'::jsonb
  and j #> '{titular,chaves,emails}' = '["zz.160403.t1@exemplo.invalid"]'::jsonb
  and j #> '{sai,chaves,emails}' = '["zz.160403.sai1@exemplo.invalid"]'::jsonb
  and j #> '{entra,chaves,emails}' = '["zz.160403.entra@exemplo.invalid"]'::jsonb
  and j #>> '{entra,socio_novo}' = 'false',
  'titular=' || (j #> '{titular,escrever}')::text || ' | sai/entra casam pelo e-mail de cada um | socio_novo=' || (j #>> '{entra,socio_novo}'))
  from (select pg_temp.ped('p2') j) x;
select pg_temp.ok('6.troca_removidos', j -> 'removidos' = jsonb_build_object(
     'Data da saída', (select d from _dia),
     'Motivo', 'Troca de sócio: saiu como sócio de ZZ Ensaio 160403 Titular Um (pedido nº ' || pg_temp.n('p2') || ')',
     'Transação de origem', 'PEDIDO-ALTERACAO-' || pg_temp.n('p2'), 'Valor', '',
     'Tinha acesso antigo?', 'ver caso de Remoção de Acessos',
     'Quem determinou', 'Pedido nº ' || pg_temp.n('p2') || ', aprovado por Victor Hugo, ' || (select d from _dia)),
  (j -> 'removidos')::text) from (select pg_temp.ped('p2') j) x;
select pg_temp.ok('6.troca_com_linha', j -> 'se_entra_com_linha' = jsonb_build_object('acao', 'apagar a linha de quem sai',
     'escrever', jsonb_build_object('Instrução', (select valor_aplicado ->> 'instrucao' from public.pa_pedidos where id = pg_temp.n('p2')),
        'Regra de acesso', 'Acompanha titular', 'Data de expiração', '31/03/2027', 'Status do acesso', 'Acompanha titular',
        'Sócio de (titular)', 'ZZ Ensaio 160403 Titular Um'),
     'copiar_do_titular', '[]'::jsonb),
  (j -> 'se_entra_com_linha')::text) from (select pg_temp.ped('p2') j) x;

-- 7. Troca com pessoa nova (titular 2 sem turma e sem entrada no THB: vêm da linha do titular na planilha)
select pg_temp.ok('7.troca_pessoa_nova',
  j #>> '{entra,socio_novo}' = 'true' and j #> '{entra,chaves,emails}' = '["zz.160403.novo@exemplo.invalid"]'::jsonb
  and j #> '{entra,chaves,documentos}' = '["48462188058"]'::jsonb
  and j #> '{se_entra_sem_linha,escrever}' = jsonb_build_object(
     'Nome', 'ZZ Ensaio 160403 Novo', 'Documento', '48462188058', 'Email', 'zz.160403.novo@exemplo.invalid',
     'Telefone', (select telefone from public.thb_alunos where email = 'zz.160403.novo@exemplo.invalid'),
     'CEP', (select cep from public.thb_alunos where email = 'zz.160403.novo@exemplo.invalid'),
     'Cidade', 'Rio de Janeiro', 'Estado', 'RJ', 'Bairro', 'Centro', 'País', 'Brasil', 'Endereço', 'Av. Ensaio', 'Número', '1',
     'Complemento', '', 'Profissão', 'Contadora', 'Instrução', 'AURUM - SÓCIO', 'Data de expiração', '31/12/2026',
     'Oferta', '(convite/cadastro manual)', 'Tipo de oferta', 'Sócio', 'Regra de acesso', 'Acompanha titular',
     'Status do acesso', 'Acompanha titular', 'Origem do acesso', 'Sócio/Convite', 'Canal de aquisição', 'Sócio',
     'Tipo de entrada', 'Sócio', 'Origem do canal (como foi atribuído)', 'É sócio — acompanha o titular',
     'Sócio de (titular)', 'ZZ Ensaio 160403 Titular Dois')
  and j #> '{se_entra_sem_linha,copiar_do_titular}' = '["Produto", "Turma Aurum", "Nível", "Turma", "Data de entrada no THB"]'::jsonb
  and j #>> '{se_entra_sem_linha,limpar_demais}' = 'true'
  and j #> '{titular,escrever}' = '{"Sócio": "ZZ Ensaio 160403 Novo", "Nº de sócios": "1"}'::jsonb,
  'sem linha: ' || jsonb_array_length(jsonb_path_query_array(j #> '{se_entra_sem_linha,escrever}', '$.keyvalue()'))
  || ' colunas a escrever; copiar do titular=' || (j #> '{se_entra_sem_linha,copiar_do_titular}')::text
  || '; Instrução=' || (j #>> '{se_entra_sem_linha,escrever,Instrução}') || '; titular=' || (j #> '{titular,escrever}')::text)
  from (select pg_temp.ped('p3') j) x;

-- 8. Sem coluna, turma e nome
select pg_temp.ok('8.sem_coluna', j -> 'escrever' = '{}'::jsonb and (j ->> 'sem_coluna')::boolean
  and j ->> 'detalhe' = 'Telefone profissional não tem coluna na Central: nada a escrever.',
  j ->> 'detalhe') from (select pg_temp.ped('p4') j) x;
select pg_temp.ok('8.turma', j -> 'escrever' = '{"Turma": "T41"}'::jsonb and j -> 'esperado_antes' = '{"Turma": "A10"}'::jsonb,
  'escrever=' || (j -> 'escrever')::text || ' antes=' || (j -> 'esperado_antes')::text) from (select pg_temp.ped('p5') j) x;
select pg_temp.ok('8.nome', j -> 'escrever' = '{"Nome": "ZZ Ensaio 160403 Aluno A Renomeado"}'::jsonb
  and j -> 'esperado_antes' = '{"Nome": "ZZ Ensaio 160403 Aluno A"}'::jsonb,
  'escrever=' || (j -> 'escrever')::text) from (select pg_temp.ped('p6') j) x;

-- 9. Todo cabeçalho que o banco manda escrever ou copiar existe na lista conferida (strings exatas da linha 1)
select pg_temp.ok('9.cabecalhos', not exists (
  select 1 from _r r, jsonb_array_elements(r.v -> 'pedidos') p,
       lateral (select jsonb_object_keys(coalesce(p -> 'escrever', '{}')) union all
                select jsonb_object_keys(coalesce(p #> '{titular,escrever}', '{}')) union all
                select jsonb_object_keys(coalesce(p #> '{se_entra_sem_linha,escrever}', '{}')) union all
                select jsonb_object_keys(coalesce(p #> '{se_entra_com_linha,escrever}', '{}')) union all
                select jsonb_array_elements_text(coalesce(p #> '{se_entra_sem_linha,copiar_do_titular}', '[]')) union all
                select jsonb_array_elements_text(coalesce(p #> '{se_entra_com_linha,copiar_do_titular}', '[]')) union all
                select value from jsonb_each_text(coalesce(p -> 'copiar_para_removidos', '{}'))) c(h)
   where r.k in ('r1', 'r2') and not (r.v #> '{cabecalhos,Central de Acessos 2026}') ? c.h)
  and not exists (
  select 1 from _r r, jsonb_array_elements(r.v -> 'pedidos') p,
       lateral (select jsonb_object_keys(coalesce(p -> 'removidos', '{}')) union all
                select jsonb_object_keys(coalesce(p -> 'copiar_para_removidos', '{}'))) c(h)
   where r.k = 'r1' and not (r.v #> '{cabecalhos,Removidos — Histórico}') ? c.h),
  'escrever/copiar ⊂ cabeçalhos de "Central de Acessos 2026" e "Removidos — Histórico"');

-- 10. Reserva vencida volta; confirmar ok / erro; sem reserva não confirma
update public.pa_planilha_reservas set reservado_em = now() - interval '11 minutes' where pedido_id = pg_temp.n('p1');
select pg_temp.ok('10.reserva_vencida', pg_temp.ids(v) = pg_temp.n('p1')::text, 'depois de 11 min sem resposta: [' || pg_temp.ids(v) || ']')
  from (select pg_temp.reservar() v) x;
insert into _r values ('c1', pg_temp.anon(format('select public.pa_planilha_confirmar(%L, %s, true, null, ''{"linha": 812}'')::jsonb',
  pg_temp.seg(), pg_temp.n('p1'))));
insert into _r values ('c2', pg_temp.anon(format('select public.pa_planilha_confirmar(%L, %s, false, ''2 linhas com o e-mail'')::jsonb',
  pg_temp.seg(), pg_temp.n('p2'))));
insert into _r values ('c1b', pg_temp.anon(format('select public.pa_planilha_confirmar(%L, %s, true)::jsonb', pg_temp.seg(), pg_temp.n('p1'))));
insert into _r values ('c9', pg_temp.anon(format('select public.pa_planilha_confirmar(%L, 9, true)::jsonb', pg_temp.seg())));
select pg_temp.ok('10.confirmar_ok', (select v from _r where k = 'c1') = '{"ok": true}'::jsonb
  and x.planilha_status = 'ok' and x.planilha_em is not null and x.planilha_erro is null
  and not exists (select 1 from public.pa_planilha_reservas where pedido_id = x.id)
  and (select detalhe from public.pa_historico where pedido_id = x.id and acao = 'planilha_ok') = '{"linha": 812}'::jsonb,
  'p1 -> planilha_status=' || x.planilha_status || ', reserva apagada, pa_historico planilha_ok')
  from public.pa_pedidos x where x.id = pg_temp.n('p1');
select pg_temp.ok('10.confirmar_erro', (select v from _r where k = 'c2') = '{"ok": true}'::jsonb
  and x.planilha_status = 'erro' and x.planilha_erro = '2 linhas com o e-mail'
  and (select detalhe ->> 'erro' from public.pa_historico where pedido_id = x.id and acao = 'planilha_erro') = '2 linhas com o e-mail',
  'p2 -> planilha_status=' || x.planilha_status || ' planilha_erro=' || coalesce(x.planilha_erro, 'nulo'))
  from public.pa_pedidos x where x.id = pg_temp.n('p2');
select pg_temp.ok('10.nao_confirma_duas_vezes', (select v ->> 'ok' from _r where k = 'c1b') = 'false'
  and (select v ->> 'ok' from _r where k = 'c9') = 'false'
  and (select planilha_status from public.pa_pedidos where id = 9) is null,
  'p1 de novo -> ' || (select v::text from _r where k = 'c1b') || ' | nº 9 sem reserva -> ' || (select v::text from _r where k = 'c9'));

-- 11. Grants e tabela fechada
select pg_temp.ok('11.grants',
  has_function_privilege('anon', 'public.pa_planilha_reservar(text)', 'execute')
  and has_function_privilege('anon', 'public.pa_planilha_confirmar(text,bigint,boolean,text,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.pa_planilha_pedido(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.pa_planilha_pedido(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.pa_planilha_chaves(uuid,text[],text[])', 'execute')
  and not has_function_privilege('anon', 'public.pa_planilha_cabecalhos()', 'execute')
  and not has_function_privilege('anon', 'public.pa_planilha_cel(text)', 'execute'),
  'reservar/confirmar: anon e authenticated; auxiliares fechadas');
select pg_temp.ok('11.reservas_fechada', v ->> 'estado' = '42501', 'anon lendo pa_planilha_reservas -> ' || coalesce(v ->> 'erro', v::text))
  from (select pg_temp.anon('select to_jsonb(r) from public.pa_planilha_reservas r limit 1') v) x;
select pg_temp.ok('11.pedido_direto_negado', v ->> 'estado' = '42501', 'anon chamando pa_planilha_pedido -> ' || coalesce(v ->> 'erro', v::text))
  from (select pg_temp.anon(format('select public.pa_planilha_pedido(%s)', pg_temp.n('p3'))) v) x;

-- 12. Plano da seleção da reserva
select pg_temp.plano('12.explain_reserva', $q$
select x.id from public.pa_pedidos x
 where x.status = 'aplicado' and x.planilha_status = 'pendente' and x.tipo in ('alterar_dado', 'trocar_socio')
   and not exists (select 1 from public.pa_planilha_reservas pr
                    where pr.pedido_id = x.id and pr.reservado_em >= now() - interval '10 minutes')
 order by x.id limit 5 for update of x skip locked $q$);

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
