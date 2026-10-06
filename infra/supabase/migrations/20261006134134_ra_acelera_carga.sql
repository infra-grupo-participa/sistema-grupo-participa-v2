-- 20261006134134: Remoção de Acessos, CARGA das 41 pessoas do Acelera Holding com reembolso sem recompra
--
-- STATUS: NÃO APLICADA. Ensaio: 20261006134134_ensaio.sql (begin … rollback). Notas: 20261006134134.explain.md.
-- DEPENDE de 20261006134133_ra_acelera_holding.sql (aplicar aquela antes; a guarda abaixo confere).
--
-- O QUE FAZ: abre 1 caso de remoção do Acelera Holding (Hotmart 8381847) por pessoa que teve reembolso e não tem outra
--   compra válida do Acelera. Pedido do Victor (06/10/2026): essas pessoas entram como casos para o Thomas marcar,
--   SEM Slack (avisar_slack = false: fora do aviso, do lembrete e do n8n) e SEM prazo (prazo_em nulo: são antigas).
--   origem = 'carga'. Cada caso nasce em_remocao com os 3 itens do Thomas (Grupo de informes, Área de membros (Hotmart),
--   Obvio), pela mesma função do webhook (ra_criar_caso_acelera).
--
-- FONTE: fin.hotmart_transacoes, conta academy (a venda do Acelera não entra em public.compras: 0 linhas do 8381847).
-- REGRA (a mesma do webhook, public.ra_acelera_compras_validas): status REFUNDED e nenhuma OUTRA transação do 8381847
--   APPROVED/COMPLETE/COMPLETED da mesma pessoa (e-mail, documento ou telefone).
-- DATA: ocorrido_em = data da compra (aprovado_em, ou pedido_em). O financeiro não guarda a data do reembolso.
--
-- TRAVA: o resultado da regra tem que bater com os 41 IDs da aba "Reembolsos sem recompra" (coluna G, ID Transação) da
--   planilha [CNHF AGO/2026] VENDAS ACELERA HOLDING (1Y40pTGVAPgdH8lJDvbUgQZSdcwPYYsmrU-bBUnejlb4), lida em 06/10/2026.
--   Divergiu: aborta e lista só os IDs (nenhum e-mail, documento ou telefone no erro).
--   Exceção aceita: transação que a regra acha e a planilha não, desde que JÁ tenha caso (chegou pelo webhook depois
--   da 20261006134133). Quem já tem caso do Acelera (pelo webhook ou reprocessamento) não ganha outro.
-- REVERSÃO: ver 20261006134134.explain.md.

set local lock_timeout = '5s';

do $carga$
declare
  v_planilha constant text[] := array[
    'HP0078747564', 'HP0168811099', 'HP0519702096', 'HP0879426993', 'HP0970154926', 'HP1047529970',
    'HP1249570759', 'HP1501565965', 'HP1712793111', 'HP1731866924', 'HP1752806997', 'HP1817060063',
    'HP1934039053', 'HP1961693356', 'HP1987885286', 'HP2204886954', 'HP2214136252', 'HP2224509148',
    'HP2345657435', 'HP2350722112', 'HP2368420561', 'HP2410727616', 'HP2643083659', 'HP2656966912',
    'HP2679297672', 'HP2787027364', 'HP3011736046', 'HP3034420907', 'HP3044024305', 'HP3089824749',
    'HP3117911418', 'HP3280675527', 'HP3287538066', 'HP3324136829', 'HP3401784419', 'HP3573404181',
    'HP3695962442', 'HP3955125025', 'HP3987974822', 'HP4049039338', 'HP4102099105'
  ];
  v_regra text[];
  v_faltam text[];
  v_sobram text[];
  v_misturados text[];
  v_criados int := 0;
  v_ja_tinham int := 0;
  r record;
  v_caso uuid;
