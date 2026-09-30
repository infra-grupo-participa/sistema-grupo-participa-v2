-- 20261003h — Lista de conciliação em UMA chamada (jsonb)
--
-- POR QUÊ
--   A tela lê fn_aluno_conciliacao(null, true): 1.495 linhas em 30/09, acima do teto de 1.000 linhas por resposta do
--   PostgREST. Paginando com range, cada página RE-EXECUTA a função inteira (~1,7 s): 2 páginas hoje = ~3,4 s, e cresce
--   com a base. Retorno escalar (jsonb) não sofre o teto: 1 execução, sempre.
--
-- SEGURANÇA
--   SECURITY INVOKER: herda a guarda de equipe de fn_aluno_conciliacao (SECURITY DEFINER com guarda no corpo).
--   Revoke de public/anon; execute só para authenticated.
--
-- AS 5 PERGUNTAS
--   escala: 1.495 linhas → 522 KB de jsonb (antes da compressão HTTP); 10x = ~5 MB — aí paginar no banco por aluno.
--   índice: nenhum (reusa a conciliação). frequência: 1 por abertura de /sistema/alunos (equipe; ficha e contador dependem), não só da aba Conciliação.
--   repetição: substitui N páginas por 1. reversão: drop function public.fn_aluno_conciliacao_lista(boolean).
--
-- ENSAIO (30/09/2026, produção, begin … ZOUT): n_json 1495 = n_tab 1495 · 522 KB · Execution Time 1.843 ms (1 chamada)
--   anon execute = false · authenticated fora da equipe = 42501 "fn_aluno_conciliacao: acesso restrito à equipe".

create function public.fn_aluno_conciliacao_lista(p_incluir_conferidos boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $f$
  select coalesce(jsonb_agg(to_jsonb(c) order by c.severidade, c.grupo, c.tipo, c.item), '[]'::jsonb)
    from public.fn_aluno_conciliacao(null, p_incluir_conferidos) c
$f$;

revoke all on function public.fn_aluno_conciliacao_lista(boolean) from public, anon;
grant execute on function public.fn_aluno_conciliacao_lista(boolean) to authenticated;

comment on function public.fn_aluno_conciliacao_lista(boolean) is
  '20261003h: conciliação inteira num jsonb (1 execução; escapa do teto de 1.000 linhas do PostgREST). Guarda herdada de fn_aluno_conciliacao.';
