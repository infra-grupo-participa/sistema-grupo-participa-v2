import { describe, expect, it } from 'vitest';
import { agruparPorEtapa, destinosPossiveis, filtrarNegocios, passoAtrasado, statusDaEtapa, validarMovimento, type Etapa, type Negocio } from './crm';

const etapas: Etapa[] = [
  { id: 1, nome: 'A contatar', ordem: 1, tipo: 'aberta', ativa: true },
  { id: 2, nome: 'Em contato', ordem: 2, tipo: 'aberta', ativa: true },
  { id: 3, nome: 'Ativado', ordem: 3, tipo: 'ganho', ativa: true },
  { id: 4, nome: 'Não ativado', ordem: 4, tipo: 'perdido', ativa: true },
  { id: 5, nome: 'Antiga', ordem: 5, tipo: 'aberta', ativa: false },
];
const e = (id: number) => etapas.find((x) => x.id === id)!;

const neg = (p: Partial<Negocio>): Negocio => ({
  id: 'n', pipeline_id: 1, etapa_id: 1, status: 'aberto', pessoa_id: 'p', pessoa: 'X', eh_aluno: false, situacao_pessoa: 'ativa',
  projeto_id: null, projeto: null, responsavel_id: null, responsavel: null, proximo_passo: null, proximo_passo_em: null,
  entrou_etapa_em: '2026-10-05T10:00:00Z', criado_em: '2026-10-05T10:00:00Z', fechado_em: null, motivo_perda: null, externo_tipo: null, ...p,
});

// Mesmos casos do passo 2 (movimento) e do passo 7 do ensaio 20261005o.
describe('crm: transições de etapa', () => {
  it('mesma etapa', () => expect(validarMovimento(e(1), e(1), false)).toBe('mesma_etapa'));
  it('etapa desativada', () => expect(validarMovimento(e(1), e(5), false)).toBe('etapa_inativa'));
  it('perda exige motivo', () => {
    expect(validarMovimento(e(1), e(4), false)).toBe('motivo_obrigatorio');
    expect(validarMovimento(e(1), e(4), true)).toBeNull();
  });
  it('fechado só volta para etapa aberta (reabrir)', () => {
    expect(validarMovimento(e(4), e(3), false)).toBe('reabrir_antes');
    expect(validarMovimento(e(3), e(4), true)).toBe('reabrir_antes');
    expect(validarMovimento(e(4), e(2), false)).toBeNull();
  });
  it('aberta para ganho e entre abertas', () => {
    expect(validarMovimento(e(2), e(3), false)).toBeNull();
    expect(validarMovimento(e(2), e(1), false)).toBeNull();
  });
  it('status da etapa', () => {
    expect(statusDaEtapa('aberta')).toBe('aberto');
    expect(statusDaEtapa('ganho')).toBe('ganho');
    expect(statusDaEtapa('perdido')).toBe('perdido');
  });
  it('destinos: de aberta vai a qualquer ativa; de fechada só a abertas', () => {
    expect(destinosPossiveis(etapas, e(1)).map((x) => x.id)).toEqual([2, 3, 4]);
    expect(destinosPossiveis(etapas, e(4)).map((x) => x.id)).toEqual([1, 2]);
  });
});

describe('crm: quadro e filtros', () => {
  it('uma coluna por etapa ativa, na ordem; inativa só aparece se tiver negócio', () => {
    expect(agruparPorEtapa(etapas, [neg({ etapa_id: 2 })]).map((c) => [c.etapa.id, c.itens.length])).toEqual([[1, 0], [2, 1], [3, 0], [4, 0]]);
    expect(agruparPorEtapa(etapas, [neg({ etapa_id: 5 })]).map((c) => c.etapa.id)).toEqual([1, 2, 3, 4, 5]);
  });
  it('próximo passo atrasado só em negócio aberto com data antes de hoje', () => {
    expect(passoAtrasado(neg({ proximo_passo_em: '2026-10-04' }), '2026-10-05')).toBe(true);
    expect(passoAtrasado(neg({ proximo_passo_em: '2026-10-05' }), '2026-10-05')).toBe(false);
    expect(passoAtrasado(neg({ proximo_passo_em: '2026-10-01', status: 'ganho' }), '2026-10-05')).toBe(false);
    expect(passoAtrasado(neg({}), '2026-10-05')).toBe(false);
  });
  it('filtro por projeto e responsável', () => {
    const l = [neg({ id: 'a', projeto_id: 1, responsavel_id: 'v' }), neg({ id: 'b', projeto_id: 2 }), neg({ id: 'c', projeto_id: 1 })];
    expect(filtrarNegocios(l, { projeto: 1 }).map((n) => n.id)).toEqual(['a', 'c']);
    expect(filtrarNegocios(l, { responsavel: 'v' }).map((n) => n.id)).toEqual(['a']);
    expect(filtrarNegocios(l, { semResponsavel: true }).map((n) => n.id)).toEqual(['b', 'c']);
  });
});
