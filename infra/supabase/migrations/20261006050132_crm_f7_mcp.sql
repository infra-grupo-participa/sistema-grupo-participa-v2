-- 20261006e: F7 do Comercial — MCP (conectar o CRM ao Claude): token pessoal hasheado, escopo, revogação, uso/limite,
--            canal 'mcp' no crm.log e 2 RPCs de leitura agregada (resumo do funil, desempenho).
--
-- STATUS: APLICADA em produção em 06/10/2026 — versão 20261006050132 (nome crm_f7_mcp) em supabase_migrations.schema_migrations;
-- md5(array_to_string(statements, E'\n')) gravado = 53b57aa0c1e5382bd18b50e7a4ddeb39 (corpo deste arquivo da linha
-- "set local lock_timeout" até o fim do bloco $confere$; comentários de cabeçalho/rodapé não foram enviados).
-- Ensaio: 20261006050132_ensaio.sql (35/35 OK) + ensaio final do corpo exato em begin … rollback (OK, nada persistiu).
-- Provas pós-aplicação: mcp_ligado=false; 0 tokens; 0 chamadas; nenhuma função crm/crm_* executável por anon/PUBLIC;
-- crm_mcp_autenticar ACL {postgres,service_role} (authenticated sem execute); tg_log md5 c31d619c… com gp_canal, ACL só
-- postgres, 40 triggers de log intactos e ativos; crm_desempenho com JWT real (gestor ok, vendedor ok, fora do comercial
-- 42501) em rollback. Medidas e decisões: 20261006050132.explain.md.
-- Desenho: docs/projetos/comercial/backend-arquitetura.md §5.9 e §6 (F7), com UMA mudança de decisão (ver explain.md §1):
-- o MCP NÃO usa service role para agir nem núcleos crm._* com p_autor. Ele chama as MESMAS RPCs public.crm_* da tela com
-- um JWT do próprio usuário (curto, assinado no servidor Next). RLS, guardas, escrita_ligada e mensagens são as da tela.
-- O service role só entra para AUTENTICAR o token (public.crm_mcp_autenticar, executável só por service_role).
-- Servidor: web/app/api/mcp/route.ts. Como conectar: docs/projetos/comercial/mcp.md.
--
-- O QUE FAZ
--   1. crm.mcp_token: token pessoal por perfil. Guardado SÓ o sha-256 (hex); o texto aparece 1 vez na criação.
--      Escopos: 'ler' (sempre) e 'operar' (criar atividade, nota, mover etapa). Validade 1–180 dias, máx. 5 ativos por
--      perfil. Revogar = carimbar revogado_em/revogado_por (nunca apagar).
--   2. crm.mcp_chamada: 1 linha por chamada de ferramenta (auditoria + limite de 60/min por token).
--   3. public.crm_mcp_criar_token / crm_mcp_tokens / crm_mcp_revogar_token (authenticated, guarda eh_comercial, o
--      próprio; gestor lista e revoga de todos). public.crm_mcp_autenticar (só service_role): hash → perfil, papel,
--      escopos; recusa com mcp_ligado=false, token revogado/expirado, perfil inativo/fora do comercial/fora do domínio,
--      e acima de 60 chamadas/min.
--   4. crm.tg_log (F0) recriado A PARTIR DO CORPO VIVO (md5 conferido na guarda) com UMA linha a mais: canal 'mcp' quando
--      o JWT traz a claim gp_canal='mcp' (só o servidor do MCP assina essa claim). Assim todo write feito pelo Claude sai
--      no registro como autor_tipo='mcp', autor = o dono do token. Nada mais muda no tg_log.
--   5. public.crm_funil_resumo(p_funil) e public.crm_desempenho(p_desde, p_ate): SECURITY INVOKER + RLS (vendedor vê os
--      seus + sem dono, gestor tudo — a mesma régua das policies da F1). Agregam no banco (nada de puxar 2.000 linhas
--      para contar no servidor). crm_desempenho é o "desempenho(periodo)" previsto no §7 da arquitetura.
--   6. NÃO liga mcp_ligado (continua false: o MCP recusa tudo até o Arthur ligar).
--
-- AS 5 PERGUNTAS (números em 20261006e.explain.md)
--   escala: tokens = dezenas (5 por perfil × ~45 perfis). mcp_chamada cresce 1 linha por chamada (≤ 60/min/token);
--     limite lê só o último minuto do token (mcp_chamada_token_idx). Expurgo: linhas > 180 dias (bloco no fim, à mão).
--     crm_funil_resumo agrega só negócios ABERTOS do funil (negocio_funil_aberto_idx) + fechados 30 d do funil;
--     crm_desempenho lê abertos + criados/fechados no período (período ≤ 366 dias), medido com 30 mil negócios.
--   índice: token por hash (unique), chamada por (token_id, em desc), negócio por negocio_funil_aberto_idx /
--     negocio_fechado_idx / negocio_criado_idx, atividade por atividade_concluida_idx / atividade_dono_aberta_idx.
--   frequência: só quando o Claude chama (humano conversando). Sem cron.
--   repetição: cada ferramenta = 1 RPC (resumo do funil e desempenho já vêm agregados).
--   reversão: crm.config.mcp_ligado=false recusa TODO token em ~10 s (sem deploy); revogar token; escrita continua
--     presa a escrita_ligada. Bloco REVERSÃO no fim.
--
-- PREMISSAS (guarda aborta se faltar): F1 aplicada (crm.negocio, crm.atividade, crm.funil, crm.etapa_funil, helpers);
--   crm.config.mcp_ligado existe e é false; crm.tg_log com o corpo vivo de 06/10/2026 (md5 abaixo); nenhuma tabela/RPC
--   do MCP ainda; pgcrypto em extensions (gen_random_bytes, digest). TOLERA a F2 (20261005t) aplicada ou não: não lê
--   nem altera nada dela (as ferramentas de escrita do MCP só funcionam depois da F2 + escrita_ligada).

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_falta text;
begin
  select string_agg(t, ', ') into v_falta
    from unnest(array['crm.config','crm.vendedor','crm.log','crm.funil','crm.etapa_funil','crm.negocio','crm.atividade']) t
   where to_regclass(t) is null;
  if v_falta is not null then raise exception '20261006e: F1 não aplicada (faltam: %)', v_falta; end if;
  if to_regprocedure('crm.tg_log()') is null or to_regprocedure('crm.eh_gestor()') is null
     or to_regprocedure('crm.eh_vendedor()') is null or to_regprocedure('crm.eh_comercial()') is null
     or to_regprocedure('crm.exige_comercial()') is null or to_regprocedure('auth.jwt()') is null then
    raise exception '20261006e: helpers da F0/F1 ausentes';
  end if;
  if md5(pg_get_functiondef('crm.tg_log()'::regprocedure)) <> '450774b246813145998822a8b8102e8d' then
    raise exception '20261006e: crm.tg_log mudou desde a leitura de 06/10/2026: refazer a seção 4 a partir do corpo vivo';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                    and column_name = 'mcp_ligado') then
    raise exception '20261006e: crm.config sem mcp_ligado';
  end if;
  if coalesce((select c.mcp_ligado from crm.config c), true) then
    raise exception '20261006e: crm.config.mcp_ligado deveria estar false';
  end if;
  if to_regclass('crm.mcp_token') is not null or to_regclass('crm.mcp_chamada') is not null
     or exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                   and p.proname in ('crm_mcp_criar_token','crm_mcp_tokens','crm_mcp_revogar_token','crm_mcp_autenticar',
                                     'crm_funil_resumo','crm_desempenho')) then
    raise exception '20261006e: objetos do MCP já existem (migration já aplicada?)';
  end if;
  if to_regprocedure('extensions.gen_random_bytes(integer)') is null or to_regprocedure('extensions.digest(text,text)') is null then
    raise exception '20261006e: pgcrypto não está em extensions';
  end if;
