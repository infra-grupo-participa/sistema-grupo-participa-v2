import { describe, expect, it } from 'vitest';
import { baseFicticia } from '../infrastructure/fixtures/gerador';
import { cplCaptacao, ingressoGrupoGeral, leadsDoTrafego, leadsPessoas, mql, taxaMql } from './numeros';
import { indexar } from './metricas';
import { grupoSemDado } from './grupo';

describe('números canônicos da Black', () => {
  it('usa ingresso_geral do banco sem cruzar membros com leads e mantém cruzados os recortes', () => {
    const linhas = baseFicticia().linhas.slice(0, 2);
    const base = grupoSemDado();
    const geral = ingressoGrupoGeral(linhas, { ...base, ingressoGeral: { numerosUnicosNoGrupo: 169, leadsUnicos: 259, pct: 65.3 } });
    expect(geral).toMatchObject({ valor: 0.653, num: 169, den: 259, recorte: 'números únicos que entraram no grupo ÷ leads únicos' });

    const recortado = ingressoGrupoGeral(linhas, {
      ...base, recorte: { tipo: 'porta', valor: 'isca' },
      ingressoGeral: { numerosUnicosNoGrupo: 169, leadsUnicos: 259, pct: 65.3 },
    });
    expect(recortado.valor).not.toBe(0.653);
    expect(recortado.recorte).toContain('pessoas únicas que entraram em grupo');

    const semCampo = ingressoGrupoGeral(linhas, { ...base, ingressoGeral: undefined });
    expect(semCampo.valor).toBe(ingressoGrupoGeral(linhas).valor);
    expect(ingressoGrupoGeral(linhas, { ...base, ingressoGeral: null }).valor).toBeNull();
  });

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
