// Formatação da Central do Tráfego. Valor nulo = "sem dado" (sem fonte ainda), nunca zero nem traço.
export const SEM_DADO = 'sem dado';

/** Tom do selo de status do projeto, o mesmo na tabela e na vida do projeto. */
export const tomStatus = (s: string | null | undefined): 'success' | 'warning' | 'neutral' =>
  s === 'ativo' ? 'success' : s === 'pausado' ? 'warning' : 'neutral';

const STATUS_PLATAFORMA: Record<string, string> = {
  ACTIVE: 'Ativa', PAUSED: 'Pausada', CAMPAIGN_PAUSED: 'Pausada', ADSET_PAUSED: 'Pausada', ARCHIVED: 'Arquivada',
  DELETED: 'Apagada', IN_PROCESS: 'Em processamento', WITH_ISSUES: 'Com problema', PENDING_REVIEW: 'Em análise',
  DISAPPROVED: 'Reprovada', ENABLED: 'Ativa', REMOVED: 'Removida',
};
/** Status que a plataforma manda (ex.: ACTIVE, PAUSED) em português; desconhecido aparece como veio. */
export const rotuloStatusPlataforma = (s: string | null | undefined): string => (s ? STATUS_PLATAFORMA[s.toUpperCase()] ?? s : '');

export const reais = (n: number | null | undefined) =>
  n == null ? SEM_DADO : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

export const centavos = (n: number | null | undefined) =>
  n == null ? SEM_DADO : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const pct = (n: number | null | undefined, casas = 1) =>
  n == null ? SEM_DADO : `${Number(n).toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas })}%`;

export const inteiro = (n: number | null | undefined) => (n == null ? SEM_DADO : Number(n).toLocaleString('pt-BR'));

export const dataBR = (ymd: string | null | undefined) => (ymd ? ymd.slice(0, 10).split('-').reverse().join('/') : SEM_DADO);
