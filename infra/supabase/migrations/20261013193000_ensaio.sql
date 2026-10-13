-- Ensaio de 20261013193000 (marca 20261013av): webhook ao vivo da conta escritório. Transação desfeita: nada persiste.
-- Gerado por script a partir da migration e da reversão (o texto delas entra aqui igual). Dado de ensaio é falso
-- (transações ENSAIO-*, e-mail @ensaio.local). Saída só com contagens, somas, md5, status e planos: nenhum dado pessoal.
-- Rodar inteiro numa chamada; termina em ROLLBACK.
--
-- ESPERADOS
--   00/00b objetos novos nulos antes; md5 do corpo vivo = 58fbc58cf082979b92dda008ddbdf808.
--   03     2 passadas da migration: mesmo estado; corpo_antes = 1; trava de conta = ok nas 4 funções; ACL só postgres;
--          RLS ligada sem policy; anon/authenticated/service_role sem acesso; cron 1.
--   04     foto com a tabela ao vivo VAZIA = foto antes em TODAS as chamadas (inclusive ATM): diferença "nenhuma".
--   05     não duplicar: APPROVED +1 venda; o mesmo evento 2x devolve 0 e a linha não muda; COMPLETED mais novo
--          continua +1; REFUNDED mais novo e depois APPROVED mais antigo: fica REFUNDED e a venda sai; mesmo instante
--          vale o posto maior; conta academy gravada na ponte não aparece em nada; payload sem documento/endereço.
--   05.10  casos do pentest (valor texto, 1e13, negativo, bigint/int estourado, decimal, data futura): 22023, nada grava.
--   05.11  8 vetores envenenados escritos por fora da função, nas ofertas a4chzrru (ATM) e mqquvrtc (setembro): dados.transacoes
--          e o ATM rodam; as 7 linhas fora da regra são ignoradas e a de commissions null entra sem quebrar.
--   06     foto com linhas de ensaio: só mudam chamadas do ATM (chave atm-elaine-1-2026-10 e escritorio/a4chzrru);
--          "fora do esperado" = nenhuma.
--   08     reversão: md5 do corpo = o de antes; tabela, funções, cron e corpo_antes somem.
--   09     foto depois da reversão = foto antes: "nenhuma".
--   10     reaplicada: a mesma transação no espelho (como o sync) → vendas e receita iguais às do passo 05.4,
--          nenhuma transação repetida; limpeza apaga só o par visto há mais de 24 h; alerta só a venda paga sem par
--          há mais de 3 h; 10x de linhas usa o índice.
begin isolation level repeatable read;  -- uma foto só do banco: o ATM está ao vivo e o lead novo mudaria a comparação
set local lock_timeout = '5s';
set local statement_timeout = '300s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
-- FILTRO das chamadas da foto (regex sobre o nome da chamada). '.' = todas (4 fotos de ~45 s cada).
-- Pela Management API, que corta a chamada em ~100 s, rodar o arquivo 4 vezes trocando só o valor abaixo; cada
-- parte é um ensaio inteiro e desfeito, com a própria foto antes/depois na mesma transação:
--   parte 1: ^(?!public\.dados_atm_(grupo_numeros|leads|pos_live|comparecimento|serie_diaria)|dados\.atm_leads)
--   parte 2: ^public\.dados_atm_grupo_numeros
--   parte 3: ^(public\.dados_atm_leads|dados\.atm_leads)
--   parte 4: ^public\.dados_atm_(pos_live|comparecimento|serie_diaria)
select set_config('z.filtro', '.', true);
insert into pg_temp._z_out (passo, linha) select '00 filtro da foto', current_setting('z.filtro');
-- Regressão de leitura: foto de TODA função que lê dados.transacoes (direta ou indiretamente), para todos os
-- dashboards de dados.dashboards e todas as ofertas da conta escritorio. Saída: contagem, soma dos campos numéricos e
-- md5 do conteúdo ordenado. Nenhuma linha é impressa.
create temp table _z_foto (fase text, chamada text, n bigint, soma numeric, md5 text, erro text, ms numeric, primary key (fase, chamada)) on commit drop;
create function pg_temp.z_foto(p_fase text) returns integer language plpgsql as $zf$
declare
  r record; v_t timestamptz; v_n bigint; v_soma numeric; v_md5 text; v_k int := 0;
