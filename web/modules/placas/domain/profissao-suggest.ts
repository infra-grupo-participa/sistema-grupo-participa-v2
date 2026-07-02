// Ranking de sugestões de profissão — porta fiel da lógica do formulário legado.
// Puro (sem DOM) para ser testável e reutilizável no autocomplete.

import { PROFISSOES } from '../ui/solicitar-placa-constants';

/** Normaliza para comparação: minúsculas, sem acento, sem espaços nas pontas. */
export function normalizeProfission(value: string): string {
  return String(value || '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

/** Score de aderência de uma sugestão à consulta (maior = melhor). */
export function scoreProfissao(inputValue: string, option: string): number {
  const query = normalizeProfission(inputValue);
  const candidate = normalizeProfission(option);
  if (!query) return -1;
  if (candidate === query) return 1000;
  if (candidate.startsWith(query)) return 900 - (candidate.length - query.length);
  if (candidate.includes(query)) return 700 - candidate.indexOf(query);

  const queryTokens = query.split(/\s+/).filter(Boolean);
  let score = 0;
  for (const token of queryTokens) {
    const index = candidate.indexOf(token);
    if (index >= 0) score += 120 - index;
    else score -= 20;
  }
  return score;
}

/** Top-7 sugestões ordenadas por score (empate → ordem alfabética pt-BR). */
export function getProfissaoSuggestions(value: string): string[] {
  const query = String(value || '').trim();
  if (!query) return [];
  return PROFISSOES.map((option) => ({ option, score: scoreProfissao(query, option) }))
    .filter((item) => item.score >= 0)
    .sort((a, b) => b.score - a.score || a.option.localeCompare(b.option, 'pt-BR'))
    .slice(0, 7)
    .map((item) => item.option);
}
