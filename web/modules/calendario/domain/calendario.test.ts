import { describe, expect, it } from 'vitest';
import {
  ehYmd, filtrar, hojeSaoPaulo, janelaCarga, mesNaJanela, mesSeguinte, montarGradeMes, normalizarEvento, opcoesFiltro,
  proximosEventos, rotuloPeriodo, rotuloQuem, semData, somarDias, type EventoCalendario,
} from './calendario';

// Linha no formato que public.calendario_eventos devolve (PB26 real em 07/10/2026 + fases hipotéticas).
const PB = {
  id: 1, chave: 'seminario-conjunto-2026-11', sigla: 'PB26', nome: 'Patrimônio Brasil 2026', tipo: 'interno',
  unidade: 'escritorio', unidade_nome: 'Escritório', tipo_lancamento: 'lancamento_classico',
  tipo_lancamento_nome: 'Lançamento clássico', especialista: null, inicio: '2026-10-05', fim: '2026-11-15',
  fases: [
    { fase: 'evento', inicio: '2026-11-09', fim: '2026-11-11', interno: false },
    { fase: 'captacao', inicio: '2026-10-05', fim: '2026-11-09', interno: false },
    { fase: 'replay', inicio: '2026-11-12', fim: '2026-11-13', interno: false },
    { fase: 'carrinho', inicio: '2026-11-09', fim: '2026-11-15' },
  ],
  links: [{ nome: 'AK1', url: 'https://patrimoniobrasil.com.br/ak1/' }, { nome: 'ruim', url: 'javascript:alert(1)' }],
};
const BF = {
  id: 4, chave: 'black-friday-2026-10', sigla: 'BF26', nome: 'Black Friday 2026', tipo: 'interno', unidade: 'csm',
  unidade_nome: 'CSM', tipo_lancamento: 'lancamento_classico', tipo_lancamento_nome: 'Lançamento clássico',
  especialista: 'Marcio Carvalho de Sá', inicio: null, fim: null,
  fases: [{ fase: 'evento', inicio: '2026-11-03', fim: '2026-11-03', interno: false }], links: [],
};
const HT = {
  id: 2, chave: null, sigla: 'HT33', nome: 'Holding Total 33', tipo: 'interno', unidade: 'csm', unidade_nome: 'CSM',
  tipo_lancamento: 'lancamento_pago', tipo_lancamento_nome: 'Lançamento pago', especialista: null,
  inicio: null, fim: null, fases: [], links: [],
};

const eventos = [PB, BF, HT].map(normalizarEvento).filter((e): e is EventoCalendario => e !== null);

describe('datas', () => {
  it('valida YYYY-MM-DD de verdade', () => {
    expect(ehYmd('2026-11-09')).toBe(true);
    expect(ehYmd('2026-02-30')).toBe(false);
    expect(ehYmd('09/11/2026')).toBe(false);
    expect(ehYmd(null)).toBe(false);
  });
  it('soma dias atravessando mês e ano sem escorregar no fuso', () => {
    expect(somarDias('2026-10-31', 1)).toBe('2026-11-01');
    expect(somarDias('2026-12-31', 1)).toBe('2027-01-01');
    expect(somarDias('2026-03-01', -1)).toBe('2026-02-28');
  });
  it('hoje em São Paulo, não em UTC', () => {
    // 07/10 às 01h UTC = 06/10 às 22h em São Paulo
    expect(hojeSaoPaulo(new Date('2026-10-07T01:00:00Z'))).toBe('2026-10-06');
    expect(hojeSaoPaulo(new Date('2026-10-07T15:00:00Z'))).toBe('2026-10-07');
  });
  it('rotula período', () => {
    expect(rotuloPeriodo('2026-11-09', '2026-11-11')).toBe('09/11 a 11/11');
    expect(rotuloPeriodo('2026-11-03', '2026-11-03')).toBe('03/11');
    expect(rotuloPeriodo('2027-01-05', '2027-01-05', 2026)).toBe('05/01/2027');
  });
});

