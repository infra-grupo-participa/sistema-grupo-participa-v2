-- 20261008200000: foto da lista de participantes do grupo do SendFlow como fonte do ingresso no grupo (dashboard ATM)
--
-- STATUS: ver 20261008200000.explain.md. Depende de 20261008161000 e 20261008191000 (aplicadas).
-- Ensaio: 20261008200000_ensaio.sql. Reversão: 20261008200000_reversao.sql. Contrato: docs/dashboard-atm/MODELO-DE-DADOS.md.
--
-- POR QUE (pedido do Victor, 08/10/2026 16h20; diagnóstico do Maestro)
--   O card de ingresso mostrava 7 e o grupo real tinha ~50. O próprio SendFlow só registra entrada (e manda pelo
--   SendHook) para uma parte de quem entra: /analytics da campanha tem 20 entradas no total. A lista de participantes
--   (POST /actions/export-leads) é completa: 67 linhas, 50 números no grupo, 2 saíram (08/10).
--   Então a fonte do ingresso passa a ser a FOTO da lista, somada aos eventos do webhook.
--
-- O QUE FAZ
--   a. dados.dashboard_grupos: sendflow_release_id (id da campanha na API) e sendflow_conta_id (conta de WhatsApp que
--      exporta; com outra conta a lista vem vazia). ATM 1: release dQq8AKicYQPUZHwp6eZp, conta "Disparo 1"
--      RoWnnm8HUTDZjBITqAFG.
--   b. dados.grupo_fotos: cada execução (exportar -> baixar CSV -> feito | erro), com hora, linhas e números no grupo.
--   c. dados.grupo_participantes: um número por grupo cadastrado: fone_key, nome (do WhatsApp), grupos, no_grupo,
--      visto_primeiro_em, visto_ultimo_em, saiu_em. Saída = "Saiu = Sim" no CSV ou sumiu da foto.
--   d. dados.grupo_foto_processar(foto, csv): lê o CSV (Posição;Grupo;Nome;Número;Saiu) e atualiza os participantes.
--   e. dados.grupo_foto_ciclo(): máquina de estados chamada pelo pg_cron a cada 2 min; abre uma foto nova por grupo a
--      cada 10 min. Chave da API no Vault (segredo sendflow_api_key, chave do Victor), nunca no código. HTTP pelo pg_net.
--   f. dados.v_grupo_pessoas_todos (nova): uma linha por número, juntando eventos do webhook e foto, com teste.
--      Entrada = evento de entrada do webhook; sem evento, 1ª vez visto na foto (entrada_aproximada = true).
--      No grupo / saída: a foto manda quando existe. dados.v_grupo_pessoas = ela sem teste (+ coluna
--      entrada_aproximada no fim). Toda RPC do ATM já lê v_grupo_pessoas: card, série, leads, comparecimento e pós-live
--      passam a contar a foto sem mudança nelas.
--   g. dados_atm_resumo ganha no fim grupo_entradas_aproximadas, grupo_foto_em e grupo_no_grupo (no grupo agora); dados_atm_grupo_numeros ganha
--      entrada_aproximada e grupos; dados.atm_pertence aceita número que só está na foto.
--   h. pg_cron: job dados-grupo-foto, '*/2 * * * *', com statement_timeout de 60 s.
--   SEGURANÇA (pentester 08/10): o POST sai por ops.cron_post (o vigia ops.vigiar rastreia o status); a URL do CSV só
--   é seguida se for do Firebase Storage; o conteúdo das respostas sai de net._http_response logo depois de lido
--   (anon/authenticated têm SELECT em net.*, embora o schema net não esteja exposto no PostgREST); a coluna erro
--   guarda só status e error_msg; CSV acima de 5 MB é recusado; nome e grupos com teto de tamanho.
--
-- AS 5 PERGUNTAS
--   escala: ~100 linhas de CSV por foto; 144 fotos por dia por grupo; participantes ~1 mil por ATM.
--   índice: único (grupo_id, fone8) em participantes; (grupo_id, iniciado_em) em fotos.
--   frequência: job a cada 2 min (barato: só olha fotos abertas); 1 export no SendFlow a cada 10 min por grupo.
--   repetição: foto nova só se não houver aberta e a última começou há 9 min ou mais.
--   reversão: 20261008200000_reversao.sql (tira o job, volta views e RPCs ao corpo de 20261008191000).
--
-- IDEMPOTENTE: if not exists / create or replace / cron.schedule com nome (substitui).

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
begin
  if to_regclass('dados.marcacoes_teste') is null or to_regprocedure('dados.atm_pertence(text,text,text)') is null then
    raise exception 'premissa: 20261008191000 não aplicada';
  end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
     or to_regprocedure('net.http_get(text,jsonb,jsonb,integer)') is null
     or to_regprocedure('cron.schedule(text,text,text)') is null
     or to_regprocedure('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)') is null then
    raise exception 'premissa: pg_net ou pg_cron ausente';
  end if;
