-- 20261005q: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql), DEPOIS da
--   20261005n (o ensaio dela não serve: ela precisa estar aplicada, ou rodar este arquivo logo depois do corpo dela na
--   mesma transação). Todo resultado vai para a tabela temporária _z_out; o penúltimo comando mostra tudo. Se o cliente
--   só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia, e rode o "rollback;"
--   em seguida. NÃO deixe a transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261005q_mkt_web_fase2.sql; se a migration
-- mudar, gerar de novo). Depois dele, os testes criam DADOS FICTÍCIOS (projeto ZZWEB98 "ZZ Ensaio Web 2" em
-- exemplo.invalid, páginas /zz1/ (zz1), /zz1-b/ (zz1-b) e /obrigado-zz/, 5 visitas inventadas, 1 delas de teste) e
-- chamam as funções como a tela chamaria (JWT simulado, role authenticated com o perfil admin do Victor) e como a rotina
-- do Google (postgres). Nenhum dado real vai para a saída. Tudo some no rollback.
--
-- Esperado: NENHUMA linha começando com "ERRADO". Cada linha diz o que conferiu. Os passos 7 (base de pessoas,
-- 20261005o) e 8 (Tráfego, 20261005p) só conferem o caminho completo se essas migrations estiverem aplicadas; sem elas,
-- conferem que a tela responde "base": false / "trafego": false sem erro.
--   1  estrutura: tabela velocidade_lab fechada, 7 funções públicas e 6 internas, as 11 páginas do PB26, a rotina
--      mkt-web-pagespeed (se houver pg_cron, ops.cron_post e Vault) sem segredo no comando
--   2  fluxo: visitas, uma página só, passos, entradas/saídas por página, passagens com "(saiu)", recarregar não conta
--   3  melhorias: entradas, rejeições, leads, por aparelho, LCP por faixa, fricção, período anterior, leitura da página
--      (seções, primeiro botão, botão que converte, formulário em degraus)
--   4  comparar: duas páginas no mesmo período e o projeto em dois períodos; página de outro projeto recusada
--   5  mapa de calor: pontos (fixo e automático fora), contagem, alcance da rolagem, largura/altura medianas, captura
--   6  laboratório do Google: guardar (recusas, 60 por página, captura só no último), fila, desligar, leitura da tela
--   7  lead ligado à pessoa   8  connect rate   8b UTM nome|id (gp-operacoes): por criativo, anúncios e Tráfego pelo id
--   9  período acima de 92 dias recusado
--   10 sem perfil, operador (mesmo com a área mkt_web), visualizador e anon: recusa 42501 nas 7 funções e no select
--   Qualquer ERRO no meio = a migration não serve como está: não aplicar.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;

-- ═══ CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if to_regclass('mkt_web.sessoes') is null or to_regclass('mkt_web.visualizacoes') is null
     or to_regclass('mkt_web.paginas_mapa') is null or to_regprocedure('mkt_web.periodo_ok(date,date)') is null
     or to_regprocedure('mkt_web.origem_ids(text,text,text,text,text,text,text)') is null then
    raise exception '20261005q: falta a 20261005n (mkt_web.sessoes, visualizacoes, paginas_mapa, periodo_ok, origem_ids)';
  end if;
  if to_regclass('mkt.paginas') is null or to_regprocedure('mkt.pode_ver(text)') is null then
    raise exception '20261005q: falta a 20261005m (mkt.paginas, mkt.pode_ver)';
  end if;
  if to_regclass('mkt_web.velocidade_lab') is not null
     or exists (select 1 from pg_proc p
                 where (p.pronamespace = 'public'::regnamespace
                        and p.proname in ('mkt_web_fluxo', 'mkt_web_melhorias', 'mkt_web_comparar', 'mkt_web_calor',
                                          'mkt_web_lab', 'mkt_web_leads', 'mkt_web_connect'))
                    or (p.pronamespace = 'mkt_web'::regnamespace
                        and p.proname in ('melhorias_base', 'leitura_achados', 'comparar_bloco', 'pagespeed_fila',
                                          'pagespeed_guardar', 'pagespeed_credenciais'))) then
    raise exception '20261005q: já aplicada (mkt_web.velocidade_lab ou funções da fase 2 existem)';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception '20261005q: papel service_role ausente';
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
       '20261005q: do patrimonio-brasil.json do Radar (id ' || v.radar || ')'
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
  'captura = {img, largura, altura} só no mais recente; erro = o teste falhou (ex.: HTTP 429 da cota pública). 20261005q.';
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
-- (visitantes.lead_ref, gravada pela 20261005o) e quantas dessas pessoas viraram MQL no projeto. Sem a 20261005o, só os
-- números da Web ("base": false). A lista (referência opaca e o id da ficha) só para quem pode ver a base
-- (pessoas.pode_ver(): hoje admin/dev). Nunca nome, e-mail ou telefone.
create function public.mkt_web_leads(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_base boolean := to_regclass('pessoas.pessoas') is not null and to_regclass('pessoas.eventos') is not null
                    and to_regprocedure('pessoas.pode_ver()') is not null;
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
  -- pessoa mesclada segue para a que ficou; pessoa de teste fica fora
  execute $q$
    with refs as (
      select vi.lead_ref, max(s.lead_em) as quando
        from mkt_web.sessoes s join mkt_web.visitantes vi on vi.projeto_id = s.projeto_id and vi.id = s.visitante
       where s.projeto_id = $1 and s.dia between $2 and $3 and not s.teste and s.lead and vi.lead_ref is not null
       group by vi.lead_ref
    ), pes as (
      select r.lead_ref, r.quando, coalesce(p.mesclada_em, p.id) as pessoa_id
        from refs r join pessoas.pessoas p on p.ref = r.lead_ref
       where not p.teste
    ), ev as (
      select pes.pessoa_id, bool_or(e.tipo = 'mql') as mql, bool_or(e.tipo = 'nao_mql') as nao_mql
        from pes left join pessoas.eventos e on e.pessoa_id = pes.pessoa_id and e.projeto_id = $1 and e.tipo in ('mql', 'nao_mql')
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
-- Por campanha do Tráfego (20261005p) do projeto: gasto, impressões e cliques no link da plataforma no período contra as
-- page views de ENTRADA da Web vindas da mesma campanha (a página de destino do anúncio; uma por visita). Casa pelo ID
-- da campanha (campaign_id da URL, ou o id do utm_campaign no formato nome|id do gp-operacoes, ou utm_campaign só id);
-- sem id na visita, pelo NOME exato (a parte do nome do utm_campaign). Leitura de mkt_web.origem_ids (20261005n); a
-- mesma regra está em mkt_trafego.resumo (20261005p). A coluna de cliques no link é procurada pelo nome
-- (cliques_link ou cliques_no_link); sem ela, connect rate fica nulo (nunca cai para "todos os cliques").
-- Por anúncio (utm_content = o anúncio/criativo em nome|id; agrupado pelo id) só a Web: o Tráfego ainda não guarda
-- clique por anúncio. Sem a 20261005p, "trafego": false.
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
    raise notice '20261005q: pg_cron, ops.cron_post ou Vault ausente; rotina mkt-web-pagespeed NÃO agendada';
    return;
  end if;
  if not exists (select 1 from vault.secrets where name = 'mkt_web_pagespeed_chave') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
      'mkt_web_pagespeed_chave', 'Header x-sync-chave do cron mkt-web-pagespeed (Edge mkt-web-pagespeed confere). 20261005q.');
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
    if has_schema_privilege(r, 'mkt_web', 'usage') then raise exception '20261005q: % tem acesso ao schema mkt_web', r; end if;
    if has_table_privilege(r, 'mkt_web.velocidade_lab', 'select, insert, update, delete, truncate, references, trigger') then
      raise exception '20261005q: % tem privilégio em mkt_web.velocidade_lab', r;
    end if;
  end loop;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'mkt_web.velocidade_lab'::regclass) then
    raise exception '20261005q: RLS desligada em mkt_web.velocidade_lab';
  end if;
  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where (p.pronamespace = 'public'::regnamespace and p.proname = any (v_publicas))
               or (p.pronamespace = 'mkt_web'::regnamespace and p.proname = any (v_internas)) loop
    if not (f.proconfig @> array['search_path=""']) then raise exception '20261005q: % sem search_path vazio', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') then raise exception '20261005q: anon executa %', f.sig; end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005q: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261005q: grant de authenticated errado em %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace) <> f.prosecdef then
      raise exception '20261005q: SECURITY DEFINER errado em % (públicas sim, internas não)', f.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (v_publicas)) <> 7
     or (select count(*) from pg_proc p where p.pronamespace = 'mkt_web'::regnamespace and p.proname = any (v_internas)) <> 6 then
    raise exception '20261005q: esperava 7 funções públicas e 6 internas';
  end if;
