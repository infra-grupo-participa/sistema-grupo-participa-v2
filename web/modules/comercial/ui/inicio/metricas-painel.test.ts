import { describe, expect, it } from 'vitest';
import type { Atividade, EventoTimeline, Negocio } from '../../domain/types';
import { calcularWidget, diaBR, diasDoIntervalo, formatarValor, inicioDiaBR, intervalos, variacao, type DadosPainel } from './metricas-painel';
import {
  agrupamentosPermitidos, coerente, moverPara, moverWidget, painelPadraoInicio, salvarWidget, validarWidget, visuaisPermitidos, widgetNovo,
} from './painel-edicao';

const AGORA = new Date('2026-10-05T18:00:00Z'); // 15h em Brasília
const min = (m: number) => new Date(AGORA.getTime() - m * 60000).toISOString();
const DIA = 1440;

const neg = (id: string, extra: Partial<Negocio> = {}): Negocio => ({
  id, contatoId: `c-${id}`, produto: 'hm', origem: 'venda_ativa', funilId: 'f1', campanhaId: null, etapaId: 'e', etapaNome: 'Qualificar', etapa: 'qualificar', status: 'aberto', donoId: 'v-marcos',
  valor: 1000, campos: {}, motivoPerda: null, criadoEm: min(5000), etapaDesde: min(10), fechadoEm: null,
  proximaAtividade: { id: 'x', tipo: 'ligacao', titulo: 'x', venceEm: min(-60) }, ultimaInteracaoEm: null, ...extra,
});
const atv = (id: string, extra: Partial<Atividade> = {}): Atividade => ({
  id, negocioId: null, contatoId: 'c', donoId: 'v-marcos', tipo: 'ligacao', titulo: id, venceEm: min(-60),
  concluidaEm: null, resultado: null, cadenciaDia: null, ...extra,
});
const evt = (id: string, extra: Partial<EventoTimeline>): EventoTimeline => ({
  id, contatoId: 'c', negocioId: null, tipo: 'etapa', titulo: '', detalhe: null, em: min(30), autorId: null, ...extra,
});

const base = (extra: Partial<DadosPainel> = {}): DadosPainel => ({
  negocios: [], atividades: [], eventos: [], funis: [{ id: 'f1', nome: 'Venda ativa HM' }, { id: 'f2', nome: 'Carrinho HT' }] as DadosPainel['funis'],
  motivos: [{ key: 'sem_interesse', label: 'Sem interesse' }, { key: 'preco', label: 'Preço' }],
  vendedores: [{ id: 'v-marcos', nome: 'Marcos Paulo' }, { id: 'v-ronan', nome: 'Ronan' }],
  agora: AGORA, donoId: null, ...extra,
});

describe('datas do painel (Brasília)', () => {
  it('dia e meia-noite no fuso', () => {
    expect(diaBR('2026-10-05T02:00:00Z')).toBe('2026-10-04'); // 23h do dia 4 em Brasília
    expect(inicioDiaBR(AGORA).toISOString()).toBe('2026-10-05T03:00:00.000Z');
  });

  it('períodos e o anterior equivalente', () => {
    const h = intervalos('hoje', AGORA);
    expect(new Date(h.atual.ini).toISOString()).toBe('2026-10-05T03:00:00.000Z');
    expect(new Date(h.anterior.fim).toISOString()).toBe('2026-10-04T18:00:00.000Z');
    const s = intervalos('7d', AGORA);
    expect(diasDoIntervalo(s.atual)).toHaveLength(7);
    const m = intervalos('mes', AGORA);
    expect(new Date(m.atual.ini).toISOString()).toBe('2026-10-01T03:00:00.000Z');
    expect(new Date(m.anterior.ini).toISOString()).toBe('2026-09-01T03:00:00.000Z');
    expect(new Date(m.anterior.fim).toISOString()).toBe('2026-09-05T18:00:00.000Z');
  });
});

