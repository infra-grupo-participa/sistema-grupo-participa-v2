-- 20260928i — Financeiro "nada faltando" (pedido do João, 27/09/2026 noite).
-- Só leitura. Nada aqui grava em cs.*, public.* nem em hm_product_catalog: o catálogo alimenta o webhook,
-- e oferta nova nele passaria a gerar pagamento e card.
--
-- 1) fin.oferta_categoria(oferta, modo, valor): o que é cada venda, na ordem abaixo.
--    * SUBSCRIPTION → 'mensalidade'.
--    * Senão, a categoria de hm_product_catalog (sinal, diferenca, compra_cheia, renovacao, reserva…).
--    * Senão, se o valor da oferta for ≥ R$ 11 mil → 'compra_cheia_inferida' (HM e Aurum cheios custam de 13 a 30 mil).
--    * Senão, 'desconhecida' ("deixa a oferta como desconhecida", João).
--    Medido em 27/09: 1.464 vendas pagas de HM/Aurum estão fora do catálogo (R$ 18,4 mi) e nunca apareciam classificadas.
-- 2) fn_fin_board_hotmart(): o corpo de 20260928d IDÊNTICO, com 4 colunas no fim: outros_pagamentos, outros_valor,
--    outros_formas, outros_ultimo. São os pagamentos da pessoa na família que o card não mostra. Os valores do card
--    NÃO mudam.
-- 3) fn_fin_hotmart_pessoas(): o "caminho" (fluxo) usa fin.oferta_categoria no lugar do papel do produto. Antes, oferta
--    fora do catálogo aparecia como "principal"/"legado".
-- 4) fn_fin_prorata_hm(): entra TODO aluno de turma THB com vencimento, mesmo sem pagamento de HM na Hotmart
--    (pago 0 → diferença cheia). Medido em 27/09: 424 alunos vigentes ficavam de fora. A regra do cálculo não muda.

-- ─── 1. Categoria de uma venda ───────────────────────────────────────────────
create or replace function fin.oferta_categoria(p_oferta text, p_modo text, p_valor numeric)
returns text language sql stable set search_path = '' as $$
  select case
    when p_modo = 'SUBSCRIPTION' then 'mensalidade'
    else coalesce((select min(c.categoria::text) from public.hm_product_catalog c where c.offer_code = p_oferta),
                  case when p_valor >= 11000 then 'compra_cheia_inferida' else 'desconhecida' end)
  end
$$;
revoke all on function fin.oferta_categoria(text, text, numeric) from public, anon, authenticated;

-- ─── 2. Board × Hotmart + outros pagamentos ──────────────────────────────────
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
  outros_pagamentos int, outros_valor numeric, outros_formas text, outros_ultimo date)
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
         coalesce(ou.n, 0), coalesce(ou.valor, 0), ou.formas, ou.ult
    from card k
    cross join sinc
    left join nc n on n.pessoa = k.pessoa and n.origem = k.origem
    left join v on v.pessoa = k.pessoa and v.familia = k.origem
    left join fp on fp.pessoa = k.pessoa and fp.familia = k.origem
    left join dv on dv.pessoa = k.pessoa and dv.familia = k.origem
    left join bsh on bsh.contato_hm_id = k.contato_hm_id and bsh.origem = k.origem
    left join ass on ass.pessoa = k.pessoa and k.origem = 'HM'
    left join ou on ou.pessoa = k.pessoa and ou.familia = k.origem
   order by k.origem, coalesce(dv.valor_atual, 0) desc, coalesce(v.valor_falta, 0) desc;
end $$;
revoke all on function public.fn_fin_board_hotmart() from public, anon;
grant execute on function public.fn_fin_board_hotmart() to authenticated;

