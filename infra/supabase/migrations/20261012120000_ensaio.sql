-- Ensaio de 20261012120000 (transação desfeita: termina em ROLLBACK). NÃO RODADO: o acesso ao banco estava bloqueado na
-- sessão que escreveu este arquivo. Roda como postgres (o mesmo papel da Edge trafego-meta), com dados fictícios
-- (ids ZZENSAIO*, criativos 99000000000000*, sem dado pessoal). Usa a primeira campanha Meta já cadastrada só como pai
-- dos conjuntos de ensaio; nada dela é alterado.
-- ESPERADOS (passo: valor):
--   0 antes md5 desempenho_dia / md5 funções atuais = os mesmos valores no passo 9 (nada existente muda)
--   1 etapa resumo: {"casos": 14, "erradas": 0}
--   2 conjuntos 1a: novos 2, recusas 5 (formato_invalido x2, id_invalido, nome_invalido, campanha_desconhecida)
--   2 conjuntos 2a (mesmo lote): novos 0, atualizados 0, iguais 2
--   2 conjuntos 3a (nome trocado num, status nulo no outro): atualizados 1, iguais 1; status do outro mantido
--   3 anuncios 1a: novos 3, recusas 2 (conjunto_desconhecido, formato_invalido), pendentes [..01, ..02]
--   3 anuncios 2a: novos 0, atualizados 0, iguais 3
--   4 miniatura: gravadas 1, erros 1, recusas 4 (criativo_invalido, caminho_invalido, criativo_desconhecido, formato_invalido)
--   4 pendentes depois da miniatura: []  (01 tem caminho, 02 falhou há menos de 24 h)
--   4 pendentes com a falha de 25 h atrás: [..02]
--   4 criativo trocado: atualizados 1, pendentes [..03], miniatura do AD1 limpa
--   5 desempenho 1a: gravadas 1, recusas 4 (anuncio_desconhecido, formato_invalido, valor_invalido x2)
--   5 desempenho 2a: gravadas 1, linhas do AD1 = 1, gasto 12.35, frequencia 1.2346
--   5 teto do lote: {"ok": false, "msg": "Lista grande demais (máximo 5000 por chamada)."}
--   6 anon/authenticated: 42501 em cada função e cada tabela; service_role: executa as 4 de entrada, 42501 na etapa_black
--   7 config: {"existe": true, "valor": null}; bucket: {"public": false, "limite": 1048576}
--   8 explain: plano da leitura do dashboard e da gravação (colar no .explain.md)
--   9 depois: md5 iguais ao passo 0
--  10 reversão: objetos 0; config 0; bucket: "apagado" ou o sqlstate do bloqueio do Supabase (anotar no .explain.md)
begin;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon, service_role;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon, service_role;
create temp table _z_c on commit drop as
  select c.campanha_externa as camp from mkt_trafego.campanhas c where c.plataforma = 'meta' order by c.id limit 1;
insert into pg_temp._z_out (passo, linha) select '0 campanha pai existe', (select count(*) from pg_temp._z_c)::text;
insert into pg_temp._z_out (passo, linha)
  select '0 antes md5 desempenho_dia', md5(coalesce((select string_agg(d::text, '|' order by d.campanha_id, d.dia) from mkt_trafego.desempenho_dia d), ''));
insert into pg_temp._z_out (passo, linha)
  select '0 antes md5 funções atuais', md5((select string_agg(p.oid::regprocedure::text || p.prosrc || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)
    from pg_proc p where p.oid in ('public.trafego_desempenho_receber(jsonb)'::regprocedure, 'public.trafego_desempenho_total_receber(jsonb)'::regprocedure,
                                   'public.trafego_campanhas_receber(jsonb)'::regprocedure)));

-- ===== MIGRATION =====
-- 20261012120000: Meta Ads por conjunto e por anúncio (painel da Black Friday)
--
-- STATUS: NÃO APLICADA. Ver 20261012120000.explain.md (conferências do estado vivo C1 a C17 ainda NÃO FEITAS; a C3,
--   colunas e checks vivos de mkt_trafego.desempenho_dia, é obrigatória antes de aplicar).
-- ARQUIVO EM UTF-8: o translate da mkt_trafego.etapa_black usa um mapa de letras acentuadas. Se o arquivo for
--   regravado em outra codificação, a etapa deixa de casar "ANTECIPAÇÃO". O ensaio confere.
-- POR QUE: o painel da Black vai mostrar quanto cada anúncio e cada conjunto gastou e entregou por dia, com miniatura e
--   com a etapa C1/C2/C3 tirada do nome da campanha. Hoje a coleta Meta (20261006g/i, 20261009230000) só grava por
--   campanha. Tudo aqui é ADITIVO: desempenho_dia, as funções de entrada atuais e os jobs não mudam.
-- O QUE FAZ:
--   1. mkt_trafego.conjuntos, mkt_trafego.anuncios e mkt_trafego.desempenho_anuncio_dia (mesmas métricas, tipos e
--      checks de desempenho_dia, copiados das migrations 20261006g e 20261009230000). Tabelas fechadas: RLS ligada,
--      sem policy, sem grant para public, anon e authenticated (o mesmo padrão de desempenho_dia).
--   2. Funções de entrada (só service_role; a Edge entra como postgres): trafego_conjuntos_receber,
--      trafego_anuncios_receber, trafego_desempenho_anuncio_receber, trafego_anuncio_miniatura_receber.
--      Cadastro: nulo nunca apaga dado conhecido (coalesce); a linha só é reescrita quando algo mudou
--      (is distinct from); ultima_coleta atualiza sempre.
--   3. mkt_trafego.etapa_black(nome): etapa (C1, C2, C3) e subtipo pelo nome da campanha, calculados na leitura e nunca
--      gravados. Sem grant para ninguém (interna; a RPC de leitura do dashboard é de outra fase).
--   4. Liga e desliga por conta: linha 'meta_anuncio_contas' em mkt_trafego.coleta_config, NASCE NULA (desligada).
--   5. Bucket privado 'trafego-miniaturas' (sem policy: só a service_role lê e grava). Caminho meta/<conta>/<criativo>.<ext>.
-- AS 5 PERGUNTAS:
--   escala: ~32 anúncios com entrega por dia na conta CNF (estimativa do desenho, não medida) = ~1 mil linhas/mês em
--     desempenho_anuncio_dia; com 10x, ~120 mil/ano. Miniaturas: até 1 MB cada (limite do bucket).
--   índice: PK (anuncio_id, dia); uniques (plataforma, *_externa) usadas pelas funções de entrada; conjuntos(campanha_id)
--     e anuncios(conjunto_id) para o join do dashboard; anuncios(criativo_externa) parcial para a miniatura.
--   frequência: as rodadas do trafego-meta (cron trafego-meta-hoje a cada 30 min + o diário), só nas contas da flag.
--   repetição: upserts idempotentes (o ensaio roda duas vezes e confere as contagens).
--   reversão: desligar a flag (update ... set valor = null); ou 20261012120000_reversao.sql.
-- JANELA: a FK para campanhas pega um lock curto. Aplicar fora dos minutos :15/:45 e fora das 09:30 UTC (jobs de coleta).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- 0. Premissas (aborta se o banco não estiver como esta migration espera)
do $g$
begin
  if (select prosrc from pg_proc where oid = 'public.trafego_desempenho_receber(jsonb)'::regprocedure) !~ '20261009230000' then
    raise exception '20261012120000: trafego_desempenho_receber não é a versão de 20261009230000. Reler antes de aplicar.';
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'mkt_trafego' and table_name = 'desempenho_dia'
         and column_name in ('alcance', 'frequencia', 'cliques_saida', 'landing_page_views', 'engajamento', 'video_plays',
                             'video_thruplay', 'video_p25', 'video_p50', 'video_p75', 'video_p100')) <> 11 then
    raise exception '20261012120000: desempenho_dia sem as colunas de 20261009230000. Reler (conferência C3).';
  end if;
  if to_regclass('mkt_trafego.conjuntos') is not null or to_regclass('mkt_trafego.anuncios') is not null
     or to_regclass('mkt_trafego.desempenho_anuncio_dia') is not null then
    raise exception '20261012120000: tabela de conjunto/anúncio já existe.';
  end if;
  if to_regprocedure('mkt_trafego.etapa_black(text)') is not null then
    raise exception '20261012120000: mkt_trafego.etapa_black já existe.';
  end if;
  if to_regprocedure('public.trafego_conjuntos_receber(jsonb)') is not null
     or to_regprocedure('public.trafego_anuncios_receber(jsonb)') is not null
     or to_regprocedure('public.trafego_desempenho_anuncio_receber(jsonb)') is not null
     or to_regprocedure('public.trafego_anuncio_miniatura_receber(jsonb)') is not null then
    raise exception '20261012120000: função de entrada de conjunto/anúncio já existe.';
  end if;
  -- Conferência do ESTADO VIVO (C11): o bucket novo é privado e sem policy, mas uma policy PERMISSIVA em
  -- storage.objects para anon, authenticated ou public que não filtre bucket_id abriria também este bucket. Se existir
  -- (inclusive de outro sistema), a premissa falha e a decisão é do Victor (não se mexe em policy de terceiro aqui).
  if exists (select 1 from pg_policies p
              where p.schemaname = 'storage' and p.tablename = 'objects' and p.permissive = 'PERMISSIVE'
                and p.roles && array['anon', 'authenticated', 'public']::name[]
                and ((p.qual is null and p.with_check is null)
                     or (p.qual is not null and p.qual not like '%bucket_id%')
                     or (p.with_check is not null and p.with_check not like '%bucket_id%'))) then
    raise exception '20261012120000: policy em storage.objects para anon/authenticated/public sem filtro de bucket_id (C11). Decidir com o Victor antes de aplicar.';
  end if;
  if exists (select 1 from mkt_trafego.coleta_config where chave = 'meta_anuncio_contas') then
    raise exception '20261012120000: coleta_config meta_anuncio_contas já existe.';
  end if;
  if exists (select 1 from storage.buckets b where b.id = 'trafego-miniaturas') then
    raise exception '20261012120000: bucket trafego-miniaturas já existe.';
  end if;
