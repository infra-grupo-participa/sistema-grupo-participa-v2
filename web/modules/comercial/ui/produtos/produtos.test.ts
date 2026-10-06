import { describe, expect, it } from 'vitest';
import type { OfertaHotmart, OfertaOrfa, ProdutoHotmart } from '../../domain/types';
import {
  FILTRO_INICIAL, colaDoVendedor, diaLocal, familias, filtrarProdutos, ofertaAlterada, ofertaVencida, ofertaValendo, ordenarOrfas,
  paraSalvar, rascunhoOferta, resumoProduto, resumoTela, rotuloModo, validarOferta, validarVinculo,
} from './produtos';

const HOJE = '2026-10-05';

const prod = (produtoId: string, extra: Partial<ProdutoHotmart> = {}): ProdutoHotmart => ({
  produtoId, nomeHotmart: `PRODUTO ${produtoId}`, conta: 'academy', familia: 'HT', noComercial: false, nomeComercial: null,
  produtoKey: null, agrupadorId: null, escada: null, sincronizadoEm: '2026-10-05T10:00:00Z', ...extra,
});

const of = (codigo: string, produtoId: string, extra: Partial<OfertaHotmart> = {}): OfertaHotmart => ({
  codigo, produtoId, nomeHotmart: `Oferta ${codigo}`, preco: 100, moeda: 'BRL', modo: 'UNIQUE_PAYMENT', principal: false,
  linkCheckout: `https://pay.hotmart.com?off=${codigo}`, vigente: false, condicao: null, validaAte: null, uso: null,
  transacoes: 0, ultimaVendaEm: null, vistaEm: '2026-10-05T10:00:00Z', ...extra,
});

describe('rotuloModo', () => {
  it('traduz os modos da Hotmart', () => {
    expect(rotuloModo('UNIQUE_PAYMENT')).toBe('Pagamento único');
    expect(rotuloModo('HOTMART_INSTALLMENTS_UNIQUE_LINK')).toBe('Parcelado (link único)');
    expect(rotuloModo('FINANCED_BILLET')).toBe('Boleto financiado');
  });
  it('modo desconhecido volta como veio; vazio vira traço', () => {
    expect(rotuloModo('NOVO_MODO')).toBe('NOVO_MODO');
    expect(rotuloModo(null)).toBe('—');
  });
});

describe('diaLocal', () => {
  it('formata em YYYY-MM-DD local', () => {
    expect(diaLocal(new Date(2026, 0, 7, 23, 30))).toBe('2026-01-07');
  });
});

describe('vigência', () => {
  it('vencida só quando vigente e validade antes de hoje', () => {
    expect(ofertaVencida({ vigente: true, validaAte: '2026-10-04' }, HOJE)).toBe(true);
    expect(ofertaVencida({ vigente: true, validaAte: '2026-10-05' }, HOJE)).toBe(false);
    expect(ofertaVencida({ vigente: false, validaAte: '2026-01-01' }, HOJE)).toBe(false);
    expect(ofertaVencida({ vigente: true, validaAte: null }, HOJE)).toBe(false);
  });
  it('valendo exige produto no comercial', () => {
    expect(ofertaValendo({ vigente: true, validaAte: null }, false, HOJE)).toBe(false);
    expect(ofertaValendo({ vigente: true, validaAte: null }, true, HOJE)).toBe(true);
    expect(ofertaValendo({ vigente: true, validaAte: '2026-09-30' }, true, HOJE)).toBe(false);
  });
});

