-- 20261013193000 (marca 20261013av): venda da conta escritório aparece no dashboard em segundos (Sessão de Viabilidade
-- do Seminário ATM, chave atm-elaine-1-2026-10, produto 5238525), por um webhook próprio da conta.
--
-- STATUS: NÃO APLICADA. Ensaiada em transação desfeita em 13/10/2026 (20261013193000_ensaio.sql). Reversão pronta e
-- ensaiada (20261013193000_reversao.sql). Relatório: 20261013193000.explain.md. Card ClickUp 17tya50ga24.
-- Ordem de publicação: esta migration → secret HOTMART_HOTTOK_ESCRITORIO → deploy da edge hotmart-escritorio-webhook
-- → por último o cadastro do webhook na Hotmart (conta escritório). Sem o cadastro, nada entra e nada muda na tela.
--
-- POR QUE
--   Pedido do Victor Hugo (13/10/2026): ver a venda da SV do ATM cair na hora, "garante que não vai quebrar nada... não
--   fica duplicando dado, não fica com vários dados no mesmo lugar... precisa do webhook, mas não pode quebrar o sistema
--   nem interferir em nada". Hoje a venda do escritório só aparece pelo espelho do Financeiro (fin.hotmart_transacoes),
--   gravado de hora em hora pela edge hotmart-sync: atraso medido (conta escritório, pagas, 14 dias, 13 transações)
--   mediana 29,7 min, p90 46,1 min, máximo 58,1 min. Os 3 webhooks existentes só recebem a conta academy.
--
-- O QUE FAZ
--   a. dados.hotmart_ao_vivo: ponte do webhook. Uma linha por (conta, transacao), último evento vale. RLS ligada, sem
--      policy, revoke de tudo para public/anon/authenticated/service_role (só o dono postgres lê e escreve).
--      Guarda só os campos que a leitura usa (payload reduzido, sem documento, endereço completo nem IP).
--   b0. dados.hotmart_ao_vivo_payload_ok(payload): regra única de payload válido, a mesma da edge (versão 2.0.0, evento
--      da lista, transação, status, creation_date/order_date/approved_date inteiros em ms de 2000 até agora + 1 dia,
--      price.value number de 0 a 999.999.999.999,99, recurrence_number inteiro até 10.000, commissions lista de objetos
--      com value number). Nunca levanta erro. Usada na gravação (recusa com 22023) e na leitura (linha fora da regra é
--      ignorada): uma linha envenenada não derruba dados.transacoes nem as RPCs do ATM (pentest 13/10/2026).
--   b. dados.hotmart_ao_vivo_gravar(conta, payload): upsert idempotente. Atualiza só se o evento é mais novo
--      (creation_date) ou, no mesmo instante, de posto maior (CHARGEBACK = REFUNDED > DISPUTE > COMPLETED > APPROVED >
--      demais). O mesmo evento 2x não muda nada (devolve 0); evento antigo depois do novo não muda nada.
--   c. dados.transacoes (só o corpo; assinatura, colunas e grants iguais): ramo ao_vivo igual ao ramo webhook da academy,
--      só com as linhas que passam em dados.hotmart_ao_vivo_payload_ok.
--      Quando o sync traz a transação (mesma conta), a linha do webhook sai da leitura: o espelho manda, nada conta 2x.
--      Corpo de antes guardado em acesso.corpo_antes (migration '20261013av').
--   d. dados.hotmart_ao_vivo_limpar(): apaga a linha cujo par no espelho foi visto há mais de 24 h. Cron diário novo
--      dados-hotmart-ao-vivo-limpar (05:37 UTC). A ponte não acumula.
--   e. dados.hotmart_ao_vivo_sem_espelho(horas = 3): alerta de forjamento/sync parado. Linha paga (APPROVED/COMPLETED)
--      sem par no espelho há mais de N horas. Só leitura, sem dado pessoal. Não está ligada a canal nenhum (ver .explain).
--   Não toca fin.*, cs.*, os 3 webhooks, o hotmart-sync nem os crons existentes.
--
-- AS 5 PERGUNTAS
--   escala: conta escritório teve 71 transações em 30 dias (máx. 16/dia); ~7 eventos/dia estimados; 10x = ~70/dia. A
--     limpeza mantém a tabela no tamanho de ~1 dia de eventos + as sem par. Leitura: CTE a mais dentro de
--     dados.transacoes, filtrada pela PK/índice (conta, oferta_codigo); anti-join pela PK do espelho.
--   índice: upsert = PK (conta, transacao); leitura = hotmart_ao_vivo_oferta_ix (conta, oferta_codigo); anti-join e
--     limpeza = hotmart_transacoes_pkey. Explain antes/depois no .explain.md.
--   frequência: escrita = 1 por evento da Hotmart; leitura igual à de hoje; limpeza 1x/dia.
--   repetição: nenhuma consulta nova por tela.
--   limpeza (dados.hotmart_ao_vivo_limpar, cron diário): escala = só a ponte (dezenas de linhas/dia; ensaio com 5.000
--     linhas: 2,8 ms); índice = PK da ponte + hotmart_transacoes_pkey (merge join, medido); frequência = 1x/dia às 05:37
--     UTC, minuto sem outra rotina; repetição = nenhuma (só o cron chama); reversão = cron.unschedule ou a _reversao.sql.
--     Cron em vez de limpar dentro da gravação: a gravação do webhook fica só com o upsert (nada que possa falhar e virar
--     500 para a Hotmart), e o vigia ops.vigiar passa a ver a rotina nova sozinho pelo schedule.
--   reversão: (1) desligar sem banco: tirar o webhook na Hotmart ou apagar o secret (a edge responde 503 e nada grava);
--     (2) 20261013193000_reversao.sql: volta o corpo de dados.transacoes byte a byte, tira o cron e apaga tabela e
--     funções. O sync não muda em nenhum momento.
--
-- IDEMPOTENTE: rodar 2x dá o mesmo estado (ensaiado). md5 do prosrc do corpo novo de dados.transacoes = efbd212fc50a114fa307b4681454e1a9
-- (a reversão só restaura se o vivo ainda for este).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- 0. Premissas: corpo vivo de dados.transacoes é o da 20261007tr (md5 do prosrc medido em 13/10) ou já o desta
do $g$
declare
  v_src text := (select p.prosrc from pg_proc p where p.oid = to_regprocedure('dados.transacoes(text,text)'));
