-- 20260928z69 — Contas a Receber, fatia F4 (banco): fotografia semanal da previsão, "o que mudou" e previsto × realizado.
--               Junto: os 2 achados BAIXOS do Kirad na z67 (obrigatórios antes de ligar projecao_no_receber) e o DEFAULT
--               de fin.premissas_recebimento.dias_uteis = true.
--
-- APLICADA em produção em 28/09/2026 (fin_receber_fotos + _b; md5 dos 8 corpos = arquivo; conferência verde). 1ª foto 551 linhas, R$ 609.036,43, 272 kB, sem bloco 8. Cron 11 9 * * 1 (postgres). Medido: listar 0,4 ms · previsto_realizado(8) 6,7 ms · semanal 203 ms.
-- Ordem obrigatória: z67 aplicada antes. Guarda: o corpo VIVO de fin.receber_posicao, fin.receber_projecao,
-- public.fn_fin_eventos_planejados_listar e public.fn_fin_evento_planejado_salvar tem que ser o da z67 (comparação sem
-- espaço, sem comentário e sem o texto das mensagens de erro). A migration inteira é UMA transação.
--
-- O que faz:
--   1) fin.premissas_recebimento.dias_uteis: DEFAULT false → true (o default false quase desfez a z60 na z68: vigência
--      nova sem a coluna voltava a dias corridos). Nenhuma linha muda.
--   2) Kirad (z67, BAIXO 1) bloco 8: a mesma fonte e o mesmo nome do board — cs.vw_fin_board + public.thb_alunos,
--      rotulo = fin.nome_do_card(b.nome, b.email, alu.nome) (z44) e o mesmo "not exists" de card gêmeo
--      (cs.hm_comprador_alias) de public.fn_fin_board. Conferência 9.6: 0 linhas com rótulo ≠ nome do fn_fin_board.
--      Kirad (z67, BAIXO 2) custo sem teto de eventos: fin.receber_projecao só lê evento planejado com
--      abertura <= horizonte e abertura + 31 > dia do corte; fn_fin_eventos_planejados_listar só calcula a curva de
--      evento não arquivado; fn_fin_evento_planejado_salvar recusa criar o 31º evento não arquivado (22023).
--      create or replace: mesma assinatura, mesmo RETURNS, mesma ACL (revoke/grant repetidos por garantia).
--   3) fin.receber_fotos_cabecalho (1 linha por foto: foto_em, dia do corte, cenário, corte, horizonte, linhas, soma) e
--      fin.receber_fotos (as linhas da previsão no corte, SEM nome, e-mail, documento, rótulo, produto, detalhe ou
--      tratamento). Só acréscimo: trigger barra UPDATE, DELETE e TRUNCATE nas duas. RLS ligada, sem policy, sem grant.
--   4) fin.receber_fotografar(cenario default 'base', corte default now()) — interna (sem guarda de sessão; o cron roda
--      como postgres). Chama fin.receber_posicao direto. Idempotente por (dia do corte em SP, cenário): a UNIQUE do
--      cabeçalho é a trava, inclusive em corrida; a 2ª chamada devolve a foto existente com nova = false.
--   5) Cron 'fin-receber-foto-semanal' '11 9 * * 1' (segunda 06:11 em São Paulo = 09:11 UTC; o pg_cron roda em UTC —
--      a guarda aborta se cron.timezone não for UTC/GMT) e a 1ª foto já nesta migration.
--   6) RPCs (guarda gp_pode_ver_financeiro; SECURITY DEFINER; search_path ''; sem EXECUTE para PUBLIC/anon):
--      fn_fin_receber_fotos_listar(), fn_fin_receber_mudancas(foto_a, foto_b), fn_fin_receber_previsto_realizado(semanas).
--
-- CONTRATO
--   fin.receber_fotos: uma linha por (foto_em, bloco, grupo, ref, data_caixa, componente, origem_dia, situacao) — as
--     linhas de fin.receber_posicao agregadas nessa chave (soma de valor e valor_bruto). ref: bloco 1 NULL; bloco 2 =
--     fin.chave_opaca('rc:e-mail|oferta') (HMAC, já opaca na origem); bloco 3 'vn:<grupo>'; 4 'ep:<id>'; 5 = id (uuid) do
--     informado; 6 'reserva'; 8 = contato_hm_id (id interno do card; o Kirad não pediu HMAC no bloco 8 na revisão da z67).
--     Nenhum ref é dado pessoal direto (são pseudônimos: chave opaca, id do informado); nenhuma RPC devolve ref.
--   public.fn_fin_receber_fotos_listar() → (foto_em, dia, cenario, corte, ate, linhas, soma_a_receber, reconstruida),
--     mais nova primeiro. reconstruida = a foto foi tirada depois do dia do corte (só por chamada manual com p_corte).
--   public.fn_fin_receber_mudancas(p_foto_a, p_foto_b) → (bloco, grupo, valor_a, valor_b, delta, motivos jsonb), uma
--     linha por (bloco, grupo) com a_receber em A ou em B. valor_* = soma de valor (esperado) com situacao = 'a_receber'
--     (a mesma soma da tela). delta = valor_b − valor_a = Σ motivos[].valor (conferido). motivos = [{motivo, itens, valor}]
--     na ordem: entrou · saiu_pagamento · saiu_atraso · saiu_periodo · saiu_outro · mudou_valor · mudou_premissa.
--     Item = (bloco, ref, dia-chave, componente); dia-chave = origem_dia nos blocos 1 e 2 (dia da venda / vencimento),
--     nenhum no 5 (o informado é um só), data_caixa nos blocos 3, 4 e 6. Regras:
--       entrou          — sem a_receber em A, com a_receber em B;
--       saiu_pagamento  — tinha em A e em B a mesma cobrança/informado está 'realizada' (bloco 2: também contrato com
--                         paga sem vencimento, caso d1 nulo); ou sumiu de B com data de caixa <= dia do corte de B nos
--                         blocos certos 1, 2, 5 (o dinheiro caiu);
--       saiu_atraso     — em B a mesma cobrança/informado está 'em_atraso_fora';
--       saiu_periodo    — blocos estimados 3, 4, 6: a data de caixa passou (o confronto é o previsto × realizado);
--       saiu_outro      — sumiu sem rastro (contrato cancelado/estornado, informado arquivado, coberta por informado);
--       mudou_valor     — está nas duas, valor diferente e valor_bruto diferente (a base mudou: estorno, parcial, valor);
--       mudou_premissa  — está nas duas, valor diferente com o mesmo valor_bruto (perda/fator), ou bloco estimado, ou
--                         fotos de cenários diferentes.
--     itens = cobranças/dias/informados distintos (antecipação e garantia da mesma cobrança contam 1).
--   public.fn_fin_receber_previsto_realizado(p_semanas default 8, 1 a 52) →
--     (linha, semana_de, semana_ate, janela_de, janela_ate, foto_em, bloco, grupo, previsto, previsto_bruto, realizado,
--      desvio, acerto_pct, chave_premissa, perda_medida, premissa_atual, cobrancas_resolvidas, cobrancas_perdidas,
--      valor_resolvido, valor_perdido, nota)
--     linha 'semana': as p_semanas semanas COMPLETAS (seg–dom) antes da semana de hoje, por (bloco, grupo).
--       foto da semana = a foto do cenário base com dia do corte em (seg − 7, seg], a mais nova (o cron tira na segunda).
--       janela = [max(seg, dia da foto + 1), dom] — a foto não prevê o próprio dia do corte (data de caixa > corte), então
--       previsto e realizado olham os MESMOS dias.
--       previsto = Σ valor (e valor_bruto) das linhas a_receber da foto com data_caixa na janela.
--       realizado (o que caiu, pela regra de caixa fin.recebimento sobre as vendas pagas de AGORA):
--         bloco 1 'Vendas já realizadas' = fin.receber_vendas_realizadas(corte da foto) com data_caixa na janela;
--         vendas pagas depois do corte até o fim da janela, por dia de aprovação → fin.recebimento, a parte com data
--         na janela, atribuídas nesta ordem: bloco 5 (casa com informado a_receber na foto — mesma regra de
--         fin.informados_situacao: e-mail/documento de fin.informados_alvos, produto, dia >= acordo_desde), bloco 2
--         (recorrência >= 2 de contrato cuja ref opaca está no bloco 2 da foto; grupo = o da foto), senão bloco NULL
--         'Fora da foto (vendas novas e outros)';
--         bloco 5 baixa manual = valor cheio do informado a_receber na foto com baixa_manual_em na janela.
--       desvio = realizado − previsto; acerto_pct = max(0, 100 × (1 − |desvio| ÷ previsto)), 1 casa; NULL sem previsto.
--       Semana sem foto: 1 linha com bloco/grupo NULL e nota 'sem foto base no início da semana'.
--       Blocos 3, 4, 6 (estimados) saem com realizado NULL: a venda nova realizada cai em 'Fora da foto'.
--     linha 'perda': 1 por grupo do bloco 2 — SUGESTÃO para perda_mensal:<grupo> (só devolve; nada grava). Coorte =
--       cobranças a_receber na foto de cada semana com vencimento dentro da semana; resolvidas na 1ª foto base com dia
--       do corte > domingo + tolerancia_atraso_dias: 'realizada' = paga; 'em_atraso_fora' ou contrato fora da previsão
--       = perdida; 'coberta_informado', ainda a_receber ou sem foto de resolução = fora da conta.
--       perda_medida = valor_perdido ÷ valor_resolvido (valor_bruto); premissa_atual = fin.premissa(chave, hoje, base).
--
-- 5 perguntas:
--   escala: 1 foto/semana; linhas por foto = linhas de fin.receber_posicao agregadas (medir na 1ª foto: prova P1);
--           o plano estimou 1 a 2 mil linhas → 52 a 104 mil/ano. As RPCs leem 1 ou 2 fotos pela UNIQUE (foto_em, ...)
--           e o previsto × realizado lê ≤ 52 semanas: nada lê a tabela inteira.
--   índice: UNIQUE NULLS NOT DISTINCT (foto_em, bloco, grupo, ref, data_caixa, componente, origem_dia, situacao) serve
--           a busca por foto_em (coluna líder): um índice só (foto_em) seria duplicado. PK do cabeçalho = foto_em;
--           UNIQUE (dia, cenario) = idempotência. Vendas: hotmart_transacoes_aprovado_pago_idx (status literal).
--   frequência: cron 1×/semana; RPCs sob demanda (a Visão geral chama 2 ao abrir).
--   repetição: a foto é o resultado de fin.receber_posicao (nenhuma regra nova de previsão); o realizado reusa
--           fin.receber_vendas_realizadas, fin.recebimento, fin.informados_alvos e fin.chave_opaca.
--   reversão (sem apagar): select cron.unschedule('fin-receber-foto-semanal'); para desligar. Reverter de vez:
--   begin;
--   select cron.unschedule('fin-receber-foto-semanal');
--   drop function public.fn_fin_receber_fotos_listar();
--   drop function public.fn_fin_receber_mudancas(timestamptz, timestamptz);
--   drop function public.fn_fin_receber_previsto_realizado(int);
--   drop function fin.receber_fotografar(text, timestamptz);
--   alter table fin.receber_fotos rename to receber_fotos_arquivada_z69;
--   alter table fin.receber_fotos_cabecalho rename to receber_fotos_cabecalho_arquivada_z69;
--   -- achados do Kirad: recriar fin.receber_projecao, fn_fin_eventos_planejados_listar e fn_fin_evento_planejado_salvar
--   -- com o corpo da z67 (create or replace). O DEFAULT dias_uteis = true FICA (é a lição).
--   commit;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.z69_norm(p text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(regexp_replace(p, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                       '--[^\n]*', '', 'g'), '\s+', '', 'g')
$$;

create or replace function pg_temp.z69_cron_bate(p_campo text, p_v int) returns boolean language sql immutable as $$
  -- campo do cron (lista com vírgula; *, n, a-b, */p, a-b/p) casa com o valor p_v? Parte que não sei ler = casa (aborta).
  select exists (
    select 1
      from unnest(string_to_array(p_campo, ',')) u(parte)
      cross join lateral (select split_part(u.parte, '/', 1) faixa,
                                 case when split_part(u.parte, '/', 2) ~ '^\d+$' then split_part(u.parte, '/', 2)::int end passo,
                                 u.parte ~ '^(\*|\d+|\d+-\d+)(/\d+)?$' legivel) s
      cross join lateral (select case when s.faixa = '*' then 0
                                      when s.faixa ~ '^\d+-\d+$' then split_part(s.faixa, '-', 1)::int
                                      when s.faixa ~ '^\d+$' then s.faixa::int end ini,
                                 case when s.faixa = '*' then 1000
                                      when s.faixa ~ '^\d+-\d+$' then split_part(s.faixa, '-', 2)::int
                                      when s.faixa ~ '^\d+$' then case when s.passo is null then s.faixa::int else 1000 end end fim) r
     where not s.legivel
        or (p_v between r.ini and r.fim and (p_v - r.ini) % coalesce(nullif(s.passo, 0), 1) = 0))
$$;

do $guarda$
declare
  v_pos  oid := to_regprocedure('fin.receber_posicao(timestamptz,date,text)');
  v_prj  oid := to_regprocedure('fin.receber_projecao(timestamptz,date,text)');
  v_lis  oid := to_regprocedure('public.fn_fin_eventos_planejados_listar()');
  v_sal  oid := to_regprocedure('public.fn_fin_evento_planejado_salvar(jsonb)');
  v_src  text;
  v_res  text;
  v_fora text;
  v_tz   text := current_setting('cron.timezone', true);
  e_pos  text := $esperado$
#variable_conflict use_column
declare
  v_corte timestamptz := p_corte;
  v_cen   text := p_cenario;
  v_dia   date;
  v_ate   date;
  v_max   int;
  v_tol   int;
  v_inf   boolean;
  v_proj  boolean;
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
  -- z67: kill-switch da projeção (blocos 3, 4, 6 e 8). Sem vigência = desligada.
  v_proj := coalesce(fin.premissa('projecao_no_receber', v_dia, 'base') > 0, false);

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
         l.sit, l.od, l.rf, l.rot, l.prod, l.kk,
         case when l.bl <> 2 then l.det
              when row_number() over (partition by l.bl, l.rf
                                      order by (l.sit = 'a_receber') desc, l.od nulls last, l.comp, l.sit,
                                               l.dc nulls last) = 1
              then l.det end,   -- z67: detalhe do bloco 2 UMA vez por contrato (1ª a_receber por vencimento)
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
  union all
  select pj.* from fin.receber_projecao(v_corte, v_ate, v_cen) pj where v_proj   -- z67
   order by 1, 4 nulls last, 2, 3;
end
$esperado$;
  e_prj  text := $esperado$
#variable_conflict use_column
declare
  v_cen text := p_cenario;
  v_dia date;
begin
  if p_corte is null or p_ate is null then
    raise exception 'fin.receber_projecao: corte e horizonte são obrigatórios' using errcode = '22023';
  end if;
  if v_cen is null or v_cen not in ('base','conservador','otimista') then
    raise exception 'Cenário inválido (base, conservador ou otimista).' using errcode = '22023';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  if p_ate < v_dia or p_ate > v_dia + 400 then
    raise exception 'Horizonte fora do intervalo (do corte até 400 dias depois).' using errcode = '22023';
  end if;

  return query
  with vig as materialized (
    -- texto do caixa por vigência de fin.premissas_recebimento (o mesmo da z66)
    select pr.vigente_de de, lead(pr.vigente_de) over (order by pr.vigente_de) ate,
           'Antecipação D+' || pr.dias_ate_entrar || case when pr.dias_uteis then ' útil' else '' end
             || ' (' || fin.receber_pct(1 - pr.pct_retido) || ' − ' || fin.receber_pct(pr.taxa_antecipacao) || ')' t_ant,
           'Retido ' || fin.receber_pct(pr.pct_retido) || ' volta em D+' || pr.dias_retencao t_ret
      from fin.premissas_recebimento pr
  ), med as materialized (
    select m.grupo, m.sugestao from fin.receber_venda_semanal_medida(p_corte) m
  ), res as materialized (
    select r.sugestao from fin.receber_reserva_medida(p_corte) r
  ), ev as materialized (
    select p.id, p.nome, p.abertura, p.pausa_avulso, p.evento_ref_id, e.nome ref_nome,
           case v_cen when 'conservador' then p.tamanho_conservador when 'otimista' then p.tamanho_otimista
                else p.tamanho_base end tam
      from fin.eventos_planejados p
      join fin.eventos e on e.id = p.evento_ref_id
     where p.arquivado_em is null
  ), curva as materialized (
    select ev.id, ev.pausa_avulso, ev.abertura + c.d dia, pg_catalog.round(ev.tam * c.liquido, 2) venda
      from ev cross join lateral fin.receber_curva_evento(ev.evento_ref_id) c
  ), pausa as materialized (
    select distinct (pg_catalog.date_trunc('week', c.dia::timestamp))::date semana from curva c where c.pausa_avulso
  ), vn as materialized (
    select g.grupo, d.dia, coalesce(pl.valor, m.sugestao) semanal,
           case when pl.valor is not null then pl.origem when m.sugestao is not null then 'mediana 12 sem' end base
      from (select distinct x.grupo from fin.receber_grupos_venda_nova x where x.grupo is not null) g
      cross join (select v_dia + s.n dia from generate_series(1, p_ate - v_dia) s(n)) d
      left join med m on m.grupo = g.grupo
      left join lateral fin.premissa_linha('venda_semanal:' || g.grupo, d.dia, v_cen) pl on true
     where not (g.grupo = 'hm_avulso'
                and exists (select 1 from pausa pa where pa.semana = (pg_catalog.date_trunc('week', d.dia::timestamp))::date))
  ), vend as (
    select 3::smallint bl, v.grupo chave, v.dia, pg_catalog.round(v.semanal / 7, 2) venda, v.base
      from vn v where v.semanal > 0
    union all
    select 4::smallint, c.id::text, c.dia, c.venda, 'curva ' || ev.ref_nome
      from curva c join ev on ev.id = c.id
     where c.dia > v_dia and c.dia <= p_ate and c.venda > 0
  ), cx as materialized (
    select v.bl, v.chave, v.dia, v.venda, v.base, r.entra_em, r.entra_rapido, r.libera_em, r.retido
      from vend v cross join lateral fin.recebimento(v.dia, v.venda) r
  ), lin as materialized (
    select x.bl, x.chave, u.comp, u.dc, sum(u.v) valor, min(x.dia) od,
           jsonb_agg(jsonb_build_object('dia', x.dia, 'valor_venda', x.venda, 'base', x.base) order by x.dia) det,
           string_agg(distinct x.base, ' + ') bases
      from cx x
      cross join lateral (values ('antecipacao'::text, x.entra_em, x.entra_rapido),
                                 ('garantia'::text, x.libera_em, x.retido)) u(comp, dc, v)
     group by x.bl, x.chave, u.comp, u.dc
  ), b6 as materialized (
    select l.dc, sum(l.valor) base_valor from lin l group by l.dc
  ), b6p as materialized (
    select b.dc, b.base_valor, coalesce(pl.valor, rs.sugestao) pct,
           case when pl.valor is not null then pl.origem
                when rs.sugestao is not null then 'taxa medida em 9 meses' end origem
      from b6 b
      cross join res rs
      left join lateral fin.premissa_linha('reserva_reembolso', b.dc, v_cen) pl on true
  ), bd as materialized (
    -- a regra da fonte 'combinado' de fn_fin_contratado (z_p), lida do board de agora
    select v.contato_hm_id, v.nome::text nome, lower(trim(v.email::text)) email, ch.produto origem, v.vencimento,
           v.saldo_a_pagar
      from cs.vw_fin_contas_receber v
      join cs.contatos_hm ch on ch.id = v.contato_hm_id
     where ch.produto in ('HM','AURUM') and v.vencimento >= v_dia and v.vencimento <= p_ate
       and coalesce(v.saldo_a_pagar, 0) > 0.5
       and v.status_financeiro not in ('cancelado','reembolsado','quitado')
  ), plano as materialized (
    select t.email, t.familia
      from fin.vw_transacoes t
     where t.email in (select bd.email from bd)
       and t.oferta_modo like 'HOTMART_INSTALLMENTS%' and t.recorrencia is not null
     group by t.email, t.familia, t.oferta_codigo
    having max(t.parcelas) > coalesce(max(t.recorrencia) filter (where t.grupo = 'pago'), 0)
  )
  -- blocos 3 e 4
  select l.bl,
         case when l.bl = 3 then case l.chave when 'hm_avulso' then 'HM avulso' when 'holding_total' then 'Holding Total'
                                              when 'outros' then 'Outros produtos' else l.chave end
              else ev.nome end,
         l.comp, l.dc, l.valor, 'a_receber'::text, l.od,
         case l.bl when 3 then 'vn:' else 'ep:' end || l.chave,
         case when l.bl = 3 then l.bases else 'Referência: ' || ev.ref_nome end,
         null::text, null::int,
         case when l.comp = 'antecipacao' then l.det end,   -- 1× por venda (a garantia é a mesma venda), como o bloco 2
         l.valor, 1::numeric, 'estimado'::text, '1. Receita de vendas (Hotmart)'::text,
         concat_ws(' · ',
           case l.comp when 'antecipacao' then coalesce(vg.t_ant, 'Antecipação') else coalesce(vg.t_ret, 'Retido') end,
           case when l.bl = 3 then 'Venda nova por dia = valor semanal ÷ 7 (' || l.bases || ')'
                else 'Evento planejado: tamanho ' || replace(pg_catalog.trim_scale(ev.tam)::text, '.', ',')
                     || ' × venda do dia de ' || ev.ref_nome || ' (cenário ' || v_cen || ')' end),
         v_cen
    from lin l
    left join ev on l.bl = 4 and ev.id::text = l.chave
    left join vig vg on l.od >= vg.de and (vg.ate is null or l.od < vg.ate)
  union all
  -- bloco 3 sem base (nem premissa, nem sugestão) em algum dia: visível, fora da soma
  select 3::smallint,
         case s.grupo when 'hm_avulso' then 'HM avulso' when 'holding_total' then 'Holding Total'
                      when 'outros' then 'Outros produtos' else s.grupo end,
         'cheio'::text, null::date, null::numeric, 'sem_base'::text, null::date, 'vn:' || s.grupo, 'sem base'::text,
         null::text, null::int, null::jsonb, null::numeric, 1::numeric, 'estimado'::text,
         '1. Receita de vendas (Hotmart)'::text,
         'Sem sugestão medida (nenhuma semana completa sem evento em 52) e sem premissa: grupo fora da projeção'::text, v_cen
    from (select distinct vn.grupo from vn where vn.semanal is null) s
  union all
  -- bloco 6: reserva negativa por data de caixa
  select 6::smallint, 'Reserva de reembolso e chargeback'::text, 'reserva'::text, b.dc,
         -pg_catalog.round(b.pct * b.base_valor, 2), 'a_receber'::text, null::date, 'reserva'::text, b.origem,
         null::text, null::int, null::jsonb, -pg_catalog.round(b.pct * b.base_valor, 2), 1::numeric, 'estimado'::text,
         '3. (Devoluções)'::text,
         'Reserva ' || fin.receber_pct(b.pct) || ' sobre as vendas novas estimadas do dia (blocos 3 e 4; base '
           || fin.receber_brl(b.base_valor) || ') · ' || b.origem,
         v_cen
    from b6p b
   where b.pct > 0
  union all
  select 6::smallint, 'Reserva de reembolso e chargeback'::text, 'reserva'::text, null::date, null::numeric,
         'sem_base'::text, null::date, 'reserva'::text, 'sem base'::text, null::text, null::int, null::jsonb,
         null::numeric, 1::numeric, 'estimado'::text, '3. (Devoluções)'::text,
         'Sem taxa medida (nada vendido em 9 meses) e sem premissa: reserva fora da projeção'::text, v_cen
   where exists (select 1 from b6p b where b.pct is null)
  union all
  -- bloco 8: acordos combinados no board — informativo, fora da soma
  select 8::smallint, 'Informativo: acordos no board'::text, 'cheio'::text, b.vencimento, b.saldo_a_pagar,
         'informativo'::text, b.vencimento, b.contato_hm_id::text, fin.nome_proprio(b.nome),
         case b.origem when 'AURUM' then 'Aurum' else 'Holding Masters' end, null::int, null::jsonb,
         b.saldo_a_pagar, 1::numeric, 'informativo'::text, null::text,
         'Saldo combinado no board: informativo, fora da soma (somar contaria duas vezes com a venda nova do bloco 3)'::text,
         v_cen
    from bd b
   where not exists (select 1 from plano p where p.email = b.email and p.familia = b.origem);
end
$esperado$;
  e_lis  text := $esperado$
#variable_conflict use_column
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select p.id, p.nome, p.abertura, p.abertura + (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)),
         p.evento_ref_id, e.nome, coalesce(e.carrinho_inicio, e.inicio), e.venda_ate, c.total, c.curva,
         p.tamanho_base, p.tamanho_conservador, p.tamanho_otimista, p.pausa_avulso, p.observacao,
         case when p.arquivado_em is not null then 'arquivado'
              when p.abertura + (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) < v_hoje then 'encerrado'
              else 'ativo' end,
         p.criado_em, pc.nome, p.atualizado_em, pu.nome, p.arquivado_em, pa.nome, p.arquivado_motivo
    from fin.eventos_planejados p
    join fin.eventos e on e.id = p.evento_ref_id
    left join lateral (
      select max(x.total) total,
             jsonb_agg(jsonb_build_object('d', x.d, 'liquido', x.liquido, 'participacao', x.participacao) order by x.d) curva
        from fin.receber_curva_evento(p.evento_ref_id) x
    ) c on true
    left join public.perfis pc on pc.id = p.criado_por
    left join public.perfis pu on pu.id = p.atualizado_por
    left join public.perfis pa on pa.id = p.arquivado_por
   order by (p.arquivado_em is not null), p.abertura desc, p.id desc;
