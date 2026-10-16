import { describe, expect, it } from 'vitest';
import { etapasPadrao } from './funis';
import {
  motivoSemEscrita, motivoSemNovoNegocio, motivoSomenteLeitura, MSG_SOMENTE_LEITURA, podeAbrirNegocioPara, podeConcluirAtividade, podeEscrever, podeEscreverContato, podeMexerNoNegocio, podePuxarNegocio, podeTrocarDono,
  operaComoGestor, somenteLeitura, travaMover, veComoGestor,
} from './travas';
import type { Funil, Negocio, SessaoComercial } from './types';

const funil: Funil = {
  id: 'f', nome: 'Venda ativa', icone: 'kanban', projeto: null, agrupadorId: 'ag', produto: 'hm', tipo: 'manual', eventosHotmart: [],
  etapas: etapasPadrao(), campanhas: [], distribuicao: null, ativo: true, criadoEm: '2026-10-05T00:00:00Z',
};
const gestor: SessaoComercial = { vendedorId: 'g', papel: 'gestor' };
const ana: SessaoComercial = { vendedorId: 'ana', papel: 'vendedor' };
const nomeDe = (id: string | null) => (id === 'bia' ? 'Bia' : id ?? 'Sem dono');
const neg = (p: Partial<Negocio> = {}): Pick<Negocio, 'donoId' | 'campos' | 'status' | 'etapaId'> => ({
  donoId: 'ana', campos: {}, status: 'aberto', etapaId: 'e-primeiro_contato', ...p,
});

describe('podeMexerNoNegocio (espelho de "Este negócio não é seu.")', () => {
  it('gestor mexe em qualquer um; sem sessão ninguém mexe', () => {
    expect(podeMexerNoNegocio({ donoId: 'bia' }, gestor)).toBe(true);
    expect(podeMexerNoNegocio({ donoId: 'ana' }, null)).toBe(false);
  });
});

describe('podePuxarNegocio', () => {
  const luis = { vendedorId: 'luis', papel: 'vendedor' as const, funisVeTodos: ['f-thb'] };
  it('vendedor puxa negócio de outro só no funil liberado', () => {
    expect(podePuxarNegocio({ donoId: 'jonathan', funilId: 'f-thb' }, luis)).toBe(true);
    expect(podePuxarNegocio({ donoId: null, funilId: 'f-thb' }, luis)).toBe(true);
    expect(podePuxarNegocio({ donoId: 'jonathan', funilId: 'outro' }, luis)).toBe(false);
    expect(podePuxarNegocio({ donoId: 'luis', funilId: 'f-thb' }, luis)).toBe(false);
  });
  it('sem funil liberado, gestor, leitor ou sem sessão: não', () => {
    expect(podePuxarNegocio({ donoId: 'jonathan', funilId: 'f-thb' }, ana)).toBe(false);
    expect(podePuxarNegocio({ donoId: 'jonathan', funilId: 'f-thb' }, { ...luis, papel: 'leitor' })).toBe(false);
    expect(podePuxarNegocio({ donoId: 'jonathan', funilId: 'f-thb' }, null)).toBe(false);
  });
});

describe('travaMover', () => {
  it('libera quando os campos da etapa estão preenchidos', () => {
    const campos = { perfil_profissional: 'advogado', atua_com_holding: 'sim', produto_interesse: 'hm' };
    expect(travaMover(neg({ campos }), funil, 'e-qualificar', ana, nomeDe)).toEqual({ permitido: true, motivo: null, faltam: [] });
  });
  it('lista os campos obrigatórios que faltam (inclui os das etapas puladas)', () => {
    const t = travaMover(neg(), funil, 'e-negociar', ana, nomeDe);
    expect(t.permitido).toBe(false);
    expect(t.faltam).toHaveLength(4);
    expect(t.motivo).toMatch(/^Falta preencher: /);
  });
  it('com os campos preenchidos, passa', () => {
    const campos = { perfil_profissional: 'advogado', atua_com_holding: 'sim', produto_interesse: 'hm', objecao_principal: 'preço' };
    expect(travaMover(neg({ campos }), funil, 'e-negociar', ana, nomeDe).permitido).toBe(true);
  });
  it('ganho só pela Hotmart; encerrado não muda; etapa atual não conta', () => {
    expect(travaMover(neg(), funil, 'e-fechado', gestor, nomeDe).motivo).toMatch(/Hotmart/);
    expect(travaMover(neg({ status: 'perdido' }), funil, 'e-negociar', gestor, nomeDe).motivo).toMatch(/encerrado/);
    expect(travaMover(neg(), funil, 'e-primeiro_contato', ana, nomeDe).permitido).toBe(false);
    expect(travaMover(neg(), funil, 'x', ana, nomeDe).motivo).toMatch(/não existe/);
  });
});

describe('podeConcluirAtividade (espelho de "Esta atividade não é sua.")', () => {
  it('já concluída ou sem sessão: ninguém', () => {
    expect(podeConcluirAtividade({ donoId: 'ana', concluidaEm: '2026-10-06T12:00:00Z' }, ana)).toBe(false);
    expect(podeConcluirAtividade({ donoId: 'ana', concluidaEm: null }, null)).toBe(false);
  });
});

