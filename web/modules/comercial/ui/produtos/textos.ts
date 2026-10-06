// Textos do (i) dos números dos cartões de Produtos e ofertas.
import type { TextoIndicador } from '../InfoIndicador';

export const INFO_TRANSACOES: TextoIndicador = {
  nome: 'Transações da oferta',
  oQueE: 'Quantas vendas a Hotmart registrou com este código de oferta.',
  comoConta: 'Transações sincronizadas da Hotmart com o código, de qualquer status, desde a primeira venda.',
  paraQue: 'Mostra se a oferta está sendo usada de fato. Oferta vigente sem transação pede revisão.',
};

export const INFO_TRANSACOES_ORFA: TextoIndicador = {
  nome: 'Transações fora do catálogo',
  oQueE: 'Vendas da Hotmart com este código, que o catálogo do comercial não reconhece.',
  comoConta: 'Transações sincronizadas com o código desde a primeira aparição.',
  paraQue: 'Cada uma é uma venda que não vira pagamento no sistema até o código ser catalogado.',
  meta: 'Zero.',
};

export const INFO_VIGENTES: TextoIndicador = {
  nome: 'Ofertas vigentes do produto',
  oQueE: 'Ofertas deste produto que o vendedor pode oferecer hoje.',
  comoConta: 'Marcadas como vigentes e dentro da validade. Marcada com validade vencida aparece à parte, em vermelho.',
  paraQue: 'Produto sem oferta vigente não deve ser abordado.',
  meta: 'Ao menos uma.',
};
