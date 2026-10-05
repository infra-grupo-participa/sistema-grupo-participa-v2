import { timingSafeEqual } from 'node:crypto';
import type { NextRequest } from 'next/server';
import { clientIp, jsonError, jsonOk, publicAppBaseUrl } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { sendMailDetalhado } from '@/shared/infrastructure/email/mailer';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { enviarEmailPlaca } from '@/modules/placas/application/enviar-email-placa';

export const dynamic = 'force-dynamic';

// Resumo diário de Placas para a equipe (pg_cron 20261005f, 08h BRT seg–sex) + cutucada ao candidato.
// Autenticação idêntica a /api/cron/interview-reminder (duplicada de propósito: aquele arquivo está em revisão).
// Contagens: UMA query agregada (fn_placas_resumo_contagens). E-mail da equipe só com NÚMEROS — nada de
// nome/e-mail/telefone/token de candidato. Resposta sem PII.
// Cutucada: só com thb_placas_config.cutucada_ativa = true (default false → nada enviado nem marcado).

const CUTUCADA_LOTE_MAX = 30;
/** Teto de "parado": candidato sumido há mais que isso não recebe cutucada (decisão a confirmar com o Marcio). */
const CUTUCADA_MAX_DIAS = 30;
// Resend: 10 req/s. 120 ms entre envios deixa folga.
const PAUSA_ENTRE_ENVIOS_MS = 120;
const TZ = 'America/Sao_Paulo';

const dormir = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

function mesmoSegredo(recebido: string, esperado: string): boolean {
  const a = Buffer.from(recebido);
  const b = Buffer.from(esperado);
  return a.length === b.length && timingSafeEqual(a, b);
}

async function chaveDoBancoOk(admin: ReturnType<typeof createAdminSupabase>, auth: string): Promise<boolean> {
  const m = /^Bearer ([0-9a-f]{64})$/.exec(auth);
  if (!m) return false;
  const { data, error } = await admin.rpc('fn_placas_cron_chave_ok', { p_chave: m[1] });
  return !error && data === true;
}

/** Dia da semana em São Paulo: 0 = domingo … 6 = sábado. */
function diaSemanaSp(ms: number): number {
  const curto = new Intl.DateTimeFormat('en-US', { timeZone: TZ, weekday: 'short' }).format(new Date(ms));
  return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(curto);
}

interface ContagensResumo {
  aguardando_analise: number;
  docs_aprovados_sem_entrevista: number;
  entrevistas_hoje: number;
  entrevistas_sem_desfecho: number;
  parados_enviado: number;
  parados_em_auditoria: number;
  parados_docs_aprovados: number;
  parados_placa_postada: number;
  /** Rascunho parado é do aluno, não da equipe: aparece no e-mail, mas sozinho não dispara envio. */
  parados_rascunho: number;
  novos: number;
}

const CHAVES: (keyof ContagensResumo)[] = [
  'aguardando_analise',
  'docs_aprovados_sem_entrevista',
  'entrevistas_hoje',
  'entrevistas_sem_desfecho',
  'parados_enviado',
  'parados_em_auditoria',
  'parados_docs_aprovados',
  'parados_placa_postada',
  'parados_rascunho',
  'novos',
];

function normalizar(row: Record<string, unknown> | undefined): ContagensResumo {
  const out = {} as ContagensResumo;
  for (const k of CHAVES) out[k] = Number(row?.[k] ?? 0) || 0;
  return out;
}

function temPendenciaEquipe(c: ContagensResumo): boolean {
  return CHAVES.some((k) => k !== 'parados_rascunho' && c[k] > 0);
}

/** Destinatários de ADMIN_EMAIL (aceita lista separada por vírgula). */
function destinatariosAdmin(): string[] {
  return String(process.env.ADMIN_EMAIL ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/.test(s));
}

function montarEmailResumo(c: ContagensResumo, horasNovos: number): { subject: string; html: string } {
  const link = `${publicAppBaseUrl()}/educacional/placas`;
  const linha = (rotulo: string, n: number) =>
    `<tr><td style="padding:6px 12px;border-bottom:1px solid #eee">${rotulo}</td><td style="padding:6px 12px;border-bottom:1px solid #eee;text-align:right;font-weight:700">${n}</td></tr>`;
  const html = `<!DOCTYPE html><html lang="pt-BR"><head><meta charset="UTF-8"><title>Resumo de placas</title></head>
<body style="margin:0;padding:24px;background:#f5f5f5;font-family:Arial,sans-serif;color:#333">
<div style="max-width:560px;margin:0 auto;background:#fff;border-radius:8px;padding:24px">
<h2 style="margin:0 0 16px;color:#F29725">Placas — resumo do dia</h2>
<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;font-size:14px">
${linha('Aguardando análise da documentação', c.aguardando_analise)}
${linha(`Novos envios (últimas ${horasNovos}h)`, c.novos)}
${linha('Documentação aprovada sem entrevista marcada', c.docs_aprovados_sem_entrevista)}
${linha('Entrevistas hoje', c.entrevistas_hoje)}
${linha('Entrevistas passadas sem desfecho', c.entrevistas_sem_desfecho)}
${linha('Parados há 3+ dias — enviado', c.parados_enviado)}
${linha('Parados há 3+ dias — em auditoria', c.parados_em_auditoria)}
${linha('Parados há 3+ dias — documentação aprovada', c.parados_docs_aprovados)}
${linha('Parados há 3+ dias — placa postada', c.parados_placa_postada)}
${linha('Rascunhos parados há 3+ dias (do aluno)', c.parados_rascunho)}
</table>
<p style="text-align:center;margin:24px 0 0"><a href="${link}" target="_blank" style="background:#F29725;color:#fff;text-decoration:none;padding:12px 24px;border-radius:8px;font-weight:bold;display:inline-block">Abrir relatório de placas</a></p>
</div></body></html>`;
  return { subject: `[Placas] Resumo do dia — ${c.aguardando_analise} aguardando análise, ${c.entrevistas_hoje} entrevista(s) hoje`, html };
}

