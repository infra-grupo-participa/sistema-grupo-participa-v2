-- Ensaio de 20261008222038 (tags do contato, reabrir atividade, 4 RPCs novas no MCP). UMA transação desfeita: aplica a
-- migration inteira (cópia literal abaixo) e roda T0..T30 como Arthur (gestor), Jusy (vendedora), Victor (leitor) e
-- service_role (caminho do MCP). Contato sintético com e-mail @exemplo.invalid; tokens de ensaio criados e revogados
-- pelas RPCs. Nenhum envio. Termina com exceção ENSAIO_RESULTADO (aborta a transação) e rollback.
-- Esperado: "ENSAIO_RESULTADO 31 ok de 31 | falhas: nenhuma". Rodado contra produção antes de aplicar (08/10/2026): 31 ok de 31.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';
-- ═══ MIGRATION (cópia literal de 20261008222038_crm_tags_reabrir_mcp.sql) ═══
-- 20261008222038: CRM, tags do contato e reabrir atividade por RPC oficial + 4 RPCs novas no MCP do Comercial
--
-- STATUS: ver 20261008222038.explain.md (ensaio 20261008222038_ensaio.sql em begin … rollback).
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

  -- 20261008222038: parâmetro array (ex.: text[]) aceita array JSON; o resto segue como literal tipado.
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
-- ═══ TESTES ═══
create temp table _r (n serial, caso text, ok boolean, det text) on commit drop;
grant all on _r to authenticated, service_role; grant all on sequence _r_n_seq to authenticated, service_role;
create temp table _v (k text primary key, v text) on commit drop;
grant all on _v to authenticated, service_role;

-- T0 normalização
insert into _r (caso, ok, det) select 'T0 normaliza', crm.tag_normalizar('  Quente Ágora!! ') = 'quente-agora'
  and crm.tag_normalizar('[HT] ALUNOS') = 'ht-alunos' and crm.tag_normalizar('🔔') is null
  and length(crm.tag_normalizar(repeat('ab ', 30))) <= 40 and crm.tag_normalizar(repeat('ab ', 30)) !~ '-$',
  crm.tag_normalizar('  Quente Ágora!! ') || ' | ' || crm.tag_normalizar(repeat('ab ', 30));

-- Arthur (gestor)
select set_config('request.jwt.claims', json_build_object('sub','3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975','role','authenticated',
  'email',(select lower(btrim(email)) from public.perfis where id='3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'))::text, true);
set local role authenticated;
insert into _v select 'c', public.crm_criar_contato('{"nome":"Ensaio Tags","email":"ensaio.tags.20261009@exemplo.invalid"}') ->> 'contatoId';
insert into _r (caso, ok, det) select 'T1 contato de ensaio criado', (select v from _v where k='c') is not null, null;
-- duplicidade: mesmo e-mail devolve o mesmo contato
insert into _r (caso, ok, det) select 'T2 criar repetido devolve o existente',
  (x ->> 'ok')::boolean and (x ->> 'nova')::boolean = false and x ->> 'contatoId' = (select v from _v where k='c'), x ->> 'msg'
  from (select public.crm_criar_contato('{"nome":"Ensaio Tags 2","email":"ensaio.tags.20261009@exemplo.invalid"}') x) s;
-- adicionar
insert into _r (caso, ok, det) select 'T3 adicionar normaliza e não repete',
  (x ->> 'ok')::boolean and x -> 'tags' = '["quente-agora","vip"]'::jsonb and (x ->> 'adicionadas')::int = 2, x::text
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, array['Quente Ágora','vip','VIP']) x) s;
insert into _r (caso, ok, det) select 'T4 repetir = nada mudou', (x ->> 'ok')::boolean and x ->> 'msg' = 'Nada mudou.', x::text
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, array['vip']) x) s;
-- remover (forma normalizada)
insert into _r (caso, ok, det) select 'T5 remover pela forma normalizada',
  (x ->> 'ok')::boolean and x -> 'tags' = '["vip"]'::jsonb and (x ->> 'removidas')::int = 1, x::text
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, null, array['QUENTE agora']) x) s;
insert into _r (caso, ok, det) select 'T6 tag inválida recusada', not (x ->> 'ok')::boolean, x ->> 'msg'
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, array['🔔']) x) s;
insert into _r (caso, ok, det) select 'T7 add e remove a mesma recusado', not (x ->> 'ok')::boolean, x ->> 'msg'
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, array['a'], array['A']) x) s;
insert into _r (caso, ok, det) select 'T8 mais de 30 no contato recusado', not (x ->> 'ok')::boolean and x ->> 'msg' like 'Máximo de 30 tags por contato%', x ->> 'msg'
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, array(select 't' || g from generate_series(1,30) g)) x) s;
insert into _r (caso, ok, det) select 'T9 mais de 30 por vez recusado', not (x ->> 'ok')::boolean, x ->> 'msg'
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, array(select 't' || g from generate_series(1,31) g)) x) s;
insert into _r (caso, ok, det) select 'T10 contato inexistente', not (x ->> 'ok')::boolean, x ->> 'msg'
  from (select public.crm_tags_contato('00000000-0000-4000-8000-000000000000', array['x']) x) s;