begin
  -- contexto autorizado das RPCs public.dados_* (mesmo usuário de equipe dos ensaios 20261007205017 e 20261008191000)
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  for r in
    with d as (select b.chave, b.conta_hotmart, b.oferta_codigo, b.ofertas_extra from dados.dashboards b),
    pares as (
      select d.conta_hotmart c, d.oferta_codigo o from d where d.oferta_codigo is not null
      union select d.conta_hotmart, x from d cross join unnest(d.ofertas_extra) x
      union select 'escritorio', e.o from (select distinct t.oferta_codigo o from (select * from fin.hotmart_transacoes where conta = 'escritorio') t
                                            where t.oferta_codigo is not null) e
    ),
    fs as (select unnest(array[
      'public.dados_miami_interesse', 'public.dados_presencial_compradores_perfil', 'public.dados_presencial_leads',
      'public.dados_presencial_pagamentos', 'public.dados_presencial_resumo', 'public.dados_presencial_serie_diaria',
      'public.dados_presencial_serie_vendas', 'public.dados_presencial_vendas', 'public.dados_presencial_vendas_por_hora',
      'public.dados_presencial_pendencias', 'public.dados_atm_resumo', 'public.dados_atm_serie_diaria',
      'public.dados_atm_comparecimento', 'public.dados_atm_pos_live', 'public.dados_atm_leads', 'public.dados_atm_grupo_numeros',
      'public.dados_atm_sv_vendas', 'dados.atm_vendas_todas', 'dados.atm_vendas', 'dados.atm_leads']) f)
    select format('%s(%L)', fs.f, d.chave) k, format('select * from %s(%L)', fs.f, d.chave) s from d, fs
    union all select format('public.dados_atm_leads(%L,teste)', d.chave), format('select * from public.dados_atm_leads(%L, null, null, true)', d.chave) from d
    union all select format('public.dados_atm_sv_vendas(%L,teste)', d.chave), format('select * from public.dados_atm_sv_vendas(%L, true)', d.chave) from d
    union all select format('public.dados_atm_grupo_numeros(%L,teste)', d.chave), format('select * from public.dados_atm_grupo_numeros(%L, null, null, true)', d.chave) from d
    union all select format('public.dados_presencial_pendencias_pessoas(%L,%L)', d.chave, g), format('select * from public.dados_presencial_pendencias_pessoas(%L,%L)', d.chave, g)
                from d cross join unnest(array['nao_pago', 'cancelada']) g
    union all select format('dados.transacoes(%L,%L)', p.c, p.o), format('select * from dados.transacoes(%L,%L)', p.c, p.o) from pares p
    union all select format('dados.pendencias(%L,%L)', p.c, p.o), format('select * from dados.pendencias(%L,%L)', p.c, p.o) from pares p
  loop
    continue when r.k !~ current_setting('z.filtro');
    v_t := clock_timestamp();
    begin
      execute format($q$with t as materialized (select to_jsonb(x) j from (%s) x)
        select (select count(*) from t),
               (select coalesce(sum((e.value #>> '{}')::numeric), 0) from t cross join lateral jsonb_each(t.j) e where jsonb_typeof(e.value) = 'number'),
               (select md5(coalesce(string_agg(t.j::text, '|' order by t.j::text), '')) from t)$q$, r.s)
        into v_n, v_soma, v_md5;
      insert into pg_temp._z_foto values (p_fase, r.k, v_n, v_soma, v_md5, null, round((extract(epoch from clock_timestamp() - v_t) * 1000)::numeric, 1));
    exception when others then
      insert into pg_temp._z_foto values (p_fase, r.k, null, null, null, sqlstate, round((extract(epoch from clock_timestamp() - v_t) * 1000)::numeric, 1));
    end;
    v_k := v_k + 1;
  end loop;
  perform set_config('request.jwt.claims', '{}', true);
  return v_k;
end
$zf$;
-- diferenças entre duas fases (só o nome da chamada)
create function pg_temp.z_dif(p_a text, p_b text) returns text language sql as $zd$
  select coalesce(string_agg(coalesce(a.chamada, b.chamada), ', ' order by coalesce(a.chamada, b.chamada)), 'nenhuma')
    from (select * from pg_temp._z_foto where fase = p_a) a
    full join (select * from pg_temp._z_foto where fase = p_b) b on b.chamada = a.chamada
   where a.chamada is null or b.chamada is null
      or (a.n, a.soma, a.md5, a.erro) is distinct from (b.n, b.soma, b.md5, b.erro)
$zd$;
create function pg_temp.z_ev(p_tx text, p_evento text, p_status text, p_em timestamptz, p_oferta text, p_valor numeric)
returns jsonb language sql as $ze$
  select jsonb_build_object('id', 'ENSAIO-EV-' || p_tx || '-' || p_status || '-' || (extract(epoch from p_em) * 1000)::bigint,
    'event', p_evento, 'version', '2.0.0', 'creation_date', (extract(epoch from p_em) * 1000)::bigint,
    'data', jsonb_build_object(
      'product', jsonb_build_object('id', 5238525, 'name', 'Ensaio'),
      'buyer', jsonb_build_object('email', lower(p_tx) || '@ensaio.local', 'name', 'Ensaio Ao Vivo', 'checkout_phone', '000',
                                  'document', '00000000000', 'address', jsonb_build_object('state', 'ZZ', 'address', 'Rua Ensaio')),
      'commissions', jsonb_build_array(jsonb_build_object('source', 'MARKETPLACE', 'value', round(p_valor * 0.1, 2)),
                                       jsonb_build_object('source', 'PRODUCER', 'value', round(p_valor * 0.9, 2))),
      'purchase', jsonb_build_object('transaction', p_tx, 'status', p_status, 'offer', jsonb_build_object('code', p_oferta),
        'recurrence_number', 1, 'buyer_ip', '0.0.0.0',
        'order_date', (extract(epoch from now()) * 1000)::bigint, 'approved_date', (extract(epoch from now()) * 1000)::bigint,
        'price', jsonb_build_object('value', p_valor, 'currency_value', 'BRL'))))
$ze$;
create function pg_temp.z_linha(p_conta text, p_tx text) returns text language plpgsql as $zl$
begin
  return coalesce((select md5(to_jsonb(a)::text) from dados.hotmart_ao_vivo a where a.conta = p_conta and a.transacao = p_tx), 'sem linha');
end
$zl$;

-- 00 antes
insert into pg_temp._z_out (passo, linha) select '00 objetos novos antes (esperado tudo nulo, cron 0, corpo_antes 0)', jsonb_build_object(
  'tabela', to_regclass('dados.hotmart_ao_vivo')::text, 'gravar', to_regprocedure('dados.hotmart_ao_vivo_gravar(text,jsonb)')::text, 'payload_ok', to_regprocedure('dados.hotmart_ao_vivo_payload_ok(jsonb)')::text,
  'limpar', to_regprocedure('dados.hotmart_ao_vivo_limpar()')::text, 'sem_espelho', to_regprocedure('dados.hotmart_ao_vivo_sem_espelho(integer)')::text,
  'cron', (select count(*) from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar'),
  'corpo_antes', (select count(*) from acesso.corpo_antes where migration = '20261013av'),
  'md5_transacoes', (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure))::text;
insert into pg_temp._z_out (passo, linha) select '01 foto antes (chamadas)', pg_temp.z_foto('0 antes')::text;
insert into pg_temp._z_out (passo, linha) select '01 erros esperados (modelo do dashboard não é o da função, igual em toda fase)', (select count(*) from pg_temp._z_foto where fase = '0 antes' and erro is not null)::text || ' de ' || (select count(*) from pg_temp._z_foto where fase = '0 antes')::text;
insert into pg_temp._z_out (passo, linha) select '01 ATM antes', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
do $x$ declare r record; i int; begin
  for i in 1..2 loop  -- 1ª = cache frio; guarda a 2ª
    for r in explain (analyze, buffers) select * from dados.transacoes('escritorio','a4chzrru') loop
      if i = 2 then insert into pg_temp._z_out (passo, linha) values ('02 explain antes dados.transacoes(escritorio,a4chzrru)', r."QUERY PLAN"); end if;
    end loop;
  end loop;
end $x$;

-- passada 1
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
set local statement_timeout = '300s';  -- a migration baixa para 30s; o ensaio volta para 300s

-- passada 2
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
set local statement_timeout = '300s';  -- a migration baixa para 30s; o ensaio volta para 300s

-- 03 conferências
insert into pg_temp._z_out (passo, linha) select '03 objetos depois de 2 passadas', jsonb_build_object(
  'tabela', to_regclass('dados.hotmart_ao_vivo')::text, 'gravar', to_regprocedure('dados.hotmart_ao_vivo_gravar(text,jsonb)')::text, 'payload_ok', to_regprocedure('dados.hotmart_ao_vivo_payload_ok(jsonb)')::text,
  'limpar', to_regprocedure('dados.hotmart_ao_vivo_limpar()')::text, 'sem_espelho', to_regprocedure('dados.hotmart_ao_vivo_sem_espelho(integer)')::text,
  'cron', (select count(*) from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar'),
  'corpo_antes', (select count(*) from acesso.corpo_antes where migration = '20261013av'),
  'md5_transacoes', (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure))::text;
insert into pg_temp._z_out (passo, linha) select '03 md5 do corpo aplicado (esperado efbd212fc50a114fa307b4681454e1a9)', (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure);
insert into pg_temp._z_out (passo, linha) select '03 corpo guardado = corpo de antes', (select (md5 = '58fbc58cf082979b92dda008ddbdf808')::text || ' / linhas ' || count(*) over () from acesso.corpo_antes where migration = '20261013av');
insert into pg_temp._z_out (passo, linha) select '03 trava de conta', (select string_agg(p.oid::regprocedure::text || ' ' || coalesce(fin.trava_conta_hotmart_violacao('pg_catalog.pg_proc'::regclass, p.oid), 'ok'), '; ' order by 1) from pg_proc p where p.oid in ('dados.transacoes(text,text)'::regprocedure, 'dados.hotmart_ao_vivo_gravar(text,jsonb)'::regprocedure, 'dados.hotmart_ao_vivo_limpar()'::regprocedure, 'dados.hotmart_ao_vivo_sem_espelho(integer)'::regprocedure, 'dados.hotmart_ao_vivo_payload_ok(jsonb)'::regprocedure));
insert into pg_temp._z_out (passo, linha) select '03 acl funções', (select string_agg(p.proname || '=' || coalesce(array_to_string(p.proacl, ','), 'padrao') || ' secdef=' || p.prosecdef, '; ' order by p.proname) from pg_proc p where p.oid in ('dados.transacoes(text,text)'::regprocedure, 'dados.hotmart_ao_vivo_gravar(text,jsonb)'::regprocedure, 'dados.hotmart_ao_vivo_limpar()'::regprocedure, 'dados.hotmart_ao_vivo_sem_espelho(integer)'::regprocedure, 'dados.hotmart_ao_vivo_payload_ok(jsonb)'::regprocedure));
insert into pg_temp._z_out (passo, linha) select '03 tabela: rls / acl / policies / índices', (select c.relrowsecurity::text || ' / ' || coalesce(array_to_string(c.relacl, ','), 'padrao') || ' / ' || (select count(*) from pg_policies where schemaname = 'dados' and tablename = 'hotmart_ao_vivo') || ' / ' || (select string_agg(indexname, ',' order by indexname) from pg_indexes where schemaname = 'dados' and tablename = 'hotmart_ao_vivo') from pg_class c where c.oid = 'dados.hotmart_ao_vivo'::regclass);
insert into pg_temp._z_out (passo, linha) select '03 privilégios (esperado tudo false)', (select string_agg(r || ':' || has_table_privilege(r, 'dados.hotmart_ao_vivo', 'select,insert,update,delete')::text || '/' || has_function_privilege(r, 'dados.hotmart_ao_vivo_gravar(text,jsonb)', 'execute')::text || '/' || has_function_privilege(r, 'dados.hotmart_ao_vivo_sem_espelho(integer)', 'execute')::text || '/' || has_schema_privilege(r, 'dados', 'usage')::text, '; ' order by r) from unnest(array['anon', 'authenticated', 'service_role']) r);
do $p$ declare v text := ''; r text; begin
  foreach r in array array['anon', 'authenticated'] loop
    execute format('set local role %I', r);
    perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
    begin perform 1 from dados.hotmart_ao_vivo limit 1; v := v || r || ' leu; ';
    exception when insufficient_privilege then v := v || r || ' 42501 na leitura; '; end;
    begin perform dados.hotmart_ao_vivo_gravar('escritorio', '{}'::jsonb); v := v || r || ' gravou; ';
    exception when insufficient_privilege then v := v || r || ' 42501 na gravação; '; end;
    reset role;
    perform set_config('request.jwt.claims', '{}', true);
  end loop;
  insert into pg_temp._z_out (passo, linha) values ('03 acesso real como anon/authenticated (esperado 42501)', v);
end $p$;
insert into pg_temp._z_out (passo, linha) select '03 cron', (select string_agg(jobname || ' ' || schedule || ' ativo=' || active, '; ') from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar');

-- 04 tabela ao vivo VAZIA: tudo igual, inclusive o ATM
insert into pg_temp._z_out (passo, linha) select '04 foto depois, tabela vazia (chamadas)', pg_temp.z_foto('1 depois vazia')::text;
insert into pg_temp._z_out (passo, linha) select '04 diferenças antes x depois vazia (esperado nenhuma)', pg_temp.z_dif('0 antes', '1 depois vazia');

-- 05 não duplicar
insert into pg_temp._z_out (passo, linha) select '05.2 gravar A APPROVED (esperado 1)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-A', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '10 minutes', 'a4chzrru', 1000))::text;
insert into pg_temp._z_out (passo, linha) select '05.2 ATM depois do APPROVED (esperado +1 venda, +1000)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
insert into pg_temp._z_out (passo, linha) select '05.3 linha A antes do reenvio', pg_temp.z_linha('escritorio', 'ENSAIO-ATM-A');
insert into pg_temp._z_out (passo, linha) select '05.3 reenvio do MESMO evento (esperado 0)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-A', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '10 minutes', 'a4chzrru', 1000))::text;
insert into pg_temp._z_out (passo, linha) select '05.3 linha A depois do reenvio (esperado igual)', pg_temp.z_linha('escritorio', 'ENSAIO-ATM-A');
insert into pg_temp._z_out (passo, linha) select '05.3 ATM depois do reenvio (esperado igual ao 05.2)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
insert into pg_temp._z_out (passo, linha) select '05.4 gravar A COMPLETED mais novo (esperado 1)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-A', 'PURCHASE_COMPLETE', 'COMPLETED', now() - interval '5 minutes', 'a4chzrru', 1000))::text;
insert into pg_temp._z_out (passo, linha) select '05.4 ATM depois do COMPLETED (esperado igual ao 05.2)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
insert into pg_temp._z_out (passo, linha) select '05.4 leitura de A', coalesce((select jsonb_agg(jsonb_build_object('status', t.status, 'grupo', t.status_grupo, 'pago', t.pago, 'bruto', t.valor_bruto, 'liquido', t.valor_liquido)) from dados.transacoes('escritorio', 'a4chzrru') t where t.transacao = 'ENSAIO-ATM-A')::text, 'nenhuma linha');
insert into pg_temp._z_out (passo, linha) select '05.5 gravar B APPROVED (esperado 1)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-B', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '10 minutes', 'a4chzrru', 500))::text;
insert into pg_temp._z_out (passo, linha) select '05.5 ATM com B aprovado (esperado +2 vendas)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
insert into pg_temp._z_out (passo, linha) select '05.5 gravar B REFUNDED mais novo (esperado 1)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-B', 'PURCHASE_REFUNDED', 'REFUNDED', now() - interval '1 minute', 'a4chzrru', 500))::text;
insert into pg_temp._z_out (passo, linha) select '05.5 gravar B APPROVED mais antigo depois (esperado 0)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-B', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '10 minutes', 'a4chzrru', 500))::text;
insert into pg_temp._z_out (passo, linha) select '05.5 leitura de B (esperado REFUNDED, pago false)', coalesce((select jsonb_agg(jsonb_build_object('status', t.status, 'grupo', t.status_grupo, 'pago', t.pago, 'bruto', t.valor_bruto, 'liquido', t.valor_liquido)) from dados.transacoes('escritorio', 'a4chzrru') t where t.transacao = 'ENSAIO-ATM-B')::text, 'nenhuma linha');
insert into pg_temp._z_out (passo, linha) select '05.5 ATM depois (esperado igual ao 05.4)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
insert into pg_temp._z_out (passo, linha) select '05.6 C APPROVED (oferta fora de dashboard)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-OUTRA-C', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '3 minutes', 'ENSAIOX', 700))::text;
insert into pg_temp._z_out (passo, linha) select '05.6 C COMPLETED no MESMO instante (posto maior, esperado 1)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-OUTRA-C', 'PURCHASE_COMPLETE', 'COMPLETED', now() - interval '3 minutes', 'ENSAIOX', 700))::text;
insert into pg_temp._z_out (passo, linha) select '05.6 C APPROVED no mesmo instante (posto menor, esperado 0)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-OUTRA-C', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '3 minutes', 'ENSAIOX', 700))::text;
insert into pg_temp._z_out (passo, linha) select '05.6 status de C (esperado COMPLETED)', (select status from dados.hotmart_ao_vivo where transacao = 'ENSAIO-OUTRA-C');
insert into pg_temp._z_out (passo, linha) select '05.7 conta academy na ponte (oferta da Clínica; esperado 1, mas não pode aparecer em nada)', dados.hotmart_ao_vivo_gravar('academy', pg_temp.z_ev('ENSAIO-ACAD-D', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '10 minutes', 'sju5pawn', 900))::text;
insert into pg_temp._z_out (passo, linha) select '05.7 academy na leitura (esperado 0)', (select count(*) from dados.transacoes('academy', 'sju5pawn') where transacao = 'ENSAIO-ACAD-D')::text;
insert into pg_temp._z_out (passo, linha) select '05.8 payload reduzido sem documento, endereço, IP (esperado 0)', (select count(*) from dados.hotmart_ao_vivo where payload #> '{data,buyer,document}' is not null or payload::text ~ 'Rua Ensaio|buyer_ip|MARKETPLACE')::text;
do $v$ declare v text := ''; begin
  begin perform dados.hotmart_ao_vivo_gravar('Escritorio', pg_temp.z_ev('ENSAIO-X', 'PURCHASE_APPROVED', 'APPROVED', now(), 'a4chzrru', 1)); v := v || 'conta inválida gravou; ';
  exception when invalid_parameter_value then v := v || 'conta inválida 22023; '; end;
  begin perform dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-X', 'PURCHASE_APPROVED', 'APPROVED', now(), 'a4chzrru', 1) || '{"version":"1.0.0"}'); v := v || 'versão errada gravou; ';
  exception when invalid_parameter_value then v := v || 'versão 22023; '; end;
  begin perform dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-X', 'PURCHASE_APPROVED', 'APPROVED', now(), 'a4chzrru', 1) #- '{data,purchase,transaction}'); v := v || 'sem transação gravou; ';
  exception when invalid_parameter_value then v := v || 'sem transação 22023; '; end;
  begin perform dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('x''; drop table x; --', 'PURCHASE_APPROVED', 'APPROVED', now(), 'a4chzrru', 1)); v := v || 'transação com aspas gravou; ';
  exception when invalid_parameter_value then v := v || 'transação fora do formato 22023; '; end;
  insert into pg_temp._z_out (passo, linha) values ('05.9 entradas inválidas (esperado 4x 22023)', v);
