import { describe, expect, it } from 'vitest';
import { NextRequest } from 'next/server';
import { PLACA_SESSION_COOKIE, failedTokenIsCookie, resolvePlacaToken, resolvePlacaTokenSource } from './session-cookie';

const URL_TOKEN = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const COOKIE_TOKEN = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const BODY_TOKEN = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

function req(query: string | null, cookie: string | null): NextRequest {
  const url = `https://grupoparticipa.app.br/api/placa${query ? `?token=${query}` : ''}`;
  const headers: Record<string, string> = {};
  if (cookie) headers.cookie = `${PLACA_SESSION_COOKIE}=${cookie}`;
  return new NextRequest(url, { headers });
}

describe('resolvePlacaTokenSource', () => {
  it('token da URL (inexistente) + cookie válido: escolhe a URL, informa a origem e preserva o cookie', () => {
    const r = resolvePlacaTokenSource(req(URL_TOKEN, COOKIE_TOKEN));
    expect(r).toEqual({ token: URL_TOKEN, source: 'query', cookieToken: COOKIE_TOKEN });
    // Falha do token da URL NÃO autoriza apagar o cookie.
    expect(failedTokenIsCookie(r)).toBe(false);
  });

  it('só cookie: falha autoriza apagar o cookie', () => {
    const r = resolvePlacaTokenSource(req(null, COOKIE_TOKEN));
    expect(r.source).toBe('cookie');
    expect(failedTokenIsCookie(r)).toBe(true);
  });

  it('URL igual ao cookie: falha autoriza apagar (o cookie é o mesmo token inválido)', () => {
    const r = resolvePlacaTokenSource(req(URL_TOKEN.toUpperCase(), URL_TOKEN));
    expect(r.source).toBe('query');
    expect(failedTokenIsCookie(r)).toBe(true);
  });

  it('body tem prioridade e não autoriza apagar cookie diferente', () => {
    const r = resolvePlacaTokenSource(req(URL_TOKEN, COOKIE_TOKEN), { token: BODY_TOKEN });
    expect(r.source).toBe('body');
    expect(r.token).toBe(BODY_TOKEN);
    expect(failedTokenIsCookie(r)).toBe(false);
  });

  it('lixo na URL é ignorado e cai para o cookie', () => {
    const r = resolvePlacaTokenSource(req('nao-e-uuid', COOKIE_TOKEN));
    expect(r).toEqual({ token: COOKIE_TOKEN, source: 'cookie', cookieToken: COOKIE_TOKEN });
  });

  it('nada válido → token vazio, source null', () => {
    const r = resolvePlacaTokenSource(req(null, 'lixo'));
    expect(r).toEqual({ token: '', source: null, cookieToken: '' });
    expect(failedTokenIsCookie(r)).toBe(false);
  });

  it('resolvePlacaToken mantém o contrato antigo (string)', () => {
    expect(resolvePlacaToken(req(URL_TOKEN, COOKIE_TOKEN))).toBe(URL_TOKEN);
  });
});