-- editar contato (cidade/UF)
insert into _r (caso, ok, det) select 'T11 editar contato', (x ->> 'ok')::boolean, x::text
  from (select public.crm_editar_contato((select v from _v where k='c')::uuid, '{"cidade":"Niterói","uf":"rj"}') x) s;
-- atividade: criar, concluir, reabrir
insert into _v select 'a', public.crm_criar_atividade(null, (select v from _v where k='c')::uuid, 'ligacao', 'Ensaio reabrir', now() + interval '1 day') ->> 'atividadeId';
insert into _r (caso, ok, det) select 'T12 concluir', (public.crm_concluir_atividade((select v from _v where k='a')::uuid, 'Atendeu') ->> 'ok')::boolean, null;
insert into _r (caso, ok, det) select 'T13 reabrir', (x ->> 'ok')::boolean, x::text
  from (select public.crm_reabrir_atividade((select v from _v where k='a')::uuid) x) s;
insert into _r (caso, ok, det) select 'T15 reabrir aberta recusa', not (x ->> 'ok')::boolean, x ->> 'msg'
  from (select public.crm_reabrir_atividade((select v from _v where k='a')::uuid) x) s;
select public.crm_concluir_atividade((select v from _v where k='a')::uuid, 'Feito de novo');
-- token MCP do Arthur (ler+operar) e (ler)
insert into _v select 'tok', public.crm_mcp_criar_token('ensaio-20261009', array['ler','operar'], 1) ->> 'id';
insert into _v select 'tokl', public.crm_mcp_criar_token('ensaio-20261009-ler', array['ler'], 1) ->> 'id';
reset role;
-- conferências no dado (como postgres: crm.* não é exposto)
insert into _r (caso, ok, det) select 'T14 reabrir limpou concluida_em e resultado',
  exists (select 1 from crm.log l where l.entidade = 'atividade' and l.entidade_id = (select v from _v where k='a')
            and l.resumo like 'Reabriu a atividade%'
            and l.mudancas @> '[{"campo":"concluida_em","para":null},{"campo":"resultado","para":null}]'::jsonb), null;
insert into _r (caso, ok, det) select 'T16 log via tela sem nome/valor de tag no resumo',
  (select count(*) = 2 from crm.log l where l.pessoa_id = (select v from _v where k='c')::uuid and l.resumo like 'Tags:%' and l.canal = 'tela')
  and (select count(*) = 1 from crm.log l where l.entidade = 'atividade' and l.resumo like 'Reabriu a atividade%' and l.entidade_id = (select v from _v where k='a')), null;

-- Jusy (vendedora, não dona do contato de ensaio)
select set_config('request.jwt.claims', json_build_object('sub','412d7d8d-7699-4dbf-977c-3b3cc82223df','role','authenticated',
  'email',(select lower(btrim(email)) from public.perfis where id='412d7d8d-7699-4dbf-977c-3b3cc82223df'))::text, true);
set local role authenticated;
insert into _r (caso, ok, det) select 'T17 D6: vendedora não dona não mexe em tag', not (x ->> 'ok')::boolean, x ->> 'msg'
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, array['x']) x) s;
insert into _r (caso, ok, det) select 'T18 vendedora não reabre atividade de outro', not (x ->> 'ok')::boolean, x ->> 'msg'
  from (select public.crm_reabrir_atividade((select v from _v where k='a')::uuid) x) s;
reset role;

-- Victor (leitor)
select set_config('request.jwt.claims', json_build_object('sub','81d2eaee-cce1-4058-8714-439b0fc6f970','role','authenticated',
  'email',(select lower(btrim(email)) from public.perfis where id='81d2eaee-cce1-4058-8714-439b0fc6f970'))::text, true);
set local role authenticated;
insert into _r (caso, ok, det) select 'T19 leitor não escreve tag', x ->> 'msg' in ('Acesso só de leitura.', 'Sem acesso ao Comercial.'), x ->> 'msg'
  from (select public.crm_tags_contato((select v from _v where k='c')::uuid, array['x']) x) s;
insert into _r (caso, ok, det) select 'T20 leitor não reabre', not (x ->> 'ok')::boolean, x ->> 'msg'
  from (select public.crm_reabrir_atividade((select v from _v where k='a')::uuid) x) s;
reset role;

