// Mapa de alunos do HM (fn_fin_mapa_alunos, 20260928m) — uma linha por pessoa, do início do Programa até hoje.
// Regras (João, 27/09): "do Programa" = pagou o cheio ou o saldo; a 2ª metade (R$ 15 mil) só depois de o parceiro
// faturar R$ 150 mil; só faturamento. Funções PURAS: rótulos, esteira e filtros.

export type ProgramaAluno = 'programa' | 'so_sinal' | 'renovacao' | 'hm_antigo' | 'tentou';
export type SituacaoAluno = 'quitado' | 'em_dia' | 'atrasado' | 'so_sinal' | 'cancelado' | 'reembolsado' | 'sem_divida';

export interface MapaAluno {
  pessoa_chave: string;
  nome: string | null;
  email: string | null;
  emails: string[] | null;
  telefone: string | null;
  programa: ProgramaAluno;
  situacao: SituacaoAluno;
  entrou_programa_em: string | null;
  primeira_compra_em: string | null;
  primeira_compra: string | null;
  origem_sck: string | null;
  canal: string | null;
  vendedor: string | null;
  turma: string | null;
  no_gps: boolean;
  contato_hm_id: string | null;
  status_card: string | null;
  pago_vida: number;
  pago_programa: number;
  sinal_pago: number;
  pacote: number | null;
  falta_pagar: number | null;
  parcelas_devidas: number;
  valor_devido: number;
  ultimo_pagamento_em: string | null;
  ultima_tentativa_em: string | null;
  veio_do_acelera: boolean;
  honorarios_contratados: number;
  segunda_metade_liberada: boolean;
}

export const COLUNAS_MAPA_ALUNOS = [
  'pessoa_chave', 'nome', 'email', 'emails', 'telefone', 'programa', 'situacao',
  'entrou_programa_em', 'primeira_compra_em', 'primeira_compra', 'origem_sck',
  'canal', 'vendedor', 'turma', 'no_gps', 'contato_hm_id', 'status_card',
  'pago_vida', 'pago_programa', 'sinal_pago', 'pacote', 'falta_pagar',
  'parcelas_devidas', 'valor_devido', 'ultimo_pagamento_em', 'ultima_tentativa_em',
  'veio_do_acelera', 'honorarios_contratados', 'segunda_metade_liberada',
] as const satisfies readonly (keyof MapaAluno)[];

export const ROTULO_PROGRAMA: Record<ProgramaAluno, string> = {
  programa: 'No Programa',
  so_sinal: 'Reservou (só sinal)',
  renovacao: 'Renovação',
  hm_antigo: 'HM antigo',
  tentou: 'Só tentou',
};

export const ROTULO_SITUACAO_ALUNO: Record<SituacaoAluno, string> = {
  quitado: 'Quitado',
  em_dia: 'Pagando em dia',
  atrasado: 'Atrasado',
  so_sinal: 'Só pagou o sinal',
  cancelado: 'Cancelado',
  reembolsado: 'Reembolsado',
  sem_divida: 'Sem dívida',
};

/** Numeric do Postgres pode chegar como string pelo PostgREST. */
export function normalizarMapaAluno(r: MapaAluno): MapaAluno {
  const n = (v: unknown) => { const x = Number(v); return Number.isFinite(x) ? x : 0; };
  const nn = (v: unknown) => (v == null ? null : n(v));
  return {
    ...r,
    pago_vida: n(r.pago_vida), pago_programa: n(r.pago_programa), sinal_pago: n(r.sinal_pago),
    pacote: nn(r.pacote), falta_pagar: nn(r.falta_pagar), parcelas_devidas: n(r.parcelas_devidas),
    valor_devido: n(r.valor_devido), honorarios_contratados: n(r.honorarios_contratados),
  };
}

/** A esteira do Programa: cada etapa com quantas pessoas e quanto dinheiro (pago e a receber). Ordem = ordem de cobrança. */
export type EtapaEsteira = 'so_sinal' | 'atrasado' | 'em_dia' | 'quitado' | 'cancelado' | 'fora';
export const ORDEM_ESTEIRA: EtapaEsteira[] = ['so_sinal', 'atrasado', 'em_dia', 'quitado', 'cancelado', 'fora'];
export const ROTULO_ESTEIRA: Record<EtapaEsteira, string> = {
  so_sinal: 'Só pagou o sinal', atrasado: 'Atrasado', em_dia: 'Pagando em dia', quitado: 'Quitado',
  cancelado: 'Cancelado / reembolsado', fora: 'Fora do Programa',
};

export function etapaDe(a: MapaAluno): EtapaEsteira {
  if (a.situacao === 'cancelado' || a.situacao === 'reembolsado') return 'cancelado';
  if (a.programa !== 'programa' && a.programa !== 'so_sinal') return a.situacao === 'atrasado' ? 'atrasado' : 'fora';
  if (a.situacao === 'atrasado') return 'atrasado';
  if (a.situacao === 'so_sinal') return 'so_sinal';
  if (a.situacao === 'em_dia') return 'em_dia';
  return 'quitado';
}

export interface ResumoEtapa { etapa: EtapaEsteira; pessoas: number; pago: number; aReceber: number }

export function montarEsteira(lista: MapaAluno[]): ResumoEtapa[] {
  const base = new Map<EtapaEsteira, ResumoEtapa>(ORDEM_ESTEIRA.map((e) => [e, { etapa: e, pessoas: 0, pago: 0, aReceber: 0 }]));
  for (const a of lista) {
    const r = base.get(etapaDe(a))!;
    r.pessoas += 1;
    r.pago += a.programa === 'programa' || a.programa === 'so_sinal' ? a.pago_programa : a.pago_vida;
    r.aReceber += etapaDe(a) === 'cancelado' ? 0 : (a.falta_pagar ?? 0) + (a.programa === 'programa' || a.programa === 'so_sinal' ? 0 : a.valor_devido);
  }
  return ORDEM_ESTEIRA.map((e) => base.get(e)!);
}
