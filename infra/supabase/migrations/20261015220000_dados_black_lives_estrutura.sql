-- 20261015220000: aba "Lives" do Dashboard da Black Friday. Tabelas, cadastro das 9 lives, funções internas da coleta e as RPCs.
--
-- POR QUE (pedido do Victor Hugo em 15/10/2026, "faz aí, mete marcha"; desenho em Projetos/dashboard-black-friday/DESENHO-ABA-LIVES.md
-- no cérebro e infra/supabase/functions/black-youtube/README.md aqui): a aba mostra as lives do Marcio até a live de venda de
-- 03/11, com curva minuto a minuto, chat, comentários e cronograma. A lista vem de um CADASTRO por id (a busca pública da API
-- não enxerga as lives não listadas), a coleta é a Edge black-youtube (migration 20261015220100 liga o cron).
--
-- O QUE FAZ
--   a. 5 tabelas no schema dados (RLS ligada, sem política e sem grant: só as funções abaixo e o postgres da Edge entram):
--      black_lives (cadastro + última leitura da API + estado do chat), black_live_minuto (origem studio|api, seg),
--      black_live_foto (views/likes/comentários de hora em hora), black_live_chat (uma linha por mensagem, msg_id único),
--      black_live_comentario (comentários do vídeo, comment_id único).
--   b. Cadastro das 9 lives (horário de Brasília, -03).
--   c. 7 funções internas (dados.*, sem grant para ninguém): credenciais do Vault, janela da coleta, alvos da Edge, "precisa chamar agora?",
--      atualizar leitura da API, gravar amostra (espectadores + chat, idempotente por msg_id) e gravar comentários.
--   d. 5 RPCs públicas (security definer, search_path vazio, authenticated): dados_black_lives, dados_black_live_detalhe
--      (leitura, mesma trava de dados_black_trafego via dados.black_evento); dados_black_live_importar,
--      dados_black_live_cadastrar, dados_black_live_remover (escrita, só master via dados.black_evento_master).
--
-- AUTOR NO CHAT E NOS COMENTÁRIOS (CORRIGIDO): esta versão guardava o displayName e dizia que era decisão do Victor. Não existe
-- essa decisão (achado do pentester, 15/10). O desenho aprovado é só o texto, sem autor, apagado 90 dias depois da Black.
-- A coluna autor foi removida por 20261015230000. Comentário corrigido depois de aplicada; o código executável não mudou.
--
-- AS 5 PERGUNTAS
--   escala: ~10 lives; minuto ~100-150 linhas por live (~1,5 mil no total); chat 100-300 por live (milhares na live de venda);
--     foto de hora em hora (~6,5 mil em 30 dias). Com 10x continua pequeno. As RPCs de detalhe limitam chat (5000), comentários
--     (1000) e fotos (1000) por chamada.
--   índice: PKs (video_id, origem, seg) e (video_id, coletado_em) servem o minuto e a foto; black_live_chat e
--     black_live_comentario têm índice por (video_id, seg) e (video_id, publicado_em). Plano medido no .explain.md.
--   frequência: leitura sob demanda (aba aberta). A coleta é da migration 20261015220100.
--   repetição: dados_black_lives responde TODA a lista numa chamada; o detalhe é 1 chamada por live aberta.
--   reversão: 20261015220000_reversao.sql (drop das 5 RPCs, 7 funções e 5 tabelas). Nada existente é alterado.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regclass('dados.black_lives') is not null then
    raise exception '20261015220000: dados.black_lives já existe';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('dados_black_lives', 'dados_black_live_detalhe', 'dados_black_live_importar',
                                'dados_black_live_cadastrar', 'dados_black_live_remover')) then
    raise exception '20261015220000: alguma RPC dados_black_live* já existe';
  end if;
  if to_regprocedure('dados.black_evento(text)') is null or to_regprocedure('dados.black_evento_master(text)') is null
     or to_regprocedure('acesso.eh_master()') is null then
    raise exception '20261015220000: dependência ausente (dados.black_evento, dados.black_evento_master ou acesso.eh_master)';
  end if;
  if not exists (select 1 from dados.dashboards where chave = 'black-friday-2026-10' and modelo = 'jornada-captacao') then
    raise exception '20261015220000: dashboard black-friday-2026-10 não está no cadastro';
  end if;
