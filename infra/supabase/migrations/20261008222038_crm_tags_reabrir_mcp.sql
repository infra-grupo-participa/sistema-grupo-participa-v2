-- 20261008222038: CRM, tags do contato e reabrir atividade por RPC oficial + 4 RPCs novas no MCP do Comercial
--
-- STATUS: APLICADA em produção em 08/10/2026 (versão 20261008222038 gravada em schema_migrations). Ensaio 31/31 ok.
--
-- POR QUE
--   - Tags do contato (crm.pessoa_comercial.tags) só eram gravadas direto na tabela (importações). Não havia RPC: a
--     ficha não editava e o MCP não tinha como. Agora: public.crm_tags_contato, com guarda de escrita e D6.
--   - Reabrir atividade concluída por engano não existia (nem na tela nem no MCP): public.crm_reabrir_atividade.
--   - MCP do Comercial ganha criar/editar contato, tags e reabrir atividade. Apagar contato e enviar WhatsApp ficam
--     FORA (decisão do Arthur pendente).
--
-- O QUE FAZ
--   a. crm.tag_normalizar(text): minúsculo, sem acento (unaccent), tudo que não é [a-z0-9] vira hífen, sem hífen nas
--      pontas, até 40 caracteres. Espelho em web/modules/comercial/domain/tags.ts.
--   b. public.crm_tags_contato(p_pessoa, p_adicionar text[], p_remover text[]): crm.exige_comercial +
--      crm.guarda_escrita (leitor, escrita_ligada) + crm.pode_escrever_pessoa (dono do contato, dono de negócio da
--      pessoa ou gestor). Adiciona normalizado (sem repetir), remove pela forma normalizada (tira também as tags
--      antigas importadas, ex.: "[HT] ALUNOS" sai com "ht-alunos"), até 30 por chamada e 30 por contato.
--      Log: o resumo diz só QUANTAS tags entraram/saíram (o crm.tg_log guarda o antes/depois da coluna, como já faz
--      para perfil/holding).
--   c. public.crm_reabrir_atividade(p_atividade): guarda_escrita + dono da atividade ou gestor; limpa concluida_em e
--      resultado (CHECK atividade_check exige os dois juntos). Log pelo crm.tg_log com resumo.
--   d. public.crm_mcp_rpc: + crm_criar_contato, crm_editar_contato, crm_tags_contato, crm_reabrir_atividade na lista
--      'operar'; parâmetro de tipo array (text[]) aceita array JSON. Corpo vivo lido: md5(prosrc) 80bb0566… (guarda).
--   e. Grants: as duas RPCs novas executáveis só por authenticated/service_role (revoke de PUBLIC e anon);
--      crm.tag_normalizar sem grant para a API; crm_mcp_rpc continua só service_role.
--
-- REVERSÃO: 20261008222038_reversao.sql (drop das 3 funções novas + crm_mcp_rpc do corpo anterior).

do $$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.crm_mcp_rpc(uuid,text,jsonb)'::regprocedure)
     is distinct from '80bb0566fcaf103ba9fdee6314ed2cb1' then
    raise exception 'premissa: public.crm_mcp_rpc mudou desde a leitura (md5 80bb0566…)';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where (n.nspname = 'public' and p.proname in ('crm_tags_contato', 'crm_reabrir_atividade'))
                 or (n.nspname = 'crm' and p.proname = 'tag_normalizar')) then
    raise exception 'premissa: crm_tags_contato/crm_reabrir_atividade/crm.tag_normalizar já existem';
  end if;
  if not exists (select 1 from pg_extension where extname = 'unaccent') then
    raise exception 'premissa: extensão unaccent ausente';
  end if;
end $$;

-- ─── a. normalização ────────────────────────────────────────────────────────────────────────────────────────────────
create function crm.tag_normalizar(p text)
 returns text
 language sql
 stable
 set search_path to ''
as $function$
  select nullif(btrim(left(btrim(regexp_replace(lower(public.unaccent('public.unaccent'::regdictionary, coalesce(p, ''))),
                                                '[^a-z0-9]+', '-', 'g'), '-'), 40), '-'), '');
$function$;
revoke all on function crm.tag_normalizar(text) from public, anon, authenticated;

