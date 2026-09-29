// Contrato RPC ↔ tipo TS do funil do escritório (z92): tsc e build não veem SQL. Lê a migração e confere que o
// RETURNS TABLE das 2 RPCs públicas tem exatamente as colunas (e a ordem) que a tela lê.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { COLUNAS_FUNIL_ESCRITORIO, COLUNAS_PESSOA_FUNIL_ESCRITORIO } from './escritorio-funil';

const sql = readFileSync(fileURLToPath(new URL(
  '../../../../infra/supabase/migrations/20260930z92_fin_escritorio_funil.sql', import.meta.url)), 'utf8');

function colunasRetorno(funcao: string): string[] {
  const nome = funcao.replace(/\./g, '\\.');
  const m = new RegExp(`create\\s+or\\s+replace\\s+function\\s+${nome}\\([^)]*\\)\\s*returns\\s+table\\s*\\(`, 'i').exec(sql);
  if (!m) throw new Error(`create function ${funcao} não encontrado`);
  let prof = 1, i = m.index + m[0].length;
  const a = i;
  while (prof > 0) { if (sql[i] === '(') prof++; if (sql[i] === ')') prof--; i++; }
  return sql.slice(a, i - 1).split(',').map((c) => c.trim().split(/\s+/)[0]);
}

describe('contrato fn_fin_escritorio_funil*', () => {
  it('fn_fin_escritorio_funil: colunas iguais ao tipo', () => {
    expect(colunasRetorno('public.fn_fin_escritorio_funil')).toEqual([...COLUNAS_FUNIL_ESCRITORIO]);
  });
  it('fn_fin_escritorio_funil_pessoas: colunas iguais ao tipo', () => {
    expect(colunasRetorno('public.fn_fin_escritorio_funil_pessoas')).toEqual([...COLUNAS_PESSOA_FUNIL_ESCRITORIO]);
  });
});
