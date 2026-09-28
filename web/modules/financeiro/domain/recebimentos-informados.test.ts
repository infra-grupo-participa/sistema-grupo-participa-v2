import { describe, expect, it } from 'vitest';
import {
  casarResultado, entradaDoFormulario, formDeInformado, identificadorMascarado, mascararLocal, lerColagem, lerDataBR, lerProdutos, lerSimNao, lerTipo, lerTSV, lerValorBR,
  normalizarInformado, normalizarResultadoImportacao, ordenarInformados, previaGravavel, SEM_PERMISSAO_IDENTIFICADOR, TETO_IMPORTACAO,
} from './recebimentos-informados';

const VE = { podeVerDoc: true };
const NAO_VE = { podeVerDoc: false };

// Dados fictícios (CPF de teste gerado, e-mail de domínio reservado).
const CAB = 'Data prevista\tCliente\tTipo\tValor informado\tVia Hotmart? S/N\tProduto na Hotmart\tIdentificador 1\tIdentificador 2\tAcordo a partir de\tBaixa manual';
const L1 = '05/10/2026\tCliente Um\tRenovação Diamante\tR$ 18.750,00\tS\tServiço Diamante\t111.444.777-35\tum@example.com\t01/09/2026\t';
const L2 = '20/10/2026\tCliente Dois\tRenovação Aurum\tR$ 9.000,00\tN\t\t\t\t\t22/10/2026';

describe('campos da planilha', () => {
  it('data dd/mm/aaaa (e ISO); vazio = null; inválida = undefined', () => {
    expect(lerDataBR('05/10/2026')).toBe('2026-10-05');
    expect(lerDataBR('5/1/2027')).toBe('2027-01-05');
    expect(lerDataBR('2026-10-05')).toBe('2026-10-05');
    expect(lerDataBR('  ')).toBeNull();
    expect(lerDataBR('31/02/2026')).toBeUndefined();
    expect(lerDataBR('05/10/26')).toBeUndefined();
    expect(lerDataBR('amanhã')).toBeUndefined();
  });
  it('valor "R$ 18.750,00" e variações; lixo = undefined', () => {
    expect(lerValorBR('R$ 18.750,00')).toBe(18750);
    expect(lerValorBR('R$ 1.238,05')).toBe(1238.05);
    expect(lerValorBR('18750')).toBe(18750);
    expect(lerValorBR('18.750')).toBe(18750);
    expect(lerValorBR('18750,5')).toBe(18750.5);
    expect(lerValorBR('18750.50')).toBe(18750.5);
    expect(lerValorBR('')).toBeNull();
    expect(lerValorBR('dezoito mil')).toBeUndefined();
    expect(lerValorBR('1,2,3')).toBeUndefined();
  });
  it('tipo por texto, sem acento e sem caixa; código também vale', () => {
    expect(lerTipo('Renovação Diamante')).toBe('renovacao_diamante');
    expect(lerTipo('RENOVACAO AURUM')).toBe('renovacao_aurum');
    expect(lerTipo('Diamante extra')).toBe('diamante_extra');
    expect(lerTipo('Serviço Diamante extras')).toBe('diamante_extra');
    expect(lerTipo('Outro')).toBe('outro');
    expect(lerTipo('renovacao_aurum')).toBe('renovacao_aurum');
    expect(lerTipo('')).toBeNull();
    expect(lerTipo('Consultoria')).toBeUndefined();
  });
  it('S/N', () => {
    expect(lerSimNao('S')).toBe(true);
    expect(lerSimNao('sim')).toBe(true);
    expect(lerSimNao('N')).toBe(false);
    expect(lerSimNao('Não')).toBe(false);
    expect(lerSimNao('')).toBeNull();
    expect(lerSimNao('talvez')).toBeUndefined();
  });
  it('produtos separados por ; , | ou quebra', () => {
    expect(lerProdutos('A; B,C | D\nE')).toEqual(['A', 'B', 'C', 'D', 'E']);
    expect(lerProdutos('  ')).toEqual([]);
  });
});

