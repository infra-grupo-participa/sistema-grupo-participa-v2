-- 20260928z71 — Financeiro: (A) F8 "dinheiro já contratado" da Análise lê o bloco 2 do Contas a Receber;
--               (B) F5 tipo de relatório 'receber' no protocolo de PDF (fin.relatorios_emitidos).
--
-- NÃO APLICADA — coordenador aplica. Depende de: 20260928p (fn_fin_contratado), z50 (relatórios), z65 (teto) e z66
-- (fin.cobrancas_previstas com a coluna detalhe). A migration inteira é UMA transação: qualquer guarda ou conferência
-- que falhe desfaz tudo (nada fica pela metade).
--
-- (A) F8 — Conflito 6 do catálogo: fn_fin_contratado (Análise) e fin.cobrancas_previstas (Receber) eram o mesmo
--     conceito com duas regras. Regra ANTIGA (20260928p), trocada aqui:
--       parcelado  = só HOTMART_INSTALLMENTS, faltam (parcelas − maior paga), uma por mês a partir da última paga,
--                    parcela vencida entra no mês corrente; em risco = parcela aberta depois da última paga ou 45+ dias.
--       assinatura = mensalidade paga nos últimos 35 dias e sem atraso em 60 dias → a última mensalidade nos 3 meses
--                    SEGUINTES ao corrente (o mês corrente ficava sem assinatura).
--     Regra NOVA = a do Receber, bloco 2 (fin.cobrancas_previstas, corte = agora, horizonte = fim do 12º mês):
--       universo   = contrato e-mail|oferta com cobrança paga nos últimos 120 dias (assinatura, MULTIPLE_PAYMENTS e
--                    HOTMART_INSTALLMENTS*), sem estorno na série;
--       fim        = parcelas do plano (parcelado) ou teto de fin.assinatura_teto (z65: 3507214 e Aurum-A = 12);
--                    assinatura sem teto vai até o horizonte (12 meses);
--       atraso     = premissas vigentes: tolerancia_atraso_dias (5) e atraso_max_projetado_dias (35). Contrato cuja
--                    próxima cobrança venceu há mais de 35 dias sai inteiro; cobrança vencida há mais de 5 dias fica
--                    'em_atraso_fora' e NÃO soma;
--       mês        = mês da data efetiva da cobrança (vencimento, ou amanhã se ainda dentro da tolerância);
--       valor      = valor da OFERTA (bruto) da última cobrança paga do contrato — a mesma cobrança que dá o valor
--                    líquido do Receber (detalhe → último elemento). A Análise compara com o faturamento BRUTO, por
--                    isso a base do valor não muda;
--       em_risco   = valor das cobranças 'a_receber' de contrato que tem cobrança 'em_atraso_fora' (6–35 dias);
--       pessoas    = e-mails distintos (igual a antes).
--     'combinado' (acordos do board) fica CARACTERE A CARACTERE como estava, inclusive o "não conta quem tem parcelado
--     Hotmart em curso" pela regra antiga do plano (Conflito 8 / BLOQUEIO 2 são outra decisão).
--     MESMO RETURNS, mesma assinatura, mesma ACL. Replace com guarda de corpo vivo.
--
-- (B) F5 — 'receber' entra na lista de tipos. A lista passa a existir UMA vez: fin.relatorio_tipos() (imutável), lida
--     pelo CHECK relatorios_emitidos_tipo_check E por fn_fin_relatorio_emitir. O CHECK vivo é conferido com
--     pg_get_constraintdef (filtrado por conname) antes de ser trocado: se tiver qualquer valor além dos 6 da z50, aborta
--     (reescrever de memória apagaria o valor). fn_fin_relatorio_emitir: replace com guarda de corpo vivo (z50); a única
--     linha que muda é a do tipo. Nível: 'receber' aceita os 3 níveis (só 'identidade' é restrito, inalterado).
--     ATENÇÃO para quem mexer depois: CHECK com função não revalida linhas antigas quando a função muda. Só ACRESCENTAR
--     tipo em fin.relatorio_tipos(); remover exige conferir as linhas existentes primeiro.
--
-- 5 perguntas (A):
--   escala: o custo passa a ser o de fin.cobrancas_previstas com horizonte de 12 meses (todas as famílias; o filtro de
--           família vem depois, pela última cobrança paga) + 1 busca por PK em hotmart_transacoes por contrato + a
--           fonte 'combinado' (inalterada). Cresce com contratos ativos em 120 dias, não com o histórico.
--   índice: universo pelo índice parcial de aprovado_em (z61); série do contrato pelo índice (e-mail, oferta,
--           recorrência) (z61); última paga pela PK hotmart_transacoes(transacao). Provas P1–P3 abaixo.
--   frequência: 1 chamada por família ao abrir a aba Análise (igual a antes).
--   repetição: a regra do contrato fica SÓ em fin.cobrancas_previstas; a Análise não recalcula nada.
--   reversão: ver abaixo.
--   Meta de tempo: não piorar mais que 10%. A conferência 4 mede (3 rodadas, 8 famílias, antes × depois, mesma
--   transação) e ABORTA se passar de 10%. Para aplicar mesmo assim (decisão do Marcio, com o número na mão):
--   colocar  set local z71.aceitar_lentidao = 'sim';  como primeira linha da migration.
--
-- REVERSÃO (uma transação; nada se apaga):
--   begin;
--   -- (A) recolocar o corpo da 20260928p (linhas 18–79, create or replace; a ACL é preservada pelo replace).
--   -- (B) recolocar o corpo da z50 em fn_fin_relatorio_emitir (linhas 102–152, create or replace) — a partir daí
--   --     nenhuma emissão nova de 'receber'. O CHECK com fin.relatorio_tipos() pode FICAR (aceita a mais, não a menos).
--   --     Voltar o CHECK para a lista literal da z50 só se não houver linha 'receber':
--   --       select count(*) from fin.relatorios_emitidos where tipo = 'receber';   -- tem que dar 0
--   --       alter table fin.relatorios_emitidos drop constraint relatorios_emitidos_tipo_check,
--   --         add constraint relatorios_emitidos_tipo_check
--   --         check (tipo in ('board','pessoas','conciliacao','identidade','acelera','prorata'));
--   commit;
--
-- PROVAS (rodar e colar; todas SELECT, seguras em produção; <UUID_FINANCEIRO> = perfil de quem vê o Financeiro):
--   P1) tempo da RPC — rodar ANTES de aplicar e DEPOIS, 2ª execução de cada:
--       begin;
--       select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
--       explain (analyze, buffers) select * from public.fn_fin_contratado('HM');
--       explain (analyze, buffers) select * from public.fn_fin_contratado('AURUM');
--       explain (analyze, buffers) select * from public.fn_fin_contratado('DIAMANTE');
--       rollback;
--   P2) o que a RPC nova chama por dentro (plano da parte cara):
--       explain (analyze, buffers)
--       select c.ref, c.tipo, c.situacao, c.data_efetiva, c.detalhe -> -1 ->> 'transacao'
--         from fin.cobrancas_previstas(now(), (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
--                                              + interval '12 months' - interval '1 day')::date) c
--        where c.situacao in ('a_receber','em_atraso_fora');
--   P3) a busca da última paga (tem que ser Index Scan em hotmart_transacoes_pkey):
--       explain (analyze, buffers)
--       select t.familia, t.email, t.valor_oferta from fin.vw_transacoes t
--        where t.transacao = (select h.transacao from fin.hotmart_transacoes h
--                              where h.oferta_modo = 'SUBSCRIPTION' order by h.aprovado_em desc nulls last limit 1);
--   P4) ACL e CHECK depois:
--       select p.oid::regprocedure, a::text from pg_proc p, unnest(p.proacl) a
--        where p.oid in ('public.fn_fin_contratado(text)'::regprocedure, 'fin.relatorio_tipos()'::regprocedure,
--                        'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)'::regprocedure) order by 1, 2;
--       select conname, pg_get_constraintdef(oid) from pg_constraint
--        where conrelid = 'fin.relatorios_emitidos'::regclass and conname = 'relatorios_emitidos_tipo_check';
--       select fin.relatorio_tipos();


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_con  oid := to_regprocedure('public.fn_fin_contratado(text)');
  v_emi  oid := to_regprocedure('public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)');
  v_cob  oid := to_regprocedure('fin.cobrancas_previstas(timestamptz,date)');
  v_src  text;
  v_res  text;
  v_def  text;
  v_n    int;
  e_con  text := $esperado$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with plano as (
    select t.email, t.oferta_codigo,
           max(t.parcelas) parcelas,
           max(t.recorrencia) filter (where t.grupo = 'pago') paga,
           max(t.dia_aprovado) filter (where t.grupo = 'pago') ult,
           (array_agg(t.valor_oferta order by t.recorrencia desc) filter (where t.grupo = 'pago'))[1] valor,
           max(t.recorrencia) filter (where t.grupo in ('atrasado','em_aberto')) rec_aberta
      from fin.vw_transacoes t
     where t.familia = p_familia and t.oferta_modo like 'HOTMART_INSTALLMENTS%' and t.recorrencia is not null
     group by t.email, t.oferta_codigo
  ), parc as (
    -- parcela vencida e não paga não some: a fila começa no mês corrente (o dinheiro ainda é devido).
    select (greatest(date_trunc('month', p.ult), date_trunc('month', v_hoje::timestamp) - interval '1 month')
            + make_interval(months => g))::date mes, p.valor, p.email,
           -- risco = parcela em aberto/atrasada DEPOIS da última paga, ou plano sem pagamento há 45+ dias
           (coalesce(p.rec_aberta > p.paga, false) or p.ult < v_hoje - 45) risco
      from plano p
      cross join lateral generate_series(1, greatest(p.parcelas - p.paga, 0)) g
     where p.paga is not null and p.parcelas > p.paga and not exists (
       select 1 from fin.vw_transacoes x where x.email = p.email and x.oferta_codigo = p.oferta_codigo and x.grupo = 'estornado')
  ), ass as (
    select t.email, (array_agg(t.valor_oferta order by t.aprovado_em desc))[1] valor, max(t.dia_aprovado) ult
      from fin.vw_transacoes t
     where t.familia = p_familia and t.oferta_modo = 'SUBSCRIPTION' and t.grupo = 'pago'
     group by t.email
    having max(t.dia_aprovado) >= v_hoje - 35
  ), ass_ok as (
    select a.* from ass a
     where not exists (select 1 from fin.vw_transacoes x where x.email = a.email and x.familia = p_familia
                        and x.oferta_modo = 'SUBSCRIPTION' and x.grupo = 'atrasado' and x.dia_pedido >= v_hoje - 60)
  ), assm as (
    select (date_trunc('month', v_hoje) + make_interval(months => g))::date mes, a.valor, a.email
      from ass_ok a cross join generate_series(1, 3) g
  ), comb as (
    select date_trunc('month', b.vencimento)::date mes, b.saldo_a_pagar valor, lower(trim(b.email)) email
      from cs.vw_fin_board b
     where b.origem = p_familia and b.vencimento >= v_hoje and coalesce(b.saldo_a_pagar, 0) > 0.5
       and b.status_financeiro not in ('cancelado','reembolsado','quitado')
       and not exists (select 1 from plano p where p.email = lower(trim(b.email)) and p.parcelas > coalesce(p.paga, 0))
  ), tudo as (
    select x.mes, 'parcelado'::text fonte, x.valor, x.email, x.risco from parc x
    union all select y.mes, 'assinatura', y.valor, y.email, false from assm y
    union all select z.mes, 'combinado', z.valor, z.email, false from comb z
  )
  select t.mes, t.fonte, round(sum(t.valor), 2), count(distinct t.email)::int,
         round(coalesce(sum(t.valor) filter (where t.risco), 0), 2)
    from tudo t
   where t.mes >= date_trunc('month', v_hoje)::date and t.mes < (date_trunc('month', v_hoje) + interval '12 months')::date
   group by t.mes, t.fonte
   order by t.mes, t.fonte;
