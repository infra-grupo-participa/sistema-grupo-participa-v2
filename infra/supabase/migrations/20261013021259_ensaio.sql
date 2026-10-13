-- Ensaio de 20261013021259 (transação desfeita, REPEATABLE READ). dados_black_trafego com campanha_externa e conjunto_externa.
-- Prova: (1) depois, o resultado sem as 2 chaves novas é idêntico ao de antes (todo o período e 10 a 12/10);
-- (2) os totais de gasto por etapa e subtipo (por campanha e por anúncio) são iguais antes, depois e depois da reversão;
-- (3) todas as campanhas e conjuntos trazem o id novo, e ele bate com a tabela de origem; (4) as travas (P0002, 42501)
-- dão a mesma resposta; (5) a reversão volta o corpo ao md5 de antes e o resultado ao de antes.
-- Só contagens, somas, sqlstate e md5. Gerado por um script a partir da migration e da reversão (texto sem mudança).
begin transaction isolation level repeatable read;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_r (fase text, periodo text, r jsonb) on commit drop;
grant all on pg_temp._z_out, pg_temp._z_r to authenticated, anon;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
-- gasto por etapa e subtipo, a partir do próprio retorno da RPC
create function pg_temp.z_gasto(r jsonb) returns jsonb language sql immutable as $f$
  select jsonb_build_object(
    'campanha', (select jsonb_object_agg(k, v) from (
        select coalesce(c->>'etapa', 'null') || '/' || coalesce(c->>'subtipo', 'null') k, sum((d->>'gasto_centavos')::bigint) v
          from jsonb_array_elements(r->'dias_campanha') d join jsonb_array_elements(r->'campanhas') c on c->>'id' = d->>'campanha_id'
         group by 1) z),
    'anuncio', (select jsonb_object_agg(k, v) from (
        select coalesce(c->>'etapa', 'null') || '/' || coalesce(c->>'subtipo', 'null') k, sum((d->>'gasto_centavos')::bigint) v
          from jsonb_array_elements(r->'dias_anuncio') d
          join jsonb_array_elements(r->'anuncios') a on a->>'id' = d->>'anuncio_id'
          join jsonb_array_elements(r->'conjuntos') j on j->>'id' = a->>'conjunto_id'
          join jsonb_array_elements(r->'campanhas') c on c->>'id' = j->>'campanha_id'
         group by 1) z),
    'total_campanha', (select sum((d->>'gasto_centavos')::bigint) from jsonb_array_elements(r->'dias_campanha') d),
    'total_anuncio', (select sum((d->>'gasto_centavos')::bigint) from jsonb_array_elements(r->'dias_anuncio') d))
$f$;
-- o retorno sem as 2 chaves novas
create function pg_temp.z_sem_novas(r jsonb) returns jsonb language sql immutable as $f$
  select r || jsonb_build_object(
    'campanhas', coalesce((select jsonb_agg(e - 'campanha_externa' order by o) from jsonb_array_elements(r->'campanhas') with ordinality x(e, o)), '[]'::jsonb),
    'conjuntos', coalesce((select jsonb_agg(e - 'conjunto_externa' order by o) from jsonb_array_elements(r->'conjuntos') with ordinality x(e, o)), '[]'::jsonb))
$f$;

-- ===== 1. ANTES =====
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_r (fase, periodo, r) select 'antes', 'todo', public.dados_black_trafego('black-friday-2026-10', null, null);
insert into pg_temp._z_r (fase, periodo, r) select 'antes', '10a12', public.dados_black_trafego('black-friday-2026-10', '2026-10-10', '2026-10-12');
do $t$ declare v text; begin v := (public.dados_black_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (M) | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (M) | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | antes', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | antes', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_trafego(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain trafego | antes', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 2. MIGRATION (texto de 20261013021259_dados_black_trafego_ids_meta.sql) =====
-- 20261013021259: dados_black_trafego devolve o id do Meta da campanha e do conjunto.
-- Pedido do Maestro (13/10/2026): a tela da Black já lê esses campos para o recorte do grupo por campanha e por conjunto
-- (commit da16e6f, branch victor-black-dashboard). Muda só isto:
--   - cada item de "campanhas" ganha a chave "campanha_externa" (mkt_trafego.campanhas.campanha_externa, text not null);
--   - cada item de "conjuntos" ganha a chave "conjunto_externa" (mkt_trafego.conjuntos.conjunto_externa, text not null).
-- Nenhuma outra chave, filtro, junção ou total muda (o ensaio prova: resultado sem as 2 chaves novas = resultado de antes,
-- e os totais de gasto por etapa são iguais). Dono, ACL, security definer e search_path iguais.
-- Pré-requisito: corpo vivo igual ao gravado por 20261012231649 (md5 conferido abaixo).
-- Reversão: 20261013021259_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '10e1a38a90f878884abe055aadaa4c39' then
    raise exception '20261013021259: corpo vivo de dados_black_trafego mudou. Reler.';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.dados_black_trafego(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
           c.campanha_externa,   -- 20261013021259: id da campanha no Meta (recorte do grupo por campanha)
           e.etapa, e.subtipo, e.conflito
      from mkt_trafego.campanhas c
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
      join mkt.projetos p on p.id = d.projeto_id
      cross join lateral mkt_trafego.etapa_black(c.nome) e
     where c.projeto_id = d.projeto_id
        or (c.projeto_id is null
            and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = upper(p.sigla)))
  ),
  cj as (select j.id, j.campanha_id, j.nome, j.status_plataforma, j.meta_otimizacao, j.conjunto_externa   -- 20261013021259
           from mkt_trafego.conjuntos j join c on c.id = j.campanha_id),
  an as (select a.id, a.conjunto_id, a.nome, a.status_plataforma, a.anuncio_externa, a.video_id
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
      'campanha_externa', c.campanha_externa
    ) order by c.nome) from c), '[]'::jsonb),
    'conjuntos', coalesce((select jsonb_agg(jsonb_build_object(
      'id', j.id, 'campanha_id', j.campanha_id, 'nome', j.nome, 'status', j.status_plataforma,
      'meta_otimizacao', j.meta_otimizacao, 'conjunto_externa', j.conjunto_externa
    ) order by j.nome, j.id) from cj j), '[]'::jsonb),
    'anuncios', coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'conjunto_id', a.conjunto_id, 'nome', a.nome, 'status', a.status_plataforma,
      'anuncio_externa', a.anuncio_externa, 'video_id', a.video_id
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
    ) order by x.dia, x.anuncio_id) from da x), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