describe('TSV do Google Sheets', () => {
  it('TAB separa célula; CRLF; linha vazia some; célula vazia no fim fica', () => {
    expect(lerTSV('a\tb\t\r\n\r\nc\td\t')).toEqual([['a', 'b', ''], ['c', 'd', '']]);
  });
  it('célula entre aspas com quebra, TAB e "" literal', () => {
    expect(lerTSV('"A\nB"\t"x\ty"\t"diz ""oi"""\n1\t2\t3')).toEqual([['A\nB', 'x\ty', 'diz "oi"'], ['1', '2', '3']]);
  });
});

describe('lerColagem — prévia local', () => {
  it('cabeçalho reconhecido e ignorado; linhas convertidas para as chaves do contrato', () => {
    const c = lerColagem(`${CAB}\n${L1}\n${L2}\n`, VE);
    expect(c.cabecalhoIgnorado).toBe(true);
    expect(c.erroGeral).toBeNull();
    expect(c.linhas.map((l) => l.n)).toEqual([2, 3]);
    expect(c.linhas.every((l) => l.erros.length === 0)).toBe(true);
    expect(c.linhas[0].entrada).toEqual({
      data_prevista: '2026-10-05', cliente: 'Cliente Um', tipo: 'renovacao_diamante', valor: 18750, via_hotmart: true,
      produtos: ['Serviço Diamante'], identificador1: '111.444.777-35', identificador2: 'um@example.com',
      acordo_desde: '2026-09-01', baixa_manual_em: null,
    });
    expect(c.linhas[1].entrada).toMatchObject({ via_hotmart: false, produtos: [], identificador1: null, identificador2: null, baixa_manual_em: '2026-10-22' });
  });
  it('sem cabeçalho: começa na linha 1', () => {
    expect(lerColagem(L1, VE).linhas.map((l) => l.n)).toEqual([1]);
  });
  it('erros por linha, sem repetir o identificador; valor ≤ 0; via S sem produto', () => {
    const c = lerColagem('31/02/2026\t\tConsultoria\t0\tS\t\t111.444.777-35\t\txx\t', VE);
    const e = c.linhas[0].erros;
    expect(e).toEqual(expect.arrayContaining([
      'Data prevista inválida (use dd/mm/aaaa).', 'Cliente vazio.',
      'Tipo não reconhecido (Renovação Diamante, Renovação Aurum, Diamante extra ou Outro).',
      'Valor informado precisa ser maior que zero.', 'Via Hotmart = S exige o produto na Hotmart.',
      'Acordo a partir de: data inválida (use dd/mm/aaaa).',
    ]));
    expect(e.join(' ')).not.toContain('111.444');
  });
  it('colunas a mais é erro; vazio e acima do teto são erro geral', () => {
    expect(lerColagem(`${L1}\textra`, VE).linhas[0].erros[0]).toBe('11 colunas; a planilha tem 10.');
    expect(lerColagem(' \n\t\n', VE).erroGeral).toBe('Nada para importar: cole as linhas da planilha.');
    expect(lerColagem(`${CAB}\n`, VE).erroGeral).not.toBeNull();
    const muitas = Array.from({ length: TETO_IMPORTACAO + 1 }, () => L2).join('\n');
    expect(lerColagem(muitas, VE).erroGeral).toBe(`São ${TETO_IMPORTACAO + 1} linhas; o limite é ${TETO_IMPORTACAO} por importação.`);
    expect(lerColagem(muitas, VE).linhas).toEqual([]);
  });
  it('sem permissão de ver CPF: linha com identificador é erro local; nenhuma entrada leva identificador1/2', () => {
    const c = lerColagem(`${CAB}\n${L1}\n${L2}\n`, NAO_VE);
    expect(c.linhas[0].erros).toEqual([SEM_PERMISSAO_IDENTIFICADOR]);
    expect(c.linhas[0].erros.join(' ')).not.toMatch(/111\.444|example\.com/);
    expect(c.linhas[1].erros).toEqual([]); // L2 não traz identificador: passa
    for (const l of c.linhas) {
      expect(Object.keys(l.entrada)).not.toContain('identificador1');
      expect(Object.keys(l.entrada)).not.toContain('identificador2');
    }
    // só o Identificador 2 preenchido também é erro
    expect(lerColagem('20/10/2026\tC\tOutro\t10\tN\t\t\tx@example.com\t\t', NAO_VE).linhas[0].erros).toEqual([SEM_PERMISSAO_IDENTIFICADOR]);
    // a prévia não fica gravável mesmo que o banco dissesse ok
    const R = (linha: number) => ({ linha, ok: true, erro: null, id: null });
    expect(previaGravavel(c.linhas, [R(1), R(2)])).toBe(false);
  });
});

