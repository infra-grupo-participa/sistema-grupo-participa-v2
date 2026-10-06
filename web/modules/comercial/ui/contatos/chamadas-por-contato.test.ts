// Guarda do ajuste rápido de 06/10/2026: nenhuma tela do Comercial busca dado de cada contato em massa.
// A tela Contatos chamava `repo.jornada(id)` para cada pessoa, todas em paralelo (~2.200 chamadas por abertura
// para um vendedor). O histórico agora só é buscado na ficha, uma pessoa por vez.
// Sem teste de componente .tsx no projeto (regra do CLAUDE.md): a prova é sobre o código-fonte das telas.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

const UI = path.resolve(__dirname, '..');
const ler = (rel: string) => readFileSync(path.join(UI, rel), 'utf8');
/** Código sem comentários (o texto explicativo pode citar o que foi removido). */
const semComentarios = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

function telas(dir = UI): string[] {
  return readdirSync(dir).flatMap((n) => {
    const p = path.join(dir, n);
    if (statSync(p).isDirectory()) return telas(p);
    return /\.tsx?$/.test(n) && !/\.test\.ts$/.test(n) ? [p] : [];
  });
}

describe('tela Contatos', () => {
  const fonte = semComentarios(ler('contatos/ContatosClient.tsx'));

  it('não chama o histórico (jornada) de nenhum contato', () => {
    expect(fonte).not.toMatch(/repo\s*\.\s*jornada\s*\(/);
  });

  it('não dispara chamadas ao repositório em lote (Promise.all / map async)', () => {
    expect(fonte).not.toMatch(/Promise\s*\.\s*all/);
    expect(fonte).not.toMatch(/\.map\(\s*async/);
  });
});

describe('ficha do contato', () => {
  it('busca a jornada de uma pessoa só, pelo id aberto', () => {
    const fonte = semComentarios(ler('contatos/ContatoDrawer.tsx'));
    const chamadas = fonte.match(/repo\s*\.\s*jornada\s*\([^)]*\)/g) ?? [];
    expect(chamadas).toEqual(['repo.jornada(contatoId)']);
  });
});

describe('todas as telas do Comercial', () => {
  it('nenhuma chama o repositório dentro de laço sobre uma lista', () => {
    const suspeitas = telas().flatMap((arq) => {
      const fonte = semComentarios(readFileSync(arq, 'utf8'));
      const achados = [
        ...(fonte.match(/Promise\s*\.\s*all(Settled)?\s*\([^;]*?repo\s*\./g) ?? []),
        ...(fonte.match(/\.(map|forEach|flatMap)\(\s*async[^;]*?repo\s*\./g) ?? []),
        ...(fonte.match(/for\s*\([^)]*\)\s*\{?[^}]*?await\s+repo\s*\./g) ?? []),
      ];
      return achados.map(() => path.relative(UI, arq));
    });
    expect(suspeitas).toEqual([]);
  });
});
