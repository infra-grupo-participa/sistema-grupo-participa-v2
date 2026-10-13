import { describe, expect, it } from 'vitest';
import { amostraCusto, amostraTaxa, classificar, lerCusto, lerTaxa, poderTaxa, precisaTestar, sugerirNivel } from './estatistica';

const perto = (v: number, alvo: number, tol = 0.025) => expect(Math.abs(v - alvo) / alvo).toBeLessThanOrEqual(tol);

describe('amostra para taxa reproduz a tabela 7.1 do playbook', () => {
  const tabela: [number, number, number][] = [
    [0.02, 0.2, 21100], [0.02, 0.3, 9800], [0.02, 0.5, 3800], [0.02, 1, 1140],
    [0.05, 0.2, 8160], [0.05, 0.3, 3780], [0.05, 0.5, 1470], [0.05, 1, 430],
    [0.1, 0.2, 3840], [0.1, 0.3, 1770], [0.1, 0.5, 690], [0.1, 1, 200],
    [0.2, 0.2, 1680], [0.2, 0.3, 770], [0.2, 0.5, 290], [0.2, 1, 80],
    [0.4, 0.2, 600], [0.4, 0.3, 270], [0.4, 0.5, 100], [0.4, 1, 22],
  ];
  it.each(tabela)('taxa %s, régua %s → ~%s', (taxa, regua, alvo) => perto(amostraTaxa(taxa, regua), alvo, 0.05));
});

describe('amostra para custo reproduz a tabela 7.2', () => {
  it.each([[1, 33], [0.5, 95], [0.3, 230], [0.25, 315]])('régua %s → ~%s', (regua, alvo) => perto(amostraCusto(regua), alvo, 0.03));
});

describe('sensibilidade do exemplo BL2 (6A.2): ~1.450 por versão, MQL por visita 11,9%', () => {
  it('30% → ~80%, 20% → ~48%, 10% → ~16%, 50% → ~99%', () => {
    expect(poderTaxa(0.119, 0.3, 1450)).toBeCloseTo(0.8, 1);
    expect(poderTaxa(0.119, 0.2, 1450)).toBeCloseTo(0.48, 1);
    expect(poderTaxa(0.119, 0.1, 1450)).toBeCloseTo(0.16, 1);
    expect(poderTaxa(0.119, 0.5, 1450)).toBeGreaterThan(0.97);
  });
  it('com ~3.400 por versão, 20% sobe para ~83%', () => expect(poderTaxa(0.119, 0.2, 3400)).toBeCloseTo(0.83, 1));
});

describe('leitura e os quatro resultados', () => {
  it('diferença grande com amostra cheia é vencedor de B', () => {
    const l = lerTaxa(1800, 180, 1800, 245)!;
    expect(l.confianca).toBeGreaterThan(0.99);
    const c = classificar(l, { regua: 0.3, amostraChegou: true, medicaoOk: true });
    expect(c.resultado).toBe('vencedor');
    expect(c.quem).toBe('B');
  });
  it('amostra que não chegou é inconclusivo, mesmo parecendo óbvio', () => {
    const l = lerTaxa(100, 10, 100, 30)!;
    expect(classificar(l, { regua: 0.3, amostraChegou: false, medicaoOk: true }).resultado).toBe('inconclusivo');
  });
  it('medição quebrada é inconclusivo', () => {
    const l = lerTaxa(1800, 180, 1800, 245)!;
    expect(classificar(l, { regua: 0.3, amostraChegou: true, medicaoOk: false }).resultado).toBe('inconclusivo');
  });
  it('confiança entre 90 e 95% é provável', () => {
    const l = lerTaxa(2000, 200, 2000, 236)!;
    expect(l.confianca).toBeGreaterThan(0.9);
    expect(l.confianca).toBeLessThan(0.95);
    expect(classificar(l, { regua: 0.3, amostraChegou: true, medicaoOk: true }).resultado).toBe('provavel');
  });
  it('intervalo inteiro dentro da régua é empate prático', () => {
    const l = lerTaxa(40000, 4000, 40000, 4020)!;
    expect(classificar(l, { regua: 0.3, amostraChegou: true, medicaoOk: true }).resultado).toBe('empate');
  });
  it('pouca diferença e margem larga é inconclusivo', () => {
    const l = lerTaxa(300, 30, 300, 33)!;
    expect(classificar(l, { regua: 0.3, amostraChegou: true, medicaoOk: true }).resultado).toBe('inconclusivo');
  });
  it('custo: B rende mais resultado por real', () => {
    const l = lerCusto(10000, 250, 10000, 350)!;
    expect(l.beneficio).toBeCloseTo(0.4, 5);
    expect(l.confianca).toBeGreaterThan(0.95);
    expect(l.detalhe.custoB).toBeLessThan(l.detalhe.custoA);
  });
  it('dados inválidos não leem', () => {
    expect(lerTaxa(0, 0, 10, 1)).toBeNull();
    expect(lerTaxa(10, 11, 10, 1)).toBeNull();
    expect(lerCusto(100, 0, 100, 1)).toBeNull();
  });
});

describe('nível e pergunta de controle', () => {
  it('seção 3', () => {
    expect(sugerirNivel({ pequenaEReversivel: true, temVolumeESorteio: true })).toBe(1);
    expect(sugerirNivel({ pequenaEReversivel: false, temVolumeESorteio: true })).toBe(3);
    expect(sugerirNivel({ pequenaEReversivel: false, temVolumeESorteio: false })).toBe(2);
  });
  it('seção 10: respostas iguais dispensam o teste', () => {
    expect(precisaTestar('Mantemos a página atual.', 'mantemos a página atual')).toBe(false);
    expect(precisaTestar('Trocamos a página', 'Mantemos a atual')).toBe(true);
    expect(precisaTestar('', '')).toBe(true);
  });
});
