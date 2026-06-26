import type { NextRequest } from 'next/server';
import { bootstrapPublic, clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { isDateIso, isTimeHm } from '@/shared/infrastructure/http/validation';
import { resolvePlacaToken } from '@/shared/infrastructure/http/session-cookie';
import { withSlotLock } from '@/shared/infrastructure/http/slot-lock';
import { SupabaseAgenda } from '@/modules/placas/infrastructure/supabase-agenda';
import {
  buildSlotStart,
  conflictsForSlot,
  holdUntil,
  resolveAuditStep,
  SCHEDULE_MIN_LEAD_MS,
} from '@/modules/placas/domain/agendamento';

// Porta de app/api/hold-horario.php — reserva temporária (10min) do slot.
export async function POST(request: NextRequest) {
  const boot = bootstrapPublic(request, ['POST']);
  if (!boot.ok) return boot.response;

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  if (!body) return jsonError('Não foi possível concluir a operação.', 400);

  const token = resolvePlacaToken(request, body);
  const data = String(body.data ?? '').trim();
  const hora = String(body.hora ?? '').trim();
  if (!token || !data || !hora) return jsonError('Campos obrigatórios ausentes.', 400);
  if (!isDateIso(data) || !isTimeHm(hora)) return jsonError('Não foi possível concluir a operação.', 400);

  const now = new Date();
  const start = buildSlotStart(data, hora);
  if (!start) return jsonError('Não foi possível concluir a operação.', 400);
  if (start.getTime() <= now.getTime() + SCHEDULE_MIN_LEAD_MS) {
    return jsonError('O horário precisa estar a pelo menos 2 horas de distância.', 400);
  }
  const max = new Date(now);
  max.setMonth(max.getMonth() + 3);
  if (start > max) return jsonError('O horário precisa estar dentro da janela de 3 meses.', 400);

  sweepRateLimit();
  if (!rateLimitOk(`${clientIp(request)}|${token}`, 'gp_hold_rate_', 30, 300)) {
    return jsonError('Tente novamente em instantes.', 429);
  }

  const slotHour = hora.slice(0, 5);
  const agenda = new SupabaseAgenda();

  const result = await withSlotLock(`${data} ${slotHour}`, async () => {
    const sol = await agenda.loadByToken(token);
    if (!sol) return jsonError('Não foi possível localizar a solicitação.', 404);
    if (!['em_auditoria', 'docs_aprovados'].includes(String(sol.status ?? ''))) {
      return jsonError('O agendamento não está disponível para o estado atual do processo.', 409);
    }
    if (resolveAuditStep(sol) >= 3) {
      return jsonError('A entrevista já foi concluída e não pode mais ser reagendada.', 409);
    }
    if (!(await agenda.slotIsActive(data, slotHour))) {
      return jsonError('Este horário não está mais disponível na grade ativa. Escolha outro horário.', 409);
    }

    const busy = await agenda.loadBusyRows(data);
    for (const row of busy) {
      if (conflictsForSlot(row, token, data, slotHour, now)) {
        await agenda.log({
          solicitacao_id: sol.id ?? null,
          aluno_id: sol.aluno_id ?? null,
          token,
          origem: 'hold-horario',
          evento: 'hold_conflict',
          status: 'warning',
          detalhe: 'Horário em uso por outro candidato.',
          slot_data: data,
          slot_hora: slotHour,
          payload: { conflict_id: row.id ?? null },
        });
        return jsonError('Este horário acabou de ficar indisponível. Escolha outro horário.', 409);
      }
    }

    const until = holdUntil(now).toISOString();
    await agenda.setHold(String(sol.id), data, slotHour, until);
    await agenda.log({
      solicitacao_id: sol.id ?? null,
      aluno_id: sol.aluno_id ?? null,
      token,
      origem: 'hold-horario',
      evento: 'hold_acquired',
      status: 'success',
      detalhe: 'Slot reservado temporariamente para confirmação.',
      slot_data: data,
      slot_hora: slotHour,
      payload: { hold_until: until },
    });
    return jsonOk({ ok: true, slot_data: data, slot_hora: slotHour, hold_until: until, hold_persisted: true });
  });

  if (result === null) {
    return jsonError('Este horário está sendo reservado por outro candidato neste momento. Tente novamente em alguns segundos.', 409);
  }
  return result;
}