describe('resumos', () => {
  const produtos = [
    prod('1', { noComercial: true, nomeComercial: 'Holding Total', escada: 'B' }),
    prod('2', { noComercial: true, nomeComercial: 'Aurum', escada: 'B', familia: 'AURUM' }),
    prod('3', { conta: 'escritorio', familia: 'ESCRITORIO' }),
  ];
  const ofertas = [
    of('a', '1', { vigente: true, condicao: 'x', transacoes: 10, ultimaVendaEm: '2026-10-01T00:00:00Z' }),
    of('b', '1', { transacoes: 5, ultimaVendaEm: '2026-10-03T00:00:00Z' }),
    of('c', '2', { vigente: true, validaAte: '2026-09-01' }),
    of('d', '3', { vigente: true }),
  ];
  const orfas: OfertaOrfa[] = [
    { codigo: 'z1', produtoId: '1', transacoes: 3, ultimaEm: '2026-10-01T00:00:00Z' },
    { codigo: 'z2', produtoId: null, transacoes: 40, ultimaEm: '2026-08-01T00:00:00Z' },
  ];

  it('resumo do produto: contagens e última venda', () => {
    expect(resumoProduto(produtos[0], ofertas, HOJE)).toEqual({ nOfertas: 2, nVigentes: 1, nVencidas: 0, ultimaVendaEm: '2026-10-03T00:00:00Z', transacoes: 15 });
    expect(resumoProduto(produtos[1], ofertas, HOJE).nVencidas).toBe(1);
    // fora do comercial: vigente não conta
    expect(resumoProduto(produtos[2], ofertas, HOJE).nVigentes).toBe(0);
  });

  it('resumo da tela', () => {
    expect(resumoTela(produtos, ofertas, orfas, HOJE)).toEqual({
      noComercial: 2, foraDoComercial: 1, ofertasVigentes: 1, ofertasVencidas: 1, orfas: 2, transacoesOrfas: 43, semVigente: 1,
    });
  });

  it('filtro por lado, conta, família, busca e sem vigente', () => {
    expect(filtrarProdutos(produtos, ofertas, FILTRO_INICIAL, HOJE).map((p) => p.produtoId)).toEqual(['1', '2']);
    expect(filtrarProdutos(produtos, ofertas, { ...FILTRO_INICIAL, lado: 'fora' }, HOJE).map((p) => p.produtoId)).toEqual(['3']);
    expect(filtrarProdutos(produtos, ofertas, { ...FILTRO_INICIAL, lado: 'fora', conta: 'academy' }, HOJE)).toHaveLength(0);
    expect(filtrarProdutos(produtos, ofertas, { ...FILTRO_INICIAL, familia: 'AURUM' }, HOJE).map((p) => p.produtoId)).toEqual(['2']);
    expect(filtrarProdutos(produtos, ofertas, { ...FILTRO_INICIAL, busca: 'aurúm' }, HOJE).map((p) => p.produtoId)).toEqual(['2']);
    // código de oferta acha o produto
    expect(filtrarProdutos(produtos, ofertas, { ...FILTRO_INICIAL, busca: 'B' }, HOJE).map((p) => p.produtoId)).toContain('1');
    expect(filtrarProdutos(produtos, ofertas, { ...FILTRO_INICIAL, semVigente: true }, HOJE).map((p) => p.produtoId)).toEqual(['2']);
  });

  it('famílias únicas e ordenadas', () => {
    expect(familias(produtos)).toEqual(['AURUM', 'ESCRITORIO', 'HT']);
  });

  it('cola do vendedor: só vinculados, só valendo, com oferta primeiro', () => {
    const cola = colaDoVendedor(produtos, ofertas, HOJE);
    expect(cola.map((c) => c.produto.produtoId)).toEqual(['1', '2']);
    expect(cola[0].vigentes.map((o) => o.codigo)).toEqual(['a']);
    expect(cola[1].vigentes).toHaveLength(0);
  });

  it('órfãs: mais transações primeiro', () => {
    expect(ordenarOrfas(orfas).map((o) => o.codigo)).toEqual(['z2', 'z1']);
  });
});

describe('validações', () => {
  it('vínculo exige nome comercial e escada', () => {
    const base = { produtoId: '1', nomeComercial: '', produtoKey: null, agrupadorId: null, escada: null };
    expect(Object.keys(validarVinculo(base)).sort()).toEqual(['escada', 'nomeComercial']);
    expect(validarVinculo({ ...base, nomeComercial: 'HT', escada: 'B' })).toEqual({});
    expect(validarVinculo({ ...base, nomeComercial: 'x'.repeat(61), escada: 'A' }).nomeComercial).toBeTruthy();
  });

  it('oferta vigente exige produto vinculado, condição e validade futura', () => {
    const r = rascunhoOferta(of('a', '1'));
    expect(validarOferta(r, false, HOJE)).toBeNull();
    const v = { ...r, vigente: true };
    expect(validarOferta(v, false, HOJE)).toMatch(/Vincule/);
    expect(validarOferta(v, true, HOJE)).toMatch(/condição/);
    expect(validarOferta({ ...v, condicao: '12x', validaAte: '2026-10-01' }, true, HOJE)).toMatch(/validade/);
    expect(validarOferta({ ...v, condicao: '12x', validaAte: HOJE }, true, HOJE)).toBeNull();
  });

  it('alterada e conversão para salvar', () => {
    const o = of('a', '1', { condicao: '12x' });
    const r = rascunhoOferta(o);
    expect(ofertaAlterada(r, o)).toBe(false);
    expect(ofertaAlterada({ ...r, uso: 'carrinho' }, o)).toBe(true);
    expect(paraSalvar({ ...r, uso: '  ', validaAte: '' })).toEqual({ codigo: 'a', vigente: false, condicao: '12x', validaAte: null, uso: null });
  });
});
