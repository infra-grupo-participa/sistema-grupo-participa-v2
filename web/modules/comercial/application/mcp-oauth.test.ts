import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { emitirToken, registrarCliente, type Cripto, type PortaOAuth } from './mcp-oauth';

const CLI = '11111111-1111-4111-8111-111111111111';
const CB = 'https://claude.ai/api/mcp/auth_callback';
let n = 0;
const cripto: Cripto = {
  sha256Hex: (s) => createHash('sha256').update(s).digest('hex'),
  s256: (v) => createHash('sha256').update(v).digest('base64url'),
  aleatorioHex: (b) => String(++n % 10).repeat(b * 2),
};

function porta(ok = true) {
  const chamadas: { op: string; p: Record<string, unknown> }[] = [];
  const p: PortaOAuth = {
    registrar: async (nome, redirects) => { chamadas.push({ op: 'registrar', p: { nome, redirects } }); return { ok: true, id: CLI }; },
    trocar: async (x) => { chamadas.push({ op: 'trocar', p: x }); return ok ? { ok: true, escopos: ['ler', 'operar'] } : { ok: false, msg: 'Código inválido ou já usado.' }; },
    renovar: async (x) => { chamadas.push({ op: 'renovar', p: x }); return ok ? { ok: true, escopos: ['ler'] } : { ok: false, msg: 'Conexão vencida.' }; },
  };
  return { p, chamadas };
}

describe('OAuth: registrar cliente', () => {
  it('201 com client_id e método none; redirect de fora não chega ao banco', async () => {
    const { p, chamadas } = porta();
    const r = await registrarCliente({ client_name: 'Claude', redirect_uris: [CB] }, p, new Date('2026-10-08T12:00:00Z'));
    expect(r.status).toBe(201);
    expect(r.corpo).toMatchObject({ client_id: CLI, token_endpoint_auth_method: 'none', redirect_uris: [CB], client_id_issued_at: 1791460800 });
    const ruim = await registrarCliente({ redirect_uris: ['https://evil.example/cb'] }, p);
    expect(ruim.status).toBe(400);
    expect(chamadas).toHaveLength(1);
  });
});

describe('OAuth: emitir token', () => {
  const verificador = 'k'.repeat(50);
  it('troca código: manda só hashes + desafio S256 ao banco e devolve os tokens 1 vez', async () => {
    const { p, chamadas } = porta();
    const codigo = 'c'.repeat(64);
    const r = await emitirToken({ grant_type: 'authorization_code', client_id: CLI, code: codigo, redirect_uri: CB, code_verifier: verificador }, p, cripto);
    expect(r.status).toBe(200);
    const corpo = r.corpo as { access_token: string; refresh_token: string; token_type: string; expires_in: number; scope: string };
    expect(corpo.access_token).toMatch(/^gpc_[0-9a-f]{64}$/);
    expect(corpo.refresh_token).toMatch(/^gpr_[0-9a-f]{64}$/);
    expect(corpo).toMatchObject({ token_type: 'Bearer', expires_in: 3600, scope: 'ler operar' });
    const enviado = chamadas[0].p;
    expect(enviado).toMatchObject({
      clienteId: CLI, redirectUri: CB, codigoHash: cripto.sha256Hex(codigo), challenge: cripto.s256(verificador),
      accessHash: cripto.sha256Hex(corpo.access_token), refreshHash: cripto.sha256Hex(corpo.refresh_token), prefixo: corpo.access_token.slice(0, 12),
    });
    expect(JSON.stringify(chamadas)).not.toContain(corpo.access_token);
    expect(JSON.stringify(chamadas)).not.toContain(codigo);
  });
  it('banco recusa → 400 invalid_grant; pedido malformado não chega ao banco', async () => {
    const { p, chamadas } = porta(false);
    const r = await emitirToken({ grant_type: 'refresh_token', client_id: CLI, refresh_token: `gpr_${'d'.repeat(64)}` }, p, cripto);
    expect(r).toEqual({ status: 400, corpo: { error: 'invalid_grant', error_description: 'Conexão vencida.' } });
    const ruim = await emitirToken({ grant_type: 'password', client_id: CLI }, p, cripto);
    expect(ruim.corpo).toMatchObject({ error: 'unsupported_grant_type' });
    expect(chamadas).toHaveLength(1);
  });
  it('refresh rotaciona: hash do refresh antigo + hash do novo', async () => {
    const { p, chamadas } = porta();
    const antigo = `gpr_${'e'.repeat(64)}`;
    const r = await emitirToken({ grant_type: 'refresh_token', client_id: CLI, refresh_token: antigo }, p, cripto);
    const novo = (r.corpo as { refresh_token: string }).refresh_token;
    expect(novo).not.toBe(antigo);
    expect(chamadas[0].p).toMatchObject({ refreshHash: cripto.sha256Hex(antigo), refreshNovo: cripto.sha256Hex(novo) });
  });
});
