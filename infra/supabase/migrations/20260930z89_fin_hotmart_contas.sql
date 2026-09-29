-- 20260930z89 — Segunda conta Hotmart no Financeiro: "escritorio" (empresa Soluções) ao lado de "academy" (Academy).
--
-- POR QUÊ
--   O espelho fin.hotmart_* só conhece uma conta (Vault 'hotmart_hm_basic'). As vendas dos eventos do escritório
--   (setor = 'escritorio', desde 2025) caem numa 2ª conta Hotmart, da Soluções — por isso fn_fin_funis marca
--   esses eventos com conta_ausente. Esta migration prepara o banco para a 2ª conta, SEM trazer venda nenhuma:
--     1. fin.hotmart_contas — cadastro das contas (qual segredo do Vault, qual empresa, ligada/desligada).
--     2. coluna conta (default 'academy', FK) em hotmart_transacoes, produtos, hotmart_catalogo, hotmart_sync_fila.
--        Fila: unique hotmart_sync_fila_uk passa a incluir conta (a mesma janela pode existir nas 2 contas).
--     3. fin.hotmart_credenciais_conta(p_conta) — credencial por conta (a atual fin.hotmart_credenciais() fica intacta).
--     4. fin.vw_transacoes ganha conta e empresa NO FIM (colunas antigas na mesma ordem).
--     5. fin.hotmart_transacoes_colisao — se a 2ª conta devolver um código de transação que já existe na outra
--        conta, a edge grava aqui em vez de sobrescrever (PK de hotmart_transacoes continua só transacao).
--     6. Patches sobre o CORPO VIVO, com guarda md5 (aborta se alguém mudou a função depois de 29/09):
--        - fn_fin_caixa_hotmart / fn_fin_caixa_hotmart_totais: filtram conta = 'academy'. Hoje somam TODA venda
--          paga, sem filtro de produto; quando a Soluções entrar, o dinheiro dela apareceria no caixa da Academy.
--          Assinatura e retorno inalterados.
--        - fn_fin_funis: conta_ausente deixa de depender só da data — passa a ser verdadeiro apenas enquanto a
--          conta 'escritorio' não estiver ativa em fin.hotmart_contas.
--   7. (pentest 29/09) fin.vw_transacoes passa a ser SÓ academy; fin.vw_transacoes_escritorio lê a outra conta.
--      'escritorio' nasce ativa = false: ativação é passo separado, depois do catálogo + backfill.
--      6b: os 15 leitores DIRETOS de fin.hotmart_transacoes filtram academy; fn_fin_funis, fn_fin_funil_compradores e
--      fn_fin_hotmart_funis leem fin.vw_transacoes_contas filtrando a conta do evento/família (escritório pós-2025).
--      6c: view fin.hotmart_transacoes_identidade só academy (identidade não funde escritório — decisão do dono).
--   8. Trava (pentest 29/09, achado MÉDIO): fin.trava_conta_hotmart_violacao confere CITAÇÃO a citação (sem
--      comentários) e aprova por nome+md5 os 7 objetos que leem todas as contas ou filtram fora da forma canônica.
--      Roda no apply sobre o banco inteiro E num event trigger (trava_conta_hotmart, ddl_command_end) em toda
--      CREATE/ALTER FUNCTION|PROCEDURE|VIEW daqui em diante. Desligar: alter event trigger trava_conta_hotmart disable.
--        - fin.hotmart_sync_enfileirar: grava a conta do produto na fila e só enfileira produto de conta ativa.
--   NÃO faz backfill, NÃO mexe na edge hotmart-sync nem nos crons '*' (ver CONTRATO no fim).
--
-- REVERSÃO
--   Desligar sem desfazer: update fin.hotmart_contas set ativa = false where conta = 'escritorio';
--     → credencial da conta volta NULL (edge pula), enfileirar ignora os produtos dela, funis volta a marcar
--       conta_ausente nos eventos do escritório. Colunas novas têm default 'academy': leitores antigos e
--       inserts que não citam conta continuam funcionando sem mudança.
--   Desfazer de verdade (ordem): drop event trigger trava_conta_hotmart, drop function fin.trava_conta_hotmart() e
--   fin.trava_conta_hotmart_violacao(oid,oid) (PRIMEIRO — senão a trava barra a recriação dos corpos antigos); recriar as 4 funções do bloco 6 e as 17 do bloco 6b pelo corpo anterior (md5 nos
--   blocos; SALVAR pg_get_functiondef das 21 funções logo antes de aplicar — nem todas têm corpo vigente no git),
--   recriar hotmart_transacoes_identidade
--   sem o filtro de conta, drop view fin.vw_transacoes_escritorio e fin.vw_transacoes_contas, recriar
--   vw_transacoes sem conta/empresa, drop function fin.hotmart_credenciais_conta(text),
--   drop index hotmart_sync_fila_uk + recriar em (produto_id, inicio, fim, tipo) where status <> 'feito',
--   alter table ... drop column conta (4 tabelas), drop table fin.hotmart_transacoes_colisao, fin.hotmart_contas.
--
-- AS 5 PERGUNTAS
--   escala: hotmart_contas tem 2 linhas; conta em transacoes (57.283 linhas hoje) é constante até a 2ª conta
--     entrar — sem índice de propósito (filtro conta='academy' seleciona ~100% das linhas; índice não seria usado).
--     Se a Soluções passar de ~20% do volume, medir de novo e considerar (conta, aprovado_em) parcial.
--   índice: caixa continua em hotmart_transacoes_aprovado_pago_idx (provado abaixo); a junção com hotmart_contas
--     na view é removida pelo planner quando empresa não é lida (left join em PK).
--   frequência: caixa/funis são abertos pela tela do Financeiro (dezenas/dia); enfileirar 2×/semana+diário.
--   repetição: nenhuma query nova por tela — só um filtro a mais nas existentes.
--   reversão: acima.
--
-- MEDIÇÃO (projeto mbvybujpkwuorhtdzcde, 29/09/2026, claims de admin via set_config('request.jwt.claims', ...),
-- janela 2025-10-01..2026-09-29, 2ª execução na mesma sessão — a 1ª de cada sessão paga ~1,2 s de cache frio
-- do plpgsql, igual antes e depois). Ensaio da migration inteira em transação desfeita (raise exception no fim).
--
--   ANTES  fn_fin_caixa_hotmart
--     Function Scan on fn_fin_caixa_hotmart (actual time=18.766..18.790 rows=363 loops=1)
--       Buffers: shared hit=9617
--     Execution Time: 19.008 ms
--     (corpo, explain direto: Index Scan using hotmart_transacoes_aprovado_pago_idx rows=6653, 21.180 ms)
--   ANTES  fn_fin_funis
--     Function Scan on fn_fin_funis (actual time=2235.019..2235.027 rows=86 loops=1)
--       Buffers: shared hit=53803 read=25, temp read=404 written=404
--     Execution Time: 2235.061 ms          ← lentidão PRÉ-EXISTENTE (não introduzida aqui), ver relatório
--
--   DEPOIS — ver bloco "DEPOIS" preenchido abaixo pelo ensaio.
--
-- Estado vivo lido antes de escrever (29/09): md5(prosrc)
--   public.fn_fin_caixa_hotmart(date,date)        6b3798631d4fa6bfaaed8c7e89c549b3
--   public.fn_fin_caixa_hotmart_totais(date,date) 534eb1c96a79dc3b1aa82eeb29cd7080
--   public.fn_fin_funis()                         c4a28cc58fd5fc380be41203d154325d
--   fin.hotmart_sync_enfileirar(integer)          972725823548d1945a0edfc415a8ed61
--   fin.hotmart_credenciais()                     322aae2712326c5a3bb878f32114a095 (não alterada)
--   hotmart_sync_fila_uk = unique (produto_id, inicio, fim, tipo) where status <> 'feito'

