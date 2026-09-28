-- 20260928z34 — fin.nome_exibicao (z33) nas telas do financeiro: board, funis (compradores), "pagaram sem card" e
-- calculadora de pro rata. Nome de escritório, apelido ou nome com pedaço repetido vira o nome da pessoa.
-- Aplicada no banco por patch sobre o corpo VIGENTE de cada função (idempotente: só troca o que ainda não foi trocado).
-- fn_fin_board foi depois reescrita inteira em z37/z44 (com fin.nome_do_card), então não entra aqui.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.fn_fin_funil_compradores'::regproc);
  if position('fin.nome_exibicao(t.nome, t.email)' in d) = 0 then
    if position('         t.nome, t.email,' in d) = 0 then raise exception 'z34: funil_compradores'; end if;
    execute replace(d, '         t.nome, t.email,', '         fin.nome_exibicao(t.nome, t.email), t.email,');
  end if;

  d := pg_get_functiondef('public.fn_fin_programa_sem_card(text)'::regprocedure);
  if position('fin.nome_exibicao(x.nome, x.email)' in d) = 0 then
    if position('  select x.nome, x.email,' in d) = 0 then raise exception 'z34: programa_sem_card'; end if;
    execute replace(d, '  select x.nome, x.email,', '  select fin.nome_exibicao(x.nome, x.email), x.email,');
  end if;

  d := pg_get_functiondef('public.fn_fin_prorata_hm(numeric)'::regprocedure);
  if position('fin.nome_exibicao(k.nome, k.email)' in d) = 0 then
    if position('  select fin.chave_opaca(k.pessoa), k.nome, k.email,' in d) = 0 then raise exception 'z34: prorata_hm'; end if;
    execute replace(d, '  select fin.chave_opaca(k.pessoa), k.nome, k.email,',
                       '  select fin.chave_opaca(k.pessoa), fin.nome_exibicao(k.nome, k.email), k.email,');
  end if;
end $do$;
