-- 20260928z67 — Contas a Receber, fatia F3: projeção (bloco 3 vendas novas, bloco 4 evento planejado, bloco 6 reserva de
--               reembolso) e o informativo dos acordos do board (bloco 8, fora da soma).
--
-- APLICADA em produção em 28/09/2026 (2 partes: fin_receber_projecao + _b; md5 das 15 funções = arquivo; conferência 9.x verde). Projeção DESLIGADA. Medido: 206–238 ms, 551 linhas, 296 KB (era 534), detalhe b2 77 KB em 76 linhas/76 contratos. Sugestões: reserva 5,10%; HM avulso 19.678/sem; HT 1.853,72; outros 10.765,63.
-- Ordem obrigatória: z66 aplicada antes. Guarda: o corpo VIVO de fin.receber_posicao, de public.fn_fin_receber_semanal
-- e de fin.premissa tem que ser o da z66 (comparação sem espaço, sem comentário e sem o texto das mensagens de erro).
-- A migration inteira é UMA transação (apply_migration).
--
-- Decisões (coordenador, 28/09; Marcio delegou):
--   · venda nova semanal e reserva são CALCULADAS (sugestão medida), com sobrescrita do Financeiro por premissa com
--     vigência e cenário; evento e cenários do evento são digitados.
--   · saldos combinados do board: linha VISÍVEL e FORA da soma (bloco 8, situacao 'informativo').
--   · Aurum, Serviço Diamante e Programa Diamante fora das vendas novas; reserva só sobre o estimado (blocos 3 e 4),
--     centro de custo '3. (Devoluções)', valor negativo; certeza 'estimado' nos blocos 3, 4 e 6.
--
-- O que faz:
--   1) fin.premissas_receber_catalogo: unidade nova 'reais' (CHECK conferido por pg_get_constraintdef antes de trocar) e
--      5 chaves: venda_semanal:hm_avulso · venda_semanal:holding_total · venda_semanal:outros (reais, com cenário) ·
--      reserva_reembolso (percentual, com cenário) · projecao_no_receber (liga/desliga). Carga: projecao_no_receber = 0
--      desde 2000-01-01 (NASCE DESLIGADA: a tela de hoje soma todo bloco a_receber; ligar quando a seção ESTIMADO publicar:
--      select * from public.fn_fin_premissa_receber_salvar('projecao_no_receber', 1, current_date, 'base');).
--      Nenhuma venda_semanal/reserva é carregada: sem vigência, vale a sugestão medida.
--   2) fin.receber_grupos_venda_nova (familia → grupo; grupo NULL = fora, com motivo). Família que não estiver na
--      tabela conta como 'outros' (produto novo entra como A_CLASSIFICAR, que já está mapeado). A guarda aborta se
--      existir família viva em fin.produtos fora do mapa.
--   3) Medidas (internas, só leitura):
--      fin.receber_venda_semanal_medida(corte) — por grupo, mediana das 12 semanas COMPLETAS (seg–dom, antes da semana
--        do corte) mais recentes SEM dia de evento, olhando até 52 semanas para trás. Dia de evento = a regra da
--        trajetória (z14/z16): fin.eventos setor 'educacao', [coalesce(carrinho_inicio, inicio), venda_ate], janela de
--        até 10 dias (os ciclos de 14 dias do HT perpétuo não contam). Venda = 1ª cobrança (recorrência nula ou ≤ 1: as
--        parcelas e assinaturas seguintes estão no bloco 2), paga OU estornada depois (é "vendido"; a reserva do
--        bloco 6 desconta o estorno), valor = coalesce(liquido, valor_oferta − taxa_hotmart) — a mesma expressão da aba
--        Funis (z_fin_funis_resultado).
--      fin.receber_reserva_medida(corte) — estornado ÷ vendido nos 9 meses antes do corte, mesmo universo e valor.
--      fin.receber_curva_evento(evento_id) — venda por dia do evento de referência, dia 0 = abertura
--        (coalesce(carrinho_inicio, inicio)) até venda_ate; produtos de papel 'oferta' da categoria (fin.evento_produtos,
--        a mesma amarração da aba Funis); mesmo universo e valor. Todos os dias da janela saem (0 quando não vendeu).
--      fin.premissa_linha(chave, dia, cenario) — a vigência que vale (mesma regra de fin.premissa: chave@cenário, senão a
--        base) com a origem 'definido por <nome> em <dd/mm/aaaa>'.
--   4) fin.eventos_planejados (+ fin.eventos_planejados_trilha): cadastro do evento planejado. Nada se apaga (trigger
--      barra DELETE/TRUNCATE); arquivado não muda; toda criação/alteração/arquivamento vai para a trilha, só-acréscimo
--      (trigger AFTER, vale para qualquer caminho de escrita). RLS ligada, sem grant.
--   5) fin.receber_projecao(corte, ate, cenario) — interna; devolve as linhas dos blocos 3, 4, 6 e 8 no contrato v2.
--   6) fin.receber_posicao: create or replace (mesma assinatura, mesmo RETURNS, mesma ACL) = corpo da z66 +
--      "union all fin.receber_projecao(...) where v_proj" (v_proj = premissa projecao_no_receber > 0 no dia do corte)
--      + CORREÇÃO do payload da z66 (veredito do João, 28/09: 534 KB, detalhe do bloco 2 = 316 KB em 301 linhas para
--      76 contratos): o detalhe do bloco 2 sai UMA vez por contrato (ref) — na 1ª linha a_receber do contrato por
--      vencimento (a 'antecipacao'); sem a_receber, na 1ª linha do contrato; NULL em todas as outras, inclusive o
--      'cheio' de realizada/em atraso/coberta. Conteúdo idêntico ao da z66 (conferência 9.3).
--      public.fn_fin_receber_semanal NÃO muda (só guarda + leitura da interna).
--   7) RPCs: fn_fin_receber_sugestoes(cenario), fn_fin_eventos_planejados_listar(), fn_fin_evento_planejado_salvar(jsonb),
--      fn_fin_evento_planejado_arquivar(id, motivo).
--
-- CONTRATO dos blocos novos em public.fn_fin_receber_semanal (as mesmas 18 colunas da z66; soma de caixa: só
-- situacao = 'a_receber', inalterado):
--   bloco 3 — Vendas novas (estimado). grupo 'HM avulso' | 'Holding Total' | 'Outros produtos'.
--     Venda por dia = round(valor semanal ÷ 7, 2), todo dia de (corte, horizonte]. Valor semanal do dia = premissa
--     venda_semanal:<grupo> vigente NAQUELE dia (cenário, senão base); sem vigência = sugestão medida.
--     'HM avulso' = 0 nos dias das semanas (seg–dom) tocadas por evento planejado ativo com pausa_avulso.
--     Cada dia passa por fin.recebimento (D+2 útil e retido D+30, exato por dia); a linha é por data de caixa.
--     componente 'antecipacao' | 'garantia'; data_caixa = a do dinheiro; situacao 'a_receber'; origem_dia = 1º dia de
--     venda da linha; ref 'vn:<grupo>' (hm_avulso | holding_total | outros); rotulo = base(s) do valor; produto NULL;
--     k NULL (sem perda composta); detalhe = [{dia, valor_venda, base}] (as vendas do dia que caem nesta data) com base
--     'mediana 12 sem' | 'definido por <nome> em <dd/mm/aaaa>', só na linha 'antecipacao' — a linha 'garantia' traz
--     NULL (é a mesma venda; mesma convenção do bloco 2 da z66, metade dos bytes); valor_bruto = valor; fator 1;
--     certeza 'estimado';
--     centro_custo '1. Receita de vendas (Hotmart)'; tratamento = regra do caixa · regra da venda.
--     Grupo sem premissa e sem sugestão (nenhuma semana sem evento em 52) em algum dia: UMA linha componente 'cheio',
--     data_caixa NULL, valor NULL, valor_bruto NULL, situacao 'sem_base' (fora da soma; "não sei" não vira zero).
--   bloco 4 — Evento planejado (estimado). grupo = nome do evento planejado. Venda do dia (abertura + d) =
--     round(tamanho(cenário) × venda_ref(d), 2) = tamanho × total_ref × participação_ref(d). Só dias em (corte, horizonte].
--     Mesmo formato do bloco 3; ref 'ep:<id>'; rotulo 'Referência: <nome do evento de referência>';
--     detalhe base = 'curva <nome do evento de referência>'. Rebote depois do evento: não somado (P32).
--   bloco 6 — Reserva de reembolso e chargeback (estimado). grupo 'Reserva de reembolso e chargeback'; componente
--     'reserva'; uma linha por data de caixa dos blocos 3+4: valor = −round(pct × Σ valor dos blocos 3 e 4 na data, 2);
--     pct = premissa reserva_reembolso vigente na data (cenário, senão base), senão a taxa medida. origem_dia NULL;
--     ref 'reserva'; rotulo = origem do pct; detalhe NULL (a base são as linhas dos blocos 3 e 4 da mesma data_caixa;
--     o valor da base vai no tratamento);
--     centro_custo '3. (Devoluções)'; certeza 'estimado'. pct nulo (sem venda medida em 9 meses e sem premissa): uma
--     linha 'sem_base' como no bloco 3. pct = 0: nenhuma linha.
--   bloco 8 — Informativo: acordos no board. grupo 'Informativo: acordos no board'; uma linha por card com saldo
--     combinado a vencer no horizonte — a MESMA regra da fonte 'combinado' de fn_fin_contratado (Análise):
--     HM/AURUM, vencimento ≥ dia do corte, saldo_a_pagar > 0,5, status fora de cancelado/reembolsado/quitado, sem
--     parcelado Hotmart em curso da mesma pessoa e família. componente 'cheio'; data_caixa = origem_dia = vencimento;
--     valor = valor_bruto = saldo_a_pagar; situacao 'informativo' (FORA da soma: somar contaria duas vezes com a venda
--     nova do bloco 3); ref = contato_hm_id; rotulo = nome próprio; produto 'Holding Masters' | 'Aurum'; k NULL;
--     detalhe NULL; fator 1; certeza 'informativo'; centro_custo NULL. Lê o board de AGORA (o board não tem histórico):
--     num corte passado a linha não reproduz o passado.
--   bloco 2 (MUDA o detalhe, veredito do João): detalhe [{transacao, n, dia, liquido}] em EXATAMENTE 1 linha por ref.
--     A tela lê as pagas por ref (iromar), não por linha.
--   Com projecao_no_receber = 0 (carga), nenhum dos blocos 3, 4, 6, 8 sai e a RPC é idêntica à z66 em tudo, menos o
--   detalhe do bloco 2 (1× por contrato, mesmo conteúdo) — conferência 9.3.
--
-- 5 perguntas:
--   escala: venda semanal = 12 intervalos de 7 dias em hotmart_transacoes (aprovado_pago_idx; estornos pelo
--           status_idx); reserva = 9 meses pelo mesmo índice; curva = ≤ 31 dias de 1 evento pelo produto_idx
--           (produto_id, aprovado_em); projeção = (horizonte ≤ 400 dias) × 3 grupos chamadas a fin.recebimento +
--           premissa_linha (PK). Board: 1 leitura de cs.vw_fin_contas_receber filtrada + contrato_rec_idx por e-mail.
--           Nada cresce com a base inteira; cresce com o horizonte e com as vendas de 9 meses.
--   índice: nenhum índice novo; explain obrigatório (provas E7–E10): nada de Seq Scan em hotmart_transacoes.
--   frequência: a mesma RPC da aba (só com a projeção ligada); sugestões numa RPC própria, sob demanda (sub-aba
--           Premissas), sem cron; evento é cadastrado raramente.
--   repetição: sugestão, curva, reserva e board só no SQL; a tela só exibe.
--   reversão: premissa projecao_no_receber = 0 desliga os blocos 3, 4, 6 e 8 sem deploy (é a carga). Reverter de verdade:
--   begin;
--   -- a) recriar fin.receber_posicao com o corpo da z66 (20260928z66 linhas 663–822, create or replace + revoke);
--   drop function public.fn_fin_receber_sugestoes(text);
--   drop function public.fn_fin_eventos_planejados_listar();
--   drop function public.fn_fin_evento_planejado_salvar(jsonb);
--   drop function public.fn_fin_evento_planejado_arquivar(bigint, text);
--   drop function fin.receber_projecao(timestamptz, date, text);
--   drop function fin.receber_sugestoes(timestamptz, text);
--   alter table fin.eventos_planejados rename to eventos_planejados_arquivada_z67;
--   alter table fin.eventos_planejados_trilha rename to eventos_planejados_trilha_arquivada_z67;
--   alter table fin.receber_grupos_venda_nova rename to receber_grupos_venda_nova_arquivada_z67;
--   -- (catálogo e vigências ficam: nenhum leitor antigo lê as chaves novas; o CHECK com 'reais' fica)
--   commit;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_pos  oid := to_regprocedure('fin.receber_posicao(timestamptz,date,text)');
  v_rpc  oid := to_regprocedure('public.fn_fin_receber_semanal(timestamptz,date,text)');
  v_pre  oid := to_regprocedure('fin.premissa(text,date,text)');
  v_src  text;
  v_res  text;
  v_fora text;
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
end $esperado$;
  e_rpc  text := $esperado$
