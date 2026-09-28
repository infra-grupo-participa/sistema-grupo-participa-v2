-- 20260928z65 — Contas a Receber, bloco 2: TETO de cobranças por plano de assinatura (fin.cobrancas_previstas).
--
-- APLICADA em produção em 28/09/2026 (apply_migration "fin_cobrancas_teto_assinatura"; mensagens de erro encurtadas e sem os raise notice, lógica idêntica). Depois (corte 25/09): Holding-HM 45→18 cobranças (R$ 86.286→34.507); Outras assinaturas 7→6.
-- Depende da z61 (aplicada). Guarda: o corpo VIVO de fin.cobrancas_previstas tem que ser o da z61, caractere a caractere
-- (sem espaço e sem comentário). A z63 NÃO mexe em fin.cobrancas_previstas (só a consome, pela mesma assinatura e o
-- mesmo RETURNS TABLE, que esta migration preserva); a z64 também não. Ordem entre z63, z64 e z65 é livre.
--
-- Bug medido em produção (28/09, corte 25/09 23:59 -03, horizonte 31/12): o bloco 2 projetava assinatura SEM FIM.
--   3507214 "Holding - Holding Masters": plano de até 12 cobranças (max(recorrencia) = 12 em 168 pessoas; confirmado
--   28/09) e a função projetava n 8–16 → 45 cobranças / 14 contratos / R$ 86.286 (planilha: 32 linhas / R$ 66 mil).
--   "Aurum - A" (Outras assinaturas): max(recorrencia) = 12 em 28 pessoas; a função projetava n 10–13.
--   "Serviço Diamante": recorrência chega a 33 — continua SEM teto (produto fora da tabela = sem teto).
--
-- Fonte do teto: a API usada pelo hotmart-sync (/payments/api/v1/sales/history) grava em bruto_json o item de venda
--   (product, buyer, producer, purchase{offer{code,payment_mode}, recurrency_number, is_subscription, payment…}); o
--   nº máximo de cobranças do plano não foi achado no código de ingestão. Não houve acesso ao banco para conferir o
--   bruto_json vivo: a prova D1 lista TODOS os caminhos do bruto_json de assinaturas. Se aparecer campo com o nº máximo
--   de cobranças, a leitura dele entra em migration NOVA (esta tabela continua como fallback). Até lá: premissa por
--   produto em fin.assinatura_teto.
--
-- O que faz:
--   1) fin.assinatura_teto (produto_id PK, max_cobrancas, ativo, fonte, criado_em). RLS ligado, sem grant a ninguém.
--      Carga: 3507214 = 12 e o produto_id de "Aurum - A" = 12 (resolvido por produto_nome EXATO no espelho; aborta se
--      não houver exatamente 1 produto_id com esse nome). Aborta também se o espelho tiver cobrança PAGA de assinatura
--      desses produtos com recorrência acima do teto (o teto contradiria o dado).
--   2) create or replace fin.cobrancas_previstas — MESMA assinatura, MESMO RETURNS TABLE, mesma ACL. Única mudança:
--      contrato em modo SUBSCRIPTION de produto com teto ativo gera n só até max_cobrancas. n > teto não é gerada.
--      Contrato que já pagou a última cobrança do plano não projeta nada (sai de "vivos"); as linhas 'realizada' dele
--      continuam (são fato, não projeção). Parcelado e produto sem teto: idêntico à z61.
--   3) Conferência interna (falha → rollback de tudo): fotografa a saída ANTES do replace (corte 25/09 e agora) e exige
--      que a saída DEPOIS seja a de ANTES menos, e só menos, cobranças não realizadas de assinatura com n > 12 dos
--      dois produtos; e nenhuma cobrança de 3507214 com n > 12.
--
-- REVERSÃO (uma transação; nada se apaga):
--   Desligar um teto sem reverter:  update fin.assinatura_teto set ativo = false where produto_id = '<id>';
--   Reverter de verdade:
--   begin;
--   -- a) recolocar o corpo da z61 em fin.cobrancas_previstas (20260928z61 linhas 132–252, create or replace; a ACL é
--   --    preservada pelo replace);
--   alter table fin.assinatura_teto rename to assinatura_teto_arquivada_z65;
--   commit;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_oid oid := to_regprocedure('fin.cobrancas_previstas(timestamptz,date)');
  v_src text;
  v_res text;
  e_src text := $esperado$
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
  -- teto de cobranças por assinatura: meses entre (corte − atraso máximo) e o horizonte, com folga de 2
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
    select t.email, t.oferta_codigo, t.produto_id, t.produto_nome, t.familia, t.oferta_modo, t.grupo,
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
           max(x.parcelas) filter (where x.oferta_modo <> 'UNIQUE_PAYMENT') parcelas
      from tx x
     group by x.email, x.oferta_codigo
  ), c2 as materialized (
    select c.email, c.oferta_codigo, c.n_ult, c.d_ult, c.valor_ult, c.nome, c.produto_nome, c.d1, c.parcelas,
           case when c.modo = 'SUBSCRIPTION' then 'assinatura' else 'parcelado' end tipo,
           case when c.modo = 'SUBSCRIPTION' then c.n_ult else c.n_max end n_base,
           case when c.modo = 'SUBSCRIPTION' and c.produto_id = '1462643' then 'Assinaturas Serviço Diamante'
                when c.modo = 'SUBSCRIPTION' and c.produto_id = '3507214' then 'Assinaturas Holding - Holding Masters'
                when c.modo = 'SUBSCRIPTION' then 'Outras assinaturas'
                when c.familia = 'HM' then 'Parcelas a vencer HM'
                when c.familia = 'AURUM' then 'Parcelas a vencer Aurum'
                else 'Parcelas a vencer outros' end grupo_nome,
           fin.chave_opaca('rc:' || c.email || '|' || c.oferta_codigo) ref   -- uma vez por contrato (lê o Vault)
      from c
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
                    else c2.n_base + v_meses end) s(n)
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
         r.entra_em, r.entra_rapido, r.libera_em, r.retido
    from prev p
    left join lateral fin.recebimento(p.efetiva, p.valor_ult) r on p.sit = 'a_receber'
  union all
  select f.grupo_nome, f.tipo, f.ref, fin.nome_proprio(f.nome), f.produto_nome, f.n_pago, f.parcelas,
         case when f.d1 is not null then (f.d1 + make_interval(months => f.n_pago - 1))::date end,
         (f.d_ult + make_interval(months => f.n_pago - f.n_ult))::date,
         'realizada', null::date, f.liq_pago, null::int, null::date, null::numeric, null::date, null::numeric
    from feitas f
   order by 1, 8, 3, 6;
