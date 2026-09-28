-- 20260928z46 — Conferência board × Hotmart compara o PERÍODO DO CARD (polimento, rodada 3).
-- Medido: depois de z43 (estorno) e z45 (parcelas), 3 cards ainda "divergem" — em todos, a
-- diferença é a compra de HM de R$ 15 mil feita ANTES do card (é a turma de origem, já na Trajetória). O card do
-- Programa conta só o dinheiro do Programa; a compra antiga não "falta no board".
-- Regra: a conferência ignora transação anterior ao 1º pagamento lançado no card daquela pessoa/produto (−1 dia de folga).
-- Card sem nenhum pagamento lançado (boleto gerado) segue comparando tudo.
do $do$
declare d text;
  alvo text := E'     where t.grupo in (''pago'',''estornado'')\n';
begin
  d := pg_get_functiondef('public.fn_fin_board_hotmart()'::regprocedure);
  if position('periodo_do_card' in d) = 0 then
    if position(alvo in d) = 0 then raise exception 'z46: trecho de fn_fin_board_hotmart não encontrado'; end if;
    d := replace(d, alvo, alvo
      || E'       -- periodo_do_card (z46): compra anterior ao 1º pagamento do card é turma de origem, não falta\n'
      || E'       and coalesce(t.aprovado_em, t.pedido_em) >= coalesce(\n'
      || E'             (select min(hp.pago_em) from card k2 join cs.hm_pagamentos hp on hp.comprador_id = k2.comprador_id\n'
      || E'               where k2.pessoa = e.pessoa and k2.origem = e.familia\n'
      || E'                 and cs.fn_hm_pagamento_do_produto(hp.oferta_codigo, k2.origem)) - interval ''1 day'',\n'
      || E'             ''-infinity''::timestamptz)\n');
    execute d;
  end if;
end $do$;
