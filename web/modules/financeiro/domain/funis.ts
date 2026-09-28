// Funis (eventos) 2020→hoje (28/09/2026). O João: "o quanto a gente recebeu por cada funil, quantas pessoas pagaram,
// quem pagou". Catálogo em fin.eventos (Mapeamento Histórico do Drive); dinheiro do espelho da Hotmart
// (fn_fin_funis / fn_fin_funil_compradores). ref_* = o número que a equipe registrou na época (conferência, não dinheiro).

export type Setor = 'educacao' | 'escritorio';

export interface Funil {
  evento_id: number;
  nome: string;
  categoria: string;
  setor: Setor;
  inicio: string;
  fim: string;
  carrinho_inicio: string | null;
  venda_ate: string;
  ingresso_de: string;
  ingressos: number;
  ingressos_bruto: number;
  ingressos_liquido: number;
  oferta_vendas: number;
  oferta_compradores: number;
  oferta_estornos: number;
  oferta_bruto: number;
  oferta_liquido: number;
  compradores: number;
  bruto: number;
  liquido: number;
  ref_vendas: number | null;
  ref_valor: number | null;
  ref_tipo: string | null;
  ref_fonte: string | null;
  observacao: string | null;
  conta_ausente: boolean;
  /** Líquido incluindo as vendas estornadas depois — como a planilha da época somava. */
  liquido_conferencia: number;
}

export interface CompradorFunil {
  papel: 'ingresso' | 'oferta';
  produto: string | null;
  oferta: string | null;
  dia: string | null;
  situacao: 'pago' | 'estornado';
  valor: number;
  liquido: number;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  parcelas: number | null;
}

export const ROTULO_CATEGORIA_FUNIL: Record<string, string> = {
  holding_total: 'Holding Total',
  jornada: 'Jornada de Holding Familiar',
  live_hm: 'Lives Direto ao Ponto (HM)',
  certificacao: 'Certificação Holding Pro',
  clinica: 'Clínicas',
  imersao: 'Imersões',
  aurum_plus: 'Aurum+ / Conexão Aurum',
  encontro_thb: 'Encontro do THB',
  congresso: 'Congresso do THB',
  diamantes: 'Encontro dos Diamantes',
  residencia: 'Residência',
  workshop: 'Workshop da Residência',
  lancamento_cnhf: 'Curso Nacional (CNHF)',
  seminario_marcio: 'Seminários — Márcio',
  seminario_elaine: 'Seminários — Elaine',
};
export const rotuloCategoriaFunil = (c: string) => ROTULO_CATEGORIA_FUNIL[c] ?? c;

export interface ResumoCategoria {
  categoria: string;
  eventos: number;
  bruto: number;
  liquido: number;
  vendas: number;
  ingressos: number;
  compradores: number;
  mediaPorEvento: number;
}

/** Soma por categoria (só eventos com dado — conta ausente fica fora da média). */
export function resumirPorCategoria(funis: Funil[]): ResumoCategoria[] {
  const por = new Map<string, ResumoCategoria>();
  for (const f of funis) {
    const r = por.get(f.categoria) ?? { categoria: f.categoria, eventos: 0, bruto: 0, liquido: 0, vendas: 0, ingressos: 0, compradores: 0, mediaPorEvento: 0 };
    r.eventos += 1;
    r.bruto += Number(f.bruto) || 0;
    r.liquido += Number(f.liquido) || 0;
    r.vendas += f.oferta_vendas;
    r.ingressos += f.ingressos;
    r.compradores += f.compradores;
    por.set(f.categoria, r);
  }
  for (const r of por.values()) r.mediaPorEvento = r.eventos ? r.bruto / r.eventos : 0;
  return [...por.values()].sort((a, b) => b.bruto - a.bruto);
}

/** Diferença % do sistema contra o número registrado na época (null quando não há referência). */
export function diferencaPct(sistema: number, referencia: number | null): number | null {
  if (referencia == null || referencia === 0) return null;
  return ((sistema - referencia) / referencia) * 100;
}

const conferePorIngresso = (f: Funil) => f.categoria === 'clinica' || f.categoria === 'encontro_thb';
/** Vendas da conferência: as PAGAS (a planilha da época contava as pagas; T11 342=342, T14 626=626). Clínica e
 *  Encontro comparam ingressos. O valor compara com liquido_conferencia (inclui estornadas depois). */
export const vendasParaConferencia = (f: Funil) => (conferePorIngresso(f) ? f.ingressos : f.oferta_vendas);
/** Valor da conferência conforme o tipo registrado. Clínica/Encontro: a planilha soma só o ingresso (Goiânia 66 ·
 *  R$ 95.597 líquido; POA 88 · R$ 100.373 bruto). Demais: bruto com bruto; o resto com o líquido incl. estornos. */
export const valorParaConferencia = (f: Funil) => {
  if (conferePorIngresso(f)) return f.ref_tipo === 'bruto' ? f.ingressos_bruto : f.ingressos_liquido;
  return f.ref_tipo === 'bruto' ? f.bruto : f.liquido_conferencia;
};
