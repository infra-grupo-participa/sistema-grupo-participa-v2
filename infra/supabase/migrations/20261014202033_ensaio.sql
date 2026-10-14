-- Ensaio de 20261014a (MCP do Comercial: criar negócio). UMA transação desfeita: aplica a migration (cópia literal
-- abaixo) e confere a lista fechada. Nenhum negócio real é tocado. Termina em exceção ENSAIO_RESULTADO + ROLLBACK.
-- Esperado: "ENSAIO_RESULTADO 4 ok de 4 | falhas: nenhuma".
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';
-- ═══ MIGRATION (cópia literal de 20261014a_crm_mcp_criar_negocio.sql) ═══
-- MCP do Comercial: criar negócio pelo Claude (comercial_criar_negocio). Pedido do Marcio (14/10/2026): pôr a lista do
-- Seminário ATM out/2026 na etapa "Lista recebida" do funil "ATM Elaine 1 2026-10 · Ativação comercial".
-- Ver docs/projetos/comercial/mcp.md e 20261014a.explain.md.
--
--   public.crm_mcp_rpc   + 'crm_criar_negocio' na lista fechada 'operar'. Resto do corpo idêntico ao de 20261009153128.
--
-- Nada novo no banco: public.crm_criar_negocio é a RPC da tela (F2, 20261006041654): guarda_escrita, pode_ver_pessoa
-- (gestor: todos), opt-out recusa, 1 negócio aberto por pessoa+funil (advisory lock), 1ª etapa do funil, dono pela
-- distribuição. Pelo MCP ela roda como o dono do token (JWT dele), igual às outras escritas.

-- ─── Guarda de premissa ─────────────────────────────────────────────────────────────────────────────────────────────
do $$
begin
  if md5((select p.prosrc from pg_catalog.pg_proc p where p.oid = 'public.crm_mcp_rpc(uuid,text,jsonb)'::regprocedure))
     <> 'e1f03b708ee5e2c8abf69d6b8f3ee895' then
    raise exception 'Premissa: public.crm_mcp_rpc mudou desde 20261009153128 (esperado md5 e1f03b70…).';
  end if;
  if to_regprocedure('public.crm_criar_negocio(uuid,uuid,uuid)') is null then
    raise exception 'Premissa: public.crm_criar_negocio(uuid,uuid,uuid) não existe.';
  end if;
end $$;

-- ─── crm_mcp_rpc: + crm_criar_negocio em 'operar' (só a lista muda) ────────────────────────────────────────────────
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
  -- 20261014a: + crm_criar_negocio (a mesma RPC do botão "Novo negócio": 1ª etapa, distribuição, opt-out, 1 aberto por funil).
  c_operar constant text[] := array['crm_criar_atividade', 'crm_adicionar_nota', 'crm_mover_etapa', 'crm_concluir_atividade',
                                    'crm_criar_contato', 'crm_editar_contato', 'crm_tags_contato', 'crm_reabrir_atividade',
                                    'crm_mcp_numeros', 'crm_mcp_templates', 'crm_mcp_situacao_conversa', 'crm_mcp_enviar_whatsapp',
                                    'crm_mcp_preencher_campos', 'crm_criar_negocio'];
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

-- ═══ TESTES ═══
do $$
declare v_ok int := 0; v_falhas text[] := '{}'; v_src text; v_estado text;
begin
  v_src := (select p.prosrc from pg_catalog.pg_proc p where p.oid = 'public.crm_mcp_rpc(uuid,text,jsonb)'::regprocedure);
  -- T1: crm_criar_negocio entrou em 'operar'
  if v_src like '%''crm_mcp_preencher_campos'', ''crm_criar_negocio''];%' then v_ok := v_ok + 1; else v_falhas := v_falhas || 'T1'; end if;
  -- T2: com token inexistente, passa da lista fechada e para no token (28000), não em "fora da lista" (42501)
  begin
    perform public.crm_mcp_rpc(gen_random_uuid(), 'crm_criar_negocio', jsonb_build_object('p_pessoa', gen_random_uuid(), 'p_funil', gen_random_uuid()));
    v_falhas := v_falhas || 'T2:sem-erro';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
    if v_estado = '28000' then v_ok := v_ok + 1; else v_falhas := v_falhas || ('T2:' || v_estado); end if;
  end;
  -- T3: RPC de fora continua recusada (42501)
  begin
    perform public.crm_mcp_rpc(gen_random_uuid(), 'crm_salvar_funil', '{}'::jsonb);
    v_falhas := v_falhas || 'T3:sem-erro';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
    if v_estado = '42501' then v_ok := v_ok + 1; else v_falhas := v_falhas || ('T3:' || v_estado); end if;
  end;
  -- T4: anon continua sem executar crm_mcp_rpc (ACL não mudou com o CREATE OR REPLACE)
  if not has_function_privilege('anon', 'public.crm_mcp_rpc(uuid,text,jsonb)', 'execute') then v_ok := v_ok + 1;
  else v_falhas := v_falhas || 'T4'; end if;
  raise exception 'ENSAIO_RESULTADO % ok de 4 | falhas: %', v_ok,
    coalesce(nullif(array_to_string(v_falhas, ', '), ''), 'nenhuma');
end $$;
rollback;
