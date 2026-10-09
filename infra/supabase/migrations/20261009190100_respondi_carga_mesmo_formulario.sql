-- 20261009190100: fn_respondi_carga só atualiza uma resposta existente se ela for do MESMO formulário.
--
-- STATUS: ver 20261009190000.explain.md §5.
-- POR QUE: pentester (09/10/2026, MÉDIO 1): com o webhook (respondi-webhook), quem tivesse a chave da URL e o uuid de
--   uma resposta de OUTRO formulário conseguia trocar e-mail, telefone, CPF e respostas dela (on conflict (uuid) do
--   update sem conferir form_slug). Corrige a classe: o sync e o webhook passam pela mesma regra.
-- EFEITO NO SYNC: nenhum. uuid é a PK e o uuid do Respondi é único entre formulários (0 casos em 09/10/2026).
-- O QUE FAZ: recria public.fn_respondi_carga (corpo de 20261004b) com "where respondi.respostas.form_slug =
--   excluded.form_slug" no do update. Resposta de outro formulário: não grava e não conta em 'respostas'.
-- REVERSÃO: recriar o corpo de 20261004b_respondi_carga.sql (o mesmo sem o where).
-- IDEMPOTENTE: create or replace; guarda pelo md5 do corpo vivo (o de 20261004b ou o desta migration).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.fn_respondi_carga(jsonb,jsonb)'))
       is distinct from '52ce3fdfb811e3d0219a5031a15c44ec'
     and (select prosrc from pg_proc where oid = to_regprocedure('public.fn_respondi_carga(jsonb,jsonb)')) !~ '20261009190100' then
    raise exception '20261009190100: corpo vivo de fn_respondi_carga mudou. Reler.';
  end if;
end
$g$;

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
         respostas=excluded.respostas, importado_em=now()
   -- 20261009190100: só a resposta do mesmo formulário (pentester, MÉDIO 1)
   where respondi.respostas.form_slug = excluded.form_slug;
  get diagnostics v_r = row_count;
  return jsonb_build_object('formularios', v_f, 'respostas', v_r);
end;
$function$;
revoke all on function public.fn_respondi_carga(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fn_respondi_carga(jsonb, jsonb) to service_role;