end
$guarda$;

-- ─── 1. Tabelas ──────────────────────────────────────────────────────────────────────────────────────────────────────
create table crm.mcp_token (
  id            uuid primary key default gen_random_uuid(),
  perfil_id     uuid not null references public.perfis(id) on delete restrict,
  nome          text not null check (length(btrim(nome)) between 1 and 60),       -- "Claude do notebook"
  prefixo       text not null check (prefixo ~ '^gpc_[0-9a-f]{8}$'),             -- o que a tela mostra
  hash_sha256   text not null unique check (hash_sha256 ~ '^[0-9a-f]{64}$'),     -- sha-256 hex do token inteiro
  escopos       text[] not null check (escopos <@ array['ler', 'operar']::text[] and 'ler' = any(escopos)),
  criado_em     timestamptz not null default now(),
  expira_em     timestamptz not null,
  revogado_em   timestamptz,
  revogado_por  uuid references public.perfis(id) on delete restrict,
  ultimo_uso_em timestamptz,
  check (expira_em > criado_em and expira_em <= criado_em + interval '180 days'),
  check ((revogado_em is null) = (revogado_por is null))
);
create index mcp_token_perfil_idx on crm.mcp_token (perfil_id, criado_em desc);

create table crm.mcp_chamada (
  id         bigint generated always as identity primary key,
  token_id   uuid not null references crm.mcp_token(id) on delete restrict,
  perfil_id  uuid not null,
  ferramenta text not null check (ferramenta ~ '^[a-z_]{3,60}$'),
  em         timestamptz not null default now()
);
create index mcp_chamada_token_idx on crm.mcp_chamada (token_id, em desc);
create index mcp_chamada_em_idx    on crm.mcp_chamada (em);