describe('podeAbrirNegocioPara (espelho de crm.pode_ver_pessoa em crm_criar_negocio)', () => {
  it('contato meu ou sem dono: abre', () => {
    expect(podeAbrirNegocioPara({ donoId: 'ana' }, [], ana)).toBe(true);
    expect(podeAbrirNegocioPara({ donoId: null }, [], ana)).toBe(true);
  });
});

describe('podeEscreverContato (espelho de crm.pode_escrever_pessoa em crm_enviar_mensagem)', () => {
  const vend = { vendedorId: 'v1', papel: 'vendedor' as const };
  const gest = { vendedorId: 'g1', papel: 'gestor' as const };
  it('gestor escreve para qualquer contato, inclusive sem dono', () => {
    expect(podeEscreverContato({ donoId: null }, [], gest)).toBe(true);
    expect(podeEscreverContato({ donoId: 'v2' }, [], gest)).toBe(true);
  });
  it('vendedor: dono do contato ou dono de algum negócio da pessoa', () => {
    expect(podeEscreverContato({ donoId: 'v1' }, [], vend)).toBe(true);
    expect(podeEscreverContato({ donoId: 'v2' }, [{ donoId: 'v1' }], vend)).toBe(true);
    expect(podeEscreverContato({ donoId: null }, [{ donoId: 'v1' }], vend)).toBe(true);
  });
  it('sem sessão não escreve', () => {
    expect(podeEscreverContato({ donoId: 'v1' }, [], null)).toBe(false);
  });
});

describe('leitor (admin/dev fora do Comercial, 20261008151801): vê tudo, não escreve nada', () => {
  const leitor: SessaoComercial = { vendedorId: 'l', papel: 'leitor' };
  it('nenhuma trava de escrita libera o leitor, nem em negócio sem dono ou "dele"', () => {
    expect(podeMexerNoNegocio({ donoId: 'l' }, leitor)).toBe(false);
    expect(podeMexerNoNegocio({ donoId: null }, leitor)).toBe(false);
    expect(podeTrocarDono(leitor)).toBe(false);
    expect(podeConcluirAtividade({ donoId: 'l', concluidaEm: null }, leitor)).toBe(false);
    expect(podeAbrirNegocioPara({ donoId: null }, [], leitor)).toBe(false);
    expect(podeEscreverContato({ donoId: null }, [], leitor)).toBe(false);
    expect(travaMover(neg({ donoId: null }), funil, 'e-qualificar', leitor, nomeDe).permitido).toBe(false);
  });
  it('as frases dizem "Acesso só de leitura." (a mesma do banco)', () => {
    expect(motivoSomenteLeitura({ donoId: 'ana' }, leitor, nomeDe)).toBe(MSG_SOMENTE_LEITURA);
    expect(motivoSemNovoNegocio({ donoId: 'ana' }, [], leitor, nomeDe)).toBe(MSG_SOMENTE_LEITURA);
    expect(motivoSemEscrita({ donoId: null }, [], leitor, nomeDe)).toBe(MSG_SOMENTE_LEITURA);
    expect(MSG_SOMENTE_LEITURA).toBe('Acesso só de leitura.');
  });
  it('somenteLeitura / podeEscrever / veComoGestor', () => {
    expect([somenteLeitura(leitor), somenteLeitura(gestor), somenteLeitura(ana), somenteLeitura(null)]).toEqual([true, false, false, false]);
    expect([podeEscrever(leitor), podeEscrever(gestor), podeEscrever(ana), podeEscrever(null)]).toEqual([false, true, true, false]);
    expect([veComoGestor(leitor), veComoGestor(gestor), veComoGestor(ana), veComoGestor(undefined)]).toEqual([true, true, false, false]);
  });
});

describe('20261017000300: vendedor opera como gestor (crm.eh_operador)', () => {
  const ana: SessaoComercial = { vendedorId: 'ana', papel: 'vendedor' };
  it('mexe, arrasta e troca dono em negócio de outro e sem dono', () => {
    expect(podeMexerNoNegocio({ donoId: 'bia' }, ana)).toBe(true);
    expect(podeMexerNoNegocio({ donoId: null }, ana)).toBe(true);
    expect(motivoSomenteLeitura({ donoId: 'bia' }, ana, () => 'Bia')).toBeNull();
    expect(podeTrocarDono(ana)).toBe(true);
    expect(operaComoGestor(ana)).toBe(true);
    expect(operaComoGestor({ vendedorId: 'l', papel: 'leitor' })).toBe(false);
  });
  it('conclui atividade, abre negócio e escreve para contato de outro e sem dono', () => {
    expect(podeConcluirAtividade({ donoId: 'bia', concluidaEm: null }, ana)).toBe(true);
    expect(podeAbrirNegocioPara({ donoId: 'bia' }, [], ana)).toBe(true);
    expect(podeEscreverContato({ donoId: 'bia' }, [], ana)).toBe(true);
    expect(podeEscreverContato({ donoId: null }, [], ana)).toBe(true);
  });
});
