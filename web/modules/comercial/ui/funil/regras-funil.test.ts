import { describe, expect, it } from 'vitest';
import type { Negocio } from '../../domain/types';
import { filtrarNegocios, ordenarPorUrgencia, quandoCurto, resumoFunil, urgenciaDoNegocio } from './regras-funil';

const agora = new Date('2026-10-05T12:00:00');
const minAtras = (m: number) => new Date(agora.getTime() - m * 60000).toISOString();
const minDepois = (m: number) => new Date(agora.getTime() + m * 60000).toISOString();

function neg(p: Partial<Negocio> = {}): Negocio {
  return {
    id: 'n', contatoId: 'c', produto: 'hm', origem: 'manual' as Negocio['origem'], funilId: 'f', campanhaId: null,
    etapaId: 'e1', etapaNome: 'Qualificar', etapa: 'qualificar', status: 'aberto', donoId: 'v1', valor: 1000,
    campos: {}, motivoPerda: null, criadoEm: minAtras(60), etapaDesde: minAtras(60), fechadoEm: null,
    proximaAtividade: { id: 'a', tipo: 'ligacao', titulo: 'Ligar', venceEm: minDepois(60) }, ultimaInteracaoEm: null,
    ...p,
  } as Negocio;
}

describe('urgenciaDoNegocio', () => {
  it('prazo crítico ganha de tudo e diz o tempo', () => {
    const u = urgenciaDoNegocio(neg({ etapa: 'primeiro_contato', etapaDesde: minAtras(20), proximaAtividade: null, donoId: null }), agora);
    expect(u).toEqual({ motivo: 'sla_critico', tom: 'red', texto: 'Crítico · 20 min nesta etapa' });
  });
  it('atrasada vem antes de sem dono', () => {
    const u = urgenciaDoNegocio(neg({ donoId: null, proximaAtividade: { id: 'a', tipo: 'ligacao', titulo: 'x', venceEm: minAtras(120) } }), agora);
    expect(u?.motivo).toBe('atrasada');
    expect(u?.texto).toBe('Atrasada 2 h');
  });
  it('sem próximo passo', () => {
    expect(urgenciaDoNegocio(neg({ proximaAtividade: null }), agora)?.motivo).toBe('sem_proximo');
  });
  it('sem dono quando o resto está em dia', () => {
    expect(urgenciaDoNegocio(neg({ donoId: null }), agora)?.motivo).toBe('sem_dono');
  });
  it('atenção é amarelo', () => {
    const u = urgenciaDoNegocio(neg({ etapa: 'primeiro_contato', etapaDesde: minAtras(8) }), agora);
    expect(u?.tom).toBe('yellow');
  });
  it('negócio em dia ou ganho não tem sinal', () => {
    expect(urgenciaDoNegocio(neg(), agora)).toBeNull();
    expect(urgenciaDoNegocio(neg({ status: 'ganho', proximaAtividade: null }), agora)).toBeNull();
  });
});

describe('filtrarNegocios', () => {
  const contatos = new Map([['c', { nome: 'Ana Souza', email: 'ana@x.com', telefone: '5511999990000' }]]);
  const lista = [
    neg({ id: '1' }),
    neg({ id: '2', donoId: null }),
    neg({ id: '3', proximaAtividade: null }),
    neg({ id: '4', etapa: 'primeiro_contato', etapaDesde: minAtras(30) }),
    neg({ id: '5', status: 'ganho', donoId: null }),
  ];
  const base = { dono: 'todos', busca: '', alerta: null, vendedorId: 'v1' } as const;
  const ids = (r: Negocio[]) => r.map((n) => n.id);

  it('sem filtro devolve tudo', () => {
    expect(ids(filtrarNegocios(lista, base, contatos, agora))).toEqual(['1', '2', '3', '4', '5']);
  });
  it('alertas filtram só negócios abertos', () => {
    expect(ids(filtrarNegocios(lista, { ...base, alerta: 'sem_dono' }, contatos, agora))).toEqual(['2']);
    expect(ids(filtrarNegocios(lista, { ...base, alerta: 'sem_proximo' }, contatos, agora))).toEqual(['3']);
    expect(ids(filtrarNegocios(lista, { ...base, alerta: 'critico' }, contatos, agora))).toEqual(['4']);
  });
  it('dono e busca', () => {
    expect(ids(filtrarNegocios(lista, { ...base, dono: 'sem_dono' }, contatos, agora))).toEqual(['2', '5']);
    expect(filtrarNegocios(lista, { ...base, busca: 'souza' }, contatos, agora)).toHaveLength(5);
    expect(filtrarNegocios(lista, { ...base, busca: 'pedro' }, contatos, agora)).toHaveLength(0);
  });
  it('resumo conta só abertos', () => {
    expect(resumoFunil(lista, agora)).toEqual({ abertos: 4, valor: 4000, criticos: 1, semProximo: 1, semDono: 1, emNegociacao: 0, valorNegociacao: 0 });
  });
});

describe('ordenarPorUrgencia', () => {
  it('crítico primeiro', () => {
    const r = ordenarPorUrgencia([neg({ id: 'ok' }), neg({ id: 'crit', etapa: 'primeiro_contato', etapaDesde: minAtras(30) })], agora);
    expect(r[0].id).toBe('crit');
  });
});

describe('quandoCurto', () => {
  it('hoje, amanhã, ontem e data', () => {
    expect(quandoCurto(new Date('2026-10-05T14:00:00').toISOString(), agora)).toBe('hoje 14:00');
    expect(quandoCurto(new Date('2026-10-06T10:00:00').toISOString(), agora)).toBe('amanhã 10:00');
    expect(quandoCurto(new Date('2026-10-04T09:00:00').toISOString(), agora)).toBe('ontem 09:00');
    expect(quandoCurto(new Date('2026-10-12T09:00:00').toISOString(), agora)).toBe('12/10 09:00');
  });
});
