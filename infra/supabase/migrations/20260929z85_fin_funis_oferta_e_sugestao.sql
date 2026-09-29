-- 20260929z85 — Funis por oferta ligada + sugestão da fila com prazo + correções do pentest (29/09/2026)
--
-- POR QUÊ
--   1. Aba Funis. O resolvedor (z82/z83, cron de hora em hora pela z84) grava em fin.evento_ofertas a ligação
--      oferta→evento, e fin.vw_acao_card / fn_fin_trajetoria (z79) já a usam com prioridade máxima. A aba Funis não:
--      public.fn_fin_funis e public.fn_fin_funil_compradores contam a OFERTA por categoria+produto+janela de data
--      (a z4 só trocou o ramo de INGRESSO). Efeitos: (a) oferta ligada a um evento continua contada, por data, em
--      qualquer evento da categoria cuja janela cruza (dupla contagem ou evento errado); (b) venda de oferta ligada a
--      evento cuja categoria não tem o produto em fin.evento_produtos some do funil (ex.: 2º Encontro Acelera,
--      categoria encontro_acelera, produto 5064314).
--      Troca (a mesma da z4, agora no ramo oferta): oferta presente em fin.evento_ofertas conta SÓ no evento dela,
--      sem janela; ausente segue a regra de data de hoje. E um ramo novo: venda de oferta ligada cujo produto não
--      está na categoria do evento entra no evento ligado (papel 'ingresso' só se o produto é ingresso em todas as
--      categorias em que aparece; senão 'oferta').
--   2. Sugestão da fila. As ofertas do Acelera de agosto (1ª venda 26–27/08) recebiam sugestão "2º Encontro Acelera
--      Holding" (evento de 28/09): a palavra 'acelera' casa e o evento está a <= 60 dias. Regra nova: por
--      palavra-chave, o evento não pode começar depois de 1ª venda + 7 dias (exceto produto ingresso: pré-venda).
--      Ordem da sugestão: nome > janela única > ingresso > palavras > sck > janela mais curta.
--      As regras de LIGAR ficam como na z83, com duas exceções pedidas: (i) ligar por palavras também respeita o prazo;
--      (ii) pentest (Kirad, MÉDIO): sck conta só vendas PAGAS (>= 3 pagas, >= 80% das pagas) e nome/palavras/ingresso
--      exigem >= 1 venda paga. O "nome contradiz" da janela/ingresso continua usando o líder de palavras SEM prazo
--      (nada que hoje fica na fila passa a ser ligado sozinho por causa desta migration).
--   3. Pentest (Kirad, MÉDIO): public.fn_fin_decidir_oferta aceitava 'infinity'/'-infinity' e janela sem limite
--      (evento que engole todas as vendas na trajetória e desliga auto:janela para todo mundo) e categoria inédita.
--      Agora: datas finitas; fim >= início; venda_ate >= início; carrinho <= venda_ate; janela <= 120 dias; todas as
--      datas a no máximo 2 anos de hoje; categoria só se já existe em fin.eventos ou fin.evento_produtos.
--      O portão (gp_pode_ver_financeiro) NÃO muda — decisão do Marcio.
--   4. Pentest (Kirad, BAIXO): public.fn_fin_board (security definer) tinha search_path 'public, cs'; passa a ''.
--      O corpo da z75 já é todo qualificado (fin., cs., public.) — create or replace com o MESMO corpo.
--
-- OBJETOS: 5 funções, todas por create or replace com a MESMA assinatura e o MESMO retorno (sem sobrecarga, sem
--   drop). Nenhuma tabela, índice, view ou dado. NÃO toca web/, fin.vw_acao_card, fn_fin_trajetoria,
--   fin.acao_card_manual.
--
-- GUARDAS (seção 0, antes de qualquer escrita): para cada função, o corpo VIVO (pg_proc.prosrc sem comentários e
--   sem espaços) tem de ser IGUAL ao corpo esperado embutido na seção 0; senão aborta mostrando o trecho vivo ×
--   esperado. Reexecução: corpo com o marcador 'z85:' é aceito e não é reaplicado.
--   ATENÇÃO — corpos de fn_fin_funis e fn_fin_funil_compradores foram RECONSTRUÍDOS dos arquivos (z + z2 + z4 + z31
--   + z34), porque z31 e z34 remendaram o corpo vivo por replace e a z31 não deixou o texto no repo. Dois trechos são
--   inferência e são exatamente os que a guarda vai conferir:
--     fn_fin_funis, conta_ausente (z31) .......... (e.setor = 'escritorio' and e.inicio >= date '2025-01-01')
--     fn_fin_funil_compradores, nome (z34) ...... fin.nome_exibicao(t.nome, t.email), t.email,
--   Se a guarda abortar num deles: nada foi alterado; cole o prosrc vivo no literal da seção 0 e rode de novo. O
--   patch das duas é por replace sobre o pg_get_functiondef VIVO (trechos exigidos exatamente 1 vez), então o corpo
--   novo = corpo vivo + a troca, sem depender da reconstrução.
--
-- 5 PERGUNTAS (~/.claude/PROTOCOLO-SUSTENTABILIDADE.md)
--   1. Escala. fn_fin_funis: continua 1 Seq Scan de fin.vw_transacoes; o CTE tx passa a ser lido 2x (Postgres
--      materializa 1x) e o ramo novo é hash join com fin.evento_ofertas (dezenas–centenas de linhas). As provas
--      exists/not exists por venda de produto 'oferta' usam evento_ofertas_oferta_uq. 10x vendas = 10x linear, igual
--      a hoje. fn_fin_funil_compradores: o ramo novo descobre os produtos das ofertas ligadas ao evento lendo
--      fin.hotmart_transacoes por oferta_codigo — NÃO há índice só em oferta_codigo: é 1 Seq Scan por clique quando
--      o evento tem oferta ligada (medir no E2 do rodapé; se passar de ~150 ms, índice em fin.hotmart_transacoes
--      (oferta_codigo) criado concurrently fora de migration). Resolvedor: +1 CTE (kwp) sobre o mesmo kws; custo
--      desprezível. Decidir: 2 buscas por categoria (índice único (categoria, inicio) de fin.eventos e PK de
--      fin.evento_produtos). Board: mesmo plano (a função já tinha SET, nunca foi inlinada).
--   2. Índice. Nenhuma expressão funcional nova sobre coluna indexada. Usados: evento_ofertas_oferta_uq,
--      evento_produtos_pkey, hotmart_transacoes_produto_idx (inalterado). Provar com o explain E1–E4 do rodapé.
--   3. Frequência. Funis: abrir a aba (equipe financeira, poucas vezes/dia). Compradores: 1 por clique no funil.
--      Resolvedor: 1x/hora (z84). Decidir: 1 por clique humano. Board: igual a hoje.
--   4. Repetição. Nenhuma RPC nova; mesma quantidade de chamadas por tela.
--   5. Reversão: abaixo. Nada a desfazer em dado (a migration não grava linha; o cron da hora seguinte só atualiza
--      sugestão de fila PENDENTE — ligação existente nunca é sobrescrita).
--
-- REVERSÃO (numa transação; os corpos anteriores são os literais da seção 0, conferidos iguais ao vivo pela guarda):
--   a. fn_fin_funis / fn_fin_funil_compradores: rodar o bloco $reverte$ do fim deste arquivo (comentado): faz o
--      replace inverso sobre o pg_get_functiondef vivo (trechos novos -> trechos antigos) + revoke/grant.
--   b. fin.resolver_ofertas_eventos: reaplicar a seção 2 de 20260929z83_fin_resolvedor_contrato_ingresso_nome.sql
--      (create or replace + revoke/grant).
--   c. public.fn_fin_decidir_oferta: reaplicar a seção 4b de 20260929z82_fin_oferta_evento_resolvedor.sql
--      (create or replace ... até o grant, linhas 507–603).
--   d. public.fn_fin_board: reaplicar 20260929z75_fin_acao_entrada_e_retorno.sql linhas 299–347 trocando
--      "create function" por "create or replace function" (NÃO rodar o drop da linha 297; a view fin.vw_acao_card
--      não é tocada).
--   Depois de b: select count(*) from fin.resolver_ofertas_eventos(true, 45); recalcula as sugestões pendentes.

-- ─── 0. Guardas (nada é escrito aqui) — os literais abaixo SÃO os corpos anteriores (texto de reversão) ─────
do $guarda$
declare
  v_fn   text[] := array['public.fn_fin_funis()', 'public.fn_fin_funil_compradores(bigint)', 'fin.resolver_ofertas_eventos(boolean,integer,text[])', 'public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)', 'public.fn_fin_board(text,text)'];
  v_esp  text[];
  v_src  text;
  v_def  boolean;
  v_viv  text;
  v_e    text;
  v_lo   int;
  v_hi   int;
  v_mid  int;
  v_x    text;
