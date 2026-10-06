-- 20261006h: Marketing > Web, fase 2 (o que não depende do Luiz)
--
-- O QUE FAZ
--   Acrescenta à coleta da Web (20261006f) as leituras da segunda fase, todas sobre o que o nosso gravador já grava,
--   sem dado pessoal e sem mexer no gravador:
--     1. Fluxo: de onde para onde as pessoas andam entre as páginas na mesma visita, onde entram e onde saem
--        (mkt_web.visualizacoes, na ordem da visita).
--     2. Melhorias: os números que as regras de achados do Radar leem (oportunidades.ts do Luiz: dobra, promessa,
--        botão, seção, formulário, fricção, velocidade, "o que o MQL lê", "qual botão converte"), do período e do
--        período anterior de mesmo tamanho; os testes A/B entre variações da mesma página (ak1, ak1-b, ak1-c) saem dos
--        mesmos números; e a comparação de duas páginas ou dois períodos. As REGRAS rodam na tela
--        (web/modules/marketing/web/domain/achados.ts e testes-ab.ts), como no Radar (lá, src/lib/oportunidades.ts e
--        testes.ts); o banco só soma.
--     3. Mapa de calor sobre a página: pontos de clique (x em % da largura, y em fração da altura da página vista) e o
--        alcance da rolagem, com a captura de página inteira do teste do Google (item 4) como fundo.
--     4. PageSpeed de laboratório: tabela mkt_web.velocidade_lab e a rotina diária mkt-web-pagespeed (pg_cron →
--        ops.cron_post → Edge Function mkt-web-pagespeed → API pública do PageSpeed Insights), só para páginas ativas de
--        projeto com a coleta ligada. Chave do Google OPCIONAL, no Vault (mkt_web_pagespeed_api_key); sem ela, a cota
--        pública. Nunca no código.
--     5. Lead ligado à pessoa: quantos leads da Web estão na base de pessoas (20261005r_pessoas_e_crm_fundacao, por visitantes.lead_ref) e
--        quantos viraram MQL. A referência e o id da ficha só para quem pode ver a base (pessoas.pode_ver(): hoje
--        admin/dev). Sem a 20261005r_pessoas_e_crm_fundacao aplicada, responde "base": false e as telas continuam.
--     6. Páginas do PB26 para a virada: as 11 do patrimonio-brasil.json do Radar em mkt.paginas, só as que faltam.
--     7. Connect rate com o Tráfego (definição do Victor): page views de entrada da Web ÷ cliques no link da plataforma,
--        por campanha (mkt_trafego, 20261006g); conversão da página = leads ÷ page views. Sem a 20261006g aplicada,
--        responde "trafego": false; sem a coluna de cliques no link, connect rate nulo.
--   Fora (decisão do Victor ou depende de terceiros): gravação/replay, Diário com IA, reenvio ao ActiveCampaign,
--   publicações/deploys, importação do histórico do Radar, CRM do Luiz.
--
-- O QUE CRIA
--   mkt_web.velocidade_lab (tabela); mkt_web.config 'pagespeed' (ligado|desligado)
--   internas (sem grant, sem SECURITY DEFINER): mkt_web.melhorias_base, leitura_achados, comparar_bloco,
--     pagespeed_fila, pagespeed_guardar, pagespeed_credenciais
--   public.mkt_web_fluxo, _melhorias, _comparar, _calor, _lab, _leads, _connect → authenticated + mkt.pode_ver('mkt_web')
--   Vault: mkt_web_pagespeed_chave (header da rotina, aleatória, criada aqui). A chave do Google, se houver, entra à mão:
--     select vault.create_secret('<chave da API do PageSpeed>', 'mkt_web_pagespeed_api_key');
--   pg_cron: mkt-web-pagespeed 09:40 UTC (06:40 SP), pelo ops.cron_post (regra 11 do CLAUDE.md)
--   mkt.paginas: até 7 linhas (as do PB26 que faltarem), marcadas com obs '20261006h: …'
--
-- AS 5 PERGUNTAS
--   escala: a do PB (~1.500 visitas/dia, ~2 mil páginas vistas/dia, ~5 mil cliques/dia); 11 páginas × 2 aparelhos no
--     laboratório = até 22 testes por dia (a rotina faz no máximo 12 por chamada; o resto fica para o dia seguinte).
--   índice: usa os da 20261006f (sessoes (projeto_id, dia), visualizacoes (sessao, ordem) e (pagina_id, dia),
--     cliques (visualizacao), eventos (sessao)); velocidade_lab (pagina_id, estrategia, medido_em desc).
--   frequência: as telas leem ao abrir a aba (período até 92 dias); a rotina do Google, 1 vez por dia.
--   repetição: nenhuma query por linha; Melhorias roda a leitura de cada página com visita (no máximo 40).
--   reversão: bloco REVERSÃO no fim.
--
-- ENSAIO: 20261006h_ensaio.sql (begin … rollback), DEPOIS da 20261006f. Explicação: 20261006h.explain.md.
-- DEPENDE: 20261006f (não aplicada) e 20261005m (aplicada). Conversa com 20261005r_pessoas_e_crm_fundacao e 20261006g só se existirem.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regclass('mkt_web.sessoes') is null or to_regclass('mkt_web.visualizacoes') is null
     or to_regclass('mkt_web.paginas_mapa') is null or to_regprocedure('mkt_web.periodo_ok(date,date)') is null
     or to_regprocedure('mkt_web.origem_ids(text,text,text,text,text,text,text)') is null then
    raise exception '20261006h: falta a 20261006f (mkt_web.sessoes, visualizacoes, paginas_mapa, periodo_ok, origem_ids)';
  end if;
  if to_regclass('mkt.paginas') is null or to_regprocedure('mkt.pode_ver(text)') is null then
    raise exception '20261006h: falta a 20261005m (mkt.paginas, mkt.pode_ver)';
  end if;
  if to_regclass('mkt_web.velocidade_lab') is not null
     or exists (select 1 from pg_proc p
                 where (p.pronamespace = 'public'::regnamespace
                        and p.proname in ('mkt_web_fluxo', 'mkt_web_melhorias', 'mkt_web_comparar', 'mkt_web_calor',
                                          'mkt_web_lab', 'mkt_web_leads', 'mkt_web_connect'))
                    or (p.pronamespace = 'mkt_web'::regnamespace
                        and p.proname in ('melhorias_base', 'leitura_achados', 'comparar_bloco', 'pagespeed_fila',
                                          'pagespeed_guardar', 'pagespeed_credenciais'))) then
    raise exception '20261006h: já aplicada (mkt_web.velocidade_lab ou funções da fase 2 existem)';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception '20261006h: papel service_role ausente';
  end if;
end
$guarda$;

-- ─── 1. Páginas do PB26 que faltam (as 11 do patrimonio-brasil.json do Radar, pacote do Luiz de 05/10/2026) ──────────
-- Caminho, nome e tipo copiados do JSON ("paginas"); funil = o funil do JSON em que a página é etapa (ak1: "raiz" e
-- "ak1"; bl2: "bl2" e "bl2-otimizacao"); as outras não são etapa de funil (funil nulo). Código só onde o JSON usa o
-- padrão da casa (bl2). "/quase-la/" fica como a 20261005m cadastrou (função pesquisa, o "tipo" do JSON).
-- Idempotente: o que já existe (mesmo caminho ou mesmo código no projeto) não é tocado.
insert into mkt.paginas (projeto_id, codigo, nome, dominio, caminho, funcao, funil, obs)
select p.id, v.codigo, v.nome, 'patrimoniobrasil.com.br', v.caminho, v.funcao, v.funil,
       '20261006h: do patrimonio-brasil.json do Radar (id ' || v.radar || ')'
  from mkt.projetos p,
       (values (null, 'Raiz (captura)', '/', 'captura', 'ak1', 'raiz'),
               ('ak1', 'AK1', '/ak1/', 'captura', 'ak1', 'ak1'),
               ('bl2', 'BL2', '/bl2/', 'captura', 'bl2', 'bl2'),
               (null, 'BL2 otimização (teste)', '/bl2-otimizacao/', 'captura', 'bl2', 'bl2-otimizacao'),
               (null, 'Pesquisa da BL2', '/quase-la/', 'pesquisa', 'bl2', 'quase-la'),
               (null, 'Pesquisa pelo link', '/pesquisa/', 'pesquisa', 'recuperacao', 'pesquisa'),
               (null, 'Obrigado', '/obrigado/', 'obrigado', 'ak1', 'obrigado'),
               (null, 'Obrigado não MQL', '/inscricao-recebida/', 'obrigado', null, 'inscricao-recebida'),
               (null, 'Profissionais (outra área)', '/profissionais/', 'obrigado', null, 'profissionais'),
               (null, 'Profissionais: advogados', '/profissionais/advogados/', 'obrigado', null, 'profissionais-advogados'),
               (null, 'Profissionais: contadores', '/profissionais/contadores/', 'obrigado', null, 'profissionais-contadores')
       ) v(codigo, nome, caminho, funcao, funil, radar)
 where p.sigla = 'PB26'
