import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { Cargo, GpUser } from './auth';
import {
  BASE_MARKETING, DEPARTAMENTOS, MODULO_DEPARTAMENTO, acessoComercial, departamento, departamentoDaRota, ehDoComercial,
  podeEditarArea, podeSolicitarEstrategia, podeVerDepartamento,
} from './departamentos';
import { podeOperarFinanceiro, podeVerFinanceiro } from './acesso-financeiro';
import {
  podeOperarFinanceiro as podeOperarFinanceiroDoModulo, podeVerFinanceiro as podeVerFinanceiroDoModulo,
} from '../../modules/financeiro/domain/acesso';

const user = (cargo: Cargo, setores: string[] = []): GpUser =>
  ({ id: 'u', email: 'x@advmais.com', nome: 'X', cargo, status: 'ativo', setores, funcoes: [], podeVerCpf: false, time: null, avatarUrl: null });

describe('departamentos: registro', () => {
  it('os 5 departamentos da decisão de 05/10/2026, nesta ordem', () => {
    expect(DEPARTAMENTOS.map((d) => d.label)).toEqual(['Educacional', 'Marketing', 'Comercial', 'Financeiro', 'Infra']);
  });
  it('todos os departamentos estão ativos (Financeiro deixou de ser "Em breve" em 15/10/2026)', () => {
    const st = Object.fromEntries(DEPARTAMENTOS.map((d) => [d.key, d.status]));
    expect(st).toEqual({ educacional: 'ativo', marketing: 'ativo', comercial: 'ativo', financeiro: 'ativo', infra: 'ativo' });
  });
  it('o módulo Contas a Receber pertence ao departamento Financeiro, e o Educacional não o anuncia mais', () => {
    expect(MODULO_DEPARTAMENTO.financeiro).toBe('financeiro');
    expect(departamento('financeiro').path).toBe('/financeiro');
    expect(departamento('financeiro').descricao).toMatch(/Contas a Receber/);
    expect(departamento('educacional').descricao).not.toMatch(/Financeiro/i);
  });
  it('Infra não tem mais o nível intermediário de áreas', () => {
    expect(departamento('infra').areas).toEqual([]);
  });
  it('Marketing tem as 5 áreas em /marketing/<area>: Web, Mensageria e Tráfego ativas, as outras "Em breve"', () => {
    const mkt = departamento('marketing');
    expect(mkt.areas.map((a) => a.label)).toEqual(['Web', 'Mensageria', 'Tráfego', 'Audiovisual', 'Social Media']);
    for (const a of mkt.areas) {
      expect(a.status).toBe(['web', 'mensageria', 'trafego'].includes(a.key) ? 'ativo' : 'em_breve');
      expect(a.path).toBe(`/marketing/${a.key}`);
    }
  });
  it('Educacional não tem áreas', () => {
    expect(departamento('educacional').areas).toEqual([]);
  });
  it('Comercial: as telas do CRM em /comercial/<tela>; só Social selling "Em breve"', () => {
    const com = departamento('comercial');
    expect(com.areas.map((a) => a.key)).toEqual(['funil', 'conversas', 'atividades', 'contatos', 'estrategias', 'disparos', 'relatorios', 'produtos', 'registro', 'playbook', 'social-selling', 'configuracoes']);
    for (const a of com.areas) {
      expect(a.status).toBe(a.key === 'social-selling' ? 'em_breve' : 'ativo');
      expect(a.path).toBe(`/comercial/${a.key}`);
    }
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

describe('departamentos: Comercial (flag NEXT_PUBLIC_COMERCIAL_VENDEDORES)', () => {
  const com = (cargo: Cargo, setores: string[], funcoes: string[], status: string | null = 'ativo'): GpUser =>
    ({ ...user(cargo, setores), funcoes, status });
  const vendedor = com('operador', ['comercial'], ['comercial.vender']);
  const gestorCom = com('gestor', ['comercial'], []);
  const LIGADA = { comercialVendedores: true };

  it('flag desligada (padrão): só admin e dev; gestor, operador e visualizador não', () => {
    expect(podeVerDepartamento(user('admin'), 'comercial')).toBe(true);
    expect(podeVerDepartamento(user('dev'), 'comercial')).toBe(true);
    for (const c of ['gestor', 'operador', 'visualizador'] as Cargo[]) expect(podeVerDepartamento(user(c), 'comercial')).toBe(false);
    expect(podeVerDepartamento(vendedor, 'comercial')).toBe(false);
    expect(podeVerDepartamento(gestorCom, 'comercial', { comercialVendedores: false })).toBe(false);
  });
  it('flag ligada: vendedor (área comercial + comercial.vender) e gestor com área comercial entram; admin/dev seguem', () => {
    expect(podeVerDepartamento(vendedor, 'comercial', LIGADA)).toBe(true);
    expect(podeVerDepartamento(gestorCom, 'comercial', LIGADA)).toBe(true);
    expect(podeVerDepartamento(user('admin'), 'comercial', LIGADA)).toBe(true);
    expect(podeVerDepartamento(user('dev'), 'comercial', LIGADA)).toBe(true);
  });
  it('flag ligada: quem não é do Comercial continua fora (espelha crm.eh_comercial)', () => {
    expect(podeVerDepartamento(com('operador', ['comercial'], []), 'comercial', LIGADA)).toBe(false);          // sem a função
    expect(podeVerDepartamento(com('operador', ['placas'], ['comercial.vender']), 'comercial', LIGADA)).toBe(false); // sem a área
    expect(podeVerDepartamento(com('gestor', ['placas'], []), 'comercial', LIGADA)).toBe(false);              // gestor de outro setor
    expect(podeVerDepartamento(user('visualizador', ['comercial']), 'comercial', LIGADA)).toBe(false);
    expect(podeVerDepartamento(com('operador', ['comercial'], ['comercial.vender'], 'pendente'), 'comercial', LIGADA)).toBe(false);
    expect(podeVerDepartamento(null, 'comercial', LIGADA)).toBe(false);
  });
  it('a flag não abre o Marketing', () => {
    expect(podeVerDepartamento(vendedor, 'marketing', LIGADA)).toBe(false);
    expect(podeVerDepartamento(gestorCom, 'marketing', LIGADA)).toBe(false);
  });
  it('ehDoComercial = régua do banco (gestor: dev/admin ou gestor+área; vendedor: área + comercial.vender)', () => {
    expect(ehDoComercial(user('admin'))).toBe(true);
    expect(ehDoComercial(gestorCom)).toBe(true);
    expect(ehDoComercial(vendedor)).toBe(true);
    expect(ehDoComercial(user('operador', ['comercial']))).toBe(false);
    expect(ehDoComercial(null)).toBe(false);
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
  it('Educacional e Infra abrem para qualquer cargo (Educacional mantém o gate de cada tela)', () => {
    for (const c of ['dev', 'admin', 'gestor', 'operador', 'visualizador'] as Cargo[]) {
      for (const k of ['educacional', 'infra'] as const) {
        expect(podeVerDepartamento(user(c), k)).toBe(true);
      }
    }
  });
});

describe('departamentos: Financeiro (desde 15/10/2026 mostra dinheiro: régua de podeVerFinanceiro)', () => {
  const todosOsCargos = ['dev', 'admin', 'gestor', 'operador', 'visualizador'] as Cargo[];
  const operadorQueOpera: GpUser = { ...user('operador', ['financeiro']), funcoes: ['financeiro.operar'] };
  const casos: GpUser[] = [
    ...todosOsCargos.map((c) => user(c)),
    ...todosOsCargos.map((c) => user(c, ['financeiro'])),
    ...todosOsCargos.map((c) => user(c, ['placas', 'centro_controle'])),
    operadorQueOpera,
  ];

  it('dev e admin veem', () => {
    expect(podeVerDepartamento(user('dev'), 'financeiro')).toBe(true);
    expect(podeVerDepartamento(user('admin'), 'financeiro')).toBe(true);
  });
  it('gestor e operador com a área financeiro veem', () => {
    expect(podeVerDepartamento(user('gestor', ['financeiro']), 'financeiro')).toBe(true);
    expect(podeVerDepartamento(user('operador', ['financeiro']), 'financeiro')).toBe(true);
  });
  it('visualizador NÃO vê, nem com a área financeiro', () => {
    expect(podeVerDepartamento(user('visualizador'), 'financeiro')).toBe(false);
    expect(podeVerDepartamento(user('visualizador', ['financeiro']), 'financeiro')).toBe(false);
  });
  it('equipe sem a área financeiro NÃO vê', () => {
    expect(podeVerDepartamento(user('gestor'), 'financeiro')).toBe(false);
    expect(podeVerDepartamento(user('operador', ['placas', 'centro_controle']), 'financeiro')).toBe(false);
  });
  it('trava: o gate do departamento é idêntico ao do módulo (podeVerFinanceiro), caso a caso', () => {
    for (const u of [...casos, null]) expect(podeVerDepartamento(u, 'financeiro'), JSON.stringify(u)).toBe(podeVerFinanceiro(u));
  });
  it('trava: o módulo lê a mesma fonte (modules/financeiro reexporta shared/domain/acesso-financeiro)', () => {
    expect(podeVerFinanceiroDoModulo).toBe(podeVerFinanceiro);
    expect(podeOperarFinanceiroDoModulo).toBe(podeOperarFinanceiro);
  });
  it('editar (v1) = canEdit da tela (podeOperarFinanceiro): operador só com financeiro.operar', () => {
    for (const u of casos) expect(podeEditarArea(u, 'financeiro'), JSON.stringify(u)).toBe(podeOperarFinanceiro(u));
    expect(podeEditarArea(operadorQueOpera, 'financeiro')).toBe(true);
    expect(podeEditarArea(user('operador', ['financeiro']), 'financeiro')).toBe(false);
  });
  it('v2: ver exige financeiro.ver (inclusive com financeiro em ver) e editar exige financeiro.operar', () => {
    const v2 = { acessoV2: true };
    const p = (capacidades: string[], ver: string[]): GpUser =>
      ({ ...user('visualizador'), acesso: { equipe: true, master: false, vinculos: [], capacidades, ver, editar: [] } });
    expect(podeVerDepartamento(p([], ['financeiro']), 'financeiro', v2)).toBe(false);
    expect(podeVerDepartamento(p(['financeiro.ver'], ['financeiro']), 'financeiro', v2)).toBe(true);
    expect(podeEditarArea(p(['financeiro.ver'], ['financeiro']), 'financeiro', null, v2)).toBe(false);
    expect(podeEditarArea(p(['financeiro.ver', 'financeiro.operar'], ['financeiro']), 'financeiro', null, v2)).toBe(true);
    // cargo legado não abre nada no v2 sem `acesso`
    expect(podeVerDepartamento(user('admin'), 'financeiro', v2)).toBe(false);
  });
});

describe('departamentos: base compartilhada do Marketing (20261005m)', () => {
  it('Projetos e páginas em /marketing/projetos, fora da lista de áreas', () => {
    expect(BASE_MARKETING.map((b) => b.path)).toEqual(['/marketing/projetos']);
    expect(departamento('marketing').areas.some((a) => a.path === '/marketing/projetos')).toBe(false);
    expect(departamentoDaRota('/marketing/projetos')).toBe('marketing');
  });
});

describe('acesso v2 por área e capacidade', () => {
  const opcoes = { acessoV2: true };
  const pessoa = (editar: string[], capacidades: string[] = [], ver = ['educacional', 'marketing', 'comercial', 'infra']): GpUser => ({
    ...user('visualizador'), acesso: { equipe: true, master: false, vinculos: [], capacidades, ver, editar },
  });
  it('Web lê Tráfego mas só edita Web', () => {
    const u = pessoa(['marketing/web']);
    expect(podeVerDepartamento(u, 'marketing', opcoes)).toBe(true);
    expect(podeEditarArea(u, 'marketing', 'web', opcoes)).toBe(true);
    expect(podeEditarArea(u, 'marketing', 'trafego', opcoes)).toBe(false);
  });
  it('Financeiro exige capacidade, inclusive quando consta em ver', () => {
    const u = pessoa([], [], ['financeiro']);
    expect(podeVerDepartamento(u, 'financeiro', opcoes)).toBe(false);
    expect(podeVerDepartamento(pessoa([], ['financeiro.ver'], ['financeiro']), 'financeiro', opcoes)).toBe(true);
  });
  it('acesso ausente falha fechado e flag desligada preserva admin legado', () => {
    expect(podeVerDepartamento(user('admin'), 'marketing', opcoes)).toBe(false);
    expect(podeEditarArea(user('admin'), 'marketing', 'trafego', opcoes)).toBe(false);
    expect(podeEditarArea(user('admin'), 'marketing', 'trafego')).toBe(true);
  });
  it('Comercial leitor fica só em relatórios', () => {
    expect(acessoComercial(pessoa([]), opcoes)).toBe('relatorios');
    expect(acessoComercial(pessoa(['comercial']), opcoes)).toBe('completo');
  });
  it('quem só pede estratégia abre Estratégias com a flag ligada (leitor ou fora do Comercial)', () => {
    const solicitante = (ver: string[]) => ({ ...pessoa([], [], ver), funcoes: ['comercial.solicitar_estrategia'], status: 'ativo' });
    expect(acessoComercial(solicitante(['comercial']), opcoes)).toBe('estrategias');
    expect(acessoComercial(solicitante(['educacional']), opcoes)).toBe('estrategias');
    // quem edita o Comercial continua com o CRM inteiro, mesmo pedindo estratégia
    expect(acessoComercial({ ...pessoa(['comercial']), funcoes: ['comercial.solicitar_estrategia'], status: 'ativo' }, opcoes)).toBe('completo');
    // sem a função e sem ver o Comercial: nada
    expect(acessoComercial(pessoa([], [], ['educacional']), opcoes)).toBeNull();
  });
  it('responsável de departamento edita as áreas dele; master edita todas', () => {
    expect(podeEditarArea(pessoa(['marketing']), 'marketing', 'trafego', opcoes)).toBe(true);
    expect(podeEditarArea(pessoa(['marketing']), 'infra', 'dados', opcoes)).toBe(false);
    const master = pessoa([]);
    master.acesso = { ...master.acesso!, master: true };
    expect(podeEditarArea(master, 'infra', 'dados', opcoes)).toBe(true);
  });
});

describe('departamentos: solicitante de estratégia (função comercial.solicitar_estrategia)', () => {
  const comFuncao = (cargo: Cargo, funcoes: string[], status: string | null = 'ativo', setores: string[] = []): GpUser =>
    ({ ...user(cargo, setores), funcoes, status });
  const SOLICITAR = ['comercial.solicitar_estrategia'];

  it('vale pela função, não pelo cargo: dev/admin sem a função não pedem; operador com a função pede', () => {
    expect(podeSolicitarEstrategia(comFuncao('dev', []))).toBe(false);
    expect(podeSolicitarEstrategia(comFuncao('admin', []))).toBe(false);
    expect(podeSolicitarEstrategia(comFuncao('dev', SOLICITAR))).toBe(true);
    expect(podeSolicitarEstrategia(comFuncao('operador', SOLICITAR))).toBe(true);
    expect(podeSolicitarEstrategia(comFuncao('visualizador', SOLICITAR))).toBe(true);
  });
  it('perfil não ativo ou sem login não pede', () => {
    expect(podeSolicitarEstrategia(comFuncao('operador', SOLICITAR, 'pendente'))).toBe(false);
    expect(podeSolicitarEstrategia(comFuncao('operador', SOLICITAR, 'negado'))).toBe(false);
    expect(podeSolicitarEstrategia(null)).toBe(false);
  });
  it('acessoComercial: CRM inteiro para quem vê o departamento; só Estratégias para o solicitante; nada para os outros', () => {
    expect(acessoComercial(comFuncao('admin', []))).toBe('completo');
    expect(acessoComercial(comFuncao('dev', SOLICITAR))).toBe('completo');
    expect(acessoComercial(comFuncao('operador', SOLICITAR))).toBe('estrategias');
    expect(acessoComercial(comFuncao('visualizador', []))).toBeNull();
    expect(acessoComercial(comFuncao('operador', ['comercial.vender'], 'ativo', ['comercial']))).toBeNull();
    expect(acessoComercial(comFuncao('operador', ['comercial.vender'], 'ativo', ['comercial']), { comercialVendedores: true })).toBe('completo');
  });
});
