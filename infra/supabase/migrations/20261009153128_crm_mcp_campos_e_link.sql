-- MCP do Comercial: campos do negócio pelo Claude (inclusive por voz), sugestão a partir da conversa e "abrir link".
-- Pedido do Marcos Paulo (09/10/2026), ok do Arthur. Ver docs/projetos/comercial/mcp.md e
-- 20261009153128.explain.md.
--
--   public.crm_mcp_negocio_campos(uuid)            leitura: campos do negócio (rótulo, opções, valor) + obrigatórios da
--                                                  próxima etapa. SECURITY INVOKER: a RLS de crm.negocio decide.
--   public.crm_mcp_preencher_campos(uuid, jsonb)   escrita: valida contra crm.campo_def / crm.linha ativa e grava pela
--                                                  MESMA RPC da tela (public.crm_salvar_campos: guarda_escrita, dono ou
--                                                  gestor, leitor recusado). Devolve o que mudou. INVOKER.
--   public.crm_mcp_lead(uuid, uuid, int)           leitura agregada (contato, negócios, próximas atividades, notas,
--                                                  mensagens) de um contato OU de um negócio. Sem acesso → "Você não tem
--                                                  acesso a este lead." INVOKER; reaproveita as RPCs de leitura da tela.
--   public.crm_mcp_rpc                             + as 3 na lista fechada (negocio_campos e lead em 'ler'; preencher em
--                                                  'operar'). Resto do corpo idêntico ao vivo (md5 789d15be…).
--
-- Funções novas: só authenticated/service_role executam (revoke de PUBLIC/anon na mesma chamada).

-- ─── Guarda de premissa ─────────────────────────────────────────────────────────────────────────────────────────────
do $$
begin
  if md5((select p.prosrc from pg_catalog.pg_proc p where p.oid = 'public.crm_mcp_rpc(uuid,text,jsonb)'::regprocedure))
     <> '789d15be63d3f9bd1b14803adeb35aa9' then
    raise exception 'Premissa: public.crm_mcp_rpc mudou desde a leitura (esperado md5 789d15be…).';
  end if;
  if md5((select p.prosrc from pg_catalog.pg_proc p where p.oid = 'public.crm_salvar_campos(uuid,jsonb)'::regprocedure))
     <> 'a8087064265d29c6c751af8a408015c5' then
    raise exception 'Premissa: public.crm_salvar_campos mudou desde a leitura (esperado md5 a8087064…).';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_mcp_negocio_campos', 'crm_mcp_preencher_campos', 'crm_mcp_lead')) then
    raise exception 'Premissa: funções do MCP de campos/link já existem.';
  end if;
end $$;

-- ─── Leitura: campos do negócio ─────────────────────────────────────────────────────────────────────────────────────
create function public.crm_mcp_negocio_campos(p_negocio uuid)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_eu uuid := auth.uid();
  n record; px record; v_linhas jsonb; v_campos jsonb; v_obrig jsonb; v_falta jsonb; v_pode boolean;
begin
  perform crm.exige_comercial();
  -- RLS de crm.negocio (negocio_ler): gestor/leitor vê todos; vendedor os seus e os sem dono.
  select x.id, x.pessoa_id, x.funil_id, x.etapa_id, x.status, x.dono_id, coalesce(x.campos, '{}'::jsonb) campos,
         e.nome etapa_nome, e.ordem etapa_ordem, f.nome funil_nome
    into n
    from crm.negocio x
    join crm.etapa_funil e on e.id = x.etapa_id
    join crm.funil f on f.id = x.funil_id and f.ativo
   where x.id = p_negocio;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Negócio não encontrado ou sem acesso.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('valor', l.chave, 'rotulo', l.nome) order by l.ordem, l.chave), '[]'::jsonb)
    into v_linhas from crm.linha l where l.ativo;

  select coalesce(jsonb_agg(jsonb_build_object(
           'chave', d.chave, 'rotulo', d.rotulo, 'tipo', d.tipo,
           'opcoes', case d.tipo when 'opcao' then to_jsonb(d.opcoes) when 'linha' then v_linhas end,
           'valor', n.campos -> d.chave) order by d.ordem, d.chave), '[]'::jsonb)
    into v_campos from crm.campo_def d where d.ativo;

  -- Próxima etapa (mesma ordem do funil, não arquivada). Obrigatórios = acumulados até ela (regra de crm.campos_faltando).
  select e.id, e.nome, e.papel, e.ordem into px
    from crm.etapa_funil e
   where e.funil_id = n.funil_id and e.arquivada_em is null and e.ordem > n.etapa_ordem
   order by e.ordem, e.id limit 1;
  if px.id is not null then
    with ex as (
      select u.c, min(e.ordem::int * 1000 + u.o) k
        from crm.etapa_funil e
       cross join lateral unnest(e.campos_obrigatorios) with ordinality u(c, o)
       where e.funil_id = n.funil_id and e.arquivada_em is null and e.ordem <= px.ordem
       group by u.c)
    select coalesce(jsonb_agg(ex.c order by ex.k), '[]'::jsonb),
           coalesce(jsonb_agg(ex.c order by ex.k) filter (where nullif(btrim(coalesce(n.campos ->> ex.c, '')), '') is null), '[]'::jsonb)
      into v_obrig, v_falta
      from ex;
  end if;

  v_pode := coalesce(crm.pode_escrever(), false) and (coalesce(crm.eh_gestor(), false) or n.dono_id = v_eu);

  return jsonb_build_object(
    'ok', true,
    'negocio', jsonb_build_object('id', n.id, 'contatoId', n.pessoa_id, 'funilId', n.funil_id, 'funilNome', n.funil_nome,
                                  'etapaId', n.etapa_id, 'etapaNome', n.etapa_nome, 'status', n.status, 'donoId', n.dono_id),
    'podeEditar', v_pode,
    'campos', v_campos,
    'proximaEtapa', case when px.id is null then null
                         else jsonb_build_object('id', px.id, 'nome', px.nome, 'papel', px.papel,
                                                 'obrigatorios', v_obrig, 'faltando', v_falta) end);
