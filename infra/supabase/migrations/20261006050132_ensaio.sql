-- 20261006050132 (antes 20261006e): ENSAIO da F7 (MCP do Comercial). NÃO aplica nada: cada parte termina em ROLLBACK.
-- Rodado em produção (mbvybujpkwuorhtdzcde) em 06/10/2026 pelo execute_sql, como postgres, cada parte numa chamada.
-- Resultado: PARTE A 35/35 OK; PARTE B números no .explain.md §4; PARTE C nada persistiu. Para rodar no execute_sql,
-- as linhas só de comentário podem ser removidas (mesmo SQL).
--   PARTE A: o corpo INTEIRO da migration (copiado sem mudança) + provas funcionais, de grant e de RLS com JWT real
--            (gestor = admin real; vendedores reais A = mp e B = ro; operador real fora do comercial — hoje não há
--            visualizador ATIVO). Só booleanos/contagens saem.
--   PARTE B: massa sintética 10× (30 mil negócios, 60 mil atividades, 300 tokens, 18 mil chamadas; triggers desligados SÓ
--            na carga, por session_replication_role = replica local à transação) + medição 2× das RPCs novas inteiras,
--            como authenticated + JWT real, e planos das consultas internas.
--   PARTE C: conferência separada de que nada persistiu.
-- Esperado: NENHUMA linha começando com "ERRADO". Dados fictícios: nomes "Ensaio …", transação "ENSAIO-F7-…".
-- Sequência com F2–F6 (20261005t, 20261006a–d, não aplicadas): nenhuma delas recria crm.tg_log nem cria objeto com nome
-- do MCP; a guarda da F2 só exige "≥ 20 RPCs crm_*" e ausência de crm_mover_etapa. A F7 tolera qualquer ordem; se alguém
-- recriar crm.tg_log antes, a guarda de md5 da F7 aborta (de propósito: refazer a seção 4 a partir do corpo vivo).
--
-- ═══ PARTE A ═════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (linha)
  values (case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, ''));
$$;

-- ═══ CORPO DA MIGRATION (copiado sem mudança de 20261006e_crm_f7_mcp.sql; mudou a migration, gerar de novo) ═══
-- 20261006e: F7 do Comercial — MCP (conectar o CRM ao Claude): token pessoal hasheado, escopo, revogação, uso/limite,
--            canal 'mcp' no crm.log e 2 RPCs de leitura agregada (resumo do funil, desempenho).
--
-- STATUS: NÃO APLICADA — aguardando ok do Arthur. Ensaio: 20261006e_ensaio.sql (begin … rollback). Medidas, decisões e
-- planos: 20261006e.explain.md. Ao aplicar: renomear o arquivo para a versão gravada em supabase_migrations.schema_migrations.
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

-- ═══ PROVAS ═════════════════════════════════════════════════════════════════════════════════════════════════════
do $t$
declare
  v_admin uuid; v_visu uuid; v_a uuid; v_b uuid;
  r jsonb; v_tok text; v_tok2 text; v_hash2 text; v_id uuid; v_id2 uuid; v_n int; v_err text; i int;
  ag uuid; f uuid; e1 uuid; e2 uuid; eg uuid; p1 uuid; p2 uuid; p3 uuid; v_mot text;
  claims_a text; claims_b text; claims_g text; claims_v text;