end
$g$;

-- a. Campanha na API
alter table dados.dashboard_grupos add column if not exists sendflow_release_id text
  check (sendflow_release_id is null or sendflow_release_id ~ '^[A-Za-z0-9]{10,40}$');
alter table dados.dashboard_grupos add column if not exists sendflow_conta_id text
  check (sendflow_conta_id is null or sendflow_conta_id ~ '^[A-Za-z0-9]{10,40}$');
comment on column dados.dashboard_grupos.sendflow_release_id is
  'Id da campanha (release) na API do SendFlow. Com ele, dados.grupo_foto_ciclo tira a foto dos participantes. 20261008200000.';
comment on column dados.dashboard_grupos.sendflow_conta_id is
  'Conta de WhatsApp do SendFlow usada no export-leads (outra conta devolve lista vazia). 20261008200000.';

update dados.dashboard_grupos
   set sendflow_release_id = 'dQq8AKicYQPUZHwp6eZp', sendflow_conta_id = 'RoWnnm8HUTDZjBITqAFG'
 where chave = 'atm-elaine-1-2026-10' and sendflow_campanha = 'ATM 10/26' and sendflow_release_id is null;

-- b. Fotos
create table if not exists dados.grupo_fotos (
  id                bigint generated always as identity primary key,
  grupo_id          uuid not null references dados.dashboard_grupos(id) on delete restrict,
  etapa             text not null default 'exportar' check (etapa in ('exportar', 'baixar', 'feito', 'erro')),
  req_exportar      bigint,
  req_baixar        bigint,
  iniciado_em       timestamptz not null default now(),
  concluido_em      timestamptz,
  linhas            integer,
  numeros_no_grupo  integer,
  numeros_sairam    integer,
  erro              text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
comment on table dados.grupo_fotos is
  'Execuções da foto da lista de participantes do SendFlow (export-leads). Etapas: exportar -> baixar -> feito | erro. 20261008200000.';
create index if not exists grupo_fotos_grupo_idx on dados.grupo_fotos (grupo_id, iniciado_em desc);
create index if not exists grupo_fotos_abertas_idx on dados.grupo_fotos (etapa) where etapa in ('exportar', 'baixar');
alter table dados.grupo_fotos enable row level security;
revoke all on dados.grupo_fotos from public, anon, authenticated;
drop trigger if exists grupo_fotos_carimbar on dados.grupo_fotos;
create trigger grupo_fotos_carimbar before update on dados.grupo_fotos
  for each row execute function public.tg_carimbar_atualizado_em();

-- c. Participantes
create table if not exists dados.grupo_participantes (
  id                 bigint generated always as identity primary key,
  grupo_id           uuid not null references dados.dashboard_grupos(id) on delete restrict,
  fone8              text not null check (fone8 ~ '^[0-9]{8}$'),
  fone_key           text check (fone_key is null or fone_key ~ '^[0-9]{10}$'),
  nome               text,
  grupos             text,
  no_grupo           boolean not null,
  visto_primeiro_em  timestamptz not null,
  visto_ultimo_em    timestamptz,
  saiu_em            timestamptz,
  primeira_foto_id   bigint references dados.grupo_fotos(id) on delete restrict,
  ultima_foto_id     bigint references dados.grupo_fotos(id) on delete restrict,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  unique (grupo_id, fone8)
);
comment on table dados.grupo_participantes is
  'Participantes do grupo vistos nas fotos do SendFlow. visto_primeiro_em = 1ª foto em que apareceu (entrada aproximada quando não há evento do webhook); visto_ultimo_em = última foto em que estava no grupo; saiu_em = 1ª foto em que apareceu como "Saiu = Sim" ou sumiu; nulo enquanto está no grupo. 20261008200000.';
create index if not exists grupo_participantes_primeira_foto_idx on dados.grupo_participantes (primeira_foto_id);
create index if not exists grupo_participantes_ultima_foto_idx on dados.grupo_participantes (ultima_foto_id);
alter table dados.grupo_participantes enable row level security;
revoke all on dados.grupo_participantes from public, anon, authenticated;
drop trigger if exists grupo_participantes_carimbar on dados.grupo_participantes;
create trigger grupo_participantes_carimbar before update on dados.grupo_participantes
  for each row execute function public.tg_carimbar_atualizado_em();

-- d. Processar um CSV
create or replace function dados.grupo_foto_processar(p_foto_id bigint, p_csv text)
returns integer language plpgsql volatile set search_path = '' as $$
-- 20261008200000: CSV "Posição;Grupo;Nome;Número;Saiu" (o nome pode ter ';': nome = campos do meio).
-- As linhas de dado vêm com ';' no fim e CRLF (o cabeçalho não): tira os dois antes de separar.
-- Devolve quantos números estão no grupo nesta foto. Aborta (sem mexer em nada) se o cabeçalho não bater.
declare
  f dados.grupo_fotos;
  v_agora timestamptz := now();
  v_cab text;
  v_linhas int;
  v_no int;
  v_sairam int;
begin
  select * into f from dados.grupo_fotos where id = p_foto_id;
  if not found then
    raise exception 'foto % não existe', p_foto_id;
  end if;
  if length(coalesce(p_csv, '')) > 5000000 then
    raise exception 'CSV do SendFlow acima de 5 MB (% caracteres)', length(p_csv);
  end if;
  v_cab := split_part(replace(replace(coalesce(p_csv, ''), chr(65279), ''), chr(13), ''), chr(10), 1);
  if v_cab <> 'Posição;Grupo;Nome;Número;Saiu' then
    -- sem o conteúdo da linha na mensagem (pode ser um participante): só tamanho e md5
    raise exception 'cabeçalho inesperado no CSV do SendFlow (% caracteres, md5 %)', length(v_cab), md5(v_cab);
  end if;

  create temp table if not exists pg_temp._foto (fone8 text, fone_key text, nome text, grupo text, no_grupo boolean) on commit drop;
  truncate pg_temp._foto;
  insert into pg_temp._foto (fone8, fone_key, nome, grupo, no_grupo)
  select right(controle.fone_key(a[array_length(a, 1) - 1]), 8),
         controle.fone_key(a[array_length(a, 1) - 1]),
         left(nullif(btrim(array_to_string(a[3:array_length(a, 1) - 2], ';')), ''), 200),
         left(nullif(btrim(a[2]), ''), 100),
         lower(btrim(a[array_length(a, 1)])) <> 'sim'
    from (select string_to_array(regexp_replace(l, ';\s*$', ''), ';') as a
            from unnest(string_to_array(replace(replace(p_csv, chr(65279), ''), chr(13), ''), chr(10))) with ordinality as t(l, n)
           where t.n > 1 and btrim(t.l) <> '') x
   where array_length(a, 1) >= 5 and controle.fone_key(a[array_length(a, 1) - 1]) is not null;
  get diagnostics v_linhas = row_count;

  with agg as (
    select fone8, max(fone_key) as fone_key,
           (array_agg(nome order by no_grupo desc) filter (where nome is not null))[1] as nome,
           left(string_agg(distinct grupo, ', ' order by grupo) filter (where no_grupo), 500) as grupos,
           bool_or(no_grupo) as no_grupo
      from pg_temp._foto group by fone8
  )
  insert into dados.grupo_participantes as p (grupo_id, fone8, fone_key, nome, grupos, no_grupo, visto_primeiro_em,
                                              visto_ultimo_em, saiu_em, primeira_foto_id, ultima_foto_id)
  select f.grupo_id, a.fone8, a.fone_key, a.nome, a.grupos, a.no_grupo, v_agora,
         case when a.no_grupo then v_agora end, case when not a.no_grupo then v_agora end, f.id, f.id
    from agg a
  on conflict (grupo_id, fone8) do update
     set fone_key        = coalesce(excluded.fone_key, p.fone_key),
         nome            = coalesce(excluded.nome, p.nome),
         grupos          = coalesce(excluded.grupos, p.grupos),
         no_grupo        = excluded.no_grupo,
         visto_ultimo_em = case when excluded.no_grupo then v_agora else p.visto_ultimo_em end,
         saiu_em         = case when excluded.no_grupo then null
                                when p.no_grupo then v_agora
                                else coalesce(p.saiu_em, v_agora) end,
         ultima_foto_id  = f.id;

  -- quem estava no grupo e sumiu da foto: saiu agora
  update dados.grupo_participantes p
     set no_grupo = false, saiu_em = v_agora, ultima_foto_id = f.id
   where p.grupo_id = f.grupo_id and p.no_grupo
     and not exists (select 1 from pg_temp._foto x where x.fone8 = p.fone8);

  select count(*) filter (where no_grupo), count(*) filter (where not no_grupo) into v_no, v_sairam
    from dados.grupo_participantes where grupo_id = f.grupo_id;
  update dados.grupo_fotos
     set etapa = 'feito', concluido_em = v_agora, linhas = v_linhas, numeros_no_grupo = v_no, numeros_sairam = v_sairam,
         erro = null
   where id = f.id;
  return v_no;
end
$$;

-- e. Ciclo (pg_cron a cada 2 min)
create or replace function dados.grupo_foto_ciclo()
returns text language plpgsql volatile set search_path = '' as $$
-- 20261008200000: exportar -> baixar -> processar; uma foto nova por grupo a cada 10 min (9 de folga para o cron)
declare
  r record;
  v_chave_api text;
  v_resp record;
  v_url text;
  v_feitas int := 0; v_abertas int := 0; v_erros int := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('dados.grupo_foto_ciclo')) then
    return 'outro ciclo em andamento';
  end if;
  -- foto parada há mais de 15 min: erro
  update dados.grupo_fotos set etapa = 'erro', concluido_em = now(), erro = 'sem resposta em 15 min'
   where etapa in ('exportar', 'baixar') and iniciado_em < now() - interval '15 minutes';
  get diagnostics v_erros = row_count;

  -- resposta que chegou depois de a foto fechar (erro por tempo): o conteúdo também sai de net._http_response
  update net._http_response h set content = null
    from dados.grupo_fotos f
   where f.etapa in ('erro', 'feito') and f.iniciado_em > now() - interval '7 hours'
     and h.id in (f.req_exportar, f.req_baixar) and h.created >= f.iniciado_em and h.content is not null;

  -- exportar respondido: pega a URL do CSV e baixa
  for r in select f.* from dados.grupo_fotos f where f.etapa = 'exportar' and f.req_exportar is not null loop
    select h.status_code, h.content, h.timed_out, h.error_msg into v_resp
      from net._http_response h where h.id = r.req_exportar and h.created >= r.iniciado_em;
    continue when not found;
    begin
      v_url := case when v_resp.status_code = 200 and length(v_resp.content) < 10000 then (v_resp.content::jsonb ->> 'url') end;
    exception when others then v_url := null;
    end;
    -- a resposta traz a URL assinada do CSV: apaga o conteúdo e mantém o status (o vigia ops.vigiar lê o status)
    update net._http_response h set content = null where h.id = r.req_exportar;
    -- só o Storage do Firebase (barra depois do host: barra https://host@outro)
    if v_url is null or v_url !~ '^https://firebasestorage\.googleapis\.com/v0/b/[A-Za-z0-9._-]+/o/[^@\s]+$' then
      update dados.grupo_fotos set etapa = 'erro', concluido_em = now(),
             erro = 'export-leads: http ' || coalesce(v_resp.status_code::text, '?')
                    || case when v_resp.timed_out then ' timeout' else '' end
                    || coalesce(' ' || left(v_resp.error_msg, 200), '')
                    || case when v_resp.status_code = 200 then ' (sem URL do Storage na resposta)' else '' end
       where id = r.id;
      v_erros := v_erros + 1;
    else
      update dados.grupo_fotos set etapa = 'baixar',
             req_baixar = net.http_get(url := v_url, params := '{}'::jsonb, headers := '{}'::jsonb, timeout_milliseconds := 60000)
       where id = r.id;
    end if;
  end loop;

  -- CSV baixado: processa
  for r in select f.* from dados.grupo_fotos f where f.etapa = 'baixar' and f.req_baixar is not null loop
    select h.status_code, h.content, h.timed_out, h.error_msg into v_resp
      from net._http_response h where h.id = r.req_baixar and h.created >= r.iniciado_em;
    continue when not found;
    -- o CSV tem telefone e nome de todo o grupo: sai de net._http_response assim que é lido
    delete from net._http_response h where h.id = r.req_baixar;
    if v_resp.status_code = 200 then
      begin
        perform dados.grupo_foto_processar(r.id, v_resp.content);
        v_feitas := v_feitas + 1;
      exception when others then
        update dados.grupo_fotos set etapa = 'erro', concluido_em = now(), erro = 'processar: ' || left(sqlerrm, 200)
         where id = r.id;
        v_erros := v_erros + 1;
      end;
    else
      update dados.grupo_fotos set etapa = 'erro', concluido_em = now(),
             erro = 'csv: http ' || coalesce(v_resp.status_code::text, '?')
                    || case when v_resp.timed_out then ' timeout' else '' end
                    || coalesce(' ' || left(v_resp.error_msg, 200), '')
       where id = r.id;
      v_erros := v_erros + 1;
    end if;
  end loop;

  -- foto nova
  select s.decrypted_secret into v_chave_api from vault.decrypted_secrets s where s.name = 'sendflow_api_key';
  if v_chave_api is null then
    return format('feitas %s, erros %s; sem segredo sendflow_api_key no Vault: nenhuma foto nova', v_feitas, v_erros);
  end if;
  for r in
    select g.* from dados.dashboard_grupos g join dados.dashboards d on d.chave = g.chave
     where d.ativo and g.sendflow_release_id is not null
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.etapa in ('exportar', 'baixar'))
       and not exists (select 1 from dados.grupo_fotos f where f.grupo_id = g.id and f.iniciado_em > now() - interval '9 minutes')
  loop
    insert into dados.grupo_fotos (grupo_id, req_exportar)
    values (r.id, ops.cron_post('dados-grupo-foto',
      url := 'https://sendflow.pro/sendapi/actions/export-leads',
      body := jsonb_strip_nulls(jsonb_build_object('releaseId', r.sendflow_release_id, 'includeLeft', true,
                                                   'accountId', r.sendflow_conta_id)),
      params := '{}'::jsonb,
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_chave_api, 'Content-Type', 'application/json'),
      timeout_milliseconds := 60000));
    v_abertas := v_abertas + 1;
  end loop;
  return format('feitas %s, abertas %s, erros %s', v_feitas, v_abertas, v_erros);
