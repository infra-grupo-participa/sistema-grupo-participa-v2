import { describe, expect, it } from 'vitest';
import {
  MODELO_VAZIO, contarPrevia, dataRelativa, marcarCriadas, modelosDoProjeto, paraSalvar, previaModelo, somaPct, somarDias, textoRelativo, validarModelo,
  type Modelo,
} from './modelos';

// Os mesmos números do ensaio da 20261006l (projeto ZD28: captação 01 a 20/11, evento 25 a 27/11, verba 10.000).
const CLASSICO: Modelo = {
  ...MODELO_VAZIO('lancamento_classico'), id: 1, nome: 'Exemplo: Lançamento clássico CSM', rascunho: true, unidades: [{ unidade: 'csm', padrao: true }],
  fases: [
    { fase: 'aquecimento', ordem: 1, inicio_ref: 'captacao_inicio', inicio_dias: -7, fim_ref: 'captacao_inicio', fim_dias: -1, pct_verba: 10, obs: null },
    { fase: 'captacao', ordem: 2, inicio_ref: 'captacao_inicio', inicio_dias: 0, fim_ref: 'captacao_fim', fim_dias: 0, pct_verba: 60, obs: null },
    { fase: 'lembrete', ordem: 3, inicio_ref: 'evento_inicio', inicio_dias: -2, fim_ref: 'evento_inicio', fim_dias: 0, pct_verba: 10, obs: null },
    { fase: 'remarketing', ordem: 4, inicio_ref: 'captacao_inicio', inicio_dias: 0, fim_ref: 'evento_fim', fim_dias: 0, pct_verba: 10, obs: null },
    { fase: 'abertura_carrinho', ordem: 5, inicio_ref: 'evento_fim', inicio_dias: 0, fim_ref: 'evento_fim', fim_dias: 3, pct_verba: 10, obs: null },
  ],
  campanhas: [{ objetivo: 'LEADS', fase: 'captacao', descricao: null, pagina: null }],
  itens: [{ texto: 'Automação de ingresso no grupo do WhatsApp configurada no SendFlow', momento: 'antes' }],
};
const PROJ = { tipo_lancamento: 'lancamento_classico', unidade: 'csm', captacao_inicio: '2026-11-01', captacao_fim: '2026-11-20', evento_inicio: '2026-11-25', evento_fim: '2026-11-27' };
const REGRAS = { csm: ['lancamento_classico', 'lancamento_pago', 'lpsg', 'atm'], escritorio: ['lancamento_classico', 'atm'] };

describe('datas relativas', () => {
  it('soma e texto', () => {
    expect(somarDias('2026-11-01', -7)).toBe('2026-10-25');
    expect(somarDias('2026-12-30', 3)).toBe('2027-01-02');
    expect(dataRelativa('evento_fim', 3, PROJ)).toBe('2026-11-30');
    expect(dataRelativa('evento_fim', 3, { ...PROJ, evento_fim: null })).toBeNull();
    expect(textoRelativo('captacao_inicio', -7)).toBe('7 dias antes do início da captação');
    expect(textoRelativo('captacao_fim', 0)).toBe('no fim da captação');
    expect(textoRelativo('evento_fim', 1)).toBe('1 dia depois do fim do evento');
  });
});

