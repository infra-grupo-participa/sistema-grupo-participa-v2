// Caso de uso: dataset neutro para a aba Relatórios. Serve os DOIS exports
// (XLSX via SheetJS e PDF com protocolo via ui/pdf/documentos.ts) a partir do
// MESMO array de linhas + colunas selecionadas — sem duplicar formatação.
//
// Datas saem em ISO puro aqui de propósito: application não importa
// shared/ui/format (é camada de apresentação) — a UI formata na hora de
// exibir/exportar (fmtData), igual ao padrão do export legado (financeiro-export.ts).
import type { ContaReceber } from '../domain/types';
import { statusLabel } from '../domain/financeiro';
import type { BoardHotmart } from '../domain/hotmart';

export interface OpcoesRelatorio {
  canVerDoc: boolean;
  /** Card do board × espelho Hotmart, por contato_hm_id — null quando a carga falhou/ainda não veio.
   *  Alimenta as colunas "hm_*" (opcionais); sem entrada para a linha, a coluna sai vazia. */
  hotmartPorCard?: Map<string, BoardHotmart> | null;
}

export interface ColunaRelatorio {
  key: string;
  label: string;
  tipo: 'texto' | 'moeda' | 'data' | 'numero';
  get: (c: ContaReceber, opts: OpcoesRelatorio) => string | number | null;
}

/** Todas as colunas disponíveis para seleção — ordem = ordem de exibição por padrão. */
export const COLUNAS_RELATORIO: ColunaRelatorio[] = [
  { key: 'nome', label: 'Nome', tipo: 'texto', get: (c) => c.nome ?? '' },
  { key: 'email', label: 'E-mail', tipo: 'texto', get: (c) => c.email ?? '' },
  { key: 'telefone', label: 'Telefone', tipo: 'texto', get: (c) => c.telefone ?? '' },
  { key: 'produto', label: 'Produto', tipo: 'texto', get: (c) => c.produto ?? '' },
  { key: 'canal', label: 'Canal', tipo: 'texto', get: (c) => c.canal ?? '' },
  { key: 'turma', label: 'Turma', tipo: 'texto', get: (c) => c.turma ?? '' },
  { key: 'status', label: 'Status', tipo: 'texto', get: (c) => statusLabel(c.status_financeiro) },
  // Documento NÃO é coluna do relatório: fn_fin_board deixou de trafegá-lo
  // (LGPD, dado pessoal sem consumidor no board), e o relatório é montado sobre
  // as contas do board. Oferecer a coluna aqui exportaria uma coluna sempre
  // vazia — coluna que mente é pior que coluna ausente. Se o financeiro precisar
  // de documento em massa, o caminho é uma RPC própria de export, com o guard
  // gp_pode_ver_cpf() aplicado no SQL.
  { key: 'total_pago_bruto', label: 'Já pago (bruto)', tipo: 'moeda', get: (c) => c.total_pago_bruto ?? 0 },
  { key: 'total_pago_liquido', label: 'Já pago (líquido)', tipo: 'moeda', get: (c) => c.total_pago_liquido ?? 0 },
  { key: 'saldo_a_pagar', label: 'Falta pagar', tipo: 'moeda', get: (c) => c.saldo_a_pagar },
  { key: 'pacote', label: 'Pacote', tipo: 'moeda', get: (c) => c.pacote },
  { key: 'credito', label: 'Crédito', tipo: 'moeda', get: (c) => c.credito },
  { key: 'vencimento', label: 'Vencimento', tipo: 'data', get: (c) => c.vencimento },
  { key: 'dias_atraso', label: 'Dias em atraso', tipo: 'numero', get: (c) => c.dias_atraso },
  { key: 'solicitou_cancelamento', label: 'Solicitou cancelamento', tipo: 'texto', get: (c) => (c.solicitou_cancelamento ? 'Sim' : 'Não') },
  { key: 'oferta_codigo', label: 'Oferta (código)', tipo: 'texto', get: (c) => c.oferta_codigo ?? '' },
  { key: 'ultimo_pagamento_em', label: 'Último pagamento', tipo: 'data', get: (c) => c.ultimo_pagamento_em },

  // ── Espelho da Hotmart por card (opcionais — vazias sem hotmartPorCard) ──
  // Fonte: fn_fin_board_hotmart via opts.hotmartPorCard (chave = contato_hm_id).
  // Nunca inventa 0: sem entrada no mapa, a célula fica vazia (formatarCelulaTela → "—").
  { key: 'hm_pago_bruto', label: 'Pago na Hotmart (bruto)', tipo: 'moeda', get: (c, opts) => opts.hotmartPorCard?.get(c.contato_hm_id)?.pago_bruto ?? null },
  { key: 'hm_taxa_hotmart', label: 'Taxa Hotmart', tipo: 'moeda', get: (c, opts) => opts.hotmartPorCard?.get(c.contato_hm_id)?.taxa_hotmart ?? null },
  { key: 'hm_liquido', label: 'Líquido Hotmart', tipo: 'moeda', get: (c, opts) => opts.hotmartPorCard?.get(c.contato_hm_id)?.liquido ?? null },
  { key: 'hm_juros', label: 'Juros do cliente', tipo: 'moeda', get: (c, opts) => opts.hotmartPorCard?.get(c.contato_hm_id)?.juros ?? null },
  {
    key: 'hm_parcelamento', label: 'Parcelamento', tipo: 'texto',
    get: (c, opts) => {
      const max = opts.hotmartPorCard?.get(c.contato_hm_id)?.parcelas_max;
      return max != null ? `até ${max}x` : null;
    },
  },
  { key: 'hm_ultimo_pagamento', label: 'Último pagamento (Hotmart)', tipo: 'data', get: (c, opts) => opts.hotmartPorCard?.get(c.contato_hm_id)?.ultimo_pagamento_em ?? null },
  { key: 'hm_devido_120', label: 'Devido ≤120 dias', tipo: 'moeda', get: (c, opts) => opts.hotmartPorCard?.get(c.contato_hm_id)?.valor_devido ?? null },
  {
    key: 'hm_diverge', label: 'Diverge da Hotmart', tipo: 'texto',
    get: (c, opts) => {
      const d = opts.hotmartPorCard?.get(c.contato_hm_id)?.diverge;
      return d == null ? null : d ? 'Sim' : 'Não';
    },
  },
];

export const COLUNAS_PADRAO = ['nome', 'email', 'produto', 'canal', 'status', 'total_pago_bruto', 'saldo_a_pagar', 'vencimento', 'dias_atraso'];

export interface LinhaRelatorio {
  chave: string;
  valores: Record<string, string | number | null>;
}

export interface DatasetRelatorio {
  colunas: ColunaRelatorio[];
  linhas: LinhaRelatorio[];
}

/** Monta o dataset neutro (colunas selecionadas + valores crus por linha).
 *  A UI decide como formatar cada `tipo` (fmtBRLc/fmtData) na exibição e no export. */
export function montarRelatorio(
  contas: ContaReceber[],
  colunasChaves: string[],
  opts: OpcoesRelatorio,
): DatasetRelatorio {
  const colunas = colunasChaves
    .map((k) => COLUNAS_RELATORIO.find((c) => c.key === k))
    .filter((c): c is ColunaRelatorio => !!c);
  return {
    colunas,
    linhas: contas.map((c) => ({
      chave: c.contato_hm_id,
      valores: Object.fromEntries(colunas.map((col) => [col.key, col.get(c, opts)])),
    })),
  };
}
