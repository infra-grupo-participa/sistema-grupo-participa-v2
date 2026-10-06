// Regras de apresentação do caso — puras, testáveis.
import type { Tone } from '@/shared/ui/components';
import type { CasoFila, Linha, MeuItem, OrigemCaso, StatusCaso, Sugestao, TipoCaso } from './types';

export const ROTULO_STATUS: Record<StatusCaso, string> = {
  alerta: 'Disputa (alerta)',
  aguardando_triagem: 'Aguardando triagem',
  em_remocao: 'Removendo acessos',
  ajustando_acesso: 'Ajustar acesso',
  mantem_acesso: 'Mantém acesso antigo',
  concluido: 'Concluído',
};

export const TOM_STATUS: Record<StatusCaso, Tone> = {
  alerta: 'info',
  aguardando_triagem: 'warning',
  em_remocao: 'accent',
  ajustando_acesso: 'warning',
  mantem_acesso: 'neutral',
  concluido: 'success',
};

export const ROTULO_TIPO: Record<TipoCaso, string> = {
  reembolso: 'Reembolso',
  chargeback: 'Chargeback',
  disputa: 'Disputa',
  troca_socio: 'Troca de sócio',
};

export const ROTULO_LINHA: Record<Linha, string> = {
  hm: 'Holding Masters',
  acelera: 'Acelera Holding',
};

/** Caso sem `linha` (banco antes da migration do Acelera) é do Holding Masters, a única linha que existia. */
export function linhaDoCaso(c: Pick<CasoFila, 'linha'>): Linha {
  return c.linha === 'acelera' ? 'acelera' : 'hm';
}

export function filtrarLinha<T extends Pick<CasoFila, 'linha'>>(casos: T[], linha: Linha): T[] {
  return casos.filter((c) => linhaDoCaso(c) === linha);
}

/** No HM, "alerta" é sempre disputa. No Acelera também cobre o reembolso de quem ainda tem outra
 *  compra válida, então o rótulo não pode dizer "Disputa". */
export function rotuloStatus(c: Pick<CasoFila, 'status' | 'linha'>): string {
  if (c.status === 'alerta' && linhaDoCaso(c) === 'acelera') return 'Alerta';
  return ROTULO_STATUS[c.status];
}

export const ROTULO_ORIGEM: Record<OrigemCaso, string> = {
  compras: 'compra no sistema',
  webhook: 'webhook da remoção',
  pedido_alteracao: 'pedido de alteração',
  carga: 'carga de casos antigos',
};

/** Rótulo da data do caso: nos importados (carga) o financeiro só guarda a data da compra, não a do reembolso. */
export function rotuloDataCaso(c: { origem?: OrigemCaso | string | null }): 'Compra em' | 'Ocorreu em' {
  return c.origem === 'carga' ? 'Compra em' : 'Ocorreu em';
}

/** Linha de um item do catálogo: a que o banco mandar; sem ela, pela chave (`acelera_*` é do Acelera). */
export function linhaDoItem(i: { item: string; linha?: Linha | null }): Linha {
  if (i.linha === 'acelera' || i.linha === 'hm') return i.linha;
  return i.item.startsWith('acelera_') ? 'acelera' : 'hm';
}

/** Itens de quem está logado que são da linha pedida. Separa pela chave, não pelo rótulo
 *  (há "Obvio" no HM e no Acelera). O formato antigo (só rótulo) é todo do HM. */
export function meusItensDaLinha(itens: MeuItem[] | null | undefined, linha: Linha): string[] {
  return (itens ?? []).flatMap((i) => {
    if (typeof i === 'string') return linha === 'hm' ? [i] : [];
    return linhaDoItem(i) === linha ? [i.rotulo] : [];
  });
}

export const ABERTOS: StatusCaso[] = ['aguardando_triagem', 'em_remocao', 'ajustando_acesso'];

export type SituacaoPrazo = 'sem_prazo' | 'no_prazo' | 'vence_hoje' | 'atrasado' | 'encerrado';

/** Situação do prazo de 1 dia útil. Caso encerrado não tem mais prazo correndo.
 *  Prazo nulo ou ausente (casos da carga) = sem prazo, nunca atrasado. */
export function situacaoPrazo(c: Pick<CasoFila, 'status' | 'prazo_em'>, agora: Date): SituacaoPrazo {
  if (!ABERTOS.includes(c.status)) return 'encerrado';
  if (!c.prazo_em) return 'sem_prazo';
  const prazo = new Date(c.prazo_em);
  if (Number.isNaN(prazo.getTime())) return 'sem_prazo';
  if (prazo.getTime() < agora.getTime()) return 'atrasado';
  const dia = (d: Date) => d.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
  return dia(prazo) === dia(agora) ? 'vence_hoje' : 'no_prazo';
}

export type Filtro = 'abertos' | 'meus' | 'alertas' | 'encerrados' | 'todos';

/** Filtro da fila. Com `linha`, considera só os casos daquela linha. "Meus" vem do banco
 *  (`meus_pendentes`, contado pelo responsável de cada item), não do rótulo do item. */
export function filtrarCasos(todos: CasoFila[], filtro: Filtro, linha?: Linha): CasoFila[] {
  const casos = linha ? filtrarLinha(todos, linha) : todos;
  switch (filtro) {
    case 'abertos': return casos.filter((c) => ABERTOS.includes(c.status));
    case 'meus': return casos.filter((c) => c.meus_pendentes > 0);
    case 'alertas': return casos.filter((c) => c.status === 'alerta');
    case 'encerrados': return casos.filter((c) => c.status === 'concluido' || c.status === 'mantem_acesso');
    default: return casos;
  }
}

/** Pré-preenchimento do "não remover": a expiração que valia antes desta compra
 *  (pelo histórico de mudanças da base) e a instrução sem o Programa de Implementação.
 *  Só sugere; quem decide é o triador. */
export function sugestaoAjuste(s: Sugestao | null | undefined): { expiracao: string; instrucao: string } {
  const atual = s?.aluno?.data_expiracao ?? null;
  const mudanca = (s?.historico_expiracao ?? []).find((h) => atual && h.para === atual && h.de);
  const expiracao = mudanca?.de && /^\d{4}-\d{2}-\d{2}$/.test(mudanca.de) ? mudanca.de : '';
  const inst = s?.aluno?.instrucao ?? '';
  const instrucao = inst.startsWith('THB IMPLEMENTAÇÃO') ? inst.replace('THB IMPLEMENTAÇÃO', 'THB') : '';
  return { expiracao, instrucao };
}
