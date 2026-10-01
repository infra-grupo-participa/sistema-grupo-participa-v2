import { beforeEach, describe, expect, it, vi } from 'vitest';

const sendMailDetalhado = vi.fn();
const logSystemEvent = vi.fn();
const readPlacasConfig = vi.fn();

vi.mock('@/shared/infrastructure/email/mailer', () => ({ sendMailDetalhado: (...a: unknown[]) => sendMailDetalhado(...a) }));
vi.mock('@/shared/infrastructure/observability/system-events', () => ({
  logSystemEvent: (...a: unknown[]) => logSystemEvent(...a),
  snippet: (v: unknown) => String(v),
}));
vi.mock('@/modules/placas/infrastructure/supabase-config', () => ({ readPlacasConfig: () => readPlacasConfig() }));
vi.mock('@/shared/infrastructure/http/security', () => ({
  placaTrackingLink: (t: string) => `https://x.test/solicitar-placa?token=${t}`,
}));

import { enviarEmailPlaca } from './enviar-email-placa';

const base = { tipo: 'solicitacao_recebida' as const, to: 'a@b.com', nome: 'Ana', token: 'tok' };

beforeEach(() => {
  vi.clearAllMocks();
  readPlacasConfig.mockResolvedValue({ email_templates: {} });
});

describe('enviarEmailPlaca', () => {
  it('envia com link de acompanhamento e devolve id', async () => {
    sendMailDetalhado.mockResolvedValue({ ok: true, id: 'abc' });
    const r = await enviarEmailPlaca(base);
    expect(r).toEqual({ ok: true, sent: true, id: 'abc' });
    const msg = sendMailDetalhado.mock.calls[0][0];
    expect(msg.to).toBe('a@b.com');
    expect(msg.html).toContain('solicitar-placa?token=tok');
    expect(logSystemEvent).not.toHaveBeenCalled();
  });

  it('aplica override do admin (assunto e introdução)', async () => {
    readPlacasConfig.mockResolvedValue({
      email_templates: { solicitacao_recebida: { assunto: ' Assunto X ', introducao: 'Intro Y' } },
    });
    sendMailDetalhado.mockResolvedValue({ ok: true });
    await enviarEmailPlaca(base);
    const msg = sendMailDetalhado.mock.calls[0][0];
    expect(msg.subject).toBe('Assunto X');
    expect(msg.html).toContain('Intro Y');
  });

  it('re-injeta caixa dinâmica no corpo customizado', async () => {
    readPlacasConfig.mockResolvedValue({ email_templates: { placa_em_caminho: { corpo_extra: '<p>meu corpo</p>' } } });
    sendMailDetalhado.mockResolvedValue({ ok: true });
    await enviarEmailPlaca({ ...base, tipo: 'placa_em_caminho', extra: { codigo_rastreio: 'BR123' } });
    const html = sendMailDetalhado.mock.calls[0][0].html;
    expect(html).toContain('BR123');
    expect(html).toContain('meu corpo');
  });

  it('falha do mailer: sent=false, erro e evento gravado', async () => {
    sendMailDetalhado.mockResolvedValue({ ok: false, erro: 'HTTP 500' });
    const r = await enviarEmailPlaca(base);
    expect(r).toEqual({ ok: false, sent: false, erro: 'HTTP 500' });
    expect(logSystemEvent).toHaveBeenCalledTimes(1);
  });

  it('evento de falha não carrega e-mail, nome nem token (só solicitacao_id e domínio)', async () => {
    sendMailDetalhado.mockResolvedValue({ ok: false, erro: 'recusado para a@b.com' });
    await enviarEmailPlaca({ ...base, solicitacaoId: '42' });
    const detalhe = logSystemEvent.mock.calls[0][0].detalhe;
    expect(detalhe).toMatchObject({ solicitacao_id: '42', para_dominio: 'b.com' });
    const log = JSON.stringify(logSystemEvent.mock.calls);
    expect(log).not.toContain('a@b.com');
    expect(log).not.toContain('Ana');
    expect(log).not.toContain('tok');
  });

  it('exceção interna não propaga', async () => {
    readPlacasConfig.mockRejectedValue(new Error('db fora'));
    const r = await enviarEmailPlaca(base);
    expect(r.ok).toBe(false);
    expect(r.sent).toBe(false);
    expect(logSystemEvent).toHaveBeenCalledTimes(1);
  });

  it('ctaLink explícito substitui o link de acompanhamento', async () => {
    sendMailDetalhado.mockResolvedValue({ ok: true, id: 'abc' });
    await enviarEmailPlaca({ ...base, tipo: 'docs_aprovados', ctaLink: 'https://x.test/agendar-entrevista?token=tok' });
    const html = sendMailDetalhado.mock.calls[0][0].html;
    expect(html).toContain('agendar-entrevista?token=tok');
    expect(html).not.toContain('solicitar-placa?token=tok');
  });
});
