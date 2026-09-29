import path from 'node:path';
import { test, expect } from '@playwright/test';
import { credenciaisFin, MOTIVO_SEM_CREDENCIAL, ROTA_FINANCEIRO } from './login';

// SOMENTE LEITURA em produção: abre painéis e cancela. Nunca clica em "Confirmar em…", "Ligar a este evento",
// "Criar evento e ligar" nem "Sim, não é de evento". Rede de segurança abaixo: qualquer RPC de escrita é abortada
// antes de sair do navegador e o teste falha.
const RPC_ESCRITA = /\/rest\/v1\/rpc\/[^?]*(decidir|salvar|criar|excluir|remover|atualizar|gravar|inserir|upsert|delete|insert|update)/i;
const JARGAO = /\b(oferta_codigo|resolvedor|sck|sinais)\b/i;

test.describe('Financeiro · Ofertas a confirmar (somente leitura)', () => {
  test.skip(!credenciaisFin(), MOTIVO_SEM_CREDENCIAL);

  test('fila aparece com linhas, painéis abrem e fecham, sem jargão', async ({ page }, info) => {
    const escritasBloqueadas: string[] = [];
    await page.route(RPC_ESCRITA, (route) => {
      escritasBloqueadas.push(new URL(route.request().url()).pathname);
      return route.abort();
    });
    // Qualquer escrita REST direta em tabela (fora de /rpc/) também é bloqueada.
    await page.route(/\/rest\/v1\/(?!rpc\/)/, (route) => {
      if (route.request().method() === 'GET' || route.request().method() === 'HEAD') return route.continue();
      escritasBloqueadas.push(`${route.request().method()} ${new URL(route.request().url()).pathname}`);
      return route.abort();
    });

    const t0 = Date.now();
    await page.goto(`${ROTA_FINANCEIRO}#receber`);
    await expect(page, 'sessão do robô caiu no login').not.toHaveURL(/\/login/);

    const fila = page.locator('section[aria-labelledby="fila-ofertas-titulo"]');
    const titulo = fila.getByRole('heading', { name: /^Ofertas a confirmar \(\d+\)$/ });
    await expect(titulo).toBeVisible({ timeout: 90_000 });
    const msAteFila = Date.now() - t0;
    console.log(`[e2e] tempo até a fila aparecer: ${msAteFila} ms (goto → título visível)`);
    info.annotations.push({ type: 'tempo-ate-fila-ms', description: String(msAteFila) });

    const nTitulo = Number((await titulo.innerText()).match(/\((\d+)\)/)?.[1]);
    const linhas = fila.locator('tbody > tr');
    await expect(linhas.first()).toBeVisible();
    const nLinhas = await linhas.count();
    console.log(`[e2e] fila: título diz ${nTitulo}, tabela tem ${nLinhas} linhas`);
    expect(nLinhas).toBeGreaterThan(0);
    expect(nLinhas, 'contagem do título difere das linhas').toBe(nTitulo);

    await expect(fila).not.toContainText(JARGAO);

    const linha = linhas.first();

    // "Outro evento…": a lista de eventos (fn_fin_funis) carrega no <select>. Depois, Cancelar.
    const btnOutro = linha.getByRole('button', { name: 'Outro evento…', exact: true });
    await btnOutro.click();
    await expect(btnOutro).toHaveAttribute('aria-expanded', 'true');
    const select = fila.locator('tbody select');
    await expect(select).toBeVisible({ timeout: 60_000 });
    await expect.poll(() => select.locator('option').count(), { timeout: 30_000 }).toBeGreaterThan(1);
    const nEventos = (await select.locator('option').count()) - 1; // menos o "—"
    console.log(`[e2e] "Outro evento…": ${nEventos} eventos no select`);
    await expect(fila).not.toContainText(JARGAO);
    await fila.getByRole('button', { name: 'Cancelar', exact: true }).click();
    await expect(select).toHaveCount(0);
    await expect(btnOutro).toHaveAttribute('aria-expanded', 'false');

    // "Criar evento": formulário abre com o nome pré-preenchido. Depois, Cancelar (nunca "Criar evento e ligar").
    const btnCriar = linha.getByRole('button', { name: 'Criar evento', exact: true });
    await btnCriar.click();
    const nome = fila.getByLabel('Nome do evento');
    await expect(nome).toBeVisible();
    await expect(nome).toHaveValue(/\S/);
    console.log(`[e2e] "Criar evento": nome pré-preenchido com ${(await nome.inputValue()).length} caracteres`);
    await expect(fila.getByRole('button', { name: 'Criar evento e ligar', exact: true })).toBeVisible();
    await expect(fila).not.toContainText(JARGAO);
    await fila.getByRole('button', { name: 'Cancelar', exact: true }).click();
    await expect(nome).toHaveCount(0);

    await page.screenshot({ path: path.join(__dirname, '.resultados', 'fila.png'), fullPage: true });

    expect(escritasBloqueadas, 'o teste tentou escrever em produção').toEqual([]);
  });
});
