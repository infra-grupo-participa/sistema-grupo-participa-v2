// Financeiro a partir do espelho da Hotmart (schema fin, 27/09/2026).
//
// A Hotmart é a fonte oficial do dinheiro: o webhook deixou de trazer o líquido
// em ~18/08 e só existe desde mar/2026; a API traz tudo desde 2022, inclusive o que
// a pessoa TENTOU comprar. Esta camada é SÓ LEITURA e fica ao lado do board —
// não altera nenhum valor que o board já mostra.
//
// Glossário (o mesmo das funções fn_fin_hotmart_* no banco):
//   valorOferta  — preço da oferta. É o BRUTO do negócio (sem os juros do parcelamento).
//   cobrado      — o que saiu do bolso do cliente (com juros, que ficam com a Hotmart).
//   taxaHotmart  — 4% + R$ 1 sobre o valor da oferta.
//   liquido      — o que fica para o produtor (comissão PRODUCER).

export type FamiliaHotmart = 'HM' | 'AURUM';

export interface DiaHotmart {
  dia: string;
  vendas: number;
  valor_oferta: number;
  cobrado_cliente: number;
  juros: number;
  taxa_hotmart: number;
  liquido: number;
  liquido_estimado: number;
  estornos: number;
  valor_estornado: number;
  recusadas: number;
  boletos_gerados: number;
  compradores: number;
}

export type SituacaoPessoa =
  | 'devendo' | 'em_pagamento' | 'negociacao_cancelamento' | 'reembolsado'
  | 'ativo' | 'inadimplencia_antiga' | 'vencido' | 'boleto_em_aberto' | 'so_tentou';

export interface PessoaHotmart {
  /** Componente conexo do grafo e-mail × documento × conta Hotmart (fin.identidade). */
  pessoa_chave: string;
  nome: string | null;
  emails: string[];
  documentos: string[];
  telefone: string | null;
  cidade: string | null;
  situacao: SituacaoPessoa;
  aviso: string | null;
  primeira_compra: string | null;
  primeira_oferta: string | null;
  /** SCK da primeira compra — de onde a pessoa veio. */
  origem: string | null;
  /** Caminho das categorias pagas, ex.: "sinal → diferenca → renovacao". */
  fluxo: string | null;
  produtos: string[] | null;
  ultima_compra_paga: string | null;
  compras_pagas: number;
  valor_pago: number;
  liquido: number;
  estornos: number;
  valor_estornado: number;
  /** Parcelas OVERDUE dos últimos 120 dias — a dívida atual. */
  parcelas_atrasadas: number;
  valor_atrasado: number;
  /** OVERDUE mais antigo (assinatura cancelada fica OVERDUE para sempre). */
  atrasadas_antigas: number;
  valor_atrasado_antigo: number;
  em_aberto: number;
  recusadas: number;
  ultima_tentativa: string | null;
  no_gps: boolean;
  turma: string | null;
  acesso_ate: string | null;
  acesso_hotmart_ate: string | null;
  cards: number;
  contato_hm_id: string | null;
  status_card: string | null;
  saldo_card: number | null;
  canal_card: string | null;
  solicitou_cancelamento: boolean;
  /** Pares "talvez mesma pessoa" (telefone/nome igual) ainda não confirmados. */
  sugestoes: number;
}

export interface TransacaoHotmart {
  transacao: string;
  /** E-mail usado NESTA compra (a pessoa pode ter vários). */
  email: string;
  produto: string | null;
  oferta_codigo: string | null;
  status: string;
  grupo: 'pago' | 'estornado' | 'atrasado' | 'em_aberto' | 'recusado' | 'expirado' | 'outro';
  metodo: string | null;
  parcelas: number | null;
  recorrencia: number | null;
  valor_oferta: number | null;
  cobrado: number | null;
  juros: number | null;
  taxa_hotmart: number | null;
  liquido: number | null;
  liquido_estimado: boolean;
  pedido_em: string | null;
  aprovado_em: string | null;
  garantia_ate: string | null;
  origem_sck: string | null;
}

export interface OfertaHotmart {
  oferta_codigo: string;
  produto: string | null;
  papel_produto: string | null;
  modo_pagamento: string | null;
  preco_oferta: number | null;
  vendas_pagas: number;
  estornos: number;
  recusadas: number;
  receita_oferta: number;
  receita_liquida: number;
  primeira_venda: string | null;
  ultima_venda: string | null;
  categoria_catalogo: string | null;
  papel_catalogo: string | null;
  nome_comercial: string | null;
  no_catalogo: boolean;
  ativa: boolean | null;
}

export interface DivergenciaHotmart {
  tipo: 'falta_no_banco' | 'produto_sem_webhook' | 'status_diferente' | 'valor_diferente';
  transacao: string | null;
  email: string | null;
  status_hotmart: string | null;
  status_banco: string | null;
  valor_hotmart: number | null;
  valor_banco: number | null;
  pedido_em: string | null;
  detalhe: string;
}

export interface SyncHotmart {
  transacoes: number;
  ultima_atualizacao: string | null;
  janelas_pendentes: number;
  janelas_com_erro: number;
  primeira_venda: string | null;
}

export interface ResumoHotmart {
  vendas: number;
  valorOferta: number;
  cobrado: number;
  juros: number;
  taxa: number;
  liquido: number;
  liquidoEstimado: number;
  estornos: number;
  valorEstornado: number;
  recusadas: number;
  /** líquido ÷ valor da oferta (0..1). null sem venda — nunca 0% inventado. */
  margem: number | null;
}

