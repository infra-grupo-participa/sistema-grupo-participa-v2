'use client';

// Cliente das APIs públicas de placa (browser). credentials:'include' p/ o cookie de sessão.

const opts = (body?: unknown): RequestInit => ({
  method: body === undefined ? 'GET' : 'POST',
  credentials: 'include',
  headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
  body: body === undefined ? undefined : JSON.stringify(body),
});

export interface PlacaGetResult {
  ok: boolean;
  solicitacao?: Record<string, unknown>;
  horarios?: Array<Record<string, unknown>>;
  booked_slots?: Array<{ entrevista_data: string; entrevista_hora: string }>;
}

export async function placaGet(token: string, includeSlots = false): Promise<PlacaGetResult | null> {
  const p = new URLSearchParams({ token });
  if (includeSlots) p.set('include_slots', '1');
  const r = await fetch(`/api/placa?${p}`, opts());
  if (!r.ok) return null;
  return r.json();
}

export async function placaSave(payload: Record<string, unknown>): Promise<{ ok: boolean; token?: string; status?: string; step_index?: number } | null> {
  const r = await fetch('/api/placa', opts({ action: 'save', ...payload }));
  if (!r.ok) return null;
  return r.json();
}

export async function placaDuplicateCheck(field: 'email' | 'documento_nf', value: string, token: string): Promise<boolean> {
  const r = await fetch('/api/placa', opts({ action: 'duplicate-check', field, value, token }));
  if (!r.ok) return false;
  const j = await r.json();
  return Boolean(j?.duplicate);
}

export async function placaRecover(email: string, documento_nf: string): Promise<PlacaGetResult & { found?: boolean }> {
  const r = await fetch('/api/placa', opts({ action: 'recover-session', email, documento_nf }));
  if (!r.ok) return { ok: false };
  return r.json();
}

export async function placaUpload(token: string, kind: 'comprovante' | 'declaracao', file: File): Promise<string | null> {
  const fd = new FormData();
  fd.append('token', token);
  fd.append('kind', kind);
  fd.append('file', file);
  const r = await fetch('/api/placa/upload', { method: 'POST', credentials: 'include', body: fd });
  if (!r.ok) return null;
  const j = await r.json();
  return j?.url ?? null;
}

export async function cepLookup(cep: string): Promise<{ logradouro: string; bairro: string; cidade: string; estado_uf: string } | null> {
  const r = await fetch(`/api/cep?cep=${encodeURIComponent(cep)}`, opts());
  if (!r.ok) return null;
  return r.json();
}
