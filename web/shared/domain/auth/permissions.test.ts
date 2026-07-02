import { describe, it, expect } from 'vitest';
import type { GpUser } from './gp-user';
import { buildGpUser } from './gp-user';
import { normalizeCargo } from './cargo';
import {
  ehDev, ehAdmin, ehAdminOuAcima, ehGestor, ehOperador, ehVisualizador,
  podeVer, podeEditar, temFuncao, podeVerCpf, mascarar,
} from './permissions';

const u = (p: Partial<GpUser>): GpUser => ({
  id: 'x', nome: 'Teste', email: 't@t.com', cargo: 'visualizador', status: 'ativo',
  setores: [], funcoes: [], podeVerCpf: false, time: null, avatarUrl: null, ...p,
});

describe('predicados de cargo', () => {
  it('identifica cada cargo', () => {
    expect(ehDev(u({ cargo: 'dev' }))).toBe(true);
    expect(ehAdmin(u({ cargo: 'admin' }))).toBe(true);
    expect(ehOperador(u({ cargo: 'operador' }))).toBe(true);
    expect(ehVisualizador(u({ cargo: 'visualizador' }))).toBe(true);
  });

  it('ehAdminOuAcima: dev e admin sim, demais não', () => {
    expect(ehAdminOuAcima(u({ cargo: 'dev' }))).toBe(true);
    expect(ehAdminOuAcima(u({ cargo: 'admin' }))).toBe(true);
    expect(ehAdminOuAcima(u({ cargo: 'gestor' }))).toBe(false);
    expect(ehAdminOuAcima(u({ cargo: 'operador' }))).toBe(false);
    expect(ehAdminOuAcima(null)).toBe(false);
  });

  it('ehGestor exige cargo gestor e, com setor, o setor atribuído', () => {
    const g = u({ cargo: 'gestor', setores: ['placas'] });
    expect(ehGestor(g)).toBe(true);
    expect(ehGestor(g, 'placas')).toBe(true);
    expect(ehGestor(g, 'depoimentos')).toBe(false);
    expect(ehGestor(u({ cargo: 'gestor', setores: [] }))).toBe(false);
    expect(ehGestor(u({ cargo: 'admin', setores: ['placas'] }), 'placas')).toBe(false);
  });
});

describe('podeVer', () => {
  it('dev/admin/visualizador veem qualquer setor', () => {
    expect(podeVer(u({ cargo: 'dev' }), 'placas')).toBe(true);
    expect(podeVer(u({ cargo: 'admin' }), 'placas')).toBe(true);
    expect(podeVer(u({ cargo: 'visualizador' }), 'placas')).toBe(true);
  });

  it('gestor/operador só veem setores atribuídos', () => {
    expect(podeVer(u({ cargo: 'gestor', setores: ['placas'] }), 'placas')).toBe(true);
    expect(podeVer(u({ cargo: 'gestor', setores: ['depoimentos'] }), 'placas')).toBe(false);
    expect(podeVer(u({ cargo: 'operador', setores: ['placas'] }), 'placas')).toBe(true);
    expect(podeVer(u({ cargo: 'operador', setores: [] }), 'placas')).toBe(false);
  });

  it('nega sem usuário ou sem setor', () => {
    expect(podeVer(null, 'placas')).toBe(false);
    expect(podeVer(u({ cargo: 'admin' }), '')).toBe(false);
  });
});

