import { describe, it, expect } from 'vitest';
import { itensRecorte, rotuloRecorte, type RecorteAtivo } from './recorte';

const base = (over: Partial<RecorteAtivo> = {}): RecorteAtivo => ({
  produtoLabel: 'Holding Masters',
  canalLabel: null,
  busca: '',
  ...over,
});

describe('itensRecorte', () => {
  it('sem canal e sem busca: nenhum item removível', () => {
    expect(itensRecorte(base())).toEqual([]);
  });

  it('canal ativo vira item removível', () => {
    expect(itensRecorte(base({ canalLabel: 'Captação T40' }))).toEqual([
      { tipo: 'canal', label: 'Captação T40' },
    ]);
  });

  it('busca ativa vira item removível, aparada', () => {
    expect(itensRecorte(base({ busca: '  maria  ' }))).toEqual([
      { tipo: 'busca', label: 'busca "maria"' },
    ]);
  });

  it('busca só com espaço não vira item (equivalente a vazia)', () => {
    expect(itensRecorte(base({ busca: '   ' }))).toEqual([]);
  });

  it('canal e busca juntos: canal primeiro, busca depois', () => {
    expect(itensRecorte(base({ canalLabel: 'Captação T40', busca: 'maria' }))).toEqual([
      { tipo: 'canal', label: 'Captação T40' },
      { tipo: 'busca', label: 'busca "maria"' },
    ]);
  });

  it('produto NUNCA vira item removível — é aba, não filtro', () => {
    const itens = itensRecorte(base({ canalLabel: 'X', busca: 'y' }));
    expect(itens.some((i) => i.label.includes('Holding Masters'))).toBe(false);
  });
});

describe('rotuloRecorte', () => {
  it('só produto quando não há canal nem busca', () => {
    expect(rotuloRecorte(base())).toBe('Holding Masters');
  });

  it('produto + canal', () => {
    expect(rotuloRecorte(base({ canalLabel: 'Captação T40' }))).toBe('Holding Masters · Captação T40');
  });

  it('produto + canal + busca, na ordem de aplicação dos filtros', () => {
    expect(rotuloRecorte(base({ canalLabel: 'Captação T40', busca: 'maria' }))).toBe(
      'Holding Masters · Captação T40 · busca "maria"',
    );
  });

  it('produto + busca sem canal', () => {
    expect(rotuloRecorte(base({ busca: 'joão' }))).toBe('Holding Masters · busca "joão"');
  });
});

// ── Cor no recorte (2026-08-27, achado do fable-orchestrator) ────────────────
// O filtro de cor (N4) mexe nos 4 totais como qualquer outro filtro. Se ele
// não entrar no recorte, o rodapé afirma "só de Holding Masters — 37 card(s)"
// enquanto HM tem 264, e a BarraRecorte não oferece como remover. Estes
// testes travam as duas pontas.
describe('recorte com filtro de cor', () => {
  const base = { produtoLabel: 'Holding Masters', canalLabel: null, busca: '' };

  it('cor vira chip removível', () => {
    const itens = itensRecorte({ ...base, corLabel: 'Vencido' });
    expect(itens).toEqual([{ tipo: 'cor', label: 'Vencido' }]);
  });

  it('cor entra no rótulo do rodapé — sem isso o total mente', () => {
    expect(rotuloRecorte({ ...base, corLabel: 'Vencido' }))
      .toBe('Holding Masters · Vencido');
  });

  it('ordem do funil: canal → busca → cor', () => {
    const itens = itensRecorte({
      produtoLabel: 'Aurum', canalLabel: 'ETHB SP', busca: 'maria', corLabel: 'Em negociação',
    });
    expect(itens.map((i) => i.tipo)).toEqual(['canal', 'busca', 'cor']);
    expect(rotuloRecorte({
      produtoLabel: 'Aurum', canalLabel: 'ETHB SP', busca: 'maria', corLabel: 'Em negociação',
    })).toBe('Aurum · ETHB SP · busca "maria" · Em negociação');
  });

  it('sem cor, nada muda (compatível com quem não passa o campo)', () => {
    expect(itensRecorte(base)).toEqual([]);
    expect(rotuloRecorte(base)).toBe('Holding Masters');
    expect(rotuloRecorte({ ...base, corLabel: null })).toBe('Holding Masters');
  });

  it('cor sozinha ainda produz chip — a BarraRecorte não pode sumir', () => {
    // Se itensRecorte voltasse vazio, BarraRecorte retorna null e o "limpar
    // tudo" que desfaz a cor deixa de existir na tela.
    expect(itensRecorte({ ...base, corLabel: 'Cancelado ou reembolsado' })).toHaveLength(1);
  });
});
