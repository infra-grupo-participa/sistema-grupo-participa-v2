import { describe, expect, it } from 'vitest';
import { etapasPadrao } from './funis';
import { motivoSomenteLeitura, podeMexerNoNegocio, podeTrocarDono, travaMover } from './travas';
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
  it('dono mexe; vendedor não mexe no de outro dono', () => {
    expect(podeMexerNoNegocio({ donoId: 'ana' }, ana)).toBe(true);
    expect(podeMexerNoNegocio({ donoId: 'bia' }, ana)).toBe(false);
  });
  it('negócio sem dono: só o gestor (o banco compara dono = eu)', () => {
    expect(podeMexerNoNegocio({ donoId: null }, ana)).toBe(false);
    expect(podeMexerNoNegocio({ donoId: null }, gestor)).toBe(true);
  });
  it('gestor mexe em qualquer um; sem sessão ninguém mexe', () => {
    expect(podeMexerNoNegocio({ donoId: 'bia' }, gestor)).toBe(true);
    expect(podeMexerNoNegocio({ donoId: 'ana' }, null)).toBe(false);
  });
});

describe('podeTrocarDono', () => {
  it('só o gestor', () => {
    expect(podeTrocarDono(gestor)).toBe(true);
    expect(podeTrocarDono(ana)).toBe(false);
    expect(podeTrocarDono(null)).toBe(false);
  });
});

describe('motivoSomenteLeitura', () => {
  it('explica de quem é, ou que está sem dono', () => {
    expect(motivoSomenteLeitura({ donoId: 'bia' }, ana, nomeDe)).toBe('Negócio de Bia: só o dono ou o gestor altera.');
    expect(motivoSomenteLeitura({ donoId: null }, ana, nomeDe)).toMatch(/sem dono/);
    expect(motivoSomenteLeitura({ donoId: 'ana' }, ana, nomeDe)).toBeNull();
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
  it('dono vem antes de tudo: vendedor nem vê os campos do negócio alheio', () => {
    const t = travaMover(neg({ donoId: 'bia' }), funil, 'e-negociar', ana, nomeDe);
    expect(t).toEqual({ permitido: false, motivo: 'Negócio de Bia: só o dono ou o gestor altera.', faltam: [] });
  });
});
