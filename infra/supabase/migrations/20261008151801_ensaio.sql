-- 20261008151801 (20261008lt) — ENSAIO (produção). Roda a migration inteira e prova com JWT real (set local role authenticated).
-- Termina SEMPRE em erro proposital 'ENSAIO_OK …' (= ROLLBACK de tudo); o resultado vem na mensagem.
-- Esperado: leitores = admin/dev ativos fora do Comercial (nenhum com eh_gestor(uuid) nem distribuição);
-- gestores (crm.config.gestores) = gestor; vendedores ativos = vendedor; operador de outro setor = 42501;
-- leitor: lê funis/negócios/conversas/log/Estratégias, TODAS as RPCs de escrita → 'Acesso só de leitura.',
-- e-mail/telefone mascarados, não sobe mídia, não aparece em crm_vendedores.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare r record;
begin
  for r in select * from (values
    ('crm.eh_gestor()', '718d8575ed47c38281abb9d1ec07f459'),
    ('crm.guarda_escrita()', 'c68205fccaa22f255827737091e6cf29'),
    ('crm.pode_escrever_pessoa(uuid)', '66e983c861f8be7c76093a880b2bbd7e'),
    ('crm.midia_pode_subir(text)', '9011d09846b6285305ce4c55fcc3e736'),
    ('crm.midia_pode_apagar(text)', 'c704d9cbdcb1a20d8b9a7ad0ba257218'),
    ('crm.contatos_itens(uuid[],boolean)', '1e39fd8e995337a906fe80ecbff2c442'),
    ('public.crm_contatos(text,integer,integer)', '8b3de3f94f1dbe6b9150fdd3bded4923'),
    ('public.crm_sessao()', '5e49da3f8c4353571635b5787320cb8e'),
    ('public.crm_vendedores()', 'f2ab767d1aa00f8eef19996ed05287ec'),
    ('public.crm_estrategia_acesso()', 'a08b656222260b17dbd1735548936801'),
    ('public.crm_catalogo_lista_salvar(text,text)', '5a7c8e22ff23010ea234041310f2d4d0'),
    ('public.crm_catalogo_reaplicar(boolean)', 'c8ffc3c30c2740a56e5f21ce952d441c'),
    ('public.crm_catalogo_regra_salvar(jsonb)', '2f68bd7474c27a6534cdfafe0c91f468'),
    ('public.crm_estrategia_salvar(jsonb)', 'da91eee3c3816ce8b9a6e5d4f76b01aa'),
    ('public.crm_hotmart_reprocessar(text)', '823cdac541509877dde59b5a811b28ea'),
    ('public.crm_mcp_criar_token(text,text[],integer)', 'fd0c3638927e8bdd2f32122fa136f20c'),
    ('public.crm_mcp_revogar_token(uuid)', '934a8d539e594edacb9959fce1530063')
  ) v(fn, esperado) loop
    if md5(pg_get_functiondef(r.fn::regprocedure)) <> r.esperado then
      raise exception 'premissa: % mudou (md5 vivo %, esperado %)', r.fn, md5(pg_get_functiondef(r.fn::regprocedure)), r.esperado;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config' and column_name = 'leitor_ligado') then
    raise exception 'premissa: crm.config.leitor_ligado já existe';
  end if;
  if to_regprocedure('crm.eh_leitor(uuid)') is not null or to_regprocedure('crm.eh_leitor()') is not null
     or to_regprocedure('crm.pode_escrever()') is not null then
    raise exception 'premissa: helpers do leitor já existem';
  end if;
  if (select count(*) from crm.config) <> 1 then raise exception 'premissa: crm.config precisa ter 1 linha'; end if;
end $g$;

-- ── 1. kill-switch ──
alter table crm.config add column leitor_ligado boolean not null default true;
comment on column crm.config.leitor_ligado is
  'Papel leitor do Comercial (admin/dev fora do Comercial vê o CRM só para leitura). false = ninguém é leitor. Regra em crm.eh_leitor(uuid).';

