-- 20261006f: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql), DEPOIS da
--   20261005m (já aplicada em 05/10/2026). Todo resultado vai para a tabela temporária _z_out; o penúltimo comando
--   mostra tudo. Se o cliente só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive),
--   leia, e rode o "rollback;" em seguida. NÃO deixe a transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261006f_mkt_web_coleta.sql; se a migration
-- mudar, gerar de novo). Depois dele, os testes chamam as funções como a rota do servidor (service_role) e como a tela
-- (JWT simulado, role authenticated). O projeto de TESTE usa a sigla ZZWEB99 e o domínio exemplo.invalid; tudo some no
-- rollback. O dia "hoje" é o de São Paulo (as datas abaixo variam com o dia em que rodar).
--
-- Esperados (conferir no _z_out):
--   1.tabelas = 14     1.funcoes_publicas = 12
--   1.contrato_pb26   = coleta=false lead=lead_qualificado,lead_inscricao,form_enviado funis=3
--   1.cron            = mkt-web-agregar 20 6 * * * ; mkt-web-manter 17 6 * * * ; mkt-web-ritmo */10 * * * *
--   2.dominio_fora = dominio   2.sem_origem = dominio   2.projeto_desconhecido = projeto   2.projeto_sem_coleta = projeto
--   2.payload_grande = tamanho   2.json_invalido = json   2.identificador = identificador
--   2.limite_ip = ok,ok,ok,ok,ok,limite   (limite baixado para 5 só no teste)
--   2.limite_sessao = ok,ok,ok,limite     (limite baixado para 3 só no teste)
--   2.pausada = pausado
--   3.A_pv1 = ok   3.A_repetido = repetido   3.A_pv2 = ok   3.B = ok   3.C_teste = ok   3.E = ok
--   3.sessao_A = engajou=evento lead=true cliques=2 raiva=1 mortos=1 erros=1 paginas=2 entrada=/zz1/ saida=/obrigado-zz/
--                entrada_pagina_ok=true utm_content=120200000000001 fbclid=true app=instagram cidade=Campinas
--   3.sessao_B = engajada=false lead=false
--   3.cliques  = auto=false raiva=false ; auto=false raiva=true ; auto=true raiva=false
--   3.erros    = pagina:-:app.js ; fora:sem_detalhe:          (o ?fbclid do arquivo some; "Script error." é de fora)
--   3.evento_lead_dados = {"motivo": "ok"}                    (o "email" do dataLayer NÃO fica: só chaves permitidas)
--   3.pv_A1    = caminho=/zz1/ pagina_ok=true lcp=2000 cls=0.05 r30=40 secoes={"topo": 5, "oferta": 7} form_email=[1, 8, 1, 1]
--   3.mapa     = {topo,oferta} {inscrever} {nome,email,telefone}
--   3.pv_E     = caminho=/x/ pagina_id=null                    (domínio cadastrado, caminho não: guarda sem página)
--   3.resumo (4 linhas; a visita de teste C fica fora):
--     /obrigado-zz/ mobile: vis=1 sess=1 ent=0 eng=0 lead_ent=0 sess_lead=1 rapidas=1 rol=100 rol75=1 lcp=- cliques=0 raiva=0 mortos=0 erros=0
--     /x/ desktop: vis=1 sess=1 ent=1 eng=0 lead_ent=0 sess_lead=0 rapidas=0 rol=50 rol75=0 lcp=- cliques=0 raiva=0 mortos=0 erros=0
--     /zz1/ desktop: vis=1 sess=1 ent=1 eng=0 lead_ent=0 sess_lead=0 rapidas=1 rol=20 rol75=0 lcp=- cliques=0 raiva=0 mortos=0 erros=0
--     /zz1/ mobile: vis=1 sess=1 ent=1 eng=1 lead_ent=1 sess_lead=1 rapidas=0 rol=80 rol75=1 lcp=2000 cliques=2 raiva=1 mortos=1 erros=1
--   3.agregar = 4     3.agregar_igual = true   (o que o agendamento grava = o que a tela calcula)
--   4.visao_kpis = {"leads": 1, "sessoes": 3, "com_erro": 1, "com_raiva": 1, "engajadas": 1, "de_anuncio": 1, "resultados": {},
--                   "visitantes": 3, "visivel_ms_medio": 6500, "paginas_por_sessao": 1.33}
--   4.visao_serie_hoje = {"dia": "<hoje>", "leads": 1, "sessoes": 3, "engajadas": 1, "visualizacoes": 4}
--   4.funil = Entrou na ZZ1=2 > Abriu o formulário=1 > Lead=1 > Viu o obrigado=1
--   4.origem = total=3 meta=1 fontes=[(direto) 2 sessões, ig/paid 1 sessão 1 lead] campanha=RS | ZZWEB99 | LEADS | TESTE | ZZ1
--              com padrao=true pagina=zz1 projeto=ZZWEB99 campanha_id=null (formato antigo: só nome, sem id)
--   4.velocidade = /obrigado-zz/ mobile lcp=- ; /x/ desktop lcp=- ; /zz1/ desktop lcp=- ; /zz1/ mobile lcp=2000
--   4.leitura = rolagem media=50 chegou_25/50/75=1 chegou_100=0 media_30s=40 vaivem_medio=2.00; secoes topo(1)=5 s,
--               oferta(2)=7 s; ctas inscrever viram=1 cliques=1
--   4.problemas = cliques=2 raiva=1 mortos=1 auto=1 erros=1 fora=[sem_detalhe n=1]
--   4.formulario = medidas=1 comecaram=1 enviaram=1; campos nome(1) email(2, com_erro=1) telefone(3)
--   4.instalacao = ZZWEB99 coleta=true dominios=["exemplo.invalid"] e as recusas do passo 2 (projeto 2, dominio 2,
--                  limite_sessao 1, limite_ip 1, identificador 1, tamanho 1, json 1)
--   4.paginas = /obrigado-zz/ vis=1 ent=0 rej=0 lead=0 cod=- ; /x/ vis=1 ent=1 rej=1 lead=0 cod=- ; /zz1/ vis=2 ent=2 rej=1 lead=1 cod=zz1
--   4.coleta_desligar = {"ok": true, "msg": "Coleta do ZZWEB99 desligada."}   4.depois_de_desligar = projeto
--   4.periodo_longo = 22023 ok     4.dominios_servico = {}   (PB26 nasce com a coleta desligada)
--   5.tabelas = anon/authenticated com privilégio em 0 de 14 ; rls_desligada=0     5.schema = mkt_web=false nos dois
--   5.funcoes = anon=0 auth=(as 10 de leitura) servico=mkt_web_coletar,mkt_web_dominios
--   6.sem_perfil / 6.operador_mkt_web / 6.visualizador / 6.anon = "42501 ok" nas 13 chamadas de cada um (as 10 de leitura,
--     a coleta, os domínios e o select direto em mkt_web.sessoes)
--   6b.* = todas as linhas começam com "ok:" (UTM nome|id: separar, ids da origem, gravação, aba Origem por id)
--   7.manter = 1   7.sessao_velha = 0   7.espaco_ok = ok   7.ritmo_velho = 0
--   7.espaco_teto = pausada   7.coleta_depois_do_teto = pausada   7.falha_registrada = 1
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
  if to_regnamespace('mkt_web') is null or to_regclass('mkt.projetos') is null or to_regclass('mkt.paginas') is null then
    raise exception '20261006f: falta a 20261005m (schema mkt_web, mkt.projetos, mkt.paginas)';
  end if;
  if exists (select 1 from pg_class c where c.relnamespace = 'mkt_web'::regnamespace)
     or exists (select 1 from pg_proc p where p.pronamespace = 'mkt_web'::regnamespace) then
    raise exception '20261006f: mkt_web não está vazio (migration já aplicada?)';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_web\_%') then
    raise exception '20261006f: já existem funções public.mkt_web_*';
  end if;
  if to_regprocedure('mkt.pode_ver(text)') is null then
    raise exception '20261006f: mkt.pode_ver(text) ausente';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception '20261006f: papel service_role ausente';
  end if;
end
$guarda$;

-- ─── 1. Auxiliares puras (internas, sem grant) ───────────────────────────────────────────────────────────────────────
-- o "dia" de tudo na Web: fuso de São Paulo (igual radar.hoje)
create function mkt_web.hoje() returns date
language sql stable set search_path = '' as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;

-- números vindos de fora: texto que não é número vira o padrão, sem erro
create function mkt_web.inteiro(t text, padrao bigint default 0) returns bigint
language sql immutable set search_path = '' as $$
  select case when t ~ '^-?[0-9]{1,15}$' then t::bigint else padrao end
$$;
create function mkt_web.decimal(t text, padrao double precision default 0) returns double precision
language sql immutable set search_path = '' as $$
  select case when t ~ '^-?[0-9]{1,12}(\.[0-9]+)?$' then t::double precision else padrao end
$$;
create function mkt_web.sim(t text) returns boolean
language sql immutable set search_path = '' as $$ select coalesce(t, '') in ('1', 'true') $$;
create function mkt_web.faixa(t text, minimo bigint, maximo bigint) returns bigint
language sql immutable set search_path = '' as $$
  select least(greatest(mkt_web.inteiro(t, minimo), minimo), maximo)
$$;
-- número opcional: ausente ou fora do formato = nulo (a velocidade sem medida não vira zero)
create function mkt_web.opcional(t text, maximo bigint) returns bigint
language sql immutable set search_path = '' as $$
  select case when t ~ '^[0-9]{1,15}$' then least(t::bigint, maximo) end
$$;

-- UTM no padrão oficial do gp-operacoes (departamentos/dados/areas/infraestrutura/processos/padronizar-utm-dos-links.md,
-- confirmado pelo Victor em 06/10/2026): no Meta, campanha, conjunto e anúncio vão como "nome|id"; o nome da campanha
-- também tem " | " dentro (GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA). O id é o que vem DEPOIS DA ÚLTIMA "|",
-- só se for número. Sem "|": número = id, senão nome (formato antigo: só id ou só nome; o Google só tem macro de id).
-- A LEITURA ÚNICA de utm_campaign, utm_medium e utm_content é esta; a mesma regra em TypeScript:
-- web/modules/marketing/projetos/domain/utm.ts (testes em utm.test.ts). Mudou aqui, muda lá.
create function mkt.utm_separar(p_texto text, out nome text, out id text)
language sql immutable parallel safe set search_path = '' as $$
  with t as (select nullif(btrim(p_texto), '') as v),
  p as (select t.v, btrim(substring(t.v from '\|([^|]*)$')) as fim, nullif(btrim(substring(t.v from '^(.*)\|[^|]*$')), '') as ini
          from t)
  select case when p.fim ~ '^[0-9]+$' then p.ini when p.v ~ '^[0-9]+$' then null else p.v end,
         case when p.fim ~ '^[0-9]+$' then p.fim when p.v ~ '^[0-9]+$' then p.v end
    from p
$$;
revoke all on function mkt.utm_separar(text) from public, anon, authenticated;

-- Os ids da origem de uma visita: o parâmetro explícito (campaign_id, adset_id, ad_id) vale primeiro; senão o id que vem
-- no UTM (campanha em utm_campaign, anúncio/criativo em utm_content, conjunto em utm_medium só com utm_source=metaads,
-- padrão do gp-operacoes). Nomes: a parte do nome do UTM, sem o id. Cruzar SEMPRE pelo id; nome só na falta dele.
-- A gravação (mkt_web.ingerir) guarda os ids em sessoes.campaign_id/adset_id/ad_id; as leituras chamam esta função de
-- novo para valer também em visita gravada sem passar pela coleta (ensaio, carga de dado antigo).
create function mkt_web.origem_ids(p_source text, p_medium text, p_campanha text, p_conteudo text,
                                   p_campaign_id text, p_adset_id text, p_ad_id text,
                                   out campanha_id text, out campanha_nome text, out conjunto_id text,
                                   out anuncio_id text, out anuncio_nome text)
language sql immutable parallel safe set search_path = '' as $$
  select coalesce(nullif(btrim(p_campaign_id), ''), c.id), c.nome,
         coalesce(nullif(btrim(p_adset_id), ''), case when lower(btrim(p_source)) = 'metaads' then m.id end),
         coalesce(nullif(btrim(p_ad_id), ''), a.id), a.nome
    from mkt.utm_separar(p_campanha) c, mkt.utm_separar(p_medium) m, mkt.utm_separar(p_conteudo) a
$$;

-- nome técnico de seção, botão ou campo (igual radar.nome_curto)
create function mkt_web.nome_curto(v text) returns text
language sql immutable set search_path = '' as $$
  select left(btrim(regexp_replace(lower(coalesce(v, '')), '[^a-z0-9_-]+', '-', 'g'), '-'), 40)
$$;

-- lista de nomes vinda do navegador, na ordem, sem repetir (igual radar.nomes)
create function mkt_web.nomes(j jsonb, limite int) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(n order by o), '{}')
    from (select n, min(o) as o
            from (select mkt_web.nome_curto(e.v) as n, e.o
                    from jsonb_array_elements_text(case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end)
                         with ordinality e(v, o)
                   where e.o <= limite) x
           where n <> '' group by n) y
$$;