begin
  select id into v_admin from public.perfis where cargo = 'admin' and status = 'ativo' and lower(email) like '%@advmais.com' order by criado_em limit 1;
  -- "fora do comercial": não há visualizador ATIVO hoje (20 pendentes); usa o operador ativo que não é vendedor
  select id into v_visu from public.perfis p where p.status = 'ativo' and p.cargo not in ('dev', 'admin') and lower(p.email) like '%@advmais.com'
     and not exists (select 1 from crm.vendedor v where v.perfil_id = p.id) order by p.criado_em limit 1;
  select perfil_id into v_a from crm.vendedor where sigla = 'mp';
  select perfil_id into v_b from crm.vendedor where sigla = 'ro';
  perform pg_temp.ok('0.perfis', v_admin is not null and v_visu is not null and v_a is not null and v_b is not null,
                     'gestor (admin real), equipe fora do comercial (operador real sem vendedor), vendedores reais A (mp) e B (ro)');
  claims_a := json_build_object('sub', v_a, 'role', 'authenticated')::text;
  claims_b := json_build_object('sub', v_b, 'role', 'authenticated')::text;
  claims_g := json_build_object('sub', v_admin, 'role', 'authenticated')::text;
  claims_v := json_build_object('sub', v_visu, 'role', 'authenticated')::text;
  perform pg_temp.ok('0.tg_log', md5(pg_get_functiondef('crm.tg_log()'::regprocedure)) <> '450774b246813145998822a8b8102e8d'
                     and pg_get_functiondef('crm.tg_log()'::regprocedure) like '%gp_canal%', 'tg_log recriado com a claim gp_canal');
  perform pg_temp.ok('0.acl_tg_log', (select proacl::text from pg_proc where oid = 'crm.tg_log()'::regprocedure) = '{postgres=X/postgres}',
                     'create or replace manteve o ACL do tg_log');

  -- 1. kill-switch desligado (estado de nascença)
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated; r := public.crm_mcp_criar_token('Ensaio', array['ler'], 30); reset role;
  perform pg_temp.ok('1.desligado_criar', r->>'ok' = 'false' and r->>'msg' = 'MCP do Comercial desligado.', r::text);
  perform set_config('request.jwt.claims', '', true);
  set local role service_role; r := public.crm_mcp_autenticar(repeat('a', 64), 'crm_resumo_funil'); reset role;
  perform pg_temp.ok('1.desligado_auth', r->>'codigo' = 'desligado', r::text);
  update crm.config set mcp_ligado = true;

  -- 2. quem não é do comercial / anon / validações
  perform set_config('request.jwt.claims', claims_v, true);
  set local role authenticated; r := public.crm_mcp_criar_token('Ensaio', array['ler'], 30); reset role;
  perform pg_temp.ok('2.visualizador', r->>'ok' = 'false' and r->>'msg' = 'Sem acesso ao Comercial.', r::text);
  v_err := null;
  begin set local role anon; r := public.crm_mcp_criar_token('x', array['ler'], 1); reset role; v_err := 'executou';
  exception when insufficient_privilege then reset role; v_err := 'negado'; end;
  perform pg_temp.ok('2.anon', v_err = 'negado', 'anon não executa crm_mcp_criar_token');
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated;
  r := public.crm_mcp_criar_token('Ensaio', array['admin'], 30); v_err := r->>'msg';
  r := public.crm_mcp_criar_token('Ensaio', array['ler'], 0); v_err := v_err || ' | ' || (r->>'msg');
  r := public.crm_mcp_criar_token('  ', array['ler'], 30); v_err := v_err || ' | ' || (r->>'msg');
  reset role;
  perform pg_temp.ok('2.validacoes', v_err = 'Escopo inválido: use ler e/ou operar. | Validade entre 1 e 180 dias. | Dê um nome ao token (até 60 caracteres).', v_err);

  -- 3. criar (A, operar → ler+operar), hash guardado, texto não guardado
  set local role authenticated; r := public.crm_mcp_criar_token('Ensaio notebook', array['operar'], 30); reset role;
  v_tok := r->>'token'; v_id := (r->>'id')::uuid;
  perform pg_temp.ok('3.criar', r->>'ok' = 'true' and v_tok ~ '^gpc_[0-9a-f]{64}$' and r->'escopos' = '["ler","operar"]'::jsonb
                     and r->>'prefixo' = left(v_tok, 12), 'ok, token gpc_ + 64 hex, escopos [ler, operar], prefixo 12');
  perform pg_temp.ok('3.hash', (select hash_sha256 = encode(extensions.digest(v_tok, 'sha256'), 'hex') and perfil_id = v_a
                                  and expira_em between now() + interval '29 days' and now() + interval '31 days'
                                  from crm.mcp_token where id = v_id)
                     and not exists (select 1 from crm.mcp_token t where position(substr(v_tok, 13) in t::text) > 0),
                     'banco guarda só o sha-256; o texto do token não aparece em nenhuma coluna');
  v_err := null;
  begin set local role authenticated; perform count(*) from crm.mcp_token; reset role; v_err := 'leu';
  exception when insufficient_privilege then reset role; v_err := 'negado'; end;
  perform pg_temp.ok('3.tabela_fechada', v_err = 'negado', 'authenticated não lê crm.mcp_token direto');

  -- 4. limite de 5 ativos
  set local role authenticated;
  for i in 1..4 loop r := public.crm_mcp_criar_token('Ensaio ' || i, array['ler'], 10); end loop;
  v_tok2 := r->>'token'; v_id2 := (r->>'id')::uuid;
  r := public.crm_mcp_criar_token('Ensaio 6', array['ler'], 10);
  reset role;
  perform pg_temp.ok('4.limite5', r->>'msg' = 'Limite de 5 tokens ativos: revogue um antes.', r::text);

  -- 5. autenticar (service_role) e grants
  perform set_config('request.jwt.claims', '', true);
  set local role service_role; r := public.crm_mcp_autenticar(encode(extensions.digest(v_tok, 'sha256'), 'hex'), 'crm_resumo_funil'); reset role;
  perform pg_temp.ok('5.autenticar', r->>'ok' = 'true' and (r->>'perfilId')::uuid = v_a and r->>'papel' = 'vendedor'
                     and r->'escopos' = '["ler","operar"]'::jsonb and r->>'email' like '%@advmais.com'
                     and (select count(*) from crm.mcp_chamada where token_id = v_id) = 1
                     and (select ultimo_uso_em is not null from crm.mcp_token where id = v_id),
                     'vendedor A, escopos, 1 chamada gravada, ultimo_uso_em carimbado');
  perform set_config('request.jwt.claims', claims_a, true);
  v_err := null;
  begin set local role authenticated; r := public.crm_mcp_autenticar(repeat('a', 64), null); reset role; v_err := 'executou';
  exception when insufficient_privilege then reset role; v_err := 'negado'; end;
  perform pg_temp.ok('5.autenticar_so_service', v_err = 'negado', 'authenticated não executa crm_mcp_autenticar');
  set local role service_role;
  r := public.crm_mcp_autenticar(repeat('a', 64), null); v_err := r->>'codigo';
  r := public.crm_mcp_autenticar('nao-e-hash', null); v_err := v_err || ',' || (r->>'codigo');
  r := public.crm_mcp_autenticar(encode(extensions.digest(v_tok, 'sha256'), 'hex'), 'DROP TABLE'); v_err := v_err || ',' || (r->>'codigo');
  reset role;
  perform pg_temp.ok('5.recusas', v_err = 'token,token,ferramenta', v_err);

  -- 6. listar e revogar
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated; r := public.crm_mcp_revogar_token(v_id); v_n := jsonb_array_length(public.crm_mcp_tokens()); reset role;
  perform pg_temp.ok('6.b_nao_revoga_de_a', r->>'msg' = 'Este token não é seu.' and v_n = 0, r::text || ' / B lista ' || v_n);
  perform set_config('request.jwt.claims', claims_g, true);
  set local role authenticated; v_n := (select count(*) from jsonb_array_elements(public.crm_mcp_tokens()) x where (x->>'perfilId')::uuid = v_a); reset role;
  perform pg_temp.ok('6.gestor_lista', v_n = 5, 'gestor vê os 5 tokens de A');
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated;
  r := public.crm_mcp_tokens();
  v_err := (select string_agg(k, ',' order by k) from jsonb_object_keys(r->0) k);
  r := public.crm_mcp_revogar_token(v_id); v_err := v_err || ' | ' || (r->>'ok');
  r := public.crm_mcp_revogar_token(v_id); v_err := v_err || ' | ' || (r->>'msg');
  reset role;
  perform pg_temp.ok('6.revogar', v_err = 'ativo,criadoEm,escopos,expiraEm,id,nome,perfilId,perfilNome,prefixo,revogadoEm,ultimoUsoEm | true | Já estava revogado.', v_err);
  perform set_config('request.jwt.claims', '', true);
  set local role service_role; r := public.crm_mcp_autenticar(encode(extensions.digest(v_tok, 'sha256'), 'hex'), 'crm_resumo_funil'); reset role;
  perform pg_temp.ok('6.revogado_recusa', r->>'codigo' = 'token', r::text);

  -- 7. limite 60/min (token v_tok2)
  v_hash2 := encode(extensions.digest(v_tok2, 'sha256'), 'hex');
  set local role service_role;
  v_n := 0;
  for i in 1..60 loop r := public.crm_mcp_autenticar(v_hash2, 'crm_listar_funis'); if r->>'ok' = 'true' then v_n := v_n + 1; end if; end loop;
  r := public.crm_mcp_autenticar(v_hash2, 'crm_listar_funis');
  reset role;
  perform pg_temp.ok('7.limite60', v_n = 60 and r->>'codigo' = 'limite' and (select count(*) from crm.mcp_chamada where token_id = v_id2) = 60,
                     v_n || ' ok + 61ª recusada; 60 chamadas gravadas');
  set local role service_role; r := public.crm_mcp_autenticar(v_hash2, null); reset role;
  perform pg_temp.ok('7.sem_ferramenta', r->>'ok' = 'true', 'autenticar sem ferramenta (initialize/tools/list) não conta no limite');

  -- 8. perfil sem acesso e token expirado (inseridos como postgres)
  insert into crm.mcp_token (perfil_id, nome, prefixo, hash_sha256, escopos, expira_em)
  values (v_visu, 'Ensaio visu', 'gpc_00000000', encode(extensions.digest('ensaio-visu', 'sha256'), 'hex'), array['ler'], now() + interval '1 day');
  insert into crm.mcp_token (perfil_id, nome, prefixo, hash_sha256, escopos, criado_em, expira_em)
  values (v_b, 'Ensaio expirado', 'gpc_00000001', encode(extensions.digest('ensaio-exp', 'sha256'), 'hex'), array['ler'], now() - interval '10 days', now() - interval '1 day');
  set local role service_role;
  r := public.crm_mcp_autenticar(encode(extensions.digest('ensaio-visu', 'sha256'), 'hex'), null); v_err := r->>'codigo';
  r := public.crm_mcp_autenticar(encode(extensions.digest('ensaio-exp', 'sha256'), 'hex'), null); v_err := v_err || ',' || (r->>'codigo');
  reset role;
  perform pg_temp.ok('8.perfil_expirado', v_err = 'perfil,token', v_err);
  update crm.vendedor set ativo = false where perfil_id = v_a;
  set local role service_role; r := public.crm_mcp_autenticar(v_hash2, null); reset role;
  update crm.vendedor set ativo = true where perfil_id = v_a;
  perform pg_temp.ok('8.vendedor_inativo', r->>'codigo' = 'perfil', 'vendedor inativado perde o MCP na hora');

  -- 9. kill-switch: desligado recusa tudo, mas revogar continua funcionando
  update crm.config set mcp_ligado = false;
  set local role service_role; r := public.crm_mcp_autenticar(v_hash2, null); reset role;
  v_err := r->>'codigo';
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated; r := public.crm_mcp_revogar_token(v_id2); reset role;
  perform pg_temp.ok('9.kill_switch', v_err = 'desligado' and r->>'ok' = 'true', 'desligado recusa; revogar funciona desligado');
  update crm.config set mcp_ligado = true;

  -- 10. crm.log: canal mcp pela claim gp_canal
  insert into pessoas.pessoas (nome, teste) values ('Ensaio F7 Ana', true) returning id into p1;
  insert into pessoas.pessoas (nome, teste) values ('Ensaio F7 Beto', true) returning id into p2;
  insert into pessoas.pessoas (nome, teste) values ('Ensaio F7 Caio', true) returning id into p3;
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated', 'gp_canal', 'mcp')::text, true);
  insert into crm.nota (pessoa_id, texto, autor_id) values (p1, 'Ensaio F7 via MCP', v_a);
  perform pg_temp.ok('10.log_mcp', (select autor_tipo = 'mcp' and canal = 'mcp' and autor_id = v_a and entidade = 'nota' and pessoa_id = p1
                                      from crm.log order by id desc limit 1), 'JWT com gp_canal=mcp → autor_tipo mcp, autor = dono do token');
  perform set_config('request.jwt.claims', claims_a, true);
  insert into crm.nota (pessoa_id, texto, autor_id) values (p1, 'Ensaio F7 tela', v_a);
  perform pg_temp.ok('10.log_tela', (select autor_tipo = 'pessoa' and canal = 'tela' from crm.log order by id desc limit 1), 'sem a claim → tela (igual a antes)');
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated', 'gp_canal', 'mcp')::text, true);
  perform set_config('crm.canal', 'hotmart', true);
  insert into crm.nota (pessoa_id, texto, autor_id) values (p1, 'Ensaio F7 canal explícito', v_a);
  perform set_config('crm.canal', '', true);
  perform pg_temp.ok('10.log_precedencia', (select canal = 'hotmart' from crm.log order by id desc limit 1), 'crm.canal explícito continua mandando');
  perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'gp_canal', 'mcp')::text, true);
  insert into crm.nota (pessoa_id, texto) values (p1, 'Ensaio F7 sem sub');
  perform pg_temp.ok('10.log_sem_sub', (select autor_tipo = 'sistema' and canal = 'sistema' from crm.log order by id desc limit 1), 'claim sem sub não vira mcp');
  perform set_config('request.jwt.claims', '', true);

  -- 11. dados para resumo e desempenho
  select id into ag from crm.agrupador where linha = 'ht';
  select chave into v_mot from crm.motivo_perda where ativo order by ordem limit 1;
  insert into crm.funil (nome, agrupador_id, linha, tipo) values ('Ensaio F7', ag, 'ht', 'manual') returning id into f;
  insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, sla_atencao_min, sla_critico_min) values
    (f, 0, 'Contato', 'primeiro_contato', 'info', 5, 15), (f, 1, 'Qualificar', 'qualificar', 'cyan', 60, 120), (f, 2, 'Fechado', 'fechado', 'green', null, null);
  select id into e1 from crm.etapa_funil where funil_id = f and ordem = 0;
  select id into e2 from crm.etapa_funil where funil_id = f and ordem = 1;
  select id into eg from crm.etapa_funil where funil_id = f and ordem = 2;
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor) values (p1, f, e1, 'ht', 'venda_ativa', v_a, 100);
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor) values (p2, f, e1, 'ht', 'venda_ativa', v_b, 200);
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor, etapa_desde) values (p3, f, e2, 'ht', 'venda_ativa', null, 50, now() - interval '1 day');
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor, status, transacao_ganho, fechado_em)
  values (p2, f, eg, 'ht', 'venda_ativa', v_a, 997, 'ganho', 'ENSAIO-F7-1', now() - interval '1 minute');
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor, status, motivo_perda, fechado_em)
  values (p3, f, e1, 'ht', 'venda_ativa', v_b, 300, 'perdido', v_mot, now() - interval '1 minute');
  insert into crm.atividade (pessoa_id, dono_id, tipo, titulo, vence_em) values (p1, v_a, 'ligacao', 'Ensaio atrasada', now() - interval '1 hour');
  insert into crm.atividade (pessoa_id, dono_id, tipo, titulo, vence_em, concluida_em, resultado)
  values (p1, v_a, 'whatsapp', 'Ensaio feita', now() - interval '2 hour', now() - interval '1 minute', 'Respondeu');

  -- 12. crm_funil_resumo (RLS)
  perform set_config('request.jwt.claims', claims_g, true);
  set local role authenticated; r := public.crm_funil_resumo(f); reset role;
  perform pg_temp.ok('12.resumo_gestor', jsonb_array_length(r->'etapas') = 3
                     and (r->'etapas'->0->>'abertos')::int = 2 and (r->'etapas'->0->>'valorAberto')::numeric = 300
                     and (r->'etapas'->1->>'abertos')::int = 1 and (r->'etapas'->1->>'semDono')::int = 1
                     and (r->'etapas'->1->>'estouradosSla')::int = 1 and (r->'etapas'->2->>'abertos')::int = 0
                     and (r->>'ganhos30d')::int = 1 and (r->>'valorGanho30d')::numeric = 997 and (r->>'perdidos30d')::int = 1,
                     'gestor: 2+1 abertos (R$ 300 na 1ª), 1 sem dono estourado, 1 ganho R$ 997, 1 perdido');
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated; r := public.crm_funil_resumo(f); reset role;
  perform pg_temp.ok('12.resumo_vendedor', (r->'etapas'->0->>'abertos')::int = 1 and (r->'etapas'->0->>'valorAberto')::numeric = 100
                     and (r->'etapas'->1->>'abertos')::int = 1 and (r->>'ganhos30d')::int = 1 and (r->>'perdidos30d')::int = 0,
                     'vendedor A: só o dele + o sem dono; o perdido de B não aparece');
  v_err := null;
  perform set_config('request.jwt.claims', claims_v, true);
  begin set local role authenticated; r := public.crm_funil_resumo(f); reset role; v_err := 'leu';
  exception when insufficient_privilege then reset role; v_err := 'negado'; end;
  perform set_config('request.jwt.claims', claims_g, true);
  begin set local role authenticated; r := public.crm_funil_resumo(gen_random_uuid()); reset role; v_err := v_err || ',leu';
  exception when no_data_found then reset role; v_err := v_err || ',naoachou'; end;
  perform pg_temp.ok('12.resumo_recusas', v_err = 'negado,naoachou', 'visualizador 42501; funil inexistente P0002');

  -- 13. crm_desempenho (RLS)
  perform set_config('request.jwt.claims', claims_g, true);
  set local role authenticated; r := public.crm_desempenho(); reset role;
  perform pg_temp.ok('13.desempenho_gestor', (r->'total'->>'abertos')::int >= 3 and (r->'total'->>'ganhos')::int >= 1
                     and exists (select 1 from jsonb_array_elements(r->'porDono') x where (x->>'donoId')::uuid = v_a
                                  and (x->>'ganhos')::int = 1 and (x->>'valorGanho')::numeric = 997 and (x->>'taxaConversao')::numeric = 1
                                  and (x->>'atividadesAtrasadas')::int = 1 and (x->>'atividadesConcluidas')::int = 1)
                     and exists (select 1 from jsonb_array_elements(r->'porDono') x where (x->>'donoId')::uuid = v_b
                                  and (x->>'perdidos')::int = 1 and (x->>'taxaConversao')::numeric = 0)
                     and exists (select 1 from jsonb_array_elements(r->'porDono') x where x->>'donoId' is null and x->>'nome' = 'Sem dono'),
                     'gestor vê A (1 ganho R$ 997, taxa 1, 1 atrasada, 1 concluída), B (1 perdido, taxa 0) e "Sem dono"');
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated; r := public.crm_desempenho(); reset role;
  perform pg_temp.ok('13.desempenho_vendedor', not exists (select 1 from jsonb_array_elements(r->'porDono') x where (x->>'donoId')::uuid = v_b)
                     and exists (select 1 from jsonb_array_elements(r->'porDono') x where (x->>'donoId')::uuid = v_a),
                     'vendedor A não vê a linha de B');
  v_err := null;
  begin set local role authenticated; r := public.crm_desempenho(now(), now() - interval '1 day'); reset role; v_err := 'aceitou';
  exception when invalid_parameter_value then reset role; v_err := 'recusou'; end;
  perform set_config('request.jwt.claims', claims_v, true);
  begin set local role authenticated; r := public.crm_desempenho(); reset role; v_err := v_err || ',leu';
  exception when insufficient_privilege then reset role; v_err := v_err || ',negado'; end;
  perform pg_temp.ok('13.desempenho_recusas', v_err = 'recusou,negado', 'período invertido 22023; visualizador 42501');
  perform set_config('request.jwt.claims', '', true);

  -- 14. privilégios finais
  perform pg_temp.ok('14.grants', not has_function_privilege('anon', 'public.crm_desempenho(timestamptz,timestamptz)', 'execute')
                     and not has_function_privilege('anon', 'public.crm_mcp_autenticar(text,text)', 'execute')
                     and not has_function_privilege('anon', 'public.crm_mcp_revogar_token(uuid)', 'execute')
                     and not has_table_privilege('authenticated', 'crm.mcp_chamada', 'select')
                     and not has_table_privilege('authenticated', 'crm.mcp_token', 'insert'),
                     'anon sem execute; authenticated sem acesso direto às tabelas do MCP');
