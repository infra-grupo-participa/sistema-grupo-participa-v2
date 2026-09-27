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
  email: string;
  nome: string | null;
  situacao: SituacaoPessoa;
  aviso: string | null;
  primeira_compra: string | null;
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
  acesso_ate: string | null;
  acesso_hotmart_ate: string | null;
  contato_hm_id: string | null;
  status_card: string | null;
  saldo_card: number | null;
  solicitou_cancelamento: boolean;
}

export interface TransacaoHotmart {
  transacao: string;
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