-- ─── 3. Pessoas: caminho com a categoria da venda ────────────────────────────
-- Recria a partir do corpo VIGENTE, trocando só a expressão do caminho (2 ocorrências, CTE flx).
do $do$
declare v text; n int;
begin
  v := pg_get_functiondef('public.fn_fin_hotmart_pessoas(text)'::regprocedure);
  n := (length(v) - length(replace(v, 'coalesce(y.categoria, y.papel_produto)', ''))) / length('coalesce(y.categoria, y.papel_produto)');
  if n <> 2 then raise exception 'fn_fin_hotmart_pessoas: esperava 2 ocorrências do caminho, achei %', n; end if;
  execute replace(v, 'coalesce(y.categoria, y.papel_produto)', 'fin.oferta_categoria(y.oferta_codigo, y.oferta_modo, y.valor_oferta)');
end $do$;

-- ─── 4. Pro rata do HM: todo aluno THB com vencimento ────────────────────────
create or replace function public.fn_fin_prorata_hm(p_valor_programa numeric default 15000)
returns table (
  pessoa_chave text, nome text, email text, turma text, vencimento date, meses_restantes int,
  pago_no_ciclo numeric, pagamentos_no_ciclo int, formas text, credito numeric, diferenca numeric,
  ultimo_pagamento date, tem_card boolean, contato_hm_id uuid, no_gps boolean)
