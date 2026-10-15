import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { REDIRECTS_COMERCIAL, REDIRECTS_EDUCACIONAL, REDIRECTS_FINANCEIRO, destinoDaRotaAntiga, redirectsNext } from './redirects';
import { departamento } from '../../domain/departamentos';
import { NAV_FINANCEIRO, REPORTS } from './config';

const APP = join(__dirname, '..', '..', '..', 'app');
const paginaExiste = (rota: string) => existsSync(join(APP, '(admin)', ...rota.split('/').filter(Boolean), 'page.tsx'));

describe('redirects do Educacional: cada rota antiga vai para a nova', () => {
  const esperado: Record<string, string> = {
    '/sistema/alunos': '/educacional/alunos',
    '/sistema/pedidos-alteracao': '/educacional/pedidos-alteracao',
    '/relatorios/placas': '/educacional/placas',
    '/relatorios/financeiro': '/financeiro', // destino trocado em 15/10/2026 (era /educacional/financeiro)
    '/relatorios/remocoes': '/educacional/remocoes',
    '/depoimentos': '/educacional/depoimentos',
    '/depoimentos/biblioteca': '/educacional/depoimentos/biblioteca',
  };

  it('a tabela é exatamente esta (entrada nunca sai: há links de Slack já enviados)', () => {
    expect(Object.fromEntries(REDIRECTS_EDUCACIONAL.map((r) => [r.de, r.para]))).toEqual(esperado);
  });

  it('todo destino existe como página e nenhuma rota antiga existe mais como página', () => {
    for (const r of REDIRECTS_EDUCACIONAL) {
      expect(paginaExiste(r.para), `falta a página ${r.para}`).toBe(true);
      expect(paginaExiste(r.de), `a página antiga ${r.de} ainda existe`).toBe(false);
    }
  });

  it('no Next: permanentes (308), sem condição, sem query no destino (o Next repassa a query original)', () => {
    for (const r of redirectsNext()) {
      expect(r.permanent).toBe(true);
      expect(r.destination).not.toContain('?');
      expect(Object.keys(r).sort()).toEqual(['destination', 'permanent', 'source']);
    }
  });

  it('link do Slack da Remoção mantém o ?caso=', () => {
    expect(destinoDaRotaAntiga('/relatorios/remocoes?caso=9f1c2d3e-0000-4000-8000-000000000001'))
      .toBe('/educacional/remocoes?caso=9f1c2d3e-0000-4000-8000-000000000001');
  });

  it('query e hash preservados em todas as rotas', () => {
    for (const [de, para] of Object.entries(esperado)) {
      expect(destinoDaRotaAntiga(de)).toBe(para);
      expect(destinoDaRotaAntiga(`${de}/`)).toBe(para);
      expect(destinoDaRotaAntiga(`${de}?a=1&b=2`)).toBe(`${para}?a=1&b=2`);
      expect(destinoDaRotaAntiga(`${de}#board?produto=HM`)).toBe(`${para}#board?produto=HM`);
    }
    expect(destinoDaRotaAntiga('/sistema/alunos#aluno=123&aba=jornada')).toBe('/educacional/alunos#aluno=123&aba=jornada');
  });

  it('o que não mudou de endereço não é redirecionado', () => {
    for (const p of ['/', '/login', '/usuarios', '/sistema/configuracoes', '/sistema/admin-dev', '/solicitar-placa',
      '/agendar-entrevista', '/api/placa', '/api/depoimentos/highlights', '/educacional/placas', '/financeiro']) {
      expect(destinoDaRotaAntiga(p), p).toBeNull();
    }
  });

  it('o menu do Educacional só aponta para rotas novas', () => {
    const antigos = REDIRECTS_EDUCACIONAL.map((r) => r.de);
    for (const g of REPORTS) {
      for (const href of [g.path, g.defaultHref, ...g.children.map((c) => c.href)]) {
        expect(href.startsWith('/educacional/'), href).toBe(true);
        expect(antigos).not.toContain(href.split(/[?#]/)[0]);
      }
    }
  });
});

describe('redirects do Financeiro (15/10/2026: Contas a Receber virou o departamento)', () => {
  it('a tabela é exatamente esta (entrada nunca sai)', () => {
    expect(Object.fromEntries(REDIRECTS_FINANCEIRO.map((r) => [r.de, r.para]))).toEqual({
      '/educacional/financeiro': '/financeiro',
    });
  });

  it('destino existe como página, a antiga não, e o Next recebe a entrada como 308', () => {
    for (const r of REDIRECTS_FINANCEIRO) {
      expect(paginaExiste(r.para), `falta a página ${r.para}`).toBe(true);
      expect(paginaExiste(r.de), `a página antiga ${r.de} ainda existe`).toBe(false);
      expect(redirectsNext()).toContainEqual({ source: r.de, destination: r.para, permanent: true });
    }
  });

  it('hash e query preservados: #board, sub-aba com ? e filtro', () => {
    expect(destinoDaRotaAntiga('/educacional/financeiro#board')).toBe('/financeiro#board');
    expect(destinoDaRotaAntiga('/educacional/financeiro/#escritorio?ver=contratos')).toBe('/financeiro#escritorio?ver=contratos');
    expect(destinoDaRotaAntiga('/educacional/financeiro?x=1#receber')).toBe('/financeiro?x=1#receber');
  });

  it('sem cadeia: nenhum destino é, ele mesmo, uma rota antiga', () => {
    const antigos = new Set(redirectsNext().map((r) => r.source));
    for (const r of redirectsNext()) expect(antigos.has(r.destination), `${r.source} → ${r.destination} encadeia`).toBe(false);
    expect(destinoDaRotaAntiga('/relatorios/financeiro#board')).toBe('/financeiro#board');
  });

  it('o menu do Financeiro só aponta para /financeiro', () => {
    for (const href of [NAV_FINANCEIRO.path, NAV_FINANCEIRO.defaultHref, ...NAV_FINANCEIRO.children.map((c) => c.href)]) {
      expect(href.split(/[?#]/)[0], href).toBe('/financeiro');
    }
  });
});

describe('redirects do Comercial', () => {
  it('a tabela é exatamente esta (entrada nunca sai)', () => {
    expect(Object.fromEntries(REDIRECTS_COMERCIAL.map((r) => [r.de, r.para]))).toEqual({
      '/comercial/recuperacao': '/comercial/estrategias',
    });
  });

  it('destino existe como página, a antiga não, e o Next recebe a entrada como 308', () => {
    for (const r of REDIRECTS_COMERCIAL) {
      expect(paginaExiste(r.para), `falta a página ${r.para}`).toBe(true);
      expect(paginaExiste(r.de), `a página antiga ${r.de} ainda existe`).toBe(false);
      expect(redirectsNext()).toContainEqual({ source: r.de, destination: r.para, permanent: true });
    }
  });

  it('mantém query e hash (link de aviso com ?pedido=)', () => {
    expect(destinoDaRotaAntiga('/comercial/recuperacao?fila=abc#x')).toBe('/comercial/estrategias?fila=abc#x');
  });

  it('o menu do Comercial não aponta para rota antiga', () => {
    const antigos = REDIRECTS_COMERCIAL.map((r) => r.de);
    for (const a of departamento('comercial').areas) expect(antigos).not.toContain(a.path);
  });
});