-- {"nome": número}: nomes limpos e números dentro do limite (igual radar.contagens)
create function mkt_web.contagens(j jsonb, maximo int, limite int default 30) returns jsonb
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(j) = 'object' then coalesce((
    select jsonb_object_agg(k, v)
      from (select mkt_web.nome_curto(e.key) as k,
                   max(least(greatest(mkt_web.inteiro(e.value #>> '{}', 0), 0), maximo))::int as v
              from jsonb_each(j) e group by 1 order by 1 limit limite) x
     where k <> ''), '{}'::jsonb) end
$$;

-- formulário: v = apareceu na tela, t = segundos do primeiro foco ao último, s = envios, u = último campo,
-- c = {campo: [focos, segundos com foco, ficou preenchido 0/1, erros de validação]}. Nunca o valor digitado.
create function mkt_web.form_limpo(j jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(j) = 'object' then jsonb_build_object(
    'v', mkt_web.faixa(j ->> 'v', 0, 1),
    't', mkt_web.faixa(j ->> 't', 0, 86400),
    's', mkt_web.faixa(j ->> 's', 0, 100),
    'u', mkt_web.nome_curto(j ->> 'u'),
    'c', coalesce((
       select jsonb_object_agg(k, v)
         from (select mkt_web.nome_curto(e.key) as k,
                      jsonb_build_array(mkt_web.faixa(e.value ->> 0, 0, 1000), mkt_web.faixa(e.value ->> 1, 0, 86400),
                                        mkt_web.faixa(e.value ->> 2, 0, 1), mkt_web.faixa(e.value ->> 3, 0, 1000)) as v
                 from jsonb_each(case when jsonb_typeof(j -> 'c') = 'object' then j -> 'c' else '{}'::jsonb end) e
                where jsonb_typeof(e.value) = 'array' limit 30) x
        where k <> ''), '{}'::jsonb)) end
$$;

-- desenho da página: lista nova que contém a antiga vale inteira; senão só acrescenta o novo (igual radar.juntar_nomes)
create function mkt_web.juntar_nomes(antigo text[], novo text[]) returns text[]
language sql immutable set search_path = '' as $$
  select case when coalesce(cardinality(novo), 0) = 0 then coalesce(antigo, '{}')
              when coalesce(antigo, '{}') <@ novo then novo
              else antigo || array(select n from unnest(novo) with ordinality x(n, o) where not (n = any (antigo)) order by o) end
$$;

-- caminho da página como em mkt.paginas: minúsculo, sem index.html, com barra no fim
create function mkt_web.caminho_limpo(c text) returns text
language sql immutable set search_path = '' as $$
  select case when x = '' then '/' when right(x, 1) = '/' then x else x || '/' end
    from (select left(regexp_replace(lower(regexp_replace(coalesce(nullif(btrim(c), ''), '/'), '[?#].*$', '')),
                                     'index\.html?$', ''), 200) as x) y
$$;

-- host da origem do navegador, sem porta e sem www. (o domínio em mkt.paginas não tem www)
create function mkt_web.host(origem text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(lower(substring(coalesce(origem, '') from '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+)')), '^www\.', '')
$$;

-- erro que não é da página (025 do Radar): app_android, app_iphone, extensao, sem_detalhe, aviso, outro_site; ou nulo
create function mkt_web.erro_de_fora_tipo(mensagem text, arquivo text, dominios text[]) returns text
language sql immutable set search_path = '' as $$
  select case
    when coalesce(arquivo, '') ~* 'navigation_performance_logger' or mensagem ~* 'java object is gone' then 'app_android'
    when mensagem ~* 'webkit\.messagehandlers|_autofillcallbackhandler|__gcrweb|instantsearchsdkjsbridge|__firefox__' then 'app_iphone'
    when (coalesce(mensagem, '') || ' ' || coalesce(arquivo, '')) ~* '(chrome|moz|safari|safari-web|ms-browser)-extension:|webkit-masked-url:' then 'extensao'
    when mensagem ~* '^\s*script error\.?\s*$' and coalesce(arquivo, '') = '' then 'sem_detalhe'
    when mensagem ~* 'resizeobserver loop' then 'aviso'
    when cardinality(dominios) > 0
         and regexp_replace(lower(substring(arquivo from '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+)')), '^www\.', '') <> all (dominios) then 'outro_site'
  end
$$;

-- o arquivo do erro sem query string e sem # (o fbclid não fica guardado)
create function mkt_web.arquivo_limpo(arquivo text) returns text
language sql immutable set search_path = '' as $$ select left(regexp_replace(arquivo, '[?#].*$', ''), 80) $$;

-- clique que não foi gente (025 do Radar): posição 0,0, ou x = 0 exato num campo de formulário
create function mkt_web.clique_automatico(x_pct real, y_px integer, seletor text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(x_pct = 0 and (y_px = 0 or seletor ~ '(^|> )(input|select|textarea)([^a-z>][^>]*)?$'), false)
$$;

-- ─── 2. Tabelas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create table mkt_web.config (
  chave         text primary key check (chave ~ '^[a-z_]{2,40}$'),
  valor         text not null check (length(valor) <= 200),
  atualizado_em timestamptz not null default now()
);
comment on table mkt_web.config is 'Chaves da coleta da Web: coleta (ligada|pausada), limites por minuto, retenções e teto de espaço.';
insert into mkt_web.config (chave, valor) values
  ('coleta', 'ligada'),                 -- 'pausada' = a função responde 'pausado' e não escreve nada
  ('limite_ip_minuto', '600'),          -- pacotes por minuto por IP (hash). Celular em rede de operadora divide IP
  ('limite_sessao_minuto', '60'),       -- pacotes por minuto por sessão (o gravador manda 1 a cada 3 s = 20)
  ('limite_mb', '2048'),                -- teto do schema mkt_web; passou, a coleta pausa sozinha
  ('retencao_sessoes_dias', '395'),     -- 13 meses: sessões e páginas vistas (como o Radar)
  ('retencao_detalhe_dias', '90');      -- cliques, eventos e erros (como o Radar)

-- O contrato do funil de cada projeto (era radar.projetos.config). coleta = a chave que liga o projeto: sem ela, o
-- pacote é recusado mesmo vindo de domínio cadastrado. funis = [{id, nome, etapas: [{nome, caminhos[] | eventos[]}]}]
create table mkt_web.funis (
  projeto_id           bigint primary key references mkt.projetos(id) on delete cascade,
  coleta               boolean not null default false,
  eventos_lead         text[] not null default '{}',
  chaves_datalayer     text[] not null default '{pagina,motivo,origem,area,versao}',
  resultados           jsonb not null default '[]' check (jsonb_typeof(resultados) = 'array'),
  funis                jsonb not null default '[]' check (jsonb_typeof(funis) = 'array'),
  engajamento_segundos int not null default 10 check (engajamento_segundos between 1 and 120),
  atualizado_em        timestamptz not null default now(),
  atualizado_por       uuid references public.perfis(id) on delete set null
);
comment on table mkt_web.funis is 'Contrato do funil por projeto (etapas, eventos de lead, resultados) e a chave da coleta. Uma linha por projeto.';

-- O navegador (id aleatório do gravador, 1 ano). lead_ref: referência opaca ao lead da base de pessoas (futura); nunca
-- e-mail ou telefone. Vazia nesta fase.
create table mkt_web.visitantes (
  projeto_id   bigint not null references mkt.projetos(id) on delete cascade,
  id           text not null check (id ~ '^[A-Za-z0-9]{8,40}$'),
  primeira_vez timestamptz not null default now(),
  ultima_vez   timestamptz not null default now(),
  sessoes      int not null default 0,
  lead_ref     text check (lead_ref is null or lead_ref ~ '^[A-Za-z0-9_-]{8,80}$'),
  primary key (projeto_id, id)
);

-- A visita: por aba, nova depois de 30 min parada ou com clique novo de anúncio. Contadores só com sinal de gente.
create table mkt_web.sessoes (
  id               text primary key check (id ~ '^[A-Za-z0-9]{8,40}$'),
  projeto_id       bigint not null references mkt.projetos(id) on delete cascade,
  visitante        text not null,
  dia              date not null,
  inicio           timestamptz not null,
  fim              timestamptz not null,
  recebido_em      timestamptz not null default now(),
  dispositivo      text not null check (dispositivo in ('mobile', 'tablet', 'desktop')),
  teste            boolean not null default false,
  utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text,
  campaign_id text, adset_id text, ad_id text,
  fbclid           boolean not null default false,
  gclid            boolean not null default false,
  referrer         text,
  entrada_pagina_id bigint references mkt.paginas(id) on delete set null,
  entrada_caminho  text not null,
  saida_caminho    text not null,
  paginas          int not null default 0,
  cliques          int not null default 0,
  raiva            int not null default 0,
  mortos           int not null default 0,
  erros            int not null default 0,
  eventos_funil    int not null default 0,
  visivel_ms       bigint not null default 0,
  engajada         boolean not null default false,
  engajou_em       timestamptz,
  engajou_por      text check (engajou_por in ('tempo', 'clique', 'evento', 'paginas')),
  lead             boolean not null default false,
  lead_em          timestamptz,
  resultado        text,
  resultado_em     timestamptz,
  sistema text, navegador text, app text, pais text, estado text, cidade text
);
create index sessoes_projeto_dia on mkt_web.sessoes (projeto_id, dia);
create index sessoes_visitante on mkt_web.sessoes (projeto_id, visitante);
create index sessoes_recebido on mkt_web.sessoes (projeto_id, recebido_em desc);
comment on column mkt_web.sessoes.utm_content is 'O anúncio (criativo) no formato nome|id, padrão oficial do gp-operacoes (padronizar-utm-dos-links.md); o sistema cruza pelo id (ad_id). Aceita o formato antigo (só id ou só nome).';
comment on column mkt_web.sessoes.utm_campaign is 'A campanha no formato nome|id (padrão do gp-operacoes; o nome tem " | " dentro, o id vem depois da última "|"); o sistema cruza pelo id (campaign_id). Google: só id.';
comment on column mkt_web.sessoes.utm_medium is 'No Meta (utm_source=metaads), o conjunto de anúncios no formato nome|id; o id vai para adset_id.';
comment on column mkt_web.sessoes.campaign_id is 'Id da campanha: parâmetro campaign_id da URL ou, na falta dele, o id do utm_campaign (mkt_web.origem_ids). Mesma lógica em adset_id (utm_medium do Meta) e ad_id (utm_content).';

create table mkt_web.visualizacoes (
  id          text primary key check (id ~ '^[A-Za-z0-9]{8,40}$'),
  sessao      text not null references mkt_web.sessoes(id) on delete cascade,
  projeto_id  bigint not null references mkt.projetos(id) on delete cascade,
  pagina_id   bigint references mkt.paginas(id) on delete set null,
  dominio     text not null,
  caminho     text not null,
  titulo      text,
  dia         date not null,
  ordem       smallint not null,
  inicio      timestamptz not null,
  fim         timestamptz not null,
  dispositivo text not null,
  largura     int,
  altura_doc  int,
  rolagem     smallint not null default 0 check (rolagem between 0 and 100),
  rolagem_30s smallint check (rolagem_30s between 0 and 100),
  visivel_ms  int not null default 0,
  ativo_ms    int,
  vaivem      smallint,
  lcp_ms int, inp_ms int, cls real, fcp_ms int, ttfb_ms int, carga_ms int, peso_kb int, rede text,
  secoes      jsonb,
  ctas        jsonb,
  form        jsonb
);
create index visualizacoes_sessao on mkt_web.visualizacoes (sessao, ordem);
create index visualizacoes_projeto_dia on mkt_web.visualizacoes (projeto_id, dia);
create index visualizacoes_pagina_dia on mkt_web.visualizacoes (pagina_id, dia) where pagina_id is not null;

create table mkt_web.eventos (
  id           bigint generated always as identity primary key,
  sessao       text not null references mkt_web.sessoes(id) on delete cascade,
  visualizacao text not null,
  projeto_id   bigint not null,
  pagina_id    bigint,
  dia          date not null,
  quando       timestamptz not null,
  nome         text not null,
  dados        jsonb not null default '{}'
);
create index eventos_projeto_dia on mkt_web.eventos (projeto_id, dia, nome);
create index eventos_sessao on mkt_web.eventos (sessao);

create table mkt_web.cliques (
  id           bigint generated always as identity primary key,
  sessao       text not null references mkt_web.sessoes(id) on delete cascade,
  visualizacao text not null,
  projeto_id   bigint not null,
  pagina_id    bigint,
  dia          date not null,
  dispositivo  text not null,
  quando       timestamptz not null,
  x_pct        real not null,
  y_px         int not null,
  seletor      text not null default '',
  texto        text not null default '',
  raiva        boolean not null default false,
  morto        boolean not null default false,
  fixo         boolean not null default false,
  automatico   boolean not null default false
);
create index cliques_projeto_dia on mkt_web.cliques (projeto_id, dia);
create index cliques_visualizacao on mkt_web.cliques (visualizacao);
create index cliques_sessao on mkt_web.cliques (sessao);

create table mkt_web.erros (
  id           bigint generated always as identity primary key,
  sessao       text not null references mkt_web.sessoes(id) on delete cascade,
  visualizacao text not null,
  projeto_id   bigint not null,
  pagina_id    bigint,
  dia          date not null,
  quando       timestamptz not null,
  mensagem     text not null,
  arquivo      text,
  linha        int,
  origem       text not null default 'pagina' check (origem in ('pagina', 'fora')),
  tipo_fora    text
);
create index erros_projeto_dia on mkt_web.erros (projeto_id, dia);
create index erros_visualizacao on mkt_web.erros (visualizacao);
create index erros_sessao on mkt_web.erros (sessao);

-- desenho de cada página cadastrada: seções, botões (data-cta) e campos, na ordem da página
create table mkt_web.paginas_mapa (
  pagina_id     bigint primary key references mkt.paginas(id) on delete cascade,
  secoes        text[] not null default '{}',
  ctas          text[] not null default '{}',
  campos        text[] not null default '{}',
  atualizado_em timestamptz not null default now()
);

-- Resumo por dia, página e aparelho (sem visitas de teste). Mora para sempre (é pequeno) e sobrevive à retenção do
-- detalhe. Sempre recalculado por mkt_web.calcular_dia: a tela e o agendamento usam a mesma conta.
create table mkt_web.resumo_dia (
  dia                date not null,
  projeto_id         bigint not null references mkt.projetos(id) on delete cascade,
  dominio            text not null,
  caminho            text not null,
  dispositivo        text not null,
  pagina_id          bigint,
  visualizacoes      int not null,
  sessoes            int not null,
  visitantes         int not null,
  entradas           int not null,
  entradas_engajadas int not null,
  entradas_lead      int not null,
  sessoes_lead       int not null,
  saidas_rapidas     int not null,
  rolagem_soma       bigint not null,
  rolagem_75         int not null,
  visivel_ms_soma    bigint not null,
  vitais_n           int not null,
  lcp_p75            int,
  inp_p75            int,
  cls_p75            real,
  cliques            int not null,
  raiva              int not null,
  mortos             int not null,
  erros              int not null,
  calculado_em       timestamptz not null default now(),
  primary key (dia, projeto_id, dominio, caminho, dispositivo)
);

-- operação: pacote já recebido (2 dias), recusas contadas por dia, falhas da própria coleta, ritmo (limite de envio)
create table mkt_web.pacotes (
  visualizacao text not null,
  seq          int not null,
  dia          date not null,
  primary key (visualizacao, seq)
);
create index pacotes_dia on mkt_web.pacotes (dia);

create table mkt_web.recusas (
  dia     date not null,
  motivo  text not null,
  detalhe text not null default '',
  vezes   int not null default 0,
  primary key (dia, motivo, detalhe)
);

create table mkt_web.falhas (
  id       bigint generated always as identity primary key,
  quando   timestamptz not null default now(),
  onde     text not null,
  mensagem text not null
);

-- chave = 'ip:<hash>' ou 's:<sessão>'; uma linha por chave e minuto. Apagada em até 1 hora (mkt-web-ritmo).
create table mkt_web.ritmo (
  chave  text not null,
  minuto timestamptz not null,
  n      int not null default 0,
  primary key (chave, minuto)
);
create index ritmo_minuto on mkt_web.ritmo (minuto);

do $rls$
declare t text;
begin
  for t in select c.relname from pg_class c where c.relnamespace = 'mkt_web'::regnamespace and c.relkind in ('r', 'p') loop
    execute format('alter table mkt_web.%I enable row level security', t);
    execute format('revoke all on mkt_web.%I from public, anon, authenticated', t);
  end loop;
end
$rls$;

-- Contrato do PB26, copiado de sistemas/radar/projetos/patrimonio-brasil.json (pacote do Luiz, 05/10/2026). As páginas
-- das etapas viram caminhos (ak1 = /ak1/, raiz = /, bl2 = /bl2/, bl2-otimizacao = /bl2-otimizacao/, obrigado =
-- /obrigado/, pesquisa = /pesquisa/). Coleta DESLIGADA: liga na virada (docs/central-de-dados.md, seção Web).
insert into mkt_web.funis (projeto_id, coleta, eventos_lead, chaves_datalayer, resultados, funis)
select p.id, false,
       '{lead_qualificado,lead_inscricao,form_enviado}',
       '{pagina,motivo,origem,area,versao}',
       '[{"id":"mql","nome":"MQL","evento":["submit_application","mql_sem_lead"]},
         {"id":"nao_mql","nome":"Não MQL","evento":["lead_desqualificado"],"motivo":"perfil"},
         {"id":"profissional","nome":"Profissional","evento":["lead_desqualificado"],"motivo":"profissional"}]'::jsonb,
       '[{"id":"ak1","nome":"Funil AK1","etapas":[
            {"nome":"Entrou na AK1","caminhos":["/ak1/","/"]},
            {"nome":"Abriu o formulário","eventos":["abriu_formulario"]},
            {"nome":"Enviou a inscrição","eventos":["lead_qualificado","lead_inscricao"]},
            {"nome":"Viu o obrigado","caminhos":["/obrigado/"]}]},
         {"id":"bl2","nome":"Funil BL2 com pesquisa","etapas":[
            {"nome":"Entrou na BL2","caminhos":["/bl2/","/bl2-otimizacao/"]},
            {"nome":"Abriu o formulário","eventos":["abriu_formulario"]},
            {"nome":"Enviou a inscrição","eventos":["form_enviado"]},
            {"nome":"Viu a pesquisa","eventos":["pesquisa_vista"]},
            {"nome":"Concluiu a pesquisa","eventos":["pesquisa_concluida"]}]},
         {"id":"recuperacao","nome":"Pesquisa pelo link","etapas":[
            {"nome":"Abriu o link","caminhos":["/pesquisa/"]},
            {"nome":"Concluiu a pesquisa","eventos":["pesquisa_whatsapp_concluida"]}]}]'::jsonb
  from mkt.projetos p where p.sigla = 'PB26';

-- ─── 3. Coleta ───────────────────────────────────────────────────────────────────────────────────────────────────────
create function mkt_web.recusa(p_motivo text, p_detalhe text default '') returns text
language plpgsql set search_path = '' as $$
begin
  insert into mkt_web.recusas as r (dia, motivo, detalhe, vezes)
  values (mkt_web.hoje(), p_motivo, left(coalesce(p_detalhe, ''), 120), 1)
  on conflict (dia, motivo, detalhe) do update set vezes = r.vezes + 1;
  return p_motivo;
end
$$;

-- conta um pacote para a chave neste minuto; true = dentro do limite
create function mkt_web.ritmo_ok(p_chave text, p_limite int) returns boolean
language plpgsql set search_path = '' as $$
declare v_n int;
begin
  insert into mkt_web.ritmo as r (chave, minuto, n) values (p_chave, date_trunc('minute', now()), 1)
  on conflict (chave, minuto) do update set n = r.n + 1
  returning n into v_n;
  return v_n <= p_limite;
end
$$;

-- a página cadastrada para o domínio e caminho: o caminho exato, senão o prefixo mais longo (sem contar a raiz)
create function mkt_web.pagina_do_caminho(p_projeto bigint, p_dominio text, p_caminho text) returns bigint
language sql stable set search_path = '' as $$
  select pg.id from mkt.paginas pg
   where pg.projeto_id = p_projeto and pg.dominio = p_dominio
     and (pg.caminho = p_caminho or (pg.caminho <> '/' and left(p_caminho, length(pg.caminho)) = pg.caminho))
   order by (pg.caminho = p_caminho) desc, length(pg.caminho) desc
   limit 1
$$;

-- O pacote (formato 2 do gravador do Radar, sem vídeo):
-- { v, projeto: 'PB26', seq, final, sessao{id, visitante, teste, origem{utm_*, campaign_id, adset_id, ad_id, fbclid,
--   gclid, referrer}, dispositivo, info{sis, nav, app, pais, estado, cidade}}, pv{id, caminho, titulo, inicio(ms),
--   largura, altura_doc, rolagem, r30, visivel_ms, ativo_ms, vaivem, vitais{lcp, inp, cls, fcp, ttfb, carga, peso, rede},
--   secoes{}, ctas{}, form{}, mapa{s, c, f}}, eventos[{t: pagina|clique|funil|erro, ts, ...}] }
create function mkt_web.ingerir(p jsonb, p_host text) returns text
language plpgsql set search_path = '' as $$
declare
  v_proj     mkt.projetos;
  v_funil    mkt_web.funis;
  s          jsonb := case when jsonb_typeof(p -> 'sessao') = 'object' then p -> 'sessao' else '{}'::jsonb end;
  v          jsonb := case when jsonb_typeof(p -> 'pv') = 'object' then p -> 'pv' else '{}'::jsonb end;
  o          jsonb := case when jsonb_typeof(p -> 'sessao' -> 'origem') = 'object' then p -> 'sessao' -> 'origem' else '{}'::jsonb end;
  inf        jsonb := case when jsonb_typeof(p -> 'sessao' -> 'info') = 'object' then p -> 'sessao' -> 'info' else '{}'::jsonb end;
  vt         jsonb := case when jsonb_typeof(p -> 'pv' -> 'vitais') = 'object' then p -> 'pv' -> 'vitais' else '{}'::jsonb end;
  eventos    jsonb := case when jsonb_typeof(p -> 'eventos') = 'array' then p -> 'eventos' else '[]'::jsonb end;
  v_sid      text := coalesce(s ->> 'id', '');
  v_pvid     text := coalesce(v ->> 'id', '');
  v_vis      text := coalesce(s ->> 'visitante', '');
  v_seq      int := mkt_web.faixa(p ->> 'seq', 0, 1000000)::int;
  v_agora    timestamptz := now();
  v_dominios text[];
  v_caminho  text;
  v_pag      bigint;
  v_ini      timestamptz;
  v_fim      timestamptz;
  v_maior_ts bigint;
  v_ts       timestamptz;
  v_nova     boolean;
  v_sess     mkt_web.sessoes;
  v_disp     text;
  v_ids      record;
  e          jsonb;
  r          jsonb;
  v_dados    jsonb;
  v_resultado text;
  v_lead     boolean := false;
  n_cl int := 0; n_rv int := 0; n_mt int := 0; n_er int := 0; n_fu int := 0;
  v_x real; v_y int; v_sel text; v_auto boolean; v_msg text; v_arq text; v_tipo text;
  v_por      text;
  v_mapa     jsonb := case when jsonb_typeof(p -> 'pv' -> 'mapa') = 'object' then p -> 'pv' -> 'mapa' end;
  v_secoes   text[]; v_ctas text[]; v_campos text[];
begin
  -- projeto pela sigla (PB26), com a coleta ligada
  select * into v_proj from mkt.projetos where sigla = upper(left(coalesce(p ->> 'projeto', ''), 14));
  if not found then return mkt_web.recusa('projeto', left(p ->> 'projeto', 40)); end if;
  select * into v_funil from mkt_web.funis where projeto_id = v_proj.id;
  if not found or not v_funil.coleta then return mkt_web.recusa('projeto', v_proj.sigla || ' sem coleta'); end if;

  -- a origem do navegador tem que ser um domínio de página ATIVA do projeto
  v_dominios := array(select distinct pg.dominio from mkt.paginas pg where pg.projeto_id = v_proj.id and pg.ativa);
  if p_host is null or p_host = '' or not (p_host = any (v_dominios)) then
    return mkt_web.recusa('dominio', coalesce(nullif(p_host, ''), '(sem origem)'));
  end if;
  if v_sid !~ '^[A-Za-z0-9]{8,40}$' or v_pvid !~ '^[A-Za-z0-9]{8,40}$' or v_vis !~ '^[A-Za-z0-9]{8,40}$' then
    return mkt_web.recusa('identificador');
  end if;

  -- o mesmo pacote reenviado não conta duas vezes
  insert into mkt_web.pacotes (visualizacao, seq, dia) values (v_pvid, v_seq, mkt_web.hoje()) on conflict do nothing;
  if not found then return 'repetido'; end if;

  -- relógio: o do navegador ordena a visita; mais de 1 dia errado, vale o do servidor
  v_ini := to_timestamp(mkt_web.inteiro(v ->> 'inicio', 0) / 1000.0);
  if abs(extract(epoch from v_ini - v_agora)) > 86400 then v_ini := v_agora; end if;
  select coalesce(max(mkt_web.faixa(x ->> 'ts', 0, 86400000)), 0) into v_maior_ts from jsonb_array_elements(eventos) x;
  v_fim := v_ini + make_interval(secs => greatest(v_maior_ts, mkt_web.faixa(v ->> 'visivel_ms', 0, 86400000)) / 1000.0);
  v_caminho := mkt_web.caminho_limpo(v ->> 'caminho');
  v_pag := mkt_web.pagina_do_caminho(v_proj.id, p_host, v_caminho);
  v_disp := case when s ->> 'dispositivo' in ('mobile', 'tablet', 'desktop') then s ->> 'dispositivo' else 'desktop' end;

  -- sessão: a primeira página e a origem valem para a visita toda. Os ids da origem (campanha, conjunto, anúncio) saem
  -- do parâmetro explícito ou do UTM no formato nome|id (mkt_web.origem_ids) e ficam guardados para o cruzamento.
  select * into v_ids from mkt_web.origem_ids(o ->> 'utm_source', o ->> 'utm_medium', o ->> 'utm_campaign', o ->> 'utm_content',
                                              o ->> 'campaign_id', o ->> 'adset_id', o ->> 'ad_id');
  insert into mkt_web.sessoes (id, projeto_id, visitante, dia, inicio, fim, recebido_em, dispositivo, teste,
                               utm_source, utm_medium, utm_campaign, utm_content, utm_term, campaign_id, adset_id, ad_id,
                               fbclid, gclid, referrer, entrada_pagina_id, entrada_caminho, saida_caminho)
  values (v_sid, v_proj.id, v_vis, (v_ini at time zone 'America/Sao_Paulo')::date, v_ini, v_fim, v_agora, v_disp,
          mkt_web.sim(s ->> 'teste'),
          left(nullif(o ->> 'utm_source', ''), 120), left(nullif(o ->> 'utm_medium', ''), 300), left(nullif(o ->> 'utm_campaign', ''), 300),
          left(nullif(o ->> 'utm_content', ''), 300), left(nullif(o ->> 'utm_term', ''), 120),
          left(v_ids.campanha_id, 60), left(v_ids.conjunto_id, 60), left(v_ids.anuncio_id, 60),
          mkt_web.sim(o ->> 'fbclid'), mkt_web.sim(o ->> 'gclid'), left(nullif(o ->> 'referrer', ''), 120),
          v_pag, v_caminho, v_caminho)
  on conflict (id) do nothing;
  v_nova := found;
  select * into v_sess from mkt_web.sessoes where id = v_sid for update;
  if v_sess.projeto_id <> v_proj.id then return mkt_web.recusa('sessao de outro projeto'); end if;

  insert into mkt_web.visitantes (projeto_id, id, primeira_vez, ultima_vez, sessoes) values (v_proj.id, v_vis, v_agora, v_agora, 1)
  on conflict (projeto_id, id) do update
    set ultima_vez = excluded.ultima_vez,
        sessoes = mkt_web.visitantes.sessoes + case when v_nova then 1 else 0 end;

  -- página vista: nova ou atualizada (fim, rolagem, tempos e leitura só crescem)
  insert into mkt_web.visualizacoes (id, sessao, projeto_id, pagina_id, dominio, caminho, titulo, dia, ordem, inicio, fim,
                                     dispositivo, largura, altura_doc, rolagem, visivel_ms)
  values (v_pvid, v_sid, v_proj.id, v_pag, p_host, v_caminho, left(v ->> 'titulo', 120), v_sess.dia,
          (select coalesce(max(x.ordem), 0) + 1 from mkt_web.visualizacoes x where x.sessao = v_sid),
          v_ini, v_fim, v_sess.dispositivo,
          mkt_web.faixa(v ->> 'largura', 0, 20000), mkt_web.faixa(v ->> 'altura_doc', 0, 500000),
          mkt_web.faixa(v ->> 'rolagem', 0, 100), mkt_web.faixa(v ->> 'visivel_ms', 0, 86400000))
  on conflict (id) do update set
    fim = greatest(mkt_web.visualizacoes.fim, excluded.fim),
    rolagem = greatest(mkt_web.visualizacoes.rolagem, excluded.rolagem),
    visivel_ms = greatest(mkt_web.visualizacoes.visivel_ms, excluded.visivel_ms),
    altura_doc = greatest(coalesce(mkt_web.visualizacoes.altura_doc, 0), coalesce(excluded.altura_doc, 0))
  where mkt_web.visualizacoes.sessao = excluded.sessao;
  if not found then return mkt_web.recusa('pagina de outra sessao'); end if;

  -- velocidade, tempo ativo, vai e vem e leitura (números que só crescem; vale o maior)
  update mkt_web.visualizacoes x set
    lcp_ms   = coalesce(mkt_web.opcional(vt ->> 'lcp', 300000)::int, x.lcp_ms),
    inp_ms   = greatest(x.inp_ms, mkt_web.opcional(vt ->> 'inp', 60000)::int),
    cls      = greatest(x.cls, case when vt ? 'cls' then least(greatest(mkt_web.decimal(vt ->> 'cls', 0), 0), 10)::real end),
    fcp_ms   = coalesce(x.fcp_ms, mkt_web.opcional(vt ->> 'fcp', 300000)::int),
    ttfb_ms  = coalesce(x.ttfb_ms, mkt_web.opcional(vt ->> 'ttfb', 120000)::int),
    carga_ms = coalesce(x.carga_ms, mkt_web.opcional(vt ->> 'carga', 300000)::int),
    peso_kb  = greatest(x.peso_kb, mkt_web.opcional(vt ->> 'peso', 1000000)::int),
    rede     = coalesce(left(nullif(vt ->> 'rede', ''), 10), x.rede),
    ativo_ms = greatest(x.ativo_ms, mkt_web.opcional(v ->> 'ativo_ms', 86400000)::int),
    vaivem   = greatest(x.vaivem, mkt_web.opcional(v ->> 'vaivem', 1000)::smallint),
    rolagem_30s = greatest(x.rolagem_30s, mkt_web.opcional(v ->> 'r30', 100)::smallint),
    secoes   = case when jsonb_typeof(v -> 'secoes') = 'object' then mkt_web.contagens(v -> 'secoes', 32767) else x.secoes end,
    ctas     = case when jsonb_typeof(v -> 'ctas') = 'object' then mkt_web.contagens(v -> 'ctas', 1, 20) else x.ctas end,
    form     = case when jsonb_typeof(v -> 'form') = 'object' then mkt_web.form_limpo(v -> 'form') else x.form end
  where x.id = v_pvid;

  -- desenho da página (só de página cadastrada)
  if v_mapa is not null and v_pag is not null then
    v_secoes := mkt_web.nomes(v_mapa -> 's', 30);
    v_ctas := mkt_web.nomes(v_mapa -> 'c', 20);
    v_campos := mkt_web.nomes(v_mapa -> 'f', 30);
    if cardinality(v_secoes) + cardinality(v_ctas) + cardinality(v_campos) > 0 then
      insert into mkt_web.paginas_mapa as pm (pagina_id, secoes, ctas, campos) values (v_pag, v_secoes, v_ctas, v_campos)
      on conflict (pagina_id) do update set
        secoes = mkt_web.juntar_nomes(pm.secoes, excluded.secoes), ctas = mkt_web.juntar_nomes(pm.ctas, excluded.ctas),
        campos = mkt_web.juntar_nomes(pm.campos, excluded.campos), atualizado_em = now();
    end if;
  end if;

  -- eventos: cliques, funil (só as chaves permitidas no contrato), erros. No máximo 300 por pacote.
  for e in select value from jsonb_array_elements(eventos) limit 300 loop
    v_ts := v_ini + make_interval(secs => mkt_web.faixa(e ->> 'ts', 0, 86400000) / 1000.0);
    if e ->> 't' = 'clique' then
      v_x := least(greatest(mkt_web.decimal(e ->> 'x', 0), 0), 100);
      v_y := mkt_web.faixa(e ->> 'y', 0, 500000)::int;
      v_sel := left(coalesce(e ->> 'sel', ''), 200);
      v_auto := mkt_web.clique_automatico(v_x, v_y, v_sel);
      insert into mkt_web.cliques (sessao, visualizacao, projeto_id, pagina_id, dia, dispositivo, quando, x_pct, y_px,
                                   seletor, texto, raiva, morto, fixo, automatico)
      values (v_sid, v_pvid, v_proj.id, v_pag, v_sess.dia, v_sess.dispositivo, v_ts, v_x, v_y, v_sel,
              left(coalesce(e ->> 'txt', ''), 40), mkt_web.sim(e ->> 'raiva'), mkt_web.sim(e ->> 'morto'),
              mkt_web.sim(e ->> 'fixo'), v_auto);
      if not v_auto then
        n_cl := n_cl + 1;
        if mkt_web.sim(e ->> 'raiva') then n_rv := n_rv + 1; end if;
        if mkt_web.sim(e ->> 'morto') then n_mt := n_mt + 1; end if;
      end if;
    elsif e ->> 't' = 'funil' and coalesce(e ->> 'nome', '') <> '' then
      select coalesce(jsonb_object_agg(k, left(e ->> k, 60)), '{}'::jsonb) into v_dados
        from unnest(v_funil.chaves_datalayer) k where e ? k;
      insert into mkt_web.eventos (sessao, visualizacao, projeto_id, pagina_id, dia, quando, nome, dados)
      values (v_sid, v_pvid, v_proj.id, v_pag, v_sess.dia, v_ts, left(e ->> 'nome', 60), v_dados);
      n_fu := n_fu + 1;
      if (e ->> 'nome') = any (v_funil.eventos_lead) then v_lead := true; end if;
      for r in select value from jsonb_array_elements(v_funil.resultados) loop
        if (e ->> 'nome') in (select jsonb_array_elements_text(coalesce(r -> 'evento', '[]'::jsonb)))
           and (r ->> 'motivo' is null or r ->> 'motivo' = v_dados ->> 'motivo') then
          v_resultado := r ->> 'id';
          exit;
        end if;
      end loop;
    elsif e ->> 't' = 'erro' then
      v_msg := left(coalesce(e ->> 'msg', ''), 160);
      v_arq := mkt_web.arquivo_limpo(e ->> 'arq');
      v_tipo := mkt_web.erro_de_fora_tipo(v_msg, v_arq, v_dominios);
      insert into mkt_web.erros (sessao, visualizacao, projeto_id, pagina_id, dia, quando, mensagem, arquivo, linha, origem, tipo_fora)
      values (v_sid, v_pvid, v_proj.id, v_pag, v_sess.dia, v_ts, v_msg, v_arq, mkt_web.faixa(e ->> 'linha', 0, 10000000)::int,
              case when v_tipo is null then 'pagina' else 'fora' end, v_tipo);
      if v_tipo is null then n_er := n_er + 1; end if;
    end if;
  end loop;

  -- sessão: contadores, lead, resultado, informações da visita e engajamento
  update mkt_web.sessoes x set
    fim = greatest(x.fim, v_fim),
    recebido_em = v_agora,
    paginas = (select count(*) from mkt_web.visualizacoes w where w.sessao = v_sid),
    saida_caminho = (select w.caminho from mkt_web.visualizacoes w where w.sessao = v_sid order by w.ordem desc limit 1),
    visivel_ms = (select coalesce(sum(w.visivel_ms), 0) from mkt_web.visualizacoes w where w.sessao = v_sid),
    cliques = x.cliques + n_cl, raiva = x.raiva + n_rv, mortos = x.mortos + n_mt, erros = x.erros + n_er,
    eventos_funil = x.eventos_funil + n_fu,
    lead = x.lead or v_lead,
    lead_em = case when v_lead and x.lead_em is null then v_agora else x.lead_em end,
    resultado = coalesce(v_resultado, x.resultado),
    resultado_em = case when v_resultado is not null then v_agora else x.resultado_em end,
    sistema   = coalesce(left(nullif(inf ->> 'sis', ''), 20), x.sistema),
    navegador = coalesce(left(nullif(inf ->> 'nav', ''), 30), x.navegador),
    app       = coalesce(left(nullif(inf ->> 'app', ''), 20), x.app),
    pais      = coalesce(left(nullif(upper(inf ->> 'pais'), ''), 2), x.pais),
    estado    = coalesce(left(nullif(inf ->> 'estado', ''), 40), x.estado),
    cidade    = coalesce(left(nullif(inf ->> 'cidade', ''), 60), x.cidade)
  where x.id = v_sid
  returning * into v_sess;

  if not v_sess.engajada then
    v_por := case
      when (select count(distinct w.caminho) from mkt_web.visualizacoes w where w.sessao = v_sid) >= 2 then 'paginas'
      when v_sess.eventos_funil > 0 then 'evento'
      when v_sess.cliques > 0 then 'clique'
      when v_sess.visivel_ms >= v_funil.engajamento_segundos * 1000 then 'tempo'
    end;
    if v_por is not null then
      update mkt_web.sessoes set engajada = true, engajou_em = v_agora, engajou_por = v_por where id = v_sid;
    end if;
  end if;
  return 'ok';
end
$$;

-- A porta da coleta. Só a rota do servidor chama (service_role). Nunca devolve detalhe de erro para fora.
-- Respostas: ok | repetido | pausado | limite | projeto | dominio | identificador | tamanho | json | erro
create function public.mkt_web_coletar(p_corpo text, p_origem text, p_ip_hash text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  p jsonb;
  v_host text;
  v_sid text;
  v_lim_ip int;
  v_lim_s int;
begin
  if (select c.valor from mkt_web.config c where c.chave = 'coleta') = 'pausada' then return 'pausado'; end if;
  if p_corpo is null or octet_length(p_corpo) > 65536 then return mkt_web.recusa('tamanho'); end if;
  begin
    p := p_corpo::jsonb;
  exception when others then
    return mkt_web.recusa('json');
  end;
  if jsonb_typeof(p) <> 'object' then return mkt_web.recusa('json'); end if;
  v_host := mkt_web.host(p_origem);

  -- limite de envio: por IP (hash) e por sessão, por minuto. Estourou: o gravador para por alguns minutos.
  select mkt_web.inteiro(c.valor, 600) into v_lim_ip from mkt_web.config c where c.chave = 'limite_ip_minuto';
  select mkt_web.inteiro(c.valor, 60) into v_lim_s from mkt_web.config c where c.chave = 'limite_sessao_minuto';
  -- (ifs aninhados: o Postgres não garante a ordem de avaliação de um AND)
  if coalesce(p_ip_hash ~ '^[a-f0-9]{16,64}$', false) then
    if not mkt_web.ritmo_ok('ip:' || p_ip_hash, coalesce(v_lim_ip, 600)) then
      perform mkt_web.recusa('limite_ip', coalesce(v_host, ''));
      return 'limite';
    end if;
  end if;
  v_sid := p -> 'sessao' ->> 'id';
  if coalesce(v_sid ~ '^[A-Za-z0-9]{8,40}$', false) then
    if not mkt_web.ritmo_ok('s:' || v_sid, coalesce(v_lim_s, 60)) then
      perform mkt_web.recusa('limite_sessao', coalesce(v_host, ''));
      return 'limite';
    end if;
  end if;

  return mkt_web.ingerir(p, v_host);
exception when others then
  insert into mkt_web.falhas (onde, mensagem) values ('coletar', left(sqlerrm, 300));
  return 'erro';
end
$$;

-- Domínios aceitos agora (páginas ativas de projetos com a coleta ligada). A rota guarda por alguns minutos e recusa
-- o resto sem ir ao banco.
create function public.mkt_web_dominios() returns text[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct pg.dominio order by pg.dominio), '{}')
    from mkt.paginas pg join mkt_web.funis f on f.projeto_id = pg.projeto_id
   where pg.ativa and f.coleta and (select c.valor from mkt_web.config c where c.chave = 'coleta') <> 'pausada'
$$;

-- ─── 4. Resumo diário, retenção e espaço ─────────────────────────────────────────────────────────────────────────────
-- A conta do dia (sem visitas de teste), por domínio, caminho e aparelho. A mesma para o agendamento e para a tela.
create function mkt_web.calcular_dia(p_dia date, p_projeto bigint default null) returns setof mkt_web.resumo_dia
language sql stable set search_path = '' as $$
  with pv as (
    select w.*, s.visitante, s.engajada, s.lead
      from mkt_web.visualizacoes w join mkt_web.sessoes s on s.id = w.sessao
     where w.dia = p_dia and not s.teste and (p_projeto is null or w.projeto_id = p_projeto)
  ), cl as (
    select c.visualizacao, count(*) as n, count(*) filter (where c.raiva) as r, count(*) filter (where c.morto) as m
      from mkt_web.cliques c
     where c.dia = p_dia and not c.automatico and (p_projeto is null or c.projeto_id = p_projeto)
     group by c.visualizacao
  ), er as (
    select e.visualizacao, count(*) as n
      from mkt_web.erros e
     where e.dia = p_dia and e.origem = 'pagina' and (p_projeto is null or e.projeto_id = p_projeto)
     group by e.visualizacao
  )
  select p_dia, pv.projeto_id, pv.dominio, pv.caminho, pv.dispositivo, max(pv.pagina_id),
         count(*)::int,
         count(distinct pv.sessao)::int,
         count(distinct pv.visitante)::int,
         count(*) filter (where pv.ordem = 1)::int,
         count(*) filter (where pv.ordem = 1 and pv.engajada)::int,
         count(*) filter (where pv.ordem = 1 and pv.lead)::int,
         count(distinct pv.sessao) filter (where pv.lead)::int,
         count(*) filter (where pv.visivel_ms < 3000)::int,
         coalesce(sum(pv.rolagem), 0)::bigint,
         count(*) filter (where pv.rolagem >= 75)::int,
         coalesce(sum(pv.visivel_ms), 0)::bigint,
         count(pv.lcp_ms)::int,
         (percentile_cont(0.75) within group (order by pv.lcp_ms))::int,
         (percentile_cont(0.75) within group (order by pv.inp_ms))::int,
         (percentile_cont(0.75) within group (order by pv.cls))::real,
         coalesce(sum(cl.n), 0)::int, coalesce(sum(cl.r), 0)::int, coalesce(sum(cl.m), 0)::int,
         coalesce(sum(er.n), 0)::int,
         now()
    from pv left join cl on cl.visualizacao = pv.id left join er on er.visualizacao = pv.id
   group by pv.projeto_id, pv.dominio, pv.caminho, pv.dispositivo
$$;

-- grava (ou regrava) o resumo do dia; o agendamento roda ontem e anteontem (pacote atrasado)
create function mkt_web.agregar(p_dia date) returns int
language plpgsql set search_path = '' as $$
declare v_n int;
begin
  delete from mkt_web.resumo_dia where dia = p_dia;
  insert into mkt_web.resumo_dia select * from mkt_web.calcular_dia(p_dia, null);
  get diagnostics v_n = row_count;
  return v_n;
end
$$;

-- retenção (o resumo diário fica)
create function mkt_web.manter() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_sess int; v_det int; v_cl int; v_er int; v_pac int; v_rec int; v_fal int;
  v_dias_s int := (select mkt_web.inteiro(c.valor, 395) from mkt_web.config c where c.chave = 'retencao_sessoes_dias');
  v_dias_d int := (select mkt_web.inteiro(c.valor, 90) from mkt_web.config c where c.chave = 'retencao_detalhe_dias');
begin
  delete from mkt_web.eventos where dia < mkt_web.hoje() - coalesce(v_dias_d, 90); get diagnostics v_det = row_count;
  delete from mkt_web.cliques where dia < mkt_web.hoje() - coalesce(v_dias_d, 90); get diagnostics v_cl = row_count;
  delete from mkt_web.erros where dia < mkt_web.hoje() - coalesce(v_dias_d, 90); get diagnostics v_er = row_count;
  delete from mkt_web.sessoes where dia < mkt_web.hoje() - coalesce(v_dias_s, 395); get diagnostics v_sess = row_count;
  delete from mkt_web.visitantes v where v.ultima_vez < now() - make_interval(days => coalesce(v_dias_s, 395));
  delete from mkt_web.pacotes where dia < mkt_web.hoje() - 2; get diagnostics v_pac = row_count;
  delete from mkt_web.recusas where dia < mkt_web.hoje() - 90; get diagnostics v_rec = row_count;
  delete from mkt_web.falhas where quando < now() - interval '30 days'; get diagnostics v_fal = row_count;
  return jsonb_build_object('sessoes', v_sess, 'eventos', v_det, 'cliques', v_cl, 'erros', v_er, 'pacotes', v_pac,
                            'recusas', v_rec, 'falhas', v_fal);
end
$$;

-- a cada 10 min: apaga o ritmo velho e confere o espaço; passou do teto, pausa a coleta (não apaga nada)
create function mkt_web.vigiar_espaco() returns text
language plpgsql set search_path = '' as $$
declare
  v_mb numeric;
  v_lim int := (select mkt_web.inteiro(c.valor, 2048) from mkt_web.config c where c.chave = 'limite_mb');
begin
  delete from mkt_web.ritmo where minuto < now() - interval '1 hour';
  select coalesce(sum(pg_total_relation_size(c.oid)), 0) / 1048576.0 into v_mb
    from pg_class c where c.relnamespace = 'mkt_web'::regnamespace and c.relkind = 'r';
  if v_mb > coalesce(v_lim, 2048) then
    update mkt_web.config set valor = 'pausada', atualizado_em = now() where chave = 'coleta' and valor <> 'pausada';
    if found then
      insert into mkt_web.falhas (onde, mensagem) values ('espaco', 'coleta pausada: ' || round(v_mb) || ' MB > ' || v_lim || ' MB');
    end if;
    return 'pausada';
  end if;
  return 'ok';
end
$$;

-- ─── 5. Leitura para as telas (authenticated; trava mkt.pode_ver('mkt_web'), hoje admin/dev) ───────────────────────
-- Todas recebem projeto, de e até (máx. 92 dias) e ignoram visita de teste.
create function mkt_web.periodo_ok(p_de date, p_ate date) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p_de is null or p_ate is null or p_ate < p_de or p_ate - p_de > 92 then
    raise exception 'período inválido (de/até, no máximo 92 dias)' using errcode = '22023';
  end if;
end
$$;

-- Visão geral: números do período, a série por dia e o estado da coleta
create function public.mkt_web_visao(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  with s as (
    select * from mkt_web.sessoes x where x.projeto_id = p_projeto and x.dia between p_de and p_ate and not x.teste
  ), dias as (
    select r.dia, sum(r.entradas) as sessoes, sum(r.visualizacoes) as visualizacoes, sum(r.entradas_engajadas) as engajadas,
           sum(r.entradas_lead) as leads
      from (select * from mkt_web.resumo_dia z where z.projeto_id = p_projeto and z.dia between p_de and least(p_ate, mkt_web.hoje() - 2)
            union all
            select c.* from generate_series(greatest(p_de, mkt_web.hoje() - 1), least(p_ate, mkt_web.hoje()), interval '1 day') d,
                   lateral mkt_web.calcular_dia(d::date, p_projeto) c) r
     group by r.dia
  )
  select jsonb_build_object(
    'kpis', (select jsonb_build_object(
        'sessoes', count(*), 'visitantes', count(distinct s.visitante),
        'engajadas', count(*) filter (where s.engajada), 'leads', count(*) filter (where s.lead),
        'visivel_ms_medio', coalesce(round(avg(s.visivel_ms)), 0), 'paginas_por_sessao', coalesce(round(avg(s.paginas), 2), 0),
        'com_raiva', count(*) filter (where s.raiva > 0), 'com_erro', count(*) filter (where s.erros > 0),
        'de_anuncio', count(*) filter (where s.fbclid or s.gclid or s.utm_source is not null),
        'resultados', coalesce((select jsonb_object_agg(t.resultado, t.n) from (select s2.resultado, count(*) as n from s s2
                                 where s2.resultado is not null group by s2.resultado) t), '{}'::jsonb)) from s),
    'serie', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia, 'sessoes', d.sessoes, 'visualizacoes', d.visualizacoes,
                                                           'engajadas', d.engajadas, 'leads', d.leads) order by d.dia) from dias d), '[]'::jsonb),
    'coleta', jsonb_build_object(
        'ligada', coalesce((select f.coleta from mkt_web.funis f where f.projeto_id = p_projeto), false),
        'pausada', (select c.valor = 'pausada' from mkt_web.config c where c.chave = 'coleta'),
        'ultimo_pacote', (select max(x.recebido_em) from mkt_web.sessoes x where x.projeto_id = p_projeto)))
  into v;
  return v;
