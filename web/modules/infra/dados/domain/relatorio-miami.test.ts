import { describe, expect, it } from 'vitest';
import {
  agruparItens, barrasDeColuna, buscar, contarPorValor, ehVazio, idadeCurta, indexar, inteiroDe, lerRespostaRelatorio, ordenar, percentualDe, valoresCategoricos,
} from './relatorio-miami';
import { conteudoExemplo, diamantes, kpiDadosIniciais, presenca, respostaExemplo } from './relatorio-miami.fixture';

describe('lerRespostaRelatorio', () => {
  it('aceita a resposta do contrato e preserva rótulos, cabeçalhos e valores como texto', () => {
    const r = lerRespostaRelatorio(JSON.parse(JSON.stringify(respostaExemplo())));
    expect(r?.conteudo?.blocos.dados_iniciais.itens[4]).toEqual({ rotulo: '% de preenchimento', valor: '88,2%' });
    expect(r?.conteudo?.blocos.presenca.linhas[0][4]).toBe('—');
    expect(r?.conteudo?.blocos.diamantes.colunas).toHaveLength(22);
    expect(r?.conteudo?.blocos.compradores.colunas).toHaveLength(16);
    expect(r?.contato_visivel).toBe(true);
  });

  it('sem cópia (disponivel false) é uma resposta válida sem conteúdo', () => {
    const r = lerRespostaRelatorio({ disponivel: false, md5: null, igual: false, lido_em: null, tentado_em: null, erro: null, contato_visivel: true, conteudo: null });
    expect(r).toMatchObject({ disponivel: false, conteudo: null, md5: null });
  });

  it('igual = true vem sem conteúdo e continua válido', () => {
    const r = lerRespostaRelatorio({ ...respostaExemplo({ igual: true, conteudo: null }) });
    expect(r).toMatchObject({ disponivel: true, igual: true, conteudo: null, md5: 'md5-a' });
  });

  it('erro da última leitura vem junto da cópia anterior', () => {
    const r = lerRespostaRelatorio(respostaExemplo({ erro: 'google_leitura' }));
    expect(r?.erro).toBe('google_leitura');
    expect(r?.conteudo).not.toBeNull();
  });

  it('recusa formato fora do contrato em vez de inventar', () => {
    expect(lerRespostaRelatorio(null)).toBeNull();
    expect(lerRespostaRelatorio({ disponivel: 'sim' })).toBeNull();
    expect(lerRespostaRelatorio({ ...respostaExemplo(), conteudo: { ...conteudoExemplo, versao: 2 } })).toBeNull();
    expect(lerRespostaRelatorio({ ...respostaExemplo(), conteudo: { ...conteudoExemplo, blocos: { ...conteudoExemplo.blocos, camisas: undefined } } })).toBeNull();
    expect(lerRespostaRelatorio({ ...respostaExemplo(), conteudo: null })).toBeNull();
  });

  it('só um false explícito esconde contato', () => {
    expect(lerRespostaRelatorio({ ...respostaExemplo(), contato_visivel: false })?.contato_visivel).toBe(false);
    const sem = { ...respostaExemplo() } as Record<string, unknown>;
    delete sem.contato_visivel;
    expect(lerRespostaRelatorio(sem)?.contato_visivel).toBe(true);
  });

  it('linha curta é completada com vazio e célula não-texto vira vazio', () => {
    const r = lerRespostaRelatorio({ ...respostaExemplo(), conteudo: { ...conteudoExemplo, blocos: { ...conteudoExemplo.blocos, camisas: { titulo: 't', colunas: ['a', 'b', 'c'], linhas: [['x', null]] } } } });
    expect(r?.conteudo?.blocos.camisas.linhas).toEqual([['x', '', '']]);
  });
});

describe('KPIs', () => {
  it('item sem valor abre um subgrupo; os de antes ficam soltos', () => {
    const { soltos, grupos } = agruparItens(kpiDadosIniciais.itens);
    expect(soltos).toHaveLength(6);
    expect(grupos).toHaveLength(1);
    expect(grupos[0].titulo).toBe('Situação de quem respondeu');
    expect(grupos[0].itens.map((i) => i.valor)).toEqual(['31', '17', '19']);
  });

  it('percentual só de texto percentual completo; travessão e vazio não viram zero', () => {
    expect(percentualDe('88,2%')).toBe(88.2);
    expect(percentualDe('100%')).toBe(100);
    expect(percentualDe('—')).toBeNull();
    expect(percentualDe('')).toBeNull();
    expect(percentualDe('150%')).toBeNull();
    expect(percentualDe(null)).toBeNull();
  });

  it('inteiro só de contagem pt-BR', () => {
    expect(inteiroDe('31')).toBe(31);
    expect(inteiroDe('1.234')).toBe(1234);
    expect(inteiroDe('—')).toBeNull();
    expect(inteiroDe('88,2%')).toBeNull();
  });
});