#variable_conflict use_column
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select * from fin.receber_posicao(coalesce(p_corte, now()), p_ate, coalesce(p_cenario, 'base'));
end $esperado$;
  e_pre  text := $esperado$
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
end $esperado$;
  e_res  text := 'TABLE(bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text, '
              || 'origem_dia date, ref text, rotulo text, produto text, k integer, detalhe jsonb, valor_bruto numeric, '
              || 'fator numeric, certeza text, centro_custo text, tratamento text, cenario text)';
  e_ck   text := 'CHECK ((unidade = ANY (ARRAY[''dias''::text, ''percentual''::text, ''liga_desliga''::text])))';
begin
  if v_pos is null or v_rpc is null or v_pre is null or to_regclass('fin.premissas_receber_catalogo') is null then
    raise exception 'z67: aplicar a z66 antes (fin.receber_posicao / fn_fin_receber_semanal(timestamptz,date,text) / fin.premissa ausente)';
  end if;
  if to_regclass('fin.eventos_planejados') is not null or to_regclass('fin.receber_grupos_venda_nova') is not null
     or to_regprocedure('fin.receber_projecao(timestamptz,date,text)') is not null
     or exists (select 1 from fin.premissas_receber_catalogo where chave = 'projecao_no_receber') then
    raise exception 'z67: já aplicada (eventos_planejados, grupos de venda nova, receber_projecao ou chave projecao_no_receber existe)';
  end if;
  if (select count(*) from pg_proc where proname = 'receber_posicao' and pronamespace = 'fin'::regnamespace) <> 1
     or (select count(*) from pg_proc where proname = 'fn_fin_receber_semanal' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'z67: sobrecarga viva de fin.receber_posicao ou fn_fin_receber_semanal — conferir pg_get_function_arguments';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('fn_fin_receber_sugestoes','fn_fin_eventos_planejados_listar',
                                'fn_fin_evento_planejado_salvar','fn_fin_evento_planejado_arquivar'))
     or exists (select 1 from pg_proc where pronamespace = 'fin'::regnamespace
                   and proname in ('receber_sugestoes','receber_venda_semanal_medida','receber_reserva_medida',
                                   'receber_curva_evento','premissa_linha','receber_brl')) then
    raise exception 'z67: função nova da z67 já existe — conferir';
  end if;
  -- dependências lidas (nome de coluna conferido: um rename em outra frente abortaria em tempo de execução)
  if to_regclass('fin.eventos') is null or to_regclass('fin.evento_produtos') is null or to_regclass('fin.produtos') is null
     or to_regclass('cs.vw_fin_contas_receber') is null or to_regclass('cs.contatos_hm') is null
     or to_regclass('cs.vw_fin_board') is null
     or to_regprocedure('fin.recebimento(date,numeric)') is null
     or to_regprocedure('public.gp_pode_operar_financeiro()') is null then
    raise exception 'z67: dependência ausente (fin.eventos, evento_produtos, produtos, cs.vw_fin_contas_receber, cs.contatos_hm, fin.recebimento, gp_pode_operar_financeiro)';
  end if;
  select string_agg(x.t || '.' || x.c, ', ') into v_fora
    from (values ('eventos','id'),('eventos','nome'),('eventos','categoria'),('eventos','setor'),('eventos','inicio'),
                 ('eventos','venda_ate'),('eventos','carrinho_inicio'),('evento_produtos','categoria'),
                 ('evento_produtos','produto_id'),('evento_produtos','papel'),('produtos','familia'),
                 ('vw_transacoes','familia'),('vw_transacoes','liquido'),('vw_transacoes','valor_oferta'),
                 ('vw_transacoes','taxa_hotmart'),('vw_transacoes','recorrencia'),('vw_transacoes','status'),
                 ('vw_transacoes','aprovado_em'),('vw_transacoes','grupo'),('vw_transacoes','produto_id'),
                 ('vw_transacoes','email'),('vw_transacoes','oferta_modo'),('vw_transacoes','oferta_codigo'),
                 ('vw_transacoes','parcelas')) x(t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = 'fin' and ic.table_name = x.t and ic.column_name = x.c);
  if v_fora is not null then raise exception 'z67: coluna ausente em fin: %', v_fora; end if;
  select string_agg(x.c, ', ') into v_fora
    from (values ('contato_hm_id'),('nome'),('email'),('vencimento'),('saldo_a_pagar'),('status_financeiro')) x(c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = 'cs' and ic.table_name = 'vw_fin_contas_receber' and ic.column_name = x.c);
  if v_fora is not null or not exists (select 1 from information_schema.columns ic where ic.table_schema = 'cs'
                                          and ic.table_name = 'contatos_hm' and ic.column_name = 'produto') then
    raise exception 'z67: coluna ausente em cs.vw_fin_contas_receber / cs.contatos_hm: %', coalesce(v_fora, 'contatos_hm.produto');
  end if;
  -- toda família viva tem destino no mapa (classe, não ocorrência)
  select string_agg(distinct p.familia, ', ') into v_fora
    from fin.produtos p
   where p.familia not in ('HM','HT','ACELERA','EVENTOS','OUTROS','A_CLASSIFICAR','OUTRO',
                           'AURUM','DIAMANTE','PROGRAMA_DIAMANTE','ESCRITORIO');
  if v_fora is not null then
    raise exception 'z67: família viva fora do mapa da venda nova: % — decidir o grupo e incluir no mapa', v_fora;
  end if;

  -- corpo vivo = z66, sem espaço, sem comentário e sem o texto das mensagens de erro
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_pos;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_pos, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_res, '\s+', '', 'g') then
    raise exception 'z67: corpo vivo de fin.receber_posicao diverge da z66. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_pos and l.lanname = 'plpgsql' and p.provolatile = 's' and not p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z67: atributos vivos de fin.receber_posicao diferentes da z66 (plpgsql/stable/invoker/search_path vazio)';
  end if;
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_rpc;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_rpc, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_res, '\s+', '', 'g') then
    raise exception 'z67: corpo vivo de public.fn_fin_receber_semanal diverge da z66. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_rpc and p.prosecdef and p.proconfig = array['search_path=""']) then
    raise exception 'z67: public.fn_fin_receber_semanal sem SECURITY DEFINER ou sem search_path vazio';
  end if;
  select prosrc into v_src from pg_proc where oid = v_pre;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_pre, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g') then
    raise exception 'z67: corpo vivo de fin.premissa diverge da z66 (a regra de cenário é replicada em fin.premissa_linha)';
  end if;

  -- CHECK da unidade do catálogo: reescrito abaixo; conferir o vivo antes (CHECK de memória apaga valor em silêncio)
  select pg_get_constraintdef(c.oid) into v_src
    from pg_constraint c
   where c.conrelid = 'fin.premissas_receber_catalogo'::regclass and c.conname = 'premissas_receber_catalogo_unidade_check';
  if v_src is null or regexp_replace(v_src, '\s+', '', 'g') <> regexp_replace(e_ck, '\s+', '', 'g') then
    raise exception 'z67: CHECK premissas_receber_catalogo_unidade_check vivo diferente do esperado: %', coalesce(v_src, 'ausente');
  end if;
end $guarda$;


-- ─── 1. Foto ANTES (z66, como admin) para a conferência 9.3 ─────────────────────────────────────────────────────────
do $foto$
declare
  v_adm uuid;
  v_ate date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                 + interval '4 months' - interval '1 day')::date;
begin
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z67: nenhum perfil admin ativo para a foto da RPC'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  create temp table z67_antes on commit drop as
    select 'passado'::text foto, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'base') x
    union all
    select 'passado_c'::text, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'conservador') x
    union all
    select 'agora'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'base') x
    union all
    select 'agora_c'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'conservador') x
    union all
    select 'agora_o'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'otimista') x;
  perform set_config('request.jwt.claims', '', true);
end $foto$;


