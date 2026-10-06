// Resumo do dia: os mesmos números do ensaio da 20261005r (passo 2), com ontem = 2026-10-04 (O).
import { describe, expect, it } from 'vitest';
import { calcularAlertas, textoAlerta as texto, textoRegra, type ProjetoEntrada } from './alertas';
import type { Regra } from './tipos';

const O = '2026-10-04';
const d = (n: number) => {
  const x = new Date(`${O}T12:00:00Z`);
  x.setUTCDate(x.getUTCDate() + n);
  return x.toISOString().slice(0, 10);
};

// Os limiares propostos da 20261005r (tabela mkt_trafego.alerta_regras).
const REGRAS: Regra[] = [
  { codigo: 'acima_verba_diaria', nome: 'Acima da verba diária', ligada: true, limiar: 0, unidade: 'pct', gravidade: 'alta', descricao: '' },
  { codigo: 'cpl_acima_meta', nome: 'CPL acima da meta', ligada: true, limiar: 0, unidade: 'pct', gravidade: 'alta', descricao: '' },
  { codigo: 'leads_abaixo_meta', nome: 'Abaixo da meta de leads para a data', ligada: true, limiar: 20, unidade: 'pct', gravidade: 'alta', descricao: '' },
  { codigo: 'ritmo_fase', nome: 'Ritmo da fase fora do planejado', ligada: true, limiar: 20, unidade: 'pct', gravidade: 'media', descricao: '' },
  { codigo: 'verba_perto_fim', nome: '% da verba perto do fim', ligada: true, limiar: 90, unidade: 'pct', gravidade: 'media', descricao: '' },
  { codigo: 'fora_padrao', nome: 'Campanhas fora do padrão', ligada: true, limiar: 7, unidade: 'dias', gravidade: 'media', descricao: '' },
  { codigo: 'sem_fase', nome: 'Campanhas sem fase', ligada: true, limiar: 7, unidade: 'dias', gravidade: 'media', descricao: '' },
];

// ZZ28 do ensaio: investido 1310 de 1400, ontem 330 de 250, 30 leads (meta 100), CPL 43,67 (meta 10).
const ZZ28: ProjetoEntrada = {
  linha: { projeto_id: 1, sigla: 'ZZ28', nome: 'Projeto Ensaio Fase 2', investido: 1310, verba_maxima: 1400, verba_diaria: 250,
    gasto_ontem: 330, ritmo_ontem: 132, pct_verba: 93.6, leads: 30, meta_leads: 100, cpl: 43.67, meta_cpl: 10, inicio: d(-9), fim: d(20) },
  entra: true,
  fases: [
    { fase: 'captacao', nome: 'Captação', verba: 2000, inicio: d(-9), fim: d(10), gastoAteOntem: 1210 },
    { fase: 'aquecimento', nome: 'Aquecimento', verba: 500, inicio: d(-5), fim: d(4), gastoAteOntem: 0 },
    { fase: 'lembrete', nome: 'Lembrete', verba: 300, inicio: d(11), fim: d(15), gastoAteOntem: 0 },
  ],
  campanhas: [
    { fora_padrao: false, fase: 'captacao', ultimoGasto: O },
    { fora_padrao: false, fase: null, ultimoGasto: O },
    { fora_padrao: true, fase: null, ultimoGasto: d(-1) },
    { fora_padrao: true, fase: null, ultimoGasto: d(-20) },
  ],
};
const ZY28: ProjetoEntrada = {
  linha: { ...ZZ28.linha, projeto_id: 2, sigla: 'ZY28', gasto_ontem: 999, verba_diaria: 100 }, entra: false, fases: [], campanhas: [],
};

