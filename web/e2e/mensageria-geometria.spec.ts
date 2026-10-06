import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import type { AddressInfo } from 'node:net';
import { test, expect, type Page } from '@playwright/test';

// Geometria e contraste da Mensageria em navegador que pinta (jsdom não prova nada disso).
// SEM banco e SEM sessão: o MensageriaClient real é empacotado pelo Vite com ui/mensageria-data.ts trocado por
// ./mensageria-geometria/dados-simulados.ts (volume real: 30 disparos AC, 28 sem projeto) e servido como página
// estática com o CSS do último `npx next build`. Não sobe `next dev`.
// Rodar (de web/, depois do build):  npx playwright test -c playwright.estatico.config.ts e2e/mensageria-geometria

const WEB = path.resolve(__dirname, '..');
const HARNESS = path.join(__dirname, 'mensageria-geometria');
const SAIDA = path.join(__dirname, '.resultados', 'mensageria-harness');
const MANIFESTO = path.join(WEB, '.next', 'server', 'app', '(admin)', 'marketing', 'mensageria', 'page_client-reference-manifest.js');
const MOTIVO_SEM_BUILD = 'Sem .next da rota /marketing/mensageria: rode `npx next build` antes (o CSS vem do build).';

/** CSS que o build liga à rota /marketing/mensageria (lido do manifesto do próprio build, não de glob em .next). */
function cssDoBuild(): string | null {
  if (!fs.existsSync(MANIFESTO)) return null;
  const arquivos = [...new Set(fs.readFileSync(MANIFESTO, 'utf8').match(/static\/chunks\/[^"]+\.css/g) ?? [])];
  if (arquivos.length === 0) return null;
  return arquivos.map((a) => fs.readFileSync(path.join(WEB, '.next', a), 'utf8')).join('\n');
}

let servidor: http.Server | null = null;
let url = '';

test.describe('Mensageria · geometria e contraste (dados simulados, sem banco)', () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test.beforeAll(async () => {
    test.setTimeout(180_000);
    const css = cssDoBuild();
    test.skip(!css, MOTIVO_SEM_BUILD);
    const { build } = await import('vite');
    await build({
      root: HARNESS,
      configFile: false,
      logLevel: 'error',
      define: { 'process.env.NODE_ENV': '"production"' },
      oxc: { jsx: { runtime: 'automatic' } },
      resolve: {
        alias: [
          { find: /^\.\/mensageria-data$/, replacement: path.join(HARNESS, 'dados-simulados.ts') },
          { find: 'next/link', replacement: path.join(HARNESS, 'link-simulado.tsx') },
          { find: /^@\//, replacement: `${WEB.replace(/\\/g, '/')}/` },
        ],
      },
      build: { outDir: SAIDA, emptyOutDir: true, minify: false },
    });
    fs.writeFileSync(path.join(SAIDA, 'app.css'), css!);
    const indice = path.join(SAIDA, 'index.html');
    fs.writeFileSync(indice, fs.readFileSync(indice, 'utf8').replace('<!--CSS_DO_BUILD-->', '<link rel="stylesheet" href="/app.css">'));

    const tipos: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
    servidor = http.createServer((req, res) => {
      const rota = decodeURIComponent((req.url ?? '/').split('?')[0]);
      const arq = path.join(SAIDA, rota === '/' ? 'index.html' : rota);
      if (!arq.startsWith(SAIDA) || !fs.existsSync(arq)) { res.statusCode = 404; res.end(); return; }
      res.setHeader('content-type', tipos[path.extname(arq)] ?? 'application/octet-stream');
      res.end(fs.readFileSync(arq));
    });
    await new Promise<void>((ok) => servidor!.listen(0, '127.0.0.1', ok));
    url = `http://127.0.0.1:${(servidor.address() as AddressInfo).port}/`;
  });

  test.afterAll(async () => {
    await new Promise<void>((ok) => (servidor ? servidor.close(() => ok()) : ok()));
  });

  for (const tema of ['dark', 'light'] as const) {
    for (const [largura, altura] of [[1280, 900], [390, 844]] as const) {
      test(`aba Disparos · tema ${tema} · ${largura}px`, async ({ page }) => {
        const erros: string[] = [];
        page.on('pageerror', (e) => erros.push(e.message));
        await page.setViewportSize({ width: largura, height: altura });
        await page.goto(url);
        // Tema trocado depois do carregamento (no init script o <html> ainda não existe); as cores vêm de var(), recalculam na hora.
        await page.evaluate((t) => document.documentElement.setAttribute('data-theme', t), tema);
        await expect(page.locator('html')).toHaveAttribute('data-theme', tema);

        const linhas = page.locator('[role=tabpanel]:not([hidden]) tbody tr');
        await expect(linhas).toHaveCount(30);
        expect(erros, 'erro de JavaScript na página').toEqual([]);

        // 1. Sem rolagem horizontal da página: nem no documento, nem no <main> (que é quem rola no AppShell).
        const rolagem = await page.evaluate(() => {
          const doc = document.scrollingElement!;
          const main = document.getElementById('main')!;
          return { docScroll: doc.scrollWidth, docClient: doc.clientWidth, mainScroll: main.scrollWidth, mainClient: main.clientWidth };
        });
        console.log(`[e2e] ${tema} ${largura}px rolagem`, JSON.stringify(rolagem));
        expect(rolagem.docScroll, 'página inteira rola na horizontal').toBeLessThanOrEqual(rolagem.docClient);
        expect(rolagem.mainScroll, 'área de conteúdo rola na horizontal').toBeLessThanOrEqual(rolagem.mainClient);

        // 2. Botão de Ações visível nas 30 linhas, e dentro da faixa visível do container que rola a tabela
        //    (toBeVisible sozinho não enxerga recorte por overflow).
        const scroller = page.locator('[role=tabpanel]:not([hidden]) .overflow-x-auto').filter({ has: page.locator('th', { hasText: 'Ações' }) });
        const caixaScroller = (await scroller.boundingBox())!;
        for (let i = 0; i < 30; i++) {
          const editar = linhas.nth(i).locator('td').last().getByRole('button', { name: /^Editar o disparo de / });
          await expect(editar, `linha ${i}: botão Editar de Ações`).toBeVisible();
          const b = (await editar.boundingBox())!;
          expect(b.x, `linha ${i}: Ações cortada à esquerda`).toBeGreaterThanOrEqual(caixaScroller.x - 1);
          expect(b.x + b.width, `linha ${i}: Ações cortada à direita`).toBeLessThanOrEqual(caixaScroller.x + caixaScroller.width + 1);
        }

        // 3. Contraste computado (cor real composta sobre o fundo efetivo) >= 4,5:1.
        const amostras = {
          selo: page.locator('tbody span[title^="Veio pela integração"]').first(),
          texto_secundario: page.locator('tbody td div.line-clamp-2').first(),
          cabecalho: page.locator('[role=tabpanel]:not([hidden]) th').first(),
          botao_acao: page.getByRole('button', { name: /^Editar o disparo de / }).first(),
        };
        for (const [nome, loc] of Object.entries(amostras)) {
          const c = await contraste(page, loc);
          console.log(`[e2e] ${tema} ${largura}px contraste ${nome} = ${c}`);
          expect(c, `contraste de ${nome}`).toBeGreaterThanOrEqual(4.5);
        }
      });
    }
  }
});

async function contraste(page: Page, loc: ReturnType<Page['locator']>): Promise<number> {
  await expect(loc).toBeVisible();
  return loc.evaluate((el) => {
    const parse = (c: string): number[] | null => {
      const m = c.match(/color\(srgb ([\d.e-]+) ([\d.e-]+) ([\d.e-]+)(?: \/ ([\d.]+))?\)/);
      if (m) return [+m[1] * 255, +m[2] * 255, +m[3] * 255, m[4] == null ? 1 : +m[4]];
      const n = c.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/);
      return n ? [+n[1], +n[2], +n[3], n[4] == null ? 1 : +n[4]] : null;
    };
    const lum = ([r, g, b]: number[]) => {
      const f = (v: number) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    // Fundo efetivo: compõe as camadas semitransparentes até achar uma opaca.
    const camadas: number[][] = [];
    for (let e: Element | null = el; e; e = e.parentElement) {
      const c = parse(getComputedStyle(e).backgroundColor);
      if (c && c[3] > 0) { camadas.push(c); if (c[3] >= 1) break; }
    }
    let fundo = [0, 0, 0];
    for (let i = camadas.length - 1; i >= 0; i--) {
      const [r, g, b, a] = camadas[i];
      fundo = [r * a + fundo[0] * (1 - a), g * a + fundo[1] * (1 - a), b * a + fundo[2] * (1 - a)];
    }
    const texto = parse(getComputedStyle(el).color);
    if (!texto) throw new Error(`cor não lida: ${getComputedStyle(el).color}`);
    const [l1, l2] = [lum(texto), lum(fundo)];
    return Math.round(((Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05)) * 100) / 100;
  });
}
