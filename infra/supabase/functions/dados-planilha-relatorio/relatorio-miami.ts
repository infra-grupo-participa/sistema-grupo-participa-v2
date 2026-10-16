// Leitor PURO da aba `Relatório` da planilha "Dados [MIAMI 2026]" (migration 20261016240000, Edge dados-planilha-relatorio).
// Recebe os valores formatados de 'Relatório'!A1:AD2000 (string[][], como o Sheets mostra) e devolve o conteúdo que o banco
// guarda e a tela lê (dados_miami_relatorio). Sem Deno e sem rede, para ser testado no vitest do web.
//
// Regras (todas por texto exato, nunca por posição fixa, porque o time insere linha e coluna na planilha):
//  - cada bloco é achado pelo TÍTULO exato, que tem de aparecer uma vez só na aba;
//  - bloco de KPI: rótulos na coluna do título, de cima para baixo até a célula vazia; valor na coluna da direita;
//    os rótulos se repetem entre blocos ("% de preenchimento"), por isso só se lê dentro do bloco;
//  - bloco de tabela: o cabeçalho tem de bater célula a célula com as strings esperadas; colunas auxiliares ficam de fora;
//    linhas cortadas pelo Sheets (células finais vazias) são completadas; a tabela termina na primeira linha sem a
//    primeira célula ou no próximo título;
//  - título, rótulo ou cabeçalho diferente = falha (ok:false): quem chama MANTÉM a cópia boa anterior e grava o erro;
//  - valores sempre como o texto formatado ("—" nunca vira 0, "88,2%" nunca vira número);
//  - tetos: 1.000 linhas por tabela e 500 caracteres por célula (excedente é cortado e vira aviso).
// O erro nunca carrega o texto de uma célula (pode ser dado pessoal se o layout deslocar): só código, bloco e posição.

export const VERSAO = 1;
export const ABA = 'Relatório';
export const TETO_LINHAS = 1000;
export const TETO_CELULA = 500;
const LARGURA_MAX = 30; // A:AD, o que a Edge lê

export type Aviso = { codigo: string; texto: string };
export type Kpis = { titulo: string; itens: { rotulo: string; valor: string | null }[] };
export type Tabela = { titulo: string; colunas: string[]; linhas: string[][] };
export type Conteudo = {
  versao: typeof VERSAO;
  aba: string;
  avisos: Aviso[];
  blocos: {
    dados_iniciais: Kpis;
    time_formulario: Kpis;
    participacao: Kpis;
    camisas: Tabela;
    presenca: Tabela;
    diamantes: Tabela;
    compradores: Tabela;
  };
};
export type Resultado = { ok: true; conteudo: Conteudo } | { ok: false; erro: string };

type DefKpi = { chave: 'dados_iniciais' | 'time_formulario' | 'participacao'; tipo: 'kpi'; titulo: string; rotulos: string[] };
type DefTabela = {
  chave: 'camisas' | 'presenca' | 'diamantes' | 'compradores'; tipo: 'tabela'; titulo: string;
  tituloNoCabecalho: boolean; // true: o título é a 1ª célula do cabeçalho (mesma linha); false: o cabeçalho é a linha de baixo
  colunas: string[]; // cabeçalho esperado, a partir da coluna do título (o que vem depois disto é auxiliar e é descartado)
};

