import { describe, expect, it } from 'vitest';
import { bloqueioMoverNoFunil, camposFaltandoNoFunil, etapasPadrao, fmtMinutos, podeRemoverEtapa, validarFunil } from './funis';
import type { Funil, Vendedor } from './types';

const vend: Vendedor[] = [
  { id: 'a', nome: 'A', sigla: 'A', papel: 'vendedor', ativo: true, percentual: 50, disparaApi: false },
  { id: 'b', nome: 'B', sigla: 'B', papel: 'vendedor', ativo: true, percentual: 50, disparaApi: false },
];
const funil = (p: Partial<Funil> = {}): Funil => ({
  id: 'f', nome: 'Venda ativa', icone: 'kanban', projeto: null, agrupadorId: 'ag', produto: 'hm', tipo: 'manual', eventosHotmart: [], etapas: etapasPadrao(),
  campanhas: [], distribuicao: null, ativo: true, criadoEm: '2026-10-05T00:00:00Z', ...p,
});

describe('validarFunil', () => {
  it('o funil padrão é válido', () => {
    expect(validarFunil(funil(), vend)).toEqual([]);
  });
  it('exige nome, agrupador e evento no automático', () => {
    const p = validarFunil(funil({ nome: ' ', agrupadorId: '', tipo: 'hotmart' }), vend).map((x) => x.campo);
    expect(p).toEqual(expect.arrayContaining(['nome', 'agrupador', 'eventos']));
  });
  it('exatamente uma etapa de Ganho, e ela é a última', () => {
    const e = etapasPadrao();
    expect(validarFunil(funil({ etapas: e.slice(0, 5) }), vend)[0].msg).toMatch(/exatamente uma/);
    expect(validarFunil(funil({ etapas: [e[5], ...e.slice(0, 5)] }), vend)[0].msg).toMatch(/última/);
  });
  it('nomes repetidos e alertas incoerentes', () => {
    const e = etapasPadrao();
    e[1].nome = e[0].nome;
    e[2].slaAtencaoMin = 100; e[2].slaCriticoMin = 50;
    const msgs = validarFunil(funil({ etapas: e }), vend).map((x) => x.msg).join(' ');
    expect(msgs).toMatch(/mesmo nome/);
    expect(msgs).toMatch(/crítico precisa vir depois/);
  });
  it('distribuição própria soma 100% entre ativos', () => {
    expect(validarFunil(funil({ distribuicao: [{ vendedorId: 'a', percentual: 70 }] }), vend)[0].campo).toBe('distribuicao');
    expect(validarFunil(funil({ distribuicao: [{ vendedorId: 'a', percentual: 70 }, { vendedorId: 'b', percentual: 30 }] }), vend)).toEqual([]);
  });
});

describe('mover no funil personalizado', () => {
  const f = funil();
  it('campos das etapas anteriores contam', () => {
    expect(camposFaltandoNoFunil({ campos: {} }, f, 'e-negociar')).toEqual(expect.arrayContaining(['perfil_profissional', 'objecao_principal']));
  });
  it('etapa de ganho só pela Hotmart; etapa inexistente; encerrado', () => {
    expect(bloqueioMoverNoFunil({ campos: {}, status: 'aberto' }, f, 'e-fechado')).toBe('ganho_so_com_pagamento');
    expect(bloqueioMoverNoFunil({ campos: {}, status: 'aberto' }, f, 'x')).toBe('etapa_inexistente');
    expect(bloqueioMoverNoFunil({ campos: {}, status: 'ganho' }, f, 'e-qualificar')).toBe('negocio_encerrado');
  });
  it('etapa com negócio aberto não pode ser removida', () => {
    expect(podeRemoverEtapa('e1', [{ etapaId: 'e1', status: 'aberto' }])).toBe(false);
    expect(podeRemoverEtapa('e1', [{ etapaId: 'e1', status: 'perdido' }])).toBe(true);
  });
});

describe('fmtMinutos', () => {
  it('min, h e dias', () => {
    expect([5, 90, 24 * 60, 7 * 24 * 60, null].map(fmtMinutos)).toEqual(['5 min', '2 h', '1 dia', '7 dias', '—']);
  });
});
