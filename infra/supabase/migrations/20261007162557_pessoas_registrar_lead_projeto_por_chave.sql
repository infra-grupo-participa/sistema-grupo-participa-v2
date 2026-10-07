-- 20261007q: base de pessoas, o lead da página chega com projeto (a fachada resolve o projeto pela chave da casa)
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007162557 (nome pessoas_registrar_lead_projeto_por_chave,
-- era 20261007q), pelo aplica_sql.py aplicar + insert em supabase_migrations.schema_migrations na mesma transação. md5
-- gravado = 0eb6195ee561c03f7fbc7123e44d5c82 = este arquivo antes desta troca de STATUS. Relatório: 20261007162557.explain.md.
--
-- POR QUE
--   A rota POST /api/captura/lead (web/app/api/captura/lead/route.ts) manda só chave_evento (ex.: clinica-miami-2026-12)
--   e pessoas.registrar acha o projeto pela SIGLA (p->>'projeto', ex.: CNFMIAMI26). Resultado: o pré-checkout gravava
--   o evento com projeto_id nulo (docs/captura-de-lead.md, "O que a base guarda"). Pedido do Victor Hugo (07/10/2026):
--   a rota precisa resolver o projeto.
--
-- O QUE FAZ
--   Recria public.pessoas_registrar_lead(p jsonb) (fachada da 20261007152702 / 20261005r, só service_role executa):
--   quando p->>'projeto' vem vazio e p->>'chave_evento' casa com mkt.projetos.etiqueta_clickup, acrescenta
--   projeto = sigla desse projeto antes de chamar pessoas.registrar. Conserta a classe (qualquer chave da casa).
--   NÃO mexe em pessoas.registrar (md5 8f77b9fc…) nem na rota. Mesma assinatura: create or replace preserva dono e grants.
--   Chamadores (07/10/2026): só a rota de captura (grep em web/, infra/supabase/functions, disparos-thb; pg_proc: 0
--   funções citam a fachada).
--
-- AS 5 PERGUNTAS
--   escala: 1 busca a mais por lead (único etiqueta_clickup). índice: projetos_etiqueta_clickup_key (único). frequência:
--   1 por envio do formulário. repetição: nenhuma. reversão: bloco REVERSÃO no fim (corpo anterior inteiro).
--
-- IDEMPOTENTE: a guarda aceita o corpo anterior (md5 89b1a218…) ou o corpo desta migration (md5 na guarda) e mais nada.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

-- 0. Guarda de premissa
do $g$
declare v_md5 text;
begin
  select md5(prosrc) into v_md5 from pg_proc where oid = to_regprocedure('public.pessoas_registrar_lead(jsonb)');
  if v_md5 is null then
    raise exception '20261007q: public.pessoas_registrar_lead(jsonb) não existe';
  end if;
  if v_md5 not in ('89b1a21812e310d6f8da97da76d6ce34', 'e4f5e14c87f1da9c55598fafe7f6dafc') then
    raise exception '20261007q: corpo vivo de pessoas_registrar_lead mudou (md5 %). Refazer a partir do pg_get_functiondef.', v_md5;
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.registrar(jsonb,text,uuid)'::regprocedure)
     is distinct from '8f77b9fc25b84d526be4c9ebad528c2e' then
    raise exception '20261007q: pessoas.registrar não é o da 20261007152702 (md5). Conferir.';
  end if;
end
$g$;

-- 1. Fachada: corpo anterior + projeto pela chave da casa
create or replace function public.pessoas_registrar_lead(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v jsonb; v_sigla text;
begin
  -- 20261007q: sem sigla, a chave da casa (mkt.projetos.etiqueta_clickup) diz o projeto
  if nullif(btrim(coalesce(p->>'projeto', '')), '') is null and nullif(btrim(coalesce(p->>'chave_evento', '')), '') is not null then
    select pr.sigla into v_sigla from mkt.projetos pr where pr.etiqueta_clickup = lower(btrim(p->>'chave_evento'));
    if v_sigla is not null then
      p := p || jsonb_build_object('projeto', v_sigla);
    end if;
  end if;
  v := pessoas.registrar(p, 'formulario', null);
  return case when (v->>'ok')::boolean
              then jsonb_build_object('ok', true, 'ref', v->>'ref', 'como', v->>'como', 'revisao', v->>'revisao')
              else v end;
end
$function$;
revoke all on function public.pessoas_registrar_lead(jsonb) from public, anon, authenticated;

-- 2. Pós-condição
do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.pessoas_registrar_lead(jsonb)'::regprocedure) <> 'e4f5e14c87f1da9c55598fafe7f6dafc' then
    raise exception '20261007q: corpo gravado diferente do arquivo';
  end if;
  if (select proacl::text from pg_proc where oid = 'public.pessoas_registrar_lead(jsonb)'::regprocedure)
     is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception '20261007q: permissões de pessoas_registrar_lead mudaram';
  end if;
end
$c$;

-- REVERSÃO (numa transação): recriar o corpo anterior (md5 89b1a21812e310d6f8da97da76d6ce34):
-- create or replace function public.pessoas_registrar_lead(p jsonb) returns jsonb language plpgsql security definer
-- set search_path to '' as $function$
-- declare v jsonb;
-- begin
--   v := pessoas.registrar(p, 'formulario', null);
--   return case when (v->>'ok')::boolean
--               then jsonb_build_object('ok', true, 'ref', v->>'ref', 'como', v->>'como', 'revisao', v->>'revisao')
--               else v end;
-- end
-- $function$;
