import { describe, expect, it } from 'vitest';
import { MOTIVOS_PADRAO } from '../../domain/catalogo';
import { calcularFechamento } from '../../domain/fechamento';
import type { Atividade, Negocio, Vendedor } from '../../domain/types';
import {
  conversaoPorEtapa, fmtDuracao, instanteDoDia, ordenarEquipe, perdidosPorMotivo, rankingEquipe, tempoMedioPorEtapa,
  textoFechamentoSlack, vendasDoDia, ymdLocal,
} from './indicadores';

const agora = new Date('2026-10-05T19:00:00-03:00');
const hoje = (h: number) => new Date(`2026-10-05T${String(h).padStart(2, '0')}:00:00-03:00`).toISOString();
const ontem = new Date('2026-10-04T12:00:00-03:00').toISOString();
const antigo = new Date('2026-08-01T12:00:00-03:00').toISOString();

const neg = (p: Partial<Negocio>): Negocio => ({
  id: 'n', contatoId: 'c', produto: 'hm', origem: 'venda_ativa', funilId: 'f', campanhaId: null, etapaId: 'e', etapaNome: 'Qualificar', etapa: 'qualificar', status: 'aberto', donoId: 'marcos',
  valor: 30000, campos: {}, motivoPerda: null, criadoEm: ontem, etapaDesde: ontem, fechadoEm: null,
  proximaAtividade: { id: 'a', tipo: 'ligacao', titulo: 'x', venceEm: hoje(20) }, ultimaInteracaoEm: null, ...p,
});
const atv = (p: Partial<Atividade>): Atividade => ({
  id: 'a', negocioId: 'n', contatoId: 'c', donoId: 'marcos', tipo: 'whatsapp', titulo: 'x', venceEm: hoje(10),
  concluidaEm: null, resultado: null, cadenciaDia: null, ...p,
});
const vend = (id: string): Vendedor => ({ id, nome: id, sigla: id.slice(0, 2).toUpperCase(), papel: 'vendedor', ativo: true, percentual: 50, disparaApi: false });
const nomeDe = (id: string | null) => (id ? id.charAt(0).toUpperCase() + id.slice(1) : 'Sem dono');

describe('instanteDoDia', () => {
  it('hoje = agora; ontem = 23:59 do dia anterior; data futura cai para agora', () => {
    expect(instanteDoDia('hoje', '', agora)).toBe(agora);
    const o = instanteDoDia('ontem', '', agora);
    expect(ymdLocal(o)).toBe(ymdLocal(new Date(agora.getTime() - 24 * 3600_000)));
    expect(o.getHours()).toBe(23);
    expect(instanteDoDia('data', '2099-01-01', agora)).toBe(agora);
    expect(ymdLocal(instanteDoDia('data', '2026-09-30', agora))).toBe('2026-09-30');
    expect(instanteDoDia('data', 'lixo', agora)).toBe(agora);
  });
});

describe('vendasDoDia', () => {
  it('agrupa ganhos do dia por produto e vendedor, maior valor primeiro', () => {
    const v = vendasDoDia([
      neg({ id: '1', status: 'ganho', fechadoEm: hoje(10), produto: 'ht', valor: 297 }),
      neg({ id: '2', status: 'ganho', fechadoEm: hoje(11), produto: 'ht', valor: 297 }),
      neg({ id: '3', status: 'ganho', fechadoEm: hoje(12), produto: 'hm', valor: 30000, donoId: 'ronan' }),
      neg({ id: '4', status: 'ganho', fechadoEm: ontem, produto: 'hm' }),
      neg({ id: '5', status: 'perdido', fechadoEm: hoje(12) }),
    ], agora);
    expect(v).toEqual([
      { produto: 'hm', donoId: 'ronan', quantidade: 1, valor: 30000 },
      { produto: 'ht', donoId: 'marcos', quantidade: 2, valor: 594 },
    ]);
  });
});

