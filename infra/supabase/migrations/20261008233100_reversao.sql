-- Reversão de 20261008233100 (NÃO rodar sem decisão). Primeiro passo, sem deploy: kill-switch
--   update crm.config set mcp_envio_ligado = false;
-- Esta reversão volta crm_mcp_rpc ao corpo de 20261008222038 (md5 9753efed…), crm.mensagem_json ao corpo anterior
-- (md5 628ca5e6…) e remove as RPCs/helpers novos. As colunas ficam (crm.mensagem.origem guarda quem enviou pelo Claude;
-- apagar perde o registro): para tirá-las, alter table … drop column numa migration própria.
begin;
drop function if exists public.crm_mcp_enviar_whatsapp(uuid, uuid, text, text, uuid);
drop function if exists public.crm_mcp_situacao_conversa(uuid, uuid, text);
drop function if exists public.crm_mcp_templates(text, integer);
drop function if exists public.crm_mcp_numeros();
drop function if exists crm.mcp_template(uuid, text);
drop function if exists crm.mcp_conversa(uuid, uuid);
drop function if exists crm.mcp_canal(uuid, uuid);
create or replace function crm.mensagem_json(m crm.mensagem, p_contato uuid)
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select jsonb_build_object(
    'id', m.id, 'contatoId', p_contato, 'canal', 'whatsapp', 'direcao', m.direcao, 'tipo', m.tipo, 'texto', m.texto, 'em', m.em,
    'status', case when m.direcao = 'entrada' then case when m.lida_em is null then null else 'lida' end
                   when m.status in ('na_fila', 'enviando') then null else m.status end,
    'envio', case when m.status in ('na_fila', 'enviando') then m.status end,
    'erro', m.erro, 'autorId', m.autor_id, 'templateId', m.template_id, 'fichaId', m.ficha_id,
    'canalId', m.numero_id, 'externa', m.externa,
    'midia', case when m.midia_status is not null then jsonb_build_object(
               'status', m.midia_status, 'caminho', case when m.midia_status = 'ok' then m.midia_caminho end,
               'mime', m.midia_mime, 'tamanho', m.midia_tamanho, 'nome', m.midia_nome) end);
$function$;
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
commit;
