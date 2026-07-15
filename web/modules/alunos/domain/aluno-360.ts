// Domínio da ficha 360 — porta dos mapas/ranks de sistema/alunos/js/app.js.
// O objeto vem do RPC fn_aluno_360_safe (documento já mascarado server-side via _can_see_sensivel).

export interface Aluno360 {
  id: string;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  telefone_profissional: string | null;
  documento: string | null;
  tipo_documento: string | null;
  profissao: string | null;
  link_facebook: string | null;
  instagram_url: string | null;
  youtube_url: string | null;
  site_profissional: string | null;
  cep: string | null;
  endereco_logradouro: string | null;
  endereco_numero: string | null;
  endereco_complemento: string | null;
  bairro: string | null;
  cidade: string | null;
  estado: string | null;
  pais: string | null;
  turma_id: number | null;
  turma_codigo: string | null;
  turma_aurum_id: number | null;
  turma_aurum_codigo: string | null;
  nivel_resultado: string | null;
  placa_aurum: string | null;
  espaco_instrucao: string | null;
  eh_socio: boolean | null;
  situacao_acesso: string | null;
  situacao_financeira: string | null;
  status_acesso: string | null;
  status_acesso_central: string | null;
  produto: string | null;
  oferta: string | null;
  tipo_oferta: string | null;
  regra_acesso: string | null;
  origem_acesso: string | null;
  instrucao: string | null;
  tempo_acesso: string | null;
  data_expiracao: string | null;
  mes_expiracao: number | null;
  ano_expiracao: number | null;
  data_compra_importada: string | null;
  hotmart_ucode: string | null;
  // financeiro
  valor_total: number | null;
  valor_pago: number | null;
  saldo_devedor: number | null;
  status_pagamento: string | null;
  ultimo_pagamento: string | null;
  num_cobrancas: number | null;
  /** Quantas vezes o aluno renovou (compras de renovação HM em public.compras). */
  num_renovacoes: number | null;
  // CS
  cs_estagio: string | null;
  cs_responsavel: string | null;
  cs_ultimo_contato_em: string | null;
  cs_proxima_acao_em: string | null;
  cs_observacoes: string | null;
  sip_registrado: boolean | null;
  tratamento_manual: string | null;
  obs_central: string | null;
  // jornada (derivada, read-only)
  tem_ht: boolean | null;
  data_compra_ht: string | null;
  ativacao_ht_status: string | null;
  tem_hm: boolean | null;
  data_compra_hm: string | null;
  ativacao_hm_status: string | null;
  hm_plano: string | null;
  tem_placa: boolean | null;
  placa_step: number | null;
  placa_encerrada: boolean | null;
  placa_protocolo: string | null;
  tem_solicitacao_placa: boolean | null;
  placa_sol_status: string | null;
  placa_rastreio: string | null;
  placa_entrevista_data: string | null;
  placa_regularizacao_pendente: boolean | null;
  tem_depoimento: boolean | null;
  total_depoimentos: number | null;
  // metadados
  fonte: string | null;
  importado_em: string | null;
  atualizado_em: string | null;
  _can_see_sensivel?: boolean;
}

// Espaço de instrução = GRUPO em que o aluno está inserido (≠ nível, que é faturamento).
// Chaves reais do banco (thb_alunos.espaco_instrucao): holding_masters, aurum,
// platina, mastermind_diamante, diamante_vermelho.
export const ESPACO_LABEL: Record<string, string> = {
  holding_masters: 'Holding Masters',
  aurum: 'Aurum',
  platina: 'Platina',
  mastermind_diamante: 'Diamante',
  diamante_vermelho: 'Diamante Vermelho',
};

/** Cor por espaço de instrução (bolinhas/badges e gráficos). */
export const ESPACO_COLOR: Record<string, string> = {
  holding_masters: 'var(--nivel-platina)',
  aurum: 'var(--nivel-ouro)',
  platina: 'var(--green)',
  mastermind_diamante: 'var(--nivel-diamante)',
  diamante_vermelho: 'var(--nivel-diamante-vermelho)',
};

export const ESPACO_CLS: Record<string, string> = {
  holding_masters: 'blue',
  aurum: 'yellow',
  platina: 'green',
  mastermind_diamante: 'purple',
  diamante_vermelho: 'red',
};

// ── Renovação por faixa de turma ──
// T1–T29 → em processo de renovação. T30+ → acesso vencido, sem processo
// (todos com acesso em dia porém vencido, pois não passaram pela renovação).
export type RenovacaoStatus = 'em_renovacao' | 'vencido_sem_processo' | null;

/** Extrai o número da turma a partir do código (T17R, T29.2 → 17, 29). */
export function turmaNumero(codigo: string | null | undefined): number | null {
  if (!codigo) return null;
  const m = /^T0*(\d+)/i.exec(codigo.trim());
  return m ? Number(m[1]) : null;
}

export function renovacaoStatus(turmaCodigo: string | null | undefined): RenovacaoStatus {
  const n = turmaNumero(turmaCodigo);
  if (n == null) return null;
  return n <= 29 ? 'em_renovacao' : 'vencido_sem_processo';
}

