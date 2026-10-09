import { describe, expect, it } from 'vitest';
import { amanha9h, emUmaHora, linkDaConversa, motivoNaoAgendar, paraInputLocal } from './agendamento';

const AGORA = new Date(2026, 9, 9, 14, 7, 30);

describe('agendamento', () => {
  it('atalhos: em 1h (arredonda 5 min) e amanhã 9h', () => {
    expect(paraInputLocal(emUmaHora(AGORA))).toBe('2026-10-09T15:10');
    expect(paraInputLocal(amanha9h(AGORA))).toBe('2026-10-10T09:00');
  });
  it('valida texto, horário e janela do oficial', () => {
    const base = { texto: 'Oi', agora: AGORA, oficial: false, comTemplate: false, janelaAteEm: null };
    expect(motivoNaoAgendar({ ...base, quando: new Date(AGORA.getTime() + 3600_000) })).toBeNull();
    expect(motivoNaoAgendar({ ...base, texto: ' ', quando: new Date(AGORA.getTime() + 3600_000) })).toBe('Escreva a mensagem.');
    expect(motivoNaoAgendar({ ...base, quando: new Date(AGORA.getTime() - 1) })).toBe('Escolha um horário no futuro.');
    expect(motivoNaoAgendar({ ...base, quando: new Date(AGORA.getTime() + 31 * 86_400_000) })).toMatch(/30 dias/);
    const quando = new Date(AGORA.getTime() + 3600_000);
    expect(motivoNaoAgendar({ ...base, oficial: true, quando, janelaAteEm: null })).toMatch(/janela de 24 h/);
    expect(motivoNaoAgendar({ ...base, oficial: true, quando, janelaAteEm: new Date(AGORA.getTime() + 7200_000).toISOString() })).toBeNull();
    expect(motivoNaoAgendar({ ...base, oficial: true, comTemplate: true, texto: '', quando, janelaAteEm: null })).toBeNull();
  });
  it('link da conversa sempre no domínio oficial', () => {
    expect(linkDaConversa('a b')).toBe('https://grupoparticipa.app.br/comercial/conversas?contato=a%20b');
  });
});
