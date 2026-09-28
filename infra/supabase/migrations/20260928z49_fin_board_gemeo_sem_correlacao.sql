-- 20260928z49 — Desempenho: o filtro de card gêmeo da z37 derrubou o board para 15,5 s (medido).
-- Qualquer subconsulta sobre cs.contatos_hm no WHERE (not exists correlacionado, not in, anti-join com CTE materializada)
-- faz o planejador reorganizar a view do board e reavaliá-la linha a linha dentro da função. Medido com cópias da
-- função: sem filtro 1,06 s · not exists 15,6 s · not in 15,5 s · anti-join CTE 15,7 s · array (InitPlan) 1,00 s.
-- Fica o array: a lista de gêmeos é calculada uma vez e não entra no plano da view. Mesmo resultado (381 cards).
do $do$
declare d text;
  velho text := E'    and not exists (\n      select 1 from cs.hm_comprador_alias al\n        join cs.contatos_hm cx on cx.id = b.contato_hm_id\n        join cs.contatos_hm cc on cc.comprador_id = al.canonico_id and cc.produto = cx.produto\n       where al.comprador_id = b.comprador_id)';
  novo text := E'    -- card gêmeo (z37/z49): cadastro com alias para outro cadastro que já tem card do mesmo produto.\n'
    || E'    -- Array de propósito (InitPlan): subconsulta aqui reavalia a view linha a linha (15 s medidos).\n'
    || E'    and not (b.contato_hm_id = any (array(\n'
    || E'      select cx.id from cs.hm_comprador_alias al\n'
    || E'        join cs.contatos_hm cx on cx.comprador_id = al.comprador_id\n'
    || E'        join cs.contatos_hm cc on cc.comprador_id = al.canonico_id and cc.produto = cx.produto)))';
begin
  d := pg_get_functiondef('public.fn_fin_board(text,text)'::regprocedure);
  -- (aplicada primeiro com "not in"; esta versão parte do corpo vigente em qualquer um dos dois)
  d := regexp_replace(d, E'    -- card gêmeo \\(z37/z49\\)[^\\n]*\\n    and b\\.contato_hm_id not in \\(.*?cc\\.produto = cx\\.produto\\)', velho, 's');
  if position(velho in d) = 0 then raise exception 'z49: filtro antigo não encontrado'; end if;
  execute replace(d, velho, novo);
end $do$;