on conflict do nothing;

-- ─── 2. Laboratório do Google (PageSpeed Insights) ───────────────────────────────────────────────────────────────────
-- Um teste por linha. Guardados os 60 mais recentes por página e aparelho; a captura (imagem da página inteira, a do
-- próprio teste do Google) só no mais recente: é o fundo do mapa de calor.
create table mkt_web.velocidade_lab (
  id            bigint generated always as identity primary key,
  pagina_id     bigint not null references mkt.paginas(id) on delete cascade,
  estrategia    text not null check (estrategia in ('mobile', 'desktop')),
  url           text not null check (url ~ '^https://' and length(url) <= 300),
  medido_em     timestamptz not null default now(),
  nota          smallint check (nota between 0 and 100),
  notas         jsonb check (notas is null or jsonb_typeof(notas) = 'object'),
  lcp_ms        int check (lcp_ms >= 0),
  fcp_ms        int check (fcp_ms >= 0),
  tbt_ms        int check (tbt_ms >= 0),
  si_ms         int check (si_ms >= 0),
  cls           real check (cls >= 0),
  oportunidades jsonb not null default '[]' check (jsonb_typeof(oportunidades) = 'array'),
  captura       jsonb check (captura is null or (jsonb_typeof(captura) = 'object' and length(captura::text) <= 2000000)),
  erro          text check (erro is null or length(erro) <= 200)
);
create index velocidade_lab_pagina on mkt_web.velocidade_lab (pagina_id, estrategia, medido_em desc);
comment on table mkt_web.velocidade_lab is
  'Teste de laboratório do Google (PageSpeed Insights) por página e aparelho, 1 vez por dia (rotina mkt-web-pagespeed). '
  'nota = desempenho 0-100; notas = desempenho, acessibilidade, praticas, seo; oportunidades = até 5 {id, titulo, ms}; '
  'captura = {img, largura, altura} só no mais recente; erro = o teste falhou (ex.: HTTP 429 da cota pública). 20261006h.';
alter table mkt_web.velocidade_lab enable row level security;
revoke all on mkt_web.velocidade_lab from public, anon, authenticated;

insert into mkt_web.config (chave, valor) values ('pagespeed', 'ligado') on conflict (chave) do nothing;

-- ─── 3. Rotina do Google (internas: a Edge entra como postgres pelo SUPABASE_DB_URL; sem grant) ─────────────────────
-- O que medir agora: páginas ativas de projeto com a coleta ligada, os dois aparelhos, sem teste nas últimas 20 horas,
-- primeiro as que estão há mais tempo sem teste.
create function mkt_web.pagespeed_fila(p_limite int default 12)
returns table (pagina_id bigint, url text, estrategia text)
language sql stable set search_path = '' as $$
  select pg.id, 'https://' || pg.dominio || pg.caminho, e.estrategia
    from mkt.paginas pg
    join mkt_web.funis f on f.projeto_id = pg.projeto_id and f.coleta
    cross join (values ('mobile'), ('desktop')) e(estrategia)
    left join lateral (select max(l.medido_em) as ultimo from mkt_web.velocidade_lab l
                        where l.pagina_id = pg.id and l.estrategia = e.estrategia) u on true
   where pg.ativa
     and coalesce((select c.valor from mkt_web.config c where c.chave = 'pagespeed'), 'ligado') <> 'desligado'
     and coalesce((select c.valor from mkt_web.config c where c.chave = 'coleta'), 'ligada') <> 'pausada'
     and (u.ultimo is null or u.ultimo < now() - interval '20 hours')
   order by u.ultimo nulls first, pg.id, e.estrategia
   limit greatest(1, least(coalesce(p_limite, 12), 40))
$$;

-- Guarda um teste (o que a Edge resumiu da resposta do Google). Responde 'ok' ou o motivo da recusa.
create function mkt_web.pagespeed_guardar(p jsonb) returns text
language plpgsql set search_path = '' as $$
declare
  v_pag mkt.paginas;
  v_est text := p ->> 'estrategia';
  v_cap jsonb := case when jsonb_typeof(p -> 'captura') = 'object'
                       and coalesce(p -> 'captura' ->> 'img', '') ~ '^data:image/(jpeg|png|webp);base64,'
                       and length((p -> 'captura')::text) <= 2000000 then
                   jsonb_build_object('img', p -> 'captura' ->> 'img',
                                      'largura', mkt_web.faixa(p -> 'captura' ->> 'largura', 0, 10000),
                                      'altura', mkt_web.faixa(p -> 'captura' ->> 'altura', 0, 100000)) end;
  v_notas jsonb;
  v_opo jsonb;
begin
  select * into v_pag from mkt.paginas where id = mkt_web.inteiro(p ->> 'pagina_id', 0);
  if not found then return 'pagina'; end if;
  if v_est is null or v_est not in ('mobile', 'desktop') then return 'estrategia'; end if;
  if coalesce(p ->> 'url', '') !~ '^https://' then return 'url'; end if;
  if jsonb_typeof(p -> 'notas') = 'object' then
    select jsonb_object_agg(k, mkt_web.faixa(p -> 'notas' ->> k, 0, 100)) into v_notas
      from unnest(array['desempenho', 'acessibilidade', 'praticas', 'seo']) k
     where coalesce(p -> 'notas' ->> k, '') ~ '^[0-9]{1,3}$';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', left(x ->> 'id', 60), 'titulo', left(x ->> 'titulo', 160),
                                               'ms', mkt_web.faixa(x ->> 'ms', 0, 600000))), '[]'::jsonb)
    into v_opo
    from (select x from jsonb_array_elements(case when jsonb_typeof(p -> 'oportunidades') = 'array'
                                                  then p -> 'oportunidades' else '[]'::jsonb end) x limit 5) y;
  insert into mkt_web.velocidade_lab (pagina_id, estrategia, url, nota, notas, lcp_ms, fcp_ms, tbt_ms, si_ms, cls,
                                      oportunidades, captura, erro)
  values (v_pag.id, v_est, left(p ->> 'url', 300), mkt_web.opcional(p ->> 'nota', 100)::smallint, v_notas,
          mkt_web.opcional(p ->> 'lcp_ms', 600000)::int, mkt_web.opcional(p ->> 'fcp_ms', 600000)::int,
          mkt_web.opcional(p ->> 'tbt_ms', 600000)::int, mkt_web.opcional(p ->> 'si_ms', 600000)::int,
          case when coalesce(p ->> 'cls', '') ~ '^[0-9]{1,3}(\.[0-9]+)?$' then least((p ->> 'cls')::real, 10) end,
          v_opo, v_cap, left(nullif(p ->> 'erro', ''), 200));
  -- 60 por página e aparelho; a captura só no mais recente que tem captura
  delete from mkt_web.velocidade_lab l
   where l.id in (select x.id from mkt_web.velocidade_lab x where x.pagina_id = v_pag.id and x.estrategia = v_est
                   order by x.medido_em desc, x.id desc offset 60);
  if v_cap is not null then
    update mkt_web.velocidade_lab l set captura = null
     where l.pagina_id = v_pag.id and l.estrategia = v_est and l.captura is not null
       and l.id <> (select max(x.id) from mkt_web.velocidade_lab x
                     where x.pagina_id = v_pag.id and x.estrategia = v_est and x.captura is not null);
  end if;
  return 'ok';
end
$$;

