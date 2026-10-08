-- 20261008150823 (escrita como 20261008mcp) — APLICADA em 08/10/2026 — MCP do Comercial: execução SEM o segredo JWT legado + servidor OAuth 2.1 próprio (claude.ai).
-- STATUS: APLICADA (versão 20261008150823, nome crm_mcp_oauth, md5 dos statements 2089de1898e8b4fee160dfaea8e5bb85). Ver .explain.md.
--
-- POR QUE
--   (a) Em produção, tools/call devolvia 503: o servidor Next não tem SUPABASE_JWT_SECRET (segredo HS256 legado) para
--       assinar o JWT curto do dono do token. O projeto já assina com chaves ES256 (privadas ficam no Supabase).
--       Em vez de espalhar o segredo legado (poder de service role) para a Hostinger, o servidor passa a chamar
--       public.crm_mcp_rpc com a service role que ele JÁ tem. A função NÃO age como service role: valida o token,
--       monta as claims do dono (sub, email, gp_canal='mcp'), faz SET LOCAL ROLE authenticated e só então chama a
--       MESMA public.crm_* da tela. RLS, auth.uid(), crm.eh_*, escrita_ligada e o crm.tg_log (autor_tipo='mcp') valem
--       igual ao JWT assinado. SET ROLE é permitido porque a função é SECURITY INVOKER e o usuário de sessão do
--       PostgREST (authenticator) é membro de authenticated. Role e claims voltam ao que eram na saída (erro: a
--       subtransação do bloco EXCEPTION desfaz; sucesso: restauração explícita — o ensaio provou que a cláusula
--       SET search_path NÃO desfaz um SET LOCAL ROLE feito no corpo).
--   (b) claude.ai (web/celular/Desktop "conectores") só conecta por OAuth 2.1. O servidor OAuth do Supabase Auth não
--       serve: a tela de consentimento = Site URL do projeto + caminho, e o Site URL é de OUTRO sistema do grupo
--       (sip.timeholdingbrasil.com.br). Então o app vira o próprio servidor OAuth, mínimo:
--         - registro dinâmico (RFC 7591) só com redirect na lista fechada (claude.ai/claude.com e loopback);
--         - código de uso único, 5 min, só hash no banco, amarrado a cliente + redirect + PKCE S256 + perfil;
--         - access token = um token gpc_ comum em crm.mcp_token (1 h), com refresh gpr_ rotativo (30 d, teto 180 d);
--           assim crm_mcp_autenticar, o limite de 60/min, o kill-switch e a revogação pela tela valem sem mudança;
--         - consentimento explícito por pessoa do Comercial (crm.mcp_papel) com o MCP ligado.
--
-- O QUE FAZ
--   1. public.crm_mcp_sessao(uuid) [service_role]: token ativo → perfil/email/escopos (null se não vale mais).
--   2. public.crm_mcp_rpc(uuid, text, jsonb) [service_role]: lista fechada de RPCs (8 de leitura, 4 de escrita;
--      escrita exige escopo operar), parâmetros só pelos nomes da assinatura viva, executa como o dono.
--   3. crm.mcp_oauth_cliente, crm.mcp_oauth_codigo (RLS ligada, sem policy, sem grant) e 3 colunas em crm.mcp_token
--      (cliente_id, refresh_sha256, refresh_expira_em).
--   4. public.crm_mcp_oauth_registrar [service_role], crm_mcp_oauth_cliente [authenticated],
--      crm_mcp_oauth_autorizar [authenticated], crm_mcp_oauth_trocar e crm_mcp_oauth_renovar [service_role].
--   5. public.crm_mcp_criar_token: o limite de 5 ativos conta só token manual (cliente_id is null). Corpo vivo
--      conferido por md5 (8726128c…) antes de trocar; 1 linha mudou.
--
-- 5 PERGUNTAS
--   escala: clientes OAuth = poucos (1 por instalação do Claude), teto 200 registros/24 h; códigos: ≤ 20 por perfil
--     a cada 10 min, apagados 1 dia depois de vencidos; tokens OAuth: 1 ativo por perfil × cliente (o novo revoga o
--     anterior). crm_mcp_rpc: 2 leituras por PK + a RPC da tela (custo dela).
--   índice: tudo por PK/UNIQUE (hash_sha256, refresh_sha256, id) + (perfil_id, criado_em) nos códigos.
--   frequência: 1 crm_mcp_rpc por RPC de ferramenta (≤ 60 ferramentas/min/token, limite já existente).
--   repetição: nenhuma leitura duplicada por pedido.
--   reversão: crm.config.mcp_ligado = false desliga tudo (rpc, autorizar, trocar, renovar) em ~10 s; revogar pela tela.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.crm_mcp_criar_token(text,text[],integer)'::regprocedure)
     <> '8726128c5cef440774ca9a395e218877' then
    raise exception '20261008mcp: crm_mcp_criar_token mudou desde a leitura; refazer a partir do corpo vivo';
  end if;
  if to_regclass('crm.mcp_oauth_cliente') is not null or to_regprocedure('public.crm_mcp_rpc(uuid,text,jsonb)') is not null then
    raise exception '20261008mcp: objetos já existem';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config' and column_name = 'mcp_ligado') then
    raise exception '20261008mcp: crm.config.mcp_ligado ausente (F7 não aplicada?)';
  end if;