describe('resultado da importação (prévia do banco)', () => {
  const R = (linha: number, ok = true, erro: string | null = null) => ({ linha, ok, erro, id: null });
  it('normaliza texto do PostgREST', () => {
    expect(normalizarResultadoImportacao({ linha: '2', ok: 't', erro: '', id: null })).toEqual({ linha: 2, ok: true, erro: null, id: null });
  });
  it('casa por posição em base 1 ou base 0; linha sem resultado fica null', () => {
    expect(casarResultado(2, [R(2, false, 'x'), R(1)]).map((r) => r?.linha)).toEqual([1, 2]);
    expect(casarResultado(2, [R(0), R(1)]).map((r) => r?.linha)).toEqual([0, 1]);
    expect(casarResultado(3, [R(1)])).toEqual([R(1), null, null]);
  });
  it('gravável só com tudo ok no banco e nada com erro de leitura', () => {
    const c = lerColagem(`${L1}\n${L2}`, VE);
    expect(previaGravavel(c.linhas, [R(1), R(2)])).toBe(true);
    expect(previaGravavel(c.linhas, [R(1), R(2, false, 'Produto desconhecido')])).toBe(false);
    expect(previaGravavel(c.linhas, [R(1), null])).toBe(false);
    expect(previaGravavel(c.linhas, null)).toBe(false);
    expect(previaGravavel([], [])).toBe(false);
  });
});

describe('lista (fn_fin_informados_listar)', () => {
  it('normaliza numeric em texto, array do Postgres em texto e boolean', () => {
    const i = normalizarInformado({
      id: 'u1', data_prevista: '2026-10-05', cliente: 'C', tipo: 'renovacao_aurum', valor: '9000.00', via_hotmart: 't',
      produtos: '{"Aurum",Outro}', identificador1: '···1234', situacao: 'a_receber', recebido_hotmart: null, acumulado_acordo: '9000',
    });
    expect(i).toMatchObject({ valor: 9000, via_hotmart: true, produtos: ['Aurum', 'Outro'], acumulado_acordo: 9000, recebido_hotmart: null, identificador2: null });
  });
  it('máscara reconhecida (CPF ···1234, e-mail a***@dominio); valor em claro não', () => {
    expect(identificadorMascarado('···1234')).toBe(true);
    expect(identificadorMascarado('a***@example.com')).toBe(true);
    expect(identificadorMascarado('111.444.777-35')).toBe(false);
    expect(identificadorMascarado(null)).toBe(false);
  });
  it('ordem: data prevista, cliente; sem data no fim', () => {
    const b = normalizarInformado({ id: 'b', cliente: 'B', data_prevista: '2026-10-01' });
    const a = normalizarInformado({ id: 'a', cliente: 'A', data_prevista: '2026-10-01' });
    const z = normalizarInformado({ id: 'z', cliente: 'Z', data_prevista: null });
    const x = normalizarInformado({ id: 'x', cliente: 'X', data_prevista: '2026-09-01' });
    expect(ordenarInformados([z, b, a, x]).map((i) => i.id)).toEqual(['x', 'a', 'b', 'z']);
  });
});