end
$g$;

-- 1. Tabelas
create table mkt_trafego.conjuntos (
  id                bigint generated always as identity primary key,
  plataforma        text not null check (plataforma in ('meta')),
  campanha_id       bigint not null references mkt_trafego.campanhas (id) on delete cascade,
  conjunto_externa  text not null check (conjunto_externa ~ '^[A-Za-z0-9_-]{1,60}$'),
  nome              text not null check (length(nome) between 1 and 400),
  status_plataforma text check (status_plataforma is null or length(status_plataforma) <= 40),
  meta_otimizacao   text check (meta_otimizacao is null or length(meta_otimizacao) <= 60),
  primeira_coleta   timestamptz not null default now(),
  ultima_coleta     timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  constraint conjuntos_externa_unica unique (plataforma, conjunto_externa)
);
create index conjuntos_campanha_idx on mkt_trafego.conjuntos (campanha_id);
comment on table mkt_trafego.conjuntos is
  'Conjuntos de anúncios (adset) do Meta com entrega, gravados pela Edge trafego-meta (contas da flag '
  'coleta_config meta_anuncio_contas). Nome EXATO do Meta. 20261012120000.';
comment on column mkt_trafego.conjuntos.meta_otimizacao is 'optimization_goal do Meta.';

create table mkt_trafego.anuncios (
  id                 bigint generated always as identity primary key,
  plataforma         text not null check (plataforma in ('meta')),
  conjunto_id        bigint not null references mkt_trafego.conjuntos (id) on delete cascade,
  anuncio_externa    text not null check (anuncio_externa ~ '^[A-Za-z0-9_-]{1,60}$'),
  nome               text not null check (length(nome) between 1 and 400),
  status_plataforma  text check (status_plataforma is null or length(status_plataforma) <= 40),
  criativo_externa   text check (criativo_externa is null or criativo_externa ~ '^[0-9]{1,30}$'),
  video_id           text check (video_id is null or video_id ~ '^[0-9]{1,30}$'),
  url_tags           text check (url_tags is null or length(url_tags) <= 2000),
  miniatura_caminho  text check (miniatura_caminho is null or miniatura_caminho ~ '^meta/[0-9]{1,30}/[0-9]{1,30}\.(jpg|png|webp)$'),
  miniatura_em       timestamptz,
  miniatura_erro     text check (miniatura_erro is null or length(miniatura_erro) <= 60),
  miniatura_erro_em  timestamptz,
  primeira_coleta    timestamptz not null default now(),
  ultima_coleta      timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  constraint anuncios_externa_unica unique (plataforma, anuncio_externa)
);
create index anuncios_conjunto_idx on mkt_trafego.anuncios (conjunto_id);
create index anuncios_criativo_idx on mkt_trafego.anuncios (criativo_externa) where criativo_externa is not null;
comment on table mkt_trafego.anuncios is
  'Anúncios do Meta com entrega, gravados pela Edge trafego-meta. Nome EXATO do Meta. A miniatura fica no bucket '
  'privado trafego-miniaturas (caminho em miniatura_caminho); a URL do Meta nunca é gravada. 20261012120000.';
comment on column mkt_trafego.anuncios.url_tags is 'url_tags do criativo, como o time de tráfego digitou. Escapar ao exibir.';

-- mesmas colunas, tipos e checks de mkt_trafego.desempenho_dia (20261006g + 20261009230000), com anuncio_id
create table mkt_trafego.desempenho_anuncio_dia (
  anuncio_id         bigint not null references mkt_trafego.anuncios (id) on delete cascade,
  dia                date not null,
  gasto              numeric(14,2) not null check (gasto >= 0),
  impressoes         bigint not null check (impressoes >= 0),
  cliques_link       bigint not null check (cliques_link >= 0),
  cliques_total      bigint check (cliques_total is null or cliques_total >= 0),
  leads_plataforma   integer check (leads_plataforma is null or leads_plataforma >= 0),
  coletado_em        timestamptz not null default now(),
  alcance            bigint check (alcance >= 0),
  frequencia         numeric(12,4) check (frequencia >= 0),
  cliques_saida      bigint check (cliques_saida >= 0),
  landing_page_views bigint check (landing_page_views >= 0),
  engajamento        bigint check (engajamento >= 0),
  video_plays        bigint check (video_plays >= 0),
  video_thruplay     bigint check (video_thruplay >= 0),
  video_p25          bigint check (video_p25 >= 0),
  video_p50          bigint check (video_p50 >= 0),
  video_p75          bigint check (video_p75 >= 0),
  video_p100         bigint check (video_p100 >= 0),
  primary key (anuncio_id, dia)
);
comment on table mkt_trafego.desempenho_anuncio_dia is
  'Desempenho diário por anúncio do Meta (mesmas métricas de desempenho_dia). Alcance e frequência NÃO somam entre '
  'anúncios nem entre dias. 20261012120000.';

alter table mkt_trafego.conjuntos enable row level security;
alter table mkt_trafego.anuncios enable row level security;
alter table mkt_trafego.desempenho_anuncio_dia enable row level security;
revoke all on mkt_trafego.conjuntos, mkt_trafego.anuncios, mkt_trafego.desempenho_anuncio_dia from public, anon, authenticated;
revoke all on sequence mkt_trafego.conjuntos_id_seq, mkt_trafego.anuncios_id_seq from public, anon, authenticated;

