import { describe, expect, it } from 'vitest';
import { agruparPorLancamento } from '../../domain/jornada';
import type { PontoJornada } from '../../domain/types';
import {
  alternadosPara, blocoAberto, chaveBloco, filtrarBlocos, indiceContatos, ordenarNegocios, paresUtm, resumoFicha,
  tiposPresentes,
} from './ficha-contato';

const p = (tipo: PontoJornada['tipo'], em: string, extra: Partial<PontoJornada> = {}): PontoJornada => ({
  id: `${tipo}-${em}`, contatoId: 'c1', tipo, em, titulo: tipo, detalhe: null, fonte: 'crm', lancamento: 'ht30',
  produto: 'ht', utm: null, valor: null, negocioId: null, ...extra,
});

const pontos: PontoJornada[] = [
  p('inscricao', '2026-03-01T10:00:00Z', { utm: { source: 'metaads', medium: 'cpc', campaign: 'ht30', content: 'ad01' } }),
  p('compra', '2026-03-05T10:00:00Z', { valor: 297 }),
  p('inscricao', '2026-09-01T10:00:00Z', { lancamento: 'ht33', utm: { source: 'infobip' } }),
  p('compra', '2026-09-03T10:00:00Z', { lancamento: 'ht33', valor: 30000 }),
  p('reembolso', '2026-09-05T10:00:00Z', { lancamento: 'ht33', valor: 30000 }),
  p('conversa', '2026-09-06T10:00:00Z', { lancamento: null }),
];

describe('resumoFicha', () => {
  it('cliente desde a primeira compra, com pago líquido e negócios abertos', () => {
    const r = resumoFicha(pontos, [{ status: 'aberto' }, { status: 'perdido' }], { criadoEm: '2026-01-01T00:00:00Z', ehAluno: false });
    expect(r).toMatchObject({
      cliente: true, desde: '2026-03-05T10:00:00Z', lancamentos: 2, compras: 2, reembolsos: 1, valorPago: 297,
      negociosAbertos: 1, negociosTotal: 2,
    });
  });

  it('lead desde o primeiro contato (cadastro ou jornada, o que vier antes)', () => {
    const r = resumoFicha([pontos[0]], [], { criadoEm: '2026-04-01T00:00:00Z', ehAluno: false });
    expect(r.cliente).toBe(false);
    expect(r.desde).toBe('2026-03-01T10:00:00Z');
    expect(resumoFicha([], [], { criadoEm: '2026-04-01T00:00:00Z', ehAluno: true })).toMatchObject({ cliente: true, desde: '2026-04-01T00:00:00Z' });
  });
});

describe('tiposPresentes', () => {
  it('conta por tipo na ordem do catálogo', () => {
    expect(tiposPresentes(pontos)).toEqual([
      { tipo: 'inscricao', n: 2 }, { tipo: 'compra', n: 2 }, { tipo: 'reembolso', n: 1 }, { tipo: 'conversa', n: 1 },
    ]);
  });
});

describe('filtrarBlocos', () => {
  const blocos = agruparPorLancamento(pontos);
  it('sem filtro devolve tudo', () => {
    expect(filtrarBlocos(blocos, [])).toBe(blocos);
  });
  it('mantém só os pontos escolhidos e tira bloco vazio, sem mudar o resumo do lançamento', () => {
    const f = filtrarBlocos(blocos, ['reembolso']);
    expect(f.map(chaveBloco)).toEqual(['ht33']);
    expect(f[0].pontos.map((x) => x.tipo)).toEqual(['reembolso']);
    expect(f[0].comprou).toBe(true);
  });
  it('bloco sem lançamento tem chave própria', () => {
    expect(blocos.map(chaveBloco)).toContain('__sem_lancamento');
  });
});

describe('blocos abertos', () => {
  it('três primeiros abertos por padrão; alternar inverte', () => {
    const vazio = new Set<string>();
    expect(blocoAberto(0, 'a', vazio)).toBe(true);
    expect(blocoAberto(3, 'd', vazio)).toBe(false);
    expect(blocoAberto(0, 'a', new Set(['a']))).toBe(false);
    expect(blocoAberto(3, 'd', new Set(['d']))).toBe(true);
  });
  it('expandir/recolher tudo', () => {
    const chaves = ['a', 'b', 'c', 'd', 'e'];
    const abrir = alternadosPara(true, chaves);
    expect(chaves.every((k, i) => blocoAberto(i, k, abrir))).toBe(true);
    const fechar = alternadosPara(false, chaves);
    expect(chaves.some((k, i) => blocoAberto(i, k, fechar))).toBe(false);
  });
});

describe('paresUtm', () => {
  it('só os preenchidos', () => {
    expect(paresUtm({ source: 'metaads', medium: ' ', campaign: 'ht30', content: null })).toEqual([
      { k: 'source', v: 'metaads' }, { k: 'campaign', v: 'ht30' },
    ]);
    expect(paresUtm(null)).toEqual([]);
  });
});

describe('ordenarNegocios', () => {
  it('abertos primeiro, depois o mais recente', () => {
    const r = ordenarNegocios([
      { id: 'a', status: 'perdido', criadoEm: '2026-01-01', fechadoEm: '2026-09-01' },
      { id: 'b', status: 'aberto', criadoEm: '2026-02-01', fechadoEm: null },
      { id: 'c', status: 'ganho', criadoEm: '2026-03-01', fechadoEm: '2026-03-10' },
      { id: 'd', status: 'aberto', criadoEm: '2026-05-01', fechadoEm: null },
    ]);
    expect(r.map((n) => n.id)).toEqual(['d', 'b', 'a', 'c']);
  });
});

describe('indiceContatos', () => {
  it('conta lançamentos distintos e pega a interação mais recente entre jornada e negócios', () => {
    const m = indiceContatos(
      new Map([['c1', pontos], ['c2', []]]),
      [
        { contatoId: 'c1', ultimaInteracaoEm: '2026-01-01T00:00:00Z' },
        { contatoId: 'c2', ultimaInteracaoEm: '2026-10-01T00:00:00Z' },
        { contatoId: 'c3', ultimaInteracaoEm: null },
      ],
    );
    expect(m.get('c1')).toEqual({ lancamentos: 2, ultimaEm: '2026-09-06T10:00:00Z' });
    expect(m.get('c2')).toEqual({ lancamentos: 0, ultimaEm: '2026-10-01T00:00:00Z' });
    expect(m.get('c3')).toEqual({ lancamentos: 0, ultimaEm: null });
  });
});