end $v$;

-- 05.10 casos do pentest (13/10): payload envenenado não grava (22023) e nada entra na ponte
do $v$ declare v text := ''; r record; begin
  for r in select * from (values
    ('P1 price.value "abc"', '{data,purchase,price,value}'::text[], '"abc"'::jsonb),
    ('P2 price.value 1e13', '{data,purchase,price,value}', '1e13'),
    ('P3 price.value negativo', '{data,purchase,price,value}', '-1'),
    ('P4 order_date bigint estourado', '{data,purchase,order_date}', '99999999999999999999'),
    ('P5 order_date decimal', '{data,purchase,order_date}', '1760380000000.5'),
    ('P6 approved_date texto', '{data,purchase,approved_date}', '"ontem"'),
    ('P7 recurrence_number int estourado', '{data,purchase,recurrence_number}', '3000000000'),
    ('P8 recurrence_number 1.0', '{data,purchase,recurrence_number}', '1.0'),
    ('P9 commissions value texto', '{data,commissions}', '[{"source":"PRODUCER","value":"z"}]'),
    ('P10 commissions não lista', '{data,commissions}', '"x"'),
    ('P11 currency_value número', '{data,purchase,price,currency_value}', '1'),
    ('P13 creation_date decimal', '{creation_date}', '1760380000000.5')) t(nome, caminho, valor)
  loop
    begin
      perform dados.hotmart_ao_vivo_gravar('escritorio',
        jsonb_set(pg_temp.z_ev('ENSAIO-P', 'PURCHASE_APPROVED', 'APPROVED', now(), 'a4chzrru', 10), r.caminho, r.valor));
      v := v || r.nome || ' GRAVOU; ';
    exception when invalid_parameter_value then v := v || r.nome || ' 22023; ';
    end;
  end loop;
  begin
    perform dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-P', 'PURCHASE_APPROVED', 'APPROVED', now() + interval '2 days', 'a4chzrru', 10));
    v := v || 'P12 creation_date futura GRAVOU; ';
  exception when invalid_parameter_value then v := v || 'P12 creation_date futura 22023; ';
  end;
  begin  -- o caso exato do relatório do pentest
    perform dados.hotmart_ao_vivo_gravar('escritorio', '{"version":"2.0.0","event":"PURCHASE_APPROVED","creation_date":1760380000000,"data":{"purchase":{"transaction":"ENSAIO-P","status":"APPROVED","offer":{"code":"a4chzrru"},"price":{"value":"abc"}}}}');
    v := v || 'P0 reprodução do pentest GRAVOU; ';
  exception when invalid_parameter_value then v := v || 'P0 reprodução do pentest 22023; ';
  end;
  insert into pg_temp._z_out (passo, linha) values ('05.10 pentest pela função de gravar (esperado 22023 em todos)', v);