-- ─── 2. Catálogo: unidade 'reais' e as chaves da projeção ───────────────────────────────────────────────────────────
alter table fin.premissas_receber_catalogo drop constraint premissas_receber_catalogo_unidade_check;
alter table fin.premissas_receber_catalogo add constraint premissas_receber_catalogo_unidade_check
  check (unidade in ('dias','percentual','liga_desliga','reais'));
comment on table fin.premissas_receber_catalogo is
  'Contas a Receber (z66; reais z67): premissas editáveis, faixa e texto de ajuda. percentual é guardado como fração '
  '(0,05 = 5%); reais em R$. aceita_cenario = pode ter vigência própria em x@conservador / x@otimista. Só migration altera.';

insert into fin.premissas_receber_catalogo (chave, rotulo, unidade, minimo, maximo, grupo_tela, ajuda, aceita_cenario) values
  ('venda_semanal:hm_avulso', 'Venda nova por semana — HM avulso', 'reais', 0, 5000000, 'Vendas novas (estimado)',
   'Sem vigência gravada, vale a sugestão medida: mediana das 12 últimas semanas completas sem dia de evento (1ª cobrança, líquido, paga ou estornada depois). Gravar aqui sobrescreve a partir da data. Zera nas semanas de evento planejado com "pausar o avulso".', true),
  ('venda_semanal:holding_total', 'Venda nova por semana — Holding Total', 'reais', 0, 5000000, 'Vendas novas (estimado)',
   'Sem vigência gravada, vale a sugestão medida: mediana das 12 últimas semanas completas sem dia de evento (1ª cobrança, líquido, paga ou estornada depois). Gravar aqui sobrescreve a partir da data.', true),
  ('venda_semanal:outros', 'Venda nova por semana — Outros produtos', 'reais', 0, 5000000, 'Vendas novas (estimado)',
   'Acelera, ingressos de eventos e demais produtos (sem Aurum, Serviço Diamante, Programa Diamante e escritório). Sem vigência gravada, vale a sugestão medida: mediana das 12 últimas semanas completas sem dia de evento.', true),
  ('reserva_reembolso', 'Reserva de reembolso e chargeback', 'percentual', 0, 0.2, 'Vendas novas (estimado)',
   'Aplicada negativa sobre as vendas novas estimadas (blocos 3 e 4). Sem vigência gravada, vale a taxa medida: estornado ÷ vendido nos últimos 9 meses.', true),
  ('projecao_no_receber', 'Projeção (vendas novas, eventos, reserva e acordos do board) na previsão', 'liga_desliga', 0, 1, 'Vendas novas (estimado)',
   '1 = os blocos 3, 4, 6 e o informativo dos acordos do board entram; 0 = desliga, sem deploy.', false);

insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values
  ('projecao_no_receber', date '2000-01-01', 0, 'z67: nasce desligada até a seção ESTIMADO da tela publicar');


-- ─── 3. Mapa família → grupo da venda nova ──────────────────────────────────────────────────────────────────────────
create table fin.receber_grupos_venda_nova (
  familia text primary key check (btrim(familia) <> ''),
  grupo   text check (grupo in ('hm_avulso','holding_total','outros')),
  motivo  text not null check (btrim(motivo) <> '')
);
comment on table fin.receber_grupos_venda_nova is
  'Contas a Receber (z67): família do produto → grupo da venda nova (bloco 3), da curva do evento (bloco 4) e da reserva. '
  'grupo NULL = fora (motivo diz por quê). Família ausente da tabela conta como outros. Só migration altera.';
alter table fin.receber_grupos_venda_nova enable row level security;
revoke all on fin.receber_grupos_venda_nova from public, anon, authenticated;

insert into fin.receber_grupos_venda_nova (familia, grupo, motivo) values
  ('HM',                'hm_avulso',     'Holding Masters vendido fora de evento'),
  ('HT',                'holding_total', 'ingresso do Holding Total'),
  ('ACELERA',           'outros',        'Acelera Holding'),
  ('EVENTOS',           'outros',        'ingressos de Encontro, Congresso, Clínica, Imersão, Residência'),
  ('OUTROS',            'outros',        'cursos e produtos de entrada antigos'),
  ('A_CLASSIFICAR',     'outros',        'produto novo ainda sem família: conta como outros até ser classificado'),
  ('OUTRO',             'outros',        'transação de produto fora do catálogo (vw_transacoes)'),
  ('AURUM',             null,            'decisão 28/09: Aurum entra por recebimento informado (bloco 5), não por venda nova'),
  ('DIAMANTE',          null,            'decisão 28/09: Serviço Diamante entra por recorrência (bloco 2) e informado (bloco 5)'),
  ('PROGRAMA_DIAMANTE', null,            'decisão 28/09: Programa Diamante fora das vendas novas'),
  ('ESCRITORIO',        null,            'Soluções/escritório: vendas novas próprias no bloco 7 (F9), conta mcsmarciosa');


-- ─── 4. Medidas e leituras (internas) ───────────────────────────────────────────────────────────────────────────────
create function fin.receber_brl(p numeric)
returns text language sql immutable set search_path = ''
as $$ select 'R$ ' || pg_catalog.translate(pg_catalog.to_char(pg_catalog.round(p, 2), 'FM999,999,999,990.00'), ',.', '.,') $$;
revoke all on function fin.receber_brl(numeric) from public, anon, authenticated;

-- A vigência que vale, com a origem. Mesma regra de fin.premissa (z66): chave@cenário vigente; sem ela, a base.
create function fin.premissa_linha(p_chave text, p_dia date, p_cenario text default 'base')
returns table (valor numeric, chave text, vigente_de date, origem text)
language sql stable set search_path = ''
as $$
  select pr.valor, pr.chave, pr.vigente_de,
         'definido por ' || coalesce(nullif(btrim(pf.nome), ''), pr.fonte) || ' em '
           || pg_catalog.to_char(pr.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
    from fin.premissas_receber pr
    left join public.perfis pf on pf.id = pr.criado_por
   where (pr.chave = p_chave or (p_cenario <> 'base' and pr.chave = p_chave || '@' || p_cenario))
     and pr.vigente_de <= p_dia
   order by (pr.chave <> p_chave) desc, pr.vigente_de desc
   limit 1
$$;
comment on function fin.premissa_linha(text, date, text) is
  'Contas a Receber (z67): a vigência de fin.premissa com a origem ("definido por <nome> em <data>"). Nenhuma linha = sem premissa.';
revoke all on function fin.premissa_linha(text, date, text) from public, anon, authenticated;

create function fin.receber_venda_semanal_medida(p_corte timestamptz)
returns table (grupo text, sugestao numeric, semanas int, de date, ate date, medida jsonb)
language sql stable set search_path = ''
as $$
  with seg as (
    select (pg_catalog.date_trunc('week', ((p_corte at time zone 'America/Sao_Paulo')::date)::timestamp))::date seg
  ), sem as materialized (
    -- as 12 semanas completas mais recentes sem dia de evento (regra z14/z16), até 52 semanas para trás
    select s.seg - 7 * g.n ini
      from seg s cross join generate_series(1, 52) g(n)
     where not exists (select 1 from fin.eventos e
                        where e.setor = 'educacao'
                          and (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) <= 10
                          and coalesce(e.carrinho_inicio, e.inicio) <= s.seg - 7 * g.n + 6
                          and e.venda_ate >= s.seg - 7 * g.n)
     order by 1 desc
     limit 12
  ), grupos as (
    select distinct m.grupo from fin.receber_grupos_venda_nova m where m.grupo is not null
  ), tx as (
    select s.ini, coalesce(m.grupo, 'outros') grupo,
           coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0)) liq
      from sem s
      join fin.vw_transacoes t
        on t.aprovado_em >= (s.ini::timestamp at time zone 'America/Sao_Paulo')
       and t.aprovado_em <  ((s.ini + 7)::timestamp at time zone 'America/Sao_Paulo')
       and t.status in ('APPROVED','COMPLETE')
      left join fin.receber_grupos_venda_nova m on m.familia = t.familia
     where coalesce(t.recorrencia, 1) <= 1 and (m.familia is null or m.grupo is not null)
    union all
    select s.ini, coalesce(m.grupo, 'outros'),
           coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
      from sem s
      join fin.vw_transacoes t
        on t.aprovado_em >= (s.ini::timestamp at time zone 'America/Sao_Paulo')
       and t.aprovado_em <  ((s.ini + 7)::timestamp at time zone 'America/Sao_Paulo')
       and t.status in ('REFUNDED','PARTIALLY_REFUNDED','CHARGEBACK')
      left join fin.receber_grupos_venda_nova m on m.familia = t.familia
     where coalesce(t.recorrencia, 1) <= 1 and (m.familia is null or m.grupo is not null)
  ), grade as (
    select s.ini, g.grupo, coalesce(sum(tx.liq), 0) v
      from sem s
      cross join grupos g
      left join tx on tx.ini = s.ini and tx.grupo = g.grupo
     group by s.ini, g.grupo
  ), ord as (
    select x.grupo, x.v, row_number() over (partition by x.grupo order by x.v, x.ini) rn,
           count(*) over (partition by x.grupo) n
      from grade x
  )
  select g.grupo,
         (select pg_catalog.round(avg(o.v), 2) from ord o
           where o.grupo = g.grupo and o.rn in ((o.n + 1) / 2, (o.n + 2) / 2)),
         (select count(*)::int from sem),
         (select min(s.ini) from sem s),
         (select max(s.ini) + 6 from sem s),
         (select jsonb_agg(jsonb_build_object('semana', x.ini, 'valor', pg_catalog.round(x.v, 2)) order by x.ini)
            from grade x where x.grupo = g.grupo)
    from grupos g
   order by 1
$$;
comment on function fin.receber_venda_semanal_medida(timestamptz) is
  'Contas a Receber (z67): sugestão da venda nova semanal por grupo = mediana das 12 semanas completas mais recentes sem '
  'dia de evento (até 52 para trás). 1ª cobrança, paga ou estornada depois, líquido. sugestao NULL = nenhuma semana achada.';
revoke all on function fin.receber_venda_semanal_medida(timestamptz) from public, anon, authenticated;