end
$esperado$;
  e_con_res text := 'TABLE(mes date, fonte text, valor numeric, pessoas integer, em_risco numeric)';
  e_emi  text := $esperado$
#variable_conflict use_column
declare
  v_uid     uuid  := auth.uid();
  v_recorte jsonb := coalesce(p_recorte, '{}'::jsonb);
  v_totais  jsonb := coalesce(p_totais,  '{}'::jsonb);
  v_nome    text;
  v_agora   timestamptz := now();
  v_proto   text;
begin
  if v_uid is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_tipo is null or p_tipo not in ('board','pessoas','conciliacao','identidade','acelera','prorata') then
    raise exception 'Tipo de relatório inválido.' using errcode = '22023';
  end if;
  if p_nivel is null or p_nivel not in ('completo','sem_dado_pessoal','so_numeros') then
    raise exception 'Nível de dado pessoal inválido.' using errcode = '22023';
  end if;
  if p_tipo = 'identidade' and p_nivel <> 'completo' then
    raise exception 'O relatório de identidade só existe no nível completo.' using errcode = '22023';
  end if;
  if not fin.relatorio_recorte_valido(v_recorte) then
    raise exception 'Recorte inválido: precisa ser objeto até 4 KB e sem texto de busca ou dado pessoal.'
      using errcode = '22023';
  end if;
  if p_linhas is null or p_linhas < 0 then
    raise exception 'Quantidade de linhas inválida.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_totais) <> 'object' or octet_length(v_totais::text) > 8192 then
    raise exception 'Totais inválidos: precisa ser objeto até 8 KB.' using errcode = '22023';
  end if;

  select coalesce(nullif(btrim(p.nome), ''), p.email) into v_nome
    from public.perfis p where p.id = v_uid;
  if v_nome is null then
    raise exception 'Perfil sem nome.' using errcode = '42501';
  end if;

  v_proto := 'GP-REL-' || to_char(v_agora at time zone 'America/Sao_Paulo', 'YYYY') || '-'
             || lpad(nextval('fin.relatorios_emitidos_protocolo_seq')::text, 6, '0');

  return query
  insert into fin.relatorios_emitidos (protocolo, tipo, nivel, recorte, linhas, totais, gerado_por, gerado_por_nome, emitido_em)
  values (v_proto, p_tipo, p_nivel, v_recorte, p_linhas, v_totais, v_uid, v_nome, v_agora)
  returning protocolo, emitido_em, gerado_por_nome;
