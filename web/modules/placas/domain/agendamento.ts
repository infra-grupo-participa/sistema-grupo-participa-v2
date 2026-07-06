// Domínio puro — AGENDAMENTO de entrevista.
// Porta fiel de confirm-horario.php / hold-horario.php / agendar-entrevista.
// Todas as funções recebem `now` injetado (testável, sem Date.now() implícito).

import { AUDIT_STEP_INDEX } from './auditoria';

// Lead mínimo para um slot ser ofertado/confirmável: 2h no futuro.
export const SCHEDULE_MIN_LEAD_MS = 2 * 60 * 60 * 1000;
// Reserva temporária do slot enquanto o candidato confirma: 10 minutos.
export const HOLD_DURATION_MS = 10 * 60 * 1000;
// Reagendamento bloqueado se a entrevista atual está a menos de 24h.
export const RESCHEDULE_MIN_LEAD_MS = 24 * 60 * 60 * 1000;
// auditStep a partir do qual a entrevista é considerada finalizada (bloqueia reagendar).
export const ENTREVISTA_FINALIZADA_STEP = AUDIT_STEP_INDEX.ENTREVISTA_FINALIZADA; // 3

export interface AgendamentoRow {
  token?: string | null;
  status?: string | null;
  step_index?: number | null;
  auditoria_step?: number | null;
  entrevista_data?: string | null;
  entrevista_hora?: string | null;
  agendamento_hold_data?: string | null;
  agendamento_hold_hora?: string | null;
  agendamento_hold_until?: string | null;
}

/** max(step_index, auditoria_step). Porta de resolve_audit_step(). */
export function resolveAuditStep(row: AgendamentoRow): number {
  const stepIndex = row?.step_index != null ? Number(row.step_index) : -1;
  const auditStep = row?.auditoria_step != null ? Number(row.auditoria_step) : -1;
  return Math.max(stepIndex, auditStep);
}

/**
 * Monta o instante de início da entrevista a partir de date (YYYY-MM-DD) + hora (HH:MM).
 * Ancorado em America/Sao_Paulo (UTC−3 fixo; Brasil sem horário de verão desde 2019),
 * igual ao legado — independe do fuso do servidor.
 */
export function buildSlotStart(date?: string | null, time?: string | null): Date | null {
  const d = String(date || '').slice(0, 10);
  const t = String(time || '').slice(0, 5);
  if (!d || !t) return null;
  const start = new Date(`${d}T${t}:00-03:00`);
  return Number.isNaN(start.getTime()) ? null : start;
}

/**
 * Carimbo "dd/mm/aaaa HH:MM" do horário da entrevista, para gravar em thb_placas_auditoria.dates.
 * Mantém a MESMA representação que o restante do histórico de auditoria usa (avancarEtapa/nowBr),
 * tornando o agendamento durável na auditoria — recuperável mesmo se entrevista_data for limpo depois.
 */
export function stampBrDateTime(data: string, hora: string): string {
  const d = String(data || '').slice(0, 10);
  const t = String(hora || '').slice(0, 5);
  return `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)} ${t}`;
}

export type RescheduleBlock =
  | 'status_invalido' // status diferente de docs_aprovados (agendar exige documentação aprovada)
  | 'entrevista_finalizada' // auditStep >= 3
  | 'entrevista_passada' // entrevista existente já ocorreu
  | 'janela_24h'; // entrevista existente a menos de 24h

/**
 * Pode (re)agendar a entrevista? Retorna null se permitido, ou o motivo do bloqueio.
 * Exige status docs_aprovados: aceitar em_auditoria deixava o candidato agendar com a
 * documentação ainda em análise, pulando o gate manual do admin (auditoria saltava 0→2).
 */
export function rescheduleBlockReason(row: AgendamentoRow, now: Date): RescheduleBlock | null {
  const status = String(row?.status || '').trim();
  if (status !== 'docs_aprovados') return 'status_invalido';
  if (resolveAuditStep(row) >= ENTREVISTA_FINALIZADA_STEP) return 'entrevista_finalizada';

  const existingStart = buildSlotStart(row?.entrevista_data, row?.entrevista_hora);
  if (existingStart) {
    if (existingStart <= now) return 'entrevista_passada';
    const diff = existingStart.getTime() - now.getTime();
    if (diff > 0 && diff < RESCHEDULE_MIN_LEAD_MS) return 'janela_24h';
  }
  return null;
}

export const canReschedule = (row: AgendamentoRow, now: Date) => rescheduleBlockReason(row, now) === null;

/**
 * Outra solicitação ocupa ativamente este slot? Porta de slot_is_active_conflict().
 * Conflita se: token diferente, status não-terminal, auditStep < 3 e entrevista no futuro.
 */