end
$g$;

-- ─── 1. Tabelas ─────────────────────────────────────────────────────────────────────────────────────────────────
create table dados.black_lives (
  video_id text primary key check (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  chave text not null references dados.dashboards (chave),
  tipo text not null check (tipo in ('consultoria', 'produto', 'black')),
  data_prevista timestamptz not null,
  ativo boolean not null default true,
  -- última leitura da API (videos.list)
  titulo text,
  miniatura text,
  situacao text not null default 'a_agendar' check (situacao in ('realizada', 'ao_vivo', 'em_breve', 'a_agendar')),
  agendada_em timestamptz,
  inicio timestamptz,
  fim timestamptz,
  duracao_seg integer check (duracao_seg >= 0),
  views bigint,
  likes bigint,
  comentarios bigint,
  espectadores_agora integer,
  coletado_em timestamptz,
  -- estado da leitura do chat ao vivo (liveChat/messages)
  live_chat_id text,
  chat_page_token text,
  chat_lido_em timestamptz,
  comentarios_lidos_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index black_lives_chave_data_idx on dados.black_lives (chave, data_prevista) where ativo;

create table dados.black_live_minuto (
  video_id text not null references dados.black_lives (video_id) on delete cascade,
  origem text not null check (origem in ('studio', 'api')),
  seg integer not null check (seg >= 0),
  espectadores integer check (espectadores >= 0),   -- null: minuto com chat mas sem leitura de espectadores (origem api)
  chat integer check (chat >= 0),
  reacoes integer check (reacoes >= 0),             -- a API pública não entrega reações: origem api fica null
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (video_id, origem, seg)
);

-- append-only: uma linha por leitura de hora em hora, nunca atualizada (por isso sem atualizado_em)
create table dados.black_live_foto (
  video_id text not null references dados.black_lives (video_id) on delete cascade,
  coletado_em timestamptz not null default now(),
  views bigint,
  likes bigint,
  comentarios bigint,
  primary key (video_id, coletado_em)
);

-- seg pode ser negativo (mensagem de antes do início da live). Guardava o displayName do autor (sem decisão do Victor; coluna removida em 20261015230000).
create table dados.black_live_chat (
  msg_id text primary key,
  video_id text not null references dados.black_lives (video_id) on delete cascade,
  seg integer not null,
  publicado_em timestamptz not null,
  autor text,
  texto text not null,
  criado_em timestamptz not null default now()
);
create index black_live_chat_video_seg_idx on dados.black_live_chat (video_id, seg);

create table dados.black_live_comentario (
  comment_id text primary key,
  video_id text not null references dados.black_lives (video_id) on delete cascade,
  publicado_em timestamptz not null,
  autor text,
  texto text not null,
  curtidas integer not null default 0,
  respostas integer not null default 0,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index black_live_comentario_video_pub_idx on dados.black_live_comentario (video_id, publicado_em);

-- RLS ligada e nenhuma política: ninguém lê pela API de tabelas. Entram só as funções security definer abaixo e o postgres da Edge.
alter table dados.black_lives enable row level security;
alter table dados.black_live_minuto enable row level security;
alter table dados.black_live_foto enable row level security;
alter table dados.black_live_chat enable row level security;
alter table dados.black_live_comentario enable row level security;
revoke all on dados.black_lives, dados.black_live_minuto, dados.black_live_foto, dados.black_live_chat,
              dados.black_live_comentario from public, anon, authenticated, service_role;

-- ─── 2. Cadastro das 9 lives (horário de Brasília, -03) ─────────────────────────────────────────────────────────
insert into dados.black_lives (video_id, chave, tipo, data_prevista) values
  ('fpgmDwBKVcQ', 'black-friday-2026-10', 'consultoria', timestamptz '2026-10-06 19:30:00-03'),
  ('Hdsg23VbfHI', 'black-friday-2026-10', 'produto',     timestamptz '2026-10-08 19:30:00-03'),
  ('t0PLYUORt1E', 'black-friday-2026-10', 'consultoria', timestamptz '2026-10-13 19:30:00-03'),
  ('A9d6HjegnTk', 'black-friday-2026-10', 'produto',     timestamptz '2026-10-15 19:30:00-03'),
  ('iFH3cD_G3n8', 'black-friday-2026-10', 'consultoria', timestamptz '2026-10-20 20:00:00-03'),
  ('KhqVjpL5Wvs', 'black-friday-2026-10', 'produto',     timestamptz '2026-10-22 19:30:00-03'),
  ('bN2XvcTwvWA', 'black-friday-2026-10', 'consultoria', timestamptz '2026-10-27 20:00:00-03'),
  ('m6zoEBBw1bQ', 'black-friday-2026-10', 'produto',     timestamptz '2026-10-29 19:30:00-03'),
  ('S1FILUs1ti0', 'black-friday-2026-10', 'black',       timestamptz '2026-11-03 20:00:00-03')
on conflict (video_id) do nothing;

-- ─── 3. Funções internas (só o postgres da Edge executa) ───────────────────────────────────────────────────────
-- Chave do header da Edge e chave da API do YouTube, lidas do Vault. Sem Vault (banco local), nulas.
create function dados.black_youtube_credenciais() returns table (chave text, api_key text)
language plpgsql stable set search_path = '' as $$
begin
  if to_regclass('vault.decrypted_secrets') is null then
    return query select null::text, null::text;
    return;
  end if;
  return query execute
    'select (select s.decrypted_secret from vault.decrypted_secrets s where s.name = ''dados_black_youtube_chave''),
            (select s.decrypted_secret from vault.decrypted_secrets s where s.name = ''dados_black_youtube_api_key'')';
end
$$;

-- Janela da live: 15 min antes do horário previsto até 3 h depois, ou enquanto a última leitura disse "ao_vivo".
create function dados.black_live_na_janela(p_prevista timestamptz, p_situacao text) returns boolean
language sql stable set search_path = '' as $$
  select p_situacao = 'ao_vivo'
      or (now() >= p_prevista - interval '15 minutes' and now() <= p_prevista + interval '3 hours')
$$;

-- O cron roda todo minuto, mas só chama a Edge quando precisa: dentro da janela de alguma live, ou a cada 10 minutos
-- (leitura de cadastro, foto e comentários). Fora disso o minuto passa sem chamada nenhuma.
create function dados.black_live_pede_chamada() returns boolean
language sql stable set search_path = '' as $$
  select (extract(minute from now() at time zone 'UTC')::int % 10 = 0)
      or exists (select 1 from dados.black_lives l
                  where l.ativo and dados.black_live_na_janela(l.data_prevista, l.situacao))
$$;

-- O que a Edge precisa saber das lives ativas.
create function dados.black_live_alvos() returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'video_id', l.video_id,
           'situacao', l.situacao,
           'data_prevista', l.data_prevista,
           'na_janela', dados.black_live_na_janela(l.data_prevista, l.situacao),
           'inicio', l.inicio,
           'live_chat_id', l.live_chat_id,
           'chat_page_token', l.chat_page_token,
           'comentarios_devidos', (l.comentarios_lidos_em is null or l.comentarios_lidos_em < now() - interval '55 minutes')
         ) order by l.data_prevista), '[]'::jsonb)
    from dados.black_lives l
   where l.ativo
