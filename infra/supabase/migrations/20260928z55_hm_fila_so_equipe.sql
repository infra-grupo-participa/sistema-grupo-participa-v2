-- 20260928z55 — SEGURANÇA: a fila de ativação do HM deixa de entregar dado pessoal a quem não é da equipe.
--
-- Achado do kirad (28/09), confirmado em produção pelo coordenador: public.fn_hm_fila() é SECURITY DEFINER, com execute
-- para authenticated e SEM guarda no corpo. auth.users é compartilhada com GPS/SIP/etc. (milhares de alunos): um aluno
-- logado chamando /rest/v1/rpc/fn_hm_fila recebia 367 compradores do HM com nome, e-mail, telefone e CPF sem máscara.
-- Anterior a esta sessão (não veio da z53).
--
-- Correção mínima, sem trancar a equipe: exige public.gp_eh_equipe() (perfil ativo com e-mail @advmais.com — a mesma
-- trava de domínio do sistema interno). Não-equipe recebe zero linhas. Restringir por área (is_ht_operator) fica como
-- decisão à parte: hoje a aba "Liberação Holding Masters" aparece para a equipe na tela de Alunos.
-- fn_hm_fila_contagem (só conta, chama fn_hm_fila) tinha execute até para anon/PUBLIC: revogado.
--
-- Replace sobre o corpo VIGENTE, com guarda (padrão z52/z53).
-- REVERSÃO:
--   do $r$ declare d text; begin
--     d := pg_get_functiondef('public.fn_hm_fila()'::regprocedure);
--     d := replace(d, E'  where (select public.gp_eh_equipe())  -- z55: só equipe\n    and (coalesce(f.categoria,'''') <> ''diferenca''', E'  where coalesce(f.categoria,'''') <> ''diferenca''');
--     d := replace(d, E'''reserva'',''renovacao'')));', E'''reserva'',''renovacao''));');
--     execute d;
--   end $r$;
--   grant execute on function public.fn_hm_fila_contagem() to public, anon;
do $do$
declare
  d  text;
  a1 text := E'  where coalesce(f.categoria,'''') <> ''diferenca''';
  b1 text := E'  where (select public.gp_eh_equipe())  -- z55: só equipe\n    and (coalesce(f.categoria,'''') <> ''diferenca''';
  a2 text := E'''reserva'',''renovacao''));';
  b2 text := E'''reserva'',''renovacao'')));';
begin
  d := pg_get_functiondef('public.fn_hm_fila()'::regprocedure);
  if position('z55: só equipe' in d) > 0 then
    raise notice 'z55: fn_hm_fila já exige equipe';
  elsif (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1
     or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1 then
    raise exception 'z55: trecho do where final não encontrado (ou repetido) no corpo vigente de fn_hm_fila';
  else
    execute replace(replace(d, a1, b1), a2, b2);
  end if;
end $do$;

revoke all on function public.fn_hm_fila_contagem() from public, anon;
grant execute on function public.fn_hm_fila_contagem() to authenticated;

-- PROVA (rodar como usuário da equipe e como aluno):
--   equipe: count(*) de fn_hm_fila() = o mesmo de antes (367 em 28/09); aluno: 0.
--   has_function_privilege('anon','public.fn_hm_fila_contagem()','execute') = false.
