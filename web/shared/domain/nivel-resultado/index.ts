// Domínio puro do enum thb_alunos.nivel_resultado.
// Porta de app/assets/js/domain/nivel-resultado.js (mantém a mesma escala 10..80).

export type NivelKey =
  | 'iniciante'
  | 'pessoal'
  | 'em_formacao'
  | 'profissional'
  | 'ouro'
  | 'platina'
  | 'diamante'
  | 'diamante_vermelho';

interface NivelEntry {
  label: string;
  order: number;
}

export const NIVEL_CATALOG: Readonly<Record<NivelKey, NivelEntry>> = Object.freeze({
  iniciante: { label: 'Iniciante', order: 10 },
  pessoal: { label: 'Pessoal', order: 20 },
  em_formacao: { label: 'Em Formação', order: 30 },
  profissional: { label: 'Profissional', order: 40 },
  ouro: { label: 'Ouro', order: 50 },
  platina: { label: 'Platina', order: 60 },
  diamante: { label: 'Diamante', order: 70 },
  diamante_vermelho: { label: 'Diamante Vermelho', order: 80 },
});

export const NIVEL_ORDERED_KEYS: NivelKey[] = (Object.keys(NIVEL_CATALOG) as NivelKey[]).sort(
  (a, b) => NIVEL_CATALOG[a].order - NIVEL_CATALOG[b].order,
);

/** Normaliza variações (case, espaços, hífen, acento) para a chave canônica. */
export function nivelNormalize(value: unknown): NivelKey | null {
  if (value == null) return null;
  const raw = String(value).toLowerCase().trim();
  if (raw === '') return null;
  const stripped = raw.normalize('NFD').replace(/[̀-ͯ]/g, '');
  const normalized = stripped.replace(/[\s-]+/g, '_').replace(/[^a-z_]/g, '');
  return Object.prototype.hasOwnProperty.call(NIVEL_CATALOG, normalized)
    ? (normalized as NivelKey)
    : null;
}

export function nivelLabel(value: unknown): string {
  const key = nivelNormalize(value);
  return key ? NIVEL_CATALOG[key].label : '';
}

export function nivelOrder(value: unknown): number | null {
  const key = nivelNormalize(value);
  return key ? NIVEL_CATALOG[key].order : null;
}

export function nivelOptions(): Array<{ id: NivelKey; label: string; order: number }> {
  return NIVEL_ORDERED_KEYS.map((key) => ({ id: key, label: NIVEL_CATALOG[key].label, order: NIVEL_CATALOG[key].order }));
}

/** Comparador estável asc; níveis null ficam no início (alunos sem nível). */
export function nivelCompare(a: unknown, b: unknown): number {
  const oa = nivelOrder(a);
  const ob = nivelOrder(b);
  if (oa === null && ob === null) return 0;
  if (oa === null) return -1;
  if (ob === null) return 1;
  return oa - ob;
}

/** Níveis que exigem comprovação de faturamento (auditoria de placa). */
export const NIVEIS_COM_COMPROVACAO: NivelKey[] = ['ouro', 'platina', 'diamante', 'diamante_vermelho'];