begin
  v_esp := array[
-- public.fn_fin_funis() (anterior)
$e_funis$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with ev as (
    select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de
      from fin.eventos e
  ), tx as (
    select t.transacao, t.produto_id, t.oferta_codigo, t.email, t.grupo, (t.aprovado_em at time zone 'America/Sao_Paulo')::date dia,
           t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end valor,
           coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
             * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end liq
      from fin.vw_transacoes t
     where t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) = 1 and t.email is not null
  ), casado as (
    select e.id, p.papel, x.*
      from ev e
      join fin.evento_produtos p on p.categoria = e.categoria
      join tx x on x.produto_id = p.produto_id
       and ((p.papel = 'oferta'   and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)
         or (p.papel = 'ingresso' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = x.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = x.oferta_codigo)
                                            and x.dia between e.ing_de and e.venda_ate))))
  ), agg as (
    select c.id,
           count(*) filter (where c.papel = 'ingresso' and c.grupo = 'pago')::int ing_n,
           coalesce(sum(c.valor) filter (where c.papel = 'ingresso' and c.grupo = 'pago'), 0) ing_b,
           coalesce(sum(c.liq) filter (where c.papel = 'ingresso' and c.grupo = 'pago'), 0) ing_l,
           count(*) filter (where c.papel = 'oferta' and c.grupo = 'pago')::int of_n,
           count(distinct c.email) filter (where c.papel = 'oferta' and c.grupo = 'pago')::int of_p,
           count(*) filter (where c.papel = 'oferta' and c.grupo = 'estornado')::int of_e,
           coalesce(sum(c.valor) filter (where c.papel = 'oferta' and c.grupo = 'pago'), 0) of_b,
           coalesce(sum(c.liq) filter (where c.papel = 'oferta' and c.grupo = 'pago'), 0) of_l,
           count(distinct c.email) filter (where c.grupo = 'pago')::int pess,
           coalesce(sum(c.liq), 0) liq_conf
      from casado c group by c.id
  )
  select e.id, e.nome, e.categoria, e.setor, e.inicio, e.fim, e.carrinho_inicio, e.venda_ate, e.ing_de,
         coalesce(a.ing_n, 0), round(coalesce(a.ing_b, 0), 2), round(coalesce(a.ing_l, 0), 2),
         coalesce(a.of_n, 0), coalesce(a.of_p, 0), coalesce(a.of_e, 0), round(coalesce(a.of_b, 0), 2), round(coalesce(a.of_l, 0), 2),
         coalesce(a.pess, 0), round(coalesce(a.ing_b, 0) + coalesce(a.of_b, 0), 2), round(coalesce(a.ing_l, 0) + coalesce(a.of_l, 0), 2),
         e.ref_vendas, e.ref_valor, e.ref_tipo, e.ref_fonte, e.observacao, (e.setor = 'escritorio' and e.inicio >= date '2025-01-01'), round(coalesce(a.liq_conf, 0), 2)
    from ev e left join agg a on a.id = e.id
   order by e.inicio desc;
end
$e_funis$,
-- public.fn_fin_funil_compradores(bigint) (anterior)
$e_compr$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with e as (
    select x.*, coalesce((select max(y.venda_ate) from fin.eventos y where y.categoria = x.categoria and y.inicio < x.inicio) + 1, x.inicio - 60) ing_de
      from fin.eventos x where x.id = p_evento_id
  )
  select p.papel, t.produto_nome, t.oferta_codigo, (t.aprovado_em at time zone 'America/Sao_Paulo')::date,
         t.grupo,
         round(t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end, 2),
         round(coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
               * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end, 2),
         fin.nome_exibicao(t.nome, t.email), t.email,
         case when coalesce(public.gp_pode_ver_cpf(), false) then h.comprador_telefone
              when h.comprador_telefone is not null then '···' || right(h.comprador_telefone, 4) end,
         t.parcelas
    from e
    join fin.evento_produtos p on p.categoria = e.categoria
    join fin.vw_transacoes t on t.produto_id = p.produto_id and t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) = 1
     and ((p.papel = 'oferta' and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)
       or (p.papel = 'ingresso' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
                                            and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between e.ing_de and e.venda_ate))))
    join fin.hotmart_transacoes h on h.transacao = t.transacao
   order by p.papel desc, t.aprovado_em;
end
$e_compr$,
-- fin.resolver_ofertas_eventos(boolean,integer,text[]) (anterior)
$e_resolv$
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
$e_resolv$,
-- public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean) (anterior)
$e_decid$
declare
  v_uid  uuid := auth.uid();
  v_of   text := nullif(btrim(p_oferta), '');
  v_f    fin.oferta_evento_fila%rowtype;
  v_ev   bigint;
  v_lig  bigint;
  v_nome text;
  v_cat  text;
  v_ini  date;
  v_fim  date;
  v_ate  date;
  v_car  date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) or v_uid is null then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_of is null then
    raise exception 'Informe a oferta.' using errcode = '22023';
  end if;
  if (p_evento_id is not null)::int + (p_criar is not null)::int + coalesce(p_rejeitar, false)::int <> 1 then
    raise exception 'Escolha uma ação: evento existente, criar evento ou rejeitar.' using errcode = '22023';
  end if;

  select * into v_f from fin.oferta_evento_fila f where f.oferta_codigo = v_of for update;
  if not found then
    raise exception 'A oferta % não está na fila.', v_of using errcode = 'P0002';
  end if;
  if v_f.status <> 'pendente' then
    raise exception 'A oferta % já foi decidida (%).', v_of, v_f.status using errcode = '55000';
  end if;
  select eo.evento_id into v_lig from fin.evento_ofertas eo where eo.oferta_codigo = v_of;
  if v_lig is not null then
    raise exception 'A oferta % já está ligada ao evento %.', v_of, v_lig using errcode = '23505';
  end if;

  if coalesce(p_rejeitar, false) then
    update fin.oferta_evento_fila f
       set status = 'rejeitada', decidido_por = v_uid, decidido_em = now()
     where f.oferta_codigo = v_of;
    return jsonb_build_object('oferta', v_of, 'status', 'rejeitada');
  end if;

  if p_criar is not null then
    v_nome := nullif(btrim(p_criar ->> 'nome'), '');
    v_cat  := nullif(lower(btrim(p_criar ->> 'categoria')), '');
    v_ini  := nullif(btrim(p_criar ->> 'inicio'), '')::date;
    v_fim  := coalesce(nullif(btrim(p_criar ->> 'fim'), '')::date, v_ini);
    v_ate  := coalesce(nullif(btrim(p_criar ->> 'venda_ate'), '')::date, v_fim);
    v_car  := nullif(btrim(p_criar ->> 'carrinho_inicio'), '')::date;
    if v_nome is null or length(v_nome) > 200 then
      raise exception 'Nome do evento obrigatório (até 200 caracteres).' using errcode = '22023';
    end if;
    if v_cat is null or v_cat !~ '^[a-z][a-z0-9_]{1,39}$' then
      raise exception 'Categoria inválida (minúsculas, números e _).' using errcode = '22023';
    end if;
    if v_ini is null or v_fim < v_ini or (v_car is not null and v_car > v_ate) then
      raise exception 'Datas do evento inválidas.' using errcode = '22023';
    end if;

    insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, fonte, observacao, automatico)
    values (v_nome, v_cat, 'educacao', v_ini, v_fim, v_ate, v_car, 'confirmado na fila',
            'criado na fila de ofertas a partir da oferta ' || v_of || ' por ' || v_uid::text, true)
    on conflict (categoria, inicio) do nothing
    returning id into v_ev;
    if v_ev is null then
      raise exception 'Já existe evento % começando em %: escolha-o na lista.', v_cat, v_ini using errcode = '23505';
    end if;
  else
    select e.id into v_ev from fin.eventos e where e.id = p_evento_id;
    if v_ev is null then
      raise exception 'Evento % não existe.', p_evento_id using errcode = 'P0002';
    end if;
  end if;

  -- sem on conflict: se alguém ligou a oferta no meio, o índice único falha e a transação desfaz tudo (inclusive o evento criado)
  insert into fin.evento_ofertas (evento_id, oferta_codigo, observacao, origem, sinais, criado_em)
  values (v_ev, v_of, 'confirmado na fila', 'confirmado',
          coalesce(v_f.sinais, '{}'::jsonb) || jsonb_build_object('decidido_por', v_uid, 'evento_criado', p_criar is not null),
          now());

  update fin.oferta_evento_fila f
     set status = 'confirmada', decidido_por = v_uid, decidido_em = now()
   where f.oferta_codigo = v_of;

  return jsonb_build_object('oferta', v_of, 'status', 'confirmada', 'evento_id', v_ev, 'evento_criado', p_criar is not null);