-- A chave do header da rotina e a chave (opcional) da API do Google, lidas do Vault. Sem Vault (banco local), nulas.
create function mkt_web.pagespeed_credenciais() returns table (chave text, api_key text)
language plpgsql stable set search_path = '' as $$
begin
  if to_regclass('vault.decrypted_secrets') is null then
    return query select null::text, null::text;
    return;
  end if;
  return query execute
    'select (select s.decrypted_secret from vault.decrypted_secrets s where s.name = ''mkt_web_pagespeed_chave''),
            (select s.decrypted_secret from vault.decrypted_secrets s where s.name = ''mkt_web_pagespeed_api_key'')';
end
$$;

-- ─── 4. Melhorias: os números que as regras de achados leem (porte de radar.api_oportunidades e radar.api_leitura) ──
-- Leitura de UMA página (seções, botões e formulário), no formato do api_leitura do Radar (banco 023 do Luiz), com as
-- mesmas definições: seção "vista" = 1 s ou mais na linha de leitura; "chegaram" = a seção mais funda vista está nela ou
-- depois; primeiro botão = o primeiro data-cta do desenho da página; o botão que converte = o último data-cta clicado
-- até 2 s depois do evento de lead; formulário em degraus por visita única (mesma pessoa pelo mesmo anúncio):
-- 1 viu, 2 abriu, 3 começou (preencheu ou errou), 4 enviou (lead depois de abrir). Só visitas que apareceram na tela.
create function mkt_web.leitura_achados(p_projeto bigint, p_pagina bigint, p_de date, p_ate date) returns jsonb
language sql stable set search_path = '' as $$
with
s as materialized (
  select x.id, x.lead, (x.resultado = 'mql') is true as mql, x.dispositivo, x.visivel_ms as s_vis,
         x.visitante || '|' || coalesce(oi.anuncio_id, oi.anuncio_nome, '') as unidade
    from mkt_web.sessoes x
    cross join lateral mkt_web.origem_ids(x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content,
                                          x.campaign_id, x.adset_id, x.ad_id) oi
   where x.projeto_id = p_projeto and x.dia between p_de and p_ate and not x.teste),
cfg as (select coalesce(f.eventos_lead, '{}') as leads from (select 1) um left join mkt_web.funis f on f.projeto_id = p_projeto),
m as (select coalesce(pm.secoes, '{}') as secoes, coalesce(pm.ctas, '{}') as ctas, coalesce(pm.campos, '{}') as campos
        from (select 1) um left join mkt_web.paginas_mapa pm on pm.pagina_id = p_pagina),
b as materialized (
  select w.id, w.sessao, w.inicio, w.visivel_ms, w.secoes, w.ctas, w.form, s.dispositivo, s.lead, s.mql, s.unidade
    from mkt_web.visualizacoes w join s on s.id = w.sessao
   where w.projeto_id = p_projeto and w.pagina_id = p_pagina and s.s_vis > 0),
lead_ev as (
  select e.sessao, min(e.quando) as quando
    from mkt_web.eventos e join s on s.id = e.sessao cross join cfg
   where e.projeto_id = p_projeto and e.nome = any (cfg.leads) group by e.sessao),
sv as materialized (
  select b.id, b.lead, b.mql, e.key as secao, mkt_web.inteiro(e.value, 0) as seg,
         coalesce(array_position(m.secoes, e.key), 999) as ordem
    from b cross join m cross join lateral jsonb_each_text(b.secoes) e
   where b.secoes is not null and mkt_web.inteiro(e.value, 0) > 0),
fundo as (select id, max(ordem) filter (where ordem < 999) as ate from sv group by id),
nomes_s as (
  select secao, min(ordem) as ordem
    from (select x.secao, x.o::int as ordem from m, unnest(m.secoes) with ordinality x(secao, o)
          union all select secao, ordem from sv) y
   group by secao),
cv as materialized (
  select b.id, e.key as cta, mkt_web.inteiro(e.value, 0) as visto
    from b cross join lateral jsonb_each_text(b.ctas) e where b.ctas is not null),
cl as materialized (
  select c.sessao, c.quando, substring(c.seletor from 'data-cta="([^"]+)"') as cta
    from mkt_web.cliques c join s on s.id = c.sessao
   where c.projeto_id = p_projeto and c.pagina_id = p_pagina and c.seletor like '%data-cta=%' and not c.automatico),
ult as (
  select distinct on (cl.sessao) cl.sessao, cl.cta
    from cl join lead_ev le on le.sessao = cl.sessao cross join m
   where cl.cta = any (m.ctas) and cl.quando <= le.quando + interval '2 seconds'
   order by cl.sessao, cl.quando desc),
nomes_c as (
  select cta, min(ordem) as ordem
    from (select x.cta, x.o::int as ordem from m, unnest(m.ctas) with ordinality x(cta, o)
          union all select cta, 999 from cv) y
   group by cta),
pc as (
  select b.dispositivo, b.lead, (b.visivel_ms >= 10000) as ficou, mkt_web.inteiro(b.ctas ->> m.ctas[1], 0) > 0 as viu
    from b cross join m where b.ctas is not null and cardinality(m.ctas) > 0),
ab as (
  select distinct e.visualizacao as id
    from mkt_web.eventos e join s on s.id = e.sessao
   where e.projeto_id = p_projeto and e.pagina_id = p_pagina
     and e.nome in ('abriu_formulario', 'abriu_form', 'form_aberto', 'formulario_aberto')),
fc0 as materialized (
  select b.id, c.key as campo, mkt_web.inteiro(c.value ->> 0, 0) as focos, mkt_web.inteiro(c.value ->> 1, 0) as seg,
         mkt_web.inteiro(c.value ->> 2, 0) as preenchido, mkt_web.inteiro(c.value ->> 3, 0) as erros
    from b cross join lateral jsonb_each(case when jsonb_typeof(b.form -> 'c') = 'object' then b.form -> 'c' else '{}'::jsonb end) c
   where b.form is not null),
fcs as (select id, bool_or(preenchido > 0 or erros > 0) as mexeu, bool_or(focos > 0) as entrou from fc0 group by id),
fs as (
  select b.id, b.inicio, b.unidade, b.dispositivo, mkt_web.inteiro(b.form ->> 't', 0) as tempo, b.form ->> 'u' as ultimo,
         mkt_web.inteiro(b.form ->> 'v', 0) > 0 as viu, ab.id is not null as abriu,
         coalesce(fcs.mexeu, false) as mexeu, coalesce(fcs.entrou, false) as entrou,
         coalesce(le.quando >= b.inicio - interval '5 seconds', false) as lead_depois
    from b left join ab on ab.id = b.id left join fcs on fcs.id = b.id left join lead_ev le on le.sessao = b.sessao
   where b.form is not null),
fm as materialized (
  select fs.*,
         case when fs.lead_depois and (fs.viu or fs.abriu or fs.mexeu or fs.entrou) then 4
              when fs.mexeu then 3
              when fs.abriu or fs.entrou then 2
              when fs.viu then 1
              else 0 end as nivel
    from fs),
fu as materialized (select distinct on (unidade) unidade, dispositivo, nivel, ultimo from fm order by unidade, nivel desc, inicio desc),
fct as (
  select fm.unidade, fc0.campo, fc0.focos, fc0.preenchido, fc0.erros,
         (fc0.preenchido > 0 or fc0.erros > 0 or (fc0.focos > 0 and fm.nivel >= 3)) as tocou
    from fc0 join fm on fm.id = fc0.id),
campos_a as (
  select campo, count(distinct unidade) filter (where tocou) as tocaram, count(distinct unidade) filter (where focos > 0) as focaram,
         count(distinct unidade) filter (where erros > 0) as com_erro
    from fct group by campo),
parou as (select ultimo as campo, count(*) as n from fu where nivel = 3 and coalesce(ultimo, '') <> '' group by ultimo),
nomes_f as (
  select y.campo, min(y.ordem) as ordem
    from (select x.campo, x.o::int as ordem from m, unnest(m.campos) with ordinality x(campo, o)
          union all select campo, 999 from campos_a union all select campo, 999 from parou) y
   where exists (select 1 from campos_a a where a.campo = y.campo and a.tocaram > 0) or exists (select 1 from parou p where p.campo = y.campo)
   group by y.campo)
