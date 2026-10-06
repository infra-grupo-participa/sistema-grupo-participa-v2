import { describe, expect, it } from 'vitest';
import {
  acharPalavras, acharTrechos, buscarSecoes, ocorrencias, palavrasDaBusca, recortar, resultadosBusca, resumoConteudo,
  segmentar, separarNegrito, textoLimpo, type Pesquisavel,
} from './busca';
import { GRUPOS, SECOES, type Secao } from './conteudo';

describe('busca no playbook', () => {
  it('acha sem acento e sem caixa, nas posições do texto original', () => {
    const t = 'Distribuição e distribuicao';
    expect(acharTrechos(t, 'DISTRIBUICAO')).toEqual([[0, 12], [15, 27]]);
    expect(acharTrechos(t, 'çã')).toEqual([[9, 11], [24, 26]]);
  });

  it('ignora termo curto ou vazio', () => {
    expect(acharTrechos('abc', 'a')).toEqual([]);
    expect(acharTrechos('abc', '   ')).toEqual([]);
  });

  it('separa negrito e mantém asterisco sem par como texto', () => {
    expect(separarNegrito('a **b** c')).toEqual([
      { texto: 'a ', negrito: false }, { texto: 'b', negrito: true }, { texto: ' c', negrito: false },
    ]);
    expect(textoLimpo('**Ganho** é pagamento')).toBe('Ganho é pagamento');
    expect(textoLimpo('nota * solta')).toBe('nota * solta');
  });

  it('segmenta com negrito e destaque juntos', () => {
    const s = segmentar('Todo **lead tem dono**, todo lead', 'lead');
    expect(s.filter((x) => x.destaque).map((x) => [x.texto, x.negrito])).toEqual([['lead', true], ['lead', false]]);
    expect(s.map((x) => x.texto).join('')).toBe('Todo lead tem dono, todo lead');
  });

  it('conta ocorrências por seção e lista só as que têm o termo', () => {
    const secoes: Secao[] = [
      { id: 'a', titulo: 'Clint', grupo: 'lead', blocos: [{ tipo: 'tabela', colunas: ['x'], linhas: [['no clint']] }] },
      { id: 'b', titulo: 'Outra', grupo: 'lead', blocos: [{ tipo: 'script', titulo: 'Oi', texto: 'olá' }] },
    ];
    expect(ocorrencias(secoes[0], 'clint')).toBe(2);
    expect([...resultadosBusca(secoes, 'clint')]).toEqual([['a', 2]]);
    expect(resultadosBusca(secoes, '').size).toBe(0);
  });
});

