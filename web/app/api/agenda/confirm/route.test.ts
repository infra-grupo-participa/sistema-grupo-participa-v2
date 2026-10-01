import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

const TOKEN = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const confirm = vi.fn();
const createMeeting = vi.fn();
const deleteMeeting = vi.fn();
const enviarEmailPlaca = vi.fn();
const afterCbs: Array<() => unknown> = [];
const logSystemEvent = vi.fn();
vi.mock('next/server', async (orig) => ({
  ...(await orig<typeof import('next/server')>()),
  after: (cb: () => unknown) => {
    afterCbs.push(cb);
  },
}));
/** Executa o que a rota agendou com after() — simula o "depois da resposta". */
const rodarAfter = async () => {
  for (const cb of afterCbs.splice(0)) await cb();
};
const logFunilPlacaAgendado = vi.fn();
const sendMail = vi.fn();

vi.mock('@/modules/placas/infrastructure/supabase-agenda', () => ({
  SupabaseAgenda: class {
    async loadByToken() {
      return { id: 'sol-1', aluno_id: null, token: TOKEN, nome: 'Ana', email: 'ana@x.com', status: 'docs_aprovados' };
    }
    async slotIsActive() {
      return true;
    }
    async loadBusyRows() {
      return [];
    }
    confirm(...a: unknown[]) {
      return confirm(...a);
    }
    async syncAuditoriaStep() {}
  },
}));
vi.mock('@/modules/placas/infrastructure/zoom-meeting', () => ({
  ZoomMeetingProvider: class {
    createMeeting(...a: unknown[]) {
      return createMeeting(...a);
    }
    deleteMeeting(...a: unknown[]) {
      return deleteMeeting(...a);
    }
  },
}));
vi.mock('@/modules/placas/application/enviar-email-placa', () => ({
  enviarEmailPlaca: (...a: unknown[]) => enviarEmailPlaca(...a),
}));
vi.mock('@/modules/placas/infrastructure/supabase-public-placa', () => ({
  logFunilPlacaAgendado: (...a: unknown[]) => logFunilPlacaAgendado(...a),
}));
vi.mock('@/shared/infrastructure/email/mailer', () => ({ sendMail: (...a: unknown[]) => sendMail(...a) }));
vi.mock('@/shared/infrastructure/observability/system-events', () => ({
  logSystemEvent: (...a: unknown[]) => logSystemEvent(...a),
}));
vi.mock('@/modules/placas/domain/agendamento', async (orig) => ({
  ...(await orig<typeof import('@/modules/placas/domain/agendamento')>()),
  rescheduleBlockReason: () => null,
  conflictsForSlot: () => false,
}));

const { POST } = await import('./route');

