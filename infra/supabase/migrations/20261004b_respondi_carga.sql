-- Carga do acervo do Respondi (chamada pelo script de importação com a service role).
-- Upsert idempotente: rodar de novo atualiza formulário e resposta, preserva aluno_id já casado.
create or replace function public.fn_respondi_carga(p_formularios jsonb, p_respostas jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_f int; v_r int;
begin
  insert into respondi.formularios (slug, form_id, workspace, nome, familia, turma_codigo, criado_em, n_respostas, campos)
  select x->>'slug', (x->>'form_id')::bigint, x->>'workspace', x->>'nome', x->>'familia', x->>'turma_codigo',
         (x->>'criado_em')::date, coalesce((x->>'n_respostas')::int,0), coalesce(x->'campos','[]'::jsonb)
    from jsonb_array_elements(coalesce(p_formularios,'[]'::jsonb)) x
  on conflict (slug) do update set nome=excluded.nome, familia=excluded.familia, turma_codigo=excluded.turma_codigo,
         n_respostas=excluded.n_respostas, campos=excluded.campos, importado_em=now();
  get diagnostics v_f = row_count;

  insert into respondi.respostas (uuid, form_slug, respondido_em, email, cpf, telefone, dados, respostas)
  select (x->>'uuid')::uuid, x->>'form_slug', (x->>'respondido_em')::timestamptz, nullif(x->>'email',''),
         nullif(x->>'cpf',''), nullif(x->>'telefone',''), coalesce(x->'dados','{}'::jsonb), coalesce(x->'respostas','[]'::jsonb)
    from jsonb_array_elements(coalesce(p_respostas,'[]'::jsonb)) x
  on conflict (uuid) do update set email=excluded.email, cpf=excluded.cpf, telefone=excluded.telefone,
         dados = respondi.respostas.dados || excluded.dados,
         respostas=excluded.respostas, importado_em=now();
  get diagnostics v_r = row_count;
  return jsonb_build_object('formularios', v_f, 'respostas', v_r);
end;
$function$;
revoke all on function public.fn_respondi_carga(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fn_respondi_carga(jsonb, jsonb) to service_role;