end
$esperado$;
  e_sal  text := $esperado$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_id    bigint;
  v_nome  text;
  v_ab    date;
  v_ref   bigint;
  v_tb    numeric;
  v_tc    numeric;
  v_to    numeric;
  v_pausa boolean;
  v_obs   text;
  v_fora  text;
  v_e     fin.eventos;
  v_tot   numeric;
  v_arq   timestamptz;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'Evento planejado: envie um objeto.' using errcode = '22023';
  end if;
  select string_agg(x.k, ', ') into v_fora from jsonb_object_keys(p) x(k)
   where x.k not in ('id','nome','abertura','evento_ref_id','tamanho_base','tamanho_conservador','tamanho_otimista',
                     'pausa_avulso','observacao');
  if v_fora is not null then
    raise exception 'Evento planejado: campo desconhecido (%).', v_fora using errcode = '22023';
  end if;
  begin
    v_id    := nullif(btrim(p ->> 'id'), '')::bigint;
    v_nome  := btrim(p ->> 'nome');
    v_ab    := (p ->> 'abertura')::date;
    v_ref   := (p ->> 'evento_ref_id')::bigint;
    v_tb    := (p ->> 'tamanho_base')::numeric;
    v_tc    := (p ->> 'tamanho_conservador')::numeric;
    v_to    := (p ->> 'tamanho_otimista')::numeric;
    v_pausa := coalesce((p ->> 'pausa_avulso')::boolean, true);
    v_obs   := nullif(btrim(p ->> 'observacao'), '');
  exception when others then
    raise exception 'Evento planejado: campo com formato inválido (data AAAA-MM-DD, número com ponto, pausa true/false).'
      using errcode = '22023';
  end;
  if coalesce(v_nome, '') = '' or length(v_nome) > 120 then
    raise exception 'Evento planejado: nome vazio ou longo demais (até 120).' using errcode = '22023';
  end if;
  if v_ab is null or v_ab < v_hoje - 31 or v_ab > v_hoje + 400 then
    raise exception 'Evento planejado: abertura entre 31 dias atrás e 400 dias à frente.' using errcode = '22023';
  end if;
  if v_tb is null or v_tc is null or v_to is null or least(v_tb, v_tc, v_to) <= 0 or greatest(v_tb, v_tc, v_to) > 20
     or not (v_tc <= v_tb and v_tb <= v_to) then
    raise exception 'Evento planejado: tamanhos maiores que 0 e até 20, com conservador ≤ base ≤ otimista.' using errcode = '22023';
  end if;
  if v_obs is not null and length(v_obs) > 500 then
    raise exception 'Evento planejado: observação longa demais (até 500).' using errcode = '22023';
  end if;
  select e.* into v_e from fin.eventos e where e.id = v_ref;
  if not found then
    raise exception 'Evento de referência não existe.' using errcode = '22023';
  end if;
  if v_e.setor <> 'educacao' then
    raise exception 'O evento de referência tem que ser da educação (a conta do escritório não está no espelho).' using errcode = '22023';
  end if;
  if v_e.venda_ate >= v_hoje then
    raise exception 'O evento de referência ainda não terminou as vendas: a curva estaria incompleta.' using errcode = '22023';
  end if;
  if v_e.venda_ate - coalesce(v_e.carrinho_inicio, v_e.inicio) > 30 then
    raise exception 'O evento de referência tem mais de 31 dias de venda: escolha um evento com curva curta.' using errcode = '22023';
  end if;
  select max(c.total) into v_tot from fin.receber_curva_evento(v_ref) c;
  if coalesce(v_tot, 0) <= 0 then
    raise exception 'O evento de referência não tem venda no espelho (oferta do evento, 1ª cobrança, sem Aurum/Diamante).'
      using errcode = '22023';
  end if;

  if v_id is null then
    insert into fin.eventos_planejados as ep (nome, abertura, evento_ref_id, tamanho_base, tamanho_conservador,
                                              tamanho_otimista, pausa_avulso, observacao, criado_por)
    values (v_nome, v_ab, v_ref, v_tb, v_tc, v_to, v_pausa, v_obs, v_uid)
    returning ep.id into v_id;
  else
    select ep.arquivado_em into v_arq from fin.eventos_planejados ep where ep.id = v_id for update;
    if not found then
      raise exception 'Evento planejado não existe.' using errcode = '22023';
    end if;
    if v_arq is not null then
      raise exception 'Evento planejado arquivado não muda: cadastre outro.' using errcode = '22023';
    end if;
    update fin.eventos_planejados ep
       set nome = v_nome, abertura = v_ab, evento_ref_id = v_ref, tamanho_base = v_tb, tamanho_conservador = v_tc,
           tamanho_otimista = v_to, pausa_avulso = v_pausa, observacao = v_obs, atualizado_em = now(), atualizado_por = v_uid
     where ep.id = v_id;
  end if;
  return query
  select ep.id, ep.nome, ep.abertura, ep.evento_ref_id,
         case when ep.abertura + (v_e.venda_ate - coalesce(v_e.carrinho_inicio, v_e.inicio)) < v_hoje then 'encerrado'
              else 'ativo' end
    from fin.eventos_planejados ep where ep.id = v_id;
