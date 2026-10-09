import { describe, expect, it } from 'vitest';
import { digitosDiscagem, linkTel, linkWhatsapp, tituloLigacao } from './ligacao';

describe('ligação', () => {
  it('põe o DDI 55 em número brasileiro sem DDI', () => {
    expect(digitosDiscagem('(21) 90000-0001')).toBe('5521900000001');
    expect(digitosDiscagem('5521900000001')).toBe('5521900000001');
    expect(digitosDiscagem('123')).toBeNull();
    expect(digitosDiscagem(null)).toBeNull();
  });
  it('links tel: e wa.me', () => {
    expect(linkTel('21900000001')).toBe('tel:+5521900000001');
    expect(linkWhatsapp('21900000001')).toBe('https://wa.me/5521900000001');
    expect(linkTel('')).toBeNull();
  });
  it('título da atividade', () => {
    expect(tituloLigacao('Ana Souza', 'telefone')).toBe('Ligação para Ana');
    expect(tituloLigacao('(sem nome)', 'whatsapp')).toBe('Ligação para o lead (WhatsApp)');
  });
});
