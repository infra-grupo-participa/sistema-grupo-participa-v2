-- Comercial: telefone e e-mail completos para a equipe do Comercial (pedido do Marcio, 16/10/2026, via João).
-- Ver 20261016a.explain.md.
--
--   crm.contatos_itens, public.crm_contatos   e-mail e telefone completos para quem já passa em eh_comercial (gestor, vendedor, leitor).
--   public.crm_estrategia_previa              e-mail completo na amostra da prévia (só o gestor já a recebe).
--   crm.mascara_texto                         deixa de mascarar telefone no Registro (e-mail segue mascarado). Vale só para o que
--                                             for gravado/lido daqui para frente: o que já está no log ficou mascarado na gravação
--                                             (crm.tg_log_mascara) e não volta.
--
-- Não muda: gates (crm.exige_comercial / eh_comercial), RLS, ACL, CPF, pessoas_ficha/pessoas_buscar (compartilhadas com o
-- Educacional). Técnica: cada função é lida por pg_get_functiondef, a expressão exata é trocada UMA vez e a função é recriada
-- com os mesmos atributos (SECURITY DEFINER/STABLE/search_path) e a mesma ACL (CREATE OR REPLACE preserva).

-- ─── Guarda de premissa: o corpo vivo é o que esta migration conhece ─────────────────────────────────────────────────
do $$
declare r record;
begin
  for r in select * from (values
      ('crm.contatos_itens(uuid[],boolean)'::regprocedure,  'ec1a024b8da6e797f79ca174bb277d78'),
      ('public.crm_contatos(text,integer,integer)'::regprocedure, '99194210bd58750394f993975945f29a'),
      ('public.crm_estrategia_previa(jsonb)'::regprocedure, 'a0fe962d610ebff6200ec5d389ed045f'),
      ('crm.mascara_texto(text)'::regprocedure,             '9ec7173c09029252da4ed079b4d12a5f')
    ) t(f, md5_esperado) loop
    if md5((select p.prosrc from pg_catalog.pg_proc p where p.oid = r.f)) <> r.md5_esperado then
      raise exception 'Premissa: % mudou desde a leitura (esperado md5 %).', r.f, r.md5_esperado;
    end if;
  end loop;
end $$;

-- ─── Troca das expressões (cada uma tem de aparecer exatamente 1 vez) ────────────────────────────────────────────────
do $$
declare r record; v_def text; n int;
begin
  for r in select * from (values
      ('crm.contatos_itens(uuid[],boolean)'::regprocedure,
         $q$'email', case when c.completo then d.d_email else pessoas.mascara_email(d.d_email) end,$q$,
         $q$'email', d.d_email,$q$),
      ('crm.contatos_itens(uuid[],boolean)'::regprocedure,
         $q$'telefone', case when c.completo or v_vend then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,$q$,
         $q$'telefone', d.d_telefone,$q$),
      ('public.crm_contatos(text,integer,integer)'::regprocedure,
         $q$'email', case when pc.completo then d.d_email else pessoas.mascara_email(d.d_email) end,$q$,
         $q$'email', d.d_email,$q$),
      ('public.crm_contatos(text,integer,integer)'::regprocedure,
         $q$'telefone', case when pc.completo or v_vend then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,$q$,
         $q$'telefone', d.d_telefone,$q$),
      ('public.crm_estrategia_previa(jsonb)'::regprocedure,
         $q$'email', pessoas.mascara_email(a.email),$q$,
         $q$'email', a.email,$q$),
      ('crm.mascara_texto(text)'::regprocedure,
         $q$if v ~ '\d{4}' then$q$,
         $q$if false and v ~ '\d{4}' then   -- 20261016a: telefone no Registro sai completo (e-mail segue mascarado)$q$)
    ) t(f, de, para) loop
    v_def := pg_get_functiondef(r.f);
    n := (length(v_def) - length(replace(v_def, r.de, ''))) / length(r.de);
    if n <> 1 then
      raise exception 'Trecho esperado 1 vez em %, achei % vezes: %', r.f, n, r.de;
    end if;
    execute replace(v_def, r.de, r.para);
  end loop;
end $$;