end
$esperado$;
  e_res  text := 'TABLE(bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text, '
              || 'origem_dia date, ref text, rotulo text, produto text, k integer, detalhe jsonb, valor_bruto numeric, '
              || 'fator numeric, certeza text, centro_custo text, tratamento text, cenario text)';
begin
  if current_setting('server_version_num')::int < 150000 then
    raise exception 'z69: Postgres < 15 (UNIQUE NULLS NOT DISTINCT) — avisar o Victor';
  end if;
  if v_pos is null or v_prj is null or v_lis is null or v_sal is null then
    raise exception 'z69: aplicar a z67 antes (receber_posicao / receber_projecao / eventos planejados ausentes)';
  end if;
  if to_regclass('fin.receber_fotos') is not null or to_regclass('fin.receber_fotos_cabecalho') is not null
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                   and proname in ('fn_fin_receber_fotos_listar','fn_fin_receber_mudancas','fn_fin_receber_previsto_realizado'))
     or exists (select 1 from pg_proc where pronamespace = 'fin'::regnamespace
                   and proname in ('receber_fotografar','tg_receber_fotos_so_acrescimo')) then
    raise exception 'z69: já aplicada (tabela ou função da z69 existe)';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'fin'::regnamespace
         and proname in ('receber_posicao','receber_projecao')) <> 2
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
            and proname in ('fn_fin_eventos_planejados_listar','fn_fin_evento_planejado_salvar')) <> 2 then
    raise exception 'z69: sobrecarga viva de receber_posicao/receber_projecao/listar/salvar — conferir pg_get_function_arguments';
  end if;

  -- corpos vivos = z67
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_pos;
  if pg_temp.z69_norm(v_src) <> pg_temp.z69_norm(e_pos) or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_res, '\s+', '', 'g') then
    raise exception 'z69: corpo vivo de fin.receber_posicao diverge da z67. Mandar pg_get_functiondef ao Victor.';
  end if;
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_prj;
  if pg_temp.z69_norm(v_src) <> pg_temp.z69_norm(e_prj) or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_res, '\s+', '', 'g') then
    raise exception 'z69: corpo vivo de fin.receber_projecao diverge da z67. Mandar pg_get_functiondef ao Victor.';
  end if;
  select prosrc into v_src from pg_proc where oid = v_lis;
  if pg_temp.z69_norm(v_src) <> pg_temp.z69_norm(e_lis) then
    raise exception 'z69: corpo vivo de public.fn_fin_eventos_planejados_listar diverge da z67. Mandar pg_get_functiondef ao Victor.';
  end if;
  select prosrc into v_src from pg_proc where oid = v_sal;
  if pg_temp.z69_norm(v_src) <> pg_temp.z69_norm(e_sal) then
    raise exception 'z69: corpo vivo de public.fn_fin_evento_planejado_salvar diverge da z67. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_prj and l.lanname = 'plpgsql' and p.provolatile = 's' and not p.prosecdef
                    and p.proconfig = array['search_path=""'])
     or not exists (select 1 from pg_proc p where p.oid = v_lis and p.prosecdef and p.provolatile = 's'
                       and p.proconfig = array['search_path=""'])
     or not exists (select 1 from pg_proc p where p.oid = v_sal and p.prosecdef and p.provolatile = 'v'
                       and p.proconfig = array['search_path=""']) then
    raise exception 'z69: atributos vivos de receber_projecao/listar/salvar diferentes da z67';
  end if;

  -- dependências (nome de coluna conferido: rename em outra frente abortaria só em tempo de execução)
  if to_regclass('cs.vw_fin_board') is null or to_regclass('public.thb_alunos') is null
     or to_regclass('cs.hm_comprador_alias') is null or to_regclass('cs.contatos_hm') is null
     or to_regprocedure('fin.nome_do_card(text,text,text)') is null
     or to_regprocedure('public.fn_fin_board(text,text)') is null
     or to_regprocedure('fin.chave_opaca(text)') is null
     or to_regprocedure('fin.informados_alvos()') is null
     or to_regprocedure('fin.receber_vendas_realizadas(timestamptz)') is null
     or to_regprocedure('fin.recebimento(date,numeric)') is null
     or to_regprocedure('fin.premissa(text,date,text)') is null
     or to_regprocedure('public.gp_pode_ver_financeiro()') is null
     or to_regclass('cron.job') is null or to_regprocedure('cron.schedule(text,text,text)') is null then
    raise exception 'z69: dependência ausente (vw_fin_board, thb_alunos, hm_comprador_alias, nome_do_card, fn_fin_board, chave_opaca, informados_alvos, receber_vendas_realizadas, recebimento, premissa, gp_pode_ver_financeiro, pg_cron)';
  end if;
  select string_agg(x.t || '.' || x.c, ', ') into v_fora
    from (values ('cs','vw_fin_board','contato_hm_id'),('cs','vw_fin_board','comprador_id'),('cs','vw_fin_board','aluno_id'),
                 ('cs','vw_fin_board','nome'),('cs','vw_fin_board','email'),('cs','vw_fin_board','origem'),
                 ('cs','vw_fin_board','vencimento'),('cs','vw_fin_board','saldo_a_pagar'),
                 ('cs','vw_fin_board','status_financeiro'),('public','thb_alunos','id'),('public','thb_alunos','nome'),
                 ('cs','hm_comprador_alias','comprador_id'),('cs','hm_comprador_alias','canonico_id'),
                 ('cs','contatos_hm','comprador_id'),('cs','contatos_hm','produto'),
                 ('fin','recebimentos_informados','baixa_manual_em'),('fin','recebimentos_informados','acordo_desde'),
                 ('fin','recebimentos_informados','produto_ids'),('fin','recebimentos_informados','via_hotmart'),
                 ('fin','hotmart_transacoes','comprador_documento'),('fin','hotmart_transacoes','comprador_email'),
                 ('fin','premissas_recebimento','dias_uteis')) x(s, t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = x.s and ic.table_name = x.t and ic.column_name = x.c);
  if v_fora is not null then raise exception 'z69: coluna ausente: %', v_fora; end if;
  if not exists (select 1 from pg_indexes where schemaname = 'fin' and tablename = 'hotmart_transacoes'
                   and indexname = 'hotmart_transacoes_aprovado_pago_idx') then
    raise exception 'z69: hotmart_transacoes_aprovado_pago_idx ausente';
  end if;
  if (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d
        join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
       where d.adrelid = 'fin.premissas_recebimento'::regclass and a.attname = 'dias_uteis') is distinct from 'false' then
    raise exception 'z69: DEFAULT vivo de premissas_recebimento.dias_uteis não é false — conferir antes de trocar';
  end if;

  -- pg_cron: horário em UTC e sem colisão com job ativo (minuto 11, hora 9 UTC, segunda)
  if v_tz is not null and v_tz not in ('GMT','UTC','Etc/UTC') then
    raise exception 'z69: cron.timezone = % (esperado UTC/GMT): o 09:11 do agendamento não seria 06:11 em São Paulo', v_tz;
  end if;
  if exists (select 1 from cron.job j where j.jobname = 'fin-receber-foto-semanal') then
    raise exception 'z69: job fin-receber-foto-semanal já existe';
  end if;
  select string_agg(j.jobname || ' (' || j.schedule || ')', ', ') into v_fora
    from cron.job j
   where j.active
     and array_length(regexp_split_to_array(btrim(j.schedule), '\s+'), 1) = 5
     -- job de todo minuto (minuto = '*') bate com qualquer horário: não é colisão evitável, só avisa (plantao-emails-sala)
     and split_part(regexp_replace(btrim(j.schedule), '\s+', ' ', 'g'), ' ', 1) <> '*'
     and pg_temp.z69_cron_bate(split_part(regexp_replace(btrim(j.schedule), '\s+', ' ', 'g'), ' ', 1), 11)
     and pg_temp.z69_cron_bate(split_part(regexp_replace(btrim(j.schedule), '\s+', ' ', 'g'), ' ', 2), 9)
     and pg_temp.z69_cron_bate(split_part(regexp_replace(btrim(j.schedule), '\s+', ' ', 'g'), ' ', 5), 1);
  if v_fora is not null then
    raise exception 'z69: colisão com job ativo às segundas 09:11 UTC: % — escolher outro minuto', v_fora;
  end if;
  raise notice 'z69: jobs ativos: %', (select string_agg(j.jobname || ' ' || j.schedule, ' | ' order by j.jobname)
                                           from cron.job j where j.active);
