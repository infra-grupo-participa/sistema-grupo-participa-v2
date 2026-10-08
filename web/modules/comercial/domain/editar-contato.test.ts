import { describe, expect, it } from 'vitest';
import { mudancasEdicao, rascunhoDe, semNome, validarEdicao, type RascunhoEdicao } from './editar-contato';
import { motivoSemEdicao, podeEditarContato } from './travas';

const base = {
  nome: 'Ana Souza', email: 'ana@exemplo.com', telefone: '11987654321', cidade: 'Campinas', uf: 'SP',
  perfil: 'advogado' as const, atuaComHolding: null, empresa: null, observacao: null,
};
const r0: RascunhoEdicao = rascunhoDe(base);

describe('semNome', () => {
  it('reconhece o "(sem nome)" do banco e vazio', () => {
    expect(semNome('(sem nome)')).toBe(true);
    expect(semNome('  ')).toBe(true);
    expect(semNome(null)).toBe(true);
    expect(semNome('Ana')).toBe(false);
  });
});

describe('rascunhoDe', () => {
  it('não usa "(sem nome)" nem valor mascarado como ponto de partida', () => {
    const r = rascunhoDe({ ...base, nome: '(sem nome)', email: 'a***@exemplo.com', telefone: '*******4321' });
    expect(r.nome).toBe('');
    expect(r.email).toBe('');
    expect(r.telefone).toBe('');
  });
  it('null vira campo vazio', () => {
    expect(r0.empresa).toBe('');
    expect(r0.atuaComHolding).toBe('');
  });
});

describe('validarEdicao', () => {
  it('nome obrigatório (2+)', () => {
    expect(validarEdicao({ ...r0, nome: 'A' })).toBe('Informe o nome.');
    expect(validarEdicao(r0)).toBeNull();
  });
  it('e-mail, telefone e UF', () => {
    expect(validarEdicao({ ...r0, email: 'ana@' })).toBe('E-mail inválido.');
    expect(validarEdicao({ ...r0, telefone: '9876' })).toMatch(/Telefone inválido/);
    expect(validarEdicao({ ...r0, telefone: '' })).toBeNull();
    expect(validarEdicao({ ...r0, uf: 'São Paulo' })).toMatch(/UF inválida/);
    expect(validarEdicao({ ...r0, uf: 'rj' })).toBeNull();
  });
  it('limite da observação', () => {
    expect(validarEdicao({ ...r0, observacao: 'x'.repeat(1001) })).toMatch(/Observação longa/);
  });
});

describe('mudancasEdicao', () => {
  it('nada mudou = objeto vazio (formatação do telefone e caixa do e-mail não contam)', () => {
    expect(mudancasEdicao(r0, { ...r0, telefone: '(11) 98765-4321', email: 'ANA@exemplo.com ', uf: 'sp' })).toEqual({});
  });
  it('manda só o que mudou, com UF em maiúsculas', () => {
    expect(mudancasEdicao(r0, { ...r0, nome: ' Ana Paula ', uf: 'rj', perfil: 'contador' }))
      .toEqual({ nome: 'Ana Paula', uf: 'RJ', perfil: 'contador' });
  });
  it('apagar manda vazio (o banco volta ao dado da base)', () => {
    expect(mudancasEdicao(r0, { ...r0, cidade: '' })).toEqual({ cidade: '' });
  });
});

describe('podeEditarContato / motivoSemEdicao (espelho de crm.pode_escrever_pessoa)', () => {
  const nomeDe = (id: string | null) => (id === 'v2' ? 'Jusy' : '?');
  const vendedor = { vendedorId: 'v1', papel: 'vendedor' as const };
  it('dono e gestor editam; leitor não', () => {
    expect(podeEditarContato({ donoId: 'v1' }, [], vendedor)).toBe(true);
    expect(podeEditarContato({ donoId: 'v2' }, [], { vendedorId: 'g', papel: 'gestor' })).toBe(true);
    expect(motivoSemEdicao({ donoId: 'v1' }, [], { vendedorId: 'l', papel: 'leitor' }, nomeDe)).toBe('Acesso só de leitura.');
  });
  it('vendedor não edita contato de outro dono, a menos que seja dono de negócio da pessoa', () => {
    expect(motivoSemEdicao({ donoId: 'v2' }, [], vendedor, nomeDe)).toBe('Contato de Jusy: só o dono ou o gestor edita.');
    expect(podeEditarContato({ donoId: 'v2' }, [{ donoId: 'v1' }], vendedor)).toBe(true);
  });
  it('sem dono e sem negócio dele: só o gestor', () => {
    expect(motivoSemEdicao({ donoId: null }, [], vendedor, nomeDe)).toBe('Contato sem dono: só o gestor edita.');
  });
});
