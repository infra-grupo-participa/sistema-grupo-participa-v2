// Regra ÚNICA de dado pessoal no PDF. Os mapeadores só DECLARAM o que cada
// coluna é (ClassePii); quem decide o que sai em cada nível é aplicarNivel().
//
//   completo          → tudo, mas coluna 'documento' sempre mascarada (···1234),
//                       mesmo para quem tem gp_pode_ver_cpf() e vê o CPF cru na tela.
//   sem_dado_pessoal  → some toda coluna com pii ≠ 'nenhuma'; seção cujas linhas
//                       são pessoas ganha "Pessoa 1", "Pessoa 2"… na ordem da lista.
//   so_numeros        → some toda seção de detalhe; ficam KPIs e seções de resumo.
//
// Busca livre no recorte (quase sempre nome de aluno) só aparece no nível completo.
import type {
  ColunaPdf, LinhaPdf, NivelPii, RascunhoRelatorio, RelatorioNivelado, SecaoPdf,
} from './modelo';

export type { NivelPii } from './modelo';

export const NIVEIS_PII: NivelPii[] = ['completo', 'sem_dado_pessoal', 'so_numeros'];

/**
 * Máscara de documento para o papel: toda sequência de 5+ dígitos (com . - / ou
 * espaço no meio) vira ···1234. Texto já mascarado pelo banco ("CPF ···1234")
 * passa igual. Prefixo "CPF"/"CNPJ" é preservado quando houver.
 */
export function mascararDocumento(texto: string): string {
  return texto.replace(/\d[\d.\-/ ]{3,}\d/g, (trecho) => {
    const digitos = trecho.replace(/\D/g, '');
    if (digitos.length < 5) return trecho;
    return `···${digitos.slice(-4)}`;
  });
}

function validar(r: RascunhoRelatorio, nivel: NivelPii): void {
  if (!r.niveisPermitidos.includes(nivel)) {
    throw new Error(`O relatório "${r.titulo}" não aceita o nível "${nivel}".`);
  }
  for (const s of r.secoes) {
    if (s.tipo === 'resumo' && s.colunas.some((c) => c.pii !== 'nenhuma')) {
      throw new Error(`Seção de resumo "${s.titulo}" não pode ter coluna com dado pessoal.`);
    }
    if (s.linhasSaoPessoas && s.tipo !== 'detalhe') {
      throw new Error(`Seção "${s.titulo}": linhasSaoPessoas só vale em seção de detalhe.`);
    }
  }
}

const COLUNA_PSEUDONIMO: ColunaPdf = { chave: '__pessoa', rotulo: 'Pessoa', tipo: 'texto', pii: 'nenhuma', peso: 0.8 };

function mascararSecao(s: SecaoPdf): SecaoPdf {
  const docs = s.colunas.filter((c) => c.pii === 'documento').map((c) => c.chave);
  if (!docs.length) return s;
  const mascarar = (cel: Record<string, string>) => {
    const out = { ...cel };
    for (const k of docs) if (out[k]) out[k] = mascararDocumento(out[k]);
    return out;
  };
  return {
    ...s,
    linhas: s.linhas.map((l) => ({ celulas: mascarar(l.celulas) })),
    total: s.total ? mascarar(s.total) : undefined,
  };
}

function semDadoPessoal(s: SecaoPdf): SecaoPdf {
  const ficam = s.colunas.filter((c) => c.pii === 'nenhuma');
  const chaves = new Set(ficam.map((c) => c.chave));
  const filtrar = (cel: Record<string, string>) =>
    Object.fromEntries(Object.entries(cel).filter(([k]) => chaves.has(k)));
  const linhas: LinhaPdf[] = s.linhas.map((l, i) => ({
    celulas: s.linhasSaoPessoas ? { [COLUNA_PSEUDONIMO.chave]: `Pessoa ${i + 1}`, ...filtrar(l.celulas) } : filtrar(l.celulas),
  }));
  return {
    ...s,
    colunas: s.linhasSaoPessoas ? [COLUNA_PSEUDONIMO, ...ficam] : ficam,
    linhas,
    total: s.total ? filtrar(s.total) : undefined,
  };
}