-- RLS ligada, sem policy e sem grant: só as funções SECURITY DEFINER abaixo tocam.
alter table crm.mcp_token enable row level security;
alter table crm.mcp_chamada enable row level security;
revoke all on crm.mcp_token, crm.mcp_chamada from public, anon, authenticated;
revoke all on sequence crm.mcp_chamada_id_seq from public, anon, authenticated;

-- ─── 2. Papel de um perfil QUALQUER (mesma régua de crm.eh_gestor/eh_vendedor, sem auth.uid()) ───────────────────────
-- Uso interno do crm_mcp_autenticar (que roda como service_role, sem JWT de usuário). Sem grant para ninguém.
create function crm.mcp_papel(p_perfil uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
           when pf.status = 'ativo'
                and (pf.cargo in ('dev', 'admin') or (pf.cargo = 'gestor' and 'comercial' = any(coalesce(pf.areas, '{}'))))
             then 'gestor'
           when pf.status = 'ativo' and coalesce(v.ativo, false)
                and 'comercial' = any(coalesce(pf.areas, '{}')) and 'comercial.vender' = any(coalesce(pf.funcoes, '{}'))
             then 'vendedor'
         end
    from public.perfis pf
    left join crm.vendedor v on v.perfil_id = pf.id
   where pf.id = p_perfil
     and lower(btrim(coalesce(pf.email, ''))) like '%@advmais.com';
$$;

-- ─── 3. RPCs de token ────────────────────────────────────────────────────────────────────────────────────────────────
-- Cria token do PRÓPRIO usuário. O texto volta 1 vez; no banco fica só o hash.
create function public.crm_mcp_criar_token(p_nome text, p_escopos text[] default array['ler'], p_dias int default 90)
returns jsonb
language plpgsql security definer set search_path = '' as $$
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
  if (select count(*) from crm.mcp_token t where t.perfil_id = v_eu and t.revogado_em is null and t.expira_em > now()) >= 5 then
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
$$;

-- Lista tokens (nunca o hash). Vendedor: os seus. Gestor: todos, com o nome do dono.
create function public.crm_mcp_tokens() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_g boolean := coalesce(crm.eh_gestor(), false); v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'nome', t.nome, 'prefixo', t.prefixo, 'escopos', to_jsonb(t.escopos), 'perfilId', t.perfil_id,
           'perfilNome', coalesce(pf.nome, ''), 'criadoEm', t.criado_em, 'expiraEm', t.expira_em,
           'revogadoEm', t.revogado_em, 'ultimoUsoEm', t.ultimo_uso_em,
           'ativo', t.revogado_em is null and t.expira_em > now()) order by t.criado_em desc), '[]'::jsonb)
    into v
    from (select * from crm.mcp_token x where v_g or x.perfil_id = v_eu order by x.criado_em desc limit 200) t
    left join public.perfis pf on pf.id = t.perfil_id;
  return v;
