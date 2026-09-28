// Cruzamentos do gráfico do Faturamento (João, 27/09: "botar um pad aí embaixo… fazer algum cruzamento para a gente
// poder fazer algumas previsões ou correlações de forma mais acessível… manter na essência"). Funções PURAS.
import type { GranularidadeFaturamento, PeriodoFaturamento } from './hotmart';

/** Média móvel simples de `n` períodos (os primeiros n−1 usam o que existe até ali). */
export function mediaMovel(valores: number[], n: number): number[] {
  return valores.map((_, i) => {
    const ini = Math.max(0, i - n + 1);
    const janela = valores.slice(ini, i + 1);
    return janela.reduce((s, v) => s + v, 0) / janela.length;
  });
}

function diasNoMes(y: number, m: number): number { return new Date(Date.UTC(y, m, 0)).getUTCDate(); }
function diaDoAno(y: number, m: number, d: number): number { return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(y, 0, 1)) / 86_400_000) + 1; }
function diasNoAno(y: number): number { return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 ? 366 : 365; }

export interface Projecao {
  /** O que a projeção descreve: "set/2026", "2026". */
  alvo: 'mes' | 'ano';
  chave: string;
  parcial: number;
  projetado: number;
  /** Fração do período já decorrida (0–1). */
  decorrido: number;
}

/**
 * Projeção pelo RITMO do período em curso: o que entrou até hoje ÷ fração decorrida. Só quando o intervalo termina hoje.
 * Diário → projeta o MÊS corrente (soma dos dias do mês); Mensal → o mês corrente; Anual → o ano corrente.
 * Nunca projeta com menos de 3 dias decorridos (ruído demais).
 */
export function projetarPeriodoAtual(
  diarios: { dia: string; bruto: number }[], g: GranularidadeFaturamento, hojeISO: string, ateISO: string,
): Projecao | null {
  if (ateISO.slice(0, 10) !== hojeISO.slice(0, 10)) return null;
  const [y, m, d] = hojeISO.slice(0, 10).split('-').map(Number);
  if (g === 'ano') {
    const decorrido = diaDoAno(y, m, d) / diasNoAno(y);
    if (diaDoAno(y, m, d) < 3) return null;
    const parcial = diarios.filter((x) => x.dia.startsWith(String(y))).reduce((s, x) => s + x.bruto, 0);
    return { alvo: 'ano', chave: String(y), parcial, projetado: parcial / decorrido, decorrido };
  }
  if (d < 3) return null;
  const pref = hojeISO.slice(0, 7);
  const parcial = diarios.filter((x) => x.dia.startsWith(pref)).reduce((s, x) => s + x.bruto, 0);
  const decorrido = d / diasNoMes(y, m);
  return { alvo: 'mes', chave: pref, parcial, projetado: parcial / decorrido, decorrido };
}

/** Alinha o período anterior ao atual pela POSIÇÃO (1º com 1º…), do mesmo tamanho. Falta vira null. */
export function alinharAnterior(atual: PeriodoFaturamento[], anterior: PeriodoFaturamento[]): (number | null)[] {
  const desloc = anterior.length - atual.length;
  return atual.map((_, i) => {
    const j = i + desloc;
    return j >= 0 && j < anterior.length ? anterior[j].bruto : null;
  });
}

/** Intervalo imediatamente anterior, com o mesmo número de dias. */
export function intervaloAnterior(deISO: string, ateISO: string): { de: string; ate: string } {
  const d = (s: string) => { const [y, m, dd] = s.slice(0, 10).split('-').map(Number); return Date.UTC(y, m - 1, dd); };
  const dias = Math.round((d(ateISO) - d(deISO)) / 86_400_000) + 1;
  const ate = new Date(d(deISO) - 86_400_000);
  const de = new Date(d(deISO) - dias * 86_400_000);
  return { de: de.toISOString().slice(0, 10), ate: ate.toISOString().slice(0, 10) };
}