end $v$;
insert into pg_temp._z_out (passo, linha) select '05.10 linhas ENSAIO-P na ponte (esperado 0)', (select count(*) from dados.hotmart_ao_vivo where transacao = 'ENSAIO-P')::text;
-- 05.11 linha envenenada escrita POR FORA da função (insert direto): a leitura ignora, nada cai
insert into dados.hotmart_ao_vivo (conta, transacao, evento, evento_em, status, produto_id, oferta_codigo, payload)
select 'escritorio', 'ENSAIO-VENENO-' || o.k || '-' || n, 'PURCHASE_APPROVED', now(), 'APPROVED', '5238525', o.oferta,
       jsonb_set(pg_temp.z_ev('ENSAIO-VENENO-' || o.k || '-' || n, 'PURCHASE_APPROVED', 'APPROVED', now(), o.oferta, 10), c, v)
  from (values (1, '{data,purchase,price,value}'::text[], '"abc"'::jsonb), (2, '{data,purchase,price,value}', '1e13'),
               (3, '{data,purchase,order_date}', '"x"'), (4, '{data,purchase,recurrence_number}', '3000000000'),
               (5, '{data,commissions}', '[{"source":"PRODUCER","value":"z"}]'),
               (6, '{creation_date}', to_jsonb((extract(epoch from now() + interval '2 days') * 1000)::bigint)),
               (7, '{data,purchase,approved_date}', '99999999999999999999'),
               (8, '{data,commissions}', 'null')) x(n, c, v)
  cross join (values ('ATM', 'a4chzrru'), ('SET', 'mqquvrtc')) o(k, oferta);