end
$$;

-- Revoga: o próprio ou o gestor. Funciona MESMO com mcp_ligado=false (revogar nunca pode depender do kill-switch).
create function public.crm_mcp_revogar_token(p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); t crm.mcp_token%rowtype;
begin
  if v_eu is null or not coalesce(crm.eh_comercial(), false) then
    return jsonb_build_object('ok', false, 'msg', 'Sem acesso ao Comercial.');
  end if;
  select * into t from crm.mcp_token x where x.id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Token não encontrado.'); end if;
  if not (t.perfil_id = v_eu or coalesce(crm.eh_gestor(), false)) then
    return jsonb_build_object('ok', false, 'msg', 'Este token não é seu.');
  end if;
  if t.revogado_em is not null then return jsonb_build_object('ok', true, 'msg', 'Já estava revogado.'); end if;
  update crm.mcp_token x set revogado_em = now(), revogado_por = v_eu where x.id = p_id;
  return jsonb_build_object('ok', true);
end
$$;

-- Autentica o token (hash sha-256 hex calculado no servidor; o texto do token nunca chega ao banco nesta chamada).
-- SÓ service_role. p_ferramenta não nulo = chamada de ferramenta: conta no limite e grava em crm.mcp_chamada.
create function public.crm_mcp_autenticar(p_hash text, p_ferramenta text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t crm.mcp_token%rowtype; v_papel text; v_email text; v_n int;
begin
  if not coalesce((select c.mcp_ligado from crm.config c), false) then
    return jsonb_build_object('ok', false, 'codigo', 'desligado', 'msg', 'MCP do Comercial desligado.');
  end if;
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'codigo', 'token', 'msg', 'Token inválido, revogado ou expirado.');
  end if;
  select * into t from crm.mcp_token x where x.hash_sha256 = p_hash;
  if not found or t.revogado_em is not null or t.expira_em <= now() then
    return jsonb_build_object('ok', false, 'codigo', 'token', 'msg', 'Token inválido, revogado ou expirado.');
  end if;
  v_papel := crm.mcp_papel(t.perfil_id);
  select lower(btrim(pf.email)) into v_email from public.perfis pf where pf.id = t.perfil_id;
  if v_papel is null or v_email is null then
    return jsonb_build_object('ok', false, 'codigo', 'perfil', 'msg', 'Perfil sem acesso ao Comercial.');
  end if;
  if p_ferramenta is not null then
    if p_ferramenta !~ '^[a-z_]{3,60}$' then
      return jsonb_build_object('ok', false, 'codigo', 'ferramenta', 'msg', 'Ferramenta inválida.');
    end if;
    select count(*) into v_n from crm.mcp_chamada c where c.token_id = t.id and c.em > now() - interval '1 minute';
    if v_n >= 60 then
      return jsonb_build_object('ok', false, 'codigo', 'limite', 'msg', 'Limite de 60 chamadas por minuto. Tente em instantes.');
    end if;
    insert into crm.mcp_chamada (token_id, perfil_id, ferramenta) values (t.id, t.perfil_id, p_ferramenta);
  end if;
  -- carimbo de uso no máximo 1×/min (não reescreve a linha a cada chamada)
  update crm.mcp_token x set ultimo_uso_em = now()
   where x.id = t.id and (x.ultimo_uso_em is null or x.ultimo_uso_em < now() - interval '1 minute');
  return jsonb_build_object('ok', true, 'tokenId', t.id, 'perfilId', t.perfil_id, 'email', v_email, 'papel', v_papel,
                            'escopos', to_jsonb(t.escopos), 'expiraEm', t.expira_em);