$$;

-- Grava a leitura do videos.list. p_itens: [{video_id, encontrado, titulo, miniatura, situacao, agendada_em, inicio, fim,
-- duracao_seg, views, likes, comentarios, espectadores_agora, live_chat_id}]. Vídeo que a API não devolveu (encontrado=false)
-- vira 'a_agendar' só se ainda era 'em_breve' ou 'a_agendar'; realizada e ao_vivo não regridem. A foto entra se a última
-- tem mais de 55 min.
create function dados.black_live_atualizar(p_itens jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_atualizadas int; v_fotos int;
begin
  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) > 50 then
    raise exception 'p_itens deve ser lista de até 50' using errcode = '22023';
  end if;
  with x as (
    select * from jsonb_to_recordset(p_itens) as t(
      video_id text, encontrado boolean, titulo text, miniatura text, situacao text, agendada_em timestamptz,
      inicio timestamptz, fim timestamptz, duracao_seg integer, views bigint, likes bigint, comentarios bigint,
      espectadores_agora integer, live_chat_id text)
  )
  update dados.black_lives l
     set titulo = case when x.encontrado then coalesce(x.titulo, l.titulo) else l.titulo end,
         miniatura = case when x.encontrado then coalesce(x.miniatura, l.miniatura) else l.miniatura end,
         situacao = case when x.encontrado then x.situacao
                         when l.situacao in ('em_breve', 'a_agendar') then 'a_agendar' else l.situacao end,
         agendada_em = case when x.encontrado then x.agendada_em else l.agendada_em end,
         inicio = case when x.encontrado then x.inicio else l.inicio end,
         fim = case when x.encontrado then x.fim else l.fim end,
         duracao_seg = case when x.encontrado then x.duracao_seg else l.duracao_seg end,
         views = case when x.encontrado then x.views else l.views end,
         likes = case when x.encontrado then x.likes else l.likes end,
         comentarios = case when x.encontrado then x.comentarios else l.comentarios end,
         espectadores_agora = case when x.encontrado then x.espectadores_agora else null end,
         chat_page_token = case when x.encontrado and x.live_chat_id is not null
                                     and x.live_chat_id is distinct from l.live_chat_id then null else l.chat_page_token end,
         live_chat_id = case when x.encontrado and x.live_chat_id is not null then x.live_chat_id else l.live_chat_id end,
         coletado_em = now(),
         atualizado_em = now()
    from x
   where l.video_id = x.video_id and l.ativo;
  get diagnostics v_atualizadas = row_count;
  insert into dados.black_live_foto (video_id, coletado_em, views, likes, comentarios)
  select x.video_id, now(), x.views, x.likes, x.comentarios
    from jsonb_to_recordset(p_itens) as x(video_id text, encontrado boolean, views bigint, likes bigint, comentarios bigint)
    join dados.black_lives l on l.video_id = x.video_id and l.ativo
   where x.encontrado
     and not exists (select 1 from dados.black_live_foto f
                      where f.video_id = x.video_id and f.coletado_em > now() - interval '55 minutes')
  on conflict do nothing;
  get diagnostics v_fotos = row_count;
  return jsonb_build_object('atualizadas', v_atualizadas, 'fotos', v_fotos);
