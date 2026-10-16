import { describe, expect, it } from 'vitest';
import type { LeadAtm } from '@/modules/infra/atm/domain/dashboard';
import { contarAptosGrupo, contarLeadsAcao, exibicaoCardIngressoGrupo, exibicaoCardLeads, motivoDeNaoValido, rotuloValidadeOferta, validadeDaOferta } from './leads';

function lead(parcial: Partial<LeadAtm> = {}): LeadAtm {
  return {
    id: 'x', pessoaId: null, dataHora: '2026-10-14T15:00:00Z', nome: 'N', email: 'a@b.com', telefone: null, teste: false,
    entrouGrupo: false, aluno: true, instrucao: 'THB', turma: 'T30', utmSource: null, estado: 'SP', listaOrigem: null,
    seminarioOrigem: null, noPreCheckout: null, comprou: null, ...parcial,
  };
}

describe('validade para a oferta', () => {
  it('quem está na lista de aptos é válido', () => {
    expect(validadeDaOferta(lead({ listaOrigem: 'lista_1' }))).toBe('sim');
    expect(validadeDaOferta(lead({ listaOrigem: 'lista_2' }))).toBe('sim');
    expect(validadeDaOferta(lead({ listaOrigem: 'lista_1_e_2' }))).toBe('sim');
  });
  it('fora da lista e retirado da lista não são válidos', () => {
    expect(validadeDaOferta(lead({ listaOrigem: 'fora_das_listas' }))).toBe('nao');
    expect(validadeDaOferta(lead({ listaOrigem: 'descartado' }))).toBe('nao');
  });
  it('sem lista carregada é "sem dado", nunca "não"', () => {
    expect(validadeDaOferta(lead({ listaOrigem: null }))).toBe('semDado');
    expect(rotuloValidadeOferta('semDado')).toBe('Sem dado');
  });
  it('explica o motivo de não ser válido', () => {
    expect(motivoDeNaoValido(lead({ listaOrigem: 'fora_das_listas' }))).toBe('E-mail fora da lista de aptos');
    expect(motivoDeNaoValido(lead({ listaOrigem: 'descartado' }))).toBe('Retirado da lista de aptos');
    expect(motivoDeNaoValido(lead({ listaOrigem: 'lista_1' }))).toBe('');
  });
});

describe('contagem de leads da ação', () => {
  it('separa gerais, válidos e fora da lista; o ingresso divide pelos válidos', () => {
    const c = contarLeadsAcao([
      lead({ listaOrigem: 'lista_1', entrouGrupo: true }),
      lead({ listaOrigem: 'lista_1', entrouGrupo: true }),
      lead({ listaOrigem: 'lista_1', entrouGrupo: false }),
      lead({ listaOrigem: 'lista_1', entrouGrupo: false }),
      lead({ listaOrigem: 'fora_das_listas', entrouGrupo: true }),
      lead({ listaOrigem: 'descartado', entrouGrupo: false }),
    ]);
    expect(c).toMatchObject({ gerais: 6, validos: 4, foraDaLista: 2, ingressoValidos: 2 });
    expect(c.ingressoValidosPct).toBe(50);
  });
  it('não conta teste', () => {
    const c = contarLeadsAcao([lead({ listaOrigem: 'lista_1' }), lead({ listaOrigem: 'lista_1', teste: true })]);
    expect(c.gerais).toBe(1);
    expect(c.validos).toBe(1);
  });
  it('sem lista de aptos carregada, válidos e ingresso ficam sem dado', () => {
    const c = contarLeadsAcao([lead(), lead()]);
    expect(c).toEqual({ gerais: 2, validos: null, foraDaLista: null, ingressoValidos: null, ingressoValidosPct: null });
  });
  it('sem fonte de grupo, o ingresso dos válidos fica sem dado', () => {
    const c = contarLeadsAcao([lead({ listaOrigem: 'lista_1', entrouGrupo: null })]);
    expect(c.validos).toBe(1);
    expect(c.ingressoValidos).toBeNull();
    expect(c.ingressoValidosPct).toBeNull();
  });
  it('lista carregada mas ninguém válido: sem divisão por zero', () => {
    const c = contarLeadsAcao([lead({ listaOrigem: 'fora_das_listas' })]);
    expect(c).toMatchObject({ validos: 0, ingressoValidos: 0, ingressoValidosPct: null });
  });
});

describe('cards do topo com leads válidos', () => {
  const c = contarLeadsAcao([
    lead({ listaOrigem: 'lista_1', entrouGrupo: true }), lead({ listaOrigem: 'lista_1', entrouGrupo: false }),
    lead({ listaOrigem: 'lista_1', entrouGrupo: true }), lead({ listaOrigem: 'lista_1', entrouGrupo: false }),
    lead({ listaOrigem: 'fora_das_listas', entrouGrupo: true }),
  ]);
  it('leads: o válido no card e o geral ao lado', () => {
    expect(exibicaoCardLeads('leads', { valor: 5, semDado: false }, c)).toEqual({ valor: 4, formato: 'inteiro', hint: 'válidos para a oferta · 5 gerais, 1 fora da lista' });
  });
  it('ingresso: o hint de leads válidos saiu (16/10) e o percentual continua', () => {
    expect(exibicaoCardLeads('ingressosGrupo', { valor: 3, semDado: false }, c)).toBeNull();
    expect(exibicaoCardLeads('percentualIngressoGrupo', { valor: 60, semDado: false }, c)).toMatchObject({ valor: 60, formato: 'percentual', hint: 'no geral · 50% sobre os leads válidos' });
  });
  it('sem lista de aptos, os cards seguem com o número do resumo', () => {
    const sem = contarLeadsAcao([lead(), lead()]);
    expect(exibicaoCardLeads('leads', { valor: 2, semDado: false }, sem)).toBeNull();
    expect(exibicaoCardLeads('ingressosGrupo', { valor: 1, semDado: false }, sem)).toBeNull();
  });
  it('outros cards não mudam', () => {
    expect(exibicaoCardLeads('cpl', { valor: 9, semDado: false }, c)).toBeNull();
  });
  it('ingresso: o geral no card e os aptos embaixo', () => {
    expect(contarAptosGrupo([{ apto: true }, { apto: false }, { apto: true }])).toBe(2);
    expect(exibicaoCardIngressoGrupo({ valor: 46, semDado: false }, 21)).toEqual({ valor: 46, formato: 'inteiro', hint: 'no geral · 21 aptos' });
    expect(exibicaoCardIngressoGrupo({ valor: 5, semDado: false }, 1)?.hint).toBe('no geral · 1 apto');
  });
  it('sem a coluna apto ou sem o geral, o card não inventa', () => {
    expect(contarAptosGrupo(null)).toBeNull();
    expect(contarAptosGrupo([{ apto: true }, { apto: null }])).toBeNull();
    expect(exibicaoCardIngressoGrupo({ valor: 46, semDado: false }, null)).toBeNull();
    expect(exibicaoCardIngressoGrupo({ valor: 0, semDado: true }, 3)).toBeNull();
  });
});
