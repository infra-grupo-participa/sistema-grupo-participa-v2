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
  const n = { mensal: 0, pagamentos: 0, sync: 0 };
  page.on('request', (r) => {
    const p = new URL(r.url()).pathname;
    if (p.endsWith('/rpc/fn_fin_contratos_hf_mensal')) n.mensal += 1;
    if (p.endsWith('/rpc/fn_fin_contratos_hf_pagamentos')) n.pagamentos += 1;
    if (p.endsWith('/rpc/fn_fin_contratos_hf_sync_status')) n.sync += 1;
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
    expect(rpc, '1 RPC da grade, 1 dos pagamentos e 1 do status por página').toEqual({ mensal: 1, pagamentos: 1, sync: 1 });
    expect(escritas, 'o teste tentou escrever em produção').toEqual([]);
  });

  // Geometria com DADOS SINTÉTICOS (rede do navegador forjada: nenhuma linha real, nada vai ao banco nas 2 RPCs da z93).
  // Roda antes do apply: prova pintura e rolagem, não o conteúdo.
  for (const largura of [1440, 1280]) {
    test(`geometria a ${largura}px: página sem rolagem lateral; grade rola dentro; 1ª coluna fixa`, async ({ page }) => {
      const escritas = await travarEscritas(page);
      await page.setViewportSize({ width: largura, height: 900 });
      const hoje = new Date();
      const meses = Array.from({ length: 12 }, (_, i) => {
        const d = new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth() - 5 + i, 1));
        return d.toISOString().slice(0, 10);
      });
      const ficha = (i: number) => ({
        contrato_id: `00000000-0000-0000-0000-00000000000${i}`, nome: `Cliente sintético ${i} com nome comprido para medir`,
        email: `sintetico${i}@example.com`, telefone: null, cidade: 'Goiânia', uf: 'GO', cpf_final3: null, origem: 'planilha_drive',
        transacao_sinal: null, data_assinatura: '2026-08-10', assinado: 'sim', fechado_em: '2026-08-12', valor_bruto: 44640,
        valor_liquido: 40000, desconto_desc: null, entrada_valor: null, entrada_pct: null,
        link_contrato: 'https://docs.google.com/document/d/sintetico/edit', observacao: null, arquivado_em: null,
      });
      const linhas = [1, 2, 3].flatMap((i) => [
        ...meses.map((mes, k) => ({ ...ficha(i), mes, esperado: k % 3 ? 12052.8 : 0, caiu_manual: k % 4 ? 0 : 5000,
          caiu_hotmart: k % 5 ? 0 : 12052.8, caiu_hotmart_liquido: 0, caiu: 0, a_receber_etapa: null,
          situacao: k === 2 ? 'em_atraso_cobrar' : 'a_receber', parcelas: [] })),
        { ...ficha(i), mes: null, esperado: null, caiu_manual: null, caiu_hotmart: null, caiu_hotmart_liquido: null, caiu: null,
          a_receber_etapa: 13392, situacao: 'a_receber_etapa',
          parcelas: [{ id: `p${i}`, parcela_n: 3, parcela_de: 3, valor: 13392, etapa: 'registros', situacao: 'a_receber_etapa' }] },
      ]);
      const pags = [{ transacao: 'HPSINTETICO', dia: meses[5], valor: 500, nome_hotmart: 'Sintético', email_hotmart: 's@example.com',
        contrato_id: null, contrato_nome: null, situacao: 'fila', motivo: 'sem_contrato: nenhuma ficha viva deste comprador.',
        informado_id: null, parcela_n: null, parcela_de: null, atualizado_em: null,
        sync_ultima_em: new Date().toISOString(), sync_erros: 0, sync_mensagem: null }];
      await page.route(/\/rest\/v1\/rpc\/fn_fin_contratos_hf_mensal/, (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(linhas) }));
      await page.route(/\/rest\/v1\/rpc\/fn_fin_contratos_hf_pagamentos/, (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(pags) }));
      const sync = [{ ultima_em: new Date().toISOString(), fichas: 0, baixas: 0, desfeitas: 0, erros: 0, mensagem: null }];
      await page.route(/\/rest\/v1\/rpc\/fn_fin_contratos_hf_sync_status/, (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(sync) }));

      await page.goto(`${ROTA_FINANCEIRO}#escritorio?ver=contratos`);
      await expect(page, 'sessão do robô caiu no login').not.toHaveURL(/\/login/);
      const grade = page.locator('table').filter({ has: page.getByRole('columnheader', { name: 'A receber na etapa' }) });
      await expect(grade).toBeVisible({ timeout: 90_000 });
      await expect(page.getByRole('tab', { name: 'Contratos', exact: true })).toBeVisible();
      await expect(page.getByText(/Última sincronização com a Hotmart: .*, sem erro\./)).toBeVisible();

      const m = await grade.evaluate((tabela) => {
        const caixa = tabela.parentElement as HTMLElement; // o div overflow-x-auto do DataTable
        const doc = document.documentElement;
        const antes = { pagina: doc.scrollWidth - doc.clientWidth, caixaSobra: caixa.scrollWidth - caixa.clientWidth };
        caixa.scrollLeft = caixa.scrollWidth; // rola a grade até o fim
        const cel = tabela.querySelector('tbody tr td') as HTMLElement;
        const btn = cel.querySelector('button') as HTMLElement;
        const rc = cel.getBoundingClientRect(); const rx = caixa.getBoundingClientRect(); const rb = btn.getBoundingClientRect();
        const topo = document.elementFromPoint(rb.left + rb.width / 2, rb.top + rb.height / 2);
        return {
          ...antes, rolou: caixa.scrollLeft, desvioEsquerda: Math.round(rc.left - rx.left), visivel: cel.offsetParent !== null,
          nomeNoTopo: !!topo && btn.contains(topo), paginaDepois: doc.scrollWidth - doc.clientWidth,
        };
      });
      console.log(`[e2e] ${largura}px: ${JSON.stringify(m)}`);
      expect(m.pagina, 'a grade empurrou a página para os lados').toBeLessThanOrEqual(0);
      expect(m.paginaDepois).toBeLessThanOrEqual(0);
      if (m.caixaSobra > 0) {
        expect(m.rolou).toBeGreaterThan(0);
        expect(Math.abs(m.desvioEsquerda), '1ª coluna saiu da borda ao rolar').toBeLessThanOrEqual(1);
        expect(m.nomeNoTopo, 'mês pintado por cima do nome do cliente').toBe(true);
      }
      expect(m.visivel).toBe(true);
      await page.screenshot({ path: path.join(__dirname, '.resultados', `contratos-hf-${largura}.png`), fullPage: false });
      expect(escritas).toEqual([]);
    });
  }

  test('sem a z93 no banco: sub-aba escondida e o link ?ver=contratos cai no Funil', async ({ page }) => {
    const escritas = await travarEscritas(page);
    const rpc = contarRpc(page);
    const ausente = { code: 'PGRST202', message: 'Could not find the function', details: null, hint: null };
    await page.route(/\/rest\/v1\/rpc\/fn_fin_contratos_hf_(pagamentos|mensal)/, (route) =>
      route.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify(ausente) }));

    await page.goto(`${ROTA_FINANCEIRO}#escritorio?ver=contratos`);
    await expect(page, 'sessão do robô caiu no login').not.toHaveURL(/\/login/);
    await expect(page.getByRole('columnheader', { name: '→ Croqui', exact: true })).toBeVisible({ timeout: 90_000 });
    await expect(page).toHaveURL(/#escritorio$/);
    await expect(page.getByRole('tab', { name: 'Contratos' })).toHaveCount(0);
    await expect(page.getByRole('tablist', { name: 'Escritório' })).toHaveCount(0);
    await expect(page.getByText('ainda não disponíveis no banco')).toHaveCount(0);
    expect(rpc.pagamentos, 'a sonda consulta 1 vez').toBe(1);
    expect(rpc.mensal, 'sem a z93 a grade nem é pedida').toBe(0);
    expect(rpc.sync, 'sem a z93 o status nem é pedido').toBe(0);
    expect(escritas).toEqual([]);
  });
});
