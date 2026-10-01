import { afterEach, describe, expect, it } from 'vitest';
import { clientIp, placaTrackingLink, publicAppBaseUrl, validateOrigin } from './security';
import { rateLimitOk } from './rate-limit';

const ORIGINAL = process.env.NEXT_PUBLIC_APP_URL;
afterEach(() => {
  if (ORIGINAL === undefined) delete process.env.NEXT_PUBLIC_APP_URL;
  else process.env.NEXT_PUBLIC_APP_URL = ORIGINAL;
});

const TOKEN = '11111111-2222-4333-8444-555555555555';

function req(method: string, headers: Record<string, string>): Request {
  return new Request('https://grupoparticipa.app.br/api/placa', { method, headers });
}

describe('link de e-mail não usa o Host da requisição', () => {
  it('usa NEXT_PUBLIC_APP_URL (sem barra final)', () => {
    process.env.NEXT_PUBLIC_APP_URL = 'https://app.exemplo.com.br/';
    expect(publicAppBaseUrl()).toBe('https://app.exemplo.com.br');
    expect(placaTrackingLink(TOKEN)).toBe(`https://app.exemplo.com.br/solicitar-placa?token=${TOKEN}`);
  });

  it('cai no fallback de produção quando a env falta ou é inválida', () => {
    delete process.env.NEXT_PUBLIC_APP_URL;
    expect(publicAppBaseUrl()).toBe('https://grupoparticipa.app.br');
    process.env.NEXT_PUBLIC_APP_URL = 'javascript:alert(1)';
    expect(publicAppBaseUrl()).toBe('https://grupoparticipa.app.br');
  });

  it('Host/X-Forwarded-Host forjados não alteram o link', () => {
    delete process.env.NEXT_PUBLIC_APP_URL;
    // Atacante fora do navegador forja Host e Origin iguais: passa no same-origin...
    const r = req('POST', { host: 'evil.com', 'x-forwarded-host': 'evil.com', origin: 'https://evil.com' });
    expect(validateOrigin(r)).toBe('https://evil.com');
    // ...mas o link do e-mail é independente da requisição.
    expect(placaTrackingLink(TOKEN)).toBe(`https://grupoparticipa.app.br/solicitar-placa?token=${TOKEN}`);
    expect(placaTrackingLink(TOKEN)).not.toContain('evil');
  });
});

describe('validateOrigin — GET sem Origin/Referer', () => {
  it('GET sem Origin, sec-fetch-site same-origin → aceito', () => {
    expect(validateOrigin(req('GET', { 'sec-fetch-site': 'same-origin' }))).not.toBeNull();
  });
  it('GET sem Origin, sec-fetch-site none → aceito', () => {
    expect(validateOrigin(req('GET', { 'sec-fetch-site': 'none' }))).not.toBeNull();
  });
  it('GET sem Origin e sem sec-fetch-site → aceito', () => {
    expect(validateOrigin(req('GET', {}))).not.toBeNull();
  });
  it('GET sem Origin, sec-fetch-site cross-site → recusado', () => {
    expect(validateOrigin(req('GET', { 'sec-fetch-site': 'cross-site' }))).toBeNull();
  });
  it('GET sem Origin, sec-fetch-site same-site → recusado', () => {
    expect(validateOrigin(req('GET', { 'sec-fetch-site': 'same-site' }))).toBeNull();
  });
  it('POST sem Origin/Referer continua recusado, mesmo com same-origin', () => {
    expect(validateOrigin(req('POST', { 'sec-fetch-site': 'same-origin' }))).toBeNull();
  });
  it('GET com Origin de terceiro continua recusado', () => {
    expect(validateOrigin(req('GET', { origin: 'https://evil.com', host: 'grupoparticipa.app.br' }))).toBeNull();
  });
  it('POST com Origin oficial continua aceito', () => {
    expect(validateOrigin(req('POST', { origin: 'https://grupoparticipa.app.br' }))).toBe('https://grupoparticipa.app.br');
  });
});

describe('clientIp (LiteSpeed sem Cloudflare)', () => {
  it('ignora cf-connecting-ip forjado', () => {
    const r = req('GET', { 'cf-connecting-ip': '6.6.6.6', 'x-forwarded-for': '200.1.2.3' });
    expect(clientIp(r)).toBe('200.1.2.3');
  });

  it('usa o salto mais à direita (o que o proxy acrescentou), não o primeiro que o cliente manda', () => {
    expect(clientIp(req('GET', { 'x-forwarded-for': '1.1.1.1, 200.1.2.3' }))).toBe('200.1.2.3');
  });

  it('pula saltos internos à direita', () => {
    expect(clientIp(req('GET', { 'x-forwarded-for': '1.1.1.1, 200.1.2.3, 127.0.0.1, 10.0.0.5' }))).toBe('200.1.2.3');
  });

  it('sem XFF cai em x-real-ip, depois unknown', () => {
    expect(clientIp(req('GET', { 'x-real-ip': '200.9.9.9' }))).toBe('200.9.9.9');
    expect(clientIp(req('GET', {}))).toBe('unknown');
  });

  it('cf-connecting-ip e XFF da esquerda forjados não mudam a chave do rate limit', () => {
    const prefixo = `gp_teste_ip_${Date.now()}_`;
    const tentativa = (i: number) =>
      rateLimitOk(
        clientIp(req('POST', { 'cf-connecting-ip': `6.6.6.${i}`, 'x-forwarded-for': `9.9.9.${i}, 200.1.2.3` })),
        prefixo,
        3,
        60,
      );
    expect([tentativa(1), tentativa(2), tentativa(3), tentativa(4), tentativa(5)]).toEqual([true, true, true, false, false]);
  });
});