end $guarda$;


-- ─── 1. DEFAULT de dias_uteis (nenhuma linha muda) ──────────────────────────────────────────────────────────────────
alter table fin.premissas_recebimento alter column dias_uteis set default true;
comment on column fin.premissas_recebimento.dias_uteis is
  'z60: true = entra_em/libera_em em dias úteis (fin.calendario_caixa); false = dias corridos (z54). DEFAULT true desde a '
  'z69: o default false quase desfez a z60 na z68 (vigência nova sem a coluna voltava a dias corridos).';


-- ─── 2. Achados BAIXOS do Kirad na z67 ──────────────────────────────────────────────────────────────────────────────
create or replace function fin.receber_projecao(p_corte timestamptz, p_ate date, p_cenario text)
returns table (bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text,
               origem_dia date, ref text, rotulo text, produto text, k int, detalhe jsonb,
               valor_bruto numeric, fator numeric, certeza text, centro_custo text, tratamento text, cenario text)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
declare
  v_cen text := p_cenario;
  v_dia date;
begin
  if p_corte is null or p_ate is null then
    raise exception 'fin.receber_projecao: corte e horizonte são obrigatórios' using errcode = '22023';
  end if;
  if v_cen is null or v_cen not in ('base','conservador','otimista') then
    raise exception 'Cenário inválido (base, conservador ou otimista).' using errcode = '22023';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  if p_ate < v_dia or p_ate > v_dia + 400 then
    raise exception 'Horizonte fora do intervalo (do corte até 400 dias depois).' using errcode = '22023';
  end if;

  return query
  with vig as materialized (
    -- texto do caixa por vigência de fin.premissas_recebimento (o mesmo da z66)
    select pr.vigente_de de, lead(pr.vigente_de) over (order by pr.vigente_de) ate,
           'Antecipação D+' || pr.dias_ate_entrar || case when pr.dias_uteis then ' útil' else '' end
             || ' (' || fin.receber_pct(1 - pr.pct_retido) || ' − ' || fin.receber_pct(pr.taxa_antecipacao) || ')' t_ant,
           'Retido ' || fin.receber_pct(pr.pct_retido) || ' volta em D+' || pr.dias_retencao t_ret
      from fin.premissas_recebimento pr
  ), med as materialized (
    select m.grupo, m.sugestao from fin.receber_venda_semanal_medida(p_corte) m
  ), res as materialized (
    select r.sugestao from fin.receber_reserva_medida(p_corte) r
  ), ev as materialized (
    select p.id, p.nome, p.abertura, p.pausa_avulso, p.evento_ref_id, e.nome ref_nome,
           case v_cen when 'conservador' then p.tamanho_conservador when 'otimista' then p.tamanho_otimista
                else p.tamanho_base end tam
      from fin.eventos_planejados p
      join fin.eventos e on e.id = p.evento_ref_id
     where p.arquivado_em is null
       -- z69 (Kirad): só evento que toca (corte, horizonte]. Curva ≤ 31 dias (abertura + 30); a pausa do avulso vale
       -- para a SEMANA inteira do dia de venda, por isso os limites são por semana (mesmo resultado da z67).
       and (pg_catalog.date_trunc('week', p.abertura::timestamp))::date <= p_ate
       and p.abertura + 30 >= (pg_catalog.date_trunc('week', v_dia::timestamp))::date
  ), curva as materialized (
    select ev.id, ev.pausa_avulso, ev.abertura + c.d dia, pg_catalog.round(ev.tam * c.liquido, 2) venda
      from ev cross join lateral fin.receber_curva_evento(ev.evento_ref_id) c
  ), pausa as materialized (
    select distinct (pg_catalog.date_trunc('week', c.dia::timestamp))::date semana from curva c where c.pausa_avulso
  ), vn as materialized (
    select g.grupo, d.dia, coalesce(pl.valor, m.sugestao) semanal,
           case when pl.valor is not null then pl.origem when m.sugestao is not null then 'mediana 12 sem' end base
      from (select distinct x.grupo from fin.receber_grupos_venda_nova x where x.grupo is not null) g
      cross join (select v_dia + s.n dia from generate_series(1, p_ate - v_dia) s(n)) d
      left join med m on m.grupo = g.grupo
      left join lateral fin.premissa_linha('venda_semanal:' || g.grupo, d.dia, v_cen) pl on true
     where not (g.grupo = 'hm_avulso'
                and exists (select 1 from pausa pa where pa.semana = (pg_catalog.date_trunc('week', d.dia::timestamp))::date))
  ), vend as (
    select 3::smallint bl, v.grupo chave, v.dia, pg_catalog.round(v.semanal / 7, 2) venda, v.base
      from vn v where v.semanal > 0
    union all
    select 4::smallint, c.id::text, c.dia, c.venda, 'curva ' || ev.ref_nome
      from curva c join ev on ev.id = c.id
     where c.dia > v_dia and c.dia <= p_ate and c.venda > 0
  ), cx as materialized (
    select v.bl, v.chave, v.dia, v.venda, v.base, r.entra_em, r.entra_rapido, r.libera_em, r.retido
      from vend v cross join lateral fin.recebimento(v.dia, v.venda) r
  ), lin as materialized (
    select x.bl, x.chave, u.comp, u.dc, sum(u.v) valor, min(x.dia) od,
           jsonb_agg(jsonb_build_object('dia', x.dia, 'valor_venda', x.venda, 'base', x.base) order by x.dia) det,
           string_agg(distinct x.base, ' + ') bases
      from cx x
      cross join lateral (values ('antecipacao'::text, x.entra_em, x.entra_rapido),
                                 ('garantia'::text, x.libera_em, x.retido)) u(comp, dc, v)
     group by x.bl, x.chave, u.comp, u.dc
  ), b6 as materialized (
    select l.dc, sum(l.valor) base_valor from lin l group by l.dc
  ), b6p as materialized (
    select b.dc, b.base_valor, coalesce(pl.valor, rs.sugestao) pct,
           case when pl.valor is not null then pl.origem
                when rs.sugestao is not null then 'taxa medida em 9 meses' end origem
      from b6 b
      cross join res rs
      left join lateral fin.premissa_linha('reserva_reembolso', b.dc, v_cen) pl on true
  ), bd as materialized (
    -- a regra da fonte 'combinado' de fn_fin_contratado (z_p), lida do board de agora.
    -- z69 (Kirad): a MESMA fonte e o MESMO nome de public.fn_fin_board (z44) — cs.vw_fin_board + thb_alunos,
    -- fin.nome_do_card e o "not exists" do card gêmeo (cs.hm_comprador_alias).
    select b.contato_hm_id, fin.nome_do_card(b.nome, b.email, alu.nome) rotulo, lower(trim(b.email::text)) email,
           b.origem, b.vencimento, b.saldo_a_pagar
      from cs.vw_fin_board b
      left join public.thb_alunos alu on alu.id = b.aluno_id
     where b.origem in ('HM','AURUM') and b.vencimento >= v_dia and b.vencimento <= p_ate
       and coalesce(b.saldo_a_pagar, 0) > 0.5
       and b.status_financeiro not in ('cancelado','reembolsado','quitado')
       and not exists (
         select 1 from cs.hm_comprador_alias al
           join cs.contatos_hm cx on cx.id = b.contato_hm_id
           join cs.contatos_hm cc on cc.comprador_id = al.canonico_id and cc.produto = cx.produto
          where al.comprador_id = b.comprador_id)
  ), plano as materialized (
    select t.email, t.familia
      from fin.vw_transacoes t
     where t.email in (select bd.email from bd)
       and t.oferta_modo like 'HOTMART_INSTALLMENTS%' and t.recorrencia is not null
     group by t.email, t.familia, t.oferta_codigo
    having max(t.parcelas) > coalesce(max(t.recorrencia) filter (where t.grupo = 'pago'), 0)
  )
  -- blocos 3 e 4
  select l.bl,
         case when l.bl = 3 then case l.chave when 'hm_avulso' then 'HM avulso' when 'holding_total' then 'Holding Total'
                                              when 'outros' then 'Outros produtos' else l.chave end
              else ev.nome end,
         l.comp, l.dc, l.valor, 'a_receber'::text, l.od,
         case l.bl when 3 then 'vn:' else 'ep:' end || l.chave,
         case when l.bl = 3 then l.bases else 'Referência: ' || ev.ref_nome end,
         null::text, null::int,
         case when l.comp = 'antecipacao' then l.det end,   -- 1× por venda (a garantia é a mesma venda), como o bloco 2
         l.valor, 1::numeric, 'estimado'::text, '1. Receita de vendas (Hotmart)'::text,
         concat_ws(' · ',
           case l.comp when 'antecipacao' then coalesce(vg.t_ant, 'Antecipação') else coalesce(vg.t_ret, 'Retido') end,
           case when l.bl = 3 then 'Venda nova por dia = valor semanal ÷ 7 (' || l.bases || ')'
                else 'Evento planejado: tamanho ' || replace(pg_catalog.trim_scale(ev.tam)::text, '.', ',')
                     || ' × venda do dia de ' || ev.ref_nome || ' (cenário ' || v_cen || ')' end),
         v_cen
    from lin l
    left join ev on l.bl = 4 and ev.id::text = l.chave
    left join vig vg on l.od >= vg.de and (vg.ate is null or l.od < vg.ate)
  union all
  -- bloco 3 sem base (nem premissa, nem sugestão) em algum dia: visível, fora da soma
  select 3::smallint,
         case s.grupo when 'hm_avulso' then 'HM avulso' when 'holding_total' then 'Holding Total'
                      when 'outros' then 'Outros produtos' else s.grupo end,
         'cheio'::text, null::date, null::numeric, 'sem_base'::text, null::date, 'vn:' || s.grupo, 'sem base'::text,
         null::text, null::int, null::jsonb, null::numeric, 1::numeric, 'estimado'::text,
         '1. Receita de vendas (Hotmart)'::text,
         'Sem sugestão medida (nenhuma semana completa sem evento em 52) e sem premissa: grupo fora da projeção'::text, v_cen
    from (select distinct vn.grupo from vn where vn.semanal is null) s
  union all
  -- bloco 6: reserva negativa por data de caixa
  select 6::smallint, 'Reserva de reembolso e chargeback'::text, 'reserva'::text, b.dc,
         -pg_catalog.round(b.pct * b.base_valor, 2), 'a_receber'::text, null::date, 'reserva'::text, b.origem,
         null::text, null::int, null::jsonb, -pg_catalog.round(b.pct * b.base_valor, 2), 1::numeric, 'estimado'::text,
         '3. (Devoluções)'::text,
         'Reserva ' || fin.receber_pct(b.pct) || ' sobre as vendas novas estimadas do dia (blocos 3 e 4; base '
           || fin.receber_brl(b.base_valor) || ') · ' || b.origem,
         v_cen
    from b6p b
   where b.pct > 0
  union all
  select 6::smallint, 'Reserva de reembolso e chargeback'::text, 'reserva'::text, null::date, null::numeric,
         'sem_base'::text, null::date, 'reserva'::text, 'sem base'::text, null::text, null::int, null::jsonb,
         null::numeric, 1::numeric, 'estimado'::text, '3. (Devoluções)'::text,
         'Sem taxa medida (nada vendido em 9 meses) e sem premissa: reserva fora da projeção'::text, v_cen
   where exists (select 1 from b6p b where b.pct is null)
  union all
  -- bloco 8: acordos combinados no board — informativo, fora da soma
  select 8::smallint, 'Informativo: acordos no board'::text, 'cheio'::text, b.vencimento, b.saldo_a_pagar,
         'informativo'::text, b.vencimento, b.contato_hm_id::text, b.rotulo,
         case b.origem when 'AURUM' then 'Aurum' else 'Holding Masters' end, null::int, null::jsonb,
         b.saldo_a_pagar, 1::numeric, 'informativo'::text, null::text,
         'Saldo combinado no board: informativo, fora da soma (somar contaria duas vezes com a venda nova do bloco 3)'::text,
         v_cen
    from bd b
   where not exists (select 1 from plano p where p.email = b.email and p.familia = b.origem);
