-- 20261007gr: gráficos novos da aba "Visão geral de vendas" do dashboard presencial (Clínica de Miami).
--
-- STATUS: NÃO APLICADA. Cria função e GRANT: só aplica depois do pentester e da ordem do Maestro.
--
-- POR QUE
--   Pedido do Victor Hugo (07/10/2026, noite): forma de pagamento, turma e instrução de quem comprou, boleto/pix gerado e
--   não pago por pessoa, compras canceladas por pessoa, vendas e receita acumuladas por dia, conversão por dia e vendas por
--   hora. As 5 funções dados_presencial_* de hoje não têm esses recortes. O contrato delas não muda.
--
-- O QUE FAZ
--   Ajudantes internos (sem grant, só o dono executa): 1 e dados.pendencias (base de 5 e 6).
--   1. dados.transacoes_extra(conta, oferta): documento, forma de pagamento, método e parcelas de cada transação das
--      ofertas do dashboard (principal + ofertas_extra), do espelho do sync e, enquanto o sync não traz, do webhook
--      (mesma regra de dados.transacoes, migration 20261007205017). Junta com dados.transacoes pela transação.
--      forma = nome da Hotmart no webhook: o espelho grava o Parcelado Hotmart como BILLET com parcelas > 1 (provado em
--      07/10: as 122 transações HOTMART_INSTALLMENTS do webhook estão no espelho como BILLET com 2 a 12 parcelas; as 63
--      BILLET do webhook estão como BILLET com 1 parcela), então BILLET com parcelas > 1 vira HOTMART_INSTALLMENTS.
--   Públicas (security definer, search_path '', mesmo gate dados.cadastro → gp_eh_equipe + dados.pode_ver; executáveis só
--   por authenticated e service_role):
--   3. dados_presencial_pagamentos(chave): vendas pagas por forma de pagamento e parcelas. Sem dado pessoal.
--   4. dados_presencial_compradores_perfil(chave): compradores únicos (pagos) por turma (public.thb_turmas.codigo), por
--      instrução (public.thb_alunos.instrucao) e por chave de casamento com a base de alunos: e-mail; senão documento
--      (só dígitos, 11 ou mais); senão telefone (últimos 11 dígitos, os dois lados com 11 ou mais). Mais de um cadastro:
--      não cancelado primeiro, titular antes de sócio, o atualizado mais recente. Sem dado pessoal.
--   5. dados_presencial_pendencias(chave): pessoas únicas com boleto/pix gerado e não pago (por meio) e com compra
--      cancelada (por status), tirando quem pagou outra transação das ofertas do dashboard. Sem dado pessoal.
--   6. dados_presencial_pendencias_pessoas(chave, grupo): a lista dessas pessoas para o modal (nome, e-mail, telefone).
--   7. dados_presencial_serie_vendas(chave): por dia, pré-checkout, vendas, receita, acumulados e conversão do dia.
--   8. dados_presencial_vendas_por_hora(chave): 24 linhas, vendas e receita pela hora da aprovação (São Paulo).
--
-- REGRAS (as mesmas do resumo, para os números baterem)
--   venda = transação paga (APPROVED ou COMPLETE) e primeira cobrança; receita = soma do valor bruto das transações pagas
--   em BRL. Pessoa = e-mail normalizado (lower + trim). "Pagou outra transação" = existe transação paga nas ofertas do
--   dashboard com o mesmo e-mail ou com o mesmo documento (só dígitos).
--   Não pago (item 4): status PRINTED_BILLET ou WAITING_PAYMENT. Meio: pix se a forma ou o método for PIX; boleto se for
--   BILLET ou FINANCED_BILLET; senão outro. OVERDUE (parcela atrasada de compra já feita) não entra.
--   Cancelada (item 5): CANCELLED, REFUNDED, PARTIALLY_REFUNDED, CHARGEBACK, EXPIRED. Não entram: NO_FUNDS, BLOCKED,
--   PROTESTED, OVERDUE.
--
-- AS 5 PERGUNTAS
--   escala: dezenas de transações por evento; thb_alunos 1.899 linhas. índice: transação (espelho e webhook) como em
--   dados.transacoes; o casamento com thb_alunos lê a tabela (pequena). frequência: a cada abertura/atualização da aba.
--   repetição: cada função chama dados.transacoes uma vez. reversão: rollback-graficos.sql (drop das 8 funções: 2 internas e 6 públicas).
--
-- IDEMPOTENTE: create or replace; revoke/grant repetíveis.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('dados.transacoes(text,text)') is null or to_regprocedure('dados.cadastro(text)') is null
     or to_regprocedure('dados.pre_checkout(text,bigint,text)') is null then
    raise exception '20261007gr: ajudantes do dashboard presencial não existem';
  end if;
  if position('20261007tr' in pg_get_functiondef('dados.transacoes(text,text)'::regprocedure)) = 0 then
    raise exception '20261007gr: dados.transacoes não é a versão com o webhook (20261007205017)';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'thb_alunos'
        and column_name in ('email', 'documento', 'telefone', 'telefone_e164', 'turma_id', 'instrucao', 'cancelado_em',
                            'eh_socio', 'atualizado_em')) <> 9 then
    raise exception '20261007gr: public.thb_alunos sem as colunas esperadas';
  end if;
