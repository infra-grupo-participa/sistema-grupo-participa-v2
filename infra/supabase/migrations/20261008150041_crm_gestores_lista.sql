-- 20261008150041 (escrita como 20261008gl) — APLICADA em 08/10/2026 — CRM: gestor do Comercial passa a ser uma LISTA explícita em crm.config.gestores (decisão do Arthur, opção A,
-- 08/10/2026: gestor = o gestor comercial e o supervisor dele). Vale para o CRM inteiro e para Estratégias.
--
-- 1. crm.config.gestores uuid[] not null default '{}' — ids de public.perfis. Só uuid aqui (sem e-mail nem nome).
--    Ninguém escreve crm.config pela API (authenticated só tem SELECT e nenhuma RPC faz update nela): a lista muda por
--    migration/SQL.
-- 2. crm.eh_gestor(uuid) = perfil ativo, e-mail da equipe e id na lista. Lista vazia → só cargo dev (ninguém se tranca fora).
--    crm.eh_gestor()            = crm.eh_gestor(auth.uid())   (usado por todas as RPCs crm_*, policies, crm_log, distribuição)
--    crm.estrategia_eh_gestor() = crm.eh_gestor()             (Estratégias: mesma regra)
-- 3. Quem calculava gestor por CARGO passa a usar o helper:
--    crm.mcp_papel (papel do token do MCP), crm_vendedores (papel na lista de vendedores),
--    crm_salvar_ficha (quem recebe "ficha para aprovar"), crm_estrategia_salvar (quem recebe "nova solicitação").
-- crm.eh_responsavel_comercial() fica viva e sem chamador (reversão).
--
-- Guarda: md5 do corpo VIVO de cada função trocada; coluna ainda não existe; os 2 perfis existem, ativos e da equipe.
-- Reversão: no .explain.md.

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

notify pgrst, 'reload schema';
