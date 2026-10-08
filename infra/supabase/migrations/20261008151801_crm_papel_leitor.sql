-- 20261008151801 (escrita como 20261008lt) — APLICADA em 08/10/2026 — CRM: papel LEITOR (decisão do Arthur, 08/10/2026). Admin ou dev do sistema que não é gestor nem vendedor
-- do Comercial vê o CRM inteiro SÓ PARA LEITURA (antes: "Sem acesso ao Comercial.", desde a 20261008150041).
--
-- 1. crm.config.leitor_ligado boolean not null default true — kill-switch (false = ninguém é leitor, volta ao 42501).
-- 2. crm.eh_leitor(uuid) = perfil ativo, e-mail da equipe, cargo dev/admin, NÃO gestor (crm.config.gestores) e NÃO vendedor
--    ativo. crm.eh_leitor() = crm.eh_leitor(auth.uid()).
-- 3. crm.pode_escrever() = não é leitor. HELPER ÚNICO DA RECUSA: toda RPC de escrita chama crm.guarda_escrita() (que agora
--    chama crm.pode_escrever() e devolve {ok:false, msg:'Acesso só de leitura.'}) ou, se não usa a guarda, chama
--    crm.pode_escrever() direto. RPC DE ESCRITA NOVA PRECISA CHAMAR UM DOS DOIS.
-- 4. crm.eh_gestor() (sem argumento = VISÃO do usuário logado) = gestor OU leitor: o leitor lê tudo o que o gestor lê
--    (policies, crm_*, crm_log, Estratégias) sem mexer em ≈70 leitores. crm.eh_gestor(uuid) NÃO muda: quem recebe aviso,
--    papel em crm_vendedores, MCP (crm.mcp_papel) e distribuição continuam só com gestor de verdade.
-- 5. Escrita fora da guarda: pode_escrever_pessoa, midia_pode_subir/apagar (Storage) e 7 RPCs (catálogo ×3,
--    estrategia_salvar, hotmart_reprocessar, mcp_criar_token, mcp_revogar_token) ganham crm.pode_escrever().
-- 6. Dado pessoal: crm.contatos_itens e crm_contatos tratam o leitor como "não completo" → e-mail e telefone mascarados
--    (pessoas.mascara_email / pessoas.mascara_fim, o mesmo do vendedor com contato alheio).
-- 7. crm_sessao devolve papel 'leitor'; crm_estrategia_acesso ganha 'leitor' e 'gestor'/'solicitar' viram false para ele;
--    crm_vendedores não lista o leitor (o "eu" entra só se for gestor de verdade).
--
-- Guarda: md5 do corpo VIVO de cada função tocada; coluna ainda não existe; helpers novos ainda não existem.
-- Reversão: no .explain.md (kill-switch primeiro).

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
