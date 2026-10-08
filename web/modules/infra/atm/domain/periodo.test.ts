import { describe, expect, it } from 'vitest';
import { dataPtBr, datasDoPeriodo, deslocarDia, hojeEmSaoPaulo } from './periodo';

describe('períodos do dashboard ATM', () => {
  it('usa a data de São Paulo, inclusive perto da virada UTC', () => {
    expect(hojeEmSaoPaulo(new Date('2026-10-08T02:59:00Z'))).toBe('2026-10-07');
    expect(hojeEmSaoPaulo(new Date('2026-10-08T03:00:00Z'))).toBe('2026-10-08');
  });

  it('calcula hoje, ontem, três e sete dias com intervalo inclusivo', () => {
    const agora = new Date('2026-10-08T15:00:00Z');
    expect(datasDoPeriodo('hoje', agora)).toEqual({ p_de: '2026-10-08', p_ate: '2026-10-08' });
    expect(datasDoPeriodo('ontem', agora)).toEqual({ p_de: '2026-10-07', p_ate: '2026-10-07' });
    expect(datasDoPeriodo('3d', agora)).toEqual({ p_de: '2026-10-06', p_ate: '2026-10-08' });
    expect(datasDoPeriodo('7d', agora)).toEqual({ p_de: '2026-10-02', p_ate: '2026-10-08' });
  });

  it('deixa o período do evento sob controle da configuração do banco', () => {
    expect(datasDoPeriodo('evento')).toEqual({ p_de: null, p_ate: null });
  });

  it('desloca datas calendáricas sem depender do fuso do navegador', () => {
    expect(deslocarDia('2026-03-01', -1)).toBe('2026-02-28');
    expect(dataPtBr('2026-10-14')).toBe('14/10/2026');
  });
});
