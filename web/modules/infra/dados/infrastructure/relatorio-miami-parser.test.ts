// Leitor puro da aba `Relatório` (Edge dados-planilha-relatorio, migration 20261016240000), testado SEM Google e SEM banco.
// A grade abaixo reproduz o layout de 16/10/2026 da planilha "Dados [MIAMI 2026]" (títulos, rótulos e cabeçalhos exatos),
// com nomes, e-mails e telefones INVENTADOS. Nenhum dado pessoal real.
import { describe, expect, it } from 'vitest';
import {
  BLOCOS, TETO_CELULA, TETO_LINHAS, inteiroBR, parseRelatorioMiami,
} from '../../../../../infra/supabase/functions/dados-planilha-relatorio/relatorio-miami';

const def = (chave: string) => BLOCOS.find((b) => b.chave === chave)!;
const cabDiamantes = (def('diamantes') as { colunas: string[] }).colunas;
const cabCompradores = (def('compradores') as { colunas: string[] }).colunas;

type Grade = string[][];
function pôr(g: Grade, linha1: number, col1: number, valores: string[]) {
  while (g.length < linha1) g.push([]);
  const l = g[linha1 - 1];
  valores.forEach((v, i) => { while (l.length < col1 - 1 + i) l.push(''); l[col1 - 1 + i] = v; });
}

/** n pessoas na Lista Diamantes e m compradores; o resto como na planilha de 16/10/2026. */
function montar(n = 3, m = 2, opts: { cortarDiamantes?: boolean } = {}): Grade {
  const g: Grade = [];
  pôr(g, 1, 1, ['Relatório de preenchimento – Miami 2026']);
  pôr(g, 2, 1, ['Nota de uso fixa da planilha.']);
  pôr(g, 4, 1, ['Formulário dados iniciais de presença']);
  pôr(g, 4, 4, ['Time (Clínica): formulário dos compradores']);
  [
    ['Pessoas na Lista Diamantes', String(n)], ['Respostas recebidas no formulário', '70'], ['Da lista, já preencheram', '67'],
    ['Da lista, faltam preencher', '9'], ['% de preenchimento', '88,2%'], ['Respostas sem correspondência na lista', '3'],
    ['Situação de quem respondeu'], ['Confirmados, com viagem organizada', '31'],
    ['Se organizando, ainda não confirmados', '17'], ['Não irão participar', '19'],
  ].forEach((l, i) => pôr(g, 5 + i, 1, l));
  [
    ['Compradores da Clínica', String(m)], ['Já responderam', '8'], ['Faltam responder', '5'], ['% de preenchimento', '61,5%'],
    ['Respostas recebidas (pessoas únicas)', '8'], ['Respostas sem correspondência na lista de compradores', '0'],
  ].forEach((l, i) => pôr(g, 5 + i, 4, l));
  pôr(g, 16, 1, ['Formulário de participação nos eventos (Miami)']);
  [
    ['Respostas recebidas (pessoas únicas)', '27'], ['Confirmados que já preencheram', '26'],
    ['Confirmados que ainda não preencheram (clique no número para ver quem)', '5'],
  ].forEach((l, i) => pôr(g, 17 + i, 1, l));
  pôr(g, 16, 4, ['Camisas (última resposta de cada pessoa)', 'Diamante', 'Time', 'Total']);
  [['P', '6', '0', '6'], ['M', '9', '4', '13'], ['G', '10', '3', '13'], ['GG', '2', '1', '3'], ['Total', '27', '8', '35']]
    .forEach((l, i) => pôr(g, 17 + i, 4, l));
  pôr(g, 23, 1, (def('presenca') as { colunas: string[] }).colunas);
  [
    ['Reunião do Diamante Vermelho', '30/11', '9', '0', '—', '9', '—', '—', '—', '—', '9'],
    ['Happy Hour de boas-vindas', '30/11, 7pm', '25', '2', '9', '34', '7', '1', '0', '7', '41'],
    ['Encontro + Clínica Internacional', '1 e 2/12', '27', '0', '—', '27', '13', '—', '—', '13', '40'],
    ['Experiência', '3/12', '26', '1', '—', '26', '8', '0', '—', '8', '34'],
    ['Festa do Diamante', '4/12', '26', '1', '—', '26', '—', '—', '—', '—', '26'],
    ['Festa dos Iates', '5/12', '23', '4', '13', '36', '6', '2', '1', '7', '43'],
    ['Enterro dos Ossos', '6/12', '21', '6', '11', '32', '—', '—', '—', '—', '32'],
  ].forEach((l, i) => pôr(g, 24 + i, 1, l));
  pôr(g, 31, 1, ['Respostas por pessoa da Lista Diamantes']);
  pôr(g, 32, 1, [...cabDiamantes, 'Lacunas (aux)', 'Linha na aba Participação (aux)']);
  for (let i = 0; i < n; i++) {
    const linha = [
      `Pessoa Teste ${i + 1}`, `Pessoa Teste ${i + 1}`, 'Respondeu', `pessoa${i + 1}@exemplo.invalido`, `+55 00 00000-000${i}`,
      'Diamante Titular', 'Já estou confirmado(a) e com a viagem organizada.', '27/11/2026', '08/12/2026', 'MIA', 'Hotel Teste',
      'Não, irei sozinho(a)', '', '13/10/2026 15:00', 'Respondeu', 'Vai', 'Vai', 'Vai', 'Vai', 'Vai', 'Não vai', 'Não vai', '', String(i + 2),
    ];
    // O Sheets corta as células vazias do fim da linha.
    pôr(g, 33 + i, 1, opts.cortarDiamantes && i === 0 ? linha.slice(0, 12) : linha);
  }
  // A "vaga" a mais do bloco de tamanho fixo (A33:A109): coluna A vazia, mas outras fórmulas devolvem texto.
  pôr(g, 33 + n, 3, ['Pendente']);
  pôr(g, 110, 1, ['Compradores da Clínica (Time): situação por comprador']);
  pôr(g, 111, 1, cabCompradores);
  for (let i = 0; i < m; i++) {
    pôr(g, 112 + i, 1, [
      `Comprador Teste ${i + 1}`, `comprador${i + 1}@exemplo.invalido`, `1100000000${i}`, 'PLATINA', 'T14', 'Respondeu', 'Sim',
      '30/11/2026', '07/12/2026', 'MIA', '0', 'Vai', 'Vai', 'Vai', 'Não vai', 'Hotel Teste',
    ]);
  }
  return g;
}