end
$$;

-- ─── 4. crm.tg_log: corpo VIVO de 06/10/2026 + canal 'mcp' pela claim do JWT ─────────────────────────────────────────
-- Única mudança: na linha de v_canal, entre crm.canal e o padrão, entra "mcp" quando auth.jwt()->>'gp_canal' = 'mcp'
-- e há auth.uid(). A claim só existe em JWT assinado pelo servidor do MCP (o usuário não consegue pôr claim no JWT da
-- sessão normal: user_metadata vai em outra chave). Mesma assinatura → create or replace mantém o ACL (postgres só).
create or replace function crm.tg_log()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_ent    text := tg_argv[0];
  v_col_id text := coalesce(tg_argv[1], 'id');
  v_old    jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new    jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row    jsonb;
  v_ign    text[] := array['atualizado_em', 'etapa_desde', 'ultima_interacao_em'];
  v_mud    jsonb := '[]';
  v_acao   text;
  v_autor  uuid;
  v_canal  text;
  v_resumo text;
  k        text;
begin
  v_row := coalesce(v_new, v_old);
  v_ign := v_ign || coalesce((select array_agg(a.attname::text) from pg_catalog.pg_attribute a
                               where a.attrelid = tg_relid and a.attgenerated <> ''), '{}');
  if tg_op = 'UPDATE' then
    for k in select jsonb_object_keys(v_new) loop
      continue when k = any(v_ign);
      if (v_new -> k) is distinct from (v_old -> k) then
        v_mud := v_mud || jsonb_build_array(jsonb_build_object('campo', k, 'de', v_old -> k, 'para', v_new -> k));
      end if;
    end loop;
    if jsonb_array_length(v_mud) = 0 then return null; end if;   -- só coluna ignorada mudou
  end if;
  v_acao := case
    when tg_op = 'INSERT' then 'criou'
    when tg_op = 'DELETE' then 'excluiu'
    when (v_new ->> 'status') is distinct from (v_old ->> 'status') and v_new ->> 'status' = 'perdido' then 'marcou_perdido'
    when (v_new ->> 'status') is distinct from (v_old ->> 'status') and v_new ->> 'status' = 'ganho' then 'marcou_ganho'
    when v_new ? 'etapa_id' and (v_new -> 'etapa_id') is distinct from (v_old -> 'etapa_id') then 'moveu_etapa'
    when v_new ? 'dono_id' and (v_new -> 'dono_id') is distinct from (v_old -> 'dono_id') then 'trocou_dono'
    when v_new ? 'arquivado_em' and v_old ->> 'arquivado_em' is null and v_new ->> 'arquivado_em' is not null then 'arquivou'
    when v_new ? 'concluida_em' and v_old ->> 'concluida_em' is null and v_new ->> 'concluida_em' is not null then 'concluiu'
    else 'editou' end;
  v_autor  := coalesce(auth.uid(), nullif(current_setting('crm.autor', true), '')::uuid);
  v_canal  := coalesce(nullif(current_setting('crm.canal', true), ''),
                       case when auth.uid() is not null and (auth.jwt() ->> 'gp_canal') = 'mcp' then 'mcp' end,
                       case when auth.uid() is null then 'sistema' else 'tela' end);
  v_resumo := nullif(current_setting('crm.resumo', true), '');
  if v_resumo is not null then perform set_config('crm.resumo', '', true); end if;
  insert into crm.log (autor_id, autor_tipo, canal, acao, entidade, entidade_id, pessoa_id, resumo, mudancas, dados)
  values (v_autor,
          case when v_canal = 'mcp' then 'mcp'
               when v_autor is not null then 'pessoa'
               when v_canal in ('hotmart', 'whatsapp', 'activecampaign', 'sendflow', 'respondi', 'clint_import') then 'integracao'
               else 'sistema' end,
          v_canal, v_acao, v_ent, coalesce(v_row ->> v_col_id, '?'),
          case when v_row ? 'pessoa_id' then nullif(v_row ->> 'pessoa_id', '')::uuid end,
          coalesce(v_resumo, initcap(v_acao) || ' ' || v_ent || ' ' || coalesce(v_row ->> v_col_id, '?')),
          v_mud,
          case when v_acao = 'moveu_etapa' then jsonb_build_object('etapa_de', v_old -> 'etapa_id', 'etapa_para', v_new -> 'etapa_id')
               else '{}'::jsonb end);
  return null;