end $esperado$;
  e_res text := 'TABLE(grupo text, tipo text, ref text, rotulo text, produto text, n integer, parcelas integer, '
             || 'vencimento date, vencimento_b date, situacao text, data_efetiva date, valor numeric, k integer, '
             || 'entra_em date, entra_rapido numeric, libera_em date, retido numeric)';
begin
  if v_oid is null or to_regclass('fin.premissas_receber') is null or to_regclass('fin.hotmart_transacoes') is null then
    raise exception 'z65: aplicar a z61 antes (fin.cobrancas_previstas / fin.premissas_receber ausentes)';
  end if;
  if to_regclass('fin.assinatura_teto') is not null then
    raise exception 'z65: já aplicada (fin.assinatura_teto existe)';
  end if;
  if (select count(*) from pg_proc where proname = 'cobrancas_previstas' and pronamespace = 'fin'::regnamespace) <> 1 then
    raise exception 'z65: há sobrecarga viva de fin.cobrancas_previstas — conferir pg_get_function_arguments';
  end if;
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_oid;
  if regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(e_src, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_res, '\s+', '', 'g') then
    raise exception 'z65: corpo vivo de fin.cobrancas_previstas diverge da z61. Já aplicada, ou alterada fora do repo? Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_oid and l.lanname = 'plpgsql' and p.provolatile = 's' and not p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z65: atributos vivos de fin.cobrancas_previstas diferentes da z61 (plpgsql/stable/invoker/search_path vazio)';
  end if;
end $guarda$;


-- ─── 1. Teto por produto ────────────────────────────────────────────────────────────────────────────────────────────
create table fin.assinatura_teto (
  produto_id    text primary key check (btrim(produto_id) <> ''),
  max_cobrancas int  not null check (max_cobrancas between 1 and 120),
  ativo         boolean not null default true,
  fonte         text not null check (btrim(fonte) <> ''),
  criado_em     timestamptz not null default now()
);
comment on table fin.assinatura_teto is
  'Contas a Receber (z65): nº máximo de cobranças do plano de ASSINATURA por produto Hotmart. Produto fora da tabela (ou ativo = false) = sem teto. Desligar: ativo = false (não apagar).';