end
$$;

-- Grava uma amostra: espectadores do minuto (origem api) e as mensagens do chat (idempotente por msg_id). O chat do minuto
-- da linha api é recontado do que está guardado (não soma). p_chat_id nulo não mexe no estado do chat (serve à carga do
-- histórico). p_mensagens: [{msg_id, seg, publicado_em, autor, texto}].
create function dados.black_live_gravar_amostra(
  p_video_id text, p_seg integer, p_espectadores integer, p_mensagens jsonb, p_page_token text, p_chat_id text
) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_novas int := 0;
begin
  if not exists (select 1 from dados.black_lives where video_id = p_video_id) then
    raise exception 'live não cadastrada' using errcode = 'P0002';
  end if;
  if p_mensagens is not null and (jsonb_typeof(p_mensagens) <> 'array' or jsonb_array_length(p_mensagens) > 5000) then
    raise exception 'p_mensagens deve ser lista de até 5000' using errcode = '22023';
  end if;
  if p_seg is not null and p_seg >= 0 and p_espectadores is not null then
    insert into dados.black_live_minuto (video_id, origem, seg, espectadores)
    values (p_video_id, 'api', (p_seg / 60) * 60, p_espectadores)
    on conflict (video_id, origem, seg) do update set espectadores = excluded.espectadores, atualizado_em = now();
  end if;
  if p_mensagens is not null and jsonb_array_length(p_mensagens) > 0 then
    with m as (
      select * from jsonb_to_recordset(p_mensagens) as t(msg_id text, seg integer, publicado_em timestamptz, autor text, texto text)
       where msg_id is not null and seg is not null and publicado_em is not null and texto is not null
    ), ins as (
      insert into dados.black_live_chat (msg_id, video_id, seg, publicado_em, autor, texto)
      select m.msg_id, p_video_id, m.seg, m.publicado_em, left(m.autor, 200), left(m.texto, 1000) from m
      on conflict (msg_id) do nothing
      returning 1
    )
    select count(*) into v_novas from ins;
    -- recontagem dos minutos tocados (só seg >= 0; mensagem de antes do início não entra na curva)
    insert into dados.black_live_minuto (video_id, origem, seg, chat)
    select p_video_id, 'api', mm.min_seg,
           (select count(*)::int from dados.black_live_chat c
             where c.video_id = p_video_id and c.seg >= mm.min_seg and c.seg < mm.min_seg + 60)
      from (select distinct (t.seg / 60) * 60 as min_seg
              from jsonb_to_recordset(p_mensagens) as t(seg integer) where t.seg >= 0) mm
    on conflict (video_id, origem, seg) do update set chat = excluded.chat, atualizado_em = now();
  end if;
  if p_chat_id is not null then
    update dados.black_lives
       set chat_page_token = p_page_token, live_chat_id = p_chat_id, chat_lido_em = now(), atualizado_em = now()
     where video_id = p_video_id;
  end if;
  return jsonb_build_object('mensagens_novas', v_novas);
