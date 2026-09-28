// Modelo neutro do documento PDF de relatório. Os mapeadores de cada relatório
// (modules/*/ui/pdf/documentos.ts) produzem um RascunhoRelatorio; aplicarNivel()
// (nivel.ts) corta o dado pessoal; a emissão devolve o protocolo; só então existe
// um DocumentoRelatorio, que é o único tipo que o DocumentoPdf aceita.
//
// Células chegam JÁ FORMATADAS (texto): quem formata é o mapeador, com os
// formatadores do domínio. O PDF só posiciona e alinha.

/** O que a coluna carrega de dado pessoal. Decide o corte por nível em nivel.ts. */
export type ClassePii = 'identificacao' | 'contato' | 'documento' | 'nenhuma';

export type TipoColunaPdf = 'texto' | 'moeda' | 'numero' | 'data';

export type NivelPii = 'completo' | 'sem_dado_pessoal' | 'so_numeros';

export interface ColunaPdf {
  chave: string;
  rotulo: string;
  tipo: TipoColunaPdf;
  pii: ClassePii;
  /** Largura relativa (flex). Padrão 1. */
  peso?: number;
}

export interface LinhaPdf {
  /** Texto por chave de coluna. Ausente/'' sai como travessão. Pode ter '\n'. */
  celulas: Record<string, string>;
}

export interface SecaoPdf {
  titulo: string;
  /**
   * 'detalhe' = uma linha por pessoa/transação — some inteira no nível so_numeros.
   * 'resumo'  = agregado (contagem/soma por grupo) — fica em todos os níveis e,
   *             por isso, NÃO pode ter coluna com dado pessoal (aplicarNivel recusa).
   */
  tipo: 'detalhe' | 'resumo';
  /**
   * Só em seção de detalhe cujas linhas SÃO pessoas: no nível sem_dado_pessoal
   * ganha a coluna "Pessoa" com "Pessoa 1", "Pessoa 2"… na ordem da lista.
   */
  linhasSaoPessoas?: boolean;
  colunas: ColunaPdf[];
  linhas: LinhaPdf[];
  /** Linha de total ao pé da tabela (texto por chave). */
  total?: Record<string, string>;
  /** Texto quando não há linha. */
  vazio?: string;
}

export interface KpiPdf {
  rotulo: string;
  valor: string;
}

/** Filtro aplicado, em texto. `pii: true` = o valor pode ser nome/e-mail (busca livre). */
export interface ItemRecorte {
  rotulo: string;
  valor: string;
  pii?: boolean;
}

/** Mesmos valores do check de fin.relatorios_emitidos.tipo. */
export type TipoRelatorioPdf = 'board' | 'pessoas' | 'conciliacao' | 'identidade' | 'acelera' | 'prorata';

/** O que o mapeador devolve: ainda sem nível aplicado e sem protocolo. */
export interface RascunhoRelatorio {
  tipo: TipoRelatorioPdf;
  titulo: string;
  recorte: ItemRecorte[];
  /** Níveis aceitos. "Mesma pessoa?" = só ['completo'] (decisão do Marcio). */
  niveisPermitidos: NivelPii[];
  kpis?: KpiPdf[];
  secoes: SecaoPdf[];
  /** Base do nome do arquivo, sem data nem extensão. */
  arquivo: string;
}

/** Rascunho depois de aplicarNivel(): ainda sem protocolo. */
export interface RelatorioNivelado extends Omit<RascunhoRelatorio, 'recorte'> {
  nivel: NivelPii;
  /** Recorte já em texto final (busca livre omitida fora do nível completo). */
  recorte: string[];
}

/** O que o PDF desenha. Protocolo e data de emissão vêm da emissão no banco — obrigatórios. */
export interface DocumentoRelatorio extends RelatorioNivelado {
  protocolo: string;
  /** ISO (timestamptz) devolvido pela emissão. */
  emitidoEm: string;
}

export const ROTULO_NIVEL: Record<NivelPii, string> = {
  completo: 'Completo',
  sem_dado_pessoal: 'Sem dados pessoais',
  so_numeros: 'Só números',
};

const FUSO = 'America/Sao_Paulo';
/**
 * Data/hora da emissão no fuso de São Paulo — a MESMA que o PDF imprime no
 * cabeçalho. Mora aqui (sem @react-pdf) para a tela de conferência usar sem
 * puxar a lib de PDF para o bundle.
 */
export function dataHoraSaoPaulo(iso: string): { data: string; hora: string } {
  const d = new Date(iso);
  return {
    data: new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit', year: 'numeric' }).format(d),
    hora: new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit', hour12: false }).format(d),
  };
}

/** Texto do indicador no cabeçalho do PDF. */
export const INDICADOR_NIVEL: Record<NivelPii, string> = {
  completo: 'Contém dados pessoais (CPF mascarado)',
  sem_dado_pessoal: 'Sem dados pessoais',
  so_numeros: 'Só números, sem lista de pessoas',
};
