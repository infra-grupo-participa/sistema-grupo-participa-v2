// Mailer transacional. Usa Resend (HTTP, sem dependência extra) se configurado.
// Sem RESEND_API_KEY → no-op silencioso (melhor-esforço, como o @mail() do legado).
// Falha de envio (HTTP/timeout) vira evento em thb_system_events (aba Admin Dev).

import { logSystemEvent, snippet } from '@/shared/infrastructure/observability/system-events';

export interface MailMessage {
  to: string | string[];
  subject: string;
  html: string;
  from?: string;
}

const DEFAULT_FROM = 'Time Holding Brasil <contato@grupoparticipa.app.br>';

export async function sendMail(msg: MailMessage): Promise<boolean> {
  const key = process.env.RESEND_API_KEY;
  const from = msg.from || process.env.MAIL_FROM || DEFAULT_FROM;
  if (!key) {
    // SMTP pode ser adicionado aqui (nodemailer) se a Hostinger preferir SMTP.
    return false;
  }
  try {
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from,
        to: Array.isArray(msg.to) ? msg.to : [msg.to],
        subject: msg.subject,
        html: msg.html,
      }),
      signal: AbortSignal.timeout(15000),
    });
    if (!resp.ok) {
      await logSystemEvent({
        tipo: 'error',
        fonte: 'mailer',
        titulo: `Falha no envio de e-mail (HTTP ${resp.status})`,
        detalhe: { para: msg.to, assunto: msg.subject, http_status: resp.status, resposta: snippet(await resp.text().catch(() => '')) },
      });
    }
    return resp.ok;
  } catch (err) {
    await logSystemEvent({
      tipo: 'error',
      fonte: 'mailer',
      titulo: 'Exceção ao enviar e-mail (timeout/rede)',
      detalhe: { para: msg.to, assunto: msg.subject, erro: snippet(err instanceof Error ? `${err.name}: ${err.message}` : String(err)) },
    });
    return false;
  }
}
