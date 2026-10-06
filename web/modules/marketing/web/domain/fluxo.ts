// Marketing > Web > Fluxo: rótulos e contas do caminho entre páginas (puro). Os números vêm de public.mkt_web_fluxo
// (migration 20261005q): a visita vira uma sequência de caminhos (recarregar a mesma página não é passo).
import type { Fluxo } from './tipos';

export const SAIU = '(saiu)';

/** "/ak1/" → "AK1 (/ak1/)" quando a página está cadastrada; "(saiu)" → "Saiu do site" */
export function rotuloCaminho(caminho: string, nomes: Record<string, string>): string {
  if (caminho === SAIU) return 'Saiu do site';
  const nome = nomes[caminho];
  return nome ? `${nome} (${caminho})` : caminho;
}

/** para cada página de origem (da mais movimentada para a menos), os destinos em ordem, com a fatia de cada um */
export function destinosPorOrigem(f: Fluxo): { de: string; total: number; destinos: { para: string; n: number; leads: number; fatia: number }[] }[] {
  const grupos = new Map<string, { para: string; n: number; leads: number }[]>();
  for (const p of f.passagens) grupos.set(p.de, [...(grupos.get(p.de) ?? []), { para: p.para, n: p.n, leads: p.leads }]);
  return [...grupos.entries()]
    .map(([de, ds]) => {
      const total = ds.reduce((s, d) => s + d.n, 0);
      return { de, total, destinos: ds.sort((a, b) => b.n - a.n).map((d) => ({ ...d, fatia: total ? d.n / total : 0 })) };
    })
    .sort((a, b) => b.total - a.total);
}

/** a sequência em texto: "AK1 › Obrigado" (com "…" quando a visita passou de 5 passos) */
export const textoCaminho = (passos: string[], mais: boolean, nomes: Record<string, string>) =>
  passos.map((c) => nomes[c] ?? c).join(' › ') + (mais ? ' › …' : '');
