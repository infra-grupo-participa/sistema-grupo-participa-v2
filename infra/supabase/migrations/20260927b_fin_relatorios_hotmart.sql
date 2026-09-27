-- 20260927b — Relatórios do financeiro a partir do espelho da Hotmart (schema fin).
--
-- Tudo SÓ LEITURA. Nenhuma função aqui escreve em lugar nenhum.
-- Guarda: public.gp_pode_ver_financeiro() (a mesma do board), que devolve
-- false — nunca NULL — sem sessão. search_path vazio, nomes qualificados.
--
-- Definições (valem para a tela inteira):
--   valor_oferta  = preço da oferta (hotmart_fee.base). É o "BRUTO" do negócio:
--                   não inclui os juros de parcelamento, que o cliente paga à Hotmart.
--   cobrado       = o que saiu do bolso do cliente (inclui juros).
--   taxa_hotmart  = 4% + R$ 1 (o que a Hotmart retém sobre o valor da oferta).
--   liquido       = comissão do PRODUTOR (sales/commissions). Sem comissão na API
--                   (venda antiga/estornada), estimado = oferta − taxa, e marcado.
--   grupo         = pago · estornado · atrasado · em_aberto · recusado · expirado.

create or replace view fin.vw_transacoes as
select
  t.transacao, t.produto_id, coalesce(p.familia, 'OUTRO') as familia, coalesce(p.papel, 'desconhecido') as papel_produto,
  t.produto_nome, t.oferta_codigo, t.oferta_modo, t.status, t.recorrencia, t.metodo, t.tipo_pagamento, t.parcelas,
  coalesce(t.valor_base, nullif(t.bruto_json #>> '{purchase,hotmart_fee,base}', '')::numeric, t.valor_cobrado) as valor_oferta,
  t.valor_cobrado, coalesce(t.juros_parcelamento, 0) as juros, t.taxa_hotmart,
  case
    when t.status in ('APPROVED','COMPLETE') then
      coalesce(t.liquido_produtor,
               coalesce(t.valor_base, nullif(t.bruto_json #>> '{purchase,hotmart_fee,base}', '')::numeric, t.valor_cobrado) - coalesce(t.taxa_hotmart, 0))
  end as liquido,
  (t.status in ('APPROVED','COMPLETE') and t.liquido_produtor is null) as liquido_estimado,
  case
    when t.status in ('APPROVED','COMPLETE') then 'pago'
    when t.status in ('REFUNDED','PARTIALLY_REFUNDED','CHARGEBACK') then 'estornado'
    when t.status in ('OVERDUE','PROTESTED') then 'atrasado'
    when t.status in ('PRINTED_BILLET','WAITING_PAYMENT','UNDER_ANALISYS','STARTED') then 'em_aberto'
    when t.status in ('CANCELLED','NO_FUNDS','BLOCKED') then 'recusado'
    when t.status = 'EXPIRED' then 'expirado'
    else 'outro'
  end as grupo,
  t.pedido_em, t.aprovado_em, t.garantia_ate,
  (t.pedido_em at time zone 'America/Sao_Paulo')::date as dia_pedido,
  (t.aprovado_em at time zone 'America/Sao_Paulo')::date as dia_aprovado,
  t.origem_sck, lower(trim(t.comprador_email)) as email, t.comprador_nome as nome, t.atualizado_em
from fin.hotmart_transacoes t
left join fin.produtos p on p.produto_id = t.produto_id;

revoke all on fin.vw_transacoes from public, anon, authenticated;

-- ─── 1. Faturamento diário (fonte Hotmart) ────────────────────────────────────
create or replace function public.fn_fin_hotmart_faturamento(
  p_familia text default 'HM', p_inicio date default null, p_fim date default null)
returns table (
  dia date, vendas int, valor_oferta numeric, cobrado_cliente numeric, juros numeric,
  taxa_hotmart numeric, liquido numeric, liquido_estimado int,
  estornos int, valor_estornado numeric, recusadas int, boletos_gerados int, compradores int)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_ini date := coalesce(p_inicio, (now() at time zone 'America/Sao_Paulo')::date - 89);
        v_fim date := coalesce(p_fim, (now() at time zone 'America/Sao_Paulo')::date);
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  -- Sem teto de dias: o custo é o das transações da família (plano 27/09: Aurum 2021→hoje 50 ms), não do intervalo.
  -- Um teto fixo voltaria a quebrar o "Tudo" da tela quando a história passasse dele.
  if v_fim < v_ini then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  return query
  with p as (
    select t.dia_aprovado d,
           count(*) filter (where t.grupo = 'pago')::int vendas,  -- estorno não é venda paga (Fable 27/09)
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'pago'), 0) oferta,
           coalesce(sum(t.valor_cobrado) filter (where t.grupo = 'pago'), 0) cobrado,
           coalesce(sum(t.juros) filter (where t.grupo = 'pago'), 0) juros,
           coalesce(sum(t.taxa_hotmart) filter (where t.grupo = 'pago'), 0) taxa,
           coalesce(sum(t.liquido) filter (where t.grupo = 'pago'), 0) liquido,
           count(*) filter (where t.liquido_estimado)::int estimado,
           count(*) filter (where t.grupo = 'estornado')::int estornos,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'estornado'), 0) estornado,
           count(distinct t.email) filter (where t.grupo = 'pago')::int compradores
      from fin.vw_transacoes t
     where t.familia = p_familia and t.grupo in ('pago','estornado') and t.dia_aprovado between v_ini and v_fim
     group by 1
  ), a as (
    select t.dia_pedido d,
           count(*) filter (where t.grupo = 'recusado')::int recusadas,
           count(*) filter (where t.grupo in ('em_aberto','expirado'))::int boletos
      from fin.vw_transacoes t
     where t.familia = p_familia and t.grupo in ('recusado','em_aberto','expirado') and t.dia_pedido between v_ini and v_fim
     group by 1
  )
  select coalesce(p.d, a.d), coalesce(p.vendas, 0), coalesce(p.oferta, 0), coalesce(p.cobrado, 0),
         coalesce(p.juros, 0), coalesce(p.taxa, 0), coalesce(p.liquido, 0), coalesce(p.estimado, 0),
         coalesce(p.estornos, 0), coalesce(p.estornado, 0), coalesce(a.recusadas, 0), coalesce(a.boletos, 0),
         coalesce(p.compradores, 0)
    from p full join a on a.d = p.d
   order by 1;
end $$;

-- ─── 2. Situação de cada pessoa (Hotmart + card do board + GPS) ────────────────
create or replace function public.fn_fin_hotmart_pessoas(p_familia text default 'HM')
returns table (
  email text, nome text, situacao text, aviso text,
  primeira_compra date, ultima_compra_paga date, compras_pagas int,
  valor_pago numeric, liquido numeric, estornos int, valor_estornado numeric,
  parcelas_atrasadas int, valor_atrasado numeric, atrasadas_antigas int, valor_atrasado_antigo numeric,
  em_aberto int, recusadas int,
  ultima_tentativa date, no_gps boolean, acesso_ate date, acesso_hotmart_ate date,
  contato_hm_id uuid, status_card text, saldo_card numeric, solicitou_cancelamento boolean)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with agg as (
    select t.email,
           (array_agg(t.nome order by t.pedido_em desc))[1] nome,
           min(t.dia_aprovado) filter (where t.grupo in ('pago','estornado')) primeira,
           max(t.dia_aprovado) filter (where t.grupo = 'pago') ultima_paga,
           count(*) filter (where t.grupo = 'pago')::int pagas,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'pago'), 0) valor_pago,
           coalesce(sum(t.liquido) filter (where t.grupo = 'pago'), 0) liquido,
           count(*) filter (where t.grupo = 'estornado')::int estornos,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'estornado'), 0) valor_estornado,
           max(t.aprovado_em) filter (where t.grupo = 'estornado') ultimo_estorno,
           max(t.aprovado_em) filter (where t.grupo = 'pago') ultimo_pago,
           -- Parcela OVERDUE de assinatura cancelada fica OVERDUE para sempre: só os últimos
           -- 120 dias são dívida atual; o resto é inadimplência antiga (coluna própria).
           count(*) filter (where t.grupo = 'atrasado' and t.pedido_em >= now() - interval '120 days')::int atrasadas,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'atrasado' and t.pedido_em >= now() - interval '120 days'), 0) valor_atrasado,
           count(*) filter (where t.grupo = 'atrasado' and t.pedido_em < now() - interval '120 days')::int atrasadas_antigas,
           coalesce(sum(t.valor_oferta) filter (where t.grupo = 'atrasado' and t.pedido_em < now() - interval '120 days'), 0) valor_atrasado_antigo,
           count(*) filter (where t.grupo = 'em_aberto')::int em_aberto,
           count(*) filter (where t.grupo = 'recusado')::int recusadas,
           max(t.dia_pedido) ultima_tentativa,
           -- parcelado Hotmart (cada parcela é uma transação): em curso se a última parcela paga < total
           bool_or(t.grupo = 'pago' and t.oferta_modo like 'HOTMART_INSTALLMENTS%'
                   and t.recorrencia is not null and t.parcelas is not null and t.recorrencia < t.parcelas
                   and t.dia_aprovado >= (now() at time zone 'America/Sao_Paulo')::date - 45) parcelado_em_curso
      from fin.vw_transacoes t
     where t.familia = p_familia and t.email is not null
     group by t.email
  ), card as (
    select distinct on (lower(trim(c.email))) lower(trim(c.email)) email, b.contato_hm_id, b.status_financeiro,
           b.saldo_a_pagar, coalesce(b.solicitou_cancelamento, false) solicitou
      from cs.vw_fin_board b
      join public.compradores c on c.id = b.comprador_id
     where b.origem = case p_familia when 'AURUM' then 'AURUM' else 'HM' end
     order by lower(trim(c.email)), b.saldo_a_pagar desc nulls last
  ), aluno as (
    select distinct on (lower(trim(a.email))) lower(trim(a.email)) email, a.data_expiracao,
           exists (select 1 from gps.membros m where m.aluno_id = a.id or m.pessoa_aluno_id = a.id) no_gps
      from public.thb_alunos a
     where a.email is not null
     order by lower(trim(a.email)), a.data_expiracao desc nulls last
  )
  select a.email, a.nome,
         case
           when a.pagas = 0 and a.estornos > 0 then 'reembolsado'
           when coalesce(c.solicitou, false) then 'negociacao_cancelamento'
           when a.atrasadas > 0 then 'devendo'
           when a.estornos > 0 and a.ultimo_estorno > coalesce(a.ultimo_pago, '-infinity') then 'reembolsado'
           when coalesce(c.saldo_a_pagar, 0) > 0.5 or a.parcelado_em_curso then 'em_pagamento'
           when a.pagas > 0 and a.ultima_paga >= (now() at time zone 'America/Sao_Paulo')::date - 365 then 'ativo'
           when a.atrasadas_antigas > 0 then 'inadimplencia_antiga'
           when a.pagas > 0 then 'vencido'
           when a.em_aberto > 0 then 'boleto_em_aberto'
           else 'so_tentou'
         end,
         case
           when coalesce(al.no_gps, false) and (a.atrasadas > 0 or a.estornos > 0 or coalesce(c.solicitou, false))
             then 'Está no GPS e tem pendência financeira — não mexer no acesso, resolver com o João'
           when a.pagas > 0 and c.contato_hm_id is null and p_familia = 'HM' and a.ultima_paga >= date '2026-06-25'
             then 'Pagou na Hotmart depois de 25/06 e não tem card no board'
         end,
         a.primeira, a.ultima_paga, a.pagas, a.valor_pago, a.liquido, a.estornos, a.valor_estornado,
         a.atrasadas, a.valor_atrasado, a.atrasadas_antigas, a.valor_atrasado_antigo, a.em_aberto, a.recusadas, a.ultima_tentativa,
         coalesce(al.no_gps, false), al.data_expiracao, a.ultima_paga + 365,
         c.contato_hm_id, c.status_financeiro, c.saldo_a_pagar, coalesce(c.solicitou, false)
    from agg a
    left join card c on c.email = a.email
    left join aluno al on al.email = a.email
   order by a.valor_atrasado desc, a.valor_atrasado_antigo desc, a.ultima_tentativa desc nulls last;
