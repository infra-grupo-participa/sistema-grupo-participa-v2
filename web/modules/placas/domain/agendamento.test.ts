import { describe, it, expect } from 'vitest';
import {
  buildSlotStart,
  canReschedule,
  conflictsForSlot,
  isActiveSlotConflict,
  isHoldActive,
  isSlotSelectable,
  rescheduleBlockReason,
  resolveAuditStep,
} from './agendamento';

const NOW = new Date('2026-06-26T12:00:00.000Z');
const inHours = (h: number) => new Date(NOW.getTime() + h * 3600000);
// buildSlotStart ancora em America/Sao_Paulo — derivar componentes nesse fuso para que
// a string reconstrua exatamente o mesmo instante, independente do fuso do runner.
const SP = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Sao_Paulo',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});
const spParts = (d: Date) => Object.fromEntries(SP.formatToParts(d).map((p) => [p.type, p.value]));
const ymd = (d: Date) => {
  const p = spParts(d);
  return `${p.year}-${p.month}-${p.day}`;
};
const hm = (d: Date) => {
  const p = spParts(d);
  return `${p.hour}:${p.minute}`;
};

describe('agendamento — resolveAuditStep', () => {
  it('usa o maior entre step_index e auditoria_step', () => {
    expect(resolveAuditStep({ step_index: 1, auditoria_step: 3 })).toBe(3);
    expect(resolveAuditStep({ step_index: 4, auditoria_step: -1 })).toBe(4);
    expect(resolveAuditStep({})).toBe(-1);
  });
});

describe('agendamento — rescheduleBlockReason', () => {
  const base = { status: 'docs_aprovados', step_index: 1, auditoria_step: 1 };

  it('permite reagendar em status válido sem entrevista marcada', () => {
    expect(rescheduleBlockReason(base, NOW)).toBeNull();
    expect(canReschedule(base, NOW)).toBe(true);
  });

  it('bloqueia status fora de em_auditoria/docs_aprovados', () => {
    expect(rescheduleBlockReason({ ...base, status: 'concluido' }, NOW)).toBe('status_invalido');
    expect(rescheduleBlockReason({ ...base, status: 'rascunho' }, NOW)).toBe('status_invalido');
  });

  it('bloqueia quando entrevista finalizada (auditStep >= 3)', () => {
    expect(rescheduleBlockReason({ ...base, auditoria_step: 3 }, NOW)).toBe('entrevista_finalizada');
  });

  it('bloqueia entrevista no passado e dentro de 24h', () => {
    const past = inHours(-1);
    expect(
      rescheduleBlockReason({ ...base, entrevista_data: ymd(past), entrevista_hora: hm(past) }, NOW),
    ).toBe('entrevista_passada');
    const soon = inHours(10);
    expect(
      rescheduleBlockReason({ ...base, entrevista_data: ymd(soon), entrevista_hora: hm(soon) }, NOW),
    ).toBe('janela_24h');
    const later = inHours(48);
    expect(
      rescheduleBlockReason({ ...base, entrevista_data: ymd(later), entrevista_hora: hm(later) }, NOW),
    ).toBeNull();
  });
});

describe('agendamento — conflitos e hold', () => {
  it('isActiveSlotConflict só com token diferente, não-terminal e futuro', () => {
    const fut = inHours(48);
    const row = {
      token: 'outro',
      status: 'em_auditoria',
      auditoria_step: 1,
      entrevista_data: ymd(fut),
      entrevista_hora: hm(fut),
    };
    expect(isActiveSlotConflict(row, 'meu', NOW)).toBe(true);
    expect(isActiveSlotConflict(row, 'outro', NOW)).toBe(false); // mesmo token
    expect(isActiveSlotConflict({ ...row, status: 'rejeitado' }, 'meu', NOW)).toBe(false);
    expect(isActiveSlotConflict({ ...row, auditoria_step: 3 }, 'meu', NOW)).toBe(false);
  });

  it('isHoldActive respeita expiração e token', () => {
    expect(isHoldActive({ token: 'x', agendamento_hold_until: inHours(0.1).toISOString() }, 'y', NOW)).toBe(true);
    expect(isHoldActive({ token: 'x', agendamento_hold_until: inHours(-0.1).toISOString() }, 'y', NOW)).toBe(false);
    expect(isHoldActive({ token: 'y', agendamento_hold_until: inHours(0.1).toISOString() }, 'y', NOW)).toBe(false);
  });

  it('isSlotSelectable exige lead de 2h e <= 3 meses', () => {
    expect(isSlotSelectable(inHours(1), NOW)).toBe(false); // dentro de 2h
    expect(isSlotSelectable(inHours(3), NOW)).toBe(true);
    const fourMonths = new Date(NOW);
    fourMonths.setMonth(fourMonths.getMonth() + 4);
    expect(isSlotSelectable(fourMonths, NOW)).toBe(false);
  });

  it('conflictsForSlot detecta entrevista e hold no mesmo slot', () => {
    const fut = inHours(48);
    const d = ymd(fut);
    const h = hm(fut);
    // entrevista confirmada de outro candidato nesse slot
    expect(conflictsForSlot({ token: 'outro', status: 'docs_aprovados', auditoria_step: 1, entrevista_data: d, entrevista_hora: h }, 'meu', d, h, NOW)).toBe(true);
    // mesmo token não conflita
    expect(conflictsForSlot({ token: 'meu', entrevista_data: d, entrevista_hora: h }, 'meu', d, h, NOW)).toBe(false);
    // hold ativo de outro nesse slot
    expect(conflictsForSlot({ token: 'outro', agendamento_hold_data: d, agendamento_hold_hora: h, agendamento_hold_until: inHours(0.1).toISOString() }, 'meu', d, h, NOW)).toBe(true);
    // hold expirado não conflita
    expect(conflictsForSlot({ token: 'outro', agendamento_hold_data: d, agendamento_hold_hora: h, agendamento_hold_until: inHours(-0.1).toISOString() }, 'meu', d, h, NOW)).toBe(false);
    // slot diferente
    expect(conflictsForSlot({ token: 'outro', entrevista_data: d, entrevista_hora: '23:59' }, 'meu', d, h, NOW)).toBe(false);
  });

  it('buildSlotStart parseia ou retorna null', () => {
    expect(buildSlotStart('2026-06-27', '14:30')?.getHours()).toBeTypeOf('number');
    expect(buildSlotStart('', '14:30')).toBeNull();
    expect(buildSlotStart('2026-06-27', '')).toBeNull();
  });
});
