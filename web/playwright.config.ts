import { defineConfig, devices } from '@playwright/test';
import { loadEnvConfig } from '@next/env';

// Mesmo carregador de .env que o `next dev` usa: E2E_FIN_EMAIL / E2E_FIN_SENHA vêm de .env.local
// (ignorado pelo git). Sem elas, os testes que precisam de login são pulados com mensagem (ver e2e/login.ts).
loadEnvConfig(process.cwd());

const PORTA = 3100;
const BASE = `http://localhost:${PORTA}`;

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.spec.ts',
  outputDir: './e2e/.resultados/artefatos',
  globalSetup: './e2e/global-setup.ts',
  // Produção é compartilhada: 1 worker, sem paralelismo, sem retry que mascare espera errada.
  workers: 1,
  fullyParallel: false,
  retries: 0,
  // 1ª compilação do `next dev` da rota do Financeiro passa de 30 s.
  timeout: 120_000,
  expect: { timeout: 30_000 },
  reporter: [['list'], ['html', { outputFolder: './e2e/.resultados/relatorio', open: 'never' }]],
  use: {
    baseURL: BASE,
    headless: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    storageState: './e2e/.auth/fin.json',
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    viewport: { width: 1440, height: 900 },
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } }],
  webServer: {
    command: `npm run dev -- --port ${PORTA}`,
    url: `${BASE}/login`,
    reuseExistingServer: true,
    timeout: 180_000,
    stdout: 'ignore',
    stderr: 'pipe',
  },
});
