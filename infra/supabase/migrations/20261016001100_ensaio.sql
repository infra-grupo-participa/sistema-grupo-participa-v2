-- Ensaio transacional da 20261016001100: aplica a migration e prova que as chaves antigas ficam iguais, o que as novas trazem,
-- o tempo antes e depois, e que a reversão devolve o resultado idêntico. Desfaz tudo no ROLLBACK final.
-- Pré-requisito: mkt_trafego.linha_black (20261016001000) já criada. Saída: contagens, nomes de campanha e R$ (sem dado pessoal).
begin;
set local statement_timeout = '120s';
create temp table _z_out (em int, passo text, linha text);
do $a$
declare v text;
begin
  select m.perfil_id::text into v from acesso.master m join public.perfis p on p.id = m.perfil_id
   where p.status = 'ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
end
$a$;

create temp table _antes as select public.dados_black_trafego('black-friday-2026-10', date '2026-09-01', date '2026-10-14') j;
do $x$
declare l text; i int;
begin
  for i in 1..3 loop
    for l in execute 'explain (analyze, buffers) select public.dados_black_trafego(''black-friday-2026-10'', date ''2026-09-01'', date ''2026-10-14'')' loop
      if l ~ 'Execution Time' then insert into pg_temp._z_out values (1, '0 antes, tempo ' || i, l); end if;
    end loop;
  end loop;
end
$x$;

-- 20261016001100: public.dados_black_trafego devolve a linha e a fase de cada campanha e a linha, o nó e a isca de cada conjunto
--
-- POR QUE: o dashboard da Black classificava por nome no front (3º campo, C1/C2/C3, regra provisória). Com o padrão de nomes do Caio
-- (guia de 15/10) a classificação passa a vir do banco, por VALOR, uma só para todas as telas (mkt_trafego.linha_black, 20261016001000).
-- O QUE FAZ: só recria public.dados_black_trafego. Cada item de 'campanhas' ganha 'linha' e 'fase'; cada item de 'conjuntos' ganha
--   'linha', 'no' e 'isca'. Aditivo: nenhuma chave existente muda, nenhuma tabela, view, policy ou grant é tocado. O ACL fica como está
--   (create or replace preserva) e a guarda final confere.
-- AS 5 PERGUNTAS: escala = uma chamada de linha_black por campanha do recorte (~15) e uma por conjunto (~105), função imutável em plpgsql
--   (~0,03 ms por chamada, medido no ensaio); índice = nenhum, não consulta tabela; frequência e repetição = as da tela, nenhuma chamada
--   nova; reversão = 20261016001100_reversao.sql (corpo anterior, guarda de md5).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('mkt_trafego.linha_black(text,text)') is null then
    raise exception '20261016001100: falta mkt_trafego.linha_black (aplicar a 20261016001000 antes)';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '59b80a10e94b0f048d671cabb749abea' then
    raise exception '20261016001100: corpo vivo de dados_black_trafego mudou. Reler a definição viva.';
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
-- 20261016001100: cada campanha ganha linha e fase, cada conjunto ganha linha, no e isca (mkt_trafego.linha_black, padrão do Caio).
-- 20261014000000: cada campanha diz se "sem linha de desempenho" é sem entrega comprovada (versão mínima, lê mkt_trafego.coletas).
declare
  d dados.dashboards := dados.black_cadastro(p_chave);
  v_de date; v_ate date;
  -- 20261014000000: validade da coleta Meta (decisão do Maestro com o Victor, 13/10: 75 min). A coleta de hoje roda às :15 e
  -- :45 (cron trafego-meta-hoje): 2 ciclos + 15 min de folga. Passou disso, o estado da conta é 'velha'.
  v_validade constant interval := interval '75 minutes';
  r jsonb;
