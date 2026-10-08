import { describe, expect, it } from 'vitest';
import { mapIntegracoesStatus } from './mapeamento-integracoes';

describe('mapIntegracoesStatus', () => {
  it('formato real da RPC (resposta de 08/10/2026)', () => {
    const p = mapIntegracoesStatus({
      geradoEm: '2026-10-08T18:10:00Z',
      integracoes: [
        { chave: 'hotmart', ligada: true, configurada: true, ultimoEventoEm: '2026-10-08T18:07:11Z', eventos24h: 12, erroRecente: null },
        { chave: 'slack', ligada: true, configurada: true, ultimoEventoEm: null, eventos24h: 0,
          erroRecente: { texto: 'Aviso não enviado: 500', em: '2026-10-08T17:00:00Z' } },
      ],
      numeros: [
        { id: 'a', nome: 'Comercial oficial', provedor: 'infobip', status: 'conectado', final: '5211', ativo: true, principal: true,
          recebe: true, envia: true, ultimaMensagemEm: '2026-10-08T17:44:44Z', mensagens24h: 5, falhas24h: 0, ultimaFalha: null },
      ],
    });
    expect(p.integracoes[0]).toEqual({
      chave: 'hotmart', ligada: true, configurada: true, ultimoEventoEm: '2026-10-08T18:07:11Z', eventos24h: 12, erroRecente: null,
    });
    expect(p.integracoes[1].erroRecente).toEqual({ texto: 'Aviso não enviado: 500', em: '2026-10-08T17:00:00Z' });
    expect(p.numeros[0]).toMatchObject({ provedor: 'infobip', status: 'conectado', final: '5211', principal: true, mensagens24h: 5 });
  });
  it('campo ausente vira falso/nulo, nunca "ligado"', () => {
    const p = mapIntegracoesStatus({ geradoEm: 'x', integracoes: [{ chave: 'mcp' }], numeros: [] });
    expect(p.integracoes[0]).toEqual({ chave: 'mcp', ligada: false, configurada: false, ultimoEventoEm: null, eventos24h: 0, erroRecente: null });
  });
  it('formato inesperado é erro (nunca lista vazia)', () => {
    expect(() => mapIntegracoesStatus(null)).toThrow();
    expect(() => mapIntegracoesStatus([])).toThrow();
    expect(() => mapIntegracoesStatus({ integracoes: [], numeros: null })).toThrow();
    expect(() => mapIntegracoesStatus({ integracoes: [{}], numeros: [] })).toThrow();
    expect(() => mapIntegracoesStatus({ integracoes: [], numeros: [{ status: 'quebrado' }] })).toThrow();
  });
});
