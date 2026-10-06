import { describe, expect, it } from 'vitest';
import { extrairCodigoOferta, linkCheckout } from './hotmart';

describe('extrairCodigoOferta', () => {
  it('link de checkout com off=', () => {
    expect(extrairCodigoOferta('https://pay.hotmart.com/4120577?off=hm30k12x&sck=hm-rec')).toBe('hm30k12x');
    expect(extrairCodigoOferta('  https://pay.hotmart.com/X1?checkoutMode=10&off=abc_123 ')).toBe('abc_123');
  });
  it('código colado direto', () => {
    expect(extrairCodigoOferta('ht33lote1')).toBe('ht33lote1');
  });
  it('lixo devolve null', () => {
    expect(extrairCodigoOferta('')).toBeNull();
    expect(extrairCodigoOferta('https://pay.hotmart.com/123')).toBeNull();
    expect(extrairCodigoOferta('isso não é código')).toBeNull();
  });
  it('monta o link', () => {
    expect(linkCheckout('1', 'a')).toBe('https://pay.hotmart.com/1?off=a');
  });
});
