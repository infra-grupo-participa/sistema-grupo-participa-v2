'use client';

const post = (body: unknown): RequestInit => ({
  method: 'POST',
  credentials: 'include',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
});

export async function agendaHold(token: string, data: string, hora: string): Promise<{ ok: boolean; error?: string }> {
  const r = await fetch('/api/agenda/hold', post({ token, data, hora }));
  const j = await r.json().catch(() => ({}));
  return r.ok ? { ok: true } : { ok: false, error: j?.error || 'Não foi possível reservar o horário.' };
}

export interface ConfirmResult {
  ok: boolean;
  zoom_link?: string | null;
  gcal_link?: string;
  data?: string;
  hora?: string;
  session_link?: string;
  error?: string;
}

export async function agendaConfirm(token: string, data: string, hora: string): Promise<ConfirmResult> {
  const r = await fetch('/api/agenda/confirm', post({ token, data, hora }));
  const j = await r.json().catch(() => ({}));
  return r.ok ? j : { ok: false, error: j?.error || 'Não foi possível confirmar o horário.', session_link: j?.session_link };
}