end
$$;

-- Páginas: uma linha por caminho (com a página cadastrada, quando houver)
create function public.mkt_web_paginas(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  return (
    with pv as (
      select w.*, s.engajada, s.lead
        from mkt_web.visualizacoes w join mkt_web.sessoes s on s.id = w.sessao
       where w.projeto_id = p_projeto and w.dia between p_de and p_ate and not s.teste
    )
    select coalesce(jsonb_agg(x order by (x ->> 'visualizacoes')::int desc), '[]'::jsonb)
      from (select jsonb_build_object(
              'pagina_id', max(pv.pagina_id), 'dominio', pv.dominio, 'caminho', pv.caminho,
              'codigo', (select pg.codigo from mkt.paginas pg where pg.id = max(pv.pagina_id)),
              'nome', (select pg.nome from mkt.paginas pg where pg.id = max(pv.pagina_id)),
              'funcao', (select pg.funcao from mkt.paginas pg where pg.id = max(pv.pagina_id)),
              'visualizacoes', count(*), 'sessoes', count(distinct pv.sessao),
              'entradas', count(*) filter (where pv.ordem = 1),
              'rejeicoes', count(*) filter (where pv.ordem = 1 and not pv.engajada),
              'entradas_lead', count(*) filter (where pv.ordem = 1 and pv.lead),
              'saidas_rapidas', count(*) filter (where pv.visivel_ms < 3000),
              'rolagem_media', coalesce(round(avg(pv.rolagem)), 0),
              'visivel_ms_medio', coalesce(round(avg(pv.visivel_ms)), 0),
              'lcp_p75', (percentile_cont(0.75) within group (order by pv.lcp_ms))::int) as x
              from pv group by pv.dominio, pv.caminho) t);
end
$$;

-- Funil: cada etapa conta as sessões que cumpriram ela E todas as anteriores (caminho visto ou evento disparado)
create function public.mkt_web_funil(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_funis jsonb;
  f jsonb;
  et jsonb;
  v_ids text[];
  v_saida jsonb := '[]'::jsonb;
  v_etapas jsonb;
  v_n int;
  v_i int;
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  select x.funis into v_funis from mkt_web.funis x where x.projeto_id = p_projeto;
  for f in select value from jsonb_array_elements(coalesce(v_funis, '[]'::jsonb)) loop
    v_ids := array(select s.id from mkt_web.sessoes s
                    where s.projeto_id = p_projeto and s.dia between p_de and p_ate and not s.teste);
    v_etapas := '[]'::jsonb;
    v_i := 0;
    for et in select value from jsonb_array_elements(coalesce(f -> 'etapas', '[]'::jsonb)) loop
      v_i := v_i + 1;
      v_ids := array(
        select distinct u.id from unnest(v_ids) u(id)
         where exists (select 1 from mkt_web.visualizacoes w
                        where w.sessao = u.id and w.caminho in (select jsonb_array_elements_text(coalesce(et -> 'caminhos', '[]'::jsonb))))
            or exists (select 1 from mkt_web.eventos e
                        where e.sessao = u.id and e.nome in (select jsonb_array_elements_text(coalesce(et -> 'eventos', '[]'::jsonb)))));
      v_n := coalesce(cardinality(v_ids), 0);
      v_etapas := v_etapas || jsonb_build_object('ordem', v_i, 'nome', et ->> 'nome', 'sessoes', v_n,
                                                 'caminhos', coalesce(et -> 'caminhos', '[]'::jsonb),
                                                 'eventos', coalesce(et -> 'eventos', '[]'::jsonb));
    end loop;
    v_saida := v_saida || jsonb_build_object('id', f ->> 'id', 'nome', f ->> 'nome', 'etapas', v_etapas);
  end loop;
  return v_saida;
end
$$;

-- Origem: plataforma (utm_source), campanha (o NOME traduzido pelo padrão de nome), anúncio/criativo (utm_content), site
-- de origem. Campanha e anúncio no formato nome|id (padrão do gp-operacoes): agrupados pelo id (mkt_web.origem_ids);
-- sem id, pelo nome. "campanha"/"anuncio" = o nome (o id quando só há id, como no Google); "padrao" nulo sem nome.
create function public.mkt_web_origem(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  return (
    with s as (
      select x.*, oi.campanha_id as c_id, oi.campanha_nome as c_nome, oi.anuncio_id as a_id, oi.anuncio_nome as a_nome
        from mkt_web.sessoes x
        cross join lateral mkt_web.origem_ids(x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content,
                                              x.campaign_id, x.adset_id, x.ad_id) oi
       where x.projeto_id = p_projeto and x.dia between p_de and p_ate and not x.teste
    )
    select jsonb_build_object(
      'total', (select count(*) from s),
      'cliques_meta', (select count(*) from s where s.fbclid), 'cliques_google', (select count(*) from s where s.gclid),
      'fontes', coalesce((select jsonb_agg(jsonb_build_object('fonte', t.f, 'meio', t.m, 'sessoes', t.n, 'engajadas', t.e, 'leads', t.l)
                                  order by t.n desc)
                            from (select coalesce(s.utm_source, '(direto)') f, s.utm_medium m, count(*) n,
                                         count(*) filter (where s.engajada) e, count(*) filter (where s.lead) l
                                    from s group by 1, 2 order by 3 desc limit 50) t), '[]'::jsonb),
      'campanhas', coalesce((select jsonb_agg(jsonb_build_object('campanha', coalesce(t.nome, t.cid), 'campanha_id', t.cid,
                                    'sessoes', t.n, 'engajadas', t.e, 'leads', t.l,
                                    'padrao', case when t.nome is not null then (tr.v ->> 'padrao')::boolean end,
                                    'pagina', tr.v ->> 'pagina', 'projeto', tr.v ->> 'projeto') order by t.n desc)
                               from (select max(s.c_id) cid, max(s.c_nome) nome, count(*) n, count(*) filter (where s.engajada) e,
                                            count(*) filter (where s.lead) l
                                       from s where coalesce(s.c_id, s.c_nome) is not null
                                      group by coalesce(s.c_id, s.c_nome) order by 3 desc limit 50) t
                               cross join lateral (select case when t.nome is not null then mkt.campanha_traduzir(t.nome) end as v) tr), '[]'::jsonb),
      'anuncios', coalesce((select jsonb_agg(jsonb_build_object('anuncio', coalesce(t.nome, t.aid), 'anuncio_id', t.aid, 'campanha', t.c,
                                                                'sessoes', t.n, 'engajadas', t.e, 'leads', t.l)
                                  order by t.n desc)
                              from (select max(s.a_id) aid, max(s.a_nome) nome, coalesce(min(s.c_nome), min(s.c_id)) c, count(*) n,
                                           count(*) filter (where s.engajada) e, count(*) filter (where s.lead) l
                                      from s where coalesce(s.a_id, s.a_nome) is not null
                                     group by coalesce(s.a_id, s.a_nome) order by 4 desc limit 50) t), '[]'::jsonb),
      'sites', coalesce((select jsonb_agg(jsonb_build_object('site', t.r, 'sessoes', t.n) order by t.n desc)
                           from (select s.referrer r, count(*) n from s where s.referrer is not null group by 1 order by 2 desc limit 20) t), '[]'::jsonb)));
end
$$;

-- Velocidade real (p75, a régua do Google) por página e aparelho, e a série diária do LCP
create function public.mkt_web_velocidade(p_projeto bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  return (
    with pv as (
      select w.* from mkt_web.visualizacoes w join mkt_web.sessoes s on s.id = w.sessao
       where w.projeto_id = p_projeto and w.dia between p_de and p_ate and not s.teste
    )
    select jsonb_build_object(
      'paginas', coalesce((select jsonb_agg(x order by x ->> 'caminho', x ->> 'dispositivo') from (
          select jsonb_build_object('caminho', pv.caminho, 'dispositivo', pv.dispositivo, 'n', count(pv.lcp_ms),
            'lcp_p75', (percentile_cont(0.75) within group (order by pv.lcp_ms))::int,
            'inp_p75', (percentile_cont(0.75) within group (order by pv.inp_ms))::int,
            'cls_p75', round((percentile_cont(0.75) within group (order by pv.cls))::numeric, 3),
            'fcp_p75', (percentile_cont(0.75) within group (order by pv.fcp_ms))::int,
            'ttfb_p75', (percentile_cont(0.75) within group (order by pv.ttfb_ms))::int,
            'lcp_bom', count(*) filter (where pv.lcp_ms <= 2500), 'peso_kb_mediano', (percentile_cont(0.5) within group (order by pv.peso_kb))::int) x
            from pv group by pv.caminho, pv.dispositivo) t), '[]'::jsonb),
      'serie', coalesce((select jsonb_agg(jsonb_build_object('dia', t.dia, 'lcp_p75', t.l, 'n', t.n) order by t.dia)
                           from (select pv.dia, (percentile_cont(0.75) within group (order by pv.lcp_ms))::int l, count(pv.lcp_ms) n
                                   from pv group by pv.dia) t), '[]'::jsonb)));
end
$$;

-- Rolagem e leitura de uma página: até onde rolam, segundos por seção (na ordem da página), botões vistos e clicados
create function public.mkt_web_leitura(p_projeto bigint, p_pagina bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  return (
    with pv as (
      select w.* from mkt_web.visualizacoes w join mkt_web.sessoes s on s.id = w.sessao
       where w.projeto_id = p_projeto and w.pagina_id = p_pagina and w.dia between p_de and p_ate and not s.teste
    ), mapa as (
      select * from mkt_web.paginas_mapa m where m.pagina_id = p_pagina
    )
    select jsonb_build_object(
      'visualizacoes', (select count(*) from pv),
      'rolagem', jsonb_build_object(
          'chegou_25', (select count(*) from pv where pv.rolagem >= 25), 'chegou_50', (select count(*) from pv where pv.rolagem >= 50),
          'chegou_75', (select count(*) from pv where pv.rolagem >= 75), 'chegou_100', (select count(*) from pv where pv.rolagem >= 100),
          'media', (select coalesce(round(avg(pv.rolagem)), 0) from pv),
          'media_30s', (select round(avg(pv.rolagem_30s)) from pv where pv.rolagem_30s is not null),
          'vaivem_medio', (select round(avg(pv.vaivem), 2) from pv where pv.vaivem is not null)),
      'secoes', coalesce((select jsonb_agg(jsonb_build_object('secao', t.k, 'ordem', t.o, 'segundos', t.seg, 'viram', t.viram,
                                         'medidas', t.medidas) order by t.o nulls last, t.k)
                            from (select e.key k, (select array_position(m.secoes, e.key) from mapa m) o,
                                         sum((e.value #>> '{}')::int) seg, count(*) filter (where (e.value #>> '{}')::int > 0) viram,
                                         (select count(*) from pv p2 where p2.secoes is not null) medidas
                                    from pv, jsonb_each(coalesce(pv.secoes, '{}'::jsonb)) e group by e.key) t), '[]'::jsonb),
      'ctas', coalesce((select jsonb_agg(jsonb_build_object('cta', t.k, 'viram', t.viram, 'medidas', t.medidas,
                                       'cliques', (select count(*) from mkt_web.cliques c join pv p3 on p3.id = c.visualizacao
                                                    where not c.automatico and c.seletor like '%[data-cta="' || t.k || '"]%')) order by t.k)
                          from (select e.key k, count(*) filter (where (e.value #>> '{}')::int > 0) viram,
                                       (select count(*) from pv p2 where p2.ctas is not null) medidas
                                  from pv, jsonb_each(coalesce(pv.ctas, '{}'::jsonb)) e group by e.key) t), '[]'::jsonb),
      'mapa', (select jsonb_build_object('secoes', m.secoes, 'ctas', m.ctas, 'campos', m.campos) from mapa m)));
end
$$;

-- Cliques e erros: raiva, mortos e erros da página (o ruído de fora contado à parte), por elemento e mensagem
create function public.mkt_web_problemas(p_projeto bigint, p_pagina bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  return (
    with s as (
      select x.id from mkt_web.sessoes x where x.projeto_id = p_projeto and x.dia between p_de and p_ate and not x.teste
    ), c as (
      select k.* from mkt_web.cliques k join s on s.id = k.sessao
       where k.projeto_id = p_projeto and k.dia between p_de and p_ate and (p_pagina is null or k.pagina_id = p_pagina)
    ), e as (
      select k.* from mkt_web.erros k join s on s.id = k.sessao
       where k.projeto_id = p_projeto and k.dia between p_de and p_ate and (p_pagina is null or k.pagina_id = p_pagina)
    )
    select jsonb_build_object(
      'cliques', (select count(*) from c where not c.automatico),
      'raiva', (select count(*) from c where not c.automatico and c.raiva),
      'mortos', (select count(*) from c where not c.automatico and c.morto),
      'automaticos', (select count(*) from c where c.automatico),
      'sessoes_com_raiva', (select count(distinct c.sessao) from c where not c.automatico and c.raiva),
      'top_raiva', coalesce((select jsonb_agg(jsonb_build_object('seletor', t.sel, 'texto', t.txt, 'n', t.n, 'sessoes', t.ss) order by t.n desc)
                               from (select c.seletor sel, max(c.texto) txt, count(*) n, count(distinct c.sessao) ss
                                       from c where not c.automatico and c.raiva group by 1 order by 3 desc limit 15) t), '[]'::jsonb),
      'top_mortos', coalesce((select jsonb_agg(jsonb_build_object('seletor', t.sel, 'texto', t.txt, 'n', t.n, 'sessoes', t.ss) order by t.n desc)
                                from (select c.seletor sel, max(c.texto) txt, count(*) n, count(distinct c.sessao) ss
                                        from c where not c.automatico and c.morto group by 1 order by 3 desc limit 15) t), '[]'::jsonb),
      'mais_clicados', coalesce((select jsonb_agg(jsonb_build_object('seletor', t.sel, 'texto', t.txt, 'n', t.n) order by t.n desc)
                                   from (select c.seletor sel, max(c.texto) txt, count(*) n
                                           from c where not c.automatico group by 1 order by 3 desc limit 15) t), '[]'::jsonb),
      'erros', (select count(*) from e where e.origem = 'pagina'),
      'sessoes_com_erro', (select count(distinct e.sessao) from e where e.origem = 'pagina'),
      'top_erros', coalesce((select jsonb_agg(jsonb_build_object('mensagem', t.m, 'arquivo', t.a, 'n', t.n, 'sessoes', t.ss) order by t.n desc)
                               from (select e.mensagem m, e.arquivo a, count(*) n, count(distinct e.sessao) ss
                                       from e where e.origem = 'pagina' group by 1, 2 order by 3 desc limit 15) t), '[]'::jsonb),
      'erros_fora', coalesce((select jsonb_agg(jsonb_build_object('tipo', t.tipo, 'n', t.n, 'sessoes', t.ss) order by t.n desc)
                                from (select e.tipo_fora tipo, count(*) n, count(distinct e.sessao) ss
                                        from e where e.origem = 'fora' group by 1) t), '[]'::jsonb)));
end
$$;

-- Formulário campo a campo (só números): quem viu, começou, enviou; por campo, focos, tempo, preenchido, erros e
-- onde parou quem começou e não enviou
create function public.mkt_web_formulario(p_projeto bigint, p_pagina bigint, p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  perform mkt_web.periodo_ok(p_de, p_ate);
  return (
    with f as (
      select w.form from mkt_web.visualizacoes w join mkt_web.sessoes s on s.id = w.sessao
       where w.projeto_id = p_projeto and w.pagina_id = p_pagina and w.dia between p_de and p_ate and not s.teste
         and w.form is not null
    ), comecou as (
      select * from f where exists (select 1 from jsonb_each(f.form -> 'c') c where (c.value ->> 0)::int > 0)
    )
    select jsonb_build_object(
      'medidas', (select count(*) from f),
      'viram', (select count(*) from f where (f.form ->> 'v')::int = 1),
      'comecaram', (select count(*) from comecou),
      'enviaram', (select count(*) from f where (f.form ->> 's')::int > 0),
      'tempo_mediano_s', (select (percentile_cont(0.5) within group (order by (c.form ->> 't')::int))::int from comecou c),
      'campos', coalesce((select jsonb_agg(jsonb_build_object('campo', t.k, 'entraram', t.entraram, 'focos', t.focos,
                                     'segundos_medio', t.seg, 'preenchidos', t.pre, 'com_erro', t.err,
                                     'ordem', (select array_position(m.campos, t.k) from mkt_web.paginas_mapa m where m.pagina_id = p_pagina))
                                   order by (select array_position(m.campos, t.k) from mkt_web.paginas_mapa m where m.pagina_id = p_pagina) nulls last, t.k)
                            from (select c.key k, count(*) filter (where (c.value ->> 0)::int > 0) entraram, sum((c.value ->> 0)::int) focos,
                                         round(avg((c.value ->> 1)::int) filter (where (c.value ->> 0)::int > 0)) seg,
                                         count(*) filter (where (c.value ->> 2)::int = 1) pre, count(*) filter (where (c.value ->> 3)::int > 0) err
                                    from f, jsonb_each(f.form -> 'c') c group by c.key) t), '[]'::jsonb),
      'pararam_em', coalesce((select jsonb_agg(jsonb_build_object('campo', t.u, 'n', t.n) order by t.n desc)
                                from (select c.form ->> 'u' u, count(*) n from comecou c
                                       where (c.form ->> 's')::int = 0 and coalesce(c.form ->> 'u', '') <> '' group by 1) t), '[]'::jsonb)));
end
$$;

-- Instalação: o que está ligado, as páginas, o contrato e o que a coleta recusou nos últimos 7 dias
create function public.mkt_web_instalacao() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object(
    'coleta_geral', (select c.valor from mkt_web.config c where c.chave = 'coleta'),
    'projetos', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'sigla', p.sigla, 'nome', p.nome, 'ativo', p.ativo,
        'coleta', coalesce(f.coleta, false), 'eventos_lead', coalesce(to_jsonb(f.eventos_lead), '[]'::jsonb),
        'funis', coalesce(f.funis, '[]'::jsonb),
        'dominios', (select coalesce(jsonb_agg(distinct pg.dominio), '[]'::jsonb) from mkt.paginas pg where pg.projeto_id = p.id and pg.ativa),
        'ultimo_pacote', (select max(s.recebido_em) from mkt_web.sessoes s where s.projeto_id = p.id)) order by p.ativo desc, p.sigla)
      from mkt.projetos p left join mkt_web.funis f on f.projeto_id = p.id), '[]'::jsonb),
    'recusas_7d', coalesce((select jsonb_agg(jsonb_build_object('motivo', t.motivo, 'vezes', t.v) order by t.v desc)
                              from (select r.motivo, sum(r.vezes) v from mkt_web.recusas r where r.dia >= mkt_web.hoje() - 6 group by 1) t), '[]'::jsonb),
    'falhas_7d', (select count(*) from mkt_web.falhas x where x.quando >= now() - interval '7 days'));
end
$$;

-- Liga ou desliga a coleta de um projeto (cria a linha do contrato vazia se faltar). Retorna {ok, msg}.
create function public.mkt_web_coleta_ligar(p_projeto bigint, p_ligada boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_sigla text;
begin
  if not mkt.pode_ver('mkt_web') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select p.sigla into v_sigla from mkt.projetos p where p.id = p_projeto;
  if v_sigla is null then return jsonb_build_object('ok', false, 'msg', 'Projeto não encontrado.'); end if;
  insert into mkt_web.funis as f (projeto_id, coleta, atualizado_por) values (p_projeto, coalesce(p_ligada, false), (select auth.uid()))
  on conflict (projeto_id) do update set coleta = excluded.coleta, atualizado_em = now(), atualizado_por = excluded.atualizado_por;
  return jsonb_build_object('ok', true, 'msg', 'Coleta do ' || v_sigla || case when p_ligada then ' ligada.' else ' desligada.' end);
end
$$;

-- ─── 6. Quem executa o quê ───────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'mkt_web'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_web\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end
$grants$;
grant execute on function public.mkt_web_coletar(text, text, text), public.mkt_web_dominios() to service_role;
grant execute on function
  public.mkt_web_visao(bigint, date, date), public.mkt_web_paginas(bigint, date, date), public.mkt_web_funil(bigint, date, date),
  public.mkt_web_origem(bigint, date, date), public.mkt_web_velocidade(bigint, date, date),
  public.mkt_web_leitura(bigint, bigint, date, date), public.mkt_web_problemas(bigint, bigint, date, date),
  public.mkt_web_formulario(bigint, bigint, date, date), public.mkt_web_instalacao(), public.mkt_web_coleta_ligar(bigint, boolean)
  to authenticated;

-- ─── 7. Rotinas (pg_cron; SQL direto, sem HTTP: não passam pelo ops.cron_post). Horário do cron em UTC ───────────────
do $cron$
begin
  if to_regnamespace('cron') is null then
    raise notice '20261006f: pg_cron ausente, rotinas não agendadas';
    return;
  end if;
  perform cron.schedule('mkt-web-manter', '17 6 * * *', 'select mkt_web.manter()');                       -- 03:17 SP
  perform cron.schedule('mkt-web-agregar', '20 6 * * *',
    'select mkt_web.agregar(mkt_web.hoje() - 1); select mkt_web.agregar(mkt_web.hoje() - 2)');            -- 03:20 SP
  perform cron.schedule('mkt-web-ritmo', '*/10 * * * *', 'select mkt_web.vigiar_espaco()');
end
$cron$;

-- ─── 8. Conferência (aborta se algo nasceu aberto ou fora do padrão) ─────────────────────────────────────────────────
do $confere$
declare
  r text;
  t record;
  f record;
  v_publicas text[] := array['mkt_web_visao', 'mkt_web_paginas', 'mkt_web_funil', 'mkt_web_origem', 'mkt_web_velocidade',
                             'mkt_web_leitura', 'mkt_web_problemas', 'mkt_web_formulario', 'mkt_web_instalacao',
                             'mkt_web_coleta_ligar'];
  v_servico text[] := array['mkt_web_coletar', 'mkt_web_dominios'];
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_schema_privilege(r, 'mkt_web', 'usage') or has_schema_privilege(r, 'mkt_web', 'create') then
      raise exception '20261006f: % tem acesso ao schema mkt_web', r;
    end if;
  end loop;
  for t in select c.oid, c.relname, c.relrowsecurity from pg_class c
            where c.relnamespace = 'mkt_web'::regnamespace and c.relkind in ('r', 'p') loop
    if not t.relrowsecurity then raise exception '20261006f: RLS desligada em mkt_web.%', t.relname; end if;
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t.oid, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261006f: % tem privilégio em mkt_web.%', r, t.relname;
      end if;
    end loop;
  end loop;
  for f in select p.oid::regprocedure as sig, p.proname, p.pronamespace, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p
            where p.pronamespace = 'mkt_web'::regnamespace
               or (p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_web\_%') loop
    if not (f.proconfig @> array['search_path=""']) then raise exception '20261006f: % sem search_path vazio', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') then raise exception '20261006f: anon executa %', f.sig; end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261006f: PUBLIC executa %', f.sig;
    end if;
    if (f.pronamespace = 'public'::regnamespace and f.proname = any(v_publicas)) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261006f: grant de authenticated errado em %', f.sig;
    end if;
    if f.proname = any(v_servico) and not has_function_privilege('service_role', f.sig, 'execute') then
      raise exception '20261006f: service_role não executa %', f.sig;
    end if;
    if (f.proname = any(v_publicas) or f.proname = any(v_servico)) and not f.prosecdef then
      raise exception '20261006f: % deveria ser SECURITY DEFINER', f.sig;
    end if;
    if f.pronamespace = 'mkt_web'::regnamespace and f.prosecdef then
      raise exception '20261006f: interna % não deveria ser SECURITY DEFINER', f.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_web\_%') <> 12 then
    raise exception '20261006f: esperava 12 funções public.mkt_web_*';
  end if;
  if (select count(*) from pg_class c where c.relnamespace = 'mkt_web'::regnamespace and c.relkind = 'r') <> 14 then
    raise exception '20261006f: esperava 14 tabelas em mkt_web';
  end if;
end
$confere$;



-- ═══ TESTES ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 1. Criou
insert into pg_temp._z_out (passo, linha) values ('1.tabelas',
  (select count(*)::text from pg_class c where c.relnamespace = 'mkt_web'::regnamespace and c.relkind = 'r'));
insert into pg_temp._z_out (passo, linha) values ('1.funcoes_publicas',
  (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_web\_%'));
insert into pg_temp._z_out (passo, linha) select '1.contrato_pb26',
  'coleta=' || f.coleta || ' lead=' || array_to_string(f.eventos_lead, ',') || ' funis=' || jsonb_array_length(f.funis)
  from mkt_web.funis f join mkt.projetos p on p.id = f.projeto_id where p.sigla = 'PB26';
insert into pg_temp._z_out (passo, linha) select '1.cron', string_agg(j.jobname || ' ' || j.schedule, ' ; ' order by j.jobname)
  from cron.job j where j.jobname like 'mkt-web-%';

-- Projeto de TESTE (some no rollback): ZZWEB99 em exemplo.invalid, páginas /zz1/ (zz1) e /obrigado-zz/, coleta ligada
insert into mkt.projetos (sigla, nome, linha) values ('ZZWEB99', 'ZZ Ensaio Web', 'ZZ Ensaio');
insert into mkt.paginas (projeto_id, codigo, nome, dominio, caminho, funcao, funil)
select p.id, v.c, v.n, 'exemplo.invalid', v.cam, v.f, 'zz'
  from mkt.projetos p, (values ('zz1', 'ZZ1', '/zz1/', 'captura'), (null, 'Obrigado ZZ', '/obrigado-zz/', 'obrigado')) v(c, n, cam, f)
 where p.sigla = 'ZZWEB99';
insert into mkt_web.funis (projeto_id, coleta, eventos_lead, funis)
select p.id, true, '{lead_zz}',
       '[{"id":"zz","nome":"Funil ZZ","etapas":[{"nome":"Entrou na ZZ1","caminhos":["/zz1/"]},
          {"nome":"Abriu o formulário","eventos":["abriu_formulario"]},{"nome":"Lead","eventos":["lead_zz"]},
          {"nome":"Viu o obrigado","caminhos":["/obrigado-zz/"]}]}]'::jsonb
  from mkt.projetos p where p.sigla = 'ZZWEB99';
create temp table _z_ids on commit drop as
  select 'proj' k, id from mkt.projetos where sigla = 'ZZWEB99'
  union all select 'zz1', id from mkt.paginas where caminho = '/zz1/' and dominio = 'exemplo.invalid';
grant all on _z_ids to public;

-- monta um pacote (formato do gravador) como texto
create function pg_temp.pk(p_proj text, p_sid text, p_pv text, p_seq int, p_caminho text, p_disp text, p_teste int,
                           p_origem jsonb, p_pv_extra jsonb, p_eventos jsonb) returns text
language sql as $$
  select jsonb_build_object('v', 2, 'projeto', p_proj, 'seq', p_seq, 'final', 0,
    'sessao', jsonb_build_object('id', p_sid, 'visitante', 'vis' || p_sid, 'teste', p_teste, 'dispositivo', p_disp,
                                 'origem', coalesce(p_origem, '{}'::jsonb), 'info', '{"sis":"Android","nav":"Instagram","app":"instagram","estado":"São Paulo","cidade":"Campinas"}'::jsonb),
    'pv', jsonb_build_object('id', p_pv, 'caminho', p_caminho, 'titulo', 'ZZ', 'inicio', (extract(epoch from now()) * 1000)::bigint,
                             'largura', 390, 'altura_doc', 4000, 'rolagem', 10, 'visivel_ms', 0) || coalesce(p_pv_extra, '{}'::jsonb),
    'eventos', coalesce(p_eventos, '[]'::jsonb))::text
$$;
grant execute on function pg_temp.pk(text, text, text, int, text, text, int, jsonb, jsonb, jsonb) to public;

-- 2. Recusas e limites (como a rota do servidor chama: service_role)
set local role service_role;
insert into pg_temp._z_out (passo, linha) values
  ('2.dominio_fora', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessao0001', 'zzpv00000001', 0, '/zz1/', 'mobile', 0, null, null, null), 'https://evil.example', 'aaaaaaaaaaaaaaaa')),
  ('2.sem_origem', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessao0001', 'zzpv00000001', 0, '/zz1/', 'mobile', 0, null, null, null), null, 'aaaaaaaaaaaaaaaa')),
  ('2.projeto_desconhecido', public.mkt_web_coletar(pg_temp.pk('XX00', 'zzsessao0001', 'zzpv00000001', 0, '/zz1/', 'mobile', 0, null, null, null), 'https://exemplo.invalid', 'aaaaaaaaaaaaaaaa')),
  ('2.projeto_sem_coleta', public.mkt_web_coletar(pg_temp.pk('PB26', 'zzsessao0001', 'zzpv00000001', 0, '/ak1/', 'mobile', 0, null, null, null), 'https://patrimoniobrasil.com.br', 'aaaaaaaaaaaaaaaa')),
  ('2.payload_grande', public.mkt_web_coletar(repeat('x', 70000), 'https://exemplo.invalid', 'aaaaaaaaaaaaaaaa')),
  ('2.json_invalido', public.mkt_web_coletar('{nao e json', 'https://exemplo.invalid', 'aaaaaaaaaaaaaaaa')),
  ('2.identificador', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'curto', 'zzpv00000001', 0, '/zz1/', 'mobile', 0, null, null, null), 'https://exemplo.invalid', 'aaaaaaaaaaaaaaaa'));
reset role;
-- limites baixos só para o teste
update mkt_web.config set valor = '5' where chave = 'limite_ip_minuto';
update mkt_web.config set valor = '3' where chave = 'limite_sessao_minuto';
set local role service_role;
insert into pg_temp._z_out (passo, linha) select '2.limite_ip',
  string_agg(public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzipsessao0' || g, 'zzippv00000' || g, 0, '/zz1/', 'desktop', 1, null, null, null),
                                    'https://exemplo.invalid', 'bbbbbbbbbbbbbbbb'), ',' order by g)
  from generate_series(1, 6) g;
insert into pg_temp._z_out (passo, linha) select '2.limite_sessao',
  string_agg(public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaolimite', 'zzpvlimite01', g, '/zz1/', 'desktop', 1, null, null, null),
                                    'https://exemplo.invalid', 'cccccccccccc' || g || g || g || g), ',' order by g)
  from generate_series(1, 4) g;
reset role;
update mkt_web.config set valor = '600' where chave = 'limite_ip_minuto';
update mkt_web.config set valor = '60' where chave = 'limite_sessao_minuto';
update mkt_web.config set valor = 'pausada' where chave = 'coleta';
set local role service_role;
insert into pg_temp._z_out (passo, linha) values ('2.pausada',
  public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessao0009', 'zzpv00000009', 0, '/zz1/', 'mobile', 0, null, null, null), 'https://exemplo.invalid', 'dddddddddddddddd'));
reset role;
update mkt_web.config set valor = 'ligada' where chave = 'coleta';
delete from mkt_web.sessoes where id in ('zzsessaolimite') or id like 'zzipsessao%';   -- as de teste do limite saem da conta

-- 3. Caso pequeno, de ponta a ponta (hoje): A celular de anúncio que vira lead; B computador que sai rápido;
--    C visita de teste (fora da conta); E caminho não cadastrado
set local role service_role;
insert into pg_temp._z_out (passo, linha) values
  ('3.A_pv1', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoAAAA', 'zzpvAAAA0001', 0, '/zz1/index.html', 'mobile', 0,
     '{"utm_source":"ig","utm_medium":"paid","utm_campaign":"RS | ZZWEB99 | LEADS | TESTE | ZZ1","utm_content":"120200000000001","fbclid":1,"gclid":0,"referrer":"l.instagram.com"}',
     '{"rolagem":80,"visivel_ms":12000,"ativo_ms":9000,"vaivem":2,"r30":40,"vitais":{"lcp":2000,"inp":120,"cls":0.05,"fcp":900,"ttfb":300,"peso":800,"rede":"4g"},
       "secoes":{"topo":5,"oferta":7},"ctas":{"inscrever":1},"form":{"v":1,"t":30,"s":1,"u":"telefone","c":{"nome":[1,5,1,0],"email":[1,8,1,1],"telefone":[1,9,1,0]}},
       "mapa":{"s":["topo","oferta"],"c":["inscrever"],"f":["nome","email","telefone"]}}',
     '[{"t":"pagina","ts":0},{"t":"clique","ts":1000,"x":50.5,"y":900,"sel":"a[data-cta=\"inscrever\"]","txt":"Quero","raiva":0,"morto":0},
       {"t":"clique","ts":2000,"x":30,"y":1500,"sel":"img.foto","txt":"","raiva":1,"morto":1},
       {"t":"clique","ts":2500,"x":0,"y":0,"sel":"input#telefone","txt":"","raiva":0,"morto":0},
       {"t":"erro","ts":3000,"msg":"x is not defined","arq":"app.js?fbclid=abc","linha":10},
       {"t":"erro","ts":3100,"msg":"Script error.","arq":"","linha":0},
       {"t":"funil","ts":4000,"nome":"abriu_formulario"},{"t":"funil","ts":9000,"nome":"lead_zz","motivo":"ok","email":"nao@deve.ficar"}]'),
     'https://exemplo.invalid', 'eeeeeeeeeeeeeeee')),
  ('3.A_repetido', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoAAAA', 'zzpvAAAA0001', 0, '/zz1/', 'mobile', 0, null, null, null), 'https://exemplo.invalid', 'eeeeeeeeeeeeeeee')),
  ('3.A_pv2', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoAAAA', 'zzpvAAAA0002', 0, '/obrigado-zz/', 'mobile', 0, null,
     '{"rolagem":100,"visivel_ms":2000}', null), 'https://www.exemplo.invalid', 'eeeeeeeeeeeeeeee')),
  ('3.B', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoBBBB', 'zzpvBBBB0001', 0, '/zz1/', 'desktop', 0, null,
     '{"rolagem":20,"visivel_ms":1500}', null), 'https://exemplo.invalid', 'ffffffffffffffff')),
  ('3.C_teste', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoCCCC', 'zzpvCCCC0001', 0, '/zz1/', 'desktop', 1, null,
     '{"rolagem":100,"visivel_ms":60000}', '[{"t":"funil","ts":1,"nome":"lead_zz"}]'), 'https://exemplo.invalid', 'ffffffffffffffff')),
  ('3.E', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoEEEE', 'zzpvEEEE0001', 0, '/x/?a=1#b', 'desktop', 0, null,
     '{"rolagem":50,"visivel_ms":4000}', null), 'https://exemplo.invalid', 'ffffffffffffffff'));