end
$esperado$;
  e_emi_res text := 'TABLE(protocolo text, emitido_em timestamp with time zone, gerado_por_nome text)';
  e_cob_res text := 'TABLE(grupo text, tipo text, ref text, rotulo text, produto text, n integer, parcelas integer, '
                    'vencimento date, vencimento_b date, situacao text, data_efetiva date, valor numeric, k integer, '
                    'entra_em date, entra_rapido numeric, libera_em date, retido numeric, detalhe jsonb)';
  e_check text := $$CHECK ((tipo = ANY (ARRAY['board'::text, 'pessoas'::text, 'conciliacao'::text, 'identidade'::text, 'acelera'::text, 'prorata'::text])))$$;
begin
  if to_regprocedure('fin.relatorio_tipos()') is not null then
    raise exception 'z71: já aplicada (fin.relatorio_tipos existe)';
  end if;
  if v_con is null or v_emi is null or v_cob is null or to_regclass('fin.relatorios_emitidos') is null
     or to_regclass('fin.assinatura_teto') is null or to_regprocedure('fin.premissa(text,date,text)') is null then
    raise exception 'z71: faltam dependências (20260928p, z50, z65 ou z66 não aplicadas)';
  end if;
  if (select count(*) from pg_proc where proname = 'fn_fin_contratado' and pronamespace = 'public'::regnamespace) <> 1
     or (select count(*) from pg_proc where proname = 'fn_fin_relatorio_emitir' and pronamespace = 'public'::regnamespace) <> 1
     or (select count(*) from pg_proc where proname = 'cobrancas_previstas' and pronamespace = 'fin'::regnamespace) <> 1 then
    raise exception 'z71: sobrecarga viva de fn_fin_contratado, fn_fin_relatorio_emitir ou fin.cobrancas_previstas';
  end if;

  -- (A) corpo vivo de fn_fin_contratado = 20260928p (sem espaço, sem comentário, sem o texto das mensagens de erro)
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_con;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_con, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_con_res, '\s+', '', 'g') then
    raise exception 'z71: corpo vivo de fn_fin_contratado diverge da 20260928p. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_con and l.lanname = 'plpgsql' and p.provolatile = 's' and p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z71: atributos vivos de fn_fin_contratado diferentes da 20260928p (plpgsql/stable/definer/search_path vazio)';
  end if;
  -- (A) o bloco 2 tem que devolver as colunas que a leitura nova usa (ref, tipo, situacao, data_efetiva, detalhe)
  if regexp_replace(pg_get_function_result(v_cob), '\s+', '', 'g') <> regexp_replace(e_cob_res, '\s+', '', 'g') then
    raise exception 'z71: RETURNS vivo de fin.cobrancas_previstas diferente da z66: %', pg_get_function_result(v_cob);
  end if;

  -- (B) corpo vivo de fn_fin_relatorio_emitir = z50
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_emi;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_emi, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_emi_res, '\s+', '', 'g') then
    raise exception 'z71: corpo vivo de fn_fin_relatorio_emitir diverge da z50. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_emi and l.lanname = 'plpgsql' and p.provolatile = 'v' and p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z71: atributos vivos de fn_fin_relatorio_emitir diferentes da z50 (plpgsql/volatile/definer/search_path vazio)';
  end if;
  -- (B) CHECK vivo, pelo nome: exatamente os 6 valores da z50. Qualquer valor a mais = alguém acrescentou fora do
  --     repo e reescrever apagaria esse valor.
  select count(*), min(pg_get_constraintdef(c.oid)) into v_n, v_def
    from pg_constraint c
   where c.conrelid = 'fin.relatorios_emitidos'::regclass and c.conname = 'relatorios_emitidos_tipo_check' and c.contype = 'c';
  if v_n <> 1 or regexp_replace(v_def, '\s+', '', 'g') <> regexp_replace(e_check, '\s+', '', 'g') then
    raise exception 'z71: CHECK vivo relatorios_emitidos_tipo_check diferente do da z50: % — não reescrever de memória', coalesce(v_def, '(ausente)');
  end if;
  select string_agg(distinct r.tipo, ', ') into v_def from fin.relatorios_emitidos r
   where r.tipo not in ('board','pessoas','conciliacao','identidade','acelera','prorata');
  if v_def is not null then
    raise exception 'z71: fin.relatorios_emitidos tem tipo fora da lista da z50: %', v_def;
  end if;