describe('resumo do dia (mesmas regras do banco)', () => {
  const a = calcularAlertas(O, REGRAS, [ZZ28, ZY28], [{ fora_padrao: true, fase: null, ultimoGasto: O }]);
  const de = (regra: string, direcao?: string) => a.find((x) => x.regra === regra && x.sigla === 'ZZ28' && (!direcao || x.detalhe.direcao === direcao))!;

  it('dispara as mesmas regras do ensaio, alta primeiro; projeto que não entra fica fora', () => {
    expect(a.filter((x) => x.sigla === 'ZZ28').map((x) => x.regra + (x.detalhe.direcao ? `:${x.detalhe.direcao}` : '')).sort()).toEqual([
      'acima_verba_diaria', 'cpl_acima_meta', 'fora_padrao', 'leads_abaixo_meta', 'ritmo_fase:abaixo', 'ritmo_fase:acima', 'sem_fase', 'verba_perto_fim',
    ]);
    expect(a.some((x) => x.sigla === 'ZY28')).toBe(false);
    expect(a.slice(0, 3).every((x) => x.gravidade === 'alta')).toBe(true);
    expect(a.find((x) => x.sigla === null)!.valor).toBe(1);
  });

  it('números: diária 330/250, captação 1210/1000, aquecimento 0/300, leads 30/50, CPL 43,67/10, 1 fora do padrão, 2 sem fase', () => {
    expect([de('acima_verba_diaria').valor, de('acima_verba_diaria').referencia]).toEqual([330, 250]);
    expect([de('ritmo_fase', 'acima').valor, de('ritmo_fase', 'acima').referencia, de('ritmo_fase', 'acima').detalhe.pct]).toEqual([1210, 1000, 121]);
    expect([de('ritmo_fase', 'abaixo').valor, de('ritmo_fase', 'abaixo').referencia]).toEqual([0, 300]);
    expect([de('leads_abaixo_meta').valor, de('leads_abaixo_meta').referencia, de('leads_abaixo_meta').detalhe.periodo]).toEqual([30, 50, 'captacao']);
    expect([de('cpl_acima_meta').valor, de('cpl_acima_meta').detalhe.pct]).toEqual([43.67, 436.7]);
    expect([de('fora_padrao').valor, de('sem_fase').valor, de('verba_perto_fim').valor]).toEqual([1, 2, 93.6]);
  });

  it('limiar vem da configuração: ritmo 50% deixa só o aquecimento; regra desligada some; captação no limite exato não dispara', () => {
    const r2 = REGRAS.map((r) => (r.codigo === 'ritmo_fase' ? { ...r, limiar: 50 } : r.codigo === 'sem_fase' ? { ...r, ligada: false } : r));
    const b = calcularAlertas(O, r2, [ZZ28], []);
    expect(b.filter((x) => x.regra === 'ritmo_fase').map((x) => x.detalhe.direcao)).toEqual(['abaixo']);
    expect(b.some((x) => x.regra === 'sem_fase')).toBe(false);
    const exato = { ...ZZ28, fases: [{ ...ZZ28.fases[0], gastoAteOntem: 1200 }] };
    expect(calcularAlertas(O, REGRAS, [exato], []).some((x) => x.regra === 'ritmo_fase')).toBe(false);
  });

  it('sem gasto coletado ou sem base de pessoas: nada de verba, ritmo, leads nem CPL', () => {
    const vazio: ProjetoEntrada = { ...ZZ28, linha: { ...ZZ28.linha, investido: null, gasto_ontem: null, pct_verba: null, leads: null, cpl: null } };
    expect(calcularAlertas(O, REGRAS, [vazio], []).map((x) => x.regra).sort()).toEqual(['fora_padrao', 'sem_fase']);
  });

  it('leads sem fase de captação usam o período do projeto; sem período não avalia', () => {
    const semCap = { ...ZZ28, fases: [], linha: { ...ZZ28.linha, meta_leads: 200 } };
    const x = calcularAlertas(O, REGRAS, [semCap], []).find((y) => y.regra === 'leads_abaixo_meta')!;
    expect([x.referencia, x.detalhe.periodo]).toEqual([67, 'projeto']); // 200 × 10/30 dias do projeto = 66,7 → 67
    const semData = { ...semCap, linha: { ...semCap.linha, inicio: null } };
    expect(calcularAlertas(O, REGRAS, [semData], []).some((y) => y.regra === 'leads_abaixo_meta')).toBe(false);
  });

  it('frases da tela, sem travessão', () => {
    const textoAlerta = (x: Parameters<typeof texto>[0]) => texto(x).replace(/\u00a0/g, ' ');
    expect(textoAlerta(de('acima_verba_diaria'))).toBe('Gastou R$ 330 ontem; a verba diária é R$ 250 (132,0%).');
    expect(textoAlerta(de('ritmo_fase', 'acima'))).toBe('Captação: gastou R$ 1.210 desde 25/09/2026; pelo planejado seriam R$ 1.000 (121,0%, acima do ritmo).');
    expect(textoAlerta(de('leads_abaixo_meta'))).toBe('30 leads; o esperado para ontem era 50 (meta 100 na captação, 25/09/2026 a 14/10/2026).');
    expect(textoAlerta(a.find((y) => y.sigla === null)!)).toContain('sem projeto ligado');
    expect(textoRegra(REGRAS[5])).toBe('Campanhas fora do padrão (limiar 7 dias)');
    for (const y of a) expect(textoAlerta(y)).not.toMatch(/[—–]/);
  });
});

