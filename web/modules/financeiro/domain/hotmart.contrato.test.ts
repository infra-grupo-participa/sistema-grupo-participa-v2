// Contrato RPC ↔ tipo TS (Fable, 27/09): a aba "Mesma pessoa?" quebrou com 42601 porque um
// ramo do UNION tinha uma coluna a mais — tsc e build não veem SQL. Este teste lê as migrações
// (espelho do corpo vigente no banco) e confere: RETURNS TABLE = colunas do tipo, e cada ramo
// do SELECT final devolve exatamente esse número de colunas.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { COLUNAS_ACELERA_PARA_HM, COLUNAS_BOARD_HOTMART, COLUNAS_IDENTIDADE_REVISAO, COLUNAS_PESSOA_HOTMART, COLUNAS_PRORATA_HM, agruparFaturamento, categoriaInferida, celulaCsv, resumirAdimplencia, rotuloCategorias, rotuloDocumento, type FunilHotmart } from './hotmart';
import { COLUNAS_ASSINATURA_HM_BOARD, COLUNAS_ASSINATURA_HM_SEM_CARD } from './assinatura-hm';

const migracao = (nome: string) =>
  readFileSync(fileURLToPath(new URL(`../../../../infra/supabase/migrations/${nome}`, import.meta.url)), 'utf8');

/** Última migração que (re)define fn_fin_board_hotmart e fn_fin_prorata_hm — o espelho do corpo vigente. */
const ULTIMA_BOARD_PRORATA = '20260928i_fin_nada_faltando.sql';

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
  const sql = migracao('20260928o_fin_board_boleto_telefone.sql');
  it('RETURNS TABLE = colunas de BoardHotmart', () => {
    expect(colunasRetorno(sql, 'public.fn_fin_board_hotmart')).toEqual([...COLUNAS_BOARD_HOTMART]);
  });
  it('o SELECT final projeta o mesmo número de colunas', () => {
    expect(projecao(selectFinal(sql, 'public.fn_fin_board_hotmart'))).toHaveLength(COLUNAS_BOARD_HOTMART.length);
  });
});

describe('contrato fn_fin_prorata_hm', () => {
  const sql = migracao(ULTIMA_BOARD_PRORATA);
  const corpo = sql.slice(inicioCreate(sql, 'public.fn_fin_prorata_hm'), sql.indexOf('end $$;', inicioCreate(sql, 'public.fn_fin_prorata_hm')));
  it('RETURNS TABLE = colunas de ProrataHM', () => {
    expect(colunasRetorno(sql, 'public.fn_fin_prorata_hm')).toEqual([...COLUNAS_PRORATA_HM]);
  });
  it('o SELECT final projeta o mesmo número de colunas', () => {
    expect(projecao(selectFinal(sql, 'public.fn_fin_prorata_hm'))).toHaveLength(COLUNAS_PRORATA_HM.length);
  });
  it('sem Acelera: o espelho é lido só na família HM', () => {
    expect(corpo).toMatch(/t\.familia = 'HM'/);
    expect(corpo).not.toMatch(/ACELERA/);
  });
  it('não devolve documento nem telefone (LGPD)', () => {
    expect(COLUNAS_PRORATA_HM.join(' ')).not.toMatch(/documento|telefone/);
  });
  it('guarda de permissão e grant só para authenticated', () => {
    expect(corpo).toMatch(/gp_pode_ver_financeiro\(\)/);
    expect(sql).toMatch(/revoke all on function public\.fn_fin_prorata_hm\(numeric\) from public, anon;/);
  });
});

