-- 20260928z56 — SEGURANÇA/LGPD: fn_aluno_360 deixa de entregar a base de alunos a quem não é da equipe.
--
-- APLICADA em produção 28/09 (contenção de vazamento, antes da revisão do kirad — revisão em seguida).
-- Achado: public.fn_aluno_360() é SECURITY DEFINER sem guarda e tinha execute para PUBLIC (=> anon). Testado em
-- produção como VISITANTE SEM LOGIN (só a chave pública do site): 1.890 alunos, 1.869 com e-mail, 1.786 com
-- documento (CPF), 1.856 com telefone. Aluno logado (auth.users compartilhada com GPS/SIP) idem.
-- O repositório antigo tem um script "db_migrate_lgpd_fn_aluno_360_safe.sql" que nunca foi aplicado.
--
-- Correção: exige public.gp_eh_equipe() (perfil ativo @advmais.com) e revoga PUBLIC/anon. Mesma assinatura e retorno.
-- Conferido: equipe 1.890 (igual a antes), aluno logado 0, anon sem execute.
-- Chamadores conhecidos: web/modules/alunos/ui/alunos-data.ts (v2, equipe) e o legado
-- sistema-grupo-participa/app/sistema/alunos/js/app.js (Centro de Controle, equipe).
--
-- REVERSÃO (reabre o vazamento — só com decisão explícita):
--   create or replace function public.fn_aluno_360(p_aluno_id uuid default null::uuid) returns setof vw_aluno_360
--    language sql stable security definer set search_path to 'public'
--   as $f$ select * from public.vw_aluno_360 where (p_aluno_id is null or id = p_aluno_id); $f$;
--   grant execute on function public.fn_aluno_360(uuid) to public;
create or replace function public.fn_aluno_360(p_aluno_id uuid default null::uuid)
 returns setof vw_aluno_360 language sql stable security definer set search_path to 'public'
as $f$
  select * from public.vw_aluno_360
   where (select public.gp_eh_equipe())  -- LGPD 28/09: só equipe (antes: qualquer um, até sem login)
     and (p_aluno_id is null or id = p_aluno_id);
$f$;
revoke all on function public.fn_aluno_360(uuid) from public, anon;
grant execute on function public.fn_aluno_360(uuid) to authenticated;
