import { describe, expect, it } from 'vitest';
import {
  agruparPremissas, anosDosFeriados, formatarFaixa, formatarPremissa, lerNumeroDigitado, normalizarFeriado,
  normalizarVigencia, paraBanco, paraExibicao, validarFeriado, validarPremissa,
} from './premissas-receber';

const V = (p: Record<string, unknown>) => normalizarVigencia({
  chave: 'perda_mensal:parcelas_hm', chave_base: 'perda_mensal:parcelas_hm', cenario: 'base',
  rotulo: 'Perda mensal — Parcelas a vencer HM', unidade: 'percentual', minimo: 0, maximo: 0.5,
  grupo_tela: 'Perda por inadimplência', ajuda: 'Esperado = valor × (1 − perda)^k', aceita_cenario: true,
  vigente_de: '2000-01-01', valor: 0.05, fonte: 'planilha', criado_em: null, criado_por_nome: null, situacao: 'vigente', ...p,
});

describe('agruparPremissas', () => {
  const lista = [
    V({}),
    V({ vigente_de: '2026-11-01', valor: 0.07, situacao: 'futura', criado_por_nome: 'Fernanda' }),
    V({ chave: 'perda_mensal:parcelas_hm@conservador', cenario: 'conservador', vigente_de: '2026-09-28', valor: 0.1 }),
    V({ chave: 'tolerancia_atraso_dias', chave_base: 'tolerancia_atraso_dias', rotulo: 'Tolerância de atraso', unidade: 'dias',
      minimo: 0, maximo: 30, grupo_tela: 'Recorrências e informados', aceita_cenario: false, valor: 5 }),
  ];
  const g = agruparPremissas(lista);
  it('um grupo por grupo_tela, na ordem do banco', () => {
    expect(g.map((x) => x.grupo)).toEqual(['Perda por inadimplência', 'Recorrências e informados']);
  });
  it('premissa com cenário: 3 linhas; cenário sem linha própria usa a base', () => {
    const p = g[0].premissas[0];
    expect(p.cenarios.map((c) => c.cenario)).toEqual(['base', 'conservador', 'otimista']);
    expect(p.cenarios[0].vigente?.valor).toBe(0.05);
    expect(p.cenarios[0].futuras.map((f) => f.valor)).toEqual([0.07]);
    expect(p.cenarios[1].vigente?.valor).toBe(0.1);
    expect(p.cenarios[1].usaBase).toBe(false);
    expect(p.cenarios[2].vigente).toBeNull();
    expect(p.cenarios[2].usaBase).toBe(true);
  });
  it('premissa sem cenário: só a base', () => {
    expect(g[1].premissas[0].cenarios.map((c) => c.cenario)).toEqual(['base']);
  });
});

describe('unidade: percentual é fração no banco e % na tela', () => {
  it('ida e volta sem resíduo de ponto flutuante', () => {
    expect(paraExibicao(0.05, 'percentual')).toBe(5);
    expect(paraExibicao(0.07, 'percentual')).toBe(7);
    expect(paraBanco(7, 'percentual')).toBe(0.07);
    expect(paraBanco(5.5, 'percentual')).toBe(0.055);
    expect(paraBanco(30, 'dias')).toBe(30);
  });
  it('formatação', () => {
    expect(formatarPremissa(0.05, 'percentual')).toBe('5%');
    expect(formatarPremissa(0.055, 'percentual')).toBe('5,5%');
    expect(formatarPremissa(30, 'dias')).toBe('30 dias');
    expect(formatarPremissa(1, 'liga_desliga')).toBe('Ligado');
    expect(formatarPremissa(0, 'liga_desliga')).toBe('Desligado');
    expect(formatarFaixa({ minimo: 0, maximo: 0.5, unidade: 'percentual' })).toBe('0% a 50%');
  });
  it('número digitado em pt-BR', () => {
    expect(lerNumeroDigitado('5,5')).toBe(5.5);
    expect(lerNumeroDigitado('5.5')).toBe(5.5);
    expect(lerNumeroDigitado('7%')).toBe(7);
    expect(lerNumeroDigitado('abc')).toBeNull();
    expect(lerNumeroDigitado('')).toBeNull();
  });
});

describe('validarPremissa — mesmas regras da RPC', () => {
  const pct = { minimo: 0, maximo: 0.5, unidade: 'percentual' as const, rotulo: 'Perda' };
  const dias = { minimo: 0, maximo: 30, unidade: 'dias' as const, rotulo: 'Tolerância' };
  const hoje = '2026-09-28';
  it('percentual dentro da faixa: devolve a fração', () => {
    expect(validarPremissa(pct, '7', hoje, hoje)).toEqual({ ok: true, valor: 0.07 });
    expect(validarPremissa(pct, '50', hoje, hoje)).toEqual({ ok: true, valor: 0.5 });
  });
  it('fora da faixa, na unidade da tela', () => {
    expect(validarPremissa(pct, '51', hoje, hoje)).toEqual({ ok: false, erros: ['Fora da faixa: 0% a 50%.'] });
    expect(validarPremissa(pct, '-1', hoje, hoje).ok).toBe(false);
  });
  it('dias: só inteiro', () => {
    expect(validarPremissa(dias, '5,5', hoje, hoje)).toEqual({ ok: false, erros: ['Só número inteiro.'] });
    expect(validarPremissa(dias, '5', hoje, hoje)).toEqual({ ok: true, valor: 5 });
  });
  it('vigência: de hoje a hoje + 366', () => {
    expect(validarPremissa(dias, '5', '2026-09-27', hoje).ok).toBe(false);
    expect(validarPremissa(dias, '5', '2027-09-29', hoje).ok).toBe(true); // 2026-09-28 + 366 = 2027-09-29
    expect(validarPremissa(dias, '5', '2027-09-30', hoje).ok).toBe(false);
    expect(validarPremissa(dias, '5', '', hoje).ok).toBe(false);
  });
  it('não número', () => {
    expect(validarPremissa(dias, 'x', hoje, hoje)).toEqual({ ok: false, erros: ['Informe um número.'] });
  });
});

describe('feriados', () => {
  it('normaliza e lista anos', () => {
    const fs = [normalizarFeriado({ dia: '2026-12-25', nome: 'Natal', ativo: true }), normalizarFeriado({ dia: '2027-01-01', nome: 'Ano novo', ativo: 'false' })];
    expect(fs[1].ativo).toBe(false);
    expect(anosDosFeriados(fs)).toEqual([2026, 2027]);
  });
  it('validação igual à fn_fin_feriado_salvar (2015–2036, nome até 120)', () => {
    expect(validarFeriado('2026-11-20', 'Consciência Negra')).toEqual([]);
    expect(validarFeriado('2037-01-01', 'X')).toHaveLength(1);
    expect(validarFeriado('2026-11-20', '  ')).toHaveLength(1);
    expect(validarFeriado('', '')).toHaveLength(2);
  });
});
