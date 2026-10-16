/**
 * Evolução diária do ingresso no grupo (padrão de todo card de ingresso no grupo, pedido do Victor em 16/10/2026).
 *
 * Entrada: as linhas de `dados_atm_serie_diaria` (uma por dia: `dia`, `leads`, `grupo_entradas`). Saída: por dia, o que
 * entrou no dia, o acumulado, os leads acumulados e a taxa. Regra da taxa: razão é soma sobre soma, então
 * % ingresso no grupo = membros únicos que entraram no grupo (acumulado) ÷ leads (acumulado) × 100, os dois do mesmo
 * período. É a mesma conta do card (`dados_atm_resumo.grupo_pct`). Nada de média de taxas diárias.
 *
 * Ausência não vira zero: `grupo_entradas` nulo (projeto sem fonte de grupo) deixa entradas, acumulado e taxa nulos;
 * dia sem lead acumulado ainda não tem taxa (nulo, nunca 0%).
 */

export type PontoEvolucaoIngresso = {
  /** 'AAAA-MM-DD' */
  dia: string;
  entradasDia: number | null;
  entradasAcumuladas: number | null;
  leadsAcumulados: number | null;
  /** 0 a 100. `null` = sem dado (sem fonte de grupo ou nenhum lead até o dia). */
  pct: number | null;
};

export type ResumoEvolucaoIngresso = {
  entradas: number | null;
  leads: number | null;
  pct: number | null;
};

function numeroOuNulo(valor: unknown): number | null {
  if (valor === null || valor === undefined || valor === '') return null;
  const n = typeof valor === 'number' ? valor : Number(valor);
  return Number.isFinite(n) ? n : null;
}

function diaIso(valor: unknown): string | null {
  return typeof valor === 'string' && /^\d{4}-\d{2}-\d{2}/.test(valor) ? valor.slice(0, 10) : null;
}

/** Linhas sem `dia` válido são descartadas; o resto sai em ordem de data. */
export function pontosEvolucaoIngresso(linhas: ReadonlyArray<Record<string, unknown>>): PontoEvolucaoIngresso[] {
  const dias = linhas
    .map((linha) => ({ dia: diaIso(linha.dia), leads: numeroOuNulo(linha.leads), entradas: numeroOuNulo(linha.grupo_entradas) }))
    .filter((x): x is { dia: string; leads: number | null; entradas: number | null } => x.dia !== null)
    .sort((a, b) => a.dia.localeCompare(b.dia));

  let leadsAcum: number | null = 0;
  let entradasAcum: number | null = 0;
  return dias.map((x) => {
    leadsAcum = leadsAcum === null || x.leads === null ? null : leadsAcum + x.leads;
    entradasAcum = entradasAcum === null || x.entradas === null ? null : entradasAcum + x.entradas;
    const pct = entradasAcum !== null && leadsAcum !== null && leadsAcum > 0 ? (entradasAcum / leadsAcum) * 100 : null;
    return { dia: x.dia, entradasDia: x.entradas, entradasAcumuladas: entradasAcum, leadsAcumulados: leadsAcum, pct };
  });
}

/** `true` quando algum dia trouxe entrada no grupo medida (inclusive 0). Sem isso o projeto não tem fonte de grupo. */
export function temFonteDeGrupo(pontos: ReadonlyArray<PontoEvolucaoIngresso>): boolean {
  return pontos.some((p) => p.entradasDia !== null);
}

/** Último dia da série = o total do período, que tem de bater com o card. */
export function resumoEvolucaoIngresso(pontos: ReadonlyArray<PontoEvolucaoIngresso>): ResumoEvolucaoIngresso {
  const ultimo = pontos[pontos.length - 1];
  return ultimo
    ? { entradas: ultimo.entradasAcumuladas, leads: ultimo.leadsAcumulados, pct: ultimo.pct }
    : { entradas: null, leads: null, pct: null };
}

export const rotuloDiaCurto = (dia: string) => `${dia.slice(8, 10)}/${dia.slice(5, 7)}`;
export const rotuloDiaCompleto = (dia: string) => `${dia.slice(8, 10)}/${dia.slice(5, 7)}/${dia.slice(0, 4)}`;