create function fin.receber_reserva_medida(p_corte timestamptz)
returns table (sugestao numeric, vendido numeric, estornado numeric, de date, ate date)
language sql stable set search_path = ''
as $$
  with j as (
    select ((p_corte at time zone 'America/Sao_Paulo')::date - interval '9 months')::date de,
           (p_corte at time zone 'America/Sao_Paulo')::date ate_excl
  ), tx as (
    select false est, coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0)) liq
      from j
      join fin.vw_transacoes t
        on t.aprovado_em >= (j.de::timestamp at time zone 'America/Sao_Paulo')
       and t.aprovado_em <  (j.ate_excl::timestamp at time zone 'America/Sao_Paulo')
       and t.status in ('APPROVED','COMPLETE')
      left join fin.receber_grupos_venda_nova m on m.familia = t.familia
     where coalesce(t.recorrencia, 1) <= 1 and (m.familia is null or m.grupo is not null)
    union all
    select true, coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
      from j
      join fin.vw_transacoes t
        on t.aprovado_em >= (j.de::timestamp at time zone 'America/Sao_Paulo')
       and t.aprovado_em <  (j.ate_excl::timestamp at time zone 'America/Sao_Paulo')
       and t.status in ('REFUNDED','PARTIALLY_REFUNDED','CHARGEBACK')
      left join fin.receber_grupos_venda_nova m on m.familia = t.familia
     where coalesce(t.recorrencia, 1) <= 1 and (m.familia is null or m.grupo is not null)
  )
  select case when sum(tx.liq) > 0 then pg_catalog.round(coalesce(sum(tx.liq) filter (where tx.est), 0) / sum(tx.liq), 4) end,
         pg_catalog.round(coalesce(sum(tx.liq), 0), 2),
         pg_catalog.round(coalesce(sum(tx.liq) filter (where tx.est), 0), 2),
         (select j.de from j), (select j.ate_excl - 1 from j)
    from tx
$$;
comment on function fin.receber_reserva_medida(timestamptz) is
  'Contas a Receber (z67): sugestão da reserva = estornado ÷ vendido (1ª cobrança, líquido, universo da venda nova) nos '
  '9 meses antes do corte. Sempre 1 linha; sugestao NULL = nada vendido na janela.';
revoke all on function fin.receber_reserva_medida(timestamptz) from public, anon, authenticated;

create function fin.receber_curva_evento(p_evento_id bigint)
returns table (d int, dia date, liquido numeric, participacao numeric, total numeric)
language sql stable set search_path = ''
as $$
  with e as (
    select x.id, x.categoria, coalesce(x.carrinho_inicio, x.inicio) ab, x.venda_ate
      from fin.eventos x where x.id = p_evento_id
  ), tx as (
    select (t.aprovado_em at time zone 'America/Sao_Paulo')::date dia,
           coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0)) liq
      from e
      join fin.evento_produtos p on p.categoria = e.categoria and p.papel = 'oferta'
      join fin.vw_transacoes t
        on t.produto_id = p.produto_id
       and t.aprovado_em >= (e.ab::timestamp at time zone 'America/Sao_Paulo')
       and t.aprovado_em <  ((e.venda_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
      left join fin.receber_grupos_venda_nova m on m.familia = t.familia
     where t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) <= 1
       and (m.familia is null or m.grupo is not null)
  ), dd as (
    select g.n d, e.ab + g.n dia, coalesce((select sum(tx.liq) from tx where tx.dia = e.ab + g.n), 0) liq
      from e cross join generate_series(0, greatest(e.venda_ate - e.ab, 0)) g(n)
  )
  select dd.d, dd.dia, pg_catalog.round(dd.liq, 2),
         case when sum(dd.liq) over () > 0 then pg_catalog.round(dd.liq / sum(dd.liq) over (), 6) end,
         pg_catalog.round(sum(dd.liq) over (), 2)
    from dd
   order by dd.d
$$;
comment on function fin.receber_curva_evento(bigint) is
  'Contas a Receber (z67): venda por dia do evento (dia 0 = carrinho_inicio ou inicio, até venda_ate), produtos de papel '
  'oferta da categoria (fin.evento_produtos), 1ª cobrança paga ou estornada depois, líquido, sem as famílias fora da venda nova.';
revoke all on function fin.receber_curva_evento(bigint) from public, anon, authenticated;


-- ─── 5. Evento planejado: cadastro, nada se apaga, trilha só-acréscimo ──────────────────────────────────────────────
create table fin.eventos_planejados (
  id                  bigint generated always as identity primary key,
  nome                text not null check (btrim(nome) <> '' and length(nome) <= 120),
  abertura            date not null,
  evento_ref_id       bigint not null references fin.eventos (id),
  tamanho_base        numeric not null check (tamanho_base > 0 and tamanho_base <= 20),
  tamanho_conservador numeric not null check (tamanho_conservador > 0 and tamanho_conservador <= 20),
  tamanho_otimista    numeric not null check (tamanho_otimista > 0 and tamanho_otimista <= 20),
  pausa_avulso        boolean not null default true,
  observacao          text check (observacao is null or length(observacao) <= 500),
  criado_em           timestamptz not null default now(),
  criado_por          uuid,
  atualizado_em       timestamptz,
  atualizado_por      uuid,
  arquivado_em        timestamptz,
  arquivado_por       uuid,
  arquivado_motivo    text,
  check (tamanho_conservador <= tamanho_base and tamanho_base <= tamanho_otimista),
  check ((arquivado_em is null) = (arquivado_motivo is null)),
  check (arquivado_motivo is null or length(btrim(arquivado_motivo)) between 3 and 500)
);
comment on table fin.eventos_planejados is
  'Contas a Receber (z67): evento planejado do bloco 4. Venda do dia = tamanho(cenário) × venda do evento de referência no '
  'mesmo dia desde a abertura. Nada se apaga (arquivar); arquivado não muda; toda escrita vai para eventos_planejados_trilha.';
alter table fin.eventos_planejados enable row level security;
revoke all on fin.eventos_planejados from public, anon, authenticated;
revoke all on sequence fin.eventos_planejados_id_seq from public, anon, authenticated;

create table fin.eventos_planejados_trilha (
  id        bigint generated always as identity primary key,
  evento_id bigint not null references fin.eventos_planejados (id),
  acao      text not null check (acao in ('criado','alterado','arquivado')),
  antes     jsonb,
  depois    jsonb not null,
  feito_por uuid,
  feito_em  timestamptz not null default now()
);
create index eventos_planejados_trilha_evento_idx on fin.eventos_planejados_trilha (evento_id, feito_em);
comment on table fin.eventos_planejados_trilha is
  'Contas a Receber (z67): trilha só-acréscimo de fin.eventos_planejados (gravada por trigger, qualquer caminho de escrita).';
alter table fin.eventos_planejados_trilha enable row level security;
revoke all on fin.eventos_planejados_trilha from public, anon, authenticated;
revoke all on sequence fin.eventos_planejados_trilha_id_seq from public, anon, authenticated;

create function fin.tg_eventos_planejados_guarda()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'Evento planejado não se apaga: arquive.' using errcode = '42501';
  end if;
  if old.arquivado_em is not null then
    raise exception 'Evento planejado arquivado não muda.' using errcode = '42501';
  end if;
  if new.id <> old.id or new.criado_em <> old.criado_em or new.criado_por is distinct from old.criado_por then
    raise exception 'Evento planejado: id e criação não mudam.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function fin.tg_eventos_planejados_guarda() from public, anon, authenticated;

create function fin.tg_eventos_planejados_trilha()
returns trigger language plpgsql set search_path = ''
as $$
declare
  v_acao text;
begin
  if tg_op = 'INSERT' then
    v_acao := 'criado';
  elsif new.arquivado_em is not null and old.arquivado_em is null then
    v_acao := 'arquivado';
  elsif (to_jsonb(new) - array['atualizado_em','atualizado_por']) = (to_jsonb(old) - array['atualizado_em','atualizado_por']) then
    return null;   -- salvar sem mudança não polui a trilha
  else
    v_acao := 'alterado';
  end if;
  insert into fin.eventos_planejados_trilha (evento_id, acao, antes, depois, feito_por)
  values (new.id, v_acao, case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new), (select auth.uid()));
  return null;
end $$;
revoke all on function fin.tg_eventos_planejados_trilha() from public, anon, authenticated;

create function fin.tg_eventos_planejados_trilha_so_acrescimo()
returns trigger language plpgsql set search_path = ''
as $$
begin
  raise exception 'fin.eventos_planejados_trilha é só acréscimo.' using errcode = '42501';
end $$;
revoke all on function fin.tg_eventos_planejados_trilha_so_acrescimo() from public, anon, authenticated;

create trigger eventos_planejados_guarda before update or delete on fin.eventos_planejados
  for each row execute function fin.tg_eventos_planejados_guarda();
create trigger eventos_planejados_nao_trunca before truncate on fin.eventos_planejados
  for each statement execute function fin.tg_eventos_planejados_guarda();
create trigger eventos_planejados_trilha after insert or update on fin.eventos_planejados
  for each row execute function fin.tg_eventos_planejados_trilha();
create trigger eventos_planejados_trilha_so_acrescimo before update or delete on fin.eventos_planejados_trilha
  for each row execute function fin.tg_eventos_planejados_trilha_so_acrescimo();
create trigger eventos_planejados_trilha_nao_trunca before truncate on fin.eventos_planejados_trilha
  for each statement execute function fin.tg_eventos_planejados_trilha_so_acrescimo();


-- ─── 6. A projeção (blocos 3, 4, 6 e 8), interna ────────────────────────────────────────────────────────────────────
create function fin.receber_projecao(p_corte timestamptz, p_ate date, p_cenario text)
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
end $$;
comment on function fin.receber_projecao(timestamptz, date, text) is
  'Contas a Receber (z67): blocos 3 (vendas novas), 4 (evento planejado), 6 (reserva, negativa) e 8 (acordos do board, '
  'informativo, fora da soma) no contrato v2. Interna: sem guarda de sessão; quem chama é fin.receber_posicao.';
revoke all on function fin.receber_projecao(timestamptz, date, text) from public, anon, authenticated;


-- ─── 7. A previsão: corpo da z66 + projeção sob o kill-switch ───────────────────────────────────────────────────────
create or replace function fin.receber_posicao(p_corte timestamptz, p_ate date, p_cenario text)
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
end $$;
comment on function fin.receber_posicao(timestamptz, date, text) is
  'Contas a Receber (z66; projeção z67): a previsão inteira no corte — blocos 1, 2, 5 (certo) e, com a premissa '
  'projecao_no_receber > 0, os blocos 3, 4, 6 (estimado) e 8 (informativo, fora da soma). Interna: sem guarda de sessão '
  '(a pública guarda; o cron da F4 chama direto). Soma só situacao = a_receber.';
revoke all on function fin.receber_posicao(timestamptz, date, text) from public, anon, authenticated;

comment on function public.fn_fin_receber_semanal(timestamptz, date, text) is
  'Aba Contas a Receber (z61 + z63 + z66 + z67): blocos 1, 2, 5 e, com a projeção ligada, 3, 4, 6 e 8. valor = esperado '
  '(bruto × fator); valor_bruto = sem perda. Soma só situacao = a_receber. Sem e-mail/documento.';


