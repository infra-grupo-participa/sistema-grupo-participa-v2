-- 20260928d — Assinatura HM à parte no board + pro rata do HM (decisões do João, 27/09/2026).
--
-- Só leitura. Nada aqui grava em cs.*, fin.* ou public.*.
--
-- 1) fn_fin_board_hotmart(): corpo de 20260928c IDÊNTICO + 5 colunas NO FIM (por pessoa × família HM):
--    assinatura_mensalidades, assinatura_valor, assinatura_de, assinatura_ate, assinatura_ativa.
--    * Assinatura HM = vendas pagas da família HM com oferta_modo = 'SUBSCRIPTION' (todo o 3507214
--      "HM antigo" e as ofertas "reserva ~2k" do 5064314). É contrato à parte: NÃO entra em
--      vendas_pagas/pago_bruto/taxa/líquido do card, que continuam só nas categorias
--      sinal/diferenca/compra_cheia (escopo do board, sem mudança).
--    * assinatura_valor = soma de valor_oferta (preço da oferta, sem juros do cliente).
--    * assinatura_de/ate = 1ª e última mensalidade paga (dia_aprovado, America/Sao_Paulo).
--    * assinatura_ativa = última mensalidade paga há ≤ 45 dias E fin.parcelas_devidas('HM').n_atual = 0
--      para a pessoa (a dívida conta TODAS as ofertas HM, mesma regra da coluna parcelas_devidas).
--      HM com pessoa e sem mensalidade = false. AURUM e card sem pessoa: 0 / 0 / null / null / null.
--
-- 2) fn_fin_prorata_hm(p_valor_programa default 15000): 1 linha por pessoa com thb_alunos.data_expiracao
--    e ao menos 1 venda HM paga no espelho.
--    * Pessoa = componente de fin.identidade (transação sem nó = a própria 'e:<email>', como em
--      fin.parcelas_devidas). thb_alunos casa pelo e-mail de QUALQUER nó 'e:' da pessoa (e pelos e-mails
--      das transações HM dela), com lower(trim(email)) — a expressão de 20260928b.
--    * Mais de um aluno na mesma pessoa (cadastro duplicado, e-mail antigo e novo): vale o MAIOR
--      data_expiracao — é o acesso que ela tem de fato; turma = a desse mesmo aluno (desempate por id).
--      no_gps = qualquer um dos alunos está no GPS.
--    * Hoje = (now() at time zone 'America/Sao_Paulo')::date.
--    * Ciclo atual = vendas HM pagas (qualquer oferta: cheio, sinal, saldo, renovação, mensalidade) com
--      dia_aprovado entre (vencimento − 12 meses − 60 dias) e vencimento, inclusive.
--    * meses_restantes = meses CHEIOS de hoje até o vencimento (age()); vencimento ≤ hoje → 0.
--    * credito = pago_no_ciclo × meses_restantes ÷ 12, truncado no centavo; diferenca = p_valor_programa −
--      credito, piso 0. SEM Acelera (só família HM). pago = valor_oferta (sem juros do cliente).
--    * O cs.fn_hm_prorata do board é OUTRA regra (por dia, base R$ 14.700) e não é tocado aqui.
--    * formas = contagem por forma no ciclo, maior primeiro: mensalidade (oferta SUBSCRIPTION) ou a
--      categoria do catálogo (sinal, saldo, compra cheia, renovação…), senão o papel do produto.
--    * ultimo_pagamento = última venda HM paga da pessoa (qualquer data, não só o ciclo).
--    * nome / email = da venda HM paga mais recente. Sem documento e sem telefone (LGPD, regra de Pessoas).
--    * tem_card / contato_hm_id = card HM no board (cs.vw_fin_board) por qualquer e-mail da pessoa;
--      mais de um card → o de maior saldo_a_pagar (mesma escolha de fn_fin_hotmart_pessoas).

