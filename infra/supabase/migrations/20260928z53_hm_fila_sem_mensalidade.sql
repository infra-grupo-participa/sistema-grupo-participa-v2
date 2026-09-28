-- 20260928z53 — Fila de ativação: a mensalidade do HM antigo (produto 3507214) só entra na 1ª compra.
--
-- Decisão do Marcio (28/09): quem ENTRA no plano de mensalidade passa pela ativação e ganha acesso (como hoje);
-- as mensalidades seguintes não têm nada a ativar e saem da fila. Antes: 32 compras do 3507214 pendentes
-- (9 entradas de jul–ago/2026 + 23 mensalidades seguintes).
--
-- "Mensalidade seguinte" = a mesma pessoa (comprador_id ou e-mail) tem compra aprovada ANTERIOR do 3507214 DENTRO da
-- janela da fila (>= hm_config.cutoff). Fica na fila a 1ª compra do plano que aparece na janela.
-- Por que dentro da janela e não na tabela inteira: 9 pessoas entraram no plano em jun/2026, ANTES do corte (06/07/26),
-- nunca passaram pela fila (0 liberações, 1 com login). Olhando a tabela inteira, a mensalidade de julho delas sumiria
-- e elas perderiam o único caminho de ativação. Medido 28/09 (simulação com rollback): 3507214 pendente 32 → 16,
-- no máximo 1 item por pessoa; outros produtos 351 → 351; fila 58 → 75 ms.
-- explain (analyze, buffers) do corpo vivo (z53 + z55), usuário da equipe, 28/09: Execution Time 69,8 ms, 367 linhas.
-- O NOT EXISTS da z53 roda 32× (só nas compras do 3507214) a 0,39 ms = 12,6 ms (Seq Scan em compras, 1.156 linhas na
-- janela — no tamanho, o certo). A guarda z55 vira One-Time Filter (InitPlan), avaliada 1×, sem custo por linha.
-- Provas do kirad (28/09): 0 compras HM sem produto_id; 0 pessoas do plano sem nenhuma linha na fila; aluno_novo das
-- compras do Programa não mudou por causa da z51.
--
-- Replace sobre o corpo VIGENTE (pg_get_functiondef), com guarda. Não reescreve a função a partir de arquivo.
-- ⚠️ RISCO DE COLISÃO: o arquivo NÃO versionado `20260908_fila_hm_reconhece_aurum.sql` (outra sessão) recria
-- fn_hm_fila INTEIRA a partir de arquivo (create or replace, ~linha 252). Se alguém aplicar aquele arquivo depois,
-- a z53 E a z55 (guarda de equipe) somem em silêncio. Conferido 28/09: o corpo vivo já tem o "aurum" daquele
-- arquivo + a marca "z53" + a "z55". Antes de aplicar qualquer create de fn_hm_fila, reaplicar z53 e z55.
--
-- REVERSÃO:
--   do $r$ declare d text; begin
--     d := pg_get_functiondef('public.fn_hm_fila()'::regprocedure);
--     d := replace(d, E'\n      and not (c.produto_id::text = ''3507214''  -- z53: mensalidade seguinte do HM antigo fora da fila\n           and exists (select 1 from compras c0 left join compradores cp0 on cp0.id = c0.comprador_id\n                        where c0.produto_id::text = ''3507214''\n                          and c0.status in (''APPROVED'',''COMPLETE'',''COMPLETED'')\n                          and (c0.comprador_id = c.comprador_id or lower(trim(cp0.email)) = lower(trim(cp.email)))\n                          and coalesce(c0.data_aprovacao, c0.data_compra) >= (select cutoff from hm_config limit 1)\n                          and coalesce(c0.data_aprovacao, c0.data_compra) < coalesce(c.data_aprovacao, c.data_compra)))', '');
--     execute d;
--   end $r$;
do $do$
declare
  d  text;
  a1 text := 'and coalesce(c.data_aprovacao, c.data_compra) >= (select cutoff from hm_config limit 1)';
  b1 text := E'and coalesce(c.data_aprovacao, c.data_compra) >= (select cutoff from hm_config limit 1)\n'
          || E'      and not (c.produto_id::text = ''3507214''  -- z53: mensalidade seguinte do HM antigo fora da fila\n'
          || E'           and exists (select 1 from compras c0 left join compradores cp0 on cp0.id = c0.comprador_id\n'
          || E'                        where c0.produto_id::text = ''3507214''\n'
          || E'                          and c0.status in (''APPROVED'',''COMPLETE'',''COMPLETED'')\n'
          || E'                          and (c0.comprador_id = c.comprador_id or lower(trim(cp0.email)) = lower(trim(cp.email)))\n'
          || E'                          and coalesce(c0.data_aprovacao, c0.data_compra) >= (select cutoff from hm_config limit 1)\n'
          || E'                          and coalesce(c0.data_aprovacao, c0.data_compra) < coalesce(c.data_aprovacao, c.data_compra)))';
begin
  d := pg_get_functiondef('public.fn_hm_fila()'::regprocedure);
  if position('z53: mensalidade' in d) > 0 then
    raise notice 'z53: fn_hm_fila já exclui a mensalidade seguinte';
  elsif (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 then
    raise exception 'z53: filtro do corte não encontrado (ou repetido) no corpo vigente de fn_hm_fila';
  else
    execute replace(d, a1, b1);
  end if;
end $do$;

-- PROVA (rodar como usuário do Financeiro; antes: 3507214 pendente = 32 → depois: 16, no máximo 1 por pessoa)
--   select f.categoria, f.aluno_novo, count(*) from public.fn_hm_fila() f join public.compras c on c.id = f.compra_id
--    where c.produto_id::text = '3507214' and f.bucket = 'pendente' group by 1, 2;
--   Total da fila de outros produtos: tem que ser IGUAL antes e depois.
