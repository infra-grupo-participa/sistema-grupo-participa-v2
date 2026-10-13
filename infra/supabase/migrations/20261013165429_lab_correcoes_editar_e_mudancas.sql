-- Correções do ensaio da 20261013 (lab): pode_editar com null nos responsáveis devolvia null (outro membro editava);
-- acumular os campos mudados com array_append (o literal 'régua' virava array malformado).
create or replace function lab.pode_editar(e lab.experimento) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false)
      or coalesce(auth.uid() = any(array_remove(array[e.criado_por, e.monta_id, e.confere_id, e.le_id], null)), false)
$$;
revoke all on function lab.pode_editar(lab.experimento) from public, anon, authenticated;

do $$
declare v_src text;
begin
  select pg_get_functiondef('public.lab_salvar(jsonb)'::regprocedure) into v_src;
  v_src := replace(v_src, 'v_mudou := v_mudou || ''régua''', 'v_mudou := array_append(v_mudou, ''régua'')');
  v_src := replace(v_src, 'v_mudou := v_mudou || ''métrica de decisão''', 'v_mudou := array_append(v_mudou, ''métrica de decisão'')');
  v_src := replace(v_src, 'v_mudou := v_mudou || ''tipo de métrica''', 'v_mudou := array_append(v_mudou, ''tipo de métrica'')');
  v_src := replace(v_src, 'v_mudou := v_mudou || ''variável''', 'v_mudou := array_append(v_mudou, ''variável'')');
  v_src := replace(v_src, 'v_mudou := v_mudou || ''sorteio''', 'v_mudou := array_append(v_mudou, ''sorteio'')');
  if v_src like '%v_mudou || %' then raise exception 'substituição incompleta'; end if;
  execute v_src;
end $$;