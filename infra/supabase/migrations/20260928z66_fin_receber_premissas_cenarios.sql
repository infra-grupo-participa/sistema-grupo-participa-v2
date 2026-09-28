-- 20260928z66 — Contas a Receber, fatia F2: premissas editáveis com vigência, perda composta, cenários e contrato v2
--               de public.fn_fin_receber_semanal.
--
-- APLICADA em produção em 28/09/2026 (conferência 8.1–8.8 verde). Faixa máx. de perda e de conciliação reduzida de 50% para 20% (achado do Kirad). Medido: RPC 204–233 ms quente, 551 linhas, 534 KB.
-- Ordem obrigatória: z63 (informados) → z64 (feriados) → z65 (já aplicada) → z66. Guarda: o corpo VIVO de
-- public.fn_fin_receber_semanal tem que ser o da z63 e o de fin.cobrancas_previstas o da z65 (comparação sem espaço,
-- sem comentário e SEM o texto das mensagens de "raise exception": a z65 foi aplicada com mensagens encurtadas).
-- A migration inteira é UMA transação (apply_migration): o drop + create da RPC não deixa janela sem função.
--
-- O que faz:
--   1) fin.premissas_receber_catalogo (chave, rotulo, unidade, minimo, maximo, grupo_tela, ajuda, aceita_cenario):
--      o que pode ser editado e em que faixa. Só migration mexe no catálogo.
--   2) fin.premissas_receber ganha criado_por, chave_base e cenario (as duas últimas GERADAS da chave: 'x' = base,
--      'x@conservador', 'x@otimista'); FK chave_base → catálogo; CHECK do formato da chave. Vigências só-acréscimo:
--      trigger barra UPDATE, DELETE e TRUNCATE; trigger BEFORE INSERT valida faixa, inteiro (dias, liga/desliga) e
--      cenário só em chave que aceita cenário — vale para qualquer caminho de escrita, não só a RPC.
--      Carga: perda_mensal:<grupo> vigente desde 2000-01-01 (mesma convenção da z61: corte no passado reproduz a regra):
--        servico_diamante 5% · holding_hm 10% · outras_assinaturas 10% · parcelas_hm 5% · parcelas_aurum 5% ·
--        parcelas_outros 5% · informados 0% (decisão de 28/09). Nenhuma chave @conservador/@otimista é carregada: a
--        planilha não tem perda por cenário, então os três cenários saem iguais até o Financeiro gravar uma.
--   3) fin.premissa(chave, dia, cenario) — ÚNICA leitura de premissa com cenário: vigente em `dia` da chave
--      'chave@cenario'; sem ela, a da base. fin.receber_pct(numeric) — '0,05' → '5%' (texto do tratamento).
--   4) fin.cobrancas_previstas: drop + create com a coluna NOVA no fim `detalhe jsonb` = transações PAGAS do contrato
--      até o corte [{transacao, n, dia, liquido}] (sem e-mail, sem documento, sem nome). Resto idêntico à z65
--      (conferência 8.4 prova linha a linha). Motivo: o e-mail do contrato só existe aqui; montar o detalhe fora
--      exigiria recalcular fin.chave_opaca (1 leitura do Vault por contrato) uma segunda vez.
--   5) fin.receber_posicao(corte, ate, cenario) — interna (invoker, search_path ''), o corpo da previsão (z63) +
--      colunas novas. É o que o cron da F4 vai chamar (sem auth.uid).
--   6) public.fn_fin_receber_semanal(p_corte, p_ate, p_cenario default 'base') — drop + create; só guarda e leitura.
--      Colunas 1–12 com os MESMOS nomes, tipos e ordem; novas NO FIM. valor passa a ser o ESPERADO.
--   7) RPCs: fn_fin_premissas_receber_listar() (leitura), fn_fin_premissa_receber_salvar(...) (escrita),
--      fn_fin_feriados_listar() (leitura).
--
-- CONTRATO v2 de public.fn_fin_receber_semanal(p_corte timestamptz default null, p_ate date default null,
--                                              p_cenario text default 'base'):
--   bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text, origem_dia date,
--   ref text, rotulo text, produto text, k int, detalhe jsonb,               ← mesmos da z61/z63
--   valor_bruto numeric, fator numeric, certeza text, centro_custo text, tratamento text, cenario text  ← novas
--   valor       = ESPERADO = round(valor_bruto × fator, 2) (fator = 1 → valor = valor_bruto exato).
--   valor_bruto = o valor de antes (z63).
--   fator       = (1 − perda_mensal)^k só em situacao 'a_receber' dos blocos 2 e 5; 1 no resto.
--                 k = meses à frente pela data efetiva (mês do corte = 1). No bloco 5 o k é interno (a coluna k
--                 continua NULL, como na z63).
--   certeza     = 'certo' (blocos 1, 2, 5). 'estimado' fica reservado aos blocos 3, 4, 6 (F3).
--   centro_custo= '1. Receita de vendas (Hotmart)' (blocos 1, 2; bloco 5 via Hotmart) |
--                 '4. Receita de vendas (Direta de clientes)' (bloco 5 fora da Hotmart) | '3. (Devoluções)' (F3).
--   tratamento  = texto curto do porquê, partes separadas por ' · '.
--   cenario     = o cenário pedido ('base' | 'conservador' | 'otimista'); outro valor → 22023.
--   detalhe     = bloco 1: [{transacao, produto, nome, liquido}] (z61); bloco 2: [{transacao, n, dia, liquido}] das
--                 pagas do contrato até o corte (NOVO), na linha 'antecipacao' ou 'cheio' da cobrança — a linha
--                 'garantia' da mesma cobrança traz NULL (metade dos bytes); bloco 5: NULL.
--   Soma de caixa: só situacao = 'a_receber' (inalterado).
--
-- 5 perguntas:
--   escala: o mesmo universo da z63 + 1 multiplicação por linha + 7 leituras de premissa por chamada (PK) + 1 jsonb_agg
--           por contrato (sobre a CTE tx que já existia). premissas_receber: dezenas de linhas por ano.
--   índice: leituras de premissa pela PK (chave, vigente_de); nenhum filtro novo em hotmart_transacoes.
--   frequência: a mesma RPC da aba; premissa só quando alguém edita.
--   repetição: perda, cenário, centro de custo e tratamento só no SQL; o TS só exibe.
--   reversão: ver abaixo.
--
-- REVERSÃO (uma transação; nada se apaga):
--   Desligar a perda sem reverter (por grupo, via tela ou SQL):
--     select * from public.fn_fin_premissa_receber_salvar('perda_mensal:holding_hm', 0, current_date, 'base');
--   Reverter de verdade:
--   begin;
--   drop function public.fn_fin_receber_semanal(timestamptz, date, text);
--   -- a) recriar public.fn_fin_receber_semanal(timestamptz, date) com o corpo da z63 (20260928z63 linhas 940–1030,
--   --    create function + revoke public, anon + grant authenticated);
--   drop function fin.receber_posicao(timestamptz, date, text);
--   drop function fin.cobrancas_previstas(timestamptz, date);
--   -- b) recriar fin.cobrancas_previstas com o corpo da z65 (20260928z65 linhas 254–381, create function + revoke);
--   drop function public.fn_fin_premissas_receber_listar();
--   drop function public.fn_fin_premissa_receber_salvar(text, numeric, date, text);
--   drop function public.fn_fin_feriados_listar();
--   alter table fin.premissas_receber drop constraint premissas_receber_chave_base_fk;
--   alter table fin.premissas_receber_catalogo rename to premissas_receber_catalogo_arquivada_z66;
--   -- (as linhas perda_mensal:* e x@cenario ficam; nenhum leitor antigo as lê. Os triggers só-acréscimo ficam.)
--   commit;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_rpc  oid := to_regprocedure('public.fn_fin_receber_semanal(timestamptz,date)');
  v_cob  oid := to_regprocedure('fin.cobrancas_previstas(timestamptz,date)');
  v_src  text;
  v_res  text;
  v_fora text;
  e_rpc  text := $esperado$