select jsonb_build_object(
  'pagina_id', p_pagina,
  'visitas', (select count(*) from b),
  'medidas', (select count(*) from b where secoes is not null),
  'medidas_lead', (select count(*) from b where secoes is not null and lead),
  'medidas_mql', (select count(*) from b where secoes is not null and mql),
  'secoes', coalesce((
     select jsonb_agg(jsonb_build_object('secao', n.secao, 'ordem', n.ordem, 'viram', coalesce(a.viram, 0),
              'chegaram', (select count(*) from fundo x where x.ate >= n.ordem),
              'viram_lead', coalesce(a.vl, 0), 'viram_mql', coalesce(a.vm, 0)) order by n.ordem, n.secao)
       from nomes_s n
       left join (select secao, count(*) as viram, count(*) filter (where lead) as vl, count(*) filter (where mql) as vm
                    from sv group by secao) a on a.secao = n.secao), '[]'::jsonb),
  'primeiro_cta', coalesce((
     select jsonb_agg(jsonb_build_object('dispositivo', dispositivo, 'medidas', n, 'viram', viu, 'ficaram', ficaram,
                                         'ficaram_sem_ver', sem_ver, 'leads_de_quem_viu', leads_viu) order by n desc)
       from (select dispositivo, count(*) as n, count(*) filter (where viu) as viu, count(*) filter (where ficou) as ficaram,
                    count(*) filter (where ficou and not viu) as sem_ver, count(*) filter (where ficou and viu and lead) as leads_viu
               from pc group by 1) x), '[]'::jsonb),
  'ctas', coalesce((
     select jsonb_agg(jsonb_build_object('cta', n.cta, 'ordem', n.ordem, 'medidas', coalesce(a.medidas, 0), 'viram', coalesce(a.viram, 0),
              'clicaram', (select count(distinct cl.sessao) from cl where cl.cta = n.cta),
              'leads', (select count(*) from ult where ult.cta = n.cta)) order by n.ordem, n.cta)
       from nomes_c n
       left join (select cta, count(*) as medidas, count(*) filter (where visto > 0) as viram from cv group by cta) a on a.cta = n.cta), '[]'::jsonb),
  'leads_com_botao', (select count(*) from ult),
  'form', jsonb_build_object(
     'viram', (select count(*) from fu where nivel >= 1),
     'abriram', (select count(*) from fu where nivel >= 2),
     'comecaram', (select count(*) from fu where nivel >= 3),
     'enviaram', (select count(*) from fu where nivel >= 4),
     'campos', coalesce((
        select jsonb_agg(jsonb_build_object('campo', n.campo, 'ordem', n.ordem, 'tocaram', coalesce(a.tocaram, 0),
                 'focaram', coalesce(a.focaram, 0), 'com_erro', coalesce(a.com_erro, 0), 'pararam', coalesce(p.n, 0))
                 order by n.ordem, n.campo)
          from nomes_f n left join campos_a a on a.campo = n.campo left join parou p on p.campo = n.campo), '[]'::jsonb)))
$$;

-- Os números por página do período (formato do api_oportunidades do Radar, banco 024/025 do Luiz). Entrada "conta" se
-- a visita engajou ou já fechou (30 min sem pacote); "rejeitou" = fechou sem engajar. p_leve = só o que o período
-- anterior precisa (entradas, rejeições, leads).
create function mkt_web.melhorias_base(p_projeto bigint, p_de date, p_ate date, p_leve boolean) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_out jsonb;
  v_leit jsonb := '[]'::jsonb;
  r record;
begin
  with
  s as materialized (
    select x.id, x.dia, x.dispositivo, x.lead, x.engajada, (x.resultado = 'mql') is true as mql, x.entrada_pagina_id,
           oi.campanha_id, oi.campanha_nome, oi.anuncio_id, oi.anuncio_nome,
           (x.engajada or x.recebido_em < now() - interval '30 minutes') as conta,
           (not x.engajada and x.recebido_em < now() - interval '30 minutes') as rejeitou
      from mkt_web.sessoes x
      cross join lateral mkt_web.origem_ids(x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content,
                                            x.campaign_id, x.adset_id, x.ad_id) oi
     where x.projeto_id = p_projeto and x.dia between p_de and p_ate and not x.teste),
  v as materialized (
    select w.id, w.sessao, w.pagina_id, w.ordem, w.lcp_ms
      from mkt_web.visualizacoes w join s on s.id = w.sessao where w.projeto_id = p_projeto and w.pagina_id is not null),
  pass as (
    select v.pagina_id, count(*) as visitas, count(distinct v.sessao) as sessoes,
           count(distinct v.sessao) filter (where s.lead) as leads, count(distinct v.sessao) filter (where s.mql) as mql,
           count(distinct s.dia) as dias
      from v join s on s.id = v.sessao group by v.pagina_id),
  ent as materialized (
    select s.entrada_pagina_id as pagina_id, s.id, s.dia, s.dispositivo, s.lead, s.mql, s.conta, s.rejeitou,
           -- campanha e criativo (anúncio) no formato nome|id do gp-operacoes: agrupados pelo id; mostram o nome
           coalesce(s.campanha_id, s.campanha_nome) as campanha_k, coalesce(s.campanha_nome, s.campanha_id, '(sem campanha)') as campanha,
           coalesce(s.anuncio_id, s.anuncio_nome) as criativo_k, coalesce(s.anuncio_nome, s.anuncio_id, '') as criativo,
           s.anuncio_id as criativo_id
      from s where s.entrada_pagina_id is not null),
  ent_pg as (
    select pagina_id, count(*) filter (where conta) as entradas, count(*) filter (where rejeitou) as rejeicoes,
           count(*) filter (where conta and lead) as leads, count(*) filter (where conta and mql) as mql
      from ent group by pagina_id),
  fr_cl as (
    select c.pagina_id, c.sessao, bool_or(c.raiva) as raiva
      from mkt_web.cliques c join s on s.id = c.sessao
     where c.projeto_id = p_projeto and c.pagina_id is not null and (c.raiva or c.morto) and not c.automatico
     group by 1, 2),
  fr_er as (
    select distinct e.pagina_id, e.sessao from mkt_web.erros e join s on s.id = e.sessao
     where e.projeto_id = p_projeto and e.pagina_id is not null and e.origem = 'pagina'),
  fr as (
    select p.pagina_id, s.lead, coalesce(c.raiva, false) as raiva, (e.sessao is not null) as erro
      from (select distinct pagina_id, sessao from v) p
      join s on s.id = p.sessao and s.engajada
      left join fr_cl c on c.pagina_id = p.pagina_id and c.sessao = p.sessao
      left join fr_er e on e.pagina_id = p.pagina_id and e.sessao = p.sessao),
  fr_pg as (
    select pagina_id, count(*) filter (where raiva) as com_raiva, count(*) filter (where erro) as com_erro,
           count(*) filter (where raiva or erro) as com_friccao, count(*) filter (where (raiva or erro) and lead) as friccao_leads,
           count(*) filter (where not (raiva or erro)) as sem_friccao, count(*) filter (where not (raiva or erro) and lead) as sem_leads
      from fr group by pagina_id)
  select jsonb_build_object(
    'sessoes', (select count(*) from s),
    'leads', (select count(*) from s where s.lead),
    'dias', (select count(distinct s.dia) from s),
    'paginas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'pagina_id', p.pagina_id, 'codigo', pg.codigo, 'nome', pg.nome, 'funcao', pg.funcao, 'caminho', pg.caminho,
               'visitas', p.visitas, 'sessoes', p.sessoes, 'leads', p.leads, 'mql', p.mql, 'dias', p.dias,
               'entradas', coalesce(e.entradas, 0), 'rejeicoes', coalesce(e.rejeicoes, 0),
               'leads_entrada', coalesce(e.leads, 0), 'mql_entrada', coalesce(e.mql, 0))
             || case when p_leve then '{}'::jsonb else jsonb_build_object(
               'por_aparelho', coalesce((
                  select jsonb_agg(jsonb_build_object('dispositivo', x.dispositivo, 'entradas', x.n, 'rejeicoes', x.r, 'leads', x.l) order by x.n desc)
                    from (select ent.dispositivo, count(*) filter (where ent.conta) as n, count(*) filter (where ent.rejeitou) as r,
                                 count(*) filter (where ent.conta and ent.lead) as l
                            from ent where ent.pagina_id = p.pagina_id group by 1) x where x.n > 0), '[]'::jsonb),
               'por_criativo', coalesce((
                  select jsonb_agg(jsonb_build_object('campanha', x.campanha, 'criativo', x.criativo, 'criativo_id', x.criativo_id,
                                                      'entradas', x.n, 'rejeicoes', x.r, 'leads', x.l) order by x.n desc)
                    from (select max(ent.campanha) as campanha, max(ent.criativo) as criativo, max(ent.criativo_id) as criativo_id,
                                 count(*) filter (where ent.conta) as n, count(*) filter (where ent.rejeitou) as r,
                                 count(*) filter (where ent.conta and ent.lead) as l
                            from ent where ent.pagina_id = p.pagina_id group by ent.campanha_k, ent.criativo_k
                           order by 4 desc limit 10) x where x.n > 0), '[]'::jsonb),
               'friccao', (select to_jsonb(fp) - 'pagina_id' from fr_pg fp where fp.pagina_id = p.pagina_id),
               'lcp', coalesce((
                  select jsonb_agg(jsonb_build_object('faixa', x.faixa, 'entradas', x.n, 'rejeicoes', x.r, 'leads', x.l) order by x.faixa)
                    from (select case when v.lcp_ms <= 2500 then 'bom' when v.lcp_ms <= 4000 then 'medio' else 'ruim' end as faixa,
                                 count(*) filter (where ent.conta) as n, count(*) filter (where ent.rejeitou) as r,
                                 count(*) filter (where ent.conta and ent.lead) as l
                            from v join ent on ent.id = v.sessao
                           where v.pagina_id = p.pagina_id and v.ordem = 1 and v.lcp_ms is not null group by 1) x), '[]'::jsonb),
               'por_dia', coalesce((
                  select jsonb_agg(jsonb_build_object('dia', x.dia, 'entradas', x.n) order by x.dia)
                    from (select ent.dia, count(*) filter (where ent.conta) as n from ent where ent.pagina_id = p.pagina_id group by 1) x), '[]'::jsonb))
             end
             order by p.sessoes desc)
        from pass p join mkt.paginas pg on pg.id = p.pagina_id left join ent_pg e on e.pagina_id = p.pagina_id), '[]'::jsonb))
  into v_out;

  if p_leve then return v_out; end if;
  for r in select (x ->> 'pagina_id')::bigint as pagina_id from jsonb_array_elements(v_out -> 'paginas') x
            where (x ->> 'visitas')::int > 0 limit 40 loop
    v_leit := v_leit || jsonb_build_array(mkt_web.leitura_achados(p_projeto, r.pagina_id, p_de, p_ate));
  end loop;
  return v_out || jsonb_build_object('leituras', v_leit);