describe('normalizarEvento', () => {
  it('ordena fases, marca replay como interno e completa fim ausente', () => {
    const pb = eventos.find((e) => e.id === 1)!;
    expect(pb.fases.map((f) => f.fase)).toEqual(['captacao', 'evento', 'carrinho', 'replay']);
    expect(pb.fases.find((f) => f.fase === 'replay')!.interno).toBe(true);
    expect(pb.fases.find((f) => f.fase === 'evento')!.interno).toBe(false);
    expect(pb.inicio).toBe('2026-10-05');
    expect(pb.fim).toBe('2026-11-15');
  });
  it('descarta link que não é https', () => {
    expect(eventos.find((e) => e.id === 1)!.links).toEqual([{ nome: 'AK1', url: 'https://patrimoniobrasil.com.br/ak1/' }]);
  });
  it('descarta fase desconhecida ou com data inválida', () => {
    const e = normalizarEvento({ ...HT, fases: [{ fase: 'sumico', inicio: '2026-10-01' }, { fase: 'evento', inicio: 'x' }] })!;
    expect(e.fases).toEqual([]);
    expect(e.inicio).toBeNull();
  });
  it('fim antes do início vira o próprio início', () => {
    const e = normalizarEvento({ ...HT, fases: [{ fase: 'evento', inicio: '2026-11-10', fim: '2026-11-01' }] })!;
    expect(e.fases[0].fim).toBe('2026-11-10');
  });
  it('linha sem id ou nome é descartada', () => {
    expect(normalizarEvento({ nome: 'x' })).toBeNull();
    expect(normalizarEvento({ id: 3, nome: '  ' })).toBeNull();
    expect(normalizarEvento(null)).toBeNull();
  });
  it('rótulo de quem: especialista e marca', () => {
    expect(rotuloQuem(eventos.find((e) => e.id === 4)!)).toBe('Marcio Carvalho de Sá · CSM');
    expect(rotuloQuem(eventos.find((e) => e.id === 1)!)).toBe('Escritório');
  });
});

describe('filtros', () => {
  it('filtra por tipo de lançamento e por unidade', () => {
    expect(filtrar(eventos, { tipoLancamento: 'lancamento_pago', unidade: '' }).map((e) => e.id)).toEqual([2]);
    expect(filtrar(eventos, { tipoLancamento: '', unidade: 'csm' }).map((e) => e.id).sort()).toEqual([2, 4]);
    expect(filtrar(eventos, { tipoLancamento: 'lancamento_classico', unidade: 'csm' }).map((e) => e.id)).toEqual([4]);
    expect(filtrar(eventos, { tipoLancamento: '', unidade: '' })).toHaveLength(3);
  });
  it('opções saem dos próprios eventos, sem repetir, em ordem alfabética', () => {
    const o = opcoesFiltro(eventos);
    expect(o.tipos).toEqual([
      { valor: 'lancamento_classico', rotulo: 'Lançamento clássico' },
      { valor: 'lancamento_pago', rotulo: 'Lançamento pago' },
    ]);
    expect(o.unidades.map((u) => u.rotulo)).toEqual(['CSM', 'Escritório']);
  });
});

