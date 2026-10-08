import type { NextRequest } from 'next/server';
import { jsonError, jsonOk, validateOrigin } from '@/shared/infrastructure/http/security';
import { getCurrentUser } from '@/shared/composition/server-container';
import { publicEnv } from '@/shared/infrastructure/config/env';
import { criarNumero } from '@/modules/comercial/application/canais-whatsapp';
import { validarNomeCanal } from '@/modules/comercial/domain/canais-whatsapp';
import { EvolutionApi, EvolutionIndisponivel } from '@/modules/comercial/infrastructure/evolution-api';
import { ehGestorCrm, portasCanais } from '@/modules/comercial/infrastructure/supabase-canais';

export const dynamic = 'force-dynamic';

// POST /api/comercial/canais {nome} — "Conectar número" (WhatsApp por QR, Evolution API). Só gestor do CRM (o banco
// confere em crm_canal_criar). Cria o número, a instância e o webhook, e devolve o primeiro QR (data URL PNG).
// Doc: docs/projetos/comercial/whatsapp-qr-evolution.md
export async function POST(req: NextRequest) {
  if (!validateOrigin(req)) return jsonError('Origem não permitida.', 403);
  const user = await getCurrentUser();
  if (!user) return jsonError('Não autorizado.', 401);
  if (!(await ehGestorCrm())) return jsonError('Só o gestor do Comercial conecta números.', 403);
  const evo = await EvolutionApi.resolver();
  if (!evo) return jsonError('Evolution não configurada (env EVOLUTION_API_URL/KEY ou Vault evolution_api_url/_key).', 503);
  const corpo = (await req.json().catch(() => null)) as { nome?: unknown } | null;
  const nome = typeof corpo?.nome === 'string' ? corpo.nome : '';
  const invalido = validarNomeCanal(nome);
  if (invalido) return jsonError(invalido, 400);
  try {
    const r = await criarNumero(evo, await portasCanais(), publicEnv.supabaseUrl, nome.trim());
    return r.ok ? jsonOk({ ok: true, canalId: r.canalId, qr: r.qr }) : jsonError(r.msg, r.http);
  } catch (e) {
    if (e instanceof EvolutionIndisponivel) return jsonError('A Evolution não respondeu. Tente de novo em instantes.', 502);
    return jsonError('Não foi possível conectar o número.', 500);
  }
}
