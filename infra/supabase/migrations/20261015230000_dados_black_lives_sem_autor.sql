-- 20261015230000: aba "Lives" da Black sem autor + expurgo do texto 90 dias depois da Black.
--
-- POR QUE (achado do pentester, 15/10/2026): 20261015220000 e a Edge black-youtube guardavam o displayName de quem escreveu no chat
-- e nos comentários, atribuindo isso a "decisão do Victor". Não existe essa decisão. O desenho aprovado
-- (Projetos/dashboard-black-friday/DESENHO-ABA-LIVES.md) guarda só o TEXTO, sem autor, e o apaga 90 dias depois da Black
-- (03/11/2026), ou seja, a partir de 01/02/2027. Esta migration alinha o banco ao desenho. A Edge deixa de ler o autor no mesmo
-- pacote (functions/black-youtube).
--
-- O QUE FAZ
--   a. Zera o autor que já foi gravado (update ... set autor = null) e REMOVE a coluna autor de black_live_chat e
--      black_live_comentario. Escolhi remover (e não só zerar): sem coluna, nenhuma função, carga ou tela futura consegue gravar
--      ou devolver nome por engano; a RPC antiga também deixaria de funcionar contra a tabela, o que é o comportamento certo.
--   b. Recria sem autor: black_live_gravar_amostra, black_live_gravar_comentarios (recordset sem autor: chave "autor" que ainda
--      venha no JSON é ignorada, então a Edge antiga continua funcionando durante a troca) e a RPC dados_black_live_detalhe
--      (o objeto de chat e o de comentário deixam de ter a chave "autor"). Assinaturas e grants não mudam.
--   c. dados.black_live_expurgar(p_agora): a partir de 01/02/2027 (03/11/2026 + 90 dias, em Brasília; se o cadastro ganhar live
--      depois de 03/11, o corte acompanha: última live + 90 dias) apaga TODO o chat e TODOS os comentários. Antes do corte não
--      apaga nada. Os números por minuto, as fotos e o cadastro ficam (não têm texto de pessoa).
--   d. Cron black-youtube-expurgo, diário às 04:52 UTC (01:52 de Brasília), chamando a função acima. Fora do corte não faz nada.
--
-- AS 5 PERGUNTAS
--   escala: 639 mensagens e 9 comentários hoje; a live de venda (03/11) pode somar milhares. O update e o drop mexem em
--     ~650 linhas; o expurgo é um delete único de milhares de linhas, uma vez, em fevereiro/2027. Com 10x continua pequeno.
--   índice: nenhum novo. O delete do expurgo lê a tabela inteira (seq scan, intencional: apaga tudo); a leitura do detalhe
--     continua pelos índices (video_id, seg) e (video_id, publicado_em). Planos no .explain.md.
--   frequência: o cron roda 1 vez por dia e, até o corte, sai na primeira linha (um select no cadastro de 9 lives).
--   repetição: nenhuma tela chama o expurgo; só o cron. O detalhe segue 1 chamada por live aberta.
--   reversão: 20261015230000_reversao.sql (tira o cron e a função, devolve as 3 funções antigas e recria a coluna autor VAZIA).
--     O nome apagado não volta, de propósito.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regclass('dados.black_live_chat') is null or to_regclass('dados.black_live_comentario') is null then
    raise exception '20261015230000: aplique antes 20261015220000 (tabelas da aba Lives ausentes)';
  end if;
  if to_regprocedure('dados.black_live_expurgar(timestamptz)') is not null then
    raise exception '20261015230000: dados.black_live_expurgar já existe';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'dados' and table_name = 'black_live_chat' and column_name = 'autor')
     or not exists (select 1 from information_schema.columns where table_schema = 'dados' and table_name = 'black_live_comentario' and column_name = 'autor') then
    raise exception '20261015230000: a coluna autor já não existe (migration já aplicada?)';
  end if;
  if exists (select 1 from pg_depend d join pg_rewrite r on r.oid = d.objid
              where d.classid = 'pg_rewrite'::regclass and d.refobjid in ('dados.black_live_chat'::regclass, 'dados.black_live_comentario'::regclass)) then
    raise exception '20261015230000: há view dependendo das tabelas; conferir antes de remover a coluna';
  end if;
end
$g$;

-- ─── a. Autor: zera e remove a coluna ──────────────────────────────────────────────────────────────────────────────
update dados.black_live_chat set autor = null where autor is not null;
update dados.black_live_comentario set autor = null where autor is not null;

