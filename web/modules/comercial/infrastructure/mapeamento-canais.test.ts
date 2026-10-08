import { describe, expect, it } from 'vitest';
import { mapCanais } from './mapeamento-canais';
import { mapConversas } from './mapeamento-supabase';

describe('mapCanais', () => {
  it('oficial e número por QR', () => {
    const p = mapCanais({
      evolutionLigado: false, envioLigado: true, limiteMinuto: 15, limiteHora: 200, novosHora: 20,
      canais: [
        { id: 'a', provedor: 'infobip', nome: 'Comercial oficial', final: '5211', status: 'conectado', recebe: true, envia: true, padrao: true },
        { id: 'b', provedor: 'evolution', nome: 'Clint', final: null, status: 'aguardando_qr', recebe: true, envia: false, padrao: false },
      ],
    });
    expect(p.evolutionLigado).toBe(false);
    expect(p.canais[0]).toMatchObject({ provedor: 'infobip', padrao: true, final: '5211' });
    expect(p.canais[1]).toMatchObject({ provedor: 'evolution', status: 'aguardando_qr', final: null, envia: false });
  });
  it('formato inesperado é erro (nunca lista vazia)', () => {
    expect(() => mapCanais(null)).toThrow();
    expect(() => mapCanais({ canais: [{ status: 'quebrado' }] })).toThrow();
  });
});

describe('conversa com canal', () => {
  it('canalId e canais da conversa e da mensagem', () => {
    const [c] = mapConversas([{
      contatoId: 'p1', naoLidas: 0, janelaAteEm: null, atribuidaA: null, canalId: 'b', canais: ['a', 'b'],
      ultimaMensagem: { id: 'm', contatoId: 'p1', direcao: 'saida', texto: 'oi', em: '2026-10-08T12:00:00Z', canalId: 'b', externa: true },
    }]);
    expect(c.canalId).toBe('b');
    expect(c.canais).toEqual(['a', 'b']);
    expect(c.ultimaMensagem).toMatchObject({ canalId: 'b', externa: true });
  });
});

describe('envio pelo número escolhido', () => {
  it('p_canal só vai quando a tela escolheu o número', async () => {
    const { argsEscrita } = await import('./mapeamento-escrita');
    expect(argsEscrita.enviarMensagem('p1', 'oi', null, null, 'c9')).toMatchObject({ p_canal: 'c9' });
    expect(argsEscrita.enviarMensagem('p1', 'oi')).not.toHaveProperty('p_canal');
    expect(argsEscrita.enviarAudio('p1', 'envio/u/a.ogg', 'k', 'c9')).toMatchObject({ p_canal: 'c9', p_chave: 'k' });
  });
});
