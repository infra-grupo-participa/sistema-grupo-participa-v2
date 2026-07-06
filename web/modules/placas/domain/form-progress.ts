// Domínio puro — validação progressiva do formulário público de solicitação.
// Porta fiel de placa_public_validate_progress() / is_plate_eligible() (placa-public.php).
// Escala do FORM público: step_index 1..6 (distinta da escala de auditoria 0..6).

export const FORM_NIVEIS = [
  'iniciante',
  'pessoal',
  'em_formacao',
  'profissional',
  'ouro',
  'platina',
  'diamante',
  'diamante_vermelho',
] as const;

/** Níveis que geram placa (exigem comprovação + endereço). */
export function isPlateEligible(nivel: string | null | undefined): boolean {
  return ['ouro', 'platina', 'diamante', 'diamante_vermelho'].includes(String(nivel ?? ''));
}

/**
 * Ordem crescente dos níveis elegíveis (que emitem placa). Índice = grau (0 = Ouro …
 * 3 = Diamante Vermelho). Usada no CTA de refazer (detectar topo: Diamante Vermelho não refaz).
 */
export const ELIGIBLE_NIVEL_ORDER = ['ouro', 'platina', 'diamante', 'diamante_vermelho'] as const;

/** Grau do nível elegível (0..3), ou -1 se não for elegível. */
export function eligibleNivelRank(nivel: string | null | undefined): number {
  return ELIGIBLE_NIVEL_ORDER.indexOf(String(nivel ?? '') as (typeof ELIGIBLE_NIVEL_ORDER)[number]);
}

/**
 * Ordem crescente COMPLETA dos níveis (ordem canônica da CLAUDE.md, = FORM_NIVEIS). Necessária
 * para o refazer de quem estava ABAIXO de Ouro (cadastro), onde o piso é um nível não-elegível.
 */
export const NIVEL_ORDER_FULL = [
  'iniciante',
  'pessoal',
  'em_formacao',
  'profissional',
  'ouro',
  'platina',
  'diamante',
  'diamante_vermelho',
] as const;

/** Grau do nível na escala completa (0..7), ou -1 se desconhecido. */
export function nivelRank(nivel: string | null | undefined): number {
  return (NIVEL_ORDER_FULL as readonly string[]).indexOf(String(nivel ?? ''));
}

/**
 * O nível escolhido é válido para re-solicitar sobre um piso `nivelAnterior`?
 * Retorna null se ok, ou o motivo do bloqueio:
 *  - 'nao_elegivel': o piso já era elegível (placa recebida) e o novo nível é abaixo de Ouro
 *    — não se "desce" de uma placa para um cadastro sem placa;
 *  - 'nao_superior': nível igual ou inferior ao anterior (piso + inferiores ficam bloqueados).
 *
 * A exigência de elegibilidade é automática pelo piso: piso elegível (concluído, ≥ Ouro) exige
 * novo nível também elegível; piso abaixo de Ouro (cadastro) aceita qualquer nível superior
 * (pode seguir abaixo de Ouro ou alcançar Ouro+).
 */
export function nivelRefazerBlockReason(
  nivel: string | null | undefined,
  nivelAnterior: string | null | undefined,
): 'nao_elegivel' | 'nao_superior' | null {
  const piso = nivelRank(nivelAnterior);
  if (piso < 0) return null; // sem piso válido → nada a bloquear
  if (isPlateEligible(nivelAnterior) && !isPlateEligible(nivel)) return 'nao_elegivel';
  const alvo = nivelRank(nivel);
  if (alvo < 0 || alvo <= piso) return 'nao_superior';
  return null;
}

/** Faturamento mínimo (R$) de cada nível elegível — coerência nível × valor declarado. */
export const NIVEL_MIN_FATURAMENTO: Record<string, number> = {
  ouro: 50_000,
  platina: 500_000,
  diamante: 1_000_000,
  diamante_vermelho: 5_000_000,
};

/** Teto de sanidade contra erro de digitação (R$ 1 bilhão). */
export const FATURAMENTO_MAX = 1_000_000_000;

/**
 * O faturamento declarado é coerente com o nível solicitado?
 * Retorna null se ok, ou o motivo: 'abaixo_minimo' (ex.: Diamante com R$ 200k) |
 * 'acima_teto' (valor absurdo, provável erro de digitação).
 */
export function faturamentoBlockReason(nivel: string | null | undefined, valor: number): 'abaixo_minimo' | 'acima_teto' | null {
  const min = NIVEL_MIN_FATURAMENTO[String(nivel ?? '')];
  if (min === undefined) return null; // nível não-elegível não declara faturamento
  if (!Number.isFinite(valor)) return 'abaixo_minimo';
  if (valor > FATURAMENTO_MAX) return 'acima_teto';
  if (valor < min) return 'abaixo_minimo';
  return null;
}

/** Maior nível elegível que o valor declarado alcança (para sugestão na UI), ou null. */
export function nivelSugeridoPorFaturamento(valor: number): string | null {
  let melhor: string | null = null;
  for (const [nivel, min] of Object.entries(NIVEL_MIN_FATURAMENTO)) {
    if (valor >= min && (melhor === null || min > NIVEL_MIN_FATURAMENTO[melhor])) melhor = nivel;
  }
  return melhor;
}