#variable_conflict use_column
declare
  v_corte timestamptz := coalesce(p_corte, now());
  v_dia   date := (coalesce(p_corte, now()) at time zone 'America/Sao_Paulo')::date;
  v_ate   date;
  v_max   int;
  v_inf   boolean;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  v_ate := coalesce(p_ate, (date_trunc('month', v_dia::timestamp) + interval '4 months' - interval '1 day')::date);
  if v_ate < v_dia or v_ate > v_dia + 400 then
    raise exception 'Horizonte fora do intervalo (do corte até 400 dias depois).' using errcode = '22023';
  end if;
  select pr.valor::int into v_max from fin.premissas_receber pr
   where pr.chave = 'atraso_max_projetado_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  select pr.valor > 0 into v_inf from fin.premissas_receber pr
   where pr.chave = 'informados_no_receber' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_max is null or v_inf is null then
    raise exception 'Premissa do contas a receber ausente (atraso_max_projetado_dias / informados_no_receber).'
      using errcode = 'P0002';
  end if;
  return query
  with cob as materialized (
    select cb.ref, cb.de, cb.ate from fin.informados_cobertura(v_corte) cb where v_inf
  ), b2 as (
    select c.grupo, c.vencimento, c.ref, c.rotulo, c.produto, c.k, c.valor, c.entra_em, c.entra_rapido,
           c.libera_em, c.retido,
           case when c.situacao in ('a_receber','em_atraso_fora')
                     and exists (select 1 from cob where cob.ref = c.ref and c.vencimento between cob.de and cob.ate)
                then 'coberta_informado' else c.situacao end sit
      from fin.cobrancas_previstas(v_corte, v_ate) c
  ), inf as materialized (
    select r.id, r.tipo, r.cliente, r.produtos, r.via_hotmart, r.data_prevista, r.valor,
           s.situacao sit, s.valor_provisionado prov, s.data_efetiva efetiva
      from fin.informados_situacao(v_corte) s
      join fin.recebimentos_informados r on r.id = s.id
     where v_inf and s.situacao <> 'arquivado' and r.data_prevista <= v_ate
       and (s.situacao = 'a_receber' or r.data_prevista >= v_dia - v_max)
  )
  select 1::smallint, 'Vendas já realizadas'::text, b.componente, b.data_caixa, b.valor, 'a_receber'::text,
         b.origem_dia, null::text, null::text, null::text, null::int, b.detalhe
    from fin.receber_vendas_realizadas(v_corte) b
  union all
  select 2::smallint, c.grupo, u.componente, u.data_caixa, u.valor, c.sit, c.vencimento,
         c.ref, c.rotulo, c.produto, c.k, null::jsonb
    from b2 c
    cross join lateral (
      select 'antecipacao'::text, c.entra_em, c.entra_rapido where c.sit = 'a_receber'
      union all
      select 'garantia'::text, c.libera_em, c.retido where c.sit = 'a_receber'
      union all
      select 'cheio'::text, null::date, c.valor where c.sit <> 'a_receber'
    ) u(componente, data_caixa, valor)
  union all
  select 5::smallint,
         case i.tipo when 'renovacao_diamante' then 'Renovações Diamante'
                     when 'renovacao_aurum'    then 'Renovações Aurum'
                     when 'diamante_extra'     then 'Serviço Diamante extras'
                     else 'Outros recebimentos informados' end,
         u.componente, u.data_caixa, u.valor, u.sit, i.data_prevista,
         i.id::text, i.cliente, i.produtos[1], null::int, null::jsonb
    from inf i
    left join lateral fin.recebimento(i.efetiva, i.prov) f on i.via_hotmart and i.sit = 'a_receber'
    cross join lateral (
      select 'antecipacao'::text, f.entra_em, f.entra_rapido, 'a_receber'::text
       where i.via_hotmart and i.sit = 'a_receber'
      union all
      select 'garantia'::text, f.libera_em, f.retido, 'a_receber'::text
       where i.via_hotmart and i.sit = 'a_receber'
      union all
      select 'cheio'::text, i.efetiva, i.prov, 'a_receber'::text
       where not i.via_hotmart and i.sit = 'a_receber'
      union all
      select 'cheio'::text, null::date, i.prov, 'em_atraso_fora'::text
       where i.sit = 'em_atraso_cobrar'
      union all
      select 'cheio'::text, null::date, i.valor::numeric, 'realizada'::text
       where i.sit in ('realizado_hotmart','baixado_fora')
    ) u(componente, data_caixa, valor, sit)
   order by 1, 4 nulls last, 2, 3;
end $esperado$;
  e_rpc_res text := 'TABLE(bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text, '
                 || 'origem_dia date, ref text, rotulo text, produto text, k integer, detalhe jsonb)';
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
end $esperado$;
  e_cob_res text := 'TABLE(grupo text, tipo text, ref text, rotulo text, produto text, n integer, parcelas integer, '
                 || 'vencimento date, vencimento_b date, situacao text, data_efetiva date, valor numeric, k integer, '
                 || 'entra_em date, entra_rapido numeric, libera_em date, retido numeric)';
begin
  if to_regclass('fin.premissas_receber_catalogo') is not null
     or to_regprocedure('fin.receber_posicao(timestamptz,date,text)') is not null
     or to_regprocedure('fin.premissa(text,date,text)') is not null
     or exists (select 1 from information_schema.columns
                 where table_schema = 'fin' and table_name = 'premissas_receber' and column_name = 'criado_por') then
    raise exception 'z66: já aplicada (catálogo, fin.receber_posicao, fin.premissa ou criado_por existe)';
  end if;
  if v_rpc is null or v_cob is null or to_regclass('fin.premissas_receber') is null
     or to_regclass('fin.recebimentos_informados') is null
     or to_regprocedure('fin.informados_situacao(timestamptz)') is null
     or to_regprocedure('fin.informados_cobertura(timestamptz)') is null then
    raise exception 'z66: aplicar a z63 antes (fn_fin_receber_semanal(timestamptz,date) / recebimentos informados ausentes)';
  end if;
  if to_regclass('fin.assinatura_teto') is null then
    raise exception 'z66: aplicar a z65 antes (fin.assinatura_teto ausente)';
  end if;
  if to_regclass('fin.feriados_bancarios_log') is null then
    raise exception 'z66: aplicar a z64 antes (fin.feriados_bancarios_log ausente)';
  end if;
  if (select count(*) from pg_proc where proname = 'fn_fin_receber_semanal' and pronamespace = 'public'::regnamespace) <> 1
     or (select count(*) from pg_proc where proname = 'cobrancas_previstas' and pronamespace = 'fin'::regnamespace) <> 1 then
    raise exception 'z66: sobrecarga viva de fn_fin_receber_semanal ou fin.cobrancas_previstas — conferir pg_get_function_arguments';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('fn_fin_premissas_receber_listar','fn_fin_premissa_receber_salvar','fn_fin_feriados_listar')) then
    raise exception 'z66: RPC de premissas/feriados já existe — conferir';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'perfis' and column_name = 'nome') then
    raise exception 'z66: public.perfis.nome ausente (a listagem mostra quem gravou)';
  end if;

  -- corpo vivo = repo, sem espaço, sem comentário e sem o texto das mensagens de erro
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_rpc;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_rpc, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_rpc_res, '\s+', '', 'g') then
    raise exception 'z66: corpo vivo de fn_fin_receber_semanal diverge da z63. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_rpc and l.lanname = 'plpgsql' and p.provolatile = 's' and p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z66: atributos vivos de fn_fin_receber_semanal diferentes da z63 (plpgsql/stable/definer/search_path vazio)';
  end if;
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_cob;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_cob, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_cob_res, '\s+', '', 'g') then
    raise exception 'z66: corpo vivo de fin.cobrancas_previstas diverge da z65. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_cob and l.lanname = 'plpgsql' and p.provolatile = 's' and not p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z66: atributos vivos de fin.cobrancas_previstas diferentes da z65 (plpgsql/stable/invoker/search_path vazio)';
  end if;

  -- toda chave viva tem que caber no catálogo (a FK abaixo abortaria sem dizer qual)
  select string_agg(distinct pr.chave, ', ') into v_fora
    from fin.premissas_receber pr
   where pr.chave not in ('tolerancia_atraso_dias','tolerancia_conciliacao','atraso_max_projetado_dias',
                          'informados_no_receber');
  if v_fora is not null then
    raise exception 'z66: fin.premissas_receber tem chave fora do catálogo novo: % — incluir no catálogo antes', v_fora;
  end if;