-- ─── b. tags do contato ─────────────────────────────────────────────────────────────────────────────────────────────
create function public.crm_tags_contato(p_pessoa uuid, p_adicionar text[] default null, p_remover text[] default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_r jsonb; v_atual uuid; v_pc uuid; v_tags text[]; v_novas text[]; v_add text[]; v_rem text[];
  v_n_rem int; v_s text; v_c text; v_m text;
begin
  perform crm.exige_comercial();
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_pessoa is null then return crm.res(false, 'Contato inválido.'); end if;
  if coalesce(cardinality(p_adicionar), 0) = 0 and coalesce(cardinality(p_remover), 0) = 0 then
    return crm.res(false, 'Informe as tags para adicionar ou remover.');
  end if;
  if coalesce(cardinality(p_adicionar), 0) > 30 or coalesce(cardinality(p_remover), 0) > 30 then
    return crm.res(false, 'Máximo de 30 tags por vez.');
  end if;
  if exists (select 1 from unnest(coalesce(p_adicionar, '{}')) x where crm.tag_normalizar(x) is null) then
    return crm.res(false, 'Tag inválida: use letras ou números (até 40 caracteres).');
  end if;

  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  if not coalesce(crm.pode_escrever_pessoa(v_atual), false) then
    return crm.res(false, 'Este contato não é seu: só o dono ou o gestor edita.');
  end if;

  v_add := array(select distinct crm.tag_normalizar(x) from unnest(coalesce(p_adicionar, '{}')) x);
  v_rem := array(select distinct crm.tag_normalizar(x) from unnest(coalesce(p_remover, '{}')) x
                  where crm.tag_normalizar(x) is not null);
  if v_add && v_rem then return crm.res(false, 'A mesma tag não pode ser adicionada e removida juntas.'); end if;

  v_pc := crm.garantir_pc(v_atual);
  select pc.tags into v_tags from crm.pessoa_comercial pc where pc.pessoa_id = v_pc for update;
  v_tags := coalesce(v_tags, '{}');
  -- remove pela forma normalizada (pega a tag importada crua também), mantendo a ordem
  v_novas := array(select t from unnest(v_tags) with ordinality u(t, i)
                    where not (coalesce(crm.tag_normalizar(t), '') = any(v_rem)) order by i);
  v_n_rem := cardinality(v_tags) - cardinality(v_novas);
  -- adiciona só o que ainda não está (comparando normalizado)
  v_add := array(select a from unnest(v_add) a
                  where not exists (select 1 from unnest(v_novas) t where crm.tag_normalizar(t) = a) order by a);
  v_novas := v_novas || v_add;
  if cardinality(v_novas) > 30 then
    return crm.res(false, format('Máximo de 30 tags por contato (ficaria com %s). Remova alguma antes.', cardinality(v_novas)));
  end if;
  if v_n_rem = 0 and cardinality(v_add) = 0 then
    return crm.res(true, 'Nada mudou.', jsonb_build_object('contatoId', v_atual, 'tags', to_jsonb(v_tags),
                                                           'adicionadas', 0, 'removidas', 0));
  end if;

  perform set_config('crm.resumo', format('Tags: %s adicionada(s), %s removida(s)', cardinality(v_add), v_n_rem), true);
  update crm.pessoa_comercial x set tags = v_novas, atualizado_em = now() where x.pessoa_id = v_pc;
  perform set_config('crm.resumo', '', true);

  begin
    perform realtime.send(jsonb_build_object('t', 'contato'), 'mudou', 'crm:caixa', true);
  exception when others then
    raise warning 'crm_tags_contato: aviso realtime falhou: %', sqlerrm;
  end;

  return crm.res(true, 'Tags atualizadas.', jsonb_build_object('contatoId', v_atual, 'tags', to_jsonb(v_novas),
                                                               'adicionadas', cardinality(v_add), 'removidas', v_n_rem));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;
revoke all on function public.crm_tags_contato(uuid, text[], text[]) from public, anon;
grant execute on function public.crm_tags_contato(uuid, text[], text[]) to authenticated, service_role;

-- ─── c. reabrir atividade ───────────────────────────────────────────────────────────────────────────────────────────
create function public.crm_reabrir_atividade(p_atividade uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; a crm.atividade%rowtype; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_atividade is null then return crm.res(false, 'Atividade inválida.'); end if;
  select * into a from crm.atividade x where x.id = p_atividade for update;
  if not found or a.concluida_em is null then return crm.res(false, 'Atividade não encontrada ou ainda aberta.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or a.dono_id = v_eu) then return crm.res(false, 'Esta atividade não é sua.'); end if;
  perform set_config('crm.resumo', left(format('Reabriu a atividade "%s"', a.titulo), 1000), true);
  update crm.atividade x set concluida_em = null, resultado = null where x.id = p_atividade;
  perform set_config('crm.resumo', '', true);
  return crm.res(true, 'Atividade reaberta.', jsonb_build_object('atividadeId', a.id, 'venceEm', a.vence_em));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;
revoke all on function public.crm_reabrir_atividade(uuid) from public, anon;
grant execute on function public.crm_reabrir_atividade(uuid) to authenticated, service_role;

-- ─── d. MCP: lista fechada + parâmetro array ────────────────────────────────────────────────────────────────────────
create or replace function public.crm_mcp_rpc(p_token uuid, p_rpc text, p_params jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare
  c_ler    constant text[] := array['crm_funis', 'crm_funil_resumo', 'crm_negocios', 'crm_contatos', 'crm_jornada',
                                    'crm_atividades', 'crm_desempenho', 'crm_mensagens'];
  c_operar constant text[] := array['crm_criar_atividade', 'crm_adicionar_nota', 'crm_mover_etapa', 'crm_concluir_atividade',
                                    'crm_criar_contato', 'crm_editar_contato', 'crm_tags_contato', 'crm_reabrir_atividade'];
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
revoke all on function public.crm_mcp_rpc(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.crm_mcp_rpc(uuid, text, jsonb) to service_role;
