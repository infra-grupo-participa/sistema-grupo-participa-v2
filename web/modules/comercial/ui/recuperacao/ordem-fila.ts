// Ordem da fila de recuperação (processo montar-fila-de-recuperacao.md + script de recuperação).
// Puro e testável: a tela só chama `ordenarFila`.
import { faixaLiberada } from '../../domain/regras';
import type { FaixaScore, ItemFila, SinalRecuperacao, StatusFila } from '../../domain/types';

/** Grupos da ordem do playbook, do 1 (primeiro a abordar) ao 8 (o resto). */
export const GRUPOS_ORDEM: { n: number; rotulo: string }[] = [
  { n: 1, rotulo: 'Respondeu e ficou sem retorno' },
  { n: 2, rotulo: 'Ficha completa + senhas' },
  { n: 3, rotulo: 'Senhas, sem ficha' },
  { n: 4, rotulo: 'Cartão recusado' },
  { n: 5, rotulo: 'Boleto' },
  { n: 6, rotulo: 'Ficha completa com parceria' },
  { n: 7, rotulo: 'Carrinho com algum sinal' },
  { n: 8, rotulo: 'O resto' },
];

/** Em qual grupo da ordem a pessoa cai, pelo sinal mais forte que ela tem. */
export function grupoPrioridade(sinais: SinalRecuperacao[]): number {
  const s = new Set(sinais);
  if (s.has('respondeu_sem_retorno')) return 1;
  if (s.has('ficha_completa') && s.has('senhas')) return 2;
  if (s.has('senhas')) return 3;
  if (s.has('cartao_recusado')) return 4;
  if (s.has('boleto_aberto')) return 5;
  if (s.has('ficha_completa') && s.has('quer_parceria')) return 6;
  if (s.has('carrinho') && s.size > 1) return 7;
  return 8;
}

/** Status que tiram a pessoa da fila de trabalho (ganho ou saída). */
export const STATUS_ENCERRADOS: StatusFila[] = ['ganho', 'sem_resposta', 'declinou', 'sem_interesse', 'numero_invalido'];

export function encerrado(status: StatusFila): boolean {
  return STATUS_ENCERRADOS.includes(status);
}

/**
 * Ordena a fila: quem ainda está em trabalho antes dos encerrados; dentro disso, o grupo do playbook;
 * dentro do grupo, score maior primeiro. Não altera o array recebido.
 */
export function ordenarFila<T extends Pick<ItemFila, 'id' | 'sinais' | 'score' | 'status'>>(itens: T[]): T[] {
  return [...itens].sort((a, b) =>
    Number(encerrado(a.status)) - Number(encerrado(b.status))
    || grupoPrioridade(a.sinais) - grupoPrioridade(b.sinais)
    || b.score - a.score
    || a.id.localeCompare(b.id));
}

/** Pendentes de A e B = itens A/B ainda "A abordar". Enquanto houver, C e D ficam travadas. */
export function pendentesAB(itens: Pick<ItemFila, 'faixa' | 'status'>[]): number {
  return itens.filter((i) => (i.faixa === 'A' || i.faixa === 'B') && i.status === 'a_abordar').length;
}

/** Atalho: a faixa pode ser trabalhada agora nesta fila? */
export function itemLiberado(faixa: FaixaScore, itens: Pick<ItemFila, 'faixa' | 'status'>[]): boolean {
  return faixaLiberada(faixa, pendentesAB(itens));
}