describe('conteúdo do playbook', () => {
  it('tem ids únicos, grupos válidos e todas as seções pedidas', () => {
    const ids = SECOES.map((s) => s.id);
    expect(new Set(ids).size).toBe(ids.length);
    const grupos = new Set(GRUPOS.map((g) => g.key));
    expect(SECOES.every((s) => grupos.has(s.grupo))).toBe(true);
    for (const id of ['inegociaveis', 'funil', 'distribuicao', 'disparo-api', 'cadencia', 'conversa', 'fechamento-do-dia',
      'area-atendimento', 'area-prospeccao', 'area-fechamento', 'em-aberto', 'glossario']) {
      expect(ids).toContain(id);
    }
  });

  it('tem os 9 inegociáveis, os 9 motivos de perda e a ficha de 7 itens', () => {
    const ineg = SECOES.find((s) => s.id === 'inegociaveis')!.blocos.filter((b) => b.tipo === 'regra');
    expect(ineg).toHaveLength(9);
    const listas = (id: string) => SECOES.find((s) => s.id === id)!.blocos.filter((b) => b.tipo === 'lista' && b.numerada);
    expect(listas('funil').some((b) => b.tipo === 'lista' && b.itens.length === 9)).toBe(true);
    expect(listas('disparo-api').some((b) => b.tipo === 'lista' && b.itens.length === 7)).toBe(true);
  });

  it('links de ferramenta apontam para telas do Comercial', () => {
    const links = SECOES.flatMap((s) => s.ferramentas ?? []);
    expect(links.length).toBeGreaterThan(0);
    expect(links.every((l) => l.href.startsWith('/comercial'))).toBe(true);
  });

  it('tabelas têm linhas do tamanho das colunas (nada de célula sobrando)', () => {
    for (const s of SECOES) for (const b of s.blocos) {
      if (b.tipo === 'tabela') for (const l of b.linhas) expect(l.length, `${s.id}: ${b.titulo ?? b.colunas.join('|')}`).toBe(b.colunas.length);
    }
  });

  it('não escreve "blindagem" como permitido nem promete replay', () => {
    const scripts = SECOES.flatMap((s) => s.blocos).filter((b) => b.tipo === 'script');
    expect(scripts.length).toBeGreaterThan(10);
    expect(scripts.every((b) => b.tipo === 'script' && !/blind|replay|https?:\/\//i.test(b.texto))).toBe(true);
  });

  it('resume o conteúdo a partir dos próprios dados', () => {
    const r = resumoConteudo(SECOES);
    expect(r.secoes).toBe(SECOES.length);
    expect(r.scripts).toBeGreaterThan(10);
    expect(r.emAberto).toBeGreaterThan(10);
    expect(r.pendencias).toBeGreaterThan(0);
  });
});

describe('busca da central de ajuda (várias palavras)', () => {
  const secoes: Pesquisavel[] = [
    { id: 'funil', titulo: 'Funil de vendas', resumo: 'Negócios por etapa.', sinonimos: ['kanban'], blocos: [{ tipo: 'paragrafo', texto: 'Arraste o card para **mover** o negócio de etapa.' }] },
    { id: 'ficha', titulo: 'Ficha do negócio', blocos: [{ tipo: 'passos', itens: ['Preencha os campos.', 'Clique em Mover para a próxima etapa.'] }] },
    { id: 'faq', titulo: 'Perguntas', blocos: [{ tipo: 'pergunta', pergunta: 'Por que não consigo mover?', resposta: 'Falta campo obrigatório na etapa.' }] },
    { id: 'outra', titulo: 'Disparos', blocos: [{ tipo: 'em_breve', titulo: 'Envio', texto: 'WhatsApp oficial conectado.' }] },
  ];

  it('tira acento, caixa e palavras vazias da busca', () => {
    expect(palavrasDaBusca('  Como MOVER o Negócio  ')).toEqual(['mover', 'negocio']);
    expect(palavrasDaBusca('de')).toEqual(['de']); // só palavra vazia: usa o que veio
    expect(palavrasDaBusca('a')).toEqual([]);
  });

  it('acha e junta as posições de várias palavras no texto original', () => {
    expect(acharPalavras('Negócio no funil', ['negocio', 'funil'])).toEqual([[0, 7], [11, 16]]);
    expect(acharPalavras('abcd', ['abc', 'bcd'])).toEqual([[0, 4]]);
  });

  it('exige todas as palavras e ignora acento e maiúscula', () => {
    expect(buscarSecoes(secoes, 'MOVER ETAPA').map((r) => r.secao.id)).toEqual(['funil', 'ficha', 'faq']);
    expect(buscarSecoes(secoes, 'mover whatsapp')).toEqual([]);
    expect(buscarSecoes(secoes, 'conexão').length).toBe(0);
    expect(buscarSecoes(secoes, 'whatsapp').map((r) => r.secao.id)).toEqual(['outra']);
  });

  it('título e sinônimo pesam mais que o corpo', () => {
    expect(buscarSecoes(secoes, 'negocio')[0].secao.id).toBe('ficha');
    expect(buscarSecoes(secoes, 'kanban').map((r) => r.secao.id)).toEqual(['funil']);
  });

  it('traz o trecho do corpo onde a busca aparece, sem asteriscos', () => {
    const [r] = buscarSecoes(secoes, 'arraste');
    expect(r.trecho).toBe('Arraste o card para mover o negócio de etapa.');
    expect(buscarSecoes(secoes, 'kanban')[0].trecho).toBe('Negócios por etapa.');
  });

  it('recorta texto longo em volta da palavra, com reticências', () => {
    const longo = `${'palavra '.repeat(40)}alvo ${'fim '.repeat(40)}`;
    const t = recortar(longo, ['alvo'], 60);
    expect(t.startsWith('… ')).toBe(true);
    expect(t.endsWith(' …')).toBe(true);
    expect(t).toContain('alvo');
    expect(t.length).toBeLessThanOrEqual(66);
  });

  it('destaca cada palavra da busca, não só a frase inteira', () => {
    const s = segmentar('Mover o negócio', 'negocio mover');
    expect(s.filter((x) => x.destaque).map((x) => x.texto)).toEqual(['Mover', 'negócio']);
  });

  it('busca vazia ou curta não devolve nada', () => {
    expect(buscarSecoes(secoes, '')).toEqual([]);
    expect(buscarSecoes(secoes, ' x ')).toEqual([]);
  });
});
