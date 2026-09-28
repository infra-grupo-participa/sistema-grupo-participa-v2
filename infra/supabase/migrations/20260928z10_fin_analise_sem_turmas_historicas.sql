-- 20260928z10 — a aba Análise ("dependência de eventos") continua medindo só as ações de 2026: as janelas contínuas das
-- turmas históricas (prioridade 50, z7) cobririam o calendário inteiro e levariam o número a ~100% em silêncio.
do $do$
declare v text;
begin
  v := pg_get_functiondef('public.fn_fin_faturamento_por_acao(text)'::regprocedure);
  if position('prioridade <> 50' in v) > 0 then return; end if;
  v := replace(v, 'and a.inicio is not null and a.fim is not null', 'and a.inicio is not null and a.fim is not null and a.prioridade <> 50');
  execute v;
end $do$;
