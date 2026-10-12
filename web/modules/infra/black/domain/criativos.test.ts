import { describe, expect, it } from 'vitest';
import { baseFicticia } from '../infrastructure/fixtures/gerador';
import { CONFIG_BLACK } from '../infrastructure/fixtures/catalogo';
import { indexar } from './metricas';
import { ordenar, painel, serieDiariaAnuncio } from './criativos';

const b = baseFicticia();
const idx = indexar(b);
const regua = CONFIG_BLACK.reguaCpl;
const nomePagina = (id: string) => id;

describe('criativos e páginas', () => {
  it('painel de campanhas: soma do gasto = gasto total; nome = string exata da campanha', () => {
    const itens = painel('campanha', {}, b.dias, b.linhas, idx, regua, nomePagina);
    const total = b.dias.reduce((s, d) => s + d.gasto, 0);
    expect(itens.reduce((s, i) => s + i.resumo.gasto, 0)).toBeCloseTo(total, 6);
    for (const i of itens) expect(i.nome).toBe(b.campanhas.find((c) => c.id === i.id)!.nome);
  });
  it('filtro cruzado: o painel de campanhas continua vendo as irmãs da campanha escolhida', () => {
    const f = { campanha: 'cp-iscas' };
    expect(painel('campanha', f, b.dias, b.linhas, idx, regua, nomePagina).length).toBeGreaterThan(1);
    const conj = painel('conjunto', f, b.dias, b.linhas, idx, regua, nomePagina);
    expect(conj.every((c) => b.conjuntos.find((x) => x.id === c.id)!.campanhaId === 'cp-iscas')).toBe(true);
  });
  it('CPL do criativo = gasto ÷ leads pagos dele; C1 é distribuição (sem CPL)', () => {
    const anuncios = painel('anuncio', {}, b.dias, b.linhas, idx, regua, nomePagina);
    const capt = anuncios.find((a) => !a.resumo.distribuicao && a.resumo.leadsPagos > 0)!;
    expect(capt.resumo.cpl).toBeCloseTo(capt.resumo.gasto / capt.resumo.leadsPagos, 6);
    const c1 = anuncios.filter((a) => idx.campanhaDoAnuncio(a.id)?.funil === 'c1');
    expect(c1.length).toBeGreaterThan(0);
    expect(c1.every((a) => a.resumo.distribuicao && a.resumo.cpl === null && a.resumo.farol === 'sem')).toBe(true);
  });
  it('ordem por menor CPL deixa quem não tem CPL no fim', () => {
    const o = ordenar(painel('anuncio', {}, b.dias, b.linhas, idx, regua, nomePagina), 'cpl');
    const primeiroNulo = o.findIndex((x) => x.resumo.cpl === null);
    expect(primeiroNulo).toBeGreaterThan(0);
    expect(o.slice(primeiroNulo).every((x) => x.resumo.cpl === null)).toBe(true);
    for (let i = 1; i < primeiroNulo; i += 1) expect(o[i].resumo.cpl!).toBeGreaterThanOrEqual(o[i - 1].resumo.cpl!);
  });
  it('série diária do anúncio fecha com o resumo', () => {
    const a = painel('anuncio', { campanha: 'cp-iscas' }, b.dias, b.linhas, idx, regua, nomePagina)[0];
    const dias = [...new Set(b.dias.map((d) => d.dia))].sort();
    const s = serieDiariaAnuncio(a.id, b.dias, b.linhas, dias);
    expect(s.reduce((x, d) => x + d.gasto, 0)).toBeCloseTo(a.resumo.gasto, 6);
  });
});
