export type MetricaSessaoViabilidade = { valor: number; semDado: boolean };

/** Vendas ÷ pré-checkouts únicos por e-mail. Sem qualquer fonte ausente, preserva Sem dado. */
export function conversaoSessaoViabilidade(vendas: MetricaSessaoViabilidade, preCheckoutsUnicos: number | null): MetricaSessaoViabilidade {
  if (vendas.semDado || preCheckoutsUnicos === null || preCheckoutsUnicos <= 0) return { valor: 0, semDado: true };
  return { valor: vendas.valor / preCheckoutsUnicos * 100, semDado: false };
}

/**
 * Uma linha de `public.dados_atm_sv_vendas(p_chave, p_incluir_teste)`: uma venda da Sessão de Viabilidade.
 * Campo ausente na fonte fica `null` ("Sem dado" na tela), nunca zero nem texto inventado.
 */
export type VendaSessaoViabilidade = {
  id: string;
  transacao: string | null;
  aprovadoEm: string | null;
  pedidoEm: string | null;
  diaAprovado: string | null;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  valorBruto: number | null;
  valorLiquido: number | null;
  moeda: string | null;
  status: string | null;
  ofertaCodigo: string | null;
  teste: boolean;
};

/** Vendas que contam: a marcação de teste (dados.marcacoes_teste) tira a linha de qualquer total da tela. */
export function vendasValidasSessaoViabilidade(vendas: VendaSessaoViabilidade[]): VendaSessaoViabilidade[] {
  return vendas.filter((venda) => !venda.teste);
}

/** Contagem da lista carregada, separando as linhas marcadas como teste. */
export function contarVendasSessaoViabilidade(vendas: VendaSessaoViabilidade[]): { validas: number; teste: number } {
  const validas = vendasValidasSessaoViabilidade(vendas).length;
  return { validas, teste: vendas.length - validas };
}

/** Nota do card Total de vendas: `vendas_teste` do `dados_atm_resumo`. Nulo ou zero não gera nota. */
export function notaVendasTesteForaDoTotal(vendasTeste: number | null | undefined): string | null {
  if (vendasTeste == null || !Number.isFinite(vendasTeste) || vendasTeste <= 0) return null;
  return vendasTeste === 1 ? '1 venda de teste fora do total' : `${vendasTeste.toLocaleString('pt-BR')} vendas de teste fora do total`;
}

/** "Data da venda" da tabela de vendas (decisão do Victor, 13/10: a visão de pré-checkout usa a data do pré-checkout): `aprovado_em` em São Paulo; sem ele, `dia_aprovado`; sem os dois, nulo. */
export function dataDaVendaSessaoViabilidade(venda: Pick<VendaSessaoViabilidade, 'aprovadoEm' | 'diaAprovado'>): string | null {
  if (venda.aprovadoEm) {
    const data = new Date(venda.aprovadoEm);
    if (!Number.isNaN(data.getTime())) return data.toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' });
  }
  const dia = venda.diaAprovado?.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return dia ? `${dia[3]}/${dia[2]}/${dia[1]}` : null;
}

/**
 * Valor na moeda da própria venda (a RPC devolve a unidade da moeda, não centavos).
 * Sem moeda na fonte não se presume real: sai só o número. Código que o Intl recusa sai cru ao lado do número.
 */
export function valorDaVendaSessaoViabilidade(valor: number | null, moeda: string | null): string | null {
  if (valor === null) return null;
  const numero = valor.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (!moeda) return numero;
  try {
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: moeda.toUpperCase() }).format(valor);
  } catch {
    return `${numero} ${moeda}`;
  }
}

export type ListaSv<T> = { data: T[]; semDado: boolean; erro: string | null; semPermissao?: boolean };

/**
 * Estado da lista depois de uma leitura. Sucesso substitui; permissão perdida (42501) limpa a lista;
 * qualquer outra falha preserva a última lista e só troca o aviso.
 */
export function listaAposLeituraSv<T>(anterior: ListaSv<T>, leitura: ListaSv<T>): ListaSv<T> {
  if (!leitura.semDado) return { data: leitura.data, semDado: false, erro: leitura.erro };
  if (leitura.semPermissao) return { data: [], semDado: true, erro: leitura.erro, semPermissao: true };
  return { data: anterior.data, semDado: anterior.semDado, erro: leitura.erro };
}
