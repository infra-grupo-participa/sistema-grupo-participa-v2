import type { NextRequest } from 'next/server';
import { clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';

export const dynamic = 'force-dynamic';

// Entrada das integrações da Mensageria (n8n → banco). Migration 20261005o.
//   POST /api/mensageria/receber
//   Headers: x-mensageria-fonte: <chave da fonte>  ·  Authorization: Bearer <chave da fonte, 64 hex, do Vault>
//   Corpo:   { "lote": [ …itens… ] }                                   → public.mkt_msg_api_receber
//         ou { "reconciliacao": { "dia": "aaaa-mm-dd", "ids": [...] } } → public.mkt_msg_api_reconciliar
//
// Ordem (nada do corpo é lido antes de a chave ser conferida):
//   1. IP pelo clientIp (salto mais à direita não interno; X-Forwarded-For cru mente) → bloqueado por falhas? 429.
//   2. Formato dos headers; 3. chave conferida no banco (mkt_msg_api_chave_ok, barata, service_role) → 401 genérico.
//   4. Só com chave válida: limite geral por IP, leitura do corpo até 5 MB e a RPC de gravação.
// Sem chave válida o limite é bem menor (FALHAS_MAX em FALHAS_JANELA_S): cada tentativa errada custa uma consulta.
// O service_role (lê o Vault) e as chaves das fontes moram só no servidor/n8n, nunca no client.
const MAX_BYTES = 5 * 1024 * 1024; // 1.000 itens com copy de 4.000 caracteres ≈ 4,5 MB
const FONTE_RE = /^[a-z][a-z_]{1,39}$/;
const CHAVE_RE = /^Bearer ([0-9a-f]{64})$/;
const DIA_RE = /^\d{4}-\d{2}-\d{2}$/;
const NAO_AUTORIZADO = 'Não autorizado.';
const FALHAS_MAX = 10;
const FALHAS_JANELA_S = 600;
const AUTORIZADAS_MAX_MIN = 120;

type Resposta = { ok?: boolean; erro?: string } & Record<string, unknown>;

// Tentativas sem chave válida por IP (janela fixa). Só leitura antes da consulta; incrementa na falha.
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
      await reader.cancel();
      return null;
    }
    partes.push(value);
  }
  return Buffer.concat(partes).toString('utf8');
}

export async function POST(request: NextRequest) {
  const ip = clientIp(request);
  if (bloqueadoPorFalhas(ip)) return jsonError('Muitas requisições. Tente novamente em instantes.', 429);

  const fonte = (request.headers.get('x-mensageria-fonte') || '').trim();
  const m = CHAVE_RE.exec(request.headers.get('authorization') || '');
  if (!FONTE_RE.test(fonte) || !m) {
    contarFalha(ip);
    return jsonError(NAO_AUTORIZADO, 401);
  }
  const chave = m[1];

  const admin = createAdminSupabase();
  const porteiro = await admin.rpc('mkt_msg_api_chave_ok', { p_fonte: fonte, p_chave: chave });
  if (porteiro.error) return jsonError('Não foi possível gravar agora.', 502);
  if (porteiro.data !== true) {
    contarFalha(ip);
    return jsonError(NAO_AUTORIZADO, 401);
  }

  sweepRateLimit();
  if (!rateLimitOk(ip, 'gp_mensageria_receber_', AUTORIZADAS_MAX_MIN, 60)) {
    return jsonError('Muitas requisições. Tente novamente em instantes.', 429);
  }

  const texto = await lerCorpo(request);
  if (texto === null) return jsonError('Corpo acima de 5 MB.', 413);
  let corpo: unknown;
  try {
    corpo = JSON.parse(texto);
  } catch {
    return jsonError('JSON inválido.', 400);
  }
  if (!corpo || typeof corpo !== 'object' || Array.isArray(corpo)) return jsonError('Corpo deve ser um objeto JSON.', 400);
  const c = corpo as { lote?: unknown; reconciliacao?: { dia?: unknown; ids?: unknown } };

  let rpc: { data: unknown; error: unknown };
  if (Array.isArray(c.lote)) {
    rpc = await admin.rpc('mkt_msg_api_receber', { p_fonte: fonte, p_chave: chave, p_lote: c.lote });
  } else if (c.reconciliacao && typeof c.reconciliacao === 'object') {
    const { dia, ids } = c.reconciliacao;
    if (typeof dia !== 'string' || !DIA_RE.test(dia) || !Array.isArray(ids)) {
      return jsonError('reconciliacao: informe dia (aaaa-mm-dd) e ids (lista).', 400);
    }
    rpc = await admin.rpc('mkt_msg_api_reconciliar', { p_fonte: fonte, p_chave: chave, p_dia: dia, p_ids: ids });
  } else {
    return jsonError('Corpo deve ter "lote" (lista) ou "reconciliacao".', 400);
  }

  // HTTP 200 do PostgREST não é sucesso: confere o erro e o "ok" do corpo.
  if (rpc.error || !rpc.data || typeof rpc.data !== 'object') return jsonError('Não foi possível gravar agora.', 502);
  const r = rpc.data as Resposta;
  if (r.ok === true) return jsonOk(r);
  switch (r.erro) {
    case 'nao_autorizado': // fonte desligada (a chave estava certa): mesmo 401 genérico
      return jsonError(NAO_AUTORIZADO, 401);
    case 'lote_grande':
      return jsonError('Lote acima de 1.000 itens: divida em lotes menores.', 413);
    case 'lote_invalido':
      return jsonError('"lote" deve ser uma lista.', 400);
    case 'dia_invalido':
      return jsonError('reconciliacao.dia fora da faixa (até 400 dias atrás, não no futuro).', 400);
    case 'ids_invalidos':
      return jsonError('reconciliacao.ids: lista de até 20.000 itens.', 400);
    default:
      return jsonError('Não foi possível gravar agora.', 502);
  }
}
