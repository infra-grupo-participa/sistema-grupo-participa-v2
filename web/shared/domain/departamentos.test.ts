import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { Cargo, GpUser } from './auth';
import { BASE_MARKETING, DEPARTAMENTOS, MODULO_DEPARTAMENTO, departamento, departamentoDaRota, podeVerDepartamento } from './departamentos';

const user = (cargo: Cargo, setores: string[] = []): GpUser =>
  ({ id: 'u', email: 'x@advmais.com', nome: 'X', cargo, status: 'ativo', setores, funcoes: [], podeVerCpf: false, time: null, avatarUrl: null });

describe('departamentos: registro', () => {
  it('os 5 departamentos da decisão de 05/10/2026, nesta ordem', () => {
    expect(DEPARTAMENTOS.map((d) => d.label)).toEqual(['Educacional', 'Marketing', 'Comercial', 'Financeiro', 'Infra']);
  });
  it('Comercial, Financeiro e Infra estão "Em breve"; Educacional e Marketing ativos', () => {
    const st = Object.fromEntries(DEPARTAMENTOS.map((d) => [d.key, d.status]));
    expect(st).toEqual({ educacional: 'ativo', marketing: 'ativo', comercial: 'em_breve', financeiro: 'em_breve', infra: 'em_breve' });
  });
  it('Marketing tem as 5 áreas em /marketing/<area>: Web ativa, as outras "Em breve"', () => {
    const mkt = departamento('marketing');
    expect(mkt.areas.map((a) => a.label)).toEqual(['Web', 'Mensageria', 'Tráfego', 'Audiovisual', 'Social Media']);
    for (const a of mkt.areas) {
      expect(a.status).toBe(a.key === 'web' ? 'ativo' : 'em_breve');
      expect(a.path).toBe(`/marketing/${a.key}`);
    }
  });
  it('Educacional e Comercial não têm áreas', () => {
    expect(departamento('educacional').areas).toEqual([]);
    expect(departamento('comercial').areas).toEqual([]);
  });
  it('cada pasta de web/modules tem departamento declarado', () => {
    const pastas = readdirSync(join(__dirname, '..', '..', 'modules'), { withFileTypes: true })
      .filter((d) => d.isDirectory()).map((d) => d.name);
    for (const p of pastas) expect(MODULO_DEPARTAMENTO[p], `módulo sem departamento: ${p}`).toBeTruthy();
  });
  it('departamentoDaRota', () => {
    expect(departamentoDaRota('/educacional/placas')).toBe('educacional');
    expect(departamentoDaRota('/marketing/mensageria')).toBe('marketing');
    expect(departamentoDaRota('/financeiro')).toBe('financeiro');
    expect(departamentoDaRota('/')).toBeNull();
    expect(departamentoDaRota('/usuarios')).toBeNull();
    expect(departamentoDaRota('/educacionalx')).toBeNull();
  });
});

describe('departamentos: Marketing bloqueado até os níveis de acesso serem desenhados', () => {
  it('admin e dev veem o Marketing', () => {
    expect(podeVerDepartamento(user('admin'), 'marketing')).toBe(true);
    expect(podeVerDepartamento(user('dev'), 'marketing')).toBe(true);
  });
  it('visualizador geral NÃO vê o Marketing', () => {
    expect(podeVerDepartamento(user('visualizador'), 'marketing')).toBe(false);
  });
  it('gestor e operador NÃO veem o Marketing, nem com todas as áreas do Educacional', () => {
    const todas = ['placas', 'depoimentos', 'centro_controle', 'financeiro', 'remocao_acessos', 'pedidos_alteracao', 'social_media'];
    expect(podeVerDepartamento(user('gestor', todas), 'marketing')).toBe(false);
    expect(podeVerDepartamento(user('operador', todas), 'marketing')).toBe(false);
  });
  it('sem usuário: nada', () => {
    for (const d of DEPARTAMENTOS) expect(podeVerDepartamento(null, d.key)).toBe(false);
  });
  it('os demais departamentos abrem para qualquer cargo (Educacional mantém o gate de cada tela)', () => {
    for (const c of ['dev', 'admin', 'gestor', 'operador', 'visualizador'] as Cargo[]) {
      for (const k of ['educacional', 'comercial', 'financeiro', 'infra'] as const) {
        expect(podeVerDepartamento(user(c), k)).toBe(true);
      }
    }
  });
});

describe('departamentos: base compartilhada do Marketing (20261005m)', () => {
  it('Projetos e páginas em /marketing/projetos, fora da lista de áreas', () => {
    expect(BASE_MARKETING.map((b) => b.path)).toEqual(['/marketing/projetos']);
    expect(departamento('marketing').areas.some((a) => a.path === '/marketing/projetos')).toBe(false);
    expect(departamentoDaRota('/marketing/projetos')).toBe('marketing');
  });
});
