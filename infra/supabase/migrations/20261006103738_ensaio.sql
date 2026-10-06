-- 20261006f: ENSAIO (não aplica nada: termina em ROLLBACK). Rodar inteiro, como postgres, numa chamada só.
-- Parte A: corpo INTEIRO da migration (copiado sem mudança de 20261006f_crm_link_checkout.sql) + provas.
-- Parte C (fim do arquivo, chamada separada): confere que nada persistiu.
-- Perfis reais escolhidos por SELECT (gestor = admin ativo mais antigo; vis = ativo fora do comercial): só ids em temp.
-- Ofertas reais: as 3 de maior volume entre os produtos com código de checkout conhecido; só a FORMA do link sai.
-- Esperado: nenhuma linha começando com "ERRADO".
--
-- ═══ PARTE A ═════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, ''));
$$;
-- forma do link sem expor código: letras viram a/A, dígitos 9
create function pg_temp.forma(p text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(regexp_replace(p, '[A-Z]', 'A', 'g'), '[a-z]', 'a', 'g'), '[0-9]', '9', 'g') $$;

-- link antigo, ANTES da migration (como o banco está hoje), para comparar
create temp table _antes on commit drop as
select o.oferta_codigo, 'https://pay.hotmart.com/' || o.produto_id || '?off=' || o.oferta_codigo link_antigo
  from fin.ofertas o;

-- ═══ CORPO DA MIGRATION (copiado sem mudança) ═══
-- 20261006f: CRM Comercial — link de checkout de public.crm_ofertas com o link REAL da Hotmart
--
-- STATUS: NÃO APLICADA — aguardando ok do Arthur. Ensaio: 20261006f_ensaio.sql (begin … rollback). Notas: 20261006f.explain.md.
--
-- O ERRO (F1, 20261005s): crm_ofertas montava 'linkCheckout' = 'https://pay.hotmart.com/' || produto_id || '?off=' || código,
--   com o id NUMÉRICO do produto (ex.: /3094405?off=…). Esse caminho não é o código de checkout do produto na Hotmart
--   (o de checkout tem a forma letra+dígitos+letra, ex.: P84471811S, e só é conhecido para 3 de 57 produtos em
--   cs.hm_produto_checkout_de_para). O UUID fin.hotmart_catalogo.ucode também NÃO é o caminho do checkout.
-- A CORREÇÃO: mesma regra da F5 (public.crm_criar_link, versão 20261006044653): o link que a própria Hotmart devolve
--   para a oferta, fin.ofertas.bruto_json->>'direct_offer_link_for_creator' (1.143/1.143 ofertas, forma
--   'https://pay.hotmart.com?off=<código>'), com fallback idêntico ao da F5 se um dia vier vazio.
--   Uma regra só para os dois lugares: o link da tela de Produtos e o link rastreável saem iguais.
--
-- O QUE MUDA: só a linha 'linkCheckout' de public.crm_ofertas(text, text). Mesma assinatura (create or replace mantém o
--   ACL), mesmo resto do corpo, recriado a partir do corpo VIVO (pg_get_functiondef de 06/10/2026, md5 abaixo).
-- O QUE NÃO MUDA:
--   public.crm_buscar_por_link: não monta link (extrai off= de qualquer forma de link e chama crm_ofertas) → herda o link
--     certo sem ser recriada.
--   public.crm_produtos_hotmart: não monta link nenhum.
--   Front (web/modules/comercial): domain/hotmart.ts linkCheckout() tem o MESMO erro, mas só é usado pelo mock
--     (infrastructure/mock-catalogo.ts); a tela real lê 'linkCheckout' do banco. Exemplo de ajuda em
--     ui/produtos/ModalColarLink.tsx e teste ui/produtos/produtos.test.ts usam a forma antiga. Não editados aqui.
--
-- GUARDA: aborta se o corpo vivo de crm_ofertas não for o lido em 06/10 (md5 do pg_get_functiondef) ou se crm_criar_link
--   não usar mais direct_offer_link_for_creator (as duas regras precisam continuar iguais).
-- REVERSÃO: recriar crm_ofertas com a linha antiga (corpo em 20261005s_crm_f1_leitura.sql, seção das ofertas).