export const RENOVACAO_LABEL: Record<Exclude<RenovacaoStatus, null>, { label: string; cls: string }> = {
  em_renovacao: { label: 'Processo de renovação', cls: 'yellow' },
  vencido_sem_processo: { label: 'Vencido — sem processo de renovação', cls: 'red' },
};

export const SITUACAO: Record<string, { cls: string; label: string }> = {
  em_dia: { cls: 'green', label: 'Em dia' },
  a_vencer: { cls: 'yellow', label: 'A vencer' },
  vencido: { cls: 'red', label: 'Vencido' },
  acompanha_titular: { cls: 'gray', label: 'Acompanha titular' },
};

// ── Acesso ao Curso (Hotmart) ──
// Estado do acesso ao curso (status_acesso).
export const STATUS_ACESSO: Record<string, { cls: string; label: string }> = {
  renovado: { cls: 'green', label: 'Renovado' },
  vigente: { cls: 'green', label: 'Vigente' },
  gratuidade: { cls: 'blue', label: 'Gratuidade' },
};

// ── Situação Financeira (adesão THB) ──
export const SITUACAO_FINANCEIRA: Record<string, { cls: string; label: string }> = {
  quitado: { cls: 'green', label: 'Quitado' },
  em_dia: { cls: 'green', label: 'Em dia' },
  em_andamento: { cls: 'yellow', label: 'Em andamento' },
  so_sinal: { cls: 'yellow', label: 'Só sinal pago' },
  em_atraso: { cls: 'red', label: 'Em atraso' },
  cancelada: { cls: 'red', label: 'Cancelada' },
  reembolsado: { cls: 'gray', label: 'Reembolsado' },
  acompanha_titular: { cls: 'gray', label: 'Acompanha titular' },
};

// Listas de sugestão (datalist) para campos de texto livre — valores reais já usados.
export const SUGESTOES = {
  produto: ['Holding Masters', 'Aurum', 'Diamante', 'Holding - Holding Masters'],
  oferta: [],
  tipo_oferta: ['Renovação (data fixa)', 'Sócio', '1 ano', 'Renovação (1 ano)', 'Parcelamento HM (1 ano)', 'Assinatura recorrente', 'Base atual (pré-Hotmart)', 'Curta — 3 meses', 'Curta — 6 meses', 'Cortesia'],
  origem_acesso: ['Hotmart (THB)', 'Sócio/Convite', 'Hotmart (Assinatura)', 'Cadastro atual', 'Cortesia'],
  regra_acesso: ['31/12/2026', 'Compra + 365 dias', 'Acompanha titular', 'Adesão + 12 meses', 'Compra + 3 meses', 'Compra + 6 meses', 'Confiar na base atual', 'Sem expiração'],
  tempo_acesso: ['Até 31/12/2026', '1 ano', 'Acompanha titular', '12 meses (assinatura)', '3 meses', '6 meses', 'Ver base atual', 'Sem prazo'],
  instrucao: ['THB', 'THB - SÓCIO', 'AURUM', 'AURUM - SÓCIO', 'DIAMANTE', 'DIAMANTE - SÓCIO', 'PLATINA', 'PLATINA - SÓCIO', 'DIAMANTE VERMELHO', 'DIAMANTE VERMELHO - SÓCIO'],
  status_acesso_central: ['Ativo', 'Vencido', 'A vencer', 'Acompanha titular', 'Verificar', 'Ativo (cortesia)'],
  status_pagamento: ['Quitado', 'Em atraso (cobrar)', 'Em atraso', 'Reembolsado', 'Quitado (plano concluído)', 'Em dia (ativa)', 'Só sinal pago', 'Em andamento', 'Cancelada pelo cliente'],
} as const;

// Rank de nível (mais alto primeiro). Porta de NRANK.
export const NRANK: Record<string, number> = {
  diamante_vermelho: 7,
  diamante: 6,
  platina: 5,
  ouro: 4,
  profissional: 3,
  em_formacao: 2,
  pessoal: 1,
  iniciante: 0,
};
// Rank de situação. Porta de SRANK.
export const SRANK: Record<string, number> = { vencido: 3, a_vencer: 2, em_dia: 1, acompanha_titular: 0 };

export function searchHaystack(a: Aluno360): string {
  const parts = [
    a.nome,
    a.email,
    a.profissao,
    a.documento,
    (a.nivel_resultado || '').replace(/_/g, ' '),
    a.cidade,
    a.estado,
    a.turma_codigo,
    a.turma_aurum_codigo,
    ESPACO_LABEL[a.espaco_instrucao || ''],
  ];
  if (a.turma_aurum_id != null) parts.push('aurum mentoria');
  if (a.tem_ht) parts.push('ht holding total');
  if (a.tem_hm) parts.push('hm holding masters');
  if (a.tem_placa) parts.push('placa');
  if (a.tem_depoimento) parts.push('depoimento');
  if (a.sip_registrado) parts.push('sip time holding brasil');
  if (!a.nivel_resultado) parts.push('sem nivel sem nível');
  return parts.filter(Boolean).join(' ').toLowerCase();
}