/** Aplica o nível de dado pessoal. Lança erro se o relatório não aceita o nível. */
export function aplicarNivel(r: RascunhoRelatorio, nivel: NivelPii): RelatorioNivelado {
  validar(r, nivel);
  let secoes: SecaoPdf[];
  if (nivel === 'completo') secoes = r.secoes.map(mascararSecao);
  else if (nivel === 'sem_dado_pessoal') secoes = r.secoes.map(semDadoPessoal);
  else secoes = r.secoes.filter((s) => s.tipo === 'resumo');

  return { ...r, nivel, recorte: recorteEmTexto(r, nivel === 'completo'), secoes };
}

function recorteEmTexto(r: RascunhoRelatorio, comBusca: boolean): string[] {
  return r.recorte.map((i) => (i.pii && !comBusca ? `${i.rotulo}: termo omitido` : `${i.rotulo}: ${i.valor}`));
}

/**
 * Acima deste número de linhas na lista o PDF sai SÓ COM TOTAIS (decisão do Marcio, 28/09):
 * a Pessoas do HM com 9.228 linhas deu 924 folhas e 83 s no Chrome. A lista completa fica
 * na planilha do relatório. Constante única: a tela avisa e o documento corta pelo mesmo número.
 */
export const LINHAS_MAX_NO_PDF = 2000;

/** true = neste nível o PDF sairia com mais linhas do que LINHAS_MAX_NO_PDF. */
export function excedeLimiteDoPdf(linhasDaLista: number, nivel: NivelPii): boolean {
  return nivel !== 'so_numeros' && linhasDaLista > LINHAS_MAX_NO_PDF;
}

export function textoAvisoSoTotais(linhasDaLista: number, temPlanilha: boolean): string {
  const n = linhasDaLista.toLocaleString('pt-BR');
  return temPlanilha
    ? `Lista completa com ${n} linhas disponível na exportação em planilha deste relatório.`
    : `Lista completa com ${n} linhas disponível na tela deste relatório.`;
}

/** O que vai para o PDF e para a emissão. */
export interface PreparoPdf {
  documento: RelatorioNivelado;
  /** Tamanho da lista da tela (linhas de detalhe do rascunho). */
  linhasDaLista: number;
  /** Linhas de detalhe que o PDF de fato imprime (0 quando só totais ou só números). */
  linhasImpressas: number;
}

/**
 * aplicarNivel + limite de linhas. Lista acima de LINHAS_MAX_NO_PDF (fora do nível só
 * números): saem as seções de detalhe — ficam cabeçalho, KPIs e resumo, o mesmo conteúdo
 * do nível so_numeros, com a busca livre omitida — e entra o aviso no corpo.
 */
export function prepararParaPdf(r: RascunhoRelatorio, nivel: NivelPii): PreparoPdf {
  const nivelado = aplicarNivel(r, nivel); // lança se o relatório não aceita o nível
  const linhasDaLista = contarLinhasDetalhe(r);
  if (!excedeLimiteDoPdf(linhasDaLista, nivel)) {
    return { documento: nivelado, linhasDaLista, linhasImpressas: contarLinhasDetalhe(nivelado) };
  }
  const documento: RelatorioNivelado = {
    ...nivelado,
    secoes: nivelado.secoes.filter((s) => s.tipo === 'resumo'),
    recorte: recorteEmTexto(r, false),
    avisoSoTotais: textoAvisoSoTotais(linhasDaLista, !!r.temPlanilha),
  };
  return { documento, linhasDaLista, linhasImpressas: 0 };
}

/** Linhas das seções de detalhe (no rascunho = tamanho da lista da tela). */
export function contarLinhasDetalhe(r: Pick<RascunhoRelatorio, 'secoes'>): number {
  return r.secoes.filter((s) => s.tipo === 'detalhe').reduce((n, s) => n + s.linhas.length, 0);
}

/** Níveis que o seletor oferece para o relatório, na ordem canônica. */
export function niveisDoRelatorio(r: Pick<RascunhoRelatorio, 'niveisPermitidos'>): NivelPii[] {
  return NIVEIS_PII.filter((n) => r.niveisPermitidos.includes(n));
}