end
$t$;

select string_agg(linha, E'\n' order by n) from _z_out;
rollback;

-- ═══ PARTE B: massa sintética 10× + medição (1 chamada, begin … rollback) ═══════════════════════════════════════════
-- Recria só as 2 RPCs de leitura (corpo idêntico à migration) e uma versão mínima das tabelas do MCP (colunas e índices
-- usados no caminho quente: hash unique, (token_id, em desc)). Carga com session_replication_role = replica (local, só
-- para não gravar 90 mil linhas de crm.log na massa: com triggers a carga levou 36 s, acima do teto de ~25 s do MCP).
-- Mede a RPC INTEIRA 2× como authenticated + JWT real (gestor = admin real; vendedor A = mp) e cola os planos das
-- consultas internas. Números colados em 20261006e.explain.md §4.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, linha text) on commit drop;
grant insert, select on _z_out to authenticated, service_role;
grant usage on sequence _z_out_n_seq to authenticated, service_role;
create temp table _vend on commit drop as select array_agg(perfil_id order by sigla) v from crm.vendedor;
create temp table _t0 on commit drop as select clock_timestamp() t;
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
grant execute on function public.crm_funil_resumo(uuid), public.crm_desempenho(timestamptz, timestamptz) to authenticated;
create table crm.mcp_token (id uuid primary key default gen_random_uuid(), perfil_id uuid not null, hash_sha256 text not null unique,
  escopos text[] not null, criado_em timestamptz not null default now(), expira_em timestamptz not null, revogado_em timestamptz, ultimo_uso_em timestamptz);