reset role;
insert into pg_temp._z_out (passo, linha) select '3.sessao_A',
  'engajou=' || s.engajou_por || ' lead=' || s.lead || ' cliques=' || s.cliques || ' raiva=' || s.raiva || ' mortos=' || s.mortos
  || ' erros=' || s.erros || ' paginas=' || s.paginas || ' entrada=' || s.entrada_caminho || ' saida=' || s.saida_caminho
  || ' entrada_pagina_ok=' || (s.entrada_pagina_id = (select id from pg_temp._z_ids where k = 'zz1'))
  || ' utm_content=' || s.utm_content || ' fbclid=' || s.fbclid || ' app=' || s.app || ' cidade=' || s.cidade
  from mkt_web.sessoes s where s.id = 'zzsessaoAAAA';
insert into pg_temp._z_out (passo, linha) select '3.sessao_B', 'engajada=' || s.engajada || ' lead=' || s.lead from mkt_web.sessoes s where s.id = 'zzsessaoBBBB';
insert into pg_temp._z_out (passo, linha) select '3.evento_lead_dados', e.dados::text from mkt_web.eventos e where e.sessao = 'zzsessaoAAAA' and e.nome = 'lead_zz';
insert into pg_temp._z_out (passo, linha) select '3.erros', string_agg(e.origem || ':' || coalesce(e.tipo_fora, '-') || ':' || coalesce(e.arquivo, ''), ' ; ' order by e.id)
  from mkt_web.erros e where e.sessao = 'zzsessaoAAAA';
