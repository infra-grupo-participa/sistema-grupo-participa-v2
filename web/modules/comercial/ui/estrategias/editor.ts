// Regras puras do editor de público (tela de Estratégias). Sem React: testadas em editor.test.ts.
import type { FiltrosPublico, RegraPesquisa } from '../../domain/estrategias';

/** "fazer a minha, própria holding" → ['fazer a minha', 'própria holding'] (vírgula ou ponto e vírgula; sem repetidos). */
export function trechosDeTexto(texto: string): string[] {
  const vistos = new Set<string>();
  const out: string[] = [];
  for (const t of texto.split(/[;,]/).map((x) => x.trim()).filter(Boolean)) {
    const k = t.toLowerCase();
    if (!vistos.has(k)) { vistos.add(k); out.push(t); }
  }
  return out;
}

export function textoDeTrechos(t: string[]): string {
  return t.join(', ');
}

/** Troca um pedaço dos filtros sem mexer no resto (imutável). */
export function comBloco<K extends keyof FiltrosPublico>(f: FiltrosPublico, chave: K, valor: FiltrosPublico[K]): FiltrosPublico {
  return { ...f, [chave]: valor };
}

export function comRegra(f: FiltrosPublico, i: number, r: RegraPesquisa | null): FiltrosPublico {
  const regras = [...(f.respondi?.regras ?? [])];
  if (r === null) regras.splice(i, 1);
  else if (i >= regras.length) regras.push(r);
  else regras[i] = r;
  return { ...f, respondi: { regras } };
}

/** Quantos filtros estão ativos (para o rótulo "Filtros (3)"). */
export function contarFiltros(f: FiltrosPublico): number {
  const n = (a?: string[]) => (a?.length ? 1 : 0);
  return n(f.alunos?.niveis) + n(f.alunos?.turmas) + n(f.alunos?.tiposTurma) + n(f.alunos?.planos) + n(f.alunos?.statusAcesso)
    + n([...(f.comprou?.produtos ?? []), ...(f.comprou?.linhas ?? [])])
    + n([...(f.naoComprou?.produtos ?? []), ...(f.naoComprou?.linhas ?? [])])
    + (f.respondi?.regras.length ?? 0) + n(f.catalogacao?.projetos) + n(f.catalogacao?.canais);
}