create table crm.mcp_chamada (id bigint generated always as identity primary key, token_id uuid not null, perfil_id uuid not null, ferramenta text not null, em timestamptz not null default now());
create index mcp_chamada_token_idx on crm.mcp_chamada (token_id, em desc);
set local session_replication_role = replica;
insert into crm.funil (nome, agrupador_id, linha, tipo) select 'Ensaio F7 massa ' || g, (select id from crm.agrupador where linha = 'ht'), 'ht', 'manual' from generate_series(1, 10) g;
insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, sla_atencao_min, sla_critico_min)
select f.id, o, 'Etapa ' || o, case o when 5 then 'fechado' else 'qualificar' end, 'info', case when o < 5 then 60 end, case when o < 5 then 120 end
  from crm.funil f, generate_series(0, 5) o where f.nome like 'Ensaio F7 massa %';
insert into pessoas.pessoas (nome, teste) select 'Ensaio F7 Massa ' || g, true from generate_series(1, 20000) g;
insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, dono_id, valor, status, transacao_ganho, motivo_perda, fechado_em, criado_em, etapa_desde)
select p.id, e.funil_id, e.id, 'ht', 'venda_ativa',
       case when p.r % 10 = 0 then null else (select v[1 + p.r % 2] from _vend) end, 297,
       s.st, case when s.st = 'ganho' then 'ENSAIO-F7-' || p.r || '-' || i end,
       case when s.st = 'perdido' then (select chave from crm.motivo_perda where ativo order by ordem limit 1) end,
       case when s.st <> 'aberto' then now() - ((p.r % 400) || ' hours')::interval end,
       now() - ((p.r % 900) || ' hours')::interval, now() - ((p.r % 50) || ' hours')::interval
  from (select id, row_number() over () r from pessoas.pessoas where teste and nome like 'Ensaio F7 Massa %') p
  cross join generate_series(1, case when p.r % 2 = 0 then 2 else 1 end) i
  cross join lateral (select case when (p.r + i) % 3 = 0 then 'ganho' when (p.r + i) % 3 = 1 then 'perdido' else 'aberto' end st) s
  join lateral (select ef.id, ef.funil_id from crm.etapa_funil ef join crm.funil ff on ff.id = ef.funil_id
                 where ff.nome like 'Ensaio F7 massa %' and ((s.st = 'ganho') = (ef.papel = 'fechado'))
                 order by ef.id offset ((p.r + i) % case when s.st = 'ganho' then 10 else 50 end) limit 1) e on true;
insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em, concluida_em, resultado)
select n.id, n.pessoa_id, coalesce(n.dono_id, (select v[1] from _vend)), 'ligacao', 'x', now() + ((j * 3 - 4) || ' hours')::interval,
       case when j = 1 then now() - interval '1 hour' end, case when j = 1 then 'ok' end
  from crm.negocio n cross join generate_series(1, 2) j;
insert into crm.mcp_token (perfil_id, hash_sha256, escopos, expira_em)
select (select v[1 + g % 2] from _vend), encode(extensions.digest('ensaio-' || g, 'sha256'), 'hex'), array['ler'], now() + interval '30 days' from generate_series(1, 300) g;
insert into crm.mcp_chamada (token_id, perfil_id, ferramenta, em)
select t.id, t.perfil_id, 'crm_listar_funis', now() - ((g * 7) || ' seconds')::interval from crm.mcp_token t cross join generate_series(1, 60) g;
set local session_replication_role = origin;
analyze crm.negocio; analyze crm.atividade; analyze crm.etapa_funil; analyze crm.mcp_token; analyze crm.mcp_chamada;
insert into _z_out (linha) select format('massa (%s s): negocio=%s (aberto %s), atividade=%s, mcp_token=%s, mcp_chamada=%s', round(extract(epoch from clock_timestamp() - (select t from _t0))::numeric, 1),
  count(*), count(*) filter (where status = 'aberto'), (select count(*) from crm.atividade), (select count(*) from crm.mcp_token), (select count(*) from crm.mcp_chamada)) from crm.negocio;
