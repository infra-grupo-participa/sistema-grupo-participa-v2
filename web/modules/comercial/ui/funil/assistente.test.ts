import { describe, expect, it } from 'vitest';
import { etapasPadrao, validarFunil } from '../../domain/funis';
import { MODELOS_FUNIL, modeloFunil } from '../../domain/modelos';
import type { Funil, Negocio, Vendedor } from '../../domain/types';
import {
  agruparPorProjeto, aplicarPartida, boasPraticas, cadeiaEtapas, capaDoModelo, iconeDoFunil, ICONES_FUNIL,
  integracoesDoFunil, passoMaximo, problemasDoPasso, trocarChave,
} from './assistente';
import { resumoFunil } from './regras-funil';

const vendedores: Vendedor[] = [
  { id: 'v1', nome: 'Ana', sigla: 'AN', papel: 'vendedor', ativo: true, percentual: 60, disparaApi: false },
  { id: 'v2', nome: 'Bia', sigla: 'BI', papel: 'vendedor', ativo: true, percentual: 40, disparaApi: false },
];

function funil(p: Partial<Funil> = {}): Funil {
  return {
    id: '', nome: 'Venda ativa', icone: 'kanban', projeto: null, agrupadorId: 'a1', produto: 'hm', tipo: 'manual',
    eventosHotmart: [], etapas: etapasPadrao('t'), campanhas: [], distribuicao: null, ativo: true, criadoEm: '', ...p,
  };
}
const pratica = (f: Funil, id: string) => boasPraticas(f, vendedores).find((p) => p.id === id)!;

describe('ícones', () => {
  it('lista só nomes do mapa, sem repetir', () => {
    const nomes = ICONES_FUNIL.map((i) => i.nome);
    expect(new Set(nomes).size).toBe(nomes.length);
    expect(nomes).toContain('kanban');
  });
  it('ícone fora da lista cai no padrão do tipo', () => {
    expect(iconeDoFunil({ icone: 'flame', tipo: 'manual' })).toBe('flame');
    expect(iconeDoFunil({ icone: '', tipo: 'hotmart' })).toBe('zap');
    expect(iconeDoFunil({ icone: 'nao-existe', tipo: 'manual' })).toBe('kanban');
  });
});

describe('passos do assistente', () => {
  it('cada passo olha só os próprios campos; a revisão olha todos', () => {
    const problemas = validarFunil(funil({ nome: '', agrupadorId: '' }), vendedores);
    expect(problemasDoPasso('partida', problemas)).toHaveLength(0);
    expect(problemasDoPasso('geral', problemas).map((p) => p.campo)).toEqual(['nome', 'agrupador']);
    expect(problemasDoPasso('etapas', problemas)).toHaveLength(0);
    expect(problemasDoPasso('revisao', problemas)).toHaveLength(2);
  });
  it('passo máximo para no primeiro com pendência', () => {
    expect(passoMaximo(validarFunil(funil({ nome: '' }), vendedores))).toBe(1);
    expect(passoMaximo(validarFunil(funil({ distribuicao: [{ vendedorId: 'v1', percentual: 50 }] }), vendedores))).toBe(4);
    expect(passoMaximo(validarFunil(funil(), vendedores))).toBe(5);
  });
});

describe('ponto de partida', () => {
  it('modelo traz etapas e campanhas com a chave do projeto', () => {
    const m = modeloFunil('quentes')!;
    const f = aplicarPartida(funil(), m, 'ht34-meteorico', 'x');
    expect(f.etapas.map((e) => e.nome)).toEqual(m.etapas.map((e) => e.nome));
    expect(f.campanhas[0].regra).toBe('utm_campaign = ht34-meteorico');
    expect(f.projeto).toBe('ht34-meteorico');
    expect(f.nome).toBe('Venda ativa');
  });
  it('em branco volta às etapas do playbook e sugere a campanha de UTM só com chave', () => {
    const f0 = funil({ etapas: [] });
    expect(aplicarPartida(f0, null, null, 'x').campanhas).toHaveLength(0);
    const f = aplicarPartida(f0, null, 'sem-2026', 'x');
    expect(f.etapas).toHaveLength(6);
    expect(f.campanhas).toEqual([expect.objectContaining({ canal: 'utm', regra: 'utm_campaign = sem-2026' })]);
  });
  it('trocar a chave mexe só nas campanhas', () => {
    const m = modeloFunil('quentes')!;
    const f = aplicarPartida(funil(), m, 'ht34', 'x');
    const etapas = f.etapas.map((e, i) => (i === 0 ? { ...e, nome: 'Editada' } : e));
    const g = trocarChave({ ...f, etapas }, 'ht34', 'ht35', m, 'y');
    expect(g.etapas[0].nome).toBe('Editada');
    expect(g.campanhas[0]).toMatchObject({ nome: 'Aula ht35', regra: 'utm_campaign = ht35' });
    expect(trocarChave(g, 'ht35', null, m, 'y').campanhas[0].nome).toBe('Aula');
    const semCampanha = trocarChave({ ...f, campanhas: [] }, null, 'ht36', m, 'z');
    expect(semCampanha.campanhas[0].regra).toBe('utm_campaign = ht36');
    expect(semCampanha.projeto).toBe('ht36');
  });
  it('capa do modelo troca o nome só se ainda for o do modelo anterior', () => {
    const quentes = modeloFunil('quentes')!;
    const checkout = modeloFunil('checkout')!;
    const a = capaDoModelo(funil({ nome: '' }), quentes, '');
    expect(a).toMatchObject({ nome: quentes.nome, icone: 'flame', tipo: 'manual' });
    const b = capaDoModelo(a, checkout, quentes.nome);
    expect(b).toMatchObject({ nome: checkout.nome, tipo: 'hotmart', icone: 'zap' });
    expect(b.eventosHotmart.length).toBeGreaterThan(0);
    expect(capaDoModelo(funil({ nome: 'Meu funil' }), checkout, quentes.nome).nome).toBe('Meu funil');
    expect(capaDoModelo(b, null, checkout.nome)).toMatchObject({ nome: '', tipo: 'manual', eventosHotmart: [], icone: 'kanban' });
  });
});