describe('cálculo dos widgets', () => {
  const negocios = [
    neg('g1', { status: 'ganho', fechadoEm: min(60), valor: 2000, donoId: 'v-marcos' }),
    neg('g2', { status: 'ganho', fechadoEm: min(2 * DIA), valor: 3000, donoId: 'v-ronan', produto: 'ht', funilId: 'f2' }),
    neg('g-ant', { status: 'ganho', fechadoEm: min(8 * DIA), valor: 1000 }),
    neg('p1', { status: 'perdido', fechadoEm: min(DIA), motivoPerda: 'sem_interesse' }),
    neg('p2', { status: 'perdido', fechadoEm: min(DIA), motivoPerda: 'preco', donoId: 'v-ronan' }),
    neg('n1', { etapa: 'negociar', valor: 5000 }),
    neg('crit', { etapa: 'primeiro_contato', etapaDesde: min(60), donoId: 'v-ronan', proximaAtividade: null }),
    neg('semdono', { donoId: null }),
  ];

  it('vendas e receita: total, variação e por vendedor', () => {
    const d = base({ negocios });
    const v = calcularWidget({ metrica: 'vendas', periodo: '7d', agrupar: 'vendedor', funilId: null }, d);
    expect(v.valor).toBe(2);
    expect(v.anterior).toBe(1);
    expect(variacao(v)).toBe(100);
    expect(v.pontos.map((p) => [p.rotulo, p.valor])).toEqual([['Marcos Paulo', 1], ['Ronan', 1]]);
    const r = calcularWidget({ metrica: 'receita', periodo: 'hoje', agrupar: 'nenhum', funilId: null }, d);
    expect(r.valor).toBe(2000);
    expect(r.pontos).toEqual([]);
  });

  it('perspectiva do vendedor e filtro por funil', () => {
    expect(calcularWidget({ metrica: 'vendas', periodo: '7d', agrupar: 'nenhum', funilId: null }, base({ negocios, donoId: 'v-ronan' })).valor).toBe(1);
    expect(calcularWidget({ metrica: 'receita', periodo: '7d', agrupar: 'nenhum', funilId: 'f2' }, base({ negocios })).valor).toBe(3000);
    // Sem dono é do time: aparece mesmo na perspectiva de um vendedor.
    expect(calcularWidget({ metrica: 'sem_dono', periodo: 'hoje', agrupar: 'nenhum', funilId: null }, base({ negocios, donoId: 'v-ronan' })).valor).toBe(1);
  });

  it('fotografias ignoram o período e não comparam', () => {
    const d = base({ negocios });
    const n = calcularWidget({ metrica: 'em_negociacao', periodo: '30d', agrupar: 'nenhum', funilId: null }, d);
    expect(n.valor).toBe(5000);
    expect(n.fotografia).toBe(true);
    expect(n.anterior).toBeNull();
    expect(calcularWidget({ metrica: 'criticos', periodo: 'hoje', agrupar: 'vendedor', funilId: null }, d).pontos).toEqual([{ chave: 'v-ronan', rotulo: 'Ronan', valor: 1 }]);
    expect(calcularWidget({ metrica: 'sem_proximo', periodo: 'hoje', agrupar: 'nenhum', funilId: null }, d).valor).toBe(1);
  });

  it('perdidos por motivo (com o cadastro) e conversão', () => {
    const d = base({ negocios });
    const p = calcularWidget({ metrica: 'perdidos', periodo: '7d', agrupar: 'motivo', funilId: null }, d);
    expect(p.pontos.map((x) => x.rotulo).sort()).toEqual(['Preço', 'Sem interesse']);
    // 2 ganhos e 2 perdidos nos últimos 7 dias.
    expect(calcularWidget({ metrica: 'conversao', periodo: '7d', agrupar: 'nenhum', funilId: null }, d).valor).toBe(50);
    expect(calcularWidget({ metrica: 'conversao', periodo: 'hoje', agrupar: 'nenhum', funilId: null }, base()).valor).toBeNull();
  });

  it('abordados: pessoa única, por dia, todo dia aparece', () => {
    const atividades = [
      atv('a1', { contatoId: 'x', concluidaEm: min(30) }),
      atv('a2', { contatoId: 'x', concluidaEm: min(20), tipo: 'whatsapp' }),
      atv('a3', { contatoId: 'y', concluidaEm: min(DIA + 30) }),
      atv('a4', { contatoId: 'z', concluidaEm: min(30), tipo: 'email' }),
    ];
    const s = calcularWidget({ metrica: 'abordados', periodo: '7d', agrupar: 'dia', funilId: null }, base({ atividades }));
    expect(s.valor).toBe(2);
    expect(s.pontos).toHaveLength(7);
    expect(s.pontos.at(-1)).toEqual({ chave: '2026-10-05', rotulo: '05/10', valor: 1 });
    expect(s.pontos.at(-2)?.valor).toBe(1);
  });

  it('responderam, entraram em contato e tempo até o primeiro contato', () => {
    const negocios2 = [neg('r', { criadoEm: min(120) })];
    const eventos = [
      evt('e1', { contatoId: 'c-r', negocioId: 'r', detalhe: 'qualificar' }),
      evt('e2', { contatoId: 'c-r', negocioId: 'r', detalhe: 'qualificar', em: min(10) }),
      evt('e3', { contatoId: 'novo', tipo: 'mensagem', titulo: 'Lead escreveu no WhatsApp' }),
    ];
    const atividades = [atv('a', { negocioId: 'r', concluidaEm: min(100) }), atv('b', { negocioId: 'r', concluidaEm: min(40) })];
    const d = base({ negocios: negocios2, eventos, atividades });
    expect(calcularWidget({ metrica: 'responderam', periodo: 'hoje', agrupar: 'nenhum', funilId: null }, d).valor).toBe(1);
    expect(calcularWidget({ metrica: 'entraram_contato', periodo: 'hoje', agrupar: 'nenhum', funilId: null }, d).valor).toBe(1);
    expect(calcularWidget({ metrica: 'tempo_primeiro_contato', periodo: 'hoje', agrupar: 'nenhum', funilId: null }, d).valor).toBe(20);
  });

  it('agrupamento que a métrica não aceita vira total', () => {
    expect(calcularWidget({ metrica: 'sem_dono', periodo: 'hoje', agrupar: 'vendedor', funilId: null }, base({ negocios })).pontos).toEqual([]);
  });

  it('formata conforme a métrica', () => {
    expect(formatarValor(null, 'numero')).toBe('—');
    expect(formatarValor(12.5, 'percentual')).toBe('12,5%');
    expect(formatarValor(45, 'minutos')).toBe('45 min');
    expect(formatarValor(125, 'minutos')).toBe('2 h 5 min');
    expect(formatarValor(1500, 'moeda')).toMatch(/R\$\s1\.500/);
  });
});