do $x$
declare v_admin uuid; v_a uuid; v_f uuid; r record; v_txt text; v_t0 timestamptz; v jsonb; i int; quem text; sub uuid;
begin
  select id into v_admin from public.perfis where cargo = 'admin' and status = 'ativo' order by criado_em limit 1;
  select perfil_id into v_a from crm.vendedor where sigla = 'mp';
  select id into v_f from crm.funil where nome = 'Ensaio F7 massa 1';
  for i in 1..2 loop
    foreach quem in array array['gestor', 'vendedor A'] loop
      sub := case quem when 'gestor' then v_admin else v_a end;
      perform set_config('request.jwt.claims', json_build_object('sub', sub, 'role', 'authenticated')::text, true);
      set local role authenticated;
      v_t0 := clock_timestamp(); v := public.crm_funil_resumo(v_f);
      insert into _z_out (linha) values (format('[%s] %s crm_funil_resumo: %s ms (abertos 1ª etapa %s)', i, quem, round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1), v->'etapas'->0->>'abertos'));
      v_t0 := clock_timestamp(); v := public.crm_desempenho();
      insert into _z_out (linha) values (format('[%s] %s crm_desempenho(hoje): %s ms (%s donos, abertos %s)', i, quem, round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1), jsonb_array_length(v->'porDono'), v->'total'->>'abertos'));
      v_t0 := clock_timestamp(); v := public.crm_desempenho(now() - interval '30 days', now());
      insert into _z_out (linha) values (format('[%s] %s crm_desempenho(30 d): %s ms (ganhos %s)', i, quem, round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1), v->'total'->>'ganhos'));
      if i = 2 then
        v_txt := '';
        for r in execute $q$explain (analyze, buffers, costs off, timing off, summary on) select coalesce(n.dono_id, '00000000-0000-0000-0000-000000000000'::uuid), count(*) from crm.negocio n
          where n.status = 'aberto' or (n.criado_em >= now() - interval '30 days') or (n.status <> 'aberto' and n.fechado_em >= now() - interval '30 days') group by 1$q$ loop
          v_txt := v_txt || btrim(r."QUERY PLAN") || ' / '; end loop;
        insert into _z_out (linha) values (format('[plano] %s desempenho.neg: %s', quem, v_txt));
        v_txt := '';
        for r in execute format($q$explain (analyze, buffers, costs off, timing off, summary on) select n.etapa_id, count(*) from crm.negocio n join crm.etapa_funil e2 on e2.id = n.etapa_id where n.funil_id = %L and n.status = 'aberto' group by n.etapa_id$q$, v_f) loop
          v_txt := v_txt || btrim(r."QUERY PLAN") || ' / '; end loop;
        insert into _z_out (linha) values (format('[plano] %s funil_resumo.abertos: %s', quem, v_txt));
      end if;
      reset role;
    end loop;
    perform set_config('request.jwt.claims', '', true);
    v_txt := '';
    for r in execute $q$explain (analyze, buffers, costs off, timing off, summary on) select count(*) from crm.mcp_chamada c where c.token_id = (select id from crm.mcp_token order by id limit 1) and c.em > now() - interval '1 minute'$q$ loop
      v_txt := v_txt || btrim(r."QUERY PLAN") || ' / '; end loop;
    insert into _z_out (linha) values (format('[%s plano] limite 60/min: %s', i, v_txt));
    v_txt := '';
    for r in execute format($q$explain (analyze, buffers, costs off, timing off, summary on) select * from crm.mcp_token x where x.hash_sha256 = %L$q$, encode(extensions.digest('ensaio-7', 'sha256'), 'hex')) loop
      v_txt := v_txt || btrim(r."QUERY PLAN") || ' / '; end loop;
    insert into _z_out (linha) values (format('[%s plano] token por hash: %s', i, v_txt));
  end loop;