end $guarda$;


-- ─── 1. Foto ANTES (corpo da z63, como admin) para a conferência 8.4 ────────────────────────────────────────────────
do $foto$
declare
  v_adm uuid;
  v_ate date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                 + interval '4 months' - interval '1 day')::date;
begin
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z66: nenhum perfil admin ativo para a foto da RPC'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  create temp table z66_antes on commit drop as
    select 'passado'::text foto, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31') x
    union all
    select 'agora'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate) x;
  create temp table z66_cob_antes on commit drop as
    select 'passado'::text foto, c.* from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
    union all
    select 'agora'::text, c.* from fin.cobrancas_previstas(now(), v_ate) c;
  perform set_config('request.jwt.claims', '', true);
end $foto$;


-- ─── 2. Catálogo e premissas só-acréscimo ───────────────────────────────────────────────────────────────────────────
create table fin.premissas_receber_catalogo (
  chave          text primary key check (chave ~ '^[a-z_]+(:[a-z_]+)?$'),
  rotulo         text not null check (btrim(rotulo) <> '' and length(rotulo) <= 120),
  unidade        text not null check (unidade in ('dias','percentual','liga_desliga')),
  minimo         numeric not null,
  maximo         numeric not null,
  grupo_tela     text not null check (btrim(grupo_tela) <> ''),
  ajuda          text not null check (btrim(ajuda) <> ''),
  aceita_cenario boolean not null default false,
  check (minimo <= maximo)
);
comment on table fin.premissas_receber_catalogo is
  'Contas a Receber (z66): premissas editáveis, faixa e texto de ajuda. percentual é guardado como fração (0,05 = 5%). '
  'aceita_cenario = pode ter vigência própria em x@conservador / x@otimista. Só migration altera.';
alter table fin.premissas_receber_catalogo enable row level security;
revoke all on fin.premissas_receber_catalogo from public, anon, authenticated;

insert into fin.premissas_receber_catalogo (chave, rotulo, unidade, minimo, maximo, grupo_tela, ajuda, aceita_cenario) values
  ('tolerancia_atraso_dias', 'Tolerância de atraso', 'dias', 0, 30, 'Recorrências e informados',
   'Cobrança vencida há até este número de dias continua na previsão e entra no dia seguinte ao corte. Passou disso, sai da projeção como "em atraso".', false),
  ('atraso_max_projetado_dias', 'Atraso máximo listado', 'dias', 0, 120, 'Recorrências e informados',
   'Contrato cuja cobrança em aberto venceu há mais que este número de dias sai inteiro da lista.', false),
  ('tolerancia_conciliacao', 'Tolerância de conciliação', 'percentual', 0, 0.2, 'Recorrências e informados',
   'Recebimento informado via Hotmart conta como realizado quando o recebido chega ao acumulado do acordo menos esta tolerância.', false),
  ('informados_no_receber', 'Recebimentos informados na previsão', 'liga_desliga', 0, 1, 'Recorrências e informados',
   '1 = os recebimentos informados entram (e cobrem a recorrência do mesmo acordo); 0 = desliga, sem deploy.', false),
  ('perda_mensal:servico_diamante', 'Perda mensal — Assinaturas Serviço Diamante', 'percentual', 0, 0.2, 'Perda por inadimplência',
   'Esperado = valor × (1 − perda)^k, k = meses à frente (mês do corte = 1).', true),
  ('perda_mensal:holding_hm', 'Perda mensal — Assinaturas Holding - Holding Masters', 'percentual', 0, 0.2, 'Perda por inadimplência',
   'Esperado = valor × (1 − perda)^k, k = meses à frente (mês do corte = 1).', true),
  ('perda_mensal:outras_assinaturas', 'Perda mensal — Outras assinaturas', 'percentual', 0, 0.2, 'Perda por inadimplência',
   'Esperado = valor × (1 − perda)^k, k = meses à frente (mês do corte = 1).', true),
  ('perda_mensal:parcelas_hm', 'Perda mensal — Parcelas a vencer HM', 'percentual', 0, 0.2, 'Perda por inadimplência',
   'Esperado = valor × (1 − perda)^k, k = meses à frente (mês do corte = 1).', true),
  ('perda_mensal:parcelas_aurum', 'Perda mensal — Parcelas a vencer Aurum', 'percentual', 0, 0.2, 'Perda por inadimplência',
   'Esperado = valor × (1 − perda)^k, k = meses à frente (mês do corte = 1).', true),
  ('perda_mensal:parcelas_outros', 'Perda mensal — Parcelas a vencer outros', 'percentual', 0, 0.2, 'Perda por inadimplência',
   'Esperado = valor × (1 − perda)^k, k = meses à frente (mês do corte = 1).', true),
  ('perda_mensal:informados', 'Perda mensal — Recebimentos informados', 'percentual', 0, 0.2, 'Perda por inadimplência',
   'Esperado = valor × (1 − perda)^k, k = meses à frente (mês do corte = 1). Decisão de 28/09: sem perda.', true);

alter table fin.premissas_receber
  add column criado_por uuid,
  add column chave_base text generated always as (split_part(chave, '@', 1)) stored,
  add column cenario    text generated always as (coalesce(nullif(split_part(chave, '@', 2), ''), 'base')) stored;
alter table fin.premissas_receber
  add constraint premissas_receber_chave_formato_ck
    check (chave ~ '^[a-z_]+(:[a-z_]+)?(@(conservador|otimista))?$'),
  add constraint premissas_receber_chave_base_fk
    foreign key (chave_base) references fin.premissas_receber_catalogo (chave);
comment on table fin.premissas_receber is
  'Premissas do Contas a Receber (z61; catálogo e cenários z66). Vale a última linha com vigente_de <= dia, por chave. '
  'Cenário: chave x@conservador / x@otimista; sem ela, vale a base (fin.premissa). Só acréscimo: UPDATE/DELETE barrados.';

create function fin.tg_premissas_receber_valida()
returns trigger language plpgsql set search_path = ''
as $$
declare
  c fin.premissas_receber_catalogo;
begin
  select k.* into c from fin.premissas_receber_catalogo k where k.chave = split_part(new.chave, '@', 1);
  if not found then
    raise exception 'Premissa desconhecida: %.', new.chave using errcode = '22023';
  end if;
  if position('@' in new.chave) > 0 and not c.aceita_cenario then
    raise exception 'A premissa "%" não varia por cenário.', c.rotulo using errcode = '22023';
  end if;
  if new.valor is null or new.valor < c.minimo or new.valor > c.maximo then
    raise exception 'Valor fora da faixa de "%" (% a %).', c.rotulo, c.minimo, c.maximo using errcode = '22023';
  end if;
  if c.unidade in ('dias','liga_desliga') and new.valor <> trunc(new.valor) then
    raise exception '"%" aceita só número inteiro.', c.rotulo using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function fin.tg_premissas_receber_valida() from public, anon, authenticated;

create function fin.tg_premissas_receber_so_acrescimo()
returns trigger language plpgsql set search_path = ''
as $$
begin
  raise exception 'fin.premissas_receber é só acréscimo: grave uma vigência nova.' using errcode = '42501';
end $$;
revoke all on function fin.tg_premissas_receber_so_acrescimo() from public, anon, authenticated;

create trigger premissas_receber_valida before insert on fin.premissas_receber
  for each row execute function fin.tg_premissas_receber_valida();
create trigger premissas_receber_so_acrescimo before update or delete on fin.premissas_receber
  for each row execute function fin.tg_premissas_receber_so_acrescimo();
create trigger premissas_receber_nao_trunca before truncate on fin.premissas_receber
  for each statement execute function fin.tg_premissas_receber_so_acrescimo();

insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values
  ('perda_mensal:servico_diamante',   date '2000-01-01', 0.05, 'planilha Contas a Receber Semanal, aba Premissas (decisão 28/09/2026)'),
  ('perda_mensal:holding_hm',         date '2000-01-01', 0.10, 'planilha Contas a Receber Semanal, aba Premissas (decisão 28/09/2026)'),
  ('perda_mensal:outras_assinaturas', date '2000-01-01', 0.10, 'planilha Contas a Receber Semanal, aba Premissas (decisão 28/09/2026)'),
  ('perda_mensal:parcelas_hm',        date '2000-01-01', 0.05, 'planilha Contas a Receber Semanal, aba Premissas (decisão 28/09/2026)'),
  ('perda_mensal:parcelas_aurum',     date '2000-01-01', 0.05, 'planilha Contas a Receber Semanal, aba Premissas (decisão 28/09/2026)'),
  ('perda_mensal:parcelas_outros',    date '2000-01-01', 0.05, 'planilha Contas a Receber Semanal, aba Premissas (decisão 28/09/2026)'),
  ('perda_mensal:informados',         date '2000-01-01', 0,    'decisão 28/09/2026: recebimento informado sem perda');


-- ─── 3. Leitura única de premissa + formatação ──────────────────────────────────────────────────────────────────────
create function fin.premissa(p_chave text, p_dia date, p_cenario text default 'base')
returns numeric language plpgsql stable set search_path = ''
as $$
declare
  v numeric;
begin
  if p_cenario is null or p_cenario not in ('base','conservador','otimista') then
    raise exception 'Cenário inválido (base, conservador ou otimista).' using errcode = '22023';
  end if;
  if p_cenario <> 'base' then
    select pr.valor into v from fin.premissas_receber pr
     where pr.chave = p_chave || '@' || p_cenario and pr.vigente_de <= p_dia
     order by pr.vigente_de desc limit 1;
    if found then return v; end if;
  end if;
  select pr.valor into v from fin.premissas_receber pr
   where pr.chave = p_chave and pr.vigente_de <= p_dia
   order by pr.vigente_de desc limit 1;
  return v;
end $$;
comment on function fin.premissa(text, date, text) is
  'Contas a Receber (z66): valor vigente em p_dia da premissa; cenário ≠ base usa chave@cenário e, sem ela, a base. NULL = sem premissa.';
revoke all on function fin.premissa(text, date, text) from public, anon, authenticated;

create function fin.receber_pct(p numeric)
returns text language sql immutable set search_path = ''
as $$ select replace(pg_catalog.trim_scale(pg_catalog.round(p * 100, 2))::text, '.', ',') || '%' $$;
revoke all on function fin.receber_pct(numeric) from public, anon, authenticated;


-- ─── 4. Bloco 2 com o detalhe do contrato (z65 + coluna detalhe no fim) ────────────────────────────────────────────
drop function fin.cobrancas_previstas(timestamptz, date);
create function fin.cobrancas_previstas(p_corte timestamptz, p_ate date)
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
end $$;
comment on function fin.cobrancas_previstas(timestamptz, date) is
  'Contas a Receber bloco 2 (z61; teto z65; detalhe z66): cobranças recorrentes previstas por contrato e-mail|oferta. '
  'detalhe = transações pagas do contrato até o corte [{transacao, n, dia, liquido}], sem e-mail/documento/nome.';
revoke all on function fin.cobrancas_previstas(timestamptz, date) from public, anon, authenticated;


-- ─── 5. A previsão, interna ─────────────────────────────────────────────────────────────────────────────────────────
create function fin.receber_posicao(p_corte timestamptz, p_ate date, p_cenario text)
returns table (bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text,
               origem_dia date, ref text, rotulo text, produto text, k int, detalhe jsonb,
               valor_bruto numeric, fator numeric, certeza text, centro_custo text, tratamento text, cenario text)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
declare
  v_corte timestamptz := p_corte;
  v_cen   text := p_cenario;
  v_dia   date;
  v_ate   date;
  v_max   int;
  v_tol   int;
  v_inf   boolean;
