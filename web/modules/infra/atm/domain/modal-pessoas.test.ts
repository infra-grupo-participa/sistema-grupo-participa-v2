import { describe, expect, it } from 'vitest';
import type { NumeroGrupoAtm } from './dashboard';
import { chaveGrupoAtm, contadorDoModalAtm, cruzarComGrupoAtm, diaEmSaoPaulo, distribuicaoAtm, serieDiariaAtm, vendasNoPeriodoAtm } from './modal-pessoas';

const numero = (foneKey: string, entrouEm: string | null, extra: Partial<NumeroGrupoAtm> = {}): NumeroGrupoAtm => ({ foneKey, nome: null, entrouEm, saiuEm: null, noGrupo: true, ehLead: true, teste: false, testeMotivo: null, ...extra });

describe('modal de pessoas do ATM: regras puras', () => {
  it('contador conta só quem não é teste', () => {
    expect(contadorDoModalAtm([{ teste: false }, { teste: true }, { teste: false }])).toBe(2);
    expect(contadorDoModalAtm([])).toBe(0);
  });

  it('dia em São Paulo, inclusive na virada do dia em UTC', () => {
    expect(diaEmSaoPaulo('2026-10-14T02:59:00Z')).toBe('2026-10-13');
    expect(diaEmSaoPaulo('2026-10-14T03:00:00Z')).toBe('2026-10-14');
    expect(diaEmSaoPaulo('2026-10-14')).toBe('2026-10-14');
    expect(diaEmSaoPaulo(null)).toBeNull();
    expect(diaEmSaoPaulo('lixo')).toBeNull();
  });

  it('vendas no período: limites inclusivos e nulo sem limite', () => {
    const v = (aprovadoEm: string | null) => ({ aprovadoEm });
    const lista = [v('2026-10-07T03:00:00Z'), v('2026-10-15T02:59:00Z'), v('2026-10-07T02:59:00Z'), v(null)];
    expect(vendasNoPeriodoAtm(lista, '2026-10-07', '2026-10-14')).toHaveLength(2);
    expect(vendasNoPeriodoAtm(lista, null, null)).toHaveLength(3);
  });

  it('chave do grupo = 8 últimos dígitos da chave de telefone (regra do banco: fone8)', () => {
    expect(chaveGrupoAtm('+55 (11) 98765-4321')).toBe('87654321');
    expect(chaveGrupoAtm('1187654321')).toBe('87654321');
    expect(chaveGrupoAtm('551187654321')).toBe('87654321');
    expect(chaveGrupoAtm('1234')).toBeNull();
    expect(chaveGrupoAtm(null)).toBeNull();
  });

  it('cruzamento com o grupo: casa pelo telefone, separa sem telefone e fica com a primeira entrada', () => {
    const pessoas = [{ id: 'a', tel: '+55 11 98765-4321' }, { id: 'b', tel: '11 3333-2222' }, { id: 'c', tel: null }];
    const numeros = [numero('1187654321', '2026-10-09T12:00:00Z'), numero('2187654321', '2026-10-08T12:00:00Z', { noGrupo: false })];
    const m = cruzarComGrupoAtm(pessoas, (p) => p.tel, numeros);
    expect(m.get('a')).toEqual({ semTelefone: false, numero: numeros[1] });
    expect(m.get('b')).toEqual({ semTelefone: false, numero: null });
    expect(m.get('c')).toEqual({ semTelefone: true });
  });

  it('série diária: sem teste, dias vazios com zero, eixo no período limitado a hoje', () => {
    const itens = [{ teste: false, d: '2026-10-08T15:00:00Z' }, { teste: false, d: '2026-10-08T16:00:00Z' }, { teste: true, d: '2026-10-09T15:00:00Z' }, { teste: false, d: '2026-10-10T15:00:00Z' }];
    expect(serieDiariaAtm(itens, (i) => i.d, '2026-10-07', '2026-10-14', '2026-10-11')).toEqual([
      { dia: '2026-10-07', quantidade: 0 }, { dia: '2026-10-08', quantidade: 2 }, { dia: '2026-10-09', quantidade: 0 },
      { dia: '2026-10-10', quantidade: 1 }, { dia: '2026-10-11', quantidade: 0 },
    ]);
    expect(serieDiariaAtm<{ teste: boolean }>([], () => null)).toEqual([]);
    // soma da série = contador do modal
    const serie = serieDiariaAtm(itens, (i) => i.d, null, null, null);
    expect(serie.reduce((s, d) => s + d.quantidade, 0)).toBe(contadorDoModalAtm(itens));
  });

  it('distribuição: sem teste, rótulo exato da fonte, ordem por quantidade', () => {
    const itens = [{ teste: false, s: 'APPROVED' }, { teste: false, s: 'COMPLETE' }, { teste: false, s: 'APPROVED' }, { teste: true, s: 'REFUNDED' }];
    expect(distribuicaoAtm(itens, (i) => i.s)).toEqual([{ rotulo: 'APPROVED', quantidade: 2 }, { rotulo: 'COMPLETE', quantidade: 1 }]);
  });
});
