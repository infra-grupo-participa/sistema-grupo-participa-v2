-- 20260928c — Board × espelho Hotmart: 1 linha por card de cs.vw_fin_board (HM e AURUM).
--
-- Propósito: mostrar ao lado de cada card o que a Hotmart diz daquela pessoa naquele produto
-- (pago, taxa, coprodução, líquido, juros, parcelas, forma, último pagamento, dívida, estornos)
-- e onde o board e a Hotmart discordam. Só leitura, uma consulta set-based (sem N+1).
--
-- Decisões fechadas:
--   * É SÓ AVISO. Nenhum valor do board muda; nada aqui grava em cs.* nem em fin.*.
--   * Casamento: card → public.compradores.email → 'e:'||lower(trim(email)) → fin.identidade.pessoa_chave
--     → todos os nós 'e:' da pessoa → fin.vw_transacoes com familia = card.origem.
--   * Valores (vendas_pagas … forma_pagamento_principal, último pagamento, estornos): só ofertas com
--     categoria do catálogo em ('sinal','diferenca','compra_cheia') — o escopo do board.
--   * Dívida: fin.parcelas_devidas(origem) da pessoa (todas as ofertas da família, mesma regra de
--     fn_fin_hotmart_pessoas).
--   * falta_no_board: venda paga no escopo cuja transação não existe em cs.hm_pagamentos.
--     board_sem_hotmart: cs.hm_pagamentos do comprador do card, origem='hotmart', roteado ao produto
--     do card por cs.fn_hm_pagamento_do_produto, cuja transação o espelho não tem ou dá como estornada.
--   * diverge: HM = falta_no_board > 0 or board_sem_hotmart > 0; AURUM = null (a planilha do Aurum não
--     tem transação); card sem pessoa = null.
--   * Card sem pessoa: encontrado = false, números 0 / null.
--   * Não devolve e-mail, documento, telefone nem nome. Pessoa sai só como fin.chave_opaca.
--   * Valores são por pessoa × família: cards_da_pessoa > 1 = a mesma pessoa tem mais de um card
--     no mesmo produto e os números se repetem neles (não somar coluna sem dividir).