interface ResultadoCutucada {
  ativa: boolean;
  reivindicados: number;
  enviados: number;
  falhas: number;
}

async function cutucar(admin: ReturnType<typeof createAdminSupabase>): Promise<ResultadoCutucada> {
  const r: ResultadoCutucada = { ativa: false, reivindicados: 0, enviados: 0, falhas: 0 };
  const cfg = await readPlacasConfig();
  if (cfg.cutucada_ativa !== true) return r;
  r.ativa = true;

  const { data, error } = await admin.rpc('fn_placas_cutucada_reivindicar', {
    p_limite: CUTUCADA_LOTE_MAX,
    p_max_dias: CUTUCADA_MAX_DIAS,
  });
  if (error) {
    r.falhas++;
    return r;
  }
  const linhas = (Array.isArray(data) ? data : []) as Array<{ id: string; token: string; nome: string | null; email: string; carimbo: string }>;
  r.reivindicados = linhas.length;

  let primeiro = true;
  for (const s of linhas) {
    if (!primeiro) await dormir(PAUSA_ENTRE_ENVIOS_MS);
    primeiro = false;
    const env = await enviarEmailPlaca({
      tipo: 'cutucada',
      to: String(s.email),
      nome: String(s.nome ?? 'Candidato'),
      token: String(s.token),
      solicitacaoId: String(s.id),
    });
    if (env.sent) {
      r.enviados++;
      continue;
    }
    // Uma vez só: o carimbo fica mesmo na falha (endereço recusado não vira reenvio diário por 30 dias).
    // A falha já está em thb_system_events (enviar-email-placa) e conta em `falhas`.
    r.falhas++;
  }
  return r;
}

async function handle(request: NextRequest) {
  const secret = process.env.CRON_SECRET || '';
  const auth = request.headers.get('authorization') || '';
  const porEnv = !!secret && mesmoSegredo(auth, `Bearer ${secret}`);
  if (!porEnv) {
    sweepRateLimit();
    if (!rateLimitOk(clientIp(request), 'gp_cron_resumo_rate_', 10, 60)) {
      return jsonError('Muitas requisições. Tente novamente em instantes.', 429);
    }
  }
  const admin = createAdminSupabase();
  if (!porEnv && !(await chaveDoBancoOk(admin, auth))) return jsonError('Não autorizado.', 401);

  const agora = Date.now();
  const dia = diaSemanaSp(agora);
  if (dia === 0 || dia === 6) return jsonOk({ ok: true, pulado: 'fim_de_semana' });

  // Segunda cobre o fim de semana: novos desde sexta 08h.
  const horasNovos = dia === 1 ? 72 : 24;
  const { data, error } = await admin.rpc('fn_placas_resumo_contagens', { p_horas_novos: horasNovos });
  if (error) return jsonError('Não foi possível consultar as solicitações.', 502);
  const contagens = normalizar((Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined);

  // Resumo da equipe.
  let enviado = false;
  let erroResumo: string | null = null;
  let motivo: string | undefined;
  if (!temPendenciaEquipe(contagens)) {
    motivo = 'nada_pendente';
  } else {
    const para = destinatariosAdmin();
    if (para.length === 0) {
      erroResumo = 'ADMIN_EMAIL ausente ou inválido';
    } else {
      const { subject, html } = montarEmailResumo(contagens, horasNovos);
      const r = await sendMailDetalhado({ to: para, subject, html });
      if (r.ok) enviado = true;
      else erroResumo = 'falha no envio do resumo';
    }
  }

  // Cutucada roda depois das contagens (com a 20261005i o carimbo não move updated_at; a ordem é só cautela).
  const cutucada = await cutucar(admin);
  const cutucadaFalhouTudo = cutucada.falhas > 0 && cutucada.enviados === 0;

  const ok = !erroResumo && !cutucadaFalhouTudo;
  const corpo = {
    ok,
    enviado,
    ...(motivo ? { motivo } : {}),
    ...(erroResumo ? { erro: erroResumo } : {}),
    contagens,
    cutucada,
  };
  // ops.cron_post só enxerga o status HTTP: falha → 500 para o vigia acusar.
  return jsonOk(corpo, ok ? 200 : 500);
}

export async function GET(request: NextRequest) {
  return handle(request);
}

/** ops.cron_post (vigia de rotinas) só faz POST — mesma lógica e mesmo Bearer do GET. */
export async function POST(request: NextRequest) {
  return handle(request);
}