-- ─── 8. Sugestões e evento planejado: RPCs ──────────────────────────────────────────────────────────────────────────
create function fin.receber_sugestoes(p_corte timestamptz, p_cenario text)
returns table (chave text, rotulo text, unidade text, sugestao numeric, base_medida text, medida jsonb,
               valor_efetivo numeric, origem text, vigente_de date, cenario text)
language sql stable set search_path = ''
as $$
  with s as (
    select 'venda_semanal:' || m.grupo chave, m.sugestao,
           case when m.semanas = 0 then 'Nenhuma semana completa sem dia de evento nas últimas 52'
                else 'Mediana de ' || m.semanas || ' semanas completas sem dia de evento ('
                     || pg_catalog.to_char(m.de, 'DD/MM/YYYY') || ' a ' || pg_catalog.to_char(m.ate, 'DD/MM/YYYY')
                     || '); 1ª cobrança, líquido, paga ou estornada depois' end base_medida,
           m.medida
      from fin.receber_venda_semanal_medida(p_corte) m
    union all
    select 'reserva_reembolso', r.sugestao,
           'Estornado ÷ vendido de ' || pg_catalog.to_char(r.de, 'DD/MM/YYYY') || ' a ' || pg_catalog.to_char(r.ate, 'DD/MM/YYYY')
             || ' (1ª cobrança, líquido, sem Aurum/Diamante/escritório)',
           jsonb_build_object('vendido', r.vendido, 'estornado', r.estornado, 'de', r.de, 'ate', r.ate)
      from fin.receber_reserva_medida(p_corte) r
  )
  select s.chave, k.rotulo, k.unidade, s.sugestao, s.base_medida, s.medida,
         coalesce(pl.valor, s.sugestao),
         case when pl.valor is not null then pl.origem when s.sugestao is not null then 'sugestão medida'
              else 'sem base medida' end,
         pl.vigente_de, p_cenario
    from s
    join fin.premissas_receber_catalogo k on k.chave = s.chave
    left join lateral fin.premissa_linha(s.chave, (p_corte at time zone 'America/Sao_Paulo')::date, p_cenario) pl on true
   order by 1
$$;
revoke all on function fin.receber_sugestoes(timestamptz, text) from public, anon, authenticated;

create function public.fn_fin_receber_sugestoes(p_cenario text default 'base')
returns table (chave text, rotulo text, unidade text, sugestao numeric, base_medida text, medida jsonb,
               valor_efetivo numeric, origem text, vigente_de date, cenario text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_cen text := coalesce(p_cenario, 'base');
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_cen not in ('base','conservador','otimista') then
    raise exception 'Cenário inválido (base, conservador ou otimista).' using errcode = '22023';
  end if;
  return query select * from fin.receber_sugestoes(now(), v_cen);
end $$;
revoke all on function public.fn_fin_receber_sugestoes(text) from public, anon;
grant execute on function public.fn_fin_receber_sugestoes(text) to authenticated;

create function public.fn_fin_eventos_planejados_listar()
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
    ) c on true
    left join public.perfis pc on pc.id = p.criado_por
    left join public.perfis pu on pu.id = p.atualizado_por
    left join public.perfis pa on pa.id = p.arquivado_por
   order by (p.arquivado_em is not null), p.abertura desc, p.id desc;
end $$;
revoke all on function public.fn_fin_eventos_planejados_listar() from public, anon;
grant execute on function public.fn_fin_eventos_planejados_listar() to authenticated;

-- Cria (sem "id") ou altera (com "id") um evento planejado. Chaves aceitas: id, nome, abertura (AAAA-MM-DD),
-- evento_ref_id, tamanho_base, tamanho_conservador, tamanho_otimista, pausa_avulso (default true), observacao.
create function public.fn_fin_evento_planejado_salvar(p jsonb)
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

create function public.fn_fin_evento_planejado_arquivar(p_id bigint, p_motivo text)
returns table (id bigint, arquivado_em timestamptz)
language plpgsql volatile security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
  v_mot text := btrim(coalesce(p_motivo, ''));
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if length(v_mot) < 3 or length(v_mot) > 500 then
    raise exception 'Arquivar: informe o motivo (3 a 500 caracteres).' using errcode = '22023';
  end if;
  return query
  update fin.eventos_planejados ep
     set arquivado_em = now(), arquivado_por = v_uid, arquivado_motivo = v_mot
   where ep.id = p_id and ep.arquivado_em is null
  returning ep.id, ep.arquivado_em;
  if not found then
    if exists (select 1 from fin.eventos_planejados ep where ep.id = p_id) then
      raise exception 'Evento planejado já arquivado.' using errcode = '22023';
    end if;
    raise exception 'Evento planejado não existe.' using errcode = '22023';
  end if;
end $$;
revoke all on function public.fn_fin_evento_planejado_arquivar(bigint, text) from public, anon;
grant execute on function public.fn_fin_evento_planejado_arquivar(bigint, text) to authenticated;


-- ─── 9. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
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
  v_ref   bigint;
  v_ev    bigint;
  v_tot   numeric;
  v_x     numeric;
  v_y     numeric;
  v_rp    numeric;
  v_ra    numeric;
  f       text;
  t       text;