drop function if exists public.fn_fin_board_hotmart();
create function public.fn_fin_board_hotmart()
returns table (
  contato_hm_id uuid, origem text, encontrado boolean, pessoa_chave text, cards_da_pessoa int,
  vendas_pagas int, pago_bruto numeric, taxa_hotmart numeric, coproducao numeric, liquido numeric,
  cobrado_cliente numeric, juros numeric, parcelas_max int, forma_pagamento_principal text,
  ultimo_pagamento_em date, ultimo_pagamento_valor numeric,
  parcelas_devidas int, valor_devido numeric, devido_antigo numeric,
  estornos int, valor_estornado numeric,
  falta_no_board int, valor_falta_no_board numeric, board_sem_hotmart int,
  diverge boolean, sincronizado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with card as (
    select b.contato_hm_id, b.origem, b.comprador_id, i.pessoa_chave pessoa
      from cs.vw_fin_board b
      left join public.compradores c on c.id = b.comprador_id
      left join fin.identidade i on i.no = 'e:' || lower(trim(c.email))
  ), nc as (
    select k.pessoa, k.origem, count(*)::int n from card k where k.pessoa is not null group by k.pessoa, k.origem
  ), em as (
    -- todos os e-mails da pessoa, por família do card
    select distinct n.pessoa, n.origem familia, substr(i.no, 3) email
      from nc n
      join fin.identidade i on i.pessoa_chave = n.pessoa and i.no like 'e:%'
  ), tx as (
    select e.pessoa, e.familia, t.transacao, t.grupo, t.metodo, t.parcelas, t.valor_oferta, t.valor_cobrado,
           t.juros, t.taxa_hotmart, t.liquido, t.aprovado_em, t.dia_aprovado,
           not exists (select 1 from cs.hm_pagamentos hp where hp.transacao = t.transacao) sem_board
      from em e
      join fin.vw_transacoes t on t.email = e.email and t.familia = e.familia
     where t.grupo in ('pago','estornado')
       and exists (select 1 from public.hm_product_catalog cat
                    where cat.offer_code = t.oferta_codigo and cat.categoria in ('sinal','diferenca','compra_cheia'))
  ), v as (
    select x.pessoa, x.familia,
           count(*) filter (where x.grupo = 'pago')::int pagas,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) bruto,
           coalesce(sum(x.taxa_hotmart) filter (where x.grupo = 'pago'), 0) taxa,
           greatest(coalesce(sum(x.valor_oferta - coalesce(x.taxa_hotmart, 0) - x.liquido) filter (where x.grupo = 'pago'), 0), 0) copro,
           coalesce(sum(x.liquido) filter (where x.grupo = 'pago'), 0) liq,
           coalesce(sum(x.valor_cobrado) filter (where x.grupo = 'pago'), 0) cobrado,
           coalesce(sum(x.juros) filter (where x.grupo = 'pago'), 0) juros,
           max(x.parcelas) filter (where x.grupo = 'pago') parcelas_max,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ult_em,
           (array_agg(x.valor_oferta order by x.aprovado_em desc nulls last) filter (where x.grupo = 'pago'))[1] ult_valor,
           count(*) filter (where x.grupo = 'estornado')::int estornos,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'estornado'), 0) estornado,
           count(*) filter (where x.grupo = 'pago' and x.sem_board)::int falta,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago' and x.sem_board), 0) valor_falta
      from tx x
     group by x.pessoa, x.familia
  ), fp as (
    -- método mais frequente nas vendas pagas do escopo; empate → o mais recente
    select distinct on (m.pessoa, m.familia) m.pessoa, m.familia, m.metodo
      from (select y.pessoa, y.familia, y.metodo, count(*) n, max(y.aprovado_em) ult
              from tx y where y.grupo = 'pago' and y.metodo is not null
             group by y.pessoa, y.familia, y.metodo) m
     order by m.pessoa, m.familia, m.n desc, m.ult desc nulls last
  ), dv as (
    select 'HM'::text familia, d.pessoa, d.n_atual, d.valor_atual, d.valor_antigo from fin.parcelas_devidas('HM') d
    union all
    select 'AURUM'::text, d.pessoa, d.n_atual, d.valor_atual, d.valor_antigo from fin.parcelas_devidas('AURUM') d
  ), bsh as (
    select k.contato_hm_id, k.origem, count(*)::int n
      from card k
      join cs.hm_pagamentos p on p.comprador_id = k.comprador_id and p.origem = 'hotmart'
     where cs.fn_hm_pagamento_do_produto(p.oferta_codigo, k.origem)
       and (not exists (select 1 from fin.vw_transacoes t where t.transacao = p.transacao)
            or exists (select 1 from fin.vw_transacoes t where t.transacao = p.transacao and t.grupo = 'estornado'))
     group by k.contato_hm_id, k.origem
  ), sinc as (
    select max(h.atualizado_em) em from fin.hotmart_transacoes h
  )
  select k.contato_hm_id, k.origem, k.pessoa is not null,
         case when k.pessoa is not null then fin.chave_opaca(k.pessoa) end,
         coalesce(n.n, 0),
         coalesce(v.pagas, 0), coalesce(v.bruto, 0), coalesce(v.taxa, 0), coalesce(v.copro, 0), coalesce(v.liq, 0),
         coalesce(v.cobrado, 0), coalesce(v.juros, 0), v.parcelas_max, fp.metodo,
         v.ult_em, v.ult_valor,
         coalesce(dv.n_atual, 0), coalesce(dv.valor_atual, 0), coalesce(dv.valor_antigo, 0),
         coalesce(v.estornos, 0), coalesce(v.estornado, 0),
         coalesce(v.falta, 0), coalesce(v.valor_falta, 0), coalesce(bsh.n, 0),
         case when k.origem = 'HM' and k.pessoa is not null
              then coalesce(v.falta, 0) > 0 or coalesce(bsh.n, 0) > 0 end,
         sinc.em
    from card k
    cross join sinc
    left join nc n on n.pessoa = k.pessoa and n.origem = k.origem
    left join v on v.pessoa = k.pessoa and v.familia = k.origem
    left join fp on fp.pessoa = k.pessoa and fp.familia = k.origem
    left join dv on dv.pessoa = k.pessoa and dv.familia = k.origem
    left join bsh on bsh.contato_hm_id = k.contato_hm_id and bsh.origem = k.origem
   order by k.origem, coalesce(dv.valor_atual, 0) desc, coalesce(v.valor_falta, 0) desc;
