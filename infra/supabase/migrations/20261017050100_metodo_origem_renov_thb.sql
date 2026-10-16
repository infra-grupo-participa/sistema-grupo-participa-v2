-- 20261017050100: de-para da origem 'renov-thb' (página hm.timeholdingbrasil.com.br/renov, tabela metodo.renov_aplicacoes)
--   para a etiqueta do projeto black-thb-2026-10, em metodo.origem_etiqueta. Mesmo desenho de 20261014200100 (renovacao-thb-vencidos).
--
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026 (branch victor-renov-padrao). Só foi rodado o ENSAIO (begin ... rollback).
--   Ensaio: 20261017050100_ensaio.sql. Reversão: 20261017050100_reversao.sql. Detalhe: 20261017050100.explain.md.
--
-- POR QUE: metodo.renov_aplicacoes não tem coluna de chave/etiqueta (a Edge renov-thb grava só origem = 'renov-thb', fixa). Para o painel
--   /renov e a marcação de teste saberem de qual ação as aplicações são, a chave sai deste de-para, que já é o lugar onde a casa liga
--   "origem da inscrição" a "etiqueta do projeto" (a mesma do ClickUp, do utm_campaign e do Active). Quando a página servir outra ação,
--   é uma linha aqui, sem mexer em tabela, Edge ou função.
-- O QUE FAZ: 1 linha em metodo.origem_etiqueta ('renov-thb' -> 'black-thb-2026-10'). Nada mais.
-- EFEITO COLATERAL CONHECIDO: o gatilho metodo.pesquisa_respostas_etiqueta também lê esta tabela, mas só para metodo.pesquisa_respostas.
--   Não existe nenhuma pesquisa_respostas com origem 'renov-thb' (0 linhas em 16/10/2026): nada é preenchido por acidente.
-- COMO VOLTAR: 20261017050100_reversao.sql.
-- AS 5 PERGUNTAS: escala = 1 linha (a tabela tem 2); busca por chave primária (origem). índice = a PK. frequência = uma vez.
--   repetição = a guarda aborta se a origem já estiver no de-para. reversão = arquivo de reversão.
-- DADO PESSOAL: nenhum.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('metodo.origem_etiqueta') is null then
    raise exception '20261017050100: falta metodo.origem_etiqueta (20261014200000)';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null then
    raise exception '20261017050100: falta metodo.renov_aplicacoes (20261016163924, Arthur)';
  end if;
  if exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb') then
    raise exception '20261017050100: renov-thb já está no de-para; revisar';
  end if;
  if not exists (select 1 from dados.dashboards where chave = 'black-thb-2026-10' and modelo = 'acao-black') then
    raise exception '20261017050100: black-thb-2026-10 não existe como acao-black';
  end if;
  if exists (select 1 from metodo.pesquisa_respostas where origem = 'renov-thb') then
    raise exception '20261017050100: já existe pesquisa_respostas com origem renov-thb; o gatilho passaria a etiquetar essas linhas. Revisar';
  end if;
end
$g$;

insert into metodo.origem_etiqueta (origem, etiqueta) values ('renov-thb', 'black-thb-2026-10');