let ip = 0;
const DATA = '2099-01-10';
function req(hora: string): NextRequest {
  return new NextRequest('https://grupoparticipa.app.br/api/agenda/confirm', {
    method: 'POST',
    headers: { origin: 'https://grupoparticipa.app.br', 'x-real-ip': `10.1.0.${++ip}`, 'content-type': 'application/json' },
    body: JSON.stringify({ token: TOKEN, data: DATA, hora }),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  afterCbs.length = 0;
  createMeeting.mockResolvedValue({ joinUrl: 'https://zoom.us/j/111', meetingId: '111' });
  deleteMeeting.mockResolvedValue(true);
  enviarEmailPlaca.mockResolvedValue({ ok: true, sent: true });
  sendMail.mockResolvedValue(true);
});

describe('POST /api/agenda/confirm — ciclo de vida da sala Zoom', () => {
  it('sucesso: grava zoom_meeting_id, não apaga nada, funil agendado, email_enviado=true', async () => {
    confirm.mockResolvedValue({ ok: true, conflict: false, previousMeetingId: null });
    const res = await POST(req('10:00'));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, zoom_link: 'https://zoom.us/j/111', email_enviado: true });
    expect(confirm.mock.calls[0][1]).toMatchObject({ zoom_meeting_id: '111', entrevista_link: 'https://zoom.us/j/111' });
    await rodarAfter();
    expect(deleteMeeting).not.toHaveBeenCalled();
    expect(logFunilPlacaAgendado).toHaveBeenCalledTimes(1);
    expect(enviarEmailPlaca.mock.calls[0][0]).toMatchObject({ tipo: 'entrevista_agendada', to: 'ana@x.com', token: TOKEN });
  });

  it('reagendamento: apaga a sala anterior (previousMeetingId)', async () => {
    confirm.mockResolvedValue({ ok: true, conflict: false, previousMeetingId: '999' });
    const res = await POST(req('11:00'));
    expect(res.status).toBe(200);
    expect(deleteMeeting).not.toHaveBeenCalled();
    await rodarAfter();
    expect(deleteMeeting).toHaveBeenCalledWith('999');
    expect(deleteMeeting).toHaveBeenCalledTimes(1);
  });

  it('conflito 23505 depois de criar a sala: 409 e apaga a sala recém-criada', async () => {
    confirm.mockResolvedValue({ ok: false, conflict: true, previousMeetingId: null });
    const res = await POST(req('12:00'));
    expect(res.status).toBe(409);
    expect(deleteMeeting).not.toHaveBeenCalled();
    await rodarAfter();
    expect(deleteMeeting).toHaveBeenCalledWith('111');
    expect(logFunilPlacaAgendado).not.toHaveBeenCalled();
    expect(enviarEmailPlaca).not.toHaveBeenCalled();
  });

  it('falha de gravação: 502 e apaga a sala recém-criada', async () => {
    confirm.mockResolvedValue({ ok: false, conflict: false, previousMeetingId: null });
    const res = await POST(req('13:00'));
    expect(res.status).toBe(502);
    expect(deleteMeeting).not.toHaveBeenCalled();
    await rodarAfter();
    expect(deleteMeeting).toHaveBeenCalledWith('111');
  });

  it('Zoom não criou sala: grava sem id, nada a apagar; e-mail falhou → email_enviado=false', async () => {
    createMeeting.mockResolvedValue(null);
    enviarEmailPlaca.mockResolvedValue({ ok: false, sent: false, erro: 'x' });
    confirm.mockResolvedValue({ ok: false, conflict: false, previousMeetingId: null });
    const r1 = await POST(req('14:00'));
    expect(r1.status).toBe(502);
    expect(deleteMeeting).not.toHaveBeenCalled();

    confirm.mockResolvedValue({ ok: true, conflict: false, previousMeetingId: null });
    const r2 = await POST(req('15:00'));
    expect(await r2.json()).toMatchObject({ ok: true, zoom_pending: true, email_enviado: false });
    expect(confirm.mock.calls[1][1]).toMatchObject({ zoom_meeting_id: null });
  });

  it('resposta não espera o Zoom: deleteMeeting pendurado não segura o 409; só roda no after()', async () => {
    deleteMeeting.mockReturnValue(new Promise(() => {}));
    confirm.mockResolvedValue({ ok: false, conflict: true, previousMeetingId: null });
    const res = await POST(req('16:00'));
    expect(res.status).toBe(409);
    expect(afterCbs).toHaveLength(1);
    expect(deleteMeeting).not.toHaveBeenCalled();
  });

  it('deleteMeeting falhou → evento de sala órfã com meeting_id e motivo', async () => {
    deleteMeeting.mockResolvedValue(false);
    confirm.mockResolvedValue({ ok: true, conflict: false, previousMeetingId: '555' });
    const res = await POST(req('16:00'));
    expect(res.status).toBe(200);
    expect(logSystemEvent.mock.calls.some(([e]) => /órfã/.test(String(e?.titulo)))).toBe(false);
    await rodarAfter();
    const orfa = logSystemEvent.mock.calls.map(([e]) => e).find((e) => /órfã/.test(String(e?.titulo)));
    expect(orfa).toMatchObject({ tipo: 'error', fonte: 'agenda_confirm', detalhe: { meeting_id: '555', motivo: 'reagendamento' } });
  });
});