end $$;
revoke all on function public.fn_fin_board_hotmart() from public, anon;
grant execute on function public.fn_fin_board_hotmart() to authenticated;

-- ─── Aceite (rodar depois de aplicar 20260928b e 20260928c, logado com gp_pode_ver_financeiro) ───
-- Em sessão de service/postgres a guarda gp_pode_ver_financeiro() barra: use um JWT de financeiro
-- (set local role authenticated; set local request.jwt.claims = '{"sub":"<uuid financeiro>"}').
/*
-- 1) Dívida por família (esperado: HM 49 / 87.031,99 / 156.146,14 · AURUM 7 / 30.626,35 / 339.085,73)
--    1ª query como postgres (fin.parcelas_devidas é interna, sem grant a authenticated); 2ª com o JWT.
select f, sum(n_atual) n_atual, sum(valor_atual) valor_atual, sum(valor_antigo) valor_antigo
  from unnest(array['HM','AURUM']) f, fin.parcelas_devidas(f) group by f;
select f, sum(parcelas_atrasadas), sum(valor_atrasado), sum(valor_atrasado_antigo)
  from unnest(array['HM','AURUM']) f, public.fn_fin_hotmart_pessoas(f) group by f;

-- 2) Fechamento oferta = taxa + coprodução + líquido (esperado ≈ 0 por família)
select f, sum(valor_pago - taxa_hotmart - coproducao - liquido) resto
  from unnest(array['HM','AURUM','ACELERA']) f, public.fn_fin_hotmart_pessoas(f) group by f;

-- 3) Juros das pessoas = juros do faturamento (período inteiro; com null,null o faturamento
--    cobre só os últimos 90 dias). Diferença residual possível: transação sem e-mail (pessoas exige e-mail).
select f,
       (select sum(juros) from public.fn_fin_hotmart_pessoas(f)) juros_pessoas,
       (select sum(juros) from public.fn_fin_hotmart_faturamento(f, date '2015-01-01', current_date)) juros_faturamento
  from unnest(array['HM','AURUM','ACELERA']) f;

-- 4) Board (esperado: 328 = HM 286 / AURUM 42; 0 encontrado=false; diverge null em todo AURUM;
--    valor_falta_no_board HM ≥ 19.024,76 — somado por pessoa, sem repetir card da mesma pessoa)
select origem, count(*) cards, count(*) filter (where not encontrado) sem_pessoa,
       count(*) filter (where diverge is not null) diverge_nao_nulo,
       count(*) filter (where diverge) divergentes,
       sum(valor_falta_no_board / nullif(cards_da_pessoa, 0)) valor_falta_no_board,
       sum(board_sem_hotmart) board_sem_hotmart
  from public.fn_fin_board_hotmart() group by rollup (origem);

-- 5) Custo (esperado < 500 ms cada)
explain (analyze, buffers) select * from public.fn_fin_board_hotmart();
explain (analyze, buffers) select * from public.fn_fin_hotmart_pessoas('HM');
explain (analyze, buffers) select * from public.fn_fin_hotmart_pessoas('AURUM');
*/
