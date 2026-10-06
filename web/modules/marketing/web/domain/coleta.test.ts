import { describe, expect, it } from 'vitest';
import { LIMITE_BYTES, avaliarPedido, corpoValido, ehRobo, hostDaOrigem, linhaDoGravador, respostaDoBanco } from './coleta';

const CELULAR = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 330.0';
const DOMINIOS = new Set(['patrimoniobrasil.com.br']);
const pedido = (x: Partial<Parameters<typeof avaliarPedido>[0]> = {}) => ({
  metodo: 'POST', origem: 'https://patrimoniobrasil.com.br', tamanhoDeclarado: 1200, userAgent: CELULAR, ...x,
});

describe('host da origem', () => {
  it('tira www, porta e caminho', () => {
    expect(hostDaOrigem('https://www.PatrimonioBrasil.com.br')).toBe('patrimoniobrasil.com.br');
    expect(hostDaOrigem('https://patrimoniobrasil.com.br:443/ak1/')).toBe('patrimoniobrasil.com.br');
  });
  it('origem vazia, "null" ou esquema estranho = vazio', () => {
    expect(hostDaOrigem(null)).toBe('');
    expect(hostDaOrigem('null')).toBe('');
    expect(hostDaOrigem('file:///c:/x.html')).toBe('');
    expect(hostDaOrigem('javascript:alert(1)')).toBe('');
  });
});

describe('primeira barreira da rota', () => {
  it('pedido normal passa, com o host', () => {
    expect(avaliarPedido(pedido(), DOMINIOS)).toEqual({ ok: true, host: 'patrimoniobrasil.com.br' });
    expect(avaliarPedido(pedido({ origem: 'https://www.patrimoniobrasil.com.br' }), DOMINIOS)).toEqual({ ok: true, host: 'patrimoniobrasil.com.br' });
  });
  it('domínio não cadastrado ou sem origem: 403 "dominio"', () => {
    expect(avaliarPedido(pedido({ origem: 'https://evil.example' }), DOMINIOS)).toMatchObject({ ok: false, resposta: 'dominio', status: 403 });
    expect(avaliarPedido(pedido({ origem: null }), DOMINIOS)).toMatchObject({ ok: false, resposta: 'dominio' });
    expect(avaliarPedido(pedido({ origem: 'https://patrimoniobrasil.com.br.evil.example' }), DOMINIOS)).toMatchObject({ ok: false, resposta: 'dominio' });
  });
  it('payload grande: 413 "tamanho"', () => {
    expect(avaliarPedido(pedido({ tamanhoDeclarado: LIMITE_BYTES + 1 }), DOMINIOS)).toMatchObject({ ok: false, resposta: 'tamanho', status: 413 });
  });
  it('método diferente de POST: 405', () => {
    expect(avaliarPedido(pedido({ metodo: 'GET' }), DOMINIOS)).toMatchObject({ ok: false, resposta: 'metodo', status: 405 });
  });
  it('robô recebe "pausado" sem ir ao banco', () => {
    expect(avaliarPedido(pedido({ userAgent: 'Mozilla/5.0 (compatible; Googlebot/2.1)' }), DOMINIOS)).toMatchObject({ ok: false, resposta: 'pausado', status: 200 });
  });
});

describe('robô', () => {
  it('reconhece robôs e o teste do Google', () => {
    expect(ehRobo('curl/8.4.0')).toBe(true);
    expect(ehRobo('facebookexternalhit/1.1')).toBe(true);
    expect(ehRobo('Mozilla/5.0 (Linux; Android 11; moto g power (2022)) AppleWebKit/537.36 Chrome/127 Mobile Safari/537.36')).toBe(true);
    expect(ehRobo('')).toBe(true);
    expect(ehRobo(CELULAR)).toBe(false);
  });
});

describe('corpo', () => {
  it('corpo de verdade acima do limite (o content-length pode mentir)', () => {
    expect(corpoValido('{' + 'x'.repeat(LIMITE_BYTES) + '}')).toBe('tamanho');
    expect(corpoValido('{"v":2}')).toBeNull();
    expect(corpoValido('nao e json')).toBe('json');
  });
  it('letra acentuada conta em bytes, não em caracteres', () => {
    expect(corpoValido('{' + 'ç'.repeat(LIMITE_BYTES / 2) + '}')).toBe('tamanho');
  });
  it('resposta do banco só da lista', () => {
    expect(respostaDoBanco('ok')).toBe('ok');
    expect(respostaDoBanco('limite')).toBe('limite');
    expect(respostaDoBanco('qualquer')).toBe('erro');
    expect(respostaDoBanco(null)).toBe('erro');
  });
});

describe('linha de instalação', () => {
  it('aponta para o nosso domínio, com a sigla e async', () => {
    expect(linhaDoGravador('PB26', 'https://grupoparticipa.app.br')).toBe(
      '<script src="https://grupoparticipa.app.br/web/radar-v1.js" data-projeto="PB26" async></script>');
  });
});
