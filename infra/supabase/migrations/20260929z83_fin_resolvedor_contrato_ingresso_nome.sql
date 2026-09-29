-- 20260929z83 — Resolvedor oferta→evento: corrige o sinal "janela" reprovado na simulação da z82
--
-- Por quê (simulação do orquestrador, 29/09, nada gravado):
--   C1 (verdade conhecida): 3 auto:janela, 3 ERRO GRAVE.
--     * 3kojl3fv (2º Encontro, ev 96, janela só 28/09) -> 89 (HT32 26–30/09): única venda paga em 29/09.
--     * m4yuvi0a, tn2jua0u (Clínica Rio 14/07/2025, ev 41) -> 40: INGRESSOS de pré-venda (16/06–07/07); a janela
--       [carrinho-2, venda_ate] pegou o evento anterior. A trajetória já resolve ingresso pelo PRÓXIMO evento da
--       categoria (ing_de = venda_ate do anterior + 1) e o resolvedor não usava.
--   S2 (120 d): ~17 das 27 auto:janela eram ofertas INDIVIDUAIS de saldo/migração/renovação de contrato ("Saldo HM
--     Programa…", "Migração Implementação Holding Masters…", "Holding Masters - Saldo 6.000 Renovação…"): pertencem ao
--     contrato da pessoa, nunca a um evento pela data do pagamento.
-- Regras novas (ordem de decisão):
--   1. contrato  : nome da oferta (fin.ofertas, normalizado sem acento) tem a palavra saldo | migracao | renovacao
--                  -> 'contrato' (não liga, não vai à fila). Exceção: se o nome casa código/nome inteiro de UM
--                  evento (ex.: "Encontro do Time Holding Brasil/2026 SP - Migração Plateia") -> 'fila' com sugestão
--                  (humano decide; nunca liga sozinho). NÃO usa hm_product_catalog.categoria = 'diferenca' (as 3
--                  ofertas do 2º Encontro são 'diferenca' e são de evento).
--   2. perene    : main offer, ou vendas espalhadas > 60 dias, ou 2 janelas disjuntas (esta última não vale para
--                  ingresso: a janela de ingresso já particiona o tempo; dividir vira fila).
--   3. auto:sck  : igual à z82.
--   4. auto:nome : (a) código/nome inteiro de UM evento com a 1ª venda na janela (igual à z82, agora sem acento);
--                  (b) NOVO: palavras-chave distintivas (cidade, clinica, encontro, acelera, ethb, htNN, imersao,
--                  ano 20NN…) entre nome da oferta e nome+código do evento, evento a <= 60 dias da 1ª venda;
--                  liga só com >= 2 palavras em comum e margem >= 1 sobre o 2º colocado.
--   5. ingresso  : produto com papel 'ingresso' na categoria (fin.evento_produtos): janela de cada evento da
--                  categoria = [venda_ate do anterior + 1, venda_ate] (mesma expressão da fn_fin_trajetoria);
--                  liga ('auto:janela', detalhe.regra = 'ingresso') ao evento com >= 90% das vendas, se as
--                  palavras-chave não apontarem outro evento; dividido -> fila.
--   6. janela    : só produto que NÃO é ingresso; exige >= 3 vendas PAGAS, 1 evento, >= 90% das vendas e nome
--                  que não contradiz (melhor evento por palavra-chave, se único, tem que ser o mesmo). Senão fila.
--   7. fila (>= 2 vendas) / ignorar (1 venda) como na z82; sinal da fila diz o motivo.
-- Sugestão da fila: evento do nome > melhor palavra-chave > ingresso > janela única > sck > janela mais curta.
--
-- Objetos: 2 funções auxiliares novas (IMMUTABLE, sem acesso a tabela) + create or replace do resolvedor com a
-- MESMA assinatura e o MESMO retorno da z82 (sem sobrecarga). Nada é gravado por esta migration.
--
-- Guardas (antes de gravar): resolvedor vivo = z82 (assinatura, retorno, marcador no corpo) ou já z83; tabela da
-- fila e CHECK de origem da z82 vivos; nenhuma sobrecarga das auxiliares; fin.ofertas com nome/is_main_offer.
--
-- Escala: igual à z82 (1 Seq Scan de fin.hotmart_transacoes por execução diária, hash join com as candidatas).
-- Novo custo: normalizar ~150 nomes de evento + dezenas de nomes de oferta por execução, e o produto
-- ofertas × eventos (dezenas × ~150) para as palavras-chave — microssegundos por par, sem tabela nova.
--
-- 5 perguntas: 1) custo por oferta candidata, não por base (a base é lida 1x/dia no job); 2) mesmos índices da z82
-- (pedido_em; evento_ofertas_oferta_uq; PK da fila); nenhuma expressão funcional em coluna indexada;
-- 3) 1x/dia quando agendado (ainda sem cron); 4) tela não muda; 5) reversão abaixo.
--
-- Reversão (numa transação):
--   1. create or replace do resolvedor com o corpo da z82 (arquivo 20260929z82, seção 3) + os mesmos revoke/grant.
--   2. drop function if exists fin.oferta_palavras(text); drop function if exists fin.oferta_normaliza(text);
--      (só depois do passo 1: o corpo da z83 chama as duas.)
--   Nada a desfazer em dado: a z83 não grava.