end
$$;

-- Grava os comentários do vídeo (commentThreads). p_itens: [{comment_id, publicado_em, autor, texto, curtidas, respostas}].
create function dados.black_live_gravar_comentarios(p_video_id text, p_itens jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_n int := 0;
begin
  if not exists (select 1 from dados.black_lives where video_id = p_video_id) then
    raise exception 'live não cadastrada' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) > 2000 then
    raise exception 'p_itens deve ser lista de até 2000' using errcode = '22023';
  end if;
  insert into dados.black_live_comentario (comment_id, video_id, publicado_em, autor, texto, curtidas, respostas)
  select t.comment_id, p_video_id, t.publicado_em, left(t.autor, 200), left(t.texto, 5000),
         coalesce(t.curtidas, 0), coalesce(t.respostas, 0)
    from jsonb_to_recordset(p_itens) as t(comment_id text, publicado_em timestamptz, autor text, texto text, curtidas integer, respostas integer)
   where t.comment_id is not null and t.publicado_em is not null and t.texto is not null
  on conflict (comment_id) do update
     set texto = excluded.texto, curtidas = excluded.curtidas, respostas = excluded.respostas, atualizado_em = now();
  get diagnostics v_n = row_count;
  update dados.black_lives set comentarios_lidos_em = now() where video_id = p_video_id;
  return jsonb_build_object('comentarios', v_n);
end
$$;

revoke all on function dados.black_youtube_credenciais(), dados.black_live_na_janela(timestamptz, text),
  dados.black_live_pede_chamada(), dados.black_live_alvos(), dados.black_live_atualizar(jsonb),
  dados.black_live_gravar_amostra(text, integer, integer, jsonb, text, text),
  dados.black_live_gravar_comentarios(text, jsonb)
  from public, anon, authenticated, service_role;

-- ─── 4. RPCs de leitura ────────────────────────────────────────────────────────────────────────────────────────
create function public.dados_black_lives(p_chave text) returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare
  d dados.dashboards := dados.black_evento(p_chave);   -- 42501 sem acesso, P0002 fora da Black
  r jsonb;
begin
  with l as (
    select * from dados.black_lives x where x.chave = d.chave and x.ativo
  ), lo as (
    select l.*, exists (select 1 from dados.black_live_minuto s where s.video_id = l.video_id and s.origem = 'studio') as tem_studio
      from l
  ), m as (   -- minutos da origem preferida: studio se houver, senão api
    select lo.video_id, x.seg, x.espectadores, x.chat, x.reacoes
      from lo join dados.black_live_minuto x
        on x.video_id = lo.video_id and x.origem = case when lo.tem_studio then 'studio' else 'api' end
  ), mp as (
    select video_id, max(espectadores) as pico from m group by video_id
  ), ag as (
    select m.video_id, mp.pico,
           min(m.seg) filter (where m.espectadores = mp.pico) as pico_seg,
           min(m.seg) filter (where m.espectadores >= mp.pico * 0.9) as sala_cheia_seg,
           (array_agg(m.espectadores order by m.seg desc) filter (where m.espectadores is not null))[1] as ultimo,
           sum(m.chat) as chat_total, sum(m.reacoes) as reacoes_total
      from m join mp using (video_id) group by m.video_id, mp.pico
  ), ch as (
    select c.video_id, count(*) as n from dados.black_live_chat c join l using (video_id) group by c.video_id
  )
  select jsonb_build_object('lives', coalesce(jsonb_agg(jsonb_build_object(
      'video_id', lo.video_id, 'tipo', lo.tipo, 'data_prevista', lo.data_prevista, 'titulo', lo.titulo,
      'miniatura', lo.miniatura, 'situacao', lo.situacao, 'agendada_em', lo.agendada_em, 'inicio', lo.inicio,
      'fim', lo.fim, 'duracao_seg', lo.duracao_seg, 'views', lo.views, 'likes', lo.likes,
      'comentarios', lo.comentarios, 'coletado_em', lo.coletado_em, 'espectadores_agora', lo.espectadores_agora,
      'tem_studio', lo.tem_studio, 'pico', ag.pico, 'pico_seg', ag.pico_seg, 'sala_cheia_seg', ag.sala_cheia_seg,
      'ultimo_espectadores', ag.ultimo, 'chat_total', ag.chat_total, 'reacoes_total', ag.reacoes_total,
      'chat_guardado', coalesce(ch.n, 0)
    ) order by lo.data_prevista, lo.video_id), '[]'::jsonb))
    into r
    from lo
    left join ag on ag.video_id = lo.video_id
    left join ch on ch.video_id = lo.video_id;
  return r;