end
$$;

revoke all on function dados.grupo_foto_processar(bigint, text), dados.grupo_foto_ciclo() from public, anon, authenticated;

-- f. Pessoas do grupo: eventos + foto
create or replace view dados.v_grupo_pessoas_todos with (security_invoker = true) as
  with ev as (
    select e.chave, e.fone8,
           (array_agg(e.fone_key order by e.ocorreu_em desc, e.evento_id desc))[1] as fone_key,
           (array_agg(e.nome order by e.ocorreu_em desc) filter (where e.nome is not null))[1] as nome,
           min(e.ocorreu_em) filter (where e.tipo = 'entrada') as entrou_em,
           max(e.ocorreu_em) filter (where e.tipo = 'entrada') as ultima_entrada,
           max(e.ocorreu_em) filter (where e.tipo = 'saida') as saiu_em,
           (array_agg(e.tipo order by e.ocorreu_em desc, e.evento_id desc))[1] = 'entrada' as no_grupo,
           (array_agg(e.pessoa_id order by e.ocorreu_em desc) filter (where e.pessoa_id is not null))[1] as pessoa_id
      from dados.v_grupo_eventos_todos e
     group by e.chave, e.fone8
  ),
  fo as (
    select g.chave, p.fone8, max(p.fone_key) as fone_key, max(p.nome) as nome,
           string_agg(p.grupos, ', ') as grupos, bool_or(p.no_grupo) as no_grupo,
           min(p.visto_primeiro_em) as visto_primeiro_em,
           max(p.saiu_em) as saiu_em
      from dados.grupo_participantes p
      join dados.dashboard_grupos g on g.id = p.grupo_id
     group by g.chave, p.fone8
  ),
  j as (
    select coalesce(ev.chave, fo.chave) as chave, coalesce(ev.fone8, fo.fone8) as fone8,
           coalesce(ev.fone_key, fo.fone_key) as fone_key, coalesce(fo.nome, ev.nome) as nome, fo.grupos,
           -- sem evento de entrada: 1ª foto, ou a saída do webhook se foi antes (entrou antes de sair)
           coalesce(ev.entrou_em, case when fo.fone8 is not null then least(fo.visto_primeiro_em, ev.saiu_em) end) as entrou_em,
           ev.entrou_em is null and fo.visto_primeiro_em is not null as entrada_aproximada,
           -- saída: sem foto, a do webhook; com foto e no grupo, nenhuma; com foto e fora, a do webhook se for depois da
           -- última entrada (hora exata), senão a hora da foto que viu a saída (aproximada)
           case when fo.fone8 is null then ev.saiu_em
                when fo.no_grupo then null
                when ev.saiu_em >= coalesce(ev.ultima_entrada, '-infinity'::timestamptz) then ev.saiu_em
                else fo.saiu_em end as saiu_em,
           coalesce(fo.no_grupo, ev.no_grupo) as no_grupo,
           ev.pessoa_id,
           fo.fone8 is not null as na_foto
      from ev full join fo on fo.chave = ev.chave and fo.fone8 = ev.fone8
  )
  select j.chave, j.fone8, j.fone_key, j.nome, j.grupos, j.entrou_em, j.entrada_aproximada,
         case when j.saiu_em >= j.entrou_em then j.saiu_em end as saiu_em,
         j.no_grupo, j.pessoa_id, j.na_foto,
         exists (select 1 from dados.marcacoes_teste m
                  where m.chave = j.chave and m.desmarcado_em is null and m.tipo = 'fone' and m.valor = j.fone8) as teste
    from j;
