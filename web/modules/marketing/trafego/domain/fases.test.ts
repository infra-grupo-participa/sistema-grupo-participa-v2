import { describe, expect, it } from 'vitest';
import { faseDaCampanha, origemDaFase } from './fases';

// O mapa abaixo é a semente da 20261006g (mkt_trafego.objetivo_fase).
const MAPA = { LEADS: 'captacao', VENDAS: 'captacao', LEMBRETE: 'lembrete', REMARKETING: 'remarketing', CARRINHO: 'abertura_carrinho', AQUECIMENTO: 'aquecimento' };

describe('fase da campanha (mesma regra de mkt_trafego.fase_efetiva)', () => {
  it('pelo objetivo do nome', () => {
    expect(faseDaCampanha('LEADS', null, MAPA)).toBe('captacao');
    expect(faseDaCampanha('VENDAS', null, MAPA)).toBe('captacao');
    expect(faseDaCampanha('CARRINHO', null, MAPA)).toBe('abertura_carrinho');
    expect(faseDaCampanha('AQUECIMENTO', null, MAPA)).toBe('aquecimento');
    expect(origemDaFase('LEADS', null, MAPA)).toBe('objetivo');
  });
  it('DISTRIBUIÇÃO e nome fora do padrão ficam sem fase', () => {
    expect(faseDaCampanha('DISTRIBUIÇÃO', null, MAPA)).toBeNull();
    expect(faseDaCampanha(null, null, MAPA)).toBeNull();
    expect(origemDaFase('DISTRIBUIÇÃO', null, MAPA)).toBeNull();
  });
  it('a correção à mão prevalece', () => {
    expect(faseDaCampanha('LEADS', 'aquecimento', MAPA)).toBe('aquecimento');
    expect(faseDaCampanha('DISTRIBUIÇÃO', 'aquecimento', MAPA)).toBe('aquecimento');
    expect(origemDaFase('LEADS', 'aquecimento', MAPA)).toBe('manual');
  });
});