end $guarda$;


-- ─── 1. Foto ANTES (corpo da 20260928p, como admin) e tempo ─────────────────────────────────────────────────────────
do $foto$
declare
  v_adm  uuid;
  v_fam  text;
  v_t0   timestamptz;
  v_ms   numeric;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_fams text[] := array['HT','EVENTOS','HM','AURUM','ACELERA','PROGRAMA_DIAMANTE','DIAMANTE','OUTROS'];
begin
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z71: nenhum perfil admin ativo para a foto da RPC'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  create temp table z71_antes (familia text, mes date, fonte text, valor numeric, pessoas int, em_risco numeric) on commit drop;
  create temp table z71_tempo (fase text, rodada int, ms numeric) on commit drop;
  foreach v_fam in array v_fams loop
    insert into z71_antes select v_fam, x.* from public.fn_fin_contratado(v_fam) x;
  end loop;
  for r in 1..3 loop
    v_t0 := clock_timestamp();
    foreach v_fam in array v_fams loop perform count(*) from public.fn_fin_contratado(v_fam); end loop;
    insert into z71_tempo values ('antes', r, extract(epoch from clock_timestamp() - v_t0) * 1000);
  end loop;

  -- réplica POR CONTRATO da regra antiga (parcelado e assinatura), só para a conferência explicar a diferença.
  -- A conferência 3a exige que a réplica somada = a foto da função antiga (senão a explicação não vale).
  create temp table z71_antes_det on commit drop as
  with plano as (
    select t.familia, t.email, t.oferta_codigo,
           max(t.parcelas) parcelas,
           max(t.recorrencia) filter (where t.grupo = 'pago') paga,
           max(t.dia_aprovado) filter (where t.grupo = 'pago') ult,
           (array_agg(t.valor_oferta order by t.recorrencia desc) filter (where t.grupo = 'pago'))[1] valor,
           max(t.recorrencia) filter (where t.grupo in ('atrasado','em_aberto')) rec_aberta
      from fin.vw_transacoes t
     where t.familia = any (v_fams) and t.oferta_modo like 'HOTMART_INSTALLMENTS%' and t.recorrencia is not null
     group by t.familia, t.email, t.oferta_codigo
  ), parc as (
    select p.familia, p.email || '|' || p.oferta_codigo chave,
           (greatest(date_trunc('month', p.ult), date_trunc('month', v_hoje::timestamp) - interval '1 month')
            + make_interval(months => g))::date mes, p.valor, p.email,
           (coalesce(p.rec_aberta > p.paga, false) or p.ult < v_hoje - 45) risco
      from plano p
      cross join lateral generate_series(1, greatest(p.parcelas - p.paga, 0)) g
     where p.paga is not null and p.parcelas > p.paga and not exists (
       select 1 from fin.vw_transacoes x where x.email = p.email and x.oferta_codigo = p.oferta_codigo and x.grupo = 'estornado')
  ), ass as (
    select t.familia, t.email, (array_agg(t.valor_oferta order by t.aprovado_em desc))[1] valor
      from fin.vw_transacoes t
     where t.familia = any (v_fams) and t.oferta_modo = 'SUBSCRIPTION' and t.grupo = 'pago'
     group by t.familia, t.email
    having max(t.dia_aprovado) >= v_hoje - 35
  ), ass_ok as (
    select a.* from ass a
     where not exists (select 1 from fin.vw_transacoes x where x.email = a.email and x.familia = a.familia
                        and x.oferta_modo = 'SUBSCRIPTION' and x.grupo = 'atrasado' and x.dia_pedido >= v_hoje - 60)
  )
  select x.familia, 'parcelado'::text fonte, x.chave, x.mes, x.valor, x.email, x.risco from parc x
  union all
  select a.familia, 'assinatura', a.email, (date_trunc('month', v_hoje::timestamp) + make_interval(months => g))::date,
         a.valor, a.email, false
    from ass_ok a cross join generate_series(1, 3) g;
  delete from z71_antes_det d
   where d.mes < date_trunc('month', v_hoje::timestamp)::date
      or d.mes >= (date_trunc('month', v_hoje::timestamp) + interval '12 months')::date;

  perform set_config('request.jwt.claims', '', true);
