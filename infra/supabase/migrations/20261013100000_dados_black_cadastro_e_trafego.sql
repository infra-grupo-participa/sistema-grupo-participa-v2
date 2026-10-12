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