describe('contrato fn_fin_board_hotmart — assinatura fora do pago do card', () => {
  const sql = migracao(ULTIMA_BOARD_PRORATA);
  it('o escopo do pago continua sinal / diferenca / compra_cheia', () => {
    const corpo = sql.slice(inicioCreate(sql, 'public.fn_fin_board_hotmart'));
    expect(corpo).toMatch(/cat\.categoria in \('sinal','diferenca','compra_cheia'\)/);
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

describe('celulaCsv — casos do pentest de 27/09', () => {
  it('CR no meio do texto fica entre aspas (não quebra a célula)', () => {
    expect(celulaCsv('x\r=HYPERLINK(A1)')).toBe('"x\r=HYPERLINK(A1)"');
  });
  it('espaço antes do = e = de largura cheia ganham apóstrofo', () => {
    expect(celulaCsv(' =1+1').startsWith("'")).toBe(true);
    expect(celulaCsv('＝1+1').startsWith("'")).toBe(true);
    expect(celulaCsv('＋55 11').startsWith("'")).toBe(true);
  });
  it('texto comum com espaço no início não muda', () => {
    expect(celulaCsv(' Maria')).toBe(' Maria');
  });
});

describe('contrato fn_fin_acelera_para_hm', () => {
  it('RETURNS TABLE = colunas de AceleraParaHM', () => {
    const sql = migracao('20260928e_fin_acelera_para_hm.sql');
    expect(colunasRetorno(sql, 'public.fn_fin_acelera_para_hm')).toEqual([...COLUNAS_ACELERA_PARA_HM]);
  });
});

describe('fn_fin_prorata_hm — desempenho protegido', () => {
  // Sem 'set enable_nestloop = off' a função volta a 34,8 s (medido 27/09). O ajuste tem de estar no CABEÇALHO
  // da última definição: um create or replace sem ele apaga o atributo em silêncio.
  it('última definição declara set enable_nestloop = off antes do corpo', () => {
    const sql = migracao(ULTIMA_BOARD_PRORATA);
    const ini = sql.lastIndexOf('create or replace function public.fn_fin_prorata_hm(');
    const cabecalho = sql.slice(ini, sql.indexOf('as $$', ini));
    expect(cabecalho).toMatch(/set\s+enable_nestloop\s*=\s*off/i);
  });
});

describe('20260928i — nada faltando', () => {
  const sql = migracao(ULTIMA_BOARD_PRORATA);
  it('categoria: mensalidade antes do catálogo, catálogo antes da inferência, e "desconhecida" no fim', () => {
    const f = sql.slice(sql.indexOf('function fin.oferta_categoria'), sql.indexOf('$$;', sql.indexOf('function fin.oferta_categoria')));
    const i = (t: string) => f.indexOf(t);
    expect(i("'mensalidade'")).toBeGreaterThan(-1);
    expect(i("'mensalidade'")).toBeLessThan(i('hm_product_catalog'));
    expect(i('hm_product_catalog')).toBeLessThan(i("'compra_cheia_inferida'"));
    expect(i("'compra_cheia_inferida'")).toBeLessThan(i("'desconhecida'"));
  });
  it('o catálogo que alimenta o webhook não é escrito', () => {
    expect(sql).not.toMatch(/(insert\s+into|update|delete\s+from)\s+public\.hm_product_catalog/i);
  });
  it('outros pagamentos do card excluem o escopo do pago e a assinatura HM', () => {
    const ou = sql.slice(sql.indexOf('), ou as ('), sql.indexOf('), sinc as ('));
    expect(ou).toMatch(/not exists \(select 1 from public\.hm_product_catalog cat[\s\S]*'sinal','diferenca','compra_cheia'/);
    expect(ou).toMatch(/not \(e\.familia = 'HM' and t\.oferta_modo is not distinct from 'SUBSCRIPTION'\)/);
  });
  it('pro rata: entra aluno THB com vencimento mesmo sem venda na Hotmart', () => {
    const corpo = sql.slice(sql.lastIndexOf('create or replace function public.fn_fin_prorata_hm('));
    expect(corpo).toMatch(/where p\.pessoa is not null or al\.thb/);
  });
  it('pessoas: o caminho é recriado do corpo vigente e a troca é conferida', () => {
    expect(sql).toMatch(/pg_get_functiondef\('public\.fn_fin_hotmart_pessoas\(text\)'::regprocedure\)/);
    expect(sql).toMatch(/if n <> 2 then raise exception/);
  });
});

describe('rotuloCategorias', () => {
  it('traduz categorias e mantém separadores', () => {
    expect(rotuloCategorias('renovacao · desconhecida')).toBe('renovação · oferta desconhecida');
    expect(rotuloCategorias('sinal → diferenca → compra_cheia_inferida')).toBe('sinal → saldo → compra cheia (inferida)');
    expect(rotuloCategorias(null)).toBe('—');
  });
});

describe('categoriaInferida (espelho de fin.oferta_categoria)', () => {
  it('mensalidade, compra cheia a partir de 11 mil, senão desconhecida', () => {
    expect(categoriaInferida('SUBSCRIPTION', 20000)).toBe('mensalidade');
    expect(categoriaInferida('UNIQUE_PAYMENT', 11000)).toBe('compra_cheia_inferida');
    expect(categoriaInferida('UNIQUE_PAYMENT', 10999.99)).toBe('desconhecida');
    expect(categoriaInferida(null, null)).toBe('desconhecida');
  });
  it('o limite de 11 mil é o mesmo da função do banco', () => {
    expect(migracao(ULTIMA_BOARD_PRORATA)).toMatch(/when p_valor >= 11000 then 'compra_cheia_inferida'/);
  });
});

describe('resumirAdimplencia', () => {
  const p = (situacao: string, extra: Record<string, unknown> = {}) =>
    ({ situacao, compras_pagas: 1, estornos: 0, cards: 0, valor_atrasado: 0, valor_atrasado_antigo: 0, valor_estornado: 0, ...extra }) as never;
  it('conta só quem pagou, separa com card e soma o valor devido', () => {
    const r = resumirAdimplencia([
      p('ativo'), p('em_pagamento', { cards: 1 }), p('devendo', { valor_atrasado: '1500.5' }),
      p('so_tentou', { compras_pagas: 0 }), p('inadimplencia_antiga', { valor_atrasado_antigo: 300 }),
    ]);
    const por = Object.fromEntries(r.map((l) => [l.chave, l]));
    expect(por.em_dia.pessoas).toBe(2);
    expect(por.em_dia.comCard).toBe(1);
    expect(por.devendo.valor).toBeCloseTo(1500.5);
    expect(por.antiga.valor).toBe(300);
    expect(r.reduce((s, l) => s + l.pessoas, 0)).toBe(4);
    expect(resumirAdimplencia([p('boleto_em_aberto')]).find((l) => l.chave === 'em_dia')!.pessoas).toBe(0);
  });
});

describe('20260928j — produto A_CLASSIFICAR fora da identidade', () => {
  const sql = migracao('20260928j_fin_identidade_sem_a_classificar.sql');
  it('a view da identidade exclui a família A_CLASSIFICAR', () => {
    expect(sql).toMatch(/create or replace view fin\.hotmart_transacoes_identidade[\s\S]*familia = 'A_CLASSIFICAR'/);
    expect(sql).toMatch(/revoke all on fin\.hotmart_transacoes_identidade from public, anon, authenticated/);
  });
  it('recalcular_identidade é recriada do corpo vigente e a troca é conferida (9 leituras)', () => {
    expect(sql).toMatch(/pg_get_functiondef\('fin\.recalcular_identidade\(\)'::regprocedure\)/);
    expect(sql).toMatch(/if n <> 9 then raise exception/);
  });
  it('o diagnóstico do pro rata classifica a venda com a mesma função da lista', () => {
    expect(sql).toMatch(/replace\(v, alvo, 'fin\.oferta_categoria\(t\.oferta_codigo, t\.oferta_modo, t\.valor_oferta\) forma'\)/);
  });
});

describe('20260928k — extrato sem produto A_CLASSIFICAR', () => {
  it('o extrato recriado do corpo vigente filtra a família e confere 1 ocorrência', () => {
    const sql = migracao('20260928k_fin_extrato_sem_a_classificar.sql');
    expect(sql).toMatch(/pg_get_functiondef\('public\.fn_fin_hotmart_extrato\(text\)'::regprocedure\)/);
    expect(sql).toMatch(/and t\.familia <> 'A_CLASSIFICAR'/);
    expect(sql).toMatch(/<> 1 then\s+raise exception/);
  });
});

describe('agruparFaturamento', () => {
  const dia = (d: string, bruto: number, preenchido = false) => ({
    dia: d, preenchido, vendas: bruto ? 1 : 0, bruto, taxa: 0, repasses: 0, liquido: bruto * 0.9, juros: 0, estornos: 0,
    valorEstornado: 0, recusadas: 0, boletos: 0, liquidoEstimado: 0, acumulado: 0, variacaoDiaAnterior: null,
  });
  const serie = [dia('2026-08-30', 100), dia('2026-08-31', 0, true), dia('2026-09-01', 300), dia('2026-09-02', 0, true)];
  let acc = 0; for (const d of serie) { acc += d.bruto; d.acumulado = acc; }
  it('soma por mês, acumulado do último dia e variação contra o mês anterior', () => {
    const m = agruparFaturamento(serie, 'mes');
    expect(m.map((p) => p.chave)).toEqual(['2026-08', '2026-09']);
    expect(m[0].bruto).toBe(100); expect(m[1].bruto).toBe(300);
    expect(m[1].acumulado).toBe(400);
    expect(m[1].variacao).toBe(200);
    expect(m[0].vazio).toBe(false);
  });
  it('por ano junta tudo; por dia mantém os dias vazios marcados', () => {
    expect(agruparFaturamento(serie, 'ano')).toHaveLength(1);
    const d = agruparFaturamento(serie, 'dia');
    expect(d).toHaveLength(4); expect(d[1].vazio).toBe(true);
  });
});


describe('20260928n — ação de todo card do board', () => {
  const sql = migracao('20260928n_fin_acoes_do_board.sql');
  it('não mexe na janela compartilhada com o sistema de disparos', () => {
    expect(sql).not.toMatch(/(insert\s+into|update|delete\s+from)\s+cs\.hm_evento_janela/i);
  });
  it('ordem da regra: janela antiga → link de venda → data → comercial → base antiga → sem pagamento', () => {
    expect(sql).toMatch(/coalesce\(c\.acao_nome, s\.nome, j\.nome,/);
  });
  it('board: guarda nunca falha aberta, grant só para authenticated/service e as 3 colunas novas no fim', () => {
    expect(sql).toMatch(/where coalesce\(public\.gp_pode_ver_financeiro\(\), false\)/);
    expect(sql).toMatch(/revoke all on function public\.fn_fin_board\(text, text\) from public, anon;/);
    expect(sql).toMatch(/pacote_regra numeric, divergencia_regra numeric,\s+acao_regra text, captado_em date, captado_sck text\)/);
  });
  it('o Mapa de alunos saiu', () => {
    expect(sql).toMatch(/drop function if exists public\.fn_fin_mapa_alunos\(\);/);
  });
});

describe('20260928o — boleto em aberto e telefone', () => {
  const sql = migracao('20260928o_fin_board_boleto_telefone.sql');
  it('telefone mascarado para quem não pode ver CPF, e o fallback é recriado do corpo vigente com guarda', () => {
    expect(sql).toMatch(/when coalesce\(public\.gp_pode_ver_cpf\(\), false\) then tl\.comprador_telefone/);
    expect(sql).toMatch(/'···' \|\| right\(/);
    expect(sql).toMatch(/raise exception 'fn_fin_board_hotmart: trecho do telefone não encontrado/);
  });
  it('boleto em aberto: só grupo em_aberto dos últimos 30 dias', () => {
    expect(sql).toMatch(/t\.grupo = 'em_aberto' and t\.dia_pedido >= \(now\(\) at time zone 'America\/Sao_Paulo'\)::date - 30/);
  });
});

describe('20260928z52 — mensalidade do HM antigo', () => {
  const sql = migracao('20260928z52_fin_assinatura_hm.sql');
  const corpoDe = (f: string) => { const i = inicioCreate(sql, f); return sql.slice(i, sql.indexOf('end $$;', i)); };

  it('lista sem card: RETURNS TABLE = colunas de AssinaturaHMSemCard', () => {
    expect(colunasRetorno(sql, 'public.fn_fin_assinatura_hm_sem_card')).toEqual([...COLUNAS_ASSINATURA_HM_SEM_CARD]);
  });
  it('lista sem card: o SELECT final projeta o mesmo número de colunas', () => {
    expect(projecao(selectFinal(sql, 'public.fn_fin_assinatura_hm_sem_card'))).toHaveLength(COLUNAS_ASSINATURA_HM_SEM_CARD.length);
  });
  it('board: RETURNS TABLE = colunas de AssinaturaHMBoard, e o SELECT projeta o mesmo número', () => {
    expect(colunasRetorno(sql, 'public.fn_fin_board_assinatura_hm')).toEqual([...COLUNAS_ASSINATURA_HM_BOARD]);
    const c = corpoDe('public.fn_fin_board_assinatura_hm');
    const sel = c.slice(c.indexOf('  select ', c.indexOf('return query')));
    expect(projecao(sel)).toHaveLength(COLUNAS_ASSINATURA_HM_BOARD.length);
  });
  it('board: a chave é fin.chave_opaca, a mesma do pessoa_chave de fn_fin_board_hotmart', () => {
    expect(corpoDe('public.fn_fin_board_assinatura_hm')).toMatch(/select fin\.chave_opaca\(a\.pessoa\)/);
    expect(migracao('20260928o_fin_board_boleto_telefone.sql')).toMatch(/case when k\.pessoa is not null then fin\.chave_opaca\(k\.pessoa\) end/);
  });
  it('board não devolve dado pessoal', () => {
    expect(COLUNAS_ASSINATURA_HM_BOARD.join(' ')).not.toMatch(/nome|email|documento|telefone/);
  });
  it.each(['public.fn_fin_assinatura_hm_sem_card', 'public.fn_fin_board_assinatura_hm'])('%s: guarda de permissão e grant só para authenticated', (f) => {
    expect(corpoDe(f)).toMatch(/auth\.uid\(\) is null or not coalesce\(public\.gp_pode_ver_financeiro\(\), false\)/);
    expect(sql).toContain(`revoke all on function ${f}() from public, anon;`);
    expect(sql).toContain(`grant execute on function ${f}() to authenticated;`);
  });
  it('lista sem card: documento e telefone completos só para gp_pode_ver_cpf()', () => {
    const c = corpoDe('public.fn_fin_assinatura_hm_sem_card');
    expect(c).toMatch(/v_cpf := coalesce\(public\.gp_pode_ver_cpf\(\), false\)/);
    expect(c).toMatch(/case when v_cpf then a\.documento/);
    expect(c).toMatch(/case when v_cpf then a\.telefone/);
  });
});
