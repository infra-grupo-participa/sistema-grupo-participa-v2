import fs from 'node:fs';
import path from 'node:path';
import { chromium, expect, type Page } from '@playwright/test';
import { DOMINIO_EQUIPE, ehEmailDaEquipe } from '../shared/domain/auth/gp-user';

// Sessão do usuário-robô do Financeiro (operador, área financeiro, sem CPF completo).
// Credenciais SÓ de .env.local (E2E_FIN_EMAIL / E2E_FIN_SENHA). Nunca logar, nunca gravar em arquivo versionado.
export const ARQUIVO_SESSAO = path.join(__dirname, '.auth', 'fin.json');
export const ROTA_FINANCEIRO = '/relatorios/financeiro';

export const MOTIVO_SEM_CREDENCIAL =
  'E2E_FIN_EMAIL e E2E_FIN_SENHA ausentes em web/.env.local — teste que precisa de login foi pulado.';

export function credenciaisFin(): { email: string; senha: string } | null {
  const email = process.env.E2E_FIN_EMAIL?.trim();
  const senha = process.env.E2E_FIN_SENHA;
  return email && senha ? { email, senha } : null;
}

/**
 * O sistema só aceita conta da equipe em 3 camadas (tela de login, proxy, RLS gp_eh_equipe()). Robô com e-mail de
 * fora do domínio nunca entra — falha aqui, com a causa, em vez de 60 s esperando a tela.
 */
export function erroDominioRobo(): string | null {
  const cred = credenciaisFin();
  if (!cred || ehEmailDaEquipe(cred.email)) return null;
  return `E2E_FIN_EMAIL não termina em ${DOMINIO_EQUIPE}: a tela de login, o proxy e a RLS recusam conta de fora da `
    + 'equipe. Troque o usuário-robô por um e-mail da equipe.';
}

/** Login pela tela real (/login). Lança erro se a tela recusar — sem ecoar a credencial. */
export async function entrarPelaTela(page: Page, destino = ROTA_FINANCEIRO): Promise<void> {
  const cred = credenciaisFin();
  if (!cred) throw new Error(MOTIVO_SEM_CREDENCIAL);
  await page.goto(`/login?redirect=${encodeURIComponent(destino)}`);
  await page.locator('input[type="email"]').fill(cred.email);
  await page.locator('input[autocomplete="current-password"]').fill(cred.senha);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  // Ou sai do /login (sucesso), ou a tela mostra o alerta de credencial recusada.
  const saiu = page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 60_000 }).then(() => 'ok' as const);
  // `form [role=alert]`: o Next tem um `#__next-route-announcer__` com role=alert fora do formulário.
  const alerta = page.locator('form [role="alert"]');
  const recusou = alerta.waitFor({ state: 'visible', timeout: 60_000 }).then(() => 'recusado' as const);
  const r = await Promise.race([saiu, recusou]);
  if (r === 'recusado') {
    throw new Error(`Login do robô recusado pela tela: "${await alerta.innerText()}"`);
  }
}

/**
 * Reusa a sessão guardada em e2e/.auth/fin.json; só faz login de novo se ela não abrir mais o Financeiro.
 * Poupa o limitador de login do Supabase (1 login por execução no pior caso, 0 no caso comum).
 */
export async function garantirSessao(baseURL: string): Promise<'reusada' | 'nova' | 'sem-credencial'> {
  fs.mkdirSync(path.dirname(ARQUIVO_SESSAO), { recursive: true });
  if (!credenciaisFin()) {
    // Arquivo vazio válido: o config aponta storageState para ele; os specs se pulam com a mensagem.
    fs.writeFileSync(ARQUIVO_SESSAO, JSON.stringify({ cookies: [], origins: [] }));
    return 'sem-credencial';
  }
  const dominio = erroDominioRobo();
  if (dominio) throw new Error(dominio);
  const browser = await chromium.launch();
  try {
    const temArquivo = fs.existsSync(ARQUIVO_SESSAO);
    const ctx = await browser.newContext({ baseURL, storageState: temArquivo ? ARQUIVO_SESSAO : undefined });
    const page = await ctx.newPage();
    await page.goto(ROTA_FINANCEIRO, { timeout: 180_000 });
    let resultado: 'reusada' | 'nova' = 'reusada';
    if (new URL(page.url()).pathname.startsWith('/login')) {
      await entrarPelaTela(page);
      resultado = 'nova';
    }
    await expect(page).toHaveURL(new RegExp(`${ROTA_FINANCEIRO}`), { timeout: 60_000 });
    await ctx.storageState({ path: ARQUIVO_SESSAO });
    return resultado;
  } finally {
    await browser.close();
  }
}
