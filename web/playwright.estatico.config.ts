import { defineConfig, devices } from '@playwright/test';

// Specs que NÃO precisam de servidor nem de sessão: o próprio spec monta e serve uma página estática (componente real
// + dados simulados + CSS do `npx next build`). Sem webServer (não sobe `next dev`) e sem globalSetup (não faz login).
// O config principal (playwright.config.ts) continua igual para os specs do Financeiro.
export default defineConfig({
  testDir: './e2e',
  testMatch: ['**/mensageria-geometria.spec.ts'],
  outputDir: './e2e/.resultados/artefatos-estatico',
  workers: 1,
  fullyParallel: false,
  retries: 0,
  timeout: 120_000,
  expect: { timeout: 15_000 },
  reporter: [['list']],
  use: { headless: true, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', trace: 'retain-on-failure', screenshot: 'only-on-failure' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
