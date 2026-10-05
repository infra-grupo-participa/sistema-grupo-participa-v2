import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { REDIRECTS_EDUCACIONAL, destinoDaRotaAntiga, redirectsNext } from './redirects';
import { REPORTS } from './config';

const APP = join(__dirname, '..', '..', '..', 'app');
const paginaExiste = (rota: string) => existsSync(join(APP, '(admin)', ...rota.split('/').filter(Boolean), 'page.tsx'));

describe('redirects do Educacional — cada rota antiga vai para a nova', () => {
  const esperado: Record<string, string> = {
    '/sistema/alunos': '/educacional/alunos',
    '/sistema/pedidos-alteracao': '/educacional/pedidos-alteracao',
    '/relatorios/placas': '/educacional/placas',
    '/relatorios/financeiro': '/educacional/financeiro',
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
