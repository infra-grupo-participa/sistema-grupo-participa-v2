import path from 'node:path';
import { test, expect } from '@playwright/test';
import { credenciaisFin, MOTIVO_SEM_CREDENCIAL, ROTA_FINANCEIRO } from './login';

// SOMENTE LEITURA: abre o board e lê os cards. Pedido do Marcio (29/09): card menor, cor como referência visual —
// sem o bloco "Hotmart / Devendo" e sem o operador/vendedor atribuído (ficam na ficha).
test.describe('Financeiro · card do board (somente leitura)', () => {
  test.skip(!credenciaisFin(), MOTIVO_SEM_CREDENCIAL);

  test('card sem bloco Hotmart/Devendo e sem vendedor', async ({ page }, info) => {
    await page.route(/\/rest\/v1\/(?!rpc\/)/, (route) =>
      ['GET', 'HEAD'].includes(route.request().method()) ? route.continue() : route.abort());

    await page.goto(`${ROTA_FINANCEIRO}#board`);
    await expect(page, 'sessão do robô caiu no login').not.toHaveURL(/\/login/);

    const cards = page.getByRole('button', { name: /^Abrir ficha de / });
    await expect(cards.first()).toBeVisible({ timeout: 90_000 });
    const n = await cards.count();
    console.log(`[e2e] board: ${n} cards visíveis`);
    expect(n).toBeGreaterThan(0);

    const amostra = Math.min(n, 40);
    for (let i = 0; i < amostra; i++) {
      const card = cards.nth(i);
      const texto = (await card.innerText()).replace(/\s+/g, ' ');
      expect(texto, `card ${i}: bloco Hotmart ainda aparece`).not.toMatch(/\bhotmart\b/i);
      expect(texto, `card ${i}: "em dia" ainda aparece (cor já diz a situação)`).not.toMatch(/\bem dia\b/i);
      await expect(card.locator('[title^="Comercial:"]'), `card ${i}: vendedor ainda aparece`).toHaveCount(0);
    }
    console.log(`[e2e] ${amostra} cards conferidos: sem Hotmart/Devendo e sem vendedor`);

    await cards.first().screenshot({ path: path.join(__dirname, '.resultados', 'card.png') });
    info.annotations.push({ type: 'cards-conferidos', description: String(amostra) });
  });
});
