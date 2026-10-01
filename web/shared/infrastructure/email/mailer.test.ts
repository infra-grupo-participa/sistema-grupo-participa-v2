import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/shared/infrastructure/observability/system-events', () => ({
  logSystemEvent: vi.fn(async () => {}),
  snippet: (v: unknown) => String(v),
}));

import { logSystemEvent } from '@/shared/infrastructure/observability/system-events';
import { sendMail, sendMailDetalhado } from './mailer';

const msg = { to: 'a@b.com', subject: 's', html: '<p>x</p>' };
const res = (status: number, body: unknown) => new Response(JSON.stringify(body), { status });

beforeEach(() => {
  vi.useFakeTimers();
  process.env.RESEND_API_KEY = 'k';
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  delete process.env.RESEND_API_KEY;
});

describe('sendMailDetalhado', () => {
  it('sem chave: ok=false com erro', async () => {
    delete process.env.RESEND_API_KEY;
    expect(await sendMailDetalhado(msg)).toEqual({ ok: false, erro: 'RESEND_API_KEY ausente' });
  });

  it('sucesso devolve id', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(res(200, { id: 'e1' })));
    expect(await sendMailDetalhado(msg)).toEqual({ ok: true, id: 'e1' });
  });

  it('429 espera ~1s e tenta 1 vez de novo', async () => {
    const f = vi.fn().mockResolvedValueOnce(res(429, {})).mockResolvedValueOnce(res(200, { id: 'e2' }));
    vi.stubGlobal('fetch', f);
    const p = sendMailDetalhado(msg);
    await vi.advanceTimersByTimeAsync(1000);
    expect(await p).toEqual({ ok: true, id: 'e2' });
    expect(f).toHaveBeenCalledTimes(2);
  });

  it('429 duas vezes: desiste após 2 chamadas', async () => {
    const f = vi.fn().mockImplementation(async () => res(429, {}));
    vi.stubGlobal('fetch', f);
    const p = sendMailDetalhado(msg);
    await vi.advanceTimersByTimeAsync(1000);
    const r = await p;
    expect(r.ok).toBe(false);
    expect(r.erro).toContain('HTTP 429');
    expect(f).toHaveBeenCalledTimes(2);
  });

  it('evento de falha grava só o domínio do destinatário, sem o endereço', async () => {
    vi.mocked(logSystemEvent).mockClear();
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(res(422, { message: 'invalid to a@b.com' })));
    expect((await sendMailDetalhado(msg)).ok).toBe(false);
    expect(logSystemEvent).toHaveBeenCalled();
    const log = JSON.stringify(vi.mocked(logSystemEvent).mock.calls);
    expect(log).toContain('"para_dominio":"b.com"');
    expect(log).not.toContain('a@b.com');
  });

  it('sendMail continua boolean', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(res(500, {})));
    expect(await sendMail(msg)).toBe(false);
  });
});