set local lock_timeout = '5s';

-- 1. Cadastro das contas ------------------------------------------------------------------------------------------
create table if not exists fin.hotmart_contas (
  conta      text primary key check (conta ~ '^[a-z][a-z0-9_]*$'),
  empresa    text not null,
  vault_nome text not null,
  ativa      boolean not null default true
);
comment on table fin.hotmart_contas is
  'Contas Hotmart espelhadas no Financeiro. vault_nome = nome do segredo (Basic) em vault.secrets. ativa=false desliga sync e marca conta_ausente nos funis.';

insert into fin.hotmart_contas (conta, empresa, vault_nome, ativa) values
  ('academy',    'Academy',  'hotmart_hm_basic',             true),
  ('escritorio', 'Soluções', 'fin_hotmart_basic_escritorio', false)  -- nasce DESLIGADA (pentest 29/09, achado BAIXO)
on conflict (conta) do nothing;

alter table fin.hotmart_contas enable row level security;
revoke all on fin.hotmart_contas from public, anon, authenticated;

-- 2. Coluna conta nas 4 tabelas do espelho --------------------------------------------------------------------------
alter table fin.hotmart_transacoes add column if not exists conta text not null default 'academy' references fin.hotmart_contas(conta);
alter table fin.produtos           add column if not exists conta text not null default 'academy' references fin.hotmart_contas(conta);
alter table fin.hotmart_catalogo   add column if not exists conta text not null default 'academy' references fin.hotmart_contas(conta);
alter table fin.hotmart_sync_fila  add column if not exists conta text not null default 'academy' references fin.hotmart_contas(conta);

-- Sem estatística da coluna nova, o planner estima conta='academy' em 0,5% (22 linhas em vez de 6.653) e troca o
-- HashAggregate do caixa por Sort externo em disco (medido no ensaio: 19 → 30 ms, 6,5 MB de temp). O analyze corrige.
analyze fin.hotmart_transacoes;

drop index if exists fin.hotmart_sync_fila_uk;
create unique index hotmart_sync_fila_uk on fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo) where status <> 'feito';

-- 3. Credencial por conta (espelha fin.hotmart_credenciais(); a original fica intacta) ------------------------------
create or replace function fin.hotmart_credenciais_conta(p_conta text)
 returns table(basic text, chave_sync text)
 language sql
 security definer
 set search_path to ''
as $function$
  select (select s.decrypted_secret
            from fin.hotmart_contas c
            join vault.decrypted_secrets s on s.name = c.vault_nome
           where c.conta = p_conta and c.ativa),
         (select decrypted_secret from vault.decrypted_secrets where name = 'fin_hotmart_sync_chave');
$function$;
revoke all on function fin.hotmart_credenciais_conta(text) from public, anon, authenticated;
grant execute on function fin.hotmart_credenciais_conta(text) to service_role;

-- 4. vw_transacoes: SÓ ACADEMY, conta e empresa no FIM --------------------------------------------------------------
--    Pentest 29/09 (achado ALTO): ~27 leitores leem o espelho via esta view; filtrar AQUI fecha a classe — todo leitor
--    atual herda o filtro sem mudar corpo. A leitura do escritório é fin.vw_transacoes_escritorio (logo abaixo).
--    CREATE OR REPLACE VIEW sem WITH SUBSTITUI as reloptions (security_invoker some em silêncio): guarda e devolve.
create temp table _z89_vw_opts on commit drop as
  select c.reloptions from pg_class c where c.oid = 'fin.vw_transacoes'::regclass;