-- 2. Funções de entrada (Edge trafego-meta). Teto de lote e formato de recusas iguais aos de
--    trafego_desempenho_total_receber (20261009230000).
create or replace function public.trafego_conjuntos_receber(p jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  e jsonb; v_plat text; v_ext text; v_nome text; v_status text; v_otim text; v_camp bigint;
  v_id bigint; v_mudou boolean;
  v_novos int := 0; v_atual int := 0; v_iguais int := 0; v_recusas jsonb := '[]'::jsonb;
begin
  -- 20261012120000: cadastro dos conjuntos (adset) com entrega. Nulo não apaga dado conhecido.
  if jsonb_typeof(p) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava uma lista.');
  end if;
  if jsonb_array_length(p) > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000 por chamada).');
  end if;
  for e in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(e) is distinct from 'object' or lower(btrim(coalesce(e ->> 'plataforma', ''))) <> 'meta' then
      v_recusas := v_recusas || jsonb_build_object('id', left(e ->> 'id', 60), 'motivo', 'formato_invalido');
      continue;
    end if;
    v_plat := 'meta';
    v_ext := btrim(coalesce(e ->> 'id', ''));
    v_nome := coalesce(e ->> 'nome', '');
    v_status := nullif(left(btrim(coalesce(e ->> 'status', '')), 40), '');
    v_otim := nullif(left(btrim(coalesce(e ->> 'meta_otimizacao', '')), 60), '');
    if v_ext !~ '^[A-Za-z0-9_-]{1,60}$' then
      v_recusas := v_recusas || jsonb_build_object('id', left(e ->> 'id', 60), 'motivo', 'id_invalido');
      continue;
    end if;
    if length(v_nome) not between 1 and 400 then
      v_recusas := v_recusas || jsonb_build_object('id', left(v_ext, 60), 'motivo', 'nome_invalido');
      continue;
    end if;
    select c.id into v_camp from mkt_trafego.campanhas c
     where c.plataforma = v_plat and c.campanha_externa = btrim(coalesce(e ->> 'campanha', ''));
    if v_camp is null then
      v_recusas := v_recusas || jsonb_build_object('id', left(v_ext, 60), 'motivo', 'campanha_desconhecida');
      continue;
    end if;
    select j.id,
           (j.campanha_id, j.nome, j.status_plataforma, j.meta_otimizacao)
             is distinct from (v_camp, v_nome, coalesce(v_status, j.status_plataforma), coalesce(v_otim, j.meta_otimizacao))
      into v_id, v_mudou
      from mkt_trafego.conjuntos j where j.plataforma = v_plat and j.conjunto_externa = v_ext for update;
    if v_id is null then
      insert into mkt_trafego.conjuntos (plataforma, campanha_id, conjunto_externa, nome, status_plataforma, meta_otimizacao)
      values (v_plat, v_camp, v_ext, v_nome, v_status, v_otim)
      on conflict (plataforma, conjunto_externa) do nothing
      returning id into v_id;
      if v_id is not null then
        v_novos := v_novos + 1;
        continue;
      end if;
      -- outra rodada inseriu entre o select e o insert: segue como atualização
      select j.id,
             (j.campanha_id, j.nome, j.status_plataforma, j.meta_otimizacao)
               is distinct from (v_camp, v_nome, coalesce(v_status, j.status_plataforma), coalesce(v_otim, j.meta_otimizacao))
        into v_id, v_mudou
        from mkt_trafego.conjuntos j where j.plataforma = v_plat and j.conjunto_externa = v_ext for update;
    end if;
    if v_mudou then
      update mkt_trafego.conjuntos j
         set campanha_id = v_camp, nome = v_nome,
             status_plataforma = coalesce(v_status, j.status_plataforma),
             meta_otimizacao = coalesce(v_otim, j.meta_otimizacao),
             atualizado_em = now(), ultima_coleta = now()
       where j.id = v_id;
      v_atual := v_atual + 1;
    else
      update mkt_trafego.conjuntos j set ultima_coleta = now() where j.id = v_id;
      v_iguais := v_iguais + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'novos', v_novos, 'atualizados', v_atual, 'iguais', v_iguais, 'recusas', v_recusas);
end
$function$;

create or replace function public.trafego_anuncios_receber(p jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  e jsonb; v_plat text; v_ext text; v_nome text; v_status text; v_cri text; v_vid text; v_tags text; v_conj bigint;
  v_id bigint; v_mudou boolean; v_cri_atual text;
  v_ids bigint[] := '{}';
  v_novos int := 0; v_atual int := 0; v_iguais int := 0; v_recusas jsonb := '[]'::jsonb; v_pend jsonb;
begin
  -- 20261012120000: cadastro dos anúncios com entrega. Nulo não apaga dado conhecido. Criativo novo = miniatura de novo.
  if jsonb_typeof(p) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava uma lista.');
  end if;
  if jsonb_array_length(p) > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000 por chamada).');
  end if;
  for e in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(e) is distinct from 'object' or lower(btrim(coalesce(e ->> 'plataforma', ''))) <> 'meta' then
      v_recusas := v_recusas || jsonb_build_object('id', left(e ->> 'id', 60), 'motivo', 'formato_invalido');
      continue;
    end if;
    v_plat := 'meta';
    v_ext := btrim(coalesce(e ->> 'id', ''));
    v_nome := coalesce(e ->> 'nome', '');
    v_status := nullif(left(btrim(coalesce(e ->> 'status', '')), 40), '');
    v_cri := nullif(btrim(coalesce(e ->> 'criativo', '')), '');
    v_vid := nullif(btrim(coalesce(e ->> 'video_id', '')), '');
    v_tags := nullif(e ->> 'url_tags', '');
    if v_ext !~ '^[A-Za-z0-9_-]{1,60}$' then
      v_recusas := v_recusas || jsonb_build_object('id', left(e ->> 'id', 60), 'motivo', 'id_invalido');
      continue;
    end if;
    if length(v_nome) not between 1 and 400 then
      v_recusas := v_recusas || jsonb_build_object('id', left(v_ext, 60), 'motivo', 'nome_invalido');
      continue;
    end if;
    if v_cri !~ '^[0-9]{1,30}$' or v_vid !~ '^[0-9]{1,30}$' or length(v_tags) > 2000 then
      v_recusas := v_recusas || jsonb_build_object('id', left(v_ext, 60), 'motivo', 'formato_invalido');
      continue;
    end if;
    select j.id into v_conj from mkt_trafego.conjuntos j
     where j.plataforma = v_plat and j.conjunto_externa = btrim(coalesce(e ->> 'conjunto', ''));
    if v_conj is null then
      v_recusas := v_recusas || jsonb_build_object('id', left(v_ext, 60), 'motivo', 'conjunto_desconhecido');
      continue;
    end if;
    select a.id, a.criativo_externa,
           (a.conjunto_id, a.nome, a.status_plataforma, a.criativo_externa, a.video_id, a.url_tags)
             is distinct from (v_conj, v_nome, coalesce(v_status, a.status_plataforma), coalesce(v_cri, a.criativo_externa),
                               coalesce(v_vid, a.video_id), coalesce(v_tags, a.url_tags))
      into v_id, v_cri_atual, v_mudou
      from mkt_trafego.anuncios a where a.plataforma = v_plat and a.anuncio_externa = v_ext for update;
    if v_id is null then
      insert into mkt_trafego.anuncios (plataforma, conjunto_id, anuncio_externa, nome, status_plataforma, criativo_externa,
                                        video_id, url_tags)
      values (v_plat, v_conj, v_ext, v_nome, v_status, v_cri, v_vid, v_tags)
      on conflict (plataforma, anuncio_externa) do nothing
      returning id into v_id;
      if v_id is not null then
        v_novos := v_novos + 1;
        v_ids := v_ids || v_id;
        continue;
      end if;
      -- outra rodada inseriu entre o select e o insert: segue como atualização
      select a.id, a.criativo_externa,
             (a.conjunto_id, a.nome, a.status_plataforma, a.criativo_externa, a.video_id, a.url_tags)
               is distinct from (v_conj, v_nome, coalesce(v_status, a.status_plataforma), coalesce(v_cri, a.criativo_externa),
                                 coalesce(v_vid, a.video_id), coalesce(v_tags, a.url_tags))
        into v_id, v_cri_atual, v_mudou
        from mkt_trafego.anuncios a where a.plataforma = v_plat and a.anuncio_externa = v_ext for update;
    end if;
    if v_mudou then
      update mkt_trafego.anuncios a
         set conjunto_id = v_conj, nome = v_nome,
             status_plataforma = coalesce(v_status, a.status_plataforma),
             criativo_externa = coalesce(v_cri, a.criativo_externa),
             video_id = coalesce(v_vid, a.video_id),
             url_tags = coalesce(v_tags, a.url_tags),
             atualizado_em = now(), ultima_coleta = now()
       where a.id = v_id;
      -- criativo trocado: a miniatura guardada é de outro criativo, baixa de novo
      if v_cri is not null and v_cri is distinct from v_cri_atual then
        update mkt_trafego.anuncios a
           set miniatura_caminho = null, miniatura_em = null, miniatura_erro = null, miniatura_erro_em = null
         where a.id = v_id;
      end if;
      v_atual := v_atual + 1;
    else
      update mkt_trafego.anuncios a set ultima_coleta = now() where a.id = v_id;
      v_iguais := v_iguais + 1;
    end if;
    v_ids := v_ids || v_id;
  end loop;
  -- criativos DESTE lote sem miniatura e sem falha nas últimas 24 h (a Edge só tem a URL dos que acabou de ler)
  select coalesce(jsonb_agg(x.criativo_externa order by x.criativo_externa), '[]'::jsonb) into v_pend
    from (select distinct a.criativo_externa from mkt_trafego.anuncios a
           where a.id = any (v_ids) and a.criativo_externa is not null and a.miniatura_caminho is null
             and (a.miniatura_erro_em is null or a.miniatura_erro_em < now() - interval '24 hours')
           order by a.criativo_externa limit 20) x;
  return jsonb_build_object('ok', true, 'novos', v_novos, 'atualizados', v_atual, 'iguais', v_iguais, 'recusas', v_recusas,
                            'pendentes_miniatura', v_pend);
