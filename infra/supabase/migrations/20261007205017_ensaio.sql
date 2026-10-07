-- Ensaio de 20261007tr (aplicada como 20261007205017) (dashboard presencial em tempo real pelo webhook): 2 passadas, regressão por oferta,
-- venda simulada (evento fictício, e-mail .invalid), dedupe com o espelho, explain, reversão. Transação desfeita.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '170s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated; grant all on sequence pg_temp._z_out_em_seq to authenticated;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '1 antes', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'vendas_status', (select jsonb_agg(v order by v) from (select to_jsonb(x) - 'email' - 'nome' - 'telefone' - 'transacao' v from public.dados_presencial_vendas('clinica-miami-2026-12') x) z),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0)
))::text;
select set_config('request.jwt.claims', '{}', true);

insert into pg_temp._z_out (passo, linha) select '1r antes', (select jsonb_object_agg(o, jsonb_build_object('n', n, 'pagos', pg, 'bruto', br)) from (
  select o.o, (select count(*) from dados.transacoes('academy', o.o)) n, (select count(*) filter (where pago) from dados.transacoes('academy', o.o)) pg, (select sum(valor_bruto) from dados.transacoes('academy', o.o)) br
    from (select distinct payload #>> '{data,purchase,offer,code}' o from cs.hotmart_eventos where recebido_em > now() - interval '60 days' and payload #>> '{data,purchase,offer,code}' is not null) o) z)::text;

-- passada 1
-- 20261007tr: dashboard presencial mostra a venda em segundos, lendo também o webhook da Hotmart.
--
-- STATUS: NÃO APLICADA.
--
-- POR QUE
--   O Victor Hugo (07/10/2026, noite): "quero em tempo real assim q cair pra gente monitorar em tempo real conforme cai a
--   venda". Hoje dados.transacoes lê só o espelho do Financeiro, que só a edge hotmart-sync grava, de hora em hora
--   (cron fin-hotmart-sync-rotina, minuto 7). Medido em 07/10 20:44 UTC, conta academy, transações dos últimos 7 dias
--   (55): atraso entre a compra e a linha aparecer = mediana 28,9 min, p90 47,3 min, máximo 59,5 min.
--   O webhook da Hotmart (edge hotmart-events-webhook do disparos-thb, do João) grava cada evento em cs.hotmart_eventos
--   na hora: PURCHASE_APPROVED chega em mediana 15 s (máximo 105,5 s) depois da aprovação (32 eventos em 7 dias).
--
-- O QUE FAZ
--   dados.transacoes (só o corpo; assinatura, colunas e grants iguais) devolve, além das linhas do espelho, as transações
--   das ofertas do dashboard que o webhook já recebeu e o sync ainda não trouxe. Quando o sync traz a transação, a linha
--   do webhook some sozinha (anti-join pela transação): nada conta duas vezes e o espelho continua mandando.
--   Linha do webhook = último evento PURCHASE_* com status daquela transação (por recebido_em), com o status traduzido
--   para o nome do espelho. Tradução provada em 07/10 contra as transações que estão nos dois lados:
--     COMPLETED → COMPLETE, CANCELED → CANCELLED, BILLET_PRINTED → PRINTED_BILLET, DELAYED → OVERDUE,
--     DISPUTE → PROTESTED; os demais (APPROVED, CHARGEBACK, EXPIRED, REFUNDED) já têm o mesmo nome.
--   Campos (conferidos em 543 transações aprovadas que estão nos dois lados): bruto = purchase.price.value (= valor base
--   do espelho em 541 de 543), líquido = commissions[source = PRODUCER].value (= liquido_produtor em 538 de 538),
--   pedido_em/aprovado_em = order_date/approved_date (543 de 543), moeda (543 de 543), e-mail (543 de 543).
--   Nome, telefone e UF vêm do checkout e podem diferir do espelho até o sync passar.
--   As 5 funções dados_presencial_* não mudam. Sem GRANT, RLS nem policy: cs.hotmart_eventos é lida pelo dono da função
--   (postgres), dentro das dados_presencial_* (security definer), que já checam dados.pode_ver.
--
-- LIMITES (não resolvidos aqui)
--   - O webhook só cobre a conta academy (a Clínica é academy). Escritório continua de hora em hora.
--   - Pedido em WAITING_PAYMENT (Pix/boleto gerado) não gera evento: aparece só pelo sync.
--   - A tela não se atualiza sozinha (só no botão Atualizar). Isso é do front.
--
-- AS 5 PERGUNTAS
--   escala: cs.hotmart_eventos tem 2.674 linhas (07/10); o filtro pela oferta lê a tabela inteira (sem índice no jsonb),
--   custo medido no explain. índice: anti-join usa a chave da transação no espelho; distinct on usa
--   hotmart_eventos_transacao_ix. frequência: a cada abertura/atualização do dashboard, igual a hoje. repetição: nenhuma.
--   reversão: corpo antigo guardado em acesso.corpo_antes (migration '20261007tr') e bloco REVERSÃO no rodapé.
--
-- IDEMPOTENTE: o corpo só é trocado se ainda for o vivo (md5); se já for o novo, não faz nada.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- 0. Premissas
do $g$
begin
  if to_regprocedure('dados.transacoes(text,text)') is null then
    raise exception '20261007tr: dados.transacoes(text,text) não existe';
  end if;
  if to_regclass('cs.hotmart_eventos') is null then
    raise exception '20261007tr: cs.hotmart_eventos não existe';
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'cs' and table_name = 'hotmart_eventos'
         and column_name in ('transacao', 'evento', 'recebido_em', 'payload')) <> 4 then
    raise exception '20261007tr: cs.hotmart_eventos sem as colunas esperadas';
  end if;
  if position('20261007ma' in pg_get_functiondef('dados.transacoes(text,text)'::regprocedure)) = 0
     and position('20261007tr' in pg_get_functiondef('dados.transacoes(text,text)'::regprocedure)) = 0 then
    raise exception '20261007tr: corpo vivo de dados.transacoes não é o da 20261007ma; conferir antes';
  end if;
end
$g$;

-- 1. Guarda o corpo de antes (uma vez; não guarda se o vivo já for o novo)
insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007tr'
  from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure
   and p.prosrc !~ '20261007tr'
on conflict do nothing;

-- 2. Corpo novo
create or replace function dados.transacoes(p_conta text, p_oferta text)
 returns table(transacao text, status text, status_grupo text, pago boolean, primeira boolean, pedido_em timestamp with time zone, aprovado_em timestamp with time zone, dia_pedido date, dia_aprovado date, moeda text, valor_bruto numeric, valor_liquido numeric, email text, nome text, telefone text, estado text)
 language plpgsql
 stable
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  v_conta text := p_conta;
  v_ofertas text[];  -- 20261007tr: oferta principal + ofertas_extra
begin
  v_ofertas := array[p_oferta] || coalesce((select d.ofertas_extra from dados.dashboards d   -- 20261007ma: ofertas_extra
                                             where d.conta_hotmart = p_conta and d.oferta_codigo = p_oferta and d.ativo
                                             limit 1), '{}'::text[]);
  return query
  with espelho as (
    select t.transacao, t.status, t.recorrencia, t.pedido_em, t.aprovado_em, t.moeda,
           coalesce(t.valor_base, nullif(t.bruto_json #>> '{purchase,hotmart_fee,base}', '')::numeric, t.valor_cobrado) as bruto,
           t.liquido_produtor, t.taxa_hotmart,
           t.comprador_email, t.comprador_nome, t.comprador_telefone, t.comprador_uf
      from (select * from fin.hotmart_transacoes where conta = v_conta) t
     where t.oferta_codigo = any (v_ofertas)
  ),
  -- 20261007tr: o que o webhook já recebeu e o sync ainda não trouxe (some quando o sync traz)
  webhook as (
    select distinct on (e.transacao)
           e.transacao, e.payload -> 'data' as d
      from cs.hotmart_eventos e
     where v_conta = 'academy'
       and e.transacao is not null
       and e.evento like 'PURCHASE%'
       and e.payload #>> '{data,purchase,status}' is not null
       and e.payload #>> '{data,purchase,offer,code}' = any (v_ofertas)
       and not exists (select 1 from (select * from fin.hotmart_transacoes where conta = v_conta) h
                        where h.transacao = e.transacao)
     order by e.transacao, e.recebido_em desc, e.id desc
  ),
  linhas as (
    select * from espelho
    union all
    select w.transacao,
           case w.d #>> '{purchase,status}'
             when 'COMPLETED' then 'COMPLETE'
             when 'CANCELED' then 'CANCELLED'
             when 'BILLET_PRINTED' then 'PRINTED_BILLET'
             when 'DELAYED' then 'OVERDUE'
             when 'DISPUTE' then 'PROTESTED'
             else w.d #>> '{purchase,status}' end,
           nullif(w.d #>> '{purchase,recurrence_number}', '')::int,
           to_timestamp(nullif(w.d #>> '{purchase,order_date}', '')::bigint / 1000.0),
           to_timestamp(nullif(w.d #>> '{purchase,approved_date}', '')::bigint / 1000.0),
           w.d #>> '{purchase,price,currency_value}',
           nullif(w.d #>> '{purchase,price,value}', '')::numeric,
           (select nullif(c ->> 'value', '')::numeric from jsonb_array_elements(coalesce(w.d -> 'commissions', '[]'::jsonb)) c
             where c ->> 'source' = 'PRODUCER' limit 1),
           null::numeric,
           w.d #>> '{buyer,email}', w.d #>> '{buyer,name}', w.d #>> '{buyer,checkout_phone}',
           w.d #>> '{buyer,address,state}'
      from webhook w
  )
  select l.transacao, l.status,
         case when l.status in ('APPROVED', 'COMPLETE') then 'pago'
              when l.status in ('REFUNDED', 'PARTIALLY_REFUNDED', 'CHARGEBACK') then 'estornado'
              when l.status in ('OVERDUE', 'PROTESTED') then 'atrasado'
              when l.status in ('PRINTED_BILLET', 'WAITING_PAYMENT', 'UNDER_ANALISYS', 'STARTED') then 'em_aberto'
              when l.status in ('CANCELLED', 'NO_FUNDS', 'BLOCKED') then 'recusado'
              when l.status = 'EXPIRED' then 'expirado'
              else 'outro' end,
         l.status in ('APPROVED', 'COMPLETE'),
         coalesce(l.recorrencia, 1) = 1,
         l.pedido_em, l.aprovado_em,
         (l.pedido_em at time zone 'America/Sao_Paulo')::date,
         (l.aprovado_em at time zone 'America/Sao_Paulo')::date,
         coalesce(l.moeda, 'BRL'),
         l.bruto::numeric(14,2),
         coalesce(l.liquido_produtor, l.bruto - coalesce(l.taxa_hotmart, 0))::numeric(14,2),
         nullif(lower(btrim(l.comprador_email)), ''),
         nullif(btrim(l.comprador_nome), ''),
         nullif(btrim(l.comprador_telefone), ''),
         nullif(btrim(l.comprador_uf), '')
    from linhas l;
end
$function$;

-- REVERSÃO (não roda aqui): volta o corpo guardado
--   do $r$ begin execute (select definicao from acesso.corpo_antes where migration = '20261007tr'
--                          and alvo = 'dados.transacoes(text,text)'); end $r$;

-- passada 2
-- 20261007tr: dashboard presencial mostra a venda em segundos, lendo também o webhook da Hotmart.
--
-- STATUS: NÃO APLICADA.
--
-- POR QUE
--   O Victor Hugo (07/10/2026, noite): "quero em tempo real assim q cair pra gente monitorar em tempo real conforme cai a
--   venda". Hoje dados.transacoes lê só o espelho do Financeiro, que só a edge hotmart-sync grava, de hora em hora
--   (cron fin-hotmart-sync-rotina, minuto 7). Medido em 07/10 20:44 UTC, conta academy, transações dos últimos 7 dias
--   (55): atraso entre a compra e a linha aparecer = mediana 28,9 min, p90 47,3 min, máximo 59,5 min.
--   O webhook da Hotmart (edge hotmart-events-webhook do disparos-thb, do João) grava cada evento em cs.hotmart_eventos
--   na hora: PURCHASE_APPROVED chega em mediana 15 s (máximo 105,5 s) depois da aprovação (32 eventos em 7 dias).
--
-- O QUE FAZ
--   dados.transacoes (só o corpo; assinatura, colunas e grants iguais) devolve, além das linhas do espelho, as transações
--   das ofertas do dashboard que o webhook já recebeu e o sync ainda não trouxe. Quando o sync traz a transação, a linha
--   do webhook some sozinha (anti-join pela transação): nada conta duas vezes e o espelho continua mandando.
--   Linha do webhook = último evento PURCHASE_* com status daquela transação (por recebido_em), com o status traduzido
--   para o nome do espelho. Tradução provada em 07/10 contra as transações que estão nos dois lados:
--     COMPLETED → COMPLETE, CANCELED → CANCELLED, BILLET_PRINTED → PRINTED_BILLET, DELAYED → OVERDUE,
--     DISPUTE → PROTESTED; os demais (APPROVED, CHARGEBACK, EXPIRED, REFUNDED) já têm o mesmo nome.
--   Campos (conferidos em 543 transações aprovadas que estão nos dois lados): bruto = purchase.price.value (= valor base
--   do espelho em 541 de 543), líquido = commissions[source = PRODUCER].value (= liquido_produtor em 538 de 538),
--   pedido_em/aprovado_em = order_date/approved_date (543 de 543), moeda (543 de 543), e-mail (543 de 543).
--   Nome, telefone e UF vêm do checkout e podem diferir do espelho até o sync passar.
--   As 5 funções dados_presencial_* não mudam. Sem GRANT, RLS nem policy: cs.hotmart_eventos é lida pelo dono da função
--   (postgres), dentro das dados_presencial_* (security definer), que já checam dados.pode_ver.
--
-- LIMITES (não resolvidos aqui)
--   - O webhook só cobre a conta academy (a Clínica é academy). Escritório continua de hora em hora.
--   - Pedido em WAITING_PAYMENT (Pix/boleto gerado) não gera evento: aparece só pelo sync.
--   - A tela não se atualiza sozinha (só no botão Atualizar). Isso é do front.
--
-- AS 5 PERGUNTAS
--   escala: cs.hotmart_eventos tem 2.674 linhas (07/10); o filtro pela oferta lê a tabela inteira (sem índice no jsonb),
--   custo medido no explain. índice: anti-join usa a chave da transação no espelho; distinct on usa
--   hotmart_eventos_transacao_ix. frequência: a cada abertura/atualização do dashboard, igual a hoje. repetição: nenhuma.
--   reversão: corpo antigo guardado em acesso.corpo_antes (migration '20261007tr') e bloco REVERSÃO no rodapé.
--
-- IDEMPOTENTE: o corpo só é trocado se ainda for o vivo (md5); se já for o novo, não faz nada.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- 0. Premissas
do $g$
begin
  if to_regprocedure('dados.transacoes(text,text)') is null then
    raise exception '20261007tr: dados.transacoes(text,text) não existe';
  end if;
  if to_regclass('cs.hotmart_eventos') is null then
    raise exception '20261007tr: cs.hotmart_eventos não existe';
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'cs' and table_name = 'hotmart_eventos'
         and column_name in ('transacao', 'evento', 'recebido_em', 'payload')) <> 4 then
    raise exception '20261007tr: cs.hotmart_eventos sem as colunas esperadas';
  end if;
  if position('20261007ma' in pg_get_functiondef('dados.transacoes(text,text)'::regprocedure)) = 0
     and position('20261007tr' in pg_get_functiondef('dados.transacoes(text,text)'::regprocedure)) = 0 then
    raise exception '20261007tr: corpo vivo de dados.transacoes não é o da 20261007ma; conferir antes';
  end if;
end
$g$;

-- 1. Guarda o corpo de antes (uma vez; não guarda se o vivo já for o novo)
insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007tr'
  from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure
   and p.prosrc !~ '20261007tr'
on conflict do nothing;

-- 2. Corpo novo
create or replace function dados.transacoes(p_conta text, p_oferta text)
 returns table(transacao text, status text, status_grupo text, pago boolean, primeira boolean, pedido_em timestamp with time zone, aprovado_em timestamp with time zone, dia_pedido date, dia_aprovado date, moeda text, valor_bruto numeric, valor_liquido numeric, email text, nome text, telefone text, estado text)
 language plpgsql
 stable
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  v_conta text := p_conta;
  v_ofertas text[];  -- 20261007tr: oferta principal + ofertas_extra
begin
  v_ofertas := array[p_oferta] || coalesce((select d.ofertas_extra from dados.dashboards d   -- 20261007ma: ofertas_extra
                                             where d.conta_hotmart = p_conta and d.oferta_codigo = p_oferta and d.ativo
                                             limit 1), '{}'::text[]);
  return query
  with espelho as (
    select t.transacao, t.status, t.recorrencia, t.pedido_em, t.aprovado_em, t.moeda,
           coalesce(t.valor_base, nullif(t.bruto_json #>> '{purchase,hotmart_fee,base}', '')::numeric, t.valor_cobrado) as bruto,
           t.liquido_produtor, t.taxa_hotmart,
           t.comprador_email, t.comprador_nome, t.comprador_telefone, t.comprador_uf
      from (select * from fin.hotmart_transacoes where conta = v_conta) t
     where t.oferta_codigo = any (v_ofertas)
  ),
  -- 20261007tr: o que o webhook já recebeu e o sync ainda não trouxe (some quando o sync traz)
  webhook as (
    select distinct on (e.transacao)
           e.transacao, e.payload -> 'data' as d
      from cs.hotmart_eventos e
     where v_conta = 'academy'
       and e.transacao is not null
       and e.evento like 'PURCHASE%'
       and e.payload #>> '{data,purchase,status}' is not null
       and e.payload #>> '{data,purchase,offer,code}' = any (v_ofertas)
       and not exists (select 1 from (select * from fin.hotmart_transacoes where conta = v_conta) h
                        where h.transacao = e.transacao)
     order by e.transacao, e.recebido_em desc, e.id desc
  ),
  linhas as (
    select * from espelho
    union all
    select w.transacao,
           case w.d #>> '{purchase,status}'
             when 'COMPLETED' then 'COMPLETE'
             when 'CANCELED' then 'CANCELLED'
             when 'BILLET_PRINTED' then 'PRINTED_BILLET'
             when 'DELAYED' then 'OVERDUE'
             when 'DISPUTE' then 'PROTESTED'
             else w.d #>> '{purchase,status}' end,
           nullif(w.d #>> '{purchase,recurrence_number}', '')::int,
           to_timestamp(nullif(w.d #>> '{purchase,order_date}', '')::bigint / 1000.0),
           to_timestamp(nullif(w.d #>> '{purchase,approved_date}', '')::bigint / 1000.0),
           w.d #>> '{purchase,price,currency_value}',
           nullif(w.d #>> '{purchase,price,value}', '')::numeric,
           (select nullif(c ->> 'value', '')::numeric from jsonb_array_elements(coalesce(w.d -> 'commissions', '[]'::jsonb)) c
             where c ->> 'source' = 'PRODUCER' limit 1),
           null::numeric,
           w.d #>> '{buyer,email}', w.d #>> '{buyer,name}', w.d #>> '{buyer,checkout_phone}',
           w.d #>> '{buyer,address,state}'
      from webhook w
  )
  select l.transacao, l.status,
         case when l.status in ('APPROVED', 'COMPLETE') then 'pago'
              when l.status in ('REFUNDED', 'PARTIALLY_REFUNDED', 'CHARGEBACK') then 'estornado'
              when l.status in ('OVERDUE', 'PROTESTED') then 'atrasado'
              when l.status in ('PRINTED_BILLET', 'WAITING_PAYMENT', 'UNDER_ANALISYS', 'STARTED') then 'em_aberto'
              when l.status in ('CANCELLED', 'NO_FUNDS', 'BLOCKED') then 'recusado'
              when l.status = 'EXPIRED' then 'expirado'
              else 'outro' end,
         l.status in ('APPROVED', 'COMPLETE'),
         coalesce(l.recorrencia, 1) = 1,
         l.pedido_em, l.aprovado_em,
         (l.pedido_em at time zone 'America/Sao_Paulo')::date,
         (l.aprovado_em at time zone 'America/Sao_Paulo')::date,
         coalesce(l.moeda, 'BRL'),
         l.bruto::numeric(14,2),
         coalesce(l.liquido_produtor, l.bruto - coalesce(l.taxa_hotmart, 0))::numeric(14,2),
         nullif(lower(btrim(l.comprador_email)), ''),
         nullif(btrim(l.comprador_nome), ''),
         nullif(btrim(l.comprador_telefone), ''),
         nullif(btrim(l.comprador_uf), '')
    from linhas l;
end
$function$;

-- REVERSÃO (não roda aqui): volta o corpo guardado
--   do $r$ begin execute (select definicao from acesso.corpo_antes where migration = '20261007tr'
--                          and alvo = 'dados.transacoes(text,text)'); end $r$;

insert into pg_temp._z_out (passo, linha) select 'corpo_antes 20261007tr', count(*)::text from acesso.corpo_antes where migration='20261007tr';
insert into pg_temp._z_out (passo, linha) select 'trava conta', coalesce(fin.trava_conta_hotmart_violacao('pg_catalog.pg_proc'::regclass, 'dados.transacoes(text,text)'::regprocedure), 'ok');
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '2 depois', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'vendas_status', (select jsonb_agg(v order by v) from (select to_jsonb(x) - 'email' - 'nome' - 'telefone' - 'transacao' v from public.dados_presencial_vendas('clinica-miami-2026-12') x) z),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0)
))::text;
select set_config('request.jwt.claims', '{}', true);

insert into pg_temp._z_out (passo, linha) select '2r depois', (select jsonb_object_agg(o, jsonb_build_object('n', n, 'pagos', pg, 'bruto', br)) from (
  select o.o, (select count(*) from dados.transacoes('academy', o.o)) n, (select count(*) filter (where pago) from dados.transacoes('academy', o.o)) pg, (select sum(valor_bruto) from dados.transacoes('academy', o.o)) br
    from (select distinct payload #>> '{data,purchase,offer,code}' o from cs.hotmart_eventos where recebido_em > now() - interval '60 days' and payload #>> '{data,purchase,offer,code}' is not null) o) z)::text;

insert into pg_temp._z_out (passo, linha) select 'regressao: ofertas que mudaram', coalesce((select jsonb_agg(k)::text from jsonb_each((select linha::jsonb from pg_temp._z_out where passo='1r antes')) a(k, v) where v is distinct from ((select linha::jsonb from pg_temp._z_out where passo='2r depois') -> k)), '[]');
insert into pg_temp._z_out (passo, linha) select 'webhook sem espelho (esperado = diferença)', (select count(distinct e.transacao) from cs.hotmart_eventos e where e.transacao is not null and e.evento like 'PURCHASE%' and e.payload #>> '{data,purchase,status}' is not null and e.recebido_em > now() - interval '60 days' and not exists (select 1 from fin.hotmart_transacoes h where h.conta='academy' and h.transacao = e.transacao))::text;
insert into pg_temp._z_out (passo, linha) select 'diferenca de linhas total', ((select sum((v->>'n')::int) from jsonb_each((select linha::jsonb from pg_temp._z_out where passo='2r depois')) x(k,v)) - (select sum((v->>'n')::int) from jsonb_each((select linha::jsonb from pg_temp._z_out where passo='1r antes')) x(k,v)))::text;
-- simulação: CRM desligado só dentro desta transação, para o gatilho não processar o evento fictício
update crm.config set hotmart_ligado = false;

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '1 seconds', 'PURCHASE_APPROVED', 'HPZZENSAIOTR01', 'ensaio@exemplo.invalid', jsonb_build_object('event', 'PURCHASE_APPROVED', 'data', jsonb_build_object(
  'product', jsonb_build_object('id', 5682989),
  'buyer', jsonb_build_object('email', 'ensaio@exemplo.invalid', 'name', 'Ensaio Tempo Real', 'checkout_phone', '000', 'address', jsonb_build_object('state', 'ZZ')),
  'commissions', jsonb_build_array(jsonb_build_object('source', 'MARKETPLACE', 'value', 500.00), jsonb_build_object('source', 'PRODUCER', 'value', 4514.20)),
  'purchase', jsonb_build_object('status', 'APPROVED', 'transaction', 'HPZZENSAIOTR01', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now()) * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '3 venda simulada APPROVED', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'vendas_status', (select jsonb_agg(v order by v) from (select to_jsonb(x) - 'email' - 'nome' - 'telefone' - 'transacao' v from public.dados_presencial_vendas('clinica-miami-2026-12') x) z),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0)
))::text;
select set_config('request.jwt.claims', '{}', true);

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '2 seconds', 'PURCHASE_COMPLETE', 'HPZZENSAIOTR01', 'ensaio@exemplo.invalid', jsonb_build_object('event', 'PURCHASE_COMPLETE', 'data', jsonb_build_object(
  'product', jsonb_build_object('id', 5682989),
  'buyer', jsonb_build_object('email', 'ensaio@exemplo.invalid', 'name', 'Ensaio Tempo Real', 'checkout_phone', '000', 'address', jsonb_build_object('state', 'ZZ')),
  'commissions', jsonb_build_array(jsonb_build_object('source', 'MARKETPLACE', 'value', 500.00), jsonb_build_object('source', 'PRODUCER', 'value', 4514.20)),
  'purchase', jsonb_build_object('status', 'COMPLETED', 'transaction', 'HPZZENSAIOTR01', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now()) * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '4 mesma venda COMPLETED (1 linha)', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'vendas_status', (select jsonb_agg(v order by v) from (select to_jsonb(x) - 'email' - 'nome' - 'telefone' - 'transacao' v from public.dados_presencial_vendas('clinica-miami-2026-12') x) z),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0)
))::text;
select set_config('request.jwt.claims', '{}', true);

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '3 seconds', 'PURCHASE_APPROVED', (select transacao from fin.hotmart_transacoes where conta='academy' and oferta_codigo='mjzv4v0s' limit 1), 'ensaio@exemplo.invalid', jsonb_build_object('event', 'PURCHASE_APPROVED', 'data', jsonb_build_object(
  'product', jsonb_build_object('id', 5682989),
  'buyer', jsonb_build_object('email', 'ensaio@exemplo.invalid', 'name', 'Ensaio Tempo Real', 'checkout_phone', '000', 'address', jsonb_build_object('state', 'ZZ')),
  'commissions', jsonb_build_array(jsonb_build_object('source', 'MARKETPLACE', 'value', 500.00), jsonb_build_object('source', 'PRODUCER', 'value', 4514.20)),
  'purchase', jsonb_build_object('status', 'APPROVED', 'transaction', (select transacao from fin.hotmart_transacoes where conta='academy' and oferta_codigo='mjzv4v0s' limit 1), 'offer', jsonb_build_object('code', 'mjzv4v0s'), 'recurrence_number', 1,
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now()) * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '5 evento de transacao que o espelho ja tem (nao muda)', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'vendas_status', (select jsonb_agg(v order by v) from (select to_jsonb(x) - 'email' - 'nome' - 'telefone' - 'transacao' v from public.dados_presencial_vendas('clinica-miami-2026-12') x) z),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0)
))::text;
select set_config('request.jwt.claims', '{}', true);

insert into cs.hotmart_eventos (recebido_em, evento, transacao, email, payload)
select clock_timestamp() + interval '4 seconds', 'PURCHASE_CANCELED', 'HPZZENSAIOTR01', 'ensaio@exemplo.invalid', jsonb_build_object('event', 'PURCHASE_CANCELED', 'data', jsonb_build_object(
  'product', jsonb_build_object('id', 5682989),
  'buyer', jsonb_build_object('email', 'ensaio@exemplo.invalid', 'name', 'Ensaio Tempo Real', 'checkout_phone', '000', 'address', jsonb_build_object('state', 'ZZ')),
  'commissions', jsonb_build_array(jsonb_build_object('source', 'MARKETPLACE', 'value', 500.00), jsonb_build_object('source', 'PRODUCER', 'value', 4514.20)),
  'purchase', jsonb_build_object('status', 'CANCELED', 'transaction', 'HPZZENSAIOTR01', 'offer', jsonb_build_object('code', 'sju5pawn'), 'recurrence_number', 1,
     'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now()) * 1000)::bigint,
     'price', jsonb_build_object('value', 5014.2, 'currency_value', 'BRL'))));

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '6 simulada CANCELED (sai das vendas)', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'vendas_status', (select jsonb_agg(v order by v) from (select to_jsonb(x) - 'email' - 'nome' - 'telefone' - 'transacao' v from public.dados_presencial_vendas('clinica-miami-2026-12') x) z),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0)
))::text;
select set_config('request.jwt.claims', '{}', true);

insert into pg_temp._z_out (passo, linha) select 'linha simulada', (select (to_jsonb(t) - 'email' - 'nome' - 'telefone')::text from dados.transacoes('academy','sju5pawn') t where t.transacao = 'HPZZENSAIOTR01');
insert into pg_temp._z_out (passo, linha) select 'transacao do espelho aparece 1 vez', (select count(*)::text from dados.transacoes('academy','sju5pawn') t where t.transacao = (select transacao from fin.hotmart_transacoes where conta='academy' and oferta_codigo='mjzv4v0s' limit 1));

-- explain
create temp table _z_ex (l text) on commit drop;
do $x$ declare r record; v_top text; begin
  for r in explain (analyze, buffers) select * from dados.transacoes('academy','sju5pawn') loop insert into pg_temp._z_out (passo, linha) values ('explain sju5pawn', r."QUERY PLAN"); end loop;
  select payload #>> '{data,purchase,offer,code}' into v_top from cs.hotmart_eventos where payload #>> '{data,purchase,offer,code}' is not null group by 1 order by count(*) desc limit 1;
  for r in explain (analyze, buffers) select * from dados.transacoes('academy', v_top) loop insert into pg_temp._z_out (passo, linha) values ('explain oferta mais movimentada', r."QUERY PLAN"); end loop;
end $x$;
-- reversão
delete from cs.hotmart_eventos where email = 'ensaio@exemplo.invalid';
update crm.config set hotmart_ligado = true;
do $r$ begin execute (select definicao from acesso.corpo_antes where migration = '20261007tr' and alvo = 'dados.transacoes(text,text)'); end $r$;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (passo, linha) select '7 depois da reversao', (select jsonb_build_object(
  'resumo', (select jsonb_build_object('vendas', r.vendas, 'compradores', r.compradores, 'bruta', r.receita_bruta, 'pre_checkout', r.pre_checkout_pessoas) from public.dados_presencial_resumo('clinica-miami-2026-12') r),
  'vendas_linhas', (select count(*) from public.dados_presencial_vendas('clinica-miami-2026-12')),
  'vendas_status', (select jsonb_agg(v order by v) from (select to_jsonb(x) - 'email' - 'nome' - 'telefone' - 'transacao' v from public.dados_presencial_vendas('clinica-miami-2026-12') x) z),
  'serie', (select jsonb_agg(jsonb_build_object('dia', s.dia, 'pedidos', s.pedidos, 'vendas', s.vendas)) from public.dados_presencial_serie_diaria('clinica-miami-2026-12') s where s.pedidos > 0 or s.vendas > 0)
))::text;
select set_config('request.jwt.claims', '{}', true);

insert into pg_temp._z_out (passo, linha) select '7r depois da reversao', (select jsonb_object_agg(o, jsonb_build_object('n', n, 'pagos', pg, 'bruto', br)) from (
  select o.o, (select count(*) from dados.transacoes('academy', o.o)) n, (select count(*) filter (where pago) from dados.transacoes('academy', o.o)) pg, (select sum(valor_bruto) from dados.transacoes('academy', o.o)) br
    from (select distinct payload #>> '{data,purchase,offer,code}' o from cs.hotmart_eventos where recebido_em > now() - interval '60 days' and payload #>> '{data,purchase,offer,code}' is not null) o) z)::text;

insert into pg_temp._z_out (passo, linha) select 'reversao volta igual', ((select linha from pg_temp._z_out where passo='1 antes') = (select linha from pg_temp._z_out where passo='7 depois da reversao') and (select linha from pg_temp._z_out where passo='1r antes') = (select linha from pg_temp._z_out where passo='7r depois da reversao'))::text;
delete from pg_temp._z_out where passo in ('1r antes','2r depois','7r depois da reversao');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
