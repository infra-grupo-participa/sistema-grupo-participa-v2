import { describe, expect, it } from 'vitest';
import { montarMensagem, varianteDoSinal } from './script';

describe('script de abordagem', () => {
  it('escolhe a variante pelo sinal mais forte', () => {
    expect(varianteDoSinal(['comunidade', 'ficha_completa'])).toBe('ficha_completa');
    expect(varianteDoSinal(['chat', 'senhas'])).toBe('senhas');
    expect(varianteDoSinal(['carrinho'])).toBe('base');
  });

  it('preenche primeiro nome do lead, do vendedor e o evento, sem link', () => {
    const m = montarMensagem('base', 'Ana Paula Souza', 'Marcos Paulo', 'Imersão Holding Total');
    expect(m.startsWith('Oi Ana, tudo bem? Aqui é o Marcos,')).toBe(true);
    expect(m).toContain('aulas do Imersão Holding Total');
    expect(m).not.toMatch(/https?:\/\//);
  });
});
