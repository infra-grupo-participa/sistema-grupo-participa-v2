-- Marketing > Web: SEED DE DESENVOLVIMENTO. NUNCA RODAR EM PRODUÇÃO.
--
-- Para quê: encher mkt_web com visitas INVENTADAS do PB26 (14 dias) num banco LOCAL (PGlite, Postgres local ou um
-- Supabase de teste) que já tenha as migrations 20261005m e 20261006f, e ver as RPCs public.mkt_web_* e as telas
-- com números. Tudo que este script cria tem id começando por "dev" e sai com o bloco LIMPAR do fim.
--
-- Trava: só roda depois de
--   select set_config('app.mkt_web_seed', 'sou-banco-de-dev', false);
-- e aborta se mkt_web.sessoes já tiver qualquer visita que não seja "dev" (sinal de banco com coleta de verdade).
--
-- Para ver as telas SEM banco (o caso normal do Victor), use o modo de demonstração do front:
-- NEXT_PUBLIC_WEB_DEMO=1 em web/.env.local (ver docs/central-de-dados.md, seção Web).

do $trava$
begin
  if coalesce(current_setting('app.mkt_web_seed', true), '') <> 'sou-banco-de-dev' then
    raise exception 'seed de DEV: rode antes select set_config(''app.mkt_web_seed'', ''sou-banco-de-dev'', false). NUNCA em produção.';
  end if;
  if exists (select 1 from mkt_web.sessoes where id not like 'dev%') then
    raise exception 'seed de DEV: mkt_web.sessoes tem visitas que não são de dev (banco de verdade?). Abortado.';
  end if;
  if not exists (select 1 from mkt.projetos where sigla = 'PB26') then
    raise exception 'seed de DEV: PB26 não está em mkt.projetos (falta a 20261005m?)';
  end if;
end
$trava$;

begin;
-- refaz do zero o que é de dev
delete from mkt_web.sessoes where id like 'dev%';
delete from mkt_web.visitantes where id like 'dev%';

create temp table _dev on commit drop as
with p as (select id from mkt.projetos where sigla = 'PB26'),
     g as (select n, (mkt_web.hoje() - (n % 14))::date as dia, random() as r1, random() as r2, random() as r3, random() as r4
             from generate_series(1, 4200) n)
select 'dev' || lpad(n::text, 9, '0') as sid, 'devv' || lpad((n * 7 % 3600)::text, 8, '0') as vis, p.id as projeto_id, g.*,
       case when r1 < 0.88 then 'mobile' when r1 < 0.95 then 'desktop' else 'tablet' end as disp,
       case when r2 < 0.60 then 'ig' when r2 < 0.88 then 'fb' when r2 < 0.95 then null else 'google' end as fonte,
       r3 < 0.55 as engaja, r3 < 0.11 as lead, r4 < 0.012 as raiva
  from g, p;

insert into mkt_web.visitantes (projeto_id, id, sessoes)
select projeto_id, vis, count(*) from _dev group by 1, 2;

insert into mkt_web.sessoes (id, projeto_id, visitante, dia, inicio, fim, dispositivo, utm_source, utm_medium, utm_campaign,
                             utm_content, fbclid, gclid, entrada_pagina_id, entrada_caminho, saida_caminho, paginas, cliques, raiva,
                             mortos, eventos_funil, visivel_ms, engajada, engajou_por, lead, sistema, navegador, app)