alter table fin.assinatura_teto enable row level security;
revoke all on fin.assinatura_teto from public, anon, authenticated;

do $carga$
declare
  v_ids  text[];
  v_bad  text;
begin
  -- "Aurum - A": nome EXATO no espelho → exatamente 1 produto_id
  select array_agg(distinct t.produto_id order by t.produto_id) into v_ids
    from fin.hotmart_transacoes t where t.produto_nome = 'Aurum - A';
  if coalesce(cardinality(v_ids), 0) <> 1 then
    raise exception 'z65: produto_nome "Aurum - A" resolve para % produto_id(s) no espelho (%); esperado exatamente 1',
      coalesce(cardinality(v_ids), 0), coalesce(array_to_string(v_ids, ', '), '∅');
  end if;
  if v_ids[1] = '3507214' then
    raise exception 'z65: "Aurum - A" resolveu para 3507214 (Holding - Holding Masters) — conferir';
  end if;

  insert into fin.assinatura_teto (produto_id, max_cobrancas, fonte) values
    ('3507214', 12, 'Holding - Holding Masters: plano de até 12 cobranças (confirmado 28/09/2026); espelho max(recorrencia) = 12 em 168 pessoas'),
    (v_ids[1],  12, 'Aurum - A: espelho max(recorrencia) = 12 em 28 pessoas (28/09/2026)');

  -- o teto não pode contradizer o dado: cada produto tem assinatura paga no espelho e nenhuma paga acima do teto
  select string_agg(format('%s (teto %s, pagas %s, max rec %s)', a.produto_id, a.max_cobrancas, coalesce(m.n, 0),
                           coalesce(m.mx::text, '∅')), '; ')
    into v_bad
    from fin.assinatura_teto a
    left join lateral (
      select count(*) n, max(t.recorrencia) mx from fin.hotmart_transacoes t
       where t.produto_id = a.produto_id and t.oferta_modo = 'SUBSCRIPTION'
         and t.status in ('APPROVED','COMPLETE') and t.recorrencia is not null
    ) m on true
   where coalesce(m.n, 0) = 0 or m.mx > a.max_cobrancas;
  if v_bad is not null then
    raise exception 'z65: teto contradiz o espelho: %', v_bad;
  end if;
  raise notice 'z65: teto 12 em 3507214 e em % (Aurum - A)', v_ids[1];
end $carga$;


-- ─── 2. Foto ANTES (corpo da z61) para a conferência ────────────────────────────────────────────────────────────────
create temp table z65_antes as
  select 'passado'::text foto, c.*
    from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
  union all
  select 'agora'::text, c.*
    from fin.cobrancas_previstas(now(), (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                                         + interval '4 months' - interval '1 day')::date) c;


