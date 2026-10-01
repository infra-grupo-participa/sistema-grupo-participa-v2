import { describe, expect, it } from 'vitest';
import { normalizarLinhas, ordenarTrajetoria, resumirTrajetoriaAluno, type LinhaTrajetoriaAluno } from './trajetoria-aluno';

const l = (x: Partial<LinhaTrajetoriaAluno>): LinhaTrajetoriaAluno => ({
  dia: '2024-01-01', momento: null, dimensao: 'vinculo', tipo: 'x', titulo: 't', detalhe: null,
  valor: null, situacao: null, fonte: 'f', regra: null, ref: null, ...x,
});

describe('ordenarTrajetoria', () => {
  it('mais recente primeiro; no mesmo dia, momento desc e sem momento por último; empate mantém ordem', () => {
    const r = ordenarTrajetoria([
      l({ dia: '2023-05-01', titulo: 'a' }),
      l({ dia: '2025-02-10', momento: null, titulo: 'b' }),
      l({ dia: '2025-02-10', momento: '2025-02-10T09:00:00', titulo: 'c' }),
      l({ dia: '2025-02-10', momento: '2025-02-10T18:00:00', titulo: 'd' }),
      l({ dia: '2023-05-01', titulo: 'e' }),
    ]);
    expect(r.map((x) => x.titulo)).toEqual(['d', 'c', 'b', 'a', 'e']);
  });
});

describe('resumirTrajetoriaAluno', () => {
  it('entrada = 1º entrada_thb; compras sem estorno/cancelamento; saídas, voltas e eventos', () => {
    const r = resumirTrajetoriaAluno([
      l({ dia: '2019-03-01', dimensao: 'compras', tipo: 'compra' }),
      l({ dia: '2020-06-01', tipo: 'entrada_thb' }),
      l({ dia: '2022-06-01', tipo: 'entrada_thb' }),
      l({ dia: '2021-01-01', dimensao: 'compras', tipo: 'estorno' }),
      l({ dia: '2021-02-01', dimensao: 'compras', tipo: 'cancelamento' }),
      l({ dia: '2021-03-01', tipo: 'saida' }),
      l({ dia: '2022-03-01', tipo: 'volta' }),
      l({ dia: '2022-04-01', dimensao: 'eventos', tipo: 'participou' }),
      l({ dia: '2022-05-01', dimensao: 'eventos', tipo: 'participou' }),
    ]);
    expect(r).toEqual({ entradaThb: '2020-06-01', entradaInferida: false, compras: 1, saidas: 1, voltas: 1, eventos: 2 });
  });
  it('sem entrada_thb, usa a linha mais antiga e marca como inferida', () => {
    const r = resumirTrajetoriaAluno([l({ dia: '2024-01-01' }), l({ dia: '2021-07-15' })]);
    expect(r.entradaThb).toBe('2021-07-15');
    expect(r.entradaInferida).toBe(true);
  });
  it('vazio', () => {
    expect(resumirTrajetoriaAluno([])).toEqual({ entradaThb: null, entradaInferida: false, compras: 0, saidas: 0, voltas: 0, eventos: 0 });
  });
});

describe('normalizarLinhas', () => {
  it('valor string vira número; null continua null; dia corta para YYYY-MM-DD', () => {
    const [a, b] = normalizarLinhas([
      { ...l({}), valor: '1234.5', dia: '2024-01-02T00:00:00' },
      { ...l({}), valor: null },
    ]);
    expect(a.valor).toBe(1234.5);
    expect(a.dia).toBe('2024-01-02');
    expect(b.valor).toBeNull();
  });
});
