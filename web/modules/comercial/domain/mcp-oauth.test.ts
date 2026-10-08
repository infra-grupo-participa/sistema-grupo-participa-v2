import { describe, expect, it } from 'vitest';
import {
  lerPedidoAutorizacao, lerPedidoToken, metadadosRecurso, metadadosServidor, redirectPermitido, urlDeRetorno, validarRegistro,
} from './mcp-oauth';

const BASE = 'https://grupoparticipa.app.br';
const RECURSO = `${BASE}/api/mcp`;
const CLI = '11111111-1111-4111-8111-111111111111';
const CH = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
const CB = 'https://claude.ai/api/mcp/auth_callback';

describe('oauth: redirect', () => {
  it('aceita só os callbacks do Claude e loopback http', () => {
    expect(redirectPermitido(CB)).toBe(true);
    expect(redirectPermitido('https://claude.com/api/mcp/auth_callback')).toBe(true);
    expect(redirectPermitido('http://localhost:33418/callback')).toBe(true);
    expect(redirectPermitido('http://127.0.0.1:8080/cb')).toBe(true);
    for (const ruim of ['https://claude.ai/outra', 'https://evil.example/cb', 'https://claude.ai.evil.example/api/mcp/auth_callback',
      'http://localhost.evil.example/cb', 'https://localhost/cb', 'http://user:x@localhost/cb', 'javascript:alert(1)', 'http://localhost/cb#x', 42]) {
      expect(redirectPermitido(ruim)).toBe(false);
    }
  });
});

describe('oauth: registro dinâmico', () => {
  it('registra cliente público com redirect permitido', () => {
    expect(validarRegistro({ client_name: ' Claude ', redirect_uris: [CB, CB], token_endpoint_auth_method: 'client_secret_post' }))
      .toEqual({ ok: true, nome: 'Claude', redirects: [CB] });
  });
  it('recusa redirect de fora, lista vazia e grant estranho', () => {
    expect(validarRegistro({ redirect_uris: ['https://evil.example/cb'] })).toMatchObject({ ok: false, erro: 'invalid_redirect_uri' });
    expect(validarRegistro({ redirect_uris: [] })).toMatchObject({ ok: false, erro: 'invalid_redirect_uri' });
    expect(validarRegistro({ redirect_uris: [CB], grant_types: ['client_credentials'] })).toMatchObject({ ok: false, erro: 'invalid_client_metadata' });
    expect(validarRegistro(null)).toMatchObject({ ok: false });
  });
});

describe('oauth: pedido de autorização', () => {
  const q = { response_type: 'code', client_id: CLI, redirect_uri: CB, code_challenge: CH, code_challenge_method: 'S256', state: 'abc' };
  it('pedido completo; sem scope = ler + operar; scope ler = só ler', () => {
    expect(lerPedidoAutorizacao(q, RECURSO)).toEqual({ ok: true, pedido: { clienteId: CLI, redirectUri: CB, challenge: CH, state: 'abc', escopos: ['ler', 'operar'] } });
    const r = lerPedidoAutorizacao({ ...q, scope: 'ler' }, RECURSO);
    expect(r.ok && r.pedido.escopos).toEqual(['ler']);
  });
  it('cliente ou redirect ruim: erro na tela (nunca redireciona)', () => {
    expect(lerPedidoAutorizacao({ ...q, redirect_uri: 'https://evil.example/cb' }, RECURSO)).toMatchObject({ ok: false, voltar: null });
    expect(lerPedidoAutorizacao({ ...q, client_id: 'x' }, RECURSO)).toMatchObject({ ok: false, voltar: null });
  });
  it('PKCE obrigatório (S256), response_type code, resource do próprio MCP', () => {
    expect(lerPedidoAutorizacao({ ...q, code_challenge_method: 'plain' }, RECURSO)).toMatchObject({ ok: false, voltar: { erro: 'invalid_request', state: 'abc' } });
    expect(lerPedidoAutorizacao({ ...q, code_challenge: undefined }, RECURSO)).toMatchObject({ ok: false, voltar: { erro: 'invalid_request' } });
    expect(lerPedidoAutorizacao({ ...q, response_type: 'token' }, RECURSO)).toMatchObject({ ok: false, voltar: { erro: 'unsupported_response_type' } });
    expect(lerPedidoAutorizacao({ ...q, resource: 'https://outro.example/mcp' }, RECURSO)).toMatchObject({ ok: false, voltar: { erro: 'invalid_target' } });
    expect(lerPedidoAutorizacao({ ...q, resource: `${RECURSO}/` }, RECURSO).ok).toBe(true);
  });
  it('urlDeRetorno preserva a query do redirect e ignora vazios', () => {
    expect(urlDeRetorno('http://localhost:1/cb?x=1', { code: 'c', state: null, iss: BASE }))
      .toBe('http://localhost:1/cb?x=1&code=c&iss=https%3A%2F%2Fgrupoparticipa.app.br');
  });
});

describe('oauth: pedido de token', () => {
  const cod = 'a'.repeat(64);
  const ver = 'v'.repeat(43);
  it('authorization_code exige código, redirect e verifier válidos', () => {
    expect(lerPedidoToken({ grant_type: 'authorization_code', client_id: CLI, code: cod, redirect_uri: CB, code_verifier: ver }))
      .toEqual({ ok: true, tipo: 'codigo', codigo: cod, clienteId: CLI, redirectUri: CB, verificador: ver });
    expect(lerPedidoToken({ grant_type: 'authorization_code', client_id: CLI, code: cod, redirect_uri: CB, code_verifier: 'curto' })).toMatchObject({ ok: false, erro: 'invalid_grant' });
    expect(lerPedidoToken({ grant_type: 'authorization_code', client_id: CLI, code: 'x', redirect_uri: CB, code_verifier: ver })).toMatchObject({ ok: false });
  });
  it('refresh_token gpr_; client_id obrigatório; outro grant recusado', () => {
    expect(lerPedidoToken({ grant_type: 'refresh_token', client_id: CLI, refresh_token: `gpr_${'b'.repeat(64)}` })).toMatchObject({ ok: true, tipo: 'refresh' });
    expect(lerPedidoToken({ grant_type: 'refresh_token', refresh_token: `gpr_${'b'.repeat(64)}` })).toMatchObject({ ok: false, erro: 'invalid_client' });
    expect(lerPedidoToken({ grant_type: 'client_credentials', client_id: CLI })).toMatchObject({ ok: false, erro: 'unsupported_grant_type' });
  });
});

describe('oauth: metadados', () => {
  it('recurso aponta o servidor; servidor anuncia PKCE S256, registro e cliente público', () => {
    expect(metadadosRecurso(BASE)).toMatchObject({ resource: RECURSO, authorization_servers: [BASE] });
    expect(metadadosServidor(BASE)).toMatchObject({
      issuer: BASE, authorization_endpoint: `${BASE}/oauth/autorizar`, token_endpoint: `${BASE}/api/oauth/token`,
      registration_endpoint: `${BASE}/api/oauth/registrar`, code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none'],
    });
  });
});