-- ─── b. Funções sem autor (antes de remover a coluna) ──────────────────────────────────────────────────────────────
-- Grava uma amostra: espectadores do minuto (origem api) e as mensagens do chat (idempotente por msg_id). O chat do minuto
-- da linha api é recontado do que está guardado (não soma). p_chat_id nulo não mexe no estado do chat (serve à carga do
-- histórico). p_mensagens: [{msg_id, seg, publicado_em, texto}] (sem autor).
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
      select * from jsonb_to_recordset(p_mensagens) as t(msg_id text, seg integer, publicado_em timestamptz, texto text)
       where msg_id is not null and seg is not null and publicado_em is not null and texto is not null
    ), ins as (
      insert into dados.black_live_chat (msg_id, video_id, seg, publicado_em, texto)
      select m.msg_id, p_video_id, m.seg, m.publicado_em, left(m.texto, 1000) from m
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

-- Grava os comentários do vídeo (commentThreads), sem autor. p_itens: [{comment_id, publicado_em, texto, curtidas, respostas}].
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
  insert into dados.black_live_comentario (comment_id, video_id, publicado_em, texto, curtidas, respostas)
  select t.comment_id, p_video_id, t.publicado_em, left(t.texto, 5000),
         coalesce(t.curtidas, 0), coalesce(t.respostas, 0)
    from jsonb_to_recordset(p_itens) as t(comment_id text, publicado_em timestamptz, texto text, curtidas integer, respostas integer)
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
    'chat', coalesce((select jsonb_agg(jsonb_build_object('seg', c.seg, 'publicado_em', c.publicado_em,
                'texto', c.texto) order by c.seg, c.publicado_em, c.msg_id)
                from (select * from dados.black_live_chat where video_id = p_video_id order by seg, publicado_em, msg_id limit 5000) c), '[]'::jsonb),
    'comentarios', coalesce((select jsonb_agg(jsonb_build_object('publicado_em', k.publicado_em,
                'texto', k.texto, 'curtidas', k.curtidas, 'respostas', k.respostas) order by k.publicado_em, k.comment_id)
                from (select * from dados.black_live_comentario where video_id = p_video_id order by publicado_em desc, comment_id limit 1000) k), '[]'::jsonb),
    'fotos', coalesce((select jsonb_agg(jsonb_build_object('coletado_em', f.coletado_em, 'views', f.views, 'likes', f.likes,
                'comentarios', f.comentarios) order by f.coletado_em)
                from (select * from dados.black_live_foto where video_id = p_video_id order by coletado_em desc limit 1000) f), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

alter table dados.black_live_chat drop column autor;
alter table dados.black_live_comentario drop column autor;

-- ─── c. Expurgo: o texto das pessoas sai 90 dias depois da Black ───────────────────────────────────────────────────
-- p_agora existe só para o ensaio poder simular a data; o cron chama sem argumento. Sem grant para ninguém.
create function dados.black_live_expurgar(p_agora timestamptz default now()) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_corte timestamptz; v_chat int := 0; v_com int := 0;
begin
  -- corte = 03/11/2026 + 90 dias = 01/02/2027 00:00 (Brasília); nunca antes disso, e acompanha a última live do cadastro
  select greatest(timestamptz '2027-02-01 00:00:00-03',
                  ((max(l.data_prevista) at time zone 'America/Sao_Paulo')::date + 90)::timestamp at time zone 'America/Sao_Paulo')
    into v_corte from dados.black_lives l;
  if p_agora < v_corte then
    return jsonb_build_object('expurgou', false, 'corte', v_corte, 'chat', 0, 'comentarios', 0);
  end if;
  delete from dados.black_live_chat where criado_em <= p_agora;
  get diagnostics v_chat = row_count;
  delete from dados.black_live_comentario where criado_em <= p_agora;
  get diagnostics v_com = row_count;
  return jsonb_build_object('expurgou', true, 'corte', v_corte, 'chat', v_chat, 'comentarios', v_com);
end
$$;
revoke all on function dados.black_live_expurgar(timestamptz) from public, anon, authenticated, service_role;

do $cron$
begin
  if to_regnamespace('cron') is null then
    raise notice '20261015230000: pg_cron ausente; cron black-youtube-expurgo NÃO agendado';
    return;
  end if;
  perform cron.schedule('black-youtube-expurgo', '52 4 * * *',
    $c$set statement_timeout = '60s'; set lock_timeout = '5s'; select dados.black_live_expurgar()$c$);
end
$cron$;

-- ─── Conferência (aborta se algo ficou fora do padrão) ─────────────────────────────────────────────────────────────
do $conf$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'dados'
                and table_name in ('black_live_chat', 'black_live_comentario') and column_name = 'autor') then
    raise exception '20261015230000: a coluna autor continua existindo';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace in ('dados'::regnamespace, 'public'::regnamespace)
                and p.proname in ('black_live_gravar_amostra', 'black_live_gravar_comentarios', 'dados_black_live_detalhe')
                and p.prosrc ~* 'autor') then
    raise exception '20261015230000: alguma função ainda cita autor';
  end if;
  if has_function_privilege('anon', 'dados.black_live_expurgar(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'dados.black_live_expurgar(timestamptz)', 'execute')
     or has_function_privilege('service_role', 'dados.black_live_expurgar(timestamptz)', 'execute') then
    raise exception '20261015230000: black_live_expurgar com grant aberto';
  end if;
  if not has_function_privilege('authenticated', 'public.dados_black_live_detalhe(text,text)', 'execute')
     or has_function_privilege('anon', 'public.dados_black_live_detalhe(text,text)', 'execute') then
    raise exception '20261015230000: grant do detalhe mudou';
  end if;
  if to_regnamespace('cron') is not null and
     (select count(*) from cron.job where jobname = 'black-youtube-expurgo' and schedule = '52 4 * * *' and active) <> 1 then
    raise exception '20261015230000: cron black-youtube-expurgo ausente ou fora do padrão';
  end if;
end
$conf$;
