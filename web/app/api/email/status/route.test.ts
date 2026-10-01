import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

const enviar = vi.fn();
vi.mock('@/modules/placas/application/enviar-email-placa', () => ({ enviarEmailPlaca: (a: unknown) => enviar(a) }));
vi.mock('@/shared/composition/server-container', () => ({ getCurrentUser: async () => ({ id: 'u1' }) }));
vi.mock('@/shared/domain/auth', () => ({ ehAdminOuAcima: () => true, podeEditar: () => true }));
vi.mock('@/shared/infrastructure/http/rate-limit', () => ({ rateLimitOk: () => true }));

process.env.NEXT_PUBLIC_APP_URL = 'https://grupoparticipa.app.br';
const { POST } = await import('./route');

const TOKEN = '11111111-2222-4333-8444-555555555555';
function req(body: Record<string, unknown>) {
  return new NextRequest('https://grupoparticipa.app.br/api/email/status', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'a@b.com', nome: 'Ana', token: TOKEN, ...body }),
  });
}
async function cta(token_link: string): Promise<string> {
  enviar.mockClear();
  await POST(req({ tipo: 'docs_aprovados', token_link }));
  return enviar.mock.calls[0][0].ctaLink;
}
const TRACK = `https://grupoparticipa.app.br/solicitar-placa?token=${TOKEN}`;

beforeEach(() => {
  enviar.mockReset();
  enviar.mockResolvedValue({ ok: true, sent: true, id: 'x' });
});

describe('POST /api/email/status', () => {
  it('responde ok e sent', async () => {
    const res = await POST(req({ tipo: 'solicitacao_recebida' }));
    expect(await res.json()).toEqual({ ok: true, sent: true });
    expect(enviar.mock.calls[0][0]).toMatchObject({ tipo: 'solicitacao_recebida', to: 'a@b.com', token: TOKEN, ctaLink: TRACK });
  });

  it('falha no envio → ok e sent false', async () => {
    enviar.mockResolvedValue({ ok: false, sent: false, erro: '500' });
    expect(await (await POST(req({ tipo: 'solicitacao_recebida' }))).json()).toEqual({ ok: false, sent: false });
  });

  it('token_link: aceita caminho relativo e o host do app', async () => {
    expect(await cta(`/agendar-entrevista?token=${TOKEN}`)).toBe(`https://grupoparticipa.app.br/agendar-entrevista?token=${TOKEN}`);
    expect(await cta('https://grupoparticipa.app.br/agendar-entrevista')).toBe('https://grupoparticipa.app.br/agendar-entrevista');
  });

  it.each([
    '//evil.com/x',
    '/\\evil.com/x',
    '\\\\evil.com',
    'https://evil.com/agendar',
    'https://grupoparticipa.app.br.evil.com/',
    'https://user@grupoparticipa.app.br/',
    'javascript:alert(1)',
    'evil.com/x',
    '/\tevil',
  ])('token_link rejeitado → link de acompanhamento: %s', async (link) => {
    expect(await cta(link)).toBe(TRACK);
  });

  it('zoom_link só passa se for zoom.us https', async () => {
    await POST(req({ tipo: 'entrevista_agendada', zoom_link: 'https://us02web.zoom.us/j/1' }));
    expect(enviar.mock.calls[0][0].extra.zoom_link).toBe('https://us02web.zoom.us/j/1');
    enviar.mockClear();
    await POST(req({ tipo: 'entrevista_agendada', zoom_link: 'https://evil.com/j/1' }));
    expect(enviar.mock.calls[0][0].extra.zoom_link).toBeUndefined();
  });
});