describe('textoFechamentoSlack', () => {
  it('traz os 5 números, vendas por produto com vendedor e alertas, sem emoji', () => {
    const negocios = [
      neg({ id: '1', status: 'ganho', fechadoEm: hoje(10), produto: 'ht', valor: 297, etapa: 'fechado' }),
      neg({ id: '2', etapa: 'negociar' }),
      neg({ id: '3', status: 'perdido', fechadoEm: hoje(9), motivoPerda: 'sem_interesse' }),
      neg({ id: '4', donoId: null, proximaAtividade: null }),
    ];
    const atividades = [atv({ id: 'x', venceEm: hoje(8) })];
    const f = calcularFechamento(negocios, atividades, [], agora);
    const txt = textoFechamentoSlack({ fechamento: f, vendas: vendasDoDia(negocios, agora), dia: agora, nomeDe, vendedorIds: ['marcos', 'ronan'] });
    expect(txt).toContain('Leads abordados: 0');
    expect(txt).toContain('Em negociação: 1 (0 entraram hoje)');
    expect(txt).toContain('Vendas: 1');
    expect(txt).toContain('- Holding Total: 1');
    expect(txt).toContain(', Marcos');
    expect(txt).toContain('Leads sem dono: 1 (meta zero)');
    expect(txt).toContain('Atividades atrasadas: Marcos 1');
    expect(txt).toContain('Perdidos do dia: Sem interesse 1');
    expect(txt).not.toMatch(/[\u{1F300}-\u{1FAFF}]/u);
  });
});

describe('conversaoPorEtapa', () => {
  it('conta quem chegou em cada etapa e a passagem da anterior; ignora origens da Hotmart', () => {
    const l = conversaoPorEtapa([
      neg({ id: '1', etapa: 'primeiro_contato' }),
      neg({ id: '2', etapa: 'qualificar' }),
      neg({ id: '3', etapa: 'negociar' }),
      neg({ id: '4', status: 'ganho', etapa: 'fechado' }),
      neg({ id: '5', origem: 'carrinho_abandonado', etapa: 'negociar' }),
    ], 'todos');
    expect(l.map((x) => x.chegaram)).toEqual([4, 3, 2, 2, 1, 1]);
    expect(l[0].passagem).toBeNull();
    expect(l[1].passagem).toBe(75);
    expect(l[5].doTotal).toBe(25);
  });
  it('filtra por produto', () => {
    const l = conversaoPorEtapa([neg({ id: '1', produto: 'ht' }), neg({ id: '2', produto: 'hm' })], 'ht');
    expect(l[0].chegaram).toBe(1);
  });
  it('sem negócios não divide por zero', () => {
    expect(conversaoPorEtapa([], 'todos').every((x) => x.doTotal === 0)).toBe(true);
  });
});

describe('tempoMedioPorEtapa', () => {
  it('média dos abertos parados na etapa; null quando vazia; sem "Fechado"', () => {
    const t = tempoMedioPorEtapa([
      neg({ id: '1', etapa: 'qualificar', etapaDesde: new Date(agora.getTime() - 60 * 60000).toISOString() }),
      neg({ id: '2', etapa: 'qualificar', etapaDesde: new Date(agora.getTime() - 180 * 60000).toISOString() }),
      neg({ id: '3', etapa: 'qualificar', status: 'perdido' }),
    ], 'todos', agora);
    expect(t).toHaveLength(5);
    const q = t.find((x) => x.etapa === 'qualificar')!;
    expect(q.abertos).toBe(2);
    expect(q.mediaMin).toBe(120);
    expect(t.find((x) => x.etapa === 'negociar')!.mediaMin).toBeNull();
  });
});