-- ─── 3. Bloco 2 com teto ────────────────────────────────────────────────────────────────────────────────────────────
create or replace function fin.cobrancas_previstas(p_corte timestamptz, p_ate date)
returns table (
  grupo text, tipo text, ref text, rotulo text, produto text, n int, parcelas int,
  vencimento date, vencimento_b date, situacao text, data_efetiva date, valor numeric, k int,
  entra_em date, entra_rapido numeric, libera_em date, retido numeric)
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
    select t.email, t.oferta_codigo, t.produto_id, t.produto_nome, t.familia, t.oferta_modo, t.grupo,
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
           max(x.parcelas) filter (where x.oferta_modo <> 'UNIQUE_PAYMENT') parcelas
      from tx x
     group by x.email, x.oferta_codigo
  ), c2 as materialized (
    select c.email, c.oferta_codigo, c.n_ult, c.d_ult, c.valor_ult, c.nome, c.produto_nome, c.d1, c.parcelas,
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
         r.entra_em, r.entra_rapido, r.libera_em, r.retido
    from prev p
    left join lateral fin.recebimento(p.efetiva, p.valor_ult) r on p.sit = 'a_receber'
  union all
  select f.grupo_nome, f.tipo, f.ref, fin.nome_proprio(f.nome), f.produto_nome, f.n_pago, f.parcelas,
         case when f.d1 is not null then (f.d1 + make_interval(months => f.n_pago - 1))::date end,
         (f.d_ult + make_interval(months => f.n_pago - f.n_ult))::date,
         'realizada', null::date, f.liq_pago, null::int, null::date, null::numeric, null::date, null::numeric
    from feitas f
   order by 1, 8, 3, 6;
end $$;
comment on function fin.cobrancas_previstas(timestamptz, date) is
  'Contas a Receber bloco 2 (z61; teto de assinatura z65): cobranças recorrentes previstas (assinatura/parcelado Hotmart) por contrato e-mail|oferta. Assinatura de produto em fin.assinatura_teto (ativo) para em max_cobrancas.';
revoke all on function fin.cobrancas_previstas(timestamptz, date) from public, anon, authenticated;


-- ─── 4. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
create temp table z65_depois as
  select 'passado'::text foto, c.*
    from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
  union all
  select 'agora'::text, c.*
    from fin.cobrancas_previstas(now(), (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                                         + interval '4 months' - interval '1 day')::date) c;

do $chk$
declare
  v_nomes  text[];
  v_novas  int;
  v_fora   int;
  v_resumo text;
begin
  -- nomes (no espelho) dos produtos com teto — é o que sai na coluna "produto"
  select array_agg(distinct t.produto_nome) into v_nomes
    from fin.hotmart_transacoes t join fin.assinatura_teto a on a.produto_id = t.produto_id
   where t.produto_nome is not null;

  -- (a) nada novo: o teto só tira
  select count(*) into v_novas from (select * from z65_depois except all select * from z65_antes) x;
  if v_novas > 0 then
    raise exception 'z65: % linha(s) na saída nova que não existiam na z61', v_novas;
  end if;

  -- (b) o que saiu é só cobrança NÃO realizada de assinatura com n > 12 dos produtos com teto
  select count(*) into v_fora
    from (select * from z65_antes except all select * from z65_depois) x
   where not (x.situacao <> 'realizada' and x.tipo = 'assinatura' and x.n > 12
              and (x.grupo = 'Assinaturas Holding - Holding Masters' or x.produto = any(v_nomes)));
  if v_fora > 0 then
    raise exception 'z65: % linha(s) removidas fora da regra do teto', v_fora;
  end if;

  -- (c) nenhuma cobrança prevista de 3507214 (ou de Aurum - A) com n > 12
  if exists (select 1 from z65_depois d
              where d.situacao <> 'realizada' and d.tipo = 'assinatura' and d.n > 12
                and (d.grupo = 'Assinaturas Holding - Holding Masters' or d.produto = any(v_nomes))) then
    raise exception 'z65: ainda há cobrança prevista com n > 12 em produto com teto';
  end if;

  select string_agg(format('%s/%s: -%s cobr. -R$ %s', x.foto, x.grupo, x.n, x.v), '; ' order by x.foto, x.grupo)
    into v_resumo
    from (select a.foto, a.grupo, count(*) n, round(sum(a.valor), 2) v
            from (select * from z65_antes except all select * from z65_depois) a group by 1, 2) x;
  raise notice 'z65: removidas pelo teto → %', coalesce(v_resumo, 'nenhuma');

  -- grants
  if has_table_privilege('anon', 'fin.assinatura_teto', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'fin.assinatura_teto', 'select,insert,update,delete,truncate,references,trigger')
     or has_function_privilege('anon', 'fin.cobrancas_previstas(timestamptz,date)', 'execute')
     or has_function_privilege('authenticated', 'fin.cobrancas_previstas(timestamptz,date)', 'execute') then
    raise exception 'z65: grant aberto demais (conferir relacl/proacl)';
  end if;
  if exists (select 1 from pg_proc p, unnest(coalesce(p.proacl, '{=X/postgres}'::aclitem[])) ac
              where p.oid = 'fin.cobrancas_previstas(timestamptz,date)'::regprocedure and ac::text like '=%')
     or exists (select 1 from pg_class c, unnest(coalesce(c.relacl, '{}'::aclitem[])) ac
                 where c.oid = 'fin.assinatura_teto'::regclass and ac::text like '=%') then
    raise exception 'z65: EXECUTE/privilégio para PUBLIC';
  end if;
end $chk$;

drop table z65_antes;
drop table z65_depois;


-- ═══ PROVAS (rodar como postgres; D* e A* são leitura; E* são explain de SELECT) ═════════════════════════════════════
-- explain: rodar 2× e usar a 2ª (1ª é cache frio). <UUID_FINANCEIRO> = perfis.id ativo que VÊ o financeiro.
/*
-- D1) ANTES de aplicar — o bruto_json traz o nº máximo de cobranças do plano? Lista TODOS os caminhos-folha do bruto_json
--     das 30 assinaturas pagas mais recentes de 3507214 e de "Aurum - A", com um exemplo de valor. Procurar chave com
--     plan / charge / cycle / max / recurrency / subscription. Achou? mandar ao Victor (migration nova lê o campo).
with recursive s as (
  select t.bruto_json j from fin.hotmart_transacoes t
   where t.oferta_modo = 'SUBSCRIPTION' and t.status in ('APPROVED','COMPLETE')
     and (t.produto_id = '3507214' or t.produto_nome = 'Aurum - A')
   order by t.aprovado_em desc nulls last limit 30
), p(caminho, v) as (
  select '{}'::text[], s.j from s
  union all
  select p.caminho || e.key, e.value
    from p cross join lateral jsonb_each(case when jsonb_typeof(p.v) = 'object' then p.v else '{}'::jsonb end) e
)
select array_to_string(p.caminho, '.') caminho, count(*) n, min(left(p.v::text, 60)) exemplo
  from p where jsonb_typeof(p.v) <> 'object'
 group by 1 order by 1;

-- D2) id de "Aurum - A" e conferência de 3507214 (a migration resolve por nome exato e aborta se ≠ 1 produto_id).
select t.produto_id, t.produto_nome, t.oferta_modo, count(*) transacoes,
       count(distinct lower(trim(t.comprador_email))) pessoas,
       max(t.recorrencia) filter (where t.status in ('APPROVED','COMPLETE')) max_rec_paga
  from fin.hotmart_transacoes t
 where t.produto_nome in ('Aurum - A', 'Holding - Holding Masters') or t.produto_id = '3507214'
 group by 1, 2, 3 order by 1, 2, 3;

-- D3) Outros produtos de ASSINATURA com cara de plano fechado (max recorrência baixa e muitas pessoas no máximo) —
--     candidatos a entrar em fin.assinatura_teto. Só leitura; decisão é do financeiro.
with m as (
  select t.produto_id, t.produto_nome, lower(trim(t.comprador_email)) e, max(t.recorrencia) r
    from fin.hotmart_transacoes t
   where t.oferta_modo = 'SUBSCRIPTION' and t.status in ('APPROVED','COMPLETE') and t.recorrencia is not null
   group by 1, 2, 3
), mx as (
  select m.*, max(m.r) over (partition by m.produto_id) rmax from m
)
select mx.produto_id, mx.produto_nome, count(*) pessoas, max(mx.rmax) max_rec,
       count(*) filter (where mx.r = mx.rmax) pessoas_no_max
  from mx group by 1, 2 order by 1, 2;

-- A1) DEPOIS — contagem por grupo (mesma query do CONF-25/09 da z61). ANTES (medido 28/09): "Assinaturas Holding -
--     Holding Masters" 45 cobranças / 14 contratos / R$ 86.286. Planilha: HHM 32 linhas / R$ 66 mil; Outras
--     assinaturas 3 / R$ 4 mil (só Gestão de Tráfego Pago Diamante); Aurum parcelas 4 / R$ 13 mil.
select c.grupo, c.situacao, count(*) cobrancas, count(distinct c.ref) contratos, round(sum(c.valor), 2) bruto
  from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
 group by rollup (1, 2) order by 1, 2;

-- A2) DEPOIS — assinaturas projetadas com n > 12, por produto. Esperado: só "Serviço Diamante" (sem teto).
select c.grupo, c.produto, min(c.n) n_min, max(c.n) n_max, count(*) cobrancas
  from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
 where c.situacao <> 'realizada' and c.tipo = 'assinatura' and c.n > 12
 group by 1, 2 order by 1, 2;

-- A3) DEPOIS — "Outras assinaturas" por produto (planilha: só Gestão de Tráfego Pago Diamante, 3 / R$ 4.259).
select c.produto, c.situacao, count(*) cobrancas, round(sum(c.valor), 2) bruto, min(c.n), max(c.n)
  from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
 where c.grupo = 'Outras assinaturas' and c.situacao <> 'realizada'
 group by 1, 2 order by 1, 2;

-- E3') Corpo do bloco 2 COM o teto. $1 corte · $2 horizonte · $3 tolerância (5) · $4 atraso máximo (35) · $5 v_meses.
--     Esperado: igual ao E3 da z61 (universo por hotmart_transacoes_aprovado_pago_idx; história por
--     hotmart_transacoes_contrato_rec_idx) + Hash/Nested Loop Left Join com fin.assinatura_teto (2 linhas). Seq Scan em
--     hotmart_transacoes = índice ignorado → avisar o Victor. Tempo ≈ o do E3 da z61 (a tabela nova tem 2 linhas).
deallocate all;
prepare b2t(timestamptz, date, int, int, int) as
  with ativos as (
    select distinct t.email, t.oferta_codigo
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em > $1 - interval '120 days' and t.aprovado_em <= $1
       and t.recorrencia is not null
       and (t.oferta_modo = 'SUBSCRIPTION' or t.oferta_modo = 'MULTIPLE_PAYMENTS'
            or t.oferta_modo like 'HOTMART_INSTALLMENTS%')
       and t.email is not null and t.oferta_codigo is not null
  ), tx as materialized (
    select t.email, t.oferta_codigo, t.produto_id, t.produto_nome, t.familia, t.oferta_modo, t.grupo,
           t.recorrencia, t.parcelas, t.liquido, t.aprovado_em, t.dia_aprovado, t.dia_pedido, t.nome,
           (t.grupo = 'pago' and t.aprovado_em <= $1) pago
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
           max(x.parcelas) filter (where x.oferta_modo <> 'UNIQUE_PAYMENT') parcelas
      from tx x
     group by x.email, x.oferta_codigo
  ), c2 as materialized (
    select c.email, c.oferta_codigo, c.n_ult, c.d_ult, c.valor_ult, c.nome, c.produto_nome, c.d1, c.parcelas,
           case when c.modo = 'SUBSCRIPTION' then 'assinatura' else 'parcelado' end tipo,
           case when c.modo = 'SUBSCRIPTION' then c.n_ult else c.n_max end n_base,
           case when c.modo = 'SUBSCRIPTION' and c.produto_id = '1462643' then 'Assinaturas Serviço Diamante'
                when c.modo = 'SUBSCRIPTION' and c.produto_id = '3507214' then 'Assinaturas Holding - Holding Masters'
                when c.modo = 'SUBSCRIPTION' then 'Outras assinaturas'
                when c.familia = 'HM' then 'Parcelas a vencer HM'
                when c.familia = 'AURUM' then 'Parcelas a vencer Aurum'
                else 'Parcelas a vencer outros' end grupo_nome,
           ta.max_cobrancas teto,
           fin.chave_opaca('rc:' || c.email || '|' || c.oferta_codigo) ref
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
               case when c2.tipo = 'parcelado' then least(c2.parcelas, c2.n_base + $5)
                    else least(c2.teto, c2.n_base + $5) end) s(n)
  ), vivos as (
    select g.ref from g where g.n = g.n_base + 1 and g.venc >= ($1 at time zone 'America/Sao_Paulo')::date - $4
  ), prev as (
    select g.*,
           case when g.venc + $3 < ($1 at time zone 'America/Sao_Paulo')::date then 'em_atraso_fora' else 'a_receber' end sit,
           case when g.venc + $3 < ($1 at time zone 'America/Sao_Paulo')::date then null::date
                else greatest(g.venc, ($1 at time zone 'America/Sao_Paulo')::date + 1) end efetiva
      from g
     where g.ref in (select vivos.ref from vivos)
       and g.venc <= $2 and g.venc >= ($1 at time zone 'America/Sao_Paulo')::date - $4
  )
  select p.grupo_nome, p.sit, p.efetiva, p.valor_ult, r.entra_em, r.entra_rapido, r.libera_em, r.retido
    from prev p
    left join lateral fin.recebimento(p.efetiva, p.valor_ult) r on p.sit = 'a_receber';
explain (analyze, buffers) execute b2t(timestamptz '2026-09-25 23:59:59-03', date '2026-12-31', 5, 35, 6);   -- $5 = v_meses (ago→dez + 2)
explain (analyze, buffers) execute b2t(now(), (date_trunc('month', current_date) + interval '4 months' - interval '1 day')::date, 5, 35, 6);

-- E5') A RPC inteira (a tela chama esta), com o usuário do Financeiro. Teto da z61: ≤ 300 ms (2ª execução).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31');
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
rollback;
*/
