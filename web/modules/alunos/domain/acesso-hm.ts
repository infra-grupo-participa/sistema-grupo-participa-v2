// Domínio da fila de Acesso HM (Holding Masters) — liberações, renovações e
// pendências de diferença. Espelha o retorno do RPC fn_hm_fila (SECURITY DEFINER).
// Processo em duas etapas: ATIVAÇÃO (turma + matrícula) e LIBERAÇÃO DE ACESSO (Hotmart).

export type HmBucket =
  | 'liberacoes'
  | 'renovacoes'
  | 'aguardando_diferenca'
  | 'nao_classificado'
  | 'concluido';

export type HmEtapa = 'ativacao' | 'acesso';

type BadgeTone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

export interface HmFilaItem {
  compraId: string;
  alunoId: string | null;
  compradorId: string | null;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  offerCode: string | null;
  ofertaLabel: string | null;
  categoria: string | null;
  preco: number | null;
  dataCompra: string | null;
  bucket: HmBucket;
  jaEraAlunoHm: boolean;
  sinalQuitado: boolean;
  needsAtivacao: boolean;
  turmaId: number | null;
  turmaCodigo: string | null;
  ativadoEm: string | null;
  ativadoPorNome: string | null;
  acessoEm: string | null;
  acessoPorNome: string | null;
  ignoradoEm: string | null;
  obs: string | null;
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

/** Metadados das sub-abas (ordem, rótulo, ícone). */
export const HM_BUCKETS: { key: HmBucket; label: string; icon: string; acionavel: boolean }[] = [
  { key: 'liberacoes', label: 'Liberações', icon: 'lock', acionavel: true },
  { key: 'renovacoes', label: 'Renovações', icon: 'refresh', acionavel: true },
  { key: 'aguardando_diferenca', label: 'Aguardando diferença', icon: 'pause', acionavel: true },
  { key: 'nao_classificado', label: 'Não classificados', icon: 'tags', acionavel: true },
  { key: 'concluido', label: 'Concluídos', icon: 'check-circle', acionavel: false },
];

/** Buckets que somam no badge principal da aba (pendências acionáveis de acesso). */
export const HM_BADGE_BUCKETS: HmBucket[] = ['liberacoes', 'renovacoes'];

export function hmBadgeTotal(contagem: Record<string, number>): number {
  return HM_BADGE_BUCKETS.reduce((s, b) => s + (contagem[b] ?? 0), 0);
}

/** Etapas aplicáveis a um item: renovação/aluno existente só precisa de acesso;
 *  aluno novo precisa de ativação (turma) + acesso. */
export function etapasDoItem(item: HmFilaItem): HmEtapa[] {
  return item.needsAtivacao ? ['ativacao', 'acesso'] : ['acesso'];
}

/** Turma obrigatória antes de ativar: aluno novo sem turma definida. */
export function turmaPendente(item: HmFilaItem): boolean {
  return item.needsAtivacao && item.turmaId == null;
}
