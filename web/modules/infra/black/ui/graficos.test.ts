import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { BarrasFase, textoDaVerba, type ItemFase } from './graficos';
import { verbaDaFase } from '../domain/verba-fase';
import { moeda } from './pecas';

const html = (itens: ItemFase[]) => renderToStaticMarkup(createElement(BarrasFase, { itens, formato: 'brl' }));
const marcos = (h: string) => (h.match(/data-marco-limite/g) ?? []).length;
// Intl usa espaço não separável entre R$ e o valor: compara sem espaços para não depender do caractere.
const plano = (t: string) => t.replace(/\s/g, '');

describe('textoDaVerba', () => {
  it('perto: percentual do limite e quanto falta', () => {
    const t = textoDaVerba(verbaDaFase(1000, 50000), true);
    expect(plano(t)).toBe(plano(`2,0% do limite · faltam ${moeda(49000)}`));
  });
  it('estourou: quanto passou', () => {
    const t = textoDaVerba(verbaDaFase(60000, 50000), true);
    expect(plano(t)).toBe(plano(`120,0% do limite · passou ${moeda(10000)} do limite`));
  });
  it('sem dado de gasto não vira zero', () => {
    const t = textoDaVerba(verbaDaFase(null, 30000), true);
    expect(plano(t)).toBe(plano(`Sem dado de gasto · limite ${moeda(30000)}`));
    expect(t).not.toMatch(/0%/);
  });
  it('sem limite cadastrado', () => {
    expect(textoDaVerba(verbaDaFase(500, null), true)).toBe('Sem limite cadastrado');
  });
  it('recorte parcial não calcula percentual nem saldo', () => {
    const t = textoDaVerba(verbaDaFase(1000, 50000), false);
    expect(t).toMatch(/Recorte parcial/);
    expect(t).not.toMatch(/faltam|passou/);
  });
});

describe('BarrasFase com limite de verba', () => {
  const itens: ItemFase[] = [
    { fase: 'captacao', rotulo: '2. Captação', valor: 1000, limite: 50000, limiteComparavel: true },
    { fase: 'aquecimento', rotulo: '3. Aquecimento', valor: 30000, limite: 26909, limiteComparavel: true },
    { fase: 'remarketing', rotulo: '4. Remarketing', valor: null, limite: 30000, limiteComparavel: true },
    { fase: 'live_carrinho', rotulo: '5. Live e carrinho', valor: null, limite: null, limiteComparavel: true },
    { fase: 'sem_fase', rotulo: 'Sem fase', valor: 12 },
  ];
  const h = html(itens);

  it('põe um marco por fase com limite cadastrado (3), nenhum na sem limite nem na sem fase', () => {
    expect(marcos(h)).toBe(3);
  });
  it('mostra limite, gasto, percentual e o que falta ou passou', () => {
    expect(plano(h)).toContain(plano(`Limite ${moeda(50000)}`));
    expect(plano(h)).toContain(plano(`faltam ${moeda(49000)}`));
    expect(plano(h)).toContain(plano(`passou ${moeda(3091)} do limite`));
  });
  it('fase sem gasto medido diz "Sem dado" e a sem limite diz "Sem limite cadastrado"', () => {
    expect(h).toContain('Sem dado de gasto');
    expect(h).toContain('Sem limite cadastrado');
  });
  it('a escala de cada barra cabe o limite: nenhuma largura passa de 100% e o marco fica dentro da trilha', () => {
    for (const m of h.matchAll(/width:([\d.]+)%/g)) expect(Number(m[1])).toBeLessThanOrEqual(100);
    for (const m of h.matchAll(/left:calc\(([\d.]+)% - 1px\)/g)) expect(Number(m[1])).toBeLessThanOrEqual(100);
  });
  it('legenda do marco só aparece com limite', () => {
    expect(h).toContain('marco do limite de verba da fase');
    expect(html([{ fase: 'captacao', rotulo: '2. Captação', valor: 10 }])).not.toContain('marco do limite');
    expect(marcos(html([{ fase: 'captacao', rotulo: '2. Captação', valor: 10 }]))).toBe(0);
  });
});
