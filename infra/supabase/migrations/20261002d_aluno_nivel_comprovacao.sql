-- 20261002d — public.fn_aluno_nivel_selo(): selo de comprovação do nível de cada aluno ativo
--
-- O QUE FAZ: devolve, para TODOS os alunos ativos (thb_alunos.cancelado_em is null, ~1.885), numa única chamada:
--   aluno_id | nivel_comprovado | comprovado_em | selo
-- Só leitura. NÃO altera thb_alunos.nivel_resultado nem nada mais.
--
-- COMPROVAÇÃO = união de duas fontes; vale a MAIS RECENTE (decisão do Marcio), desempate id DESC:
--   * public.thb_placas_solicitacoes com status IN ('concluido','placa_postada') e nivel NOT NULL;
--       data = updated_at (mantido por trigger BEFORE UPDATE; medido: 0 de 50 concluídas/postadas com
--       updated_at parado em created_at). Mesma regra de "concluída" da 20261002c (fn_sync_placa_nivel).
--   * public.thb_placas_ciclos com tipo = 'placa' e nivel NOT NULL; data = concluido_em (nulo vai para o fim).
--       tipo 'cadastro' fica fora: é snapshot de solicitação em 'cadastro_concluido' (fn_placas_refazer), status
--       que também NÃO conta como comprovação na solicitação. Ver "Decisão" no relatório; o ensaio mede o impacto.
--
-- ESCALA DE NÍVEIS: web/shared/domain/nivel-resultado/index.ts
--   NIVEIS_COM_COMPROVACAO = ['ouro','platina','diamante','diamante_vermelho']  (níveis que exigem placa).
--   Obs.: o CHECK thb_alunos_nivel_resultado_check aceita também 'super_diamante', que NÃO está no domínio;
--   aqui ele segue o domínio (selo null). O ensaio conta quantos ativos têm esse valor.
--
-- REGRA DO selo:
--   nivel_resultado fora de NIVEIS_COM_COMPROVACAO (abaixo de ouro) ou nulo -> null
--   sem comprovação                                                        -> 'nao_comprovado'
--   comprovação = nivel_resultado                                          -> 'comprovado'
--   comprovação <> nivel_resultado                                         -> 'outro_nivel'
--   nivel_comprovado/comprovado_em vêm preenchidos para qualquer aluno que tenha comprovação, mesmo com selo null.
--
-- SEGURANÇA: SECURITY DEFINER, search_path public, pg_temp; guarda gp_eh_equipe() (perfil ativo @advmais.com)
--   com errcode 42501; EXECUTE revogado de PUBLIC e anon (revogar só de anon não pega o grant de PUBLIC), concedido
--   só a authenticated.
--
-- AS 5 PERGUNTAS
--   escala: 1 SELECT set-based; custo = seq de thb_alunos (1.888) + solicitações (191) + ciclos (10). Linear na base;
--           com 10x continua na casa de dezenas de milhares de linhas lidas, sem N+1.
--   índice: não precisa. Lê as 3 tabelas inteiras (a lista mostra todos); DISTINCT ON sobre ~60 comprovações.
--           Plano medido no ensaio (passo 6). Nenhum índice criado.
--   frequência: 1 chamada por carga da lista de alunos (equipe interna).
--   repetição: 1 chamada devolve todos; o front não chama por aluno.
--   reversão: bloco REVERSÃO no fim.
--
-- ENSAIO: infra/supabase/migrations/20261002d_ensaio.sql

select set_config('lock_timeout', '3s', true);

-- ─── 1. Função ────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_nivel_selo()
returns table (aluno_id uuid, nivel_comprovado text, comprovado_em timestamptz, selo text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
#variable_conflict use_column
begin
  if not public.gp_eh_equipe() then
    raise exception 'fn_aluno_nivel_selo: acesso restrito à equipe' using errcode = '42501';
  end if;

  return query
  with comp as (
    select distinct on (x.aid) x.aid, x.nivel, x.em
      from (
        select s.aluno_id as aid, s.nivel, s.updated_at as em, s.id
          from public.thb_placas_solicitacoes s
         where s.status in ('concluido', 'placa_postada')
           and s.nivel is not null
           and s.aluno_id is not null
        union all
        select c.aluno_id as aid, c.nivel, c.concluido_em as em, c.id
          from public.thb_placas_ciclos c
         where c.tipo = 'placa'
           and c.nivel is not null
           and c.aluno_id is not null
      ) x
     order by x.aid, x.em desc nulls last, x.id desc
  )
  select a.id,
         cp.nivel,
         cp.em,
         case
           when a.nivel_resultado in ('ouro', 'platina', 'diamante', 'diamante_vermelho') then
             case
               when cp.nivel is null               then 'nao_comprovado'
               when cp.nivel = a.nivel_resultado   then 'comprovado'
               else                                     'outro_nivel'
             end
         end::text
    from public.thb_alunos a
    left join comp cp on cp.aid = a.id
   where a.cancelado_em is null;
end;
$function$;

revoke all on function public.fn_aluno_nivel_selo() from public, anon;
grant execute on function public.fn_aluno_nivel_selo() to authenticated;

-- ─── 2. Conferência pós-aplicação ─────────────────────────────────────────────────────────────────────────────────────
do $confere$
begin
  if not exists (select 1 from pg_proc p
                  where p.oid = 'public.fn_aluno_nivel_selo()'::regprocedure
                    and p.prosecdef
                    and p.proconfig @> array['search_path=public, pg_temp']) then
    raise exception '20261002d: fn_aluno_nivel_selo sem SECURITY DEFINER ou search_path';
  end if;
  if exists (select 1 from pg_proc p
              where p.oid = 'public.fn_aluno_nivel_selo()'::regprocedure
                and (p.proacl is null
                     or exists (select 1 from aclexplode(p.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE'))) then
    raise exception '20261002d: PUBLIC executa public.fn_aluno_nivel_selo()';
  end if;
  if has_function_privilege('anon', 'public.fn_aluno_nivel_selo()', 'execute') then
    raise exception '20261002d: anon executa public.fn_aluno_nivel_selo()';
  end if;
  if not has_function_privilege('authenticated', 'public.fn_aluno_nivel_selo()', 'execute') then
    raise exception '20261002d: authenticated sem EXECUTE em public.fn_aluno_nivel_selo()';
  end if;
end $confere$;


-- ═══ REVERSÃO ═════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Função nova, só leitura, sem dado próprio: reverter = remover a função (antes, remover o consumidor no web/).
--
-- drop function if exists public.fn_aluno_nivel_selo();