end
$function$;

create function public.dados_black_live_detalhe(p_chave text, p_video_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare
  d dados.dashboards := dados.black_evento(p_chave);
  v_org text;
  r jsonb;
begin
  if not exists (select 1 from dados.black_lives l where l.video_id = p_video_id and l.chave = d.chave and l.ativo) then
    raise exception 'live não cadastrada' using errcode = 'P0002';
  end if;
  v_org := case when exists (select 1 from dados.black_live_minuto s where s.video_id = p_video_id and s.origem = 'studio')
                then 'studio' else 'api' end;
  select jsonb_build_object(
    'minutos', coalesce((select jsonb_agg(jsonb_build_object('seg', x.seg, 'espectadores', x.espectadores, 'chat', x.chat,
                'reacoes', x.reacoes, 'origem', x.origem) order by x.seg)
                from dados.black_live_minuto x where x.video_id = p_video_id and x.origem = v_org), '[]'::jsonb),
    'chat', coalesce((select jsonb_agg(jsonb_build_object('seg', c.seg, 'publicado_em', c.publicado_em, 'autor', c.autor,
                'texto', c.texto) order by c.seg, c.publicado_em, c.msg_id)
                from (select * from dados.black_live_chat where video_id = p_video_id order by seg, publicado_em, msg_id limit 5000) c), '[]'::jsonb),
    'comentarios', coalesce((select jsonb_agg(jsonb_build_object('publicado_em', k.publicado_em, 'autor', k.autor,
                'texto', k.texto, 'curtidas', k.curtidas, 'respostas', k.respostas) order by k.publicado_em, k.comment_id)
                from (select * from dados.black_live_comentario where video_id = p_video_id order by publicado_em desc, comment_id limit 1000) k), '[]'::jsonb),
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('coletado_em', f.coletado_em, 'views', f.views, 'likes', f.likes,
                'comentarios', f.comentarios) order by f.coletado_em)
                from (select * from dados.black_live_foto where video_id = p_video_id order by coletado_em desc limit 1000) f), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

-- ─── 5. RPCs de escrita (só master) ────────────────────────────────────────────────────────────────────────────
-- p_linhas: [{seg, espectadores, chat, reacoes}] do liveViewership_*.csv do Studio. confirmar=false devolve a prévia sem
-- gravar; true substitui as linhas studio do vídeo numa transação. Idempotente: se as linhas já são exatamente essas,
-- não escreve nada (alteradas = 0, gravado = false).
create function public.dados_black_live_importar(p_chave text, p_video_id text, p_linhas jsonb, p_confirmar boolean)
returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare
  d dados.dashboards := dados.black_evento_master(p_chave);   -- 42501 se não for master, P0002 fora da Black
  v_n int; v_invalidas int; v_dup int; v_alt int; v_exist int;
  v_pico int; v_pico_seg int; v_dur int;
