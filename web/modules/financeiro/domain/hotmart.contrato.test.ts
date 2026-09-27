// Contrato RPC ↔ tipo TS (Fable, 27/09): a aba "Mesma pessoa?" quebrou com 42601 porque um
// ramo do UNION tinha uma coluna a mais — tsc e build não veem SQL. Este teste lê as migrações
// (espelho do corpo vigente no banco) e confere: RETURNS TABLE = colunas do tipo, e cada ramo
// do SELECT final devolve exatamente esse número de colunas.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { COLUNAS_BOARD_HOTMART, COLUNAS_IDENTIDADE_REVISAO, COLUNAS_PESSOA_HOTMART, celulaCsv, rotuloDocumento, type FunilHotmart } from './hotmart';

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

/** Posição do CREATE da função — não do `drop function <nome>(...)` que o precede na migração. */
function inicioCreate(sql: string, funcao: string): number {
  const nome = funcao.replace(/\./g, '\\.');
  const m = new RegExp(`create\\s+(or\\s+replace\\s+)?function\\s+${nome}\\(`, 'i').exec(sql);
  if (!m) throw new Error(`create function ${funcao} não encontrado`);
  return m.index;
}

function colunasRetorno(sql: string, funcao: string): string[] {
  const trecho = sql.slice(inicioCreate(sql, funcao));
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

/** Último `select` do corpo antes do `order by` final da função. */
function selectFinal(sql: string, funcao: string): string {
  const corpo = sql.slice(inicioCreate(sql, funcao));
  const fim = corpo.indexOf('\n   order by ');
  return corpo.slice(corpo.lastIndexOf('\n  select ', fim), fim);
}

describe('contrato fn_fin_hotmart_pessoas', () => {
  const sql = migracao('20260928b_fin_pessoas_operacao.sql');
  it('RETURNS TABLE = colunas de PessoaHotmart', () => {
    expect(colunasRetorno(sql, 'public.fn_fin_hotmart_pessoas')).toEqual([...COLUNAS_PESSOA_HOTMART]);
  });
  it('o SELECT final projeta o mesmo número de colunas', () => {
    expect(projecao(selectFinal(sql, 'public.fn_fin_hotmart_pessoas'))).toHaveLength(COLUNAS_PESSOA_HOTMART.length);
  });
});

describe('contrato fn_fin_board_hotmart', () => {
  const sql = migracao('20260928c_fn_fin_board_hotmart.sql');
  it('RETURNS TABLE = colunas de BoardHotmart', () => {
    expect(colunasRetorno(sql, 'public.fn_fin_board_hotmart')).toEqual([...COLUNAS_BOARD_HOTMART]);
  });
  it('o SELECT final projeta o mesmo número de colunas', () => {
    expect(projecao(selectFinal(sql, 'public.fn_fin_board_hotmart'))).toHaveLength(COLUNAS_BOARD_HOTMART.length);
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

describe('contrato fn_fin_hotmart_faturamento', () => {
  // O preset "Tudo" cresce todo dia. Um teto fixo de dias na RPC já quebrou a tela duas vezes
  // (3 anos cortava o HM de ago/2023; 7 anos voltaria a dar 400 em 2028). O custo é o das transações, não do intervalo.
  it('não tem teto fixo de dias no período', () => {
    const sql = migracao('20260927b_fin_relatorios_hotmart.sql');
    const corpo = sql.slice(sql.lastIndexOf('function public.fn_fin_hotmart_faturamento('));
    const fim = corpo.indexOf('end $$;');
    expect(corpo.slice(0, fim)).not.toMatch(/v_fim\s*-\s*v_ini\s*>\s*\d+/);
  });
});

describe('contrato fn_fin_hotmart_funis', () => {
  const COLUNAS_FUNIL = [
    'funil', 'vale_de', 'vale_ate', 'vendas', 'compradores', 'valor_oferta', 'cobrado_cliente', 'juros', 'taxa_hotmart',
    'liquido', 'estornos', 'valor_estornado', 'recusadas', 'boletos', 'parcelado', 'parcelas_media',
  ] as const satisfies readonly (keyof FunilHotmart)[];
  it('RETURNS TABLE = colunas de FunilHotmart', () => {
    const sql = migracao('20260927h_fin_acelera_e_funis.sql');
    expect(colunasRetorno(sql, 'public.fn_fin_hotmart_funis')).toEqual([...COLUNAS_FUNIL]);
  });
});
