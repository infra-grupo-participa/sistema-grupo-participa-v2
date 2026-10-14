import { describe, expect, it } from 'vitest';
import { buscarAcaoBlack, registroAcoesBlack } from './registro';

describe('registro de ações da Black', () => {
  it('registra THB vencidos como a única ação ativa com etiqueta conhecida', () => {
    const ativas = registroAcoesBlack.filter((acao) => acao.estado === 'ativa');
    expect(ativas).toHaveLength(1);
    expect(ativas[0]).toMatchObject({
      nome: 'THB vencidos',
      etiqueta: 'black-thb-2026-10',
      origem: 'renovacao-thb-vencidos',
      ofertaHotmart: null,
    });
  });

  it('mantém THB a vencer e Aurum sem etiqueta e como em breve', () => {
    expect(registroAcoesBlack.filter((acao) => acao.estado === 'em breve')).toEqual([
      { id: 'thb-a-vencer', nome: 'THB a vencer', estado: 'em breve', etiqueta: null, origem: null, ofertaHotmart: null },
      { id: 'aurum', nome: 'Aurum', estado: 'em breve', etiqueta: null, origem: null, ofertaHotmart: null },
    ]);
  });

  it('busca uma ação pelo identificador de interface', () => {
    expect(buscarAcaoBlack('thb-vencidos')?.etiqueta).toBe('black-thb-2026-10');
    expect(buscarAcaoBlack('inexistente')).toBeUndefined();
  });
});
