import { describe, expect, it } from 'vitest';
import { etapaDe, montarEsteira, type MapaAluno } from './mapa-alunos';

const a = (o: Partial<MapaAluno>): MapaAluno => ({
  pessoa_chave: 'x', nome: 'N', email: 'n@x', emails: ['n@x'], telefone: null, programa: 'programa', situacao: 'quitado',
  entrou_programa_em: null, primeira_compra_em: null, primeira_compra: null, origem_sck: null, canal: null, vendedor: null,
  turma: null, no_gps: false, contato_hm_id: null, status_card: null, pago_vida: 0, pago_programa: 0, sinal_pago: 0,
  pacote: 15000, falta_pagar: 0, parcelas_devidas: 0, valor_devido: 0, ultimo_pagamento_em: null, ultima_tentativa_em: null,
  veio_do_acelera: false, honorarios_contratados: 0, segunda_metade_liberada: false, ...o,
});

describe('esteira do Programa', () => {
  it('cada pessoa cai numa etapa só', () => {
    expect(etapaDe(a({ programa: 'so_sinal', situacao: 'so_sinal' }))).toBe('so_sinal');
    expect(etapaDe(a({ programa: 'so_sinal', situacao: 'atrasado' }))).toBe('atrasado');
    expect(etapaDe(a({ situacao: 'em_dia' }))).toBe('em_dia');
    expect(etapaDe(a({ situacao: 'cancelado' }))).toBe('cancelado');
    expect(etapaDe(a({ programa: 'hm_antigo', situacao: 'sem_divida' }))).toBe('fora');
  });
  it('soma pessoas, pago e a receber (cancelado não entra no a receber)', () => {
    const e = montarEsteira([
      a({ programa: 'so_sinal', situacao: 'so_sinal', pago_programa: 300, falta_pagar: 14700 }),
      a({ programa: 'so_sinal', situacao: 'so_sinal', pago_programa: 697, falta_pagar: 14303 }),
      a({ situacao: 'cancelado', falta_pagar: 14700 }),
    ]);
    const s = e.find((x) => x.etapa === 'so_sinal')!;
    expect(s.pessoas).toBe(2); expect(s.pago).toBe(997); expect(s.aReceber).toBe(29003);
    expect(e.find((x) => x.etapa === 'cancelado')!.aReceber).toBe(0);
  });
});
