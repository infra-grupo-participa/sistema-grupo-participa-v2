-- 20261007tr: dashboard presencial mostra a venda em segundos, lendo também o webhook da Hotmart.
--
-- STATUS: APLICADA em produção em 07/10/2026 às 20:50 UTC, versão 20261007205017 (nome dashboard_vendas_tempo_real, era
-- 20261007tr), com a linha em supabase_migrations.schema_migrations na mesma transação; md5 gravado =
-- 000da904ebe10d23b9af0af20e7818e9 = este arquivo antes desta troca de STATUS. Ensaio: 20261007205017_ensaio.sql.
-- Relatório: 20261007205017.explain.md.
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
