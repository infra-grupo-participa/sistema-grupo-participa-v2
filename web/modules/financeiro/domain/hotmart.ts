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

export type FamiliaHotmart = 'HM' | 'AURUM' | 'ACELERA';

/** Rótulo de tela da família (fin.produtos.familia). Acelera Holding = preparatório do HM (27/09/2026). */
export const ROTULO_FAMILIA: Record<FamiliaHotmart, string> = {
  HM: 'Holding Masters', AURUM: 'Aurum', ACELERA: 'Acelera Holding',
};

/** Faturamento por funil (fin.funis: janela de datas por família), de fn_fin_hotmart_funis. */
export interface FunilHotmart {
  funil: string;
  vale_de: string | null;
  vale_ate: string | null;
  vendas: number;
  compradores: number;
  valor_oferta: number;
  cobrado_cliente: number;
  juros: number;
  taxa_hotmart: number;
  liquido: number;
  estornos: number;
  valor_estornado: number;
  recusadas: number;
  boletos: number;
  /** Vendas pagas em mais de 1 parcela. */
  parcelado: number;
  parcelas_media: number | null;
}

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
  /** Parcelas devidas há até 120 dias — a dívida atual. Parcela = e-mail × produto × oferta ×
   *  recorrência: cada nova tentativa de cobrança não conta de novo, e parcela paga depois sai. */
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
  /** Operação (20260928b), só vendas pagas: o que saiu do bolso do cliente (inclui juros). */
  cobrado_cliente: number;
  juros: number;
  taxa_hotmart: number;
  /** oferta − taxa − líquido somado (piso 0): a parte do coprodutor. */
  coproducao: number;
  vendas_parceladas: number;
  parcelas_max: number | null;
  /** Método mais frequente nas vendas pagas; empate → o mais recente. */
  forma_pagamento_principal: string | null;
}

/**
 * Card do board × espelho Hotmart (fn_fin_board_hotmart, 20260928c). Só aviso: não muda valor do board.
 * Valores são por pessoa × família — cards_da_pessoa > 1 repete os números em cada card.
 */
export interface BoardHotmart {
  contato_hm_id: string;
  origem: 'HM' | 'AURUM';
  encontrado: boolean;
  pessoa_chave: string | null;
  cards_da_pessoa: number;
  /** Vendas pagas em ofertas de categoria sinal / diferenca / compra_cheia (escopo do board). */
  vendas_pagas: number;
  pago_bruto: number;
  taxa_hotmart: number;
  coproducao: number;
  liquido: number;
  cobrado_cliente: number;
  juros: number;
  parcelas_max: number | null;
  forma_pagamento_principal: string | null;
  ultimo_pagamento_em: string | null;
  ultimo_pagamento_valor: number | null;
  /** Dívida por parcela (fin.parcelas_devidas), todas as ofertas da família. */
  parcelas_devidas: number;
  valor_devido: number;
  devido_antigo: number;
  estornos: number;
  valor_estornado: number;
  /** Vendas pagas no escopo cuja transação não está em cs.hm_pagamentos. */
  falta_no_board: number;
  valor_falta_no_board: number;
  /** Lançamentos origem 'hotmart' do card que o espelho não tem ou dá como estornados. */
  board_sem_hotmart: number;
  /** null no AURUM (planilha sem transação) e em card sem pessoa. */
  diverge: boolean | null;
  sincronizado_em: string | null;
  /**
   * Assinatura HM (20260928d): mensalidades pagas (oferta_modo SUBSCRIPTION) — contrato à parte, fora de
   * vendas_pagas/pago_bruto. Por pessoa × família HM; AURUM e card sem pessoa = 0 / null.
   * Opcionais: a função de 20260928c (antes de aplicar a 20260928d) não devolve estas colunas.
   */
  assinatura_mensalidades?: number;
  assinatura_valor?: number;
  assinatura_de?: string | null;
  assinatura_ate?: string | null;
  /** Última mensalidade paga há ≤ 45 dias e nenhuma parcela HM devida (≤ 120 d). null no AURUM / sem pessoa. */
  assinatura_ativa?: boolean | null;
}

/**
 * Pro rata do HM (fn_fin_prorata_hm, 20260928d): 1 linha por pessoa com acesso (thb_alunos.data_expiracao)
 * e ao menos 1 venda HM paga. credito = pago_no_ciclo × meses_restantes ÷ 12; diferenca = programa − credito
 * (piso 0). Sem Acelera. Numeric pode chegar como string pelo PostgREST.
 */