-- anon não executa
insert into _r (caso, ok, det) select 'T21 anon sem execute nas novas',
  not has_function_privilege('anon', 'public.crm_tags_contato(uuid,text[],text[])', 'execute')
  and not has_function_privilege('anon', 'public.crm_reabrir_atividade(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.crm_mcp_rpc(uuid,text,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'crm.tag_normalizar(text)', 'execute')
  and has_function_privilege('authenticated', 'public.crm_tags_contato(uuid,text[],text[])', 'execute'), null;

-- MCP (como o servidor: service_role chama crm_mcp_rpc)
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
insert into _r (caso, ok, det) select 'T22 MCP tags com array JSON', (x ->> 'ok')::boolean and x -> 'tags' = '["vip","via-mcp"]'::jsonb, x::text
  from (select public.crm_mcp_rpc((select v from _v where k='tok')::uuid, 'crm_tags_contato',
        jsonb_build_object('p_pessoa', (select v from _v where k='c'), 'p_adicionar', jsonb_build_array('Via MCP'))) x) s;
insert into _r (caso, ok, det) select 'T23 MCP remover tag', (x ->> 'ok')::boolean and x -> 'tags' = '["via-mcp"]'::jsonb, x::text
  from (select public.crm_mcp_rpc((select v from _v where k='tok')::uuid, 'crm_tags_contato',
        jsonb_build_object('p_pessoa', (select v from _v where k='c'), 'p_remover', jsonb_build_array('VIP'))) x) s;
insert into _r (caso, ok, det) select 'T24 MCP editar contato', (x ->> 'ok')::boolean, x::text
  from (select public.crm_mcp_rpc((select v from _v where k='tok')::uuid, 'crm_editar_contato',
        jsonb_build_object('p_contato', (select v from _v where k='c'), 'p_dados', jsonb_build_object('empresa', 'Ensaio Ltda'))) x) s;
insert into _r (caso, ok, det) select 'T25 MCP criar contato repetido devolve existente',
  (x ->> 'ok')::boolean and x ->> 'contatoId' = (select v from _v where k='c'), x ->> 'msg'
  from (select public.crm_mcp_rpc((select v from _v where k='tok')::uuid, 'crm_criar_contato',
        jsonb_build_object('p_dados', jsonb_build_object('nome', 'Ensaio X', 'email', 'ensaio.tags.20261009@exemplo.invalid'))) x) s;
insert into _r (caso, ok, det) select 'T26 MCP reabrir', (x ->> 'ok')::boolean, x::text
  from (select public.crm_mcp_rpc((select v from _v where k='tok')::uuid, 'crm_reabrir_atividade',
        jsonb_build_object('p_atividade', (select v from _v where k='a'))) x) s;
do $$
begin
  perform public.crm_mcp_rpc((select v from _v where k='tokl')::uuid, 'crm_tags_contato',
          jsonb_build_object('p_pessoa', (select v from _v where k='c'), 'p_adicionar', jsonb_build_array('x')));
  insert into _r (caso, ok, det) values ('T28 token só ler recusa escrita', false, 'passou');
exception when insufficient_privilege then
  insert into _r (caso, ok, det) values ('T28 token só ler recusa escrita', true, sqlerrm);
end $$;
do $$
begin
  perform public.crm_mcp_rpc((select v from _v where k='tok')::uuid, 'crm_excluir_contato', '{}'::jsonb);
  insert into _r (caso, ok, det) values ('T29 apagar contato fora da lista', false, 'passou');
exception when insufficient_privilege then
  insert into _r (caso, ok, det) values ('T29 apagar contato fora da lista', true, sqlerrm);
end $$;
reset role;
insert into _r (caso, ok, det) select 'T27 log canal mcp',
  (select count(*) >= 3 from crm.log l where l.pessoa_id = (select v from _v where k='c')::uuid and l.canal = 'mcp' and l.autor_tipo = 'mcp')
  or (select count(*) >= 3 from crm.log l where l.canal = 'mcp' and l.em >= now()), null;

-- revoga os tokens de ensaio pela RPC (Arthur)
select set_config('request.jwt.claims', json_build_object('sub','3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975','role','authenticated',
  'email',(select lower(btrim(email)) from public.perfis where id='3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'))::text, true);
set local role authenticated;
insert into _r (caso, ok, det) select 'T30 revogar tokens', (public.crm_mcp_revogar_token((select v from _v where k='tok')::uuid) ->> 'ok')::boolean
  and (public.crm_mcp_revogar_token((select v from _v where k='tokl')::uuid) ->> 'ok')::boolean, null;
reset role;

do $$ begin
  raise exception 'ENSAIO_RESULTADO % ok de % | falhas: %', (select count(*) filter (where ok) from _r), (select count(*) from _r),
    coalesce((select json_agg(json_build_object('caso', caso, 'det', det)) from _r where ok is not true)::text, 'nenhuma');
end $$;
rollback;