comment on view dados.v_grupo_pessoas_todos is
  'Um número por dashboard: eventos do webhook do SendFlow + foto da lista de participantes, com a marcação de teste. Entrada = evento; sem evento, 1ª vez visto na foto (entrada_aproximada). A foto manda em no_grupo/saída quando existe. 20261008200000.';

create or replace view dados.v_grupo_pessoas with (security_invoker = true) as
  select t.chave, t.fone8, t.entrou_em, t.saiu_em, t.no_grupo, t.pessoa_id, t.entrada_aproximada
    from dados.v_grupo_pessoas_todos t
   where not t.teste;
comment on view dados.v_grupo_pessoas is
  'Pessoas do grupo do dashboard (eventos + foto do SendFlow), sem teste. 20261008161000; foto e entrada_aproximada em 20261008200000.';
revoke all on dados.v_grupo_pessoas_todos, dados.v_grupo_pessoas from public, anon, authenticated;

-- g. Quem só está na foto também pode ser marcado
create or replace function dados.atm_pertence(p_chave text, p_tipo text, p_valor text)
returns boolean language sql stable set search_path = '' as $$
  -- 20261008191000; número da foto do grupo em 20261008200000
  select case p_tipo
    when 'email' then
         exists (select 1 from dados.atm_leads(p_chave) l where l.email = p_valor)
      or exists (select 1 from dados.dashboards d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
                  where d.chave = p_chave and lower(btrim(y.email)) = p_valor)
      or exists (select 1 from dados.atm_vendas_todas(p_chave) v where lower(btrim(v.email)) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and pr.email_norm = p_valor)
    when 'fone' then
         exists (select 1 from dados.v_grupo_pessoas_todos e where e.chave = p_chave and e.fone8 = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where right(controle.fone_key(l.telefone), 8) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and right(pr.fone_key, 8) = p_valor)
    else false end
