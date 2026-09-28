-- 20260928s — Serviço Diamante vira a família 'DIAMANTE' (depois do histórico completo, 2017→hoje).
-- Efeitos: Faturamento, Relatórios e Ofertas ganham "Serviço Diamante" com a mesma lógica das outras famílias; os
-- compradores entram no grafo de identidade (e-mails da mesma pessoa se juntam; a junção foi medida antes — ver
-- o Diário de 27/09); o extrato da ficha passa a mostrar as mensalidades de serviço.
-- O board do Serviço Diamante (fn_fin_diamante_servicos) não depende da família: lê papel = 'servico'.
-- "Dependência de eventos" não se aplica: as ações de fin.acoes são do HM/Aurum, não de serviço.
-- Reverter: update fin.produtos set familia = 'A_CLASSIFICAR' where produto_id = '1462643'; select fin.recalcular_identidade();
update fin.produtos set familia = 'DIAMANTE' where produto_id = '1462643';
select fin.recalcular_identidade();

do $do$
declare v text; a text := $a$where a.produto = case when p_familia = 'AURUM' then 'AURUM' else 'HM' end$a$;
begin
  v := pg_get_functiondef('public.fn_fin_faturamento_por_acao(text)'::regprocedure);
  if position(a in v) = 0 then raise exception 'trecho do produto não encontrado'; end if;
  execute replace(v, a, $b$where a.produto = case when p_familia = 'AURUM' then 'AURUM' when p_familia in ('HM','ACELERA') then 'HM' end$b$);
end $do$;
