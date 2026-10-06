import { describe, expect, it } from 'vitest';
import type { Atividade, Conversa, FichaDisparo, Negocio, Vendedor } from '../../domain/types';
import {
  agruparPorUrgencia, cargaDe, cargaPorVendedor, controle9h, itensAgirAgora, negocioDoContato, nomeCurto, perspectiva, saudacao, VER_TIME,
} from './painel';

const AGORA = new Date('2026-10-05T18:00:00Z'); // 15h em Brasília
const min = (m: number) => new Date(AGORA.getTime() - m * 60000).toISOString();

const neg = (id: string, extra: Partial<Negocio> = {}): Negocio => ({
  id, contatoId: `c-${id}`, produto: 'hm', origem: 'venda_ativa', funilId: 'f', campanhaId: null, etapaId: 'e', etapaNome: 'Qualificar', etapa: 'qualificar', status: 'aberto', donoId: 'v-marcos',
  valor: 1000, campos: {}, motivoPerda: null, criadoEm: min(5000), etapaDesde: min(10), fechadoEm: null,
  proximaAtividade: { id: 'x', tipo: 'ligacao', titulo: 'x', venceEm: min(-60) }, ultimaInteracaoEm: null, ...extra,
});
const atv = (id: string, extra: Partial<Atividade> = {}): Atividade => ({
  id, negocioId: null, contatoId: 'c', donoId: 'v-marcos', tipo: 'ligacao', titulo: id, venceEm: min(-60),
  concluidaEm: null, resultado: null, cadenciaDia: null, ...extra,
});
const conv = (contatoId: string, naoLidas: number, atribuidaA: string | null): Conversa => ({
  contatoId, naoLidas, atribuidaA, janelaAteEm: null,
  ultimaMensagem: { id: 'm', contatoId, canal: 'whatsapp', direcao: 'entrada', texto: 'oi', em: min(30), status: null, autorId: null, templateId: null },
});

