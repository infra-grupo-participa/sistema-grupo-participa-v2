import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const logSystemEvent = vi.hoisted(() => vi.fn(async (_ev: unknown) => {}));
vi.mock('@/shared/infrastructure/observability/system-events', () => ({
  logSystemEvent,
  snippet: (v: unknown) => String(v),
}));

import { ZoomMeetingProvider } from './zoom-meeting';

const resp = (status: number, body: unknown = {}) =>
  new Response(typeof body === 'string' ? body : JSON.stringify(body), { status });

const fetchMock = vi.fn();
const tokenOk = () => resp(200, { access_token: 'tok' });

beforeEach(() => {
  logSystemEvent.mockClear();
  fetchMock.mockReset();
  vi.stubGlobal('fetch', fetchMock);
  process.env.ZOOM_ACCOUNT_ID = 'acc';
  process.env.ZOOM_CLIENT_ID = 'cid';
  process.env.ZOOM_CLIENT_SECRET = 'sec';
});
afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.ZOOM_ACCOUNT_ID;
  delete process.env.ZOOM_CLIENT_ID;
  delete process.env.ZOOM_CLIENT_SECRET;
});

const input = { topic: 'Entrevista X', startIso: '2026-10-05T10:00:00', durationMin: 60 };

describe('createMeeting', () => {
  it('devolve joinUrl e meetingId (id numérico vira string)', async () => {
    fetchMock.mockResolvedValueOnce(tokenOk()).mockResolvedValueOnce(resp(201, { join_url: 'https://zoom.us/j/1', id: 89123456789 }));
    expect(await new ZoomMeetingProvider().createMeeting(input)).toEqual({ joinUrl: 'https://zoom.us/j/1', meetingId: '89123456789' });
  });

  it('cria em users/me sem ZOOM_HOST_USER', async () => {
    delete process.env.ZOOM_HOST_USER;
    fetchMock.mockResolvedValueOnce(tokenOk()).mockResolvedValueOnce(resp(201, { join_url: 'https://zoom.us/j/1', id: 1 }));
    await new ZoomMeetingProvider().createMeeting(input);
    expect(fetchMock.mock.calls[1][0]).toBe('https://api.zoom.us/v2/users/me/meetings');
  });

  it('com ZOOM_HOST_USER cria no anfitrião informado, com encode', async () => {
    process.env.ZOOM_HOST_USER = 'sala+1@grupo.com/x';
    try {
      fetchMock.mockResolvedValueOnce(tokenOk()).mockResolvedValueOnce(resp(201, { join_url: 'https://zoom.us/j/1', id: 1 }));
      await new ZoomMeetingProvider().createMeeting(input);
      expect(fetchMock.mock.calls[1][0]).toBe('https://api.zoom.us/v2/users/sala%2B1%40grupo.com%2Fx/meetings');
    } finally {
      delete process.env.ZOOM_HOST_USER;
    }
  });

  it('sem id na resposta: mantém o link, meetingId null e registra warn', async () => {
    fetchMock.mockResolvedValueOnce(tokenOk()).mockResolvedValueOnce(resp(201, { join_url: 'https://zoom.us/j/1' }));
    expect(await new ZoomMeetingProvider().createMeeting(input)).toEqual({ joinUrl: 'https://zoom.us/j/1', meetingId: null });
    expect(logSystemEvent).toHaveBeenCalledWith(expect.objectContaining({ tipo: 'warn' }));
  });

  it('env ausente: null sem chamar a rede', async () => {
    delete process.env.ZOOM_CLIENT_SECRET;
    expect(await new ZoomMeetingProvider().createMeeting(input)).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('deleteMeeting', () => {
  it('DELETE no endpoint certo com Bearer; 204 = true', async () => {
    fetchMock.mockResolvedValueOnce(tokenOk()).mockResolvedValueOnce(new Response(null, { status: 204 }));
    expect(await new ZoomMeetingProvider().deleteMeeting('89123456789')).toBe(true);
    const [url, init] = fetchMock.mock.calls[1];
    expect(url).toBe('https://api.zoom.us/v2/meetings/89123456789');
    expect(init.method).toBe('DELETE');
    expect(init.headers.Authorization).toBe('Bearer tok');
    expect(init.signal).toBeInstanceOf(AbortSignal);
    expect(logSystemEvent).not.toHaveBeenCalled();
  });

  it('404 (sala já não existe) conta como ok', async () => {
    fetchMock.mockResolvedValueOnce(tokenOk()).mockResolvedValueOnce(resp(404, { code: 3001 }));
    expect(await new ZoomMeetingProvider().deleteMeeting('123')).toBe(true);
  });

  it('HTTP 500: false + evento de erro', async () => {
    fetchMock.mockResolvedValueOnce(tokenOk()).mockResolvedValueOnce(resp(500, 'boom'));
    expect(await new ZoomMeetingProvider().deleteMeeting('123')).toBe(false);
    expect(logSystemEvent).toHaveBeenCalledWith(expect.objectContaining({ tipo: 'error', fonte: 'zoom' }));
  });

  it('falha no OAuth: false, não tenta o DELETE', async () => {
    fetchMock.mockResolvedValueOnce(resp(401, 'nope'));
    expect(await new ZoomMeetingProvider().deleteMeeting('123')).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('timeout/rede: nunca lança, devolve false', async () => {
    fetchMock.mockRejectedValueOnce(new DOMException('timeout', 'TimeoutError'));
    await expect(new ZoomMeetingProvider().deleteMeeting('123')).resolves.toBe(false);
    expect(logSystemEvent).toHaveBeenCalledWith(expect.objectContaining({ tipo: 'error' }));
  });

  it('id não numérico: false sem chamar a rede (evita path injection)', async () => {
    expect(await new ZoomMeetingProvider().deleteMeeting('../users/me')).toBe(false);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