end
$function$;

-- ─── 5. Leitura agregada (SECURITY INVOKER + RLS da F1) ──────────────────────────────────────────────────────────────
-- Resumo de UM funil: por etapa ativa, negócios abertos visíveis (quantidade, valor, sem dono, estourados no SLA crítico)
-- + ganhos/perdidos dos últimos 30 dias. Vendedor enxerga só o que a policy negocio_ler deixa (os seus + sem dono).
create function public.crm_funil_resumo(p_funil uuid) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v jsonb;
begin
  perform crm.exige_comercial();
  if p_funil is null then raise exception 'Informe o funil.' using errcode = '22023'; end if;
  select jsonb_build_object(
           'funilId', f.id, 'nome', f.nome, 'produto', f.linha, 'tipo', f.tipo, 'ativo', f.ativo,
           'etapas', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'etapaId', e.id, 'nome', e.nome, 'papel', e.papel, 'ordem', e.ordem,
                      'abertos', coalesce(a.qtd, 0), 'valorAberto', coalesce(a.valor, 0),
                      'semDono', coalesce(a.sem_dono, 0), 'estouradosSla', coalesce(a.estourados, 0)) order by e.ordem)
               from crm.etapa_funil e
               left join (select n.etapa_id, count(*) qtd, sum(n.valor) valor,
                                 count(*) filter (where n.dono_id is null) sem_dono,
                                 count(*) filter (where e2.sla_critico_min is not null
                                                    and n.etapa_desde < now() - make_interval(mins => e2.sla_critico_min)) estourados
                            from crm.negocio n
                            join crm.etapa_funil e2 on e2.id = n.etapa_id
                           where n.funil_id = f.id and n.status = 'aberto'
                           group by n.etapa_id) a on a.etapa_id = e.id
              where e.funil_id = f.id and e.arquivada_em is null), '[]'::jsonb),
           'ganhos30d', (select count(*) from crm.negocio n
                          where n.funil_id = f.id and n.status = 'ganho' and n.fechado_em >= now() - interval '30 days'),
           'valorGanho30d', (select coalesce(sum(n.valor), 0) from crm.negocio n
                              where n.funil_id = f.id and n.status = 'ganho' and n.fechado_em >= now() - interval '30 days'),
           'perdidos30d', (select count(*) from crm.negocio n
                            where n.funil_id = f.id and n.status = 'perdido' and n.fechado_em >= now() - interval '30 days'))
    into v
    from crm.funil f where f.id = p_funil;
  if v is null then raise exception 'Funil não encontrado.' using errcode = 'P0002'; end if;
  return v;
end
$$;

-- Desempenho por dono no período [p_desde, p_ate) (padrão: hoje em São Paulo até agora; máx. 366 dias).
-- Vendedor: só a própria linha (+ "sem dono"); gestor: o time inteiro. Taxa = ganhos / (ganhos + perdidos) no período.
create function public.crm_desempenho(p_desde timestamptz default null, p_ate timestamptz default null) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_desde timestamptz := coalesce(p_desde, (date_trunc('day', now() at time zone 'America/Sao_Paulo')) at time zone 'America/Sao_Paulo');
  v_ate   timestamptz := coalesce(p_ate, now());
  v jsonb;