-- ─── 0. Guardas ─────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v    text;
  v_fn record;
begin
  select p.prosrc, pg_get_function_result(p.oid) res into v_fn
    from pg_proc p where p.oid = to_regprocedure('fin.resolver_ofertas_eventos(boolean,integer,text[])');
  if v_fn.prosrc is null then
    raise exception 'z83: fin.resolver_ofertas_eventos(boolean,integer,text[]) não existe (z82 não aplicada?)';
  end if;
  if v_fn.res <> 'TABLE(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)' then
    raise exception 'z83: retorno vivo do resolvedor mudou: %', v_fn.res;
  end if;
  if position('fila:sinal_fraco' in v_fn.prosrc) = 0 and position('z83:' in v_fn.prosrc) = 0 then
    raise exception 'z83: corpo vivo do resolvedor não é o da z82 nem o da z83';
  end if;

  if to_regclass('fin.oferta_evento_fila') is null
     or not exists (select 1 from pg_constraint c where c.conrelid = 'fin.evento_ofertas'::regclass
                     and c.conname = 'evento_ofertas_origem_ck'
                     and pg_get_constraintdef(c.oid) like '%auto:janela%' and pg_get_constraintdef(c.oid) like '%auto:nome%') then
    raise exception 'z83: fila ou CHECK de origem da z82 ausentes';
  end if;

  select string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')', ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'fin' and p.proname in ('oferta_normaliza','oferta_palavras')
     and oidvectortypes(p.proargtypes) <> 'text';
  if v is not null then
    raise exception 'z83: auxiliar com outra assinatura já existe: %', v;
  end if;

  if to_regclass('fin.ofertas') is not null then
    select string_agg(c.col, ', ') into v
      from (values ('oferta_codigo'), ('nome'), ('is_main_offer')) c(col)
     where not exists (select 1 from information_schema.columns i
                        where i.table_schema = 'fin' and i.table_name = 'ofertas' and i.column_name = c.col);
    if v is not null then
      raise exception 'z83: fin.ofertas sem as colunas: %', v;
    end if;
  end if;
end $guarda$;


-- ─── 1. Auxiliares (puras) ──────────────────────────────────────────────────────────────────
-- Normaliza nome de oferta/evento: sem acento, minúsculo, só [a-z0-9] separados por 1 espaço, sinônimos de
-- cidade/evento unificados (São Paulo = sp, Porto Alegre = poa, Rio de Janeiro = rio, Belo Horizonte = bh,
-- Time Holding Brasil = ethb, Curso Nacional de Formação em Holding Familiar = cnhf).
create or replace function fin.oferta_normaliza(p text)
returns text
language sql immutable parallel safe set search_path = ''
as $$
  select btrim(
    replace(replace(replace(replace(replace(replace(
      ' ' || btrim(regexp_replace(lower(translate(coalesce(p, ''),
               'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüçºª',
               'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuucoa')), '[^a-z0-9]+', ' ', 'g')) || ' ',
      ' sao paulo ', ' sp '), ' porto alegre ', ' poa '), ' rio de janeiro ', ' rio '),
      ' belo horizonte ', ' bh '), ' time holding brasil ', ' ethb '),
      ' curso nacional de formacao em holding familiar ', ' cnhf '))
$$;
revoke all on function fin.oferta_normaliza(text) from public, anon, authenticated;