begin
  if p_corte is null then
    raise exception 'fin.receber_posicao: corte obrigatório' using errcode = '22023';
  end if;
  if v_cen is null or v_cen not in ('base','conservador','otimista') then
    raise exception 'Cenário inválido (base, conservador ou otimista).' using errcode = '22023';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  v_ate := coalesce(p_ate, (date_trunc('month', v_dia::timestamp) + interval '4 months' - interval '1 day')::date);
  if v_ate < v_dia or v_ate > v_dia + 400 then
    raise exception 'Horizonte fora do intervalo (do corte até 400 dias depois).' using errcode = '22023';
  end if;
  v_max := fin.premissa('atraso_max_projetado_dias', v_dia, 'base')::int;
  v_tol := fin.premissa('tolerancia_atraso_dias', v_dia, 'base')::int;
  v_inf := fin.premissa('informados_no_receber', v_dia, 'base') > 0;
  if v_max is null or v_tol is null or v_inf is null then
    raise exception 'Premissa do contas a receber ausente (atraso_max_projetado_dias / tolerancia_atraso_dias / informados_no_receber).'
      using errcode = 'P0002';
  end if;

  return query
  with vig as materialized (
    -- texto do caixa por vigência de fin.premissas_recebimento (as mesmas premissas de fin.recebimento)
    select pr.vigente_de de, lead(pr.vigente_de) over (order by pr.vigente_de) ate,
           'Antecipação D+' || pr.dias_ate_entrar || case when pr.dias_uteis then ' útil' else '' end
             || ' (' || fin.receber_pct(1 - pr.pct_retido) || ' − ' || fin.receber_pct(pr.taxa_antecipacao) || ')' t_ant,
           'Retido ' || fin.receber_pct(pr.pct_retido) || ' volta em D+' || pr.dias_retencao t_ret
      from fin.premissas_recebimento pr
  ), perda as materialized (
    select m.bloco, m.grupo, x.p,
           case when x.p > 0 then 'Perda ' || fin.receber_pct(x.p) || '/mês' end t_perda
      from (values (2::smallint, 'Assinaturas Serviço Diamante'::text,         'perda_mensal:servico_diamante'::text),
                   (2::smallint, 'Assinaturas Holding - Holding Masters'::text, 'perda_mensal:holding_hm'::text),
                   (2::smallint, 'Outras assinaturas'::text,                    'perda_mensal:outras_assinaturas'::text),
                   (2::smallint, 'Parcelas a vencer HM'::text,                  'perda_mensal:parcelas_hm'::text),
                   (2::smallint, 'Parcelas a vencer Aurum'::text,               'perda_mensal:parcelas_aurum'::text),
                   (2::smallint, 'Parcelas a vencer outros'::text,              'perda_mensal:parcelas_outros'::text),
                   (5::smallint, null::text,                                    'perda_mensal:informados'::text)
           ) m(bloco, grupo, chave)
      cross join lateral (select fin.premissa(m.chave, v_dia, v_cen) p) x
  ), cob as materialized (
    select cb.ref, cb.de, cb.ate from fin.informados_cobertura(v_corte) cb where v_inf
  ), b2 as (
    select c.grupo, c.vencimento, c.ref, c.rotulo, c.produto, c.k, c.valor, c.entra_em, c.entra_rapido,
           c.libera_em, c.retido, c.data_efetiva, c.detalhe,
           case when c.situacao in ('a_receber','em_atraso_fora')
                     and exists (select 1 from cob where cob.ref = c.ref and c.vencimento between cob.de and cob.ate)
                then 'coberta_informado' else c.situacao end sit
      from fin.cobrancas_previstas(v_corte, v_ate) c
  ), inf as materialized (
    select r.id, r.tipo, r.cliente, r.produtos, r.via_hotmart, r.data_prevista, r.valor,
           s.situacao sit, s.valor_provisionado prov, s.data_efetiva efetiva
      from fin.informados_situacao(v_corte) s
      join fin.recebimentos_informados r on r.id = s.id
     where v_inf and s.situacao <> 'arquivado' and r.data_prevista <= v_ate
       and (s.situacao = 'a_receber' or r.data_prevista >= v_dia - v_max)
  ), linhas as (
    select 1::smallint bl, 'Vendas já realizadas'::text gr, b.componente comp, b.data_caixa dc, b.valor bruto,
           'a_receber'::text sit, b.origem_dia od, null::text rf, null::text rot, null::text prod, null::int kk,
           b.detalhe det, b.origem_dia dia_regra, null::int k_perda, true via, null::text trat
      from fin.receber_vendas_realizadas(v_corte) b
    union all
    select 2::smallint, c.grupo, u.componente, u.data_caixa, u.valor, c.sit, c.vencimento,
           c.ref, c.rotulo, c.produto, c.k,
           case when u.componente <> 'garantia' then c.detalhe end,   -- 1× por cobrança (a garantia é a mesma cobrança)
           c.data_efetiva, c.k, true,
           case c.sit when 'em_atraso_fora'    then 'Fora da projeção: atraso > ' || v_tol || ' dias'
                      when 'realizada'         then 'Paga: sai da previsão'
                      when 'coberta_informado' then 'Coberta por recebimento informado'
                      when 'a_receber' then case when c.vencimento <= v_dia
                                                 then 'Atraso dentro da tolerância: entra no dia seguinte ao corte' end
           end
      from b2 c
      cross join lateral (
        select 'antecipacao'::text, c.entra_em, c.entra_rapido where c.sit = 'a_receber'
        union all
        select 'garantia'::text, c.libera_em, c.retido where c.sit = 'a_receber'
        union all
        select 'cheio'::text, null::date, c.valor where c.sit <> 'a_receber'
      ) u(componente, data_caixa, valor)
    union all
    select 5::smallint,
           case i.tipo when 'renovacao_diamante' then 'Renovações Diamante'
                       when 'renovacao_aurum'    then 'Renovações Aurum'
                       when 'diamante_extra'     then 'Serviço Diamante extras'
                       else 'Outros recebimentos informados' end,
           u.componente, u.data_caixa, u.valor, u.sit, i.data_prevista,
           i.id::text, i.cliente, i.produtos[1], null::int, null::jsonb,
           i.efetiva,
           case when u.sit = 'a_receber'
                then ((extract(year from i.efetiva) - extract(year from v_dia)) * 12
                      + extract(month from i.efetiva) - extract(month from v_dia))::int + 1 end,
           i.via_hotmart, u.trat
      from inf i
      left join lateral fin.recebimento(i.efetiva, i.prov) f on i.via_hotmart and i.sit = 'a_receber'
      cross join lateral (
        select 'antecipacao'::text, f.entra_em, f.entra_rapido, 'a_receber'::text, null::text
         where i.via_hotmart and i.sit = 'a_receber'
        union all
        select 'garantia'::text, f.libera_em, f.retido, 'a_receber'::text, null::text
         where i.via_hotmart and i.sit = 'a_receber'
        union all
        select 'cheio'::text, i.efetiva, i.prov, 'a_receber'::text, 'Fora da Hotmart: entra cheio na data'::text
         where not i.via_hotmart and i.sit = 'a_receber'
        union all
        select 'cheio'::text, null::date, i.prov, 'em_atraso_fora'::text,
               'Em atraso: cobrar (vencido há mais de ' || v_tol || ' dias)'
         where i.sit = 'em_atraso_cobrar'
        union all
        select 'cheio'::text, null::date, i.valor::numeric, 'realizada'::text,
               case i.sit when 'baixado_fora' then 'Baixado fora da Hotmart' else 'Realizado na Hotmart' end
         where i.sit in ('realizado_hotmart','baixado_fora')
      ) u(componente, data_caixa, valor, sit, trat)
  )
  select l.bl, l.gr, l.comp, l.dc,
         case when f.fator = 1 then l.bruto else round(l.bruto * f.fator, 2) end,
         l.sit, l.od, l.rf, l.rot, l.prod, l.kk, l.det,
         l.bruto, f.fator,
         case when l.bl in (1, 2, 5) then 'certo' else 'estimado' end,
         case when l.via then '1. Receita de vendas (Hotmart)' else '4. Receita de vendas (Direta de clientes)' end,
         concat_ws(' · ',
           case when l.sit = 'a_receber' and l.comp = 'antecipacao' then coalesce(v.t_ant, 'Antecipação')
                when l.sit = 'a_receber' and l.comp = 'garantia'    then coalesce(v.t_ret, 'Retido')
           end,
           l.trat,
           case when l.sit = 'a_receber' and l.k_perda is not null then
                  case when pe.p is null then 'Sem premissa de perda do grupo (fator 1)'
                       when pe.p > 0 then pe.t_perda || ' × ' || l.k_perda
                                          || case when l.k_perda = 1 then ' mês' else ' meses' end
                  end
           end),
         v_cen
    from linhas l
    left join perda pe on pe.bloco = l.bl and (pe.grupo = l.gr or pe.grupo is null)
    left join vig v on l.comp in ('antecipacao','garantia') and l.dia_regra >= v.de and (v.ate is null or l.dia_regra < v.ate)
    cross join lateral (
      select case when l.sit = 'a_receber' and l.k_perda is not null and pe.p > 0
                  then pg_catalog.trim_scale(round(power(1 - pe.p, l.k_perda), 10)) else 1::numeric end fator
    ) f
   order by 1, 4 nulls last, 2, 3;
end $$;
comment on function fin.receber_posicao(timestamptz, date, text) is
  'Contas a Receber (z66): a previsão inteira (blocos 1, 2, 5) no corte, com perda composta por cenário. Interna: '
  'sem guarda de sessão (a pública guarda; o cron da F4 chama direto). Soma só situacao = a_receber.';
revoke all on function fin.receber_posicao(timestamptz, date, text) from public, anon, authenticated;


-- ─── 6. A RPC da aba: drop + create (RETURNS TABLE muda), mesma transação, mesma ACL ──────────────────────────────
drop function public.fn_fin_receber_semanal(timestamptz, date);
create function public.fn_fin_receber_semanal(p_corte timestamptz default null, p_ate date default null,
                                              p_cenario text default 'base')