begin
  perform crm.exige_comercial();
  if v_ate <= v_desde or v_ate - v_desde > interval '366 days' then
    raise exception 'Período inválido (início antes do fim, até 366 dias).' using errcode = '22023';
  end if;
  -- dono nulo vira a chave zero só para o FULL JOIN (FULL JOIN não aceita "is not distinct from")
  with neg as (
    select coalesce(n.dono_id, '00000000-0000-0000-0000-000000000000'::uuid) dono_k,
           count(*) filter (where n.status = 'aberto') abertos,
           count(*) filter (where n.criado_em >= v_desde and n.criado_em < v_ate) criados,
           count(*) filter (where n.status = 'ganho' and n.fechado_em >= v_desde and n.fechado_em < v_ate) ganhos,
           coalesce(sum(n.valor) filter (where n.status = 'ganho' and n.fechado_em >= v_desde and n.fechado_em < v_ate), 0) valor_ganho,
           count(*) filter (where n.status = 'perdido' and n.fechado_em >= v_desde and n.fechado_em < v_ate) perdidos
      from crm.negocio n
     where n.status = 'aberto'
        or (n.criado_em >= v_desde and n.criado_em < v_ate)
        or (n.status <> 'aberto' and n.fechado_em >= v_desde and n.fechado_em < v_ate)
     group by 1),
  atv as (
    select coalesce(a.dono_id, '00000000-0000-0000-0000-000000000000'::uuid) dono_k,
           count(*) filter (where a.concluida_em >= v_desde and a.concluida_em < v_ate) concluidas,
           count(*) filter (where a.concluida_em is null and not a.cancelada and a.vence_em < now()) atrasadas
      from crm.atividade a
     where (a.concluida_em >= v_desde and a.concluida_em < v_ate) or a.concluida_em is null
     group by 1),
  junta as (
    select nullif(coalesce(neg.dono_k, atv.dono_k), '00000000-0000-0000-0000-000000000000'::uuid) dono_id,
           coalesce(neg.abertos, 0) abertos, coalesce(neg.criados, 0) criados, coalesce(neg.ganhos, 0) ganhos,
           coalesce(neg.valor_ganho, 0) valor_ganho, coalesce(neg.perdidos, 0) perdidos,
           coalesce(atv.concluidas, 0) concluidas, coalesce(atv.atrasadas, 0) atrasadas
      from neg full join atv on atv.dono_k = neg.dono_k)
  select jsonb_build_object(
           'desde', v_desde, 'ate', v_ate,
           'porDono', coalesce(jsonb_agg(jsonb_build_object(
                        'donoId', j.dono_id,
                        'nome', case when j.dono_id is null then 'Sem dono'
                                     else coalesce((select pf.nome from public.perfis pf where pf.id = j.dono_id), '') end,
                        'abertos', j.abertos, 'criados', j.criados, 'ganhos', j.ganhos, 'valorGanho', j.valor_ganho,
                        'perdidos', j.perdidos,
                        'taxaConversao', case when j.ganhos + j.perdidos > 0
                                              then round(j.ganhos::numeric / (j.ganhos + j.perdidos), 4) end,
                        'atividadesConcluidas', j.concluidas, 'atividadesAtrasadas', j.atrasadas)
                      order by j.valor_ganho desc, j.ganhos desc, j.dono_id nulls last), '[]'::jsonb),
           'total', jsonb_build_object('abertos', coalesce(sum(j.abertos), 0), 'criados', coalesce(sum(j.criados), 0),
                                       'ganhos', coalesce(sum(j.ganhos), 0), 'valorGanho', coalesce(sum(j.valor_ganho), 0),
                                       'perdidos', coalesce(sum(j.perdidos), 0),
                                       'atividadesConcluidas', coalesce(sum(j.concluidas), 0),
                                       'atividadesAtrasadas', coalesce(sum(j.atrasadas), 0)))
    into v
    from junta j;
  return v;