-- ─── 1. Board × Hotmart + assinatura ─────────────────────────────────────────
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
  assinatura_ativa boolean)
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
              then coalesce(ass.ate >= sinc.hoje - 45, false) and coalesce(dv.n_atual, 0) = 0 end
    from card k
    cross join sinc
    left join nc n on n.pessoa = k.pessoa and n.origem = k.origem
    left join v on v.pessoa = k.pessoa and v.familia = k.origem
    left join fp on fp.pessoa = k.pessoa and fp.familia = k.origem
    left join dv on dv.pessoa = k.pessoa and dv.familia = k.origem
    left join bsh on bsh.contato_hm_id = k.contato_hm_id and bsh.origem = k.origem
    left join ass on ass.pessoa = k.pessoa and k.origem = 'HM'
   order by k.origem, coalesce(dv.valor_atual, 0) desc, coalesce(v.valor_falta, 0) desc;
end $$;
revoke all on function public.fn_fin_board_hotmart() from public, anon;
grant execute on function public.fn_fin_board_hotmart() to authenticated;

-- ─── 2. Pro rata do HM ───────────────────────────────────────────────────────
create or replace function public.fn_fin_prorata_hm(p_valor_programa numeric default 15000)
returns table (
  pessoa_chave text, nome text, email text, turma text, vencimento date, meses_restantes int,
  pago_no_ciclo numeric, pagamentos_no_ciclo int, formas text, credito numeric, diferenca numeric,
  ultimo_pagamento date, tem_card boolean, contato_hm_id uuid, no_gps boolean)