begin
  if not exists (select 1 from dados.black_lives l where l.video_id = p_video_id and l.chave = d.chave and l.ativo) then
    raise exception 'live não cadastrada' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_linhas) is distinct from 'array' then
    raise exception 'p_linhas deve ser uma lista' using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_linhas);
  if v_n < 1 or v_n > 2000 then
    raise exception 'p_linhas deve ter de 1 a 2000 linhas' using errcode = '22023';
  end if;
  -- toda linha: objeto com seg e espectadores inteiros >= 0; chat e reacoes inteiros >= 0 ou ausentes
  select count(*) into v_invalidas
    from jsonb_array_elements(p_linhas) e
   where jsonb_typeof(e) <> 'object'
      or jsonb_typeof(e -> 'seg') is distinct from 'number' or (e ->> 'seg') !~ '^[0-9]{1,7}$'
      or jsonb_typeof(e -> 'espectadores') is distinct from 'number' or (e ->> 'espectadores') !~ '^[0-9]{1,7}$'
      or (e ? 'chat' and (jsonb_typeof(e -> 'chat') is distinct from 'number' or (e ->> 'chat') !~ '^[0-9]{1,7}$'))
      or (e ? 'reacoes' and (jsonb_typeof(e -> 'reacoes') is distinct from 'number' or (e ->> 'reacoes') !~ '^[0-9]{1,7}$'));
  if v_invalidas > 0 then
    raise exception 'p_linhas tem % linha(s) inválida(s)', v_invalidas using errcode = '22023';
  end if;

  -- sem tabela temporária (a função roda mais de uma vez na mesma transação nos ensaios): o CTE "n" repete em cada consulta
  with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores
               from jsonb_array_elements(p_linhas) e)
  select count(*) - count(distinct seg), max(espectadores), max(seg) + 60,
         min(seg) filter (where espectadores = (select max(espectadores) from n))
    into v_dup, v_pico, v_dur, v_pico_seg from n;
  if v_dup > 0 then
    raise exception 'p_linhas tem seg repetido' using errcode = '22023';
  end if;
  select count(*) into v_exist from dados.black_live_minuto where video_id = p_video_id and origem = 'studio';
  with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores,
                    coalesce((e ->> 'chat')::int, 0) as chat, coalesce((e ->> 'reacoes')::int, 0) as reacoes
               from jsonb_array_elements(p_linhas) e)
  select count(*) into v_alt
    from n
    full join (select seg, espectadores, chat, reacoes from dados.black_live_minuto
                where video_id = p_video_id and origem = 'studio') o using (seg)
   where n.espectadores is null or o.espectadores is null
      or n.espectadores is distinct from o.espectadores or n.chat is distinct from o.chat or n.reacoes is distinct from o.reacoes;

  if p_confirmar is true and v_alt > 0 then
    delete from dados.black_live_minuto where video_id = p_video_id and origem = 'studio';
    insert into dados.black_live_minuto (video_id, origem, seg, espectadores, chat, reacoes)
    select p_video_id, 'studio', (e ->> 'seg')::int, (e ->> 'espectadores')::int,
           coalesce((e ->> 'chat')::int, 0), coalesce((e ->> 'reacoes')::int, 0)
      from jsonb_array_elements(p_linhas) e;
    update dados.black_lives set atualizado_em = now() where video_id = p_video_id;
  end if;
  return jsonb_build_object('linhas', v_n, 'pico', v_pico, 'pico_seg', v_pico_seg, 'duracao_seg', v_dur,
                            'existentes', v_exist, 'alteradas', v_alt, 'gravado', (p_confirmar is true and v_alt > 0));
end
$function$;

create function public.dados_black_live_cadastrar(p_chave text, p_video_id text, p_tipo text, p_data_prevista timestamptz)
returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare
  d dados.dashboards := dados.black_evento_master(p_chave);
  v_chave_atual text;
