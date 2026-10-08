-- 20261008150041 (20261008gl) — ENSAIO (produção). Roda a migration inteira e prova com JWT real (set local role authenticated).
-- Termina SEMPRE em erro proposital 'ENSAIO_OK …' (= ROLLBACK de tudo); o resultado vem na mensagem.
-- Esperado: Jonathan e Arthur gestor no CRM, em Estratégias, no crm_sessao e no MCP; Marcos e Jusy vendedor;
-- admin qualquer (Isabela), Victor Hugo e João Pedro NÃO gestores (crm_sessao → 42501 para quem não é vendedor);
-- lista vazia → só dev (João Pedro) é gestor; corpos de crm_vendedores/crm_salvar_ficha/crm_estrategia_salvar sem cargo.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare r record;
begin
  for r in select * from (values
    ('crm.eh_gestor()', '727b1e985c8e52b0e3a45d641dbab6c0'),
    ('crm.estrategia_eh_gestor()', '0f0febc677cea25ab187b0fbfaeb156d'),
    ('crm.mcp_papel(uuid)', '4cce11f1e90cf06ec2a56a9043a525ea'),
    ('public.crm_vendedores()', 'fbea2cc535485da9904a22c93a943b72'),
    ('public.crm_salvar_ficha(jsonb,boolean)', '99ab6c5410ec549917019ace4856a8e6'),
    ('public.crm_estrategia_salvar(jsonb)', '736964598059e9c57cc47284314b57d8')
  ) v(fn, esperado) loop
    if md5(pg_get_functiondef(r.fn::regprocedure)) <> r.esperado then
      raise exception 'premissa: % mudou (md5 vivo %, esperado %)', r.fn, md5(pg_get_functiondef(r.fn::regprocedure)), r.esperado;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config' and column_name = 'gestores') then
    raise exception 'premissa: crm.config.gestores já existe';
  end if;
  if (select count(*) from crm.config) <> 1 then raise exception 'premissa: crm.config precisa ter 1 linha'; end if;
  if (select count(*) from public.perfis p
       where p.id in ('bd5361bc-3c3f-4f85-8b5a-f21433d040e3', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975')
         and p.status = 'ativo' and lower(btrim(p.email)) like '%@advmais.com') <> 2 then
    raise exception 'premissa: os 2 gestores precisam existir em perfis, ativos e da equipe';
  end if;
end $g$;

-- ── 1. a lista ──
alter table crm.config add column gestores uuid[] not null default '{}';
comment on column crm.config.gestores is
  'Gestores do Comercial (CRM e Estratégias): ids de public.perfis. Vazia = só cargo dev. Regra em crm.eh_gestor(uuid).';
update crm.config set gestores = array['bd5361bc-3c3f-4f85-8b5a-f21433d040e3', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975']::uuid[];

-- ── 2. helper único ──
create function crm.eh_gestor(p_uid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008gl: gestor = id em crm.config.gestores (perfil ativo, e-mail da equipe). Lista vazia → só cargo dev.
  select coalesce((
    select case when cardinality(coalesce(c.gestores, '{}')) = 0 then p.cargo = 'dev'
                else p.id = any(c.gestores) end
      from public.perfis p
      left join crm.config c on true
     where p.id = p_uid and p.status = 'ativo' and lower(btrim(coalesce(p.email, ''))) like '%@advmais.com'
     limit 1), false);
$$;
revoke execute on function crm.eh_gestor(uuid) from public, anon, authenticated;
grant execute on function crm.eh_gestor(uuid) to service_role;

create or replace function crm.eh_gestor()
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008gl: a lista de crm.config.gestores (ver crm.eh_gestor(uuid)).
  select crm.eh_gestor((select auth.uid()));
$$;

create or replace function crm.estrategia_eh_gestor()
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008gl: Estratégias usa a mesma regra do CRM (crm.config.gestores).
  select coalesce(crm.eh_gestor(), false);
$$;

-- ── 3. quem calculava por cargo ──
create or replace function crm.mcp_papel(p_perfil uuid)
returns text language sql stable security definer set search_path = '' as $function$
  select case
           when crm.eh_gestor(pf.id) then 'gestor'   -- 20261008gl: era cargo dev/admin ou gestor + área comercial
           when pf.status = 'ativo' and coalesce(v.ativo, false)
                and 'comercial' = any(coalesce(pf.areas, '{}')) and 'comercial.vender' = any(coalesce(pf.funcoes, '{}'))
             then 'vendedor'
         end
    from public.perfis pf
    left join crm.vendedor v on v.perfil_id = pf.id
   where pf.id = p_perfil
     and lower(btrim(coalesce(pf.email, ''))) like '%@advmais.com';
$function$;

-- Funções grandes: troca cirúrgica do trecho no corpo VIVO (já conferido por md5 acima); aborta se o trecho não estiver lá.
do $t$
declare
  r record; v_def text; v_novo text;
begin
  for r in select * from (values
    ('public.crm_vendedores()',
     E'''papel'', case when p.status = ''ativo'' and (p.cargo in (''dev'', ''admin'')\n                                or (p.cargo = ''gestor'' and ''comercial'' = any(coalesce(p.areas, ''{}'')))) then ''gestor'' else ''vendedor'' end,',
     E'''papel'', case when crm.eh_gestor(p.id) then ''gestor'' else ''vendedor'' end,  -- 20261008gl'),
    ('public.crm_salvar_ficha(jsonb,boolean)',
     E'and ''comercial'' = any(coalesce(p.areas, ''{}''))\n         and p.cargo in (''dev'', ''admin'', ''gestor'')',
     E'\n         and crm.eh_gestor(p.id)  -- 20261008gl: gestores do Comercial (crm.config.gestores)'),
    ('public.crm_estrategia_salvar(jsonb)',
     E'-- Gestores do Comercial (mesma regra de crm.estrategia_eh_gestor), menos quem pediu.\n  for g in select p2.id from public.perfis p2\n            where p2.status = ''ativo'' and p2.cargo in (''dev'', ''admin'', ''gestor'') and ''comercial'' = any(coalesce(p2.areas, ''{}''))',
     E'-- Gestores do Comercial (20261008gl: crm.eh_gestor = crm.config.gestores), menos quem pediu.\n  for g in select p2.id from public.perfis p2\n            where crm.eh_gestor(p2.id)')
  ) v(fn, antes, depois) loop
    v_def := pg_get_functiondef(r.fn::regprocedure);
    if position(r.antes in v_def) = 0 then raise exception 'premissa: trecho não encontrado em %', r.fn; end if;
    v_novo := replace(v_def, r.antes, r.depois);
    if v_novo ~* 'cargo in \(' then raise exception 'premissa: % ainda tem regra por cargo', r.fn; end if;
    execute v_novo;
  end loop;
end $t$;


do $e$
declare
  r record; v text := ''; v_papel text; v_estr text; v_log bigint; v_t0 timestamptz; v_ms numeric;
begin
  for r in select * from (values
    ('jonathan', 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3'::uuid), ('arthur', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'),
    ('marcos', '9d347183-5395-434e-9e96-2a65dde1a3cd'), ('jusy', '412d7d8d-7699-4dbf-977c-3b3cc82223df'),
    ('admin_isabela', 'e1d2863d-c975-46bd-b35f-45b1039328e3'), ('victor_hugo', '81d2eaee-cce1-4058-8714-439b0fc6f970'),
    ('joao_pedro_dev', '843d43db-73b3-44a9-b449-1731e362dbc3')) u(nome, id) loop
    v := v || format(E'\n%s: mcp=%s', r.nome, coalesce(crm.mcp_papel(r.id), '-'));
    perform set_config('request.jwt.claims', json_build_object('sub', r.id, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', r.id::text, true);
    execute 'set local role authenticated';
    v_t0 := clock_timestamp();
    begin v_papel := public.crm_sessao() ->> 'papel'; exception when others then v_papel := 'ERRO ' || sqlstate; end;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 2);
    begin v_estr := public.crm_estrategia_acesso() ->> 'gestor'; exception when others then v_estr := 'ERRO ' || sqlstate; end;
    select count(*) into v_log from crm.log;
    v := v || format(' eh_gestor=%s estrategia=%s sessao=%s (%s ms) estr_acesso=%s log_visivel=%s',
                     crm.eh_gestor(), crm.estrategia_eh_gestor(), v_papel, v_ms, v_estr, v_log);
    execute 'reset role';
  end loop;
  -- crm_vendedores visto pelo Jonathan
  perform set_config('request.jwt.claims', json_build_object('sub', 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3', true);
  execute 'set local role authenticated';
  v := v || E'\ncrm_vendedores: ' || (select string_agg(left(x->>'nome', 8) || '=' || (x->>'papel'), ', ') from jsonb_array_elements(public.crm_vendedores()) x);
  execute 'reset role';
  -- lista vazia → só dev
  update crm.config set gestores = '{}';
  v := v || format(E'\nlista vazia: jonathan=%s arthur=%s joao_pedro_dev=%s marcos=%s',
    crm.eh_gestor('bd5361bc-3c3f-4f85-8b5a-f21433d040e3'), crm.eh_gestor('3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'),
    crm.eh_gestor('843d43db-73b3-44a9-b449-1731e362dbc3'), crm.eh_gestor('9d347183-5395-434e-9e96-2a65dde1a3cd'));
  -- gestores entre TODOS os perfis ativos, com a lista da migration
  update crm.config set gestores = array['bd5361bc-3c3f-4f85-8b5a-f21433d040e3', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975']::uuid[];
  v := v || format(E'\nperfis gestores (todos): %s', (select count(*) from public.perfis p where crm.eh_gestor(p.id)));
  v := v || format(E'\ncorpos: vendedores=%s ficha=%s estrategia=%s',
    pg_get_functiondef('public.crm_vendedores()'::regprocedure) ~ 'crm.eh_gestor\(p.id\)',
    pg_get_functiondef('public.crm_salvar_ficha(jsonb,boolean)'::regprocedure) ~ 'crm.eh_gestor\(p.id\)',
    pg_get_functiondef('public.crm_estrategia_salvar(jsonb)'::regprocedure) ~ 'crm.eh_gestor\(p2.id\)');
  v := v || format(E'\nacl eh_gestor(uuid)=%s', (select proacl::text from pg_proc where oid = 'crm.eh_gestor(uuid)'::regprocedure));
  raise exception 'ENSAIO_OK %', v;
end $e$;

rollback;
