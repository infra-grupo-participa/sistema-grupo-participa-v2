// Abas da ficha do aluno e o estado delas na URL (`#aluno=<id>&aba=<k>`).
// Estado puro de UI: vai no hash por `history.replaceState` (sem navegação do Next, 0 request).

export type AbaFicha = 'resumo' | 'programa' | 'jornada' | 'trajetoria' | 'curso';
export const ABAS_FICHA: readonly AbaFicha[] = ['resumo', 'programa', 'jornada', 'trajetoria', 'curso'];

export function ehAbaFicha(k: unknown): k is AbaFicha {
  return typeof k === 'string' && (ABAS_FICHA as readonly string[]).includes(k);
}

/** Lê `#aluno=<id>&aba=<k>`. Sem `aluno` → null; aba desconhecida → null (quem chama cai em Resumo). */
export function lerHashFicha(hash: string): { alunoId: string; aba: AbaFicha | null } | null {
  const p = new URLSearchParams(hash.replace(/^#/, ''));
  const alunoId = (p.get('aluno') || '').trim();
  if (!alunoId) return null;
  const aba = p.get('aba');
  return { alunoId, aba: ehAbaFicha(aba) ? aba : null };
}

export function montarHashFicha(alunoId: string, aba: AbaFicha): string {
  return `#${new URLSearchParams({ aluno: alunoId, aba }).toString()}`;
}
