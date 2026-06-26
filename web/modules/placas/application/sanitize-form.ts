// Sanitização do payload do formulário público — porta de placa_public_allowed_payload().
// Retorna o conjunto de campos permitidos (já sanitizados) ou um erro de validação.

import { onlyDigits, safeEmail, normalizeText, isSafeStorageUrl } from '@/shared/infrastructure/http/validation';
import { FORM_NIVEIS } from '../domain/form-progress';

export interface SanitizeResult {
  ok: boolean;
  code?: string;
  payload?: Record<string, unknown>;
}

function safeText(v: unknown, max: number): string | null {
  if (v === null || v === undefined) return null;
  const t = normalizeText(String(v), max);
  return t === '' ? null : t;
}

function safePhone(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  const d = onlyDigits(v);
  return d === '' ? null : d.slice(0, 20);
}

function safeHttpUrl(v: unknown, allowedHosts: string[] = []): string | null {
  const raw = String(v ?? '').replace(/[\r\n]+/g, '').trim();
  if (!raw) return null;
  try {
    const u = new URL(raw);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    if (allowedHosts.length) {
      const host = u.host.toLowerCase();
      const ok = allowedHosts.some((h) => host === h || host.endsWith('.' + h));
      if (!ok) return null;
    }
    return raw;
  } catch {
    return null;
  }
}

const SOCIAL = {
  instagram: { hosts: ['instagram.com'], base: 'https://instagram.com/' },
  facebook: { hosts: ['facebook.com', 'fb.com'], base: 'https://facebook.com/' },
} as const;

function safeSocialUrl(v: unknown, network: keyof typeof SOCIAL): string | null {
  if (v === null || v === undefined) return null;
  const raw = String(v).replace(/[\r\n]+/g, '').trim();
  if (!raw) return null;
  const cfg = SOCIAL[network];
  let candidate = raw;
  if (!/^https?:\/\//i.test(candidate) && /^(?:www\.)?(?:instagram\.com|facebook\.com|fb\.com)\//i.test(candidate)) {
    candidate = 'https://' + candidate.replace(/^\/+/, '');
  }
  const safe = safeHttpUrl(candidate, cfg.hosts as unknown as string[]);
  if (safe) return safe;
  let handle = raw.replace(/^(?:https?:\/\/)?(?:www\.)?(?:instagram\.com|facebook\.com|fb\.com)\//i, '');
  handle = handle.replace(/^[@/]+/, '').replace(/[?#].*$/, '').replace(/[/ \t\n\r]+$/, '');
  if (!handle || !/^[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*$/.test(handle)) return null;
  return cfg.base + handle;
}

export function sanitizeFormPayload(body: Record<string, unknown>): SanitizeResult {
  const allowed: Record<string, unknown> = {};

  const map: Record<string, (v: unknown) => unknown> = {
    nome: (v) => safeText(v, 120),
    email: (v) => safeEmail(String(v ?? '')) || null,
    telefone: (v) => safePhone(v),
    turma: (v) => safeText(v, 24),
    profissao: (v) => safeText(v, 120),
    telefone_profissional: (v) => safePhone(v),
    youtube_url: (v) => safeHttpUrl(v),
    site_profissional: (v) => safeHttpUrl(v),
    instagram_url: (v) => safeSocialUrl(v, 'instagram'),
    facebook_url: (v) => safeSocialUrl(v, 'facebook'),
    interesse: (v) => safeText(v, 80),
    espaco_instrucao: (v) => safeText(v, 80),
    nivel: (v) => (FORM_NIVEIS.includes(String(v) as (typeof FORM_NIVEIS)[number]) ? String(v) : null),
    faturamento_declarado: (v) => (/^\d+$/.test(String(v)) ? Number(v) : typeof v === 'number' && v >= 0 ? v : null),
    cep: (v) => (onlyDigits(v).length === 8 ? onlyDigits(v) : null),
    logradouro: (v) => safeText(v, 180),
    numero: (v) => safeText(v, 40),
    complemento: (v) => safeText(v, 120),
    bairro: (v) => safeText(v, 120),
    cidade: (v) => safeText(v, 120),
    estado_uf: (v) => (/^[A-Za-z]{2}$/.test(String(v ?? '').trim()) ? String(v).trim().toUpperCase() : null),
    pais: (v) => safeText(v, 80),
    documento_nf: (v) => ([11, 14].includes(onlyDigits(v).length) ? onlyDigits(v) : null),
    proof_url: (v) => (isSafeStorageUrl(String(v ?? '')) ? String(v) : null),
    declaracao_url: (v) => (isSafeStorageUrl(String(v ?? '')) ? String(v) : null),
    motivo_retorno: (v) => (v === null ? null : safeText(v, 2000)),
  };

  for (const [field, fn] of Object.entries(map)) {
    if (Object.prototype.hasOwnProperty.call(body, field)) allowed[field] = fn(body[field]);
  }

  // "uploaded" é placeholder do front (arquivo já existe) → não sobrescreve a URL real.
  for (const f of ['proof_url', 'declaracao_url']) {
    if (String(body[f] ?? '').trim() === 'uploaded') delete allowed[f];
  }

  const stepRaw = body.step_index;
  const step = /^\d+$/.test(String(stepRaw)) ? Number(stepRaw) : typeof stepRaw === 'number' ? stepRaw : NaN;
  if (!Number.isInteger(step) || step < 1 || step > 6) return { ok: false, code: 'invalid_step_index' };
  allowed.step_index = step;

  const status = String(body.status ?? 'rascunho').trim();
  if (!['rascunho', 'cadastro_concluido', 'enviado'].includes(status)) return { ok: false, code: 'invalid_status' };
  allowed.status = status;
  allowed.updated_at = new Date().toISOString();

  return { ok: true, payload: allowed };
}