end $x$;
select string_agg(linha, E'\n' order by n) from _z_out;
rollback;

-- ═══ PARTE C: conferência (chamada separada, sem transação) ════════════════════════════════════════════════════════
-- Esperado (medido 06/10/2026): mcp_token/mcp_chamada null; 20 RPCs crm_*; crm_desempenho null; tg_log md5
-- 450774b246813145998822a8b8102e8d (corpo original); mcp_ligado false; 0 funis; 0 negócios; 0 pessoas/log de ensaio;
-- vendedor A ativo; última versão 20261006034317; 0 sessões presas.
select to_regclass('crm.mcp_token') mcp_token, to_regclass('crm.mcp_chamada') mcp_chamada,
 (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname like 'crm\_%') rpcs_crm,
 to_regprocedure('public.crm_desempenho(timestamptz,timestamptz)') desempenho,
 md5(pg_get_functiondef('crm.tg_log()'::regprocedure)) tglog_md5,
 (select mcp_ligado from crm.config) mcp_ligado, (select count(*) from crm.funil) funis, (select count(*) from crm.negocio) negocios,
 (select count(*) from pessoas.pessoas where nome like 'Ensaio F7%') pessoas_ensaio, (select count(*) from crm.log where resumo like '%Ensaio F7%' or canal='mcp') log_ensaio,
 (select ativo from crm.vendedor where sigla='mp') vend_a_ativo,
 (select version from supabase_migrations.schema_migrations order by version desc limit 1) ultima_versao,
 (select count(*) from pg_stat_activity where state like 'idle in transaction%') sessoes_presas;