insert into pg_temp._z_out (passo, linha) select '05.11 dados.transacoes(escritorio,a4chzrru) com os 8 vetores: roda; as 7 fora da regra são ignoradas (esperado 1 ENSAIO-VENENO, o de commissions null)', (select count(*) filter (where transacao like 'ENSAIO-VENENO-%')::text || ' de ' || count(*)::text || ' linhas' from dados.transacoes('escritorio', 'a4chzrru'));
insert into pg_temp._z_out (passo, linha) select '05.11 dados.transacoes(escritorio,mqquvrtc, edição de setembro) com os 8 vetores: roda (esperado 1 ENSAIO-VENENO, o de commissions null)', (select count(*) filter (where transacao like 'ENSAIO-VENENO-%')::text || ' de ' || count(*)::text || ' linhas' from dados.transacoes('escritorio', 'mqquvrtc'));
insert into pg_temp._z_out (passo, linha) select '05.11 commissions JSON null passa na regra (é ausente) e a leitura não cai (esperado true)', dados.hotmart_ao_vivo_payload_ok((select payload from dados.hotmart_ao_vivo where transacao = 'ENSAIO-VENENO-ATM-8'))::text;
insert into pg_temp._z_out (passo, linha) select '05.11 ATM com veneno na ponte (esperado 05.5 + 1 venda de 10: o vetor commissions null é payload válido)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
delete from dados.hotmart_ao_vivo where transacao in ('ENSAIO-VENENO-ATM-8', 'ENSAIO-VENENO-SET-8');  -- tira os 2 válidos; ficam só os 14 fora da regra para a foto 06
insert into pg_temp._z_out (passo, linha) select '05.11 ATM só com os 14 vetores fora da regra (esperado igual ao 05.5)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;