end
$$;

-- Os números de UMA página (ou do projeto inteiro, p_pagina nulo) num período: a base de "Comparar". As taxas são sobre
-- as visitas que viram a página (como o Comparar do Radar).
create function mkt_web.comparar_bloco(p_projeto bigint, p_pagina bigint, p_de date, p_ate date) returns jsonb
language sql stable set search_path = '' as $$
  with s as materialized (
    select x.* from mkt_web.sessoes x where x.projeto_id = p_projeto and x.dia between p_de and p_ate and not x.teste
  ), pv as materialized (
    select w.* from mkt_web.visualizacoes w join s on s.id = w.sessao
     where w.projeto_id = p_projeto and (p_pagina is null or w.pagina_id = p_pagina)
  ), vs as materialized (
    select s.* from s where exists (select 1 from pv where pv.sessao = s.id)
  ), ent as (
    select s.* from s where (p_pagina is null or s.entrada_pagina_id = p_pagina)
  )
  select jsonb_build_object(
    'pagina_id', p_pagina, 'de', p_de, 'ate', p_ate,
    'nome', (select pg.nome from mkt.paginas pg where pg.id = p_pagina),
    'caminho', (select pg.caminho from mkt.paginas pg where pg.id = p_pagina),
    'visitas', (select count(*) from vs),
    'leads', (select count(*) from vs where vs.lead),
    'mql', (select count(*) from vs where vs.resultado = 'mql'),
    'entradas', (select count(*) from ent),
    'rejeicoes', (select count(*) from ent where not ent.engajada),
    'leads_entrada', (select count(*) from ent where ent.lead),
    'vistas', (select count(*) from pv),
    'rolagem_media', (select coalesce(round(avg(pv.rolagem)), 0) from pv),
    'visivel_ms_medio', (select coalesce(round(avg(pv.visivel_ms)), 0) from pv),
    'lcp_p75', (select (percentile_cont(0.75) within group (order by pv.lcp_ms))::int from pv),
    'dias', (select count(distinct vs.dia) from vs),
    'por_aparelho', coalesce((select jsonb_agg(jsonb_build_object('chave', t.k, 'visitas', t.n, 'leads', t.l) order by t.n desc)
                                from (select vs.dispositivo k, count(*) n, count(*) filter (where vs.lead) l from vs group by 1) t), '[]'::jsonb),
    'por_origem', coalesce((select jsonb_agg(jsonb_build_object('chave', t.k, 'visitas', t.n, 'leads', t.l) order by t.n desc)
                              from (select coalesce(vs.utm_source, '(direto)') k, count(*) n, count(*) filter (where vs.lead) l
                                      from vs group by 1 order by 2 desc limit 8) t), '[]'::jsonb))
$$;