describe('montarGradeMes', () => {
  const grade = montarGradeMes(2026, 11, eventos, '2026-11-10');
  const dia = (d: string) => grade.flat().find((x) => x.data === d)!;

  it('6 semanas de segunda a domingo', () => {
    expect(grade).toHaveLength(6);
    expect(grade.every((s) => s.length === 7)).toBe(true);
    // 01/11/2026 é domingo: a grade começa na segunda 26/10
    expect(grade[0][0].data).toBe('2026-10-26');
    expect(grade[0][6].data).toBe('2026-11-01');
    expect(grade[0][0].doMes).toBe(false);
    expect(grade[0][6].doMes).toBe(true);
  });
  it('marca hoje', () => {
    expect(dia('2026-11-10').hoje).toBe(true);
    expect(grade.flat().filter((d) => d.hoje)).toHaveLength(1);
  });
  it('põe as fases nos dias certos, com começo e fim', () => {
    expect(dia('2026-11-03').marcas.map((m) => `${m.sigla}:${m.fase}`)).toEqual(['PB26:captacao', 'BF26:evento']);
    const d9 = dia('2026-11-09').marcas.map((m) => m.fase);
    expect(d9).toEqual(['captacao', 'evento', 'carrinho']);
    const cap9 = dia('2026-11-09').marcas.find((m) => m.fase === 'captacao')!;
    expect(cap9.termina).toBe(true);
    const ev9 = dia('2026-11-09').marcas.find((m) => m.fase === 'evento')!;
    expect(ev9.comeca).toBe(true);
    expect(dia('2026-11-10').marcas.find((m) => m.fase === 'evento')!.comeca).toBe(false);
    expect(dia('2026-11-12').marcas.find((m) => m.fase === 'replay')!.interno).toBe(true);
    expect(dia('2026-11-16').marcas).toEqual([]);
  });
  it('fase que atravessa a semana repete o rótulo na segunda-feira', () => {
    // captação do PB começa em 05/10; segunda 02/11 é início de semana na grade de novembro
    expect(dia('2026-11-02').marcas.find((m) => m.fase === 'captacao')!.comeca).toBe(true);
    expect(dia('2026-11-03').marcas.find((m) => m.fase === 'captacao')!.comeca).toBe(false);
  });
  it('projeto sem data não aparece na grade', () => {
    expect(grade.flat().some((d) => d.marcas.some((m) => m.eventoId === 2))).toBe(false);
  });
});

describe('proximosEventos e semData', () => {
  it('em curso primeiro, depois pela próxima fase; terminados saem', () => {
    const p = proximosEventos(eventos, '2026-10-07');
    expect(p.map((i) => i.evento.sigla)).toEqual(['PB26', 'BF26']);
    expect(p[0].faseAtual?.fase).toBe('captacao');
    expect(p[0].proximaFase?.fase).toBe('evento');
    expect(p[1].faseAtual).toBeNull();
    expect(p[1].diasAteProxima).toBe(27);
    expect(proximosEventos(eventos, '2026-11-16')).toEqual([]);
  });
  it('fase atual é a mais adiantada no funil', () => {
    const p = proximosEventos(eventos, '2026-11-10');
    expect(p.find((i) => i.evento.id === 1)!.faseAtual?.fase).toBe('carrinho');
  });
  it('lista os sem data à parte', () => {
    expect(semData(eventos).map((e) => e.sigla)).toEqual(['HT33']);
  });
});

describe('janela', () => {
  it('vai do mês anterior até 3 meses à frente, abaixo de 400 dias', () => {
    const j = janelaCarga(2026, 10);
    expect(j).toEqual({ de: '2026-09-01', ate: '2027-01-31' });
    const j2 = janelaCarga(2026, 1);
    expect(j2).toEqual({ de: '2025-12-01', ate: '2026-04-30' });
  });
  it('sabe se o mês cabe na janela', () => {
    const j = janelaCarga(2026, 10);
    expect(mesNaJanela(2026, 9, j)).toBe(true);
    expect(mesNaJanela(2027, 1, j)).toBe(true);
    expect(mesNaJanela(2027, 2, j)).toBe(false);
    expect(mesNaJanela(2026, 8, j)).toBe(false);
  });
  it('navega entre meses', () => {
    expect(mesSeguinte(2026, 12, 1)).toEqual({ ano: 2027, mes: 1 });
    expect(mesSeguinte(2026, 1, -1)).toEqual({ ano: 2025, mes: 12 });
  });
});