describe('boas práticas', () => {
  it('etapas do playbook com campanha da chave: tudo verde', () => {
    const f = funil({ projeto: 'hm-out26', campanhas: [{ id: 'c', nome: 'Captação', canal: 'utm', regra: 'utm_campaign = hm-out26', ativa: true, criadoEm: '' }] });
    const r = boasPraticas(f, vendedores);
    expect(r.filter((p) => p.situacao !== 'ok').map((p) => p.id)).toEqual([]);
  });
  it('ganho fora do fim e sem pagamento', () => {
    const es = etapasPadrao('t');
    const f = funil({ etapas: [es[5], es[0], es[1]] });
    expect(pratica(f, 'ganho_no_fim').situacao).toBe('pendente');
    expect(pratica(f, 'pagamento_antes_ganho').situacao).toBe('pendente');
  });
  it('entrada sem alerta e etapa sem critério', () => {
    const es = etapasPadrao('t').map((e, i) => (i === 0 ? { ...e, slaAtencaoMin: null, slaCriticoMin: null, criterio: '' } : e));
    const f = funil({ etapas: es });
    expect(pratica(f, 'alerta_entrada')).toMatchObject({ situacao: 'pendente', detalhe: expect.stringContaining(es[0].nome) });
    expect(pratica(f, 'criterio_escrito').situacao).toBe('pendente');
  });
  it('qualificação: pendente sem campo antes da oferta; não se aplica no funil automático', () => {
    const es = etapasPadrao('t').map((e) => ({ ...e, camposObrigatorios: [] }));
    expect(pratica(funil({ etapas: es }), 'qualificacao_antes_oferta').situacao).toBe('pendente');
    expect(pratica(funil({ etapas: es, tipo: 'hotmart', eventosHotmart: ['carrinho_abandonado'] }), 'qualificacao_antes_oferta').situacao).toBe('nao_se_aplica');
  });
  it('campanha sem a chave do projeto fica pendente', () => {
    const f = funil({ projeto: 'ht34', campanhas: [{ id: 'c', nome: 'Outra', canal: 'utm', regra: 'utm_campaign = ht33', ativa: true, criadoEm: '' }] });
    expect(pratica(f, 'campanha_com_chave').situacao).toBe('pendente');
    expect(pratica(funil(), 'campanha_com_chave').situacao).toBe('pendente');
  });
  it('distribuição própria precisa somar 100 entre os ativos', () => {
    expect(pratica(funil({ distribuicao: [{ vendedorId: 'v1', percentual: 70 }] }), 'distribuicao_100').situacao).toBe('pendente');
    expect(pratica(funil({ distribuicao: [{ vendedorId: 'v1', percentual: 70 }, { vendedorId: 'v2', percentual: 30 }] }), 'distribuicao_100').situacao).toBe('ok');
  });
  it('todo modelo pronto passa nas regras que travam salvar', () => {
    for (const m of MODELOS_FUNIL) {
      const f = aplicarPartida(capaDoModelo(funil(), m, ''), m, 'proj', m.id);
      expect(validarFunil(f, vendedores), m.id).toEqual([]);
    }
  });
});

describe('integrações e lista', () => {
  it('formulário aparece no funil manual; Hotmart, links, WhatsApp e Slack sempre', () => {
    const ids = (f: Parameters<typeof integracoesDoFunil>[0]) => integracoesDoFunil(f).map((i) => i.id);
    expect(ids({ tipo: 'manual', campanhas: [] })).toEqual(['hotmart', 'links', 'whatsapp', 'formulario', 'slack']);
    expect(ids({ tipo: 'hotmart', campanhas: [] })).toEqual(['hotmart', 'links', 'whatsapp', 'slack']);
  });
  it('agrupa por projeto: soltos primeiro', () => {
    const g = agruparPorProjeto([{ projeto: 'p1', id: 'a' }, { projeto: null, id: 'b' }, { projeto: 'p1', id: 'c' }, { projeto: 'p2', id: 'd' }]);
    expect(g.map((x) => [x.projeto, x.funis.map((f) => f.id)])).toEqual([[null, ['b']], ['p1', ['a', 'c']], ['p2', ['d']]]);
  });
  it('cadeia de etapas', () => {
    expect(cadeiaEtapas([{ nome: 'A' }, { nome: 'B' }])).toBe('A → B');
  });
  it('resumo conta em negociação (negociar + pagamento)', () => {
    const base = { status: 'aberto', valor: 100, donoId: 'v1', proximaAtividade: null, etapaDesde: new Date().toISOString(), sla: null } as unknown as Negocio;
    const r = resumoFunil([{ ...base, etapa: 'negociar' }, { ...base, etapa: 'aguardar_pagamento' }, { ...base, etapa: 'qualificar' }], new Date());
    expect(r).toMatchObject({ emNegociacao: 2, valorNegociacao: 200, abertos: 3 });
  });
});