-- 06 com linhas de ensaio: só o ATM muda
insert into pg_temp._z_out (passo, linha) select '06 foto com ensaio (chamadas)', pg_temp.z_foto('2 com ensaio')::text;
insert into pg_temp._z_out (passo, linha) select '06 diferenças antes x com ensaio', pg_temp.z_dif('0 antes', '2 com ensaio');
insert into pg_temp._z_out (passo, linha) select '06 fora do esperado (esperado nenhuma)', coalesce((select string_agg(x, ', ') from unnest(string_to_array(pg_temp.z_dif('0 antes', '2 com ensaio'), ', ')) x where x <> 'nenhuma' and x !~ 'atm-elaine-1-2026-10' and x !~ $q$'escritorio','a4chzrru'$q$), 'nenhuma');
insert into pg_temp._z_out (passo, linha) select '06 tabela antes/depois por chamada (n antes, n depois, soma antes, soma depois)', (select string_agg(a.chamada || ': ' || coalesce(a.n::text, a.erro) || '→' || coalesce(b.n::text, b.erro) || ' | ' || coalesce(a.soma::text, '-') || '→' || coalesce(b.soma::text, '-'), E'\n    ' order by a.chamada) from pg_temp._z_foto a join pg_temp._z_foto b on b.chamada = a.chamada and b.fase = '2 com ensaio' where a.fase = '0 antes' and (a.n, a.soma, a.md5, a.erro) is distinct from (b.n, b.soma, b.md5, b.erro));

-- 07 explain com as linhas de ensaio
do $x$ declare r record; i int; begin
  for i in 1..2 loop  -- 1ª = cache frio; guarda a 2ª
    for r in explain (analyze, buffers) select * from dados.transacoes('escritorio','a4chzrru') loop
      if i = 2 then insert into pg_temp._z_out (passo, linha) values ('07 explain depois dados.transacoes(escritorio,a4chzrru)', r."QUERY PLAN"); end if;
    end loop;
  end loop;
end $x$;
insert into pg_temp._z_out (passo, linha) select '07 tempo por função antes x vazia x com ensaio (ms; ATM e escritorio/a4chzrru)', (select string_agg(a.chamada || ' ' || a.ms || ' / ' || b.ms || ' / ' || c.ms, E'\n    ' order by a.chamada) from pg_temp._z_foto a join pg_temp._z_foto b on b.chamada = a.chamada and b.fase = '1 depois vazia' join pg_temp._z_foto c on c.chamada = a.chamada and c.fase = '2 com ensaio' where a.fase = '0 antes' and a.erro is null and (a.chamada ~ 'atm-elaine-1-2026-10' or a.chamada ~ $q$'escritorio','a4chzrru'$q$));
insert into pg_temp._z_out (passo, linha) select '07 tempo total da foto (ms) antes / vazia / com ensaio', (select string_agg(fase || '=' || round(sum_ms), ' / ' order by fase) from (select fase, sum(ms) sum_ms from pg_temp._z_foto group by fase) z);

-- 08 reversão (texto de 20261013193000_reversao.sql)
-- 20261013193000_reversao.sql: desfaz 20261013193000 (marca 20261013av) inteira.
--
-- O que faz: volta o corpo de dados.transacoes guardado em acesso.corpo_antes (md5 do prosrc conferido, byte a byte),
-- confere antes que o corpo vivo ainda é o desta migration (md5 efbd212fc50a114fa307b4681454e1a9), tira o cron dados-hotmart-ao-vivo-limpar e apaga dados.hotmart_ao_vivo (com o que estiver dentro, que é só ponte: o
-- espelho do Financeiro continua com tudo) e as 4 funções novas. Não toca fin.*, cs.*, os webhooks nem o sync.
-- Antes de rodar em produção: tirar o webhook na Hotmart (senão ela recebe 500 até o cadastro sair). O arquivo já
-- abre e fecha a própria transação (begin ... commit); em psql, rodar com ON_ERROR_STOP. Ensaiada dentro de 20261013193000_ensaio.sql (aplica, reverte, compara).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $r$
declare
  v_def text;
  v_md5 text;
begin
  select c.definicao, c.md5 into v_def, v_md5
    from acesso.corpo_antes c
   where c.tipo = 'funcao' and c.migration = '20261013av' and c.alvo = 'dados.transacoes(text,text)';
  if v_def is null then
    raise exception '20261013av reversão: corpo de antes não está em acesso.corpo_antes; nada foi revertido';
  end if;
  -- só restaura se o corpo vivo ainda for o que esta migration aplicou (alguém pode ter mudado depois)
  if md5((select p.prosrc from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure)) <> 'efbd212fc50a114fa307b4681454e1a9' then
    raise exception '20261013av reversão: corpo vivo de dados.transacoes não é o desta migration (md5 %); conferir antes, nada foi revertido',
      md5((select p.prosrc from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure));
  end if;
  execute v_def;
  if md5((select p.prosrc from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure)) <> v_md5 then
    raise exception '20261013av reversão: corpo restaurado não bate com o md5 guardado; nada foi revertido';
  end if;
end
$r$;

select cron.unschedule(j.jobid) from cron.job j where j.jobname = 'dados-hotmart-ao-vivo-limpar';

