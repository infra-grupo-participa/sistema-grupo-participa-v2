-- 20260928z72 — Financeiro, F8: "dinheiro já contratado" da Análise e bloco 2 do Contas a Receber com UM núcleo só.
--
-- APLICADA em produção em 29/09/2026 00:14 UTC (fin_contratado_unificado + _b, este só recoloca o corpo do núcleo idêntico ao arquivo). Ensaio: fn_fin_contratado 8 famílias 1176,4 → 961,0 ms (−18%); fn_fin_receber_semanal 204,5 → 195,1 ms. Depois: HM/parcelado 505.572 → 390.222; HM/assinatura 40.473 → 43.952; DIAMANTE/assinatura 71.500 → 447.167 (12 meses em vez de 3); AURUM/assinatura 0 → 9.750.
-- com detalhe). Independe da z71. A migration inteira é UMA transação: guarda ou conferência que falhe desfaz tudo.
-- Guarda: corpo VIVO de fin.cobrancas_previstas = z66 e de fn_fin_contratado = 20260928p (sem espaço, sem comentário,
-- sem o texto das mensagens de erro).
--
-- Por quê: Conflito 6 do catálogo — fn_fin_contratado e fin.cobrancas_previstas eram o mesmo conceito com duas regras.
-- A 1ª tentativa (z71 antiga) fazia a Análise chamar fin.cobrancas_previstas inteira: ~7× mais lenta no PGlite, por causa
-- da decoração da tela do Receber (fin.chave_opaca = 1 leitura do Vault por contrato, fin.nome_proprio, fin.recebimento).
--
-- O que faz:
--   1) fin.cobrancas_nucleo(p_corte, p_ate, p_detalhe, p_familia) — interna (invoker, search_path '', sem grant a ninguém). É o
--      corpo da z66 SEM chave_opaca, nome_proprio e recebimento, e SEM order by. Contrato agrupado por
--      chave = md5(e-mail|oferta) (barato; só agrupa por dentro, nunca sai de RPC). Devolve também, da ÚLTIMA cobrança
--      paga do contrato (a mesma que dá o valor), familia e valor_oferta. e-mail, oferta e nome crus saem só para a
--      decoração de fin.cobrancas_previstas (função interna chamando função interna). p_detalhe = false não monta o
--      jsonb do detalhe (a Análise não usa). p_familia (default null = todas) corta o universo JÁ em `ativos` (índice
--      de aprovado_em + filtro de família): a Análise monta só a família pedida; o Receber passa null.
--      (1º ensaio em produção, sem esse corte: fn_fin_contratado 1169,2 → 2363,2 ms nas 8 famílias — cada família
--      montava o núcleo de todas. Espelho: 57.243 linhas, 125 MB.)
--   2) fin.cobrancas_previstas — create or replace, MESMA assinatura, MESMO RETURNS, mesma ACL: núcleo + decoração.
--      chave_opaca passa a rodar 1× por contrato QUE APARECE na saída (antes: por contrato do universo). Saída idêntica
--      ao centavo: a conferência 1 compara linha a linha (EXCEPT ALL nos dois sentidos) em 3 cortes, e a 2 compara
--      fn_fin_receber_semanal inteira.
--   3) fn_fin_contratado — create or replace, MESMO RETURNS, mesma ACL. parcelado e assinatura = núcleo:
--       universo  = contrato e-mail|oferta com cobrança paga nos últimos 120 dias (assinatura, MULTIPLE_PAYMENTS e
--                   HOTMART_INSTALLMENTS*), sem estorno na série;
--       fim       = parcelas do plano ou teto de fin.assinatura_teto (z65); assinatura sem teto vai até o horizonte;
--       atraso    = premissas vigentes tolerancia_atraso_dias (5) e atraso_max_projetado_dias (35);
--       horizonte = do mês corrente ao fim do 12º mês; mês = mês da data efetiva da cobrança;
--       valor     = valor da OFERTA (bruto) da última paga — a Análise compara com o faturamento bruto;
--       em_risco  = cobranças 'a_receber' de contrato que tem cobrança 'em_atraso_fora' (6–35 dias); só 'a_receber' soma;
--       pessoas   = e-mails distintos (igual a antes).
--      'combinado' (board) fica como estava, inclusive o "não conta quem tem parcelado Hotmart em curso" pela regra antiga.
--   4) Conferência: fotos antes/depois; 'combinado' idêntico; a função nova = bloco 2 somado de forma independente (via
--      fin.cobrancas_previstas + busca da última paga pela PK); explicação por família × fonte × mês e por contrato em
--      NOTICE (sem dado pessoal); TEMPO: fn_fin_contratado (8 famílias) e fn_fin_receber_semanal, melhor de 5 rodadas
--      antes × depois na mesma transação — mais de +10% em qualquer uma ABORTA (sem exceção).
--
-- 5 perguntas:
--   escala: núcleo = universo de 120 dias pelo índice parcial de aprovado_em + série do contrato pelo índice
--           (e-mail, oferta, recorrência); cresce com contratos ativos, não com o histórico. Análise: 1 núcleo por
--           chamada, sem Vault. Receber: Vault só para contrato que aparece na saída.
--   índice: os mesmos da z61/z66 (nada novo em hotmart_transacoes). Provas P1–P3.
--   frequência: igual (1 chamada por família ao abrir a Análise; a RPC do Receber como antes).
--   repetição: a regra do contrato mora SÓ em fin.cobrancas_nucleo.
--   reversão: abaixo.
--
-- REVERSÃO (uma transação; nada se apaga):
--   begin;
--   -- a) recolocar o corpo da z66 em fin.cobrancas_previstas (20260928z66 linhas 528–655, create OR REPLACE — não drop;
--   --    a ACL é preservada) e o comment da z66;
--   -- b) recolocar o corpo da 20260928p em fn_fin_contratado (linhas 18–79, create or replace);
--   -- c) fin.cobrancas_nucleo pode ficar (ninguém mais chama; sem grant).
--   commit;
--
-- PROVAS (rodar e colar; todas SELECT, seguras; <UUID_FINANCEIRO> = perfil de quem vê o Financeiro):
--   P1) RPCs — rodar ANTES de aplicar e DEPOIS, 2ª execução de cada:
--       begin;
--       select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
--       explain (analyze, buffers) select * from public.fn_fin_contratado('HM');
--       explain (analyze, buffers) select * from public.fn_fin_contratado('DIAMANTE');
--       explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null, 'base');
--       rollback;
--   P2) núcleo (depois):
--       explain (analyze, buffers) select * from fin.cobrancas_nucleo(now(),
--         (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp) + interval '12 months'
--          - interval '1 day')::date, false, 'HM');
--   P3) o universo (tem que ser Index Scan em hotmart_transacoes_aprovado_pago_idx, sem Seq Scan em hotmart_transacoes):
--       explain (analyze, buffers) select distinct t.email, t.oferta_codigo from fin.vw_transacoes t
--        where t.status in ('APPROVED','COMPLETE') and t.aprovado_em > now() - interval '120 days' and t.aprovado_em <= now()
--          and t.recorrencia is not null;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_con  oid := to_regprocedure('public.fn_fin_contratado(text)');
  v_cob  oid := to_regprocedure('fin.cobrancas_previstas(timestamptz,date)');
  v_src  text;
  v_res  text;
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
  e_cob  text := $esperado$