end
$function$;

-- corpo de public.trafego_desempenho_receber (20261009230000), com anuncio no lugar de campanha
create or replace function public.trafego_desempenho_anuncio_receber(p jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  e jsonb;
  v_anu bigint; v_dia date; v_gasto numeric; v_imp bigint; v_cli bigint; v_tot bigint; v_leads integer;
  v_alc bigint; v_freq numeric; v_sai bigint; v_lpv bigint; v_eng bigint; v_vpl bigint; v_vth bigint;
  v_v25 bigint; v_v50 bigint; v_v75 bigint; v_v100 bigint;
  v_n int := 0;
  v_recusas jsonb := '[]'::jsonb;
begin
  -- 20261012120000: desempenho diário por anúncio
  if jsonb_typeof(p) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava uma lista.');
  end if;
  if jsonb_array_length(p) > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000 por chamada).');
  end if;
  for e in select * from jsonb_array_elements(p) loop
    select a.id into v_anu from mkt_trafego.anuncios a
     where a.plataforma = lower(btrim(coalesce(e ->> 'plataforma', ''))) and a.anuncio_externa = btrim(coalesce(e ->> 'anuncio', ''));
    if v_anu is null then
      v_recusas := v_recusas || jsonb_build_object('anuncio', left(e ->> 'anuncio', 60), 'dia', left(e ->> 'dia', 60), 'motivo', 'anuncio_desconhecido');
      continue;
    end if;
    begin
      v_dia := (e ->> 'dia')::date;
      v_gasto := coalesce((e ->> 'gasto')::numeric, 0);
      v_imp := coalesce((e ->> 'impressoes')::bigint, 0);
      v_cli := coalesce((e ->> 'cliques_link')::bigint, 0);
      v_tot := (e ->> 'cliques_total')::bigint;
      v_leads := (e ->> 'leads')::integer;
      v_alc := (e ->> 'alcance')::bigint; v_freq := (e ->> 'frequencia')::numeric; v_sai := (e ->> 'cliques_saida')::bigint;
      v_lpv := (e ->> 'landing_page_views')::bigint; v_eng := (e ->> 'engajamento')::bigint;
      v_vpl := (e ->> 'video_plays')::bigint; v_vth := (e ->> 'video_thruplay')::bigint;
      v_v25 := (e ->> 'video_p25')::bigint; v_v50 := (e ->> 'video_p50')::bigint;
      v_v75 := (e ->> 'video_p75')::bigint; v_v100 := (e ->> 'video_p100')::bigint;
    exception when others then
      v_recusas := v_recusas || jsonb_build_object('anuncio', left(e ->> 'anuncio', 60), 'dia', left(e ->> 'dia', 60), 'motivo', 'formato_invalido');
      continue;
    end;
    if v_dia is null or v_dia > mkt_trafego.ontem() + 1 or v_gasto < 0 or v_imp < 0 or v_cli < 0 or v_tot < 0 or v_leads < 0
       or v_gasto >= 1e12
       or v_alc < 0 or v_freq < 0 or v_freq >= 1e6 or v_sai < 0 or v_lpv < 0 or v_eng < 0 or v_vpl < 0 or v_vth < 0
       or v_v25 < 0 or v_v50 < 0 or v_v75 < 0 or v_v100 < 0 then
      v_recusas := v_recusas || jsonb_build_object('anuncio', left(e ->> 'anuncio', 60), 'dia', left(e ->> 'dia', 60), 'motivo', 'valor_invalido');
      continue;
    end if;
    insert into mkt_trafego.desempenho_anuncio_dia (anuncio_id, dia, gasto, impressoes, cliques_link, cliques_total, leads_plataforma,
                                                    coletado_em, alcance, frequencia, cliques_saida, landing_page_views, engajamento,
                                                    video_plays, video_thruplay, video_p25, video_p50, video_p75, video_p100)
    values (v_anu, v_dia, round(v_gasto, 2), v_imp, v_cli, v_tot, v_leads, now(),
            v_alc, round(v_freq, 4), v_sai, v_lpv, v_eng, v_vpl, v_vth, v_v25, v_v50, v_v75, v_v100)
    on conflict (anuncio_id, dia) do update
       set gasto = excluded.gasto, impressoes = excluded.impressoes, cliques_link = excluded.cliques_link,
           cliques_total = excluded.cliques_total,
           leads_plataforma = excluded.leads_plataforma, coletado_em = now(),
           alcance = excluded.alcance, frequencia = excluded.frequencia, cliques_saida = excluded.cliques_saida,
           landing_page_views = excluded.landing_page_views, engajamento = excluded.engajamento,
           video_plays = excluded.video_plays, video_thruplay = excluded.video_thruplay, video_p25 = excluded.video_p25,
           video_p50 = excluded.video_p50, video_p75 = excluded.video_p75, video_p100 = excluded.video_p100;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'gravadas', v_n, 'recusas', v_recusas);
end
$function$;

