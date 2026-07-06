// Entidades de persistência do módulo Placas — formas exatas das tabelas Supabase
// (introspecção real do projeto mbvybujpkwuorhtdzcde).

/** thb_placas_solicitacoes — uma linha por aluno, identificada por token UUID. */
export interface Solicitacao {
  id: string;
  token: string;
  aluno_id: string | null;

  // Dados pessoais informados pelo aluno
  nome: string | null;
  email: string | null;
  telefone: string | null;
  turma: string | null;
  profissao: string | null;
  telefone_profissional: string | null;

  // Presença online
  youtube_url: string | null;
  site_profissional: string | null;
  instagram_url: string | null;
  facebook_url: string | null;

  // Questionário / nível
  interesse: string | null;
  espaco_instrucao: string | null;
  nivel: string | null;
  faturamento_declarado: number | null; // bigint

  // Documentos (Supabase Storage bucket "documentos")
  proof_url: string | null;
  declaracao_url: string | null;

  // Endereço de entrega
  cep: string | null;
  logradouro: string | null;
  numero: string | null;
  complemento: string | null;
  bairro: string | null;
  cidade: string | null;
  estado_uf: string | null;
  pais: string | null; // default 'Brasil'

  // NF / entrega
  documento_nf: string | null;
  email_entrega: string | null;

  // Entrevista agendada
  entrevista_data: string | null; // YYYY-MM-DD
  entrevista_hora: string | null; // HH:MM[:SS]
  entrevista_link: string | null;
  meet_link: string | null;
  codigo_rastreio: string | null;

  // Progresso / estado
  step_index: number; // form 0-9 (rascunho) ou audit 0-6 (após submissão)
  auditoria_step: number; // -1 = não iniciada; 0-6 = escala de auditoria
  status: string;

  // Ciclos (feature "refazer processo — subiu de nível")
  ciclo: number; // 1 = primeiro processo; incrementa a cada refazer
  nivel_anterior: string | null; // piso de bloqueio de nível no ciclo atual (null fora de um refazer)

  // Regularização / fila do admin
  motivo_retorno: string | null;
  regularizacao_pendente: boolean | null;
  admin_seen_at: string | null;
  admin_attention_at: string | null;
  /** Matching com a central (thb_alunos): 'email' | 'documento' | 'nenhum' (possível ex-aluno) | null (não verificado). */
  central_match: string | null;

  // Hold de concorrência (agendamento)
  agendamento_hold_data: string | null;
  agendamento_hold_hora: string | null;
  agendamento_hold_until: string | null;

  reminder_sent_at: string | null;

  created_at: string;
  updated_at: string;
}

/** thb_placas_auditoria — estado/histórico da auditoria por aluno (UNIQUE aluno_id). */
export interface Auditoria {
  id: string;
  aluno_id: string | null;
  step_index: number;
  encerrado: boolean;
  dates: Record<string, string>; // { [stepKey]: 'DD/MM/YYYY HH:MM' }
  obs: string | null;
  faturamento: number | null; // bigint (comprovado)
  protocolo: string | null;
  criado_em: string | null;
  atualizado_em: string | null;
}

/** thb_placas_ciclos — snapshot imutável de cada ciclo concluído (arquivado ao refazer). */
export interface Ciclo {
  id: string;
  solicitacao_id: string | null;
  aluno_id: string | null;
  ciclo: number;
  nivel: string | null;
  faturamento_declarado: number | null; // bigint
  faturamento_comprovado: number | null; // bigint
  protocolo: string | null;
  codigo_rastreio: string | null;
  turma: string | null;
  espaco_instrucao: string | null;
  dates: Record<string, string>;
  endereco: Record<string, string | null> | null;
  concluido_em: string | null;
  created_at: string;
}

/** thb_horarios_disponiveis — slots por data (recorrência por slot_data). */
export interface HorarioSlot {
  id: number;
  slot_data: string; // YYYY-MM-DD
  hora: string; // HH:MM[:SS]
  ativo: boolean;
  criado_em: string;
}

/** thb_placas_agendamento_logs — trilha de eventos de agendamento. */
export interface AgendamentoLog {
  id: number;
  solicitacao_id: string | null;
  aluno_id: string | null;
  token: string | null;
  origem: string;
  evento: string;
  status: string;
  detalhe: string | null;
  slot_data: string | null;
  slot_hora: string | null;
  payload: Record<string, unknown>;
  criado_em: string;
}