do $guarda$
begin
  if md5(pg_get_functiondef('public.crm_ofertas(text,text)'::regprocedure)) <> 'ef005ec99c91f3c9c63c2975a337cb44' then
    raise exception '20261006f: corpo vivo de public.crm_ofertas mudou desde 06/10 (md5 diferente) — reler e regerar';
  end if;
  if position('direct_offer_link_for_creator' in
              pg_get_functiondef('public.crm_criar_link(uuid,text,text,text,text,text,text)'::regprocedure)) = 0 then
    raise exception '20261006f: crm_criar_link (F5) não usa mais direct_offer_link_for_creator — alinhar a regra antes';
  end if;
end
$guarda$;

CREATE OR REPLACE FUNCTION public.crm_ofertas(p_produto text DEFAULT NULL::text, p_codigo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  perform crm.exige_comercial();
  with o as (
    select o.* from fin.ofertas o
     where (p_produto is null or o.produto_id = p_produto) and (p_codigo is null or o.oferta_codigo = p_codigo)
  ), t as (
    select h.oferta_codigo, count(*) n,
           max(coalesce(h.aprovado_em, h.pedido_em)) filter (where h.status in ('APPROVED', 'COMPLETE')) ultima
      from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
     where h.oferta_codigo in (select o.oferta_codigo from o)
     group by h.oferta_codigo
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', o.oferta_codigo, 'produtoId', o.produto_id, 'nomeHotmart', o.nome, 'preco', o.preco,
           'moeda', coalesce(o.moeda, 'BRL'), 'modo', coalesce(o.modo, ''), 'principal', coalesce(o.is_main_offer, false),
           'linkCheckout', coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo),
           'vigente', coalesce(oc.vigente, false), 'condicao', oc.condicao, 'validaAte', oc.valida_ate, 'uso', oc.uso,
           'transacoes', coalesce(t.n, 0), 'ultimaVendaEm', t.ultima, 'vistaEm', o.visto_em)
           order by coalesce(oc.vigente, false) desc, coalesce(t.n, 0) desc, o.oferta_codigo), '[]'::jsonb)
    into v
    from o
    left join crm.oferta_comercial oc on oc.oferta_codigo = o.oferta_codigo
    left join t on t.oferta_codigo = o.oferta_codigo;
  return v;
end
$function$;

-- Grants: os mesmos da F1 (authenticated executa; public/anon não). create or replace já preserva; reafirmado.
revoke all on function public.crm_ofertas(text, text) from public, anon, authenticated;
grant execute on function public.crm_ofertas(text, text) to authenticated;

do $confere$
declare v_def text := pg_get_functiondef('public.crm_ofertas(text,text)'::regprocedure);
begin
  if has_function_privilege('anon', 'public.crm_ofertas(text,text)'::regprocedure, 'execute') then
    raise exception '20261006f: crm_ofertas executável por anon';
  end if;
  if not has_function_privilege('authenticated', 'public.crm_ofertas(text,text)'::regprocedure, 'execute') then
    raise exception '20261006f: crm_ofertas sem execute para authenticated';
  end if;
  if position('direct_offer_link_for_creator' in v_def) = 0 or position('|| o.produto_id ||' in v_def) > 0 then
    raise exception '20261006f: corpo novo de crm_ofertas não ficou com a regra da F5';
  end if;
end
$confere$;

-- ═══ FIM DO CORPO ═══

