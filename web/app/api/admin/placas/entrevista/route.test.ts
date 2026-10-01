import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

const ID = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
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

vi.mock('@/shared/composition/server-container', () => ({ getCurrentUser: async () => ({ id: 'u1' }) }));
vi.mock('@/shared/domain/auth', () => ({ ehAdminOuAcima: () => true, podeEditar: () => true }));
vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({
  createAdminSupabase: () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({
            data: { id: ID, aluno_id: null, token: TOKEN, nome: 'Ana', email: 'ana@x.com', status: 'docs_aprovados' },
          }),
        }),
      }),
    }),
  }),
}));
vi.mock('@/modules/placas/infrastructure/supabase-agenda', () => ({
  SupabaseAgenda: class {
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
vi.mock('@/shared/infrastructure/observability/system-events', () => ({
  logSystemEvent: (...a: unknown[]) => logSystemEvent(...a),
}));

const { POST } = await import('./route');

const req = (body: Record<string, unknown>) =>
  new NextRequest('https://grupoparticipa.app.br/api/admin/placas/entrevista', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ id: ID, data: '2099-01-10', hora: '10:00', ...body }),
  });

beforeEach(() => {
  vi.clearAllMocks();
  afterCbs.length = 0;
  createMeeting.mockResolvedValue({ joinUrl: 'https://zoom.us/j/222', meetingId: '222' });
  deleteMeeting.mockResolvedValue(true);
  enviarEmailPlaca.mockResolvedValue({ ok: true, sent: true });
});

describe('POST /api/admin/placas/entrevista — sala Zoom e e-mail', () => {
  it('sucesso: grava zoom_meeting_id, e-mail via enviarEmailPlaca, sent=true', async () => {
    confirm.mockResolvedValue({ ok: true, conflict: false, previousMeetingId: null });
    const res = await POST(req({}));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, zoom_link: 'https://zoom.us/j/222', sent: true });
    expect(confirm.mock.calls[0][1]).toMatchObject({ zoom_meeting_id: '222' });
    expect(enviarEmailPlaca.mock.calls[0][0]).toMatchObject({ tipo: 'entrevista_agendada', to: 'ana@x.com', token: TOKEN });
    expect(deleteMeeting).not.toHaveBeenCalled();
  });

  it('reagendamento: apaga a sala anterior', async () => {
    confirm.mockResolvedValue({ ok: true, conflict: false, previousMeetingId: '777' });
    await POST(req({}));
    expect(deleteMeeting).not.toHaveBeenCalled();
    await rodarAfter();
    expect(deleteMeeting).toHaveBeenCalledWith('777');
  });

  it('conflito: 409 e apaga a sala recém-criada', async () => {
    confirm.mockResolvedValue({ ok: false, conflict: true, previousMeetingId: null });
    const res = await POST(req({}));
    expect(res.status).toBe(409);
    expect(deleteMeeting).not.toHaveBeenCalled();
    await rodarAfter();
    expect(deleteMeeting).toHaveBeenCalledWith('222');
    expect(enviarEmailPlaca).not.toHaveBeenCalled();
  });

  it('falha de gravação: 502 e apaga a sala recém-criada', async () => {
    confirm.mockResolvedValue({ ok: false, conflict: false, previousMeetingId: null });
    const res = await POST(req({}));
    expect(res.status).toBe(502);
    expect(deleteMeeting).not.toHaveBeenCalled();
    await rodarAfter();
    expect(deleteMeeting).toHaveBeenCalledWith('222');
  });

  it('enviar_email=false: não envia, sent=false; e-mail falhou também devolve sent=false', async () => {
    confirm.mockResolvedValue({ ok: true, conflict: false, previousMeetingId: null });
    const r1 = await POST(req({ enviar_email: false }));
    expect(await r1.json()).toMatchObject({ sent: false });
    expect(enviarEmailPlaca).not.toHaveBeenCalled();

    enviarEmailPlaca.mockResolvedValue({ ok: false, sent: false, erro: 'x' });
    const r2 = await POST(req({}));
    expect(await r2.json()).toMatchObject({ ok: true, sent: false });
  });

  it('resposta não espera o Zoom: deleteMeeting pendurado não segura o 409; só roda no after()', async () => {
    deleteMeeting.mockReturnValue(new Promise(() => {}));
    confirm.mockResolvedValue({ ok: false, conflict: true, previousMeetingId: null });
    const res = await POST(req({}));
    expect(res.status).toBe(409);
    expect(afterCbs).toHaveLength(1);
    expect(deleteMeeting).not.toHaveBeenCalled();
  });

  it('deleteMeeting falhou → evento de sala órfã com meeting_id e motivo', async () => {
    deleteMeeting.mockResolvedValue(false);
    confirm.mockResolvedValue({ ok: true, conflict: false, previousMeetingId: '555' });
    const res = await POST(req({}));
    expect(res.status).toBe(200);
    expect(logSystemEvent.mock.calls.some(([e]) => /órfã/.test(String(e?.titulo)))).toBe(false);
    await rodarAfter();
    const orfa = logSystemEvent.mock.calls.map(([e]) => e).find((e) => /órfã/.test(String(e?.titulo)));
    expect(orfa).toMatchObject({ tipo: 'error', fonte: 'agenda_admin', detalhe: { meeting_id: '555', motivo: 'reagendamento' } });
  });
});
