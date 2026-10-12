-- 20261012120000: Meta Ads por conjunto e por anúncio (painel da Black Friday)
--
-- STATUS: NÃO APLICADA. Ver 20261012120000.explain.md (conferências do estado vivo C1 a C17 ainda NÃO FEITAS; a C3,
--   colunas e checks vivos de mkt_trafego.desempenho_dia, é obrigatória antes de aplicar).
-- ARQUIVO EM UTF-8: o translate da mkt_trafego.etapa_black usa um mapa de letras acentuadas. Se o arquivo for
--   regravado em outra codificação, o termo acentuado deixa de casar (ex.: "Manifésto"). O ensaio confere.
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
--   3. mkt_trafego.etapa_black(nome): etapa (C1, C2, C3), subtipo e conflito (mais de um código) pelo nome da campanha,
--      calculados na leitura e nunca gravados. Sem grant para ninguém (interna; a RPC de leitura do dashboard é de outra
--      fase). Campanha da Black, para o dashboard, = nome com o termo BF26 (decisão do Victor, 12/10/2026).
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

-- 3. Etapa da Black pelo nome da campanha (regra final do Victor, 12/10/2026). A regra mora SÓ aqui: para trocar,
--    create or replace com a mesma assinatura numa migration nova.
--    C1 = termo C1 + TEASER, MANIFESTO, REELS ou CORTES. C2 = termo C2 + CONSULTORIA ou ISCA (só no singular: ISCAS não
--    casa). C3 = termo C3 + LEADS. ANTECIPAÇÃO não é subtipo (saiu da lista em 12/10/2026).
--    Como casa: o nome é dividido por "|", cada termo sem espaço nas pontas; o termo INTEIRO tem que ser o código
--    (C1, C2, C3) ou o subtipo (CPF01 não vira C1; "C2 ISCAS" num termo só não casa). Acento e maiúscula não importam:
--    o translate tira o acento ANTES do upper (não depende do ctype do banco). O subtipo sai na grafia oficial.
--    Casos especiais:
--      - código sem subtipo da etapa: etapa preenchida e subtipo nulo (DECIDIDO pelo Victor em 12/10/2026);
--      - mais de um subtipo da etapa: subtipo nulo, sem precedência (PENDENTE: o Victor ainda vai ver);
--      - mais de um código: etapa e subtipo nulos e conflito = true. O dashboard mostra o conflito à parte do
--        "sem etapa" comum (conflito = false). O mesmo código repetido não é conflito.
create or replace function mkt_trafego.etapa_black(p_nome text)
 returns table (etapa text, subtipo text, conflito boolean)
 language sql
 immutable parallel safe
 set search_path to ''
as $function$
  with regra (etapa, chave, rotulo) as (
    values ('C1', 'TEASER', 'TEASER'), ('C1', 'MANIFESTO', 'MANIFESTO'), ('C1', 'REELS', 'REELS'), ('C1', 'CORTES', 'CORTES'),
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
  -- código sem subtipo (ex.: "X | C3 | LEAD"): etapa preenchida e subtipo nulo, para o gasto não sumir da etapa (DECIDIDO)
  select case when (select count(*) from cod) = 1 then (select c.etapa from cod c) end as etapa,
         case when (select count(*) from cod) = 1 and (select count(*) from sub) = 1 then (select s.rotulo from sub s) end as subtipo,
         (select count(*) from cod) > 1 as conflito
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
