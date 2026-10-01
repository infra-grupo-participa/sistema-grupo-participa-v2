// Barra de vigência da aba Programa: posição de hoje entre o início e o vencimento do acesso.
// O tom segue a mesma janela de `situacao_acesso` no banco (migration 20261003d): vencido quando
// a data já passou, "a vencer" até 30 dias antes, em dia depois disso.

export type TomVigencia = 'success' | 'warning' | 'danger';

export interface Vigencia {
  /** Dias até o vencimento (negativo = vencido há N dias). */
  diasRestantes: number;
  tom: TomVigencia;
  /** % decorrido da vigência (0–100). `null` quando não há início válido para a barra. */
  pct: number | null;
}

export const JANELA_A_VENCER_DIAS = 30;

/** Dia (UTC) de uma data `YYYY-MM-DD` ou ISO; `null` se inválida. */
function dia(v: string | null | undefined): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v ?? '').trim());
  if (!m) return null;
  const t = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(t) ? null : Math.round(t / 86_400_000);
}

export function vigenciaPrograma(inicio: string | null | undefined, fim: string | null | undefined, hoje: string): Vigencia | null {
  const f = dia(fim);
  const h = dia(hoje);
  if (f == null || h == null) return null;
  const diasRestantes = f - h;
  const tom: TomVigencia = diasRestantes < 0 ? 'danger' : diasRestantes <= JANELA_A_VENCER_DIAS ? 'warning' : 'success';
  const i = dia(inicio);
  const pct = i != null && i < f ? Math.max(0, Math.min(100, ((h - i) / (f - i)) * 100)) : null;
  return { diasRestantes, tom, pct };
}

/** "vence em 12 dias", "vence hoje", "vencido há 3 dias". */
export function textoPrazo(dias: number): string {
  if (dias === 0) return 'vence hoje';
  const n = Math.abs(dias);
  const u = n === 1 ? 'dia' : 'dias';
  return dias > 0 ? `vence em ${n} ${u}` : `vencido há ${n} ${u}`;
}
