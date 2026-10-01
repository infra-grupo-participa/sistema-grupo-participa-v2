import { timingSafeEqual } from 'node:crypto';
import type { NextRequest } from 'next/server';
import { clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { buildSlotStart } from '@/modules/placas/domain/agendamento';
import type { EmailExtra } from '@/modules/placas/application/email-content';
import { enviarEmailPlaca } from '@/modules/placas/application/enviar-email-placa';

export const dynamic = 'force-dynamic';

// Porta de send-interview-reminder.php — lembrete ~4h antes da entrevista.
// Janela larga (3h30–4h30) para tolerar cron de até 1h. GET ou POST (ops.cron_post) com
// Authorization: Bearer $CRON_SECRET.
// Sem e-mail duplo: cada linha é REIVINDICADA atomicamente antes do envio
//   UPDATE ... SET reminder_sent_at = now() WHERE id = $1 AND reminder_sent_at IS NULL RETURNING id
// — duas execuções sobrepostas não enviam 2x: só quem reivindicou envia. Falha no envio
// devolve reminder_sent_at a null (só se ainda for o carimbo desta execução) para a próxima passagem.
const WINDOW_MIN_MS = 3.5 * 60 * 60 * 1000;
const WINDOW_MAX_MS = 4.5 * 60 * 60 * 1000;
const LOTE_MAX = 50;
// Resend: 10 req/s. 120 ms entre envios deixa folga.
const PAUSA_ENTRE_ENVIOS_MS = 120;
// buildSlotStart ancora o horário em -03:00 fixo (Brasil sem horário de verão desde 2019).
const OFFSET_SP_MS = -3 * 60 * 60 * 1000;

const dormir = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

// Comparação em tempo constante: a rota é chamada pela internet.
function mesmoSegredo(recebido: string, esperado: string): boolean {
  const a = Buffer.from(recebido);
  const b = Buffer.from(esperado);
  return a.length === b.length && timingSafeEqual(a, b);
}

// Chave do pg_cron: nasce no Vault (migration 20261005b) e só o banco a conhece — confere por RPC
// (service_role). Formato fixo (64 hex) checado antes, para lixo da internet não virar consulta.
async function chaveDoBancoOk(admin: ReturnType<typeof createAdminSupabase>, auth: string): Promise<boolean> {
  const m = /^Bearer ([0-9a-f]{64})$/.exec(auth);
  if (!m) return false;
  const { data, error } = await admin.rpc('fn_placas_cron_chave_ok', { p_chave: m[1] });
  return !error && data === true;
}

/** Data (YYYY-MM-DD) e hora (HH:MM) de um instante no fuso de buildSlotStart (-03:00). */
function dataHoraSp(ms: number): { data: string; hora: string } {
  const iso = new Date(ms + OFFSET_SP_MS).toISOString();
  return { data: iso.slice(0, 10), hora: iso.slice(11, 16) };
}

async function handle(request: NextRequest) {
  const secret = process.env.CRON_SECRET || '';
  const auth = request.headers.get('authorization') || '';
  const porEnv = !!secret && mesmoSegredo(auth, `Bearer ${secret}`);
  if (!porEnv) {
    // Só quem não passou pela env chega à RPC — limita por IP para a internet não martelar o banco.
    sweepRateLimit();
    if (!rateLimitOk(clientIp(request), 'gp_cron_reminder_rate_', 10, 60)) {
      return jsonError('Muitas requisições. Tente novamente em instantes.', 429);
    }
  }
  const admin = createAdminSupabase();
  if (!porEnv && !(await chaveDoBancoOk(admin, auth))) return jsonError('Não autorizado.', 401);

  // Corte grosso no SQL: só entrevistas cujo início pode cair na janela (no máximo hoje/amanhã em SP),
  // com piso de hora no dia inicial para entrevistas já passadas não ocuparem o lote.
  const now = Date.now();
  const ini = dataHoraSp(now + WINDOW_MIN_MS);
  const fim = dataHoraSp(now + WINDOW_MAX_MS);
  const { data, error } = await admin
    .from('thb_placas_solicitacoes')
    .select('id, token, nome, email, entrevista_data, entrevista_hora, entrevista_link, auditoria_step, reminder_sent_at')
    .eq('auditoria_step', 2)
    .is('reminder_sent_at', null)
    .not('entrevista_data', 'is', null)
    .not('entrevista_hora', 'is', null)
    .gte('entrevista_data', ini.data)
    .lte('entrevista_data', fim.data)
    .or(`entrevista_data.gt.${ini.data},entrevista_hora.gte."${ini.hora}"`)
    .order('entrevista_data', { ascending: true })
    .order('entrevista_hora', { ascending: true })
    .limit(LOTE_MAX);
  if (error) return jsonError('Não foi possível consultar as entrevistas.', 502);

  const alvo = (data ?? []).filter((s) => {
    const start = buildSlotStart(String(s.entrevista_data), String(s.entrevista_hora));
    if (!start) return false;
    const diff = start.getTime() - now;
    return diff >= WINDOW_MIN_MS && diff <= WINDOW_MAX_MS;
  });

  let enviados = 0;
  let falhas = 0;
  let jaReivindicados = 0;
  let primeiroEnvio = true;

  for (const s of alvo) {
    const to = String(s.email ?? '').trim();
    if (!to) continue;

    // Reivindicação atômica: só segue quem efetivamente trocou null → carimbo.
    const carimbo = new Date().toISOString();
    const { data: claimed, error: claimErr } = await admin
      .from('thb_placas_solicitacoes')
      .update({ reminder_sent_at: carimbo })
      .eq('id', s.id)
      .eq('auditoria_step', 2)
      .is('reminder_sent_at', null)
      .select('id, reminder_sent_at');
    if (claimErr) {
      falhas++;
      continue;
    }
    if (!claimed || claimed.length === 0) {
      jaReivindicados++;
      continue;
    }
    const carimboGravado = String(claimed[0].reminder_sent_at ?? carimbo);

    const extra: EmailExtra = {
      entrevista_data: String(s.entrevista_data).slice(0, 10),
      entrevista_hora: String(s.entrevista_hora).slice(0, 5),
      zoom_link: s.entrevista_link ? String(s.entrevista_link) : undefined,
    };
    if (!primeiroEnvio) await dormir(PAUSA_ENTRE_ENVIOS_MS);
    primeiroEnvio = false;
    const r = await enviarEmailPlaca({
      tipo: 'lembrete_entrevista',
      to,
      nome: String(s.nome ?? 'Candidato'),
      token: String(s.token),
      extra,
    });
    if (r.sent) {
      enviados++;
    } else {
      falhas++;
      // Devolve a linha para a próxima passagem — só se o carimbo ainda for o nosso.
      await admin
        .from('thb_placas_solicitacoes')
        .update({ reminder_sent_at: null })
        .eq('id', s.id)
        .eq('reminder_sent_at', carimboGravado);
    }
  }

  const corpo = { ok: !(falhas > 0 && enviados === 0), candidatos: alvo.length, enviados, falhas, ja_reivindicados: jaReivindicados };
  // ops.cron_post só enxerga o status HTTP: tudo falhou → 500 para o vigia acusar.
  if (falhas > 0 && enviados === 0) return jsonOk(corpo, 500);
  return jsonOk(corpo);
}

export async function GET(request: NextRequest) {
  return handle(request);
}

/** ops.cron_post (vigia de rotinas) só faz POST — mesma lógica e mesmo Bearer do GET. */
export async function POST(request: NextRequest) {
  return handle(request);
}
