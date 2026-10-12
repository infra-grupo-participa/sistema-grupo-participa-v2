-- Ensaio de 20261013100000 (transação desfeita). Lê como pessoa da equipe o tráfego real da Black (sem dado pessoal: só campanha,
-- conjunto e anúncio). Confere o gasto de 10 a 12/10 por campanha, o total desde 04/10, a soma por anúncio contra a soma por
-- campanha, as travas de acesso e o que as RPCs de outro modelo fazem com a chave da Black.
begin;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
insert into pg_temp._z_out (passo, linha) select '1 antes', jsonb_build_object('dashboards', (select count(*) from dados.dashboards), 'black', (select count(*) from dados.dashboards where chave = 'black-friday-2026-10'))::text;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '1 antes md5 atm_trafego', md5((select public.dados_atm_trafego('atm-elaine-1-2026-10'))::text);
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== MIGRATION =====
-- 20261013100000: cadastro do dashboard da Black Friday (modelo jornada-captacao) e tráfego Meta por campanha, conjunto e anúncio
--
-- STATUS: ver 20261013100000.explain.md.
-- POR QUE: pedido do Victor (13/10/2026). O dashboard da Black (/infra/dashboards/csm/black-friday-2026-10) sai do modo demo
--   e passa a ler o banco. Esta é a migration A; a B (20261013110000, leads, perfil e marcar teste) depende desta.
-- O QUE FAZ:
--   1. dados.dashboards: o CHECK do modelo passa a aceitar 'jornada-captacao' (os dois modelos de hoje continuam).
--   2. Linha da Black: chave black-friday-2026-10, projeto 4 (BF26), conta_hotmart academy (confirmado pelo Victor em
--      13/10/2026), periodo_inicio 04/10/2026 (decisão do Victor: o gasto de antecipação começa aí). Sem oferta e sem lista AC.
--   3. dados.black_cadastro(p_chave): a trava das RPCs da Black (dados.cadastro + modelo jornada-captacao), igual à do ATM.
--   4. public.dados_black_trafego(p_chave, p_de, p_ate) jsonb: campanhas do projeto do cadastro, mais as sem projeto que têm
--      a sigla do projeto (BF26) entre barras no nome (conta em BRL), com etapa,
--      subtipo e conflito de mkt_trafego.etapa_black; conjuntos; anúncios; dia a dia por campanha e por anúncio.
--      Não devolve url_tags nem miniatura (dado que o navegador não precisa).
-- AS 5 PERGUNTAS: escala: 1 linha, 1 CHECK, 2 funções; leitura de ~4 campanhas, ~40 anúncios, ~100 linhas/dia no máximo;
--   índice: PKs (campanha_id, dia) e (anuncio_id, dia); frequência: a abertura do dashboard; repetição: idempotente
--   (insert on conflict do nothing + conferência); reversão: 20261013100000_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mkt_trafego.etapa_black(text)'::regprocedure) <> 'ad283827886ef398bff20d806a8fd02b' then
    raise exception '20261013100000: corpo vivo de mkt_trafego.etapa_black mudou. Reler.';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint
       where conrelid = 'dados.dashboards'::regclass and conname = 'dashboards_modelo_check')
     not in ('CHECK ((modelo = ANY (ARRAY[''presencial-base''::text, ''seminario-atm''::text])))',
             'CHECK ((modelo = ANY (ARRAY[''presencial-base''::text, ''seminario-atm''::text, ''jornada-captacao''::text])))') then
    raise exception '20261013100000: dashboards_modelo_check mudou. Reler.';
  end if;
  if exists (select 1 from dados.dashboards where chave = 'black-friday-2026-10'
              and (modelo, projeto_id, conta_hotmart, periodo_inicio) is distinct from
                  ('jornada-captacao', 4::bigint, 'academy', date '2026-10-04')) then
    raise exception '20261013100000: já existe uma linha black-friday-2026-10 diferente. Reler.';
  end if;
  if not exists (select 1 from mkt.projetos where id = 4 and sigla = 'BF26') then
    raise exception '20261013100000: projeto 4 não é o BF26. Reler.';
  end if;
end
$g$;

-- 1. modelo novo
alter table dados.dashboards drop constraint dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check
  check (modelo = any (array['presencial-base'::text, 'seminario-atm'::text, 'jornada-captacao'::text]));

-- 2. a linha da Black
insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, periodo_inicio)
values ('black-friday-2026-10', 'jornada-captacao', 4, 'academy', date '2026-10-04')
on conflict (chave) do nothing;

-- 3. trava das RPCs da Black
create or replace function dados.black_cadastro(p_chave text)
 returns dados.dashboards
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  r dados.dashboards := dados.cadastro(p_chave);   -- 42501 sem acesso, P0002 chave fora do cadastro
begin
  if r.modelo is distinct from 'jornada-captacao' then
    raise exception 'dashboard de outro modelo' using errcode = 'P0002';
  end if;
  return r;