begin
  select x.de, x.ate into v_de, v_ate from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  with c as (
    -- 20261013100000: campanhas do projeto do cadastro; a campanha sem projeto_id (o CPF01 hoje; ver o explain) entra
    -- quando um dos termos entre barras do nome é a sigla do projeto (BF26). O termo vem do cadastro, não fica fixo aqui.
    select c.id, c.nome, c.plataforma, c.status_plataforma, c.objetivo, c.projeto_id, ct.nome as conta,
           c.campanha_externa,   -- 20261013014209: id da campanha no Meta (recorte do grupo por campanha)
           ct.conta_externa,     -- id da conta no Meta (link "Abrir no Gerenciador" do criativo)
           e.etapa, e.subtipo, e.conflito,
           c.primeira_coleta,   -- 20261014000000: 1ª vez que o coletor viu a campanha
           lb.linha, lb.fase   -- 20261016001100: linha do orçamento e fase pelo padrão do Caio
      from mkt_trafego.campanhas c
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
      join mkt.projetos p on p.id = d.projeto_id
      cross join lateral mkt_trafego.etapa_black(c.nome) e
      cross join lateral mkt_trafego.linha_black(c.nome) lb
     where c.projeto_id = d.projeto_id
        or (c.projeto_id is null
            and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = upper(p.sigla)))
  ),
  cj as (select j.id, j.campanha_id, j.nome, j.status_plataforma, j.meta_otimizacao, j.conjunto_externa,   -- 20261013014209
                lj.linha, lj.no, lj.isca   -- 20261016001100: o conjunto herda a linha da campanha (CAPTAÇÃO | ISCAS vira iscas ou consultoria)
           from mkt_trafego.conjuntos j join c on c.id = j.campanha_id
          cross join lateral mkt_trafego.linha_black(c.nome, j.nome) lj),
  an as (select a.id, a.conjunto_id, a.nome, a.status_plataforma, a.anuncio_externa, a.video_id,
                a.miniatura_caminho   -- caminho no bucket privado trafego-miniaturas (url_tags continua fora)
           from mkt_trafego.anuncios a join cj on cj.id = a.conjunto_id),
  dc as (select x.* from mkt_trafego.desempenho_dia x join c on c.id = x.campanha_id
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date)),
  da as (select x.* from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date)),
  -- 20261014000000: estado da coleta Meta de cada conta das campanhas, lido de mkt_trafego.coletas como está (guarda as últimas
  -- 200 execuções). Falha da conta = a conta voltou com ok diferente de true, ou a execução inteira falhou sem trazer a
  -- conta (nenhum resultado por conta).
  ct_col as (
    select x.conta,
           max(x.em) filter (where x.conta_ok) as ultima_ok_em,
           max(x.em) filter (where not x.conta_ok) as ultima_falha_em
      from (select k.conta_externa as conta, r.em, coalesce((e.el->>'ok') = 'true', false) as conta_ok   -- execução que falhou sem trazer a conta = falha (pentester 14/10)
              from (select distinct c.conta_externa from c) k
              cross join mkt_trafego.coletas r
              left join lateral (select el from jsonb_array_elements(case when jsonb_typeof(r.resultado->'contas') = 'array'
                                                                           then r.resultado->'contas' else '[]'::jsonb end) el
                                  where el->>'conta' = k.conta_externa limit 1) e on true
             where r.fonte = 'meta' and (e.el is not null or not r.ok)) x
     group by x.conta
  ),
  cv as (
    select c.id, k.ultima_ok_em, k.ultima_falha_em,
           case when k.ultima_ok_em is null and k.ultima_falha_em is null then 'sem_coleta'
                when k.ultima_falha_em is not null and (k.ultima_ok_em is null or k.ultima_falha_em > k.ultima_ok_em) then 'falha_recente'
                when k.ultima_ok_em < now() - v_validade then 'velha'
                else 'atual' end as estado,
           exists (select 1 from dc where dc.campanha_id = c.id) as tem_linha
      from c left join ct_col k on k.conta = c.conta_externa
  )
  select jsonb_build_object(
    'periodo_de', v_de, 'periodo_ate', v_ate, 'moeda', 'BRL',
    'coletado_em', greatest((select max(coletado_em) from dc), (select max(coletado_em) from da)),
    -- primeiro dia com quebra por anúncio, em qualquer data (antes dele só existe o número por campanha)
    'anuncio_desde', (select min(x.dia) from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id),
    'campanhas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'nome', c.nome, 'plataforma', c.plataforma, 'status', c.status_plataforma, 'objetivo', c.objetivo,
      'conta', c.conta, 'projeto_id', c.projeto_id, 'etapa', c.etapa, 'subtipo', c.subtipo, 'conflito', c.conflito,
      'campanha_externa', c.campanha_externa, 'conta_externa', c.conta_externa,
      -- 20261016001100
      'linha', c.linha, 'fase', c.fase,
      -- 20261014000000
      'primeira_vista_em', c.primeira_coleta,
      'coleta', jsonb_build_object('estado', cv.estado, 'ultima_ok_em', cv.ultima_ok_em, 'ultima_falha_em', cv.ultima_falha_em,
                                   'validade_min', extract(epoch from v_validade)::int / 60),
      'sem_entrega_comprovada', (not cv.tem_linha and c.primeira_coleta is not null and cv.estado = 'atual'
                                 and cv.ultima_ok_em > c.primeira_coleta)
    ) order by c.nome) from c join cv on cv.id = c.id), '[]'::jsonb),
    'conjuntos', coalesce((select jsonb_agg(jsonb_build_object(
      'id', j.id, 'campanha_id', j.campanha_id, 'nome', j.nome, 'status', j.status_plataforma,
      'meta_otimizacao', j.meta_otimizacao, 'conjunto_externa', j.conjunto_externa,
      -- 20261016001100
      'linha', j.linha, 'no', j.no, 'isca', j.isca
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

do $g$
begin
  -- sem grant novo: o ACL tem de continuar sendo só o dono e authenticated (execute)
  if (select p.proacl::text from pg_proc p where p.oid = 'public.dados_black_trafego(text,date,date)'::regprocedure)
       is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception '20261016001100: ACL de dados_black_trafego mudou';
  end if;
end
$g$;

create temp table _depois as select public.dados_black_trafego('black-friday-2026-10', date '2026-09-01', date '2026-10-14') j;
do $x$
declare l text; i int;
begin
  for i in 1..3 loop
    for l in execute 'explain (analyze, buffers) select public.dados_black_trafego(''black-friday-2026-10'', date ''2026-09-01'', date ''2026-10-14'')' loop
      if l ~ 'Execution Time' then insert into pg_temp._z_out values (3, '2 depois, tempo ' || i, l); end if;
    end loop;
  end loop;
end
$x$;

-- chaves antigas iguais: campanhas sem linha/fase, conjuntos sem linha/no/isca, e o resto do JSON inteiro
insert into _z_out
select 2, 'resto_do_json_igual', ((a.j - 'campanhas' - 'conjuntos') = (d.j - 'campanhas' - 'conjuntos'))::text from _antes a, _depois d
union all
select 2, 'campanhas_antigas_iguais',
       ((select jsonb_agg(e - 'linha' - 'fase' order by e->>'nome', e->>'id') from jsonb_array_elements(d.j->'campanhas') e)
        = (select jsonb_agg(e order by e->>'nome', e->>'id') from jsonb_array_elements(a.j->'campanhas') e))::text from _antes a, _depois d
union all
select 2, 'conjuntos_antigos_iguais',
       ((select jsonb_agg(e - 'linha' - 'no' - 'isca' order by e->>'nome', e->>'id') from jsonb_array_elements(d.j->'conjuntos') e)
        = (select jsonb_agg(e order by e->>'nome', e->>'id') from jsonb_array_elements(a.j->'conjuntos') e))::text from _antes a, _depois d
union all
select 2, 'tamanho_json_antes_depois_bytes', length(a.j::text) || ' -> ' || length(d.j::text) from _antes a, _depois d;

-- tabela antes x depois por campanha
insert into _z_out
select 4, 'campanha ' || lpad((row_number() over (order by e->>'nome', (e->>'id')::int))::text, 2, '0') || ' ' || (e->>'nome'),
       'etapa antes ' || coalesce(e->>'etapa', 'null') || ' | linha ' || coalesce(e->>'linha', 'null') || ' | fase ' || coalesce(e->>'fase', 'null')
  from _depois d cross join lateral jsonb_array_elements(d.j->'campanhas') e;

-- conjuntos por (linha, nó)
insert into _z_out
select 5, 'conjuntos linha=' || coalesce(e->>'linha', '<null>') || ' no=' || coalesce(e->>'no', '<null>'), count(*)::text
  from _depois d cross join lateral jsonb_array_elements(d.j->'conjuntos') e
 group by e->>'linha', e->>'no';
insert into _z_out
select 5, 'conjuntos_sem_linha_ou_no', count(*)::text
  from _depois d cross join lateral jsonb_array_elements(d.j->'conjuntos') e
 where e->>'linha' is null or e->>'no' is null;

-- gasto do recorte por linha (01/09 a 14/10) e campanha com gasto sem linha
insert into _z_out
select 6, 'gasto_linha ' || coalesce(c->>'linha', '<sem classificação>'), to_char(sum((x->>'gasto_centavos')::numeric) / 100, 'FM999G999D00')
  from _depois d
  cross join lateral jsonb_array_elements(d.j->'dias_campanha') x
  join lateral jsonb_array_elements(d.j->'campanhas') c on (c->>'id') = (x->>'campanha_id')
 group by c->>'linha';
insert into _z_out
select 6, 'campanha_com_gasto_sem_linha',
       coalesce((select string_agg(c->>'nome', '; ') from _depois d cross join lateral jsonb_array_elements(d.j->'campanhas') c
                  where c->>'linha' is null
                    and exists (select 1 from jsonb_array_elements(d.j->'dias_campanha') x
                                 where (x->>'campanha_id') = (c->>'id') and (x->>'gasto_centavos')::numeric > 0)), 'nenhuma');

-- ACL igual
insert into _z_out
select 7, 'acl_dados_black_trafego', p.proacl::text from pg_proc p where p.oid = 'public.dados_black_trafego(text,date,date)'::regprocedure;

-- reversão ensaiada: tem de devolver o JSON idêntico ao de antes
-- Reversão da 20261016001100: volta public.dados_black_trafego ao corpo da 20261014000000 (sem linha, fase, no e isca).
-- Depois: delete from supabase_migrations.schema_migrations where version = '20261016001100';
-- Quem lê 'linha' (front do dashboard da Black) precisa estar revertido antes, ou cai no fallback do front.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.dados_black_trafego(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 20261013225000: devolve também 'totais' (alcance e frequência do período inteiro de cada campanha, mkt_trafego.desempenho_total).
-- 20261014000000: cada campanha diz se "sem linha de desempenho" é sem entrega comprovada (versão mínima, lê mkt_trafego.coletas).
declare
  d dados.dashboards := dados.black_cadastro(p_chave);
  v_de date; v_ate date;
  -- 20261014000000: validade da coleta Meta (decisão do Maestro com o Victor, 13/10: 75 min). A coleta de hoje roda às :15 e
  -- :45 (cron trafego-meta-hoje): 2 ciclos + 15 min de folga. Passou disso, o estado da conta é 'velha'.
  v_validade constant interval := interval '75 minutes';
  r jsonb;
begin
  select x.de, x.ate into v_de, v_ate from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  with c as (
    -- 20261013100000: campanhas do projeto do cadastro; a campanha sem projeto_id (o CPF01 hoje; ver o explain) entra
    -- quando um dos termos entre barras do nome é a sigla do projeto (BF26). O termo vem do cadastro, não fica fixo aqui.
    select c.id, c.nome, c.plataforma, c.status_plataforma, c.objetivo, c.projeto_id, ct.nome as conta,
           c.campanha_externa,   -- 20261013014209: id da campanha no Meta (recorte do grupo por campanha)
           ct.conta_externa,     -- id da conta no Meta (link "Abrir no Gerenciador" do criativo)
           e.etapa, e.subtipo, e.conflito,
           c.primeira_coleta   -- 20261014000000: 1ª vez que o coletor viu a campanha
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
          where x.dia >= coalesce(v_de, '-infinity'::date) and x.dia <= coalesce(v_ate, 'infinity'::date)),
  -- 20261014000000: estado da coleta Meta de cada conta das campanhas, lido de mkt_trafego.coletas como está (guarda as últimas
  -- 200 execuções). Falha da conta = a conta voltou com ok diferente de true, ou a execução inteira falhou sem trazer a
  -- conta (nenhum resultado por conta).
  ct_col as (
    select x.conta,
           max(x.em) filter (where x.conta_ok) as ultima_ok_em,
           max(x.em) filter (where not x.conta_ok) as ultima_falha_em
      from (select k.conta_externa as conta, r.em, coalesce((e.el->>'ok') = 'true', false) as conta_ok   -- execução que falhou sem trazer a conta = falha (pentester 14/10)
              from (select distinct c.conta_externa from c) k
              cross join mkt_trafego.coletas r
              left join lateral (select el from jsonb_array_elements(case when jsonb_typeof(r.resultado->'contas') = 'array'
                                                                           then r.resultado->'contas' else '[]'::jsonb end) el
                                  where el->>'conta' = k.conta_externa limit 1) e on true
             where r.fonte = 'meta' and (e.el is not null or not r.ok)) x
     group by x.conta
  ),
  cv as (
    select c.id, k.ultima_ok_em, k.ultima_falha_em,
           case when k.ultima_ok_em is null and k.ultima_falha_em is null then 'sem_coleta'
                when k.ultima_falha_em is not null and (k.ultima_ok_em is null or k.ultima_falha_em > k.ultima_ok_em) then 'falha_recente'
                when k.ultima_ok_em < now() - v_validade then 'velha'
                else 'atual' end as estado,
           exists (select 1 from dc where dc.campanha_id = c.id) as tem_linha
      from c left join ct_col k on k.conta = c.conta_externa
  )
  select jsonb_build_object(
    'periodo_de', v_de, 'periodo_ate', v_ate, 'moeda', 'BRL',
    'coletado_em', greatest((select max(coletado_em) from dc), (select max(coletado_em) from da)),
    -- primeiro dia com quebra por anúncio, em qualquer data (antes dele só existe o número por campanha)
    'anuncio_desde', (select min(x.dia) from mkt_trafego.desempenho_anuncio_dia x join an on an.id = x.anuncio_id),
    'campanhas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'nome', c.nome, 'plataforma', c.plataforma, 'status', c.status_plataforma, 'objetivo', c.objetivo,
      'conta', c.conta, 'projeto_id', c.projeto_id, 'etapa', c.etapa, 'subtipo', c.subtipo, 'conflito', c.conflito,
      'campanha_externa', c.campanha_externa, 'conta_externa', c.conta_externa,
      -- 20261014000000
      'primeira_vista_em', c.primeira_coleta,
      'coleta', jsonb_build_object('estado', cv.estado, 'ultima_ok_em', cv.ultima_ok_em, 'ultima_falha_em', cv.ultima_falha_em,
                                   'validade_min', extract(epoch from v_validade)::int / 60),
      'sem_entrega_comprovada', (not cv.tem_linha and c.primeira_coleta is not null and cv.estado = 'atual'
                                 and cv.ultima_ok_em > c.primeira_coleta)
    ) order by c.nome) from c join cv on cv.id = c.id), '[]'::jsonb),
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

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '59b80a10e94b0f048d671cabb749abea' then
    raise exception '20261016001100 reversão: corpo restaurado não confere com a 20261014000000';
  end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'public.dados_black_trafego(text,date,date)'::regprocedure)
       is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception '20261016001100 reversão: ACL de dados_black_trafego mudou';
  end if;
end
$g$;

create temp table _revertido as select public.dados_black_trafego('black-friday-2026-10', date '2026-09-01', date '2026-10-14') j;
insert into _z_out
select 8, 'apos_reversao_json_identico_ao_antes', (a.j = r.j)::text from _antes a, _revertido r
union all
select 8, 'apos_reversao_md5', md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
