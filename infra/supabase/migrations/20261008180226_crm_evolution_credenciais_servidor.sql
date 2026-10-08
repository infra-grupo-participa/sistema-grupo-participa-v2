-- crm_evolution_credenciais — o servidor Next lê URL e chave da Evolution no Vault quando o env da Hostinger está vazio.
-- Doc: docs/projetos/comercial/whatsapp-qr-evolution.md · ensaio: 20261008180226_ensaio.sql · explicação: 20261008180226.explain.md
-- APLICADA em 08/10/2026 (apply_migration; versão gravada 20261008180226).
--
-- Embrulho em public (exposto à API) de crm.evolution_credenciais() (só dono executa; usado pelas Edges via
-- SUPABASE_DB_URL), devolvendo SÓ url e api_key (a chave interna crm_whatsapp_envio_chave fica de fora).
-- Execute SÓ para service_role: o servidor chama com createAdminSupabase() depois de autorizar o gestor (crm_sessao).
-- Reversão: drop function public.crm_evolution_credenciais();

do $$ begin
  if to_regprocedure('crm.evolution_credenciais()') is null then
    raise exception 'premissa: crm.evolution_credenciais() não existe (migration 20261008152212 aplicada?)';
  end if;
  if to_regprocedure('public.crm_evolution_credenciais()') is not null then
    raise exception 'premissa: public.crm_evolution_credenciais() já existe';
  end if;
end $$;

create function public.crm_evolution_credenciais()
returns table (url text, api_key text)
language sql stable security definer set search_path = ''
as $$ select c.url, c.api_key from crm.evolution_credenciais() c $$;

revoke all on function public.crm_evolution_credenciais() from public, anon, authenticated;
grant execute on function public.crm_evolution_credenciais() to service_role;

comment on function public.crm_evolution_credenciais() is
  'URL e chave global da Evolution (Vault evolution_api_url/_key). Só service_role. Servidor Next, depois do portão de gestor. Nunca logar.';