end
$function$;
revoke all on function dados.black_cadastro(text) from public, anon, authenticated, service_role;

-- 4. tráfego da Black
create or replace function public.dados_black_trafego(p_chave text, p_de date default null, p_ate date default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
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
  if not exists (select 1 from dados.dashboards where chave = 'black-friday-2026-10' and ativo and modelo = 'jornada-captacao'
                  and projeto_id = 4 and conta_hotmart = 'academy' and periodo_inicio = date '2026-10-04') then
    raise exception '20261013100000: a linha da Black não ficou como esperado';
  end if;
  if not has_function_privilege('authenticated', 'public.dados_black_trafego(text,date,date)', 'execute')
     or has_function_privilege('anon', 'public.dados_black_trafego(text,date,date)', 'execute')
     or has_function_privilege('service_role', 'public.dados_black_trafego(text,date,date)', 'execute')
     or has_function_privilege('authenticated', 'dados.black_cadastro(text)', 'execute')
     or has_function_privilege('anon', 'dados.black_cadastro(text)', 'execute') then
    raise exception '20261013100000: permissões erradas';
  end if;
end
$c$;

-- ===== TESTES =====
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '2 depois md5 atm_trafego (igual ao antes)', md5((select public.dados_atm_trafego('atm-elaine-1-2026-10'))::text);
create temp table _z_t on commit drop as select public.dados_black_trafego('black-friday-2026-10') as j, public.dados_black_trafego('black-friday-2026-10', '2026-10-10', '2026-10-12') as k;
insert into pg_temp._z_out (passo, linha) select '3 cabecalho', jsonb_build_object('de', j->'periodo_de', 'ate', j->'periodo_ate', 'anuncio_desde', j->'anuncio_desde', 'coletado_em', j->'coletado_em',
  'campanhas', jsonb_array_length(j->'campanhas'), 'conjuntos', jsonb_array_length(j->'conjuntos'), 'anuncios', jsonb_array_length(j->'anuncios'),
  'dias_campanha', jsonb_array_length(j->'dias_campanha'), 'dias_anuncio', jsonb_array_length(j->'dias_anuncio'))::text from pg_temp._z_t;
insert into pg_temp._z_out (passo, linha) select '3 campanhas', (select jsonb_agg(c - array['conta']) from jsonb_array_elements(j->'campanhas') c)::text from pg_temp._z_t;
insert into pg_temp._z_out (passo, linha) select '4 gasto 10-12/10 por campanha (centavos)', (select jsonb_object_agg(c->>'nome', (select sum((x->>'gasto_centavos')::bigint) from jsonb_array_elements(k->'dias_campanha') x where x->>'campanha_id' = c->>'id')) from jsonb_array_elements(k->'campanhas') c)::text from pg_temp._z_t;
insert into pg_temp._z_out (passo, linha) select '4 gasto 10-12/10 por anuncio somado na campanha', (select jsonb_object_agg(c->>'nome', (select sum((x->>'gasto_centavos')::bigint) from jsonb_array_elements(k->'dias_anuncio') x
   join jsonb_array_elements(k->'anuncios') a on a->>'id' = x->>'anuncio_id' join jsonb_array_elements(k->'conjuntos') s on s->>'id' = a->>'conjunto_id' where s->>'campanha_id' = c->>'id')) from jsonb_array_elements(k->'campanhas') c)::text from pg_temp._z_t;
insert into pg_temp._z_out (passo, linha) select '5 total desde 04/10 (centavos)', jsonb_build_object('campanha', (select sum((x->>'gasto_centavos')::bigint) from jsonb_array_elements(j->'dias_campanha') x),
  'anuncio', (select sum((x->>'gasto_centavos')::bigint) from jsonb_array_elements(j->'dias_anuncio') x),
  'primeiro_dia', (select min(x->>'dia') from jsonb_array_elements(j->'dias_campanha') x), 'ultimo_dia', (select max(x->>'dia') from jsonb_array_elements(j->'dias_campanha') x))::text from pg_temp._z_t;
reset role;
insert into pg_temp._z_out (passo, linha) select '5 conferencia direta na tabela (centavos)', (select round(sum(dd.gasto) * 100)::bigint from mkt_trafego.desempenho_dia dd join mkt_trafego.campanhas c on c.id = dd.campanha_id where c.nome ilike '%BF26%' and dd.dia >= '2026-10-04')::text;
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '6 sem url_tags nem miniatura', (select count(*) from jsonb_array_elements(j->'anuncios') a where a ? 'url_tags' or a ? 'miniatura_caminho')::text from pg_temp._z_t;
do $t$ begin perform public.dados_black_trafego('nao-existe');
  insert into pg_temp._z_out (passo, linha) values ('7 chave inexistente', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('7 chave inexistente', sqlstate); end $t$;
do $t$ begin perform public.dados_black_trafego('atm-elaine-1-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('7 chave do ATM na RPC da Black', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('7 chave do ATM na RPC da Black', sqlstate); end $t$;
do $t$ begin perform public.dados_atm_trafego('black-friday-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('7 chave da Black na RPC do ATM', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('7 chave da Black na RPC do ATM', sqlstate); end $t$;
do $t$ begin perform public.dados_black_trafego('black-friday-2026-10', '2026-10-12', '2026-10-10');
  insert into pg_temp._z_out (passo, linha) values ('7 de depois de ate', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('7 de depois de ate', sqlstate); end $t$;
do $t$ begin perform dados.black_cadastro('black-friday-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('7 equipe chama black_cadastro direto', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('7 equipe chama black_cadastro direto', sqlstate); end $t$;
-- risco registrado no explain: RPCs de outro modelo que usam dados.cadastro sem checar o modelo
do $t$
declare f record; n bigint;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname like 'dados\_%' and p.provolatile = 's' and p.pronargs >= 1
              and p.proargtypes[0] = 'text'::regtype and p.pronargdefaults = p.pronargs - 1 and p.proname not like 'dados\_black\_%'
            order by 1 loop
    begin
      -- offset 0 e o where obrigam a função a rodar (sem eles o planejador descarta a coluna que o count não usa)
      execute format('select count(*) from (select %I.%I(%L) as v offset 0) z where z.v is not distinct from z.v', 'public', f.proname, 'black-friday-2026-10') into n;
      insert into pg_temp._z_out (passo, linha) values ('8 outro modelo com a chave da Black', f.sig::text || ' => RODOU, linhas ' || n);
    exception when others then
      insert into pg_temp._z_out (passo, linha) values ('8 outro modelo com a chave da Black', f.sig::text || ' => ' || sqlstate);
    end;
  end loop;
end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000abcd","role":"authenticated"}', true);
set local role authenticated;
do $t$ begin perform public.dados_black_trafego('black-friday-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('7 fora da equipe', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('7 fora da equipe', sqlstate); end $t$;
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $t$ begin perform public.dados_black_trafego('black-friday-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('7 anon', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('7 anon', sqlstate); end $t$;
reset role;
-- teste A do pentester: outro dashboard jornada-captacao (projeto 1) não pode receber o tráfego da Black
insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, periodo_inicio)
values ('zz-pentest-jornada', 'jornada-captacao', 1, 'academy', date '2026-10-04');
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '11 outro projeto no mesmo modelo (BF26 esperado 0)', jsonb_build_object(
  'campanhas', jsonb_array_length(x->'campanhas'),
  'com_bf26', (select count(*) from jsonb_array_elements(x->'campanhas') c where c->>'nome' ~* '(^|\|)\s*BF26\s*(\||$)'),
  'projetos', (select jsonb_agg(distinct c->'projeto_id') from jsonb_array_elements(x->'campanhas') c))::text
  from (select public.dados_black_trafego('zz-pentest-jornada') x) z;
insert into pg_temp._z_out (passo, linha) select '11 Black: campanhas e projetos', jsonb_build_object(
  'campanhas', jsonb_array_length(x->'campanhas'),
  'projetos', (select jsonb_agg(distinct c->'projeto_id') from jsonb_array_elements(x->'campanhas') c),
  'nomes', (select jsonb_agg(c->>'id' order by (c->>'id')::bigint) from jsonb_array_elements(x->'campanhas') c))::text
  from (select public.dados_black_trafego('black-friday-2026-10') x) z;
reset role;
delete from dados.dashboards where chave = 'zz-pentest-jornada';
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '9 grants', (select string_agg(p.proname || '=' || coalesce(p.proacl::text,'null'), ' ; ' order by 1) from pg_proc p where p.proname in ('dados_black_trafego','black_cadastro'));
insert into pg_temp._z_out (passo, linha) select '9 linha', (select to_jsonb(d) - 'criado_em' from dados.dashboards d where chave = 'black-friday-2026-10')::text;

-- ===== REVERSÃO =====
-- Reversão de 20261013100000. Numa transação. ANTES: reverter a 20261013110000 (B), que usa dados.black_cadastro e grava
-- marcações de teste com a chave da Black (FK em dados.dashboards; o delete abaixo falha se ainda houver linha filha).
-- O dashboard da Black volta a não ter cadastro (a tela cai em "dashboard não cadastrado").

drop function if exists public.dados_black_trafego(text, date, date);
drop function if exists dados.black_cadastro(text);
delete from dados.dashboards where chave = 'black-friday-2026-10';
-- falha de propósito se outra linha tiver passado a usar o modelo jornada-captacao
alter table dados.dashboards drop constraint dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check
  check (modelo = any (array['presencial-base'::text, 'seminario-atm'::text]));

insert into pg_temp._z_out (passo, linha) select '10 depois da reversao', jsonb_build_object('trafego', to_regprocedure('public.dados_black_trafego(text,date,date)') is null,
  'cadastro', to_regprocedure('dados.black_cadastro(text)') is null, 'dashboards', (select count(*) from dados.dashboards),
  'check', (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'dados.dashboards'::regclass and conname = 'dashboards_modelo_check'))::text;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