insert into pg_temp._z_out (passo, linha) select '3.cliques', string_agg('auto=' || c.automatico || ' raiva=' || c.raiva, ' ; ' order by c.id)
  from mkt_web.cliques c where c.sessao = 'zzsessaoAAAA';
insert into pg_temp._z_out (passo, linha) select '3.pv_A1',
  'caminho=' || w.caminho || ' pagina_ok=' || (w.pagina_id = (select id from pg_temp._z_ids where k = 'zz1')) || ' lcp=' || w.lcp_ms
  || ' cls=' || w.cls || ' r30=' || w.rolagem_30s || ' secoes=' || w.secoes::text || ' form_email=' || (w.form -> 'c' -> 'email')::text
  from mkt_web.visualizacoes w where w.id = 'zzpvAAAA0001';
insert into pg_temp._z_out (passo, linha) select '3.pv_E', 'caminho=' || w.caminho || ' pagina_id=' || coalesce(w.pagina_id::text, 'null')
  from mkt_web.visualizacoes w where w.id = 'zzpvEEEE0001';
insert into pg_temp._z_out (passo, linha) select '3.mapa', m.secoes::text || ' ' || m.ctas::text || ' ' || m.campos::text
  from mkt_web.paginas_mapa m where m.pagina_id = (select id from pg_temp._z_ids where k = 'zz1');