end
$e_decid$,
-- public.fn_fin_board(text,text) (anterior)
$e_board$
  select
    b.origem, b.contato_hm_id, b.comprador_id, b.aluno_id,
    fin.nome_do_card(b.nome, b.email, alu.nome)::character varying, b.email,
    coalesce(tu.turma, b.turma), b.turma_origem,
    case when b.canal is null or b.canal = 'Não classificado' then coalesce(a.acao_canal, b.canal) else b.canal end,
    b.publico, b.produto,
    e.chave as estagio_chave,
    b.estagio_nome, b.estagio_aba, b.vendedor,
    b.status_financeiro, b.faixa,
    b.pacote, b.total_pago_bruto, b.total_pago_liquido,
    b.sinal_bruto, b.saldo_pago_bruto,
    b.saldo_a_pagar, b.credito, b.pago_pct,
    b.vencimento, b.dias_atraso,
    b.entrou_estagio_em, b.dias_no_estagio,
    b.solicitou_cancelamento, b.cancelamento_em, b.cancelamento_efetivado_em,
    b.quitado_em, b.reembolso_em, b.reembolso_valor,
    b.oferta_codigo, b.oferta_enviada_em, b.ultimo_pagamento_em,
    b.aurum_excecao, b.aurum_excecao_motivo, b.aurum_rotulo_operador,
    a.acao_nome, a.acao_data,
    b.reuniao_resultado, b.intencao_pagamento, b.intencao_pagamento_obs,
    b.reuniao_motivo_tipo, b.reuniao_retomar_em,
    b.pacote_regra, b.divergencia_regra,
    a.acao_regra, a.captado_em, a.captado_sck,
    a.voltou_nome, a.voltou_data, a.voltou_regra
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  left join fin.vw_acao_card a on a.contato_hm_id = b.contato_hm_id
  left join fin.vw_turma_origem_card tu on tu.contato_hm_id = b.contato_hm_id
  left join public.thb_alunos alu on alu.id = b.aluno_id
  where coalesce(public.gp_pode_ver_financeiro(), false)
    and (p_turma is null or coalesce(tu.turma, b.turma) = p_turma)
    and (p_produto is null or b.origem = p_produto)
    -- card gêmeo (z37/z49): cadastro com alias para outro cadastro que já tem card do mesmo produto.
    -- Array de propósito (InitPlan): subconsulta aqui reavalia a view linha a linha (15 s medidos).
    and not (b.contato_hm_id = any (array(
      select cx.id from cs.hm_comprador_alias al
        join cs.contatos_hm cx on cx.comprador_id = al.comprador_id
        join cs.contatos_hm cc on cc.comprador_id = al.canonico_id and cc.produto = cx.produto)))
  order by b.saldo_a_pagar desc nulls last, b.nome;