export interface ProrataHM {
  pessoa_chave: string;
  nome: string | null;
  email: string | null;
  turma: string | null;
  /** Maior data_expiracao entre os alunos da pessoa. */
  vencimento: string;
  /** Meses cheios de hoje (America/Sao_Paulo) até o vencimento; vencido = 0. */
  meses_restantes: number;
  /** Vendas HM pagas com dia_aprovado em [vencimento − 12 meses − 60 dias, vencimento]. */
  pago_no_ciclo: number;
  pagamentos_no_ciclo: number;
  /** Ex.: '12 mensalidades · 1 renovação'. null sem pagamento no ciclo. */
  formas: string | null;
  credito: number;
  diferenca: number;
  ultimo_pagamento: string | null;
  tem_card: boolean;
  contato_hm_id: string | null;
  no_gps: boolean;
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
  /** Repasse a coprodutor/afiliado/add-on = oferta − taxa − líquido (Aurum antigo tem coprodutor; HM não). */
  repasses: number;
  /** líquido ÷ valor da oferta (0..1). null sem venda — nunca 0% inventado. */
  margem: number | null;
  /** taxa ÷ valor da oferta (0..1). null sem venda. */
  taxaPct: number | null;
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
  const repasses = Math.max(0, Math.round((r.valorOferta - r.taxa - r.liquido) * 100) / 100);
  return {
    ...r,
    repasses,
    margem: r.valorOferta > 0 ? r.liquido / r.valorOferta : null,
    taxaPct: r.valorOferta > 0 ? r.taxa / r.valorOferta : null,
  };
}

/**
 * Regra de cobrança da Hotmart por produto, medida em 27/09/2026 sobre as vendas pagas:
 * - HM e Aurum: **4% do valor da oferta + R$ 1** (≈ 95% de 3.571 vendas; até 2024 algumas saíam a ~6%). Efetiva 4,05%.
 * - Acelera Holding: **5,3% + R$ 1** (414 de 415 vendas). Efetiva 5,35%.
 * Juros do parcelamento são pagos pelo CLIENTE e ficam com a Hotmart — não saem do bruto nem entram no líquido.
 */
export const REGRA_TAXA_HOTMART: Record<FamiliaHotmart, string> = {
  HM: '4% do valor + R$ 1 por venda',
  AURUM: '4% do valor + R$ 1 por venda',
  ACELERA: '5,3% do valor + R$ 1 por venda',
};

/** Quem divide a venda com o produtor, por produto (comissões COPRODUCER/AFFILIATE/ADDON da API). */
export const QUEM_DIVIDE: Record<FamiliaHotmart, string> = {
  HM: 'coprodutor, afiliados e add-on',
  AURUM: 'coprodutor (Borboleta Digital), afiliados e add-on — produtos antigos do Aurum',
  ACELERA: 'coprodutores Filipe Jung Jorge e Henrique Brenha, e add-on',
};

export interface DiaHotmartSerie {
  dia: string;
  /** true = dia sem movimento algum (a RPC só devolve dias com movimento) — zero explícito, não omitido. */
  preenchido: boolean;
  vendas: number;
  bruto: number;
  taxa: number;
  repasses: number;
  liquido: number;
  juros: number;
  estornos: number;
  valorEstornado: number;
  recusadas: number;
  boletos: number;
  liquidoEstimado: number;
  acumulado: number;
  /** Variação % do bruto vs. o dia anterior (null sem dia anterior com venda). */
  variacaoDiaAnterior: number | null;
}

function proximoDia(ymd: string): string {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
}

/**
 * Série do Faturamento Diário: dias em ordem crescente, com os dias SEM movimento entre o primeiro e o
 * último preenchidos como zero explícito (`preenchido`) — senão a variação comparava com um dia que não
 * é o anterior. Números do Postgres (numeric) podem vir como string.
 */
