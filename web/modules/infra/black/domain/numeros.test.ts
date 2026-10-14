import { describe, expect, it } from 'vitest';
import { baseFicticia } from '../infrastructure/fixtures/gerador';
import { cplCaptacao, leadsDoTrafego, leadsPessoas, mql, taxaMql } from './numeros';
import { indexar } from './metricas';

describe('números canônicos da Black', () => {
  it('conta pessoas, pagos atribuídos e % de MQL sem duplicar cadastros', () => {
    const fixture = baseFicticia();
    const idx = indexar(fixture);
    const pessoas = leadsPessoas(fixture.linhas);
    const pagos = leadsDoTrafego(fixture.linhas, idx);
    const resultadoMql = mql(fixture.linhas);
    const percentual = taxaMql(fixture.linhas);

    expect(pessoas.valor).toBe(new Set(fixture.linhas.map((linha) => linha.pessoaId)).size);
    expect(pagos.valor).toBeLessThanOrEqual(pessoas.valor!);
    expect(percentual.num).toBe(resultadoMql.num);
    expect(percentual.den).toBe(pessoas.valor);
    expect(percentual.valor).toBeCloseTo((resultadoMql.num as number) / (pessoas.valor as number));
    expect(pagos.recorte).toContain('pessoas únicas');
  });

  it('CPL compartilha numerador e denominador e deixa ausência de lead como sem dado', () => {
    const comLeads = cplCaptacao(709.83, { valor: 29, num: 29, den: null, recorte: '29 pessoas únicas', nota: null });
    const semLeads = cplCaptacao(709.83, { valor: 0, num: 0, den: null, recorte: 'nenhuma pessoa única', nota: null });
    expect(comLeads).toMatchObject({ valor: 709.83 / 29, num: 709.83, den: 29 });
    expect(semLeads.valor).toBeNull();
  });

  it('classifica MQL pelo envio mais recente que tem profissão e mantém as pessoas sem profissão na base', () => {
    const original = baseFicticia().linhas[0];
    const linhas = [
      { ...original, pessoaId: 'a', criadoEm: '2026-10-12T10:00:00-03:00', profissao: 'advogado' as const },
      { ...original, pessoaId: 'a', criadoEm: '2026-10-12T11:00:00-03:00', profissao: null },
      { ...original, pessoaId: 'b', criadoEm: '2026-10-12T10:30:00-03:00', profissao: 'outros' as const },
    ];
    expect(mql(linhas)).toMatchObject({ num: 1, den: 2, valor: 0.5 });
  });
});
