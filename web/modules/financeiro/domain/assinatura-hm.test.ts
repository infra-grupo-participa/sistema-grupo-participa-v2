import { describe, expect, it } from 'vitest';
import {
  assinaturaDoCard, assinaturaEmDia, indexarAssinaturaHM, linhaAtrasoMensalidade, linhaResumoAssinatura, normalizarAssinaturaSemCard,
  resumoAssinaturaCard, totaisAssinaturaSemCard, type AssinaturaHMBoard, type AssinaturaHMSemCard,
} from './assinatura-hm';
import type { BoardHotmart } from './hotmart';

const ass = (over: Partial<AssinaturaHMBoard> = {}): AssinaturaHMBoard => ({
  pessoa_chave: 'p1', mensalidades_pagas: 12, pago: 23964, primeira: '2025-10-03', ultima_paga: '2026-09-03',
  ainda_paga: true, atraso_120d_n: 0, atraso_120d_valor: 0, turma_origem: 'T29', ...over,
});
const hm = (over: Partial<BoardHotmart> = {}) =>
  ({ contato_hm_id: 'c1', origem: 'HM', encontrado: true, pessoa_chave: 'p1', ...over }) as BoardHotmart;
const semCard = (over: Partial<AssinaturaHMSemCard> = {}): AssinaturaHMSemCard => ({
  pessoa_chave: 'p1', nome: 'Ana', emails: ['a@x.com'], documento: 'CPF ···1234', telefone: '···9999',
  turma_origem: 'T29', origem_regra: 'calendário', turma_calendario: 'T29', turma_cadastro: null,
  primeira: '2024-01-10', ultima_paga: '2026-09-10', mensalidades_pagas: 10, pago: 19970, ainda_paga: true,
  atraso_120d_n: 0, atraso_120d_valor: 0, ...over,
});

describe('indexarAssinaturaHM', () => {
  it('indexa por pessoa_chave e converte numeric que chega como string', () => {
    const m = indexarAssinaturaHM([ass({ pago: '23964.00' as unknown as number, atraso_120d_valor: '1997.5' as unknown as number })]);
    expect(m.get('p1')!.pago).toBe(23964);
    expect(m.get('p1')!.atraso_120d_valor).toBe(1997.5);
  });
  it('linha sem pessoa_chave não entra (nunca junta gente numa chave vazia)', () => {
    expect(indexarAssinaturaHM([ass({ pessoa_chave: '' })]).size).toBe(0);
  });
});

describe('assinaturaDoCard', () => {
  const m = indexarAssinaturaHM([ass()]);
  it('card HM acha pela pessoa_chave do board', () => {
    expect(assinaturaDoCard(hm(), m)?.turma_origem).toBe('T29');
  });
  it('card Aurum, pessoa não encontrada, sem chave ou mapa ausente → null', () => {
    expect(assinaturaDoCard(hm({ origem: 'AURUM' }), m)).toBeNull();
    expect(assinaturaDoCard(hm({ encontrado: false }), m)).toBeNull();
    expect(assinaturaDoCard(hm({ pessoa_chave: null }), m)).toBeNull();
    expect(assinaturaDoCard(hm(), null)).toBeNull();
    expect(assinaturaDoCard(null, m)).toBeNull();
  });
});

describe('assinaturaEmDia', () => {
  it('ainda paga e sem atraso em 120 d', () => {
    expect(assinaturaEmDia(ass())).toBe(true);
    expect(assinaturaEmDia(ass({ atraso_120d_n: 1 }))).toBe(false);
    expect(assinaturaEmDia(ass({ ainda_paga: false }))).toBe(false);
  });
});