begin
  -- guarda: a 20261006134133 está aplicada
  if to_regprocedure('public.ra_criar_caso_acelera(jsonb)') is null
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'ra_casos' and column_name = 'avisar_slack') then
    raise exception '20261006134134: aplicar antes a 20261006134133_ra_acelera_holding.sql';
  end if;
  if cardinality(v_planilha) <> 41 then
    raise exception '20261006134134: a lista da planilha tem % IDs (esperado 41)', cardinality(v_planilha);
  end if;

  create temp table _carga on commit drop as
    select h.transacao, h.comprador_nome as nome, h.comprador_email as email, h.comprador_documento as documento,
           h.comprador_telefone as telefone, h.produto_nome, h.oferta_codigo, h.valor_cobrado,
           coalesce(h.aprovado_em, h.pedido_em) as quando,
           lower(trim(coalesce(h.comprador_email, ''))) as em,
           regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') as doc,
           regexp_replace(coalesce(h.comprador_telefone, ''), '\D', '', 'g') as fone
      from (select * from fin.hotmart_transacoes where conta = 'academy') h
     where h.produto_id = '8381847' and upper(h.status) = 'REFUNDED'
       and cardinality(public.ra_acelera_compras_validas(h.transacao, h.comprador_email, h.comprador_documento, h.comprador_telefone)) = 0;

  select coalesce(array_agg(transacao order by transacao), '{}') into v_regra from _carga;

  -- trava 1: todo ID da planilha tem que sair da regra
  select coalesce(array_agg(x order by x), '{}') into v_faltam
    from unnest(v_planilha) x where x <> all (v_regra);
  -- trava 2: o que a regra acha e a planilha não, só se já tiver caso (chegou pelo webhook)
  select coalesce(array_agg(x order by x), '{}') into v_sobram
    from unnest(v_regra) x
   where x <> all (v_planilha)
     and not exists (select 1 from public.ra_casos c where c.hotmart_transaction = x and c.linha = 'acelera');
  if cardinality(v_faltam) > 0 or cardinality(v_sobram) > 0 then
    raise exception '20261006134134: regra e planilha divergem. Na planilha e fora da regra: [%]. Na regra, fora da planilha e sem caso: [%]',
      array_to_string(v_faltam, ', '), array_to_string(v_sobram, ', ');
  end if;

  -- trava 3: 1 caso por pessoa = 1 por e-mail. Documento ou telefone ligando e-mails diferentes: aborta.
  select coalesce(array_agg(distinct a.transacao order by a.transacao), '{}') into v_misturados
    from _carga a join _carga b on a.transacao <> b.transacao and a.em <> b.em
     and ((length(a.doc) >= 11 and a.doc = b.doc)
          or (length(a.fone) >= 10 and length(b.fone) >= 10
              and (a.fone = b.fone or a.fone = '55' || b.fone or '55' || a.fone = b.fone)))
   where a.transacao = any (v_planilha);
  if cardinality(v_misturados) > 0 then
    raise exception '20261006134134: documento ou telefone liga e-mails diferentes nas transações [%]: conferir à mão antes da carga',
      array_to_string(v_misturados, ', ');
  end if;

  -- 1 caso por pessoa (e-mail), pela transação mais recente; pula quem já tem caso do Acelera
  for r in
    select distinct on (c.em) c.*
      from _carga c
     where c.transacao = any (v_planilha)
     order by c.em, c.quando desc nulls last, c.transacao
  loop
    if exists (select 1 from public.ra_casos k
                where k.linha = 'acelera'
                  and (k.hotmart_transaction in (select x.transacao from _carga x where x.em = r.em)
                       or (r.em <> '' and lower(trim(coalesce(k.email, ''))) = r.em))) then
      v_ja_tinham := v_ja_tinham + 1;
      continue;
    end if;
    v_caso := public.ra_criar_caso_acelera(jsonb_build_object(
      'transacao', r.transacao, 'tipo', 'reembolso', 'produto_nome', r.produto_nome, 'oferta', r.oferta_codigo,
      'valor', r.valor_cobrado, 'nome', r.nome, 'email', r.email, 'telefone', r.telefone, 'documento', r.documento,
      'ocorrido_em', r.quando, 'origem', 'carga', 'avisar_slack', false, 'com_prazo', false,
      'motivo', 'Reembolso no Acelera Holding sem outra compra válida do Acelera (carga de 06/10/2026, sem prazo e sem Slack): '
                || 'remover do Grupo de informes, da Área de membros (Hotmart) e do Obvio.',
      'detalhe', jsonb_build_object('fonte', 'fin.hotmart_transacoes', 'status_compra', 'REFUNDED',
                                    'ocorrido_em_e', 'data da compra (o financeiro não guarda a data do reembolso)',
                                    'planilha', '1Y40pTGVAPgdH8lJDvbUgQZSdcwPYYsmrU-bBUnejlb4 / Reembolsos sem recompra')));
    if v_caso is null then
      v_ja_tinham := v_ja_tinham + 1;
    else
      v_criados := v_criados + 1;
    end if;
  end loop;

  -- conferência: toda pessoa da planilha tem caso do Acelera
  if exists (select 1 from _carga c
              where c.transacao = any (v_planilha)
                and not exists (select 1 from public.ra_casos k
                                 where k.linha = 'acelera'
                                   and (k.hotmart_transaction = c.transacao
                                        or (c.em <> '' and lower(trim(coalesce(k.email, ''))) = c.em)))) then
    raise exception '20261006134134: pessoa da planilha ficou sem caso depois da carga';
  end if;

  raise notice '20261006134134 carga Acelera: % caso(s) criado(s), % pessoa(s) já tinham caso', v_criados, v_ja_tinham;
  drop table _carga;
end
$carga$;