describe('20261006a: campanha do projeto em conta de fora e período de captação', () => {
  const REGRA: Regra = { codigo: 'conta_fora_projeto', nome: 'Campanha do projeto em conta de fora', ligada: true, limiar: 7, unidade: 'dias', gravidade: 'media', descricao: '' };
  const ZR28: ProjetoEntrada = {
    linha: { projeto_id: 9, sigla: 'ZR28', nome: 'Projeto Ensaio Contas', investido: 60, verba_maxima: null, verba_diaria: null, gasto_ontem: 60,
      ritmo_ontem: null, pct_verba: null, leads: null, meta_leads: null, cpl: null, meta_cpl: null, inicio: null, fim: null },
    entra: true, fases: [], campanhas: [],
    contasProjeto: [1],
    campanhasDaSigla: [
      { fora_padrao: false, fase: 'captacao', ultimoGasto: O, conta_id: 1, conta: 'Conta Ensaio A' },
      { fora_padrao: false, fase: 'captacao', ultimoGasto: O, conta_id: 2, conta: 'Conta Ensaio B' },
      { fora_padrao: true, fase: null, ultimoGasto: d(-30), conta_id: 2, conta: 'Conta Ensaio B' },
    ],
  };
  it('1 campanha gastando na Conta Ensaio B (os mesmos números do ensaio da 20261006a)', () => {
    const a = calcularAlertas(O, [REGRA], [ZR28], []);
    expect(a.map((x) => [x.regra, x.valor, x.detalhe.contas])).toEqual([['conta_fora_projeto', 1, ['Conta Ensaio B']]]);
    expect(texto(a[0])).toContain('em conta que não é do projeto (Conta Ensaio B)');
  });
  it('sem conta ligada ou com as duas contas: não avalia / não dispara', () => {
    expect(calcularAlertas(O, [REGRA], [{ ...ZR28, contasProjeto: [] }], [])).toEqual([]);
    expect(calcularAlertas(O, [REGRA], [{ ...ZR28, contasProjeto: [1, 2] }], [])).toEqual([]);
  });
  it('meta de leads sem fase de captação planejada: vale o período de captação do projeto', () => {
    const leads = REGRAS.find((r) => r.codigo === 'leads_abaixo_meta')!;
    const p: ProjetoEntrada = { ...ZZ28, fases: [], linha: { ...ZZ28.linha, inicio: d(-30), fim: d(30), captacao_inicio: d(-9), captacao_fim: d(10) } };
    const a = calcularAlertas(O, [leads], [p], []);
    expect(a[0].detalhe).toMatchObject({ periodo: 'projeto', inicio: d(-9), fim: d(10) });
    expect(a[0].referencia).toBe(50);
  });
});