$$;
revoke all on function dados.atm_pertence(text, text, text) from public, anon, authenticated;

-- g2. Leituras que contam saída: saída vista na mesma foto da 1ª aparição conta (>=)
create or replace function dados.atm_leads(p_chave text)
returns table(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text,
              utm_medium text, utm_campaign text, utm_content text, utm_term text, ddd text, estado text,
              entrou_grupo boolean, saiu_grupo boolean, eh_aluno boolean, instrucao text, turma text,
              lista_origem text, seminario_origem text, no_pre_checkout boolean, comprou boolean, pessoa_id uuid,
              teste boolean)
language sql stable set search_path = '' as $$
  -- 20261008161000; teste marcado no evento em 20261008191000; saída da foto (>=) em 20261008200000
  with d as (select * from dados.dashboards where chave = p_chave),
  l as (
    select t.*, controle.fone_key(t.telefone) as fk
      from d cross join lateral dados.leads_todos(d.chave, d.projeto_id, d.lista_ac_leads) t
  ),
  tem as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = p_chave) as grupo,
           exists (select 1 from dados.lista_membros m where m.chave = p_chave) as listas
  ),
  pc as (select y.email from d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y),
  vd as (select distinct v.email from dados.atm_vendas(p_chave) v where v.email is not null)
  select l.email, l.nome, l.telefone, l.primeiro_em, l.fonte, l.utm_source, l.utm_medium, l.utm_campaign,
         l.utm_content, l.utm_term,
         left(l.fk, 2),
         case when l.fk is null then null else coalesce((select u.uf from dados.ddd_uf u where u.ddd = left(l.fk, 2)), 'Outros') end,
         case when tem.grupo then coalesce(gp.entrou_em is not null, false) end,
         case when tem.grupo then coalesce(gp.entrou_em is not null and gp.saiu_em >= gp.entrou_em, false) end,
         pf.instrucao is not null, pf.instrucao, pf.turma,
         case when not tem.listas then null
              when lm.l1 and lm.l2 then 'lista_1_e_2'
              when lm.l1 then 'lista_1' when lm.l2 then 'lista_2'
              else 'fora_das_listas' end,
         case when lm.marcio and lm.elaine then 'marcio_e_elaine'
              when lm.marcio then 'marcio' when lm.elaine then 'elaine' end,
         exists (select 1 from pc where pc.email = l.email),
         case when (select oferta_codigo from d) is null then null else exists (select 1 from vd where vd.email = l.email) end,
         l.pessoa_id,
         l.teste or dados.teste_ativo(p_chave, l.email, l.fk)
    from l cross join tem
    left join lateral (select g.entrou_em, g.saiu_em from dados.v_grupo_pessoas g
                        where g.chave = p_chave and g.entrou_em is not null
                          and ((l.fk is not null and g.fone8 = right(l.fk, 8)) or (l.pessoa_id is not null and g.pessoa_id = l.pessoa_id))
                        order by g.entrou_em limit 1) gp on true
    left join lateral (select bool_or(m.lista = 'lista_1') as l1, bool_or(m.lista = 'lista_2') as l2,
                              bool_or(m.seminario_origem in ('marcio', 'marcio_e_elaine')) as marcio,
                              bool_or(m.seminario_origem in ('elaine', 'marcio_e_elaine')) as elaine
                         from dados.lista_membros m
                        where m.chave = p_chave
                          and (m.email_norm = l.email or (l.fk is not null and right(m.fone_key, 8) = right(l.fk, 8)))) lm on true
    left join lateral (select x.instrucao, x.turma from dados.perfil(l.email) x) pf on true