begin
  if p_video_id is null or p_video_id !~ '^[A-Za-z0-9_-]{11}$' then
    raise exception 'video_id inválido (11 caracteres do YouTube)' using errcode = '22023';
  end if;
  if p_tipo is null or p_tipo not in ('consultoria', 'produto', 'black') then
    raise exception 'tipo inválido (consultoria, produto ou black)' using errcode = '22023';
  end if;
  if p_data_prevista is null then
    raise exception 'data prevista obrigatória' using errcode = '22023';
  end if;
  select chave into v_chave_atual from dados.black_lives where video_id = p_video_id;
  if v_chave_atual is not null and v_chave_atual <> d.chave then
    raise exception 'live cadastrada em outro dashboard' using errcode = '22023';
  end if;
  insert into dados.black_lives (video_id, chave, tipo, data_prevista)
  values (p_video_id, d.chave, p_tipo, p_data_prevista)
  on conflict (video_id) do update
     set tipo = excluded.tipo, data_prevista = excluded.data_prevista, ativo = true, atualizado_em = now();
  return (select jsonb_build_object('video_id', l.video_id, 'tipo', l.tipo, 'data_prevista', l.data_prevista,
                                    'ativo', l.ativo, 'situacao', l.situacao)
            from dados.black_lives l where l.video_id = p_video_id);
end
$function$;

create function public.dados_black_live_remover(p_chave text, p_video_id text) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare
  d dados.dashboards := dados.black_evento_master(p_chave);
  v_n int;
begin
  update dados.black_lives set ativo = false, atualizado_em = now()
   where video_id = p_video_id and chave = d.chave;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'live não cadastrada' using errcode = 'P0002';
  end if;
  return jsonb_build_object('video_id', p_video_id, 'ativo', false);
end
$function$;

revoke all on function public.dados_black_lives(text), public.dados_black_live_detalhe(text, text),
  public.dados_black_live_importar(text, text, jsonb, boolean),
  public.dados_black_live_cadastrar(text, text, text, timestamptz),
  public.dados_black_live_remover(text, text) from public, anon, service_role;
grant execute on function public.dados_black_lives(text), public.dados_black_live_detalhe(text, text),
  public.dados_black_live_importar(text, text, jsonb, boolean),
  public.dados_black_live_cadastrar(text, text, text, timestamptz),
  public.dados_black_live_remover(text, text) to authenticated;

-- ─── 6. Conferência (aborta se algo nasceu aberto ou fora do padrão) ──────────────────────────────────────────────
do $confere$
declare
  f record; t text;
  v_publicas text[] := array['dados_black_lives', 'dados_black_live_detalhe', 'dados_black_live_importar',
                             'dados_black_live_cadastrar', 'dados_black_live_remover'];
  v_internas text[] := array['black_youtube_credenciais', 'black_live_na_janela', 'black_live_pede_chamada', 'black_live_alvos',
                             'black_live_atualizar', 'black_live_gravar_amostra', 'black_live_gravar_comentarios'];
begin
  foreach t in array array['black_lives', 'black_live_minuto', 'black_live_foto', 'black_live_chat', 'black_live_comentario'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid = ('dados.' || t)::regclass) then
      raise exception '20261015220000: RLS desligada em dados.%', t;
    end if;
    if has_table_privilege('anon', 'dados.' || t, 'select, insert, update, delete')
       or has_table_privilege('authenticated', 'dados.' || t, 'select, insert, update, delete') then
      raise exception '20261015220000: anon ou authenticated com privilégio em dados.%', t;
    end if;
  end loop;
  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig
             from pg_proc p
            where (p.pronamespace = 'public'::regnamespace and p.proname = any (v_publicas))
               or (p.pronamespace = 'dados'::regnamespace and p.proname = any (v_internas)) loop
    if not (f.proconfig @> array['search_path=""']) then raise exception '20261015220000: % sem search_path vazio', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') then raise exception '20261015220000: anon executa %', f.sig; end if;
    if has_function_privilege('service_role', f.sig, 'execute') then raise exception '20261015220000: service_role executa %', f.sig; end if;
    if (f.pronamespace = 'public'::regnamespace) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261015220000: grant de authenticated errado em %', f.sig;
    end if;
    if f.pronamespace = 'public'::regnamespace and not f.prosecdef then
      raise exception '20261015220000: % deveria ser security definer', f.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (v_publicas)) <> 5
     or (select count(*) from pg_proc p where p.pronamespace = 'dados'::regnamespace and p.proname = any (v_internas)) <> 7 then
    raise exception '20261015220000: esperava 5 funções públicas e 7 internas';
  end if;
  if (select count(*) from dados.black_lives where chave = 'black-friday-2026-10' and ativo) <> 9 then
    raise exception '20261015220000: esperava 9 lives no cadastro';
  end if;
end
$confere$;