$e_board$
  ];

  for i in 1 .. array_length(v_fn, 1) loop
    v_src := null;
    select p.prosrc, p.prosecdef into v_src, v_def from pg_proc p where p.oid = to_regprocedure(v_fn[i]);
    if v_src is null then
      raise exception 'z85: % não existe (ou mudou de assinatura)', v_fn[i];
    end if;
    if not v_def then
      raise exception 'z85: % não é mais security definer', v_fn[i];
    end if;
    continue when position('z85:' in v_src) > 0;          -- já aplicada: reexecução não reaplica
    -- corpo sem comentários de linha e sem espaço algum (mesma normalização dos dois lados)
    v_viv := regexp_replace(regexp_replace(v_src,    '--[^\n]*', '', 'g'), '\s+', '', 'g');
    v_e   := regexp_replace(regexp_replace(v_esp[i], '--[^\n]*', '', 'g'), '\s+', '', 'g');
    if v_viv is distinct from v_e then
      v_lo := 0;                                           -- maior prefixo comum (busca binária)
      v_hi := least(length(v_viv), length(v_e));
      while v_lo < v_hi loop
        v_mid := (v_lo + v_hi + 1) / 2;
        if left(v_viv, v_mid) = left(v_e, v_mid) then v_lo := v_mid; else v_hi := v_mid - 1; end if;
      end loop;
      raise exception 'z85: corpo vivo de % difere do esperado a partir do caractere % (texto sem espaços/comentários). Nada foi alterado.', v_fn[i], v_lo + 1
        using detail = 'vivo:     ' || substr(v_viv, greatest(v_lo - 80, 1), 200) || chr(10)
                    || 'esperado: ' || substr(v_e,   greatest(v_lo - 80, 1), 200),
              hint   = 'Conferir: select prosrc from pg_proc where oid = to_regprocedure(''' || v_fn[i] || '''); '
                    || 'se a diferença for legítima, colar o corpo vivo no literal esperado da seção 0.';
    end if;
  end loop;

  -- board: o retorno tem de ser o da z75 (create or replace não troca retorno)
  select pg_get_function_result(p.oid) into v_x from pg_proc p where p.oid = to_regprocedure('public.fn_fin_board(text,text)');
  if v_x <> 'TABLE(origem text, contato_hm_id uuid, comprador_id uuid, aluno_id uuid, nome character varying, email character varying, turma text, turma_origem text, canal text, publico text, produto text, estagio_chave text, estagio_nome text, estagio_aba text, vendedor text, status_financeiro text, faixa text, pacote numeric, total_pago_bruto numeric, total_pago_liquido numeric, sinal_bruto numeric, saldo_pago_bruto numeric, saldo_a_pagar numeric, credito numeric, pago_pct numeric, vencimento date, dias_atraso integer, entrou_estagio_em timestamp with time zone, dias_no_estagio integer, solicitou_cancelamento boolean, cancelamento_em timestamp with time zone, cancelamento_efetivado_em timestamp with time zone, quitado_em timestamp with time zone, reembolso_em timestamp with time zone, reembolso_valor numeric, oferta_codigo text, oferta_enviada_em timestamp with time zone, ultimo_pagamento_em timestamp with time zone, aurum_excecao boolean, aurum_excecao_motivo text, aurum_rotulo_operador text, acao_nome text, acao_data timestamp with time zone, reuniao_resultado text, intencao_pagamento text, intencao_pagamento_obs text, reuniao_motivo_tipo text, reuniao_retomar_em date, pacote_regra numeric, divergencia_regra numeric, acao_regra text, captado_em date, captado_sck text, voltou_nome text, voltou_data timestamp with time zone, voltou_regra text)' then
    raise exception 'z85: retorno vivo de fn_fin_board mudou: %', v_x;
  end if;
  select pg_get_function_result(p.oid) into v_x from pg_proc p where p.oid = to_regprocedure('fin.resolver_ofertas_eventos(boolean,integer,text[])');
  if v_x <> 'TABLE(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)' then
    raise exception 'z85: retorno vivo do resolvedor mudou: %', v_x;
  end if;
  select pg_get_function_result(p.oid) into v_x from pg_proc p where p.oid = to_regprocedure('public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)');
  if v_x <> 'jsonb' then
    raise exception 'z85: retorno vivo de fn_fin_decidir_oferta mudou: %', v_x;
  end if;

  -- sem sobrecarga das 5 (create or replace criaria outra em vez de substituir)
  select string_agg(n.nspname || '.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')', ', ') into v_x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname, p.proname) in (('public','fn_fin_funis'), ('public','fn_fin_funil_compradores'), ('fin','resolver_ofertas_eventos'),
                                    ('public','fn_fin_decidir_oferta'), ('public','fn_fin_board'))
     and p.oid not in (select to_regprocedure(f) from unnest(v_fn) f);
  if v_x is not null then
    raise exception 'z85: sobrecarga inesperada: %', v_x;
  end if;

  -- dependências do corpo novo
  if to_regprocedure('fin.oferta_normaliza(text)') is null or to_regprocedure('fin.oferta_palavras(text)') is null then
    raise exception 'z85: auxiliares da z83 ausentes';
  end if;
  select string_agg(c.t || '.' || c.col, ', ') into v_x
    from (values ('evento_ofertas','evento_id'), ('evento_ofertas','oferta_codigo'), ('evento_ofertas','origem'),
                 ('eventos','inicio'), ('eventos','categoria'), ('evento_produtos','papel'),
                 ('hotmart_transacoes','oferta_codigo'), ('hotmart_transacoes','produto_id')) c(t, col)
   where not exists (select 1 from information_schema.columns i
                      where i.table_schema = 'fin' and i.table_name = c.t and i.column_name = c.col);
  if v_x is not null then
    raise exception 'z85: colunas ausentes: %', v_x;
  end if;
  if not exists (select 1 from pg_index x join pg_attribute a on a.attrelid = x.indrelid and a.attnum = x.indkey[0]
                  where x.indrelid = 'fin.evento_ofertas'::regclass and x.indisunique and x.indnatts = 1 and a.attname = 'oferta_codigo') then
    raise exception 'z85: índice único de fin.evento_ofertas(oferta_codigo) ausente — uma oferta poderia estar em 2 eventos e contar 2x';
  end if;
end $guarda$;

-- ─── 1. Funis: ramo OFERTA pela ligação oferta→evento + venda ligada fora da categoria ────────────────
-- Corpo novo = pg_get_functiondef VIVO + as trocas abaixo (cada trecho antigo exatamente 1 vez).
do $funis$
declare
  v_old text[] := array[
      $o0$(p.papel = 'oferta'   and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)$o0$,
      $o1$  ), agg as ($o1$];
  v_new text[] := array[
      $n0$(p.papel = 'oferta'   and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = x.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = x.oferta_codigo)
                                            and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))$n0$,
      $n1$    union all
    -- z85: venda de oferta ligada ao evento (fin.evento_ofertas) cujo produto a categoria do evento não tem
    select e.id,
           case when exists (select 1 from fin.evento_produtos p2 where p2.produto_id = x.produto_id and p2.papel = 'ingresso')
                  and not exists (select 1 from fin.evento_produtos p2 where p2.produto_id = x.produto_id and p2.papel = 'oferta')
                 then 'ingresso' else 'oferta' end,
           x.*
      from fin.evento_ofertas eo
      join ev e on e.id = eo.evento_id
      join tx x on x.oferta_codigo = eo.oferta_codigo
     where not exists (select 1 from fin.evento_produtos p where p.categoria = e.categoria and p.produto_id = x.produto_id)
  ), agg as ($n1$];
  v     text;
  n     int;
begin
  v := pg_get_functiondef('public.fn_fin_funis()'::regprocedure);
  if position('z85:' in v) > 0 then
    return;                                                -- já aplicada
  end if;
  for i in 1 .. array_length(v_old, 1) loop
    n := (length(v) - length(replace(v, v_old[i], ''))) / length(v_old[i]);
    if n <> 1 then
      raise exception 'z85: fn_fin_funis — trecho % encontrado % vez(es) (esperado 1): %', i, n, v_old[i];
    end if;
  end loop;
  for i in 1 .. array_length(v_old, 1) loop
    v := replace(v, v_old[i], v_new[i]);
  end loop;
  execute v;                                               -- mesmo cabeçalho vivo: stable, security definer, search_path ''
end $funis$;
revoke all on function public.fn_fin_funis() from public, anon;
grant execute on function public.fn_fin_funis() to authenticated;

do $compr$
declare
  v_old text[] := array[
      $o0$join fin.evento_produtos p on p.categoria = e.categoria$o0$,
      $o1$join fin.vw_transacoes t on t.produto_id = p.produto_id and$o1$,
      $o2$(p.papel = 'oferta' and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)$o2$];
  v_new text[] := array[
      $n0$join lateral (
      -- z85: produtos da categoria + produtos de ofertas ligadas a ESTE evento que a categoria não tem
      select ep.papel, ep.produto_id, true na_categoria
        from fin.evento_produtos ep
       where ep.categoria = e.categoria
      union all
      select distinct
             case when exists (select 1 from fin.evento_produtos p2 where p2.produto_id = t0.produto_id and p2.papel = 'ingresso')
                  and not exists (select 1 from fin.evento_produtos p2 where p2.produto_id = t0.produto_id and p2.papel = 'oferta')
                 then 'ingresso' else 'oferta' end,
             t0.produto_id, false
        from fin.evento_ofertas eo0
        join fin.hotmart_transacoes t0 on t0.oferta_codigo = eo0.oferta_codigo
       where eo0.evento_id = e.id
         and not exists (select 1 from fin.evento_produtos ep where ep.categoria = e.categoria and ep.produto_id = t0.produto_id)
    ) p on true$n0$,
      $n1$join fin.vw_transacoes t on t.produto_id = p.produto_id
     and (p.na_categoria or exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)) and$n1$,
      $n2$(p.papel = 'oferta' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
                                            and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))$n2$];
  v     text;
  n     int;
begin
  v := pg_get_functiondef('public.fn_fin_funil_compradores(bigint)'::regprocedure);
  if position('z85:' in v) > 0 then
    return;                                                -- já aplicada
  end if;
  for i in 1 .. array_length(v_old, 1) loop
    n := (length(v) - length(replace(v, v_old[i], ''))) / length(v_old[i]);
    if n <> 1 then
      raise exception 'z85: fn_fin_funil_compradores — trecho % encontrado % vez(es) (esperado 1): %', i, n, v_old[i];
    end if;
  end loop;
  for i in 1 .. array_length(v_old, 1) loop
    v := replace(v, v_old[i], v_new[i]);
  end loop;
  execute v;                                               -- mesmo cabeçalho vivo: stable, security definer, search_path ''
end $compr$;
revoke all on function public.fn_fin_funil_compradores(bigint) from public, anon;
grant execute on function public.fn_fin_funil_compradores(bigint) to authenticated;

-- ─── 2. Resolvedor: prazo das palavras-chave, ordem da sugestão, sck/ligar só com venda paga ─────────
-- Diferenças para a z83 (marcadas 'z85' no corpo): ev.inicio; sv só vendas pagas; kws.no_prazo; kwp; dec.kw_*;
-- cls.r_sck/r_nome/r_kw/r_ing; sinal 'fila:sem_venda_paga'; sug; detalhe.palavras.lider_sem_prazo; detalhe.sck.base.
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
-- z85: palavra-chave só vale para evento que começa até 1ª venda + 7 dias (ingresso isento: pré-venda);
--      sck conta só vendas PAGAS; nome/palavras/ingresso exigem >= 1 venda paga;
--      sugestão da fila: nome > janela única > ingresso > palavras > sck > janela mais curta.
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
    select e.id, e.nome, e.categoria, e.setor, e.inicio,
           coalesce(e.carrinho_inicio, e.inicio) ref_de,
           coalesce(e.carrinho_inicio, e.inicio) - 2 ja_de, e.venda_ate ja_ate,
           -- mesma expressão de evs.ing_de em public.fn_fin_trajetoria
           coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de,
           fin.oferta_normaliza(e.codigo) cod_n,
           fin.oferta_normaliza(e.nome) evn_n,
           fin.oferta_palavras(coalesce(e.nome, '') || ' ' || coalesce(e.codigo, '')) kw
      from fin.eventos e
  ), sv as (              -- por venda PAGA (z85): o evento das ações cujo sck_regex casa (só se for UM evento)
    select x.oc, x.tr, min(a.evento_id) ev_id
      from tx x
      join fin.acoes a on a.evento_id is not null and a.sck_regex is not null and x.sck ~* a.sck_regex
     where x.pago
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
           cardinality(array(select unnest(o.kw) intersect select unnest(e.kw))) score,
           -- z85: evento que começa depois da 1ª venda + 7 dias não é desta oferta (exceto ingresso: pré-venda)
           (o.eh_ingresso or e.inicio <= o.primeira + 7) no_prazo
      from ofr o
      join ev e on o.primeira between e.ref_de - 60 and e.ja_ate + 60
     where cardinality(o.kw) > 0 and cardinality(e.kw) > 0
  ), kwr as (             -- líder SEM o prazo: só para "nome contradiz" da janela/ingresso (regra de ligar da z83, intacta)
    select distinct on (k.oc) k.oc, k.id, k.nome, k.score,
           coalesce(lead(k.score) over (partition by k.oc order by k.score desc, k.id), 0) segundo
      from kws k
     where k.score > 0
     order by k.oc, k.score desc, k.id
  ), kwp as (             -- z85: líder COM o prazo: liga (auto:nome por palavras) e sugere
    select distinct on (k.oc) k.oc, k.id, k.nome, k.score,
           coalesce(lead(k.score) over (partition by k.oc order by k.score desc, k.id), 0) segundo
      from kws k
     where k.score > 0 and k.no_prazo
     order by k.oc, k.score desc, k.id
  ), dec as (
    select o.*, s.ev_id sck_ev, coalesce(s.n_sck, 0) n_sck,
           j.n_ev j_n, j.id j_id, j.n_dentro j_dentro, j.melhor j_melhor, j.cands j_cands,
           m.n_ev nm_n, m.id nm_id, m.cands nm_cands,
           g.id ing_id, g.n ing_n, g.cands ing_cands,
           kp.id kw_id, kp.nome kw_nome, coalesce(kp.score, 0) kw_score, coalesce(kp.segundo, 0) kw_segundo,
           case when k.score > k.segundo then k.id end kw_melhor,                        -- líder único sem prazo (contradiz)
           case when kp.score > kp.segundo then kp.id end kw_sug,                        -- líder único no prazo (sugere)
           (kp.score >= 2 and kp.score > kp.segundo) kw_liga,                           -- >= 2 e margem >= 1, no prazo
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
      left join kwp kp on kp.oc = o.oc
      left join pd on pd.oc = o.oc
  ), cls as (             -- cada regra vira um booleano (uma fonte só para decisao e sinal)
    select d.*,
           coalesce(d.contrato and coalesce(d.nm_n, 0) <> 1, false) r_contrato,
           coalesce(d.contrato and d.nm_n = 1, false) r_contrato_fila,
           coalesce(d.main or d.espalhada or d.duas_janelas, false) r_perene,
           -- z85: sck sobre vendas PAGAS (boleto em aberto não prende a oferta); nome/palavras/ingresso: >= 1 paga
           coalesce(d.n_pagas >= 3 and d.sck_ev is not null and d.n_sck >= 0.8 * d.n_pagas, false) r_sck,
           coalesce(d.nm_n = 1 and d.n_pagas >= 1, false) r_nome,
           coalesce(d.kw_liga and d.n_pagas >= 1, false) r_kw,
           coalesce(d.eh_ingresso and d.n_pagas >= 1 and d.ing_id is not null and d.ing_n >= 0.9 * d.n
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
                  case when c.n_pagas = 0 then 'fila:sem_venda_paga'                    -- z85
                       when c.eh_ingresso and c.ing_id is null then 'fila:sem_evento'
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
           -- z85: nome > janela única > ingresso > palavras (no prazo) > sck > janela mais curta
           coalesce(case when c.nm_n = 1 then c.nm_id end,
                    case when c.j_n = 1 then c.j_id end,
                    case when c.eh_ingresso then c.ing_id end,
                    c.kw_sug, c.sck_ev, c.j_melhor) sug,
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
              'sck', jsonb_build_object('evento_id', r.sck_ev, 'vendas', r.n_sck, 'base', 'pagas'),
              'janela', jsonb_build_object('n_eventos', coalesce(r.j_n, 0), 'candidatos', r.j_cands),
              'ingresso', jsonb_build_object('eh_ingresso', r.eh_ingresso, 'evento_id', r.ing_id, 'vendas', r.ing_n,
                                             'candidatos', r.ing_cands),
              'nome', jsonb_build_object('n_eventos', coalesce(r.nm_n, 0), 'candidatos', r.nm_cands,
                                         'fonte', case when v_tem_ofertas then 'fin.ofertas' else 'fin.ofertas ausente' end),
              'palavras', jsonb_build_object('oferta', to_jsonb(r.kw), 'evento_id', r.kw_id, 'evento', r.kw_nome,
                                             'comuns', r.kw_score, 'segundo', r.kw_segundo,
                                             'lider_sem_prazo', r.kw_melhor),
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

-- ─── 3. fn_fin_decidir_oferta: datas finitas e limitadas, categoria existente (pentest) ────────────────
-- Corpo = z82 §4b + o bloco 'z85 (pentest)'. Portão (gp_pode_ver_financeiro) inalterado.
create or replace function public.fn_fin_decidir_oferta(
  p_oferta    text,
  p_evento_id bigint  default null,
  p_criar     jsonb   default null,
  p_rejeitar  boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
-- z85: datas finitas, janela <= 120 dias, datas a <= 2 anos de hoje, categoria já existente (pentest).
declare
  v_uid  uuid := auth.uid();
  v_of   text := nullif(btrim(p_oferta), '');
  v_f    fin.oferta_evento_fila%rowtype;
  v_ev   bigint;
  v_lig  bigint;
  v_nome text;
  v_cat  text;
  v_ini  date;
  v_fim  date;
  v_ate  date;
  v_car  date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) or v_uid is null then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_of is null then
    raise exception 'Informe a oferta.' using errcode = '22023';
  end if;
  if (p_evento_id is not null)::int + (p_criar is not null)::int + coalesce(p_rejeitar, false)::int <> 1 then
    raise exception 'Escolha uma ação: evento existente, criar evento ou rejeitar.' using errcode = '22023';
  end if;

  select * into v_f from fin.oferta_evento_fila f where f.oferta_codigo = v_of for update;
  if not found then
    raise exception 'A oferta % não está na fila.', v_of using errcode = 'P0002';
  end if;
  if v_f.status <> 'pendente' then
    raise exception 'A oferta % já foi decidida (%).', v_of, v_f.status using errcode = '55000';
  end if;
  select eo.evento_id into v_lig from fin.evento_ofertas eo where eo.oferta_codigo = v_of;
  if v_lig is not null then
    raise exception 'A oferta % já está ligada ao evento %.', v_of, v_lig using errcode = '23505';
  end if;

  if coalesce(p_rejeitar, false) then
    update fin.oferta_evento_fila f
       set status = 'rejeitada', decidido_por = v_uid, decidido_em = now()
     where f.oferta_codigo = v_of;
    return jsonb_build_object('oferta', v_of, 'status', 'rejeitada');
  end if;

  if p_criar is not null then
    v_nome := nullif(btrim(p_criar ->> 'nome'), '');
    v_cat  := nullif(lower(btrim(p_criar ->> 'categoria')), '');
    v_ini  := nullif(btrim(p_criar ->> 'inicio'), '')::date;
    v_fim  := coalesce(nullif(btrim(p_criar ->> 'fim'), '')::date, v_ini);
    v_ate  := coalesce(nullif(btrim(p_criar ->> 'venda_ate'), '')::date, v_fim);
    v_car  := nullif(btrim(p_criar ->> 'carrinho_inicio'), '')::date;
    if v_nome is null or length(v_nome) > 200 then
      raise exception 'Nome do evento obrigatório (até 200 caracteres).' using errcode = '22023';
    end if;
    if v_cat is null or v_cat !~ '^[a-z][a-z0-9_]{1,39}$' then
      raise exception 'Categoria inválida (minúsculas, números e _).' using errcode = '22023';
    end if;
    -- z85 (pentest): categoria inédita vai por migration — aqui só a que já existe em evento ou no mapa de produtos
    if not exists (select 1 from fin.eventos e where e.categoria = v_cat)
       and not exists (select 1 from fin.evento_produtos ep where ep.categoria = v_cat) then
      raise exception 'Categoria % não existe: evento de categoria nova é cadastrado pela equipe técnica.', v_cat using errcode = '22023';
    end if;
    if v_ini is null or v_fim < v_ini or (v_car is not null and v_car > v_ate) then
      raise exception 'Datas do evento inválidas.' using errcode = '22023';
    end if;
    -- z85 (pentest): 'infinity' e janela sem limite faziam um evento engolir todas as vendas na trajetória
    if not (isfinite(v_ini) and isfinite(v_fim) and isfinite(v_ate) and (v_car is null or isfinite(v_car))) then
      raise exception 'Datas do evento inválidas (data infinita).' using errcode = '22023';
    end if;
    if v_ate < v_ini then
      raise exception 'Datas do evento inválidas (venda até antes do início).' using errcode = '22023';
    end if;
    if v_ate - coalesce(v_car, v_ini) > 120 then
      raise exception 'Janela de venda maior que 120 dias.' using errcode = '22023';
    end if;
    if least(v_ini, v_fim, v_ate, coalesce(v_car, v_ini)) < ((now() at time zone 'America/Sao_Paulo') - interval '2 years')::date
       or greatest(v_ini, v_fim, v_ate, coalesce(v_car, v_ini)) > ((now() at time zone 'America/Sao_Paulo') + interval '2 years')::date then
      raise exception 'Datas do evento fora de 2 anos para trás ou para frente.' using errcode = '22023';
    end if;

    insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, fonte, observacao, automatico)
    values (v_nome, v_cat, 'educacao', v_ini, v_fim, v_ate, v_car, 'confirmado na fila',
            'criado na fila de ofertas a partir da oferta ' || v_of || ' por ' || v_uid::text, true)
    on conflict (categoria, inicio) do nothing
    returning id into v_ev;
    if v_ev is null then
      raise exception 'Já existe evento % começando em %: escolha-o na lista.', v_cat, v_ini using errcode = '23505';
    end if;
  else
    select e.id into v_ev from fin.eventos e where e.id = p_evento_id;
    if v_ev is null then
      raise exception 'Evento % não existe.', p_evento_id using errcode = 'P0002';
    end if;
  end if;

  -- sem on conflict: se alguém ligou a oferta no meio, o índice único falha e a transação desfaz tudo (inclusive o evento criado)
  insert into fin.evento_ofertas (evento_id, oferta_codigo, observacao, origem, sinais, criado_em)
  values (v_ev, v_of, 'confirmado na fila', 'confirmado',
          coalesce(v_f.sinais, '{}'::jsonb) || jsonb_build_object('decidido_por', v_uid, 'evento_criado', p_criar is not null),
          now());

  update fin.oferta_evento_fila f
     set status = 'confirmada', decidido_por = v_uid, decidido_em = now()
   where f.oferta_codigo = v_of;

  return jsonb_build_object('oferta', v_of, 'status', 'confirmada', 'evento_id', v_ev, 'evento_criado', p_criar is not null);
end
$$;
revoke all on function public.fn_fin_decidir_oferta(text, bigint, jsonb, boolean) from public, anon;
grant execute on function public.fn_fin_decidir_oferta(text, bigint, jsonb, boolean) to authenticated;

-- ─── 4. fn_fin_board: search_path '' (pentest) — corpo e retorno idênticos aos da z75 ─────────────────
create or replace function public.fn_fin_board(p_turma text default null::text, p_produto text default null::text)
 RETURNS TABLE(origem text, contato_hm_id uuid, comprador_id uuid, aluno_id uuid, nome character varying, email character varying, turma text, turma_origem text, canal text, publico text, produto text, estagio_chave text, estagio_nome text, estagio_aba text, vendedor text, status_financeiro text, faixa text, pacote numeric, total_pago_bruto numeric, total_pago_liquido numeric, sinal_bruto numeric, saldo_pago_bruto numeric, saldo_a_pagar numeric, credito numeric, pago_pct numeric, vencimento date, dias_atraso integer, entrou_estagio_em timestamp with time zone, dias_no_estagio integer, solicitou_cancelamento boolean, cancelamento_em timestamp with time zone, cancelamento_efetivado_em timestamp with time zone, quitado_em timestamp with time zone, reembolso_em timestamp with time zone, reembolso_valor numeric, oferta_codigo text, oferta_enviada_em timestamp with time zone, ultimo_pagamento_em timestamp with time zone, aurum_excecao boolean, aurum_excecao_motivo text, aurum_rotulo_operador text, acao_nome text, acao_data timestamp with time zone, reuniao_resultado text, intencao_pagamento text, intencao_pagamento_obs text, reuniao_motivo_tipo text, reuniao_retomar_em date, pacote_regra numeric, divergencia_regra numeric, acao_regra text, captado_em date, captado_sck text, voltou_nome text, voltou_data timestamp with time zone, voltou_regra text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- z85: search_path vazio (pentest); corpo = z75, já todo qualificado (fin., cs., public.).
  select
    b.origem, b.contato_hm_id, b.comprador_id, b.aluno_id,
    fin.nome_do_card(b.nome, b.email, alu.nome)::character varying, b.email,
    coalesce(tu.turma, b.turma), b.turma_origem,
    case when b.canal is null or b.canal = 'Não classificado' then coalesce(a.acao_canal, b.canal) else b.canal end,
    b.publico, b.produto,
    e.chave as estagio_chave,
    b.estagio_nome, b.estagio_aba, b.vendedor,
    b.status_financeiro, b.faixa,
    b.pacote, b.total_pago_bruto, b.total_pago_liquido,
    b.sinal_bruto, b.saldo_pago_bruto,
    b.saldo_a_pagar, b.credito, b.pago_pct,
    b.vencimento, b.dias_atraso,
    b.entrou_estagio_em, b.dias_no_estagio,
    b.solicitou_cancelamento, b.cancelamento_em, b.cancelamento_efetivado_em,
    b.quitado_em, b.reembolso_em, b.reembolso_valor,
    b.oferta_codigo, b.oferta_enviada_em, b.ultimo_pagamento_em,
    b.aurum_excecao, b.aurum_excecao_motivo, b.aurum_rotulo_operador,
    a.acao_nome, a.acao_data,
    b.reuniao_resultado, b.intencao_pagamento, b.intencao_pagamento_obs,
    b.reuniao_motivo_tipo, b.reuniao_retomar_em,
    b.pacote_regra, b.divergencia_regra,
    a.acao_regra, a.captado_em, a.captado_sck,
    a.voltou_nome, a.voltou_data, a.voltou_regra
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  left join fin.vw_acao_card a on a.contato_hm_id = b.contato_hm_id
  left join fin.vw_turma_origem_card tu on tu.contato_hm_id = b.contato_hm_id
  left join public.thb_alunos alu on alu.id = b.aluno_id
  where coalesce(public.gp_pode_ver_financeiro(), false)
    and (p_turma is null or coalesce(tu.turma, b.turma) = p_turma)
    and (p_produto is null or b.origem = p_produto)
    -- card gêmeo (z37/z49): cadastro com alias para outro cadastro que já tem card do mesmo produto.
    -- Array de propósito (InitPlan): subconsulta aqui reavalia a view linha a linha (15 s medidos).
    and not (b.contato_hm_id = any (array(
      select cx.id from cs.hm_comprador_alias al
        join cs.contatos_hm cx on cx.comprador_id = al.comprador_id
        join cs.contatos_hm cc on cc.comprador_id = al.canonico_id and cc.produto = cx.produto)))
  order by b.saldo_a_pagar desc nulls last, b.nome;
$function$;

revoke all on function public.fn_fin_board(text, text) from public, anon;
grant execute on function public.fn_fin_board(text, text) to authenticated, service_role;

-- ─── 5. Conferência (falha a migration) ─────────────────────────────────────────────────────────────
do $confere$
declare
  v    text;
  v_c1 record;
begin
  -- 5.1 marcador, security definer, search_path '' e volatilidade de cada uma
  select string_agg(x.f, ', ') into v
    from (values ('public.fn_fin_funis()', 's'), ('public.fn_fin_funil_compradores(bigint)', 's'),
                 ('fin.resolver_ofertas_eventos(boolean,integer,text[])', 'v'),
                 ('public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)', 'v'), ('public.fn_fin_board(text,text)', 's')) x(f, vol)
    left join pg_proc p on p.oid = to_regprocedure(x.f)
   where p.oid is null or position('z85:' in p.prosrc) = 0 or not p.prosecdef or p.provolatile <> x.vol
      or p.proconfig is distinct from array['search_path=""'];
  if v is not null then
    raise exception 'z85: função fora do esperado (marcador/definer/search_path/volatilidade): %', v;
  end if;

  -- 5.2 permissões: ninguém via PUBLIC nem anon; authenticated só nas RPCs de tela; resolvedor só service_role
  select string_agg(x.f || ' ' || x.o, ', ') into v
    from (values
      ('public.fn_fin_funis()', 'anon', false), ('public.fn_fin_funis()', 'authenticated', true),
      ('public.fn_fin_funil_compradores(bigint)', 'anon', false), ('public.fn_fin_funil_compradores(bigint)', 'authenticated', true),
      ('fin.resolver_ofertas_eventos(boolean,integer,text[])', 'anon', false),
      ('fin.resolver_ofertas_eventos(boolean,integer,text[])', 'authenticated', false),
      ('fin.resolver_ofertas_eventos(boolean,integer,text[])', 'service_role', true),
      ('public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)', 'anon', false),
      ('public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)', 'authenticated', true),
      ('public.fn_fin_board(text,text)', 'anon', false), ('public.fn_fin_board(text,text)', 'authenticated', true),
      ('public.fn_fin_board(text,text)', 'service_role', true)
    ) x(f, o, deve)
   where has_function_privilege(x.o, x.f, 'execute') <> x.deve;
  if v is not null then
    raise exception 'z85: permissão fora do esperado: %', v;
  end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.oid in (to_regprocedure('public.fn_fin_funis()'), to_regprocedure('public.fn_fin_funil_compradores(bigint)'),
                   to_regprocedure('fin.resolver_ofertas_eventos(boolean,integer,text[])'),
                   to_regprocedure('public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)'),
                   to_regprocedure('public.fn_fin_board(text,text)'))
     and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0));
  if v is not null then
    raise exception 'z85: execução liberada para PUBLIC: %', v;
  end if;

  -- 5.3 C1 do resolvedor (verdade conhecida, só leitura): ligações manuais avaliadas como se não existissem.
  --     Aceite: nenhum erro grave e todas acertadas (ligar ou sugerir o evento certo) — "7/7" da z83.
  select count(*) total,
         count(*) filter (where r.evento_id = eo.evento_id) acerto,
         count(*) filter (where r.decisao = 'ligar' and r.evento_id <> eo.evento_id) erro_grave,
         string_agg(r.oferta_codigo || ':' || r.decisao || '->' || coalesce(r.evento_id::text, '-') || ' (certo ' || eo.evento_id || ')', ', ')
           filter (where r.evento_id is distinct from eo.evento_id) erradas
    into v_c1
    from fin.resolver_ofertas_eventos(false, 45, array(select x.oferta_codigo from fin.evento_ofertas x where x.origem = 'manual')) r
    join fin.evento_ofertas eo on eo.oferta_codigo = r.oferta_codigo;
  raise notice 'z85 C1: % de % acertadas, % erro grave', v_c1.acerto, v_c1.total, v_c1.erro_grave;
  -- ajuste do orquestrador (29/09): antes da z85 o C1 já era 7 de 9 (2 iam para fila/ignorar, nenhuma errada);
  -- o aceite é nunca ligar errado, não acertar 100%.
  if v_c1.erro_grave > 0 then
    raise exception 'z85: C1 do resolvedor caiu: % de % acertadas, % erro grave — %', v_c1.acerto, v_c1.total, v_c1.erro_grave, v_c1.erradas;
  end if;
end $confere$;

-- ─── RODAPÉ — consultas do orquestrador (NÃO fazem parte da aplicação) ─────────────────────────────────
-- Onde aparece <UUID-ADMIN>: id (auth.users) de um usuário com gp_pode_ver_financeiro() = true.
-- set_config(..., true) vale só na transação: mandar cada bloco INTEIRO numa chamada só.
--
-- G0) ENSAIO DAS GUARDAS sem aplicar nada: rodar só a seção 0 (do $guarda$ … end $guarda$;). Não escreve.
--     Se abortar em fn_fin_funis/fn_fin_funil_compradores: é um dos 2 trechos inferidos do cabeçalho.
--
-- F1) FOTO ANTES (rodar ANTES de aplicar; guardar a coluna "antes" — é um jsonb):
--   select set_config('request.jwt.claims', '{"sub":"<UUID-ADMIN>","role":"authenticated"}', true);
--   select jsonb_object_agg(f.evento_id, jsonb_build_object('v', f.ingressos + f.oferta_vendas, 'b', f.bruto)) antes,
--          sum(f.ingressos + f.oferta_vendas) vendas_total, sum(f.bruto) bruto_total, count(*) eventos
--     from public.fn_fin_funis() f;
--
-- F2) FOTO DEPOIS, por evento_id (colar o jsonb de F1 em <ANTES>): lista só os eventos que mudaram + total.
--   select set_config('request.jwt.claims', '{"sub":"<UUID-ADMIN>","role":"authenticated"}', true);
--   with a as (select k.key::bigint evento_id, (k.value->>'v')::int v, (k.value->>'b')::numeric b
--                from jsonb_each('<ANTES>'::jsonb) k),
--        d as (select f.evento_id, f.nome, f.categoria, f.ingressos + f.oferta_vendas v, f.bruto b from public.fn_fin_funis() f)
--   select coalesce(d.evento_id, a.evento_id) evento_id, d.nome, d.categoria,
--          a.v vendas_antes, d.v vendas_depois, a.b bruto_antes, d.b bruto_depois, d.b - a.b dif_bruto
--     from d full join a on a.evento_id = d.evento_id
--    where d.v is distinct from a.v or d.b is distinct from a.b
--   union all
--   select null, 'TOTAL', null, (select sum(v) from a), (select sum(v) from d), (select sum(b) from a), (select sum(b) from d),
--          (select sum(b) from d) - (select sum(b) from a)
--    order by 1 nulls last;
--   ACEITE: todo evento que mudou tem oferta ligada (fin.evento_ofertas) e a diferença bate com F3.
--   ATENÇÃO ao critério "total igual ou maior": o total PODE CAIR — venda de oferta ligada que a regra de data
--   contava em 2+ eventos (janelas sobrepostas da mesma categoria; ex.: 5064314 em holding_total e live_hm) passa a
--   contar 1 vez só. Queda no total = soma de F3."sai_de_outro_evento" menos o que continua contando no ligado.
--
-- F3) EXPLICAÇÃO por oferta ligada (independe das funções): onde a regra de DATA contava as vendas pagas × evento
--     ligado. "sai" = evento que perde a venda; linhas com evento_ligado fora da categoria = vendas que "entram".
--   with tx as (select t.oferta_codigo, t.produto_id, (t.aprovado_em at time zone 'America/Sao_Paulo')::date dia, t.valor_oferta
--                      * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end valor
--                 from fin.vw_transacoes t
--                where t.grupo = 'pago' and coalesce(t.recorrencia, 1) = 1 and t.email is not null)
--   select eo.evento_id evento_ligado, el.nome nome_ligado, e.id contava_por_data, e.nome, count(*) vendas, sum(x.valor) bruto,
--          case when e.id is null then 'entra (categoria sem o produto ou fora da janela)'
--               when e.id = eo.evento_id then 'fica' else 'sai (ia para outro evento)' end efeito
--     from fin.evento_ofertas eo
--     join fin.eventos el on el.id = eo.evento_id
--     join tx x on x.oferta_codigo = eo.oferta_codigo
--     left join fin.evento_produtos p on p.produto_id = x.produto_id and p.papel = 'oferta'
--     left join fin.eventos e on e.categoria = p.categoria and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate
--    group by 1,2,3,4,7 order by 1, 7;
--
-- R1) C1 do resolvedor (também roda dentro da migration, seção 5.3). ACEITE: 7/7, erro_grave = 0.
--   with v as (select eo.oferta_codigo, eo.evento_id from fin.evento_ofertas eo where eo.origem = 'manual')
--   select r.decisao, r.sinal, r.detalhe->>'regra' regra, count(*) total,
--          count(*) filter (where r.evento_id = v.evento_id) acerto,
--          count(*) filter (where r.decisao = 'ligar' and r.evento_id <> v.evento_id) erro_grave,
--          string_agg(r.oferta_codigo || '->' || coalesce(r.evento_id::text, '-') || ' (certo ' || v.evento_id || ')', ', ') ofertas
--     from fin.resolver_ofertas_eventos(false, 45, array(select oferta_codigo from fin.evento_ofertas where origem = 'manual')) r
--     join v on v.oferta_codigo = r.oferta_codigo
--    group by 1,2,3 order by 1,2,3;
--
-- R2) SUGESTÕES DA FILA recalculadas × gravadas (a gravada é a da z83 até o cron da próxima hora):
--   select r.oferta_codigo, f.sugestao_evento_id sugestao_z83, r.evento_id sugestao_z85, e.nome, e.inicio,
--          r.detalhe->>'primeira_venda' primeira_venda, r.detalhe->>'oferta_nome' oferta, r.sinal
--     from fin.resolver_ofertas_eventos(false, 120) r
--     left join fin.oferta_evento_fila f on f.oferta_codigo = r.oferta_codigo
--     left join fin.eventos e on e.id = r.evento_id
--    where r.decisao = 'fila'
--    order by (f.sugestao_evento_id is distinct from r.evento_id) desc, r.oferta_codigo;
--   Forma curta pedida: select oferta_codigo, evento_id sugestao_evento_id from fin.resolver_ofertas_eventos(false, 120) where decisao = 'fila';
--   ACEITE (Acelera de agosto): nenhuma oferta com 1ª venda antes de 21/09 sugerida/ligada ao 2º Encontro Acelera
--   (ev 96, 28/09) sem ser ingresso — tem de voltar vazia:
--   select r.oferta_codigo, r.decisao, r.sinal, r.detalhe->>'primeira_venda' primeira_venda, r.detalhe->>'oferta_nome'
--     from fin.resolver_ofertas_eventos(false, 120) r
--    where r.evento_id = 96 and (r.detalhe->>'primeira_venda')::date < date '2026-09-21'
--      and not (r.detalhe->'ingresso'->>'eh_ingresso')::boolean;
--   E o motivo, oferta a oferta (líder por palavras sem prazo × no prazo):
--   select r.oferta_codigo, r.detalhe->>'primeira_venda', r.detalhe->'palavras'->>'lider_sem_prazo' lider_sem_prazo,
--          r.detalhe->'palavras'->>'evento_id' lider_no_prazo, r.evento_id sugestao
--     from fin.resolver_ofertas_eventos(false, 120) r where r.decisao = 'fila' and r.detalhe->'palavras'->>'lider_sem_prazo' is not null;
--
-- R3) LIGAÇÕES JÁ GRAVADAS por palavras que a regra nova recusaria (só olhar; a migration não apaga nada):
--   select eo.oferta_codigo, eo.evento_id, e.nome, e.inicio, eo.sinais->>'primeira_venda' primeira_venda, eo.origem
--     from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id
--    where eo.origem = 'auto:nome' and eo.sinais->>'regra' = 'palavras'
--      and not coalesce((eo.sinais->'ingresso'->>'eh_ingresso')::boolean, false)
--      and e.inicio > (eo.sinais->>'primeira_venda')::date + 7;
--
-- K1) PENTEST sck/pagas: nenhuma ligação com 0 paga; auto:sck com >= 3 pagas e >= 80% das pagas. ACEITE: vazio.
--   select oferta_codigo, sinal, detalhe->>'n_pagas' pagas, detalhe->'sck' sck
--     from fin.resolver_ofertas_eventos(false, 120)
--    where decisao = 'ligar'
--      and ((detalhe->>'n_pagas')::int < 1
--        or (sinal = 'auto:sck' and ((detalhe->>'n_pagas')::int < 3
--                                    or (detalhe->'sck'->>'vendas')::int < 0.8 * (detalhe->>'n_pagas')::int)));
--   E as 12 ligações gravadas continuam com venda paga (medido pelo Kirad: 9 a 176):
--   select eo.origem, min((eo.sinais->>'n_pagas')::int), max((eo.sinais->>'n_pagas')::int), count(*)
--     from fin.evento_ofertas eo where eo.origem like 'auto:%' group by 1;
--
-- K2) PENTEST fn_fin_decidir_oferta: cada tentativa tem de falhar com 22023. O bloco sempre termina em exceção
--     (rollback total, nada fica gravado) e o relatório vem na mensagem de erro. Precisa de 1 oferta pendente.
--   do $k2$
--   declare
--     v_of  text;
--     v_out text := '';
--     c     record;
--   begin
--     perform set_config('request.jwt.claims', '{"sub":"<UUID-ADMIN>","role":"authenticated"}', true);
--     select f.oferta_codigo into v_of from fin.oferta_evento_fila f where f.status = 'pendente' limit 1;
--     if v_of is null then raise exception 'K2: nenhuma oferta pendente na fila para testar'; end if;
--     for c in select * from (values
--       ('inicio infinity',   '{"nome":"t","categoria":"clinica","inicio":"infinity"}'),
--       ('carrinho -infinity','{"nome":"t","categoria":"clinica","inicio":"2026-11-10","carrinho_inicio":"-infinity"}'),
--       ('venda_ate infinity','{"nome":"t","categoria":"clinica","inicio":"2026-11-10","fim":"2026-11-11","venda_ate":"infinity"}'),
--       ('janela 200 dias',   '{"nome":"t","categoria":"clinica","inicio":"2026-11-10","carrinho_inicio":"2026-04-24"}'),
--       ('venda_ate < inicio','{"nome":"t","categoria":"clinica","inicio":"2026-11-10","venda_ate":"2026-11-01"}'),
--       ('ano 2031',          '{"nome":"t","categoria":"clinica","inicio":"2031-01-10"}'),
--       ('ano 2019',          '{"nome":"t","categoria":"clinica","inicio":"2019-01-10"}'),
--       ('categoria inedita', '{"nome":"t","categoria":"zz_inedita_k2","inicio":"2026-11-10"}')) t(caso, j) loop
--       begin
--         perform public.fn_fin_decidir_oferta(v_of, null, c.j::jsonb, false);
--         v_out := v_out || c.caso || '=ACEITOU(FALHA DE SEGURANÇA); ';
--       exception when others then
--         v_out := v_out || c.caso || '=' || sqlstate || '; ';
--       end;
--     end loop;
--     raise exception 'K2 (rollback proposital): %', v_out;
--   end $k2$;
--   ACEITE: os 8 casos com 22023 e nenhum "ACEITOU". (42501 em todos = <UUID-ADMIN> sem permissão: trocar o uuid.)
--   Controle positivo (rodar À PARTE, com a lista trocada só por este caso — se rodar junto, a oferta vira
--   'confirmada' e os casos seguintes falham com 55000 em vez de 22023; o raise final desfaz tudo):
--       ('valido', '{"nome":"t","categoria":"clinica","inicio":"2026-11-10"}')  -> tem de aparecer "valido=ACEITOU".
--
-- K3) PENTEST fn_fin_board: search_path vazio e mesma saída.
--   select p.proconfig, p.prosecdef from pg_proc p where p.oid = 'public.fn_fin_board(text,text)'::regprocedure;  -- {search_path=""}, t
--   select set_config('request.jwt.claims', '{"sub":"<UUID-ADMIN>","role":"authenticated"}', true);
--   select count(*), sum(saldo_a_pagar) from public.fn_fin_board();   -- igual antes e depois
--
-- K4) Permissões (anon/PUBLIC fechados, também conferido na seção 5.2):
--   select p.oid::regprocedure, p.proacl from pg_proc p
--    where p.oid in ('public.fn_fin_funis()'::regprocedure, 'public.fn_fin_funil_compradores(bigint)'::regprocedure,
--                    'fin.resolver_ofertas_eventos(boolean,integer,text[])'::regprocedure,
--                    'public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)'::regprocedure,
--                    'public.fn_fin_board(text,text)'::regprocedure);
--
-- E) EXPLAIN (todas só leitura; resolvedor com p_gravar = false). Rodar ANTES e DEPOIS e colar os dois.
--    Como a função é plpgsql, o plano interno só aparece com auto_explain; o tempo total é o que se compara.
--   E1) select set_config('request.jwt.claims', '{"sub":"<UUID-ADMIN>","role":"authenticated"}', true);
--       explain (analyze, buffers) select * from public.fn_fin_funis();                        -- 2x (cache)
--   E1b) plano do corpo novo sem a função (mesma consulta do corpo, sem o portão): copiar o "with ev as (...) select ..."
--        de pg_get_functiondef('public.fn_fin_funis()'::regprocedure) e rodar com explain (analyze, buffers).
--   E2) select set_config('request.jwt.claims', '{"sub":"<UUID-ADMIN>","role":"authenticated"}', true);
--       explain (analyze, buffers) select * from public.fn_fin_funil_compradores(96);          -- 2º Encontro Acelera
--       explain (analyze, buffers) select * from public.fn_fin_funil_compradores(
--         (select id from fin.eventos where categoria = 'clinica' order by inicio desc limit 1));
--   E3) explain (analyze, buffers) select * from fin.resolver_ofertas_eventos(false);
--       explain (analyze, buffers) select * from fin.resolver_ofertas_eventos(false, 120);
--   E4) explain (analyze, buffers) select * from public.fn_fin_board();   -- com o set_config do admin; tempo ~ igual
--   Limite: E1 e E2 não podem piorar mais que 20% sobre o "antes"; E2 > 150 ms => índice em
--   fin.hotmart_transacoes (oferta_codigo) (create index concurrently, fora de migration).
--
-- ─── REVERSÃO de fn_fin_funis / fn_fin_funil_compradores (replace inverso sobre o corpo vivo) ────────────
-- do $reverte$
-- declare v text;
-- begin
--   v := pg_get_functiondef('public.fn_fin_funis()'::regprocedure);
--   if position($n0$(p.papel = 'oferta'   and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = x.oferta_codigo)
--                                         or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = x.oferta_codigo)
--                                             and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))$n0$ in v) = 0 then raise exception 'reverte fn_fin_funis: trecho 1 ausente'; end if;
--   v := replace(v, $n0$(p.papel = 'oferta'   and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = x.oferta_codigo)
--                                         or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = x.oferta_codigo)
--                                             and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))$n0$,
--               $o0$(p.papel = 'oferta'   and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)$o0$);
--   if position($n1$    union all
--     -- z85: venda de oferta ligada ao evento (fin.evento_ofertas) cujo produto a categoria do evento não tem
--     select e.id,
--            case when exists (select 1 from fin.evento_produtos p2 where p2.produto_id = x.produto_id and p2.papel = 'ingresso')
--                   and not exists (select 1 from fin.evento_produtos p2 where p2.produto_id = x.produto_id and p2.papel = 'oferta')
--                  then 'ingresso' else 'oferta' end,
--            x.*
--       from fin.evento_ofertas eo
--       join ev e on e.id = eo.evento_id
--       join tx x on x.oferta_codigo = eo.oferta_codigo
--      where not exists (select 1 from fin.evento_produtos p where p.categoria = e.categoria and p.produto_id = x.produto_id)
--   ), agg as ($n1$ in v) = 0 then raise exception 'reverte fn_fin_funis: trecho 2 ausente'; end if;
--   v := replace(v, $n1$    union all
--     -- z85: venda de oferta ligada ao evento (fin.evento_ofertas) cujo produto a categoria do evento não tem
--     select e.id,
--            case when exists (select 1 from fin.evento_produtos p2 where p2.produto_id = x.produto_id and p2.papel = 'ingresso')
--                   and not exists (select 1 from fin.evento_produtos p2 where p2.produto_id = x.produto_id and p2.papel = 'oferta')
--                  then 'ingresso' else 'oferta' end,
--            x.*
--       from fin.evento_ofertas eo
--       join ev e on e.id = eo.evento_id
--       join tx x on x.oferta_codigo = eo.oferta_codigo
--      where not exists (select 1 from fin.evento_produtos p where p.categoria = e.categoria and p.produto_id = x.produto_id)
--   ), agg as ($n1$,
--               $o1$  ), agg as ($o1$);
--   execute v;
--   v := pg_get_functiondef('public.fn_fin_funil_compradores(bigint)'::regprocedure);
--   if position($n0$join lateral (
--       -- z85: produtos da categoria + produtos de ofertas ligadas a ESTE evento que a categoria não tem
--       select ep.papel, ep.produto_id, true na_categoria
--         from fin.evento_produtos ep
--        where ep.categoria = e.categoria
--       union all
--       select distinct
--              case when exists (select 1 from fin.evento_produtos p2 where p2.produto_id = t0.produto_id and p2.papel = 'ingresso')
--                   and not exists (select 1 from fin.evento_produtos p2 where p2.produto_id = t0.produto_id and p2.papel = 'oferta')
--                  then 'ingresso' else 'oferta' end,
--              t0.produto_id, false
--         from fin.evento_ofertas eo0
--         join fin.hotmart_transacoes t0 on t0.oferta_codigo = eo0.oferta_codigo
--        where eo0.evento_id = e.id
--          and not exists (select 1 from fin.evento_produtos ep where ep.categoria = e.categoria and ep.produto_id = t0.produto_id)
--     ) p on true$n0$ in v) = 0 then raise exception 'reverte fn_fin_funil_compradores: trecho 1 ausente'; end if;
--   v := replace(v, $n0$join lateral (
--       -- z85: produtos da categoria + produtos de ofertas ligadas a ESTE evento que a categoria não tem
--       select ep.papel, ep.produto_id, true na_categoria
--         from fin.evento_produtos ep
--        where ep.categoria = e.categoria
--       union all
--       select distinct
--              case when exists (select 1 from fin.evento_produtos p2 where p2.produto_id = t0.produto_id and p2.papel = 'ingresso')
--                   and not exists (select 1 from fin.evento_produtos p2 where p2.produto_id = t0.produto_id and p2.papel = 'oferta')
--                  then 'ingresso' else 'oferta' end,
--              t0.produto_id, false
--         from fin.evento_ofertas eo0
--         join fin.hotmart_transacoes t0 on t0.oferta_codigo = eo0.oferta_codigo
--        where eo0.evento_id = e.id
--          and not exists (select 1 from fin.evento_produtos ep where ep.categoria = e.categoria and ep.produto_id = t0.produto_id)
--     ) p on true$n0$,
--               $o0$join fin.evento_produtos p on p.categoria = e.categoria$o0$);
--   if position($n1$join fin.vw_transacoes t on t.produto_id = p.produto_id
--      and (p.na_categoria or exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)) and$n1$ in v) = 0 then raise exception 'reverte fn_fin_funil_compradores: trecho 2 ausente'; end if;
--   v := replace(v, $n1$join fin.vw_transacoes t on t.produto_id = p.produto_id
--      and (p.na_categoria or exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)) and$n1$,
--               $o1$join fin.vw_transacoes t on t.produto_id = p.produto_id and$o1$);
--   if position($n2$(p.papel = 'oferta' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
--                                         or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
--                                             and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))$n2$ in v) = 0 then raise exception 'reverte fn_fin_funil_compradores: trecho 3 ausente'; end if;
--   v := replace(v, $n2$(p.papel = 'oferta' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
--                                         or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
--                                             and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))$n2$,
--               $o2$(p.papel = 'oferta' and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)$o2$);
--   execute v;
-- end $reverte$;
-- revoke all on function public.fn_fin_funis() from public, anon;
-- grant execute on function public.fn_fin_funis() to authenticated;
-- revoke all on function public.fn_fin_funil_compradores(bigint) from public, anon;
-- grant execute on function public.fn_fin_funil_compradores(bigint) to authenticated;