create or replace function public.trafego_anuncio_miniatura_receber(p jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  e jsonb; v_cri text; v_cam text; v_err text; v_n int;
  v_ok int := 0; v_erros int := 0; v_recusas jsonb := '[]'::jsonb;
begin
  -- 20261012120000: resultado do download da miniatura. {criativo, caminho} = guardada; {criativo, erro} = falhou
  -- (tenta de novo depois de 24 h). O caminho tem que ser meta/<conta>/<o mesmo criativo>.<jpg|png|webp>.
  if jsonb_typeof(p) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'msg', 'Esperava uma lista.');
  end if;
  if jsonb_array_length(p) > 5000 then
    return jsonb_build_object('ok', false, 'msg', 'Lista grande demais (máximo 5000 por chamada).');
  end if;
  for e in select * from jsonb_array_elements(p) loop
    v_cri := btrim(coalesce(e ->> 'criativo', ''));
    v_cam := nullif(btrim(coalesce(e ->> 'caminho', '')), '');
    v_err := nullif(left(btrim(coalesce(e ->> 'erro', '')), 60), '');
    if v_cri !~ '^[0-9]{1,30}$' then
      v_recusas := v_recusas || jsonb_build_object('criativo', left(e ->> 'criativo', 60), 'motivo', 'criativo_invalido');
      continue;
    end if;
    if v_cam is not null then
      -- v_cri só tem dígitos (conferido acima): seguro dentro da expressão
      if v_cam !~ ('^meta/[0-9]{1,30}/' || v_cri || '\.(jpg|png|webp)$') then
        v_recusas := v_recusas || jsonb_build_object('criativo', left(v_cri, 60), 'motivo', 'caminho_invalido');
        continue;
      end if;
      update mkt_trafego.anuncios a
         set miniatura_caminho = v_cam, miniatura_em = now(), miniatura_erro = null, miniatura_erro_em = null
       where a.plataforma = 'meta' and a.criativo_externa = v_cri;
      get diagnostics v_n = row_count;
      if v_n > 0 then v_ok := v_ok + 1; end if;
    elsif v_err is not null then
      update mkt_trafego.anuncios a
         set miniatura_erro = v_err, miniatura_erro_em = now()
       where a.plataforma = 'meta' and a.criativo_externa = v_cri and a.miniatura_caminho is null;
      get diagnostics v_n = row_count;
      if v_n > 0 then v_erros := v_erros + 1; end if;
    else
      v_recusas := v_recusas || jsonb_build_object('criativo', left(v_cri, 60), 'motivo', 'formato_invalido');
      continue;
    end if;
    if v_n = 0 then
      v_recusas := v_recusas || jsonb_build_object('criativo', left(v_cri, 60), 'motivo',
        case when exists (select 1 from mkt_trafego.anuncios a where a.plataforma = 'meta' and a.criativo_externa = v_cri)
             then 'ja_tem_miniatura' else 'criativo_desconhecido' end);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'gravadas', v_ok, 'erros', v_erros, 'recusas', v_recusas);
end
$function$;

revoke all on function public.trafego_conjuntos_receber(jsonb) from public, anon, authenticated;
revoke all on function public.trafego_anuncios_receber(jsonb) from public, anon, authenticated;
revoke all on function public.trafego_desempenho_anuncio_receber(jsonb) from public, anon, authenticated;
revoke all on function public.trafego_anuncio_miniatura_receber(jsonb) from public, anon, authenticated;
grant execute on function public.trafego_conjuntos_receber(jsonb) to service_role;
grant execute on function public.trafego_anuncios_receber(jsonb) to service_role;
grant execute on function public.trafego_desempenho_anuncio_receber(jsonb) to service_role;
grant execute on function public.trafego_anuncio_miniatura_receber(jsonb) to service_role;

-- 3. Etapa da Black pelo nome da campanha (regra de 12/10/2026). A regra mora SÓ aqui: para trocar, create or replace
--    com a mesma assinatura numa migration nova.
--    Como casa: o nome é dividido por "|", cada termo sem espaço nas pontas; o termo INTEIRO tem que ser o código
--    (C1, C2, C3) ou o subtipo (CPF01 não vira C1; "C2 ISCAS" num termo só não casa). Acento e maiúscula não importam:
--    o translate tira o acento ANTES do upper (não depende do ctype do banco). O subtipo sai na grafia oficial.
--    Mais de um código: etapa nula. Mais de um subtipo da etapa: subtipo nulo.
create or replace function mkt_trafego.etapa_black(p_nome text)
 returns table (etapa text, subtipo text)
 language sql
 immutable parallel safe
 set search_path to ''
as $function$
  with regra (etapa, chave, rotulo) as (
    values ('C1', 'TEASER', 'TEASER'), ('C1', 'ANTECIPACAO', 'ANTECIPAÇÃO'), ('C1', 'REELS', 'REELS'), ('C1', 'CORTES', 'CORTES'),
           -- MANIFESTO: EM ABERTO (decisão de 12/10). Se o Victor decidir que é do C1, acrescentar aqui
           -- ('C1', 'MANIFESTO', 'MANIFESTO'). Hoje "X | C1 | MANIFESTO" dá C1 sem subtipo.
           ('C2', 'CONSULTORIA', 'CONSULTORIA'), ('C2', 'ISCA', 'ISCA'),
           ('C3', 'LEADS', 'LEADS')
  ),
  termo as (
    select distinct upper(btrim(translate(u.t, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
                                               'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'))) as t
      from unnest(string_to_array(coalesce(p_nome, ''), '|')) as u (t)
  ),
  cod as (select distinct r.etapa from regra r join termo on termo.t = r.etapa),
  sub as (select distinct r.rotulo from regra r join termo on termo.t = r.chave join cod on cod.etapa = r.etapa)
  -- DECISÃO PENDENTE DO VICTOR: código que casa sem subtipo (ex.: "X | C3 | LEAD") hoje fica COM a etapa e subtipo
  -- nulo, para o gasto não sumir da etapa. Para virar "sem etapa", a linha da etapa abaixo passa a exigir também
  -- (select count(*) from sub) = 1.
  select case when (select count(*) from cod) = 1 then (select c.etapa from cod c) end as etapa,
         case when (select count(*) from cod) = 1 and (select count(*) from sub) = 1 then (select s.rotulo from sub s) end as subtipo
$function$;
revoke all on function mkt_trafego.etapa_black(text) from public, anon, authenticated, service_role;

-- 4. Liga e desliga por conta (nasce DESLIGADA). A Edge lê pela coleta_parametros(), que agrega a tabela inteira.
insert into mkt_trafego.coleta_config (chave, valor, descricao) values
  ('meta_anuncio_contas', null,
   'Contas Meta (id sem act_, separadas por vírgula) com coleta por conjunto e anúncio na Edge trafego-meta. '
   'Nulo = desligada. Ligar só com o ok do Victor (recomendado: só a CNF). 20261012120000.');

-- 5. Bucket privado das miniaturas (sem policy: só a service_role, que ignora RLS, lê e grava)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('trafego-miniaturas', 'trafego-miniaturas', false, 1048576, array['image/jpeg', 'image/png', 'image/webp']);

-- 6. Conferência (aborta a migration inteira se algo não ficou como deveria)
do $c$
declare
  t text; f text; r text;
