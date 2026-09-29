// `npm run e2e:prod`: os mesmos testes (somente leitura) contra o site publicado — confere se o deploy subiu.
import { spawnSync } from 'node:child_process';
const r = spawnSync('npx', ['playwright', 'test', ...process.argv.slice(2)], {
  stdio: 'inherit', shell: true, env: { ...process.env, E2E_BASE_URL: process.env.E2E_BASE_URL || 'https://grupoparticipa.app.br' },
});
process.exit(r.status ?? 1);
