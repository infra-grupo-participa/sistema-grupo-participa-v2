-- Ensaio de 20261013225000 (transação desfeita): as chaves antigas de dados_black_trafego ficam idênticas e 'totais' aparece.
begin;
create temp table _z_out (em serial, passo text, linha text);
do $a$
declare v text;
begin
  select m.perfil_id::text into v from acesso.master m join public.perfis p on p.id = m.perfil_id
   where p.status = 'ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
end
$a$;

create temp table _antes as select public.dados_black_trafego('black-friday-2026-10', null, null) - 'totais' as j;
insert into pg_temp._z_out(passo, linha) select '1 antes: tem totais?', (public.dados_black_trafego('black-friday-2026-10', null, null) ? 'totais')::text;
-- 20261013225000: dados_black_trafego devolve 'totais' (alcance e frequência por campanha)
--
-- POR QUE: o card do C1 e a gaveta da etapa mostram alcance e frequência "do período", que não somam entre dias. A
-- função só mandava o alcance por dia; o front montava totais = [] e a tela ficava sempre em "Sem dado".
-- O QUE FAZ: acrescenta a chave 'totais' ao jsonb, lida de mkt_trafego.desempenho_total (gravada pela Edge trafego-meta
-- desde 20261009230000, uma linha por campanha com de/ate). Nenhuma chave existente muda. Assinatura igual (sem
-- sobrecarga), ACL preservada pelo create or replace.
-- AS 5 PERGUNTAS: escala = 1 linha por campanha do projeto (hoje 10), join pela PK (campanha_id); índice = PK de
-- desempenho_total; frequência = a mesma da tela (releitura a cada 5 min com a aba aberta); repetição = nenhuma consulta
-- nova (mesma chamada); reversão = 20261013225000_reversao.sql (corpo anterior, md5 4ecabc5c67e683f8f5523c2fe739d00c).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '4ecabc5c67e683f8f5523c2fe739d00c' then
    raise exception '20261013225000: corpo vivo de dados_black_trafego mudou. Reler a definição viva.';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.dados_black_trafego(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 20261013225000: devolve também 'totais' (alcance e frequência do período inteiro de cada campanha, mkt_trafego.desempenho_total).
declare
  d dados.dashboards := dados.black_cadastro(p_chave);
  v_de date; v_ate date;
  r jsonb;
begin
  select x.de, x.ate into v_de, v_ate from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  with c as (
    -- 20261013100000: campanhas do projeto do cadastro; a campanha sem projeto_id (o CPF01 hoje; ver o explain) entra
    -- quando um dos termos entre barras do nome é a sigla do projeto (BF26). O termo vem do cadastro, não fica fixo aqui.
    select c.id, c.nome, c.plataforma, c.status_plataforma, c.objetivo, c.projeto_id, ct.nome as conta,
           c.campanha_externa,   -- 20261013014209: id da campanha no Meta (recorte do grupo por campanha)
           ct.conta_externa,     -- id da conta no Meta (link "Abrir no Gerenciador" do criativo)
           e.etapa, e.subtipo, e.conflito
      from mkt_trafego.campanhas c
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
      join mkt.projetos p on p.id = d.projeto_id
      cross join lateral mkt_trafego.etapa_black(c.nome) e
     where c.projeto_id = d.projeto_id
        or (c.projeto_id is null
            and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = upper(p.sigla)))
  ),
  cj as (select j.id, j.campanha_id, j.nome, j.status_plataforma, j.meta_otimizacao, j.conjunto_externa   -- 20261013014209
           from mkt_trafego.conjuntos j join c on c.id = j.campanha_id),
  an as (select a.id, a.conjunto_id, a.nome, a.status_plataforma, a.anuncio_externa, a.video_id,
                a.miniatura_caminho   -- caminho no bucket privado trafego-miniaturas (url_tags continua fora)
           from mkt_trafego.anuncios a join cj on cj.id = a.conjunto_id),
  dc as (select x.* from mkt_trafego.desempenho_dia x join c on c.id = x.campanha_id
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date)),
  da as (select x.* from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date))
  select jsonb_build_object(
    'periodo_de', v_de, 'periodo_ate', v_ate, 'moeda', 'BRL',
    'coletado_em', greatest((select max(coletado_em) from dc), (select max(coletado_em) from da)),
    -- primeiro dia com quebra por anúncio, em qualquer data (antes dele só existe o número por campanha)
    'anuncio_desde', (select min(x.dia) from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id),
    'campanhas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'nome', c.nome, 'plataforma', c.plataforma, 'status', c.status_plataforma, 'objetivo', c.objetivo,
      'conta', c.conta, 'projeto_id', c.projeto_id, 'etapa', c.etapa, 'subtipo', c.subtipo, 'conflito', c.conflito,
      'campanha_externa', c.campanha_externa, 'conta_externa', c.conta_externa
    ) order by c.nome) from c), '[]'::jsonb),
    'conjuntos', coalesce((select jsonb_agg(jsonb_build_object(
      'id', j.id, 'campanha_id', j.campanha_id, 'nome', j.nome, 'status', j.status_plataforma,
      'meta_otimizacao', j.meta_otimizacao, 'conjunto_externa', j.conjunto_externa
    ) order by j.nome, j.id) from cj j), '[]'::jsonb),
    'anuncios', coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'conjunto_id', a.conjunto_id, 'nome', a.nome, 'status', a.status_plataforma,
      'anuncio_externa', a.anuncio_externa, 'video_id', a.video_id, 'miniatura_caminho', a.miniatura_caminho
    ) order by a.nome, a.id) from an a), '[]'::jsonb),
    'dias_campanha', coalesce((select jsonb_agg(jsonb_build_object(
      'campanha_id', x.campanha_id, 'dia', x.dia, 'gasto_centavos', round(x.gasto * 100)::bigint,
      'impressoes', x.impressoes, 'alcance', x.alcance, 'frequencia', x.frequencia,
      'cliques_link', x.cliques_link, 'cliques_total', x.cliques_total, 'cliques_saida', x.cliques_saida,
      'landing_page_views', x.landing_page_views, 'leads_plataforma', x.leads_plataforma, 'engajamento', x.engajamento,
      'video_plays', x.video_plays, 'video_thruplay', x.video_thruplay,
      'video_p25', x.video_p25, 'video_p50', x.video_p50, 'video_p75', x.video_p75, 'video_p100', x.video_p100
    ) order by x.dia, x.campanha_id) from dc x), '[]'::jsonb),
    'dias_anuncio', coalesce((select jsonb_agg(jsonb_build_object(
      'anuncio_id', x.anuncio_id, 'dia', x.dia, 'gasto_centavos', round(x.gasto * 100)::bigint,
      'impressoes', x.impressoes, 'alcance', x.alcance, 'frequencia', x.frequencia,
      'cliques_link', x.cliques_link, 'cliques_total', x.cliques_total, 'cliques_saida', x.cliques_saida,
      'landing_page_views', x.landing_page_views, 'leads_plataforma', x.leads_plataforma, 'engajamento', x.engajamento,
      'video_plays', x.video_plays, 'video_thruplay', x.video_thruplay,
      'video_p25', x.video_p25, 'video_p50', x.video_p50, 'video_p75', x.video_p75, 'video_p100', x.video_p100
    ) order by x.dia, x.anuncio_id) from da x), '[]'::jsonb),
    -- 20261013225000: total do período INTEIRO de cada campanha (date_preset=maximum na Edge trafego-meta), não o filtro da tela:
    -- alcance e frequência não somam entre dias nem entre campanhas. de/ate dizem o período que o número cobre.
    'totais', coalesce((select jsonb_agg(jsonb_build_object(
      'campanha_id', t.campanha_id, 'de', t.de, 'ate', t.ate, 'gasto_centavos', round(t.gasto * 100)::bigint,
      'impressoes', t.impressoes, 'alcance', t.alcance, 'frequencia', t.frequencia, 'coletado_em', t.coletado_em
    ) order by t.campanha_id) from mkt_trafego.desempenho_total t join c on c.id = t.campanha_id), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

revoke execute on function public.dados_black_trafego(text, date, date) from public, anon, service_role;
grant execute on function public.dados_black_trafego(text, date, date) to authenticated;

insert into pg_temp._z_out(passo, linha) select '2 depois: chaves antigas idênticas', ((public.dados_black_trafego('black-friday-2026-10', null, null) - 'totais') = (select j from pg_temp._antes))::text;
insert into pg_temp._z_out(passo, linha) select '3 depois: totais (campanhas)', jsonb_array_length(public.dados_black_trafego('black-friday-2026-10', null, null) -> 'totais')::text;
insert into pg_temp._z_out(passo, linha) select '4 depois: totais', (select string_agg(x->>'campanha_id' || ' ' || (x->>'de') || '..' || (x->>'ate') || ' alcance ' || (x->>'alcance') || ' freq ' || (x->>'frequencia'), ' | ')
  from jsonb_array_elements(public.dados_black_trafego('black-friday-2026-10', null, null) -> 'totais') x);
insert into pg_temp._z_out(passo, linha) select '5 ACL', (select coalesce(proacl::text, 'NULL') from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure);
insert into pg_temp._z_out(passo, linha) select '6 sobrecargas', (select count(*)::text from pg_proc where proname = 'dados_black_trafego');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