drop function if exists dados.hotmart_ao_vivo_sem_espelho(integer);
drop function if exists dados.hotmart_ao_vivo_limpar();
drop function if exists dados.hotmart_ao_vivo_gravar(text, jsonb);
drop function if exists dados.hotmart_ao_vivo_payload_ok(jsonb);
drop table if exists dados.hotmart_ao_vivo;

delete from acesso.corpo_antes where tipo = 'funcao' and migration = '20261013av' and alvo = 'dados.transacoes(text,text)';
delete from supabase_migrations.schema_migrations where version = '20261013193000';

-- (commit da reversão omitido: aqui ela roda dentro da transação desfeita do ensaio)
set local statement_timeout = '300s';  -- a migration baixa para 30s; o ensaio volta para 300s
insert into pg_temp._z_out (passo, linha) select '08 objetos depois da reversão (esperado tudo nulo, md5 = 58fbc58cf082979b92dda008ddbdf808)', jsonb_build_object(
  'tabela', to_regclass('dados.hotmart_ao_vivo')::text, 'gravar', to_regprocedure('dados.hotmart_ao_vivo_gravar(text,jsonb)')::text, 'payload_ok', to_regprocedure('dados.hotmart_ao_vivo_payload_ok(jsonb)')::text,
  'limpar', to_regprocedure('dados.hotmart_ao_vivo_limpar()')::text, 'sem_espelho', to_regprocedure('dados.hotmart_ao_vivo_sem_espelho(integer)')::text,
  'cron', (select count(*) from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar'),
  'corpo_antes', (select count(*) from acesso.corpo_antes where migration = '20261013av'),
  'md5_transacoes', (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure))::text;
insert into pg_temp._z_out (passo, linha) select '08 corpo volta byte a byte', ((select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure) = '58fbc58cf082979b92dda008ddbdf808')::text;
insert into pg_temp._z_out (passo, linha) select '09 foto depois da reversão (chamadas)', pg_temp.z_foto('3 depois da reversao')::text;
insert into pg_temp._z_out (passo, linha) select '09 diferenças antes x depois da reversão (esperado nenhuma)', pg_temp.z_dif('0 antes', '3 depois da reversao');

-- 10 reaplica (passada 3, depois da reversão) para o passo 6, a limpeza, o alerta e a escala
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
set local statement_timeout = '300s';  -- a migration baixa para 30s; o ensaio volta para 300s
insert into pg_temp._z_out (passo, linha) select '10 objetos reaplicados', jsonb_build_object(
  'tabela', to_regclass('dados.hotmart_ao_vivo')::text, 'gravar', to_regprocedure('dados.hotmart_ao_vivo_gravar(text,jsonb)')::text, 'payload_ok', to_regprocedure('dados.hotmart_ao_vivo_payload_ok(jsonb)')::text,
  'limpar', to_regprocedure('dados.hotmart_ao_vivo_limpar()')::text, 'sem_espelho', to_regprocedure('dados.hotmart_ao_vivo_sem_espelho(integer)')::text,
  'cron', (select count(*) from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar'),
  'corpo_antes', (select count(*) from acesso.corpo_antes where migration = '20261013av'),
  'md5_transacoes', (select md5(prosrc) from pg_proc where oid = 'dados.transacoes(text,text)'::regprocedure))::text;
insert into pg_temp._z_out (passo, linha) select '10.1 A APPROVED', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-A', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '10 minutes', 'a4chzrru', 1000))::text;
insert into pg_temp._z_out (passo, linha) select '10.1 A COMPLETED', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-A', 'PURCHASE_COMPLETE', 'COMPLETED', now() - interval '5 minutes', 'a4chzrru', 1000))::text;
insert into pg_temp._z_out (passo, linha) select '10.1 B APPROVED', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-B', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '10 minutes', 'a4chzrru', 500))::text;
insert into pg_temp._z_out (passo, linha) select '10.1 B REFUNDED', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-ATM-B', 'PURCHASE_REFUNDED', 'REFUNDED', now() - interval '1 minute', 'a4chzrru', 500))::text;
insert into pg_temp._z_out (passo, linha) select '10.1 C COMPLETED (oferta fora)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-OUTRA-C', 'PURCHASE_COMPLETE', 'COMPLETED', now() - interval '3 minutes', 'ENSAIOX', 700))::text;
insert into pg_temp._z_out (passo, linha) select '10.1 E APPROVED (oferta fora)', dados.hotmart_ao_vivo_gravar('escritorio', pg_temp.z_ev('ENSAIO-OUTRA-E', 'PURCHASE_APPROVED', 'APPROVED', now() - interval '3 minutes', 'ENSAIOX', 300))::text;
insert into pg_temp._z_out (passo, linha) select '10.2 ATM só com o webhook (esperado = 05.4)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
-- passo 6: a mesma transação chega no espelho como o sync grava (CRM desligado só dentro desta transação)
update crm.config set hotmart_ligado = false where hotmart_ligado;
insert into fin.hotmart_transacoes (transacao, conta, produto_id, oferta_codigo, status, recorrencia, moeda, valor_base, valor_cobrado,
  liquido_produtor, taxa_hotmart, pedido_em, aprovado_em, comprador_email, comprador_nome, bruto_json, primeiro_visto_em, atualizado_em)
values ('ENSAIO-ATM-A', 'escritorio', '5238525', 'a4chzrru', 'COMPLETE', 1, 'BRL', 1000, 1000, 900, 100, now(), now(),
        'ensaio-atm-a@ensaio.local', 'Ensaio Ao Vivo', '{}'::jsonb, now() - interval '25 hours', now() - interval '25 hours'),
       ('ENSAIO-OUTRA-E', 'escritorio', '5238525', 'ENSAIOX', 'APPROVED', 1, 'BRL', 300, 300, 270, 30, now(), now(),
        'ensaio-outra-e@ensaio.local', 'Ensaio Ao Vivo', '{}'::jsonb, now() - interval '1 hour', now() - interval '1 hour');