language plpgsql stable security definer set search_path = ''
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
  ), tx as (
    -- vendas HM pagas, qualquer oferta; forma = mensalidade (SUBSCRIPTION) ou categoria do catálogo
    select coalesce(i.pessoa_chave, 'e:' || t.email) pessoa, t.email, t.nome, t.valor_oferta, t.dia_aprovado, t.aprovado_em,
           case when t.oferta_modo = 'SUBSCRIPTION' then 'mensalidade'
                else coalesce((select min(cat.categoria) from public.hm_product_catalog cat where cat.offer_code = t.oferta_codigo),
                              t.papel_produto) end forma
      from fin.vw_transacoes t
      left join fin.identidade i on i.no = 'e:' || t.email
     where t.familia = 'HM' and t.grupo = 'pago' and t.email is not null
  ), pes as (
    select x.pessoa,
           (array_agg(x.nome order by x.aprovado_em desc nulls last))[1] nome,
           (array_agg(x.email order by x.aprovado_em desc nulls last))[1] email,
           max(x.dia_aprovado) ult
      from tx x
     group by x.pessoa
  ), email_pessoa as (
    select distinct x.pessoa, x.email from tx x
    union
    select i.pessoa_chave, substr(i.no, 3) from fin.identidade i
     where i.no like 'e:%' and i.pessoa_chave in (select p.pessoa from pes p)
  ), aluno as materialized (
    -- mais de um aluno na pessoa: vale o maior data_expiracao (turma do mesmo aluno)
    select e.pessoa, max(a.data_expiracao)::date venc,
           (array_agg(tt.codigo order by a.data_expiracao desc, a.id))[1] turma,
           bool_or(exists (select 1 from gps.membros m where m.aluno_id = a.id or m.pessoa_aluno_id = a.id)) no_gps
      from email_pessoa e
      join public.thb_alunos a on lower(trim(a.email)) = e.email
      left join public.thb_turmas tt on tt.id = a.turma_id
     where a.data_expiracao is not null
     group by e.pessoa
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
               else coalesce(f.forma, 'outra') end,
             ' · ' order by f.n desc, f.forma) formas
      from fc f
     group by f.pessoa
  ), crd as materialized (
    select e.pessoa, (array_agg(b.contato_hm_id order by b.saldo_a_pagar desc nulls last))[1] contato_hm_id
      from email_pessoa e
      join public.compradores c on lower(trim(c.email)) = e.email
      join cs.vw_fin_board b on b.comprador_id = c.id and b.origem = 'HM'
     group by e.pessoa
  ), calc as (
    select p.pessoa, p.nome, p.email, al.turma, al.venc, p.ult, al.no_gps,
           coalesce(ci.pago, 0) pago, coalesce(ci.n, 0) n, ci.formas,
           case when al.venc > h.d
                then (extract(year from age(al.venc::timestamp, h.d::timestamp)) * 12
                      + extract(month from age(al.venc::timestamp, h.d::timestamp)))::int
                else 0 end meses
      from pes p
      join aluno al on al.pessoa = p.pessoa
      cross join hoje h
      left join cic ci on ci.pessoa = p.pessoa
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

-- ─── Aceite (rodar depois de aplicar, logado com gp_pode_ver_financeiro) ─────
-- Guarda barra sessão postgres/service: use JWT de financeiro
-- (begin; set local role authenticated; set local request.jwt.claims = '{"sub":"<uuid financeiro>"}'; … rollback;).
/*
-- 0) Índices que as junções usam (a expressão tem que bater: lower(trim(email)))
select tablename, indexdef from pg_indexes
 where (schemaname, tablename) in (('public','thb_alunos'), ('public','compradores'), ('fin','identidade'), ('fin','hotmart_transacoes'));

-- 1) Marcio (esperado com hoje = 2026-09-27: venc 2026-12-31, meses 3, pago 3997, crédito 999,25, diferença 14000,75)
--    Carlos (esperado: venc 2026-10-05, meses 0, 12 pagamentos / 23.964 no ciclo, crédito 0, diferença 15000)
select p.* from public.fn_fin_prorata_hm() p
 where p.email in ('marciomorais2722@gmail.com', 'newwaycontabilidade@gmail.com');
--    se o e-mail exibido for outro nó da pessoa, procure pela turma/vencimento e pela chave:
--    (como postgres) select fin.chave_opaca(pessoa_chave) from fin.identidade where no in ('e:marciomorais2722@gmail.com','e:newwaycontabilidade@gmail.com');

-- 2) Contagem e distribuição
select count(*) pessoas, count(*) filter (where meses_restantes = 0) sem_credito,
       count(*) filter (where vencimento < (now() at time zone 'America/Sao_Paulo')::date) vencidos,
       count(*) filter (where tem_card) com_card, count(*) filter (where no_gps) no_gps,
       count(*) - count(distinct pessoa_chave) chave_repetida,  -- esperado 0
       sum(credito) credito, sum(diferenca) diferenca
  from public.fn_fin_prorata_hm();

-- 3) Board: contagem não muda (328 = HM 286 / AURUM 42) e os valores do card são os mesmos de antes
--    (rodar ANTES de aplicar e guardar; comparar depois). Assinatura: AURUM tudo 0/null.
select origem, count(*) cards, sum(pago_bruto / nullif(cards_da_pessoa, 0)) pago_bruto,
       sum(liquido / nullif(cards_da_pessoa, 0)) liquido,
       count(*) filter (where assinatura_mensalidades > 0) com_assinatura,
       count(*) filter (where assinatura_ativa) assinatura_ativa,
       sum(assinatura_valor / nullif(cards_da_pessoa, 0)) assinatura_valor
  from public.fn_fin_board_hotmart() group by rollup (origem);

-- 4) (como postgres) Mensalidade que TAMBÉM cai no escopo do card (categoria sinal/diferenca/compra_cheia).
--    Esperado 0. Se > 0, essa venda aparece no "pago" do card e no bloco Assinatura — levar ao João.
select t.oferta_codigo, cat.categoria, count(*), sum(t.valor_oferta)
  from fin.vw_transacoes t
  join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
 where t.familia = 'HM' and t.grupo = 'pago' and t.oferta_modo = 'SUBSCRIPTION'
   and cat.categoria in ('sinal','diferenca','compra_cheia')
 group by 1, 2;

-- 5) Custo (esperado < 500 ms cada; ambas só leem — sem risco de executar escrita)
explain (analyze, buffers) select * from public.fn_fin_board_hotmart();
explain (analyze, buffers) select * from public.fn_fin_prorata_hm();

-- 6) Grants (esperado: só authenticated e postgres/service; nada para PUBLIC nem anon)
select p.proname, a.grantee::regrole, a.privilege_type
  from pg_proc p cross join lateral aclexplode(p.proacl) a
 where p.proname in ('fn_fin_board_hotmart', 'fn_fin_prorata_hm');
*/

-- Medido 27/09 depois de aplicar: o planejador escolhia laço aninhado sobre as CTEs cic/crd (1.196 × ~1.200 → 34,8 s).
-- Com as CTEs materialized: 640 ms; sem laço aninhado nesta função: 265 ms chamando como financeiro.
alter function public.fn_fin_prorata_hm(numeric) set enable_nestloop = off;
