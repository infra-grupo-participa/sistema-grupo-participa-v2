-- 20260928z48 — Toda venda paga tem família (polimento, rodada 4).
-- Medido: 504 vendas pagas (R$ 3,23 mi) em 12 produtos ainda 'A_CLASSIFICAR' — fora de toda tela, do extrato e do grafo.
--   · PROGRAMA_DIAMANTE — "Diamante" 3094430 (101 vendas, R$ 2.191.221, dez/2023–mar/2026, taxa 4,00%, líquido 96%) e
--     "Diamante 2024" 1667105 (sem venda). É o programa/mentoria acima do Aurum — NÃO é o Serviço Diamante (família DIAMANTE).
--   · OUTROS — cursos e produtos de entrada antigos (403 vendas, R$ 1.036.584, 2021–2026): Programa de Aperfeiçoamento
--     (2022–23), Holding Familiar (2023–24), Zerando Dúvidas, Holding em 12/9 Passos, maisum2023, Tabela de Precificação,
--     Aula expressa, Porta de entrada, TIME HOLDING BRASIL, Kit de Diagnóstico… e os 25 produtos do catálogo sem venda.
-- Grafo de identidade (dry-run): 23.066 → 23.149 pessoas (compradores só desses produtos), 0 pessoas com 2+ CPFs,
-- 0 cards duplicados; 1 e-mail-ponte novo, que a z42 já tira sozinha.
-- Produto novo da Hotmart continua entrando como A_CLASSIFICAR (rotina diária) — a nota de confiança acusa quando vender.
-- Reverter: update fin.produtos set familia = 'A_CLASSIFICAR' where familia in ('PROGRAMA_DIAMANTE','OUTROS');
--           select fin.recalcular_identidade();
update fin.produtos
   set familia = case when produto_id in ('3094430','1667105') then 'PROGRAMA_DIAMANTE' else 'OUTROS' end
 where familia = 'A_CLASSIFICAR';

select fin.recalcular_identidade();