language plpgsql stable security definer set search_path = ''
-- sem laço aninhado: com ele o planejador reavalia cic/crd por linha (34,8 s); com hash, 265 ms (27/09). Mantenha no cabeçalho —
-- um create or replace sem esta linha apaga o ajuste em silêncio (o teste de contrato cobra).
set enable_nestloop = off
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_valor_programa is null or p_valor_programa < 0 then
    raise exception 'Valor do programa inválido.' using errcode = '22023';
  end if;
  return query
  with hoje as (
    select (now() at time zone 'America/Sao_Paulo')::date d
  ), tx as materialized (
    -- vendas HM pagas, qualquer oferta; forma = fin.oferta_categoria (mensalidade, categoria do catálogo, inferida, desconhecida)
    select coalesce(i.pessoa_chave, 'e:' || t.email) pessoa, t.email, t.nome, t.valor_oferta, t.dia_aprovado, t.aprovado_em,
           fin.oferta_categoria(t.oferta_codigo, t.oferta_modo, t.valor_oferta) forma
      from fin.vw_transacoes t
      left join fin.identidade i on i.no = 'e:' || t.email
     where t.familia = 'HM' and t.grupo = 'pago' and t.email is not null
  ), pes as materialized (
    select x.pessoa,
           (array_agg(x.nome order by x.aprovado_em desc nulls last))[1] nome,
           (array_agg(x.email order by x.aprovado_em desc nulls last))[1] email,
           max(x.dia_aprovado) ult
      from tx x
     group by x.pessoa
  ), alu as materialized (
    -- aluno → pessoa pela mesma chave das transações (nó 'e:' da identidade, senão o próprio e-mail)
    select coalesce(i.pessoa_chave, 'e:' || lower(trim(a.email))) pessoa, a.id, a.nome, lower(trim(a.email)) email,
           a.data_expiracao::date venc, tt.codigo turma, tt.tipo
      from public.thb_alunos a
      left join fin.identidade i on i.no = 'e:' || lower(trim(a.email))
      left join public.thb_turmas tt on tt.id = a.turma_id
     where a.data_expiracao is not null and a.email is not null
  ), aluno as materialized (
    -- mais de um aluno na pessoa: vale o maior data_expiracao (turma, nome e e-mail do mesmo aluno)
    select l.pessoa, max(l.venc) venc,
           (array_agg(l.turma order by l.venc desc, l.id))[1] turma,
           (array_agg(l.nome order by l.venc desc, l.id))[1] nome,
           (array_agg(l.email order by l.venc desc, l.id))[1] email,
           bool_or(l.tipo = 'thb') thb,
           bool_or(exists (select 1 from gps.membros m where m.aluno_id = l.id or m.pessoa_aluno_id = l.id)) no_gps
      from alu l
     group by l.pessoa
  ), fc as materialized (
    -- vendas do ciclo atual por forma: dia_aprovado em [venc − 12 meses − 60 dias, venc]
    select x.pessoa, x.forma, count(*)::int n, coalesce(sum(x.valor_oferta), 0) v
      from tx x
      join aluno al on al.pessoa = x.pessoa
     where x.dia_aprovado between (al.venc - interval '12 months')::date - 60 and al.venc
     group by x.pessoa, x.forma
  ), cic as materialized (
    select f.pessoa, sum(f.n)::int n, sum(f.v) pago,
           string_agg(f.n || ' ' || case f.forma
               when 'mensalidade'  then case when f.n = 1 then 'mensalidade' else 'mensalidades' end
               when 'renovacao'    then case when f.n = 1 then 'renovação' else 'renovações' end
               when 'sinal'        then case when f.n = 1 then 'sinal' else 'sinais' end
               when 'diferenca'    then case when f.n = 1 then 'saldo' else 'saldos' end
               when 'saldo'        then case when f.n = 1 then 'saldo' else 'saldos' end
               when 'compra_cheia' then case when f.n = 1 then 'compra cheia' else 'compras cheias' end
               when 'compra_cheia_inferida' then case when f.n = 1 then 'compra cheia (inferida)' else 'compras cheias (inferidas)' end
               when 'desconhecida' then case when f.n = 1 then 'oferta desconhecida' else 'ofertas desconhecidas' end
               else coalesce(f.forma, 'outra') end,
             ' · ' order by f.n desc, f.forma) formas
      from fc f
     group by f.pessoa
  ), base as materialized (
    -- quem entra: tem venda HM paga e vencimento, OU é aluno de turma THB com vencimento (mesmo sem venda na Hotmart)
    select al.pessoa, coalesce(p.nome, al.nome) nome, coalesce(p.email, al.email) email, al.turma, al.venc, p.ult,
           al.no_gps
      from aluno al
      left join pes p on p.pessoa = al.pessoa
     where p.pessoa is not null or al.thb
  ), email_pessoa as materialized (
    select distinct x.pessoa, x.email from tx x
    union
    select l.pessoa, l.email from alu l
    union
    select i.pessoa_chave, substr(i.no, 3) from fin.identidade i
     where i.no like 'e:%' and i.pessoa_chave in (select b.pessoa from base b)
  ), crd as materialized (
    select e.pessoa, (array_agg(b.contato_hm_id order by b.saldo_a_pagar desc nulls last))[1] contato_hm_id
      from email_pessoa e
      join public.compradores c on lower(trim(c.email)) = e.email
      join cs.vw_fin_board b on b.comprador_id = c.id and b.origem = 'HM'
     where e.pessoa in (select b2.pessoa from base b2)
     group by e.pessoa
  ), calc as (
    select b.pessoa, b.nome, b.email, b.turma, b.venc, b.ult, b.no_gps,
           coalesce(ci.pago, 0) pago, coalesce(ci.n, 0) n, ci.formas,
           case when b.venc > h.d
                then (extract(year from age(b.venc::timestamp, h.d::timestamp)) * 12
                      + extract(month from age(b.venc::timestamp, h.d::timestamp)))::int
                else 0 end meses
      from base b
      cross join hoje h
      left join cic ci on ci.pessoa = b.pessoa
  )
  select fin.chave_opaca(k.pessoa), k.nome, k.email, k.turma, k.venc, k.meses,
         k.pago, k.n, k.formas,
         trunc(k.pago * k.meses / 12, 2),
         greatest(p_valor_programa - trunc(k.pago * k.meses / 12, 2), 0),
         k.ult, cr.pessoa is not null, cr.contato_hm_id, coalesce(k.no_gps, false)
    from calc k
    left join crd cr on cr.pessoa = k.pessoa
   order by k.venc, k.nome;
end $$;
revoke all on function public.fn_fin_prorata_hm(numeric) from public, anon;
grant execute on function public.fn_fin_prorata_hm(numeric) to authenticated;
alter function public.fn_fin_prorata_hm(numeric) set enable_nestloop = off;