describe('podeEditar', () => {
  it('dev/admin editam qualquer setor; visualizador nunca', () => {
    expect(podeEditar(u({ cargo: 'dev' }), 'placas')).toBe(true);
    expect(podeEditar(u({ cargo: 'admin' }), 'placas')).toBe(true);
    expect(podeEditar(u({ cargo: 'visualizador' }), 'placas')).toBe(false);
  });

  it('gestor edita apenas setores atribuídos', () => {
    expect(podeEditar(u({ cargo: 'gestor', setores: ['placas'] }), 'placas')).toBe(true);
    expect(podeEditar(u({ cargo: 'gestor', setores: ['depoimentos'] }), 'placas')).toBe(false);
  });

  it('operador exige setor E função do setor', () => {
    expect(podeEditar(u({ cargo: 'operador', setores: ['placas'], funcoes: ['placas.avancar'] }), 'placas')).toBe(true);
    expect(podeEditar(u({ cargo: 'operador', setores: ['placas'], funcoes: [] }), 'placas')).toBe(false);
    expect(podeEditar(u({ cargo: 'operador', setores: [], funcoes: ['placas.avancar'] }), 'placas')).toBe(false);
  });

  it('nega null/setor vazio', () => {
    expect(podeEditar(null, 'placas')).toBe(false);
    expect(podeEditar(u({ cargo: 'admin' }), '')).toBe(false);
  });
});

describe('temFuncao', () => {
  it('dev/admin sempre; visualizador nunca', () => {
    expect(temFuncao(u({ cargo: 'admin' }), 'placas.avancar')).toBe(true);
    expect(temFuncao(u({ cargo: 'visualizador' }), 'placas.avancar')).toBe(false);
  });

  it('gestor herda pelas áreas; operador exige a função exata', () => {
    expect(temFuncao(u({ cargo: 'gestor', setores: ['placas'] }), 'placas.avancar')).toBe(true);
    expect(temFuncao(u({ cargo: 'gestor', setores: ['depoimentos'] }), 'placas.avancar')).toBe(false);
    expect(temFuncao(u({ cargo: 'operador', funcoes: ['placas.avancar'] }), 'placas.avancar')).toBe(true);
    expect(temFuncao(u({ cargo: 'operador', funcoes: ['placas.voltar'] }), 'placas.avancar')).toBe(false);
  });
});

describe('podeVerCpf / mascarar (LGPD)', () => {
  it('dev/admin ou flag explícita veem CPF completo', () => {
    expect(podeVerCpf(u({ cargo: 'admin' }))).toBe(true);
    expect(podeVerCpf(u({ cargo: 'operador', podeVerCpf: true }))).toBe(true);
    expect(podeVerCpf(u({ cargo: 'operador' }))).toBe(false);
    expect(podeVerCpf(null)).toBe(false);
  });

  it('mascarar preserva só os 4 últimos dígitos para quem não pode ver', () => {
    const viewer = u({ cargo: 'visualizador' });
    expect(mascarar(viewer, '123.456.789-01')).toBe('**********8901');
    expect(mascarar(viewer, '')).toBe('');
    expect(mascarar(u({ cargo: 'admin' }), '123.456.789-01')).toBe('123.456.789-01');
  });
});

describe('normalizeCargo / buildGpUser (dados reais do banco)', () => {
  it('cargo=admin prevalece mesmo com nivel_hierarquia divergente', () => {
    // Estado real encontrado na auditoria: 2 perfis com cargo=admin e nivel=visualizador.
    expect(normalizeCargo({ cargo: 'admin', nivel_hierarquia: 'visualizador' })).toBe('admin');
  });

  it('nivel_hierarquia promove quando cargo é legado', () => {
    expect(normalizeCargo({ cargo: null, nivel_hierarquia: 'admin_principal' })).toBe('admin');
    expect(normalizeCargo({ cargo: null, nivel_hierarquia: 'dev' })).toBe('dev');
    expect(normalizeCargo({ cargo: 'ativacao', nivel_hierarquia: null })).toBe('operador');
    expect(normalizeCargo({})).toBe('visualizador');
  });

  it('buildGpUser usa fallback areas→setores e deriva podeVerCpf', () => {
    const user = buildGpUser({ id: '1', cargo: 'gestor', areas: ['placas'], pode_ver_cpf_completo: false });
    expect(user.setores).toEqual(['placas']);
    expect(user.podeVerCpf).toBe(false);
    expect(buildGpUser({ id: '2', cargo: 'admin' }).podeVerCpf).toBe(true);
  });
});