#variable_conflict use_column
declare
  v_dia   date;
  v_tol   int;
  v_max   int;
  v_meses int;
begin
  if p_corte is null or p_ate is null then
    raise exception 'fin.cobrancas_previstas: corte e horizonte são obrigatórios' using errcode = '22023';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  if p_ate < v_dia or p_ate > v_dia + 400 then
    raise exception 'fin.cobrancas_previstas: horizonte fora de [corte, corte + 400 dias]' using errcode = '22023';
  end if;
  select pr.valor::int into v_tol from fin.premissas_receber pr
   where pr.chave = 'tolerancia_atraso_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  select pr.valor::int into v_max from fin.premissas_receber pr
   where pr.chave = 'atraso_max_projetado_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_tol is null or v_max is null then
    raise exception 'fin.cobrancas_previstas: premissa de atraso ausente em fin.premissas_receber' using errcode = 'P0002';
  end if;
  -- limite de geração por assinatura (horizonte): meses entre (corte − atraso máximo) e o horizonte, com folga de 2.
  -- O fim do PLANO vem de fin.assinatura_teto (z65).
  v_meses := ((extract(year from p_ate) - extract(year from v_dia - v_max)) * 12
              + extract(month from p_ate) - extract(month from v_dia - v_max))::int + 2;

  return query
  with ativos as (
    select distinct t.email, t.oferta_codigo
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em > p_corte - interval '120 days' and t.aprovado_em <= p_corte
       and t.recorrencia is not null
       and (t.oferta_modo = 'SUBSCRIPTION' or t.oferta_modo = 'MULTIPLE_PAYMENTS'
            or t.oferta_modo like 'HOTMART_INSTALLMENTS%')
       and t.email is not null and t.oferta_codigo is not null
  ), tx as materialized (
    select t.email, t.oferta_codigo, t.transacao, t.produto_id, t.produto_nome, t.familia, t.oferta_modo, t.grupo,
           t.recorrencia, t.parcelas, t.liquido, t.aprovado_em, t.dia_aprovado, t.dia_pedido, t.nome,
           (t.grupo = 'pago' and t.aprovado_em <= p_corte) pago
      from ativos a
      join fin.vw_transacoes t
        on t.email = a.email and t.oferta_codigo = a.oferta_codigo and t.recorrencia is not null
  ), c as (
    select x.email, x.oferta_codigo,
           (array_agg(x.oferta_modo order by x.aprovado_em desc, x.recorrencia desc)
              filter (where x.pago and x.oferta_modo <> 'UNIQUE_PAYMENT'))[1] modo,
           (array_agg(x.recorrencia  order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] n_ult,
           (array_agg(x.dia_aprovado order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] d_ult,
           (array_agg(x.liquido      order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] valor_ult,
           (array_agg(x.nome         order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] nome,
           (array_agg(x.produto_nome order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] produto_nome,
           (array_agg(x.produto_id   order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] produto_id,
           (array_agg(x.familia      order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] familia,
           max(x.recorrencia) filter (where x.pago) n_max,
           max(x.dia_aprovado) filter (where x.pago and x.recorrencia = 1) d1,
           max(x.parcelas) filter (where x.oferta_modo <> 'UNIQUE_PAYMENT') parcelas,
           jsonb_agg(jsonb_build_object('transacao', x.transacao, 'n', x.recorrencia, 'dia', x.dia_aprovado,
                                        'liquido', x.liquido)
                     order by x.aprovado_em, x.recorrencia) filter (where x.pago) detalhe   -- z66: sem e-mail/doc/nome
      from tx x
     group by x.email, x.oferta_codigo
  ), c2 as materialized (
    select c.email, c.oferta_codigo, c.n_ult, c.d_ult, c.valor_ult, c.nome, c.produto_nome, c.d1, c.parcelas, c.detalhe,
           case when c.modo = 'SUBSCRIPTION' then 'assinatura' else 'parcelado' end tipo,
           case when c.modo = 'SUBSCRIPTION' then c.n_ult else c.n_max end n_base,
           case when c.modo = 'SUBSCRIPTION' and c.produto_id = '1462643' then 'Assinaturas Serviço Diamante'
                when c.modo = 'SUBSCRIPTION' and c.produto_id = '3507214' then 'Assinaturas Holding - Holding Masters'
                when c.modo = 'SUBSCRIPTION' then 'Outras assinaturas'
                when c.familia = 'HM' then 'Parcelas a vencer HM'
                when c.familia = 'AURUM' then 'Parcelas a vencer Aurum'
                else 'Parcelas a vencer outros' end grupo_nome,
           ta.max_cobrancas teto,                                            -- z65: NULL = sem teto
           fin.chave_opaca('rc:' || c.email || '|' || c.oferta_codigo) ref   -- uma vez por contrato (lê o Vault)
      from c
      left join fin.assinatura_teto ta
        on ta.produto_id = c.produto_id and ta.ativo and c.modo = 'SUBSCRIPTION'
     where c.modo is not null and c.n_ult is not null
       and not exists (select 1 from tx e
                        where e.email = c.email and e.oferta_codigo = c.oferta_codigo and e.grupo = 'estornado'
                          and (c.d1 is null or coalesce(e.dia_aprovado, e.dia_pedido) >= c.d1))
  ), g as (
    select c2.*, s.n,
           case when c2.d1 is not null then (c2.d1 + make_interval(months => s.n - 1))::date
                else (c2.d_ult + make_interval(months => s.n - c2.n_ult))::date end venc,
           (c2.d_ult + make_interval(months => s.n - c2.n_ult))::date venc_b
      from c2
      cross join lateral generate_series(c2.n_base + 1,
               case when c2.tipo = 'parcelado' then least(c2.parcelas, c2.n_base + v_meses)
                    else least(c2.teto, c2.n_base + v_meses) end) s(n)   -- least ignora NULL: sem teto = z61
  ), vivos as (
    select g.ref from g where g.n = g.n_base + 1 and g.venc >= v_dia - v_max
  ), prev as (
    select g.*,
           case when g.venc + v_tol < v_dia then 'em_atraso_fora' else 'a_receber' end sit,
           case when g.venc + v_tol < v_dia then null::date else greatest(g.venc, v_dia + 1) end efetiva
      from g
     where g.ref in (select vivos.ref from vivos)
       and g.venc <= p_ate and g.venc >= v_dia - v_max
  ), feitas as (
    select c2.*, x.recorrencia n_pago, x.liquido liq_pago
      from c2
      join tx x on x.email = c2.email and x.oferta_codigo = c2.oferta_codigo
     where x.pago and x.dia_aprovado > v_dia - v_max
  )
  select p.grupo_nome, p.tipo, p.ref, fin.nome_proprio(p.nome), p.produto_nome, p.n, p.parcelas,
         p.venc, p.venc_b, p.sit, p.efetiva, p.valor_ult,
         case when p.sit = 'a_receber'
              then ((extract(year from p.efetiva) - extract(year from v_dia)) * 12
                    + extract(month from p.efetiva) - extract(month from v_dia))::int + 1 end,
         r.entra_em, r.entra_rapido, r.libera_em, r.retido, p.detalhe
    from prev p
    left join lateral fin.recebimento(p.efetiva, p.valor_ult) r on p.sit = 'a_receber'
  union all
  select f.grupo_nome, f.tipo, f.ref, fin.nome_proprio(f.nome), f.produto_nome, f.n_pago, f.parcelas,
         case when f.d1 is not null then (f.d1 + make_interval(months => f.n_pago - 1))::date end,
         (f.d_ult + make_interval(months => f.n_pago - f.n_ult))::date,
         'realizada', null::date, f.liq_pago, null::int, null::date, null::numeric, null::date, null::numeric, f.detalhe
    from feitas f
   order by 1, 8, 3, 6;
end
$esperado$;
  e_cob_res text := 'TABLE(grupo text, tipo text, ref text, rotulo text, produto text, n integer, parcelas integer, '
                    'vencimento date, vencimento_b date, situacao text, data_efetiva date, valor numeric, k integer, '
                    'entra_em date, entra_rapido numeric, libera_em date, retido numeric, detalhe jsonb)';
begin
  if to_regprocedure('fin.cobrancas_nucleo(timestamptz,date,boolean,text)') is not null
     or exists (select 1 from pg_proc where proname = 'cobrancas_nucleo' and pronamespace = 'fin'::regnamespace) then
    raise exception 'z72: já aplicada (fin.cobrancas_nucleo existe)';
  end if;
  if v_con is null or v_cob is null or to_regclass('fin.assinatura_teto') is null
     or to_regprocedure('public.fn_fin_receber_semanal(timestamptz,date,text)') is null then
    raise exception 'z72: faltam dependências (20260928p, z65 ou z66 não aplicadas)';
  end if;
  if (select count(*) from pg_proc where proname = 'fn_fin_contratado' and pronamespace = 'public'::regnamespace) <> 1
     or (select count(*) from pg_proc where proname = 'cobrancas_previstas' and pronamespace = 'fin'::regnamespace) <> 1 then
    raise exception 'z72: sobrecarga viva de fn_fin_contratado ou fin.cobrancas_previstas — conferir pg_get_function_arguments';
  end if;

  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_con;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_con, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_con_res, '\s+', '', 'g') then
    raise exception 'z72: corpo vivo de fn_fin_contratado diverge da 20260928p. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_con and l.lanname = 'plpgsql' and p.provolatile = 's' and p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z72: atributos vivos de fn_fin_contratado diferentes da 20260928p (plpgsql/stable/definer/search_path vazio)';
  end if;

  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_cob;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_cob, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_cob_res, '\s+', '', 'g') then
    raise exception 'z72: corpo vivo de fin.cobrancas_previstas diverge da z66. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_cob and l.lanname = 'plpgsql' and p.provolatile = 's' and not p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z72: atributos vivos de fin.cobrancas_previstas diferentes da z66 (plpgsql/stable/invoker/search_path vazio)';
  end if;
end $guarda$;


-- ─── 1. Fotos ANTES e tempo ─────────────────────────────────────────────────────────────────────────────────────────
do $foto$
declare
  v_adm  uuid;
  v_fam  text;
  v_t0   timestamptz;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_a4   date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                  + interval '4 months' - interval '1 day')::date;
  v_a12  date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                  + interval '12 months' - interval '1 day')::date;
  v_fams text[] := array['HT','EVENTOS','HM','AURUM','ACELERA','PROGRAMA_DIAMANTE','DIAMANTE','OUTROS'];
begin
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z72: nenhum perfil admin ativo para a foto das RPCs'; end if;

  -- bloco 2 (interna, sem auth) em 3 cortes
  create temp table z72_cob_antes on commit drop as
    select 'passado'::text foto, c.* from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
    union all select 'agora_4m', c.* from fin.cobrancas_previstas(now(), v_a4) c
    union all select 'agora_12m', c.* from fin.cobrancas_previstas(now(), v_a12) c;

  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  create temp table z72_rs_antes on commit drop as
    select x.* from public.fn_fin_receber_semanal(null, null, 'base') x;
  create temp table z72_antes (familia text, mes date, fonte text, valor numeric, pessoas int, em_risco numeric) on commit drop;
  create temp table z72_tempo (fase text, rpc text, rodada int, ms numeric) on commit drop;
  foreach v_fam in array v_fams loop
    insert into z72_antes select v_fam, x.* from public.fn_fin_contratado(v_fam) x;
  end loop;
  for r in 1..5 loop
    v_t0 := clock_timestamp();
    foreach v_fam in array v_fams loop perform count(*) from public.fn_fin_contratado(v_fam); end loop;
    insert into z72_tempo values ('antes', 'contratado', r, extract(epoch from clock_timestamp() - v_t0) * 1000);
    v_t0 := clock_timestamp();
    perform count(*) from public.fn_fin_receber_semanal(null, null, 'base');
    insert into z72_tempo values ('antes', 'receber', r, extract(epoch from clock_timestamp() - v_t0) * 1000);
  end loop;
  perform set_config('request.jwt.claims', '', true);

  -- réplica POR CONTRATO da regra antiga (parcelado e assinatura), só para a conferência explicar a diferença.
  -- A conferência 3a exige que a réplica somada = a foto da função antiga (senão a explicação não vale).
  create temp table z72_antes_det on commit drop as
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
  delete from z72_antes_det d
   where d.mes < date_trunc('month', v_hoje::timestamp)::date
      or d.mes >= (date_trunc('month', v_hoje::timestamp) + interval '12 months')::date;
end $foto$;


-- ─── 2. O núcleo ────────────────────────────────────────────────────────────────────────────────────────────────────
create function fin.cobrancas_nucleo(p_corte timestamptz, p_ate date, p_detalhe boolean default true,
                                     p_familia text default null)
returns table (
  grupo text, tipo text, chave text, email text, oferta_codigo text, nome text, produto text, familia text,
  valor_oferta numeric, n int, parcelas int, vencimento date, vencimento_b date, situacao text, data_efetiva date,
  valor numeric, k int, detalhe jsonb)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dia   date;
  v_tol   int;
  v_max   int;
  v_meses int;
begin
  if p_corte is null or p_ate is null then
    raise exception 'fin.cobrancas_nucleo: corte e horizonte são obrigatórios' using errcode = '22023';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  if p_ate < v_dia or p_ate > v_dia + 400 then
    raise exception 'fin.cobrancas_nucleo: horizonte fora de [corte, corte + 400 dias]' using errcode = '22023';
  end if;
  select pr.valor::int into v_tol from fin.premissas_receber pr
   where pr.chave = 'tolerancia_atraso_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  select pr.valor::int into v_max from fin.premissas_receber pr
   where pr.chave = 'atraso_max_projetado_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_tol is null or v_max is null then
    raise exception 'fin.cobrancas_nucleo: premissa de atraso ausente em fin.premissas_receber' using errcode = 'P0002';
  end if;
  -- limite de geração por assinatura (horizonte): meses entre (corte − atraso máximo) e o horizonte, com folga de 2.
  -- O fim do PLANO vem de fin.assinatura_teto (z65).
  v_meses := ((extract(year from p_ate) - extract(year from v_dia - v_max)) * 12
              + extract(month from p_ate) - extract(month from v_dia - v_max))::int + 2;

  return query
  with ativos as (
    select distinct t.email, t.oferta_codigo
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em > p_corte - interval '120 days' and t.aprovado_em <= p_corte
       and (p_familia is null or t.familia = p_familia)   -- z72: a Análise corta a família já no universo
       and t.recorrencia is not null
       and (t.oferta_modo = 'SUBSCRIPTION' or t.oferta_modo = 'MULTIPLE_PAYMENTS'
            or t.oferta_modo like 'HOTMART_INSTALLMENTS%')
       and t.email is not null and t.oferta_codigo is not null
  ), tx as materialized (
    select t.email, t.oferta_codigo, t.transacao, t.produto_id, t.produto_nome, t.familia, t.oferta_modo, t.grupo,
           t.recorrencia, t.parcelas, t.liquido, t.valor_oferta, t.aprovado_em, t.dia_aprovado, t.dia_pedido, t.nome,
           (t.grupo = 'pago' and t.aprovado_em <= p_corte) pago
      from ativos a
      join fin.vw_transacoes t
        on t.email = a.email and t.oferta_codigo = a.oferta_codigo and t.recorrencia is not null
  ), c as (
    select x.email, x.oferta_codigo,
           (array_agg(x.oferta_modo order by x.aprovado_em desc, x.recorrencia desc)
              filter (where x.pago and x.oferta_modo <> 'UNIQUE_PAYMENT'))[1] modo,
           (array_agg(x.recorrencia  order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] n_ult,
           (array_agg(x.dia_aprovado order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] d_ult,
           (array_agg(x.liquido      order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] valor_ult,
           (array_agg(x.nome         order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] nome,
           (array_agg(x.produto_nome order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] produto_nome,
           (array_agg(x.produto_id   order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] produto_id,
           (array_agg(x.familia      order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] familia,
           (array_agg(x.valor_oferta order by x.aprovado_em desc, x.recorrencia desc) filter (where x.pago))[1] valor_oferta_ult,  -- z72
           max(x.recorrencia) filter (where x.pago) n_max,
           max(x.dia_aprovado) filter (where x.pago and x.recorrencia = 1) d1,
           max(x.parcelas) filter (where x.oferta_modo <> 'UNIQUE_PAYMENT') parcelas,
           jsonb_agg(jsonb_build_object('transacao', x.transacao, 'n', x.recorrencia, 'dia', x.dia_aprovado,
                                        'liquido', x.liquido)
                     order by x.aprovado_em, x.recorrencia) filter (where x.pago and p_detalhe) detalhe   -- z66: sem e-mail/doc/nome; z72: só se pedido
      from tx x
     group by x.email, x.oferta_codigo
  ), c2 as materialized (
    select c.email, c.oferta_codigo, c.n_ult, c.d_ult, c.valor_ult, c.nome, c.produto_nome, c.d1, c.parcelas, c.detalhe,
           c.familia, c.valor_oferta_ult,
           case when c.modo = 'SUBSCRIPTION' then 'assinatura' else 'parcelado' end tipo,
           case when c.modo = 'SUBSCRIPTION' then c.n_ult else c.n_max end n_base,
           case when c.modo = 'SUBSCRIPTION' and c.produto_id = '1462643' then 'Assinaturas Serviço Diamante'
                when c.modo = 'SUBSCRIPTION' and c.produto_id = '3507214' then 'Assinaturas Holding - Holding Masters'
                when c.modo = 'SUBSCRIPTION' then 'Outras assinaturas'
                when c.familia = 'HM' then 'Parcelas a vencer HM'
                when c.familia = 'AURUM' then 'Parcelas a vencer Aurum'
                else 'Parcelas a vencer outros' end grupo_nome,
           ta.max_cobrancas teto,                                            -- z65: NULL = sem teto
           pg_catalog.md5(c.email || '|' || c.oferta_codigo) chave         -- z72: só agrupa por dentro (sem Vault)
      from c
      left join fin.assinatura_teto ta
        on ta.produto_id = c.produto_id and ta.ativo and c.modo = 'SUBSCRIPTION'
     where c.modo is not null and c.n_ult is not null
       and not exists (select 1 from tx e
                        where e.email = c.email and e.oferta_codigo = c.oferta_codigo and e.grupo = 'estornado'
                          and (c.d1 is null or coalesce(e.dia_aprovado, e.dia_pedido) >= c.d1))
  ), g as (
    select c2.*, s.n,
           case when c2.d1 is not null then (c2.d1 + make_interval(months => s.n - 1))::date
                else (c2.d_ult + make_interval(months => s.n - c2.n_ult))::date end venc,
           (c2.d_ult + make_interval(months => s.n - c2.n_ult))::date venc_b
      from c2
      cross join lateral generate_series(c2.n_base + 1,
               case when c2.tipo = 'parcelado' then least(c2.parcelas, c2.n_base + v_meses)
                    else least(c2.teto, c2.n_base + v_meses) end) s(n)   -- least ignora NULL: sem teto = z61
  ), vivos as (
    select g.chave from g where g.n = g.n_base + 1 and g.venc >= v_dia - v_max
  ), prev as (
    select g.*,
           case when g.venc + v_tol < v_dia then 'em_atraso_fora' else 'a_receber' end sit,
           case when g.venc + v_tol < v_dia then null::date else greatest(g.venc, v_dia + 1) end efetiva
      from g
     where g.chave in (select vivos.chave from vivos)
       and g.venc <= p_ate and g.venc >= v_dia - v_max
  ), feitas as (
    select c2.*, x.recorrencia n_pago, x.liquido liq_pago
      from c2
      join tx x on x.email = c2.email and x.oferta_codigo = c2.oferta_codigo
     where x.pago and x.dia_aprovado > v_dia - v_max
  )
  select p.grupo_nome, p.tipo, p.chave, p.email, p.oferta_codigo, p.nome, p.produto_nome, p.familia, p.valor_oferta_ult,
         p.n, p.parcelas, p.venc, p.venc_b, p.sit, p.efetiva, p.valor_ult,
         case when p.sit = 'a_receber'
              then ((extract(year from p.efetiva) - extract(year from v_dia)) * 12
                    + extract(month from p.efetiva) - extract(month from v_dia))::int + 1 end,
         p.detalhe
    from prev p
  union all
  select f.grupo_nome, f.tipo, f.chave, f.email, f.oferta_codigo, f.nome, f.produto_nome, f.familia, f.valor_oferta_ult,
         f.n_pago, f.parcelas,
         case when f.d1 is not null then (f.d1 + make_interval(months => f.n_pago - 1))::date end,
         (f.d_ult + make_interval(months => f.n_pago - f.n_ult))::date,
         'realizada', null::date, f.liq_pago, null::int, f.detalhe
    from feitas f;
end $$;
comment on function fin.cobrancas_nucleo(timestamptz, date, boolean, text) is
  'Interna (z72): regra ÚNICA das cobranças recorrentes previstas por contrato (z61; teto z65; detalhe z66). Sem Vault, '
  'sem nome formatado, sem recebimento. chave = md5(e-mail|oferta), só para agrupar por dentro. Consumidores: '
  'fin.cobrancas_previstas (Receber, bloco 2) e public.fn_fin_contratado (Análise). Nunca expor em RPC.';
revoke all on function fin.cobrancas_nucleo(timestamptz, date, boolean, text) from public, anon, authenticated;


-- ─── 3. Bloco 2 do Receber = núcleo + decoração (saída idêntica) ────────────────────────────────────────────────────
create or replace function fin.cobrancas_previstas(p_corte timestamptz, p_ate date)
returns table (
  grupo text, tipo text, ref text, rotulo text, produto text, n int, parcelas int,
  vencimento date, vencimento_b date, situacao text, data_efetiva date, valor numeric, k int,
  entra_em date, entra_rapido numeric, libera_em date, retido numeric, detalhe jsonb)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dia   date;
  v_tol   int;
  v_max   int;
begin
  if p_corte is null or p_ate is null then
    raise exception 'fin.cobrancas_previstas: corte e horizonte são obrigatórios' using errcode = '22023';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  if p_ate < v_dia or p_ate > v_dia + 400 then
    raise exception 'fin.cobrancas_previstas: horizonte fora de [corte, corte + 400 dias]' using errcode = '22023';
  end if;
  select pr.valor::int into v_tol from fin.premissas_receber pr
   where pr.chave = 'tolerancia_atraso_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  select pr.valor::int into v_max from fin.premissas_receber pr
   where pr.chave = 'atraso_max_projetado_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_tol is null or v_max is null then
    raise exception 'fin.cobrancas_previstas: premissa de atraso ausente em fin.premissas_receber' using errcode = 'P0002';
  end if;

  return query
  with nu as materialized (
    -- z72: a regra mora em fin.cobrancas_nucleo; aqui só a decoração da tela do Receber
    select x.* from fin.cobrancas_nucleo(p_corte, p_ate, true, null) x
  ), kr as materialized (
    -- ref opaca 1× por contrato que aparece na saída (lê o Vault)
    select d.chave, fin.chave_opaca('rc:' || d.email || '|' || d.oferta_codigo) ref
      from (select distinct nu.chave, nu.email, nu.oferta_codigo from nu) d
  )
  select nu.grupo, nu.tipo, kr.ref, fin.nome_proprio(nu.nome), nu.produto, nu.n, nu.parcelas,
         nu.vencimento, nu.vencimento_b, nu.situacao, nu.data_efetiva, nu.valor, nu.k,
         r.entra_em, r.entra_rapido, r.libera_em, r.retido, nu.detalhe
    from nu
    join kr on kr.chave = nu.chave
    left join lateral fin.recebimento(nu.data_efetiva, nu.valor) r on nu.situacao = 'a_receber'
   order by 1, 8, 3, 6;
end $$;
comment on function fin.cobrancas_previstas(timestamptz, date) is
  'Contas a Receber bloco 2 (z61; teto z65; detalhe z66; núcleo z72): cobranças recorrentes previstas por contrato '
  'e-mail|oferta = fin.cobrancas_nucleo + ref opaca, nome e recebimento. detalhe = transações pagas do contrato até o '
  'corte [{transacao, n, dia, liquido}], sem e-mail/documento/nome.';
revoke all on function fin.cobrancas_previstas(timestamptz, date) from public, anon, authenticated;


-- ─── 4. Análise = núcleo ────────────────────────────────────────────────────────────────────────────────────────────
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
    -- z72 (F8): parcelado e assinatura = a regra do Receber, bloco 2 (fin.cobrancas_nucleo, sem Vault e sem detalhe).
    -- Família e valor da OFERTA (bruto) vêm da última cobrança paga do contrato. Só 'a_receber' soma; 'em_atraso_fora'
    -- marca o contrato inteiro como em risco.
    select nu.chave, nu.tipo, nu.situacao, nu.data_efetiva, nu.email, nu.valor_oferta
      from fin.cobrancas_nucleo(now(), v_fim, false, p_familia) nu   -- só a família pedida, cortada no universo
     where nu.familia = p_familia and nu.situacao in ('a_receber','em_atraso_fora')
  ), rk as (
    select cp.chave, bool_or(cp.situacao = 'em_atraso_fora') risco from cp group by cp.chave
  ), rec as (
    select date_trunc('month', cp.data_efetiva::timestamp)::date mes, cp.tipo fonte, cp.valor_oferta valor, cp.email, rk.risco
      from cp join rk on rk.chave = cp.chave
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
  'Análise do Faturamento (20260928p; z72): dinheiro já vendido que ainda vai entrar, por mês (12) e fonte. parcelado e '
  'assinatura = fin.cobrancas_nucleo (a regra do Receber, bloco 2), valor = oferta (bruto) da última paga; em_risco = '
  'contrato com cobrança em_atraso_fora. combinado = board (inalterado).';
revoke all on function public.fn_fin_contratado(text) from public, anon;
grant execute on function public.fn_fin_contratado(text) to authenticated;


-- ─── 5. Conferência (falha → rollback de tudo) ──────────────────────────────────────────────────────────────────────
do $conf$
declare
  v_adm  uuid;
  v_fam  text;
  v_t0   timestamptz;
  v_ini  date := date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)::date;
  v_a4   date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                  + interval '4 months' - interval '1 day')::date;
  v_fim  date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                  + interval '12 months' - interval '1 day')::date;
  v_fams text[] := array['HT','EVENTOS','HM','AURUM','ACELERA','PROGRAMA_DIAMANTE','DIAMANTE','OUTROS'];
  v_a    numeric;
  v_d    numeric;
  v_ra   numeric;
  v_rd   numeric;
  v_txt  text;
  v_n    int;
  r      record;
begin
  -- 1) bloco 2 idêntico ao centavo, linha a linha, nos 3 cortes
  create temp table z72_cob_depois on commit drop as
    select 'passado'::text foto, c.* from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
    union all select 'agora_4m', c.* from fin.cobrancas_previstas(now(), v_a4) c
    union all select 'agora_12m', c.* from fin.cobrancas_previstas(now(), v_fim) c;
  select (select count(*) from (select * from z72_cob_antes except all select * from z72_cob_depois) x)
       + (select count(*) from (select * from z72_cob_depois except all select * from z72_cob_antes) y) into v_n;
  if v_n > 0 or (select count(*) from z72_cob_antes) <> (select count(*) from z72_cob_depois) then
    raise exception 'z72: conferência 1 — fin.cobrancas_previstas mudou (% linha(s) diferentes entre antes e depois)', v_n;
  end if;
  raise notice 'z72 conferência 1: fin.cobrancas_previstas idêntica — % linhas (passado %, agora 4 m %, agora 12 m %)',
    (select count(*) from z72_cob_depois), (select count(*) from z72_cob_depois where foto = 'passado'),
    (select count(*) from z72_cob_depois where foto = 'agora_4m'), (select count(*) from z72_cob_depois where foto = 'agora_12m');

  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);

  -- 2) a RPC do Receber inteira idêntica
  create temp table z72_rs_depois on commit drop as
    select x.* from public.fn_fin_receber_semanal(null, null, 'base') x;
  select (select count(*) from (select * from z72_rs_antes except all select * from z72_rs_depois) x)
       + (select count(*) from (select * from z72_rs_depois except all select * from z72_rs_antes) y) into v_n;
  if v_n > 0 then
    raise exception 'z72: conferência 2 — fn_fin_receber_semanal mudou (% linha(s) diferentes)', v_n;
  end if;
  raise notice 'z72 conferência 2: fn_fin_receber_semanal idêntica — % linhas', (select count(*) from z72_rs_depois);

  create temp table z72_depois (familia text, mes date, fonte text, valor numeric, pessoas int, em_risco numeric) on commit drop;
  foreach v_fam in array v_fams loop
    insert into z72_depois select v_fam, x.* from public.fn_fin_contratado(v_fam) x;
  end loop;
  for i in 1..5 loop
    v_t0 := clock_timestamp();
    foreach v_fam in array v_fams loop perform count(*) from public.fn_fin_contratado(v_fam); end loop;
    insert into z72_tempo values ('depois', 'contratado', i, extract(epoch from clock_timestamp() - v_t0) * 1000);
    v_t0 := clock_timestamp();
    perform count(*) from public.fn_fin_receber_semanal(null, null, 'base');
    insert into z72_tempo values ('depois', 'receber', i, extract(epoch from clock_timestamp() - v_t0) * 1000);
  end loop;
  perform set_config('request.jwt.claims', '', true);

  -- bloco 2 com o contrato resolvido de forma independente do núcleo: saída de fin.cobrancas_previstas + a última paga
  -- (último elemento do detalhe) buscada pela PK em fin.vw_transacoes
  create temp table z72_cp on commit drop as
  select c.ref, c.tipo, c.situacao, c.n, c.vencimento, c.data_efetiva, t.familia, t.email, t.oferta_codigo,
         t.oferta_modo, t.produto_id, t.valor_oferta
    from z72_cob_depois c
    join fin.vw_transacoes t on t.transacao = (c.detalhe -> (jsonb_array_length(c.detalhe) - 1) ->> 'transacao')
   where c.foto = 'agora_12m' and c.situacao in ('a_receber','em_atraso_fora');

  -- 3a) a réplica da regra antiga explica a foto ANTES
  select count(*) into v_n from (
    select 1
      from (select familia, mes, fonte, valor, pessoas, em_risco from z72_antes where fonte <> 'combinado') a
      full join (select d.familia, d.mes, d.fonte, round(sum(d.valor), 2) valor, count(distinct d.email)::int pessoas,
                        round(coalesce(sum(d.valor) filter (where d.risco), 0), 2) em_risco
                   from z72_antes_det d group by 1, 2, 3) b
        on b.familia = a.familia and b.mes = a.mes and b.fonte = a.fonte
     where a.valor is distinct from b.valor or a.pessoas is distinct from b.pessoas
        or a.em_risco is distinct from b.em_risco) z;
  if v_n > 0 then
    raise exception 'z72: conferência 3a — a réplica da regra antiga não bate com a foto ANTES em % linha(s)', v_n;
  end if;

  -- 3b) 'combinado' idêntico, linha a linha, em todas as famílias
  select count(*) into v_n from (
    select 1 from (select * from z72_antes where fonte = 'combinado') a
      full join (select * from z72_depois where fonte = 'combinado') b
        on b.familia = a.familia and b.mes = a.mes
     where a.valor is distinct from b.valor or a.pessoas is distinct from b.pessoas
        or a.em_risco is distinct from b.em_risco) z;
  if v_n > 0 then
    raise exception 'z72: conferência 3b — fonte combinado mudou em % linha(s) (tinha que ficar como está)', v_n;
  end if;

  -- 3c) parcelado/assinatura DEPOIS = bloco 2 somado de forma independente (só a_receber; risco pelo contrato)
  select count(*) into v_n from (
    select 1
      from (select * from z72_depois where fonte <> 'combinado') a
      full join (
        select c.familia, date_trunc('month', c.data_efetiva::timestamp)::date mes, c.tipo fonte,
               round(sum(c.valor_oferta), 2) valor, count(distinct c.email)::int pessoas,
               round(coalesce(sum(c.valor_oferta) filter (where c.ref in (
                 select x.ref from z72_cp x where x.situacao = 'em_atraso_fora')), 0), 2) em_risco
          from z72_cp c
         where c.situacao = 'a_receber' and c.familia = any (v_fams)
           and c.data_efetiva >= v_ini and c.data_efetiva <= v_fim
         group by 1, 2, 3) b
        on b.familia = a.familia and b.mes = a.mes and b.fonte = a.fonte
     where a.valor is distinct from b.valor or a.pessoas is distinct from b.pessoas
        or a.em_risco is distinct from b.em_risco) z;
  if v_n > 0 then
    raise exception 'z72: conferência 3c — fn_fin_contratado nova não é o bloco 2 somado (% linha(s) diferentes)', v_n;
  end if;

  -- 3d) forma
  if exists (select 1 from z72_depois d
              where d.fonte not in ('parcelado','assinatura','combinado') or d.mes < v_ini or d.mes > v_fim
                 or d.valor <= 0 or d.em_risco < 0 or d.em_risco > d.valor or d.pessoas < 1) then
    raise exception 'z72: conferência 3d — linha fora da forma (fonte, janela de 12 meses, valor > 0, 0 ≤ risco ≤ valor)';
  end if;

  -- 3e) família que tinha parcelado/assinatura não pode zerar
  select string_agg(a.familia, ', ') into v_txt
    from (select familia, sum(valor) v from z72_antes where fonte <> 'combinado' group by 1) a
    left join (select familia, sum(valor) v from z72_depois where fonte <> 'combinado' group by 1) b on b.familia = a.familia
   where a.v > 0 and coalesce(b.v, 0) = 0;
  if v_txt is not null then
    raise exception 'z72: conferência 3e — parcelado/assinatura zerou em: % (antes tinha)', v_txt;
  end if;

  -- 3f) EXPLICAÇÃO (NOTICE, sem dado pessoal)
  for r in
    select coalesce(a.familia, b.familia) familia, coalesce(a.fonte, b.fonte) fonte,
           string_agg(to_char(coalesce(a.mes, b.mes), 'YYYY-MM') || ' ' || coalesce(a.valor, 0) || '→' || coalesce(b.valor, 0)
                      || case when coalesce(a.em_risco, 0) + coalesce(b.em_risco, 0) > 0
                              then ' (risco ' || coalesce(a.em_risco, 0) || '→' || coalesce(b.em_risco, 0) || ')' else '' end,
                      '; ' order by coalesce(a.mes, b.mes)) meses,
           sum(coalesce(a.valor, 0)) ta, sum(coalesce(b.valor, 0)) td
      from z72_antes a
      full join z72_depois b on b.familia = a.familia and b.fonte = a.fonte and b.mes = a.mes
     group by 1, 2
     order by 1, 2
  loop
    raise notice 'z72 % / %: antes % → depois % | %', r.familia, r.fonte, r.ta, r.td, r.meses;
  end loop;

  for r in
    with a as (
      select d.familia, d.fonte, d.chave, sum(d.valor) v from z72_antes_det d group by 1, 2, 3
    ), cps as (
      select c.familia, c.tipo fonte, case when c.tipo = 'parcelado' then c.email || '|' || c.oferta_codigo else c.email end chave,
             c.situacao, c.data_efetiva, c.valor_oferta, c.oferta_modo
        from z72_cp c where c.familia = any (v_fams)
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
    raise notice 'z72 % / % por contrato: ambos % (antes % → depois %, dos quais % nos meses +1 a +3, a janela da assinatura antiga) · só antes % (R$ %; % em atraso 6–35 d fora da soma, % fora do universo: atraso > 35 d, sem pagamento em 120 d ou estorno) · só depois % (R$ %; % MULTIPLE_PAYMENTS, que a regra antiga não lia)',
      r.familia, r.fonte, r.n_amb, r.amb_a, r.amb_d, r.amb_d_jan, r.n_so_a, r.so_a, r.n_so_a_fora,
      r.n_so_a_fora_universo, r.n_so_d, r.so_d, r.n_so_d_multiple;
  end loop;

  for r in
    select c.familia, c.produto_id, t.max_cobrancas, count(distinct c.ref) n,
           count(distinct c.ref) filter (where mx.n_max = t.max_cobrancas) n_teto
      from z72_cp c
      join fin.assinatura_teto t on t.produto_id = c.produto_id and t.ativo
      join (select ref, max(n) n_max from z72_cp group by ref) mx on mx.ref = c.ref
     where c.tipo = 'assinatura'
     group by 1, 2, 3
  loop
    raise notice 'z72 teto z65: % produto % (teto %): % contratos no horizonte, % chegam ao teto dentro dos 12 meses',
      r.familia, r.produto_id, r.max_cobrancas, r.n, r.n_teto;
  end loop;

  -- 4) TEMPO: melhor de 5 rodadas de cada lado, mesma transação. +10% em qualquer uma aborta. Sem exceção.
  select min(ms) filter (where fase = 'antes' and rpc = 'contratado'), min(ms) filter (where fase = 'depois' and rpc = 'contratado'),
         min(ms) filter (where fase = 'antes' and rpc = 'receber'),    min(ms) filter (where fase = 'depois' and rpc = 'receber')
    into v_a, v_d, v_ra, v_rd from z72_tempo;
  raise notice 'z72 tempo (melhor de 5): fn_fin_contratado 8 famílias antes % ms · depois % ms (% %%) | fn_fin_receber_semanal antes % ms · depois % ms (% %%)',
    round(v_a, 1), round(v_d, 1), round((v_d / nullif(v_a, 0) - 1) * 100, 1),
    round(v_ra, 1), round(v_rd, 1), round((v_rd / nullif(v_ra, 0) - 1) * 100, 1);
  if v_d > v_a * 1.10 or v_rd > v_ra * 1.10 then
    raise exception 'z72: conferência 4 — tempo acima da meta (+10%%): fn_fin_contratado % → % ms · fn_fin_receber_semanal % → % ms',
      round(v_a, 1), round(v_d, 1), round(v_ra, 1), round(v_rd, 1);
  end if;

  -- 5) ACL: núcleo e bloco 2 internos; RPC só para authenticated; nada para PUBLIC/anon
  if has_function_privilege('anon', 'fin.cobrancas_nucleo(timestamptz,date,boolean,text)', 'execute')
     or has_function_privilege('authenticated', 'fin.cobrancas_nucleo(timestamptz,date,boolean,text)', 'execute')
     or has_function_privilege('anon', 'fin.cobrancas_previstas(timestamptz,date)', 'execute')
     or has_function_privilege('authenticated', 'fin.cobrancas_previstas(timestamptz,date)', 'execute')
     or has_function_privilege('anon', 'public.fn_fin_contratado(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_contratado(text)', 'execute')
     or exists (select 1 from pg_proc p, unnest(p.proacl) a
                 where p.oid in ('fin.cobrancas_nucleo(timestamptz,date,boolean,text)'::regprocedure,
                                 'fin.cobrancas_previstas(timestamptz,date)'::regprocedure,
                                 'public.fn_fin_contratado(text)'::regprocedure)
                   and a::text like '=%') then
    raise exception 'z72: conferência 5 — ACL errada (núcleo/bloco 2 expostos, ou PUBLIC/anon com execute)';
  end if;
end $conf$;

-- ═══ MEDIDO em produção (29/09/2026, coordenador; 2ª execução; usuário do Financeiro) ════════════════════════════
-- P1 fn_fin_contratado('HM') 185,4 ms (17 linhas, shared hit=22510) · ('DIAMANTE') 182,3 ms (12 linhas, hit=19581)
--    · fn_fin_receber_semanal(null,null,'base') 200,9 ms (551 linhas, hit=9515).
-- P2 fin.cobrancas_nucleo(now(), +12 meses, false, 'HM') 39,6 ms (325 linhas, hit=2356).
-- P3 universo 120 d: Bitmap Heap Scan on hotmart_transacoes ← BitmapAnd(Bitmap Index Scan on
--    hotmart_transacoes_aprovado_pago_idx (2.297) + Bitmap Index Scan on hotmart_transacoes_contrato_rec_idx (5.622))
--    → 280 linhas, 1,25 ms. Nenhum Seq Scan em hotmart_transacoes. O resto do custo de fn_fin_contratado é o CTE `plano`
--    da fonte 'combinado' (inalterado).
