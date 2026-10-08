import type { NextRequest } from 'next/server';
import { jsonError, jsonOk, validateOrigin } from '@/shared/infrastructure/http/security';
import { isUuid } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { publicEnv } from '@/shared/infrastructure/config/env';
import { desconectarNumero, estadoConexao } from '@/modules/comercial/application/canais-whatsapp';
import { EvolutionApi, EvolutionIndisponivel } from '@/modules/comercial/infrastructure/evolution-api';
import { portasCanais } from '@/modules/comercial/infrastructure/supabase-canais';

export const dynamic = 'force-dynamic';

type Ctx = { params: Promise<{ id: string }> };

// Número de WhatsApp conectado por QR (Evolution API). Só gestor do CRM (o banco confere em crm_canal_portao).
//   GET  → estado para a tela que espera o QR (chamada a cada 3 s): {status, qr, final}
//   POST {acao:'conectar'}    → refaz instância/webhook e pede QR novo (reconectar)
//   POST {acao:'desconectar'} → desconecta o aparelho (o número segue no celular e na Clint)
// Doc: docs/projetos/comercial/whatsapp-qr-evolution.md

async function preparar(req: NextRequest, ctx: Ctx) {
  const user = await getCurrentUser();
  if (!user) return { erro: jsonError('Não autorizado.', 401) };
  const { id } = await ctx.params;
  if (!isUuid(id)) return { erro: jsonError('Número inválido.', 400) };
  const evo = EvolutionApi.doAmbiente();
  if (!evo) return { erro: jsonError('Evolution não configurada no servidor (EVOLUTION_API_URL / EVOLUTION_API_KEY).', 503) };
  return { id, evo };
}

export async function GET(req: NextRequest, ctx: Ctx) {
  if (!validateOrigin(req)) return jsonError('Origem não permitida.', 403);
  const p = await preparar(req, ctx);
  if ('erro' in p) return p.erro;
  try {
    const r = await estadoConexao(p.evo, await portasCanais(), publicEnv.supabaseUrl, p.id, false);
    return r.ok ? jsonOk(r) : jsonError(r.msg, r.http);
  } catch (e) {
    if (e instanceof EvolutionIndisponivel) return jsonError('A Evolution não respondeu.', 502);
    return jsonError('Não foi possível ler o estado do número.', 500);
  }
}

export async function POST(req: NextRequest, ctx: Ctx) {
  if (!validateOrigin(req)) return jsonError('Origem não permitida.', 403);
  const p = await preparar(req, ctx);
  if ('erro' in p) return p.erro;
  const corpo = (await req.json().catch(() => null)) as { acao?: unknown } | null;
  try {
    if (corpo?.acao === 'conectar') {
      const r = await estadoConexao(p.evo, await portasCanais(), publicEnv.supabaseUrl, p.id, true);
      return r.ok ? jsonOk(r) : jsonError(r.msg, r.http);
    }
    if (corpo?.acao === 'desconectar') {
      const r = await desconectarNumero(p.evo, await portasCanais(), p.id);
      return r.ok ? jsonOk({ ok: true }) : jsonError(r.msg, r.http);
    }
    return jsonError('Ação inválida.', 400);
  } catch (e) {
    if (e instanceof EvolutionIndisponivel) return jsonError('A Evolution não respondeu.', 502);
    return jsonError('Não foi possível concluir.', 500);
  }
}
