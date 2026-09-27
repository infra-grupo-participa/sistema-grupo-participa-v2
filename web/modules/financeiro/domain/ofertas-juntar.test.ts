import { describe, it, expect } from 'vitest';
import { juntarOfertas } from './ofertas-juntar';
import type { Oferta } from './types';
import type { OfertaHotmart } from './hotmart';

function oferta(over: Partial<Oferta> = {}): Oferta {
  return { codigo: 'ABC1', valor: 300, recorrente: false, link: 'https://x', ativo: true, usos: 5, ...over };
}

function venda(over: Partial<OfertaHotmart> = {}): OfertaHotmart {
  return {
    oferta_codigo: 'ABC1', produto: 'Holding Masters', papel_produto: 'principal', modo_pagamento: 'unico',
    preco_oferta: 300, vendas_pagas: 2, estornos: 0, recusadas: 0, receita_oferta: 600, receita_liquida: 575,
    primeira_venda: '2026-01-01', ultima_venda: '2026-01-10', categoria_catalogo: 'sinal', papel_catalogo: 'principal',
    nome_comercial: 'Sinal HM', no_catalogo: true, ativa: true, ...over,
  };
}

describe('juntarOfertas', () => {
  it('código só na configuração: temConfig true, temVenda false, números de venda zerados', () => {
    const [linha] = juntarOfertas([oferta({ codigo: 'SOCONFIG' })], []);
    expect(linha.codigo).toBe('SOCONFIG');
    expect(linha.temConfig).toBe(true);
    expect(linha.temVenda).toBe(false);
    expect(linha.vendasPagas).toBe(0);
    expect(linha.receitaBruta).toBe(0);
    expect(linha.valorConfig).toBe(300);
  });

  it('código só em vendas: temVenda true, temConfig false, campos de config nulos', () => {
    const [linha] = juntarOfertas([], [venda({ oferta_codigo: 'SOVENDA' })]);
    expect(linha.codigo).toBe('SOVENDA');
    expect(linha.temVenda).toBe(true);
    expect(linha.temConfig).toBe(false);
    expect(linha.valorConfig).toBeNull();
    expect(linha.papel).toBeNull();
    expect(linha.vendasPagas).toBe(2);
    expect(linha.receitaBruta).toBe(600);
  });

  it('código nos dois: uma linha só, com dados de configuração e de venda', () => {
    const linhas = juntarOfertas([oferta({ codigo: 'NOSDOIS', papel: 'saldo' })], [venda({ oferta_codigo: 'NOSDOIS' })]);
    expect(linhas).toHaveLength(1);
    const [linha] = linhas;
    expect(linha.temConfig).toBe(true);
    expect(linha.temVenda).toBe(true);
    expect(linha.papel).toBe('saldo');
    expect(linha.vendasPagas).toBe(2);
    expect(linha.categoriaCatalogo).toBe('sinal');
  });

  it('mesmo código duplicado com espaço e maiúscula (config e vendas) cai numa única linha, somando as vendas', () => {
    const linhas = juntarOfertas(
      [oferta({ codigo: ' Dup123 ' }), oferta({ codigo: 'dup123', papel: 'atualizado' })],
      [venda({ oferta_codigo: 'DUP123 ' }), venda({ oferta_codigo: ' dup123' })],
    );
    expect(linhas).toHaveLength(1);
    const [linha] = linhas;
    expect(linha.temConfig).toBe(true);
    expect(linha.temVenda).toBe(true);
    // Configuração duplicada: a última entrada prevalece.
    expect(linha.papel).toBe('atualizado');
    // Vendas duplicadas: soma, não perde dado em silêncio.
    expect(linha.vendasPagas).toBe(4);
    expect(linha.receitaBruta).toBe(1200);
  });

  it('cada código aparece uma única vez mesmo com várias entradas', () => {
    const linhas = juntarOfertas(
      [oferta({ codigo: 'A' }), oferta({ codigo: 'B' })],
      [venda({ oferta_codigo: 'A' }), venda({ oferta_codigo: 'C' })],
    );
    const codigos = linhas.map((l) => l.codigo.toLowerCase()).sort();
    expect(codigos).toEqual(['a', 'b', 'c']);
  });
});