begin
  if v_src is null then
    raise exception '20261013av: dados.transacoes(text,text) não existe';
  end if;
  if md5(v_src) <> '58fbc58cf082979b92dda008ddbdf808' and position('20261013av' in v_src) = 0 then
    raise exception '20261013av: corpo vivo de dados.transacoes mudou desde 13/10 (md5 %); refazer a partir do vivo', md5(v_src);
  end if;
  if to_regclass('acesso.corpo_antes') is null or to_regclass('dados.dashboards') is null then
    raise exception '20261013av: acesso.corpo_antes ou dados.dashboards não existe';
  end if;
  if to_regnamespace('cron') is null then
    raise exception '20261013av: pg_cron ausente';
  end if;
  if exists (select 1 from cron.job j where j.jobname = 'dados-hotmart-ao-vivo-limpar'
              and j.command <> $c$set statement_timeout = '60s'; set lock_timeout = '5s'; select dados.hotmart_ao_vivo_limpar()$c$) then
    raise exception '20261013av: já existe cron dados-hotmart-ao-vivo-limpar com outro comando';
  end if;
end
$g$;

-- a. Tabela-ponte
create table if not exists dados.hotmart_ao_vivo (
  conta         text        not null constraint hotmart_ao_vivo_conta_ck check (conta ~ '^[a-z][a-z0-9_]*$'),
  transacao     text        not null constraint hotmart_ao_vivo_transacao_ck check (transacao ~ '^[A-Za-z0-9_-]{1,64}$'),
  evento        text        not null,
  evento_id     text,
  evento_em     timestamptz not null,
  status        text        not null,
  produto_id    text,
  oferta_codigo text,
  payload       jsonb       not null,
  recebido_em   timestamptz not null default now(),
  primeiro_em   timestamptz not null default now(),
  constraint hotmart_ao_vivo_pkey primary key (conta, transacao)
);
create index if not exists hotmart_ao_vivo_oferta_ix on dados.hotmart_ao_vivo (conta, oferta_codigo);
alter table dados.hotmart_ao_vivo enable row level security;
revoke all on table dados.hotmart_ao_vivo from public, anon, authenticated, service_role;
comment on table dados.hotmart_ao_vivo is
  '20261013av: ponte do webhook hotmart-escritorio-webhook. Uma linha por (conta, transacao), último evento. Some da leitura '
  'de dados.transacoes quando o espelho do Financeiro traz a transação; a linha é apagada 24 h depois (dados.hotmart_ao_vivo_limpar). '
  'Contém dado pessoal do comprador: só o dono lê.';

-- b0. Regra única de payload válido (a mesma do validar() da edge). Usada na gravação E na leitura: linha que não passa
--     nunca é gravada e, se aparecer (escrita direta por fora da função), é ignorada pela leitura em vez de derrubar o ATM.
--     Nunca levanta erro: qualquer falha de conversão = false.
create or replace function dados.hotmart_ao_vivo_payload_ok(p jsonb)
 returns boolean
 language plpgsql
 stable
 set search_path to ''
