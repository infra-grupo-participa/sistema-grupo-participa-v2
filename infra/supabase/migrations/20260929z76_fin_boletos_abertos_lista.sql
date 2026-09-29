-- 20260929z76 — Lista dos boletos/Pix em aberto por card (alerta: aluno com sinal pago gera boleto do HM CHEIO
-- e pagaria a mais). fn_fin_board_hotmart devolvia só a soma (boleto_aberto_n/valor) e a categoria/método do mais
-- recente; agora ganha no FIM do RETURNS TABLE `boletos_abertos jsonb` = lista ordenada por pedido_em desc de
--   {valor, categoria (hm_product_catalog; null fora do catálogo), rotulo (fin.oferta_categoria), oferta_codigo, metodo, pedido_em (date)}
-- com o MESMO filtro do CTE bol (grupo em_aberto, últimos 30 dias, família do card). As 5 colunas boleto_aberto_* e
-- todas as demais ficam idênticas. Só leitura.
--
-- Corpo = 20260928o (create) + 20260928o2 (tel_card, aplicado ali por replace) + 20260928z46 (periodo_do_card no CTE tx,
-- aplicado ali por replace) já incorporados, para a migração ser um create completo e não depender de replace.
-- z49 não toca esta função (só fn_fin_board). CONFERIR contra pg_get_functiondef vivo antes de aplicar.
--
-- Tipo de retorno muda → drop + create. Permissão: função nova nasce executável por PUBLIC → revoke explícito.
-- Grants vivos antes: authenticated, postgres (dono), service_role. Mantidos.
-- Prova (rodar após aplicar, em transação com rollback se preferir):
--   explain (analyze, buffers) select * from public.fn_fin_board_hotmart();   -- referência: ≈ 1,0 s (z52)
--   select count(*) filter (where boleto_aberto_n > 0) cards_com_boleto,
--          count(*) filter (where jsonb_array_length(coalesce(boletos_abertos, '[]'::jsonb)) = boleto_aberto_n) lista_bate
--     from public.fn_fin_board_hotmart();   -- lista_bate tem de ser = total de linhas

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
  diverge boolean, sincronizado_em timestamptz,
  assinatura_mensalidades int, assinatura_valor numeric, assinatura_de date, assinatura_ate date,
  assinatura_ativa boolean,
  outros_pagamentos int, outros_valor numeric, outros_formas text, outros_ultimo date,
  telefone text, boleto_aberto_n int, boleto_aberto_valor numeric, boleto_aberto_em date,
  boleto_aberto_categoria text, boleto_aberto_metodo text,
  boletos_abertos jsonb)
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
       -- periodo_do_card (z46): compra anterior ao 1º pagamento do card é turma de origem, não falta
       and coalesce(t.aprovado_em, t.pedido_em) >= coalesce(
             (select min(hp.pago_em) from card k2 join cs.hm_pagamentos hp on hp.comprador_id = k2.comprador_id
               where k2.pessoa = e.pessoa and k2.origem = e.familia
                 and cs.fn_hm_pagamento_do_produto(hp.oferta_codigo, k2.origem)) - interval '1 day',
             '-infinity'::timestamptz)
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
  ), ass as (
    -- 20260928d: assinatura HM (mensalidades) — contrato à parte, fora do escopo de v/tx
    select e.pessoa, count(*)::int n, coalesce(sum(t.valor_oferta), 0) valor,
           min(t.dia_aprovado) de, max(t.dia_aprovado) ate
      from em e
      join fin.vw_transacoes t on t.email = e.email and t.familia = 'HM'
     where e.familia = 'HM' and t.grupo = 'pago' and t.oferta_modo = 'SUBSCRIPTION'
     group by e.pessoa
  ), ou as (
    -- 20260928i: pagamentos da família que o card NÃO mostra (renovação, complemento, oferta fora do catálogo…).
    -- Fora: o escopo do card (sinal/diferenca/compra_cheia, CTE tx) e a assinatura HM (CTE ass). No AURUM a
    -- mensalidade entra aqui (não há bloco de assinatura). Categoria: fin.oferta_categoria ('desconhecida' quando não dá).
    select e.pessoa, e.familia, count(*)::int n, coalesce(sum(t.valor_oferta), 0) valor, max(t.dia_aprovado) ult,
           string_agg(distinct fin.oferta_categoria(t.oferta_codigo, t.oferta_modo, t.valor_oferta), ' · ') formas
      from em e
      join fin.vw_transacoes t on t.email = e.email and t.familia = e.familia
     where t.grupo = 'pago'
       and not (e.familia = 'HM' and t.oferta_modo is not distinct from 'SUBSCRIPTION')
       and not exists (select 1 from public.hm_product_catalog cat
                        where cat.offer_code = t.oferta_codigo and cat.categoria in ('sinal','diferenca','compra_cheia'))
     group by e.pessoa, e.familia
  ), bol as (
    -- 20260928o: boleto/Pix gerado e ainda não pago (grupo em_aberto) nos últimos 30 dias, da família do card.
    -- A Hotmart não informa o vencimento do boleto: a tela mostra quando foi gerado e há quantos dias.
    -- z76: + lista (jsonb) de todos eles, mais recente primeiro. categoria = a do catálogo (null fora dele; subselect
    -- escalar min() como fin.oferta_categoria, para uma oferta duplicada no catálogo não multiplicar o boleto);
    -- rotulo = fin.oferta_categoria (mensalidade / catálogo / inferida / desconhecida).
    select e.pessoa, e.familia, count(*)::int n, coalesce(sum(t.valor_oferta), 0) valor, max(t.dia_pedido) em,
           (array_agg(fin.oferta_categoria(t.oferta_codigo, t.oferta_modo, t.valor_oferta) order by t.pedido_em desc))[1] categoria,
           (array_agg(t.metodo order by t.pedido_em desc))[1] metodo,
           jsonb_agg(jsonb_build_object(
             'valor', t.valor_oferta,
             'categoria', (select min(c.categoria::text) from public.hm_product_catalog c where c.offer_code = t.oferta_codigo),
             'rotulo', fin.oferta_categoria(t.oferta_codigo, t.oferta_modo, t.valor_oferta),
             'oferta_codigo', t.oferta_codigo,
             'metodo', t.metodo,
             'pedido_em', t.dia_pedido) order by t.pedido_em desc) lista
      from em e
      join fin.vw_transacoes t on t.email = e.email and t.familia = e.familia
     where t.grupo = 'em_aberto' and t.dia_pedido >= (now() at time zone 'America/Sao_Paulo')::date - 30
     group by e.pessoa, e.familia
  ), tel as (
    -- telefone mais recente que a pessoa informou na Hotmart (qualquer e-mail dela)
    select distinct on (e.pessoa) e.pessoa, h.comprador_telefone
      from em e
      join fin.hotmart_transacoes h on lower(trim(h.comprador_email)) = e.email
     where h.comprador_telefone is not null
     order by e.pessoa, h.pedido_em desc
  ), tel_card as (
    -- sem telefone na Hotmart: o do cadastro do comprador do card, senão o da base de alunos
    select k.contato_hm_id,
           coalesce(nullif(trim(cp.telefone), ''),
                    (select nullif(trim(a.telefone), '') from public.thb_alunos a
                      where lower(trim(a.email)) = lower(trim(cp.email)) and nullif(trim(a.telefone), '') is not null limit 1)) telefone
      from card k
      join public.compradores cp on cp.id = k.comprador_id
  ), sinc as (
    select max(h.atualizado_em) em, (now() at time zone 'America/Sao_Paulo')::date hoje from fin.hotmart_transacoes h
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
         sinc.em,
         coalesce(ass.n, 0), coalesce(ass.valor, 0), ass.de, ass.ate,
         case when k.origem = 'HM' and k.pessoa is not null
              then coalesce(ass.ate >= sinc.hoje - 45, false) and coalesce(dv.n_atual, 0) = 0 end,
         coalesce(ou.n, 0), coalesce(ou.valor, 0), ou.formas, ou.ult,
         -- LGPD (regra da 0819g): telefone completo só para gp_pode_ver_cpf(); o resto vê ···1234
         case when coalesce(public.gp_pode_ver_cpf(), false) then coalesce(tl.comprador_telefone, tc.telefone)
              when coalesce(tl.comprador_telefone, tc.telefone) is not null
                then '···' || right(regexp_replace(coalesce(tl.comprador_telefone, tc.telefone), '\D', '', 'g'), 4) end,
         coalesce(bo.n, 0), coalesce(bo.valor, 0), bo.em, bo.categoria, bo.metodo,
         bo.lista
    from card k
    cross join sinc
    left join nc n on n.pessoa = k.pessoa and n.origem = k.origem
    left join v on v.pessoa = k.pessoa and v.familia = k.origem
    left join fp on fp.pessoa = k.pessoa and fp.familia = k.origem
    left join dv on dv.pessoa = k.pessoa and dv.familia = k.origem
    left join bsh on bsh.contato_hm_id = k.contato_hm_id and bsh.origem = k.origem
    left join ass on ass.pessoa = k.pessoa and k.origem = 'HM'
    left join ou on ou.pessoa = k.pessoa and ou.familia = k.origem
    left join bol bo on bo.pessoa = k.pessoa and bo.familia = k.origem
    left join tel tl on tl.pessoa = k.pessoa
    left join tel_card tc on tc.contato_hm_id = k.contato_hm_id
   order by k.origem, coalesce(dv.valor_atual, 0) desc, coalesce(v.valor_falta, 0) desc;
end $$;

revoke all on function public.fn_fin_board_hotmart() from public, anon;
grant execute on function public.fn_fin_board_hotmart() to authenticated, service_role;