end
$g$;

-- 1. Documento e pagamento por transação
create or replace function dados.transacoes_extra(p_conta text, p_oferta text)
 returns table(transacao text, documento text, forma text, metodo text, parcelas integer)
 language plpgsql
 stable
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  v_conta text := p_conta;
  v_ofertas text[];
begin
  v_ofertas := array[p_oferta] || coalesce((select d.ofertas_extra from dados.dashboards d
                                             where d.conta_hotmart = p_conta and d.oferta_codigo = p_oferta and d.ativo
                                             limit 1), '{}'::text[]);
  return query
  select t.transacao,
         nullif(regexp_replace(coalesce(t.comprador_documento, ''), '\D', '', 'g'), ''),
         case when t.tipo_pagamento = 'BILLET' and coalesce(t.parcelas, 1) > 1 then 'HOTMART_INSTALLMENTS'
              else t.tipo_pagamento end,
         t.metodo, t.parcelas
    from (select * from fin.hotmart_transacoes where conta = v_conta) t
   where t.oferta_codigo = any (v_ofertas)
  union all
  select w.transacao,
         nullif(regexp_replace(coalesce(w.d #>> '{buyer,document}', ''), '\D', '', 'g'), ''),
         w.d #>> '{purchase,payment,type}',
         case when w.d #>> '{purchase,payment,type}' in ('PIX', 'BILLET') then w.d #>> '{purchase,payment,type}' end,
         nullif(w.d #>> '{purchase,payment,installments_number}', '')::int
    from (select distinct on (e.transacao) e.transacao, e.payload -> 'data' as d
            from cs.hotmart_eventos e
           where v_conta = 'academy'
             and e.transacao is not null
             and e.evento like 'PURCHASE%'
             and e.payload #>> '{data,purchase,status}' is not null
             and e.payload #>> '{data,purchase,offer,code}' = any (v_ofertas)
             and not exists (select 1 from (select * from fin.hotmart_transacoes where conta = v_conta) h
                              where h.transacao = e.transacao)
           order by e.transacao, (e.payload #>> '{data,purchase,payment,type}' is null), e.recebido_em desc, e.id desc) w;
end
$function$;
revoke all on function dados.transacoes_extra(text, text) from public, anon, authenticated, service_role;

-- 3. Formas de pagamento das vendas
create or replace function public.dados_presencial_pagamentos(p_chave text)
 returns table(forma text, forma_nome text, parcelas integer, vendas integer, receita_bruta numeric)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  select coalesce(x.forma, 'NAO_INFORMADO'),
         case coalesce(x.forma, 'NAO_INFORMADO')
           when 'CREDIT_CARD' then 'Cartão de crédito'
           when 'PIX' then 'Pix'
           when 'BILLET' then 'Boleto'
           when 'HOTMART_INSTALLMENTS' then 'Parcelado Hotmart'
           when 'FINANCED_BILLET' then 'Boleto financiado'
           when 'HYBRID' then 'Híbrido'
           when 'WALLET' then 'Saldo Hotmart'
           when 'APPLE_PAY' then 'Apple Pay'
           when 'GOOGLE_PAY' then 'Google Pay'
           when 'SAMSUNG_PAY' then 'Samsung Pay'
           when 'PAYPAL' then 'PayPal'
           when 'DIRECT_DEBIT' then 'Débito em conta'
           when 'CASH_PAYMENT' then 'Pagamento em dinheiro'
           when 'NAO_INFORMADO' then 'Não informado'
           else x.forma end,
         coalesce(x.parcelas, 1),
         (count(*) filter (where t.primeira))::int,
         coalesce(sum(t.valor_bruto) filter (where t.moeda = 'BRL'), 0)::numeric(14,2)
    from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
    left join dados.transacoes_extra(d.conta_hotmart, d.oferta_codigo) x on x.transacao = t.transacao
   where t.pago
   group by 1, 2, 3
   order by 4 desc, 1, 3;
end
$function$;

-- 4. Compradores por turma, instrução e chave de casamento
create or replace function public.dados_presencial_compradores_perfil(p_chave text)
 returns table(dimensao text, valor text, compradores integer)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with tx as (
    select t.email, x.documento, t.telefone
      from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
      left join dados.transacoes_extra(d.conta_hotmart, d.oferta_codigo) x on x.transacao = t.transacao
     where t.pago and t.email is not null
  ), comp as (
    select tx.email, max(tx.documento) as documento, max(tx.telefone) as telefone from tx group by tx.email
  ), al as materialized (
    select al0.turma_id, al0.instrucao, al0.cancelado_em, al0.eh_socio, al0.atualizado_em,
           nullif(lower(btrim(al0.email)), '') as em,
           nullif(regexp_replace(coalesce(al0.documento, ''), '\D', '', 'g'), '') as doc,
           case when length(regexp_replace(coalesce(al0.telefone_e164, al0.telefone, ''), '\D', '', 'g')) >= 11
                then right(regexp_replace(coalesce(al0.telefone_e164, al0.telefone, ''), '\D', '', 'g'), 11) end as tel11
      from public.thb_alunos al0
  ), cn as (
    select c.email,
           nullif(regexp_replace(coalesce(c.documento, ''), '\D', '', 'g'), '') as doc,
           case when length(regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g')) >= 11
                then right(regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g'), 11) end as tel11
      from comp c
  ), cand as (
    select cn.email, al.*, 1 as prio, 'email'::text as k from cn join al on al.em = cn.email
    union all
    select cn.email, al.*, 2, 'documento' from cn join al on al.doc = cn.doc where length(cn.doc) >= 11
    union all
    select cn.email, al.*, 3, 'telefone' from cn join al on al.tel11 = cn.tel11
  ), m as (
    select distinct on (cand.email) cand.email, cand.turma_id, cand.instrucao, cand.k
      from cand
     order by cand.email, cand.prio, (cand.cancelado_em is null) desc, coalesce(cand.eh_socio, false),
              cand.atualizado_em desc nulls last
  ), pf as (
    select cn.email, tu.codigo as turma, nullif(btrim(m.instrucao), '') as instrucao, m.k as casou_por
      from cn
      left join m on m.email = cn.email
      left join public.thb_turmas tu on tu.id = m.turma_id
  )
  select 'turma'::text, case when pf.casou_por is null then 'Não é aluno'
                             else coalesce(pf.turma, 'Aluno sem turma') end, count(*)::int
    from pf group by 2
  union all
  select 'instrucao', case when pf.casou_por is null then 'Não é aluno'
                           else coalesce(pf.instrucao, 'Aluno sem instrução') end, count(*)::int
    from pf group by 2
  union all
  select 'casamento', coalesce(pf.casou_por, 'nao_casou'), count(*)::int
    from pf group by 2
  order by 1, 3 desc, 2;
end
$function$;

-- 5 e 6. Boleto/pix não pago e compras canceladas, por pessoa única
create or replace function dados.pendencias(p_conta text, p_oferta text)
 returns table(grupo text, categoria text, email text, transacao text, status text, valor_bruto numeric,
               quando timestamp with time zone, nome text, telefone text)
 language sql
 stable
 set search_path to ''
as $function$
  with tx as (
    select t.*, x.documento, x.forma, x.metodo
      from dados.transacoes(p_conta, p_oferta) t
      left join dados.transacoes_extra(p_conta, p_oferta) x on x.transacao = t.transacao
     where t.email is not null
  ), pagou as (
    select tx.email, tx.documento from tx where tx.pago
  ), fora as (
    select tx.* from tx
     where not exists (select 1 from pagou p where p.email = tx.email or (tx.documento is not null and p.documento = tx.documento))
  )
  select 'nao_pago'::text,
         case when f.forma = 'PIX' or f.metodo = 'PIX' then 'pix'
              when f.forma in ('BILLET', 'FINANCED_BILLET') or f.metodo = 'BILLET' then 'boleto'
              else 'outro' end,
         f.email, f.transacao, f.status, f.valor_bruto, coalesce(f.pedido_em, f.aprovado_em), f.nome, f.telefone
    from fora f where f.status in ('PRINTED_BILLET', 'WAITING_PAYMENT')
  union all
  select 'cancelada', f.status, f.email, f.transacao, f.status, f.valor_bruto, coalesce(f.pedido_em, f.aprovado_em),
         f.nome, f.telefone
    from fora f where f.status in ('CANCELLED', 'REFUNDED', 'PARTIALLY_REFUNDED', 'CHARGEBACK', 'EXPIRED')
$function$;
revoke all on function dados.pendencias(text, text) from public, anon, authenticated, service_role;

create or replace function public.dados_presencial_pendencias(p_chave text)
 returns table(grupo text, categoria text, pessoas integer, transacoes integer)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with p as (select * from dados.pendencias(d.conta_hotmart, d.oferta_codigo)),
       g as (select x.grupo from (values ('nao_pago'), ('cancelada')) x(grupo))
  select g.grupo, 'total'::text, (select count(distinct p.email)::int from p where p.grupo = g.grupo),
         (select count(*)::int from p where p.grupo = g.grupo)
    from g
  union all
  select p.grupo, p.categoria, count(distinct p.email)::int, count(*)::int
    from p group by p.grupo, p.categoria
  order by 1 desc, 2;
end
$function$;

create or replace function public.dados_presencial_pendencias_pessoas(p_chave text, p_grupo text)
 returns table(email text, nome text, telefone text, categorias text, transacoes integer, valor_bruto numeric,
               ultimo_em timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  if p_grupo is null or p_grupo not in ('nao_pago', 'cancelada') then
    raise exception 'grupo inválido' using errcode = '22023';
  end if;
  return query
  select p.email,
         (array_agg(p.nome order by p.quando desc) filter (where p.nome is not null))[1],
         (array_agg(p.telefone order by p.quando desc) filter (where p.telefone is not null))[1],
         string_agg(distinct p.categoria, ', ' order by p.categoria),
         count(*)::int,
         (array_agg(p.valor_bruto order by p.quando desc))[1],
         max(p.quando)
    from dados.pendencias(d.conta_hotmart, d.oferta_codigo) p
   where p.grupo = p_grupo
   group by p.email
   order by max(p.quando) desc nulls last, p.email;
end
$function$;

-- 7. Série de vendas: acumulados e conversão do dia
create or replace function public.dados_presencial_serie_vendas(p_chave text)
 returns table(dia date, pre_checkout integer, vendas integer, receita_bruta numeric, vendas_acumuladas integer,
               receita_acumulada numeric, conversao_pct numeric)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  return query
  with pc as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
                from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x),
       tx as (select * from dados.transacoes(d.conta_hotmart, d.oferta_codigo)),
       ini as (select least((select min(pc.dia) from pc), (select min(t.dia_pedido) from tx t),
                            (select min(t.dia_aprovado) from tx t where t.pago)) as d0),
       base as (
         select g.dia::date as dia,
                (select count(*)::int from pc where pc.dia = g.dia) as pc,
                (select count(*)::int from tx t where t.pago and t.primeira and t.dia_aprovado = g.dia) as ven,
                (select coalesce(sum(t.valor_bruto), 0) from tx t
                  where t.pago and t.moeda = 'BRL' and t.dia_aprovado = g.dia)::numeric(14,2) as rec
           from ini cross join lateral generate_series(ini.d0, greatest(ini.d0, v_hoje), interval '1 day') g(dia)
          where ini.d0 is not null
       )
  select b.dia, b.pc, b.ven, b.rec,
         (sum(b.ven) over (order by b.dia))::int,
         (sum(b.rec) over (order by b.dia))::numeric(14,2),
         case when b.pc > 0 then round(b.ven::numeric * 100 / b.pc, 2)::numeric(7,2) end
    from base b
   order by b.dia;
end
$function$;

-- 8. Vendas por hora do dia (São Paulo)
create or replace function public.dados_presencial_vendas_por_hora(p_chave text)
 returns table(hora integer, vendas integer, receita_bruta numeric)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with tx as (select extract(hour from (t.aprovado_em at time zone 'America/Sao_Paulo'))::int as h, t.primeira,
                     t.moeda, t.valor_bruto
                from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
               where t.pago and t.aprovado_em is not null)
  select g.h,
         (select count(*)::int from tx where tx.h = g.h and tx.primeira),
         (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.h = g.h and tx.moeda = 'BRL')::numeric(14,2)
    from generate_series(0, 23) g(h)
   order by 1;
end
$function$;

-- Permissões: as 6 públicas só para authenticated e service_role (o gate dentro decide quem vê)
revoke all on function public.dados_presencial_pagamentos(text), public.dados_presencial_compradores_perfil(text),
  public.dados_presencial_pendencias(text), public.dados_presencial_pendencias_pessoas(text, text),
  public.dados_presencial_serie_vendas(text), public.dados_presencial_vendas_por_hora(text)
  from public, anon;
grant execute on function public.dados_presencial_pagamentos(text), public.dados_presencial_compradores_perfil(text),
  public.dados_presencial_pendencias(text), public.dados_presencial_pendencias_pessoas(text, text),
  public.dados_presencial_serie_vendas(text), public.dados_presencial_vendas_por_hora(text)
  to authenticated, service_role;
