import { createHash, timingSafeEqual } from 'node:crypto';
import type { NextRequest } from 'next/server';
import { clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { env } from '@/shared/infrastructure/config/env';
import { validarLead } from './validar-lead';

export const dynamic = 'force-dynamic';

// Captura de lead servidor → servidor (docs/captura-de-lead.md).
//   POST /api/captura/lead
//   Headers: Content-Type: application/json · Authorization: Bearer $CAPTURA_LEAD_SECRET
//   Corpo:   { chave_evento, tipo, nome, email, telefone, utm_*, sck, xcod, pagina_origem, teste }
//   → public.pessoas_registrar_lead (service_role) → pessoas.registrar(p, 'formulario').
// Quem chama: o PHP da página (ex.: clinica.timeholdingbrasil.com.br/miami/api/submit.php), nunca o navegador: o segredo
// mora no servidor da página. Sem CORS de propósito.
//
// Ordem (nada do corpo é lido antes do segredo conferido):
//   1. IP com falhas demais → 429. 2. Segredo ausente no servidor → 503 (fail-closed). 3. Bearer conferido em tempo
//   constante → 401 genérico. 4. Limite por IP, corpo até 8 KB, JSON, validação → 400/413. 5. RPC → 200 ou 400/502.
// LGPD: nome, e-mail, telefone e documento NUNCA vão para log nem para a resposta. Erro do banco loga só o código.
const MAX_BYTES = 8 * 1024;
const NAO_AUTORIZADO = 'Não autorizado.';
const FALHAS_MAX = 10;
const FALHAS_JANELA_S = 600;
const AUTORIZADAS_MAX_MIN = 20; // condição B1 do pentester (07/10/2026): era 120/min
const SEGREDO_MIN = 32;

// Tentativas sem segredo válido por IP (janela fixa), como em /api/mensageria/receber.
const falhas = new Map<string, { inicio: number; n: number }>();
function bloqueadoPorFalhas(ip: string): boolean {
  const f = falhas.get(ip);
  if (!f) return false;
  if (Date.now() / 1000 - f.inicio >= FALHAS_JANELA_S) {
    falhas.delete(ip);
    return false;
  }
  return f.n >= FALHAS_MAX;
}
function contarFalha(ip: string): void {
  const agora = Date.now() / 1000;
  const f = falhas.get(ip);
  if (!f || agora - f.inicio >= FALHAS_JANELA_S) falhas.set(ip, { inicio: agora, n: 1 });
  else f.n += 1;
  if (falhas.size > 10000) {
    for (const [k, v] of falhas) if (agora - v.inicio >= FALHAS_JANELA_S) falhas.delete(k);
  }
}

// Tempo constante também no tamanho: compara o sha256 dos dois lados (timingSafeEqual exige o mesmo comprimento).
function mesmoSegredo(recebido: string, esperado: string): boolean {
  const a = createHash('sha256').update(recebido).digest();
  const b = createHash('sha256').update(esperado).digest();
  return timingSafeEqual(a, b);
}

/** Lê o corpo com teto de bytes (Content-Length mente; o stream é contado). null = passou do teto. */
async function lerCorpo(request: NextRequest): Promise<string | null> {
  const declarado = Number(request.headers.get('content-length') || '0');
  if (declarado > MAX_BYTES) return null;
  if (!request.body) return '';
  const reader = request.body.getReader();
  const partes: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BYTES) {
      await reader.cancel().catch(() => {});
      return null;
    }
    partes.push(value);
  }
  return Buffer.concat(partes).toString('utf8');
}

export async function POST(request: NextRequest) {
  const ip = clientIp(request);
  if (bloqueadoPorFalhas(ip)) return jsonError('Muitas requisições. Tente novamente em instantes.', 429);

  // Fail-closed: sem segredo configurado (ou curto demais) a rota não grava nada.
  const segredo = env.captura.leadSecret;
  if (segredo.length < SEGREDO_MIN) return jsonError('Captura indisponível.', 503);

  const auth = request.headers.get('authorization') || '';
  if (!mesmoSegredo(auth, `Bearer ${segredo}`)) {
    contarFalha(ip);
    return jsonError(NAO_AUTORIZADO, 401);
  }

  sweepRateLimit();
  if (!rateLimitOk(ip, 'gp_captura_lead_', AUTORIZADAS_MAX_MIN, 60)) {
    return jsonError('Muitas requisições. Tente novamente em instantes.', 429);
  }

  if (!(request.headers.get('content-type') || '').toLowerCase().startsWith('application/json')) {
    return jsonError('Content-Type deve ser application/json.', 400);
  }
  const bruto = await lerCorpo(request);
  if (bruto === null) return jsonError('Corpo acima de 8 KB.', 413);
  let corpo: unknown;
  try {
    corpo = JSON.parse(bruto);
  } catch {
    return jsonError('JSON inválido.', 400);
  }
  const v = validarLead(corpo);
  if (!v.ok) return jsonError(v.erro, 400);

  const admin = createAdminSupabase();
  const { data, error } = await admin.rpc('pessoas_registrar_lead', { p: v.lead });
  // HTTP 200 do PostgREST não é sucesso: confere o erro e o "ok" do corpo. Log só com o código (a mensagem do
  // Postgres pode trazer a linha recusada, com dado pessoal).
  if (error || !data || typeof data !== 'object') {
    console.error('[captura/lead] falha na RPC', { code: (error as { code?: string } | null)?.code ?? 'sem_corpo' });
    return jsonError('Não foi possível gravar agora.', 502);
  }
  const r = data as { ok?: boolean; msg?: unknown };
  if (r.ok === true) return jsonOk({ ok: true });
  // Recusa da base (mensagem pública da função, sem dado pessoal): "Evento inválido…", "Informe um e-mail…".
  const msg = typeof r.msg === 'string' && r.msg.length <= 200 ? r.msg : 'Dados recusados pela base.';
  return jsonError(msg, 400);
}