describe('inteiroBR', () => {
  it('lê contagem e recusa o que não é inteiro', () => {
    expect(inteiroBR('76')).toBe(76);
    expect(inteiroBR('1.234')).toBe(1234);
    expect(inteiroBR('88,2%')).toBeNull();
    expect(inteiroBR('—')).toBeNull();
    expect(inteiroBR(null)).toBeNull();
  });
});

describe('parseRelatorioMiami: grade completa', () => {
  const r = parseRelatorioMiami(montar(3, 2));
  if (!r.ok) throw new Error(r.erro);
  const b = r.conteudo.blocos;

  it('devolve versão 1, a aba e nenhum aviso quando tudo fecha', () => {
    expect(r.conteudo.versao).toBe(1);
    expect(r.conteudo.aba).toBe('Relatório');
    expect(r.conteudo.avisos).toEqual([]);
    expect(Object.keys(b)).toEqual(['dados_iniciais', 'time_formulario', 'participacao', 'camisas', 'presenca', 'diamantes', 'compradores']);
  });

  it('lê os KPIs pelo rótulo dentro do bloco: rótulo repetido não mistura os blocos', () => {
    const v = (k: { itens: { rotulo: string; valor: string | null }[] }, rotulo: string) => k.itens.find((x) => x.rotulo === rotulo)?.valor;
    expect(v(b.dados_iniciais, '% de preenchimento')).toBe('88,2%');
    expect(v(b.time_formulario, '% de preenchimento')).toBe('61,5%');
    expect(v(b.dados_iniciais, 'Pessoas na Lista Diamantes')).toBe('3');
    expect(v(b.time_formulario, 'Compradores da Clínica')).toBe('2');
    expect(v(b.participacao, 'Confirmados que ainda não preencheram (clique no número para ver quem)')).toBe('5');
    expect(b.dados_iniciais.itens).toHaveLength(10);
    expect(b.time_formulario.itens).toHaveLength(6);
    expect(b.participacao.itens).toHaveLength(3);
  });

  it('subtítulo sem valor vira valor null, na ordem da planilha', () => {
    expect(b.dados_iniciais.itens[6]).toEqual({ rotulo: 'Situação de quem respondeu', valor: null });
  });

  it('camisas: 5 linhas, a coluna do lado não vaza', () => {
    expect(b.camisas.colunas).toEqual(['Camisas (última resposta de cada pessoa)', 'Diamante', 'Time', 'Total']);
    expect(b.camisas.linhas).toEqual([['P', '6', '0', '6'], ['M', '9', '4', '13'], ['G', '10', '3', '13'], ['GG', '2', '1', '3'], ['Total', '27', '8', '35']]);
  });

  it('presença: 7 eventos, o travessão continua texto e nunca vira 0', () => {
    expect(b.presenca.linhas).toHaveLength(7);
    expect(b.presenca.colunas).toHaveLength(11);
    expect(b.presenca.linhas[0]).toEqual(['Reunião do Diamante Vermelho', '30/11', '9', '0', '—', '9', '—', '—', '—', '—', '9']);
    expect(b.presenca.linhas[5][10]).toBe('43');
  });

  it('diamantes: para na vaga sem nome, descarta as colunas auxiliares e mantém 22 colunas', () => {
    expect(b.diamantes.linhas).toHaveLength(3);
    expect(b.diamantes.colunas).toEqual(cabDiamantes);
    expect(b.diamantes.colunas).toHaveLength(22);
    for (const l of b.diamantes.linhas) expect(l).toHaveLength(22);
    expect(b.diamantes.linhas[0].slice(0, 5)).toEqual(['Pessoa Teste 1', 'Pessoa Teste 1', 'Respondeu', 'pessoa1@exemplo.invalido', '+55 00 00000-0000']);
    expect(b.diamantes.linhas.flat()).not.toContain('Pendente');
  });

  it('compradores: 16 colunas, uma linha por comprador, sem a coluna auxiliar', () => {
    expect(b.compradores.colunas).toEqual(cabCompradores);
    expect(b.compradores.linhas).toHaveLength(2);
    expect(b.compradores.linhas[1][0]).toBe('Comprador Teste 2');
    expect(b.compradores.linhas[1]).toHaveLength(16);
  });
});