begin
  foreach t in array array['mkt_trafego.conjuntos', 'mkt_trafego.anuncios', 'mkt_trafego.desempenho_anuncio_dia'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261012120000: RLS desligada em %', t;
    end if;
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261012120000: % tem privilégio em %', r, t;
      end if;
    end loop;
    if exists (select 1 from pg_class c cross join lateral aclexplode(c.relacl) g where c.oid = t::regclass and g.grantee = 0) then
      raise exception '20261012120000: PUBLIC tem privilégio em %', t;
    end if;
    if exists (select 1 from pg_policies p where p.schemaname = 'mkt_trafego' and p.tablename = split_part(t, '.', 2)) then
      raise exception '20261012120000: % tem policy (devia ser fechada)', t;
    end if;
  end loop;
  foreach f in array array['public.trafego_conjuntos_receber(jsonb)', 'public.trafego_anuncios_receber(jsonb)',
                           'public.trafego_desempenho_anuncio_receber(jsonb)', 'public.trafego_anuncio_miniatura_receber(jsonb)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception '20261012120000: permissão errada em %', f;
    end if;
    -- proacl só com o dono e a service_role
    if exists (select 1 from pg_proc p cross join lateral aclexplode(p.proacl) g
                where p.oid = f::regprocedure and g.grantee <> p.proowner and g.grantee <> 'service_role'::regrole::oid) then
      raise exception '20261012120000: % tem grant além do dono e da service_role', f;
    end if;
    if not (select coalesce(p.proconfig, '{}') @> array['search_path=""'] and p.prosecdef from pg_proc p where p.oid = f::regprocedure) then
      raise exception '20261012120000: % sem search_path vazio ou sem security definer', f;
    end if;
  end loop;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(r, 'mkt_trafego.etapa_black(text)', 'execute') then
      raise exception '20261012120000: % executa mkt_trafego.etapa_black', r;
    end if;
  end loop;
  if exists (select 1 from pg_proc p cross join lateral aclexplode(p.proacl) g
              where p.oid = 'mkt_trafego.etapa_black(text)'::regprocedure and g.grantee <> p.proowner) then
    raise exception '20261012120000: mkt_trafego.etapa_black tem grant além do dono (inclusive PUBLIC)';
  end if;
  if (select b.public from storage.buckets b where b.id = 'trafego-miniaturas') is distinct from false then
    raise exception '20261012120000: bucket trafego-miniaturas não ficou privado';
  end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
              and (coalesce(p.qual, '') || coalesce(p.with_check, '')) like '%trafego-miniaturas%') then
    raise exception '20261012120000: há policy em storage.objects citando trafego-miniaturas';
  end if;
  if not exists (select 1 from mkt_trafego.coleta_config k where k.chave = 'meta_anuncio_contas' and k.valor is null) then
    raise exception '20261012120000: coleta_config meta_anuncio_contas não ficou criada e desligada';
  end if;
end
$c$;

-- ===== FIM DA MIGRATION =====

-- 1. Etapa pelo nome (os 14 casos da regra de 12/10/2026)
create temp table _z_etapa on commit drop as
select v.n, v.esp_e, v.esp_s, e.etapa, e.subtipo,
       (e.etapa is not distinct from v.esp_e and e.subtipo is not distinct from v.esp_s) as confere
  from (values
    ('BF26 | CPF01 | META | IG | MORNO | ABO | LEAD', null::text, null::text),
    ('CF | BF26 | ANTECIPAÇÃO | TEASER | X', null, null),
    ('X | C1 | Antecipacao', 'C1', 'ANTECIPAÇÃO'),
    ('X | c1 | antecipação', 'C1', 'ANTECIPAÇÃO'),
    ('X | C1 | MANIFESTO', 'C1', null),
    ('X | c2 | isca', 'C2', 'ISCA'),
    ('X | C2 | ISCAS', 'C2', null),
    ('X | C2 ISCAS | Y', null, null),
    ('X | C3 | LEADS', 'C3', 'LEADS'),
    ('X | C3 | LEAD', 'C3', null),
    ('X | C1 | C2 | TEASER', null, null),
    ('C1|TEASER', 'C1', 'TEASER'),
    ('C1 | ANTECIPAÇÃO | TEASER', 'C1', null),
    (null, null, null)
  ) v (n, esp_e, esp_s)
  cross join lateral mkt_trafego.etapa_black(v.n) e;
insert into pg_temp._z_out (passo, linha)
  select '1 etapa ' || coalesce(n, '(nulo)'), jsonb_build_object('etapa', etapa, 'subtipo', subtipo, 'confere', confere)::text from pg_temp._z_etapa;
insert into pg_temp._z_out (passo, linha)
  select '1 etapa resumo', jsonb_build_object('casos', count(*), 'erradas', count(*) filter (where not confere))::text from pg_temp._z_etapa;

-- 2. Conjuntos
insert into pg_temp._z_out (passo, linha)
select '2 conjuntos 1a', public.trafego_conjuntos_receber(jsonb_build_array(
  1,
  jsonb_build_object('plataforma', 'google', 'id', 'ZZENSAIO009', 'nome', 'x', 'campanha', (select camp from pg_temp._z_c)),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZ ENSAIO', 'nome', 'x', 'campanha', (select camp from pg_temp._z_c)),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIO008', 'nome', '', 'campanha', (select camp from pg_temp._z_c)),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIO007', 'nome', 'x', 'campanha', 'ZZ_NAO_EXISTE'),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIO001', 'nome', 'ENSAIO | CONJUNTO A', 'status', 'ACTIVE',
                     'meta_otimizacao', 'LEAD_GENERATION', 'campanha', (select camp from pg_temp._z_c)),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIO002', 'nome', 'ENSAIO | CONJUNTO B', 'status', 'ACTIVE',
                     'meta_otimizacao', 'LINK_CLICKS', 'campanha', (select camp from pg_temp._z_c))))::text;
insert into pg_temp._z_out (passo, linha)
select '2 conjuntos 2a', (public.trafego_conjuntos_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIO001', 'nome', 'ENSAIO | CONJUNTO A', 'status', 'ACTIVE',
                     'meta_otimizacao', 'LEAD_GENERATION', 'campanha', (select camp from pg_temp._z_c)),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIO002', 'nome', 'ENSAIO | CONJUNTO B', 'status', 'ACTIVE',
                     'meta_otimizacao', 'LINK_CLICKS', 'campanha', (select camp from pg_temp._z_c)))) - 'recusas')::text;
insert into pg_temp._z_out (passo, linha)
select '2 conjuntos 3a', (public.trafego_conjuntos_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIO001', 'nome', 'ENSAIO | CONJUNTO A RENOMEADO', 'status', 'ACTIVE',
                     'meta_otimizacao', 'LEAD_GENERATION', 'campanha', (select camp from pg_temp._z_c)),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIO002', 'nome', 'ENSAIO | CONJUNTO B',
                     'campanha', (select camp from pg_temp._z_c)))) - 'recusas')::text;
insert into pg_temp._z_out (passo, linha)
select '2 conjuntos estado', (select jsonb_agg(jsonb_build_object('id', conjunto_externa, 'nome', nome, 'status', status_plataforma,
                                                                    'otim', meta_otimizacao) order by conjunto_externa)
                                from mkt_trafego.conjuntos where conjunto_externa like 'ZZENSAIO%')::text;

-- 3. Anúncios
insert into pg_temp._z_out (passo, linha)
select '3 anuncios 1a', public.trafego_anuncios_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD1', 'nome', 'ENSAIO | AD 1', 'status', 'ACTIVE', 'conjunto', 'ZZENSAIO001',
                     'criativo', '990000000000001', 'video_id', '990000000000101', 'url_tags', 'utm_source=FB&utm_term={{ad.name}}'),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD2', 'nome', 'ENSAIO | AD 2', 'status', 'ACTIVE', 'conjunto', 'ZZENSAIO001',
                     'criativo', '990000000000001'),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD3', 'nome', 'ENSAIO | AD 3', 'status', 'PAUSED', 'conjunto', 'ZZENSAIO002',
                     'criativo', '990000000000002'),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD8', 'nome', 'x', 'conjunto', 'ZZ_NAO_EXISTE'),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD9', 'nome', 'x', 'conjunto', 'ZZENSAIO001', 'criativo', 'abc')))::text;
insert into pg_temp._z_out (passo, linha)
select '3 anuncios 2a', (public.trafego_anuncios_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD1', 'nome', 'ENSAIO | AD 1', 'status', 'ACTIVE', 'conjunto', 'ZZENSAIO001',
                     'criativo', '990000000000001', 'video_id', '990000000000101', 'url_tags', 'utm_source=FB&utm_term={{ad.name}}'),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD2', 'nome', 'ENSAIO | AD 2', 'status', 'ACTIVE', 'conjunto', 'ZZENSAIO001',
                     'criativo', '990000000000001'),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD3', 'nome', 'ENSAIO | AD 3', 'status', 'PAUSED', 'conjunto', 'ZZENSAIO002',
                     'criativo', '990000000000002'))) - 'recusas' - 'pendentes_miniatura')::text;