begin
  -- 9.1 grants: tabelas e sequências fechadas, RLS ligada; internas sem EXECUTE e invoker; RPCs só authenticated
  foreach t in array array['fin.eventos_planejados','fin.eventos_planejados_trilha','fin.receber_grupos_venda_nova',
                           'fin.premissas_receber','fin.premissas_receber_catalogo'] loop
    if has_table_privilege('anon', t, 'select,insert,update,delete,truncate,references,trigger')
       or has_table_privilege('authenticated', t, 'select,insert,update,delete,truncate,references,trigger') then
      raise exception 'z67: grant aberto em %', t;
    end if;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception 'z67: RLS desligada em %', t;
    end if;
  end loop;
  foreach t in array array['fin.eventos_planejados_id_seq','fin.eventos_planejados_trilha_id_seq'] loop
    if has_sequence_privilege('anon', t, 'usage,select,update') or has_sequence_privilege('authenticated', t, 'usage,select,update') then
      raise exception 'z67: sequência aberta: %', t;
    end if;
  end loop;
  foreach f in array array['fin.receber_brl(numeric)','fin.premissa_linha(text,date,text)',
                           'fin.receber_venda_semanal_medida(timestamptz)','fin.receber_reserva_medida(timestamptz)',
                           'fin.receber_curva_evento(bigint)','fin.receber_projecao(timestamptz,date,text)',
                           'fin.receber_posicao(timestamptz,date,text)','fin.receber_sugestoes(timestamptz,text)',
                           'fin.tg_eventos_planejados_guarda()','fin.tg_eventos_planejados_trilha()',
                           'fin.tg_eventos_planejados_trilha_so_acrescimo()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z67: interna % executável por anon/authenticated', f;
    end if;
    if exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef) then
      raise exception 'z67: interna % é SECURITY DEFINER', f;
    end if;
  end loop;
  foreach f in array array['public.fn_fin_receber_semanal(timestamptz,date,text)',
                           'public.fn_fin_receber_sugestoes(text)',
                           'public.fn_fin_eventos_planejados_listar()',
                           'public.fn_fin_evento_planejado_salvar(jsonb)',
                           'public.fn_fin_evento_planejado_arquivar(bigint,text)'] loop
    if has_function_privilege('anon', f, 'execute') then raise exception 'z67: % executável por anon', f; end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z67: authenticated sem execute em %', f;
    end if;
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                      and p.proconfig = array['search_path=""']) then
      raise exception 'z67: % sem SECURITY DEFINER ou sem search_path vazio', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p
              where p.oid in ('fin.receber_brl(numeric)'::regprocedure, 'fin.premissa_linha(text,date,text)'::regprocedure,
                              'fin.receber_venda_semanal_medida(timestamptz)'::regprocedure,
                              'fin.receber_reserva_medida(timestamptz)'::regprocedure,
                              'fin.receber_curva_evento(bigint)'::regprocedure,
                              'fin.receber_projecao(timestamptz,date,text)'::regprocedure,
                              'fin.receber_posicao(timestamptz,date,text)'::regprocedure,
                              'fin.receber_sugestoes(timestamptz,text)'::regprocedure,
                              'fin.tg_eventos_planejados_guarda()'::regprocedure,
                              'fin.tg_eventos_planejados_trilha()'::regprocedure,
                              'fin.tg_eventos_planejados_trilha_so_acrescimo()'::regprocedure,
                              'public.fn_fin_receber_semanal(timestamptz,date,text)'::regprocedure,
                              'public.fn_fin_receber_sugestoes(text)'::regprocedure,
                              'public.fn_fin_eventos_planejados_listar()'::regprocedure,
                              'public.fn_fin_evento_planejado_salvar(jsonb)'::regprocedure,
                              'public.fn_fin_evento_planejado_arquivar(bigint,text)'::regprocedure)
                and (p.proacl is null or exists (select 1 from unnest(p.proacl) ac where ac::text like '=%'))) then
    raise exception 'z67: função com EXECUTE para PUBLIC (ou proacl nulo = padrão público)';
  end if;
  if (select count(*) from pg_proc where proname = 'receber_posicao' and pronamespace = 'fin'::regnamespace) <> 1
     or (select count(*) from pg_proc where proname = 'fn_fin_receber_semanal' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'z67: sobrecarga viva (receber_posicao / fn_fin_receber_semanal)';
  end if;

  -- 9.2 sem sessão → 42501 nas 4 RPCs novas, e nada gravado
  select count(*) into v_n from fin.eventos_planejados;
  foreach f in array array[
      'select * from public.fn_fin_receber_sugestoes(''base'')',
      'select * from public.fn_fin_eventos_planejados_listar()',
      'select * from public.fn_fin_evento_planejado_salvar(''{"nome":"x"}''::jsonb)',
      'select * from public.fn_fin_evento_planejado_arquivar(1, ''teste z67'')'] loop
    v_ok := false;
    begin
      execute f;
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z67: RPC respondeu sem sessão: %', f; end if;
  end loop;
  if (select count(*) from fin.eventos_planejados) <> v_n then raise exception 'z67: RPC gravou sem sessão'; end if;

  -- 9.3 projeção DESLIGADA (a carga): as 18 colunas idênticas à z66, linha a linha, 2 cortes × cenários
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  create temp table z67_desligada on commit drop as
    select 'passado'::text foto, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'base') x
    union all
    select 'passado_c'::text, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'conservador') x
    union all
    select 'agora'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'base') x
    union all
    select 'agora_c'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'conservador') x
    union all
    select 'agora_o'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'otimista') x;
  --     (tudo menos o detalhe do bloco 2, conferido à parte logo abaixo)
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp
    from (select a.foto, a.bloco, a.grupo, a.componente, a.data_caixa, a.valor, a.situacao, a.origem_dia, a.ref, a.rotulo,
                 a.produto, a.k, case when a.bloco = 2 then null else a.detalhe end, a.valor_bruto, a.fator, a.certeza,
                 a.centro_custo, a.tratamento, a.cenario
            from z67_antes a) x;
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
    from (select a.foto, a.bloco, a.grupo, a.componente, a.data_caixa, a.valor, a.situacao, a.origem_dia, a.ref, a.rotulo,
                 a.produto, a.k, case when a.bloco = 2 then null else a.detalhe end, a.valor_bruto, a.fator, a.certeza,
                 a.centro_custo, a.tratamento, a.cenario
            from z67_desligada a) x;
  if v_esp is distinct from v_obt then
    raise exception 'z67: com a projeção desligada a RPC difere da z66 (linhas antes %, depois %)',
      (select count(*) from z67_antes), (select count(*) from z67_desligada);
  end if;
  --     bloco 2: detalhe em exatamente 1 linha por contrato, a 1ª a_receber por vencimento ('antecipacao'; sem a_receber,
  --     qualquer linha do contrato), conteúdo = o da z66, sem @, só as chaves transacao/n/dia/liquido
  select string_agg(format('%s %s (n=%s)', x.foto, x.ref, x.n), '; ') into v_txt
    from (select d.foto, d.ref,
                 count(*) filter (where d.detalhe is not null) n,
                 bool_or(d.situacao = 'a_receber') existe_ar,
                 bool_or(d.detalhe is not null and d.situacao = 'a_receber' and d.componente = 'antecipacao'
                         and d.origem_dia = (select min(y.origem_dia) from z67_desligada y
                                              where y.foto = d.foto and y.bloco = 2 and y.ref = d.ref
                                                and y.situacao = 'a_receber')) no_lugar,
                 (array_agg(d.detalhe) filter (where d.detalhe is not null))[1] det,
                 (select a.detalhe from z67_antes a
                   where a.foto = d.foto and a.bloco = 2 and a.ref = d.ref and a.detalhe is not null limit 1) det_z66
            from z67_desligada d
           where d.bloco = 2
           group by d.foto, d.ref) x
   where x.n <> 1 or x.det is distinct from x.det_z66 or x.det::text like '%@%'
      or (x.existe_ar and not x.no_lugar)
      or jsonb_typeof(x.det) <> 'array'
      or exists (select 1 from jsonb_array_elements(x.det) e(v), jsonb_object_keys(e.v) kk(ch)
                  where kk.ch not in ('transacao','n','dia','liquido'));
  if v_txt is not null then
    raise exception 'z67: detalhe do bloco 2 fora da regra 1× por contrato: %', left(v_txt, 800);
  end if;

  -- 9.4 fin.premissa_linha = fin.premissa (a regra replicada), com vigências de teste desfeitas
  begin
    insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values
      ('venda_semanal:outros', date '2000-01-01', 100, 'teste z67'),
      ('venda_semanal:outros@otimista', date '2000-01-01', 300, 'teste z67'),
      ('venda_semanal:outros', v_dia + 5, 150, 'teste z67'),
      ('reserva_reembolso@conservador', v_dia + 3, 0.07, 'teste z67');
    foreach t in array array['venda_semanal:outros','venda_semanal:hm_avulso','reserva_reembolso','perda_mensal:holding_hm',
                             'projecao_no_receber'] loop
      foreach f in array array['base','conservador','otimista'] loop
        for v_n in 0..6 loop
          if fin.premissa(t, v_dia + v_n, f)
             is distinct from (select pl.valor from fin.premissa_linha(t, v_dia + v_n, f) pl) then
            raise exception 'z67: premissa_linha ≠ premissa em % / % / dia +%', t, f, v_n;
          end if;
        end loop;
      end loop;
    end loop;
    raise exception using errcode = 'P0001', message = 'z67_desfaz';
  exception when raise_exception then
    if sqlerrm <> 'z67_desfaz' then raise; end if;
  end;

  -- 9.5 projeção LIGADA (vigência de teste desfeita no fim)
  begin
    insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values ('projecao_no_receber', date '2000-01-02', 1, 'teste z67');
    -- sugestões medidas nos dois cortes (1 vez; as conferências abaixo comparam com elas)
    create temp table z67_sug on commit drop as
      select 'passado'::text q, m.grupo, m.sugestao from fin.receber_venda_semanal_medida('2026-09-25 23:59:59-03') m
      union all
      select 'agora'::text, m.grupo, m.sugestao from fin.receber_venda_semanal_medida(now()) m;
    select m.sugestao into v_rp from fin.receber_reserva_medida('2026-09-25 23:59:59-03') m;
    select m.sugestao into v_ra from fin.receber_reserva_medida(now()) m;
    create temp table z67_ligada on commit drop as
      select 'passado'::text foto, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'base') x
      union all
      select 'passado_c'::text, x.* from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'conservador') x
      union all
      select 'agora'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'base') x
      union all
      select 'agora_c'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'conservador') x
      union all
      select 'agora_o'::text, x.* from public.fn_fin_receber_semanal(now(), v_ate, 'otimista') x;
    -- a) blocos 1, 2, 5 intocados (iguais aos da projeção desligada, todas as colunas)
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp from z67_desligada x;
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
      from z67_ligada x where x.bloco in (1, 2, 5);
    if v_esp is distinct from v_obt then
      raise exception 'z67: com a projeção ligada os blocos 1, 2, 5 mudaram';
    end if;
    -- b) contrato das linhas novas
    select string_agg(format('%s/%s/%s/%s', d.foto, d.bloco, d.grupo, d.situacao), '; ') into v_txt
      from z67_ligada d
     where d.bloco in (3, 4, 6, 8)
       and not (
         d.fator = 1 and d.k is null and d.valor is not distinct from d.valor_bruto
         and d.cenario = case when d.foto like '%\_c' then 'conservador' when d.foto like '%\_o' then 'otimista' else 'base' end
         and d.tratamento is not null and d.tratamento <> ''
         and case
               when d.bloco in (3, 4) and d.situacao = 'a_receber' then
                    d.certeza = 'estimado' and d.centro_custo = '1. Receita de vendas (Hotmart)'
                and d.componente in ('antecipacao','garantia') and d.data_caixa is not null and d.valor >= 0
                and d.origem_dia > (case when d.foto like 'passado%' then date '2026-09-25' else v_dia end)
                and d.ref ~ case d.bloco when 3 then '^vn:(hm_avulso|holding_total|outros)$' else '^ep:[0-9]+$' end
                and case when d.componente = 'garantia' then d.detalhe is null
                         else jsonb_typeof(d.detalhe) = 'array' and d.detalhe::text not like '%@%' end
                and not exists (select 1 from jsonb_array_elements(d.detalhe) e(v), jsonb_object_keys(e.v) kk(ch)
                                 where kk.ch not in ('dia','valor_venda','base'))
               when d.bloco = 3 and d.situacao = 'sem_base' then d.valor is null and d.data_caixa is null
               when d.bloco = 6 and d.situacao = 'a_receber' then
                    d.certeza = 'estimado' and d.centro_custo = '3. (Devoluções)' and d.componente = 'reserva'
                and d.valor <= 0 and d.ref = 'reserva' and d.detalhe is null
               when d.bloco = 6 and d.situacao = 'sem_base' then d.valor is null
               when d.bloco = 8 then
                    d.situacao = 'informativo' and d.certeza = 'informativo' and d.centro_custo is null
                and d.componente = 'cheio' and d.data_caixa = d.origem_dia and d.valor > 0.5 and d.detalhe is null
                and d.produto in ('Holding Masters','Aurum') and d.rotulo not like '%@%'
               else false
             end);
    if v_txt is not null then
      raise exception 'z67: linhas novas fora do contrato: %', left(v_txt, 800);
    end if;
    -- c) bloco 6 = −round(pct × Σ blocos 3 e 4 da data, 2), pct = premissa ou taxa medida
    select string_agg(format('%s %s: %s × %s', r.foto, r.data_caixa, r.valor, r.esperado), '; ') into v_txt
      from (select d.foto, d.data_caixa, d.valor,
                   -round(coalesce(fin.premissa('reserva_reembolso', d.data_caixa, d.cenario),
                                   case when d.foto like 'passado%' then v_rp else v_ra end)
                          * (select sum(b.valor) from z67_ligada b
                              where b.foto = d.foto and b.bloco in (3, 4) and b.situacao = 'a_receber'
                                and b.data_caixa = d.data_caixa), 2) esperado
              from z67_ligada d where d.bloco = 6 and d.situacao = 'a_receber') r
     where r.valor is distinct from r.esperado;
    if v_txt is not null then raise exception 'z67: reserva fora da regra: %', left(v_txt, 800); end if;
    -- d) bloco 3: cada dia de (corte, horizonte] uma vez por grupo e componente; venda do dia = round(sugestão ÷ 7, 2)
    select string_agg(format('%s %s', x.foto, x.ref), '; ') into v_txt
      from (select d.foto, d.ref, d.componente, count(*) n, count(distinct (e.v ->> 'dia')) nd,
                   min((e.v ->> 'dia')::date) d0, max((e.v ->> 'dia')::date) d1,
                   bool_and((e.v ->> 'valor_venda')::numeric
                            = round((select m.sugestao from z67_sug m
                                      where m.q = case when d.foto like 'passado%' then 'passado' else 'agora' end
                                        and 'vn:' || m.grupo = d.ref) / 7, 2)) igual
              from z67_ligada d, jsonb_array_elements(d.detalhe) e(v)
             where d.bloco = 3 and d.situacao = 'a_receber'
             group by d.foto, d.ref, d.componente) x
     where x.n <> x.nd or not x.igual
        or x.d1 > case when x.foto like 'passado%' then date '2026-12-31' else v_ate end
        or x.n <> (case when x.foto like 'passado%' then date '2026-12-31' - date '2026-09-25' else v_ate - v_dia end);
    if v_txt is not null then raise exception 'z67: bloco 3 fora da regra dia a dia: %', left(v_txt, 800); end if;
    -- e) sem vigência de cenário e sem evento: os três cenários iguais (menos a coluna cenario)
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp
      from (select d.bloco, d.grupo, d.componente, d.data_caixa, d.valor, d.situacao, d.ref from z67_ligada d
             where d.foto = 'agora' and d.bloco in (3, 6, 8)) x;
    foreach t in array array['agora_c','agora_o'] loop
      select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
        from (select d.bloco, d.grupo, d.componente, d.data_caixa, d.valor, d.situacao, d.ref from z67_ligada d
               where d.foto = t and d.bloco in (3, 6, 8)) x;
      if v_esp is distinct from v_obt then raise exception 'z67: cenário % difere do base sem premissa própria', t; end if;
    end loop;
    -- h) bloco 8 = fonte 'combinado' de fn_fin_contratado, reescrita como lá (cs.vw_fin_board + plano por família),
    --    por card: mesmo conjunto de (card, vencimento, saldo)
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp
      from (select distinct b.contato_hm_id::text ref, b.vencimento, b.saldo_a_pagar
              from cs.vw_fin_board b
             where b.origem in ('HM','AURUM') and b.vencimento >= v_dia and b.vencimento <= v_ate
               and coalesce(b.saldo_a_pagar, 0) > 0.5
               and b.status_financeiro not in ('cancelado','reembolsado','quitado')
               and not exists (select 1
                                 from (select t.email, t.familia, t.oferta_codigo, max(t.parcelas) parcelas,
                                              max(t.recorrencia) filter (where t.grupo = 'pago') paga
                                         from fin.vw_transacoes t
                                        where t.familia in ('HM','AURUM') and t.oferta_modo like 'HOTMART_INSTALLMENTS%'
                                          and t.recorrencia is not null
                                        group by 1, 2, 3) p
                                where p.email = lower(trim(b.email)) and p.familia = b.origem
                                  and p.parcelas > coalesce(p.paga, 0))) x;
    select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
      from (select distinct d.ref, d.data_caixa, d.valor from z67_ligada d where d.foto = 'agora' and d.bloco = 8) x;
    if v_esp is distinct from v_obt then
      raise exception 'z67: bloco 8 difere da fonte combinado de fn_fin_contratado (board)';
    end if;
    -- f) sobrescrita por cenário: venda_semanal:hm_avulso@conservador = 7000 → R$ 1.000/dia só no conservador
    insert into fin.premissas_receber (chave, vigente_de, valor, fonte)
    values ('venda_semanal:hm_avulso@conservador', date '2000-01-01', 7000, 'teste z67');
    select count(*) filter (where (e.v ->> 'valor_venda')::numeric <> 1000 or e.v ->> 'base' not like 'definido por %'),
           count(*)
      into v_n, v_x
      from public.fn_fin_receber_semanal(now(), v_ate, 'conservador') d, jsonb_array_elements(d.detalhe) e(v)
     where d.bloco = 3 and d.ref = 'vn:hm_avulso' and d.componente = 'antecipacao';
    if v_n <> 0 or v_x <> v_ate - v_dia then
      raise exception 'z67: sobrescrita conservador do HM avulso fora da regra (% dias errados de %)', v_n, v_x;
    end if;
    if exists (select 1 from public.fn_fin_receber_semanal(now(), v_ate, 'base') d, jsonb_array_elements(d.detalhe) e(v)
                where d.bloco = 3 and d.ref = 'vn:hm_avulso' and e.v ->> 'base' like 'definido por %') then
      raise exception 'z67: sobrescrita do conservador vazou para o base';
    end if;

    -- g) evento planejado ponta a ponta (se houver evento de referência com venda): salvar, curva, pausa, cenários,
    --    alterar, arquivar, trilha, nada se apaga
    select e.id into v_ref
      from fin.eventos e
     where e.setor = 'educacao' and e.venda_ate < v_dia and e.venda_ate - coalesce(e.carrinho_inicio, e.inicio) <= 30
       and (select max(c.total) from fin.receber_curva_evento(e.id) c) > 0
     order by e.venda_ate desc limit 1;
    if v_ref is null then
      raise notice 'z67: nenhum evento de referência com venda — parte g da conferência pulada';
    else
      select max(c.total) into v_tot from fin.receber_curva_evento(v_ref) c;
      select s.id into v_ev from public.fn_fin_evento_planejado_salvar(jsonb_build_object(
        'nome', 'Teste z67', 'abertura', v_dia + 14, 'evento_ref_id', v_ref, 'tamanho_base', 1,
        'tamanho_conservador', 0.5, 'tamanho_otimista', 1.5, 'pausa_avulso', true)) s;
      -- venda do evento no horizonte = Σ round(tamanho × venda_ref(d), 2) dos dias ≤ horizonte
      select coalesce(sum(round(c.liquido, 2)), 0) into v_x from fin.receber_curva_evento(v_ref) c where v_dia + 14 + c.d <= v_ate;
      select coalesce(sum((e.v ->> 'valor_venda')::numeric), 0) into v_y
        from public.fn_fin_receber_semanal(now(), v_ate, 'base') d, jsonb_array_elements(d.detalhe) e(v)
       where d.bloco = 4 and d.ref = 'ep:' || v_ev and d.componente = 'antecipacao';
      if v_x <> v_y then raise exception 'z67: bloco 4 base (%) ≠ curva × 1 (%)', v_y, v_x; end if;
      select coalesce(sum((e.v ->> 'valor_venda')::numeric), 0) into v_y
        from public.fn_fin_receber_semanal(now(), v_ate, 'otimista') d, jsonb_array_elements(d.detalhe) e(v)
       where d.bloco = 4 and d.ref = 'ep:' || v_ev and d.componente = 'antecipacao';
      if v_y <> (select coalesce(sum(round(1.5 * c.liquido, 2)), 0) from fin.receber_curva_evento(v_ref) c
                  where v_dia + 14 + c.d <= v_ate) then
        raise exception 'z67: bloco 4 otimista fora de 1,5 × curva';
      end if;
      -- HM avulso sem dia de venda nas semanas do evento
      if exists (select 1 from public.fn_fin_receber_semanal(now(), v_ate, 'base') d, jsonb_array_elements(d.detalhe) e(v),
                        fin.receber_curva_evento(v_ref) c
                  where d.bloco = 3 and d.ref = 'vn:hm_avulso'
                    and date_trunc('week', (e.v ->> 'dia')::date::timestamp) = date_trunc('week', (v_dia + 14 + c.d)::timestamp)) then
        raise exception 'z67: HM avulso não pausou na semana do evento';
      end if;
      -- alterar (tamanho 1,2) e salvar igual (sem trilha nova)
      perform 1 from public.fn_fin_evento_planejado_salvar(jsonb_build_object(
        'id', v_ev, 'nome', 'Teste z67', 'abertura', v_dia + 14, 'evento_ref_id', v_ref, 'tamanho_base', 1.2,
        'tamanho_conservador', 0.5, 'tamanho_otimista', 1.5, 'pausa_avulso', true));
      perform 1 from public.fn_fin_evento_planejado_salvar(jsonb_build_object(
        'id', v_ev, 'nome', 'Teste z67', 'abertura', v_dia + 14, 'evento_ref_id', v_ref, 'tamanho_base', 1.2,
        'tamanho_conservador', 0.5, 'tamanho_otimista', 1.5, 'pausa_avulso', true));
      -- listar
      if (select l.situacao from public.fn_fin_eventos_planejados_listar() l where l.id = v_ev) <> 'ativo'
         or (select l.total_ref from public.fn_fin_eventos_planejados_listar() l where l.id = v_ev) <> v_tot then
        raise exception 'z67: listar não devolve o evento ativo com o total da referência';
      end if;
      -- erros de entrada
      foreach f in array array[
          format('select * from public.fn_fin_evento_planejado_salvar(%L::jsonb)', jsonb_build_object('nome','x','abertura',v_dia,'evento_ref_id',v_ref,'tamanho_base',1,'tamanho_conservador',1.1,'tamanho_otimista',1.5)),
          format('select * from public.fn_fin_evento_planejado_salvar(%L::jsonb)', jsonb_build_object('nome','x','abertura',v_dia,'evento_ref_id',v_ref,'tamanho_base',1,'tamanho_conservador',1,'tamanho_otimista',1,'cor','azul')),
          format('select * from public.fn_fin_evento_planejado_salvar(%L::jsonb)', jsonb_build_object('nome','x','abertura','2026-13-45','evento_ref_id',v_ref,'tamanho_base',1,'tamanho_conservador',1,'tamanho_otimista',1)),
          format('select * from public.fn_fin_evento_planejado_salvar(%L::jsonb)', jsonb_build_object('nome','x','abertura',v_dia - 60,'evento_ref_id',v_ref,'tamanho_base',1,'tamanho_conservador',1,'tamanho_otimista',1)),
          format('select * from public.fn_fin_evento_planejado_salvar(%L::jsonb)', jsonb_build_object('nome','x','abertura',v_dia,'evento_ref_id',-1,'tamanho_base',1,'tamanho_conservador',1,'tamanho_otimista',1)),
          format('select * from public.fn_fin_evento_planejado_arquivar(%s, %L)', v_ev, 'x')] loop
        v_ok := false;
        begin
          execute f;
        exception when invalid_parameter_value then v_ok := true;
        end;
        if not v_ok then raise exception 'z67: entrada inválida aceita: %', f; end if;
      end loop;
      -- arquivar: some da projeção; não muda mais; nada se apaga
      perform 1 from public.fn_fin_evento_planejado_arquivar(v_ev, 'teste z67');
      if exists (select 1 from public.fn_fin_receber_semanal(now(), v_ate, 'base') d where d.bloco = 4 and d.ref = 'ep:' || v_ev) then
        raise exception 'z67: evento arquivado continua na projeção';
      end if;
      if (select string_agg(tr.acao, ',' order by tr.id) from fin.eventos_planejados_trilha tr where tr.evento_id = v_ev)
         is distinct from 'criado,alterado,arquivado' then
        raise exception 'z67: trilha fora do esperado (criado, alterado, arquivado)';
      end if;
      foreach f in array array[
          format('update fin.eventos_planejados set nome = %L where id = %s', 'y', v_ev),
          format('delete from fin.eventos_planejados where id = %s', v_ev),
          'truncate fin.eventos_planejados cascade',
          format('update fin.eventos_planejados_trilha set acao = %L where evento_id = %s', 'criado', v_ev),
          format('delete from fin.eventos_planejados_trilha where evento_id = %s', v_ev),
          'truncate fin.eventos_planejados_trilha'] loop
        v_ok := false;
        begin
          execute f;
        exception when insufficient_privilege then v_ok := true;
        end;
        if not v_ok then raise exception 'z67: só-acréscimo furado: %', f; end if;
      end loop;
      v_ok := false;
      begin
        perform 1 from public.fn_fin_evento_planejado_salvar(jsonb_build_object(
          'id', v_ev, 'nome', 'Teste z67', 'abertura', v_dia + 14, 'evento_ref_id', v_ref, 'tamanho_base', 1,
          'tamanho_conservador', 0.5, 'tamanho_otimista', 1.5));
      exception when invalid_parameter_value then v_ok := true;
      end;
      if not v_ok then raise exception 'z67: salvar alterou evento arquivado'; end if;
      -- quem não opera não grava
      perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
      v_ok := false;
      begin
        perform 1 from public.fn_fin_evento_planejado_arquivar(v_ev, 'teste z67');
      exception when insufficient_privilege then v_ok := true;
      end;
      if not v_ok then raise exception 'z67: arquivar sem gp_pode_operar_financeiro passou'; end if;
      perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    end if;
    -- sugestões: 4 chaves; sem premissa, valor efetivo = sugestão
    if (select string_agg(s.chave, ',' order by s.chave) from public.fn_fin_receber_sugestoes('base') s)
       <> 'reserva_reembolso,venda_semanal:hm_avulso,venda_semanal:holding_total,venda_semanal:outros'
       or exists (select 1 from public.fn_fin_receber_sugestoes('base') s
                   where s.chave <> 'venda_semanal:hm_avulso' and s.valor_efetivo is distinct from s.sugestao) then
      raise exception 'z67: fn_fin_receber_sugestoes fora do contrato';
    end if;
    raise exception using errcode = 'P0001', message = 'z67_desfaz';
  exception when raise_exception then
    if sqlerrm <> 'z67_desfaz' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  if exists (select 1 from fin.premissas_receber where fonte = 'teste z67')
     or exists (select 1 from fin.eventos_planejados) or exists (select 1 from fin.eventos_planejados_trilha) then
    raise exception 'z67: linhas de teste não foram desfeitas';
  end if;
