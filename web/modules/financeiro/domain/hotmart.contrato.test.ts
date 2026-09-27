// Contrato RPC ↔ tipo TS (Fable, 27/09): a aba "Mesma pessoa?" quebrou com 42601 porque um
// ramo do UNION tinha uma coluna a mais — tsc e build não veem SQL. Este teste lê as migrações
// (espelho do corpo vigente no banco) e confere: RETURNS TABLE = colunas do tipo, e cada ramo
// do SELECT final devolve exatamente esse número de colunas.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { COLUNAS_IDENTIDADE_REVISAO, COLUNAS_PESSOA_HOTMART, celulaCsv, rotuloDocumento } from './hotmart';

const migracao = (nome: string) =>
  readFileSync(fileURLToPath(new URL(`../../../../infra/supabase/migrations/${nome}`, import.meta.url)), 'utf8');

/** Divide por vírgula no nível zero (fora de parênteses, colchetes e aspas simples). */
function dividirTopo(s: string): string[] {
  const partes: string[] = [];
  let prof = 0, aspas = false, atual = '';
  for (const c of s) {
    if (c === "'") aspas = !aspas;
    if (!aspas) {
      if (c === '(' || c === '[') prof++;
      if (c === ')' || c === ']') prof--;
      if (c === ',' && prof === 0) { partes.push(atual.trim()); atual = ''; continue; }
    }
    atual += c;
  }
  if (atual.trim()) partes.push(atual.trim());
  return partes;
}

function colunasRetorno(sql: string, funcao: string): string[] {
  const ini = sql.indexOf(`function ${funcao}(`);
  const trecho = sql.slice(ini);
  const a = trecho.indexOf('returns table (') + 'returns table ('.length;
  let prof = 1, i = a;
  while (prof > 0) { if (trecho[i] === '(') prof++; if (trecho[i] === ')') prof--; i++; }
  return dividirTopo(trecho.slice(a, i - 1)).map((c) => c.split(/\s+/)[0]);
}

/** Colunas projetadas entre `select` e o `from` final de um ramo. */
function projecao(ramo: string): string[] {
  const corpo = ramo.replace(/^\s*select\s+/i, '');
  // o FROM do ramo é o último " from " no nível zero
  let prof = 0, aspas = false, corte = -1;
  for (let i = 0; i < corpo.length; i++) {
    const c = corpo[i];
    if (c === "'") aspas = !aspas;
    if (aspas) continue;
    if (c === '(') prof++;
    if (c === ')') prof--;
    if (prof === 0 && /\sfrom\s/i.test(corpo.slice(i, i + 6))) corte = i;
  }
  return dividirTopo(corpo.slice(0, corte));
}

describe('contrato fn_fin_hotmart_pessoas', () => {
  const sql = migracao('20260927e_fin_pessoa_360.sql');
  it('RETURNS TABLE = colunas de PessoaHotmart', () => {
    expect(colunasRetorno(sql, 'public.fn_fin_hotmart_pessoas')).toEqual([...COLUNAS_PESSOA_HOTMART]);
  });
  it('o SELECT final projeta o mesmo número de colunas', () => {
    const corpo = sql.slice(sql.indexOf('function public.fn_fin_hotmart_pessoas('));
    const fim = corpo.indexOf('order by a.valor_atrasado desc');
    const ultimo = corpo.slice(corpo.lastIndexOf('\n  select ', fim), fim);
    expect(projecao(ultimo)).toHaveLength(COLUNAS_PESSOA_HOTMART.length);
  });
});

describe('contrato fn_fin_hotmart_identidade', () => {
  const sql = migracao('20260927f_fin_identidade_revisao_rpc.sql');
  it('RETURNS TABLE = colunas de IdentidadeRevisao', () => {
    expect(colunasRetorno(sql, 'public.fn_fin_hotmart_identidade')).toEqual([...COLUNAS_IDENTIDADE_REVISAO]);
  });
  it.each(['sugestao', 'revisao'])('o ramo "%s" do UNION projeta o mesmo número de colunas (regressão 42601)', (tipo) => {
    const ini = sql.indexOf(`select '${tipo}'`);
    const fim = sql.indexOf(tipo === 'sugestao' ? 'union all' : 'order by 1, 2', ini);
    expect(projecao(sql.slice(ini, fim))).toHaveLength(COLUNAS_IDENTIDADE_REVISAO.length);
  });
});

describe('rotuloDocumento', () => {
  it('dígitos completos: tipo pelo tamanho', () => {
    expect(rotuloDocumento('12345678901')).toBe('CPF ···8901');
    expect(rotuloDocumento('12345678000199')).toBe('CNPJ ···0199');
  });
  it('mascarado pelo banco: mantém o rótulo que veio (CNPJ não vira CPF)', () => {
    expect(rotuloDocumento('CNPJ ···0199')).toBe('CNPJ ···0199');
    expect(rotuloDocumento('CPF ···8901')).toBe('CPF ···8901');
  });
});

describe('celulaCsv', () => {
  it.each(['=HYPERLINK("x")', '+1+1', '-2', '@SUM(A1)', '\tx', '\rx'])('neutraliza fórmula em %j', (v) => {
    expect(celulaCsv(v).replace(/^"/, '').startsWith("'")).toBe(true);
  });
  it('texto comum passa igual; ; e aspas vão entre aspas', () => {
    expect(celulaCsv('Maria')).toBe('Maria');
    expect(celulaCsv('a;b')).toBe('"a;b"');
    expect(celulaCsv('diz "oi"')).toBe('"diz ""oi"""');
    expect(celulaCsv(null)).toBe('');
  });
});