-- ─── 5. Leitura para as telas (authenticated; trava mkt.pode_ver('mkt_web'), hoje admin/dev) ───────────────────────
-- Fluxo: a visita como sequência de caminhos (recarregar a mesma página não conta como passo). Entradas, saídas,
-- passagens de uma página para a outra (com "(saiu)") e os caminhos mais comuns (até 5 passos).
create function public.mkt_web_fluxo(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  return (
    with s as materialized (
      select x.id, x.lead from mkt_web.sessoes x where x.projeto_id = p_projeto and x.dia between p_de and p_ate and not x.teste
    ), pv0 as (
      select w.sessao, w.ordem, w.caminho, s.lead, lag(w.caminho) over (partition by w.sessao order by w.ordem) as antes
        from mkt_web.visualizacoes w join s on s.id = w.sessao where w.projeto_id = p_projeto
    ), pv as materialized (
      select sessao, caminho, lead, row_number() over (partition by sessao order by ordem) as passo,
             lead(caminho) over (partition by sessao order by ordem) as prox
        from pv0 where antes is distinct from caminho
    ), por_sessao as materialized (
      select sessao, bool_or(lead) as lead, count(*) as passos,
             array_agg(caminho order by passo) filter (where passo <= 5) as seq
        from pv group by sessao
    )
    select jsonb_build_object(
      'sessoes', (select count(*) from por_sessao),
      'uma_pagina', (select count(*) from por_sessao where passos = 1),
      'passos_medio', (select coalesce(round(avg(passos), 2), 0) from por_sessao),
      'nomes', coalesce((select jsonb_object_agg(pg.caminho, pg.nome) from mkt.paginas pg where pg.projeto_id = p_projeto), '{}'::jsonb),
      'paginas', coalesce((select jsonb_agg(jsonb_build_object('caminho', t.caminho, 'vistas', t.vistas, 'entradas', t.entradas,
                                                             'saidas', t.saidas, 'leads', t.leads) order by t.vistas desc)
                             from (select pv.caminho, count(distinct pv.sessao) as vistas,
                                          count(*) filter (where pv.passo = 1) as entradas,
                                          count(*) filter (where pv.prox is null) as saidas,
                                          count(distinct pv.sessao) filter (where pv.lead) as leads
                                     from pv group by pv.caminho order by 2 desc limit 40) t), '[]'::jsonb),
      'passagens', coalesce((select jsonb_agg(jsonb_build_object('de', t.de, 'para', t.para, 'n', t.n, 'leads', t.l) order by t.n desc)
                               from (select pv.caminho as de, coalesce(pv.prox, '(saiu)') as para, count(*) as n,
                                            count(*) filter (where pv.lead) as l
                                       from pv group by 1, 2 order by 3 desc limit 80) t), '[]'::jsonb),
      'caminhos', coalesce((select jsonb_agg(jsonb_build_object('passos', t.seq, 'mais', t.mais, 'n', t.n, 'leads', t.l) order by t.n desc)
                              from (select ps.seq, ps.passos > 5 as mais, count(*) as n, count(*) filter (where ps.lead) as l
                                      from por_sessao ps group by 1, 2 order by 3 desc limit 15) t), '[]'::jsonb)));
end
$$;

-- Melhorias: o período (com as leituras de cada página) e o anterior de mesmo tamanho (só os números de entrada)
create function public.mkt_web_melhorias(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_dias int;
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  v_dias := p_ate - p_de + 1;
  return jsonb_build_object(
    'de', p_de, 'ate', p_ate, 'antes_de', p_de - v_dias, 'antes_ate', p_de - 1,
    'atual', mkt_web.melhorias_base(p_projeto, p_de, p_ate, false),
    'antes', mkt_web.melhorias_base(p_projeto, p_de - v_dias, p_de - 1, true));
end
$$;

-- Comparar: duas páginas no mesmo período, ou a mesma página (ou o projeto, página nula) em dois períodos
create function public.mkt_web_comparar(p_projeto bigint, p_pagina_a bigint, p_de_a date, p_ate_a date,
                                        p_pagina_b bigint, p_de_b date, p_ate_b date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de_a, p_ate_a);
  perform mkt_web.periodo_ok(p_de_b, p_ate_b);
  if (p_pagina_a is not null and not exists (select 1 from mkt.paginas pg where pg.id = p_pagina_a and pg.projeto_id = p_projeto))
     or (p_pagina_b is not null and not exists (select 1 from mkt.paginas pg where pg.id = p_pagina_b and pg.projeto_id = p_projeto)) then
    raise exception 'página de outro projeto' using errcode = '22023';
  end if;
  return jsonb_build_object('a', mkt_web.comparar_bloco(p_projeto, p_pagina_a, p_de_a, p_ate_a),
                            'b', mkt_web.comparar_bloco(p_projeto, p_pagina_b, p_de_b, p_ate_b));
end
$$;

-- Mapa de calor de uma página num aparelho: pontos (x %, y como fração da altura da página vista, tipo 0 clique,
-- 1 raiva, 2 morto, 3 os dois, índice do elemento), até 5.000 por amostra estável; o alcance da rolagem a cada 5%;
-- a largura e a altura medianas; a captura do último teste do Google do mesmo aparelho (celular/tablet = mobile).
-- O elemento fixo na tela (janela, barra) não tem lugar na página: fica fora dos pontos e é contado à parte.
create function public.mkt_web_calor(p_projeto bigint, p_pagina bigint, p_dispositivo text, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_est text := case when p_dispositivo = 'desktop' then 'desktop' else 'mobile' end;
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  if p_dispositivo is null or p_dispositivo not in ('mobile', 'tablet', 'desktop') then
    raise exception 'aparelho inválido' using errcode = '22023';
  end if;
  return (
    with s as materialized (
      select x.id from mkt_web.sessoes x
       where x.projeto_id = p_projeto and x.dia between p_de and p_ate and not x.teste and x.dispositivo = p_dispositivo
    ), vv as materialized (
      select w.id, w.rolagem, w.largura, w.altura_doc from mkt_web.visualizacoes w join s on s.id = w.sessao
       where w.projeto_id = p_projeto and w.pagina_id = p_pagina
    ), cl as materialized (
      select c.id, c.x_pct, c.y_px, c.seletor, c.texto, c.raiva, c.morto, c.fixo, vv.altura_doc
        from mkt_web.cliques c join vv on vv.id = c.visualizacao
       where c.projeto_id = p_projeto and not c.automatico
    ), des as materialized (
      select * from cl where not cl.fixo and cl.altura_doc > 0
    ), el as materialized (
      select des.seletor, max(des.texto) as txt, (row_number() over (order by count(*) desc, des.seletor) - 1)::int as i
        from des group by des.seletor
    ), pts as (
      select d.x_pct, d.y_px, d.altura_doc, d.raiva, d.morto, e.i
        from (select * from des order by hashtext(des.id::text), des.id limit 5000) d join el e on e.seletor = d.seletor
    )
    select jsonb_build_object(
      'url', (select 'https://' || pg.dominio || pg.caminho from mkt.paginas pg where pg.id = p_pagina and pg.projeto_id = p_projeto),
      'visitas', (select count(*) from vv),
      'largura', (select (percentile_cont(0.5) within group (order by vv.largura))::int from vv where vv.largura > 0),
      'altura_doc', (select (percentile_cont(0.5) within group (order by vv.altura_doc))::int from vv where vv.altura_doc > 0),
      'pontos', coalesce((select jsonb_agg(jsonb_build_array(round(pts.x_pct::numeric, 1),
                                                             round(least(pts.y_px::numeric / pts.altura_doc, 1), 4),
                                                             pts.raiva::int + 2 * pts.morto::int, pts.i)) from pts), '[]'::jsonb),
      'amostra', (select count(*) > 5000 from des),
      'elementos', coalesce((select jsonb_agg(jsonb_build_array(el.seletor, el.txt) order by el.i) from el where el.i < 200), '[]'::jsonb),
      'contagem', (select jsonb_build_object('cliques', count(*) filter (where not cl.fixo), 'raiva', count(*) filter (where not cl.fixo and cl.raiva),
                                             'mortos', count(*) filter (where not cl.fixo and cl.morto), 'fixos', count(*) filter (where cl.fixo))
                     from cl),
      'alcance', (select jsonb_agg((select count(*) from vv where vv.rolagem >= g) order by g) from generate_series(0, 100, 5) g),
      'top', coalesce((select jsonb_agg(jsonb_build_object('sel', t.seletor, 'txt', t.txt, 'n', t.n, 'raiva', t.rv, 'morto', t.mt, 'fixo', t.fixo) order by t.n desc)
                         from (select cl.seletor, max(cl.texto) as txt, count(*) as n, count(*) filter (where cl.raiva) as rv,
                                      count(*) filter (where cl.morto) as mt, bool_or(cl.fixo) as fixo
                                 from cl group by 1 order by 3 desc limit 15) t), '[]'::jsonb),
      'captura', (select jsonb_build_object('img', l.captura ->> 'img', 'largura', l.captura -> 'largura',
                                            'altura', l.captura -> 'altura', 'medido_em', l.medido_em)
                    from mkt_web.velocidade_lab l
                   where l.pagina_id = p_pagina and l.estrategia = v_est and l.captura is not null
                     and exists (select 1 from mkt.paginas pg where pg.id = p_pagina and pg.projeto_id = p_projeto)
                   order by l.medido_em desc limit 1)));
end
$$;

-- Laboratório do Google por página e aparelho: o último teste (com o anterior, para a variação) e a nota dos 30 mais
-- recentes. Só páginas do projeto. "ligado" = a rotina está ligada; "coleta" = o projeto tem a coleta ligada.
create function public.mkt_web_lab(p_projeto bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object(
    'ligado', coalesce((select c.valor from mkt_web.config c where c.chave = 'pagespeed'), 'ligado') <> 'desligado',
    'coleta', coalesce((select f.coleta from mkt_web.funis f where f.projeto_id = p_projeto), false),
    'paginas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'pagina_id', pg.id, 'nome', pg.nome, 'caminho', pg.caminho, 'estrategia', e.estrategia,
               'ultimo', (select jsonb_build_object('medido_em', l.medido_em, 'nota', l.nota, 'notas', l.notas, 'lcp_ms', l.lcp_ms,
                                                    'fcp_ms', l.fcp_ms, 'tbt_ms', l.tbt_ms, 'si_ms', l.si_ms, 'cls', l.cls,
                                                    'oportunidades', l.oportunidades, 'erro', l.erro)
                            from mkt_web.velocidade_lab l where l.pagina_id = pg.id and l.estrategia = e.estrategia
                           order by l.medido_em desc, l.id desc limit 1),
               'anterior_nota', (select l.nota from mkt_web.velocidade_lab l
                                  where l.pagina_id = pg.id and l.estrategia = e.estrategia and l.nota is not null
                                  order by l.medido_em desc, l.id desc offset 1 limit 1),
               'serie', coalesce((select jsonb_agg(jsonb_build_object('quando', t.medido_em, 'nota', t.nota, 'lcp_ms', t.lcp_ms) order by t.medido_em)
                                    from (select l.medido_em, l.nota, l.lcp_ms from mkt_web.velocidade_lab l
                                           where l.pagina_id = pg.id and l.estrategia = e.estrategia and l.nota is not null
                                           order by l.medido_em desc limit 30) t), '[]'::jsonb))
             order by pg.caminho, e.estrategia desc)
        from mkt.paginas pg cross join (values ('mobile'), ('desktop')) e(estrategia)
       where pg.projeto_id = p_projeto and (pg.ativa or exists (select 1 from mkt_web.velocidade_lab l where l.pagina_id = pg.id))), '[]'::jsonb));
