-- 20260928k — O extrato da pessoa não mostra produto 'A_CLASSIFICAR' (reprovação do Fable, 27/09/2026).
-- fn_fin_hotmart_extrato filtra só por e-mail. Com o 446345 espelhado (20260928h), o "Curso Prático de Holding Familiar"
-- passou a aparecer no extrato da ficha e na linha expansível de Pessoas antes de o João decidir o que ele é.
-- Recria a partir do corpo VIGENTE trocando só o where (1 ocorrência, conferida).
-- O contador de fn_fin_hotmart_sync_status continua contando tudo: é saúde do espelho, não dinheiro.
do $do$
declare v text; alvo text := 'where t.email in (select email from alvo)';
begin
  v := pg_get_functiondef('public.fn_fin_hotmart_extrato(text)'::regprocedure);
  if (length(v) - length(replace(v, alvo, ''))) / length(alvo) <> 1 then
    raise exception 'fn_fin_hotmart_extrato: esperava 1 ocorrência do filtro por e-mail';
  end if;
  execute replace(v, alvo, alvo || $a$ and t.familia <> 'A_CLASSIFICAR'$a$);
end $do$;