end
$g$;

-- ═══ 1–2. Execução como o dono do token, sem segredo JWT ═══════════════════════════════════════════════════════════
create function public.crm_mcp_sessao(p_token uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('perfilId', t.perfil_id, 'email', lower(btrim(pf.email)), 'escopos', to_jsonb(t.escopos))
    from crm.mcp_token t
    join public.perfis pf on pf.id = t.perfil_id
   where t.id = p_token
     and t.revogado_em is null
     and t.expira_em > now()
     and coalesce((select c.mcp_ligado from crm.config c), false)
     and crm.mcp_papel(t.perfil_id) is not null
     and pf.email is not null;
$$;

create function public.crm_mcp_rpc(p_token uuid, p_rpc text, p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  c_ler    constant text[] := array['crm_funis', 'crm_funil_resumo', 'crm_negocios', 'crm_contatos', 'crm_jornada',
                                    'crm_atividades', 'crm_desempenho', 'crm_mensagens'];
  c_operar constant text[] := array['crm_criar_atividade', 'crm_adicionar_nota', 'crm_mover_etapa', 'crm_concluir_atividade'];
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

  with a as (
    select x.nome, pg_catalog.format_type(x.tipo, null) as tipo
      from pg_catalog.pg_proc p,
           unnest(p.proargnames[1:p.pronargs], p.proargtypes::oid[]) as x(nome, tipo)
     where p.oid = v_oid
  )
  select string_agg(e.key, ', ') filter (where a.nome is null),
         string_agg(format('%I => %L::%s', a.nome, e.value #>> '{}', a.tipo), ', ') filter (where a.nome is not null)
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
$$;

-- ═══ 3. OAuth: clientes, códigos, colunas no token ═════════════════════════════════════════════════════════════════
create table crm.mcp_oauth_cliente (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null check (length(btrim(nome)) between 1 and 100),
  redirect_uris text[] not null check (cardinality(redirect_uris) between 1 and 5),
  criado_em     timestamptz not null default now()
);

create table crm.mcp_oauth_codigo (
  hash_sha256    text primary key check (hash_sha256 ~ '^[0-9a-f]{64}$'),
  cliente_id     uuid not null references crm.mcp_oauth_cliente (id) on delete cascade,
  perfil_id      uuid not null references public.perfis (id) on delete restrict,
  redirect_uri   text not null,
  code_challenge text not null check (code_challenge ~ '^[A-Za-z0-9_-]{43}$'),
  escopos        text[] not null check (escopos <@ array['ler', 'operar']::text[] and 'ler' = any(escopos)),
  criado_em      timestamptz not null default now(),
  expira_em      timestamptz not null,
  usado_em       timestamptz
);
create index mcp_oauth_codigo_perfil_idx on crm.mcp_oauth_codigo (perfil_id, criado_em);

alter table crm.mcp_token
  add column cliente_id        uuid references crm.mcp_oauth_cliente (id) on delete restrict,
  add column refresh_sha256    text unique check (refresh_sha256 ~ '^[0-9a-f]{64}$'),
  add column refresh_expira_em timestamptz;

alter table crm.mcp_oauth_cliente enable row level security;
alter table crm.mcp_oauth_codigo enable row level security;
revoke all on crm.mcp_oauth_cliente, crm.mcp_oauth_codigo from public, anon, authenticated;

-- ═══ 4. RPCs do OAuth ══════════════════════════════════════════════════════════════════════════════════════════════
-- Registro dinâmico. A lista fechada de redirect é validada no servidor (domain/mcp-oauth.ts); aqui, formato e teto.
create function public.crm_mcp_oauth_registrar(p_nome text, p_redirects text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid; v_nome text := left(btrim(coalesce(p_nome, '')), 100);
begin
  if v_nome = '' then v_nome := 'Cliente MCP'; end if;
  if p_redirects is null or cardinality(p_redirects) not between 1 and 5
     or exists (select 1 from unnest(p_redirects) r where r is null or length(r) > 300 or r !~ '^https?://') then
    return jsonb_build_object('ok', false, 'msg', 'redirect_uris inválidas.');
  end if;
  if (select count(*) from crm.mcp_oauth_cliente c where c.criado_em > now() - interval '1 day') >= 200 then
    return jsonb_build_object('ok', false, 'msg', 'Muitos registros hoje. Tente amanhã.');
  end if;
  insert into crm.mcp_oauth_cliente (nome, redirect_uris) values (v_nome, p_redirects) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'nome', v_nome);
end
$$;

-- Tela de consentimento: o pedido é válido e a pessoa pode conectar?
create function public.crm_mcp_oauth_cliente(p_cliente uuid, p_redirect text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_eu uuid := auth.uid(); c crm.mcp_oauth_cliente%rowtype;
begin
  if not coalesce((select x.mcp_ligado from crm.config x), false) then
    return jsonb_build_object('ok', false, 'msg', 'A conexão com o Claude está desligada no CRM. Fale com o gestor.');
  end if;
  if v_eu is null or crm.mcp_papel(v_eu) is null then
    return jsonb_build_object('ok', false, 'msg', 'Só quem é do Comercial pode conectar o Claude ao CRM.');
  end if;
  select * into c from crm.mcp_oauth_cliente x where x.id = p_cliente;
  if not found or p_redirect is null or not (p_redirect = any(c.redirect_uris)) then
    return jsonb_build_object('ok', false, 'msg', 'Pedido de conexão inválido. Comece de novo pelo Claude.');
  end if;
  return jsonb_build_object('ok', true, 'nome', c.nome, 'papel', crm.mcp_papel(v_eu));
end
$$;

-- Consentimento dado: emite o código (uso único, 5 min). O texto do código sai 1 vez; o banco guarda o sha-256.
create function public.crm_mcp_oauth_autorizar(p_cliente uuid, p_redirect text, p_challenge text, p_escopos text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_eu uuid := auth.uid(); c crm.mcp_oauth_cliente%rowtype; v_esc text[]; v_codigo text;
begin
  if not coalesce((select x.mcp_ligado from crm.config x), false) then
    return jsonb_build_object('ok', false, 'msg', 'A conexão com o Claude está desligada no CRM.');
  end if;
  if v_eu is null or crm.mcp_papel(v_eu) is null then
    return jsonb_build_object('ok', false, 'msg', 'Só quem é do Comercial pode conectar o Claude ao CRM.');
  end if;
  select * into c from crm.mcp_oauth_cliente x where x.id = p_cliente;
  if not found or p_redirect is null or not (p_redirect = any(c.redirect_uris)) then
    return jsonb_build_object('ok', false, 'msg', 'Pedido de conexão inválido. Comece de novo pelo Claude.');
  end if;
  if p_challenge is null or p_challenge !~ '^[A-Za-z0-9_-]{43}$' then
    return jsonb_build_object('ok', false, 'msg', 'Pedido de conexão inválido (PKCE).');
  end if;
  v_esc := array(select distinct e from unnest(coalesce(p_escopos, array['ler'])) e where e is not null order by 1);
  if cardinality(v_esc) = 0 or not (v_esc <@ array['ler', 'operar']::text[]) then
    return jsonb_build_object('ok', false, 'msg', 'Permissão inválida.');
  end if;
  if not ('ler' = any(v_esc)) then v_esc := array['ler'] || v_esc; end if;
  if (select count(*) from crm.mcp_oauth_codigo k where k.perfil_id = v_eu and k.criado_em > now() - interval '10 minutes') >= 20 then
    return jsonb_build_object('ok', false, 'msg', 'Muitas tentativas. Espere alguns minutos.');
  end if;
  delete from crm.mcp_oauth_codigo k where k.perfil_id = v_eu and k.expira_em < now() - interval '1 day';
  v_codigo := encode(extensions.gen_random_bytes(32), 'hex');
  insert into crm.mcp_oauth_codigo (hash_sha256, cliente_id, perfil_id, redirect_uri, code_challenge, escopos, expira_em)
  values (encode(extensions.digest(v_codigo, 'sha256'), 'hex'), c.id, v_eu, p_redirect, p_challenge, v_esc,
          now() + interval '5 minutes');
  return jsonb_build_object('ok', true, 'codigo', v_codigo);
end
$$;

-- Troca do código por tokens. O servidor gera os textos (gpc_/gpr_) e manda só os hashes + o desafio PKCE calculado.
create function public.crm_mcp_oauth_trocar(p_codigo_hash text, p_cliente uuid, p_redirect text, p_challenge text,
                                            p_access_hash text, p_prefixo text, p_refresh_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare k crm.mcp_oauth_codigo%rowtype; v_nome text; v_exp timestamptz;
begin
  if not coalesce((select x.mcp_ligado from crm.config x), false) then
    return jsonb_build_object('ok', false, 'erro', 'invalid_grant', 'msg', 'MCP do Comercial desligado.');
  end if;
  update crm.mcp_oauth_codigo x set usado_em = now()
   where x.hash_sha256 = p_codigo_hash and x.usado_em is null
  returning * into k;
  if not found then
    -- código repetido: derruba o que ele já emitiu (RFC 6749 §4.1.2)
    select * into k from crm.mcp_oauth_codigo x where x.hash_sha256 = p_codigo_hash;
    if found then
      update crm.mcp_token t set revogado_em = now(), revogado_por = k.perfil_id
       where t.perfil_id = k.perfil_id and t.cliente_id = k.cliente_id and t.revogado_em is null
         and t.criado_em >= k.criado_em;
    end if;
    return jsonb_build_object('ok', false, 'erro', 'invalid_grant', 'msg', 'Código inválido ou já usado.');
  end if;
  if k.expira_em <= now() or k.cliente_id <> p_cliente or k.redirect_uri <> coalesce(p_redirect, '')
     or k.code_challenge <> coalesce(p_challenge, '') then
    return jsonb_build_object('ok', false, 'erro', 'invalid_grant', 'msg', 'Código inválido, vencido ou de outro pedido.');
  end if;
  if crm.mcp_papel(k.perfil_id) is null then
    return jsonb_build_object('ok', false, 'erro', 'invalid_grant', 'msg', 'Perfil sem acesso ao Comercial.');
  end if;
  select left('Claude: ' || c.nome, 60) into v_nome from crm.mcp_oauth_cliente c where c.id = k.cliente_id;
  -- 1 conexão ativa por pessoa × cliente: a nova substitui a anterior
  update crm.mcp_token t set revogado_em = now(), revogado_por = k.perfil_id
   where t.perfil_id = k.perfil_id and t.cliente_id = k.cliente_id and t.revogado_em is null;
  v_exp := now() + interval '1 hour';
  insert into crm.mcp_token (perfil_id, nome, prefixo, hash_sha256, escopos, expira_em, cliente_id, refresh_sha256,
                             refresh_expira_em)
  values (k.perfil_id, v_nome, p_prefixo, p_access_hash, k.escopos, v_exp, k.cliente_id, p_refresh_hash,
          now() + interval '30 days');
  return jsonb_build_object('ok', true, 'escopos', to_jsonb(k.escopos), 'expiraEm', v_exp);
end
$$;

-- Renovação com rotação do refresh (o anterior deixa de valer). Teto: 180 dias desde o consentimento.
create function public.crm_mcp_oauth_renovar(p_refresh_hash text, p_cliente uuid, p_access_hash text, p_prefixo text,
                                             p_refresh_novo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare t crm.mcp_token%rowtype; v_exp timestamptz;
begin
  if not coalesce((select x.mcp_ligado from crm.config x), false) then
    return jsonb_build_object('ok', false, 'erro', 'invalid_grant', 'msg', 'MCP do Comercial desligado.');
  end if;
  select * into t from crm.mcp_token x where x.refresh_sha256 = p_refresh_hash for update;
  if not found or t.cliente_id is distinct from p_cliente or t.revogado_em is not null
     or t.refresh_expira_em is null or t.refresh_expira_em <= now() then
    return jsonb_build_object('ok', false, 'erro', 'invalid_grant', 'msg', 'Conexão vencida ou revogada. Conecte de novo.');
  end if;
  if crm.mcp_papel(t.perfil_id) is null then
    return jsonb_build_object('ok', false, 'erro', 'invalid_grant', 'msg', 'Perfil sem acesso ao Comercial.');
  end if;
  v_exp := least(now() + interval '1 hour', t.criado_em + interval '180 days');
  if v_exp <= now() then
    return jsonb_build_object('ok', false, 'erro', 'invalid_grant', 'msg', 'Conexão vencida. Conecte de novo.');
  end if;
  update crm.mcp_token x
     set hash_sha256 = p_access_hash, prefixo = p_prefixo, refresh_sha256 = p_refresh_novo, expira_em = v_exp,
         refresh_expira_em = least(now() + interval '30 days', t.criado_em + interval '180 days')
   where x.id = t.id;
  return jsonb_build_object('ok', true, 'escopos', to_jsonb(t.escopos), 'expiraEm', v_exp);
end
$$;

-- ═══ 5. crm_mcp_criar_token: limite de 5 conta só token manual (corpo vivo, 1 linha mudou) ═════════════════════════
create or replace function public.crm_mcp_criar_token(p_nome text, p_escopos text[] DEFAULT ARRAY['ler'::text], p_dias integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_esc text[]; v_token text; v_hash text; v_id uuid; v_exp timestamptz;
begin
  if not coalesce((select c.mcp_ligado from crm.config c), false) then
    return jsonb_build_object('ok', false, 'msg', 'MCP do Comercial desligado.');
  end if;
  if v_eu is null or not coalesce(crm.eh_comercial(), false) then
    return jsonb_build_object('ok', false, 'msg', 'Sem acesso ao Comercial.');
  end if;
  if length(btrim(coalesce(p_nome, ''))) not between 1 and 60 then
    return jsonb_build_object('ok', false, 'msg', 'Dê um nome ao token (até 60 caracteres).');
  end if;
  v_esc := array(select distinct e from unnest(coalesce(p_escopos, array['ler'])) e where e is not null order by 1);
  if cardinality(v_esc) = 0 or not (v_esc <@ array['ler', 'operar']::text[]) then
    return jsonb_build_object('ok', false, 'msg', 'Escopo inválido: use ler e/ou operar.');
  end if;
  if not ('ler' = any(v_esc)) then v_esc := array['ler'] || v_esc; end if;   -- operar sem ler não faz sentido
  if p_dias is null or p_dias not between 1 and 180 then
    return jsonb_build_object('ok', false, 'msg', 'Validade entre 1 e 180 dias.');
  end if;
  if (select count(*) from crm.mcp_token t where t.perfil_id = v_eu and t.cliente_id is null and t.revogado_em is null and t.expira_em > now()) >= 5 then
    return jsonb_build_object('ok', false, 'msg', 'Limite de 5 tokens ativos: revogue um antes.');
  end if;
  v_token := 'gpc_' || encode(extensions.gen_random_bytes(32), 'hex');
  v_hash  := encode(extensions.digest(v_token, 'sha256'), 'hex');
  v_exp   := now() + make_interval(days => p_dias);
  insert into crm.mcp_token (perfil_id, nome, prefixo, hash_sha256, escopos, expira_em)
  values (v_eu, btrim(p_nome), left(v_token, 12), v_hash, v_esc, v_exp)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'token', v_token, 'prefixo', left(v_token, 12),
                            'escopos', to_jsonb(v_esc), 'expiraEm', v_exp,
                            'msg', 'Copie agora: o token não aparece de novo.');
end
$function$;

-- ═══ Grants ════════════════════════════════════════════════════════════════════════════════════════════════════════
revoke all on function public.crm_mcp_sessao(uuid), public.crm_mcp_rpc(uuid, text, jsonb),
  public.crm_mcp_oauth_registrar(text, text[]), public.crm_mcp_oauth_cliente(uuid, text),
  public.crm_mcp_oauth_autorizar(uuid, text, text, text[]),
  public.crm_mcp_oauth_trocar(text, uuid, text, text, text, text, text),
  public.crm_mcp_oauth_renovar(text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.crm_mcp_sessao(uuid), public.crm_mcp_rpc(uuid, text, jsonb),
  public.crm_mcp_oauth_registrar(text, text[]), public.crm_mcp_oauth_trocar(text, uuid, text, text, text, text, text),
  public.crm_mcp_oauth_renovar(text, uuid, text, text, text)
  to service_role;
grant execute on function public.crm_mcp_oauth_cliente(uuid, text), public.crm_mcp_oauth_autorizar(uuid, text, text, text[])
  to authenticated;

do $p$
declare v text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'crm_mcp_oauth%' or p.proname in ('crm_mcp_rpc', 'crm_mcp_sessao', 'crm_mcp_criar_token'))
     and (has_function_privilege('anon', p.oid, 'execute')
          or (p.proname in ('crm_mcp_rpc', 'crm_mcp_sessao', 'crm_mcp_oauth_registrar', 'crm_mcp_oauth_trocar', 'crm_mcp_oauth_renovar')
              and has_function_privilege('authenticated', p.oid, 'execute')));
  if v is not null then raise exception '20261008mcp: grant indevido: %', v; end if;
end
$p$;