-- grants de antes (create or replace mantém; reafirmados)
revoke all on function public.dados_black_trafego(text, date, date) from public, anon, service_role;
grant execute on function public.dados_black_trafego(text, date, date) to authenticated;

do $c$
begin
  if (select proacl::text from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or not (select prosecdef from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) then
    raise exception '20261013021259: permissão de dados_black_trafego errada';
  end if;
end
$c$;

-- ===== fim da migration =====

reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'F acl e secdef', (select proacl::text || ' secdef=' || prosecdef from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure);
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_r (fase, periodo, r) select 'depois', 'todo', public.dados_black_trafego('black-friday-2026-10', null, null);
insert into pg_temp._z_r (fase, periodo, r) select 'depois', '10a12', public.dados_black_trafego('black-friday-2026-10', '2026-10-10', '2026-10-12');
do $t$ declare v text; begin v := (public.dados_black_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (M) | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (M) | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | depois', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | depois', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_trafego(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain trafego | depois', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 3. REVERSÃO (texto de 20261013021259_reversao.sql) =====
-- Reversão de 20261013021259. Numa transação (o arquivo não abre nem fecha uma).
-- Devolve dados_black_trafego ao corpo exato gravado por 20261012231649 (lido no banco em 13/10/2026 ~01:40 UTC):
-- "campanhas" e "conjuntos" deixam de trazer campanha_externa e conjunto_externa. Não toca em dado.
-- Efeito na tela: o recorte do grupo por campanha e por conjunto volta a mostrar "Sem dado" com o motivo.
set local lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.dados_black_trafego(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
           e.etapa, e.subtipo, e.conflito
      from mkt_trafego.campanhas c
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
      join mkt.projetos p on p.id = d.projeto_id
      cross join lateral mkt_trafego.etapa_black(c.nome) e
     where c.projeto_id = d.projeto_id
        or (c.projeto_id is null
            and exists (select 1 from unnest(string_to_array(c.nome, '|')) t where upper(btrim(t)) = upper(p.sigla)))
  ),
  cj as (select j.id, j.campanha_id, j.nome, j.status_plataforma, j.meta_otimizacao
           from mkt_trafego.conjuntos j join c on c.id = j.campanha_id),
  an as (select a.id, a.conjunto_id, a.nome, a.status_plataforma, a.anuncio_externa, a.video_id
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
      'conta', c.conta, 'projeto_id', c.projeto_id, 'etapa', c.etapa, 'subtipo', c.subtipo, 'conflito', c.conflito
    ) order by c.nome) from c), '[]'::jsonb),
    'conjuntos', coalesce((select jsonb_agg(jsonb_build_object(
      'id', j.id, 'campanha_id', j.campanha_id, 'nome', j.nome, 'status', j.status_plataforma,
      'meta_otimizacao', j.meta_otimizacao
    ) order by j.nome, j.id) from cj j), '[]'::jsonb),
    'anuncios', coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'conjunto_id', a.conjunto_id, 'nome', a.nome, 'status', a.status_plataforma,
      'anuncio_externa', a.anuncio_externa, 'video_id', a.video_id
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
    ) order by x.dia, x.anuncio_id) from da x), '[]'::jsonb)
  ) into r;
  return r;
end
$function$;