export interface FormState {
  token?: string | null;
  step_index?: number | null;
  status?: string | null;
  nivel?: string | null;
  /** Piso de bloqueio de nível ao refazer (setado só pela RPC fn_placas_refazer). */
  nivel_anterior?: string | null;
  faturamento_declarado?: number | string | null;
  nome?: string | null;
  email?: string | null;
  telefone?: string | null;
  turma?: string | null;
  documento_nf?: string | null;
  interesse?: string | null;
  espaco_instrucao?: string | null;
  proof_url?: string | null;
  declaracao_url?: string | null;
  cep?: string | null;
  logradouro?: string | null;
  numero?: string | null;
  bairro?: string | null;
  cidade?: string | null;
  estado_uf?: string | null;
  pais?: string | null;
  [k: string]: unknown;
}

const hasValue = (v: unknown): boolean => !(v === null || v === undefined || String(v).trim() === '');
const nonNegInt = (v: unknown): boolean => {
  if (typeof v === 'number') return Number.isInteger(v) && v >= 0;
  return typeof v === 'string' && /^\d+$/.test(v);
};

/** Uma URL de documento pertence ao token? (bucket documentos/placas/{token}/). */
export function isTokenDocumentUrl(url: string | null | undefined, token: string): boolean {
  const tk = String(token ?? '').toLowerCase().trim();
  const u = String(url ?? '').trim();
  if (!tk || !u) return false;
  let parsed: URL;
  try {
    parsed = new URL(u);
  } catch {
    return false;
  }
  if (parsed.protocol !== 'https:') return false;
  if (!parsed.host.toLowerCase().endsWith('supabase.co')) return false;
  const path = parsed.pathname.toLowerCase();
  return (
    path.startsWith(`/storage/v1/object/public/documentos/placas/${tk}/`) ||
    path.startsWith(`/storage/v1/object/sign/documentos/placas/${tk}/`)
  );
}

export interface ProgressError {
  code: string;
  field?: string;
}

const STEP1 = ['nome', 'email', 'telefone', 'turma', 'documento_nf'];
const ADDRESS = ['cep', 'logradouro', 'numero', 'bairro', 'cidade', 'estado_uf', 'pais'];

function missing(state: FormState, fields: string[], code: string): ProgressError | null {
  for (const f of fields) {
    if (!hasValue(state[f])) return { code, field: f };
  }
  return null;
}

/**
 * Valida o progresso do formulário. Retorna null se válido, ou o erro (code + field).
 * `existing` é o estado já persistido (merge antes de validar), como no legado.
 */
export function validateFormProgress(payload: FormState, existing?: FormState | null): ProgressError | null {
  const state: FormState = existing ? { ...existing, ...payload } : { ...payload };
  const step = nonNegInt(state.step_index) ? Number(state.step_index) : 0;
  const status = String(state.status ?? 'rascunho').trim();
  const nivel = String(state.nivel ?? '');
  const token = String(state.token ?? '').toLowerCase().trim();
  const eligible = isPlateEligible(nivel);

  if (step >= 1) {
    const e = missing(state, STEP1, 'missing_step1_field');
    if (e) return e;
  }
  if (step >= 2) {
    const e = missing(state, ['interesse'], 'missing_step2_field');
    if (e) return e;
  }
  if (step >= 3) {
    const e = missing(state, ['espaco_instrucao', 'nivel'], 'missing_step3_field');
    if (e) return e;
    // Refazer processo: se há piso (nivel_anterior), o novo nível precisa ser elegível E superior.
    const nivelAnterior = String(state.nivel_anterior ?? '');
    if (nivelAnterior && nivel) {
      const motivo = nivelRefazerBlockReason(nivel, nivelAnterior);
      if (motivo === 'nao_elegivel') return { code: 'refazer_nivel_nao_elegivel', field: nivelAnterior };
      if (motivo === 'nao_superior') return { code: 'refazer_nivel_nao_superior', field: nivelAnterior };
    }
    if (eligible) {
      if (!nonNegInt(state.faturamento_declarado)) return { code: 'missing_faturamento' };
      // Coerência nível × valor: bloqueia p.ex. Diamante com R$ 200k declarados.
      const motivo = faturamentoBlockReason(nivel, Number(state.faturamento_declarado));
      if (motivo === 'abaixo_minimo') return { code: 'faturamento_abaixo_nivel', field: nivel };
      if (motivo === 'acima_teto') return { code: 'faturamento_acima_teto' };
    }
  }

  if (!eligible) {
    if (step > 3 || status === 'enviado') return { code: 'invalid_non_eligible_progress' };
    if (status === 'cadastro_concluido' && step !== 3) return { code: 'invalid_cadastro_status' };
    return null;
  }

  if (status === 'cadastro_concluido') return { code: 'invalid_eligible_status' };

  if (step >= 4 || status === 'enviado') {
    const e = missing(state, ['proof_url'], 'missing_proof');
    if (e) return e;
    if (!isTokenDocumentUrl(state.proof_url, token)) return { code: 'invalid_proof_url' };
  }
  if (step >= 5 || status === 'enviado') {
    const e = missing(state, ['declaracao_url'], 'missing_declaracao');
    if (e) return e;
    if (!isTokenDocumentUrl(state.declaracao_url, token)) return { code: 'invalid_declaracao_url' };
  }
  if (step >= 6 || status === 'enviado') {
    const e = missing(state, ADDRESS, 'missing_address');
    if (e) return e;
  }
  if (status === 'enviado' && step !== 6) return { code: 'invalid_submit_step' };

  return null;
}