describe('parseRelatorioMiami: layout que se mexe', () => {
  it('completa a linha que o Sheets cortou nas células finais vazias', () => {
    const r = parseRelatorioMiami(montar(2, 1, { cortarDiamantes: true }));
    if (!r.ok) throw new Error(r.erro);
    const l = r.conteudo.blocos.diamantes.linhas[0];
    expect(l).toHaveLength(22);
    expect(l[11]).toBe('Não, irei sozinho(a)');
    expect(l.slice(12)).toEqual(Array(10).fill(''));
  });

  it('acha os blocos mesmo com linhas inseridas no topo e colunas inseridas à esquerda', () => {
    const g = montar(2, 1).map((l) => ['', ...l]);
    g.unshift([], []);
    const r = parseRelatorioMiami(g);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.conteudo.blocos.diamantes.linhas).toHaveLength(2);
      expect(r.conteudo.blocos.time_formulario.itens[0]).toEqual({ rotulo: 'Compradores da Clínica', valor: '1' });
    }
  });

  it('célula nula ou número vindo do Google vira texto', () => {
    const g = montar(1, 1) as unknown as (string | number | null)[][];
    g[4][1] = 76;
    g[5][1] = null;
    const r = parseRelatorioMiami(g);
    expect(r.ok).toBe(true);
  });
});