end $foto$;


-- ─── 2. (A) fn_fin_contratado lê fin.cobrancas_previstas ────────────────────────────────────────────────────────────
create or replace function public.fn_fin_contratado(p_familia text default 'HM')
returns table (mes date, fonte text, valor numeric, pessoas int, em_risco numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini  date;
  v_fim  date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  v_ini := date_trunc('month', v_hoje::timestamp)::date;
  v_fim := (date_trunc('month', v_hoje::timestamp) + interval '12 months' - interval '1 day')::date;
  return query
  with cp as materialized (
    -- z71 (F8): parcelado e assinatura = Contas a Receber, bloco 2 (fin.cobrancas_previstas): universo de 120 dias,
    -- fim do plano (parcelas ou teto da z65), tolerância e atraso máximo das premissas vigentes. Só 'a_receber' soma;
    -- 'em_atraso_fora' marca o contrato inteiro como em risco.
    select c.ref, c.tipo, c.situacao, c.data_efetiva, c.detalhe -> -1 ->> 'transacao' tx_ult
      from fin.cobrancas_previstas(now(), v_fim) c
     where c.situacao in ('a_receber','em_atraso_fora')
  ), ct as materialized (
    -- 1 linha por contrato. A última paga (último elemento do detalhe = a que dá o valor no Receber) dá família,
    -- e-mail e o valor da OFERTA (bruto: a Análise compara com o faturamento bruto). Busca pela PK, 1 por contrato.
    select u.ref, t.email, t.valor_oferta, u.risco
      from (select cp.ref, min(cp.tx_ult) tx_ult, bool_or(cp.situacao = 'em_atraso_fora') risco
              from cp group by cp.ref) u
      cross join lateral (select v.familia, v.email, v.valor_oferta from fin.vw_transacoes v
                           where v.transacao = u.tx_ult limit 1) t
     where t.familia = p_familia
  ), rec as (
    select date_trunc('month', cp.data_efetiva::timestamp)::date mes, cp.tipo fonte, ct.valor_oferta valor, ct.email, ct.risco
      from cp join ct on ct.ref = cp.ref
     where cp.situacao = 'a_receber'
  ), plano as (
    -- só para a fonte 'combinado' (inalterada desde a 20260928p): quem tem parcelado Hotmart em curso não entra
    select t.email, t.oferta_codigo,
           max(t.parcelas) parcelas,
           max(t.recorrencia) filter (where t.grupo = 'pago') paga,
           max(t.dia_aprovado) filter (where t.grupo = 'pago') ult,
           (array_agg(t.valor_oferta order by t.recorrencia desc) filter (where t.grupo = 'pago'))[1] valor,
           max(t.recorrencia) filter (where t.grupo in ('atrasado','em_aberto')) rec_aberta
      from fin.vw_transacoes t
     where t.familia = p_familia and t.oferta_modo like 'HOTMART_INSTALLMENTS%' and t.recorrencia is not null
     group by t.email, t.oferta_codigo
  ), comb as (
    select date_trunc('month', b.vencimento)::date mes, b.saldo_a_pagar valor, lower(trim(b.email)) email
      from cs.vw_fin_board b
     where b.origem = p_familia and b.vencimento >= v_hoje and coalesce(b.saldo_a_pagar, 0) > 0.5
       and b.status_financeiro not in ('cancelado','reembolsado','quitado')
       and not exists (select 1 from plano p where p.email = lower(trim(b.email)) and p.parcelas > coalesce(p.paga, 0))
  ), tudo as (
    select x.mes, x.fonte, x.valor, x.email, x.risco from rec x
    union all select z.mes, 'combinado', z.valor, z.email, false from comb z
  )
  select t.mes, t.fonte, round(sum(t.valor), 2), count(distinct t.email)::int,
         round(coalesce(sum(t.valor) filter (where t.risco), 0), 2)
    from tudo t
   where t.mes >= v_ini and t.mes < (v_ini + interval '12 months')::date
   group by t.mes, t.fonte
   order by t.mes, t.fonte;
end $$;
comment on function public.fn_fin_contratado(text) is
  'Análise do Faturamento (20260928p; z71): dinheiro já vendido que ainda vai entrar, por mês (12) e fonte. parcelado e '
  'assinatura = fin.cobrancas_previstas (Receber, bloco 2: 120 dias, teto z65, tolerância/atraso máximo das premissas), '
  'valor = oferta (bruto) da última paga; em_risco = contrato com cobrança em_atraso_fora. combinado = board (inalterado).';
revoke all on function public.fn_fin_contratado(text) from public, anon;
grant execute on function public.fn_fin_contratado(text) to authenticated;


-- ─── 3. (B) Tipo 'receber': a lista num lugar só ────────────────────────────────────────────────────────────────────
-- ÚNICA lista de tipos de relatório (CHECK da tabela + fn_fin_relatorio_emitir). Só ACRESCENTAR: o CHECK não revalida
-- linhas antigas quando esta função muda.
create function fin.relatorio_tipos()
returns text[] language sql immutable set search_path = ''
as $$ select array['board','pessoas','conciliacao','identidade','acelera','prorata','receber']::text[] $$;
comment on function fin.relatorio_tipos() is
  'Tipos de relatório PDF aceitos (z50 + receber na z71). Lida pelo CHECK relatorios_emitidos_tipo_check e por '
  'fn_fin_relatorio_emitir. Só acrescentar: remover exige conferir as linhas de fin.relatorios_emitidos antes.';
revoke all on function fin.relatorio_tipos() from public, anon, authenticated;

-- um só ALTER: não há instante sem CHECK. Valida as linhas existentes (dezenas) sob o lock da tabela.
alter table fin.relatorios_emitidos
  drop constraint relatorios_emitidos_tipo_check,
  add constraint relatorios_emitidos_tipo_check check (tipo = any (fin.relatorio_tipos()));

create or replace function public.fn_fin_relatorio_emitir(
  p_tipo text, p_nivel text, p_recorte jsonb, p_linhas int, p_totais jsonb)
returns table (protocolo text, emitido_em timestamptz, gerado_por_nome text)
language plpgsql volatile security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid     uuid  := auth.uid();
  v_recorte jsonb := coalesce(p_recorte, '{}'::jsonb);
  v_totais  jsonb := coalesce(p_totais,  '{}'::jsonb);
  v_nome    text;
  v_agora   timestamptz := now();
  v_proto   text;
begin
  if v_uid is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_tipo is null or not (p_tipo = any (fin.relatorio_tipos())) then   -- z71: a lista mora em fin.relatorio_tipos()
    raise exception 'Tipo de relatório inválido.' using errcode = '22023';
  end if;
  if p_nivel is null or p_nivel not in ('completo','sem_dado_pessoal','so_numeros') then
    raise exception 'Nível de dado pessoal inválido.' using errcode = '22023';
  end if;
  if p_tipo = 'identidade' and p_nivel <> 'completo' then
    raise exception 'O relatório de identidade só existe no nível completo.' using errcode = '22023';
  end if;
  if not fin.relatorio_recorte_valido(v_recorte) then
    raise exception 'Recorte inválido: precisa ser objeto até 4 KB e sem texto de busca ou dado pessoal.'
      using errcode = '22023';
  end if;
  if p_linhas is null or p_linhas < 0 then
    raise exception 'Quantidade de linhas inválida.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_totais) <> 'object' or octet_length(v_totais::text) > 8192 then
    raise exception 'Totais inválidos: precisa ser objeto até 8 KB.' using errcode = '22023';
  end if;

  select coalesce(nullif(btrim(p.nome), ''), p.email) into v_nome
    from public.perfis p where p.id = v_uid;
  if v_nome is null then
    raise exception 'Perfil sem nome.' using errcode = '42501';
  end if;

  v_proto := 'GP-REL-' || to_char(v_agora at time zone 'America/Sao_Paulo', 'YYYY') || '-'
             || lpad(nextval('fin.relatorios_emitidos_protocolo_seq')::text, 6, '0');

  return query
  insert into fin.relatorios_emitidos (protocolo, tipo, nivel, recorte, linhas, totais, gerado_por, gerado_por_nome, emitido_em)
  values (v_proto, p_tipo, p_nivel, v_recorte, p_linhas, v_totais, v_uid, v_nome, v_agora)
  returning protocolo, emitido_em, gerado_por_nome;
end $$;
revoke all on function public.fn_fin_relatorio_emitir(text, text, jsonb, int, jsonb) from public, anon;
grant execute on function public.fn_fin_relatorio_emitir(text, text, jsonb, int, jsonb) to authenticated;


-- ─── 4. Conferência (falha → rollback de tudo) ──────────────────────────────────────────────────────────────────────
do $conf$
declare
  v_adm  uuid;
  v_fam  text;
  v_t0   timestamptz;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini  date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)::date;
  v_fim  date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                  + interval '12 months' - interval '1 day')::date;
  v_fams text[] := array['HT','EVENTOS','HM','AURUM','ACELERA','PROGRAMA_DIAMANTE','DIAMANTE','OUTROS'];
  v_a    numeric;
  v_d    numeric;
  v_txt  text;
  v_n    int;
  r      record;