end
$$;

-- ─── 6. Grants e conferência ─────────────────────────────────────────────────────────────────────────────────────────
-- Supabase dá EXECUTE a anon/authenticated/service_role em função nova de public por default privileges: revogar tudo
-- e conceder só o necessário.
revoke all on function crm.mcp_papel(uuid) from public, anon, authenticated;
revoke all on function public.crm_mcp_criar_token(text, text[], int), public.crm_mcp_tokens(),
                       public.crm_mcp_revogar_token(uuid), public.crm_mcp_autenticar(text, text),
                       public.crm_funil_resumo(uuid), public.crm_desempenho(timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.crm_mcp_criar_token(text, text[], int), public.crm_mcp_tokens(),
                          public.crm_mcp_revogar_token(uuid), public.crm_funil_resumo(uuid),
                          public.crm_desempenho(timestamptz, timestamptz)
  to authenticated;
grant execute on function public.crm_mcp_autenticar(text, text) to service_role;

do $confere$
declare v_aberto text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where (p.pronamespace = 'crm'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%'))
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  if v_aberto is not null then raise exception '20261006e: executável por anon/PUBLIC: %', v_aberto; end if;
  if has_function_privilege('authenticated', 'public.crm_mcp_autenticar(text,text)', 'execute')
     or not has_function_privilege('service_role', 'public.crm_mcp_autenticar(text,text)', 'execute')
     or has_function_privilege('authenticated', 'crm.mcp_papel(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_mcp_criar_token(text,text[],integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_desempenho(timestamptz,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'crm.tg_log()', 'execute') then
    raise exception '20261006e: grants das funções fora do esperado';
  end if;
  select string_agg(table_name || ':' || grantee || ':' || privilege_type, ', ') into v_aberto
    from information_schema.role_table_grants
   where table_schema = 'crm' and table_name in ('mcp_token', 'mcp_chamada')
     and grantee in ('anon', 'authenticated', 'PUBLIC');
  if v_aberto is not null then raise exception '20261006e: grant indevido nas tabelas do MCP: %', v_aberto; end if;
  if exists (select 1 from pg_class c where c.oid in ('crm.mcp_token'::regclass, 'crm.mcp_chamada'::regclass) and not c.relrowsecurity) then
    raise exception '20261006e: tabela do MCP sem RLS';
  end if;
  if coalesce((select c.mcp_ligado from crm.config c), true) then
    raise exception '20261006e: mcp_ligado não pode ser ligado aqui';
  end if;
end
$confere$;

-- ═══ LIGAR (o Arthur, depois do ok, em chamada separada; desliga do mesmo jeito com false) ═══════════════════════════
-- update crm.config set mcp_ligado = true;
-- Escrita pelo MCP exige também a F2 (20261005t) aplicada e crm.config.escrita_ligada = true.

-- ═══ EXPURGO (à mão, quando crm.mcp_chamada passar de ~1 milhão de linhas; manual §10: guardar antes se precisar) ═════
-- delete from crm.mcp_chamada where em < now() - interval '180 days';

-- ═══ REVERSÃO (numa transação) ══════════════════════════════════════════════════════════════════════════════════════
-- update crm.config set mcp_ligado = false;           -- desliga em ~10 s, sem deploy (preferir isto)
-- begin;
-- set local lock_timeout = '3s';
-- drop function public.crm_mcp_criar_token(text, text[], int), public.crm_mcp_tokens(), public.crm_mcp_revogar_token(uuid),
--   public.crm_mcp_autenticar(text, text), public.crm_funil_resumo(uuid), public.crm_desempenho(timestamptz, timestamptz),
--   crm.mcp_papel(uuid);
-- drop table crm.mcp_chamada, crm.mcp_token;           -- exportar antes se houver uso real (auditoria)
-- -- crm.tg_log: recriar com o corpo de 20261005r (sem a linha do gp_canal). Linhas já gravadas com canal 'mcp' ficam.
-- commit;