-- ─── Fixtures ───
create temp table _v (k text primary key, u uuid) on commit drop;
insert into _v select 'gestor', p.id from public.perfis p where p.cargo = 'admin' and p.status = 'ativo' order by p.criado_em limit 1;
insert into _v select 'vis', p.id from public.perfis p
 where p.status = 'ativo' and p.cargo not in ('dev', 'admin', 'gestor')
   and not exists (select 1 from crm.vendedor v where v.perfil_id = p.id)
   and not coalesce('comercial' = any(p.areas), false) order by p.criado_em limit 1;
create function pg_temp.chamar(p_perfil uuid, p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;
create temp table _of on commit drop as
select x.oferta_codigo, x.produto_id, x.produto_checkout from (
  select o.oferta_codigo, o.produto_id, d.produto_checkout,
         row_number() over (partition by o.produto_id order by (select count(*) from fin.hotmart_transacoes h where h.oferta_codigo = o.oferta_codigo) desc, o.oferta_codigo) rn
    from fin.ofertas o join cs.hm_produto_checkout_de_para d on d.product_id = o.produto_id and d.provado) x
 where x.rn = 1;

select pg_temp.ok('0.fixtures', (select count(*) from _v) = 2 and (select count(*) from _of) = 3,
  format('perfis=%s ofertas=%s', (select count(*) from _v), (select count(*) from _of)));

-- ─── 1. Três ofertas reais, chamadas como a tela (authenticated + JWT do gestor) ───
do $p1$
declare r record; v jsonb; v_link text; v_esp text; v_ant text; i int := 0;
begin
  for r in select * from _of order by produto_id loop
    i := i + 1;
    v := pg_temp.chamar((select u from _v where k = 'gestor'), format('select public.crm_ofertas(null, %L)', r.oferta_codigo)) -> 0;
    v_link := v ->> 'linkCheckout';
    select coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo)
      into v_esp from fin.ofertas o where o.oferta_codigo = r.oferta_codigo;
    select link_antigo into v_ant from _antes where oferta_codigo = r.oferta_codigo;
    perform pg_temp.ok('1.oferta_' || i,
      v_link = v_esp and v_link like '%off=' || r.oferta_codigo and position('/' || r.produto_id in v_link) = 0,
      format('antes %s → agora %s (checkout do produto conhecido: %s)', pg_temp.forma(v_ant), pg_temp.forma(v_link), pg_temp.forma(r.produto_checkout)));
  end loop;
end $p1$;

-- ─── 2. Catálogo inteiro: nenhum link com id numérico, todos iguais à regra da F5 ───
do $p2$
declare v jsonb; t0 timestamptz; ms1 numeric; ms2 numeric;
begin
  t0 := clock_timestamp();
  v := pg_temp.chamar((select u from _v where k = 'gestor'), 'select public.crm_ofertas()');
  ms1 := extract(epoch from clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp();
  v := pg_temp.chamar((select u from _v where k = 'gestor'), 'select public.crm_ofertas()');
  ms2 := extract(epoch from clock_timestamp() - t0) * 1000;
  perform pg_temp.ok('2.catalogo',
    jsonb_array_length(v) = (select count(*) from fin.ofertas)
    and not exists (select 1 from jsonb_array_elements(v) e
                     where position('/' || (e ->> 'produtoId') || '?' in e ->> 'linkCheckout') > 0
                        or e ->> 'linkCheckout' is distinct from (select coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo)
                                                                    from fin.ofertas o where o.oferta_codigo = e ->> 'codigo')),
    format('%s ofertas; formas: %s; crm_ofertas() inteira %s ms / %s ms (2×)', jsonb_array_length(v),
           (select string_agg(distinct regexp_replace(e ->> 'linkCheckout', 'off=.*$', 'off=<código>'), ', ') from jsonb_array_elements(v) e),
           round(ms1, 1), round(ms2, 1)));
end $p2$;