returns table (bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text,
               origem_dia date, ref text, rotulo text, produto text, k int, detalhe jsonb,
               valor_bruto numeric, fator numeric, certeza text, centro_custo text, tratamento text, cenario text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select * from fin.receber_posicao(coalesce(p_corte, now()), p_ate, coalesce(p_cenario, 'base'));
end $$;
comment on function public.fn_fin_receber_semanal(timestamptz, date, text) is
  'Aba Contas a Receber (z61 + z63 + z66): blocos 1, 2 e 5. valor = esperado (bruto × fator); valor_bruto = sem perda. '
  'Soma só situacao = a_receber. Sem e-mail/documento: ref opaca ou id do informado, nome próprio/cliente.';
revoke all on function public.fn_fin_receber_semanal(timestamptz, date, text) from public, anon;
grant execute on function public.fn_fin_receber_semanal(timestamptz, date, text) to authenticated;


-- ─── 7. Premissas e feriados: RPCs da sub-aba Premissas ─────────────────────────────────────────────────────────────
-- Uma linha por vigência (histórico inteiro) com o catálogo repetido. situacao: 'vigente' (a que vale hoje para a
-- chave), 'futura' (vigente_de > hoje) ou 'anterior'. Cenário sem linha própria = usa a base (a tela mostra isso).
create function public.fn_fin_premissas_receber_listar()
returns table (chave text, chave_base text, cenario text, rotulo text, unidade text, minimo numeric, maximo numeric,
               grupo_tela text, ajuda text, aceita_cenario boolean, vigente_de date, valor numeric, fonte text,
               criado_em timestamptz, criado_por_nome text, situacao text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select pr.chave, pr.chave_base, pr.cenario, k.rotulo, k.unidade, k.minimo, k.maximo, k.grupo_tela, k.ajuda,
         k.aceita_cenario, pr.vigente_de, pr.valor, pr.fonte, pr.criado_em, pf.nome,
         case when pr.vigente_de > v_hoje then 'futura'
              when pr.vigente_de = max(pr.vigente_de) filter (where pr.vigente_de <= v_hoje)
                                     over (partition by pr.chave) then 'vigente'
              else 'anterior' end
    from fin.premissas_receber pr
    join fin.premissas_receber_catalogo k on k.chave = pr.chave_base
    left join public.perfis pf on pf.id = pr.criado_por
   order by k.grupo_tela, pr.chave_base, pr.cenario, pr.vigente_de desc;
end $$;
revoke all on function public.fn_fin_premissas_receber_listar() from public, anon;
grant execute on function public.fn_fin_premissas_receber_listar() to authenticated;

-- Grava uma vigência nova (nunca altera). p_vigente_de: de hoje até hoje + 366 (passado mudaria posição já vista).
-- Mesma chave e mesma data já gravadas → 23505 (corrigir = gravar outra data). Faixa e inteiro: catálogo (trigger).
create function public.fn_fin_premissa_receber_salvar(p_chave text, p_valor numeric, p_vigente_de date,
                                                      p_cenario text default 'base')
returns table (chave text, cenario text, vigente_de date, valor numeric)
language plpgsql volatile security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid  uuid := (select auth.uid());
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_cen  text := coalesce(nullif(btrim(p_cenario), ''), 'base');
  v_cat  fin.premissas_receber_catalogo;
  v_ch   text;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_cen not in ('base','conservador','otimista') then
    raise exception 'Cenário inválido (base, conservador ou otimista).' using errcode = '22023';
  end if;
  select k.* into v_cat from fin.premissas_receber_catalogo k where k.chave = btrim(coalesce(p_chave, ''));
  if not found then
    raise exception 'Premissa desconhecida.' using errcode = '22023';
  end if;
  if v_cen <> 'base' and not v_cat.aceita_cenario then
    raise exception 'A premissa "%" não varia por cenário.', v_cat.rotulo using errcode = '22023';
  end if;
  if p_valor is null or p_valor < v_cat.minimo or p_valor > v_cat.maximo then
    raise exception 'Valor fora da faixa de "%" (% a %).', v_cat.rotulo, v_cat.minimo, v_cat.maximo using errcode = '22023';
  end if;
  if v_cat.unidade in ('dias','liga_desliga') and p_valor <> trunc(p_valor) then
    raise exception '"%" aceita só número inteiro.', v_cat.rotulo using errcode = '22023';
  end if;
  if p_vigente_de is null or p_vigente_de < v_hoje or p_vigente_de > v_hoje + 366 then
    raise exception 'Vigência entre hoje e um ano à frente (a previsão já vista não muda).' using errcode = '22023';
  end if;
  v_ch := v_cat.chave || case when v_cen = 'base' then '' else '@' || v_cen end;
  return query
  insert into fin.premissas_receber as pr (chave, vigente_de, valor, fonte, criado_por)
  values (v_ch, p_vigente_de, p_valor, 'tela do Financeiro', v_uid)
  on conflict on constraint premissas_receber_pkey do nothing
  returning pr.chave_base, pr.cenario, pr.vigente_de, pr.valor;
  if not found then
    raise exception 'Já existe vigência desta premissa nesta data. Grave com outra data.' using errcode = '23505';
  end if;
end $$;
revoke all on function public.fn_fin_premissa_receber_salvar(text, numeric, date, text) from public, anon;
grant execute on function public.fn_fin_premissa_receber_salvar(text, numeric, date, text) to authenticated;

create function public.fn_fin_feriados_listar()
returns table (dia date, nome text, ativo boolean, fonte text, criado_em timestamptz, atualizado_em timestamptz,
               atualizado_por_nome text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select f.dia, f.nome, f.ativo, f.fonte, f.criado_em, f.atualizado_em, pf.nome
    from fin.feriados_bancarios f
    left join public.perfis pf on pf.id = coalesce(f.atualizado_por, f.criado_por)
   order by f.dia;
end $$;
revoke all on function public.fn_fin_feriados_listar() from public, anon;
grant execute on function public.fn_fin_feriados_listar() to authenticated;


-- ─── 8. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
do $chk$
declare
  v_dia   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ate   date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                   + interval '4 months' - interval '1 day')::date;
  v_adm   uuid;
  v_ok    boolean;
  v_esp   text;
  v_obt   text;
  v_n     int;
  v_txt   text;
  f       text;
  t       text;
begin
  -- 8.1 grants: tabelas fechadas e com RLS; internas sem EXECUTE; RPCs só para authenticated; proacl nunca nulo/PUBLIC
  foreach t in array array['fin.premissas_receber','fin.premissas_receber_catalogo'] loop
    if has_table_privilege('anon', t, 'select,insert,update,delete,truncate,references,trigger')
       or has_table_privilege('authenticated', t, 'select,insert,update,delete,truncate,references,trigger') then
      raise exception 'z66: grant aberto em %', t;
    end if;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception 'z66: RLS desligada em %', t;
    end if;
  end loop;
  foreach f in array array['fin.premissa(text,date,text)','fin.receber_pct(numeric)',
                           'fin.cobrancas_previstas(timestamptz,date)','fin.receber_posicao(timestamptz,date,text)',
                           'fin.tg_premissas_receber_valida()','fin.tg_premissas_receber_so_acrescimo()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z66: interna % executável por anon/authenticated', f;
    end if;
    if exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef) then
      raise exception 'z66: interna % é SECURITY DEFINER', f;
    end if;
  end loop;
  foreach f in array array['public.fn_fin_receber_semanal(timestamptz,date,text)',
                           'public.fn_fin_premissas_receber_listar()',
                           'public.fn_fin_premissa_receber_salvar(text,numeric,date,text)',
                           'public.fn_fin_feriados_listar()'] loop
    if has_function_privilege('anon', f, 'execute') then raise exception 'z66: % executável por anon', f; end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z66: authenticated sem execute em %', f;
    end if;
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                      and p.proconfig = array['search_path=""']) then
      raise exception 'z66: % sem SECURITY DEFINER ou sem search_path vazio', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p
              where p.oid in ('fin.premissa(text,date,text)'::regprocedure, 'fin.receber_pct(numeric)'::regprocedure,
                              'fin.cobrancas_previstas(timestamptz,date)'::regprocedure,
                              'fin.receber_posicao(timestamptz,date,text)'::regprocedure,
                              'fin.tg_premissas_receber_valida()'::regprocedure,
                              'fin.tg_premissas_receber_so_acrescimo()'::regprocedure,
                              'public.fn_fin_receber_semanal(timestamptz,date,text)'::regprocedure,
                              'public.fn_fin_premissas_receber_listar()'::regprocedure,
                              'public.fn_fin_premissa_receber_salvar(text,numeric,date,text)'::regprocedure,
                              'public.fn_fin_feriados_listar()'::regprocedure)
                and (p.proacl is null or exists (select 1 from unnest(p.proacl) ac where ac::text like '=%'))) then
    raise exception 'z66: função com EXECUTE para PUBLIC (ou proacl nulo = padrão público)';
  end if;
  if (select count(*) from pg_proc where proname = 'fn_fin_receber_semanal' and pronamespace = 'public'::regnamespace) <> 1
     or to_regprocedure('public.fn_fin_receber_semanal(timestamptz,date)') is not null
     or (select count(*) from pg_proc where proname = 'cobrancas_previstas' and pronamespace = 'fin'::regnamespace) <> 1 then
    raise exception 'z66: sobrecarga viva (fn_fin_receber_semanal / cobrancas_previstas)';
  end if;

  -- 8.2 sem sessão → 42501 nas 4 RPCs, e nada gravado
  select count(*) into v_n from fin.premissas_receber;
  foreach f in array array[
      'select * from public.fn_fin_receber_semanal(null, null)',
      'select * from public.fn_fin_premissas_receber_listar()',
      'select * from public.fn_fin_premissa_receber_salvar(''perda_mensal:holding_hm'', 0.2, current_date + 1, ''base'')',
      'select * from public.fn_fin_feriados_listar()'] loop
    v_ok := false;
    begin
      execute f;
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z66: RPC respondeu sem sessão: %', f; end if;
  end loop;
  if (select count(*) from fin.premissas_receber) <> v_n then raise exception 'z66: RPC gravou sem sessão'; end if;

  -- 8.3 fin.premissa: base, cenário próprio e reserva na base (linha de teste desfeita)
  begin
    insert into fin.premissas_receber (chave, vigente_de, valor, fonte)
    values ('perda_mensal:holding_hm@conservador', date '2000-01-01', 0.2, 'teste z66');
    if fin.premissa('perda_mensal:holding_hm', v_dia, 'base') <> 0.10
       or fin.premissa('perda_mensal:holding_hm', v_dia, 'conservador') <> 0.2
       or fin.premissa('perda_mensal:holding_hm', v_dia, 'otimista') <> 0.10
       or fin.premissa('perda_mensal:servico_diamante', v_dia, 'conservador') <> 0.05
       or fin.premissa('nao_existe', v_dia, 'base') is not null then
      raise exception 'z66: fin.premissa fora da regra base/cenário/reserva';
    end if;
    raise exception using errcode = 'P0001', message = 'z66_desfaz';
  exception when raise_exception then
    if sqlerrm <> 'z66_desfaz' then raise; end if;
  end;

  -- 8.4 equivalência com a z63: com TODAS as perdas = 0, as 12 colunas antigas batem linha a linha com a foto antes
  --     (detalhe do bloco 2 era NULL e agora é o do contrato: comparado à parte). Cortes: 25/09 e agora.
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  begin
    insert into fin.premissas_receber (chave, vigente_de, valor, fonte)
    select k.chave, date '2000-01-02', 0, 'teste z66' from fin.premissas_receber_catalogo k where k.chave like 'perda_mensal:%';
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    create temp table z66_depois_zero on commit drop as
      select 'passado'::text foto, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31') x
      union all
      select 'agora'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate) x;
    perform set_config('request.jwt.claims', '', true);
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp
      from (select a.foto, a.bloco, a.grupo, a.componente, a.data_caixa, a.valor, a.situacao, a.origem_dia, a.ref,
                   a.rotulo, a.produto, a.k, case when a.bloco = 2 then null else a.detalhe end
              from z66_antes a) x;
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
      from (select d.foto, d.bloco, d.grupo, d.componente, d.data_caixa, d.valor, d.situacao, d.origem_dia, d.ref,
                   d.rotulo, d.produto, d.k, case when d.bloco = 2 then null else d.detalhe end
              from z66_depois_zero d) x;
    if v_esp is distinct from v_obt then
      raise exception 'z66: com perdas = 0 a RPC nova difere da z63 (linhas antes %, depois %)',
        (select count(*) from z66_antes), (select count(*) from z66_depois_zero);
    end if;
    if exists (select 1 from z66_depois_zero d where d.fator <> 1 or d.valor is distinct from d.valor_bruto) then
      raise exception 'z66: com perdas = 0 há fator ≠ 1 ou valor ≠ valor_bruto';
    end if;
    raise exception using errcode = 'P0001', message = 'z66_desfaz';
  exception when raise_exception then
    if sqlerrm <> 'z66_desfaz' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  if exists (select 1 from fin.premissas_receber where fonte = 'teste z66') then
    raise exception 'z66: linhas de teste não foram desfeitas';
  end if;

  -- 8.5 com as perdas carregadas: valor_bruto = valor da z63 linha a linha; valor = round(bruto × fator, 2);
  --     fator = (1 − p)^k só em a_receber do bloco 2; contrato do bloco 2 sem e-mail no detalhe.
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  create temp table z66_depois on commit drop as
    select 'passado'::text foto, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31') x
    union all
    select 'agora'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate) x;
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp
    from (select md5(concat_ws('|', 'b', x.bloco, x.grupo, x.componente, x.data_caixa, x.valor, x.situacao, x.origem_dia, x.ref,
                  x.rotulo, x.produto, x.k, x.certeza, x.cenario)) x
            from (select a.*, 'certo'::text certeza, 'base'::text cenario from z66_antes a) x) x;
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
    from (select md5(concat_ws('|', 'b', d.bloco, d.grupo, d.componente, d.data_caixa, d.valor_bruto, d.situacao, d.origem_dia,
                  d.ref, d.rotulo, d.produto, d.k, d.certeza, d.cenario)) x
            from z66_depois d) x;
  if v_esp is distinct from v_obt then
    raise exception 'z66: valor_bruto (ou certeza/cenário) difere do valor da z63';
  end if;
  select string_agg(format('%s/%s/%s fator %s', d.bloco, d.grupo, d.situacao, d.fator), '; ') into v_txt
    from z66_depois d
    left join lateral (
      select fin.premissa(case d.grupo when 'Assinaturas Serviço Diamante' then 'perda_mensal:servico_diamante'
                                       when 'Assinaturas Holding - Holding Masters' then 'perda_mensal:holding_hm'
                                       when 'Outras assinaturas' then 'perda_mensal:outras_assinaturas'
                                       when 'Parcelas a vencer HM' then 'perda_mensal:parcelas_hm'
                                       when 'Parcelas a vencer Aurum' then 'perda_mensal:parcelas_aurum'
                                       when 'Parcelas a vencer outros' then 'perda_mensal:parcelas_outros' end,
                          v_dia, 'base') p
    ) pe on d.bloco = 2
   where d.valor is distinct from case when d.fator = 1 then d.valor_bruto else round(d.valor_bruto * d.fator, 2) end
      or (d.bloco = 2 and d.situacao = 'a_receber' and d.fator is distinct from trim_scale(round(power(1 - pe.p, d.k), 10)))
      or (d.bloco = 2 and d.situacao = 'a_receber' and pe.p is null)
      or (d.bloco in (1, 5) and d.fator <> 1)                      -- informados: perda 0 na carga
      or (d.situacao <> 'a_receber' and d.fator <> 1)
      or d.tratamento is null or d.tratamento = '' or d.centro_custo is null or d.certeza <> 'certo'
      or (d.bloco = 2 and d.componente = 'garantia' and d.detalhe is not null)
      or (d.bloco = 2 and d.componente <> 'garantia'
          and (d.detalhe is null or jsonb_typeof(d.detalhe) <> 'array' or d.detalhe::text like '%@%'
                           or exists (select 1 from jsonb_array_elements(d.detalhe) e(v), jsonb_object_keys(e.v) kk(chave)
                                       where kk.chave not in ('transacao','n','dia','liquido'))));
  if v_txt is not null then
    raise exception 'z66: linhas fora do contrato v2: %', left(v_txt, 800);
  end if;

  -- 8.6 cenários: sem chave @conservador/@otimista, os três cenários saem iguais ao base (menos a coluna cenario)
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp
    from (select d.bloco, d.grupo, d.componente, d.data_caixa, d.valor, d.situacao, d.origem_dia, d.ref, d.fator
            from z66_depois d where d.foto = 'agora') x;
  foreach t in array array['conservador','otimista'] loop
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
      from (select x.bloco, x.grupo, x.componente, x.data_caixa, x.valor, x.situacao, x.origem_dia, x.ref, x.fator
              from public.fn_fin_receber_semanal(now(), v_ate, t) x where x.cenario = t) x;
    if v_esp is distinct from v_obt and not exists (select 1 from fin.premissas_receber where cenario = t) then
      raise exception 'z66: cenário % sem premissa própria difere do base', t;
    end if;
  end loop;
  v_ok := false;
  begin
    perform 1 from public.fn_fin_receber_semanal(now(), v_ate, 'pessimista');
  exception when invalid_parameter_value then v_ok := true;
  end;
  if not v_ok then raise exception 'z66: cenário inválido não foi barrado'; end if;

  -- 8.7 escrita: salvar (admin opera) grava criado_por; faixa, cenário, passado e duplicata barrados; UPDATE/DELETE
  --     barrados; listar devolve a linha nova como 'futura'. Tudo desfeito.
  begin
    perform 1 from public.fn_fin_premissa_receber_salvar('perda_mensal:holding_hm', 0.12, v_dia + 1, 'conservador');
    if not exists (select 1 from fin.premissas_receber
                    where chave = 'perda_mensal:holding_hm@conservador' and criado_por = v_adm
                      and cenario = 'conservador' and chave_base = 'perda_mensal:holding_hm') then
      raise exception 'z66: salvar não gravou chave@cenário com criado_por';
    end if;
    if (select l.situacao from public.fn_fin_premissas_receber_listar() l
         where l.chave = 'perda_mensal:holding_hm@conservador') is distinct from 'futura' then
      raise exception 'z66: listar não marcou a vigência futura';
    end if;
    foreach f in array array[
        format('select * from public.fn_fin_premissa_receber_salvar(%L, 0.9, %L, %L)', 'perda_mensal:holding_hm', v_dia + 2, 'base'),
        format('select * from public.fn_fin_premissa_receber_salvar(%L, 7, %L, %L)', 'tolerancia_atraso_dias', v_dia + 2, 'conservador'),
        format('select * from public.fn_fin_premissa_receber_salvar(%L, 7.5, %L, %L)', 'tolerancia_atraso_dias', v_dia + 2, 'base'),
        format('select * from public.fn_fin_premissa_receber_salvar(%L, 0.1, %L, %L)', 'perda_mensal:holding_hm', v_dia - 1, 'base'),
        format('select * from public.fn_fin_premissa_receber_salvar(%L, 0.1, %L, %L)', 'perda_mensal:holding_hm', v_dia + 400, 'base'),
        format('select * from public.fn_fin_premissa_receber_salvar(%L, 0.1, %L, %L)', 'perda_mensal:holding_hm@otimista', v_dia + 2, 'base'),
        format('select * from public.fn_fin_premissa_receber_salvar(%L, 0.1, %L, %L)', 'perda_mensal:holding_hm', v_dia + 2, 'pessimista')] loop
      v_ok := false;
      begin
        execute f;
      exception when invalid_parameter_value then v_ok := true;
      end;
      if not v_ok then raise exception 'z66: salvar aceitou: %', f; end if;
    end loop;
    v_ok := false;
    begin
      perform 1 from public.fn_fin_premissa_receber_salvar('perda_mensal:holding_hm', 0.13, v_dia + 1, 'conservador');
    exception when unique_violation then v_ok := true;
    end;
    if not v_ok then raise exception 'z66: duplicata (chave, vigente_de) não foi barrada'; end if;
    foreach f in array array['update fin.premissas_receber set valor = 0.2 where chave = ''perda_mensal:holding_hm''',
                             'delete from fin.premissas_receber where chave = ''perda_mensal:holding_hm''',
                             'truncate fin.premissas_receber'] loop
      v_ok := false;
      begin
        execute f;
      exception when insufficient_privilege then v_ok := true;
      end;
      if not v_ok then raise exception 'z66: só-acréscimo furado: %', f; end if;
    end loop;
    v_ok := false;
    begin
      insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values ('perda_mensal:holding_hm', v_dia + 3, 0.9, 'x');
    exception when invalid_parameter_value then v_ok := true;
    end;
    if not v_ok then raise exception 'z66: INSERT direto fora da faixa não foi barrado pelo trigger'; end if;
    -- quem não opera (sessão sem perfil) não grava
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
    v_ok := false;
    begin
      perform 1 from public.fn_fin_premissa_receber_salvar('perda_mensal:holding_hm', 0.1, v_dia + 5, 'base');
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z66: salvar sem gp_pode_operar_financeiro passou'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    if (select count(*) from public.fn_fin_feriados_listar()) <> (select count(*) from fin.feriados_bancarios) then
      raise exception 'z66: feriados_listar não devolve todos os feriados';
    end if;
    raise exception using errcode = 'P0001', message = 'z66_desfaz';
  exception when raise_exception then
    if sqlerrm <> 'z66_desfaz' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  if exists (select 1 from fin.premissas_receber where criado_por is not null or cenario <> 'base') then
    raise exception 'z66: linhas de teste da escrita não foram desfeitas';
  end if;

  -- 8.8 fin.cobrancas_previstas: as 17 colunas da z65 idênticas linha a linha (só ganhou detalhe no fim)
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp from z66_cob_antes x;
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
    from (select 'passado'::text foto, c.grupo, c.tipo, c.ref, c.rotulo, c.produto, c.n, c.parcelas, c.vencimento,
                 c.vencimento_b, c.situacao, c.data_efetiva, c.valor, c.k, c.entra_em, c.entra_rapido, c.libera_em, c.retido
            from fin.cobrancas_previstas('2026-09-25 23:59:59-03', '2026-12-31') c
          union all
          select 'agora'::text, c.grupo, c.tipo, c.ref, c.rotulo, c.produto, c.n, c.parcelas, c.vencimento,
                 c.vencimento_b, c.situacao, c.data_efetiva, c.valor, c.k, c.entra_em, c.entra_rapido, c.libera_em, c.retido
            from fin.cobrancas_previstas(now(), v_ate) c) x;
  if v_esp is distinct from v_obt then
    raise exception 'z66: fin.cobrancas_previstas mudou além da coluna detalhe';
  end if;
  perform set_config('request.jwt.claims', '', true);