export function isActiveSlotConflict(row: AgendamentoRow, currentToken: string, now: Date): boolean {
  const rowToken = String(row?.token || '').trim();
  if (rowToken === '' || rowToken === currentToken) return false;
  if (['concluido', 'rejeitado'].includes(String(row?.status || '').trim())) return false;
  if (resolveAuditStep(row) >= ENTREVISTA_FINALIZADA_STEP) return false;
  const start = buildSlotStart(row?.entrevista_data, row?.entrevista_hora);
  if (!start) return false;
  return start > now; // só conflita se a entrevista ainda não passou
}

/** Hold (reserva temporária) de outra solicitação ainda válido? */
export function isHoldActive(row: AgendamentoRow, currentToken: string, now: Date): boolean {
  const rowToken = String(row?.token || '').trim();
  if (rowToken !== '' && rowToken === currentToken) return false;
  const until = row?.agendamento_hold_until ? new Date(row.agendamento_hold_until) : null;
  if (!until || Number.isNaN(until.getTime())) return false;
  return until > now;
}

/** Instante em que um novo hold expira. */
export function holdUntil(now: Date): Date {
  return new Date(now.getTime() + HOLD_DURATION_MS);
}

/**
 * A linha conflita com um slot ESPECÍFICO (date+hour)? Porta de hold_schedule_slot_conflict.
 * Conflita se (token diferente, não-terminal, auditStep<3) E
 *   - tem entrevista confirmada exatamente nesse slot, ainda futura; OU
 *   - tem hold ativo (não expirado) exatamente nesse slot.
 */
export function conflictsForSlot(
  row: AgendamentoRow,
  currentToken: string,
  date: string,
  hour: string,
  now: Date,
): boolean {
  const rowToken = String(row?.token || '').trim();
  if (rowToken !== '' && rowToken === currentToken) return false;
  if (['concluido', 'rejeitado'].includes(String(row?.status || '').trim())) return false;
  if (resolveAuditStep(row) >= ENTREVISTA_FINALIZADA_STEP) return false;

  const h = hour.slice(0, 5);
  const confDate = String(row?.entrevista_data || '').slice(0, 10);
  const confHour = String(row?.entrevista_hora || '').slice(0, 5);
  if (confDate === date && confHour === h) {
    const start = buildSlotStart(confDate, confHour);
    if (start && start > now) return true;
  }

  const holdDate = String(row?.agendamento_hold_data || '').slice(0, 10);
  const holdHour = String(row?.agendamento_hold_hora || '').slice(0, 5);
  if (holdDate === date && holdHour === h && row?.agendamento_hold_until) {
    const until = new Date(row.agendamento_hold_until);
    if (!Number.isNaN(until.getTime()) && until > now) return true;
  }
  return false;
}

/**
 * Link "Adicionar ao Google Agenda" da entrevista (1h de duração).
 * Datas em wall-time de America/Sao_Paulo + `ctz`: sem o ctz o Google interpretava a hora
 * no fuso do dispositivo, e o cálculo manual de fim estourava em slots 23:xx.
 */
export function buildGcalLink(nome: string, data: string, hora: string, zoomLink?: string | null): string {
  const start = buildSlotStart(data, hora);
  const fmtSp = (d: Date) => new Date(d.getTime() - 3 * 3600 * 1000).toISOString().slice(0, 19).replace(/[-:]/g, '');
  const startStr = start ? fmtSp(start) : `${data.replace(/-/g, '')}T${hora.replace(':', '')}00`;
  const endStr = start ? fmtSp(new Date(start.getTime() + 60 * 60 * 1000)) : startStr;
  const details = zoomLink
    ? `Entrevista - Time Holding Brasil.\n\nLink Zoom:\n${zoomLink}`
    : 'Entrevista - Time Holding Brasil.\n\nO link da reunião será enviado em breve.';
  let url =
    'https://calendar.google.com/calendar/render?action=TEMPLATE' +
    `&text=${encodeURIComponent(`Entrevista ${nome || 'Candidato'} - Time Holding Brasil`)}` +
    `&dates=${startStr}/${endStr}` +
    '&ctz=America/Sao_Paulo' +
    `&details=${encodeURIComponent(details)}`;
  if (zoomLink) url += `&location=${encodeURIComponent(zoomLink)}`;
  return url;
}

/**
 * Slot é selecionável/ofertável? Lead mínimo de 2h e no máximo 3 meses à frente.
 * Porta de hold-horario.php (`> +2 hours`, `<= +3 months`) e do filtro do calendário.
 */
export function isSlotSelectable(slotStart: Date, now: Date): boolean {
  if (Number.isNaN(slotStart.getTime())) return false;
  if (slotStart.getTime() <= now.getTime() + SCHEDULE_MIN_LEAD_MS) return false;
  const maxAhead = new Date(now);
  maxAhead.setMonth(maxAhead.getMonth() + 3);
  return slotStart <= maxAhead;
}