describe('prévia de aplicar (a mesma conta de mkt_trafego.modelo_previa)', () => {
  it('datas e verba como no ensaio; captação existente mudaria', () => {
    const p = previaModelo(CLASSICO, PROJ, 10000, [{ fase: 'captacao', verba: 5000, inicio: null, fim: null }], (f) => f);
    expect(p.fases.map((f) => `${f.fase} ${f.verba} ${f.inicio}/${f.fim}`)).toEqual([
      'aquecimento 1000 2026-10-25/2026-10-31', 'captacao 6000 2026-11-01/2026-11-20', 'lembrete 1000 2026-11-23/2026-11-25',
      'remarketing 1000 2026-11-01/2026-11-27', 'abertura_carrinho 1000 2026-11-27/2026-11-30']);
    expect(contarPrevia(p)).toEqual({ novas: 4, mudam: 1, iguais: 0, campanhas: 1, itens: 1 });
    expect(p.pode_aplicar).toBe(true);
  });
  it('sem verba e sem períodos: avisa e as fases nascem vazias; outra unidade não pode aplicar', () => {
    const p = previaModelo(CLASSICO, { ...PROJ, captacao_inicio: null, captacao_fim: null, evento_inicio: null, evento_fim: null }, null, [], (f) => f);
    expect(p.avisos).toEqual(['sem_verba_maxima', 'sem_periodos']);
    expect(p.fases[0]).toMatchObject({ inicio: null, verba: null, aviso: 'sem_data' });
    expect(previaModelo(CLASSICO, { ...PROJ, unidade: 'escritorio' }, 1, [], (f) => f).pode_aplicar).toBe(false);
  });
  it('datas invertidas ficam em branco; o que já está no projeto não se repete', () => {
    const m = { ...CLASSICO, fases: [{ ...CLASSICO.fases[0], fim_ref: 'captacao_inicio' as const, fim_dias: -10 }] };
    expect(previaModelo(m, PROJ, 100, [], (f) => f).fases[0]).toMatchObject({ inicio: null, fim: null, aviso: 'datas_invertidas' });
    const p = previaModelo(CLASSICO, PROJ, 100, [], (f) => f, [{ objetivo: 'LEADS', fase: 'captacao', descricao: null, pagina: null }],
      ['automação de ingresso no grupo do whatsapp configurada no sendflow']);
    expect([p.campanhas[0].ja_existe, p.itens[0].ja_existe]).toEqual([true, true]);
  });
});

describe('modelo: validação, lista do projeto e o que vai para o banco', () => {
  it('validar', () => {
    const ok = (x: Partial<Modelo>) => validarModelo({ ...CLASSICO, ...x }, REGRAS, ['LEADS']);
    expect(ok({})).toBeNull();
    expect(ok({ tipo_lancamento: 'lpsg', unidades: [{ unidade: 'escritorio', padrao: false }] })).toMatch(/LPSG só na CSM/);
    expect(ok({ fases: [CLASSICO.fases[0], CLASSICO.fases[0]] })).toMatch(/mesma fase/);
    expect(ok({ campanhas: [{ objetivo: 'TOPO', fase: null, descricao: null, pagina: null }] })).toMatch(/Objetivo/);
    expect(ok({ unidades: [] })).toMatch(/unidade/);
    expect(somaPct(CLASSICO.fases)).toBe(100);
  });
  it('lista do projeto: ativos, do tipo e da unidade, padrão primeiro', () => {
    const outro = { ...CLASSICO, id: 2, nome: 'A outro', rascunho: false, unidades: [{ unidade: 'csm', padrao: false }] };
    const inativo = { ...CLASSICO, id: 3, nome: 'B inativo', ativo: false };
    expect(modelosDoProjeto([outro, inativo, CLASSICO], 'lancamento_classico', 'csm').map((m) => [m.id, m.padrao])).toEqual([[1, true], [2, false]]);
    expect(modelosDoProjeto([CLASSICO], 'lancamento_classico', null)).toEqual([]);
  });
  it('paraSalvar: ordem pela posição e vazio no lugar de nulo', () => {
    const p = paraSalvar({ ...CLASSICO, id: 0 });
    expect('id' in p).toBe(false);
    expect(p.fases.map((f) => f.ordem)).toEqual([1, 2, 3, 4, 5]);
    expect(p.meta_cpl).toBe('');
  });
});

describe('campanhas esperadas × encontradas', () => {
  it('conta por objetivo e página', () => {
    const e = [{ id: 1, objetivo: 'LEADS', fase: null, descricao: null, pagina: null }, { id: 2, objetivo: 'LEADS', fase: null, descricao: null, pagina: null },
      { id: 3, objetivo: 'LEADS', fase: null, descricao: null, pagina: 'ak1' }];
    expect(marcarCriadas(e, [{ objetivo: 'LEADS', pagina: 'bl2' }]).map((x) => x.criada)).toEqual([true, false, false]);
    expect(marcarCriadas(e, [{ objetivo: 'LEADS', pagina: 'ak1' }, { objetivo: 'LEADS', pagina: null }]).map((x) => x.criada)).toEqual([true, true, true]);
  });
});