insert into pg_temp._z_out (passo, linha) select '10.3 ATM com A também no espelho (esperado = 05.4, repetidas 0)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
insert into pg_temp._z_out (passo, linha) select '10.3 A aparece quantas vezes (esperado 1)', (select count(*) from dados.transacoes('escritorio', 'a4chzrru') where transacao = 'ENSAIO-ATM-A')::text;
insert into pg_temp._z_out (passo, linha) select '10.3 group by transacao having count > 1 no ATM (esperado 0)', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z)::text;
insert into pg_temp._z_out (passo, linha) select '10.4 limpar (esperado 1: só A, par visto há 25 h; E tem par há 1 h e fica)', dados.hotmart_ao_vivo_limpar()::text;
insert into pg_temp._z_out (passo, linha) select '10.4 linhas na ponte depois (esperado B, C, E)', (select string_agg(transacao, ',' order by transacao) from dados.hotmart_ao_vivo);
insert into pg_temp._z_out (passo, linha) select '10.4 limpar de novo (esperado 0)', dados.hotmart_ao_vivo_limpar()::text;
insert into pg_temp._z_out (passo, linha) select '10.4 ATM depois da limpeza (esperado = 10.3)', jsonb_build_object(
  'vendas_todas', (select count(*) from dados.atm_vendas_todas('atm-elaine-1-2026-10')), 'receita_todas', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas_todas('atm-elaine-1-2026-10')),
  'vendas', (select count(*) from dados.atm_vendas('atm-elaine-1-2026-10')), 'receita', (select coalesce(sum(valor_bruto), 0) from dados.atm_vendas('atm-elaine-1-2026-10')),
  'linhas_transacoes', (select count(*) from dados.transacoes('escritorio', 'a4chzrru')),
  'repetidas', (select count(*) from (select transacao from dados.transacoes('escritorio', 'a4chzrru') group by 1 having count(*) > 1) z))::text;
update dados.hotmart_ao_vivo set primeiro_em = now() - interval '4 hours' where transacao in ('ENSAIO-ATM-B', 'ENSAIO-OUTRA-C', 'ENSAIO-OUTRA-E');
insert into pg_temp._z_out (passo, linha) select '10.5 alerta sem espelho > 3 h (esperado só C: B é REFUNDED, E tem par)', (select coalesce(string_agg(transacao || ' ' || status || ' ' || horas_sem_espelho, '; '), 'nenhum') from dados.hotmart_ao_vivo_sem_espelho());
insert into pg_temp._z_out (passo, linha) select '10.5 alerta com 5 h (esperado nenhum)', (select coalesce(string_agg(transacao, '; '), 'nenhum') from dados.hotmart_ao_vivo_sem_espelho(5));
-- 10x: ~700 linhas/mês estimadas; simula 5.000 linhas em ofertas falsas e mede
insert into dados.hotmart_ao_vivo (conta, transacao, evento, evento_id, evento_em, status, produto_id, oferta_codigo, payload)
select 'escritorio', 'ENSAIO-ESC-' || g, 'PURCHASE_APPROVED', null, now(), 'APPROVED', '5238525', 'ENSAIOESC' || (g % 50), '{"data":{}}'::jsonb
  from generate_series(1, 5000) g;
analyze dados.hotmart_ao_vivo;
do $x$ declare r record; i int; begin
  for i in 1..2 loop  -- 1ª = cache frio; guarda a 2ª
    for r in explain (analyze, buffers) select * from dados.transacoes('escritorio','a4chzrru') loop
      if i = 2 then insert into pg_temp._z_out (passo, linha) values ('10.6 explain 5.000 linhas: dados.transacoes(escritorio,a4chzrru)', r."QUERY PLAN"); end if;
    end loop;
  end loop;
end $x$;
do $x$ declare r record; i int; begin
  for i in 1..2 loop  -- 1ª = cache frio; guarda a 2ª
    for r in explain (analyze, buffers) select a.transacao from dados.hotmart_ao_vivo a where a.conta = 'escritorio' and a.oferta_codigo = any (array['a4chzrru']) and dados.hotmart_ao_vivo_payload_ok(a.payload) and not exists (select 1 from (select * from fin.hotmart_transacoes where conta = 'escritorio') h where h.transacao = a.transacao) loop
      if i = 2 then insert into pg_temp._z_out (passo, linha) values ('10.6 explain 5.000 linhas: ramo ao_vivo isolado', r."QUERY PLAN"); end if;
    end loop;
  end loop;
end $x$;
do $x$ declare r record; i int; begin
  for i in 1..2 loop  -- 1ª = cache frio; guarda a 2ª
    for r in explain (analyze, buffers) delete from dados.hotmart_ao_vivo a where a.conta = 'escritorio' and exists (select 1 from (select * from fin.hotmart_transacoes where conta = 'escritorio') h where h.transacao = a.transacao and h.primeiro_visto_em < now() - interval '24 hours') loop
      if i = 2 then insert into pg_temp._z_out (passo, linha) values ('10.6 explain 5.000 linhas: limpeza (delete, desfeito)', r."QUERY PLAN"); end if;
    end loop;
  end loop;
end $x$;
do $x$ declare r record; i int; begin
  for i in 1..2 loop  -- 1ª = cache frio; guarda a 2ª
    for r in explain (analyze, buffers) insert into dados.hotmart_ao_vivo as t (conta, transacao, evento, evento_em, status, payload) values ('escritorio', 'ENSAIO-ESC-77', 'PURCHASE_APPROVED', now() - interval '1 day', 'APPROVED', '{}') on conflict (conta, transacao) do update set status = excluded.status where excluded.evento_em > t.evento_em loop
      if i = 2 then insert into pg_temp._z_out (passo, linha) values ('10.6 explain 5.000 linhas: upsert pela PK', r."QUERY PLAN"); end if;
    end loop;
  end loop;
end $x$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
