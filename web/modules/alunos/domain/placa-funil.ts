// Funil da placa na ficha do aluno: regras puras (rótulos e limiares).

/** Mesmo limiar da cutucada: a partir de 3 dias parado vira alerta. */
export const PLACA_PARADO_ALERTA_DIAS = 3;

/** "Parado há N dias" + se deve alertar. null/negativo/inválido = não exibir. */
export function placaParadoInfo(dias: number | null | undefined): { label: string; alerta: boolean } | null {
  if (dias == null || !Number.isFinite(dias) || dias < 0) return null;
  const n = Math.floor(dias);
  return {
    label: n === 0 ? 'Parado desde hoje' : `Parado há ${n} ${n === 1 ? 'dia' : 'dias'}`,
    alerta: n >= PLACA_PARADO_ALERTA_DIAS,
  };
}

/** Ciclo só aparece a partir do 2º (refez por subir de nível). */
export function placaCicloLabel(ciclo: number | null | undefined): string | null {
  return ciclo != null && ciclo > 1 ? `Ciclo ${ciclo}` : null;
}

/** "dd/mm hh:mm" no fuso do navegador; inválido = null. */
export function placaLembreteLabel(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(d.getDate())}/${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
}