end
$function$;
revoke execute on function public.crm_mcp_negocio_campos(uuid) from public, anon;
grant execute on function public.crm_mcp_negocio_campos(uuid) to authenticated, service_role;

-- ─── Escrita: preencher campos (valida e grava pela RPC da tela) ────────────────────────────────────────────────────
create function public.crm_mcp_preencher_campos(p_negocio uuid, p_campos jsonb)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  k text; val jsonb; d record; v_txt text;
  v_limpo jsonb := '{}'::jsonb; v_antes jsonb; v_r jsonb; v_depois jsonb; v_mud jsonb;
begin
  perform crm.exige_comercial();
  if jsonb_typeof(p_campos) is distinct from 'object' or p_campos = '{}'::jsonb then
    return jsonb_build_object('ok', false, 'msg', 'Informe ao menos um campo.');
  end if;
  if (select count(*) from jsonb_object_keys(p_campos)) > 20 then
    return jsonb_build_object('ok', false, 'msg', 'Campos demais.');
  end if;

  for k, val in select e.key, e.value from jsonb_each(p_campos) e loop
    select x.chave, x.rotulo, x.tipo, x.opcoes into d from crm.campo_def x where x.chave = k and x.ativo;
    if not found then
      return jsonb_build_object('ok', false, 'msg', format('Campo desconhecido: %s. Veja comercial_campos_negocio.', left(k, 60)));
    end if;
    if jsonb_typeof(val) = 'null' or (jsonb_typeof(val) = 'string' and btrim(val #>> '{}') = '') then
      v_limpo := v_limpo || jsonb_build_object(k, null);   -- limpar (crm_salvar_campos tira a chave)
      continue;
    end if;
    if jsonb_typeof(val) <> 'string' then
      return jsonb_build_object('ok', false, 'msg', format('%s precisa ser texto.', d.rotulo));
    end if;
    v_txt := btrim(val #>> '{}');
    if d.tipo = 'opcao' and not (v_txt = any(coalesce(d.opcoes, '{}'::text[]))) then
      return jsonb_build_object('ok', false, 'msg',
        format('%s: valor inválido "%s". Use: %s.', d.rotulo, left(v_txt, 60), array_to_string(d.opcoes, ', ')));
    end if;
    if d.tipo = 'linha' and not exists (select 1 from crm.linha l where l.chave = v_txt and l.ativo) then
      return jsonb_build_object('ok', false, 'msg',
        format('%s: produto "%s" não existe. Use: %s.', d.rotulo, left(v_txt, 60),
               (select string_agg(l.chave || ' (' || l.nome || ')', ', ' order by l.ordem) from crm.linha l where l.ativo)));
    end if;
    if length(v_txt) > 200 then
      return jsonb_build_object('ok', false, 'msg', format('%s: até 200 caracteres.', d.rotulo));
    end if;
    v_limpo := v_limpo || jsonb_build_object(k, v_txt);
  end loop;

  v_antes := public.crm_mcp_negocio_campos(p_negocio);
  if not coalesce((v_antes ->> 'ok')::boolean, false) then return v_antes; end if;

  -- A MESMA RPC da tela: guarda_escrita (leitor, escrita_ligada, Comercial), dono ou gestor, log com canal mcp.
  v_r := public.crm_salvar_campos(p_negocio, v_limpo);
  if not coalesce((v_r ->> 'ok')::boolean, false) then return v_r; end if;

  v_depois := public.crm_mcp_negocio_campos(p_negocio);
  select coalesce(jsonb_agg(jsonb_build_object('chave', c.key, 'rotulo', a.rotulo, 'de', a.valor, 'para', b.valor)
                            order by a.o), '[]'::jsonb)
    into v_mud
    from jsonb_each(v_limpo) c
    join lateral (select x ->> 'rotulo' rotulo, x -> 'valor' valor, o
                    from jsonb_array_elements(v_antes -> 'campos') with ordinality t(x, o) where x ->> 'chave' = c.key) a on true
    join lateral (select x -> 'valor' valor
                    from jsonb_array_elements(v_depois -> 'campos') x where x ->> 'chave' = c.key) b on true
   where a.valor is distinct from b.valor;

  return jsonb_build_object('ok', true, 'mudou', v_mud, 'negocio', v_depois -> 'negocio',
                            'campos', v_depois -> 'campos', 'proximaEtapa', v_depois -> 'proximaEtapa');
end
$function$;
revoke execute on function public.crm_mcp_preencher_campos(uuid, jsonb) from public, anon;
grant execute on function public.crm_mcp_preencher_campos(uuid, jsonb) to authenticated, service_role;

-- ─── Leitura agregada: lead por contato ou negócio (para "resume este link" e sugestão de campos) ───────────────────
create function public.crm_mcp_lead(p_contato uuid default null, p_negocio uuid default null, p_mensagens integer default 30)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_lim int := least(greatest(coalesce(p_mensagens, 30), 1), 200);
  v_p uuid; v_contato jsonb; v_neg jsonb; v_ats jsonb; v_notas jsonb; v_msgs jsonb;
  c_sem constant text := 'Você não tem acesso a este lead.';
begin
  perform crm.exige_comercial();
  if (p_contato is null) = (p_negocio is null) then
    raise exception 'Informe contato ou negócio (um dos dois).' using errcode = '22023';
  end if;
  if p_negocio is not null then
    select x.pessoa_id into v_p from crm.negocio x where x.id = p_negocio;   -- RLS de crm.negocio
  else
    v_p := p_contato;
  end if;
  if v_p is null or not coalesce(crm.pode_ver_pessoa(v_p), false) then
    return jsonb_build_object('ok', false, 'msg', c_sem);
  end if;
  v_contato := public.crm_contatos_por_ids(array[v_p]) -> 'itens' -> 0;
  if v_contato is null then
    return jsonb_build_object('ok', false, 'msg', c_sem);
  end if;

  v_neg := public.crm_negocios(null, null, v_p, 50, 0);
  select coalesce(jsonb_agg(a.x order by a.o), '[]'::jsonb) into v_ats
    from jsonb_array_elements(public.crm_atividades(null, v_p, 200, 0)) with ordinality a(x, o)
   where a.x ->> 'concluidaEm' is null;
  -- notas: RLS de crm.nota (nota_ler); negócio oculto fica de fora, como na jornada
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'em', t.em, 'negocioId', t.negocio_id, 'autorId', t.autor_id,
                                               'texto', t.texto) order by t.em desc, t.id), '[]'::jsonb)
    into v_notas
    from (select nt.* from crm.nota nt
           where nt.pessoa_id = any(crm.pessoa_grupo(v_p)) and not crm.negocio_oculto(nt.negocio_id::text)
           order by nt.em desc, nt.id limit 20) t;
  v_msgs := public.crm_mensagens(v_p, v_lim);

  return jsonb_build_object('ok', true, 'contato', v_contato, 'negocios', v_neg, 'proximasAtividades', v_ats,
                            'notas', v_notas, 'mensagens', v_msgs);
