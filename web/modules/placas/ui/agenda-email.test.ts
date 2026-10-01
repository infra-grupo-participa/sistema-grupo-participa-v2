import { describe, expect, it, vi, afterEach } from 'vitest';
import { EMAIL_CONFIRMADO_TEXTO, EMAIL_FALHOU_TITULO, emailConfirmado } from './agenda-email';
import { agendaConfirm } from './agenda-api';

afterEach(() => vi.unstubAllGlobals());

const stubFetch = (body: unknown, ok = true) =>
  vi.stubGlobal('fetch', vi.fn(async () => ({ ok, json: async () => body })));

describe('agendaConfirm -> prova de e-mail', () => {
  it('repassa email_enviado:true e a frase "caixa de entrada" é liberada', async () => {
    stubFetch({ ok: true, email_enviado: true });
    const r = await agendaConfirm('t', '2026-10-05', '10:00');
    expect(r.email_enviado).toBe(true);
    expect(emailConfirmado(r)).toBe(true);
    expect(EMAIL_CONFIRMADO_TEXTO).toMatch(/caixa de entrada/);
  });
  it('email_enviado:false → não confirmado; aviso existe e não contém "caixa de entrada"', async () => {
    stubFetch({ ok: true, email_enviado: false });
    const r = await agendaConfirm('t', '2026-10-05', '10:00');
    expect(emailConfirmado(r)).toBe(false);
    expect(EMAIL_FALHOU_TITULO).toMatch(/Não conseguimos enviar o e-mail/);
    expect(EMAIL_FALHOU_TITULO).not.toMatch(/caixa de entrada/);
  });
  it('resposta antiga (undefined) e null contam como não confirmado', async () => {
    stubFetch({ ok: true });
    expect(emailConfirmado(await agendaConfirm('t', '2026-10-05', '10:00'))).toBe(false);
    expect(emailConfirmado(null)).toBe(false);
  });
});
