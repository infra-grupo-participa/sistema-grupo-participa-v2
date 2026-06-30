// Token guard (spec identidade-visual, task 0.6).
// Falha se houver cor hex hardcoded no design system (shared/ui).
// Exceções legítimas (NÃO escaneadas): templates de e-mail (clientes de e-mail não suportam
// CSS vars), gráficos/color-pickers em modules/**/ui marcados com /* viz-colors */.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOTS = ['shared/ui'];
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