as $function$
-- 20261013av (pentest 13/10/2026: linha envenenada derrubava dados.transacoes)
declare
  v_min constant numeric := 946684800000;                                          -- 2000-01-01 em ms
  v_max constant numeric := floor(extract(epoch from now()) * 1000) + 86400000;    -- agora + 1 dia, em ms
  v_lim constant numeric := 999999999999.99;                                       -- cabe em numeric(14,2)
  v_d jsonb;
  v_c jsonb;
  v_x jsonb;
  v_n numeric;
begin
  if jsonb_typeof(p) is distinct from 'object' or (p ->> 'version') is distinct from '2.0.0' then return false; end if;
  if jsonb_typeof(p -> 'event') is distinct from 'string'
     or (p ->> 'event') not in ('PURCHASE_APPROVED', 'PURCHASE_COMPLETE', 'PURCHASE_CANCELED', 'PURCHASE_BILLET_PRINTED',
                                'PURCHASE_DELAYED', 'PURCHASE_REFUNDED', 'PURCHASE_EXPIRED', 'PURCHASE_PROTEST',
                                'PURCHASE_CHARGEBACK') then
    return false;
  end if;
  v_d := p -> 'data';
  if jsonb_typeof(v_d) is distinct from 'object' or jsonb_typeof(v_d -> 'purchase') is distinct from 'object' then return false; end if;
  v_c := v_d -> 'purchase';
  if jsonb_typeof(v_c -> 'transaction') is distinct from 'string' or btrim(v_c ->> 'transaction') !~ '^[A-Za-z0-9_-]{1,64}$' then
    return false;
  end if;
  if jsonb_typeof(v_c -> 'status') is distinct from 'string' or btrim(v_c ->> 'status') = '' then return false; end if;
  -- datas em ms: creation_date obrigatória; order_date/approved_date opcionais. Inteiro, de 2000 até agora + 1 dia.
  if jsonb_typeof(p -> 'creation_date') is distinct from 'number' then return false; end if;
  foreach v_x in array array[p -> 'creation_date', v_c -> 'order_date', v_c -> 'approved_date'] loop
    continue when coalesce(jsonb_typeof(v_x), 'null') = 'null';
    -- só dígitos no texto (a leitura converte com ::bigint; "1.0" ou "1e12" derrubariam)
    if jsonb_typeof(v_x) <> 'number' or (v_x #>> '{}') !~ '^[0-9]{1,16}$' then return false; end if;
    v_n := (v_x #>> '{}')::numeric;
    if v_n < v_min or v_n > v_max then return false; end if;
  end loop;
  -- preço opcional; se vier: objeto, value number de 0 até o limite, currency_value texto curto
  if coalesce(jsonb_typeof(v_c -> 'price'), 'null') not in ('null', 'object') then return false; end if;
  v_x := v_c #> '{price,value}';
  if coalesce(jsonb_typeof(v_x), 'null') <> 'null' then
    if jsonb_typeof(v_x) <> 'number' then return false; end if;
    v_n := (v_x #>> '{}')::numeric;
    if v_n < 0 or v_n > v_lim then return false; end if;
  end if;
  v_x := v_c #> '{price,currency_value}';
  if coalesce(jsonb_typeof(v_x), 'null') <> 'null' then
    if jsonb_typeof(v_x) <> 'string' then return false; end if;
    if length(v_x #>> '{}') > 10 then return false; end if;
  end if;
  v_x := v_c -> 'recurrence_number';
  if coalesce(jsonb_typeof(v_x), 'null') <> 'null' then
    if jsonb_typeof(v_x) <> 'number' or (v_x #>> '{}') !~ '^[0-9]{1,5}$' then return false; end if;  -- lido com ::int
    if (v_x #>> '{}')::numeric > 10000 then return false; end if;
  end if;
  -- comissões opcionais; se vierem: lista de objetos, value number dentro do limite
  v_x := v_d -> 'commissions';
  if coalesce(jsonb_typeof(v_x), 'null') <> 'null' then
    if jsonb_typeof(v_x) <> 'array' then return false; end if;
    for v_c in select e from jsonb_array_elements(v_x) e loop
      if jsonb_typeof(v_c) <> 'object' then return false; end if;
      if coalesce(jsonb_typeof(v_c -> 'value'), 'null') <> 'null' then
        if jsonb_typeof(v_c -> 'value') <> 'number' then return false; end if;
        if abs((v_c ->> 'value')::numeric) > v_lim then return false; end if;
      end if;
    end loop;
  end if;
  return true;
exception when others then
  return false;
end
$function$;
revoke all on function dados.hotmart_ao_vivo_payload_ok(jsonb) from public, anon, authenticated, service_role;

-- b. Gravação idempotente (a edge chama; conta fixa no código da edge)
create or replace function dados.hotmart_ao_vivo_gravar(p_conta text, p_payload jsonb)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- 20261013av: upsert do último evento por (conta, transacao). Devolve 1 se gravou/atualizou, 0 se não mudou nada.
declare
  v_d      jsonb := p_payload -> 'data';
  v_tx     text  := btrim(p_payload #>> '{data,purchase,transaction}');
  v_status text  := btrim(p_payload #>> '{data,purchase,status}');
  v_evento text  := btrim(p_payload ->> 'event');
  v_cd     text  := p_payload ->> 'creation_date';
  v_red    jsonb;
  v_n      integer;
begin
  if p_conta is null or p_conta !~ '^[a-z][a-z0-9_]*$' then
    raise exception 'conta inválida' using errcode = '22023';
  end if;
  -- mesma regra da edge (tipo e faixa de todo número/data que a leitura converte); a edge trata 22023 como "ignorado"
  if not dados.hotmart_ao_vivo_payload_ok(p_payload) then
    raise exception 'payload fora da regra (versão, evento, transação, status, datas, valores)' using errcode = '22023';
  end if;
  -- só o que a leitura usa (mesmos caminhos do ramo webhook de dados.transacoes); sem documento, endereço nem IP
  v_red := jsonb_strip_nulls(jsonb_build_object(
    'id', p_payload -> 'id', 'event', p_payload -> 'event', 'version', p_payload -> 'version',
    'creation_date', p_payload -> 'creation_date',
    'data', jsonb_build_object(
      'product', jsonb_build_object('id', v_d #> '{product,id}'),
      'purchase', jsonb_build_object(
        'transaction', v_d #> '{purchase,transaction}', 'status', v_d #> '{purchase,status}',
        'offer', jsonb_build_object('code', v_d #> '{purchase,offer,code}'),
        'price', jsonb_build_object('value', v_d #> '{purchase,price,value}',
                                    'currency_value', v_d #> '{purchase,price,currency_value}'),
        'order_date', v_d #> '{purchase,order_date}', 'approved_date', v_d #> '{purchase,approved_date}',
        'recurrence_number', v_d #> '{purchase,recurrence_number}'),
      'commissions', (select jsonb_agg(jsonb_build_object('source', c -> 'source', 'value', c -> 'value'))
                        from jsonb_array_elements(case when jsonb_typeof(v_d -> 'commissions') = 'array'
                                                       then v_d -> 'commissions' else '[]'::jsonb end) c
                       where c ->> 'source' = 'PRODUCER'),
      'buyer', jsonb_build_object('email', v_d #> '{buyer,email}', 'name', v_d #> '{buyer,name}',
                                  'checkout_phone', v_d #> '{buyer,checkout_phone}',
                                  'address', jsonb_build_object('state', v_d #> '{buyer,address,state}')))));

  insert into dados.hotmart_ao_vivo as t
         (conta, transacao, evento, evento_id, evento_em, status, produto_id, oferta_codigo, payload, recebido_em, primeiro_em)
  values (p_conta, v_tx, v_evento, p_payload ->> 'id', to_timestamp(v_cd::numeric / 1000.0), v_status,
          v_d #>> '{product,id}', v_d #>> '{purchase,offer,code}', v_red, clock_timestamp(), clock_timestamp())
  on conflict (conta, transacao) do update
     set evento = excluded.evento, evento_id = excluded.evento_id, evento_em = excluded.evento_em,
         status = excluded.status, produto_id = excluded.produto_id, oferta_codigo = excluded.oferta_codigo,
         payload = excluded.payload, recebido_em = excluded.recebido_em
   where excluded.evento_em > t.evento_em
      or (excluded.evento_em = t.evento_em
          and (case excluded.status when 'CHARGEBACK' then 4 when 'REFUNDED' then 4 when 'DISPUTE' then 3
                                    when 'COMPLETED' then 2 when 'APPROVED' then 1 else 0 end)
            > (case t.status when 'CHARGEBACK' then 4 when 'REFUNDED' then 4 when 'DISPUTE' then 3
                             when 'COMPLETED' then 2 when 'APPROVED' then 1 else 0 end));
  get diagnostics v_n = row_count;
  return v_n;
end
$function$;
revoke all on function dados.hotmart_ao_vivo_gravar(text, jsonb) from public, anon, authenticated, service_role;

-- c. Guarda o corpo de antes de dados.transacoes (uma vez; não guarda se o vivo já for o novo)
insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261013av'
  from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure
   and p.prosrc !~ '20261013av'
on conflict do nothing;

-- Corpo novo de dados.transacoes (parte do corpo vivo da 20261007tr; só acrescenta o CTE ao_vivo e a união)
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
  -- 20261013av: o que a edge hotmart-escritorio-webhook gravou em dados.hotmart_ao_vivo e o sync ainda não trouxe
  -- (some quando o sync traz). Só fora da academy, que já tem o ramo webhook acima: os dois ramos nunca valem juntos.
  ao_vivo as (
    select a.transacao, a.payload -> 'data' as d
      from dados.hotmart_ao_vivo a
     where v_conta <> 'academy'
       and a.conta = v_conta
       and a.oferta_codigo = any (v_ofertas)
       and dados.hotmart_ao_vivo_payload_ok(a.payload)  -- linha fora da regra é ignorada, nunca derruba a leitura
       and not exists (select 1 from (select * from fin.hotmart_transacoes where conta = v_conta) h
                        where h.transacao = a.transacao)
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
           (select nullif(c ->> 'value', '')::numeric from jsonb_array_elements(case when jsonb_typeof(w.d -> 'commissions') = 'array' then w.d -> 'commissions' else '[]'::jsonb end) c  -- 20261013av: JSON null ou não-lista não derruba
             where c ->> 'source' = 'PRODUCER' limit 1),
           null::numeric,
           w.d #>> '{buyer,email}', w.d #>> '{buyer,name}', w.d #>> '{buyer,checkout_phone}',
           w.d #>> '{buyer,address,state}'
      from (select * from webhook union all select * from ao_vivo) w  -- 20261013av
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

-- d. Limpeza: linha cujo par no espelho foi visto há mais de 24 h (o espelho já manda; a ponte não acumula)
create or replace function dados.hotmart_ao_vivo_limpar()
 returns integer
 language plpgsql
 set search_path to ''
as $function$
-- 20261013av
declare
  v_conta text;
  v_n     integer;
  v_tot   integer := 0;
begin
  for v_conta in select distinct a.conta from dados.hotmart_ao_vivo a loop
    delete from dados.hotmart_ao_vivo a
     where a.conta = v_conta
       and exists (select 1 from (select * from fin.hotmart_transacoes where conta = v_conta) h
                    where h.transacao = a.transacao
                      and h.primeiro_visto_em < now() - interval '24 hours');
    get diagnostics v_n = row_count;
    v_tot := v_tot + v_n;
  end loop;
  return v_tot;
end
$function$;
revoke all on function dados.hotmart_ao_vivo_limpar() from public, anon, authenticated, service_role;

select cron.schedule('dados-hotmart-ao-vivo-limpar', '37 5 * * *',
  $c$set statement_timeout = '60s'; set lock_timeout = '5s'; select dados.hotmart_ao_vivo_limpar()$c$);

-- e. Alerta: venda paga do webhook sem par no espelho há mais de p_horas (forjada com hottok vazado, ou sync parado)
create or replace function dados.hotmart_ao_vivo_sem_espelho(p_horas integer default 3)
 returns table(conta text, transacao text, evento text, status text, oferta_codigo text, primeiro_em timestamptz,
               horas_sem_espelho numeric)
 language plpgsql
 stable
 set search_path to ''
as $function$
-- 20261013av: sem dado pessoal (código da transação não identifica pessoa)
#variable_conflict use_column
declare
  v_conta text;
begin
  for v_conta in select distinct a.conta from dados.hotmart_ao_vivo a loop
    return query
    select a.conta, a.transacao, a.evento, a.status, a.oferta_codigo, a.primeiro_em,
           round((extract(epoch from (now() - a.primeiro_em)) / 3600)::numeric, 1)
      from dados.hotmart_ao_vivo a
     where a.conta = v_conta
       and a.status in ('APPROVED', 'COMPLETED')
       and a.primeiro_em < now() - make_interval(hours => greatest(coalesce(p_horas, 3), 1))
       and not exists (select 1 from (select * from fin.hotmart_transacoes where conta = v_conta) h
                        where h.transacao = a.transacao);
  end loop;
end
$function$;
revoke all on function dados.hotmart_ao_vivo_sem_espelho(integer) from public, anon, authenticated, service_role;

-- REVERSÃO: 20261013193000_reversao.sql (volta o corpo guardado em acesso.corpo_antes, migration '20261013av').
