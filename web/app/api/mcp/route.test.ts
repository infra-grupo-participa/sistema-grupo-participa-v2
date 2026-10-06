import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

const TOKEN = 'gpc_' + 'ab'.repeat(32);
const recebidos: { corpo: unknown; hash: string }[] = [];
let resposta: { status: number; corpo?: unknown; autenticar?: boolean } = { status: 200, corpo: { jsonrpc: '2.0', id: 1, result: {} } };

vi.mock('@/modules/comercial/infrastructure/supabase-mcp', () => ({ SupabaseMcpAdapter: class {} }));
vi.mock('@/modules/comercial/application/mcp-servidor', () => ({
  atenderMcp: async (corpo: unknown, hash: string) => { recebidos.push({ corpo, hash }); return resposta; },
}));

const { POST, GET } = await import('./route');

const req = (corpo: string, headers: Record<string, string> = {}) =>
  new NextRequest('https://grupoparticipa.app.br/api/mcp', {
    method: 'POST',
    body: corpo,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${TOKEN}`, 'x-forwarded-for': '203.0.113.9', ...headers },
  });

describe('/api/mcp', () => {
  beforeEach(() => { recebidos.length = 0; resposta = { status: 200, corpo: { jsonrpc: '2.0', id: 1, result: {} } }; });

  it('sem Bearer gpc_… → 401 com WWW-Authenticate, sem tocar no banco', async () => {
    const r = await POST(req('{}', { authorization: 'Bearer abc' }));
    expect(r.status).toBe(401);
    expect(r.headers.get('www-authenticate')).toContain('Bearer');
    expect(recebidos).toHaveLength(0);
  });
  it('passa só o sha-256 do token (o texto nunca sai daqui)', async () => {
    const r = await POST(req(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' })));
    expect(r.status).toBe(200);
    expect(recebidos[0].hash).toBe(createHash('sha256').update(TOKEN).digest('hex'));
    expect(JSON.stringify(recebidos)).not.toContain(TOKEN);
  });
  it('Origin de terceiro → 403; JSON quebrado → 400 -32700; content-type errado → 415', async () => {
    expect((await POST(req('{}', { origin: 'https://evil.example' }))).status).toBe(403);
    const quebrado = await POST(req('{'));
    expect(quebrado.status).toBe(400);
    expect(await quebrado.json()).toMatchObject({ error: { code: -32700 } });
    expect((await POST(req('{}', { 'content-type': 'text/plain' }))).status).toBe(415);
  });
  it('notificação → 202 sem corpo; 401 do banco leva WWW-Authenticate', async () => {
    resposta = { status: 202 };
    const r = await POST(req(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })));
    expect(r.status).toBe(202);
    expect(await r.text()).toBe('');
    resposta = { status: 401, corpo: { error: 'Token inválido, revogado ou expirado.' }, autenticar: true };
    const r2 = await POST(req(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' })));
    expect(r2.status).toBe(401);
    expect(r2.headers.get('www-authenticate')).toContain('invalid_token');
  });
  it('GET → 405 (sem SSE)', async () => {
    expect(GET().status).toBe(405);
  });
});
