-- Ensaio de 20261009190100 (transação desfeita). Usa uma resposta real de outro formulário só por uuid; não imprime dado.
begin;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _alvo on commit drop as
  select uuid, form_slug, md5(row(email, cpf, telefone, dados, respostas)::text) as antes
    from respondi.respostas where form_slug not in ('xmaNmRIV', 'HFaSnLRf') and cpf is not null limit 1;
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

insert into pg_temp._z_out (passo, linha)
select 'outro formulário (uuid de resposta com CPF)', public.fn_respondi_carga('[]'::jsonb, jsonb_build_array(jsonb_build_object(
  'uuid', a.uuid, 'form_slug', 'HFaSnLRf', 'respondido_em', '2026-10-09T10:00:00Z', 'email', 'x@exemplo.invalid',
  'cpf', '', 'telefone', '', 'dados', '{}'::jsonb, 'respostas', '[]'::jsonb)))::text
  from pg_temp._alvo a;
insert into pg_temp._z_out (passo, linha)
select 'linha intacta', (md5(row(r.email, r.cpf, r.telefone, r.dados, r.respostas)::text) = a.antes and r.form_slug = a.form_slug)::text
  from pg_temp._alvo a join respondi.respostas r on r.uuid = a.uuid;
insert into pg_temp._z_out (passo, linha)
select 'mesmo formulário atualiza', public.fn_respondi_carga('[]'::jsonb, jsonb_build_array(jsonb_build_object(
  'uuid', a.uuid, 'form_slug', a.form_slug, 'respondido_em', '2026-10-09T10:00:00Z', 'email', 'x@exemplo.invalid',
  'cpf', '', 'telefone', '', 'dados', '{}'::jsonb, 'respostas', '[]'::jsonb)))::text
  from pg_temp._alvo a;
insert into pg_temp._z_out (passo, linha)
select 'nova insere', public.fn_respondi_carga('[]'::jsonb, '[{"uuid":"00000000-0000-4000-8000-0000000000f1","form_slug":"HFaSnLRf","respondido_em":"2026-10-09T10:00:00Z","respostas":[{"p":"x","v":"y"}]}]'::jsonb)::text;
insert into pg_temp._z_out (passo, linha)
select 'grants', jsonb_build_object('anon', has_function_privilege('anon','public.fn_respondi_carga(jsonb,jsonb)','execute'),
  'authenticated', has_function_privilege('authenticated','public.fn_respondi_carga(jsonb,jsonb)','execute'),
  'service_role', has_function_privilege('service_role','public.fn_respondi_carga(jsonb,jsonb)','execute'))::text;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
