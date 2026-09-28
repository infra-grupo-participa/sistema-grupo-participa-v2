-- 20260928z57 — SEGURANÇA/LGPD: fn_aluno_360_safe (a que o sistema interno usa) só para a equipe.
--
-- APLICADA em produção 28/09 (contenção, antes da revisão do kirad).
-- Achado: SECURITY DEFINER com execute para PUBLIC (=> anon). Mascarava só o documento; entregava nome, e-mail,
-- telefone e endereço. Testado como VISITANTE SEM LOGIN: 1.890 alunos, 1.869 com e-mail, 1.856 com telefone,
-- 1.666 com endereço. É a função chamada pelo navegador do sistema interno (logs de 27–28/09: /rpc/fn_aluno_360_safe).
--
-- Correção: se não for public.gp_eh_equipe() (perfil ativo @advmais.com) → não devolve nada; revoke PUBLIC/anon.
-- Replace no corpo VIGENTE com guarda. Conferido: equipe 1.890 (igual), aluno logado 0, anon sem execute.
--
-- REVERSÃO (reabre o vazamento — só com decisão explícita):
--   do $r$ declare d text; begin
--     d := pg_get_functiondef('public.fn_aluno_360_safe(uuid)'::regprocedure);
--     d := replace(d, E'  -- LGPD 28/09 (z57): só equipe. Antes: PUBLIC/anon executavam e recebiam nome, e-mail, telefone e endereço.\n  if not coalesce(public.gp_eh_equipe(), false) then return; end if;\n', '');
--     execute d;
--   end $r$;
--   grant execute on function public.fn_aluno_360_safe(uuid) to public;
do $do$
declare d text;
  a1 text := E'begin\n  v_can_see := public.tem_permissao(v_user_id, ''alunos.ver_sensivel'');';
  b1 text := E'begin\n  -- LGPD 28/09 (z57): só equipe. Antes: PUBLIC/anon executavam e recebiam nome, e-mail, telefone e endereço.\n  if not coalesce(public.gp_eh_equipe(), false) then return; end if;\n  v_can_see := public.tem_permissao(v_user_id, ''alunos.ver_sensivel'');';
begin
  d := pg_get_functiondef('public.fn_aluno_360_safe(uuid)'::regprocedure);
  if position('(z57): só equipe' in d) > 0 then
    raise notice 'z57: já aplicada';
  elsif (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then
    raise exception 'z57: trecho não encontrado (ou repetido) no corpo vigente de fn_aluno_360_safe';
  else
    execute replace(d, a1, b1);
  end if;
end $do$;
revoke all on function public.fn_aluno_360_safe(uuid) from public, anon;
grant execute on function public.fn_aluno_360_safe(uuid) to authenticated;