describe('parseRelatorioMiami: falha e não grava nada parcial', () => {
  it.each([[[]], [null], ['texto']])('entrada vazia ou inválida (%j)', (entrada) => {
    expect(parseRelatorioMiami(entrada)).toEqual({ ok: false, erro: 'aba_vazia' });
  });

  it('título ausente', () => {
    const g = montar();
    g[30][0] = 'Respostas por pessoa (renomeado)';
    expect(parseRelatorioMiami(g)).toEqual({ ok: false, erro: 'titulo_ausente:diamantes' });
  });

  it('título duplicado', () => {
    const g = montar();
    pôr(g, 120, 1, ['Presença por evento']);
    expect(parseRelatorioMiami(g)).toEqual({ ok: false, erro: 'titulo_duplicado:presenca' });
  });

  it('cabeçalho mudado: diz o bloco e a posição, nunca o texto da célula', () => {
    const g = montar();
    g[31][3] = 'Joana Exemplo Secreta'; // deslocamento: um dado pessoal cai onde era o cabeçalho "E-mail"
    const r = parseRelatorioMiami(g);
    expect(r).toEqual({ ok: false, erro: 'cabecalho_diferente:diamantes:3' });
    expect(JSON.stringify(r)).not.toContain('Secreta');
  });

  it('cabeçalho da presença com uma coluna a menos', () => {
    const g = montar();
    g[22].splice(4, 1);
    expect(parseRelatorioMiami(g)).toEqual({ ok: false, erro: 'cabecalho_diferente:presenca:4' });
  });

  it('rótulo de KPI renomeado', () => {
    const g = montar();
    g[4][0] = 'Pessoas na lista dos Diamantes';
    const r = parseRelatorioMiami(g);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.erro).toBe('rotulo_ausente:dados_iniciais:0');
  });
});

describe('parseRelatorioMiami: avisos de integridade', () => {
  it('Diamantes com menos linhas do que "Pessoas na Lista Diamantes"', () => {
    const g = montar(3, 2);
    pôr(g, 5, 2, ['5']);
    const r = parseRelatorioMiami(g);
    if (!r.ok) throw new Error(r.erro);
    expect(r.conteudo.avisos.map((a) => a.codigo)).toEqual(['diamantes_linhas_menos_que_a_lista']);
    expect(r.conteudo.avisos[0].texto).toContain('5');
    expect(r.conteudo.avisos[0].texto).toContain('3 linha(s)');
  });

  it('compradores com menos linhas do que "Compradores da Clínica"', () => {
    const g = montar(3, 2);
    pôr(g, 5, 5, ['4']);
    const r = parseRelatorioMiami(g);
    if (!r.ok) throw new Error(r.erro);
    expect(r.conteudo.avisos.map((a) => a.codigo)).toEqual(['compradores_linhas_menos_que_os_compradores']);
  });

  it('contagem ilegível avisa em vez de ficar calado', () => {
    const g = montar(3, 2);
    pôr(g, 5, 2, ['#REF!']);
    const r = parseRelatorioMiami(g);
    if (!r.ok) throw new Error(r.erro);
    expect(r.conteudo.avisos.map((a) => a.codigo)).toEqual(['diamantes_linhas_menos_que_a_lista_ilegivel']);
  });
});

describe('parseRelatorioMiami: tetos', () => {
  it('corta célula acima de 500 caracteres e avisa', () => {
    const g = montar(1, 1);
    pôr(g, 33, 13, ['x'.repeat(TETO_CELULA + 50)]);
    const r = parseRelatorioMiami(g);
    if (!r.ok) throw new Error(r.erro);
    expect(r.conteudo.blocos.diamantes.linhas[0][12]).toHaveLength(TETO_CELULA);
    expect(r.conteudo.avisos.some((a) => a.codigo === 'teto_celula')).toBe(true);
  });

  it('corta tabela acima de 1.000 linhas e avisa', () => {
    const g = montar(1, 1);
    for (let i = 0; i < TETO_LINHAS + 5; i++) pôr(g, 112 + i, 1, [`Comprador Teste ${i}`]);
    const r = parseRelatorioMiami(g);
    if (!r.ok) throw new Error(r.erro);
    expect(r.conteudo.blocos.compradores.linhas).toHaveLength(TETO_LINHAS);
    expect(r.conteudo.avisos.some((a) => a.codigo === 'teto_linhas')).toBe(true);
  });
});