create or replace view fin.vw_transacoes as
 SELECT t.transacao,
    t.produto_id,
    COALESCE(p.familia, 'OUTRO'::text) AS familia,
    COALESCE(p.papel, 'desconhecido'::text) AS papel_produto,
    t.produto_nome,
    t.oferta_codigo,
    t.oferta_modo,
    t.status,
    t.recorrencia,
    t.metodo,
    t.tipo_pagamento,
    t.parcelas,
    COALESCE(t.valor_base, (NULLIF((t.bruto_json #>> '{purchase,hotmart_fee,base}'::text[]), ''::text))::numeric, t.valor_cobrado) AS valor_oferta,
    t.valor_cobrado,
    GREATEST(COALESCE(t.juros_parcelamento, (0)::numeric), (t.valor_cobrado - COALESCE(t.valor_base, (NULLIF((t.bruto_json #>> '{purchase,hotmart_fee,base}'::text[]), ''::text))::numeric, t.valor_cobrado)), (0)::numeric) AS juros,
    t.taxa_hotmart,
        CASE
            WHEN (t.status = ANY (ARRAY['APPROVED'::text, 'COMPLETE'::text])) THEN COALESCE(t.liquido_produtor, (COALESCE(t.valor_base, (NULLIF((t.bruto_json #>> '{purchase,hotmart_fee,base}'::text[]), ''::text))::numeric, t.valor_cobrado) - COALESCE(t.taxa_hotmart, (0)::numeric)))
            ELSE NULL::numeric
        END AS liquido,
    ((t.status = ANY (ARRAY['APPROVED'::text, 'COMPLETE'::text])) AND (t.liquido_produtor IS NULL)) AS liquido_estimado,
        CASE
            WHEN (t.status = ANY (ARRAY['APPROVED'::text, 'COMPLETE'::text])) THEN 'pago'::text
            WHEN (t.status = ANY (ARRAY['REFUNDED'::text, 'PARTIALLY_REFUNDED'::text, 'CHARGEBACK'::text])) THEN 'estornado'::text
            WHEN (t.status = ANY (ARRAY['OVERDUE'::text, 'PROTESTED'::text])) THEN 'atrasado'::text
            WHEN (t.status = ANY (ARRAY['PRINTED_BILLET'::text, 'WAITING_PAYMENT'::text, 'UNDER_ANALISYS'::text, 'STARTED'::text])) THEN 'em_aberto'::text
            WHEN (t.status = ANY (ARRAY['CANCELLED'::text, 'NO_FUNDS'::text, 'BLOCKED'::text])) THEN 'recusado'::text
            WHEN (t.status = 'EXPIRED'::text) THEN 'expirado'::text
            ELSE 'outro'::text
        END AS grupo,
    t.pedido_em,
    t.aprovado_em,
    t.garantia_ate,
    ((t.pedido_em AT TIME ZONE 'America/Sao_Paulo'::text))::date AS dia_pedido,
    ((t.aprovado_em AT TIME ZONE 'America/Sao_Paulo'::text))::date AS dia_aprovado,
    t.origem_sck,
    lower(TRIM(BOTH FROM t.comprador_email)) AS email,
    t.comprador_nome AS nome,
    t.atualizado_em,
    t.conta,
    hc.empresa
   FROM fin.hotmart_transacoes t
     LEFT JOIN fin.produtos p ON p.produto_id = t.produto_id
     LEFT JOIN fin.hotmart_contas hc ON hc.conta = t.conta
  WHERE t.conta = 'academy'::text;

--    Duas views irmãs, geradas do corpo vivo da original (não há cópia à mão para divergir):
--      fin.vw_transacoes_escritorio — mesmo corpo, conta 'escritorio'.
--      fin.vw_transacoes_contas     — mesmo corpo SEM o filtro de conta. Uso restrito: só leitor que escolhe a conta
--        por linha (funis por evento/família). Existe porque "vw_transacoes UNION ALL vw_transacoes_escritorio" foi
--        medido no ensaio: o planner não empurra o join por produto_id para dentro do UNION de views com join —
--        fn_fin_funil_compradores 11 → 6.942 ms. Com esta view: 12 ms (mesmo plano de antes).
--        Leitor de vw_transacoes_contas só passa pela trava do bloco 8 se estiver aprovado por nome+md5 (os 3 funis).
do $vw$
declare
  v_opts text[] := (select reloptions from _z89_vw_opts);
  v_def  text   := pg_get_viewdef('fin.vw_transacoes'::regclass);
  v_todas text;
  v_n    int;
  v_nome text;
  a      record;
begin
  if v_opts is not null then
    execute format('alter view fin.vw_transacoes set (%s)', array_to_string(v_opts, ', '));
  end if;
  -- o literal da conta tem que aparecer exatamente 1 vez
  v_n := (length(v_def) - length(replace(v_def, '''academy''::text', ''))) / length('''academy''::text');
  if v_n <> 1 then
    raise exception 'z89: ''academy''::text aparece % vez(es) em fin.vw_transacoes (esperado 1)', v_n;
  end if;
  v_todas := regexp_replace(v_def, '\s+WHERE\s+\(?t\.conta = ''academy''::text\)?\s*;?\s*$', '');
  if v_todas = v_def or position('''academy''::text' in v_todas) > 0 then
    raise exception 'z89: não consegui tirar o WHERE de conta de fin.vw_transacoes: %', right(v_def, 120);
  end if;
  execute 'create or replace view fin.vw_transacoes_escritorio'
       || case when v_opts is not null then format(' with (%s)', array_to_string(v_opts, ', ')) else '' end
       || ' as ' || replace(v_def, '''academy''::text', '''escritorio''::text');
  execute 'create or replace view fin.vw_transacoes_contas'
       || case when v_opts is not null then format(' with (%s)', array_to_string(v_opts, ', ')) else '' end
       || ' as ' || v_todas;
  -- Mesma ACL da original: zera e copia grant a grant (PUBLIC incluso).
  foreach v_nome in array array['fin.vw_transacoes_escritorio', 'fin.vw_transacoes_contas'] loop
    execute format('revoke all on %s from public, anon, authenticated, service_role', v_nome);
    for a in
      select case when x.grantee = 0 then 'public' else quote_ident(r.rolname) end as quem, x.privilege_type as priv
        from pg_class c, aclexplode(c.relacl) x
        left join pg_roles r on r.oid = x.grantee
       where c.oid = 'fin.vw_transacoes'::regclass and x.grantee <> c.relowner
    loop
      execute format('grant %s on %s to %s', a.priv, v_nome, a.quem);
    end loop;
  end loop;
end
$vw$;
comment on view fin.vw_transacoes_escritorio is
  'Espelho Hotmart da conta escritorio (Soluções). Mesmas colunas, opções e grants de fin.vw_transacoes (que é só academy).';
comment on view fin.vw_transacoes_contas is
  'Espelho Hotmart de TODAS as contas (coluna conta). Uso restrito a leitor que filtra conta por linha (funis). Leitor da Academy usa fin.vw_transacoes.';

-- 5. Colisão de código de transação entre contas --------------------------------------------------------------------
create table if not exists fin.hotmart_transacoes_colisao (
  transacao text not null,
  conta     text not null references fin.hotmart_contas(conta),
  visto_em  timestamptz not null default now(),
  bruto     jsonb,
  primary key (transacao, conta)
);
comment on table fin.hotmart_transacoes_colisao is
  'Transação devolvida por uma conta Hotmart cujo código já existe em fin.hotmart_transacoes com OUTRA conta. A edge grava aqui em vez de sobrescrever.';
alter table fin.hotmart_transacoes_colisao enable row level security;
revoke all on fin.hotmart_transacoes_colisao from public, anon, authenticated;

-- 6. Patches sobre o corpo vivo, com guarda md5 e trava "trecho aparece exatamente 1 vez" ----------------------------
--    md5 = null → mesma função do passo anterior (o md5 já mudou pelo patch de cima).
do $patch$
declare
  r      record;
  v_def  text;
  v_md5  text;
  v_n    int;
begin
  for r in
    select * from (values
      (1, 'public.fn_fin_caixa_hotmart(date,date)',        '6b3798631d4fa6bfaaed8c7e89c549b3',
          'and t.aprovado_em >= v_ini_ts and t.aprovado_em < v_fim_ts',
          'and t.conta = ''academy'' and t.aprovado_em >= v_ini_ts and t.aprovado_em < v_fim_ts'),
      (2, 'public.fn_fin_caixa_hotmart_totais(date,date)', '534eb1c96a79dc3b1aa82eeb29cd7080',
          'and t.aprovado_em >= v_ini_ts and t.aprovado_em < v_fim_ts',
          'and t.conta = ''academy'' and t.aprovado_em >= v_ini_ts and t.aprovado_em < v_fim_ts'),
      (3, 'public.fn_fin_funis()',                         'c4a28cc58fd5fc380be41203d154325d',
          '(e.setor = ''escritorio'' and e.inicio >= date ''2025-01-01'')',
          '(e.setor = ''escritorio'' and e.inicio >= date ''2025-01-01'' and not exists (select 1 from fin.hotmart_contas hc where hc.conta = ''escritorio'' and hc.ativa))'),
      (4, 'fin.hotmart_sync_enfileirar(integer)',          '972725823548d1945a0edfc415a8ed61',
          'insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)',
          'insert into fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo)'),
      (5, 'fin.hotmart_sync_enfileirar(integer)',          null,
          'select p.produto_id, g::date,',
          'select p.conta, p.produto_id, g::date,'),
      (6, 'fin.hotmart_sync_enfileirar(integer)',          null,
          'where p.sincroniza',
          'where p.sincroniza and exists (select 1 from fin.hotmart_contas c where c.conta = p.conta and c.ativa)')
    ) v(ordem, sig, md5_esperado, de, para)
    order by ordem
  loop
    select md5(p.prosrc), pg_get_functiondef(p.oid) into v_md5, v_def
      from pg_proc p where p.oid = r.sig::regprocedure;
    if r.md5_esperado is not null and v_md5 is distinct from r.md5_esperado then
      raise exception 'z89: corpo vivo de % mudou (md5 % <> %). Reler a função e refazer o patch.', r.sig, v_md5, r.md5_esperado;
    end if;
    v_n := (length(v_def) - length(replace(v_def, r.de, ''))) / length(r.de);
    if v_n <> 1 then
      raise exception 'z89: trecho aparece % vez(es) em % (esperado 1): %', v_n, r.sig, r.de;
    end if;
    execute replace(v_def, r.de, r.para);
  end loop;
end
$patch$;

-- 6b. Leitores DIRETOS de fin.hotmart_transacoes + funis por conta ---------------------------------------------------
--    Mesmo molde do bloco 6, com uma diferença: cada linha diz QUANTAS vezes o trecho aparece (n) e o replace troca
--    todas — a contagem é conferida antes. Corpo vivo lido em 29/09 (md5(prosrc) na 3ª coluna).
--
--    a) Só academy (13 funções). Forma única: "fin.hotmart_transacoes X" vira
--       "(select * from fin.hotmart_transacoes where conta = 'academy') X" — subquery simples, o planner achata
--       (mesmos índices). Conferência no fim do bloco: em cada uma, toda citação de hotmart_transacoes é filtrada.
--       Identidade (recalcular_identidade, nome_da_pessoa, fn_fin_hotmart_identidade, view hotmart_transacoes_identidade):
--       escritório FORA de propósito — fundir cliente do escritório com aluno HM é decisão pendente do dono.
--       resolver_ofertas_eventos: só academy — ligar oferta do escritório a evento é passo da ativação (senão uma
--       oferta da Soluções poderia ser casada, por data, com evento da Academy).
--    b) fn_fin_hotmart_sync_status: só academy (transações E fila). A RPC devolve UMA linha e a tela é do espelho da
--       Academy; somar as 2 contas esconderia atraso da Academy atrás de sync recente da Soluções ("atualizado há
--       5 min"). Status por conta = RPC nova + tela, junto com a ativação (fora desta migration: web/** intocado).
--    c) Funis — conta do EVENTO: setor 'escritorio' com início >= 2025-01-01 lê a conta escritorio; o resto
--       (inclusive seminários do escritório de 2022–2024, que venderam pela conta da Academy — 8 eventos, R$ 684 mil
--       bruto medidos em 29/09) continua na academy. Mesmo corte de data que já define conta_ausente.
--       fn_fin_funis e fn_fin_funil_compradores (o detalhe do mesmo funil) usam a mesma regra (conta_ev), lendo
--       fin.vw_transacoes_contas com "conta = conta_ev" em todo casamento de venda com evento.
--       fn_fin_hotmart_funis é por FAMÍLIA, não por evento: lê a conta escritorio só se TODOS os produtos da família
--       são dessa conta; família mista, 'OUTRO' (coalesce da view) ou A_CLASSIFICAR ficam na academy — nunca soma as 2.
do $patch_b$
declare
  r      record;
  v_def  text;
  v_md5  text;
  v_n    int;
  v_sub  constant text := '(select * from fin.hotmart_transacoes where conta = ''academy'')';
  v_esc  constant text := 'case when %1$s.setor = ''escritorio'' and %1$s.inicio >= date ''2025-01-01'' then ''escritorio'' else ''academy'' end conta_ev';
begin
  for r in
    select * from (values
      -- a) só academy
      (10, 'fin.assinatura_hm_por_pessoa()',                        '8af4af488136d4b1efd3cfd8adb621a0', 'fin.hotmart_transacoes h', v_sub || ' h', 1),
      (11, 'fin.informados_catalogo()',                             '8a89da0000b51c0f4154ff94297c1ead', 'fin.hotmart_transacoes h', v_sub || ' h', 1),
      (12, 'fin.informados_cobertura(timestamp with time zone)',    '4eeab481dc6455df29ffb69cda492a5b', 'fin.hotmart_transacoes h', v_sub || ' h', 2),
      (13, 'fin.informados_situacao(timestamp with time zone)',     '21153124466d8491aab7e2cfc103f1c4', 'fin.hotmart_transacoes h', v_sub || ' h', 2),
      (14, 'fin.nome_da_pessoa(text)',                              'fb0f2a86d08d8bb642a4b98f148a762b', 'fin.hotmart_transacoes h', v_sub || ' h', 3),
      (15, 'fin.recalcular_identidade()',                           'd57232b856cd387e4137bc12c0fea902', 'from fin.hotmart_transacoes)', 'from fin.hotmart_transacoes where conta = ''academy'')', 2),
      (16, 'fin.resolver_ofertas_eventos(boolean,integer,text[])',  '8ebbc75c70885e9d4bee429abe24b2e2', 'fin.hotmart_transacoes t', v_sub || ' t', 2),
      (17, 'public.fn_fin_board_hotmart()',                         '4487f430664b69ef88d22c0ff0eafdae', 'fin.hotmart_transacoes h', v_sub || ' h', 2),
      (18, 'public.fn_fin_diamante_servicos()',                     'c34dceaf09c1031f41c45d6c91ac31e3', 'fin.hotmart_transacoes h', v_sub || ' h', 1),
      (19, 'public.fn_fin_hotmart_identidade()',                    'b72673295c7d3337a5d2176bf3efe9c0', 'fin.hotmart_transacoes t', v_sub || ' t', 1),
      (20, 'public.fn_fin_hotmart_pessoas(text)',                   '3a772aa8b7ce1968d73d52a7f39006a7', 'fin.hotmart_transacoes h', v_sub || ' h', 1),
      (21, 'public.fn_fin_programa_sem_card(text)',                 'bd57f052d1a16a67d592af53885a07b8', 'fin.hotmart_transacoes h', v_sub || ' h', 1),
      (22, 'public.fn_fin_receber_previsto_realizado(integer)',     'a5fb0ebc38fc04fb4b567770eae7dd57', 'fin.hotmart_transacoes h', v_sub || ' h', 1),
      -- b) status do sync: só academy
      (23, 'public.fn_fin_hotmart_sync_status()',                   '63555ec9bba204e65b7833b1ba3bf8a1', 'from fin.hotmart_transacoes)', 'from fin.hotmart_transacoes where conta = ''academy'')', 2),
      (24, 'public.fn_fin_hotmart_sync_status()',                   null, 'from fin.hotmart_sync_fila where status', 'from fin.hotmart_sync_fila where conta = ''academy'' and status', 2),
      -- informados_catalogo lista TODO fin.produtos: no ensaio com produto falso do escritório o catálogo da Academy
      -- passou de 91 para 92 linhas. Recebimento informado é da Academy → só produto academy.
      (25, 'fin.informados_catalogo()',                             null, 'from fin.produtos p', 'from (select * from fin.produtos where conta = ''academy'') p', 2),
      -- c) funis pela conta do evento
      (30, 'public.fn_fin_funil_compradores(bigint)',               '4d37da9419f77f6bb6e1f959130160ba', 'x.inicio - 60) ing_de', 'x.inicio - 60) ing_de, ' || format(v_esc, 'x'), 1),
      (31, 'public.fn_fin_funil_compradores(bigint)',               null, 'join fin.hotmart_transacoes t0 on t0.oferta_codigo', 'join fin.hotmart_transacoes t0 on t0.conta = e.conta_ev and t0.oferta_codigo', 1),
      (32, 'public.fn_fin_funil_compradores(bigint)',               null, 'join fin.vw_transacoes t on t.produto_id = p.produto_id', 'join fin.vw_transacoes_contas t on t.produto_id = p.produto_id and t.conta = e.conta_ev', 1),
      (33, 'public.fn_fin_funil_compradores(bigint)',               null, 'join fin.hotmart_transacoes h on h.transacao = t.transacao', 'join fin.hotmart_transacoes h on h.transacao = t.transacao and h.conta = t.conta', 1),
      -- fn_fin_funis: md5 null — o bloco 6 já conferiu o md5 original nesta mesma transação e trocou conta_ausente
      (40, 'public.fn_fin_funis()',                                 null, 'e.inicio - 60) ing_de', 'e.inicio - 60) ing_de, ' || format(v_esc, 'e'), 1),
      (41, 'public.fn_fin_funis()',                                 null, 'select t.transacao, t.produto_id, t.oferta_codigo, t.email', 'select t.conta, t.transacao, t.produto_id, t.oferta_codigo, t.email', 1),
      (42, 'public.fn_fin_funis()',                                 null, 'from fin.vw_transacoes t', 'from fin.vw_transacoes_contas t', 1),
      -- conta NÃO entra no join: "x.conta = e.conta_ev" no join derrubou a estimativa (0,5%) e o plano foi de
      -- 1.960 ms / 53 mil buffers para 14.053 ms / 9,8 milhões (medido no ensaio). casado vira MATERIALIZED (cerca:
      -- mesmo plano de antes para o casamento) e a conta filtra DEPOIS, antes de agregar.
      (43, 'public.fn_fin_funis()',                                 null, 'casado as (', 'casado as materialized (', 1),
      (44, 'public.fn_fin_funis()',                                 null, 'select e.id, p.papel, x.*', 'select e.id, p.papel, e.conta_ev, x.*', 1),
      (45, 'public.fn_fin_funis()',                                 null, 'then ''ingresso'' else ''oferta'' end,', 'then ''ingresso'' else ''oferta'' end, e.conta_ev,', 1),
      (46, 'public.fn_fin_funis()',                                 null, 'from casado c group by c.id', 'from casado c where c.conta = c.conta_ev group by c.id', 1),
      (50, 'public.fn_fin_hotmart_funis(text,date,date)',           'f74a829822e01739565baf93ca0993ea', 'v_fim  date := coalesce(p_fim, v_hoje);',
          'v_fim  date := coalesce(p_fim, v_hoje); v_conta text := case when exists (select 1 from fin.produtos p where p.familia = p_familia and p.conta = ''escritorio'') and not exists (select 1 from fin.produtos p where p.familia = p_familia and p.conta <> ''escritorio'') then ''escritorio'' else ''academy'' end;', 1),
      (51, 'public.fn_fin_hotmart_funis(text,date,date)',           null, 'from fin.vw_transacoes x where x.familia = p_familia',
          'from fin.vw_transacoes_contas x where x.conta = v_conta and x.familia = p_familia', 1)
    ) v(ordem, sig, md5_esperado, de, para, n)
    order by ordem
  loop
    select md5(p.prosrc), pg_get_functiondef(p.oid) into v_md5, v_def
      from pg_proc p where p.oid = r.sig::regprocedure;
    if r.md5_esperado is not null and v_md5 is distinct from r.md5_esperado then
      raise exception 'z89: corpo vivo de % mudou (md5 % <> %). Reler a função e refazer o patch.', r.sig, v_md5, r.md5_esperado;
    end if;
    v_n := (length(v_def) - length(replace(v_def, r.de, ''))) / length(r.de);
    if v_n <> r.n then
      raise exception 'z89: trecho aparece % vez(es) em % (esperado %): %', v_n, r.sig, r.n, r.de;
    end if;
    execute replace(v_def, r.de, r.para);   -- create or replace: mantém dono, ACL, security definer e proconfig
  end loop;

  -- Conferência de a) e b): toda citação de hotmart_transacoes nessas 14 funções é a forma filtrada.
  select string_agg(x.sig, ', ') into v_def
    from (select p.oid::regprocedure::text sig,
                 (select count(*) from regexp_matches(p.prosrc, 'hotmart_transacoes\M', 'g')) tot,
                 (select count(*) from regexp_matches(p.prosrc, 'hotmart_transacoes where conta = ''academy''\)', 'g')) filtr
            from pg_proc p
           where p.oid in ('fin.assinatura_hm_por_pessoa()'::regprocedure, 'fin.informados_catalogo()'::regprocedure,
                           'fin.informados_cobertura(timestamp with time zone)'::regprocedure,
                           'fin.informados_situacao(timestamp with time zone)'::regprocedure, 'fin.nome_da_pessoa(text)'::regprocedure,
                           'fin.recalcular_identidade()'::regprocedure, 'fin.resolver_ofertas_eventos(boolean,integer,text[])'::regprocedure,
                           'public.fn_fin_board_hotmart()'::regprocedure, 'public.fn_fin_diamante_servicos()'::regprocedure,
                           'public.fn_fin_hotmart_identidade()'::regprocedure, 'public.fn_fin_hotmart_pessoas(text)'::regprocedure,
                           'public.fn_fin_programa_sem_card(text)'::regprocedure,
                           'public.fn_fin_receber_previsto_realizado(integer)'::regprocedure,
                           'public.fn_fin_hotmart_sync_status()'::regprocedure)) x
   where x.tot <> x.filtr;
  if v_def is not null then
    raise exception 'z89: leitura de hotmart_transacoes sem filtro academy sobrou em: %', v_def;
  end if;
end
$patch_b$;

-- 6c. View fin.hotmart_transacoes_identidade (base do grafo de identidade): só academy --------------------------------
--    Colunas explícitas no corpo (sem t.*): a coluna conta NÃO entra na view, só o filtro. Mesmo cuidado de reloptions
--    da vw_transacoes; ACL é preservada pelo CREATE OR REPLACE.
do $vw_ident$
declare
  v_def  text := pg_get_viewdef('fin.hotmart_transacoes_identidade'::regclass);
  v_opts text[] := (select c.reloptions from pg_class c where c.oid = 'fin.hotmart_transacoes_identidade'::regclass);
  v_de   constant text := 'WHERE (NOT (EXISTS';
  v_n    int;
begin
  if md5(v_def) is distinct from '0211f68ae65dc1c3f0843880e1a3a427' then
    raise exception 'z89: fin.hotmart_transacoes_identidade mudou (md5 %). Reler e refazer.', md5(v_def);
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_de, ''))) / length(v_de);
  if v_n <> 1 then
    raise exception 'z89: trecho aparece % vez(es) em hotmart_transacoes_identidade (esperado 1)', v_n;
  end if;
  execute 'create or replace view fin.hotmart_transacoes_identidade as '
       || replace(v_def, v_de, 'WHERE t.conta = ''academy''::text AND (NOT (EXISTS');
  if v_opts is not null then
    execute format('alter view fin.hotmart_transacoes_identidade set (%s)', array_to_string(v_opts, ', '));
  end if;
end
$vw_ident$;

-- 8. Trava de leitor: conferência por citação + event trigger (pentest 29/09, achado MÉDIO) --------------------------
--    A trava antiga (regex "conta =" em qualquer ponto do corpo) era por OBJETO e deixava passar: a própria
--    vw_transacoes_contas (o "hc.conta = t.conta" do join casava), comentário com "conta =", e corpo com uma leitura
--    filtrada e outra não. E só rodava no apply desta migration — não protegia leitor futuro (o comentário dizia que sim).
--    Agora a regra mora em UMA função, fin.trava_conta_hotmart_violacao, usada em dois lugares:
--      a) no apply (fim deste bloco): todo pg_proc/view/matview do banco é conferido;
--      b) no event trigger trava_conta_hotmart (ddl_command_end): toda CREATE/ALTER FUNCTION|PROCEDURE, CREATE/ALTER
--         VIEW e CREATE MATERIALIZED VIEW daqui em diante é conferida na hora — a DDL que violar é desfeita com erro.
--    Regra (texto do corpo SEM comentários; literais são mantidos):
--      1. Corpo aprovado = nome + md5 do corpo em v_aprovados → passa. Mudou 1 byte, sai da lista (de propósito: quem
--         muda um funil ou uma view do espelho atualiza v_aprovados NA MESMA migration, com create or replace desta
--         função ANTES do create or replace do objeto; o erro da trava já traz o md5 novo).
--      2. Citou vw_transacoes_contas e não está aprovado → falha. (Só os 3 funis leem todas as contas.)
--      3. Cada citação de hotmart_transacoes (palavra inteira; "hotmart_transacoes.col" e "%rowtype" não contam) tem
--         que estar na forma canônica, uma a uma:
--             (select * from fin.hotmart_transacoes where conta = '<conta>') x      -- ou  = p_xxx / v_xxx
--         Faltou uma → falha. Escritor de hotmart_transacoes dentro do banco (hoje: 0) entra em v_aprovados.
--    Limites (declarados): SQL montado por concatenação ('hotmart_' || 'transacoes') não é visto; "where conta =
--    'academy' or true" passa (a trava é contra esquecimento, não contra sabotagem de quem já tem DDL); DDL de
--    superusuário (supabase_admin) não dispara event trigger no Supabase; policy/rule/trigger não são conferidos;
--    string E'...' com \', dollar-quote aninhado com -- dentro e identificador entre aspas duplas contendo --, /* ou '
--    (ex.: as "--total") podem confundir o corte de comentários — um /* sem fechamento descarta o resto do corpo.
--    Falha INTERNA da conferência (bug, catálogo) não bloqueia DDL: vira WARNING e a DDL segue — event trigger que
--    quebra trava TODA DDL do projeto. A violação da regra, essa sim, aborta.
--    ⚠️ Função dropada ou recriada com erro = trava desligada EM SILÊNCIO (só WARNING, invisível no db push).
--    REGRA: toda migration que recriar fin.trava_conta_hotmart_violacao REPETE no fim o bloco do $trava$ (~0,4 s).
--    DESLIGAR:  alter event trigger trava_conta_hotmart disable;      (religar: ... enable)
--    REMOVER:   drop event trigger trava_conta_hotmart; drop function fin.trava_conta_hotmart();
--               drop function fin.trava_conta_hotmart_violacao(oid, oid);
create or replace function fin.trava_conta_hotmart_violacao(p_classid oid, p_objid oid)
 returns text
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  -- nome (regprocedure/regclass com schema) | md5 do corpo cru (prosrc; view: pg_get_viewdef com search_path '')
  v_aprovados constant text[] := array[
    -- leem fin.vw_transacoes_contas (conta por linha, pela conta do evento/família)
    'public.fn_fin_funis()|b72ed7dda46ecc1c6ff0c0ebf835e2a0',
    'public.fn_fin_funil_compradores(bigint)|f354c46da0d29c173d46daf52d7c1421',
    'public.fn_fin_hotmart_funis(text,date,date)|a36eed87268bb5ca192b3857d9e8476c',
    -- views do espelho (filtro de conta no WHERE final, fora da forma canônica)
    'fin.vw_transacoes|cda2f17094687e5ccb47447a98acc2ca',
    'fin.vw_transacoes_escritorio|3c0fbd675bf280e1a26c813bf3ce7692',
    'fin.vw_transacoes_contas|6f8931078a38ff6327519c86f953c788',
    'fin.hotmart_transacoes_identidade|189be8b9849b529e25fdc6ccf36fae6f'
    -- escritores de fin.hotmart_transacoes no banco: nenhum (a edge hotmart-sync não é objeto do banco)
  ];
  v_obj  text;
  v_src  text;
  v_s    text := '';
  v_tot  int;
  v_ok   int;
  i int := 1; j int; k int; d int;
begin
  if p_classid = 'pg_catalog.pg_proc'::regclass then
    if p_objid in ('fin.trava_conta_hotmart_violacao(oid,oid)'::regprocedure, 'fin.trava_conta_hotmart()'::regprocedure) then
      return null;  -- a própria trava cita os nomes nas regras
    end if;
    select p.oid::regprocedure::text, coalesce(nullif(p.prosrc, ''), pg_get_functiondef(p.oid))
      into v_obj, v_src
      from pg_catalog.pg_proc p where p.oid = p_objid and p.prolang not in (12, 13);  -- internal, c
  elsif p_classid = 'pg_catalog.pg_class'::regclass then
    select c.oid::regclass::text, pg_get_viewdef(c.oid)
      into v_obj, v_src
      from pg_catalog.pg_class c where c.oid = p_objid and c.relkind in ('v', 'm');
  end if;
  if v_src is null or v_src !~* '(hotmart_transacoes|vw_transacoes_contas)' then
    return null;  -- caminho rápido: a imensa maioria das DDL para aqui
  end if;
  if (v_obj || '|' || md5(v_src)) = any (v_aprovados) then
    return null;
  end if;

  -- tira comentários (-- e /* */ aninhado) respeitando literais '...' ('' escapado); literais ficam
  loop
    j := regexp_instr(v_src, '''|--|/\*', i);
    if j = 0 then v_s := v_s || substr(v_src, i); exit; end if;
    v_s := v_s || substr(v_src, i, j - i);
    if substr(v_src, j, 1) = '''' then
      k := j + 1;
      loop
        k := regexp_instr(v_src, '''', k);
        exit when k = 0 or substr(v_src, k + 1, 1) <> '''';
        k := k + 2;
      end loop;
      if k = 0 then v_s := v_s || substr(v_src, j); exit; end if;
      v_s := v_s || substr(v_src, j, k - j + 1);
      i := k + 1;
    elsif substr(v_src, j, 2) = '--' then
      k := strpos(substr(v_src, j), chr(10));
      exit when k = 0;
      v_s := v_s || ' ';
      i := j + k - 1;
    else
      d := 1; k := j + 2;
      while d > 0 loop
        k := regexp_instr(v_src, '/\*|\*/', k);
        exit when k = 0;
        d := d + case when substr(v_src, k, 2) = '/*' then 1 else -1 end;
        k := k + 2;
      end loop;
      exit when k = 0;
      v_s := v_s || ' ';
      i := k;
    end if;
  end loop;

  if v_s ~* '\mvw_transacoes_contas\M' then
    return format('%s lê fin.vw_transacoes_contas (todas as contas) e não está em v_aprovados de fin.trava_conta_hotmart_violacao (md5 do corpo: %s)',
                  v_obj, md5(v_src));
  end if;
  v_tot := (select count(*) from regexp_matches(v_s, '\mhotmart_transacoes\M(?!\s*[.%])', 'gi'));
  v_ok  := (select count(*) from regexp_matches(v_s,
             '\mhotmart_transacoes\s+where\s+\(*((fin\.)?hotmart_transacoes\.)?conta\s*=\s*(''[a-z][a-z0-9_]*''|[pv]_[a-z0-9_]+\M)', 'gi'));
  if v_tot > v_ok then
    return format('%s: %s de %s citação(ões) de fin.hotmart_transacoes fora da forma "(select * from fin.hotmart_transacoes where conta = ''<conta>'')" (md5 do corpo: %s)',
                  v_obj, v_tot - v_ok, v_tot, md5(v_src));
  end if;
  return null;
end
$function$;
revoke all on function fin.trava_conta_hotmart_violacao(oid, oid) from public, anon, authenticated, service_role;

create or replace function fin.trava_conta_hotmart()
 returns event_trigger
 language plpgsql
 security definer   -- roda como o dono (postgres): chama fin.* mesmo quando a DDL vem de outro papel
 set search_path to ''
as $function$
declare
  c      record;
  v_erro text;
begin
  for c in select distinct d.classid, d.objid from pg_catalog.pg_event_trigger_ddl_commands() d
            where d.classid in ('pg_catalog.pg_proc'::regclass, 'pg_catalog.pg_class'::regclass) loop
    v_erro := null;
    begin
      v_erro := fin.trava_conta_hotmart_violacao(c.classid, c.objid);
    exception when others then
      raise warning 'fin.trava_conta_hotmart: conferência falhou (%) — DDL segue sem conferir', sqlerrm;
    end;
    if v_erro is not null then
      raise exception 'trava conta Hotmart: %', v_erro
        using hint = 'Leitor da Academy: fin.vw_transacoes ou (select * from fin.hotmart_transacoes where conta = ''academy'') x. '
                  || 'Mudou objeto aprovado: atualize v_aprovados em fin.trava_conta_hotmart_violacao na mesma migration. '
                  || 'Emergência: alter event trigger trava_conta_hotmart disable.';
    end if;
  end loop;
end
$function$;
revoke all on function fin.trava_conta_hotmart() from public, anon, authenticated, service_role;

drop event trigger if exists trava_conta_hotmart;
create event trigger trava_conta_hotmart on ddl_command_end
  when tag in ('CREATE FUNCTION', 'ALTER FUNCTION', 'CREATE PROCEDURE', 'ALTER PROCEDURE',
               'CREATE VIEW', 'ALTER VIEW', 'CREATE MATERIALIZED VIEW')
  execute function fin.trava_conta_hotmart();

--    Apply: a mesma regra sobre TODO o banco (inclusive o que esta migration criou/alterou acima).
do $trava$
declare
  v_fora text;
begin
  select string_agg(x.erro, E'\n' order by x.erro) into v_fora
    from (select fin.trava_conta_hotmart_violacao('pg_catalog.pg_proc'::regclass, p.oid) erro
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_toast'
             and p.prokind in ('f', 'p')
          union all
          select fin.trava_conta_hotmart_violacao('pg_catalog.pg_class'::regclass, c.oid)
            from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')) x
   where x.erro is not null;
  if v_fora is not null then
    raise exception E'z89 trava:\n%', v_fora;
  end if;
end
$trava$;

-- ==================================================================================================================
-- DEPOIS (ensaio da migration inteira em transação desfeita, 29/09/2026, mesmas condições do ANTES)
--
--   Resultado idêntico (except nos 2 sentidos, janela 2025-10-01..2026-09-29, hoje só existe 'academy'):
--     fn_fin_caixa_hotmart         antes−depois = 0, depois−antes = 0 (363 linhas)
--     fn_fin_caixa_hotmart_totais  antes−depois = 0, depois−antes = 0
--     fin.vw_transacoes (transacao, liquido, grupo, familia) 0 / 0 — dependentes vw_acao_card e
--       vw_turma_origem_card continuam lendo (385 / 385 linhas)
--     2ª rodada (29/09 noite, z89 com 6b/6c): 27 saídas com hash idêntico antes × depois × depois-com-
--       venda-falsa-do-escritório; ver 20260930z89.explain.md (conta_ausente 8 → 8 com escritorio inativa).
--
--   DEPOIS fn_fin_caixa_hotmart
--     Function Scan on fn_fin_caixa_hotmart (actual time=18.437..18.460 rows=363 loops=1)
--       Buffers: shared hit=9617
--     Execution Time: 18.503 ms                       (antes 19.008 ms, mesmos 9617 buffers)
--     corpo: HashAggregate (Batches: 1, Memory 369kB)
--       -> Index Scan using hotmart_transacoes_aprovado_pago_idx rows=6653
--            Filter: (conta = 'academy'::text)        (junção com hotmart_contas removida pelo planner)
--     Execution Time: 14.493 ms                       (antes 21.180 ms)
--     SEM o analyze acima: GroupAggregate + Sort external merge Disk: 6552kB, 29.812 ms.
--   DEPOIS fn_fin_funis
--     Function Scan on fn_fin_funis (actual time=1955.938..1955.946 rows=86 loops=1)
--       Buffers: shared hit=53830, temp read=404 written=404
--     Execution Time: 1955.977 ms                     (antes 2235 ms; mesma ordem, lentidão pré-existente)
--
--   Outras provas do ensaio: hotmart_sync_fila_uk recriado com conta; fin.hotmart_credenciais_conta devolve
--   basic não-nulo para 'academy', NULL para conta inexistente e para 'escritorio' enquanto ativa = false; acl = postgres + service_role;
--   anon/authenticated sem select em hotmart_contas e sem execute na credencial; RLS ligado em hotmart_contas e
--   hotmart_transacoes_colisao; enfileirar(60) = 108 linhas, todas conta='academy'. Nada persistiu (conferido).
--
-- ==================================================================================================================
-- CONTRATO PARA A EDGE hotmart-sync (outro executor — esta migration não mexe nela)
--   Credencial:  select basic, chave_sync from fin.hotmart_credenciais_conta(<conta>)
--                basic NULL = conta inativa/inexistente → pular a conta. Cache de token POR conta (hoje é global).
--                A chave x-sync-chave continua a mesma (fin_hotmart_sync_chave), igual para as 2 contas.
--   Contas:      select conta from fin.hotmart_contas where ativa   (edge roda como postgres; RLS não a afeta)
--   Fila:        cada linha de fin.hotmart_sync_fila tem conta; o UPDATE ... RETURNING do job deve devolver conta
--                e processarJanela usa o token dessa conta. Insert na fila SEMPRE com conta explícita.
--                Unique: (conta, produto_id, inicio, fim, tipo) where status <> 'feito' → on conflict do nothing.
--   Transações:  insert em fin.hotmart_transacoes com conta = conta do job; upsert on conflict (transacao)
--                do update ... WHERE fin.hotmart_transacoes.conta = excluded.conta.
--                Se o código já existe com OUTRA conta (update não pegou linha): insert into
--                fin.hotmart_transacoes_colisao (transacao, conta, bruto) values (..) on conflict (transacao, conta)
--                do update set bruto = excluded.bruto, visto_em = now(). Nunca sobrescrever a outra conta.
--                O update de comprador (/sales/users) também filtra "and conta = <conta>".
--   Catálogo:    fin.hotmart_catalogo e fin.produtos (insert do A_CLASSIFICAR) com conta explícita; o join de
--                ofertas usa o token da conta do produto (fin.produtos.conta).
--   Rotina '*':  os crons 'fin-hotmart-rotina-todos' e 'fin-hotmart-rotina-todos-45dias' e o ramo body.rotina da
--                edge inserem SEM conta → hoje caem em 'academy'. Reagendar NO MESMO deploy da edge (antes disso a
--                edge velha processaria a linha 'escritorio' com a credencial da Academy):
--                  insert into fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo, status, tentativas)
--                  select c.conta, '*', <ini>, <fim>, 'rotina', 'pendente', 0 from fin.hotmart_contas c
--                   where c.ativa and not exists (select 1 from fin.hotmart_sync_fila f where f.conta = c.conta and
--                         f.produto_id = '*' and f.tipo = 'rotina' and f.status in ('pendente','processando') ...)
--                fin.hotmart_sync_enfileirar já grava p.conta e só enfileira produto de conta ativa (bloco 6).