end $chk$;


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres; cada bloco é UMA chamada — o MCP é autocommit) ════════════════
-- <UUID_FINANCEIRO> = perfis.id ativo que VÊ o financeiro. explain: rodar 2× e usar a 2ª (1ª é cache frio).
/*
-- E5-v2) A RPC inteira. Meta: ≤ 300 ms quente (z63/Painel: 186 ms quente / 741 ms frio). Comparar com o mesmo
--        explain na z63 — a diferença esperada é o jsonb_agg por contrato (bloco 2) e 7 leituras de premissa.
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
explain (analyze, buffers) select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'conservador');
explain (analyze, buffers) select * from public.fn_fin_premissas_receber_listar();
explain (analyze, buffers) select * from public.fn_fin_feriados_listar();
-- bytes que vão para a tela (antes: medir o mesmo na z63 se ainda houver foto; o detalhe do bloco 2 é o acréscimo)
select count(*) linhas, pg_size_pretty(sum(pg_column_size(x))::bigint) total,
       pg_size_pretty(sum(pg_column_size(x.detalhe)) filter (where x.bloco = 2)::bigint) detalhe_bloco2
  from public.fn_fin_receber_semanal(null, null) x;
rollback;

-- E6) O corpo interno (é aí que o tempo mora; a pública é só guarda). Esperado: Index Scan em
--     hotmart_transacoes_aprovado_pago_idx (bloco 1 e universo do bloco 2), hotmart_transacoes_contrato_rec_idx (tx);
--     leitura de premissa por premissas_receber_pkey. "Seq Scan on hotmart_transacoes" = avisar o Victor.
explain (analyze, buffers) select * from fin.receber_posicao(now(), null, 'base');
explain (analyze, buffers) select * from fin.cobrancas_previstas(now(), (current_date + 95));

-- S1) Soma por grupo e cenário (o que entra no caixa: situacao = a_receber). Corte 25/09, horizonte 31/12.
--     Enquanto não houver chave @conservador/@otimista, as três colunas são iguais (esperado).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
with b as (select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'base') where situacao = 'a_receber'),
     c as (select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'conservador') where situacao = 'a_receber'),
     o as (select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'otimista') where situacao = 'a_receber')
select g.bloco, g.grupo,
       (select round(sum(b.valor_bruto), 2) from b where b.bloco = g.bloco and b.grupo = g.grupo) bruto,
       (select round(sum(b.valor), 2) from b where b.bloco = g.bloco and b.grupo = g.grupo) base,
       (select round(sum(c.valor), 2) from c where c.bloco = g.bloco and c.grupo = g.grupo) conservador,
       (select round(sum(o.valor), 2) from o where o.bloco = g.bloco and o.grupo = g.grupo) otimista
  from (select distinct b.bloco, b.grupo from b) g
 order by 1, 2;
-- tratamento: uma amostra de cada texto
select bloco, situacao, componente, tratamento, count(*) from public.fn_fin_receber_semanal(null, null)
 group by 1, 2, 3, 4 order by 1, 2, 3, 4;
rollback;

-- P-GRANTS) Vivo.
select p.oid::regprocedure, p.proacl, p.prosecdef, p.proconfig from pg_proc p
 where (p.pronamespace = 'public'::regnamespace
        and p.proname in ('fn_fin_receber_semanal','fn_fin_premissas_receber_listar','fn_fin_premissa_receber_salvar',
                          'fn_fin_feriados_listar'))
    or (p.pronamespace = 'fin'::regnamespace
        and p.proname in ('premissa','receber_pct','receber_posicao','cobrancas_previstas',
                          'tg_premissas_receber_valida','tg_premissas_receber_so_acrescimo'))
 order by 1::text;
select relname, relacl, relrowsecurity from pg_class
 where oid in ('fin.premissas_receber'::regclass, 'fin.premissas_receber_catalogo'::regclass);
*/
