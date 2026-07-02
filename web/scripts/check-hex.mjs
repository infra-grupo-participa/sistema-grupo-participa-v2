// Token guard (spec identidade-visual, task 0.6).
// Falha se houver cor hex hardcoded fora de app/globals.css (fonte de verdade dos tokens).
// Exceções legítimas por linha: /* hex-ok */ (e-mails — clientes não suportam CSS vars;
// contraste fixo) e /* viz-colors */ (gráficos/color-pickers com cor definida pelo usuário).
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOTS = ['shared', 'modules', 'app'];
// Arquivos inteiros fora do guard:
// - globals.css é a fonte de verdade dos tokens;
// - templates de e-mail usam hex por obrigação (clientes de e-mail não suportam CSS vars);
// - solicitar-placa.css é a identidade própria da página pública (bloco de tokens independente).
const SKIP_FILES = new Set([
  join('app', 'globals.css'),
  join('shared', 'infrastructure', 'email', 'template.ts'),
  join('modules', 'placas', 'application', 'email-content.ts'),
  join('modules', 'placas', 'ui', 'solicitar-placa.css'),
]);
const HEX = /#[0-9a-fA-F]{3,8}\b/;
const offenders = [];

function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const s = statSync(p);
    if (s.isDirectory()) walk(p);
    else if (/\.(tsx?|css)$/.test(name)) scan(p);
  }
}

function scan(file) {
  if (SKIP_FILES.has(file)) return;
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    if (line.includes('viz-colors') || line.includes('hex-ok')) return;
    if (HEX.test(line)) offenders.push(`${file}:${i + 1}  ${line.trim()}`);
  });
}

for (const r of ROOTS) walk(r);

if (offenders.length) {
  console.error(`\n✗ hex hardcoded no design system (use tokens de globals.css):\n${offenders.join('\n')}\n`);
  process.exit(1);
}
console.log('✓ design system sem hex hardcoded');