describe('tabelas', () => {
  const base = indexar(diamantes.linhas);
  const col = (nome: string) => diamantes.colunas.indexOf(nome);

  it('busca ignora acento e caixa, em qualquer coluna', () => {
    expect(buscar(base, 'pessoa teste 2').map((l) => l.i)).toEqual([1]);
    expect(buscar(base, 'CONVIDADO').map((l) => l.i)).toEqual([2]);
    expect(buscar(base, 'organizando').map((l) => l.i)).toEqual([1]);
    expect(buscar(base, '  ')).toHaveLength(4);
    expect(buscar(base, 'não existe')).toEqual([]);
  });

  it('ordena texto com número natural (Pessoa Teste 2 antes de 10)', () => {
    expect(ordenar(base, col('Nome (Lista Diamantes)'), 'asc').map((l) => l.celulas[0])).toEqual(['Pessoa Teste 1', 'Pessoa Teste 2', 'Pessoa Teste 3', 'Pessoa Teste 10']);
    expect(ordenar(base, col('Nome (Lista Diamantes)'), 'desc').map((l) => l.celulas[0])[0]).toBe('Pessoa Teste 10');
  });

  it('ordena data e hora pelo calendário, e vazio fica no fim nos dois sentidos', () => {
    const k = col('Enviado em');
    expect(ordenar(base, k, 'asc').map((l) => l.celulas[k])).toEqual(['02/10/2026 09:30', '09/10/2026 18:00', '13/10/2026 15:00', '']);
    expect(ordenar(base, k, 'desc').map((l) => l.celulas[k])).toEqual(['13/10/2026 15:00', '09/10/2026 18:00', '02/10/2026 09:30', '']);
  });

  it('ordena número pt-BR como número, e travessão fica no fim', () => {
    const k = presenca.colunas.indexOf('Time: presentes');
    expect(ordenar(indexar(presenca.linhas), k, 'asc').map((l) => l.celulas[k])).toEqual(['6', '7', '—']);
    expect(ordenar(indexar([['9'], ['10'], ['1.000'], ['2']]), 0, 'asc').map((l) => l.celulas[0])).toEqual(['2', '9', '10', '1.000']);
  });

  it('ordenar não muda a lista original', () => {
    const antes = base.map((l) => l.i);
    ordenar(base, 0, 'desc');
    expect(base.map((l) => l.i)).toEqual(antes);
  });

  it('valores categóricos: strings exatas por frequência; coluna com valores demais ou sem valor não é gráfico', () => {
    expect(valoresCategoricos(diamantes.linhas, col('Status'))).toEqual(['Respondeu', 'Pendente']);
    expect(valoresCategoricos(diamantes.linhas, col('Nome (Lista Diamantes)'), 3)).toBeNull();
    expect(valoresCategoricos(diamantes.linhas, col('Formulário dos eventos'))).toBeNull();
  });

  it('contagem por valor soma só o que existe e conta o vazio à parte, sem virar categoria', () => {
    const { barras, semValor } = contarPorValor(base, col('Situação para os eventos nos EUA'), valoresCategoricos(diamantes.linhas, col('Situação para os eventos nos EUA'))!);
    expect(barras).toEqual([
      { valor: 'Já estou confirmado(a) e com a viagem organizada.', rotulo: 'Já estou confirmado(a) e com a viagem organizada.', quantidade: 2 },
      { valor: 'Estou me organizando para participar, mas ainda não confirmado(a).', rotulo: 'Estou me organizando para participar, mas ainda não confirmado(a).', quantidade: 1 },
    ]);
    expect(semValor).toBe(1);
  });

  it('barras da presença: uma por evento, evento com travessão fica de fora e é contado', () => {
    const d = barrasDeColuna(presenca, 'Time: total estimado')!;
    expect(d.barras.map((b) => [b.rotulo, b.quantidade])).toEqual([['Happy Hour de boas-vindas', 7], ['Festa dos Iates', 7]]);
    expect(d.semDado).toBe(1);
    expect(barrasDeColuna(presenca, 'Coluna que não existe')).toBeNull();
  });

  it('ehVazio trata só vazio e travessão como vazio', () => {
    expect(ehVazio('')).toBe(true);
    expect(ehVazio(' — ')).toBe(true);
    expect(ehVazio('0')).toBe(false);
    expect(ehVazio('Não vai')).toBe(false);
  });
});

describe('idadeCurta', () => {
  const agora = Date.parse('2026-10-16T18:00:00Z');
  it('descreve a idade da cópia', () => {
    expect(idadeCurta('2026-10-16T17:57:00Z', agora)).toBe('há 3 min');
    expect(idadeCurta('2026-10-16T15:00:00Z', agora)).toBe('há 3 h');
    expect(idadeCurta('2026-10-13T18:00:00Z', agora)).toBe('há 3 d');
    expect(idadeCurta('2026-10-16T18:00:00Z', agora)).toBe('agora há pouco');
  });
  it('data inválida, vazia ou no futuro não vira idade', () => {
    expect(idadeCurta(null, agora)).toBeNull();
    expect(idadeCurta('lixo', agora)).toBeNull();
    expect(idadeCurta('2026-10-17T18:00:00Z', agora)).toBeNull();
  });
});