begin
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  create temp table z71_depois (familia text, mes date, fonte text, valor numeric, pessoas int, em_risco numeric) on commit drop;
  foreach v_fam in array v_fams loop
    insert into z71_depois select v_fam, x.* from public.fn_fin_contratado(v_fam) x;
  end loop;
  for i in 1..3 loop
    v_t0 := clock_timestamp();
    foreach v_fam in array v_fams loop perform count(*) from public.fn_fin_contratado(v_fam); end loop;
    insert into z71_tempo values ('depois', i, extract(epoch from clock_timestamp() - v_t0) * 1000);
  end loop;
  perform set_config('request.jwt.claims', '', true);

  -- bloco 2 com o contrato resolvido, lido de forma independente da função (mesmo "agora": now() é o da transação)
  create temp table z71_cp on commit drop as
  select c.ref, c.tipo, c.situacao, c.n, c.vencimento, c.data_efetiva, t.familia, t.email, t.oferta_codigo,
         t.oferta_modo, t.produto_id, t.valor_oferta
    from fin.cobrancas_previstas(now(), v_fim) c
    join fin.vw_transacoes t on t.transacao = (c.detalhe -> (jsonb_array_length(c.detalhe) - 1) ->> 'transacao')
   where c.situacao in ('a_receber','em_atraso_fora');

  -- 3a) a réplica da regra antiga explica a foto ANTES (senão a explicação por contrato não vale)
  select count(*) into v_n from (
    select coalesce(a.familia, b.familia) f
      from (select familia, mes, fonte, valor, pessoas, em_risco from z71_antes where fonte <> 'combinado') a
      full join (select d.familia, d.mes, d.fonte, round(sum(d.valor), 2) valor, count(distinct d.email)::int pessoas,
                        round(coalesce(sum(d.valor) filter (where d.risco), 0), 2) em_risco
                   from z71_antes_det d group by 1, 2, 3) b
        on b.familia = a.familia and b.mes = a.mes and b.fonte = a.fonte
     where a.valor is distinct from b.valor or a.pessoas is distinct from b.pessoas
        or a.em_risco is distinct from b.em_risco) z;
  if v_n > 0 then
    raise exception 'z71: conferência 3a — a réplica da regra antiga não bate com a foto ANTES em % linha(s)', v_n;
  end if;

  -- 3b) 'combinado' idêntico, linha a linha, em todas as famílias
  select count(*) into v_n from (
    select 1 from (select * from z71_antes where fonte = 'combinado') a
      full join (select * from z71_depois where fonte = 'combinado') b
        on b.familia = a.familia and b.mes = a.mes
     where a.valor is distinct from b.valor or a.pessoas is distinct from b.pessoas
        or a.em_risco is distinct from b.em_risco) z;
  if v_n > 0 then
    raise exception 'z71: conferência 3b — fonte combinado mudou em % linha(s) (tinha que ficar como está)', v_n;
  end if;

  -- 3c) parcelado/assinatura DEPOIS = bloco 2 somado de forma independente (só a_receber; risco pelo contrato)
  select count(*) into v_n from (
    select 1
      from (select * from z71_depois where fonte <> 'combinado') a
      full join (
        select c.familia, date_trunc('month', c.data_efetiva::timestamp)::date mes, c.tipo fonte,
               round(sum(c.valor_oferta), 2) valor, count(distinct c.email)::int pessoas,
               round(coalesce(sum(c.valor_oferta) filter (where c.ref in (
                 select x.ref from z71_cp x where x.situacao = 'em_atraso_fora')), 0), 2) em_risco
          from z71_cp c
         where c.situacao = 'a_receber' and c.familia = any (v_fams)
           and c.data_efetiva >= v_ini and c.data_efetiva <= v_fim
         group by 1, 2, 3) b
        on b.familia = a.familia and b.mes = a.mes and b.fonte = a.fonte
     where a.valor is distinct from b.valor or a.pessoas is distinct from b.pessoas
        or a.em_risco is distinct from b.em_risco) z;
  if v_n > 0 then
    raise exception 'z71: conferência 3c — fn_fin_contratado nova não é o bloco 2 somado (% linha(s) diferentes)', v_n;
  end if;

  -- 3d) forma: fontes, janela de 12 meses, valores positivos, risco ≤ valor
  if exists (select 1 from z71_depois d
              where d.fonte not in ('parcelado','assinatura','combinado') or d.mes < v_ini or d.mes > v_fim
                 or d.valor <= 0 or d.em_risco < 0 or d.em_risco > d.valor or d.pessoas < 1) then
    raise exception 'z71: conferência 3d — linha fora da forma (fonte, janela de 12 meses, valor > 0, 0 ≤ risco ≤ valor)';
  end if;

  -- 3e) sanidade: família que tinha parcelado/assinatura não pode zerar (sinal de leitura quebrada)
  select string_agg(a.familia, ', ') into v_txt
    from (select familia, sum(valor) v from z71_antes where fonte <> 'combinado' group by 1) a
    left join (select familia, sum(valor) v from z71_depois where fonte <> 'combinado' group by 1) b on b.familia = a.familia
   where a.v > 0 and coalesce(b.v, 0) = 0;
  if v_txt is not null then
    raise exception 'z71: conferência 3e — parcelado/assinatura zerou em: % (antes tinha)', v_txt;
  end if;

  -- 3f) EXPLICAÇÃO (NOTICE, sem dado pessoal): por família × fonte × mês, e por contrato (só antes / só depois / ambos)
  for r in
    select coalesce(a.familia, b.familia) familia, coalesce(a.fonte, b.fonte) fonte,
           string_agg(to_char(coalesce(a.mes, b.mes), 'YYYY-MM') || ' ' || coalesce(a.valor, 0) || '→' || coalesce(b.valor, 0)
                      || case when coalesce(a.em_risco, 0) + coalesce(b.em_risco, 0) > 0
                              then ' (risco ' || coalesce(a.em_risco, 0) || '→' || coalesce(b.em_risco, 0) || ')' else '' end,
                      '; ' order by coalesce(a.mes, b.mes)) meses,
           sum(coalesce(a.valor, 0)) ta, sum(coalesce(b.valor, 0)) td
      from z71_antes a
      full join z71_depois b on b.familia = a.familia and b.fonte = a.fonte and b.mes = a.mes
     group by 1, 2
     order by 1, 2
  loop
    raise notice 'z71 % / %: antes % → depois % | %', r.familia, r.fonte, r.ta, r.td, r.meses;
  end loop;

  for r in
    with a as (
      select d.familia, d.fonte, d.chave, sum(d.valor) v
        from z71_antes_det d group by 1, 2, 3
    ), cps as (
      select c.familia, c.tipo fonte, case when c.tipo = 'parcelado' then c.email || '|' || c.oferta_codigo else c.email end chave,
             c.situacao, c.data_efetiva, c.valor_oferta, c.oferta_modo
        from z71_cp c where c.familia = any (v_fams)
    ), d as (
      select c.familia, c.fonte, c.chave,
             coalesce(sum(c.valor_oferta) filter (where c.situacao = 'a_receber' and c.data_efetiva between v_ini and v_fim), 0) v,
             coalesce(sum(c.valor_oferta) filter (where c.situacao = 'a_receber'
                        and c.data_efetiva >= v_ini + interval '1 month' and c.data_efetiva < v_ini + interval '4 months'), 0) v_jan,
             bool_or(c.situacao = 'em_atraso_fora') fora,
             bool_and(c.oferta_modo like 'HOTMART_INSTALLMENTS%') inst
        from cps c group by 1, 2, 3
    )
    select coalesce(a.familia, d.familia) familia, coalesce(a.fonte, d.fonte) fonte,
           count(*) filter (where a.chave is not null and d.v > 0) n_amb,
           coalesce(sum(a.v) filter (where a.chave is not null and d.v > 0), 0) amb_a,
           coalesce(sum(d.v) filter (where a.chave is not null and d.v > 0), 0) amb_d,
           coalesce(sum(d.v_jan) filter (where a.chave is not null and d.v > 0), 0) amb_d_jan,
           count(*) filter (where a.chave is not null and coalesce(d.v, 0) = 0) n_so_a,
           coalesce(sum(a.v) filter (where a.chave is not null and coalesce(d.v, 0) = 0), 0) so_a,
           count(*) filter (where a.chave is not null and coalesce(d.v, 0) = 0 and d.fora) n_so_a_fora,
           count(*) filter (where a.chave is not null and d.chave is null) n_so_a_fora_universo,
           count(*) filter (where a.chave is null and d.v > 0) n_so_d,
           coalesce(sum(d.v) filter (where a.chave is null and d.v > 0), 0) so_d,
           count(*) filter (where a.chave is null and d.v > 0 and d.fonte = 'parcelado' and not d.inst) n_so_d_multiple
      from a full join d on d.familia = a.familia and d.fonte = a.fonte and d.chave = a.chave
     group by 1, 2
     order by 1, 2
  loop
    raise notice 'z71 % / % por contrato: ambos % (antes % → depois %, dos quais % nos meses +1 a +3, a janela da assinatura antiga) · só antes % (R$ %; % em atraso 6–35 d fora da soma, % fora do universo: atraso > 35 d, sem pagamento em 120 d ou estorno) · só depois % (R$ %; % MULTIPLE_PAYMENTS, que a regra antiga não lia)',
      r.familia, r.fonte, r.n_amb, r.amb_a, r.amb_d, r.amb_d_jan, r.n_so_a, r.so_a, r.n_so_a_fora,
      r.n_so_a_fora_universo, r.n_so_d, r.so_d, r.n_so_d_multiple;
  end loop;

  for r in
    select c.familia, c.produto_id, t.max_cobrancas, count(distinct c.ref) n,
           count(distinct c.ref) filter (where mx.n_max = t.max_cobrancas) n_teto
      from z71_cp c
      join fin.assinatura_teto t on t.produto_id = c.produto_id and t.ativo
      join (select ref, max(n) n_max from z71_cp group by ref) mx on mx.ref = c.ref
     where c.tipo = 'assinatura'
     group by 1, 2, 3
  loop
    raise notice 'z71 teto z65: % produto % (teto %): % contratos no horizonte, % chegam ao teto dentro dos 12 meses',
      r.familia, r.produto_id, r.max_cobrancas, r.n, r.n_teto;
  end loop;

  -- 4) tempo: 3 rodadas × 8 famílias, melhor rodada de cada lado. Meta: +10% no máximo.
  select min(ms) filter (where fase = 'antes'), min(ms) filter (where fase = 'depois') into v_a, v_d from z71_tempo;
  raise notice 'z71 tempo (8 famílias, melhor de 3): antes % ms · depois % ms · %', round(v_a, 1), round(v_d, 1),
    case when v_a > 0 then to_char(round((v_d / v_a - 1) * 100, 1), 'FM999990.0') || '%' else 'n/d' end;
  if v_d > v_a * 1.10 and coalesce(current_setting('z71.aceitar_lentidao', true), '') <> 'sim' then
    raise exception 'z71: conferência 4 — fn_fin_contratado ficou % %% mais lenta (antes % ms, depois % ms; meta 10%%). Para aplicar mesmo assim: set local z71.aceitar_lentidao = ''sim''.',
      round((v_d / v_a - 1) * 100, 1), round(v_a, 1), round(v_d, 1);
  end if;

  -- 5) (B) a lista num lugar só, CHECK e linhas
  if fin.relatorio_tipos() is distinct from array['board','pessoas','conciliacao','identidade','acelera','prorata','receber']::text[] then
    raise exception 'z71: conferência 5 — fin.relatorio_tipos() inesperada';
  end if;
  select pg_get_constraintdef(c.oid) into v_txt from pg_constraint c
   where c.conrelid = 'fin.relatorios_emitidos'::regclass and c.conname = 'relatorios_emitidos_tipo_check' and c.contype = 'c';
  if v_txt is null or v_txt !~ 'relatorio_tipos\(\)' or v_txt ~ 'prorata' then
    raise exception 'z71: conferência 5 — CHECK novo não lê fin.relatorio_tipos(): %', v_txt;
  end if;
  select prosrc into v_txt from pg_proc where oid = 'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)'::regprocedure;
  if v_txt !~ 'fin\.relatorio_tipos\(\)' or v_txt ~ '''prorata''' or v_txt ~ '''board''' then
    raise exception 'z71: conferência 5 — fn_fin_relatorio_emitir ainda tem lista própria de tipos';
  end if;
  if exists (select 1 from fin.relatorios_emitidos re where not (re.tipo = any (fin.relatorio_tipos()))) then
    raise exception 'z71: conferência 5 — linha de fin.relatorios_emitidos fora da lista';
  end if;

  -- 6) ACL: PUBLIC e anon fora; authenticated só nas RPCs; a lista é interna
  if has_function_privilege('anon', 'public.fn_fin_contratado(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_contratado(text)', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)', 'execute')
     or has_function_privilege('anon', 'fin.relatorio_tipos()', 'execute')
     or has_function_privilege('authenticated', 'fin.relatorio_tipos()', 'execute')
     or exists (select 1 from pg_proc p, unnest(p.proacl) a
                 where p.oid in ('public.fn_fin_contratado(text)'::regprocedure, 'fin.relatorio_tipos()'::regprocedure,
                                 'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)'::regprocedure)
                   and a::text like '=%')
     or has_table_privilege('authenticated', 'fin.relatorios_emitidos', 'insert')
     or has_table_privilege('anon', 'fin.relatorios_emitidos', 'select') then
    raise exception 'z71: conferência 6 — ACL errada (PUBLIC/anon com execute, lista exposta ou tabela gravável)';
  end if;
end $conf$;
