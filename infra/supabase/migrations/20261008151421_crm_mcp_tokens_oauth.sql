-- 20261008151421 (escrita como 20261008mcq) — APLICADA em 08/10/2026 (md5 dos statements c83562eb4a95b051f38cce6d3629d089) — crm_mcp_tokens mostra a conexão OAuth pela validade da CONEXÃO (refresh), não do access de 1 h.
-- Sem isto, uma conexão do claude.ai parada há mais de 1 h aparecia "Expirada" na tela e sumia o botão Revogar,
-- embora o refresh (30 d) ainda renovasse o acesso. Corpo vivo conferido por md5 (c15fd4f2…); mudam 2 campos e entra
-- 'oauth' (true = conexão pelo OAuth; a tela não conta essas no limite de 5 tokens manuais).
-- Mesma assinatura e retorno: create or replace mantém o GRANT (authenticated) e a guarda.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.crm_mcp_tokens()'::regprocedure) <> 'c15fd4f277fd59f7c13fdba9930e44d3' then
    raise exception '20261008mcq: crm_mcp_tokens mudou desde a leitura';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'mcp_token' and column_name = 'refresh_expira_em') then
    raise exception '20261008mcq: falta a 20261008150823 (crm_mcp_oauth)';
  end if;
end
$g$;

create or replace function public.crm_mcp_tokens()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_g boolean := coalesce(crm.eh_gestor(), false); v jsonb;
begin
  perform crm.exige_comercial();
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'nome', t.nome, 'prefixo', t.prefixo, 'escopos', to_jsonb(t.escopos), 'perfilId', t.perfil_id,
           'perfilNome', coalesce(pf.nome, ''), 'criadoEm', t.criado_em,
           'expiraEm', coalesce(t.refresh_expira_em, t.expira_em),
           'revogadoEm', t.revogado_em, 'ultimoUsoEm', t.ultimo_uso_em, 'oauth', t.cliente_id is not null,
           'ativo', t.revogado_em is null and coalesce(t.refresh_expira_em, t.expira_em) > now()) order by t.criado_em desc), '[]'::jsonb)
    into v
    from (select * from crm.mcp_token x where v_g or x.perfil_id = v_eu order by x.criado_em desc limit 200) t
    left join public.perfis pf on pf.id = t.perfil_id;
  return v;
end
$function$;

do $p$
begin
  if has_function_privilege('anon', 'public.crm_mcp_tokens()', 'execute')
     or not has_function_privilege('authenticated', 'public.crm_mcp_tokens()', 'execute') then
    raise exception '20261008mcq: grants de crm_mcp_tokens fora do esperado';
  end if;
end
$p$;
