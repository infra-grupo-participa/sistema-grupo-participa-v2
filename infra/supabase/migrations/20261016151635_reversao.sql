-- Reversão de 20261016a (volta a mascarar e-mail/telefone nas 4 funções). Cada trecho novo tem de aparecer 1 vez.
-- Não recupera o que foi gravado completo no Registro depois da migration (isso fica como está); só volta a regra.
do $$
declare r record; v_def text; n int;
begin
  for r in select * from (values
      ('crm.contatos_itens(uuid[],boolean)'::regprocedure,
         $q$'email', d.d_email,$q$,
         $q$'email', case when c.completo then d.d_email else pessoas.mascara_email(d.d_email) end,$q$),
      ('crm.contatos_itens(uuid[],boolean)'::regprocedure,
         $q$'telefone', d.d_telefone,$q$,
         $q$'telefone', case when c.completo or v_vend then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,$q$),
      ('public.crm_contatos(text,integer,integer)'::regprocedure,
         $q$'email', d.d_email,$q$,
         $q$'email', case when pc.completo then d.d_email else pessoas.mascara_email(d.d_email) end,$q$),
      ('public.crm_contatos(text,integer,integer)'::regprocedure,
         $q$'telefone', d.d_telefone,$q$,
         $q$'telefone', case when pc.completo or v_vend then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,$q$),
      ('public.crm_estrategia_previa(jsonb)'::regprocedure,
         $q$'email', a.email,$q$,
         $q$'email', pessoas.mascara_email(a.email),$q$),
      ('crm.mascara_texto(text)'::regprocedure,
         $q$if false and v ~ '\d{4}' then   -- 20261016a: telefone no Registro sai completo (e-mail segue mascarado)$q$,
         $q$if v ~ '\d{4}' then$q$)
    ) t(f, de, para) loop
    v_def := pg_get_functiondef(r.f);
    n := (length(v_def) - length(replace(v_def, r.de, ''))) / length(r.de);
    if n <> 1 then
      raise exception 'Trecho esperado 1 vez em %, achei % vezes: %', r.f, n, r.de;
    end if;
    execute replace(v_def, r.de, r.para);
  end loop;
end $$;
