-- 20260928l — O "Curso Prático de Holding Familiar" (446345) é HM. Decisão do João, 27/09/2026:
-- "acho que todas... por mais que o nome seja outro na época, o conteúdo é o mesmo... a gente vai ter uma visão
-- macro de como funcionava, como eram as ofertas na época, qual oferta mais vendeu".
-- O produto INTEIRO entra (2019–2024, R$ 31,0 mi líquidos, 7.746 vendas pagas; o total bate com o sales/summary
-- da Hotmart ao centavo: 31.035.461,91). Papel 'legado': é o HM de antes do produto 5064314 (02/2025).
-- Efeitos: Faturamento/Relatórios/Ofertas/Pessoas do HM passam a contar a história desde 2019; os compradores
-- entram no grafo de identidade (o filtro A_CLASSIFICAR de 20260928j/k deixa de excluí-lo). O "pago" do card
-- do board não muda (escopo sinal/diferenca/compra_cheia do catálogo). O ciclo do pro rata é o último ano antes
-- do vencimento, então vendas até 01/2025 raramente entram.
-- Reverter: update fin.produtos set familia = 'A_CLASSIFICAR' where produto_id = '446345'; select fin.recalcular_identidade();
update fin.produtos
   set familia = 'HM', papel = 'legado',
       nota = 'HM antigo (2019–2024), vendido como "Curso Prático de Holding Familiar". Incluído no HM por decisão do João em 27/09/2026.'
 where produto_id = '446345';
select fin.recalcular_identidade();

-- A história do HM agora começa em 10/2019: a releitura semanal (reembolso/chargeback de venda velha) passa a ir até 2019.
select cron.schedule('fin-hotmart-sync-historia', '13 2 * * 0',
  $$ select fin.hotmart_sync_enfileirar(((now() at time zone 'America/Sao_Paulo')::date - date '2019-01-01')) $$);

-- Aplicado à parte, como DADO (não roda de novo numa reconstrução): 1 CPF em fin.identidade_bloqueio.
-- Na inclusão, 15 pessoas antigas foram juntadas no grafo. Conferidas uma a uma:
--   * 12 corretas (mesmo nome, ou mesma pessoa com outro e-mail ou CPF/CNPJ).
--   * 2 são compra paga com o CPF de outra pessoa (cônjuge/família); a compra é do dono do CPF, e ficam juntas.
--   * 1 juntava dois alunos distintos, cada um com cadastro próprio. O CPF que fazia a ponte foi bloqueado.