/** Soma os dias do período. Números vêm do Postgres como string às vezes (numeric). */
export function resumirHotmart(dias: DiaHotmart[]): ResumoHotmart {
  const n = (v: unknown) => Number(v ?? 0) || 0;
  const r = dias.reduce(
    (a, d) => ({
      vendas: a.vendas + n(d.vendas),
      valorOferta: a.valorOferta + n(d.valor_oferta),
      cobrado: a.cobrado + n(d.cobrado_cliente),
      juros: a.juros + n(d.juros),
      taxa: a.taxa + n(d.taxa_hotmart),
      liquido: a.liquido + n(d.liquido),
      liquidoEstimado: a.liquidoEstimado + n(d.liquido_estimado),
      estornos: a.estornos + n(d.estornos),
      valorEstornado: a.valorEstornado + n(d.valor_estornado),
      recusadas: a.recusadas + n(d.recusadas),
    }),
    { vendas: 0, valorOferta: 0, cobrado: 0, juros: 0, taxa: 0, liquido: 0, liquidoEstimado: 0, estornos: 0, valorEstornado: 0, recusadas: 0 },
  );
  return { ...r, margem: r.valorOferta > 0 ? r.liquido / r.valorOferta : null };
}

export const ROTULO_SITUACAO: Record<SituacaoPessoa, string> = {
  devendo: 'Devendo',
  em_pagamento: 'Em pagamento',
  negociacao_cancelamento: 'Cancelamento em negociação',
  reembolsado: 'Reembolsado / chargeback',
  ativo: 'Ativo (pagou no último ano)',
  inadimplencia_antiga: 'Inadimplência antiga (+120 dias)',
  vencido: 'Vencido (último pagamento há mais de 1 ano)',
  boleto_em_aberto: 'Boleto em aberto',
  so_tentou: 'Só tentou (nunca pagou)',
};

/** Ordem de leitura da tela: o que pede ação primeiro. */
export const ORDEM_SITUACAO: SituacaoPessoa[] = [
  'devendo', 'negociacao_cancelamento', 'em_pagamento', 'boleto_em_aberto',
  'reembolsado', 'ativo', 'inadimplencia_antiga', 'vencido', 'so_tentou',
];

export function contarSituacoes(pessoas: PessoaHotmart[]): Record<SituacaoPessoa, number> {
  const base = Object.fromEntries(ORDEM_SITUACAO.map((s) => [s, 0])) as Record<SituacaoPessoa, number>;
  for (const p of pessoas) if (p.situacao in base) base[p.situacao] += 1;
  return base;
}

export const ROTULO_GRUPO: Record<TransacaoHotmart['grupo'], string> = {
  pago: 'Pago',
  estornado: 'Reembolsado / chargeback',
  atrasado: 'Parcela atrasada',
  em_aberto: 'Boleto em aberto',
  recusado: 'Cartão recusado',
  expirado: 'Boleto vencido',
  outro: 'Outro',
};

/** Par "talvez mesma pessoa" (telefone/nome igual) ou documento em revisão. Nada é juntado sozinho. */
export interface IdentidadeRevisao {
  tipo: 'sugestao' | 'revisao';
  motivo: string;
  evidencia: string | null;
  pessoa_a: string;
  emails_a: string[] | null;
  nomes_a: string[] | null;
  pessoa_b: string | null;
  emails_b: string[] | null;
  nomes_b: string[] | null;
  pago_a: number | null;
  pago_b: number | null;
}

/**
 * Rótulo do documento na lista. Quem tem gp_pode_ver_cpf() recebe só dígitos e o tipo sai
 * do tamanho; os demais já recebem "CPF ···1234" / "CNPJ ···1234" do banco — o tamanho da
 * string mascarada não diz o tipo (7 caracteres rotulariam todo CNPJ como CPF).
 */
export function rotuloDocumento(doc: string): string {
  if (!/^\d+$/.test(doc)) return doc;
  return `${doc.length === 14 ? 'CNPJ' : 'CPF'} ···${doc.slice(-4)}`;
}

/**
 * Célula de CSV (separador ;). Nome e origem vêm de terceiros (Hotmart): célula que começa
 * com = + - @ tab ou CR ganha apóstrofo, para o Excel/Sheets ler como texto e não fórmula.
 */
export function celulaCsv(v: unknown): string {
  let t = v == null ? '' : String(v);
  if (/^[=+\-@\t\r]/.test(t)) t = `'${t}`;
  return /[;"\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
}

/** Colunas que as RPCs devolvem — o teste de contrato confere contra o RETURNS TABLE das migrações. */
export const COLUNAS_PESSOA_HOTMART = [
  'pessoa_chave', 'nome', 'emails', 'documentos', 'telefone', 'cidade', 'situacao', 'aviso',
  'primeira_compra', 'primeira_oferta', 'origem', 'fluxo', 'produtos', 'ultima_compra_paga', 'compras_pagas',
  'valor_pago', 'liquido', 'estornos', 'valor_estornado', 'parcelas_atrasadas', 'valor_atrasado',
  'atrasadas_antigas', 'valor_atrasado_antigo', 'em_aberto', 'recusadas', 'ultima_tentativa', 'no_gps', 'turma',
  'acesso_ate', 'acesso_hotmart_ate', 'cards', 'contato_hm_id', 'status_card', 'saldo_card', 'canal_card',
  'solicitou_cancelamento', 'sugestoes',
] as const satisfies readonly (keyof PessoaHotmart)[];

export const COLUNAS_IDENTIDADE_REVISAO = [
  'tipo', 'motivo', 'evidencia', 'pessoa_a', 'emails_a', 'nomes_a', 'pessoa_b', 'emails_b', 'nomes_b', 'pago_a', 'pago_b',
] as const satisfies readonly (keyof IdentidadeRevisao)[];
