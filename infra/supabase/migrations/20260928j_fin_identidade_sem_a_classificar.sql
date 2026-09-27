-- 20260928j — A identidade não usa produto 'A_CLASSIFICAR' (achado do pentest, 27/09/2026).
-- fin.recalcular_identidade junta e-mails pelo CPF de QUALQUER transação espelhada. O 446345 (20260928h) traz
-- compradores de 2019–2024 de um produto ainda sem uso decidido: cônjuges com o mesmo CPF e e-mails diferentes
-- virariam uma pessoa só no board, no extrato e no pro rata. Até o João classificar o produto, as transações dele
-- ficam fora do grafo. Medido antes de aplicar: último recálculo 18:20 UTC, 1ª transação do 446345 às 18:55 UTC —
-- o grafo ainda não tinha sido tocado.
-- Recria a partir do corpo VIGENTE trocando a tabela pela view filtrada (9 leituras; as 2 do resumo jsonb final continuam na tabela inteira).
create or replace view fin.hotmart_transacoes_identidade as
select t.* from fin.hotmart_transacoes t
 where not exists (select 1 from fin.produtos p where p.produto_id = t.produto_id and p.familia = 'A_CLASSIFICAR');
revoke all on fin.hotmart_transacoes_identidade from public, anon, authenticated;

do $do$
declare v text; n int;
begin
  v := pg_get_functiondef('fin.recalcular_identidade()'::regprocedure);
  n := (length(v) - length(replace(v, 'fin.hotmart_transacoes ', ''))) / length('fin.hotmart_transacoes ');
  if n <> 9 then raise exception 'fin.recalcular_identidade: esperava 9 leituras de fin.hotmart_transacoes, achei %', n; end if;
  execute replace(v, 'fin.hotmart_transacoes ', 'fin.hotmart_transacoes_identidade ');
end $do$;

-- Achado BAIXO do mesmo pentest: o diagnóstico do pro rata classificava a venda com coalesce(catálogo, papel do produto)
-- enquanto a lista (fn_fin_prorata_hm, 20260928i) já usa fin.oferta_categoria — a mesma venda aparecia "compra cheia
-- (inferida)" na lista e "principal" no porquê. Recria do corpo VIGENTE trocando só a expressão (1 ocorrência).
do $do$
declare v text; alvo text := $a$case when t.oferta_modo = 'SUBSCRIPTION' then 'mensalidade'
                     else coalesce((select min(c.categoria) from public.hm_product_catalog c where c.offer_code = t.oferta_codigo), t.papel_produto) end forma$a$;
begin
  v := pg_get_functiondef('public.fn_fin_prorata_diagnostico(text,date,numeric)'::regprocedure);
  if position(alvo in v) = 0 then raise exception 'fn_fin_prorata_diagnostico: expressão da forma não encontrada no corpo vigente'; end if;
  execute replace(v, alvo, 'fin.oferta_categoria(t.oferta_codigo, t.oferta_modo, t.valor_oferta) forma');
end $do$;