end
$confere$;



-- ═══ TESTES ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
create function pg_temp.ok(p_passo text, p_cond boolean, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, case when coalesce(p_cond, false) then 'ok: ' else 'ERRADO: ' end || p_info);
$$;
create function pg_temp.diz(p_passo text, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, p_info);
$$;
-- chama uma função como o ADMIN (perfil do Victor) e devolve o jsonb
create function pg_temp.adm(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  set local role authenticated;
  execute p_sql into v;
  reset role;
  return v;
end $$;
grant execute on all functions in schema pg_temp to public;

-- 1. Estrutura
select pg_temp.ok('1.tabela', (select c.relrowsecurity from pg_class c where c.oid = 'mkt_web.velocidade_lab'::regclass)
                   and not has_table_privilege('authenticated', 'mkt_web.velocidade_lab', 'select')
                   and not has_table_privilege('anon', 'mkt_web.velocidade_lab', 'select'),
                   'mkt_web.velocidade_lab com RLS e sem privilégio para anon/authenticated');
select pg_temp.ok('1.funcoes',
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
     ('mkt_web_fluxo', 'mkt_web_melhorias', 'mkt_web_comparar', 'mkt_web_calor', 'mkt_web_lab', 'mkt_web_leads', 'mkt_web_connect')
     and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')) = 7
  and (select count(*) from pg_proc p where p.pronamespace = 'mkt_web'::regnamespace and p.proname in
     ('melhorias_base', 'leitura_achados', 'comparar_bloco', 'pagespeed_fila', 'pagespeed_guardar', 'pagespeed_credenciais')
     and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute')
     and not p.prosecdef) = 6,
  '7 públicas (authenticated, sem anon) e 6 internas (sem grant, sem SECURITY DEFINER)');
select pg_temp.ok('1.paginas_pb26',
  (select count(*) from mkt.paginas pg join mkt.projetos p on p.id = pg.projeto_id
    where p.sigla = 'PB26' and pg.dominio = 'patrimoniobrasil.com.br' and pg.caminho in
      ('/', '/ak1/', '/bl2/', '/bl2-otimizacao/', '/quase-la/', '/pesquisa/', '/obrigado/', '/inscricao-recebida/',
       '/profissionais/', '/profissionais/advogados/', '/profissionais/contadores/')) = 11
  or not exists (select 1 from mkt.projetos where sigla = 'PB26'),
  'as 11 páginas do patrimonio-brasil.json no PB26 (' ||
  (select count(*) from mkt.paginas pg join mkt.projetos p on p.id = pg.projeto_id where p.sigla = 'PB26' and pg.obs like '20261005q:%')
  || ' criadas por esta migration)');
do $c$
begin
  if to_regnamespace('cron') is null or to_regprocedure('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)') is null
     or to_regclass('vault.decrypted_secrets') is null then
    perform pg_temp.diz('1.cron', 'PULADO: sem pg_cron, ops.cron_post ou Vault (banco local)');
  else
    perform pg_temp.ok('1.cron',
      exists (select 1 from cron.job j where j.jobname = 'mkt-web-pagespeed' and j.schedule = '40 9 * * *'
               and j.command like '%ops.cron_post(''mkt-web-pagespeed''%' and j.command like '%vault.decrypted_secrets%'
               and position((select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'mkt_web_pagespeed_chave') in j.command) = 0),
      'mkt-web-pagespeed 40 9 * * * pelo ops.cron_post, chave lida do Vault (não literal no comando)');
  end if;
end $c$;

-- Projeto de TESTE (some no rollback): ZZWEB98 em exemplo.invalid
insert into mkt.projetos (sigla, nome, linha) values ('ZZWEB98', 'ZZ Ensaio Web 2', 'ZZ Ensaio');
insert into mkt.paginas (projeto_id, codigo, nome, dominio, caminho, funcao, funil)
select p.id, v.c, v.n, 'exemplo.invalid', v.cam, v.f, 'zz'
  from mkt.projetos p, (values ('zz1', 'ZZ1', '/zz1/', 'captura'), ('zz1-b', 'ZZ1 B', '/zz1-b/', 'captura'),
                               (null, 'Obrigado ZZ', '/obrigado-zz/', 'obrigado')) v(c, n, cam, f)
 where p.sigla = 'ZZWEB98';
insert into mkt_web.funis (projeto_id, coleta, eventos_lead, resultados)
select p.id, true, '{lead_zz}', '[{"id":"mql","nome":"MQL","evento":["mql_zz"]}]'::jsonb from mkt.projetos p where p.sigla = 'ZZWEB98';
create temp table _z_ids on commit drop as
  select 'proj' k, id from mkt.projetos where sigla = 'ZZWEB98'
  union all select 'zz1', id from mkt.paginas where caminho = '/zz1/' and dominio = 'exemplo.invalid'
  union all select 'zz1b', id from mkt.paginas where caminho = '/zz1-b/' and dominio = 'exemplo.invalid'
  union all select 'obr', id from mkt.paginas where caminho = '/obrigado-zz/' and dominio = 'exemplo.invalid';
grant all on _z_ids to public;
create function pg_temp.id(p_k text) returns bigint language sql stable as $$ select id from pg_temp._z_ids where k = p_k $$;
grant execute on function pg_temp.id(text) to public;
insert into mkt_web.paginas_mapa (pagina_id, secoes, ctas, campos) values (pg_temp.id('zz1'), '{topo,meio,fim}', '{topo-cta,fim-cta}', '{nome,email}');

-- 5 visitas (todas fechadas: último pacote há 2 h). S4 é visita de TESTE (fica fora de tudo).
--   S1 celular: /zz1/ → /obrigado-zz/, engajou, lead, MQL, campanha no padrão, anúncio ad111, campaign_id camp1
--   S2 celular: só /zz1/, não engajou (rejeição), começou o formulário e parou no "nome"
--   S3 computador: /zz1-b/ → /zz1-b/ (recarregou) → /zz1/, engajou, sem lead, campanha fora do cadastro, anúncio ad222
--   S5 computador: só /zz1-b/, engajou, lead (sem MQL), erro de JavaScript da página
insert into mkt_web.sessoes (id, projeto_id, visitante, dia, inicio, fim, recebido_em, dispositivo, teste, utm_source, utm_campaign,
                             utm_content, campaign_id, entrada_pagina_id, entrada_caminho, saida_caminho, paginas, visivel_ms,
                             engajada, lead, lead_em, resultado)
select v.id, pg_temp.id('proj'), v.vis, mkt_web.hoje(), now() - interval '3 hours', now() - interval '2 hours', now() - interval '2 hours',
       v.disp, v.teste, v.src, v.camp, v.ad, v.cid, pg_temp.id(v.ent), v.ecam, v.scam, v.pags, v.vms, v.eng, v.lead,
       case when v.lead then now() - interval '3 hours' end, v.res
  from (values ('zzS1sessao01', 'zzvisit0001', 'mobile', false, 'ig', 'RS | ZZWEB98 | LEADS | TESTE | ZZ1', 'ad111', 'camp1', 'zz1', '/zz1/', '/obrigado-zz/', 2, 20000, true, true, 'mql'),
               ('zzS2sessao02', 'zzvisit0002', 'mobile', false, null, null, null, null, 'zz1', '/zz1/', '/zz1/', 1, 2000, false, false, null),
               ('zzS3sessao03', 'zzvisit0003', 'desktop', false, 'fb', 'outra campanha', 'ad222', null, 'zz1b', '/zz1-b/', '/zz1/', 3, 30000, true, false, null),
               ('zzS4sessao04', 'zzvisit0004', 'mobile', true, null, null, null, null, 'zz1', '/zz1/', '/zz1/', 1, 9000, true, true, null),
               ('zzS5sessao05', 'zzvisit0005', 'desktop', false, null, null, null, null, 'zz1b', '/zz1-b/', '/zz1-b/', 1, 12000, true, true, null)
       ) v(id, vis, disp, teste, src, camp, ad, cid, ent, ecam, scam, pags, vms, eng, lead, res);
insert into mkt_web.visitantes (projeto_id, id, sessoes)
select pg_temp.id('proj'), s.visitante, 1 from mkt_web.sessoes s where s.projeto_id = pg_temp.id('proj');
insert into mkt_web.visualizacoes (id, sessao, projeto_id, pagina_id, dominio, caminho, dia, ordem, inicio, fim, dispositivo, largura, altura_doc,
                                   rolagem, visivel_ms, lcp_ms, secoes, ctas, form)
select v.id, v.s, pg_temp.id('proj'), pg_temp.id(v.pg), 'exemplo.invalid', v.cam, mkt_web.hoje(), v.o,
       now() - interval '3 hours' + make_interval(secs => v.o * 60), now() - interval '2 hours', v.disp, v.larg, v.alt, v.rol, v.vms, v.lcp,
       v.sec::jsonb, v.cta::jsonb, v.frm::jsonb
  from (values
    ('zzS1pv000001', 'zzS1sessao01', 'zz1', '/zz1/', 1, 'mobile', 390, 4000, 80, 15000, 2000, '{"topo":5,"meio":3}', '{"topo-cta":1,"fim-cta":0}',
     '{"v":1,"t":20,"s":1,"u":"email","c":{"nome":[1,5,1,0],"email":[1,8,1,1]}}'),
    ('zzS1pv000002', 'zzS1sessao01', 'obr', '/obrigado-zz/', 2, 'mobile', 390, 1500, 100, 5000, null, null, null, null),
    ('zzS2pv000001', 'zzS2sessao02', 'zz1', '/zz1/', 1, 'mobile', 390, 4000, 10, 2000, 5000, '{"topo":2}', '{"topo-cta":0}',
     '{"v":1,"t":0,"s":0,"u":"nome","c":{"nome":[1,3,1,0]}}'),
    ('zzS3pv000001', 'zzS3sessao03', 'zz1b', '/zz1-b/', 1, 'desktop', 1280, 3000, 40, 10000, 1800, null, null, null),
    ('zzS3pv000002', 'zzS3sessao03', 'zz1b', '/zz1-b/', 2, 'desktop', 1280, 3000, 60, 10000, null, null, null, null),
    ('zzS3pv000003', 'zzS3sessao03', 'zz1', '/zz1/', 3, 'desktop', 1280, 5000, 30, 10000, null, null, null, null),
    ('zzS4pv000001', 'zzS4sessao04', 'zz1', '/zz1/', 1, 'mobile', 390, 4000, 90, 9000, 1000, '{"topo":9}', '{"topo-cta":1}', null),
    ('zzS5pv000001', 'zzS5sessao05', 'zz1b', '/zz1-b/', 1, 'desktop', 1280, 3000, 70, 12000, 3000, null, null, null)
  ) v(id, s, pg, cam, o, disp, larg, alt, rol, vms, lcp, sec, cta, frm);
-- S1: clique no botão do topo (10 s), clique de raiva, clique num elemento fixo, clique automático (0,0); eventos
insert into mkt_web.cliques (sessao, visualizacao, projeto_id, pagina_id, dia, dispositivo, quando, x_pct, y_px, seletor, texto, raiva, morto, fixo, automatico)
select 'zzS1sessao01', 'zzS1pv000001', pg_temp.id('proj'), pg_temp.id('zz1'), mkt_web.hoje(), 'mobile', now() - interval '3 hours' + make_interval(secs => 60 + v.t),
       v.x, v.y, v.sel, v.txt, v.raiva, false, v.fixo, v.auto
  from (values (10, 50.0, 400, 'button[data-cta="topo-cta"]', 'Quero', false, false, false),
               (30, 20.0, 1000, 'div.foto', '', true, false, false),
               (40, 90.0, 100, 'div.barra-fixa', '', false, true, false),
               (50, 0.0, 0, 'input#nome', '', false, false, true)) v(t, x, y, sel, txt, raiva, fixo, auto);
insert into mkt_web.eventos (sessao, visualizacao, projeto_id, pagina_id, dia, quando, nome)
select 'zzS1sessao01', 'zzS1pv000001', pg_temp.id('proj'), pg_temp.id('zz1'), mkt_web.hoje(), now() - interval '3 hours' + make_interval(secs => 60 + v.t), v.n
  from (values (8, 'abriu_formulario'), (11, 'lead_zz'), (12, 'mql_zz')) v(t, n);
insert into mkt_web.eventos (sessao, visualizacao, projeto_id, pagina_id, dia, quando, nome)
values ('zzS5sessao05', 'zzS5pv000001', pg_temp.id('proj'), pg_temp.id('zz1b'), mkt_web.hoje(), now() - interval '3 hours' + interval '70 seconds', 'lead_zz');
insert into mkt_web.erros (sessao, visualizacao, projeto_id, pagina_id, dia, quando, mensagem, origem)
values ('zzS5sessao05', 'zzS5pv000001', pg_temp.id('proj'), pg_temp.id('zz1b'), mkt_web.hoje(), now() - interval '3 hours', 'x is undefined', 'pagina');

-- 2. Fluxo
create temp table _z_j (k text primary key, v jsonb) on commit drop;
grant all on _z_j to public;
insert into _z_j select 'fluxo', pg_temp.adm(format('select public.mkt_web_fluxo(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
select pg_temp.ok('2.totais', v ->> 'sessoes' = '4' and v ->> 'uma_pagina' = '2' and (v ->> 'passos_medio')::numeric = 1.5,
                  'visitas=' || (v ->> 'sessoes') || ' uma_pagina=' || (v ->> 'uma_pagina') || ' passos_medio=' || (v ->> 'passos_medio')
                  || ' (esperado 4, 2, 1.5: a visita de teste fica fora e recarregar a /zz1-b/ não é passo)')
  from _z_j where k = 'fluxo';
select pg_temp.ok('2.paginas', string_agg(x ->> 'caminho' || ' vistas=' || (x ->> 'vistas') || ' ent=' || (x ->> 'entradas') || ' sai=' || (x ->> 'saidas') || ' lead=' || (x ->> 'leads'), ' ; ' order by x ->> 'caminho')
                  = '/obrigado-zz/ vistas=1 ent=0 sai=1 lead=1 ; /zz1-b/ vistas=2 ent=2 sai=1 lead=1 ; /zz1/ vistas=3 ent=2 sai=2 lead=1',
                  string_agg(x ->> 'caminho' || ' vistas=' || (x ->> 'vistas') || ' ent=' || (x ->> 'entradas') || ' sai=' || (x ->> 'saidas') || ' lead=' || (x ->> 'leads'), ' ; ' order by x ->> 'caminho'))
  from _z_j, jsonb_array_elements(v -> 'paginas') x where k = 'fluxo';
select pg_temp.ok('2.passagens', string_agg((x ->> 'de') || '>' || (x ->> 'para') || '=' || (x ->> 'n'), ' ; ' order by x ->> 'de', x ->> 'para')
                  = '/obrigado-zz/>(saiu)=1 ; /zz1-b/>(saiu)=1 ; /zz1-b/>/zz1/=1 ; /zz1/>(saiu)=2 ; /zz1/>/obrigado-zz/=1',
                  string_agg((x ->> 'de') || '>' || (x ->> 'para') || '=' || (x ->> 'n'), ' ; ' order by x ->> 'de', x ->> 'para'))
  from _z_j, jsonb_array_elements(v -> 'passagens') x where k = 'fluxo';
select pg_temp.ok('2.caminhos', count(*) = 4 and bool_and((x ->> 'n')::int = 1) and bool_or(x -> 'passos' = '["/zz1-b/", "/zz1/"]'::jsonb),
                  count(*) || ' caminhos, um deles /zz1-b/ › /zz1/ (sem repetir a recarga)')
  from _z_j, jsonb_array_elements(v -> 'caminhos') x where k = 'fluxo';
select pg_temp.ok('2.nomes', v -> 'nomes' ->> '/zz1/' = 'ZZ1', 'nome da página cadastrada para o caminho') from _z_j where k = 'fluxo';

-- 3. Melhorias
insert into _z_j select 'melh', pg_temp.adm(format('select public.mkt_web_melhorias(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
insert into _z_j select 'zz1', x from _z_j, jsonb_array_elements(v -> 'atual' -> 'paginas') x where k = 'melh' and x ->> 'codigo' = 'zz1';
insert into _z_j select 'zz1b', x from _z_j, jsonb_array_elements(v -> 'atual' -> 'paginas') x where k = 'melh' and x ->> 'codigo' = 'zz1-b';
insert into _z_j select 'leit', x from _z_j, jsonb_array_elements(v -> 'atual' -> 'leituras') x where k = 'melh' and (x ->> 'pagina_id')::bigint = pg_temp.id('zz1');
select pg_temp.ok('3.topo', v -> 'atual' ->> 'sessoes' = '4' and v -> 'atual' ->> 'leads' = '2' and v -> 'atual' ->> 'dias' = '1'
                  and v ->> 'antes_ate' = (mkt_web.hoje() - 1)::text and v -> 'antes' ->> 'sessoes' = '0' and not (v -> 'antes' ? 'leituras'),
                  'atual: 4 visitas, 2 leads, 1 dia; anterior (1 dia antes): 0 visitas, sem leitura') from _z_j where k = 'melh';
select pg_temp.ok('3.zz1', v ->> 'visitas' = '3' and v ->> 'sessoes' = '3' and v ->> 'entradas' = '2' and v ->> 'rejeicoes' = '1'
                  and v ->> 'leads_entrada' = '1' and v ->> 'mql_entrada' = '1',
                  'zz1: visitas=' || (v ->> 'visitas') || ' entradas=' || (v ->> 'entradas') || ' rejeicoes=' || (v ->> 'rejeicoes')
                  || ' leads_entrada=' || (v ->> 'leads_entrada') || ' mql_entrada=' || (v ->> 'mql_entrada') || ' (esperado 3, 2, 1, 1, 1)')
  from _z_j where k = 'zz1';
select pg_temp.ok('3.zz1_aparelho', v -> 'por_aparelho' = '[{"leads": 1, "entradas": 2, "rejeicoes": 1, "dispositivo": "mobile"}]'::jsonb,
                  'por aparelho ' || (v -> 'por_aparelho')::text) from _z_j where k = 'zz1';
select pg_temp.ok('3.zz1_lcp', v -> 'lcp' = '[{"faixa": "bom", "leads": 1, "entradas": 1, "rejeicoes": 0}, {"faixa": "ruim", "leads": 0, "entradas": 1, "rejeicoes": 1}]'::jsonb,
                  'LCP da entrada por faixa ' || (v -> 'lcp')::text) from _z_j where k = 'zz1';
select pg_temp.ok('3.zz1_friccao', v -> 'friccao' ->> 'com_raiva' = '1' and v -> 'friccao' ->> 'friccao_leads' = '1'
                  and v -> 'friccao' ->> 'sem_friccao' = '1' and v -> 'friccao' ->> 'sem_leads' = '0',
                  'fricção ' || (v -> 'friccao')::text) from _z_j where k = 'zz1';
select pg_temp.ok('3.zz1b', v ->> 'visitas' = '3' and v ->> 'entradas' = '2' and v ->> 'rejeicoes' = '0' and v ->> 'leads_entrada' = '1'
                  and v -> 'friccao' ->> 'com_erro' = '1' and jsonb_array_length(v -> 'por_dia') = 1,
                  'zz1-b: visitas=' || (v ->> 'visitas') || ' entradas=' || (v ->> 'entradas') || ' com_erro=' || (v -> 'friccao' ->> 'com_erro'))
  from _z_j where k = 'zz1b';
select pg_temp.ok('3.leitura_medidas', v ->> 'visitas' = '3' and v ->> 'medidas' = '2' and v ->> 'medidas_lead' = '1' and v ->> 'medidas_mql' = '1',
                  'leitura zz1: visitas=' || (v ->> 'visitas') || ' medidas=' || (v ->> 'medidas')) from _z_j where k = 'leit';
select pg_temp.ok('3.leitura_secoes', string_agg((x ->> 'secao') || '(' || (x ->> 'ordem') || ') viram=' || (x ->> 'viram') || ' cheg=' || (x ->> 'chegaram') || ' mql=' || (x ->> 'viram_mql'), ' ; ' order by (x ->> 'ordem')::int)
                  = 'topo(1) viram=2 cheg=2 mql=1 ; meio(2) viram=1 cheg=1 mql=1 ; fim(3) viram=0 cheg=0 mql=0',
                  string_agg((x ->> 'secao') || '(' || (x ->> 'ordem') || ') viram=' || (x ->> 'viram') || ' cheg=' || (x ->> 'chegaram') || ' mql=' || (x ->> 'viram_mql'), ' ; ' order by (x ->> 'ordem')::int))
  from _z_j, jsonb_array_elements(v -> 'secoes') x where k = 'leit';
select pg_temp.ok('3.leitura_primeiro_botao', v -> 'primeiro_cta' = '[{"viram": 1, "medidas": 2, "ficaram": 1, "dispositivo": "mobile", "ficaram_sem_ver": 0, "leads_de_quem_viu": 1}]'::jsonb,
                  'primeiro botão ' || (v -> 'primeiro_cta')::text) from _z_j where k = 'leit';
select pg_temp.ok('3.leitura_botoes', v ->> 'leads_com_botao' = '1'
                  and (select string_agg((x ->> 'cta') || ' viram=' || (x ->> 'viram') || ' clic=' || (x ->> 'clicaram') || ' leads=' || (x ->> 'leads'), ' ; ' order by (x ->> 'ordem')::int)
                         from jsonb_array_elements(v -> 'ctas') x) = 'topo-cta viram=1 clic=1 leads=1 ; fim-cta viram=0 clic=0 leads=0',
                  'o lead veio pelo botão do topo (clique 1 s antes do evento de lead)') from _z_j where k = 'leit';
select pg_temp.ok('3.leitura_form', v -> 'form' ->> 'viram' = '2' and v -> 'form' ->> 'abriram' = '2' and v -> 'form' ->> 'comecaram' = '2'
                  and v -> 'form' ->> 'enviaram' = '1'
                  and (select string_agg((x ->> 'campo') || ' toc=' || (x ->> 'tocaram') || ' err=' || (x ->> 'com_erro') || ' parou=' || (x ->> 'pararam'), ' ; ' order by (x ->> 'ordem')::int)
                         from jsonb_array_elements(v -> 'form' -> 'campos') x) = 'nome toc=2 err=0 parou=1 ; email toc=1 err=1 parou=0',
                  'formulário: viram 2, começaram 2, enviaram 1; S2 parou no nome; e-mail com erro de validação') from _z_j where k = 'leit';

-- 4. Comparar
insert into _z_j select 'cmp', pg_temp.adm(format('select public.mkt_web_comparar(%s, %s, %L, %L, %s, %L, %L)', pg_temp.id('proj'),
  pg_temp.id('zz1'), mkt_web.hoje(), mkt_web.hoje(), pg_temp.id('zz1b'), mkt_web.hoje(), mkt_web.hoje()));
select pg_temp.ok('4.duas_paginas', v -> 'a' ->> 'visitas' = '3' and v -> 'a' ->> 'leads' = '1' and v -> 'a' ->> 'mql' = '1' and v -> 'a' ->> 'entradas' = '2'
                  and v -> 'a' ->> 'rejeicoes' = '1' and v -> 'b' ->> 'visitas' = '2' and v -> 'b' ->> 'leads' = '1' and v -> 'b' ->> 'entradas' = '2'
                  and v -> 'a' ->> 'nome' = 'ZZ1',
                  'A zz1: 3 visitas, 1 lead, 1 MQL; B zz1-b: 2 visitas, 1 lead') from _z_j where k = 'cmp';
insert into _z_j select 'cmp2', pg_temp.adm(format('select public.mkt_web_comparar(%s, null, %L, %L, null, %L, %L)', pg_temp.id('proj'),
  mkt_web.hoje(), mkt_web.hoje(), mkt_web.hoje() - 7, mkt_web.hoje() - 1));
select pg_temp.ok('4.dois_periodos', v -> 'a' ->> 'visitas' = '4' and v -> 'a' ->> 'leads' = '2' and v -> 'b' ->> 'visitas' = '0'
                  and jsonb_array_length(v -> 'a' -> 'por_aparelho') = 2,
                  'projeto hoje: 4 visitas, 2 leads; semana anterior: 0') from _z_j where k = 'cmp2';
do $t$
begin
  perform pg_temp.adm(format('select public.mkt_web_comparar(%s, %s, %L, %L, null, %L, %L)', pg_temp.id('proj'),
    (select min(id) from mkt.paginas where projeto_id <> pg_temp.id('proj')), mkt_web.hoje(), mkt_web.hoje(), mkt_web.hoje(), mkt_web.hoje()));
  if (select min(id) from mkt.paginas where projeto_id <> pg_temp.id('proj')) is null then
    perform pg_temp.diz('4.outro_projeto', 'PULADO: não há página de outro projeto');
  else
    perform pg_temp.ok('4.outro_projeto', false, 'página de outro projeto passou');
  end if;
exception when sqlstate '22023' then
  reset role;
  perform pg_temp.ok('4.outro_projeto', true, 'página de outro projeto recusada (22023)');
end $t$;

-- 6 (antes do 5: o mapa usa a captura). Laboratório do Google, como a rotina chama (postgres)
select pg_temp.ok('6.recusas', mkt_web.pagespeed_guardar('{"pagina_id": 0, "estrategia": "mobile", "url": "https://exemplo.invalid/zz1/"}') = 'pagina'
                  and mkt_web.pagespeed_guardar(jsonb_build_object('pagina_id', pg_temp.id('zz1'), 'estrategia', 'tv', 'url', 'https://exemplo.invalid/zz1/')) = 'estrategia'
                  and mkt_web.pagespeed_guardar(jsonb_build_object('pagina_id', pg_temp.id('zz1'), 'estrategia', 'mobile', 'url', 'http://exemplo.invalid/zz1/')) = 'url',
                  'página inexistente, aparelho e url sem https recusados');
select pg_temp.ok('6.fila_inicial', (select count(*) from mkt_web.pagespeed_fila(40) f where f.pagina_id in (pg_temp.id('zz1'), pg_temp.id('zz1b'), pg_temp.id('obr'))) = 6,
                  'fila: 3 páginas ativas × 2 aparelhos do projeto com a coleta ligada');
select mkt_web.pagespeed_guardar(jsonb_build_object('pagina_id', pg_temp.id('zz1'), 'estrategia', 'mobile', 'url', 'https://exemplo.invalid/zz1/',
         'nota', 30 + g, 'lcp_ms', 3000, 'cls', '0.05', 'notas', jsonb_build_object('desempenho', 30 + g, 'seo', 99, 'acessibilidade', 'x'),
         'oportunidades', '[{"id":"render-blocking-resources","titulo":"Elimine recursos que bloqueiam a renderização","ms":1200},{"id":"a","titulo":"b","ms":1},{"id":"c","titulo":"d","ms":1},{"id":"e","titulo":"f","ms":1},{"id":"g","titulo":"h","ms":1},{"id":"i","titulo":"j","ms":1}]'::jsonb,
         'captura', case when g >= 61 then jsonb_build_object('img', 'data:image/jpeg;base64,AAAA' || g, 'largura', 412, 'altura', 4200) end))
  from generate_series(1, 62) g;
update mkt_web.velocidade_lab set medido_em = medido_em - make_interval(secs => 100 - id % 100) where pagina_id = pg_temp.id('zz1');
select pg_temp.ok('6.guardou', count(*) = 60 and count(captura) = 1 and max(jsonb_array_length(oportunidades)) = 5
                  and bool_and(notas = jsonb_build_object('seo', 99, 'desempenho', least(nota, 100))),
                  count(*) || ' testes guardados (60 por página e aparelho), ' || count(captura) || ' com captura, até 5 oportunidades, nota fora do formato descartada')
  from mkt_web.velocidade_lab where pagina_id = pg_temp.id('zz1') and estrategia = 'mobile';
select pg_temp.ok('6.captura_ultima', (select captura ->> 'img' from mkt_web.velocidade_lab where pagina_id = pg_temp.id('zz1') and captura is not null) = 'data:image/jpeg;base64,AAAA62',
                  'a captura fica só no teste mais recente');
select pg_temp.ok('6.fila_depois', (select count(*) from mkt_web.pagespeed_fila(40) f where f.pagina_id in (pg_temp.id('zz1'), pg_temp.id('zz1b'), pg_temp.id('obr'))) = 5,
                  'fila: a página medida há menos de 20 h sai (5)');
update mkt_web.config set valor = 'desligado' where chave = 'pagespeed';
select pg_temp.ok('6.desligado', (select count(*) from mkt_web.pagespeed_fila(40)) = 0, 'com pagespeed = desligado, a fila fica vazia');
update mkt_web.config set valor = 'ligado' where chave = 'pagespeed';
insert into _z_j select 'lab', pg_temp.adm(format('select public.mkt_web_lab(%s)', pg_temp.id('proj')));
select pg_temp.ok('6.tela', (v ->> 'ligado')::boolean and (v ->> 'coleta')::boolean and jsonb_array_length(v -> 'paginas') = 6
                  and (select (x -> 'ultimo' ->> 'nota')::int = 92 and (x ->> 'anterior_nota')::int = 91 and jsonb_array_length(x -> 'serie') = 30
                         and not (x -> 'ultimo' ? 'captura')
                         from jsonb_array_elements(v -> 'paginas') x where x ->> 'caminho' = '/zz1/' and x ->> 'estrategia' = 'mobile'),
                  'tela: 6 linhas (página × aparelho), último 92, anterior 91, 30 na série, sem a imagem')
  from _z_j where k = 'lab';

-- 5. Mapa de calor
insert into _z_j select 'calor', pg_temp.adm(format('select public.mkt_web_calor(%s, %s, %L, %L, %L)', pg_temp.id('proj'), pg_temp.id('zz1'), 'mobile', mkt_web.hoje(), mkt_web.hoje()));
select pg_temp.ok('5.pontos', jsonb_array_length(v -> 'pontos') = 2 and v -> 'contagem' = '{"fixos": 1, "raiva": 1, "mortos": 0, "cliques": 2}'::jsonb
                  and (select string_agg((x ->> 0) || ',' || (x ->> 1) || ',' || (x ->> 2), ' ; ' order by (x ->> 0)::numeric) from jsonb_array_elements(v -> 'pontos') x)
                      = '20.0,0.2500,1 ; 50.0,0.1000,0',
                  'pontos (x, y/altura, tipo): ' || coalesce((select string_agg((x ->> 0) || ',' || (x ->> 1) || ',' || (x ->> 2), ' ; ' order by (x ->> 0)::numeric) from jsonb_array_elements(v -> 'pontos') x), '-')
                  || '; o fixo é contado à parte e o automático fica fora') from _z_j where k = 'calor';
select pg_temp.ok('5.pagina', v ->> 'visitas' = '2' and v ->> 'largura' = '390' and v ->> 'altura_doc' = '4000' and v ->> 'url' = 'https://exemplo.invalid/zz1/'
                  and v -> 'alcance' ->> 0 = '2' and v -> 'alcance' ->> 2 = '2' and v -> 'alcance' ->> 3 = '1' and v -> 'alcance' ->> 16 = '1' and v -> 'alcance' ->> 17 = '0',
                  'celular: 2 visitas, 390 px, 4000 px; alcance 0%=2, 10%=2, 15%=1, 80%=1, 85%=0') from _z_j where k = 'calor';
select pg_temp.ok('5.captura', v -> 'captura' ->> 'img' = 'data:image/jpeg;base64,AAAA62' and v -> 'captura' ->> 'largura' = '412',
                  'captura do último teste do Google no celular') from _z_j where k = 'calor';
insert into _z_j select 'calor_d', pg_temp.adm(format('select public.mkt_web_calor(%s, %s, %L, %L, %L)', pg_temp.id('proj'), pg_temp.id('zz1'), 'desktop', mkt_web.hoje(), mkt_web.hoje()));
select pg_temp.ok('5.computador', v ->> 'visitas' = '1' and jsonb_array_length(v -> 'pontos') = 0 and v -> 'captura' = 'null'::jsonb,
                  'computador: 1 visita (S3), sem clique, sem captura') from _z_j where k = 'calor_d';
do $t$
begin
  perform pg_temp.adm(format('select public.mkt_web_calor(%s, %s, %L, %L, %L)', pg_temp.id('proj'), pg_temp.id('zz1'), 'tv', mkt_web.hoje(), mkt_web.hoje()));
  perform pg_temp.ok('5.aparelho', false, 'aparelho inválido passou');
exception when sqlstate '22023' then
  reset role;
  perform pg_temp.ok('5.aparelho', true, 'aparelho inválido recusado (22023)');
end $t$;

-- 7. Lead ligado à pessoa
update mkt_web.visitantes set lead_ref = 'pe_0000000000000000000000000000ab01' where projeto_id = pg_temp.id('proj') and id = 'zzvisit0001';
do $t$
declare v jsonb; v_pid uuid;
begin
  if to_regclass('pessoas.pessoas') is null then
    v := pg_temp.adm(format('select public.mkt_web_leads(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
    perform pg_temp.ok('7.sem_base', v ->> 'base' = 'false' and v ->> 'leads_web' = '2' and v ->> 'com_ref' = '1' and v -> 'lista' = '[]'::jsonb,
                       'sem a 20261005o: base=false, leads da Web=' || (v ->> 'leads_web') || ', com referência=' || (v ->> 'com_ref'));
    return;
  end if;
  execute 'insert into pessoas.pessoas (ref, nome) values ($1, $2) returning id' into v_pid using 'pe_0000000000000000000000000000ab01', 'Pessoa Ensaio Web';
  execute 'insert into pessoas.eventos (pessoa_id, tipo, projeto_id, fonte) values ($1, ''lead'', $2, ''sistema''), ($1, ''mql'', $2, ''sistema'')'
    using v_pid, pg_temp.id('proj');
  v := pg_temp.adm(format('select public.mkt_web_leads(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
  perform pg_temp.ok('7.base', v ->> 'base' = 'true' and v ->> 'pode_abrir' = 'true' and v ->> 'pessoas' = '1' and v ->> 'mql' = '1'
                     and v -> 'lista' -> 0 ->> 'pessoa_id' = v_pid::text and not (v::text like '%Pessoa Ensaio%'),
                     'com a 20261005o: 1 pessoa, 1 MQL, a ficha abre para o admin, sem nome na resposta');
end $t$;

-- 8. Connect rate (page views de entrada ÷ cliques no link; conversão = leads ÷ page views)
do $t$
declare v jsonb; v_conta bigint; v_camp bigint; v_col text;
begin
  if to_regclass('mkt_trafego.desempenho_dia') is null then
    v := pg_temp.adm(format('select public.mkt_web_connect(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
    perform pg_temp.ok('8.sem_trafego', v ->> 'trafego' = 'false' and jsonb_array_length(v -> 'anuncios') = 2,
                       'sem a 20261005p: trafego=false e as page views por anúncio (ad111, ad222)');
    return;
  end if;
  select c.column_name into v_col from information_schema.columns c
   where c.table_schema = 'mkt_trafego' and c.table_name = 'desempenho_dia' and c.column_name in ('cliques_link', 'cliques_no_link')
   order by c.column_name limit 1;
  execute 'insert into mkt_trafego.contas (plataforma, conta_externa, nome, dono) values (''meta'', ''zz9000001'', ''Conta Ensaio Web'', ''grupo'') returning id' into v_conta;
  execute 'insert into mkt_trafego.campanhas (plataforma, conta_id, campanha_externa, nome, leitura, fora_padrao, projeto_id)
           values (''meta'', $1, ''camp1'', ''RS | ZZWEB98 | LEADS | TESTE | ZZ1'', mkt.campanha_traduzir(''RS | ZZWEB98 | LEADS | TESTE | ZZ1''), false, $2) returning id'
    into v_camp using v_conta, pg_temp.id('proj');
  -- a coluna de cliques totais chama cliques_total na 20261005p atual (cliques numa versão antiga)
  execute format('insert into mkt_trafego.desempenho_dia (campanha_id, dia, gasto, impressoes, %I%s) values ($1, $2, 100, 1000, 9%s)',
                 coalesce((select c.column_name::text from information_schema.columns c
                            where c.table_schema = 'mkt_trafego' and c.table_name = 'desempenho_dia'
                              and c.column_name in ('cliques_total', 'cliques') order by c.column_name desc limit 1), 'cliques'),
                 case when v_col is null then '' else ', ' || quote_ident(v_col) end, case when v_col is null then '' else ', 4' end)
    using v_camp, mkt_web.hoje();
  v := pg_temp.adm(format('select public.mkt_web_connect(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
  perform pg_temp.ok('8.trafego', v ->> 'trafego' = 'true' and v -> 'campanhas' -> 0 ->> 'page_views' = '1' and v -> 'campanhas' -> 0 ->> 'pagina' = 'zz1'
                     and (v -> 'campanhas' -> 0 ->> 'conversao')::numeric = 1 and v -> 'sem_campanha' ->> 'page_views' = '1'
                     and case when v_col is null then v -> 'campanhas' -> 0 -> 'connect_rate' = 'null'::jsonb and v ->> 'cliques_link' = 'false'
                              else (v -> 'campanhas' -> 0 ->> 'connect_rate')::numeric = 0.25 end,
                     'com a 20261005p: camp1, 1 page view, conversão 100%; ' ||
                     case when v_col is null then 'sem coluna de cliques no link: connect rate nulo (não usa os 9 cliques totais)'
                          else '4 cliques no link: connect rate 25%' end || '; 1 page view de campanha fora do cadastro');
end $t$;

-- 8b. UTM no padrão do gp-operacoes (campanha e anúncio em nome|id; o id vem depois da última "|"). 4 visitas novas,
--     entrada na /zz1/: U1 nome|id (lead), U2 só id (formato antigo e Google), U3 só nome, U4 nome certo com id que
--     não é do cadastro. Achados por criativo e anúncios da Web agrupam pelo id; o Tráfego casa pelo id (nome na falta).
insert into mkt_web.sessoes (id, projeto_id, visitante, dia, inicio, fim, recebido_em, dispositivo, teste, utm_source, utm_campaign,
                             utm_content, entrada_pagina_id, entrada_caminho, saida_caminho, paginas, visivel_ms, engajada, lead)
select v.id, pg_temp.id('proj'), v.vis, mkt_web.hoje(), now() - interval '3 hours', now() - interval '2 hours', now() - interval '2 hours',
       'mobile', false, v.src, v.camp, v.ad, pg_temp.id('zz1'), '/zz1/', '/zz1/', 1, 20000, true, v.lead
  from (values ('zzU1sessao01', 'zzvisitU001', 'metaads', 'RS | ZZWEB98 | LEADS | NOVA | ZZ1|120100000000098', 'CRIATIVO Q|120200000000098', true),
               ('zzU2sessao02', 'zzvisitU002', 'metaads', '120100000000098', '120200000000098', false),
               ('zzU3sessao03', 'zzvisitU003', 'metaads', 'RS | ZZWEB98 | LEADS | NOVA | ZZ1', null, false),
               ('zzU4sessao04', 'zzvisitU004', 'metaads', 'RS | ZZWEB98 | LEADS | NOVA | ZZ1|120100000000555', null, false))
       v(id, vis, src, camp, ad, lead);
do $t$
declare v jsonb; x jsonb; v_conta bigint; v_camp bigint;
begin
  v := pg_temp.adm(format('select public.mkt_web_melhorias(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
  select p -> 'por_criativo' into x from jsonb_array_elements(v -> 'atual' -> 'paginas') p where p ->> 'codigo' = 'zz1';
  perform pg_temp.ok('8b.por_criativo', exists (select 1 from jsonb_array_elements(x) c
                                                  where c ->> 'criativo' = 'CRIATIVO Q' and c ->> 'criativo_id' = '120200000000098'
                                                    and c ->> 'campanha' = 'RS | ZZWEB98 | LEADS | NOVA | ZZ1' and c ->> 'entradas' = '2'),
                     'achados por criativo: nome|id e só id do mesmo anúncio somam juntos pelo id (2 entradas), mostram o nome: ' || x::text);
  v := pg_temp.adm(format('select public.mkt_web_connect(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
  perform pg_temp.ok('8b.anuncios', exists (select 1 from jsonb_array_elements(v -> 'anuncios') a
                                             where a ->> 'anuncio' = 'CRIATIVO Q' and a ->> 'anuncio_id' = '120200000000098' and a ->> 'page_views' = '2'
                                               and a ->> 'campanha' = 'RS | ZZWEB98 | LEADS | NOVA | ZZ1')
                     and exists (select 1 from jsonb_array_elements(v -> 'anuncios') a where a ->> 'anuncio' = 'ad111'),
                     'anúncios da Web pelo id (CRIATIVO Q, 2 page views) e o formato antigo (ad111) continua: ' || (v -> 'anuncios')::text);
  if to_regclass('mkt_trafego.desempenho_dia') is null then
    perform pg_temp.diz('8b.trafego', 'PULADO (20261005p não aplicada: o cruzamento com o Tráfego fica para quando ela existir)');
    return;
  end if;
  select c.conta_id into v_conta from mkt_trafego.campanhas c where c.campanha_externa = 'camp1';
  execute 'insert into mkt_trafego.campanhas (plataforma, conta_id, campanha_externa, nome, leitura, fora_padrao, projeto_id)
           values (''meta'', $1, ''120100000000098'', ''RS | ZZWEB98 | LEADS | NOVA | ZZ1'', mkt.campanha_traduzir(''RS | ZZWEB98 | LEADS | NOVA | ZZ1''), false, $2) returning id'
    into v_camp using v_conta, pg_temp.id('proj');
  v := pg_temp.adm(format('select public.mkt_web_connect(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje(), mkt_web.hoje()));
  perform pg_temp.ok('8b.trafego', exists (select 1 from jsonb_array_elements(v -> 'campanhas') c
                                            where c ->> 'campanha_externa' = '120100000000098' and c ->> 'page_views' = '3' and c ->> 'leads' = '1')
                     and v -> 'sem_campanha' ->> 'page_views' = '2' and v -> 'sem_campanha' ->> 'campanhas' = '2',
                     'campanha 120100000000098: 3 page views (nome|id, só id, só nome) e 1 lead; nome certo com id de outra campanha '
                     || 'fica em "sem campanha" (2 page views de 2 campanhas, com a "outra campanha" do passo 8): ' || (v -> 'sem_campanha')::text);
end $t$;

-- 9. Período acima de 92 dias
do $t$
begin
  perform pg_temp.adm(format('select public.mkt_web_fluxo(%s, %L, %L)', pg_temp.id('proj'), mkt_web.hoje() - 100, mkt_web.hoje()));
  perform pg_temp.ok('9.periodo', false, 'período de 100 dias passou');
exception when sqlstate '22023' then
  reset role;
  perform pg_temp.ok('9.periodo', true, 'período acima de 92 dias recusado (22023)');
end $t$;

-- 10. Quem não é admin/dev não lê
do $t$
declare
  c text;
  v_quem text;
  v_uid text;
  v_role text;
  v_n int;
  v_chamadas text[] := array[
    'select public.mkt_web_fluxo(1, current_date, current_date)',
    'select public.mkt_web_melhorias(1, current_date, current_date)',
    'select public.mkt_web_comparar(1, null, current_date, current_date, null, current_date, current_date)',
    'select public.mkt_web_calor(1, 1, ''mobile'', current_date, current_date)',
    'select public.mkt_web_lab(1)',
    'select public.mkt_web_leads(1, current_date, current_date)',
    'select public.mkt_web_connect(1, current_date, current_date)',
    'select 1 from mkt_web.velocidade_lab limit 1'];
begin
  foreach v_quem in array array['sem_perfil', 'operador_mkt_web', 'visualizador', 'anon'] loop
    v_uid := case v_quem when 'sem_perfil' then '00000000-0000-4000-8000-0000000000ff'
                         when 'operador_mkt_web' then '11111111-1111-4111-8111-111111111111'
                         when 'visualizador' then '22222222-2222-4222-8222-222222222222'
                         else '00000000-0000-4000-8000-0000000000fe' end;
    v_role := case when v_quem = 'anon' then 'anon' else 'authenticated' end;
    perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"' || v_role || '"}', true);
    v_n := 0;
    foreach c in array v_chamadas loop
      execute format('set local role %I', v_role);
      begin
        execute c;
        reset role;
        perform pg_temp.ok('10.' || v_quem, false, 'PASSOU: ' || c);
      exception when insufficient_privilege then
        reset role;
        v_n := v_n + 1;
      end;
    end loop;
    perform pg_temp.ok('10.' || v_quem, v_n = cardinality(v_chamadas), v_n || ' de ' || cardinality(v_chamadas) || ' recusadas (42501)');
  end loop;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
