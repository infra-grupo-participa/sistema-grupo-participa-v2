import path from 'node:path';
import { test, expect, type Page } from '@playwright/test';
import { credenciaisFin, MOTIVO_SEM_CREDENCIAL, ROTA_FINANCEIRO } from './login';

// SOMENTE LEITURA: abre a aba Escritório, lê o funil, abre e fecha o drill-down de pessoas. Rede de segurança igual à
// de financeiro-fila.spec.ts: RPC com nome de escrita e escrita REST fora de /rpc/ são abortadas e o teste falha.
const RPC_ESCRITA = /\/rest\/v1\/rpc\/[^?]*(decidir|salvar|criar|excluir|remover|atualizar|gravar|inserir|upsert|delete|insert|update)/i;

function contarRpc(page: Page) {
  const n = { funil: 0, pessoas: 0 };
  page.on('request', (r) => {
    const p = new URL(r.url()).pathname;
    if (p.endsWith('/rpc/fn_fin_escritorio_funil')) n.funil += 1;
    if (p.endsWith('/rpc/fn_fin_escritorio_funil_pessoas')) n.pessoas += 1;
  });
  return n;
}

test.describe('Financeiro · aba Escritório (somente leitura)', () => {
  test.skip(!credenciaisFin(), MOTIVO_SEM_CREDENCIAL);

  test('funil com linhas, drill-down abre com pessoas, 1 RPC por aba e 1 por linha', async ({ page }) => {
    const escritas: string[] = [];
    await page.route(RPC_ESCRITA, (route) => { escritas.push(new URL(route.request().url()).pathname); return route.abort(); });
    await page.route(/\/rest\/v1\/(?!rpc\/)/, (route) => {
      if (['GET', 'HEAD'].includes(route.request().method())) return route.continue();
      escritas.push(`${route.request().method()} ${new URL(route.request().url()).pathname}`);
      return route.abort();
    });
    const rpc = contarRpc(page);

    await page.goto(`${ROTA_FINANCEIRO}#escritorio`);
    await expect(page, 'sessão do robô caiu no login').not.toHaveURL(/\/login/);
    await expect(page.getByRole('heading', { level: 1, name: /Setor\s*Escritório/ })).toBeVisible({ timeout: 90_000 });

    const tabela = page.locator('table').filter({ has: page.getByRole('columnheader', { name: '→ Croqui' }) });
    const linhas = tabela.locator('tbody > tr[class*="cursor-pointer"]');
    await expect(linhas.first()).toBeVisible({ timeout: 60_000 });
    const nLinhas = await linhas.count();
    console.log(`[e2e] funil do escritório: ${nLinhas} linhas clicáveis (eventos + baldes)`);
    expect(nLinhas).toBeGreaterThan(0);
    await expect(tabela.getByText('Fora de evento', { exact: true })).toBeVisible();
    for (const balde of ['Sessão sem evento', 'Entrou direto no Croqui (sem Sessão)', 'Entrou direto na Holding Familiar']) {
      await expect(tabela.getByRole('button', { name: balde, exact: true })).toBeVisible();
    }
    const rodape = tabela.locator('tfoot tr');
    await expect(rodape).toContainText('Total');
    console.log(`[e2e] rodapé: ${(await rodape.innerText()).replace(/\s+/g, ' ')}`);
    const aviso = page.getByRole('status').filter({ hasText: 'ainda estão sendo carregadas' });
    console.log(`[e2e] aviso de conta do escritório oculta: ${await aviso.count()}`);

    // Primeira linha de EVENTO com pessoas (coluna Pessoas > 0).
    let alvo = -1;
    for (let i = 0; i < nLinhas; i++) {
      const pessoas = Number((await linhas.nth(i).locator('td').nth(2).innerText()).replace(/\D/g, ''));
      if (pessoas > 0) { alvo = i; break; }
    }
    expect(alvo, 'nenhuma linha com pessoas').toBeGreaterThanOrEqual(0);
    const linha = linhas.nth(alvo);
    const nome = (await linha.locator('td').first().getByRole('button').innerText()).trim();
    const nPessoas = Number((await linha.locator('td').nth(2).innerText()).replace(/\D/g, ''));
    await linha.click();

    const drawer = page.locator('div.fixed.inset-0').filter({ has: page.getByRole('heading', { level: 2, name: nome }) });
    await expect(drawer).toBeVisible();
    const pessoas = drawer.locator('tbody > tr');
    await expect(pessoas.first()).toBeVisible({ timeout: 60_000 });
    const nDrawer = await pessoas.count();
    console.log(`[e2e] drill-down "${nome}": ${nDrawer} pessoas (funil diz ${nPessoas})`);
    expect(nDrawer, 'linhas do drill-down ≠ coluna Pessoas').toBe(nPessoas);
    await expect(drawer.getByRole('button', { name: /^Baixar lista \(\d+\)$/ })).toBeEnabled();
    // Robô sem CPF: telefone vem mascarado do banco ("···" + 4 dígitos) ou ausente.
    const tels = await pessoas.locator('td:nth-child(3)').allInnerTexts();
    expect(tels.filter((t) => !/^(···\d{4}|—)$/.test(t.trim())), 'telefone sem máscara para perfil sem CPF').toEqual([]);
    await page.screenshot({ path: path.join(__dirname, '.resultados', 'escritorio-drill.png'), fullPage: false });

    await drawer.getByRole('button', { name: 'Fechar' }).last().click();
    await expect(drawer).toHaveCount(0);
    // Reabrir a mesma linha e trocar de aba e voltar: nenhuma consulta nova.
    await linha.click();
    await expect(page.getByRole('heading', { level: 2, name: nome })).toBeVisible();
    await page.keyboard.press('Escape');
    await page.evaluate(() => { window.location.hash = 'board'; });
    await expect(page.getByRole('heading', { level: 1, name: /Board\s*Financeiro/ })).toBeVisible();
    await page.evaluate(() => { window.location.hash = 'escritorio'; });
    await expect(linhas.first()).toBeVisible();
    expect(rpc, '1 RPC do funil por página e 1 por linha aberta').toEqual({ funil: 1, pessoas: 1 });

    await page.screenshot({ path: path.join(__dirname, '.resultados', 'escritorio.png'), fullPage: true });
    expect(escritas, 'o teste tentou escrever em produção').toEqual([]);
  });

  test('porta de entrada: menu e link na aba Funis levam ao Escritório', async ({ page }) => {
    await page.route(/\/rest\/v1\/(?!rpc\/)/, (route) =>
      ['GET', 'HEAD'].includes(route.request().method()) ? route.continue() : route.abort());
    await page.goto(`${ROTA_FINANCEIRO}#funis`);
    await expect(page, 'sessão do robô caiu no login').not.toHaveURL(/\/login/);
    await expect(page.locator('a[href="/relatorios/financeiro#escritorio"]').first()).toBeAttached({ timeout: 90_000 });
    await page.getByRole('button', { name: 'Escritório', exact: true }).click();
    await page.getByRole('link', { name: /aba Escritório/ }).click();
    await expect(page).toHaveURL(/#escritorio$/);
    await expect(page.getByRole('heading', { level: 1, name: /Setor\s*Escritório/ })).toBeVisible();
  });
});