select d.sid, d.projeto_id, d.vis, d.dia, d.dia + time '10:00' + (d.r1 * interval '12 hours'), d.dia + time '10:01' + (d.r1 * interval '12 hours'),
       d.disp, d.fonte, case when d.fonte is null then null when d.fonte = 'google' then 'cpc' else 'paid' end,
       -- UTM no padrão do gp-operacoes: Meta em nome|id (o id depois da última "|"), Google só id
       case when d.fonte in ('ig', 'fb') then case when d.r4 < 0.6 then 'RS | PB26 | LEADS | DEV A | AK1|120200000000000100' else 'CF | PB26 | LEADS | DEV B|120200000000000200' end
            when d.fonte = 'google' then '22000000000' end,
       case when d.fonte in ('ig', 'fb') then 'CRIATIVO DEV ' || (1 + (d.n % 4)) || '|12020000000000000' || (1 + (d.n % 4))
            when d.fonte = 'google' then '700000000001' end,
       coalesce(d.fonte in ('ig', 'fb'), false), coalesce(d.fonte = 'google', false),
       (select pg.id from mkt.paginas pg where pg.projeto_id = d.projeto_id and pg.caminho = '/ak1/'), '/ak1/',
       case when d.lead then '/obrigado/' else '/ak1/' end, case when d.lead then 2 else 1 end,
       case when d.engaja then 1 + (d.n % 3) else 0 end, case when d.raiva then 3 else 0 end, (d.n % 9 = 0)::int,
       case when d.lead then 3 when d.engaja and d.r2 < 0.5 then 1 else 0 end,
       case when d.engaja then 15000 + (d.r2 * 90000)::int else 1000 + (d.r2 * 7000)::int end,
       d.engaja or d.lead, case when d.lead then 'evento' when d.engaja then 'tempo' end, d.lead,
       case when d.disp = 'desktop' then 'Windows' when d.r2 < 0.5 then 'Android' else 'iOS' end,
       case when d.r4 < 0.7 then 'Instagram' else 'Chrome' end, case when d.r4 < 0.7 then 'instagram' end
  from _dev d;

insert into mkt_web.visualizacoes (id, sessao, projeto_id, pagina_id, dominio, caminho, titulo, dia, ordem, inicio, fim, dispositivo,
                                   largura, altura_doc, rolagem, rolagem_30s, visivel_ms, ativo_ms, vaivem, lcp_ms, inp_ms, cls, fcp_ms,
                                   ttfb_ms, peso_kb, secoes, ctas, form)
select 'devpv' || substr(d.sid, 4), d.sid, d.projeto_id, (select pg.id from mkt.paginas pg where pg.projeto_id = d.projeto_id and pg.caminho = '/ak1/'),
       'patrimoniobrasil.com.br', '/ak1/', 'AK1 (dev)', d.dia, 1, d.dia + time '10:00', d.dia + time '10:01', d.disp,
       case when d.disp = 'desktop' then 1440 else 390 end, 9000,
       case when d.engaja then 40 + (d.r2 * 60)::int else 5 + (d.r2 * 30)::int end, 10 + (d.r3 * 40)::int,
       case when d.engaja then 15000 + (d.r2 * 90000)::int else 1000 + (d.r2 * 7000)::int end, 8000, (d.n % 4),
       1200 + (d.r1 * 3400)::int, 60 + (d.r3 * 400)::int, round((d.r4 * 0.2)::numeric, 3), 800 + (d.r1 * 1200)::int, 200 + (d.r2 * 500)::int, 900,
       jsonb_build_object('topo', 5 + (d.n % 8), 'padrao', case when d.engaja then 4 + (d.n % 12) else 0 end, 'faq', case when d.engaja and d.r2 > 0.6 then 3 else 0 end),
       jsonb_build_object('topo', 1, 'virada', (d.engaja)::int, 'final', (d.engaja and d.r2 > 0.6)::int),
       case when d.engaja then jsonb_build_object('v', 1, 't', 20 + (d.n % 40), 's', d.lead::int, 'u', case when d.lead then 'telefone' when d.r4 < 0.5 then 'email' else 'telefone' end,
            'c', jsonb_build_object('nome', jsonb_build_array(1, 5, 1, 0), 'email', jsonb_build_array(1, 8, 1, (d.n % 11 = 0)::int),
                                    'telefone', jsonb_build_array((d.r3 < 0.4)::int, 10, (d.lead)::int, (d.n % 7 = 0)::int))) end
  from _dev d;