-- agregação: calcular_dia e agregar dão as mesmas linhas
insert into pg_temp._z_out (passo, linha)
select '3.resumo', r.caminho || ' ' || r.dispositivo || ': vis=' || r.visualizacoes || ' sess=' || r.sessoes || ' ent=' || r.entradas
       || ' eng=' || r.entradas_engajadas || ' lead_ent=' || r.entradas_lead || ' sess_lead=' || r.sessoes_lead
       || ' rapidas=' || r.saidas_rapidas || ' rol=' || r.rolagem_soma || ' rol75=' || r.rolagem_75 || ' lcp=' || coalesce(r.lcp_p75::text, '-')
       || ' cliques=' || r.cliques || ' raiva=' || r.raiva || ' mortos=' || r.mortos || ' erros=' || r.erros
  from mkt_web.calcular_dia(mkt_web.hoje(), (select id from pg_temp._z_ids where k = 'proj')) r
 order by r.caminho, r.dispositivo;
insert into pg_temp._z_out (passo, linha) values ('3.agregar', mkt_web.agregar(mkt_web.hoje())::text);
insert into pg_temp._z_out (passo, linha) select '3.agregar_igual',
  ((select count(*) from (select dia, projeto_id, dominio, caminho, dispositivo, pagina_id, visualizacoes, sessoes, visitantes, entradas,
          entradas_engajadas, entradas_lead, sessoes_lead, saidas_rapidas, rolagem_soma, rolagem_75, visivel_ms_soma, vitais_n, lcp_p75,
          inp_p75, cls_p75, cliques, raiva, mortos, erros from mkt_web.resumo_dia where projeto_id = (select id from pg_temp._z_ids where k = 'proj')
        except
        select dia, projeto_id, dominio, caminho, dispositivo, pagina_id, visualizacoes, sessoes, visitantes, entradas,
          entradas_engajadas, entradas_lead, sessoes_lead, saidas_rapidas, rolagem_soma, rolagem_75, visivel_ms_soma, vitais_n, lcp_p75,
          inp_p75, cls_p75, cliques, raiva, mortos, erros from mkt_web.calcular_dia(mkt_web.hoje(), (select id from pg_temp._z_ids where k = 'proj'))) d) = 0)::text;

