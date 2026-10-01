import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

const URL_TOKEN = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const COOKIE_TOKEN = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const rows = new Map<string, Record<string, unknown>>();

vi.mock('@/modules/placas/infrastructure/supabase-public-placa', () => ({
  maskDocsForPublic: (r: Record<string, unknown>) => r,
  SupabasePublicPlaca: class {
    async loadByToken(t: string) {
      return rows.get(t) ?? null;
    }
    async duplicateExists() {
      return false;
    }
    async loadActiveSlots() {
      return [];
    }
    async loadBookedSlots() {
      return [];
    }
  },
}));
vi.mock('@/modules/placas/infrastructure/supabase-config', () => ({ readPlacasConfig: async () => ({}) }));
vi.mock('@/shared/infrastructure/email/mailer', () => ({ sendMail: async () => true }));

const { GET, POST } = await import('./route');

let ip = 0;
function req(method: string, query: string | null, cookie: string | null, body?: unknown): NextRequest {
  const headers: Record<string, string> = { origin: 'https://grupoparticipa.app.br', 'x-real-ip': `10.0.0.${++ip}` };
  if (cookie) headers.cookie = `gp_placa_session=${cookie}`;
  if (body) headers['content-type'] = 'application/json';
  return new NextRequest(`https://grupoparticipa.app.br/api/placa${query ? `?token=${query}` : ''}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
}
const cookieApagado = (res: Response) => /gp_placa_session=;.*Max-Age=0/i.test(res.headers.get('set-cookie') ?? '');

beforeEach(() => {
  rows.clear();
  rows.set(COOKIE_TOKEN, { token: COOKIE_TOKEN, status: 'rascunho', step_index: 2 });
});

describe('GET /api/placa — token da URL inválido não derruba a sessão do cookie', () => {
  it('URL inexistente + cookie válido → 200 com a sessão do cookie e token_url_invalido', async () => {
    const res = await GET(req('GET', URL_TOKEN, COOKIE_TOKEN));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toMatchObject({ ok: true, token_url_invalido: true, token_fonte: 'cookie', token: COOKIE_TOKEN });
    expect(json.solicitacao.token).toBe(COOKIE_TOKEN);
    expect(cookieApagado(res)).toBe(false);
  });

  it('URL inexistente sem cookie → 404, token_fonte query, sem apagar cookie', async () => {
    const res = await GET(req('GET', URL_TOKEN, null));
    expect(res.status).toBe(404);
    expect(await res.json()).toMatchObject({ token_invalido: true, token_fonte: 'query', sessao_preservada: false });
    expect(cookieApagado(res)).toBe(false);
  });

  it('URL e cookie inexistentes → 404 e cookie apagado', async () => {
    rows.clear();
    const res = await GET(req('GET', URL_TOKEN, COOKIE_TOKEN));
    expect(res.status).toBe(404);
    expect(cookieApagado(res)).toBe(true);
  });

  it('só cookie inexistente → 404, token_fonte cookie, cookie apagado', async () => {
    rows.clear();
    const res = await GET(req('GET', null, COOKIE_TOKEN));
    expect(res.status).toBe(404);
    expect(await res.json()).toMatchObject({ token_invalido: true, token_fonte: 'cookie', sessao_preservada: false });
    expect(cookieApagado(res)).toBe(true);
  });
});

describe('POST /api/placa save — sem fallback de escrita', () => {
  it('token do body inexistente + cookie válido → 404, sessao_preservada, cookie intacto', async () => {
    const res = await POST(req('POST', null, COOKIE_TOKEN, { action: 'save', token: URL_TOKEN, step_index: 1 }));
    expect(res.status).toBe(404);
    expect(await res.json()).toMatchObject({ token_invalido: true, token_fonte: 'body', sessao_preservada: true });
    expect(cookieApagado(res)).toBe(false);
  });
});