insert into mkt_web.visualizacoes (id, sessao, projeto_id, pagina_id, dominio, caminho, titulo, dia, ordem, inicio, fim, dispositivo, rolagem, visivel_ms, lcp_ms)
select 'devob' || substr(d.sid, 4), d.sid, d.projeto_id, (select pg.id from mkt.paginas pg where pg.projeto_id = d.projeto_id and pg.caminho = '/obrigado/'),
       'patrimoniobrasil.com.br', '/obrigado/', 'Obrigado (dev)', d.dia, 2, d.dia + time '10:02', d.dia + time '10:03', d.disp, 90, 9000, 1400
  from _dev d where d.lead;

insert into mkt_web.eventos (sessao, visualizacao, projeto_id, pagina_id, dia, quando, nome, dados)
select d.sid, 'devpv' || substr(d.sid, 4), d.projeto_id, null, d.dia, d.dia + time '10:00', e.nome, '{}'
  from _dev d, lateral (values ('abriu_formulario'), ('lead_qualificado')) e(nome)
 where (e.nome = 'abriu_formulario' and (d.lead or (d.engaja and d.r2 < 0.5))) or (e.nome = 'lead_qualificado' and d.lead);

insert into mkt_web.cliques (sessao, visualizacao, projeto_id, pagina_id, dia, dispositivo, quando, x_pct, y_px, seletor, texto, raiva, morto, automatico)
select d.sid, 'devpv' || substr(d.sid, 4), d.projeto_id, null, d.dia, d.disp, d.dia + time '10:00', 50, 800,
       case when d.raiva then 'div.modal-fundo' when d.n % 9 = 0 then 'img.foto-especialista' else 'button[data-cta="topo"]' end,
       case when d.raiva or d.n % 9 = 0 then '' else 'Quero participar' end, d.raiva, d.n % 9 = 0, false
  from _dev d where d.engaja;

insert into mkt_web.erros (sessao, visualizacao, projeto_id, pagina_id, dia, quando, mensagem, arquivo, linha, origem, tipo_fora)
select d.sid, 'devpv' || substr(d.sid, 4), d.projeto_id, null, d.dia, d.dia + time '10:00',
       case when d.n % 50 = 0 then 'Cannot read properties of null (dev)' else 'Error invoking postMessage: Java object is gone' end,
       case when d.n % 50 = 0 then 'form.js' else '' end, 1, case when d.n % 50 = 0 then 'pagina' else 'fora' end,
       case when d.n % 50 = 0 then null else 'app_android' end
  from _dev d where d.n % 10 = 0;

-- páginas vistas e cliques ganham o id da página cadastrada
update mkt_web.eventos e set pagina_id = w.pagina_id from mkt_web.visualizacoes w where w.id = e.visualizacao and e.sessao like 'dev%';
update mkt_web.cliques c set pagina_id = w.pagina_id from mkt_web.visualizacoes w where w.id = c.visualizacao and c.sessao like 'dev%';
update mkt_web.erros x set pagina_id = w.pagina_id from mkt_web.visualizacoes w where w.id = x.visualizacao and x.sessao like 'dev%';
update mkt_web.sessoes set erros = 1 where id in (select sessao from mkt_web.erros where origem = 'pagina' and sessao like 'dev%');

insert into mkt_web.paginas_mapa (pagina_id, secoes, ctas, campos)
select pg.id, '{topo,padrao,faq}', '{topo,virada,final}', '{nome,email,telefone}'
  from mkt.paginas pg join mkt.projetos p on p.id = pg.projeto_id where p.sigla = 'PB26' and pg.caminho = '/ak1/'
on conflict (pagina_id) do nothing;

select mkt_web.agregar(d::date) from generate_series(mkt_web.hoje() - 13, mkt_web.hoje() - 2, interval '1 day') d;
commit;

select count(*) as sessoes_dev from mkt_web.sessoes where id like 'dev%';

-- ═══ LIMPAR (apaga só o que é de dev) ════════════════════════════════════════════════════════════════════════════════
-- delete from mkt_web.sessoes where id like 'dev%';            -- leva visualizações, eventos, cliques e erros junto
-- delete from mkt_web.visitantes where id like 'dev%';
-- delete from mkt_web.resumo_dia where projeto_id = (select id from mkt.projetos where sigla = 'PB26');
