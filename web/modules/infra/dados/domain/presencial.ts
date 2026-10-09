export type Numerico = number | string | null;
export type ResumoPresencial = {
  chave: string; projeto_id: number; projeto_sigla: string | null; projeto_nome: string;
  evento_inicio: string | null; evento_fim: string | null; oferta_codigo: string;
  disparos_qtd: number; disparos_sem_custo: number; custo_disparo_centavos: Numerico; custo_completo: boolean;
  pre_checkout_pessoas: number; custo_por_pre_checkout_centavos: Numerico;
  vendas: number; vendas_fora_brl: number; compradores: number; compradores_no_pre_checkout: number;
  conversao_pct: Numerico; receita_bruta: Numerico; receita_liquida: Numerico; cac_centavos: Numerico; atualizado_em: string;
};
export type LeadPresencial = {
  email: string; nome: string | null; telefone: string | null; primeiro_em: string; fonte: string;
  utm_source: string | null; utm_medium: string | null; utm_campaign: string | null;
  utm_content: string | null; utm_term: string | null; instrucao: string | null; turma: string | null; comprou: boolean;
  pessoa_id?: string | null; teste?: boolean;
};
export type VendaPresencial = {
  transacao: string; status_grupo: string; status_hotmart: string; dia_pedido: string | null; dia_aprovado: string | null;
  moeda: string | null; valor_bruto: Numerico; valor_liquido: Numerico; email: string; nome: string | null;
  telefone: string | null; estado: string | null; instrucao: string | null; turma: string | null;
  no_pre_checkout: boolean; entrou_grupo: boolean | null; grupo_fonte: string | null;
};
export type DisparoPresencial = {
  disparo_id: number; dia: string | null; nome: string; canal: string | null; ferramenta: string | null;
  tamanho_lista: number | null; entregues: number | null; lidas: number | null; cliques: number | null; falhas: number | null;
  custo_centavos: Numerico; entrega_pct: Numerico; leitura_pct: Numerico; clique_pct: Numerico;
};
export type DiaPresencial = { dia: string; pre_checkout: number; pedidos: number; vendas: number; abandonos: number | null };
export type PagamentoPresencial = { forma: string; forma_nome: string; parcelas: number | null; vendas: number; receita_bruta: Numerico };
export type PerfilCompradorPresencial = { dimensao: 'turma' | 'instrucao' | 'casamento'; valor: string; compradores: number };
export type PendenciaPresencial = { grupo: 'nao_pago' | 'cancelada'; categoria: string; pessoas: number; transacoes: number };
export type GrupoPendencia = PendenciaPresencial['grupo'];
export type PessoaPendenciaPresencial = { email: string; nome: string | null; telefone: string | null; categorias: string; transacoes: number; valor_bruto: Numerico; ultimo_em: string };
export type SerieVendasPresencial = { dia: string; pre_checkout: number; vendas: number; receita_bruta: Numerico; vendas_acumuladas: number; receita_acumulada: Numerico; conversao_pct: Numerico };
export type VendaHoraPresencial = { hora: number; vendas: number; receita_bruta: Numerico };
export type DiamantePresencial = {
  lista_ordem: number | null; lista_nome: string | null; status: 'respondeu' | 'pendente' | 'fora_da_lista';
  casamento: 'nome' | 'manual' | null; resposta_uuid: string | null; respondido_em: string | null; n_respostas: number;
  nome_formulario: string | null; email: string | null; telefone: string | null; grupo: string | null;
  situacao: string | null; situacao_codigo: 'confirmado' | 'organizando' | 'nao_vai' | null;
  chegada: string | null; chegada_data: string | null; retorno: string | null; retorno_data: string | null;
  aeroporto: string | null; hospedagem: string | null; acompanhado: string | null; acompanhantes: string | null;
};
export type FichaInteresseMiami = {
  resposta_uuid: string; respondido_em: string | null; n_respostas: number;
  nome: string | null; email: string | null; telefone: string | null; turma: string | null;
  passaporte: string | null; visto: string | null; planos: string | null; comprou_passagem: string | null;
  data_passagem: string | null; confirma_pre_venda: string | null; deseja_programa: string | null;
  comprou: boolean; compra_status: string | null; compra_transacao: string | null; compra_em: string | null;
  casou_por: 'email' | 'telefone' | null;
};

export function numero(valor: Numerico | undefined): number | null {
  if (valor === null || valor === undefined || valor === '') return null;
  const resultado = Number(valor);
  return Number.isFinite(resultado) ? resultado : null;
}
export function normalizarNumericos<T extends object>(item: T, campos: (keyof T)[]): T {
  const copia = { ...item };
  for (const campo of campos) copia[campo] = numero(item[campo] as Numerico) as T[keyof T];
  return copia;
}
