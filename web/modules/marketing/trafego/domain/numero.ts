// Número digitado no jeito brasileiro (vírgula decimal, ponto de milhar). Sem isto, "10.000" de verba ia para o banco
// como 10 (o cast numeric lê o ponto como decimal) e "12," apagava a vírgula enquanto a pessoa digitava.

/**
 * Lê o que a pessoa digitou. null = campo vazio; undefined = não é número (ou ainda está pela metade, como "-" ou "12,").
 * Aceita "10.000", "10.000,50", "1500,5", "1500.5", "12,5%", "R$ 1.200". Com vírgula, o ponto é sempre milhar; sem
 * vírgula, ponto seguido de grupos de 3 dígitos é milhar ("1.500" = 1500) e qualquer outro ponto é decimal ("12.5").
 */
export function lerNumeroBR(s: string): number | null | undefined {
  let t = s.replace(/R\$|%|\s/g, '');
  if (t === '') return null;
  if (t.includes(',')) t = t.replace(/\./g, '').replace(',', '.');
  else if (/^-?\d{1,3}(\.\d{3})+$/.test(t)) t = t.replace(/\./g, '');
  if (!/^-?\d+(\.\d+)?$/.test(t)) return undefined;
  const n = Number(t);
  return Number.isFinite(n) ? n : undefined;
}

/** Para os formulários que mandam texto ao banco: '' = vazio, número em formato do banco, ou null se inválido. */
export function numeroParaBanco(s: string): string | null {
  const n = lerNumeroBR(s);
  if (n === undefined) return null;
  return n === null ? '' : String(n);
}

/** Mostra um número para edição (vírgula decimal, sem milhar, para não brigar com a digitação). */
export const numeroParaCampo = (n: number | null | undefined): string => (n == null ? '' : String(n).replace('.', ','));
