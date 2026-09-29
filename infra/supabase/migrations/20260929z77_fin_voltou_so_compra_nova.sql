-- 20260929z77 — "Voltou em" conta só COMPRA NOVA (sinal ou HM cheio), não pagamento de saldo
--
-- Medido após a z75: 82 cards com voltou_*, 78 deles por transação `diferenca` (saldo do
-- próprio contrato, pago dentro de outra janela de ação). Pagar o saldo não é voltar:
-- o card diria "Voltou em Comercial" para quem só quitou a parcela. Restam os casos reais
-- (ex.: HT30 → boleto HM cheio na Imersão HT32).
-- Troca só o array de categorias do retorno_ok; o critério de entrada não muda.
-- Reversão: mesmo replace ao contrário.

do $$
declare
  v_def text := pg_get_viewdef('fin.vw_acao_card'::regclass, true);
  v_de  text := 'ARRAY[''sinal''::text, ''compra_cheia''::text, ''diferenca''::text]';
  v_por text := 'ARRAY[''sinal''::text, ''compra_cheia''::text]';
begin
  if position(v_de in v_def) = 0 then
    raise exception 'z77: trecho do retorno_ok não encontrado na view viva';
  end if;
  execute 'create or replace view fin.vw_acao_card as ' || replace(v_def, v_de, v_por);
end $$;

revoke all on fin.vw_acao_card from public, anon, authenticated;
