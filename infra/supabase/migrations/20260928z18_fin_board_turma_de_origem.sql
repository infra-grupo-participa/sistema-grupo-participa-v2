-- 20260928z18 — fn_fin_board exibe e filtra pela turma de origem (fin.vw_turma_origem_card). Dinheiro intocado
-- (medido: 343 cards, pago R$ 2.077.281, saldo R$ 3.970.064 antes e depois). Novatos em T39–T41: 183 → 89.
do $do$
declare v text;
begin
  v := pg_get_functiondef('public.fn_fin_board(text,text)'::regprocedure);
  if position('vw_turma_origem_card' in v) > 0 then return; end if;
  v := replace(v, 'b.turma, b.turma_origem', 'coalesce(tu.turma, b.turma), b.turma_origem');
  v := replace(v, 'left join fin.vw_acao_card a on a.contato_hm_id = b.contato_hm_id',
                  'left join fin.vw_acao_card a on a.contato_hm_id = b.contato_hm_id
  left join fin.vw_turma_origem_card tu on tu.contato_hm_id = b.contato_hm_id');
  v := replace(v, '(p_turma is null or b.turma = p_turma)', '(p_turma is null or coalesce(tu.turma, b.turma) = p_turma)');
  execute v;
end $do$;