-- ─── 3. crm_buscar_por_link: colar link antigo, link novo ou só o código → mesma oferta, link novo ───
do $p3$
declare r record; a jsonb; b jsonb; c jsonb; v_esp text;
begin
  select * into r from _of order by produto_id limit 1;
  select coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo)
    into v_esp from fin.ofertas o where o.oferta_codigo = r.oferta_codigo;
  a := pg_temp.chamar((select u from _v where k = 'gestor'), format('select public.crm_buscar_por_link(%L)', 'https://pay.hotmart.com/' || r.produto_id || '?off=' || r.oferta_codigo));
  b := pg_temp.chamar((select u from _v where k = 'gestor'), format('select public.crm_buscar_por_link(%L)', 'https://pay.hotmart.com/' || r.produto_checkout || '?off=' || r.oferta_codigo || '&sck=x'));
  c := pg_temp.chamar((select u from _v where k = 'gestor'), format('select public.crm_buscar_por_link(%L)', r.oferta_codigo));
  perform pg_temp.ok('3.buscar_por_link',
    a #>> '{oferta,linkCheckout}' = v_esp and b #>> '{oferta,linkCheckout}' = v_esp and c #>> '{oferta,linkCheckout}' = v_esp
    and a #>> '{produto,produtoId}' = r.produto_id and b #>> '{produto,produtoId}' = r.produto_id,
    'link /<id>?off=, link /<checkout>?off=&sck= e só o código → mesma oferta e produto, linkCheckout novo');
end $p3$;

-- ─── 4. Mesma regra da F5: base do link rastreável (crm_criar_link) = linkCheckout ───
select pg_temp.ok('4.regra_f5',
  position($r$coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo)$r$
           in pg_get_functiondef('public.crm_criar_link(uuid,text,text,text,text,text,text)'::regprocedure)) > 0
  and position($r$coalesce(nullif(o.bruto_json ->> 'direct_offer_link_for_creator', ''), 'https://pay.hotmart.com?off=' || o.oferta_codigo)$r$
           in pg_get_functiondef('public.crm_ofertas(text,text)'::regprocedure)) > 0,
  'expressão idêntica nos dois corpos');

-- ─── 5. Permissões: authenticated sim, anon não; guarda de comercial continua ───
select pg_temp.ok('5.grants',
  has_function_privilege('authenticated', 'public.crm_ofertas(text,text)'::regprocedure, 'execute')
  and not has_function_privilege('anon', 'public.crm_ofertas(text,text)'::regprocedure, 'execute')
  and not has_function_privilege('public', 'public.crm_ofertas(text,text)'::regprocedure, 'execute'),
  (select p.proacl::text from pg_proc p where p.oid = 'public.crm_ofertas(text,text)'::regprocedure));
do $p5$
declare v jsonb;
begin
  v := pg_temp.chamar((select u from _v where k = 'vis'), 'select public.crm_ofertas()');
  perform pg_temp.ok('5.visualizador_barrado', v ->> 'estado' = '42501', coalesce(v ->> 'erro', 'NÃO deu erro'));
  begin
    execute 'set local role anon';
    perform public.crm_ofertas();
    execute 'reset role';
    perform pg_temp.ok('5.anon_barrado', false, 'anon executou');
  exception when insufficient_privilege then
    execute 'reset role';
    perform pg_temp.ok('5.anon_barrado', true, sqlerrm);
  end;
end $p5$;

select linha from _z_out order by n;
rollback;

-- ═══ PARTE C (chamada separada): nada persistiu ═══════════════════════════════════════════════════════════════════
-- select md5(pg_get_functiondef('public.crm_ofertas(text,text)'::regprocedure)) = 'ef005ec99c91f3c9c63c2975a337cb44' corpo_igual_ao_de_antes,
--        position('direct_offer_link_for_creator' in pg_get_functiondef('public.crm_ofertas(text,text)'::regprocedure)) = 0 ainda_regra_antiga,
--        (select p.proacl::text from pg_proc p where p.oid = 'public.crm_ofertas(text,text)'::regprocedure) acl,
--        (select count(*) from supabase_migrations.schema_migrations where name ilike '%link_checkout%') migrations_gravadas;