-- 4. Leituras como o Victor (admin). O dia de hoje vai numa tabela temporária (authenticated não enxerga mkt_web)
create temp table _z_hoje on commit drop as select mkt_web.hoje() as d;
grant all on _z_hoje to public;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '4.visao_kpis', (x -> 'kpis')::text
  from public.mkt_web_visao((select id from pg_temp._z_ids where k = 'proj'), (select d from pg_temp._z_hoje) - 6, (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha) select '4.visao_serie_hoje', (select e::text from jsonb_array_elements(x -> 'serie') e where e ->> 'dia' = (select d from pg_temp._z_hoje)::text)
  from public.mkt_web_visao((select id from pg_temp._z_ids where k = 'proj'), (select d from pg_temp._z_hoje) - 6, (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha) select '4.funil',
  (select string_agg((e ->> 'nome') || '=' || (e ->> 'sessoes'), ' > ' order by (e ->> 'ordem')::int) from jsonb_array_elements(x -> 0 -> 'etapas') e)
  from public.mkt_web_funil((select id from pg_temp._z_ids where k = 'proj'), (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha) select '4.origem',
  'total=' || (x ->> 'total') || ' meta=' || (x ->> 'cliques_meta') || ' fontes=' || (x -> 'fontes')::text || ' campanha=' || (x -> 'campanhas' -> 0)::text
  from public.mkt_web_origem((select id from pg_temp._z_ids where k = 'proj'), (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha) select '4.velocidade',
  (select string_agg((e ->> 'caminho') || ' ' || (e ->> 'dispositivo') || ' lcp=' || coalesce(e ->> 'lcp_p75', '-'), ' ; ' order by e ->> 'caminho', e ->> 'dispositivo')
     from jsonb_array_elements(x -> 'paginas') e)
  from public.mkt_web_velocidade((select id from pg_temp._z_ids where k = 'proj'), (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha) select '4.leitura',
  'rolagem=' || (x -> 'rolagem')::text || ' secoes=' || (x -> 'secoes')::text || ' ctas=' || (x -> 'ctas')::text
  from public.mkt_web_leitura((select id from pg_temp._z_ids where k = 'proj'), (select id from pg_temp._z_ids where k = 'zz1'), (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha) select '4.problemas',
  'cliques=' || (x ->> 'cliques') || ' raiva=' || (x ->> 'raiva') || ' mortos=' || (x ->> 'mortos') || ' auto=' || (x ->> 'automaticos')
  || ' erros=' || (x ->> 'erros') || ' fora=' || (x -> 'erros_fora')::text
  from public.mkt_web_problemas((select id from pg_temp._z_ids where k = 'proj'), null, (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha) select '4.formulario',
  'medidas=' || (x ->> 'medidas') || ' comecaram=' || (x ->> 'comecaram') || ' enviaram=' || (x ->> 'enviaram') || ' campos=' || (x -> 'campos')::text
  from public.mkt_web_formulario((select id from pg_temp._z_ids where k = 'proj'), (select id from pg_temp._z_ids where k = 'zz1'), (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha) select '4.instalacao',
  (select (e ->> 'sigla') || ' coleta=' || (e ->> 'coleta') || ' dominios=' || (e -> 'dominios')::text from jsonb_array_elements(x -> 'projetos') e where e ->> 'sigla' = 'ZZWEB99')
  || ' recusas=' || (x -> 'recusas_7d')::text
  from public.mkt_web_instalacao() x;
insert into pg_temp._z_out (passo, linha) select '4.paginas',
  (select string_agg((e ->> 'caminho') || ' vis=' || (e ->> 'visualizacoes') || ' ent=' || (e ->> 'entradas') || ' rej=' || (e ->> 'rejeicoes')
                     || ' lead=' || (e ->> 'entradas_lead') || ' cod=' || coalesce(e ->> 'codigo', '-'), ' ; ' order by e ->> 'caminho')
     from jsonb_array_elements(x) e)
  from public.mkt_web_paginas((select id from pg_temp._z_ids where k = 'proj'), (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;
do $t$
begin
  begin
    perform public.mkt_web_visao(1, current_date, current_date + 200);
    insert into pg_temp._z_out (passo, linha) values ('4.periodo_longo', 'ACEITOU (ERRADO)');
  exception when invalid_parameter_value then
    insert into pg_temp._z_out (passo, linha) values ('4.periodo_longo', '22023 ok');
  end;
end
$t$;
insert into pg_temp._z_out (passo, linha) values ('4.coleta_desligar',
  public.mkt_web_coleta_ligar((select id from pg_temp._z_ids where k = 'proj'), false)::text);
reset role;
set local role service_role;
insert into pg_temp._z_out (passo, linha) values ('4.depois_de_desligar',
  public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoAAAA', 'zzpvAAAA0003', 0, '/zz1/', 'mobile', 0, null, null, null), 'https://exemplo.invalid', 'eeeeeeeeeeeeeeee'));
insert into pg_temp._z_out (passo, linha) values ('4.dominios_servico', public.mkt_web_dominios()::text);
reset role;

-- 5. Permissões
insert into pg_temp._z_out (passo, linha)
select '5.tabelas', 'anon/authenticated com privilégio em ' || count(*) filter (where has_table_privilege('anon', c.oid, 'select,insert,update,delete')
                     or has_table_privilege('authenticated', c.oid, 'select,insert,update,delete')) || ' de ' || count(*)
       || ' ; rls_desligada=' || count(*) filter (where not c.relrowsecurity)
  from pg_class c where c.relnamespace = 'mkt_web'::regnamespace and c.relkind = 'r';
insert into pg_temp._z_out (passo, linha)
select '5.schema', r || ' mkt_web=' || has_schema_privilege(r, 'mkt_web', 'usage') from unnest(array['anon', 'authenticated']) r;
insert into pg_temp._z_out (passo, linha)
select '5.funcoes', 'anon=' || count(*) filter (where has_function_privilege('anon', p.oid, 'execute'))
       || ' auth=' || string_agg(p.proname, ',' order by p.proname) filter (where has_function_privilege('authenticated', p.oid, 'execute'))
       || ' servico=' || string_agg(p.proname, ',' order by p.proname) filter (where p.proname in ('mkt_web_coletar', 'mkt_web_dominios')
                                                                                and has_function_privilege('service_role', p.oid, 'execute'))
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mkt\_web\_%';

-- 6. Quem não é admin/dev não lê; ninguém fora do servidor coleta
do $t$
declare
  c text;
  v_quem text;
  v_uid text;
  v_role text;
  v_chamadas text[] := array[
    'select public.mkt_web_visao(1, current_date, current_date)',
    'select public.mkt_web_paginas(1, current_date, current_date)',
    'select public.mkt_web_funil(1, current_date, current_date)',
    'select public.mkt_web_origem(1, current_date, current_date)',
    'select public.mkt_web_velocidade(1, current_date, current_date)',
    'select public.mkt_web_leitura(1, 1, current_date, current_date)',
    'select public.mkt_web_problemas(1, null, current_date, current_date)',
    'select public.mkt_web_formulario(1, 1, current_date, current_date)',
    'select public.mkt_web_instalacao()',
    'select public.mkt_web_coleta_ligar(1, true)',
    'select public.mkt_web_coletar(''{}'', ''https://exemplo.invalid'', null)',
    'select public.mkt_web_dominios()',
    'select 1 from mkt_web.sessoes limit 1'];
begin
  foreach v_quem in array array['sem_perfil', 'operador_mkt_web', 'visualizador', 'anon'] loop
    v_uid := case v_quem when 'sem_perfil' then '00000000-0000-4000-8000-0000000000ff'
                         when 'operador_mkt_web' then '11111111-1111-4111-8111-111111111111'
                         when 'visualizador' then '22222222-2222-4222-8222-222222222222'
                         else '00000000-0000-4000-8000-0000000000fe' end;
    v_role := case when v_quem = 'anon' then 'anon' else 'authenticated' end;
    perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"' || v_role || '"}', true);
    foreach c in array v_chamadas loop
      execute format('set local role %I', v_role);
      begin
        execute c;
        reset role;
        insert into pg_temp._z_out (passo, linha) values ('6.' || v_quem, 'PASSOU (ERRADO): ' || c);
      exception when insufficient_privilege then
        reset role;
        insert into pg_temp._z_out (passo, linha) values ('6.' || v_quem, '42501 ok: ' || split_part(split_part(c, '(', 1), ' ', 2));
      end;
    end loop;
  end loop;
end
$t$;

-- 6b. UTM no padrão do gp-operacoes (nome|id; o id é o que vem depois da última "|"). Linha "ok:" ou "ERRADO:".
insert into pg_temp._z_out (passo, linha)
select '6b.utm_separar', case when x.nome is not distinct from x.n_esp and x.id is not distinct from x.i_esp then 'ok: ' else 'ERRADO: ' end
       || x.caso || ' -> nome=' || coalesce(x.nome, '(nulo)') || ' id=' || coalesce(x.id, '(nulo)')
  from (select c.caso, c.n_esp, c.i_esp, u.nome, u.id
          from (values ('nome|id com " | " no nome', 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1|120211234', 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1', '120211234'),
                       ('anúncio nome|id com espaços', '  CRIATIVO 01 | 120200000000009 ', 'CRIATIVO 01', '120200000000009'),
                       ('só id (formato antigo, Google)', '120200000000001', null, '120200000000001'),
                       ('só nome com " | " (último campo não é número)', 'RS | ZZWEB99 | LEADS | TESTE | ZZ1', 'RS | ZZWEB99 | LEADS | TESTE | ZZ1', null),
                       ('só nome sem "|"', 'aula ao vivo', 'aula ao vivo', null),
                       ('vazio', '   ', null, null),
                       ('nulo', null, null, null)) c(caso, texto, n_esp, i_esp)
          cross join lateral mkt.utm_separar(c.texto) u) x;
insert into pg_temp._z_out (passo, linha)
select '6b.origem_ids', case when (o.campanha_id, o.conjunto_id, o.anuncio_id) is not distinct from (x.c, x.j, x.a) then 'ok: ' else 'ERRADO: ' end
       || x.caso || ' -> campanha=' || coalesce(o.campanha_id, '-') || ' conjunto=' || coalesce(o.conjunto_id, '-') || ' anuncio=' || coalesce(o.anuncio_id, '-')
  from (values ('Meta nome|id: conjunto do utm_medium', 'metaads', 'CONJ|120300000000001', 'C|120100000000001', 'A|120200000000001', null, null, null,
                '120100000000001', '120300000000001', '120200000000001'),
               ('utm_medium fora do Meta não vira conjunto', 'ig', 'paid|123', 'C|120100000000001', 'A|120200000000001', null, null, null,
                '120100000000001', null, '120200000000001'),
               ('parâmetro explícito vale primeiro', 'metaads', null, 'C|120100000000001', 'A|120200000000001', '999', '888', '777',
                '999', '888', '777'),
               ('Google só id', 'google', 'cpc', '22000000001', '700000000001', null, null, null, '22000000001', null, '700000000001'))
       x(caso, src, med, camp, cont, cid, sid, aid, c, j, a)
  cross join lateral mkt_web.origem_ids(x.src, x.med, x.camp, x.cont, x.cid, x.sid, x.aid) o;
-- gravação: Meta no padrão (nome|id) e Google (só id); a coleta do ZZWEB99 volta a ligar (o passo 4 desligou)
update mkt_web.funis set coleta = true where projeto_id = (select id from pg_temp._z_ids where k = 'proj');
set local role service_role;
insert into pg_temp._z_out (passo, linha) values
  ('6b.coleta_meta', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoUTM1', 'zzpvUTM00001', 0, '/zz1/', 'mobile', 0,
     '{"utm_source":"metaads","utm_medium":"CONJUNTO ZZ|120300000000077","utm_campaign":"RS | ZZWEB99 | LEADS | TESTE | ZZ1|120100000000077","utm_content":"CRIATIVO ZZ 01|120200000000077","utm_term":"instagram_stories","fbclid":1}',
     null, null), 'https://exemplo.invalid', 'ffffffffffffffff')),
  ('6b.coleta_google', public.mkt_web_coletar(pg_temp.pk('ZZWEB99', 'zzsessaoUTM2', 'zzpvUTM00002', 0, '/zz1/', 'desktop', 0,
     '{"utm_source":"google","utm_medium":"cpc","utm_campaign":"22000000077","utm_content":"700000000077","gclid":1}',
     null, null), 'https://exemplo.invalid', 'ffffffffffffffff'));
reset role;
insert into pg_temp._z_out (passo, linha)
select '6b.sessao_ids', case when string_agg(s.id || '=' || coalesce(s.campaign_id, '-') || '/' || coalesce(s.adset_id, '-') || '/' || coalesce(s.ad_id, '-'), ' ; ' order by s.id)
                                = 'zzsessaoUTM1=120100000000077/120300000000077/120200000000077 ; zzsessaoUTM2=22000000077/-/700000000077'
                              then 'ok: ' else 'ERRADO: ' end
       || string_agg(s.id || '=' || coalesce(s.campaign_id, '-') || '/' || coalesce(s.adset_id, '-') || '/' || coalesce(s.ad_id, '-'), ' ; ' order by s.id)
       || ' (utm_campaign guardado inteiro: ' || max(s.utm_campaign) filter (where s.id = 'zzsessaoUTM1') || ')'
  from mkt_web.sessoes s where s.id in ('zzsessaoUTM1', 'zzsessaoUTM2');
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha)
select '6b.origem_campanhas',
       case when (select count(*) from jsonb_array_elements(x -> 'campanhas') e
                   where e ->> 'campanha_id' = '120100000000077' and e ->> 'campanha' = 'RS | ZZWEB99 | LEADS | TESTE | ZZ1'
                     and e ->> 'padrao' = 'true' and e ->> 'pagina' = 'zz1') = 1
             and (select count(*) from jsonb_array_elements(x -> 'campanhas') e
                   where e ->> 'campanha_id' = '22000000077' and e ->> 'campanha' = '22000000077' and e -> 'padrao' = 'null'::jsonb) = 1
             and (select count(*) from jsonb_array_elements(x -> 'campanhas') e
                   where e -> 'campanha_id' = 'null'::jsonb and e ->> 'campanha' = 'RS | ZZWEB99 | LEADS | TESTE | ZZ1') = 1
            then 'ok: ' else 'ERRADO: ' end
       || 'Meta nome|id traduzido só pelo NOME (padrão, página zz1) e agrupado pelo id; Google só id (padrao nulo); formato antigo (só nome) à parte: '
       || (x -> 'campanhas')::text
  from public.mkt_web_origem((select id from pg_temp._z_ids where k = 'proj'), (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;
insert into pg_temp._z_out (passo, linha)
select '6b.origem_anuncios',
       case when (select count(*) from jsonb_array_elements(x -> 'anuncios') e
                   where e ->> 'anuncio_id' = '120200000000077' and e ->> 'anuncio' = 'CRIATIVO ZZ 01'
                     and e ->> 'campanha' = 'RS | ZZWEB99 | LEADS | TESTE | ZZ1') = 1
             and (select count(*) from jsonb_array_elements(x -> 'anuncios') e
                   where e ->> 'anuncio_id' = '120200000000001' and e ->> 'anuncio' = '120200000000001') = 1
             and (select count(*) from jsonb_array_elements(x -> 'anuncios') e where e ->> 'anuncio_id' = '700000000077') = 1
            then 'ok: ' else 'ERRADO: ' end
       || 'anúncio pelo id com o nome do criativo; só id (formato antigo e Google) mostra o id: ' || (x -> 'anuncios')::text
  from public.mkt_web_origem((select id from pg_temp._z_ids where k = 'proj'), (select d from pg_temp._z_hoje), (select d from pg_temp._z_hoje)) x;

-- 7. Retenção e espaço
insert into mkt_web.sessoes (id, projeto_id, visitante, dia, inicio, fim, dispositivo, entrada_caminho, saida_caminho)
select 'zzsessaoVELHA', id, 'zzvisitante1', mkt_web.hoje() - 400, now() - interval '400 days', now() - interval '400 days', 'mobile', '/zz1/', '/zz1/'
  from pg_temp._z_ids where k = 'proj';
insert into mkt_web.ritmo (chave, minuto, n) values ('ip:velho', now() - interval '2 hours', 1);
insert into pg_temp._z_out (passo, linha) values ('7.manter', (mkt_web.manter() ->> 'sessoes'));
insert into pg_temp._z_out (passo, linha) values ('7.sessao_velha', (select count(*)::text from mkt_web.sessoes where id = 'zzsessaoVELHA'));
insert into pg_temp._z_out (passo, linha) values ('7.espaco_ok', mkt_web.vigiar_espaco());
insert into pg_temp._z_out (passo, linha) values ('7.ritmo_velho', (select count(*)::text from mkt_web.ritmo where chave = 'ip:velho'));
update mkt_web.config set valor = '0' where chave = 'limite_mb';
insert into pg_temp._z_out (passo, linha) values ('7.espaco_teto', mkt_web.vigiar_espaco());
insert into pg_temp._z_out (passo, linha) values ('7.coleta_depois_do_teto', (select valor from mkt_web.config where chave = 'coleta'));
insert into pg_temp._z_out (passo, linha) values ('7.falha_registrada', (select count(*)::text from mkt_web.falhas where onde = 'espaco'));

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