export const BLOCOS: (DefKpi | DefTabela)[] = [
  { chave: 'dados_iniciais', tipo: 'kpi', titulo: 'Formulário dados iniciais de presença', rotulos: [
    'Pessoas na Lista Diamantes', 'Respostas recebidas no formulário', 'Da lista, já preencheram', 'Da lista, faltam preencher',
    '% de preenchimento', 'Respostas sem correspondência na lista', 'Situação de quem respondeu',
    'Confirmados, com viagem organizada', 'Se organizando, ainda não confirmados', 'Não irão participar'] },
  { chave: 'time_formulario', tipo: 'kpi', titulo: 'Time (Clínica): formulário dos compradores', rotulos: [
    'Compradores da Clínica', 'Já responderam', 'Faltam responder', '% de preenchimento', 'Respostas recebidas (pessoas únicas)',
    'Respostas sem correspondência na lista de compradores'] },
  { chave: 'participacao', tipo: 'kpi', titulo: 'Formulário de participação nos eventos (Miami)', rotulos: [
    'Respostas recebidas (pessoas únicas)', 'Confirmados que já preencheram',
    'Confirmados que ainda não preencheram (clique no número para ver quem)'] },
  { chave: 'camisas', tipo: 'tabela', titulo: 'Camisas (última resposta de cada pessoa)', tituloNoCabecalho: true,
    colunas: ['Camisas (última resposta de cada pessoa)', 'Diamante', 'Time', 'Total'] },
  { chave: 'presenca', tipo: 'tabela', titulo: 'Presença por evento', tituloNoCabecalho: true, colunas: [
    'Presença por evento', 'Data', 'Diamante: presentes', 'Diamante: não estarão', 'Diamante: acompanhantes (nº informado)',
    'Diamante: total estimado', 'Time: presentes', 'Time: não estarão', 'Time: acompanhantes (nº informado)',
    'Time: total estimado', 'Total geral estimado (Diamante + Time)'] },
  { chave: 'diamantes', tipo: 'tabela', titulo: 'Respostas por pessoa da Lista Diamantes', tituloNoCabecalho: false, colunas: [
    'Nome (Lista Diamantes)', 'Nome no formulário', 'Status', 'E-mail', 'Telefone (WhatsApp)', 'Grupo',
    'Situação para os eventos nos EUA', 'Chegada em Miami', 'Retorno', 'Aeroporto', 'Hospedagem', 'Acompanhado(a)',
    'Quem acompanha', 'Enviado em', 'Formulário dos eventos', 'Reunião DV (30/11)', 'Happy Hour (30/11)',
    'Encontro + Clínica (1-2/12)', 'Experiência (3/12)', 'Festa do Diamante (4/12)', 'Festa dos Iates (5/12)',
    'Enterro dos Ossos (6/12)'] },
  { chave: 'compradores', tipo: 'tabela', titulo: 'Compradores da Clínica (Time): situação por comprador', tituloNoCabecalho: false, colunas: [
    'Nome (compra)', 'E-mail', 'Telefone', 'Instrução (Central)', 'Turma (Central)', 'Formulário',
    'Espaço de instrução (formulário)', 'Chegada', 'Saída', 'Aeroporto', 'Acompanhantes na viagem', 'Happy Hour (30/11)',
    'Clínica (1-2/12): comprou', 'Experiência (3/12)', 'Festa dos Iates (5/12)', 'Hospedagem'] },
];

const TITULOS = new Set(BLOCOS.map((b) => b.titulo));

/** "1.234" → 1234, "76" → 76, "88,2%" → null (não é contagem). Só inteiro pt-BR. */
export function inteiroBR(s: string | null | undefined): number | null {
  const t = (s ?? '').trim();
  if (!/^\d{1,3}(\.\d{3})+$|^\d+$/.test(t)) return null;
  return Number(t.replace(/\./g, ''));
}

