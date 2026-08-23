// Gate de tipos das Edge Functions (Deno) — `npm run lint:edge`.
//
// Por que existe: `tsc --noEmit` do app cobre só `web/`. As functions em
// `infra/supabase/functions/**` ficavam fora de qualquer trava, e em 23/08/2026 um
// `const existente` duplicado no mesmo escopo passou por revisão humana, por
// checagem de sintaxe e pelo build verde do web — só apareceu porque alguém
// rodou o compilador na mão. `supabase functions deploy` teria falhado no bundle.
//
// O que ele NÃO faz: resolver os imports remotos do Deno (`https://`, `jsr:`,
// `npm:`) nem carregar as libs do runtime Deno. Esses erros são filtrados de
// propósito — o alvo aqui é erro de código nosso: símbolo duplicado, variável
// inexistente, propriedade que não existe no tipo, retorno incompatível.
import { readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const RAIZ = join(fileURLToPath(new URL('.', import.meta.url)), '..', '..');
const DIR_FUNCTIONS = join(RAIZ, 'infra', 'supabase', 'functions');

// Erros que decorrem de o Deno não estar disponível aqui, não de código errado.
const IGNORADOS = new Set([
  2307, // Cannot find module 'https://…' / 'jsr:…'
  2304, // Cannot find name 'Deno'
  2583, // requires lib 'esnext' etc.
  2585,
  2318, // Cannot find global type
  2503, // Cannot find namespace
  // Com `noResolve`, o tipo de callbacks vindos de lib externa (o `req` de
  // `serve()`, o `r` de `.then()`) não resolve e vira implicit any. É ruído da
  // checagem, não do código — o Deno tipa esses parâmetros normalmente.
  7006, // Parameter implicitly has an 'any' type
  7031, // Binding element implicitly has an 'any' type
]);

function listarEntrypoints(dir) {
  let saida = [];
  for (const nome of readdirSync(dir)) {
    const caminho = join(dir, nome);
    if (statSync(caminho).isDirectory()) saida = saida.concat(listarEntrypoints(caminho));
    else if (nome.endsWith('.ts')) saida.push(caminho);
  }
  return saida;
}

const arquivos = listarEntrypoints(DIR_FUNCTIONS);
if (arquivos.length === 0) {
  console.log('nenhuma edge function encontrada — nada a checar');
  process.exit(0);
}

const programa = ts.createProgram(arquivos, {
  noEmit: true,
  allowJs: false,
  target: ts.ScriptTarget.ESNext,
  module: ts.ModuleKind.ESNext,
  moduleResolution: ts.ModuleResolutionKind.Bundler,
  strict: true,
  skipLibCheck: true,
  noResolve: true, // não tenta baixar https:// — o filtro acima cuida do ruído
});

const diagnosticos = ts
  .getPreEmitDiagnostics(programa)
  .filter((d) => !IGNORADOS.has(d.code))
  .filter((d) => d.file && d.file.fileName.includes('infra'));

if (diagnosticos.length === 0) {
  console.log(`✓ ${arquivos.length} edge function(s) sem erro de tipo`);
  process.exit(0);
}

for (const d of diagnosticos) {
  const { line, character } = d.file.getLineAndCharacterOfPosition(d.start ?? 0);
  const arquivo = relative(RAIZ, d.file.fileName).replace(/\\/g, '/');
  const msg = ts.flattenDiagnosticMessageText(d.messageText, ' ');
  console.error(`${arquivo}:${line + 1}:${character + 1} — TS${d.code}: ${msg}`);
}
console.error(`\n✗ ${diagnosticos.length} erro(s) de tipo nas edge functions`);
process.exit(1);