end
$$;

-- Lead ligado à pessoa: leads da Web (visitas com evento de lead) cujo navegador tem a referência da base de pessoas
-- (visitantes.lead_ref = pessoas.pessoas.ref, gravada por pessoas.registrar da 20261005r_pessoas_e_crm_fundacao do Arthur
-- quando o formulário manda o visitante) e quantas dessas pessoas viraram MQL no projeto. Sem a base de pessoas, só os
-- números da Web ("base": false). A lista (referência opaca e o id da ficha) só para quem pode ver a base
-- (pessoas.pode_ver(): hoje admin/dev). Nunca nome, e-mail ou telefone.
create function public.mkt_web_leads(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_base boolean := to_regclass('pessoas.pessoas') is not null and to_regclass('pessoas.eventos') is not null
                    and to_regprocedure('pessoas.pode_ver()') is not null and to_regprocedure('pessoas.atual(uuid)') is not null
                    and to_regprocedure('pessoas.grupo(uuid)') is not null;
  v_pode boolean := false;
  v_web jsonb;
  v_pes jsonb;
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  select jsonb_build_object(
           'leads_web', count(*) filter (where s.lead),
           'navegadores_lead', count(distinct s.visitante) filter (where s.lead),
           'com_ref', count(distinct s.visitante) filter (where s.lead and vi.lead_ref is not null))
    into v_web
    from mkt_web.sessoes s left join mkt_web.visitantes vi on vi.projeto_id = s.projeto_id and vi.id = s.visitante
   where s.projeto_id = p_projeto and s.dia between p_de and p_ate and not s.teste;
  if not v_base then
    return v_web || jsonb_build_object('base', false, 'pode_abrir', false, 'pessoas', null, 'mql', null, 'nao_mql', null, 'lista', '[]'::jsonb);
  end if;
  execute 'select coalesce(pessoas.pode_ver(), false)' into v_pode;
  -- base do Arthur (20261005r_pessoas_e_crm_fundacao): pessoa mesclada segue para a que ficou no fim da cadeia
  -- (pessoas.atual) e os eventos contam no grupo inteiro (pessoas.grupo: a atual + as que apontam para ela); pessoa de
  -- teste (a que ficou) fica fora
  execute $q$
    with refs as (
      select vi.lead_ref, max(s.lead_em) as quando
        from mkt_web.sessoes s join mkt_web.visitantes vi on vi.projeto_id = s.projeto_id and vi.id = s.visitante
       where s.projeto_id = $1 and s.dia between $2 and $3 and not s.teste and s.lead and vi.lead_ref is not null
       group by vi.lead_ref
    ), pes0 as (
      select r.lead_ref, r.quando, pessoas.atual(p.id) as pessoa_id
        from refs r join pessoas.pessoas p on p.ref = r.lead_ref
    ), pes as (
      -- uma linha por pessoa atual (dois navegadores da mesma pessoa = uma pessoa), a referência mais recente
      select distinct on (x.pessoa_id) x.lead_ref, max(x.quando) over (partition by x.pessoa_id) as quando, x.pessoa_id
        from pes0 x join pessoas.pessoas a on a.id = x.pessoa_id
       where not a.teste
       order by x.pessoa_id, x.quando desc nulls last
    ), ev as (
      select pes.pessoa_id, bool_or(e.tipo = 'mql') as mql, bool_or(e.tipo = 'nao_mql') as nao_mql
        from pes left join pessoas.eventos e on e.pessoa_id = any(pessoas.grupo(pes.pessoa_id)) and e.projeto_id = $1
                                            and e.tipo in ('mql', 'nao_mql')
       group by pes.pessoa_id
    )
    select jsonb_build_object(
      'pessoas', (select count(*) from ev),
      'mql', (select count(*) from ev where ev.mql),
      'nao_mql', (select count(*) from ev where ev.nao_mql and not ev.mql),
      'lista', case when $4 then coalesce((
        select jsonb_agg(jsonb_build_object('ref', t.lead_ref, 'pessoa_id', t.pessoa_id, 'quando', t.quando,
                                            'mql', coalesce(ev.mql, false), 'nao_mql', coalesce(ev.nao_mql, false)) order by t.quando desc nulls last)
          from (select * from pes order by pes.quando desc nulls last limit 50) t left join ev on ev.pessoa_id = t.pessoa_id), '[]'::jsonb)
        else '[]'::jsonb end)
  $q$ into v_pes using p_projeto, p_de, p_ate, v_pode;
  return v_web || v_pes || jsonb_build_object('base', true, 'pode_abrir', v_pode);
end
$$;

-- Connect rate (definição do Victor, 05/10/2026): page views ÷ cliques no link; conversão da página: leads ÷ page views.
-- Por campanha do Tráfego (20261006g) do projeto: gasto, impressões e cliques no link da plataforma no período contra as
-- page views de ENTRADA da Web vindas da mesma campanha (a página de destino do anúncio; uma por visita). Casa pelo ID
-- da campanha (campaign_id da URL, ou o id do utm_campaign no formato nome|id do gp-operacoes, ou utm_campaign só id);
-- sem id na visita, pelo NOME exato (a parte do nome do utm_campaign). Leitura de mkt_web.origem_ids (20261006f); a
-- mesma regra está em mkt_trafego.resumo (20261006g). A coluna de cliques no link é procurada pelo nome
-- (cliques_link ou cliques_no_link); sem ela, connect rate fica nulo (nunca cai para "todos os cliques").
-- Por anúncio (utm_content = o anúncio/criativo em nome|id; agrupado pelo id) só a Web: o Tráfego ainda não guarda
-- clique por anúncio. Sem a 20261006g, "trafego": false.
create function public.mkt_web_connect(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_trafego boolean := to_regclass('mkt_trafego.campanhas') is not null and to_regclass('mkt_trafego.desempenho_dia') is not null;
  v_col text;
  v_camp jsonb := '[]'::jsonb;
  v_sem jsonb;
  v_anun jsonb;
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  select coalesce(jsonb_agg(jsonb_build_object('anuncio', coalesce(t.nome, t.aid), 'anuncio_id', t.aid, 'campanha', t.c,
                                                'page_views', t.n, 'engajadas', t.e, 'leads', t.l) order by t.n desc), '[]'::jsonb)
    into v_anun
    from (select max(oi.anuncio_id) aid, max(oi.anuncio_nome) nome, coalesce(min(oi.campanha_nome), min(oi.campanha_id)) c,
                 count(*) n, count(*) filter (where s.engajada) e, count(*) filter (where s.lead) l
            from mkt_web.sessoes s
            cross join lateral mkt_web.origem_ids(s.utm_source, s.utm_medium, s.utm_campaign, s.utm_content,
                                                  s.campaign_id, s.adset_id, s.ad_id) oi
           where s.projeto_id = p_projeto and s.dia between p_de and p_ate and not s.teste
             and coalesce(oi.anuncio_id, oi.anuncio_nome) is not null
           group by coalesce(oi.anuncio_id, oi.anuncio_nome) order by 4 desc limit 30) t;
  if not v_trafego then
    return jsonb_build_object('trafego', false, 'cliques_link', false, 'campanhas', '[]'::jsonb, 'sem_campanha', null, 'anuncios', v_anun);
  end if;
  select c.column_name into v_col from information_schema.columns c
   where c.table_schema = 'mkt_trafego' and c.table_name = 'desempenho_dia' and c.column_name in ('cliques_link', 'cliques_no_link')
   order by c.column_name limit 1;
  execute format($q$
    with c as (
      select c.id, c.plataforma, c.campanha_externa, c.nome, c.leitura ->> 'pagina' as pagina
        from mkt_trafego.campanhas c where c.projeto_id = $1
    ), d as (
      select d.campanha_id, sum(d.gasto) as gasto, sum(d.impressoes) as impressoes, %s as cliques_link, count(*) as dias
        from mkt_trafego.desempenho_dia d join c on c.id = d.campanha_id
       where d.dia between $2 and $3 group by d.campanha_id
    ), s as (
      select x.id, oi.campanha_id, oi.campanha_nome, x.engajada, x.lead
        from mkt_web.sessoes x
        cross join lateral mkt_web.origem_ids(x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content,
                                              x.campaign_id, x.adset_id, x.ad_id) oi
       where x.projeto_id = $1 and x.dia between $2 and $3 and not x.teste
    ), m as (
      select c.id, count(s.id) as page_views, count(s.id) filter (where s.engajada) as engajadas, count(s.id) filter (where s.lead) as leads
        from c left join s on s.campanha_id = c.campanha_externa or (s.campanha_id is null and s.campanha_nome = c.nome)
       group by c.id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'campanha', c.nome, 'campanha_externa', c.campanha_externa, 'plataforma', c.plataforma, 'pagina', c.pagina,
             'gasto', d.gasto, 'impressoes', d.impressoes, 'cliques_link', d.cliques_link, 'dias_com_gasto', coalesce(d.dias, 0),
             'page_views', m.page_views, 'engajadas', m.engajadas, 'leads', m.leads,
             'connect_rate', case when d.cliques_link > 0 then round(m.page_views::numeric / d.cliques_link, 4) end,
             'conversao', case when m.page_views > 0 then round(m.leads::numeric / m.page_views, 4) end)
             order by d.gasto desc nulls last, m.page_views desc), '[]'::jsonb)
      from c join m on m.id = c.id left join d on d.campanha_id = c.id
     where d.campanha_id is not null or m.page_views > 0
  $q$, case when v_col is null then 'null::bigint' else format('sum(d.%I)', v_col) end)
  into v_camp using p_projeto, p_de, p_ate;
  -- page views com campanha (id ou nome) que não casam com nenhuma campanha cadastrada no Tráfego
  execute $q$
    select jsonb_build_object('page_views', count(*), 'campanhas', count(distinct coalesce(oi.campanha_id, oi.campanha_nome)))
      from mkt_web.sessoes x
      cross join lateral mkt_web.origem_ids(x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content,
                                            x.campaign_id, x.adset_id, x.ad_id) oi
     where x.projeto_id = $1 and x.dia between $2 and $3 and not x.teste and coalesce(oi.campanha_id, oi.campanha_nome) is not null
       and not exists (select 1 from mkt_trafego.campanhas c
                        where c.projeto_id = $1 and (oi.campanha_id = c.campanha_externa
                                                     or (oi.campanha_id is null and oi.campanha_nome = c.nome)))
  $q$ into v_sem using p_projeto, p_de, p_ate;
  return jsonb_build_object('trafego', true, 'cliques_link', v_col is not null, 'campanhas', v_camp, 'sem_campanha', v_sem, 'anuncios', v_anun);
