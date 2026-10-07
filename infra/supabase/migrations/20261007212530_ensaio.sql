-- Ensaio de 20261007gr (refeito depois do pentester: cast das parcelas e pós-condição) (gráficos da Visão geral de vendas): 2 passadas, grants, gate, foto da Clínica, simulação
-- com eventos fictícios (CRM desligado só aqui) e teste em volume com outra oferta. Transação desfeita.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '170s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated; grant all on sequence pg_temp._z_out_em_seq to authenticated;
-- passada 1
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
         case when w.d #>> '{purchase,payment,installments_number}' ~ '^[0-9]{1,4}$'   -- valor não numérico vira null
              then (w.d #>> '{purchase,payment,installments_number}')::int end
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

-- Pós-condição: permissões como o esperado (aborta a transação se não)
do $c$
declare
  f text;
begin
  foreach f in array array['public.dados_presencial_pagamentos(text)', 'public.dados_presencial_compradores_perfil(text)',
                           'public.dados_presencial_pendencias(text)', 'public.dados_presencial_pendencias_pessoas(text,text)',
                           'public.dados_presencial_serie_vendas(text)', 'public.dados_presencial_vendas_por_hora(text)'] loop
    if not has_function_privilege('authenticated', f, 'execute') or not has_function_privilege('service_role', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or not (select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p where p.oid = f::regprocedure) then
      raise exception '20261007gr: permissão ou definição errada em %', f;
    end if;
  end loop;
  foreach f in array array['dados.transacoes_extra(text,text)', 'dados.pendencias(text,text)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '20261007gr: ajudante interno exposto: %', f;
    end if;
  end loop;
  if has_schema_privilege('anon', 'dados', 'usage') or has_schema_privilege('authenticated', 'dados', 'usage') then
    raise exception '20261007gr: schema dados exposto';
  end if;
end
$c$;

-- passada 2
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
         case when w.d #>> '{purchase,payment,installments_number}' ~ '^[0-9]{1,4}$'   -- valor não numérico vira null
              then (w.d #>> '{purchase,payment,installments_number}')::int end
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

-- Pós-condição: permissões como o esperado (aborta a transação se não)
do $c$
declare
  f text;
begin
  foreach f in array array['public.dados_presencial_pagamentos(text)', 'public.dados_presencial_compradores_perfil(text)',
                           'public.dados_presencial_pendencias(text)', 'public.dados_presencial_pendencias_pessoas(text,text)',
                           'public.dados_presencial_serie_vendas(text)', 'public.dados_presencial_vendas_por_hora(text)'] loop
    if not has_function_privilege('authenticated', f, 'execute') or not has_function_privilege('service_role', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or not (select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p where p.oid = f::regprocedure) then
      raise exception '20261007gr: permissão ou definição errada em %', f;
    end if;
  end loop;
  foreach f in array array['dados.transacoes_extra(text,text)', 'dados.pendencias(text,text)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '20261007gr: ajudante interno exposto: %', f;
    end if;
  end loop;
  if has_schema_privilege('anon', 'dados', 'usage') or has_schema_privilege('authenticated', 'dados', 'usage') then
    raise exception '20261007gr: schema dados exposto';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select 'grants', (select jsonb_object_agg(f, jsonb_build_object('anon', has_function_privilege('anon', f, 'execute'), 'auth', has_function_privilege('authenticated', f, 'execute'), 'service', has_function_privilege('service_role', f, 'execute'), 'public_acl', coalesce((select array_to_string(proacl, ',') from pg_proc where oid = f::regprocedure), ''))) from unnest(array['public.dados_presencial_pagamentos(text)','public.dados_presencial_compradores_perfil(text)','public.dados_presencial_pendencias(text)','public.dados_presencial_pendencias_pessoas(text,text)','public.dados_presencial_serie_vendas(text)','public.dados_presencial_vendas_por_hora(text)','dados.transacoes_extra(text,text)','dados.pendencias(text,text)']) f)::text;
insert into pg_temp._z_out (passo, linha) select 'trava conta', coalesce(fin.trava_conta_hotmart_violacao('pg_catalog.pg_proc'::regclass, 'dados.transacoes_extra(text,text)'::regprocedure), 'ok');
insert into pg_temp._z_out (passo, linha) select 'secdef e search_path', (select jsonb_agg(p.proname || ':' || p.prosecdef || ':' || coalesce(array_to_string(p.proconfig, ','), '')) from pg_proc p where p.proname in ('dados_presencial_pagamentos','dados_presencial_compradores_perfil','dados_presencial_pendencias','dados_presencial_pendencias_pessoas','dados_presencial_serie_vendas','dados_presencial_vendas_por_hora','transacoes_extra','pendencias'))::text;

select set_config('request.jwt.claims', '{}', true);
do $t$ declare f text; r text := ''; begin
  foreach f in array array['dados_presencial_pagamentos','dados_presencial_compradores_perfil','dados_presencial_pendencias','dados_presencial_serie_vendas','dados_presencial_vendas_por_hora'] loop
    begin execute format('select count(*) from public.%I(%L)', f, 'clinica-miami-2026-12'); r := r || f || ':passou '; exception when others then r := r || f || ':' || sqlstate || ' '; end;
  end loop;
  begin perform count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago'); r := r || 'pessoas:passou'; exception when others then r := r || 'pessoas:' || sqlstate; end;
  insert into pg_temp._z_out (passo, linha) values ('gate sem login (esperado 42501)', r);
end $t$;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $t$ declare r text; begin
  begin perform count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'qualquer'); r := 'passou'; exception when others then r := sqlstate; end;
  insert into pg_temp._z_out (passo, linha) values ('grupo inválido (esperado 22023)', r);
  begin perform count(*) from public.dados_presencial_pagamentos('nao-existe'); r := 'passou'; exception when others then r := sqlstate; end;
  insert into pg_temp._z_out (passo, linha) values ('chave inexistente (esperado P0002)', r);
end $t$;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '1 Clínica hoje', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'pagamentos', (select jsonb_agg(to_jsonb(x)) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x),
  'perfil', (select jsonb_agg(x.dimensao || ':' || x.valor || '=' || x.compradores) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x),
  'pendencias', (select jsonb_agg(x.grupo || ':' || x.categoria || '=' || x.pessoas || '/' || x.transacoes) from public.dados_presencial_pendencias('clinica-miami-2026-12') x),
  'lista_nao_pago', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')),
  'lista_cancelada', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pc', s.pre_checkout, 'v', s.vendas, 'r', s.receita_bruta, 'va', s.vendas_acumuladas, 'ra', s.receita_acumulada, 'conv', s.conversao_pct)) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s where s.pre_checkout > 0 or s.vendas > 0),
  'hora', (select jsonb_agg(h.hora || 'h=' || h.vendas || '/' || h.receita_bruta) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12') h where h.vendas > 0 or h.receita_bruta > 0),
  'horas_linhas', (select count(*) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12')),
  'confere', jsonb_build_object(
     'acum_vendas=resumo', (select max(s.vendas_acumuladas) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'acum_receita=resumo', (select max(s.receita_acumulada) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s) = (select r.receita_bruta from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'hora=resumo', (select sum(h.vendas) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12') h) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'pagamentos=resumo', (select coalesce(sum(x.vendas),0) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'pag_receita=resumo', (select coalesce(sum(x.receita_bruta),0) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x) = (select r.receita_bruta from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'perfil_turma=compradores', (select coalesce(sum(x.compradores),0) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x where x.dimensao='turma') = (select r.compradores from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'perfil_instr=compradores', (select coalesce(sum(x.compradores),0) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x where x.dimensao='instrucao') = (select r.compradores from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'lista_np=total', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')) = (select x.pessoas from public.dados_presencial_pendencias('clinica-miami-2026-12') x where x.grupo='nao_pago' and x.categoria='total'),
     'lista_ca=total', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')) = (select x.pessoas from public.dados_presencial_pendencias('clinica-miami-2026-12') x where x.grupo='cancelada' and x.categoria='total'))
))::text;
select set_config('request.jwt.claims', '{}', true);

update crm.config set hotmart_ligado = false;
-- A: boleto gerado e não pago; B: cancelada e depois paga (não entra); C: pix expirado; D: aluno pagou (turma); E: cancelada sem pagar, mesmo documento de B (não entra)
insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '1 seconds', 'PURCHASE_BILLET_PRINTED', 'HPZZGR_A1', 'a@ensaio.invalid', jsonb_build_object('event', 'PURCHASE_BILLET_PRINTED', 'data', jsonb_build_object(
  'buyer', jsonb_build_object('email', 'a@ensaio.invalid', 'name', 'Ensaio', 'document', '99999999965'),
  'purchase', jsonb_build_object('status', 'BILLET_PRINTED', 'transaction', 'HPZZGR_A1', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'payment', jsonb_build_object('type', 'BILLET', 'installments_number', 1),
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now() - interval '1 hours') * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '2 seconds', 'PURCHASE_CANCELED', 'HPZZGR_B1', 'b@ensaio.invalid', jsonb_build_object('event', 'PURCHASE_CANCELED', 'data', jsonb_build_object(
  'buyer', jsonb_build_object('email', 'b@ensaio.invalid', 'name', 'Ensaio', 'document', '99999999966'),
  'purchase', jsonb_build_object('status', 'CANCELED', 'transaction', 'HPZZGR_B1', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'payment', jsonb_build_object('type', 'CREDIT_CARD', 'installments_number', 1),
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now() - interval '2 hours') * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '3 seconds', 'PURCHASE_APPROVED', 'HPZZGR_B2', 'b@ensaio.invalid', jsonb_build_object('event', 'PURCHASE_APPROVED', 'data', jsonb_build_object(
  'buyer', jsonb_build_object('email', 'b@ensaio.invalid', 'name', 'Ensaio', 'document', '99999999966'),
  'purchase', jsonb_build_object('status', 'APPROVED', 'transaction', 'HPZZGR_B2', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'payment', jsonb_build_object('type', 'PIX', 'installments_number', 1),
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now() - interval '3 hours') * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '4 seconds', 'PURCHASE_EXPIRED', 'HPZZGR_C1', 'c@ensaio.invalid', jsonb_build_object('event', 'PURCHASE_EXPIRED', 'data', jsonb_build_object(
  'buyer', jsonb_build_object('email', 'c@ensaio.invalid', 'name', 'Ensaio', 'document', '99999999967'),
  'purchase', jsonb_build_object('status', 'EXPIRED', 'transaction', 'HPZZGR_C1', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'payment', jsonb_build_object('type', 'PIX', 'installments_number', 1),
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now() - interval '4 hours') * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '5 seconds', 'PURCHASE_APPROVED', 'HPZZGR_D1', (select lower(btrim(a.email)) from public.thb_alunos a join public.thb_turmas t on t.id=a.turma_id where a.email like '%@%' and a.cancelado_em is null order by a.id limit 1), jsonb_build_object('event', 'PURCHASE_APPROVED', 'data', jsonb_build_object(
  'buyer', jsonb_build_object('email', (select lower(btrim(a.email)) from public.thb_alunos a join public.thb_turmas t on t.id=a.turma_id where a.email like '%@%' and a.cancelado_em is null order by a.id limit 1), 'name', 'Ensaio', 'document', '99999999968'),
  'purchase', jsonb_build_object('status', 'APPROVED', 'transaction', 'HPZZGR_D1', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'payment', jsonb_build_object('type', 'CREDIT_CARD', 'installments_number', 1),
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now() - interval '5 hours') * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '6 seconds', 'PURCHASE_CANCELED', 'HPZZGR_E1', 'e@ensaio.invalid', jsonb_build_object('event', 'PURCHASE_CANCELED', 'data', jsonb_build_object(
  'buyer', jsonb_build_object('email', 'e@ensaio.invalid', 'name', 'Ensaio', 'document', '99999999966'),
  'purchase', jsonb_build_object('status', 'CANCELED', 'transaction', 'HPZZGR_E1', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'payment', jsonb_build_object('type', 'CREDIT_CARD', 'installments_number', 1),
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now() - interval '6 hours') * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '2 com eventos fictícios', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'pagamentos', (select jsonb_agg(to_jsonb(x)) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x),
  'perfil', (select jsonb_agg(x.dimensao || ':' || x.valor || '=' || x.compradores) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x),
  'pendencias', (select jsonb_agg(x.grupo || ':' || x.categoria || '=' || x.pessoas || '/' || x.transacoes) from public.dados_presencial_pendencias('clinica-miami-2026-12') x),
  'lista_nao_pago', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')),
  'lista_cancelada', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pc', s.pre_checkout, 'v', s.vendas, 'r', s.receita_bruta, 'va', s.vendas_acumuladas, 'ra', s.receita_acumulada, 'conv', s.conversao_pct)) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s where s.pre_checkout > 0 or s.vendas > 0),
  'hora', (select jsonb_agg(h.hora || 'h=' || h.vendas || '/' || h.receita_bruta) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12') h where h.vendas > 0 or h.receita_bruta > 0),
  'horas_linhas', (select count(*) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12')),
  'confere', jsonb_build_object(
     'acum_vendas=resumo', (select max(s.vendas_acumuladas) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'acum_receita=resumo', (select max(s.receita_acumulada) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s) = (select r.receita_bruta from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'hora=resumo', (select sum(h.vendas) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12') h) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'pagamentos=resumo', (select coalesce(sum(x.vendas),0) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'pag_receita=resumo', (select coalesce(sum(x.receita_bruta),0) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x) = (select r.receita_bruta from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'perfil_turma=compradores', (select coalesce(sum(x.compradores),0) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x where x.dimensao='turma') = (select r.compradores from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'perfil_instr=compradores', (select coalesce(sum(x.compradores),0) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x where x.dimensao='instrucao') = (select r.compradores from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'lista_np=total', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')) = (select x.pessoas from public.dados_presencial_pendencias('clinica-miami-2026-12') x where x.grupo='nao_pago' and x.categoria='total'),
     'lista_ca=total', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')) = (select x.pessoas from public.dados_presencial_pendencias('clinica-miami-2026-12') x where x.grupo='cancelada' and x.categoria='total'))
))::text;
select set_config('request.jwt.claims', '{}', true);

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '7 seconds', 'PURCHASE_APPROVED', 'HPZZGR_F1', 'f@ensaio.invalid', jsonb_build_object('event', 'PURCHASE_APPROVED', 'data', jsonb_build_object(
  'buyer', jsonb_build_object('email', 'f@ensaio.invalid', 'name', 'Ensaio', 'document', '99999999970'),
  'purchase', jsonb_build_object('status', 'APPROVED', 'transaction', 'HPZZGR_F1', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'payment', jsonb_build_object('type', 'CREDIT_CARD', 'installments_number', 'doze'),
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now() - interval '7 hours') * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '2b parcelas não numéricas no webhook', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'pagamentos', (select jsonb_agg(to_jsonb(x)) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x),
  'perfil', (select jsonb_agg(x.dimensao || ':' || x.valor || '=' || x.compradores) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x),
  'pendencias', (select jsonb_agg(x.grupo || ':' || x.categoria || '=' || x.pessoas || '/' || x.transacoes) from public.dados_presencial_pendencias('clinica-miami-2026-12') x),
  'lista_nao_pago', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')),
  'lista_cancelada', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pc', s.pre_checkout, 'v', s.vendas, 'r', s.receita_bruta, 'va', s.vendas_acumuladas, 'ra', s.receita_acumulada, 'conv', s.conversao_pct)) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s where s.pre_checkout > 0 or s.vendas > 0),
  'hora', (select jsonb_agg(h.hora || 'h=' || h.vendas || '/' || h.receita_bruta) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12') h where h.vendas > 0 or h.receita_bruta > 0),
  'horas_linhas', (select count(*) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12')),
  'confere', jsonb_build_object(
     'acum_vendas=resumo', (select max(s.vendas_acumuladas) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'acum_receita=resumo', (select max(s.receita_acumulada) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s) = (select r.receita_bruta from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'hora=resumo', (select sum(h.vendas) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12') h) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'pagamentos=resumo', (select coalesce(sum(x.vendas),0) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'pag_receita=resumo', (select coalesce(sum(x.receita_bruta),0) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x) = (select r.receita_bruta from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'perfil_turma=compradores', (select coalesce(sum(x.compradores),0) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x where x.dimensao='turma') = (select r.compradores from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'perfil_instr=compradores', (select coalesce(sum(x.compradores),0) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x where x.dimensao='instrucao') = (select r.compradores from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'lista_np=total', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')) = (select x.pessoas from public.dados_presencial_pendencias('clinica-miami-2026-12') x where x.grupo='nao_pago' and x.categoria='total'),
     'lista_ca=total', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')) = (select x.pessoas from public.dados_presencial_pendencias('clinica-miami-2026-12') x where x.grupo='cancelada' and x.categoria='total'))
))::text;
select set_config('request.jwt.claims', '{}', true);

delete from cs.hotmart_eventos where transacao like 'HPZZGR_%';
update crm.config set hotmart_ligado = true;
-- volume: aponta o dashboard (só nesta transação) para a oferta academy com mais transações nos últimos 60 dias
update dados.dashboards set oferta_codigo = (select oferta_codigo from fin.hotmart_transacoes where conta='academy' and pedido_em > now()-interval '60 days' group by 1 order by count(*) desc limit 1), ofertas_extra = '{}' where chave = 'clinica-miami-2026-12';
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '3 volume (outra oferta)', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'pagamentos', (select jsonb_agg(to_jsonb(x)) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x),
  'perfil', (select jsonb_agg(x.dimensao || ':' || x.valor || '=' || x.compradores) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x),
  'pendencias', (select jsonb_agg(x.grupo || ':' || x.categoria || '=' || x.pessoas || '/' || x.transacoes) from public.dados_presencial_pendencias('clinica-miami-2026-12') x),
  'lista_nao_pago', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')),
  'lista_cancelada', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pc', s.pre_checkout, 'v', s.vendas, 'r', s.receita_bruta, 'va', s.vendas_acumuladas, 'ra', s.receita_acumulada, 'conv', s.conversao_pct)) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s where s.pre_checkout > 0 or s.vendas > 0),
  'hora', (select jsonb_agg(h.hora || 'h=' || h.vendas || '/' || h.receita_bruta) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12') h where h.vendas > 0 or h.receita_bruta > 0),
  'horas_linhas', (select count(*) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12')),
  'confere', jsonb_build_object(
     'acum_vendas=resumo', (select max(s.vendas_acumuladas) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'acum_receita=resumo', (select max(s.receita_acumulada) from public.dados_presencial_serie_vendas('clinica-miami-2026-12') s) = (select r.receita_bruta from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'hora=resumo', (select sum(h.vendas) from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12') h) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'pagamentos=resumo', (select coalesce(sum(x.vendas),0) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x) = (select r.vendas from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'pag_receita=resumo', (select coalesce(sum(x.receita_bruta),0) from public.dados_presencial_pagamentos('clinica-miami-2026-12') x) = (select r.receita_bruta from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'perfil_turma=compradores', (select coalesce(sum(x.compradores),0) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x where x.dimensao='turma') = (select r.compradores from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'perfil_instr=compradores', (select coalesce(sum(x.compradores),0) from public.dados_presencial_compradores_perfil('clinica-miami-2026-12') x where x.dimensao='instrucao') = (select r.compradores from public.dados_presencial_resumo('clinica-miami-2026-12') r),
     'lista_np=total', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')) = (select x.pessoas from public.dados_presencial_pendencias('clinica-miami-2026-12') x where x.grupo='nao_pago' and x.categoria='total'),
     'lista_ca=total', (select count(*) from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')) = (select x.pessoas from public.dados_presencial_pendencias('clinica-miami-2026-12') x where x.grupo='cancelada' and x.categoria='total'))
))::text;
select set_config('request.jwt.claims', '{}', true);

create temp table _z_t (t numeric) on commit drop;
do $x$ declare t0 timestamptz; f text; begin
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  foreach f in array array['dados_presencial_pagamentos','dados_presencial_compradores_perfil','dados_presencial_pendencias','dados_presencial_serie_vendas','dados_presencial_vendas_por_hora','dados_presencial_resumo'] loop
    t0 := clock_timestamp(); execute format('select count(*) from public.%I(%L)', f, 'clinica-miami-2026-12');
    insert into pg_temp._z_out (passo, linha) values ('tempo volume ' || f, round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms');
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
end $x$;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