end $$;
comment on function fin.receber_projecao(timestamptz, date, text) is
  'Contas a Receber (z67; Kirad z69): blocos 3 (vendas novas), 4 (evento planejado, só os que tocam o horizonte), '
  '6 (reserva, negativa) e 8 (acordos do board, informativo, fora da soma; nome e fonte = fn_fin_board). Interna.';
revoke all on function fin.receber_projecao(timestamptz, date, text) from public, anon, authenticated;

create or replace function public.fn_fin_eventos_planejados_listar()
returns table (id bigint, nome text, abertura date, fim_vendas date, evento_ref_id bigint, evento_ref_nome text,
               evento_ref_abertura date, evento_ref_venda_ate date, total_ref numeric, curva jsonb,
               tamanho_base numeric, tamanho_conservador numeric, tamanho_otimista numeric, pausa_avulso boolean,
               observacao text, situacao text, criado_em timestamptz, criado_por_nome text, atualizado_em timestamptz,
               atualizado_por_nome text, arquivado_em timestamptz, arquivado_por_nome text, arquivado_motivo text)
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
  select p.id, p.nome, p.abertura, p.abertura + (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)),
         p.evento_ref_id, e.nome, coalesce(e.carrinho_inicio, e.inicio), e.venda_ate, c.total, c.curva,
         p.tamanho_base, p.tamanho_conservador, p.tamanho_otimista, p.pausa_avulso, p.observacao,
         case when p.arquivado_em is not null then 'arquivado'
              when p.abertura + (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) < v_hoje then 'encerrado'
              else 'ativo' end,
         p.criado_em, pc.nome, p.atualizado_em, pu.nome, p.arquivado_em, pa.nome, p.arquivado_motivo
    from fin.eventos_planejados p
    join fin.eventos e on e.id = p.evento_ref_id
    left join lateral (
      select max(x.total) total,
             jsonb_agg(jsonb_build_object('d', x.d, 'liquido', x.liquido, 'participacao', x.participacao) order by x.d) curva
        from fin.receber_curva_evento(p.evento_ref_id) x
       where p.arquivado_em is null   -- z69 (Kirad): curva só de evento não arquivado (One-Time Filter: não chama a função)
    ) c on true
    left join public.perfis pc on pc.id = p.criado_por
    left join public.perfis pu on pu.id = p.atualizado_por
    left join public.perfis pa on pa.id = p.arquivado_por
   order by (p.arquivado_em is not null), p.abertura desc, p.id desc;
end $$;
revoke all on function public.fn_fin_eventos_planejados_listar() from public, anon;
grant execute on function public.fn_fin_eventos_planejados_listar() to authenticated;

create or replace function public.fn_fin_evento_planejado_salvar(p jsonb)
returns table (id bigint, nome text, abertura date, evento_ref_id bigint, situacao text)
language plpgsql volatile security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_id    bigint;
  v_nome  text;
  v_ab    date;
  v_ref   bigint;
  v_tb    numeric;
  v_tc    numeric;
  v_to    numeric;
  v_pausa boolean;
  v_obs   text;
  v_fora  text;
  v_e     fin.eventos;
  v_tot   numeric;
  v_arq   timestamptz;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'Evento planejado: envie um objeto.' using errcode = '22023';
  end if;
  select string_agg(x.k, ', ') into v_fora from jsonb_object_keys(p) x(k)
   where x.k not in ('id','nome','abertura','evento_ref_id','tamanho_base','tamanho_conservador','tamanho_otimista',
                     'pausa_avulso','observacao');
  if v_fora is not null then
    raise exception 'Evento planejado: campo desconhecido (%).', v_fora using errcode = '22023';
  end if;
  begin
    v_id    := nullif(btrim(p ->> 'id'), '')::bigint;
    v_nome  := btrim(p ->> 'nome');
    v_ab    := (p ->> 'abertura')::date;
    v_ref   := (p ->> 'evento_ref_id')::bigint;
    v_tb    := (p ->> 'tamanho_base')::numeric;
    v_tc    := (p ->> 'tamanho_conservador')::numeric;
    v_to    := (p ->> 'tamanho_otimista')::numeric;
    v_pausa := coalesce((p ->> 'pausa_avulso')::boolean, true);
    v_obs   := nullif(btrim(p ->> 'observacao'), '');
  exception when others then
    raise exception 'Evento planejado: campo com formato inválido (data AAAA-MM-DD, número com ponto, pausa true/false).'
      using errcode = '22023';
  end;
  if coalesce(v_nome, '') = '' or length(v_nome) > 120 then
    raise exception 'Evento planejado: nome vazio ou longo demais (até 120).' using errcode = '22023';
  end if;
  if v_ab is null or v_ab < v_hoje - 31 or v_ab > v_hoje + 400 then
    raise exception 'Evento planejado: abertura entre 31 dias atrás e 400 dias à frente.' using errcode = '22023';
  end if;
  if v_tb is null or v_tc is null or v_to is null or least(v_tb, v_tc, v_to) <= 0 or greatest(v_tb, v_tc, v_to) > 20
     or not (v_tc <= v_tb and v_tb <= v_to) then
    raise exception 'Evento planejado: tamanhos maiores que 0 e até 20, com conservador ≤ base ≤ otimista.' using errcode = '22023';
  end if;
  if v_obs is not null and length(v_obs) > 500 then
    raise exception 'Evento planejado: observação longa demais (até 500).' using errcode = '22023';
  end if;
  select e.* into v_e from fin.eventos e where e.id = v_ref;
  if not found then
    raise exception 'Evento de referência não existe.' using errcode = '22023';
  end if;
  if v_e.setor <> 'educacao' then
    raise exception 'O evento de referência tem que ser da educação (a conta do escritório não está no espelho).' using errcode = '22023';
  end if;
  if v_e.venda_ate >= v_hoje then
    raise exception 'O evento de referência ainda não terminou as vendas: a curva estaria incompleta.' using errcode = '22023';
  end if;
  if v_e.venda_ate - coalesce(v_e.carrinho_inicio, v_e.inicio) > 30 then
    raise exception 'O evento de referência tem mais de 31 dias de venda: escolha um evento com curva curta.' using errcode = '22023';
  end if;
  select max(c.total) into v_tot from fin.receber_curva_evento(v_ref) c;
  if coalesce(v_tot, 0) <= 0 then
    raise exception 'O evento de referência não tem venda no espelho (oferta do evento, 1ª cobrança, sem Aurum/Diamante).'
      using errcode = '22023';
  end if;

  if v_id is null then
    -- z69 (Kirad): teto de 30 eventos não arquivados (a listagem calcula a curva de cada um). Trava de transação: duas
    -- criações simultâneas não passam juntas do teto.
    perform pg_advisory_xact_lock(hashtext('fin.eventos_planejados:teto'));
    if (select count(*) from fin.eventos_planejados ep where ep.arquivado_em is null) >= 30 then
      raise exception 'Evento planejado: limite de 30 eventos não arquivados. Arquive um encerrado antes de cadastrar outro.'
        using errcode = '22023';
    end if;
    insert into fin.eventos_planejados as ep (nome, abertura, evento_ref_id, tamanho_base, tamanho_conservador,
                                              tamanho_otimista, pausa_avulso, observacao, criado_por)
    values (v_nome, v_ab, v_ref, v_tb, v_tc, v_to, v_pausa, v_obs, v_uid)
    returning ep.id into v_id;
  else
    select ep.arquivado_em into v_arq from fin.eventos_planejados ep where ep.id = v_id for update;
    if not found then
      raise exception 'Evento planejado não existe.' using errcode = '22023';
    end if;
    if v_arq is not null then
      raise exception 'Evento planejado arquivado não muda: cadastre outro.' using errcode = '22023';
    end if;
    update fin.eventos_planejados ep
       set nome = v_nome, abertura = v_ab, evento_ref_id = v_ref, tamanho_base = v_tb, tamanho_conservador = v_tc,
           tamanho_otimista = v_to, pausa_avulso = v_pausa, observacao = v_obs, atualizado_em = now(), atualizado_por = v_uid
     where ep.id = v_id;
  end if;
  return query
  select ep.id, ep.nome, ep.abertura, ep.evento_ref_id,
         case when ep.abertura + (v_e.venda_ate - coalesce(v_e.carrinho_inicio, v_e.inicio)) < v_hoje then 'encerrado'
              else 'ativo' end
    from fin.eventos_planejados ep where ep.id = v_id;
end $$;
revoke all on function public.fn_fin_evento_planejado_salvar(jsonb) from public, anon;
grant execute on function public.fn_fin_evento_planejado_salvar(jsonb) to authenticated;


-- ─── 3. As fotos (só acréscimo) ─────────────────────────────────────────────────────────────────────────────────────
create table fin.receber_fotos_cabecalho (
  foto_em         timestamptz primary key,
  dia             date not null,
  cenario         text not null check (cenario in ('base','conservador','otimista')),
  corte           timestamptz not null,
  ate             date not null,
  linhas          int not null check (linhas >= 0),
  soma_a_receber  numeric not null,
  feita_por       text not null default current_user,
  constraint receber_fotos_cabecalho_dia_cenario_key unique (dia, cenario)
);
comment on table fin.receber_fotos_cabecalho is
  'Contas a Receber (z69): uma linha por fotografia da previsão. dia = dia do corte em São Paulo; (dia, cenario) único = '
  'idempotência de fin.receber_fotografar. soma_a_receber = Σ valor com situacao a_receber (a soma da tela). Só acréscimo.';

create table fin.receber_fotos (
  foto_em      timestamptz not null references fin.receber_fotos_cabecalho (foto_em),
  corte        timestamptz not null,
  cenario      text not null,
  bloco        smallint not null,
  grupo        text,
  ref          text,
  origem_dia   date,
  data_caixa   date,
  componente   text not null,
  valor        numeric,
  valor_bruto  numeric,
  certeza      text,
  situacao     text not null
);
create unique index receber_fotos_chave_uidx on fin.receber_fotos
  (foto_em, bloco, grupo, ref, data_caixa, componente, origem_dia, situacao) nulls not distinct;
comment on table fin.receber_fotos is
  'Contas a Receber (z69): as linhas de fin.receber_posicao no corte da foto, agregadas por (bloco, grupo, ref, '
  'data_caixa, componente, origem_dia, situacao). Sem nome, e-mail, documento, rótulo, produto, detalhe ou tratamento. '
  'ref: bloco 2 HMAC do contrato; 5 id do informado; 8 id do card; 3/4/6 chaves da projeção; 1 nulo. Só acréscimo.';

create function fin.tg_receber_fotos_so_acrescimo()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'fin.%: só acréscimo (% bloqueado). Foto é histórico: não se edita nem apaga.', tg_table_name, tg_op
    using errcode = 'P0001';
end $$;
revoke all on function fin.tg_receber_fotos_so_acrescimo() from public, anon, authenticated;

create trigger receber_fotos_so_acrescimo before update or delete on fin.receber_fotos
  for each row execute function fin.tg_receber_fotos_so_acrescimo();
create trigger receber_fotos_nao_trunca before truncate on fin.receber_fotos
  for each statement execute function fin.tg_receber_fotos_so_acrescimo();
