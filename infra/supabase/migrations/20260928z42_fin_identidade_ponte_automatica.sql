-- 20260928z42 — A ponte entre CPFs fica fora do grafo SOZINHA, a cada recálculo (consertar a classe da z41).
-- Antes: só o documento ligado a 7+ e-mails ia para revisão; ponte de 2 CPFs dependia de alguém bloquear à mão.
-- Agora, a cada fin.recalcular_identidade():
--   · e-mail vizinho direto de 2+ CPFs diferentes → revisão ("ponte entre CPFs");
--   · CNPJ que alcança 2+ CPFs diferentes pelos seus e-mails → revisão ("CNPJ ponte entre CPFs").
-- Revisão tira o nó das arestas (mesmo tratamento do bloqueio), mas é recalculada: some quando a ponte some.
-- CPF já bloqueado/em revisão (000.000.000-00, documento de escritório) não conta como segundo CPF.
-- Medido: 81 pontes automáticas, todas já no bloqueio (z27, z29, z41); 0 novas; 0 pessoas com 2+ CPFs.
do $do$
declare d text; alvo text := E'  insert into fin.identidade_revisao (no, motivo, emails)\n  select b.valor, ''bloqueado: '' || b.motivo';
begin
  d := pg_get_functiondef('fin.recalcular_identidade()'::regprocedure);
  if position('ponte entre CPFs' in d) = 0 then
    if position(alvo in d) = 0 then raise exception 'z42: trecho de fin.recalcular_identidade não encontrado'; end if;
    d := replace(d, alvo,
      E'  -- z42: ponte entre CPFs (e-mail de escritório/cônjuge) nunca junta duas pessoas\n'
      || E'  insert into fin.identidade_revisao (no, motivo, emails)\n'
      || E'  select x.no, ''ponte entre CPFs: e-mail ligado a '' || x.n || '' CPFs diferentes — não juntado'', null\n'
      || E'    from (select e.no, count(distinct e.cpf) n\n'
      || E'            from (select a no, b cpf from fin.identidade_aresta where a like ''e:%'' and b ~ ''^d:\\d{11}$''\n'
      || E'                  union select b, a from fin.identidade_aresta where b like ''e:%'' and a ~ ''^d:\\d{11}$'') e\n'
      || E'           where e.cpf not in (select valor from fin.identidade_bloqueio)\n'
      || E'             and e.cpf not in (select no from fin.identidade_revisao)\n'
      || E'           group by e.no having count(distinct e.cpf) > 1) x\n'
      || E'  on conflict (no) do nothing;\n'
      || E'  insert into fin.identidade_revisao (no, motivo, emails)\n'
      || E'  select x.no, ''CNPJ ponte entre CPFs: alcança '' || x.n || '' CPFs pelos e-mails — não juntado'', null\n'
      || E'    from (select c.b no, count(distinct p.b) n\n'
      || E'            from fin.identidade_aresta c\n'
      || E'            join fin.identidade_aresta p on p.a = c.a and p.b ~ ''^d:\\d{11}$''\n'
      || E'           where c.b ~ ''^d:\\d{14}$'' and c.a like ''e:%''\n'
      || E'             and c.a not in (select no from fin.identidade_revisao)\n'
      || E'             and p.b not in (select valor from fin.identidade_bloqueio)\n'
      || E'             and p.b not in (select no from fin.identidade_revisao)\n'
      || E'           group by c.b having count(distinct p.b) > 1) x\n'
      || E'  on conflict (no) do nothing;\n'
      || alvo);
    execute d;
  end if;
end $do$;
