-- 20260929z78 — Devolve ao funil "2º Encontro Acelera Holding (28/09/2026)" (fin.acoes 135)
-- as vendas de HM feitas a partir de 28/09 (pedido do Marcio, 29/09, depois da reversão da z74).
--
-- Mesmo critério da z74 (compra HM não recorrente, pedida/aprovada desde 28/09 00:00 BRT),
-- EXCETO o card de entrada HT30 (sinal R$ 697 em 11/08, contato 0ce9d20e…): ele entrou no
-- Programa pelo HT30 e o boleto de 28/09 já aparece como "Voltou em" (z75). Pô-lo como
-- entrada no 2º Encontro tiraria o HT30 da contagem e o card diria "Entrou por 2º Encontro,
-- voltou na Imersão". Para incluir: um insert com o id dele.
-- Reversão: delete from fin.acao_card_manual where definido_por = 'migration 20260929z78';

insert into fin.acao_card_manual (contato_hm_id, acao_id, motivo, definido_por)
select distinct b.contato_hm_id, 135,
       'venda de 28–29/09, funil do 2º Encontro Acelera (pedido do Marcio em 29/09)',
       'migration 20260929z78'
  from cs.vw_fin_board b
  join fin.vw_transacoes x on lower(trim(x.email)) = lower(trim(b.email))
 where b.origem = 'HM'
   and x.produto_id = '5064314'
   and coalesce(x.recorrencia, 1) = 1
   and greatest(x.pedido_em, coalesce(x.aprovado_em, x.pedido_em)) >= timestamptz '2026-09-28 00:00-03'
   and b.contato_hm_id <> '0ce9d20e-80f5-408a-b1a8-912e6fff8599'
on conflict (contato_hm_id) do nothing;