create trigger receber_fotos_cabecalho_so_acrescimo before update or delete on fin.receber_fotos_cabecalho
  for each row execute function fin.tg_receber_fotos_so_acrescimo();
create trigger receber_fotos_cabecalho_nao_trunca before truncate on fin.receber_fotos_cabecalho
  for each statement execute function fin.tg_receber_fotos_so_acrescimo();

alter table fin.receber_fotos_cabecalho enable row level security;
alter table fin.receber_fotos enable row level security;
revoke all on table fin.receber_fotos_cabecalho from public, anon, authenticated;
revoke all on table fin.receber_fotos from public, anon, authenticated;


-- ─── 4. Fotografar (interna) ────────────────────────────────────────────────────────────────────────────────────────
-- p_corte: só para chamada manual (reconstrução/teste). O cron usa o default (agora). Foto reconstruída usa os dados de
-- AGORA (status, informados, board) — fn_fin_receber_fotos_listar a marca como reconstruida.
create function fin.receber_fotografar(p_cenario text default 'base', p_corte timestamptz default null)
returns table (foto_em timestamptz, corte timestamptz, nova boolean, linhas int, soma_a_receber numeric)
language plpgsql volatile set search_path = ''
as $$
#variable_conflict use_column
declare
  v_cen   text := coalesce(p_cenario, 'base');
  v_corte timestamptz := coalesce(p_corte, now());
  v_foto  timestamptz := pg_catalog.clock_timestamp();
  v_dia   date;
  v_ate   date;
begin
  if v_cen not in ('base','conservador','otimista') then
    raise exception 'Cenário inválido (base, conservador ou otimista).' using errcode = '22023';
  end if;
  if v_corte > now() then
    raise exception 'fin.receber_fotografar: corte no futuro' using errcode = '22023';
  end if;
  v_dia := (v_corte at time zone 'America/Sao_Paulo')::date;
  v_ate := (date_trunc('month', v_dia::timestamp) + interval '4 months' - interval '1 day')::date;   -- o default da tela

  -- idempotência por (dia do corte, cenário): já existe → devolve a existente
  return query
  select c.foto_em, c.corte, false, c.linhas, c.soma_a_receber
    from fin.receber_fotos_cabecalho c where c.dia = v_dia and c.cenario = v_cen;
  if found then return; end if;

  with p as materialized (
    select x.bloco, x.grupo, x.ref, x.origem_dia, x.data_caixa, x.componente, x.situacao, x.certeza,
           sum(x.valor) valor, sum(x.valor_bruto) valor_bruto
      from fin.receber_posicao(v_corte, v_ate, v_cen) x
     where x.bloco <> 8   -- Kirad z69: o informativo do board não é lido por nenhuma RPC → não se guarda (LGPD art. 6º III)
     group by x.bloco, x.grupo, x.ref, x.origem_dia, x.data_caixa, x.componente, x.situacao, x.certeza
  ), h as (
    -- corrida: a UNIQUE (dia, cenario) decide; quem perde não grava linha nenhuma
    insert into fin.receber_fotos_cabecalho as c (foto_em, dia, cenario, corte, ate, linhas, soma_a_receber)
    select v_foto, v_dia, v_cen, v_corte, v_ate, (select count(*) from p)::int,
           coalesce((select sum(p.valor) from p where p.situacao = 'a_receber'), 0)
    on conflict (dia, cenario) do nothing
    returning c.foto_em
  )
  insert into fin.receber_fotos (foto_em, corte, cenario, bloco, grupo, ref, origem_dia, data_caixa, componente, valor,
                                 valor_bruto, certeza, situacao)
  select h.foto_em, v_corte, v_cen, p.bloco, p.grupo, p.ref, p.origem_dia, p.data_caixa, p.componente, p.valor,
         p.valor_bruto, p.certeza, p.situacao
    from p cross join h;

  return query
  select c.foto_em, c.corte, c.foto_em = v_foto, c.linhas, c.soma_a_receber
    from fin.receber_fotos_cabecalho c where c.dia = v_dia and c.cenario = v_cen;
end $$;
comment on function fin.receber_fotografar(text, timestamptz) is
  'Contas a Receber (z69): grava a foto da previsão (fin.receber_posicao, horizonte padrão da tela) no cenário. '
  'Idempotente por (dia do corte em SP, cenário). Interna: sem guarda de sessão; quem chama é o cron (postgres).';
revoke all on function fin.receber_fotografar(text, timestamptz) from public, anon, authenticated;


-- ─── 5. RPCs ────────────────────────────────────────────────────────────────────────────────────────────────────────
create function public.fn_fin_receber_fotos_listar()
returns table (foto_em timestamptz, dia date, cenario text, corte timestamptz, ate date, linhas int,
               soma_a_receber numeric, reconstruida boolean)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select c.foto_em, c.dia, c.cenario, c.corte, c.ate, c.linhas, c.soma_a_receber,
         (c.foto_em at time zone 'America/Sao_Paulo')::date > c.dia
    from fin.receber_fotos_cabecalho c
   order by c.foto_em desc;
end $$;
comment on function public.fn_fin_receber_fotos_listar() is
  'Contas a Receber (z69): fotos disponíveis (mais nova primeiro), com a soma a receber de cada uma.';
revoke all on function public.fn_fin_receber_fotos_listar() from public, anon;
grant execute on function public.fn_fin_receber_fotos_listar() to authenticated;

create function public.fn_fin_receber_mudancas(p_foto_a timestamptz, p_foto_b timestamptz)
returns table (bloco smallint, grupo text, valor_a numeric, valor_b numeric, delta numeric, motivos jsonb)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_cen_a text;
  v_cen_b text;
  v_dia_b date;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_foto_a is null or p_foto_b is null then
    raise exception 'Informe as duas fotos.' using errcode = '22023';
  end if;
  select c.cenario into v_cen_a from fin.receber_fotos_cabecalho c where c.foto_em = p_foto_a;
  select c.cenario, c.dia into v_cen_b, v_dia_b from fin.receber_fotos_cabecalho c where c.foto_em = p_foto_b;
  if v_cen_a is null or v_cen_b is null then
    raise exception 'Foto não encontrada (use fn_fin_receber_fotos_listar).' using errcode = '22023';
  end if;

  return query
  with a as materialized (
    select f.bloco, f.grupo, coalesce(f.ref, '') r,
           coalesce(case when f.bloco in (1, 2) then f.origem_dia when f.bloco = 5 then null else f.data_caixa end,
                    date '0001-01-01') kd,
           f.componente, f.situacao, f.data_caixa, f.origem_dia, f.valor, f.valor_bruto
      from fin.receber_fotos f where f.foto_em = p_foto_a
  ), b as materialized (
    select f.bloco, f.grupo, coalesce(f.ref, '') r,
           coalesce(case when f.bloco in (1, 2) then f.origem_dia when f.bloco = 5 then null else f.data_caixa end,
                    date '0001-01-01') kd,
           f.componente, f.situacao, f.data_caixa, f.origem_dia, f.valor, f.valor_bruto
      from fin.receber_fotos f where f.foto_em = p_foto_b
  ), ia as (
    select a.bloco, a.r, a.kd, a.componente, max(a.grupo) grupo, sum(a.valor) v, sum(a.valor_bruto) vb, max(a.data_caixa) dc
      from a where a.situacao = 'a_receber' group by 1, 2, 3, 4
  ), ib as (
    select b.bloco, b.r, b.kd, b.componente, max(b.grupo) grupo, sum(b.valor) v, sum(b.valor_bruto) vb
      from b where b.situacao = 'a_receber' group by 1, 2, 3, 4
  ), sb as (
    select b.bloco, b.r, b.kd, bool_or(b.situacao = 'realizada') pago, bool_or(b.situacao = 'em_atraso_fora') atraso,
           bool_or(b.situacao = 'coberta_informado') coberta
      from b where b.situacao <> 'a_receber' group by 1, 2, 3
  ), b2n as (
    select distinct b.r from b where b.bloco = 2 and b.situacao = 'realizada' and b.origem_dia is null
  ), j as (
    select coalesce(ib.bloco, ia.bloco) bloco, coalesce(ib.grupo, ia.grupo) grupo,
           coalesce(ib.r, ia.r) || '|' || coalesce(ib.kd, ia.kd) item, ia.v va, ib.v vb,
           case when ia.v is null and ib.v is null then null
                when ia.bloco is null then 'entrou'
                when ib.bloco is null then
                  case when sb.pago then 'saiu_pagamento'
                       when sb.atraso then 'saiu_atraso'
                       when sb.coberta then 'saiu_outro'
                       when ia.bloco = 2 and exists (select 1 from b2n where b2n.r = ia.r) then 'saiu_pagamento'
                       when ia.dc <= v_dia_b then case when ia.bloco in (1, 2, 5) then 'saiu_pagamento' else 'saiu_periodo' end
                       else 'saiu_outro' end
                when ia.v = ib.v then null
                when ia.bloco in (3, 4, 6) or v_cen_a <> v_cen_b or ia.vb = ib.vb then 'mudou_premissa'
                else 'mudou_valor' end motivo
      from ia
      full join ib on ib.bloco = ia.bloco and ib.r = ia.r and ib.kd = ia.kd and ib.componente = ia.componente
      left join sb on ib.bloco is null and sb.bloco = ia.bloco and sb.r = ia.r and sb.kd = ia.kd
  ), k as (
    select j.bloco, j.grupo, j.motivo, count(distinct j.item)::int itens, sum(coalesce(j.vb, 0) - coalesce(j.va, 0)) valor
      from j where j.motivo is not null group by 1, 2, 3
  ), t as (
    select j.bloco, j.grupo, coalesce(sum(j.va), 0) va, coalesce(sum(j.vb), 0) vb from j group by 1, 2
  )
  select t.bloco, t.grupo, t.va, t.vb, t.vb - t.va,
         coalesce((select jsonb_agg(jsonb_build_object('motivo', k.motivo, 'itens', k.itens, 'valor', k.valor)
                                    order by array_position(array['entrou','saiu_pagamento','saiu_atraso','saiu_periodo',
                                                                  'saiu_outro','mudou_valor','mudou_premissa'], k.motivo))
                     from k where k.bloco = t.bloco and k.grupo is not distinct from t.grupo), '[]'::jsonb)
    from t
   order by 1, 2;
end $$;
comment on function public.fn_fin_receber_mudancas(timestamptz, timestamptz) is
  'Contas a Receber (z69): foto A × foto B por (bloco, grupo): valor a receber em cada uma, delta e motivos '
  '[{motivo, itens, valor}] (entrou, saiu_pagamento, saiu_atraso, saiu_periodo, saiu_outro, mudou_valor, '
  'mudou_premissa). Σ motivos.valor = delta.';
revoke all on function public.fn_fin_receber_mudancas(timestamptz, timestamptz) from public, anon;
grant execute on function public.fn_fin_receber_mudancas(timestamptz, timestamptz) to authenticated;