describe('resumoAssinaturaCard', () => {
  const doBoard = hm({ assinatura_mensalidades: 12, assinatura_valor: 23964, assinatura_de: '2025-10-03', assinatura_ate: '2026-09-03', assinatura_ativa: true });
  it('quantidade e valor continuam os do board; situação e atraso vêm da z52', () => {
    const r = resumoAssinaturaCard(hm({ ...doBoard, assinatura_mensalidades: 11, assinatura_ativa: true }),
      ass({ mensalidades_pagas: 12, atraso_120d_n: 2, atraso_120d_valor: 3994 }))!;
    expect(r.mensalidades).toBe(11);
    expect(r.situacao).toBe('em_atraso');
    expect(r.atrasoN).toBe(2);
    expect(r.turmaOrigem).toBe('T29');
  });
  it('depois da seção 4: board diz ativa mas quem decide é ainda_paga && atraso = 0', () => {
    expect(resumoAssinaturaCard(doBoard, ass({ ainda_paga: false }))!.situacao).toBe('encerrada');
    expect(resumoAssinaturaCard(hm({ ...doBoard, assinatura_ativa: false }), ass())!.situacao).toBe('ativa');
  });
  it('sem a z52 (carregando/erro): cai no assinatura_ativa do board e não mostra atraso', () => {
    const r = resumoAssinaturaCard(doBoard, null)!;
    expect(r.situacao).toBe('ativa');
    expect(r.atrasoN).toBe(0);
    expect(linhaAtrasoMensalidade(r, String)).toBeNull();
  });
  it('só atraso, nenhuma paga no board: aparece (senão o atraso some do card depois da seção 4)', () => {
    const r = resumoAssinaturaCard(hm(), ass({ mensalidades_pagas: 0, pago: 0, ainda_paga: false, atraso_120d_n: 1, atraso_120d_valor: 1997 }))!;
    expect(r).not.toBeNull();
    expect(r.situacao).toBe('em_atraso');
    expect(linhaAtrasoMensalidade(r, (n) => `R$ ${n}`)).toBe('mensalidade em atraso: 1 · R$ 1997');
  });
  it('nada pago e nada em atraso → null (bloco não aparece)', () => {
    expect(resumoAssinaturaCard(hm(), null)).toBeNull();
    expect(resumoAssinaturaCard(hm(), ass({ mensalidades_pagas: 0, atraso_120d_n: 0 }))).toBeNull();
    expect(resumoAssinaturaCard(hm({ encontrado: false, assinatura_mensalidades: 3 }), null)).toBeNull();
  });
});

describe('linhaResumoAssinatura', () => {
  it('mesma linha que o card já mostrava; só atraso vira "nenhuma paga"', () => {
    const fmt = (n: number) => `R$ ${n}`;
    const doBoard = hm({ assinatura_mensalidades: 12, assinatura_valor: 23964, assinatura_ate: '2026-09-03', assinatura_ativa: true });
    expect(linhaResumoAssinatura(resumoAssinaturaCard(doBoard, null)!, fmt)).toBe('Assinatura HM: 12 × · R$ 23964 · até 09/2026');
    expect(linhaResumoAssinatura(resumoAssinaturaCard(hm(), ass({ mensalidades_pagas: 0, atraso_120d_n: 1 }))!, fmt)).toBe('Assinatura HM: nenhuma paga');
  });
});

describe('totaisAssinaturaSemCard', () => {
  it('pessoas, pago, ainda pagam e atraso', () => {
    const t = totaisAssinaturaSemCard([
      semCard(),
      semCard({ pessoa_chave: 'p2', pago: '1000.5' as unknown as number, ainda_paga: false, atraso_120d_n: 2, atraso_120d_valor: 3994 }),
    ]);
    expect(t).toEqual({ pessoas: 2, pago: 20970.5, aindaPagam: 1, comAtraso: 1, atrasoValor: 3994 });
  });
  it('normaliza emails nulos e numeric em string', () => {
    const n = normalizarAssinaturaSemCard(semCard({ emails: null as unknown as string[], mensalidades_pagas: '3' as unknown as number }));
    expect(n.emails).toEqual([]);
    expect(n.mensalidades_pagas).toBe(3);
  });
});
