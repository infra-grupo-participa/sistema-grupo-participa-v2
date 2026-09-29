import type { FullConfig } from '@playwright/test';
import { garantirSessao } from './login';

export default async function globalSetup(config: FullConfig) {
  const baseURL = config.projects[0]?.use.baseURL ?? 'http://localhost:3100';
  const r = await garantirSessao(baseURL);
  console.log(`[e2e] sessão do robô Financeiro: ${r}`);
}