end $$;

-- ─── 3. Extrato completo de uma pessoa (inclui o que ela TENTOU comprar) ───────
create or replace function public.fn_fin_hotmart_extrato(p_email text)
returns table (
  transacao text, produto text, oferta_codigo text, status text, grupo text, metodo text, parcelas int,
  recorrencia int, valor_oferta numeric, cobrado numeric, juros numeric, taxa_hotmart numeric,
  liquido numeric, liquido_estimado boolean, pedido_em timestamptz, aprovado_em timestamptz,
  garantia_ate timestamptz, origem_sck text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if coalesce(trim(p_email), '') = '' then return; end if;
  return query
  select t.transacao, t.produto_nome, t.oferta_codigo, t.status, t.grupo, t.metodo, t.parcelas, t.recorrencia,
         t.valor_oferta, t.valor_cobrado, t.juros, t.taxa_hotmart, t.liquido, t.liquido_estimado,
         t.pedido_em, t.aprovado_em, t.garantia_ate, t.origem_sck
    from fin.vw_transacoes t
   where t.email = lower(trim(p_email))
   order by t.pedido_em desc
   limit 500;
end $$;

-- ─── 4. Ofertas (o que cada código é, quanto vendeu, de que família/papel) ─────
create or replace function public.fn_fin_hotmart_ofertas(p_familia text default 'HM')
returns table (
  oferta_codigo text, produto text, papel_produto text, modo_pagamento text,
  preco_oferta numeric, vendas_pagas int, estornos int, recusadas int,
  receita_oferta numeric, receita_liquida numeric, primeira_venda date, ultima_venda date,
  categoria_catalogo text, papel_catalogo text, nome_comercial text, no_catalogo boolean, ativa boolean)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select t.oferta_codigo,
         (array_agg(t.produto_nome order by t.pedido_em desc))[1],
         (array_agg(t.papel_produto order by t.pedido_em desc))[1],
         (array_agg(t.oferta_modo order by t.pedido_em desc))[1],
         (mode() within group (order by t.valor_oferta)),
         count(*) filter (where t.grupo = 'pago')::int,
         count(*) filter (where t.grupo = 'estornado')::int,
         count(*) filter (where t.grupo = 'recusado')::int,
         coalesce(sum(t.valor_oferta) filter (where t.grupo = 'pago'), 0),
         coalesce(sum(t.liquido) filter (where t.grupo = 'pago'), 0),
         min(t.dia_aprovado), max(t.dia_aprovado),
         max(c.categoria), max(c.papel), max(c.nome_comercial),
         bool_or(c.offer_code is not null), bool_or(c.ativo)
    from fin.vw_transacoes t
    left join public.hm_product_catalog c on c.offer_code = t.oferta_codigo
   where t.familia = p_familia and t.oferta_codigo is not null
   group by t.oferta_codigo
   order by max(t.pedido_em) desc;
end $$;

-- ─── 5. Conciliação: espelho da Hotmart × o que o webhook gravou ──────────────
create or replace function public.fn_fin_hotmart_conciliacao(p_familia text default 'HM')
returns table (tipo text, transacao text, email text, status_hotmart text, status_banco text,
               valor_hotmart numeric, valor_banco numeric, pedido_em timestamptz, detalhe text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  -- O webhook de cada produto só existe desde a 1ª compra dele gravada; antes disso "faltar" não é furo.
  -- Produto que o banco nunca recebeu vira um aviso só (produto_sem_webhook), não milhares de linhas.
  -- Cobrança ATRASADA (OVERDUE) não é pagamento: o webhook não a grava, então não é "falta no banco" (27/09).
  return query
  with inicio as (select c.produto_id, min(c.data_compra) desde from public.compras c group by 1)
  select 'falta_no_banco', t.transacao, t.email, t.status, null::text, t.valor_oferta, null::numeric, t.pedido_em,
         'Venda paga na Hotmart que o webhook não gravou'
    from fin.vw_transacoes t
    join inicio i on i.produto_id = t.produto_id
   where t.familia = p_familia and t.grupo in ('pago','estornado') and t.pedido_em >= i.desde
     and not exists (select 1 from public.compras c where c.hotmart_transaction = t.transacao)
  union all
  select 'produto_sem_webhook', null, null, null, null, sum(t.valor_oferta), null, max(t.pedido_em),
         'Produto ' || t.produto_id || ' (' || max(t.produto_nome) || '): ' || count(*) || ' transações pagas/estornadas e nenhuma no banco'
    from fin.vw_transacoes t
   where t.familia = p_familia and t.grupo in ('pago','estornado')
     and not exists (select 1 from inicio i where i.produto_id = t.produto_id)
   group by t.produto_id
  union all
  select 'status_diferente', t.transacao, t.email, t.status, c.status::text, t.valor_oferta, c.preco, t.pedido_em,
         'Status da Hotmart diferente do banco'
    from fin.vw_transacoes t
    join public.compras c on c.hotmart_transaction = t.transacao
   where t.familia = p_familia
     and case t.grupo when 'pago' then c.status not in ('APPROVED','COMPLETE','COMPLETED')
                      when 'estornado' then c.status not in ('REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED')
                      when 'recusado' then c.status in ('APPROVED','COMPLETE','COMPLETED')
                      when 'expirado' then c.status in ('APPROVED','COMPLETE','COMPLETED')
                      else false end
  union all
  select 'valor_diferente', t.transacao, t.email, t.status, c.status::text, t.valor_oferta, c.preco, t.pedido_em,
         'Preço da oferta na Hotmart diferente do preço gravado'
    from fin.vw_transacoes t
    join public.compras c on c.hotmart_transaction = t.transacao
   where t.familia = p_familia and t.grupo = 'pago' and abs(coalesce(c.preco, 0) - t.valor_oferta) > 1;
end $$;

-- ─── 6. Estado da sincronização ───────────────────────────────────────────────
create or replace function public.fn_fin_hotmart_sync_status()
returns table (transacoes int, ultima_atualizacao timestamptz, janelas_pendentes int, janelas_com_erro int, primeira_venda date)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select (select count(*) from fin.hotmart_transacoes)::int,
         (select max(atualizado_em) from fin.hotmart_transacoes),
         (select count(*) from fin.hotmart_sync_fila where status in ('pendente','processando'))::int,
         (select count(*) from fin.hotmart_sync_fila where status = 'erro')::int,
         (select min(dia_aprovado) from fin.vw_transacoes where grupo = 'pago');
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.fn_fin_hotmart_faturamento(text,date,date)', 'public.fn_fin_hotmart_pessoas(text)',
    'public.fn_fin_hotmart_extrato(text)', 'public.fn_fin_hotmart_ofertas(text)',
    'public.fn_fin_hotmart_conciliacao(text)', 'public.fn_fin_hotmart_sync_status()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