describe('perdidosPorMotivo', () => {
  it('lista os 9 motivos e marca a falha de distribuição', () => {
    const l = perdidosPorMotivo([
      neg({ id: '1', status: 'perdido', motivoPerda: 'ja_atendido_outro_vendedor' }),
      neg({ id: '2', status: 'perdido', motivoPerda: 'ja_atendido_outro_vendedor' }),
      neg({ id: '3', status: 'perdido', motivoPerda: 'sem_interesse', produto: 'ht' }),
    ], 'hm');
    expect(l).toHaveLength(9);
    const f = l.find((x) => x.motivo === 'ja_atendido_outro_vendedor')!;
    expect(f.quantidade).toBe(2);
    expect(f.falhaDistribuicao).toBe(true);
    expect(l.find((x) => x.motivo === 'sem_interesse')!.quantidade).toBe(0);
  });

  it('usa o cadastro: personalizados, desativados com perdido e chaves fora do cadastro', () => {
    const cadastro = [
      ...MOTIVOS_PADRAO.map((m) => (m.key === 'fora_do_perfil' ? { ...m, ativo: false } : m.key === 'contato_invalido' ? { ...m, ativo: false } : m)),
      { key: 'preco_alto', label: 'Preço alto', reativa: true, bloqueia: false, alertaGestor: true, nota: null, sistema: false, ativo: true },
    ];
    const l = perdidosPorMotivo([
      neg({ id: '1', status: 'perdido', motivoPerda: 'preco_alto' }),
      neg({ id: '2', status: 'perdido', motivoPerda: 'fora_do_perfil' }),
      neg({ id: '3', status: 'perdido', motivoPerda: 'motivo_antigo' }),
    ], 'todos', cadastro);
    // 9 de fábrica − contato_invalido (desativado e sem perdido) + preco_alto + motivo_antigo
    expect(l).toHaveLength(10);
    const preco = l.find((x) => x.motivo === 'preco_alto')!;
    expect(preco).toMatchObject({ rotulo: 'Preço alto', quantidade: 1, personalizado: true, alertaGestor: true });
    expect(l.find((x) => x.motivo === 'fora_do_perfil')).toMatchObject({ desativado: true, quantidade: 1 });
    expect(l.at(-1)).toMatchObject({ motivo: 'motivo_antigo', rotulo: 'motivo antigo', quantidade: 1 });
  });
});

describe('fmtDuracao', () => {
  it('formata minutos, horas e dias', () => {
    expect(fmtDuracao(null)).toBe('—');
    expect(fmtDuracao(12)).toBe('12 min');
    expect(fmtDuracao(180)).toBe('3 h');
    expect(fmtDuracao(24 * 60)).toBe('1 dia');
    expect(fmtDuracao(3 * 24 * 60)).toBe('3 dias');
  });
});

describe('rankingEquipe', () => {
  const negocios = [
    neg({ id: '1', status: 'ganho', fechadoEm: hoje(10), valor: 30000 }),
    neg({ id: '2', status: 'perdido', fechadoEm: hoje(11) }),
    neg({ id: '3', status: 'perdido', fechadoEm: hoje(12) }),
    neg({ id: '4', status: 'ganho', fechadoEm: antigo, valor: 297 }),
    neg({ id: '5' }),
    neg({ id: '6', donoId: 'ronan', status: 'ganho', fechadoEm: hoje(9), valor: 297 }),
  ];
  const atividades = [
    atv({ id: 'a1', concluidaEm: hoje(10) }),
    atv({ id: 'a2', venceEm: hoje(8) }),
    atv({ id: 'a3', donoId: 'ronan', concluidaEm: antigo }),
  ];
  it('vendas, receita, conversão, carga e atividades no período', () => {
    const desde = new Date(agora.getTime() - 7 * 24 * 3600_000);
    const [m, r] = rankingEquipe([vend('marcos'), vend('ronan')], negocios, atividades, agora, desde);
    expect(m).toMatchObject({ vendas: 1, receita: 30000, encerrados: 3, abertos: 1, concluidas: 1, atrasadas: 1 });
    expect(m.conversao).toBeCloseTo(33.33, 1);
    expect(r).toMatchObject({ vendas: 1, receita: 297, conversao: 100, concluidas: 0 });
  });
  it('sem período conta todo o histórico; sem encerrados a conversão é null', () => {
    const [m, x] = rankingEquipe([vend('marcos'), vend('ninguem')], negocios, atividades, agora, null);
    expect(m.vendas).toBe(2);
    expect(x.conversao).toBeNull();
  });
  it('ordena por coluna e deixa conversão vazia no fim', () => {
    const linhas = rankingEquipe([vend('marcos'), vend('ronan'), vend('ninguem')], negocios, atividades, agora, null);
    const porConv = ordenarEquipe(linhas, 'conversao', 'desc', nomeDe);
    expect(porConv.map((l) => l.vendedorId)).toEqual(['ronan', 'marcos', 'ninguem']);
    expect(ordenarEquipe(linhas, 'conversao', 'asc', nomeDe).at(-1)!.vendedorId).toBe('ninguem');
    expect(ordenarEquipe(linhas, 'nome', 'asc', nomeDe).map((l) => l.vendedorId)).toEqual(['marcos', 'ninguem', 'ronan']);
  });
});
