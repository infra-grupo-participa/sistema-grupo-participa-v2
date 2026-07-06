'use client';

// Cliente das APIs públicas de placa (browser). credentials:'include' p/ o cookie de sessão.
// fetchJson: falha de rede (offline/DNS) vira retorno de erro em vez de exceção não tratada.

import { fetchJson } from '@/shared/ui/fetch-json';

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
  const r = await fetchJson<PlacaGetResult>(`/api/placa?${p}`, opts());
  return r.ok ? r.json : null;
}

export async function placaSave(
  payload: Record<string, unknown>,
): Promise<{ ok: boolean; token?: string; status?: string; step_index?: number; error?: string }> {
  const r = await fetchJson<{ ok?: boolean; token?: string; status?: string; step_index?: number; error?: string }>(
    '/api/placa',
    opts({ action: 'save', ...payload }),
  );
  if (r.ok && r.json) return { ok: true, ...r.json };
  // Propaga a mensagem específica do servidor (ex.: qual campo falta) quando houver.
  return { ok: false, error: r.json?.error };
}

export async function placaDuplicateCheck(field: 'email' | 'documento_nf', value: string, token: string): Promise<boolean> {
  const r = await fetchJson<{ duplicate?: boolean }>('/api/placa', opts({ action: 'duplicate-check', field, value, token }));
  return r.ok ? Boolean(r.json?.duplicate) : false;
}

export async function placaRecover(email: string, documento_nf: string): Promise<PlacaGetResult & { found?: boolean }> {
  const r = await fetchJson<PlacaGetResult & { found?: boolean }>('/api/placa', opts({ action: 'recover-session', email, documento_nf }));
  return r.ok && r.json ? r.json : { ok: false };
}

export async function placaRefazer(token: string): Promise<{ ok: boolean; solicitacao?: Record<string, unknown>; error?: string }> {
  const r = await fetchJson<{ ok?: boolean; solicitacao?: Record<string, unknown>; error?: string }>('/api/placa', opts({ action: 'refazer', token }));
  if (r.ok && r.json?.ok) return { ok: true, solicitacao: r.json.solicitacao };
  return { ok: false, error: r.json?.error };
}

export async function placaUpload(token: string, kind: 'comprovante' | 'declaracao', file: File): Promise<string | null> {
  const fd = new FormData();
  fd.append('token', token);
  fd.append('kind', kind);
  fd.append('file', file);
  const r = await fetchJson<{ url?: string }>('/api/placa/upload', { method: 'POST', credentials: 'include', body: fd });
  return r.ok ? r.json?.url ?? null : null;
}

export async function cepLookup(cep: string): Promise<{ logradouro: string; bairro: string; cidade: string; estado_uf: string } | null> {
  const r = await fetchJson<{ logradouro: string; bairro: string; cidade: string; estado_uf: string }>(`/api/cep?cep=${encodeURIComponent(cep)}`, opts());
  return r.ok ? r.json : null;
}