describe('formulário criar/editar', () => {
  const orig = normalizarInformado({
    id: 'u1', data_prevista: '2026-10-05', cliente: 'Cliente Um', tipo: 'renovacao_diamante', valor: '18750', via_hotmart: true,
    produtos: ['Serviço Diamante'], identificador1: '···7735', identificador2: 'u***@example.com', acordo_desde: '2026-09-01',
    baixa_manual_em: '2026-10-06', situacao: 'baixado_fora',
  });
  it('máscara nunca entra no campo', () => {
    expect(formDeInformado(orig, false)).toMatchObject({
      identificador1: '', identificador2: '', valor: '18750,00', via_hotmart: 'S', produtos: 'Serviço Diamante',
    });
    expect(formDeInformado(orig, true)).toMatchObject({ identificador1: '', identificador2: '' });
  });
  it('edição sem mexer no identificador oculto: chave AUSENTE (manter); baixa nunca vai', () => {
    const { entrada, erros } = entradaDoFormulario(formDeInformado(orig, false), orig, false);
    expect(erros).toEqual([]);
    expect(entrada).toEqual({
      id: 'u1', data_prevista: '2026-10-05', cliente: 'Cliente Um', tipo: 'renovacao_diamante', valor: 18750, via_hotmart: true,
      produtos: ['Serviço Diamante'], acordo_desde: '2026-09-01',
    });
    expect(Object.keys(entrada ?? {})).not.toContain('identificador1');
    expect(Object.keys(entrada ?? {})).not.toContain('baixa_manual_em');
  });
  it('sem permissão de ver CPF: identificador digitado NÃO vai (chaves ausentes), na edição e na criação', () => {
    // O campo fica desabilitado na tela; mesmo com valor no estado, o p não leva identificador (banco daria P0001).
    const f = { ...formDeInformado(orig, false), identificador1: 'novo@example.com', identificador2: '111.444.777-35' };
    const ed = entradaDoFormulario(f, orig, false).entrada;
    expect(Object.keys(ed ?? {})).not.toContain('identificador1');
    expect(Object.keys(ed ?? {})).not.toContain('identificador2');
    const novo = {
      ...formDeInformado(null, false), data_prevista: '2026-11-10', cliente: 'Novo', tipo: 'outro', valor: '1000', via_hotmart: 'N' as const,
      identificador1: 'novo@example.com',
    };
    expect(entradaDoFormulario(novo, null, false).entrada).toEqual({
      data_prevista: '2026-11-10', cliente: 'Novo', tipo: 'outro', valor: 1000, via_hotmart: false, produtos: [], acordo_desde: null,
      baixa_manual_em: null,
    });
  });
  it('quem vê CPF, edição digitando identificador novo: vai em claro', () => {
    const f = { ...formDeInformado(orig, true), identificador1: 'novo@example.com' };
    expect(entradaDoFormulario(f, orig, true).entrada).toMatchObject({ identificador1: 'novo@example.com' });
    expect(Object.keys(entradaDoFormulario(f, orig, true).entrada ?? {})).not.toContain('identificador2'); // mascarado e vazio: manter
  });
  it('quem vê documento e apaga o identificador em claro: vai null (limpar)', () => {
    const claro = { ...orig, identificador1: '111.444.777-35', identificador2: null };
    expect(formDeInformado(claro, true).identificador1).toBe('111.444.777-35');
    const f = { ...formDeInformado(claro, true), identificador1: '' };
    expect(entradaDoFormulario(f, claro, true).entrada).toMatchObject({ identificador1: null, identificador2: null });
  });
  it('criação: sem id, identificadores vazios = null, baixa = null', () => {
    const f = {
      ...formDeInformado(null, true), data_prevista: '2026-11-10', cliente: 'Novo', tipo: 'outro', valor: 'R$ 1.000,00', via_hotmart: 'N' as const,
    };
    expect(entradaDoFormulario(f, null, true).entrada).toEqual({
      data_prevista: '2026-11-10', cliente: 'Novo', tipo: 'outro', valor: 1000, via_hotmart: false, produtos: [], acordo_desde: null,
      baixa_manual_em: null, identificador1: null, identificador2: null,
    });
  });
  it('obrigatórios', () => {
    const { entrada, erros } = entradaDoFormulario(formDeInformado(null, true), null, true);
    expect(entrada).toBeNull();
    expect(erros).toEqual([
      'Data prevista obrigatória.', 'Cliente obrigatório.', 'Tipo obrigatório.', 'Valor precisa ser maior que zero.', 'Informe se é via Hotmart.',
    ]);
  });
});

describe('máscara local da prévia', () => {
  it('não reexibe CPF nem e-mail em claro', () => {
    expect(mascararLocal('111.444.777-35')).toBe('···7735');
    expect(mascararLocal('um@example.com')).toBe('u***@example.com');
    expect(mascararLocal(null)).toBe('—');
  });
});
