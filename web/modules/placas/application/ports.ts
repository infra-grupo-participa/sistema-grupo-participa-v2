import type { Solicitacao, Auditoria, HorarioSlot, AgendamentoLog } from '../domain/types';

// Ports (contratos) do módulo Placas. Implementados por adapters Supabase em infrastructure.
// Casos de uso dependem destas interfaces, nunca de Supabase diretamente.

export interface SolicitacaoRepository {
  getByToken(token: string): Promise<Solicitacao | null>;
  getById(id: string): Promise<Solicitacao | null>;
  listAll(): Promise<Solicitacao[]>;
  /** Solicitações que ocupam um slot (mesma data+hora de entrevista). */
  findByEntrevistaSlot(data: string, hora: string): Promise<Solicitacao[]>;
  /** Solicitações com hold ativo OU entrevista numa data (para checagem de conflito). */
  findHoldOrInterviewOnDate(data: string): Promise<Solicitacao[]>;
  update(id: string, patch: Partial<Solicitacao>): Promise<Solicitacao>;
  updateByToken(token: string, patch: Partial<Solicitacao>): Promise<Solicitacao>;
}

export interface AuditoriaRepository {
  getByAlunoId(alunoId: string): Promise<Auditoria | null>;
  upsertByAlunoId(data: Partial<Auditoria> & { aluno_id: string }): Promise<void>;
}

export interface HorariosRepository {
  /** Slots ativos a partir de uma data (calendário público). */
  listActiveFrom(dateIso: string): Promise<HorarioSlot[]>;
  findActive(slotData: string, hora: string): Promise<HorarioSlot | null>;
  /** CRUD admin */
  listAll(): Promise<HorarioSlot[]>;
  create(slotData: string, hora: string): Promise<HorarioSlot>;
  setAtivo(id: number, ativo: boolean): Promise<void>;
  delete(id: number): Promise<void>;
  deleteBySlot(slotData: string, hora: string): Promise<void>;
}

export interface AgendamentoLogRepository {
  log(entry: Omit<AgendamentoLog, 'id' | 'criado_em'>): Promise<void>;
}

/** Bootstrap de aluno a partir de uma solicitação (cruza com o módulo alunos). */
export interface AlunoBootstrapPort {
  findByEmail(email: string): Promise<{ id: string } & Record<string, unknown> | null>;
  create(data: Record<string, unknown>): Promise<{ id: string }>;
  update(id: string, patch: Record<string, unknown>): Promise<void>;
}

/** Envio de e-mails transacionais do fluxo de placas. */
export interface PlacaMailer {
  sendStatus(
    sol: Pick<Solicitacao, 'nome' | 'email' | 'token' | 'status' | 'codigo_rastreio' | 'entrevista_data' | 'entrevista_hora'>,
    tipo: 'docs_aprovados' | 'entrevista_finalizada' | 'placa_em_caminho' | 'nivel_registrado',
    extra?: Record<string, string>,
  ): Promise<void>;
}

/** Criação de sala de reunião (Zoom/Meet). */
export interface MeetingProvider {
  createMeeting(input: {
    topic: string;
    startIso: string;
    durationMin: number;
  }): Promise<{ joinUrl: string } | null>;
}

/** Consulta de CEP (ViaCEP). */
export interface CepLookup {
  buscar(cep: string): Promise<{
    cep: string;
    logradouro: string;
    bairro: string;
    cidade: string;
    estado_uf: string;
  } | null>;
}