end
$function$;
revoke execute on function public.crm_mcp_lead(uuid, uuid, integer) from public, anon;
grant execute on function public.crm_mcp_lead(uuid, uuid, integer) to authenticated, service_role;

-- ─── crm_mcp_rpc: + as 3 na lista fechada (corpo vivo, só as listas mudam) ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.crm_mcp_rpc(p_token uuid, p_rpc text, p_params jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  -- 20261009070000: + campos do negócio e lead agregado (leitura).
  c_ler    constant text[] := array['crm_funis', 'crm_funil_resumo', 'crm_negocios', 'crm_contatos', 'crm_jornada',
                                    'crm_atividades', 'crm_desempenho', 'crm_mensagens',
                                    'crm_mcp_negocio_campos', 'crm_mcp_lead'];
  -- 20261009060000: + WhatsApp pelo Claude (crm_mcp_*). crm_enviar_mensagem continua fora: o envio passa pelas travas do MCP.
  -- 20261009070000: + crm_mcp_preencher_campos (grava por crm_salvar_campos, que continua fora da lista).
  c_operar constant text[] := array['crm_criar_atividade', 'crm_adicionar_nota', 'crm_mover_etapa', 'crm_concluir_atividade',
                                    'crm_criar_contato', 'crm_editar_contato', 'crm_tags_contato', 'crm_reabrir_atividade',
                                    'crm_mcp_numeros', 'crm_mcp_templates', 'crm_mcp_situacao_conversa', 'crm_mcp_enviar_whatsapp',
                                    'crm_mcp_preencher_campos'];
  s jsonb; v_oid oid; v_n int; v_fora text; v_args text; v jsonb; v_role text; v_claims text[];
begin
  if p_rpc is null or not (p_rpc = any(c_ler || c_operar)) then
    raise exception 'Função fora da lista do MCP.' using errcode = '42501';
  end if;
  if p_params is not null and jsonb_typeof(p_params) <> 'object' then
    raise exception 'Parâmetros precisam ser objeto.' using errcode = '22023';
  end if;
  s := public.crm_mcp_sessao(p_token);
  if s is null then
    raise exception 'Token do MCP inválido, revogado ou expirado.' using errcode = '28000';
  end if;
  if p_rpc = any(c_operar) and not coalesce((s -> 'escopos') ? 'operar', false) then
    raise exception 'Este token não tem o escopo operar.' using errcode = '42501';
  end if;

  select min(p.oid), count(*) into v_oid, v_n
    from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = p_rpc;
  if v_n <> 1 then
    raise exception 'Função do CRM indisponível.' using errcode = '42883';
  end if;

  -- 20261009050000: parâmetro array (ex.: text[]) aceita array JSON; o resto segue como literal tipado.
  with a as (
    select x.nome, pg_catalog.format_type(x.tipo, null) as tipo
      from pg_catalog.pg_proc p,
           unnest(p.proargnames[1:p.pronargs], p.proargtypes::oid[]) as x(nome, tipo)
     where p.oid = v_oid
  )
  select string_agg(e.key, ', ') filter (where a.nome is null),
         string_agg(case when a.tipo like '%[]' and jsonb_typeof(e.value) = 'array'
                         then format('%I => array(select pg_catalog.jsonb_array_elements_text(%L::jsonb))::%s',
                                     a.nome, e.value::text, a.tipo)
                         else format('%I => %L::%s', a.nome, e.value #>> '{}', a.tipo) end, ', ')
           filter (where a.nome is not null)
    into v_fora, v_args
    from jsonb_each(coalesce(p_params, '{}'::jsonb)) e
    left join a on a.nome = e.key;
  if v_fora is not null then
    raise exception 'Parâmetro desconhecido: %', v_fora using errcode = '22023';
  end if;

  -- Bloco com EXCEPTION = subtransação: se a RPC falhar, role e claims voltam sozinhos; no sucesso, volta à mão.
  v_role := current_user;
  v_claims := array[current_setting('request.jwt.claims', true), current_setting('request.jwt.claim.sub', true),
                    current_setting('request.jwt.claim.role', true), current_setting('request.jwt.claim.email', true)];
  begin
    perform pg_catalog.set_config('request.jwt.claims', jsonb_build_object(
              'sub', s ->> 'perfilId', 'role', 'authenticated', 'aud', 'authenticated', 'email', s ->> 'email',
              'is_anonymous', false, 'gp_canal', 'mcp', 'gp_mcp_token', p_token)::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', s ->> 'perfilId', true);
    perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
    perform pg_catalog.set_config('request.jwt.claim.email', s ->> 'email', true);
    set local role authenticated;

    execute format('select public.%I(%s)', p_rpc, coalesce(v_args, '')) into v;

    execute format('set local role %I', v_role);
    perform pg_catalog.set_config('request.jwt.claims', coalesce(v_claims[1], ''), true);
    perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_claims[2], ''), true);
    perform pg_catalog.set_config('request.jwt.claim.role', coalesce(v_claims[3], ''), true);
    perform pg_catalog.set_config('request.jwt.claim.email', coalesce(v_claims[4], ''), true);
  exception when others then
    raise;
  end;
  return v;
end
$function$;