-- ── 2. helpers ──
create function crm.eh_leitor(p_uid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008lt: leitor = admin ou dev do sistema (perfil ativo, e-mail da equipe) que não é gestor (crm.config.gestores)
  -- nem vendedor ativo. Vê o que o gestor vê, com e-mail/telefone mascarados, e não escreve nada (crm.pode_escrever()).
  select coalesce((
    select coalesce(c.leitor_ligado, false) and p.cargo in ('dev', 'admin')
           and not coalesce(crm.eh_gestor(p.id), false) and not coalesce(crm.vendedor_ativo(p.id), false)
      from public.perfis p
      left join crm.config c on true
     where p.id = p_uid and p.status = 'ativo' and lower(btrim(coalesce(p.email, ''))) like '%@advmais.com'
     limit 1), false);
$$;
revoke execute on function crm.eh_leitor(uuid) from public, anon, authenticated;
grant execute on function crm.eh_leitor(uuid) to service_role;

create function crm.eh_leitor()
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008lt: o usuário logado é leitor do Comercial (ver crm.eh_leitor(uuid)).
  select crm.eh_leitor((select auth.uid()));
$$;
revoke execute on function crm.eh_leitor() from public, anon;
grant execute on function crm.eh_leitor() to authenticated, service_role;

create function crm.pode_escrever()
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008lt: HELPER ÚNICO da recusa de escrita do leitor. Toda RPC de escrita chama crm.guarda_escrita() (que usa esta
  -- função) ou esta função direto, antes de escrever. Sem JWT (cron, service_role): true — a regra é só do leitor.
  select not coalesce(crm.eh_leitor(), false);
$$;
revoke execute on function crm.pode_escrever() from public, anon;
grant execute on function crm.pode_escrever() to authenticated, service_role;

-- ── 3. visão de gestor inclui o leitor ──
create or replace function crm.eh_gestor()
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008gl: a lista de crm.config.gestores (ver crm.eh_gestor(uuid)).
  -- 20261008lt: VISÃO de gestor = gestor OU leitor. O leitor lê tudo; a escrita dele para em crm.guarda_escrita()/crm.pode_escrever().
  -- Para "é gestor de verdade" (aviso, papel, distribuição, MCP) use crm.eh_gestor(uuid).
  select coalesce(crm.eh_gestor((select auth.uid())), false) or coalesce(crm.eh_leitor((select auth.uid())), false);
$$;

-- ── 4. a guarda central de escrita ──
create or replace function crm.guarda_escrita()
returns jsonb language plpgsql security definer set search_path = '' as $function$
begin
  perform set_config('crm.resumo', '', true);
  -- 20261008lt: leitor não escreve nada. RPC de escrita nova: chamar esta guarda (ou crm.pode_escrever()) antes de escrever.
  if not crm.pode_escrever() then
    return crm.res(false, 'Acesso só de leitura.');
  end if;
  if not coalesce((select c.escrita_ligada from crm.config c), false) then
    return crm.res(false, 'CRM em manutenção: escrita desligada.');
  end if;
  if not coalesce(crm.eh_comercial(), false) then
    return crm.res(false, 'Sem acesso ao Comercial.');
  end if;
  return null;
end
$function$;

-- ── 5. sessão e Estratégias ──
create or replace function public.crm_sessao()
returns jsonb language plpgsql stable set search_path = '' as $function$
declare v_l boolean := coalesce(crm.eh_leitor(), false); v_g boolean := coalesce(crm.eh_gestor(), false);
        v_v boolean := coalesce(crm.eh_vendedor(), false);
begin
  if not (v_g or v_v) then raise exception 'Sem acesso ao Comercial.' using errcode = '42501'; end if;
  -- 20261008lt: leitor = admin/dev fora do Comercial, só leitura
  return jsonb_build_object('vendedorId', auth.uid(),
                            'papel', case when v_l then 'leitor' when v_g then 'gestor' else 'vendedor' end);
end
$function$;

create or replace function public.crm_estrategia_acesso()
returns jsonb language sql stable security definer set search_path = '' as $function$
  -- 20261008lt: o leitor vê os pedidos do time ('leitor'), mas não pede nem decide ('solicitar'/'gestor' = false).
  select jsonb_build_object('solicitar', coalesce(crm.pode_solicitar_estrategia(), false) and crm.pode_escrever(),
                            'gestor', coalesce(crm.estrategia_eh_gestor(), false) and crm.pode_escrever(),
                            'leitor', coalesce(crm.eh_leitor(), false));
$function$;

-- ── 6. trocas cirúrgicas no corpo VIVO (já conferido por md5); aborta se o trecho não estiver lá ──
do $t$
declare r record; v_def text; v_novo text;
begin
  for r in select * from (values
    ('crm.pode_escrever_pessoa(uuid)',
     E'  if coalesce(crm.eh_gestor(), false) then return true; end if;',
     E'  if not crm.pode_escrever() then return false; end if;  -- 20261008lt: leitor não escreve\n  if coalesce(crm.eh_gestor(), false) then return true; end if;'),
    ('crm.midia_pode_subir(text)',
     E'     and (coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false));',
     E'     and (coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false))\n     and crm.pode_escrever();  -- 20261008lt: leitor não sobe arquivo'),
    ('crm.midia_pode_apagar(text)',
     E'  if not (coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false)) then return false; end if;',
     E'  if not (coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false)) then return false; end if;\n  if not crm.pode_escrever() then return false; end if;  -- 20261008lt'),
    ('crm.contatos_itens(uuid[],boolean)',
     E'  v_gestor boolean := coalesce(crm.eh_gestor(), false);\n',
     E'  v_gestor boolean := coalesce(crm.eh_gestor(), false);\n  v_leitor boolean := coalesce(crm.eh_leitor(), false);  -- 20261008lt: leitor vê tudo, e-mail/telefone mascarados\n'),
    ('crm.contatos_itens(uuid[],boolean)',
     E'(select coalesce(v_gestor or pc.dono_id = v_eu',
     E'(select coalesce((v_gestor and not v_leitor) or pc.dono_id = v_eu'),
    ('public.crm_contatos(text,integer,integer)',
     E'  v_gestor boolean := coalesce(crm.eh_gestor(), false);\n',
     E'  v_gestor boolean := coalesce(crm.eh_gestor(), false);\n  v_leitor boolean := coalesce(crm.eh_leitor(), false);  -- 20261008lt: leitor vê tudo, e-mail/telefone mascarados\n'),
    ('public.crm_contatos(text,integer,integer)',
     E'(select pc0.*, (v_gestor or pc0.dono_id = v_eu',
     E'(select pc0.*, ((v_gestor and not v_leitor) or pc0.dono_id = v_eu'),
    ('public.crm_vendedores()',
     E'or (p.id = v_eu and coalesce(crm.eh_gestor(), false))) x;',
     E'or (p.id = v_eu and coalesce(crm.eh_gestor(v_eu), false))) x;  -- 20261008lt: só gestor de verdade; leitor fora da lista')
  ) v(fn, antes, depois) loop
    v_def := pg_get_functiondef(r.fn::regprocedure);
    if (length(v_def) - length(replace(v_def, r.antes, ''))) / length(r.antes) <> 1 then
      raise exception 'premissa: trecho não encontrado (ou repetido) em %: %', r.fn, left(r.antes, 60);
    end if;
    v_novo := replace(v_def, r.antes, r.depois);
    execute v_novo;
  end loop;
end $t$;

-- ── 7. RPCs de escrita que não passam por crm.guarda_escrita(): recusa logo depois do begin ──
do $w$
declare r record; v_def text;
begin
  for r in select unnest(array[
    'public.crm_catalogo_lista_salvar(text,text)', 'public.crm_catalogo_reaplicar(boolean)',
    'public.crm_catalogo_regra_salvar(jsonb)', 'public.crm_estrategia_salvar(jsonb)', 'public.crm_hotmart_reprocessar(text)',
    'public.crm_mcp_criar_token(text,text[],integer)', 'public.crm_mcp_revogar_token(uuid)']) fn loop
    v_def := pg_get_functiondef(r.fn::regprocedure);
    if (select count(*) from regexp_matches(v_def, E'\nbegin\n', 'g')) <> 1 then
      raise exception 'premissa: % não tem exatamente um begin de topo', r.fn;
    end if;
    execute regexp_replace(v_def, E'\nbegin\n',
      E'\nbegin\n  if not crm.pode_escrever() then return crm.res(false, ''Acesso só de leitura.''); end if;  -- 20261008lt\n');
  end loop;
end $w$;

notify pgrst, 'reload schema';

do $e$
declare
  r record; f record; v text := ''; v_papel text; v_t0 timestamptz; v_ms numeric; v_res jsonb; v_msg text;
  v_leitor uuid; v_oper uuid; v_ok int := 0; v_tot int := 0; v_fora text := ''; v_x jsonb;
  v_tel int; v_tel_masc int; v_mail int; v_mail_masc int;
begin
  select p.id into v_leitor from public.perfis p where crm.eh_leitor(p.id) and p.cargo = 'admin' order by p.id limit 1;
  select p.id into v_oper from public.perfis p
   where p.status = 'ativo' and p.cargo = 'operador' and lower(btrim(coalesce(p.email, ''))) like '%@advmais.com'
     and not crm.vendedor_ativo(p.id) and not ('comercial' = any(coalesce(p.areas, '{}'))) order by p.id limit 1;
  v := format('leitores: total=%s admin=%s dev=%s masters=%s (masters fora: %s)',
    (select count(*) from public.perfis p where crm.eh_leitor(p.id)),
    (select count(*) from public.perfis p where crm.eh_leitor(p.id) and p.cargo = 'admin'),
    (select count(*) from public.perfis p where crm.eh_leitor(p.id) and p.cargo = 'dev'),
    (select count(*) from acesso.master m where crm.eh_leitor(m.perfil_id)),
    (select string_agg(pf.cargo || case when crm.eh_gestor(pf.id) then '/gestor' else '' end, ',')
       from acesso.master m join public.perfis pf on pf.id = m.perfil_id where not crm.eh_leitor(m.perfil_id)));
  v := v || format(E'\nleitor com eh_gestor(uuid)=%s mcp_papel=%s distribuicao=%s vendedor_row=%s',
    (select count(*) from public.perfis p where crm.eh_leitor(p.id) and crm.eh_gestor(p.id)),
    (select count(*) from public.perfis p where crm.eh_leitor(p.id) and crm.mcp_papel(p.id) is not null),
    (select count(*) from crm.distribuicao d where crm.eh_leitor(d.vendedor_id)),
    (select count(*) from crm.vendedor x where crm.eh_leitor(x.perfil_id)));

  for r in select 'gestor' k, g id from crm.config c, unnest(c.gestores) g
           union all select 'vendedor', p.id from public.perfis p where crm.vendedor_ativo(p.id) and not crm.eh_gestor(p.id)
           union all select 'leitor', v_leitor
           union all select 'operador', v_oper loop
    perform set_config('request.jwt.claims', json_build_object('sub', r.id, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', r.id::text, true);
    execute 'set local role authenticated';
    v_t0 := clock_timestamp();
    begin v_papel := public.crm_sessao() ->> 'papel'; exception when others then v_papel := 'ERRO ' || sqlstate || ' ' || sqlerrm; end;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 2);
    v := v || format(E'\n%s: sessao=%s (%s ms) eh_gestor()=%s pode_escrever=%s', r.k, v_papel, v_ms, crm.eh_gestor(), crm.pode_escrever());
    begin
      v := v || format(' funis=%s negocios=%s conversas=%s log=%s estrategias=%s estr_acesso=%s',
        jsonb_array_length(coalesce(public.crm_funis(false) -> 'itens', public.crm_funis(false))),
        length(public.crm_negocios(null, null, null, 200, 0)::text) > 20,
        length(public.crm_conversas(50)::text) > 20,
        (select count(*) from crm.log),
        length(public.crm_estrategias()::text) > 5,
        public.crm_estrategia_acesso()::text);
    exception when others then v := v || ' leitura=ERRO ' || sqlstate || ' ' || left(sqlerrm, 60); end;
    begin v_msg := public.crm_adicionar_nota(null, null, 'ensaio') ->> 'msg'; exception when others then v_msg := 'ERRO ' || sqlstate; end;
    v := v || format(' nota=%s', v_msg);
    execute 'reset role';
  end loop;

  -- leitor: TODAS as RPCs de escrita (guarda_escrita ou pode_escrever no corpo), com argumentos nulos
  perform set_config('request.jwt.claims', json_build_object('sub', v_leitor, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_leitor::text, true);
  execute 'set local role authenticated';
  for f in select p.proname, (select string_agg(format('null::%s', t::regtype), ', ' order by o) from unnest(p.proargtypes) with ordinality u(t, o)) args
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'crm\_%' and has_function_privilege('authenticated', p.oid, 'execute')
              and pg_get_functiondef(p.oid) ~ '(crm\.guarda_escrita\(\)|crm\.pode_escrever\(\))'
              and p.proname <> 'crm_estrategia_acesso'
            order by 1 loop
    v_tot := v_tot + 1;
    begin
      execute format('select public.%I(%s)', f.proname, coalesce(f.args, '')) into v_res;
      v_msg := v_res ->> 'msg';
    exception when others then v_msg := 'ERRO ' || sqlstate || ' ' || sqlerrm; end;
    if v_msg = 'Acesso só de leitura.' then v_ok := v_ok + 1; else v_fora := v_fora || f.proname || '=' || coalesce(v_msg, '?') || '; '; end if;
  end loop;
  v := v || format(E'\nleitor escrita recusada: %s de %s %s', v_ok, v_tot, v_fora);
  -- MCP OAuth (gate por crm.mcp_papel, sem guarda): o leitor também é recusado
  begin v_msg := public.crm_mcp_oauth_autorizar(null, null, null, null) ->> 'msg'; exception when others then v_msg := 'ERRO ' || sqlstate; end;
  v := v || format(E'\nleitor mcp_oauth_autorizar=%s', v_msg);
  v := v || format(E'\nleitor midia_pode_subir=%s midia_pode_apagar=%s',
    crm.midia_pode_subir('envio/' || v_leitor || '/00000000-0000-0000-0000-000000000000.jpg'),
    crm.midia_pode_apagar('envio/' || v_leitor || '/00000000-0000-0000-0000-000000000000.jpg'));
  -- dado pessoal mascarado
  v_x := public.crm_contatos_pagina(null, null, null, null, null, false, false, 'criado', 'desc', 50, 0, null, null) -> 'itens';
  select count(*) filter (where e->>'telefone' is not null), count(*) filter (where e->>'telefone' like '%*%'),
         count(*) filter (where e->>'email' is not null), count(*) filter (where e->>'email' like '%*%')
    into v_tel, v_tel_masc, v_mail, v_mail_masc from jsonb_array_elements(v_x) e;
  v := v || format(E'\nleitor contatos_pagina(50): itens=%s tel=%s mascarados=%s email=%s mascarados=%s',
    jsonb_array_length(v_x), v_tel, v_tel_masc, v_mail, v_mail_masc);
  v_x := public.crm_contatos(null, 50, 0) -> 'itens';
  select count(*) filter (where e->>'telefone' is not null), count(*) filter (where e->>'telefone' like '%*%'),
         count(*) filter (where e->>'email' is not null), count(*) filter (where e->>'email' like '%*%')
    into v_tel, v_tel_masc, v_mail, v_mail_masc from jsonb_array_elements(v_x) e;
  v := v || format(E'\nleitor crm_contatos(50): itens=%s tel=%s mascarados=%s email=%s mascarados=%s',
    jsonb_array_length(v_x), v_tel, v_tel_masc, v_mail, v_mail_masc);
  v := v || format(E'\nleitor crm_vendedores: %s (inclui o leitor=%s)',
    (select string_agg(x->>'papel', ',' order by x->>'papel') from jsonb_array_elements(public.crm_vendedores()) x),
    exists (select 1 from jsonb_array_elements(public.crm_vendedores()) x where x->>'id' = v_leitor::text));
  execute 'reset role';
  -- pode_escrever_pessoa só roda como postgres (o JWT do leitor continua nos claims)
  v := v || format(E'\nleitor pode_escrever_pessoa=%s', (select crm.pode_escrever_pessoa(pc.pessoa_id) from crm.pessoa_comercial pc limit 1));

  -- gestor: o mesmo contato vem completo
  perform set_config('request.jwt.claims', json_build_object('sub', 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3', true);
  execute 'set local role authenticated';
  v_x := public.crm_contatos_pagina(null, null, null, null, null, false, false, 'criado', 'desc', 50, 0, null, null) -> 'itens';
  select count(*) filter (where e->>'telefone' is not null), count(*) filter (where e->>'telefone' like '%*%'),
         count(*) filter (where e->>'email' is not null), count(*) filter (where e->>'email' like '%*%')
    into v_tel, v_tel_masc, v_mail, v_mail_masc from jsonb_array_elements(v_x) e;
  v := v || format(E'\ngestor contatos_pagina(50): itens=%s tel=%s mascarados=%s email=%s mascarados=%s',
    jsonb_array_length(v_x), v_tel, v_tel_masc, v_mail, v_mail_masc);
  v := v || format(E'\ngestor crm_vendedores: %s', (select string_agg(x->>'papel', ',' order by x->>'papel') from jsonb_array_elements(public.crm_vendedores()) x));
  execute 'reset role';

  -- kill-switch
  update crm.config set leitor_ligado = false;
  v := v || format(E'\nkill-switch: leitores=%s', (select count(*) from public.perfis p where crm.eh_leitor(p.id)));
  v := v || format(E'\nacl eh_leitor(uuid)=%s eh_leitor()=%s pode_escrever()=%s',
    (select proacl::text from pg_proc where oid = 'crm.eh_leitor(uuid)'::regprocedure),
    (select proacl::text from pg_proc where oid = 'crm.eh_leitor()'::regprocedure),
    (select proacl::text from pg_proc where oid = 'crm.pode_escrever()'::regprocedure));
  raise exception 'ENSAIO_OK %', v;
end $e$;

rollback;