end
$$;

-- ─── 6. Quem executa o quê ───────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where (p.pronamespace = 'mkt_web'::regnamespace
                   and p.proname in ('melhorias_base', 'leitura_achados', 'comparar_bloco', 'pagespeed_fila',
                                     'pagespeed_guardar', 'pagespeed_credenciais'))
               or (p.pronamespace = 'public'::regnamespace
                   and p.proname in ('mkt_web_fluxo', 'mkt_web_melhorias', 'mkt_web_comparar', 'mkt_web_calor',
                                     'mkt_web_lab', 'mkt_web_leads', 'mkt_web_connect')) loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end
$grants$;
revoke all on function mkt_web.pagespeed_credenciais() from service_role;
grant execute on function
  public.mkt_web_fluxo(bigint, date, date), public.mkt_web_melhorias(bigint, date, date),
  public.mkt_web_comparar(bigint, bigint, date, date, bigint, date, date),
  public.mkt_web_calor(bigint, bigint, text, date, date), public.mkt_web_lab(bigint),
  public.mkt_web_leads(bigint, date, date), public.mkt_web_connect(bigint, date, date)
  to authenticated;

-- ─── 7. Rotina do Google (pg_cron → ops.cron_post → Edge mkt-web-pagespeed). Horário do cron em UTC ───────────────
-- A chave do header é aleatória, criada aqui no Vault; a Edge confere. Sem pg_cron, ops.cron_post ou Vault (banco
-- local), não agenda (aviso). A Edge precisa estar publicada ANTES de a rotina rodar (senão o vigia acusa 404).
do $cron$
begin
  if to_regnamespace('cron') is null or to_regprocedure('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)') is null
     or to_regclass('vault.decrypted_secrets') is null then
    raise notice '20261006h: pg_cron, ops.cron_post ou Vault ausente; rotina mkt-web-pagespeed NÃO agendada';
    return;
  end if;
  if not exists (select 1 from vault.secrets where name = 'mkt_web_pagespeed_chave') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
      'mkt_web_pagespeed_chave', 'Header x-sync-chave do cron mkt-web-pagespeed (Edge mkt-web-pagespeed confere). 20261006h.');
  end if;
  perform cron.schedule('mkt-web-pagespeed', '40 9 * * *', $c$
    select ops.cron_post('mkt-web-pagespeed',
      url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/mkt-web-pagespeed',
      body := '{}'::jsonb,
      headers := jsonb_build_object('Content-Type', 'application/json',
        'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'mkt_web_pagespeed_chave')),
      timeout_milliseconds := 150000)
  $c$);
end
$cron$;

-- ─── 8. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  f record;
  v_publicas text[] := array['mkt_web_fluxo', 'mkt_web_melhorias', 'mkt_web_comparar', 'mkt_web_calor', 'mkt_web_lab',
                             'mkt_web_leads', 'mkt_web_connect'];
  v_internas text[] := array['melhorias_base', 'leitura_achados', 'comparar_bloco', 'pagespeed_fila', 'pagespeed_guardar',
                             'pagespeed_credenciais'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_web', 'usage') then raise exception '20261006h: % tem acesso ao schema mkt_web', r; end if;
    if has_table_privilege(r, 'mkt_web.velocidade_lab', 'select, insert, update, delete, truncate, references, trigger') then
      raise exception '20261006h: % tem privilégio em mkt_web.velocidade_lab', r;
    end if;
  end loop;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'mkt_web.velocidade_lab'::regclass) then
    raise exception '20261006h: RLS desligada em mkt_web.velocidade_lab';
  end if;
  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where (p.pronamespace = 'public'::regnamespace and p.proname = any (v_publicas))
               or (p.pronamespace = 'mkt_web'::regnamespace and p.proname = any (v_internas)) loop
    if not (f.proconfig @> array['search_path=""']) then raise exception '20261006h: % sem search_path vazio', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') then raise exception '20261006h: anon executa %', f.sig; end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261006h: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261006h: grant de authenticated errado em %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> f.prosecdef then
      raise exception '20261006h: SECURITY DEFINER errado em % (públicas sim, internas não)', f.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (v_publicas)) <> 7
     or (select count(*) from pg_proc p where p.pronamespace = 'mkt_web'::regnamespace and p.proname = any (v_internas)) <> 6 then
    raise exception '20261006h: esperava 7 funções públicas e 6 internas';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação; apaga os testes do Google e as funções da fase 2; a coleta da 20261006f fica) ═══════
-- begin;
-- select cron.unschedule('mkt-web-pagespeed') where exists (select 1 from cron.job where jobname = 'mkt-web-pagespeed');
-- do $$ declare f regprocedure; begin
--   for f in select p.oid::regprocedure from pg_proc p
--             where (p.pronamespace = 'public'::regnamespace and p.proname in ('mkt_web_fluxo', 'mkt_web_melhorias',
--                    'mkt_web_comparar', 'mkt_web_calor', 'mkt_web_lab', 'mkt_web_leads', 'mkt_web_connect'))
--                or (p.pronamespace = 'mkt_web'::regnamespace and p.proname in ('melhorias_base', 'leitura_achados',
--                    'comparar_bloco', 'pagespeed_fila', 'pagespeed_guardar', 'pagespeed_credenciais'))
--   loop execute format('drop function %s', f); end loop; end $$;
-- drop table mkt_web.velocidade_lab;
-- delete from mkt_web.config where chave = 'pagespeed';
-- -- as páginas do PB26 que esta migration criou (só se ninguém as usa: visitas e campanhas soltam a página sozinhas)
-- delete from mkt.paginas where obs like '20261006h:%';
-- -- o segredo do header fica no Vault (inofensivo sem a rotina); para apagar: delete from vault.secrets where name = 'mkt_web_pagespeed_chave';
-- commit;