-- 4. Miniatura
insert into pg_temp._z_out (passo, linha)
select '4 miniatura', public.trafego_anuncio_miniatura_receber(jsonb_build_array(
  jsonb_build_object('criativo', '990000000000001', 'caminho', 'meta/000555/990000000000001.jpg'),
  jsonb_build_object('criativo', '990000000000002', 'erro', 'miniatura_http_403'),
  jsonb_build_object('criativo', 'x1', 'erro', 'y'),
  jsonb_build_object('criativo', '990000000000002', 'caminho', 'meta/000555/990000000000001.jpg'),
  jsonb_build_object('criativo', '990000000000009', 'erro', 'miniatura_rede'),
  jsonb_build_object('criativo', '990000000000002')))::text;
insert into pg_temp._z_out (passo, linha)
select '4 pendentes depois da miniatura', (public.trafego_anuncios_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD1', 'nome', 'ENSAIO | AD 1', 'conjunto', 'ZZENSAIO001', 'criativo', '990000000000001'),
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD3', 'nome', 'ENSAIO | AD 3', 'conjunto', 'ZZENSAIO002', 'criativo', '990000000000002')))
  -> 'pendentes_miniatura')::text;
update mkt_trafego.anuncios set miniatura_erro_em = now() - interval '25 hours' where criativo_externa = '990000000000002';
insert into pg_temp._z_out (passo, linha)
select '4 pendentes com a falha de 25 h atrás', (public.trafego_anuncios_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD3', 'nome', 'ENSAIO | AD 3', 'conjunto', 'ZZENSAIO002', 'criativo', '990000000000002')))
  -> 'pendentes_miniatura')::text;
insert into pg_temp._z_out (passo, linha)
select '4 criativo trocado', (public.trafego_anuncios_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'id', 'ZZENSAIOAD1', 'nome', 'ENSAIO | AD 1', 'conjunto', 'ZZENSAIO001', 'criativo', '990000000000003')))
  - 'recusas')::text;
insert into pg_temp._z_out (passo, linha)
select '4 estado das miniaturas', (select jsonb_agg(jsonb_build_object('id', anuncio_externa, 'criativo', criativo_externa,
                                     'caminho', miniatura_caminho, 'erro', miniatura_erro) order by anuncio_externa)
                                     from mkt_trafego.anuncios where anuncio_externa like 'ZZENSAIO%')::text;

-- 5. Desempenho por anúncio
insert into pg_temp._z_out (passo, linha)
select '5 desempenho 1a', public.trafego_desempenho_anuncio_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'anuncio', 'ZZENSAIOAD1', 'dia', (current_date - 1)::text, 'gasto', 12.345, 'impressoes', 1000,
                     'cliques_link', 30, 'cliques_total', 45, 'leads', 3, 'alcance', 810, 'frequencia', 1.23456, 'cliques_saida', 28,
                     'landing_page_views', 25, 'engajamento', 60, 'video_plays', 400, 'video_thruplay', 90, 'video_p25', 200,
                     'video_p50', 120, 'video_p75', 80, 'video_p100', 50),
  jsonb_build_object('plataforma', 'meta', 'anuncio', 'ZZ_NAO_EXISTE', 'dia', (current_date - 1)::text, 'gasto', 1),
  jsonb_build_object('plataforma', 'meta', 'anuncio', 'ZZENSAIOAD2', 'dia', 'ontem', 'gasto', 1),
  jsonb_build_object('plataforma', 'meta', 'anuncio', 'ZZENSAIOAD2', 'dia', (current_date - 1)::text, 'gasto', -1),
  jsonb_build_object('plataforma', 'meta', 'anuncio', 'ZZENSAIOAD2', 'dia', (current_date + 5)::text, 'gasto', 1)))::text;
insert into pg_temp._z_out (passo, linha)
select '5 desempenho 2a', (public.trafego_desempenho_anuncio_receber(jsonb_build_array(
  jsonb_build_object('plataforma', 'meta', 'anuncio', 'ZZENSAIOAD1', 'dia', (current_date - 1)::text, 'gasto', 12.345, 'impressoes', 1000,
                     'cliques_link', 30, 'cliques_total', 45, 'leads', 3, 'alcance', 810, 'frequencia', 1.23456, 'cliques_saida', 28,
                     'landing_page_views', 25, 'engajamento', 60, 'video_plays', 400, 'video_thruplay', 90, 'video_p25', 200,
                     'video_p50', 120, 'video_p75', 80, 'video_p100', 50))) - 'recusas')::text;
insert into pg_temp._z_out (passo, linha)
select '5 linhas do AD1', (select jsonb_build_object('linhas', count(*), 'gasto', max(d.gasto), 'frequencia', max(d.frequencia))
                             from mkt_trafego.desempenho_anuncio_dia d join mkt_trafego.anuncios a on a.id = d.anuncio_id
                            where a.anuncio_externa = 'ZZENSAIOAD1')::text;
insert into pg_temp._z_out (passo, linha)
select '5 teto do lote', (public.trafego_desempenho_anuncio_receber((select jsonb_agg(jsonb_build_object('x', g)) from generate_series(1, 5001) g)))::text;

-- 6. Quem pode o quê (42501 = sem permissão)
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $t$
declare f text; t text;
begin
  foreach f in array array['public.trafego_conjuntos_receber', 'public.trafego_anuncios_receber',
                           'public.trafego_desempenho_anuncio_receber', 'public.trafego_anuncio_miniatura_receber'] loop
    begin
      execute format('select %s(''[]''::jsonb)', f);
      insert into pg_temp._z_out (passo, linha) values ('6 anon ' || f, 'ERRO DO ENSAIO: executou');
    exception when others then insert into pg_temp._z_out (passo, linha) values ('6 anon ' || f, sqlstate);
    end;
  end loop;
  begin
    perform * from mkt_trafego.etapa_black('X | C1 | TEASER');
    insert into pg_temp._z_out (passo, linha) values ('6 anon etapa_black', 'ERRO DO ENSAIO: executou');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('6 anon etapa_black', sqlstate);
  end;
  foreach t in array array['mkt_trafego.conjuntos', 'mkt_trafego.anuncios', 'mkt_trafego.desempenho_anuncio_dia'] loop
    begin
      execute format('select count(*) from %s', t);
      insert into pg_temp._z_out (passo, linha) values ('6 anon ' || t, 'ERRO DO ENSAIO: leu');
    exception when others then insert into pg_temp._z_out (passo, linha) values ('6 anon ' || t, sqlstate);
    end;
  end loop;
end
$t$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role authenticated;
do $t$
declare f text; t text;
begin
  foreach f in array array['public.trafego_conjuntos_receber', 'public.trafego_anuncios_receber',
                           'public.trafego_desempenho_anuncio_receber', 'public.trafego_anuncio_miniatura_receber'] loop
    begin
      execute format('select %s(''[]''::jsonb)', f);
      insert into pg_temp._z_out (passo, linha) values ('6 authenticated ' || f, 'ERRO DO ENSAIO: executou');
    exception when others then insert into pg_temp._z_out (passo, linha) values ('6 authenticated ' || f, sqlstate);
    end;
  end loop;
  begin
    perform * from mkt_trafego.etapa_black('X | C1 | TEASER');
    insert into pg_temp._z_out (passo, linha) values ('6 authenticated etapa_black', 'ERRO DO ENSAIO: executou');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('6 authenticated etapa_black', sqlstate);
  end;
  foreach t in array array['mkt_trafego.conjuntos', 'mkt_trafego.anuncios', 'mkt_trafego.desempenho_anuncio_dia'] loop
    begin
      execute format('select count(*) from %s', t);
      insert into pg_temp._z_out (passo, linha) values ('6 authenticated ' || t, 'ERRO DO ENSAIO: leu');
    exception when others then insert into pg_temp._z_out (passo, linha) values ('6 authenticated ' || t, sqlstate);
    end;
  end loop;
