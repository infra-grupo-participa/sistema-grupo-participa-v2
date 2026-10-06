-- 20261006f: CRM Comercial — link de checkout de public.crm_ofertas com o link REAL da Hotmart
--
-- STATUS: APLICADA em 06/10/2026, versão 20261006103738 (crm_link_checkout), com ok do Arthur. Statement gravado = corpo executável deste arquivo (cabeçalho de comentário resumido). Ensaio: 20261006f_ensaio.sql (begin … rollback). Notas: 20261006f.explain.md.
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
