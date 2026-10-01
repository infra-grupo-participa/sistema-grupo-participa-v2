import { afterEach, describe, expect, it, vi } from 'vitest';
import { agendarEntrevistaManual } from './placas-admin-data';

afterEach(() => vi.unstubAllGlobals());

const sol = { id: 'x' } as unknown as Parameters<typeof agendarEntrevistaManual>[0];
const stub = (body: unknown) => vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, json: async () => body })));

describe('agendarEntrevistaManual -> sent', () => {
  it('enviarEmail && sent:false → avisa que o e-mail NÃO foi enviado', async () => {
    stub({ ok: true, sent: false });
    const r = await agendarEntrevistaManual(sol, '2026-10-05', '10:00', true);
    expect(r).toEqual({ ok: true, msg: 'Entrevista agendada. O e-mail ao aluno NÃO foi enviado.' });
  });
  it('enviarEmail && sent ausente → também não confirmado', async () => {
    stub({ ok: true });
    expect((await agendarEntrevistaManual(sol, '2026-10-05', '10:00', true)).msg).toContain('NÃO foi enviado');
  });
  it('enviarEmail && sent:true → texto normal', async () => {
    stub({ ok: true, sent: true });
    expect((await agendarEntrevistaManual(sol, '2026-10-05', '10:00', true)).msg).toBe('Entrevista agendada!');
  });
  it('Zoom pendente E e-mail não enviado → os dois avisos aparecem', async () => {
    stub({ ok: true, sent: false, zoom_pending: true });
    const { msg } = await agendarEntrevistaManual(sol, '2026-10-05', '10:00', true);
    expect(msg).toContain('link Zoom pendente');
    expect(msg).toContain('NÃO foi enviado');
  });
  it('enviarEmail=false → texto atual, sem aviso', async () => {
    stub({ ok: true, sent: false });
    expect((await agendarEntrevistaManual(sol, '2026-10-05', '10:00', false)).msg).toBe('Entrevista agendada!');
  });
});
