// Mailer transacional. Usa Resend (HTTP, sem dependência extra) se configurado.
// Sem RESEND_API_KEY → no-op silencioso (melhor-esforço, como o @mail() do legado).
// Falha de envio (HTTP/timeout) vira evento em thb_system_events (aba Admin Dev).

import { logSystemEvent, snippet } from '@/shared/infrastructure/observability/system-events';
import { dominioEmail, mascararEmails } from '@/shared/infrastructure/observability/pii';

export interface MailMessage {
  to: string | string[];
  subject: string;
  html: string;
  from?: string;
}

const DEFAULT_FROM = 'Time Holding Brasil <contato@grupoparticipa.app.br>';

export interface MailResult {
  ok: boolean;
  id?: string;
  erro?: string;
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Igual a sendMail, mas devolve id/erro. Em 429 do Resend espera ~1s e tenta 1 vez de novo. */
export async function sendMailDetalhado(msg: MailMessage): Promise<MailResult> {
  const key = process.env.RESEND_API_KEY;
  const from = msg.from || process.env.MAIL_FROM || DEFAULT_FROM;
  if (!key) {
    // SMTP pode ser adicionado aqui (nodemailer) se a Hostinger preferir SMTP.
    return { ok: false, erro: 'RESEND_API_KEY ausente' };
  }
  const body = JSON.stringify({
    from,
    to: Array.isArray(msg.to) ? msg.to : [msg.to],
    subject: msg.subject,
    html: msg.html,
  });
  try {
    let resp: Response | undefined;
    for (let tentativa = 0; tentativa < 2; tentativa++) {
      resp = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body,
        signal: AbortSignal.timeout(15000),
      });
      if (resp.status !== 429 || tentativa === 1) break;
      await sleep(1000);
    }
    if (!resp) return { ok: false, erro: 'sem resposta' };
    if (!resp.ok) {
      const texto = await resp.text().catch(() => '');
      await logSystemEvent({
        tipo: 'error',
        fonte: 'mailer',
        titulo: `Falha no envio de e-mail (HTTP ${resp.status})`,
        detalhe: { para_dominio: dominioEmail(msg.to), assunto: msg.subject, http_status: resp.status, resposta: snippet(mascararEmails(texto)) },
      });
      return { ok: false, erro: `HTTP ${resp.status}: ${snippet(mascararEmails(texto), 200)}` };
    }
    const json = (await resp.json().catch(() => null)) as { id?: unknown } | null;
    return { ok: true, id: typeof json?.id === 'string' ? json.id : undefined };
  } catch (err) {
    const erro = snippet(err instanceof Error ? `${err.name}: ${err.message}` : String(err));
    await logSystemEvent({
      tipo: 'error',
      fonte: 'mailer',
      titulo: 'Exceção ao enviar e-mail (timeout/rede)',
      detalhe: { para_dominio: dominioEmail(msg.to), assunto: msg.subject, erro: mascararEmails(erro) },
    });
    return { ok: false, erro };
  }
}

export async function sendMail(msg: MailMessage): Promise<boolean> {
  return (await sendMailDetalhado(msg)).ok;
}
