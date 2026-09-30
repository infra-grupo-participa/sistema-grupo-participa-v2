import path from 'node:path';
import { test, expect, type Page } from '@playwright/test';
import { credenciaisFin, MOTIVO_SEM_CREDENCIAL, ROTA_FINANCEIRO } from './login';

// Escritório › Contratos da Holding Familiar (z93). SOMENTE LEITURA — rede de segurança igual à de
// financeiro-escritorio.spec.ts: RPC com nome de escrita e escrita REST fora de /rpc/ são abortadas e o teste falha.
// O 1º teste só passa DEPOIS do apply da z93. O 2º simula o banco SEM a z93 (resposta PGRST202 forjada na rede do
// navegador) e pode rodar antes do apply.
const RPC_ESCRITA = /\/rest\/v1\/rpc\/[^?]*(decidir|salvar|criar|excluir|remover|atualizar|gravar|inserir|upsert|delete|insert|update|concluir|baixar|desfundir|importar|arquivar)/i;
const LINK_OK = /^https:\/\/(docs|drive)\.google\.com\/[A-Za-z0-9/_?=&.%#-]*$/;

function contarRpc(page: Page) {
  const n = { mensal: 0, pagamentos: 0 };
  page.on('request', (r) => {
    const p = new URL(r.url()).pathname;
    if (p.endsWith('/rpc/fn_fin_contratos_hf_mensal')) n.mensal += 1;
    if (p.endsWith('/rpc/fn_fin_contratos_hf_pagamentos')) n.pagamentos += 1;
  });
  return n;
}

async function travarEscritas(page: Page) {
  const escritas: string[] = [];
  await page.route(RPC_ESCRITA, (route) => { escritas.push(new URL(route.request().url()).pathname); return route.abort(); });
  await page.route(/\/rest\/v1\/(?!rpc\/)/, (route) => {
    if (['GET', 'HEAD'].includes(route.request().method())) return route.continue();
    escritas.push(`${route.request().method()} ${new URL(route.request().url()).pathname}`);
    return route.abort();
  });
  return escritas;
}

test.describe('Financeiro · Escritório › Contratos HF (somente leitura)', () => {
  test.skip(!credenciaisFin(), MOTIVO_SEM_CREDENCIAL);

  test('grade mês a mês, fila de conferência, ficha abre; 1 RPC de cada; geometria', async ({ page }) => {
    const escritas = await travarEscritas(page);
    const rpc = contarRpc(page);

    await page.goto(`${ROTA_FINANCEIRO}#escritorio`);
    await expect(page, 'sessão do robô caiu no login').not.toHaveURL(/\/login/);
    const aba = page.getByRole('tab', { name: 'Contratos', exact: true });
    await expect(aba, 'sub-aba Contratos não apareceu: a z93 está aplicada?').toBeVisible({ timeout: 90_000 });
    await aba.click();
    await expect(page).toHaveURL(/#escritorio\?ver=contratos$/);

    const grade = page.locator('table').filter({ has: page.getByRole('columnheader', { name: 'A receber na etapa' }) });
    await expect(grade).toBeVisible({ timeout: 60_000 });
    await expect(grade.locator('tfoot tr')).toContainText('Total');
    const cab = await grade.locator('thead th').allInnerTexts();
    const meses = cab.filter((t) => /^[a-z]{3}\/\d{2}$/.test(t.trim()));
    console.log(`[e2e] colunas de mês: ${meses.join(' ')}`);
    expect(meses.length, 'padrão do banco = 5 meses atrás a 6 à frente').toBe(12);
    await expect(page.getByRole('heading', { level: 2, name: /Conferência da Hotmart/ })).toBeVisible();

    // Link do contrato: todo <a> da grade passa na regra do banco e abre sem opener.
    const links = grade.locator('tbody a[href]');
    for (let i = 0; i < await links.count(); i++) {
      const a = links.nth(i);
      expect(await a.getAttribute('href')).toMatch(LINK_OK);
      expect(await a.getAttribute('rel')).toBe('noopener noreferrer');
    }

    // Geometria: a grade larga rola DENTRO do próprio contêiner; a página não ganha rolagem horizontal.
    const g = await page.evaluate(() => ({
      doc: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    }));
    expect(g.doc, 'a grade empurrou a página para os lados').toBeLessThanOrEqual(0);
    await page.screenshot({ path: path.join(__dirname, '.resultados', 'contratos-hf.png'), fullPage: true });

    // Ficha: abre pelo nome (não pela linha), mostra as parcelas; visível de verdade (offsetParent), fecha com Esc.
    const nomes = grade.locator('tbody td:first-child button');
    const n = await nomes.count();
    console.log(`[e2e] contratos na grade: ${n}`);
    if (n > 0) {
      const nome = (await nomes.first().innerText()).trim();
      await nomes.first().click();
      const titulo = page.getByRole('heading', { level: 2, name: nome });
      await expect(titulo).toBeVisible();
      const drawer = page.locator('div.fixed.inset-0').filter({ has: titulo });
      await expect(drawer.getByText('Parcelas', { exact: false }).first()).toBeVisible();
      const visivel = await drawer.getByText('Valor cheio', { exact: true }).first().evaluate((e) => (e as HTMLElement).offsetParent !== null);
      expect(visivel).toBe(true);
      await page.screenshot({ path: path.join(__dirname, '.resultados', 'contratos-hf-ficha.png'), fullPage: false });
      await page.keyboard.press('Escape');
      await expect(drawer).toHaveCount(0);
    }

    // Trocar de aba e voltar: nenhuma consulta nova.
    await page.evaluate(() => { window.location.hash = 'board'; });
    await expect(page.getByRole('heading', { level: 1, name: /Board\s*Financeiro/ })).toBeVisible();
    await page.evaluate(() => { window.location.hash = 'escritorio?ver=contratos'; });
    await expect(grade).toBeVisible();
    expect(rpc, '1 RPC da grade e 1 dos pagamentos por página').toEqual({ mensal: 1, pagamentos: 1 });
    expect(escritas, 'o teste tentou escrever em produção').toEqual([]);
  });

  test('sem a z93 no banco: sub-aba escondida e o link ?ver=contratos cai no Funil', async ({ page }) => {
    const escritas = await travarEscritas(page);
    const rpc = contarRpc(page);
    const ausente = { code: 'PGRST202', message: 'Could not find the function', details: null, hint: null };
    await page.route(/\/rest\/v1\/rpc\/fn_fin_contratos_hf_(pagamentos|mensal)/, (route) =>
      route.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify(ausente) }));

    await page.goto(`${ROTA_FINANCEIRO}#escritorio?ver=contratos`);
    await expect(page, 'sessão do robô caiu no login').not.toHaveURL(/\/login/);
    await expect(page.getByRole('columnheader', { name: '→ Croqui' })).toBeVisible({ timeout: 90_000 });
    await expect(page).toHaveURL(/#escritorio$/);
    await expect(page.getByRole('tab', { name: 'Contratos' })).toHaveCount(0);
    await expect(page.getByRole('tablist', { name: 'Escritório' })).toHaveCount(0);
    await expect(page.getByText('ainda não disponíveis no banco')).toHaveCount(0);
    expect(rpc.pagamentos, 'a sonda consulta 1 vez').toBe(1);
    expect(rpc.mensal, 'sem a z93 a grade nem é pedida').toBe(0);
    expect(escritas).toEqual([]);
  });
});
