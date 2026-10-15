-- Reversão de 20261015230000 (aba Lives sem autor): tira o cron e a função de expurgo, devolve as 3 funções que citavam autor
-- e recria a coluna autor nas duas tabelas. ATENÇÃO: a coluna volta VAZIA. O nome de exibição que existia foi apagado de propósito
-- e não é recuperável por aqui (só de backup do banco). Reverter só faz sentido se houver decisão do Victor de guardar o autor.
-- Se a Edge black-youtube já tiver sido republicada sem autor, as mensagens novas entram com autor nulo (a função antiga aceita).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

select cron.unschedule('black-youtube-expurgo') where exists (select 1 from cron.job where jobname = 'black-youtube-expurgo');
drop function if exists dados.black_live_expurgar(timestamptz);

alter table dados.black_live_chat add column if not exists autor text;
alter table dados.black_live_comentario add column if not exists autor text;

-- Grava uma amostra: espectadores do minuto (origem api) e as mensagens do chat (idempotente por msg_id). O chat do minuto
-- da linha api é recontado do que está guardado (não soma). p_chat_id nulo não mexe no estado do chat (serve à carga do
-- histórico). p_mensagens: [{msg_id, seg, publicado_em, autor, texto}].
create or replace function dados.black_live_gravar_amostra(
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
create or replace function dados.black_live_gravar_comentarios(p_video_id text, p_itens jsonb) returns jsonb
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

create or replace function public.dados_black_live_detalhe(p_chave text, p_video_id text) returns jsonb
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

do $c$
begin
  if exists (select 1 from cron.job where jobname = 'black-youtube-expurgo') or to_regprocedure('dados.black_live_expurgar(timestamptz)') is not null
     or (select count(*) from information_schema.columns where table_schema = 'dados'
            and table_name in ('black_live_chat', 'black_live_comentario') and column_name = 'autor') <> 2 then
    raise exception 'reversão de 20261015230000 incompleta';
  end if;
end
$c$;
