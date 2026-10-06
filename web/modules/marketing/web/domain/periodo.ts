// Marketing > Web: o período das telas (dia de São Paulo, no máximo 92 dias, como no banco).

export const MAX_DIAS = 92;

/** 'AAAA-MM-DD' de um instante, no fuso de São Paulo */
export const diaSP = (d: Date) => d.toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });

/** soma dias a 'AAAA-MM-DD' (conta em UTC ao meio-dia: sem tropeço de horário de verão) */
export function somaDias(ymd: string, dias: number): string {
  const d = new Date(ymd + 'T12:00:00Z');
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

export const diasEntre = (de: string, ate: string) =>
  Math.round((new Date(ate + 'T12:00:00Z').getTime() - new Date(de + 'T12:00:00Z').getTime()) / 86400000);

export interface Periodo { de: string; ate: string }

/** os últimos N dias até hoje (inclusive) */
export function ultimosDias(n: number, hoje = diaSP(new Date())): Periodo {
  return { de: somaDias(hoje, -(n - 1)), ate: hoje };
}

/** null = período válido; senão, a mensagem */
export function validarPeriodo(p: Periodo): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(p.de) || !/^\d{4}-\d{2}-\d{2}$/.test(p.ate)) return 'Informe as duas datas.';
  if (p.ate < p.de) return 'A data final é antes da inicial.';
  if (diasEntre(p.de, p.ate) > MAX_DIAS) return `No máximo ${MAX_DIAS} dias.`;
  return null;
}

/** 'AAAA-MM-DD' → 'DD/MM' */
export const diaCurto = (ymd: string) => ymd.split('-').reverse().slice(0, 2).join('/');
