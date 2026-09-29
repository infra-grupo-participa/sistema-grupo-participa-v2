import { describe, it, expect } from 'vitest';
import { entradaRetorno, fmtDiaMes } from './entrada-retorno';

describe('entradaRetorno', () => {
  it('HT30 → voltou na HT32: duas linhas, data dd/mm em São Paulo', () => {
    const r = entradaRetorno({
      acao_nome: 'Holding Total HT30 (09–10/08/2026)',
      voltou_nome: 'Imersão Holding Total HT32 (26–27/09/2026)',
      voltou_data: '2026-09-27T01:30:00+00:00', // 26/09 22:30 em São Paulo
    });
    expect(r.entrou).toBe('Entrou por Holding Total HT30 (09–10/08/2026)');
    expect(r.voltou).toBe('Voltou em Imersão Holding Total HT32 (26–27/09/2026) · 26/09');
  });
  it('sem voltou → só a entrada; tira o prefixo de turma', () => {
    const r = entradaRetorno({ acao_nome: 'T39 · Holding Total ATM (06/07/2026)', voltou_nome: null });
    expect(r.entrou).toBe('Entrou por Holding Total ATM (06/07/2026)');
    expect(r.voltou).toBeNull();
  });
  it('sem ação de entrada → null (nunca "Entrou por —")', () => {
    expect(entradaRetorno({}).entrou).toBeNull();
  });
  it('voltou sem data válida → linha sem data', () => {
    expect(entradaRetorno({ voltou_nome: 'X', voltou_data: 'lixo' }).voltou).toBe('Voltou em X');
  });
  it('fmtDiaMes aceita date puro', () => {
    expect(fmtDiaMes('2026-09-26')).toBe('26/09');
    expect(fmtDiaMes(null)).toBeNull();
  });
});