end
$t$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
do $t$
declare f text; r jsonb;
begin
  foreach f in array array['public.trafego_conjuntos_receber', 'public.trafego_anuncios_receber',
                           'public.trafego_desempenho_anuncio_receber', 'public.trafego_anuncio_miniatura_receber'] loop
    begin
      execute format('select %s(''[]''::jsonb)', f) into r;
      insert into pg_temp._z_out (passo, linha) values ('6 service_role ' || f, (r ->> 'ok'));
    exception when others then insert into pg_temp._z_out (passo, linha) values ('6 service_role ' || f, 'ERRO DO ENSAIO: ' || sqlstate);
    end;
  end loop;
  begin
    perform * from mkt_trafego.etapa_black('X | C1 | TEASER');
    insert into pg_temp._z_out (passo, linha) values ('6 service_role etapa_black', 'ERRO DO ENSAIO: executou');
  exception when others then insert into pg_temp._z_out (passo, linha) values ('6 service_role etapa_black', sqlstate);
  end;
end
$t$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- 7. Liga e desliga e bucket
insert into pg_temp._z_out (passo, linha)
select '7 config', jsonb_build_object('existe', (select mkt_trafego.coleta_parametros()) ? 'meta_anuncio_contas',
                                      'valor', (select mkt_trafego.coleta_parametros()) -> 'meta_anuncio_contas')::text;
insert into pg_temp._z_out (passo, linha)
select '7 bucket', (select jsonb_build_object('public', b.public, 'limite', b.file_size_limit, 'tipos', b.allowed_mime_types)
                      from storage.buckets b where b.id = 'trafego-miniaturas')::text;

-- 8. Planos (colar no .explain.md)
create temp table _z_plan (l text) on commit drop;
do $e$
declare r record;
begin
  for r in execute $q$explain (analyze, buffers)
    select c.nome as campanha, e.etapa, e.subtipo, j.nome as conjunto, a.nome as anuncio, a.miniatura_caminho,
           sum(d.gasto) as gasto, sum(d.impressoes) as impressoes, sum(d.leads_plataforma) as leads
      from mkt_trafego.desempenho_anuncio_dia d
      join mkt_trafego.anuncios a on a.id = d.anuncio_id
      join mkt_trafego.conjuntos j on j.id = a.conjunto_id
      join mkt_trafego.campanhas c on c.id = j.campanha_id
      cross join lateral mkt_trafego.etapa_black(c.nome) e
     where d.dia between current_date - 30 and current_date
     group by 1, 2, 3, 4, 5, 6$q$ loop
    insert into pg_temp._z_plan values (r."QUERY PLAN");
  end loop;
end
$e$;
insert into pg_temp._z_out (passo, linha) select '8 explain leitura', (select string_agg(l, ' || ') from pg_temp._z_plan);
truncate pg_temp._z_plan;
do $e$
declare r record;
begin
  for r in execute $q$explain (analyze, buffers)
    select public.trafego_desempenho_anuncio_receber(jsonb_build_array(
      jsonb_build_object('plataforma', 'meta', 'anuncio', 'ZZENSAIOAD2', 'dia', (current_date - 1)::text, 'gasto', 3.5,
                         'impressoes', 100, 'cliques_link', 2)))$q$ loop
    insert into pg_temp._z_plan values (r."QUERY PLAN");
  end loop;
end
$e$;
insert into pg_temp._z_out (passo, linha) select '8 explain gravação', (select string_agg(l, ' || ') from pg_temp._z_plan);

-- 9. Nada existente mudou
insert into pg_temp._z_out (passo, linha)
  select '9 depois md5 desempenho_dia', md5(coalesce((select string_agg(d::text, '|' order by d.campanha_id, d.dia) from mkt_trafego.desempenho_dia d), ''));
insert into pg_temp._z_out (passo, linha)
  select '9 depois md5 funções atuais', md5((select string_agg(p.oid::regprocedure::text || p.prosrc || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)
    from pg_proc p where p.oid in ('public.trafego_desempenho_receber(jsonb)'::regprocedure, 'public.trafego_desempenho_total_receber(jsonb)'::regprocedure,
                                   'public.trafego_campanhas_receber(jsonb)'::regprocedure)));

-- ===== REVERSÃO (20261012120000_reversao.sql, sem a linha do bucket, que vai num bloco à parte) =====
-- Reversão de 20261012120000. Numa transação.
-- ANTES, nesta ordem:
--   1. Desligar a flag: update mkt_trafego.coleta_config set valor = null where chave = 'meta_anuncio_contas';
--      (com a flag nula a Edge trafego-meta não chama nenhuma função daqui; a coleta por campanha segue igual).
--   2. Se a Edge com anuncios.ts estiver publicada, publicar a versão anterior da trafego-meta (ou deixar a flag nula:
--      a versão nova com a flag nula não toca nada desta migration).
--   3. Esvaziar o bucket trafego-miniaturas pela Storage API ou pelo painel do Supabase (Storage > trafego-miniaturas >
--      selecionar tudo > Delete). NÃO VERIFICADO se o Supabase deste projeto bloqueia delete direto em storage.objects
--      e storage.buckets (há projetos com o gatilho storage.protect_delete). Se o último comando abaixo falhar por isso,
--      apagar o bucket pela Storage API (DELETE /storage/v1/bucket/trafego-miniaturas, com o bucket vazio).
-- O QUE SE PERDE: o cadastro de conjuntos e anúncios e o desempenho por anúncio (o por campanha, em desempenho_dia, fica).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

drop function if exists mkt_trafego.etapa_black(text);
drop function if exists public.trafego_anuncio_miniatura_receber(jsonb);
drop function if exists public.trafego_desempenho_anuncio_receber(jsonb);
drop function if exists public.trafego_anuncios_receber(jsonb);
drop function if exists public.trafego_conjuntos_receber(jsonb);
drop table if exists mkt_trafego.desempenho_anuncio_dia;
drop table if exists mkt_trafego.anuncios;
drop table if exists mkt_trafego.conjuntos;
delete from mkt_trafego.coleta_config where chave = 'meta_anuncio_contas';

-- ===== FIM DA REVERSÃO =====

-- 10. Depois da reversão
insert into pg_temp._z_out (passo, linha)
select '10 reversão objetos', ((to_regclass('mkt_trafego.conjuntos') is not null)::int + (to_regclass('mkt_trafego.anuncios') is not null)::int
  + (to_regclass('mkt_trafego.desempenho_anuncio_dia') is not null)::int + (to_regprocedure('mkt_trafego.etapa_black(text)') is not null)::int
  + (to_regprocedure('public.trafego_conjuntos_receber(jsonb)') is not null)::int + (to_regprocedure('public.trafego_anuncios_receber(jsonb)') is not null)::int
  + (to_regprocedure('public.trafego_desempenho_anuncio_receber(jsonb)') is not null)::int
  + (to_regprocedure('public.trafego_anuncio_miniatura_receber(jsonb)') is not null)::int)::text;
insert into pg_temp._z_out (passo, linha)
select '10 reversão config', (select count(*) from mkt_trafego.coleta_config where chave = 'meta_anuncio_contas')::text;
do $t$
begin
  delete from storage.buckets where id = 'trafego-miniaturas';
  insert into pg_temp._z_out (passo, linha) values ('10 reversão bucket', 'apagado');
exception when others then
  insert into pg_temp._z_out (passo, linha) values ('10 reversão bucket', sqlstate || ' ' || left(sqlerrm, 120));
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