$$;
revoke all on function dados.atm_leads(text) from public, anon, authenticated;

create or replace function public.dados_atm_serie_diaria(p_chave text, p_de date default null, p_ate date default null)
returns table(dia date, leads integer, grupo_entradas integer, grupo_saidas integer, pre_checkout integer, vendas integer,
              receita_bruta numeric, custo_disparo_centavos bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_tem_grupo boolean := exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  if v_de is not null and least(coalesce(v_ate, v_hoje), v_hoje) - v_de > 400 then
    raise exception 'período longo demais para a série (máximo 400 dias)' using errcode = '22023';
  end if;
  return query
  with ld as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_leads(d.chave) x
               where not x.teste and x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ge as (select (g.entrou_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em >= v_ini and g.entrou_em < v_fim),
  gs as (select (g.saiu_em at time zone 'America/Sao_Paulo')::date as dia from dados.v_grupo_pessoas g
          where g.chave = d.chave and g.entrou_em is not null and g.saiu_em >= g.entrou_em
            and g.saiu_em >= v_ini and g.saiu_em < v_fim),
  pc as (select (y.primeiro_em at time zone 'America/Sao_Paulo')::date as dia from dados.atm_pre_checkout(d.chave) y
          where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select v.dia_aprovado as dia, v.valor_bruto, v.moeda
           from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ds as (select (coalesce(x.enviado_em, x.criado_em) at time zone 'America/Sao_Paulo')::date as dia, x.custo_centavos
           from mkt_mensageria.disparos x
          where x.projeto_id = d.projeto_id and x.arquivado_em is null
            and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim),
  lim as (
    select coalesce(v_de, least((select min(dia) from ld), (select min(dia) from ge), (select min(dia) from pc),
                                (select min(dia) from tx), (select min(dia) from ds))) as de,
           least(coalesce(v_ate, v_hoje), v_hoje) as ate
  )
  select s::date,
         (select count(*)::int from ld where ld.dia = s::date),
         case when v_tem_grupo then (select count(*)::int from ge where ge.dia = s::date) end,
         case when v_tem_grupo then (select count(*)::int from gs where gs.dia = s::date) end,
         (select count(*)::int from pc where pc.dia = s::date),
         case when d.oferta_codigo is not null then (select count(*)::int from tx where tx.dia = s::date) end,
         case when d.oferta_codigo is not null then
           (select coalesce(sum(tx.valor_bruto), 0)::numeric(14,2) from tx where tx.dia = s::date and tx.moeda = 'BRL') end,
         (select case when count(*) filter (where ds.custo_centavos is null) = 0 then sum(ds.custo_centavos)::bigint end
            from ds where ds.dia = s::date having count(*) > 0)
    from lim
    cross join lateral generate_series(lim.de, lim.ate, interval '1 day') s
   where lim.de is not null and lim.de <= lim.ate
   order by 1;
end
$$;

drop function if exists public.dados_atm_resumo(text, date, date);
create or replace function public.dados_atm_resumo(p_chave text, p_de date default null, p_ate date default null)
returns table(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text,
              disparos_qtd integer, disparos_enviados integer, leads integer, grupo_tem_fonte boolean,
              grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric,
              custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint,
              pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer,
              compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint,
              receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric,
              atualizado_em timestamp with time zone,
              periodo_de date, periodo_ate date, leads_teste integer, grupo_teste integer, vendas_teste integer,
              receita_teste_bruta numeric, grupo_entradas_aproximadas integer, grupo_foto_em timestamp with time zone,
              grupo_no_grupo integer)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with disp as (
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo, sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
       and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
  ),
  lt as (select * from dados.atm_leads(d.chave) x where x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ld as (select * from lt where not lt.teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim)::int as entradas,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.entrada_aproximada)::int as aprox,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.no_grupo)::int as no_agora,
           (select max(f.concluido_em) from dados.grupo_fotos f join dados.dashboard_grupos dg on dg.id = f.grupo_id
             where dg.chave = d.chave and f.etapa = 'feito') as foto_em,
           count(*) filter (where g.entrou_em is not null and g.saiu_em >= g.entrou_em
                              and g.saiu_em >= v_ini and g.saiu_em < v_fim)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  gt as (
    select count(*)::int as n from dados.v_grupo_pessoas_todos e
     where e.chave = d.chave and e.teste and e.entrou_em >= v_ini and e.entrou_em < v_fim
  ),
  pc as (select y.email from dados.atm_pre_checkout(d.chave) y where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select * from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  txt as (select count(*)::int as n, coalesce(sum(v.valor_bruto) filter (where v.moeda = 'BRL'), 0)::numeric(14,2) as bruta
            from dados.atm_vendas_todas(d.chave) v
           where v.teste and v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ag as (
    select (select count(*)::int from ld) as leads,
           (select count(*)::int from lt where lt.teste) as leads_teste,
           (select count(*)::int from pc) as pc,
           (select count(*)::int from tx) as vendas,
           (select count(*)::int from tx where tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  ),
  k as (select (disp.qtd > 0 and disp.sem = 0) as completo, d.oferta_codigo is not null as tem_oferta from disp)
  select d.chave, pr.id, pr.sigla, pr.nome, d.oferta_codigo,
         disp.qtd, disp.enviados, ag.leads,
         gr.fonte,
         case when gr.fonte then gr.entradas end,
         case when gr.fonte then gr.saidas end,
         case when gr.fonte and ag.leads > 0 then round(gr.entradas::numeric * 100 / ag.leads, 2)::numeric(7,2) end,
         case when gr.fonte and gr.entradas > 0 then round(gr.saidas::numeric * 100 / gr.entradas, 2)::numeric(7,2) end,
         disp.custo, disp.sem, k.completo,
         case when k.completo and ag.leads > 0 then round(disp.custo::numeric / ag.leads)::bigint end,
         ag.pc,
         case when k.tem_oferta then ag.vendas end,
         case when k.tem_oferta then ag.fora end,
         case when k.tem_oferta then ag.comp end,
         case when k.tem_oferta then ag.comp_pc end,
         case when k.tem_oferta and ag.pc > 0 then round(ag.comp::numeric * 100 / ag.pc, 2)::numeric(7,2) end,
         case when k.tem_oferta and k.completo and ag.vendas > 0 then round(disp.custo::numeric / ag.vendas)::bigint end,
         case when k.tem_oferta then ag.bruta end,
         case when k.tem_oferta then ag.liq end,
         case when k.tem_oferta and k.completo and disp.custo > 0 then round(ag.bruta * 100 / disp.custo, 2)::numeric(10,2) end,
         case when k.tem_oferta and k.completo and disp.custo > 0 then round(ag.liq * 100 / disp.custo, 2)::numeric(10,2) end,
         now(),
         v_de, v_ate, ag.leads_teste, case when gr.fonte then gt.n end,
         case when k.tem_oferta then txt.n end, case when k.tem_oferta then txt.bruta end,
         case when gr.fonte then gr.aprox end, gr.foto_em, case when gr.fonte then gr.no_agora end
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join gt cross join txt cross join k
   where pr.id = d.projeto_id;
end
$$;

drop function if exists public.dados_atm_grupo_numeros(text, date, date, boolean);
create or replace function public.dados_atm_grupo_numeros(p_chave text, p_de date default null, p_ate date default null,
                                                          p_incluir_teste boolean default false)
returns table(fone_key text, nome text, entrou_em timestamp with time zone, saiu_em timestamp with time zone,
              no_grupo boolean, eh_lead boolean, teste boolean, teste_motivo text, entrada_aproximada boolean, grupos text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with l as (select right(controle.fone_key(x.telefone), 8) as fk8, x.pessoa_id from dados.atm_leads(d.chave) x)
  select coalesce(p.fone_key, p.fone8), p.nome, p.entrou_em, p.saiu_em, p.no_grupo,
         exists (select 1 from l where l.fk8 = p.fone8 or (p.pessoa_id is not null and l.pessoa_id = p.pessoa_id)),
         p.teste,
         (select m.motivo from dados.marcacoes_teste m
           where m.chave = d.chave and m.desmarcado_em is null and m.tipo = 'fone' and m.valor = p.fone8),
         p.entrada_aproximada, p.grupos
    from dados.v_grupo_pessoas_todos p
   where p.chave = d.chave
     and p.entrou_em >= v_ini and p.entrou_em < v_fim
     and (coalesce(p_incluir_teste, false) or not p.teste)
   order by p.entrou_em desc, p.fone8;
end
$$;

revoke all on function public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                       public.dados_atm_grupo_numeros(text, date, date, boolean)
  from public, anon, service_role;
grant execute on function public.dados_atm_resumo(text, date, date), public.dados_atm_serie_diaria(text, date, date),
                          public.dados_atm_grupo_numeros(text, date, date, boolean)
  to authenticated;

-- h. Agenda
select cron.schedule('dados-grupo-foto', '*/2 * * * *', 'set statement_timeout = ''60s''; select dados.grupo_foto_ciclo()');

-- pós-condição
do $p$
declare f text;
begin
  foreach f in array array['public.dados_atm_resumo(text,date,date)', 'public.dados_atm_serie_diaria(text,date,date)',
                           'public.dados_atm_grupo_numeros(text,date,date,boolean)'] loop
    if not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') then
      raise exception 'pós-condição: grant errado em %', f;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'dados.grupo_participantes', 'select')
     or has_function_privilege('authenticated', 'dados.grupo_foto_ciclo()', 'execute') then
    raise exception 'pós-condição: authenticated alcança a foto do grupo';
  end if;
end
$p$;

notify pgrst, 'reload schema';