export function serieHotmart(dias: DiaHotmart[]): DiaHotmartSerie[] {
  if (!dias.length) return [];
  const n = (v: unknown) => Number(v ?? 0) || 0;
  const asc = [...dias].sort((a, b) => a.dia.localeCompare(b.dia));
  const porDia = new Map(asc.map((d) => [d.dia, d]));
  const saida: DiaHotmartSerie[] = [];
  let acumulado = 0;
  let anterior: DiaHotmartSerie | null = null;
  for (let dia = asc[0].dia; dia <= asc[asc.length - 1].dia; dia = proximoDia(dia)) {
    const d = porDia.get(dia);
    const bruto = n(d?.valor_oferta), taxa = n(d?.taxa_hotmart), liquido = n(d?.liquido);
    acumulado += bruto;
    const linha: DiaHotmartSerie = {
      dia, preenchido: !d, vendas: n(d?.vendas), bruto, taxa, liquido,
      repasses: Math.max(0, Math.round((bruto - taxa - liquido) * 100) / 100),
      juros: n(d?.juros), estornos: n(d?.estornos), valorEstornado: n(d?.valor_estornado),
      recusadas: n(d?.recusadas), boletos: n(d?.boletos_gerados), liquidoEstimado: n(d?.liquido_estimado),
      acumulado,
      variacaoDiaAnterior: anterior && anterior.bruto > 0 ? ((bruto - anterior.bruto) / anterior.bruto) * 100 : null,
    };
    saida.push(linha);
    anterior = linha;
  }
  return saida;
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
 * Rótulo pt-BR do método de pagamento (fin.*.metodo — vem cru da API da Hotmart, ex.:
 * CREDIT_CARD_VISA, CREDIT_CARD_MASTERCARD, BILLET, PIX, PAYPAL, APPLE_PAY, GOOGLE_PAY…).
 * Qualquer CREDIT_CARD_* cai em "Cartão" — a bandeira não importa para o financeiro.
 * Desconhecido: Title Case do texto cru (nunca esconde um método novo como "—").
 */
export function rotuloMetodo(metodo: string | null): string {
  if (!metodo) return '—';
  const m = metodo.toUpperCase();
  if (m.startsWith('CREDIT_CARD')) return 'Cartão';
  if (m === 'BILLET' || m === 'BOLETO') return 'Boleto';
  if (m === 'PIX') return 'Pix';
  const CONHECIDOS: Record<string, string> = {
    PAYPAL: 'PayPal', APPLE_PAY: 'Apple Pay', GOOGLE_PAY: 'Google Pay', SAMSUNG_PAY: 'Samsung Pay',
    DIRECT_BANK_TRANSFER: 'Transferência bancária', HOTCARD: 'HotCard', PICPAY: 'PicPay',
  };
  if (CONHECIDOS[m]) return CONHECIDOS[m];
  return m.split('_').filter(Boolean).map((w) => w.charAt(0) + w.slice(1).toLowerCase()).join(' ');
}

/**
 * Célula de CSV (separador ;). Nome, cidade e origem (sck) vêm de terceiros (Hotmart):
 * - célula que começa (depois de espaços) com = + - @ — inclusive as de largura cheia ＝＋－＠ — ou tab/CR
 *   ganha apóstrofo, para o Excel/Sheets ler como texto e não fórmula;
 * - CR ou LF no MEIO do texto também força aspas: o Excel lê `\r` solto como fim de linha e a fórmula
 *   depois dele abriria célula nova (pentest 27/09).
 */
export function celulaCsv(v: unknown): string {
  let t = v == null ? '' : String(v);
  if (/^\s*[=+\-@＝＋－＠]/.test(t) || /^[\t\r]/.test(t)) t = `'${t}`;
  return /[;"\r\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
}

/** Colunas que as RPCs devolvem — o teste de contrato confere contra o RETURNS TABLE das migrações. */
export const COLUNAS_PESSOA_HOTMART = [
  'pessoa_chave', 'nome', 'emails', 'documentos', 'telefone', 'cidade', 'situacao', 'aviso',
  'primeira_compra', 'primeira_oferta', 'origem', 'fluxo', 'produtos', 'ultima_compra_paga', 'compras_pagas',
  'valor_pago', 'liquido', 'estornos', 'valor_estornado', 'parcelas_atrasadas', 'valor_atrasado',
  'atrasadas_antigas', 'valor_atrasado_antigo', 'em_aberto', 'recusadas', 'ultima_tentativa', 'no_gps', 'turma',
  'acesso_ate', 'acesso_hotmart_ate', 'cards', 'contato_hm_id', 'status_card', 'saldo_card', 'canal_card',
  'solicitou_cancelamento', 'sugestoes',
  'cobrado_cliente', 'juros', 'taxa_hotmart', 'coproducao', 'vendas_parceladas', 'parcelas_max', 'forma_pagamento_principal',
] as const satisfies readonly (keyof PessoaHotmart)[];

export const COLUNAS_BOARD_HOTMART = [
  'contato_hm_id', 'origem', 'encontrado', 'pessoa_chave', 'cards_da_pessoa',
  'vendas_pagas', 'pago_bruto', 'taxa_hotmart', 'coproducao', 'liquido',
  'cobrado_cliente', 'juros', 'parcelas_max', 'forma_pagamento_principal',
  'ultimo_pagamento_em', 'ultimo_pagamento_valor',
  'parcelas_devidas', 'valor_devido', 'devido_antigo',
  'estornos', 'valor_estornado',
  'falta_no_board', 'valor_falta_no_board', 'board_sem_hotmart',
  'diverge', 'sincronizado_em',
  'assinatura_mensalidades', 'assinatura_valor', 'assinatura_de', 'assinatura_ate', 'assinatura_ativa',
] as const satisfies readonly (keyof BoardHotmart)[];

export const COLUNAS_PRORATA_HM = [
  'pessoa_chave', 'nome', 'email', 'turma', 'vencimento', 'meses_restantes', 'pago_no_ciclo', 'pagamentos_no_ciclo',
  'formas', 'credito', 'diferenca', 'ultimo_pagamento', 'tem_card', 'contato_hm_id', 'no_gps',
] as const satisfies readonly (keyof ProrataHM)[];

export const COLUNAS_IDENTIDADE_REVISAO = [
  'tipo', 'motivo', 'evidencia', 'pessoa_a', 'emails_a', 'nomes_a', 'pessoa_b', 'emails_b', 'nomes_b', 'pago_a', 'pago_b',
] as const satisfies readonly (keyof IdentidadeRevisao)[];

/** Quem comprou o Acelera Holding e o que comprou de HM depois (fn_fin_acelera_para_hm, 27/09/2026). */
export interface AceleraParaHM {
  pessoa_chave: string;
  nome: string | null;
  email: string | null;
  primeira_acelera: string | null;
  acelera_pago: number;
  acelera_funil: string | null;
  /** Já tinha pago HM antes da 1ª compra do Acelera. */
  ja_era_hm: boolean;
  /** Pagou HM na data da 1ª compra do Acelera ou depois. */
  subiu: boolean;
  primeira_hm_depois: string | null;
  dias_ate_subir: number | null;
  hm_pago_depois: number;
  hm_caminho: string | null;
  tem_card: boolean;
}

export const COLUNAS_ACELERA_PARA_HM = [
  'pessoa_chave', 'nome', 'email', 'primeira_acelera', 'acelera_pago', 'acelera_funil', 'ja_era_hm', 'subiu',
  'primeira_hm_depois', 'dias_ate_subir', 'hm_pago_depois', 'hm_caminho', 'tem_card',
] as const satisfies readonly (keyof AceleraParaHM)[];

/** Um pagamento no diagnóstico do pro rata, com o motivo de entrar ou não no ciclo. */
export interface ProrataPagamento {
  transacao: string;
  data: string | null;
  produto: string | null;
  familia: FamiliaHotmart;
  oferta: string | null;
  /** mensalidade · sinal · diferenca · compra_cheia · renovacao · reserva… */
  forma: string | null;
  metodo: string | null;
  parcelas: number | null;
  recorrencia: number | null;
  situacao: TransacaoHotmart['grupo'];
  valor: number | null;
  cobrado: number | null;
  juros: number | null;
  liquido: number | null;
  entra: boolean;
  /** Frase pronta: "entra: pago dentro do ciclo atual", "fora: pago antes do ciclo atual (ciclo anterior)"… */
  motivo: string;
  email: string;
}

/**
 * Diagnóstico do pro rata de UMA pessoa (fn_fin_prorata_diagnostico, 27/09/2026) — a Calculadora de Pro Rata.
 * crédito = pago no ciclo × meses cheios restantes ÷ 12; diferença = valor do programa − crédito. Sem Acelera.
 * `vencimento`/`valor` informados na tela são SIMULAÇÃO (nada é gravado).
 */
export interface ProrataDiagnostico {
  pessoa: {
    nome: string | null;
    emails: string[];
    turma: string | null;
    vencimento_cadastrado: string | null;
    vencimento_usado: string | null;
    vencimento_simulado: boolean;
    no_gps: boolean;
  };
  ciclo: { inicio: string | null; fim: string | null; hoje: string; meses_restantes: number };
  calculo: {
    pago_no_ciclo: number;
    pagamentos_no_ciclo: number;
    meses_restantes: number;
    credito: number;
    valor_programa: number;
    diferenca: number;
  };
  pagamentos: ProrataPagamento[];
  board: { contato_hm_id: string; status: string | null; pago: number | null; saldo: number | null; canal: string | null } | null;
  avisos: string[];
}
