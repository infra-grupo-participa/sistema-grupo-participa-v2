import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { VALIDADE_JWT_MCP_S, assinarJwtHs256, montarClaimsMcp } from './mcp-jwt';

describe('JWT do dono do token MCP', () => {
  const agora = new Date('2026-10-06T12:00:00Z');
  const c = montarClaimsMcp({ perfilId: 'p1', email: 'v@advmais.com', tokenId: 't1' }, 'https://x.supabase.co/', agora);

  it('claims: usuário autenticado, 5 min, canal mcp, iss do Auth do projeto', () => {
    expect(c).toMatchObject({ sub: 'p1', role: 'authenticated', aud: 'authenticated', email: 'v@advmais.com', gp_canal: 'mcp', gp_mcp_token: 't1', iss: 'https://x.supabase.co/auth/v1' });
    expect(c.exp - c.iat).toBe(VALIDADE_JWT_MCP_S);
    expect(VALIDADE_JWT_MCP_S).toBeLessThanOrEqual(300);
    expect(JSON.stringify(c)).not.toMatch(/service_role/);
  });
  it('assinatura HS256 confere com o segredo', () => {
    const jwt = assinarJwtHs256(c, 'segredo-de-teste');
    const [h, p, s] = jwt.split('.');
    expect(JSON.parse(Buffer.from(h, 'base64url').toString())).toEqual({ alg: 'HS256', typ: 'JWT' });
    expect(JSON.parse(Buffer.from(p, 'base64url').toString())).toEqual(c);
    expect(s).toBe(createHmac('sha256', 'segredo-de-teste').update(`${h}.${p}`).digest('base64url'));
    expect(s).not.toBe(createHmac('sha256', 'outro').update(`${h}.${p}`).digest('base64url'));
  });
  it('sem segredo não assina', () => {
    expect(() => assinarJwtHs256(c, '')).toThrow();
  });
});