end $chk$;


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres; cada bloco é UMA chamada — o MCP é autocommit) ════════════════
-- <UUID_FINANCEIRO> = perfis.id ativo que VÊ o financeiro. explain: rodar 2× e usar a 2ª (1ª é cache frio).
-- A projeção nasce DESLIGADA: os blocos abaixo ligam dentro da transação e desfazem no rollback (insert, não UPDATE).
/*
-- E0) ANTES de aplicar a z67 (z66 viva) e DE NOVO depois (mesma consulta): o split de bytes do veredito do João.
--     Esperado depois: linhas_com_detalhe_b2 = contratos_b2 (antes: todas as linhas não-garantia do bloco 2).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
select count(*) linhas, pg_size_pretty(sum(pg_column_size(x))::bigint) total,
       pg_size_pretty(sum(pg_column_size(x.detalhe)) filter (where x.bloco = 2)::bigint) detalhe_bloco2,
       count(*) filter (where x.bloco = 2 and x.detalhe is not null) linhas_com_detalhe_b2,
       count(distinct x.ref) filter (where x.bloco = 2) contratos_b2
  from public.fn_fin_receber_semanal(null, null) x;
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
rollback;

-- E7) A RPC inteira com a projeção LIGADA. Meta: ≤ 300 ms quente (z66: medir o mesmo explain desligado para a diferença).
begin;
insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values ('projecao_no_receber', current_date, 1, 'prova z67');
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null, 'conservador');
explain (analyze, buffers) select * from public.fn_fin_receber_sugestoes('base');
explain (analyze, buffers) select * from public.fn_fin_eventos_planejados_listar();
select count(*) linhas, count(*) filter (where bloco in (3,4,6,8)) linhas_novas,
       pg_size_pretty(sum(pg_column_size(x))::bigint) total,
       pg_size_pretty(sum(pg_column_size(x)) filter (where bloco in (3,4,6,8))::bigint) bytes_novos
  from public.fn_fin_receber_semanal(null, null) x;
rollback;

-- E8) Por dentro (as funções SQL com "set search_path" não são inlinadas: o explain acima só mostra Function Scan).
--     Esperado: Index Scan / Bitmap Index Scan em hotmart_transacoes_aprovado_pago_idx (ramo pago) e
--     hotmart_transacoes_status_idx (ramo estorno); NENHUM "Seq Scan on hotmart_transacoes".
explain (analyze, buffers)
with seg as (select (date_trunc('week', current_date::timestamp))::date seg),
sem as materialized (
  select s.seg - 7 * g.n ini from seg s cross join generate_series(1, 52) g(n)
   where not exists (select 1 from fin.eventos e where e.setor = 'educacao'
                        and (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) <= 10
                        and coalesce(e.carrinho_inicio, e.inicio) <= s.seg - 7 * g.n + 6 and e.venda_ate >= s.seg - 7 * g.n)
   order by 1 desc limit 12)
select s.ini, coalesce(m.grupo, 'outros'), sum(coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0)))
  from sem s
  join fin.vw_transacoes t on t.aprovado_em >= (s.ini::timestamp at time zone 'America/Sao_Paulo')
   and t.aprovado_em < ((s.ini + 7)::timestamp at time zone 'America/Sao_Paulo') and t.status in ('APPROVED','COMPLETE')
  left join fin.receber_grupos_venda_nova m on m.familia = t.familia
 where coalesce(t.recorrencia, 1) <= 1 and (m.familia is null or m.grupo is not null)
 group by 1, 2;
explain (analyze, buffers)
select count(*), sum(coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0)))
  from fin.vw_transacoes t
 where t.aprovado_em >= ((current_date - interval '9 months')::date::timestamp at time zone 'America/Sao_Paulo')
   and t.aprovado_em < (current_date::timestamp at time zone 'America/Sao_Paulo')
   and t.status in ('REFUNDED','PARTIALLY_REFUNDED','CHARGEBACK');
explain (analyze, buffers)
select count(*), sum(coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0)))
  from fin.vw_transacoes t
 where t.aprovado_em >= ((current_date - interval '9 months')::date::timestamp at time zone 'America/Sao_Paulo')
   and t.aprovado_em < (current_date::timestamp at time zone 'America/Sao_Paulo')
   and t.status in ('APPROVED','COMPLETE');

-- E9) Curva do evento de referência (produto_idx): trocar <EVENTO_ID> por um id de fin.eventos com venda (ex.: o do CNHF).
explain (analyze, buffers)
select (t.aprovado_em at time zone 'America/Sao_Paulo')::date, sum(coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0)))
  from fin.eventos e
  join fin.evento_produtos p on p.categoria = e.categoria and p.papel = 'oferta'
  join fin.vw_transacoes t on t.produto_id = p.produto_id
   and t.aprovado_em >= (coalesce(e.carrinho_inicio, e.inicio)::timestamp at time zone 'America/Sao_Paulo')
   and t.aprovado_em < ((e.venda_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
 where e.id = <EVENTO_ID> and t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) <= 1
 group by 1;
select * from fin.receber_curva_evento(<EVENTO_ID>);

-- E10) Board (bloco 8): leitura do combinado + contrato_rec_idx por e-mail.
explain (analyze, buffers)
with bd as materialized (
  select v.contato_hm_id, lower(trim(v.email::text)) email, ch.produto origem, v.vencimento, v.saldo_a_pagar
    from cs.vw_fin_contas_receber v join cs.contatos_hm ch on ch.id = v.contato_hm_id
   where ch.produto in ('HM','AURUM') and v.vencimento >= current_date and v.vencimento <= current_date + 95
     and coalesce(v.saldo_a_pagar, 0) > 0.5 and v.status_financeiro not in ('cancelado','reembolsado','quitado'))
select t.email, t.familia from fin.vw_transacoes t
 where t.email in (select bd.email from bd) and t.oferta_modo like 'HOTMART_INSTALLMENTS%' and t.recorrencia is not null
 group by t.email, t.familia, t.oferta_codigo
having max(t.parcelas) > coalesce(max(t.recorrencia) filter (where t.grupo = 'pago'), 0);

-- S2) Sugestões medidas por grupo (as 12 semanas usadas e o valor de cada uma em "medida").
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
select chave, sugestao, base_medida, valor_efetivo, origem, medida from public.fn_fin_receber_sugestoes('base');
rollback;

-- S3) Soma por bloco e grupo nos 3 cenários, projeção LIGADA (o que entra no caixa: situacao = a_receber; o bloco 8
--     aparece em "informativo", fora da soma). Corte 25/09, horizonte 31/12.
begin;
insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values ('projecao_no_receber', date '2000-01-02', 1, 'prova z67');
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
with b as (select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'base')),
     c as (select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'conservador')),
     o as (select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'otimista'))
select g.bloco, g.grupo, g.situacao,
       (select round(sum(b.valor), 2) from b where b.bloco = g.bloco and b.grupo = g.grupo and b.situacao = g.situacao) base,
       (select round(sum(c.valor), 2) from c where c.bloco = g.bloco and c.grupo = g.grupo and c.situacao = g.situacao) conservador,
       (select round(sum(o.valor), 2) from o where o.bloco = g.bloco and o.grupo = g.grupo and o.situacao = g.situacao) otimista,
       (select count(*) from b where b.bloco = g.bloco and b.grupo = g.grupo and b.situacao = g.situacao) linhas
  from (select distinct b.bloco, b.grupo, b.situacao from b where b.situacao in ('a_receber','informativo','sem_base')) g
 order by 1, 2, 3;
select bloco, round(sum(valor) filter (where situacao = 'a_receber'), 2) soma_caixa
  from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31', 'base') group by 1 order by 1;
rollback;

-- P-GRANTS) Vivo.
select p.oid::regprocedure, p.proacl, p.prosecdef, p.proconfig from pg_proc p
 where (p.pronamespace = 'public'::regnamespace
        and p.proname in ('fn_fin_receber_semanal','fn_fin_receber_sugestoes','fn_fin_eventos_planejados_listar',
                          'fn_fin_evento_planejado_salvar','fn_fin_evento_planejado_arquivar'))
    or (p.pronamespace = 'fin'::regnamespace
        and p.proname in ('receber_posicao','receber_projecao','receber_sugestoes','receber_venda_semanal_medida',
                          'receber_reserva_medida','receber_curva_evento','premissa_linha','receber_brl',
                          'tg_eventos_planejados_guarda','tg_eventos_planejados_trilha',
                          'tg_eventos_planejados_trilha_so_acrescimo'))
 order by 1::text;
select relname, relacl, relrowsecurity from pg_class
 where oid in ('fin.eventos_planejados'::regclass, 'fin.eventos_planejados_trilha'::regclass,
               'fin.receber_grupos_venda_nova'::regclass);
*/