create function public.fn_fin_receber_previsto_realizado(p_semanas int default 8)
returns table (linha text, semana_de date, semana_ate date, janela_de date, janela_ate date, foto_em timestamptz,
               bloco smallint, grupo text, previsto numeric, previsto_bruto numeric, realizado numeric, desvio numeric,
               acerto_pct numeric, chave_premissa text, perda_medida numeric, premissa_atual numeric,
               cobrancas_resolvidas int, cobrancas_perdidas int, valor_resolvido numeric, valor_perdido numeric,
               nota text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_seg  date;
  v_tol  int;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_semanas is null or p_semanas < 1 or p_semanas > 52 then
    raise exception 'Semanas: de 1 a 52.' using errcode = '22023';
  end if;
  v_seg := (date_trunc('week', v_hoje::timestamp))::date;
  v_tol := fin.premissa('tolerancia_atraso_dias', v_hoje, 'base')::int;
  if v_tol is null then
    raise exception 'Premissa tolerancia_atraso_dias ausente.' using errcode = 'P0002';
  end if;

  return query
  with fw as materialized (
    -- a semana, a foto base do início dela e a janela que a foto consegue prever
    select s.de, s.de + 6 ate, c.foto_em, c.corte, c.dia,
           case when c.foto_em is not null then greatest(s.de, c.dia + 1) end j0, s.de + 6 j1,
           (c.foto_em at time zone 'America/Sao_Paulo')::date > c.dia reconstruida
      from (select v_seg - 7 * g.n de from generate_series(1, p_semanas) g(n)) s
      left join lateral (
        select c.foto_em, c.corte, c.dia from fin.receber_fotos_cabecalho c
         where c.cenario = 'base' and c.dia <= s.de and c.dia > s.de - 7
         order by c.dia desc, c.foto_em desc limit 1
      ) c on true
  ), itens as materialized (
    select fw.de, f.bloco, f.grupo, f.ref, f.origem_dia, f.componente, f.data_caixa, f.valor, f.valor_bruto
      from fw join fin.receber_fotos f on f.foto_em = fw.foto_em
     where f.situacao = 'a_receber'
  ), prev as (
    select i.de, i.bloco, i.grupo, sum(i.valor) previsto, sum(i.valor_bruto) previsto_bruto
      from itens i join fw on fw.de = i.de
     where i.data_caixa between fw.j0 and fw.j1
     group by 1, 2, 3
  ), r1 as (
    -- bloco 1: as vendas pagas até o corte (status de AGORA), pela mesma função da previsão
    select fw.de, 1::smallint bloco, 'Vendas já realizadas'::text grupo, sum(v.valor) realizado
      from fw cross join lateral fin.receber_vendas_realizadas(fw.corte) v
     where fw.foto_em is not null and v.data_caixa between fw.j0 and fw.j1
     group by fw.de
  ), tx as materialized (
    -- vendas pagas DEPOIS do corte até o fim da janela (predicado literal do índice parcial aprovado_pago_idx)
    select fw.de, t.transacao, t.email, t.oferta_codigo, t.oferta_modo, t.produto_id, t.recorrencia, t.dia_aprovado,
           t.liquido
      from fw
      join fin.vw_transacoes t
        on t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em > fw.corte
       and t.aprovado_em < (fw.j1 + 1)::timestamp at time zone 'America/Sao_Paulo'
     where fw.foto_em is not null
  ), inf as materialized (
    select distinct i.de, i.ref::uuid id, i.grupo from itens i where i.bloco = 5
  ), alvo as materialized (
    select a.id, a.emails, a.docs from fin.informados_alvos() a where a.id in (select inf.id from inf)
  ), m5 as (
    -- bloco 5 via Hotmart: a mesma regra de casamento de fin.informados_situacao (e-mail OU documento, produto, acordo)
    select distinct on (x.de, x.transacao) x.de, x.transacao, inf.grupo
      from tx x
      join inf on inf.de = x.de
      join fin.recebimentos_informados r on r.id = inf.id and r.via_hotmart
      join alvo a on a.id = inf.id
      join fin.hotmart_transacoes h on h.transacao = x.transacao
     where x.produto_id = any (r.produto_ids) and x.dia_aprovado >= r.acordo_desde
       and (lower(trim(h.comprador_email)) = any (a.emails)
            or regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = any (a.docs))
     order by x.de, x.transacao, r.data_prevista, r.id
  ), rc as materialized (
    -- contrato recorrente → a MESMA ref opaca de fin.cobrancas_previstas ('rc:' || e-mail || '|' || oferta)
    select y.email, y.oferta_codigo, fin.chave_opaca('rc:' || y.email || '|' || y.oferta_codigo) ref
      from (select distinct x.email, x.oferta_codigo from tx x
             where x.recorrencia >= 2 and x.email is not null and x.oferta_codigo is not null
               and (x.oferta_modo in ('SUBSCRIPTION','MULTIPLE_PAYMENTS') or x.oferta_modo like 'HOTMART_INSTALLMENTS%')) y
  ), g2 as materialized (
    select distinct on (fw.de, f.ref) fw.de, f.ref, f.grupo
      from fw join fin.receber_fotos f on f.foto_em = fw.foto_em
     where f.bloco = 2
     order by fw.de, f.ref, f.grupo
  ), atrib as (
    select x.de, x.dia_aprovado, x.liquido,
           case when m5.transacao is not null then 5 when g2.ref is not null then 2 end::smallint bloco,
           coalesce(m5.grupo, g2.grupo, 'Fora da foto (vendas novas e outros)') grupo
      from tx x
      left join m5 on m5.de = x.de and m5.transacao = x.transacao
      left join rc on x.recorrencia >= 2 and rc.email = x.email and rc.oferta_codigo = x.oferta_codigo
                  and (x.oferta_modo in ('SUBSCRIPTION','MULTIPLE_PAYMENTS') or x.oferta_modo like 'HOTMART_INSTALLMENTS%')
      left join g2 on g2.de = x.de and g2.ref = rc.ref
  ), rpos as (
    select d.de, d.bloco, d.grupo,
           sum(case when r.entra_em between fw.j0 and fw.j1 then r.entra_rapido else 0 end
               + case when r.libera_em between fw.j0 and fw.j1 then r.retido else 0 end) realizado
      from (select a.de, a.bloco, a.grupo, a.dia_aprovado, sum(a.liquido) liq
              from atrib a group by 1, 2, 3, 4) d
      join fw on fw.de = d.de
      cross join lateral fin.recebimento(d.dia_aprovado, d.liq) r
     group by 1, 2, 3
  ), r5b as (
    -- baixa manual (fora da Hotmart): valor cheio na data da baixa
    select inf.de, 5::smallint bloco, inf.grupo, sum(r.valor) realizado
      from inf
      join fw on fw.de = inf.de
      join fin.recebimentos_informados r on r.id = inf.id
     where r.baixa_manual_em between fw.j0 and fw.j1
     group by 1, 2, 3
  ), rea as (
    select u.de, u.bloco, u.grupo, sum(u.realizado) realizado
      from (select * from r1 union all select * from rpos union all select * from r5b) u
     group by 1, 2, 3
  ), sem as (
    select fw.de, fw.ate, fw.j0, fw.j1, fw.foto_em, coalesce(p.bloco, r.bloco) bloco, coalesce(p.grupo, r.grupo) grupo,
           p.previsto, p.previsto_bruto,
           case when coalesce(p.bloco, r.bloco) in (3, 4, 6) then null else coalesce(r.realizado, 0) end realizado,
           case when fw.reconstruida then 'foto reconstruída (dados de hoje)' end nota
      from fw
      join (prev p full join rea r on r.de = p.de and coalesce(r.bloco, 0) = coalesce(p.bloco, 0) and r.grupo = p.grupo)
        on fw.de = coalesce(p.de, r.de)
     where fw.foto_em is not null and (p.previsto is not null or coalesce(r.realizado, 0) <> 0)
  ), coorte as (
    select i.de, i.grupo, i.ref, i.origem_dia, sum(i.valor_bruto) vb
      from itens i join fw on fw.de = i.de
     where i.bloco = 2 and i.origem_dia between fw.de and fw.ate
     group by 1, 2, 3, 4
  ), res as materialized (
    select fw.de, c.foto_em
      from fw
      cross join lateral (
        select c.foto_em from fin.receber_fotos_cabecalho c
         where c.cenario = 'base' and c.dia > fw.ate + v_tol
         order by c.dia, c.foto_em limit 1
      ) c
     where fw.foto_em is not null
  ), rf as materialized (
    select res.de, f.ref, f.origem_dia, bool_or(f.situacao = 'realizada') pago, bool_or(f.situacao = 'em_atraso_fora') atraso,
           bool_or(f.situacao = 'coberta_informado') coberta, bool_or(f.situacao = 'a_receber') aberta
      from res join fin.receber_fotos f on f.foto_em = res.foto_em and f.bloco = 2
     group by 1, 2, 3
  ), rref as (
    select rf.de, rf.ref, bool_or(rf.pago and rf.origem_dia is null) pago_sem_venc from rf group by 1, 2
  ), est as (
    select co.grupo, co.vb,
           case when res.foto_em is null then 'pendente'
                when x.pago then 'paga'
                when x.coberta then 'fora'
                when x.atraso then 'perdida'
                when x.aberta then 'pendente'
                when y.pago_sem_venc then 'paga'
                when y.ref is null then 'perdida'
                else 'fora' end st
      from coorte co
      left join res on res.de = co.de
      left join rf x on x.de = co.de and x.ref = co.ref and x.origem_dia = co.origem_dia
      left join rref y on y.de = co.de and y.ref = co.ref
  ), perda as (
    select e.grupo, count(*) filter (where e.st in ('paga','perdida'))::int resolvidas,
           count(*) filter (where e.st = 'perdida')::int perdidas,
           coalesce(sum(e.vb) filter (where e.st in ('paga','perdida')), 0) v_res,
           coalesce(sum(e.vb) filter (where e.st = 'perdida'), 0) v_perd
      from est e group by 1
  )
  select 'semana'::text, s.de, s.ate, s.j0, s.j1, s.foto_em, s.bloco, s.grupo, s.previsto, s.previsto_bruto, s.realizado,
         s.realizado - coalesce(s.previsto, 0),
         case when s.previsto > 0 and s.realizado is not null
              then pg_catalog.round(greatest(0::numeric, 100 * (1 - abs(s.realizado - s.previsto) / s.previsto)), 1) end,
         null::text, null::numeric, null::numeric, null::int, null::int, null::numeric, null::numeric, s.nota
    from sem s
  union all
  select 'semana'::text, fw.de, fw.ate, null::date, null::date, null::timestamptz, null::smallint, null::text,
         null::numeric, null::numeric, null::numeric, null::numeric, null::numeric, null::text, null::numeric,
         null::numeric, null::int, null::int, null::numeric, null::numeric, 'sem foto base no início da semana'::text
    from fw where fw.foto_em is null
  union all
  select 'perda'::text, null::date, null::date, null::date, null::date, null::timestamptz, 2::smallint, pe.grupo,
         null::numeric, null::numeric, null::numeric, null::numeric, null::numeric, m.chave,
         case when pe.v_res > 0 then pg_catalog.round(pe.v_perd / pe.v_res, 4) end,
         fin.premissa(m.chave, v_hoje, 'base'),
         pe.resolvidas, pe.perdidas, pe.v_res, pe.v_perd,
         'sugestão medida (não grava): perdidas ÷ resolvidas, por valor, nas ' || p_semanas || ' semanas'
    from perda pe
    left join (values ('Assinaturas Serviço Diamante'::text,         'perda_mensal:servico_diamante'::text),
                      ('Assinaturas Holding - Holding Masters'::text, 'perda_mensal:holding_hm'::text),
                      ('Outras assinaturas'::text,                    'perda_mensal:outras_assinaturas'::text),
                      ('Parcelas a vencer HM'::text,                  'perda_mensal:parcelas_hm'::text),
                      ('Parcelas a vencer Aurum'::text,               'perda_mensal:parcelas_aurum'::text),
                      ('Parcelas a vencer outros'::text,              'perda_mensal:parcelas_outros'::text)
              ) m(grupo, chave) on m.grupo = pe.grupo
   order by 1 desc, 2 desc nulls last, 7 nulls last, 8;
end $$;
comment on function public.fn_fin_receber_previsto_realizado(int) is
  'Contas a Receber (z69): previsto (foto base do início de cada semana) × realizado (regra de caixa sobre as vendas '
  'pagas + baixas manuais) por semana e (bloco, grupo), com acerto %; e a perda medida do bloco 2 por grupo como '
  'sugestão para perda_mensal (só devolve).';
revoke all on function public.fn_fin_receber_previsto_realizado(int) from public, anon;
grant execute on function public.fn_fin_receber_previsto_realizado(int) to authenticated;


-- ─── 6. Cron semanal + 1ª foto ──────────────────────────────────────────────────────────────────────────────────────
select cron.schedule('fin-receber-foto-semanal', '11 9 * * 1', $c$select fin.receber_fotografar('base')$c$);

select * from fin.receber_fotografar('base');


-- ─── 9. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
do $chk$
declare
  v_adm   uuid;
  v_ok    boolean;
  v_n     int;
  v_m     int;
  v_foto  timestamptz;
  v_corte timestamptz;
  v_ate   date;
  v_soma  numeric;
  v_x     numeric;
  v_y     numeric;
  v_esp   text;
  v_obt   text;
  v_txt   text;
  f       text;
  t       text;
begin
  -- 9.1 grants: tabelas fechadas e com RLS; internas sem EXECUTE; RPCs só authenticated, definer, search_path ''
  foreach t in array array['fin.receber_fotos','fin.receber_fotos_cabecalho'] loop
    if has_table_privilege('anon', t, 'select,insert,update,delete,truncate,references,trigger')
       or has_table_privilege('authenticated', t, 'select,insert,update,delete,truncate,references,trigger') then
      raise exception 'z69: grant aberto em %', t;
    end if;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception 'z69: RLS desligada em %', t;
    end if;
  end loop;
  foreach f in array array['fin.receber_fotografar(text,timestamptz)','fin.tg_receber_fotos_so_acrescimo()',
                           'fin.receber_projecao(timestamptz,date,text)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z69: interna % executável por anon/authenticated', f;
    end if;
    if exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef) then
      raise exception 'z69: interna % é SECURITY DEFINER', f;
    end if;
  end loop;
  foreach f in array array['public.fn_fin_receber_fotos_listar()','public.fn_fin_receber_mudancas(timestamptz,timestamptz)',
                           'public.fn_fin_receber_previsto_realizado(integer)','public.fn_fin_eventos_planejados_listar()',
                           'public.fn_fin_evento_planejado_salvar(jsonb)'] loop
    if has_function_privilege('anon', f, 'execute') then raise exception 'z69: % executável por anon', f; end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z69: authenticated sem execute em %', f;
    end if;
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                      and p.proconfig = array['search_path=""']) then
      raise exception 'z69: % sem SECURITY DEFINER ou sem search_path vazio', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p
              where p.oid in ('fin.receber_fotografar(text,timestamptz)'::regprocedure,
                              'fin.tg_receber_fotos_so_acrescimo()'::regprocedure,
                              'fin.receber_projecao(timestamptz,date,text)'::regprocedure,
                              'public.fn_fin_receber_fotos_listar()'::regprocedure,
                              'public.fn_fin_receber_mudancas(timestamptz,timestamptz)'::regprocedure,
                              'public.fn_fin_receber_previsto_realizado(integer)'::regprocedure,
                              'public.fn_fin_eventos_planejados_listar()'::regprocedure,
                              'public.fn_fin_evento_planejado_salvar(jsonb)'::regprocedure)
                and (p.proacl is null or exists (select 1 from unnest(p.proacl) ac where ac::text like '=%'))) then
    raise exception 'z69: função com EXECUTE para PUBLIC (ou proacl nulo = padrão público)';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'fin'::regnamespace
         and proname in ('receber_projecao','receber_fotografar')) <> 2
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
            and proname in ('fn_fin_eventos_planejados_listar','fn_fin_evento_planejado_salvar','fn_fin_receber_fotos_listar',
                            'fn_fin_receber_mudancas','fn_fin_receber_previsto_realizado')) <> 5 then
    raise exception 'z69: sobrecarga viva';
  end if;
  if (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d
        join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
       where d.adrelid = 'fin.premissas_recebimento'::regclass and a.attname = 'dias_uteis') is distinct from 'true' then
    raise exception 'z69: DEFAULT de dias_uteis não virou true';
  end if;
  if not exists (select 1 from cron.job j where j.jobname = 'fin-receber-foto-semanal' and j.schedule = '11 9 * * 1'
                    and j.command = $c$select fin.receber_fotografar('base')$c$ and j.active) then
    raise exception 'z69: job fin-receber-foto-semanal ausente ou diferente';
  end if;

  -- 9.2 sem sessão → 42501 nas 3 RPCs novas
  foreach f in array array[
      'select * from public.fn_fin_receber_fotos_listar()',
      'select * from public.fn_fin_receber_mudancas(now(), now())',
      'select * from public.fn_fin_receber_previsto_realizado(8)'] loop
    v_ok := false;
    begin
      execute f;
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z69: RPC respondeu sem sessão: %', f; end if;
  end loop;

  -- 9.3 a 1ª foto = fin.receber_posicao no mesmo corte, linha a linha e ao centavo
  select c.foto_em, c.corte, c.ate, c.soma_a_receber, c.linhas into v_foto, v_corte, v_ate, v_soma, v_n
    from fin.receber_fotos_cabecalho c
   where c.dia = (now() at time zone 'America/Sao_Paulo')::date and c.cenario = 'base';
  if v_foto is null then raise exception 'z69: 1ª foto não gravada'; end if;
  select coalesce(sum(x.valor) filter (where x.situacao = 'a_receber'), 0) into v_x
    from fin.receber_posicao(v_corte, v_ate, 'base') x;
  select coalesce(sum(f.valor) filter (where f.situacao = 'a_receber'), 0), count(*) into v_y, v_m
    from fin.receber_fotos f where f.foto_em = v_foto;
  if v_x is distinct from v_soma or v_y is distinct from v_soma or v_m <> v_n then
    raise exception 'z69: 1ª foto ≠ posição (posição %, cabeçalho %, linhas %, linhas no cabeçalho %)', v_x, v_y, v_m, v_n;
  end if;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_esp
    from (select x.bloco, x.grupo, x.ref, x.origem_dia, x.data_caixa, x.componente, x.situacao, x.certeza,
                 sum(x.valor) valor, sum(x.valor_bruto) valor_bruto
            from fin.receber_posicao(v_corte, v_ate, 'base') x
           where x.bloco <> 8
           group by 1, 2, 3, 4, 5, 6, 7, 8) z;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_obt
    from (select f.bloco, f.grupo, f.ref, f.origem_dia, f.data_caixa, f.componente, f.situacao, f.certeza, f.valor,
                 f.valor_bruto
            from fin.receber_fotos f where f.foto_em = v_foto) z;
  if v_esp is distinct from v_obt then raise exception 'z69: linhas da 1ª foto ≠ posição agregada'; end if;
  if exists (select 1 from fin.receber_fotos f where f.bloco = 8) then
    raise exception 'z69: bloco 8 (informativo do board) gravado na foto';
  end if;
  if exists (select 1 from fin.receber_fotos f where f.foto_em = v_foto and (f.corte <> v_corte or f.cenario <> 'base')) then
    raise exception 'z69: corte/cenário da linha ≠ cabeçalho';
  end if;

  -- 9.4 idempotência: 2ª chamada no mesmo dia não grava
  select count(*) into v_n from fin.receber_fotos;
  select count(*) into v_m from fin.receber_fotos_cabecalho;
  if (select r.nova from fin.receber_fotografar('base') r) is distinct from false
     or (select count(*) from fin.receber_fotos) <> v_n or (select count(*) from fin.receber_fotos_cabecalho) <> v_m then
    raise exception 'z69: fotografar não é idempotente por (dia, cenário)';
  end if;

  -- 9.5 só acréscimo: UPDATE, DELETE e TRUNCATE barrados nas duas tabelas (mesmo como postgres)
  foreach f in array array[
      'update fin.receber_fotos set valor = valor where foto_em = ''' || v_foto || '''',
      'delete from fin.receber_fotos where foto_em = ''' || v_foto || '''',
      'truncate fin.receber_fotos',
      'update fin.receber_fotos_cabecalho set linhas = linhas where foto_em = ''' || v_foto || '''',
      'delete from fin.receber_fotos_cabecalho where foto_em = ''' || v_foto || '''',
      'truncate fin.receber_fotos_cabecalho cascade'] loop
    v_ok := false;
    begin
      execute f;
    exception when others then
      v_ok := sqlerrm like 'fin.receber_fotos%: só acréscimo%';
    end;
    if not v_ok then raise exception 'z69: só-acréscimo não barrou: %', f; end if;
  end loop;

  -- 9.6 Kirad 1: rótulo do bloco 8 = nome do fn_fin_board; nenhum card fora do board (gêmeo)
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z69: nenhum perfil admin ativo para conferir o board'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  select count(*), string_agg(x.ref, ', ') into v_n, v_txt
    from fin.receber_projecao(now(), (now() at time zone 'America/Sao_Paulo')::date + 400, 'base') x
    left join (select b.contato_hm_id::text id, b.nome::text nome from public.fn_fin_board() b) fb on fb.id = x.ref
   where x.bloco = 8 and (fb.id is null or x.rotulo is distinct from fb.nome);
  if v_n <> 0 then raise exception 'z69: bloco 8 com rótulo ≠ board ou card fora do board: %', v_txt; end if;

  -- 9.7 RPCs com sessão: mudanças da foto com ela mesma = nada; previsto × realizado responde
  if exists (select 1 from public.fn_fin_receber_mudancas(v_foto, v_foto) m where m.delta <> 0 or m.motivos <> '[]'::jsonb) then
    raise exception 'z69: mudancas(A, A) devolveu mudança';
  end if;
  if (select coalesce(sum(m.valor_a), 0) from public.fn_fin_receber_mudancas(v_foto, v_foto) m) <> v_soma then
    raise exception 'z69: mudancas(A, A).valor_a ≠ soma da foto';
  end if;
  if (select count(*) from public.fn_fin_receber_fotos_listar() l where l.foto_em = v_foto) <> 1 then
    raise exception 'z69: fotos_listar sem a 1ª foto';
  end if;
  if (select count(*) from public.fn_fin_receber_previsto_realizado(8) r where r.linha = 'semana') < 8 then
    raise exception 'z69: previsto × realizado sem as 8 semanas';
  end if;
  perform set_config('request.jwt.claims', '', true);
end $chk$;

drop function pg_temp.z69_norm(text);
drop function pg_temp.z69_cron_bate(text, int);


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres; cada bloco é UMA chamada — o MCP é autocommit) ════════════════
-- <UUID_FINANCEIRO> = perfis.id ativo que VÊ o financeiro. explain: rodar 2× e usar a 2ª (1ª é cache frio).
/*
-- P1) Tamanho por foto (linhas, bytes das linhas) e projeção de 1 ano (52 fotos base) pela média medida.
--     PGlite (dados sintéticos, 12 fotos): 90–115 linhas/foto, 15–20 KB de linhas; tabela + índice ≈ 420 bytes/linha.
select c.foto_em, c.cenario, c.linhas, c.soma_a_receber,
       (select sum(pg_column_size(f.*)) from fin.receber_fotos f where f.foto_em = c.foto_em) bytes_linhas
  from fin.receber_fotos_cabecalho c order by c.foto_em;
select count(*) fotos, sum(c.linhas) linhas,
       pg_size_pretty(pg_total_relation_size('fin.receber_fotos')) tabela_mais_indice,
       pg_size_pretty(pg_relation_size('fin.receber_fotos_chave_uidx')) indice,
       pg_size_pretty((52 * pg_total_relation_size('fin.receber_fotos') / count(*))::bigint) projecao_1_ano,
       52 * sum(c.linhas) / count(*) linhas_1_ano
  from fin.receber_fotos_cabecalho c;
select f.bloco, f.situacao, count(*) from fin.receber_fotos f group by 1, 2 order by 1, 2;

-- P2) As 3 RPCs (plpgsql: o explain de fora mostra Function Scan; o tempo total é o que importa).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_receber_fotos_listar();
explain (analyze, buffers) select * from public.fn_fin_receber_fotos_listar();
explain (analyze, buffers) select * from public.fn_fin_receber_mudancas(
  (select min(foto_em) from fin.receber_fotos_cabecalho), (select max(foto_em) from fin.receber_fotos_cabecalho));
explain (analyze, buffers) select * from public.fn_fin_receber_mudancas(
  (select min(foto_em) from fin.receber_fotos_cabecalho), (select max(foto_em) from fin.receber_fotos_cabecalho));
explain (analyze, buffers) select * from public.fn_fin_receber_previsto_realizado(8);
explain (analyze, buffers) select * from public.fn_fin_receber_previsto_realizado(8);
explain (analyze, buffers) select * from public.fn_fin_receber_previsto_realizado(52);
rollback;

-- P3) Por dentro: a leitura de uma foto usa receber_fotos_chave_uidx (Index Scan / Bitmap), não Seq Scan.
explain (analyze, buffers)
select f.bloco, f.grupo, sum(f.valor) from fin.receber_fotos f
 where f.foto_em = (select max(foto_em) from fin.receber_fotos_cabecalho) and f.situacao = 'a_receber' group by 1, 2;
--     vendas depois do corte: Index Scan em hotmart_transacoes_aprovado_pago_idx, nada de Seq Scan em hotmart_transacoes.
explain (analyze, buffers)
select t.transacao, t.dia_aprovado, t.liquido from fin.vw_transacoes t
 where t.status in ('APPROVED','COMPLETE') and t.aprovado_em > now() - interval '7 days' and t.aprovado_em < now();

-- P4) Kirad: bloco 8 pela fonte do board (plano de cs.vw_fin_board filtrado) e o custo da projeção com eventos.
begin;
insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values ('projecao_no_receber', current_date, 1, 'prova z69');
explain (analyze, buffers) select * from fin.receber_projecao(now(), current_date + 120, 'base');
select count(*) filter (where bloco = 8) linhas_b8, count(*) linhas from fin.receber_projecao(now(), current_date + 120, 'base');
rollback;

-- P5) Cron: o job e as execuções (depois da 1ª segunda-feira).
select jobid, jobname, schedule, command, active from cron.job where jobname = 'fin-receber-foto-semanal';
select status, start_time, end_time, return_message from cron.job_run_details
 where jobid = (select jobid from cron.job where jobname = 'fin-receber-foto-semanal') order by start_time desc limit 5;
*/