-- Palavras distintivas (tipo de evento, cidade, código HTNN, ano 20NN). "holding", "familiar", "total" etc. NÃO
-- entram: aparecem em quase todo nome e não distinguem evento.
create or replace function fin.oferta_palavras(p text)
returns text[]
language sql immutable parallel safe set search_path = ''
as $$
  select coalesce(array_agg(distinct w.w order by w.w), '{}'::text[])
    from regexp_split_to_table(fin.oferta_normaliza(p), ' ') w(w)
   where w.w in ('clinica','encontro','acelera','ethb','imersao','jornada','congresso','residencia','workshop',
                 'seminario','diamantes','cnhf','live',
                 'sp','rio','poa','bh','goiania','brasilia','curitiba','recife','salvador','fortaleza','florianopolis',
                 'floripa','campinas','manaus','belem','natal','vitoria','cuiaba','uberlandia','londrina','maceio',
                 'teresina','aracaju','joinville','santos','ribeirao','sorocaba','gramado','balneario','lisboa','orlando')
      or w.w ~ '^ht[0-9]{1,3}$'
      or w.w ~ '^20[0-9]{2}$'
$$;
revoke all on function fin.oferta_palavras(text) from public, anon, authenticated;


-- ─── 2. Resolvedor (mesma assinatura e retorno da z82) ──────────────────────────────────────
create or replace function fin.resolver_ofertas_eventos(
  p_gravar  boolean default false,
  p_dias    integer default 45,
  p_ofertas text[]  default null)
