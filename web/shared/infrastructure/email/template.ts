import type { EmailTemplateData } from '@/modules/placas/application/email-content';

// Builder do template HTML de e-mail — porta de buildEmailTemplate (email-template.php).

const esc = (s: string) =>
  String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function button(link: string, label: string, cor: string): string {
  return `<p style="text-align:center;margin:28px 0;"><a href="${esc(link)}" target="_blank" style="background:${cor};color:#fff;text-decoration:none;padding:14px 28px;border-radius:8px;font-weight:bold;display:inline-block;">${esc(label)}</a></p>`;
}

// Base pública do app — o logo é servido pelo próprio Next (web/public/images/).
const APP_BASE = (process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br').replace(/\/$/, '');
const APP_HOST = APP_BASE.replace(/^https?:\/\//, '');

const FOOTER = `<div style="margin-top:32px;padding-top:20px;border-top:1px solid #eee;text-align:center;color:#888;font-size:12px;"><p style="margin:0;">Time Holding Brasil</p><p style="margin:6px 0 0;"><a href="${APP_BASE}" style="color:#F29725;text-decoration:none;">${APP_HOST}</a></p></div>`;

const HEADER = `<div style="text-align:center;padding:32px 0 24px;border-bottom:1px solid #eee;margin-bottom:28px;"><img src="${APP_BASE}/images/TimeHoldingBrasil.png" alt="Time Holding Brasil" style="height:80px;width:auto;display:inline-block;" /></div>`;

export function buildEmailTemplate(data: EmailTemplateData): string {
  const nome = esc(data.nome || 'Candidato');
  const tituloCor = data.titulo_cor || '#F29725';
  const ctaHtml = data.cta_link ? button(data.cta_link, data.cta_label || 'Acompanhar meu processo', data.cta_cor || '#F29725') : '';
  const notaHtml = data.nota ? `<p style="color:#888;font-size:13px;">${esc(data.nota)}</p>` : '';

  const corpo = `
    <h2 style="color:${tituloCor};">${esc(data.titulo)}</h2>
    <p>Olá, Dr(a). <strong>${nome}</strong>,</p>
    <p>${data.introducao ?? ''}</p>
    ${data.corpo_extra ?? ''}
    ${ctaHtml}
    ${notaHtml}
    ${data.pos_cta ?? ''}
    <p style="margin-top:24px">Ficamos no aguardo de boas notícias!</p>
    <p style="margin:4px 0 0">Atenciosamente,<br><strong>Equipe Holding Masters</strong></p>`;

  return `<!DOCTYPE html><html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Time Holding Brasil</title></head>
<body style="margin:0;padding:0;background:#f5f5f5;font-family:Arial,sans-serif;color:#333;line-height:1.6;">
<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;background:#f5f5f5;"><tr><td align="center" style="padding:24px 16px;">
<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;background:#ffffff;border-radius:8px;overflow:hidden;"><tr><td style="padding:20px 32px 32px;">
${HEADER}${corpo}${FOOTER}
</td></tr></table></td></tr></table></body></html>`;
}