revoke all on function public.dados_black_trafego(text, date, date) from public, anon, service_role;
grant execute on function public.dados_black_trafego(text, date, date) to authenticated;

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_trafego(text,date,date)'::regprocedure) <> '10e1a38a90f878884abe055aadaa4c39' then
    raise exception 'reversão 20261013021259: corpo de dados_black_trafego não voltou ao de antes';
  end if;
end
$c$;

-- ===== fim da reversão =====

reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_r (fase, periodo, r) select 'reversao', 'todo', public.dados_black_trafego('black-friday-2026-10', null, null);
insert into pg_temp._z_r (fase, periodo, r) select 'reversao', '10a12', public.dados_black_trafego('black-friday-2026-10', '2026-10-10', '2026-10-12');
do $t$ declare v text; begin v := (public.dados_black_trafego('atm-elaine-1-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (M) | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B ATM na trafego da Black (M) | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B fora da equipe | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
set local role anon;
do $t$ declare v text; begin v := (public.dados_black_trafego('black-friday-2026-10'))::text;
  insert into pg_temp._z_out (passo, linha) values ('B anon | reversao', 'ok:' || md5(coalesce(v, 'null')));
exception when others then insert into pg_temp._z_out (passo, linha) values ('B anon | reversao', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $x$ declare l text; begin
  for l in execute 'explain (analyze, timing) select public.dados_black_trafego(''black-friday-2026-10'')' loop
    if l ~ '(Execution|Planning) Time' then insert into pg_temp._z_out (passo, linha) values ('E explain trafego | reversao', l); end if;
  end loop;
end $x$;
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== 4. COMPARAÇÕES =====
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.periodo || ' depois sem as chaves novas = antes', (pg_temp.z_sem_novas(d.r) = a.r)::text
  from pg_temp._z_r a join pg_temp._z_r d on d.periodo = a.periodo and d.fase = 'depois' where a.fase = 'antes';
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.periodo || ' reversao = antes', (r.r = a.r)::text
  from pg_temp._z_r a join pg_temp._z_r r on r.periodo = a.periodo and r.fase = 'reversao' where a.fase = 'antes';
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.periodo || ' gasto por etapa igual nas 3 fases', (pg_temp.z_gasto(a.r) = pg_temp.z_gasto(d.r) and pg_temp.z_gasto(a.r) = pg_temp.z_gasto(r.r))::text
  from pg_temp._z_r a join pg_temp._z_r d on d.periodo = a.periodo and d.fase = 'depois' join pg_temp._z_r r on r.periodo = a.periodo and r.fase = 'reversao'
 where a.fase = 'antes';
insert into pg_temp._z_out (passo, linha)
select 'Z ' || a.periodo || ' gasto por etapa (centavos)', pg_temp.z_gasto(a.r)::text from pg_temp._z_r a where a.fase = 'antes';
insert into pg_temp._z_out (passo, linha)
select 'Z ' || d.periodo || ' ids novos', jsonb_build_object(
   'campanhas', jsonb_array_length(d.r->'campanhas'),
   'campanhas_com_campanha_externa', (select count(*) from jsonb_array_elements(d.r->'campanhas') e where nullif(e->>'campanha_externa', '') is not null),
   'campanha_externa_bate_com_a_tabela', (select count(*) from jsonb_array_elements(d.r->'campanhas') e join mkt_trafego.campanhas c on c.id::text = e->>'id' and c.campanha_externa = e->>'campanha_externa'),
   'conjuntos', jsonb_array_length(d.r->'conjuntos'),
   'conjuntos_com_conjunto_externa', (select count(*) from jsonb_array_elements(d.r->'conjuntos') e where nullif(e->>'conjunto_externa', '') is not null),
   'conjunto_externa_bate_com_a_tabela', (select count(*) from jsonb_array_elements(d.r->'conjuntos') e join mkt_trafego.conjuntos j on j.id::text = e->>'id' and j.conjunto_externa = e->>'conjunto_externa'),
   'chaves_campanha', (select jsonb_agg(k order by k) from jsonb_object_keys(d.r->'campanhas'->0) k),
   'chaves_conjunto', (select jsonb_agg(k order by k) from jsonb_object_keys(d.r->'conjuntos'->0) k))::text
  from pg_temp._z_r d where d.fase = 'depois';
insert into pg_temp._z_out (passo, linha)
select 'Z trava ' || split_part(a.passo, ' | ', 1), case when a.linha = d.linha and a.linha = r.linha then 'IGUAL ' || a.linha else 'DIFERENTE ' || a.linha || ' / ' || d.linha || ' / ' || r.linha end
  from pg_temp._z_out a join pg_temp._z_out d on d.passo = replace(a.passo, '| antes', '| depois') join pg_temp._z_out r on r.passo = replace(a.passo, '| antes', '| reversao')
 where a.passo like 'B %| antes';
select passo, linha from pg_temp._z_out where passo not like 'B %' order by em;
rollback;
