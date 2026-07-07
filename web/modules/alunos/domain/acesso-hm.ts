// Domínio da lista de Acesso HM (Holding Masters) — notificação + controle das
// compras/renovações que exigem o operador liberar o acesso manualmente.
// Espelha fn_hm_fila (SECURITY DEFINER). Só entram compras a partir do corte (hm_config.cutoff).

export type HmBucket = 'pendente' | 'concluido';

/** Abas da UI: pendentes divididos por natureza da compra + concluídos. */
export type HmTab = 'nova' | 'renovacao' | 'concluido';

type BadgeTone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

export interface HmFilaItem {
  compraId: string;
  alunoId: string | null;
  compradorId: string | null;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  documento: string | null;
  offerCode: string | null;
  ofertaLabel: string | null;
  categoria: string | null;
  preco: number | null;
  dataCompra: string | null;
  bucket: HmBucket;
  alunoNovo: boolean;
  turmaId: number | null;
  turmaCodigo: string | null;
  acessoEm: string | null;
  acessoPorNome: string | null;
  ignoradoEm: string | null;
  obs: string | null;
  /** Aluno já existia na base (importado antes desta compra) apesar de ser novo no HM — caso de exceção. */
  jaCadastrado: boolean;
}

export interface TurmaThb {
  id: number;
  codigo: string;
  atual: boolean;
}

/** Rótulo + tom (dot da Badge) por categoria de oferta. */
export const HM_CATEGORIA_LABEL: Record<string, { label: string; tone: BadgeTone }> = {
  compra_cheia: { label: 'Compra cheia', tone: 'success' },
  renovacao: { label: 'Renovação', tone: 'info' },
  sinal: { label: 'Sinal', tone: 'warning' },
  reserva: { label: 'Reserva de vaga', tone: 'warning' },
  diferenca: { label: 'Diferença', tone: 'neutral' },
};

/** Sub-abas: compras novas (ação), renovações (ação) e concluídos (histórico). */
export const HM_TABS: { key: HmTab; label: string; icon: string; acionavel: boolean }[] = [
  { key: 'nova', label: 'Compras novas', icon: 'inbox', acionavel: true },
  { key: 'renovacao', label: 'Renovações', icon: 'refresh', acionavel: true },
  { key: 'concluido', label: 'Concluídos', icon: 'check-circle', acionavel: false },
];

/** Aba do item, derivada do bucket + categoria (renovação só entre os pendentes). */
export function hmTab(item: HmFilaItem): HmTab {
  if (item.bucket === 'concluido') return 'concluido';
  return item.categoria === 'renovacao' ? 'renovacao' : 'nova';
}

/** Abas que somam no badge geral (pendências acionáveis). */
export const HM_BADGE_TABS: HmTab[] = ['nova', 'renovacao'];

export function hmBadgeTotal(contagem: Record<string, number>): number {
  return HM_BADGE_TABS.reduce((s, b) => s + (contagem[b] ?? 0), 0);
}

/** Turma obrigatória antes de liberar: aluno novo sem turma definida. */
export function turmaPendente(item: HmFilaItem): boolean {
  return item.alunoNovo && item.turmaId == null;
}

/**
 * Exceção a tratar com atenção: entra como compra nova no HM (aluno_novo),
 * mas o aluno já existia na base antes desta compra. Sinal de que veio de
 * outro fluxo (planilha/backfill/HT) — o operador deve conferir antes de liberar.
 */
export function alunoExcecao(item: HmFilaItem): boolean {
  return item.alunoNovo && item.jaCadastrado;
}

/** Bloco de dados do aluno para cadastro manual na área de membros (compra e renovação). */
export function dadosAreaMembros(item: HmFilaItem): string {
  return [
    `Nome: ${item.nome ?? '—'}`,
    `E-mail: ${item.email ?? '—'}`,
    `Telefone: ${item.telefone ?? '—'}`,
    `CPF/CNPJ: ${item.documento ?? '—'}`,
    item.turmaCodigo ? `Turma: ${item.turmaCodigo}` : null,
  ].filter(Boolean).join('\n');
}
