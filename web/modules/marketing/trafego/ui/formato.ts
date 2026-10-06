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

/**
 * Quebra da receita do projeto por nível de certeza (decisão do Victor, 06/10/2026), para o tooltip da Central e o
 * detalhe da vida do projeto. A receita do projeto = níveis 1 a 3; a estimada (nível 4) vem à parte e não soma.
 */
export interface LinhaQuebra { rotulo: string; valor: number | null | undefined; vendas: number | null | undefined }
export function quebraReceita(l: {
  receita_oferta?: number | null; receita_sck?: number | null; receita_lead?: number | null; receita_estimada?: number | null;
  receita_compras_oferta?: number | null; receita_compras_sck?: number | null; receita_compras_lead?: number | null;
  receita_compras_estimada?: number | null;
}): LinhaQuebra[] {
  return [
    { rotulo: '1. Oferta exclusiva (certa)', valor: l.receita_oferta, vendas: l.receita_compras_oferta },
    { rotulo: '2. SCK com o projeto (certa)', valor: l.receita_sck, vendas: l.receita_compras_sck },
    { rotulo: '3. Lead do projeto (provável)', valor: l.receita_lead, vendas: l.receita_compras_lead },
    { rotulo: '4. Estimada, só produto + período (à parte, não soma)', valor: l.receita_estimada, vendas: l.receita_compras_estimada },
  ];
}

/** O texto do tooltip da coluna Receita: a quebra por nível e as vendas em disputa. */
export function tituloReceita(l: Parameters<typeof quebraReceita>[0] & { receita_disputa?: number | null }): string {
  const linhas = quebraReceita(l).map((q) => `${q.rotulo}: ${reais(q.valor)}${q.vendas ? ` (${inteiro(q.vendas)} venda(s))` : ''}`);
  if (l.receita_disputa) linhas.push(`Em disputa com outro projeto (não somam): ${inteiro(l.receita_disputa)} venda(s)`);
  return ['Receita do projeto = níveis 1 a 3.', ...linhas].join('\n');
}