describe('edição do painel', () => {
  it('padrão por papel', () => {
    expect(painelPadraoInicio('v-x', true).widgets).toHaveLength(5);
    expect(painelPadraoInicio('v-x', false).widgets.every((w) => w.id.startsWith('v-x-'))).toBe(true);
  });

  it('visual e agrupamento coerentes com a métrica', () => {
    expect(visuaisPermitidos('conversao')).not.toContain('pizza');
    expect(visuaisPermitidos('abertos')).not.toContain('linha');
    expect(agrupamentosPermitidos('vendas', 'linha')).toEqual(['dia']);
    expect(agrupamentosPermitidos('vendas', 'numero')).toEqual(['nenhum']);
    const w = coerente({ ...widgetNovo('n'), metrica: 'abertos', visual: 'linha', agrupar: 'dia' });
    expect(w.visual).toBe('numero');
    expect(w.agrupar).toBe('nenhum');
    const b = coerente({ ...widgetNovo('n'), visual: 'barras' });
    expect(b.agrupar).toBe('dia');
  });

  it('valida antes de salvar', () => {
    expect(validarWidget(widgetNovo('n'))).toMatch(/título/);
    expect(validarWidget({ ...widgetNovo('n'), titulo: 'Ok' })).toBeNull();
    expect(validarWidget({ ...widgetNovo('n'), titulo: 'Ok', visual: 'barras', agrupar: 'nenhum' })).toMatch(/agrupamento/);
  });

  it('inclui, substitui e reordena', () => {
    const a = { ...widgetNovo('a'), titulo: 'A' };
    const b = { ...widgetNovo('b'), titulo: 'B' };
    let l = salvarWidget(salvarWidget([], a), b);
    expect(l.map((w) => w.id)).toEqual(['a', 'b']);
    l = salvarWidget(l, { ...a, titulo: 'A2' });
    expect(l[0].titulo).toBe('A2');
    expect(moverWidget(l, 'b', -1).map((w) => w.id)).toEqual(['b', 'a']);
    expect(moverWidget(l, 'b', 1)).toBe(l);
    expect(moverPara([1, 2, 3, 4], 0, 2)).toEqual([2, 3, 1, 4]);
  });
});