describe('painel de início', () => {
  it('agir agora: só o que é meu, do mais urgente para o menos', () => {
    const negocios = [
      neg('critico', { etapa: 'primeiro_contato', etapaDesde: min(20) }),
      neg('atencao', { etapa: 'primeiro_contato', etapaDesde: min(8) }),
      neg('ok'),
      neg('outro', { etapa: 'primeiro_contato', etapaDesde: min(60), donoId: 'v-ronan' }),
    ];
    const itens = itensAgirAgora({
      negocios,
      conversas: [conv('c-ok', 2, 'v-marcos'), conv('c-outro', 1, 'v-ronan'), conv('c-lida', 0, 'v-marcos')],
      atividades: [atv('atrasada', { venceEm: min(30), negocioId: 'ok' }), atv('hoje', { negocioId: 'ok' }), atv('amanha', { venceEm: min(-2000) })],
      donoId: 'v-marcos',
      agora: AGORA,
    });
    expect(itens.map((i) => i.id)).toEqual(['sla-critico', 'conv-c-ok', 'atv-atrasada', 'sla-atencao', 'atv-hoje']);
    expect(itens.find((i) => i.tipo === 'conversa')?.negocioId).toBe('ok');
    expect(agruparPorUrgencia(itens).map((g) => [g.urgencia, g.itens.map((i) => i.id)])).toEqual([
      ['atrasado', ['sla-critico', 'atv-atrasada']], ['agora', ['conv-c-ok', 'sla-atencao']], ['hoje', ['atv-hoje']],
    ]);
    // Gestor (null) vê o time.
    expect(itensAgirAgora({ negocios, conversas: [], atividades: [], donoId: null, agora: AGORA }).map((i) => i.id)).toContain('sla-outro');
  });

  it('negócio do contato prefere aberto e do dono', () => {
    const lista = [neg('a', { contatoId: 'c', status: 'perdido' }), neg('b', { contatoId: 'c', donoId: 'v-ronan' }), neg('d', { contatoId: 'c' })];
    expect(negocioDoContato(lista, 'c', 'v-marcos')?.id).toBe('d');
    expect(negocioDoContato(lista, 'zz', null)).toBeNull();
  });

  it('controle das 9h e carga', () => {
    const negocios = [
      neg('semdono', { donoId: null }),
      neg('semprox', { proximaAtividade: null }),
      neg('falha', { status: 'perdido', motivoPerda: 'ja_atendido_outro_vendedor', fechadoEm: min(60) }),
      neg('falha-antiga', { status: 'perdido', motivoPerda: 'ja_atendido_outro_vendedor', fechadoEm: min(3 * 1440) }),
    ];
    const fichas = [{ id: 'f1', status: 'aguardando_aprovacao' }, { id: 'f2', status: 'aprovada' }] as FichaDisparo[];
    const c = controle9h(negocios, fichas, AGORA);
    expect(c.semDono.map((n) => n.id)).toEqual(['semdono']);
    expect(c.semProximo.map((n) => n.id)).toEqual(['semprox']);
    expect(c.perdidosOutroVendedor.map((n) => n.id)).toEqual(['falha']);
    expect(c.fichasAguardando.map((f) => f.id)).toEqual(['f1']);

    const vendedores = [
      { id: 'v-marcos', ativo: true }, { id: 'v-ronan', ativo: true }, { id: 'v-x', ativo: false },
    ] as Vendedor[];
    const carga = cargaPorVendedor(negocios, [atv('a', { venceEm: min(5) })], vendedores, AGORA);
    expect(carga).toEqual([
      { vendedorId: 'v-marcos', abertos: 1, criticos: 0, semProximo: 1, atrasadas: 1 },
      { vendedorId: 'v-ronan', abertos: 0, criticos: 0, semProximo: 0, atrasadas: 0 },
    ]);
  });

  it('saudação pela hora de Brasília', () => {
    expect(saudacao(new Date('2026-10-05T11:00:00Z'))).toBe('Bom dia');
    expect(saudacao(AGORA)).toBe('Boa tarde');
    expect(saudacao(new Date('2026-10-05T23:00:00Z'))).toBe('Boa noite');
  });

  it('perspectiva: gestor escolhe, vendedor só vê o próprio', () => {
    const gestor = { vendedorId: 'v-jonathan', papel: 'gestor' as const };
    expect(perspectiva(gestor, VER_TIME)).toEqual({ donoId: null, painelDe: 'v-jonathan', deOutro: false });
    expect(perspectiva(gestor, 'v-ronan')).toEqual({ donoId: 'v-ronan', painelDe: 'v-ronan', deOutro: true });
    expect(perspectiva(gestor, 'v-jonathan').deOutro).toBe(false);
    expect(perspectiva({ vendedorId: 'v-marcos', papel: 'vendedor' }, 'v-ronan')).toEqual({ donoId: 'v-marcos', painelDe: 'v-marcos', deOutro: false });
    expect(nomeCurto('Jonathan Mendes')).toBe('Jonathan');
    expect(nomeCurto('Marcos Paulo')).toBe('Marcos Paulo');
  });

  it('carga de uma pessoa ou do time', () => {
    const negocios = [neg('a', { proximaAtividade: null }), neg('b', { donoId: 'v-ronan', etapa: 'primeiro_contato', etapaDesde: min(60) })];
    const atividades = [atv('x', { venceEm: min(5) }), atv('y', { venceEm: min(5), donoId: 'v-ronan' })];
    const conversas = [conv('c1', 2, 'v-marcos'), conv('c2', 0, 'v-marcos'), conv('c3', 1, null)];
    expect(cargaDe({ negocios, atividades, conversas, donoId: 'v-marcos', agora: AGORA }))
      .toEqual({ abertos: 1, criticos: 0, semProximo: 1, atrasadas: 1, conversasEsperando: 1 });
    expect(cargaDe({ negocios, atividades, conversas, donoId: null, agora: AGORA }))
      .toEqual({ abertos: 2, criticos: 1, semProximo: 1, atrasadas: 2, conversasEsperando: 1 });
  });
});