returns table (oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
language plpgsql volatile security definer set search_path = ''
as $$
#variable_conflict use_column
-- z83: contrato (saldo/migração/renovação), ingresso pelo próximo evento da categoria, palavras-chave no nome,
--      janela só com >= 3 vendas pagas e nome que não contradiz.
declare
  v_desde timestamptz := now() - make_interval(days => greatest(coalesce(p_dias, 45), 1));
  v_cod   text[];
  v_of    jsonb := '{}'::jsonb;
  v_tem_ofertas boolean := to_regclass('fin.ofertas') is not null;
  v_res   jsonb;
begin
  if p_ofertas is not null and coalesce(p_gravar, false) then
    raise exception 'p_ofertas é só para conferência: use p_gravar = false.' using errcode = '22023';
  end if;

  -- 1. candidatas
  if p_ofertas is not null then
    select coalesce(array_agg(distinct c.oc), '{}') into v_cod
      from unnest(p_ofertas) c(oc) where c.oc is not null;
  else
    select coalesce(array_agg(distinct t.oferta_codigo), '{}') into v_cod
      from fin.hotmart_transacoes t
     where t.pedido_em >= v_desde
       and t.oferta_codigo is not null
       and t.status in ('APPROVED','COMPLETE','PRINTED_BILLET','WAITING_PAYMENT','UNDER_ANALISYS','STARTED')
       and coalesce(t.recorrencia, 1) <= 1
       and not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
       and not exists (select 1 from fin.oferta_evento_fila f
                        where f.oferta_codigo = t.oferta_codigo and f.status in ('confirmada','rejeitada'));
  end if;
  if cardinality(v_cod) = 0 then
    return;
  end if;

  -- 2. nome/main offer (fin.ofertas pode não existir: SQL dinâmico)
  if v_tem_ofertas then
    execute 'select coalesce(jsonb_object_agg(o.oferta_codigo, jsonb_build_object(''nome'', o.nome, ''main'', o.is_main_offer)), ''{}''::jsonb)
               from fin.ofertas o where o.oferta_codigo = any($1)'
       into v_of using v_cod;
  end if;

  -- 3. decisão
  with tx as (
    select t.transacao tr, t.oferta_codigo oc, t.produto_id, t.produto_nome, t.origem_sck sck,
           (coalesce(t.aprovado_em, t.pedido_em) at time zone 'America/Sao_Paulo')::date d,
           t.status in ('APPROVED','COMPLETE') pago,
           coalesce(p.familia, 'OUTRO') familia
      from unnest(v_cod) c(oc)
      join fin.hotmart_transacoes t on t.oferta_codigo = c.oc
      left join fin.produtos p on p.produto_id = t.produto_id
     where t.status in ('APPROVED','COMPLETE','PRINTED_BILLET','WAITING_PAYMENT','UNDER_ANALISYS','STARTED',
                        'OVERDUE','PROTESTED','REFUNDED','PARTIALLY_REFUNDED','CHARGEBACK')
       and coalesce(t.recorrencia, 1) <= 1
       and coalesce(t.aprovado_em, t.pedido_em) is not null
  ), ofr0 as (
    select x.oc, min(x.produto_id) produto_id, min(x.produto_nome) produto_nome, min(x.familia) familia,
           count(*)::int n, count(*) filter (where x.pago)::int n_pagas,
           count(*) filter (where coalesce(x.sck, '') <> '')::int n_com_sck,
           min(x.d) primeira, max(x.d) ultima,
           percentile_disc(0.9) within group (order by x.d) p90
      from tx x
     group by x.oc
  ), ofr as (
    select o.*,
           v_of -> o.oc ->> 'nome' oferta_nome,
           fin.oferta_normaliza(v_of -> o.oc ->> 'nome') nome_n,
           fin.oferta_palavras(v_of -> o.oc ->> 'nome') kw,
           exists (select 1 from fin.evento_produtos ep where ep.produto_id = o.produto_id and ep.papel = 'ingresso') eh_ingresso
      from ofr0 o
  ), ev as (
    select e.id, e.nome, e.categoria, e.setor,
           coalesce(e.carrinho_inicio, e.inicio) ref_de,
           coalesce(e.carrinho_inicio, e.inicio) - 2 ja_de, e.venda_ate ja_ate,
           -- mesma expressão de evs.ing_de em public.fn_fin_trajetoria
           coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de,
           fin.oferta_normaliza(e.codigo) cod_n,
           fin.oferta_normaliza(e.nome) evn_n,
           fin.oferta_palavras(coalesce(e.nome, '') || ' ' || coalesce(e.codigo, '')) kw
      from fin.eventos e
  ), sv as (              -- por venda: o evento das ações cujo sck_regex casa (só se for UM evento)
    select x.oc, x.tr, min(a.evento_id) ev_id
      from tx x
      join fin.acoes a on a.evento_id is not null and a.sck_regex is not null and x.sck ~* a.sck_regex
     group by x.oc, x.tr
    having count(distinct a.evento_id) = 1
  ), sck as (
    select distinct on (s.oc) s.oc, s.ev_id, count(*)::int n_sck
      from sv s
     group by s.oc, s.ev_id
     order by s.oc, count(*) desc, s.ev_id
  ), pw as (              -- eventos educação cuja janela contém vendas da oferta
    select x.oc, e.id, e.ja_de, e.ja_ate, count(*)::int n
      from tx x
      join ev e on e.setor = 'educacao' and x.d between e.ja_de and e.ja_ate
               and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
     group by x.oc, e.id, e.ja_de, e.ja_ate
  ), pd as (              -- perene: vendas relevantes em 2 janelas que não se sobrepõem
    select distinct a.oc
      from pw a
      join pw b on b.oc = a.oc and a.ja_ate < b.ja_de
      join ofr o on o.oc = a.oc
     where a.n >= greatest(1, ceil(o.n * 0.1)) and b.n >= greatest(1, ceil(o.n * 0.1))
  ), jw as (              -- eventos educação cuja janela contém a 1ª venda (só produto que não é ingresso)
    select o.oc, e.id, e.nome, e.ja_de, e.ja_ate,
           count(*) filter (where x.d between e.ja_de and e.ja_ate + 7)::int n_dentro
      from ofr o
      join ev e on e.setor = 'educacao' and o.primeira between e.ja_de and e.ja_ate
               and not (o.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
      join tx x on x.oc = o.oc
     where not o.eh_ingresso
     group by o.oc, e.id, e.nome, e.ja_de, e.ja_ate
  ), jwa as (
    select j.oc, count(*)::int n_ev, min(j.id) id, min(j.n_dentro) n_dentro,
           (array_agg(j.id order by (j.ja_ate - j.ja_de), j.id))[1] melhor,
           jsonb_agg(jsonb_build_object('evento_id', j.id, 'nome', j.nome, 'de', j.ja_de, 'ate', j.ja_ate,
                                        'vendas_dentro', j.n_dentro) order by (j.ja_ate - j.ja_de), j.id) cands
      from jw j
     group by j.oc
  ), ing as (             -- ingresso: janela [venda_ate do anterior da categoria + 1, venda_ate]
    select x.oc, e.id, count(*)::int n
      from tx x
      join ofr o on o.oc = x.oc and o.eh_ingresso
      join fin.evento_produtos ep on ep.produto_id = x.produto_id and ep.papel = 'ingresso'
      join ev e on e.categoria = ep.categoria and x.d between e.ing_de and e.ja_ate
     group by x.oc, e.id
  ), ingr as (
    select distinct on (i.oc) i.oc, i.id, i.n,
           jsonb_agg(jsonb_build_object('evento_id', i.id, 'vendas', i.n)) over (partition by i.oc) cands
      from ing i
     order by i.oc, i.n desc, i.id
  ), nm as (              -- nome da oferta contém código/nome inteiro de evento cuja janela contém a 1ª venda
    select o.oc, count(*)::int n_ev, min(e.id) id,
           jsonb_agg(jsonb_build_object('evento_id', e.id, 'nome', e.nome) order by e.id) cands
      from ofr o
      join ev e on o.primeira between e.ja_de and e.ja_ate
     where length(o.nome_n) > 2
       and ((length(e.cod_n) >= 3 and position(' ' || e.cod_n || ' ' in ' ' || o.nome_n || ' ') > 0)
         or (length(e.evn_n) >= 8 and position(' ' || e.evn_n || ' ' in ' ' || o.nome_n || ' ') > 0))
     group by o.oc
  ), kws as (             -- palavras-chave em comum, evento a <= 60 dias da 1ª venda
    select o.oc, e.id, e.nome,
           cardinality(array(select unnest(o.kw) intersect select unnest(e.kw))) score
      from ofr o
      join ev e on o.primeira between e.ref_de - 60 and e.ja_ate + 60
     where cardinality(o.kw) > 0 and cardinality(e.kw) > 0
  ), kwr as (
    select distinct on (k.oc) k.oc, k.id, k.nome, k.score,
           coalesce(lead(k.score) over (partition by k.oc order by k.score desc, k.id), 0) segundo
      from kws k
     where k.score > 0
     order by k.oc, k.score desc, k.id
  ), dec as (
    select o.*, s.ev_id sck_ev, coalesce(s.n_sck, 0) n_sck,
           j.n_ev j_n, j.id j_id, j.n_dentro j_dentro, j.melhor j_melhor, j.cands j_cands,
           m.n_ev nm_n, m.id nm_id, m.cands nm_cands,
           g.id ing_id, g.n ing_n, g.cands ing_cands,
           k.id kw_id, k.nome kw_nome, coalesce(k.score, 0) kw_score, coalesce(k.segundo, 0) kw_segundo,
           case when k.score > k.segundo then k.id end kw_melhor,                        -- líder único (>= 1)
           (k.score >= 2 and k.score > k.segundo) kw_liga,                              -- >= 2 e margem >= 1
           (o.nome_n ~ '(^| )(saldo|migracao|renovacao)( |$)') contrato,
           coalesce((v_of -> o.oc ->> 'main')::boolean, false) main,
           (o.ultima - o.primeira) > 60 espalhada,
           (pd.oc is not null and not o.eh_ingresso) duas_janelas
      from ofr o
      left join sck s on s.oc = o.oc
      left join jwa j on j.oc = o.oc
      left join nm m on m.oc = o.oc
      left join ingr g on g.oc = o.oc
      left join kwr k on k.oc = o.oc
      left join pd on pd.oc = o.oc
  ), cls as (             -- cada regra vira um booleano (uma fonte só para decisao e sinal)
    select d.*,
           coalesce(d.contrato and coalesce(d.nm_n, 0) <> 1, false) r_contrato,
           coalesce(d.contrato and d.nm_n = 1, false) r_contrato_fila,
           coalesce(d.main or d.espalhada or d.duas_janelas, false) r_perene,
           coalesce(d.n >= 3 and d.sck_ev is not null and d.n_sck >= 0.8 * d.n, false) r_sck,
           coalesce(d.nm_n = 1, false) r_nome,
           coalesce(d.kw_liga, false) r_kw,
           coalesce(d.eh_ingresso and d.ing_id is not null and d.ing_n >= 0.9 * d.n
              and (d.kw_melhor is null or d.kw_melhor = d.ing_id), false) r_ing,
           coalesce(not d.eh_ingresso and d.j_n = 1 and d.j_dentro >= 0.9 * d.n and d.n_pagas >= 3
              and (d.kw_melhor is null or d.kw_melhor = d.j_id), false) r_jan
      from dec d
  ), res as (
    select c.*,
           case when c.r_contrato then 'contrato'
                when c.r_contrato_fila then 'fila'
                when c.r_perene then 'perene'
                when c.r_sck or c.r_nome or c.r_kw or c.r_ing or c.r_jan then 'ligar'
                when c.n >= 2 then 'fila'
                else 'ignorar' end dcs,
           case when c.r_contrato then 'contrato:nome'
                when c.r_contrato_fila then 'fila:contrato_com_nome_de_evento'
                when c.r_perene then
                  'perene:' || concat_ws('+', case when c.main then 'main_offer' end,
                                              case when c.espalhada then 'mais_de_60_dias' end,
                                              case when c.duas_janelas then 'duas_janelas' end)
                when c.r_sck then 'auto:sck'
                when c.r_nome or c.r_kw then 'auto:nome'
                when c.r_ing or c.r_jan then 'auto:janela'
                when c.n >= 2 then
                  case when c.eh_ingresso and c.ing_id is null then 'fila:sem_evento'
                       when c.eh_ingresso and c.ing_n < 0.9 * c.n then 'fila:ingresso_dividido'
                       when c.eh_ingresso then 'fila:nome_contradiz'
                       when c.j_n is null then 'fila:sem_evento'
                       when c.j_n > 1 then 'fila:varios_eventos'
                       when c.kw_melhor is not null and c.kw_melhor <> c.j_id then 'fila:nome_contradiz'
                       when c.n_pagas < 3 then 'fila:poucas_vendas'
                       else 'fila:sinal_fraco' end
                else 'sem_sinal' end sn,
           case when c.r_sck then c.sck_ev
                when c.r_nome then c.nm_id
                when c.r_kw then c.kw_id
                when c.r_ing then c.ing_id
                when c.r_jan then c.j_id end ev_ligar,
           coalesce(case when c.nm_n = 1 then c.nm_id end, c.kw_melhor,
                    case when c.eh_ingresso then c.ing_id end,
                    case when c.j_n = 1 then c.j_id end, c.sck_ev, c.j_melhor) sug,
           case when c.eh_ingresso then c.ing_id is null else c.j_n is null end sem_evento
      from cls c
  )
  select jsonb_agg(jsonb_build_object(
           'oferta_codigo', r.oc,
           'decisao', r.dcs,
           'sinal', r.sn,
           'evento_id', case when r.dcs = 'ligar' then r.ev_ligar when r.dcs = 'fila' then r.sug end,
           'detalhe', jsonb_build_object(
              'produto_id', r.produto_id, 'produto_nome', r.produto_nome, 'oferta_nome', r.oferta_nome,
              'n_vendas', r.n, 'n_pagas', r.n_pagas, 'n_com_sck', r.n_com_sck,
              'primeira_venda', r.primeira, 'ultima_venda', r.ultima, 'p90_venda', r.p90,
              'regra', case when r.r_ing then 'ingresso' when r.r_jan then 'janela'
                            when r.r_kw and not r.r_nome then 'palavras' when r.r_nome then 'nome' end,
              'contrato', r.contrato,
              'sck', jsonb_build_object('evento_id', r.sck_ev, 'vendas', r.n_sck),
              'janela', jsonb_build_object('n_eventos', coalesce(r.j_n, 0), 'candidatos', r.j_cands),
              'ingresso', jsonb_build_object('eh_ingresso', r.eh_ingresso, 'evento_id', r.ing_id, 'vendas', r.ing_n,
                                             'candidatos', r.ing_cands),
              'nome', jsonb_build_object('n_eventos', coalesce(r.nm_n, 0), 'candidatos', r.nm_cands,
                                         'fonte', case when v_tem_ofertas then 'fin.ofertas' else 'fin.ofertas ausente' end),
              'palavras', jsonb_build_object('oferta', to_jsonb(r.kw), 'evento_id', r.kw_id, 'evento', r.kw_nome,
                                             'comuns', r.kw_score, 'segundo', r.kw_segundo),
              'perene', jsonb_build_object('main_offer', r.main, 'mais_de_60_dias', r.espalhada, 'duas_janelas', r.duas_janelas),
              'sugestao_evento_id', case when r.dcs = 'fila' then r.sug end,
              'proposta_evento', case when r.dcs = 'fila' and r.sem_evento and not r.contrato then jsonb_build_object(
                  'nome', coalesce(r.oferta_nome, r.produto_nome),
                  'categoria', (select ep.categoria from fin.evento_produtos ep
                                 where ep.produto_id = r.produto_id
                                 order by (ep.papel = 'ingresso') desc, ep.categoria limit 1),
                  'carrinho_inicio', r.primeira,
                  'venda_ate', r.p90) end,
              'calculado_em', now())))
    into v_res
    from res r;

  if v_res is null then
    return;
  end if;

  -- 4. gravação (só com p_gravar): nunca sobrescreve ligação; fila só atualiza o que ainda está pendente
  if coalesce(p_gravar, false) then
    insert into fin.evento_ofertas (evento_id, oferta_codigo, observacao, origem, sinais, criado_em)
    select r.evento_id, r.oferta_codigo, 'ligada sozinha pelo resolvedor (' || r.sinal || ')', r.sinal, r.detalhe, now()
      from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
     where r.decisao = 'ligar' and r.evento_id is not null
    on conflict do nothing;

    insert into fin.oferta_evento_fila as f (oferta_codigo, produto_id, sugestao_evento_id, proposta_evento, sinais, n_vendas)
    select r.oferta_codigo, r.detalhe ->> 'produto_id', r.evento_id, r.detalhe -> 'proposta_evento', r.detalhe,
           (r.detalhe ->> 'n_vendas')::int
      from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
     where r.decisao = 'fila'
    on conflict on constraint oferta_evento_fila_pkey do update
       set produto_id = excluded.produto_id,
           sugestao_evento_id = excluded.sugestao_evento_id,
           proposta_evento = excluded.proposta_evento,
           sinais = excluded.sinais,
           n_vendas = excluded.n_vendas
     where f.status = 'pendente';
  end if;

  return query
  select r.oferta_codigo, r.decisao, r.evento_id, r.sinal, r.detalhe
    from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
   order by r.decisao, r.oferta_codigo;
end
$$;
revoke all on function fin.resolver_ofertas_eventos(boolean, integer, text[]) from public, anon, authenticated;
grant execute on function fin.resolver_ofertas_eventos(boolean, integer, text[]) to service_role;


-- ─── 3. Conferência (falha a migration) ─────────────────────────────────────────────────────
do $confere$
declare v text;
begin
  -- auxiliares: casos reais do veredito
  select string_agg(x.caso, ' | ') into v
    from (values
      ('saldo HM',        fin.oferta_normaliza('Saldo HM Programa de Implementação R$ 10.000') ~ '(^| )(saldo|migracao|renovacao)( |$)'),
      ('migração HM',     fin.oferta_normaliza(' Migração Implementação Holding Masters') ~ '(^| )(saldo|migracao|renovacao)( |$)'),
      ('renovação HM',    fin.oferta_normaliza('Holding Masters - Saldo 6.000 Renovação') ~ '(^| )(saldo|migracao|renovacao)( |$)'),
      ('saldo reserva',   fin.oferta_normaliza('Saldo (R$ 14.303 de R$ 15.000 - taxa de reserva de R$ 697)') ~ '(^| )(saldo|migracao|renovacao)( |$)'),
      ('não contrato',    not (fin.oferta_normaliza('2º Encontro Acelera Holding R$ 1.249') ~ '(^| )(saldo|migracao|renovacao)( |$)')),
      ('não contrato 2',  not (fin.oferta_normaliza('Taxa de inscrição R$ 697') ~ '(^| )(saldo|migracao|renovacao)( |$)')),
      ('normaliza',       fin.oferta_normaliza('Clínica São Paulo 2º/2026') = 'clinica sp 2o 2026'),
      ('palavras ethb',   fin.oferta_palavras('Encontro do Time Holding Brasil/2027 - LOTE 0') = array['2027','encontro','ethb']),
      ('palavras ht',     fin.oferta_palavras('Holding Total (HT32)') = array['ht32']),
      ('palavras vazio',  fin.oferta_palavras(null) = '{}'::text[])
    ) x(caso, ok)
   where not coalesce(x.ok, false);
  if v is not null then
    raise exception 'z83: auxiliares falharam nos casos: %', v;
  end if;

  select string_agg(x.o, ', ') into v
    from (values
      ('anon resolver', has_function_privilege('anon', 'fin.resolver_ofertas_eventos(boolean,integer,text[])', 'execute')),
      ('auth resolver', has_function_privilege('authenticated', 'fin.resolver_ofertas_eventos(boolean,integer,text[])', 'execute')),
      ('anon normaliza', has_function_privilege('anon', 'fin.oferta_normaliza(text)', 'execute')),
      ('auth normaliza', has_function_privilege('authenticated', 'fin.oferta_normaliza(text)', 'execute')),
      ('anon palavras', has_function_privilege('anon', 'fin.oferta_palavras(text)', 'execute')),
      ('auth palavras', has_function_privilege('authenticated', 'fin.oferta_palavras(text)', 'execute'))
    ) x(o, aberto)
   where x.aberto;
  if v is not null then
    raise exception 'z83: permissão aberta: %', v;
  end if;

  if exists (select 1 from fin.evento_ofertas eo where eo.origem like 'auto:%') then
    raise exception 'z83: há ligação automática gravada — esta migration não deveria encontrar nenhuma (cron/backfill rodou antes?)';
  end if;
end $confere$;


-- ─── Simulação e conferência (orquestrador; NÃO faz parte da aplicação; p_gravar=false = só leitura) ─────
-- C1) verdade conhecida (ligações manuais avaliadas como se não existissem). ACEITE: erro_grave = 0.
--   with v as (select eo.oferta_codigo, eo.evento_id from fin.evento_ofertas eo where eo.origem = 'manual')
--   select r.decisao, r.sinal, r.detalhe->>'regra' regra, count(*) total,
--          count(*) filter (where r.evento_id = v.evento_id) acerto,
--          count(*) filter (where r.decisao = 'ligar' and r.evento_id <> v.evento_id) erro_grave,
--          string_agg(r.oferta_codigo || '->' || coalesce(r.evento_id::text, '-') || ' (certo ' || v.evento_id || ')', ', ') ofertas
--     from fin.resolver_ofertas_eventos(false, 45, array(select oferta_codigo from fin.evento_ofertas where origem = 'manual')) r
--     join v on v.oferta_codigo = r.oferta_codigo
--    group by 1,2,3 order by 1,2,3;
-- C1b) detalhe por oferta (para ver palavras/ingresso de cada uma):
--   select r.oferta_codigo, r.decisao, r.sinal, r.evento_id, v.evento_id certo, r.detalhe->>'oferta_nome' nome,
--          r.detalhe->'palavras' palavras, r.detalhe->'ingresso' ingresso, r.detalhe->'janela'->'n_eventos' janelas
--     from fin.resolver_ofertas_eventos(false, 45, array(select oferta_codigo from fin.evento_ofertas where origem = 'manual')) r
--     join fin.evento_ofertas v on v.oferta_codigo = r.oferta_codigo order by 2,3;
-- S2) 120 dias. ACEITE: zero linha na 2ª consulta.
--   select decisao, sinal, detalhe->>'regra' regra, count(*) ofertas, sum((detalhe->>'n_vendas')::int) vendas
--     from fin.resolver_ofertas_eventos(false, 120) group by 1,2,3 order by 1,2,3;
--   select oferta_codigo, sinal, detalhe->>'oferta_nome' from fin.resolver_ofertas_eventos(false, 120)
--    where decisao = 'ligar' and fin.oferta_normaliza(detalhe->>'oferta_nome') ~ '(^| )(saldo|migracao|renovacao)( |$)';
-- S3) o que seria ligado, para olho humano:
--   select r.oferta_codigo, r.sinal, r.detalhe->>'regra' regra, r.evento_id, e.nome evento, r.detalhe->>'oferta_nome' oferta,
--          r.detalhe->>'n_vendas' n, r.detalhe->>'n_pagas' pagas, r.detalhe->>'primeira_venda' de, r.detalhe->>'ultima_venda' ate
--     from fin.resolver_ofertas_eventos(false, 120) r left join fin.eventos e on e.id = r.evento_id
--    where r.decisao = 'ligar' order by r.sinal, e.nome;
-- S4) o que virou contrato (conferir que nenhuma é de evento):
--   select oferta_codigo, sinal, detalhe->>'oferta_nome', detalhe->>'n_vendas' from fin.resolver_ofertas_eventos(false, 120)
--    where decisao = 'contrato' or sinal = 'fila:contrato_com_nome_de_evento' order by 2,3;
-- E1) explain (analyze, buffers) select * from fin.resolver_ofertas_eventos(false);        -- 2x
-- E2) explain (analyze, buffers) select * from fin.resolver_ofertas_eventos(false, 120);
