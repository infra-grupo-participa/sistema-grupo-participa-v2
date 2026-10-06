import { describe, expect, it, vi } from 'vitest';
import { receberPacote, type Entrada, type PortasColeta } from './receber-pacote';
import { LIMITE_BYTES } from '../domain/coleta';

const UA = 'Mozilla/5.0 (Linux; Android 14; SM-S911B) AppleWebKit/537.36 Chrome/129 Mobile Safari/537.36';
const PACOTE = JSON.stringify({ v: 2, projeto: 'PB26', seq: 0, sessao: { id: 'abcdefgh1234' }, pv: { id: 'pvabcdefgh12' }, eventos: [] });

function portas(x: Partial<PortasColeta> = {}): PortasColeta & { coletar: ReturnType<typeof vi.fn> } {
  return {
    dominios: async () => new Set(['patrimoniobrasil.com.br']),
    coletar: vi.fn(async () => 'ok'),
    ritmoOk: () => true,
    hashIp: (ip) => 'h' + ip.replace(/\D/g, ''),
    ...x,
  } as PortasColeta & { coletar: ReturnType<typeof vi.fn> };
}
const entrada = (x: Partial<Entrada> = {}): Entrada => ({
  metodo: 'POST', origem: 'https://patrimoniobrasil.com.br', tamanhoDeclarado: PACOTE.length, userAgent: UA, ip: '200.1.2.3',
  lerCorpo: async () => PACOTE, ...x,
});

describe('rota /api/web/coletar', () => {
  it('pacote bom vai ao banco com a origem e o hash do IP (nunca o IP)', async () => {
    const p = portas();
    const s = await receberPacote(entrada(), p);
    expect(s).toEqual({ status: 200, resposta: 'ok', origemPermitida: 'https://patrimoniobrasil.com.br' });
    expect(p.coletar).toHaveBeenCalledWith(PACOTE, 'https://patrimoniobrasil.com.br', 'h200123');
    expect(JSON.stringify(p.coletar.mock.calls)).not.toContain('200.1.2.3');
  });
  it('domínio não cadastrado: 403, sem CORS e sem banco', async () => {
    const p = portas();
    const s = await receberPacote(entrada({ origem: 'https://evil.example' }), p);
    expect(s).toEqual({ status: 403, resposta: 'dominio', origemPermitida: null });
    expect(p.coletar).not.toHaveBeenCalled();
  });
  it('payload grande pelo content-length ou pelo corpo de verdade: 413', async () => {
    const p = portas();
    expect((await receberPacote(entrada({ tamanhoDeclarado: LIMITE_BYTES + 10 }), p)).resposta).toBe('tamanho');
    const s = await receberPacote(entrada({ tamanhoDeclarado: null, lerCorpo: async () => null }), p);
    expect(s).toMatchObject({ status: 413, resposta: 'tamanho' });
    expect(p.coletar).not.toHaveBeenCalled();
  });
  it('excesso de envio do mesmo IP: 429 "limite", sem banco', async () => {
    const p = portas({ ritmoOk: () => false });
    const s = await receberPacote(entrada(), p);
    expect(s).toMatchObject({ status: 429, resposta: 'limite' });
    expect(p.coletar).not.toHaveBeenCalled();
  });
  it('o limite do banco (por sessão) também vira 429', async () => {
    const s = await receberPacote(entrada(), portas({ coletar: vi.fn(async () => 'limite') }));
    expect(s).toMatchObject({ status: 429, resposta: 'limite' });
  });
  it('robô: "pausado" com CORS (o gravador lê e para), sem banco', async () => {
    const p = portas();
    const s = await receberPacote(entrada({ userAgent: 'curl/8.4.0' }), p);
    expect(s).toEqual({ status: 200, resposta: 'pausado', origemPermitida: 'https://patrimoniobrasil.com.br' });
    expect(p.coletar).not.toHaveBeenCalled();
  });
  it('corpo que não é JSON: 400 "json"', async () => {
    expect(await receberPacote(entrada({ lerCorpo: async () => 'oi' }), portas())).toMatchObject({ status: 400, resposta: 'json' });
  });
  it('banco fora: lista de domínios indisponível = 503; erro na coleta = 502 "erro"', async () => {
    expect(await receberPacote(entrada(), portas({ dominios: async () => null }))).toMatchObject({ status: 503, resposta: 'erro' });
    const s = await receberPacote(entrada(), portas({ coletar: vi.fn(async () => { throw new Error('rede'); }) }));
    expect(s).toMatchObject({ status: 502, resposta: 'erro' });
  });
  it('resposta estranha do banco vira "erro"', async () => {
    expect((await receberPacote(entrada(), portas({ coletar: vi.fn(async () => ({ x: 1 })) }))).resposta).toBe('erro');
  });
});