export function parseRelatorioMiami(valores: unknown): Resultado {
  if (!Array.isArray(valores) || valores.length === 0) return { ok: false, erro: 'aba_vazia' };
  const grade = valores as unknown[][];
  const avisos: Aviso[] = [];
  let celulasCortadas = 0;

  const bruto = (r: number, c: number): string => {
    const linha = grade[r];
    if (!Array.isArray(linha) || c < 0 || c >= LARGURA_MAX) return '';
    const v = linha[c];
    return v == null ? '' : String(v);
  };
  const celula = (r: number, c: number): string => {
    const t = bruto(r, c).trim();
    if (t.length > TETO_CELULA) {
      celulasCortadas++;
      return t.slice(0, TETO_CELULA);
    }
    return t;
  };

  // 1. Achar cada título (único na aba)
  const achados = new Map<string, { r: number; c: number }[]>();
  for (let r = 0; r < grade.length; r++) {
    const linha = grade[r];
    if (!Array.isArray(linha)) continue;
    for (let c = 0; c < Math.min(linha.length, LARGURA_MAX); c++) {
      const t = bruto(r, c).trim();
      if (TITULOS.has(t)) {
        const l = achados.get(t) ?? [];
        l.push({ r, c });
        achados.set(t, l);
      }
    }
  }
  const pos = new Map<string, { r: number; c: number }>();
  for (const b of BLOCOS) {
    const l = achados.get(b.titulo) ?? [];
    if (l.length === 0) return { ok: false, erro: `titulo_ausente:${b.chave}` };
    if (l.length > 1) return { ok: false, erro: `titulo_duplicado:${b.chave}` };
    pos.set(b.chave, l[0]);
  }

  const blocos: Partial<Conteudo['blocos']> = {};

  for (const b of BLOCOS) {
    const { r, c } = pos.get(b.chave)!;
    if (b.tipo === 'kpi') {
      const itens: Kpis['itens'] = [];
      for (let i = r + 1; i < grade.length && itens.length < 100; i++) {
        const rotulo = celula(i, c);
        if (rotulo === '' || TITULOS.has(rotulo)) break;
        const valor = celula(i, c + 1);
        itens.push({ rotulo, valor: valor === '' ? null : valor });
      }
      for (const esperado of b.rotulos) {
        if (!itens.some((x) => x.rotulo === esperado)) return { ok: false, erro: `rotulo_ausente:${b.chave}:${b.rotulos.indexOf(esperado)}` };
      }
      blocos[b.chave] = { titulo: b.titulo, itens };
      continue;
    }

    const linhaCab = b.tituloNoCabecalho ? r : r + 1;
    for (let i = 0; i < b.colunas.length; i++) {
      if (bruto(linhaCab, c + i).trim() !== b.colunas[i]) return { ok: false, erro: `cabecalho_diferente:${b.chave}:${i}` };
    }
    const linhas: string[][] = [];
    for (let i = linhaCab + 1; i < grade.length; i++) {
      const chave = bruto(i, c).trim();
      if (chave === '' || TITULOS.has(chave)) break;
      if (linhas.length >= TETO_LINHAS) {
        avisos.push({ codigo: 'teto_linhas', texto: `A tabela "${b.titulo}" passou de ${TETO_LINHAS} linhas; o excedente não foi copiado.` });
        break;
      }
      linhas.push(b.colunas.map((_, k) => celula(i, c + k)));
    }
    blocos[b.chave] = { titulo: b.titulo, colunas: [...b.colunas], linhas };
  }

  const bl = blocos as Conteudo['blocos'];
  if (celulasCortadas > 0) {
    avisos.push({ codigo: 'teto_celula', texto: `${celulasCortadas} célula(s) passaram de ${TETO_CELULA} caracteres e foram cortadas.` });
  }

  // 2. Integridade: a tabela por pessoa não pode ter menos linhas do que a contagem do próprio relatório
  const valorDe = (k: Kpis, rotulo: string) => k.itens.find((x) => x.rotulo === rotulo)?.valor ?? null;
  const confere = (codigo: string, rotulo: string, k: Kpis, tabela: Tabela, nomeTabela: string) => {
    const bruta = valorDe(k, rotulo);
    const esperado = inteiroBR(bruta);
    if (esperado === null) {
      avisos.push({ codigo: `${codigo}_ilegivel`, texto: `Não deu para ler "${rotulo}" como número; a conferência de "${nomeTabela}" não foi feita.` });
    } else if (tabela.linhas.length < esperado) {
      avisos.push({ codigo, texto: `"${rotulo}" diz ${esperado}, mas "${nomeTabela}" trouxe ${tabela.linhas.length} linha(s). Pode haver gente fora da tabela na planilha.` });
    }
  };
  confere('diamantes_linhas_menos_que_a_lista', 'Pessoas na Lista Diamantes', bl.dados_iniciais, bl.diamantes, 'Respostas por pessoa da Lista Diamantes');
  confere('compradores_linhas_menos_que_os_compradores', 'Compradores da Clínica', bl.time_formulario, bl.compradores, 'Compradores da Clínica (Time)');

  return { ok: true, conteudo: { versao: VERSAO, aba: ABA, avisos, blocos: bl } };
}
