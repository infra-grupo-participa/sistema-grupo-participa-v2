// Marketing > Web: adapters da coleta no SERVIDOR (nunca importar no navegador). Chama public.mkt_web_coletar e
// public.mkt_web_dominios com a chave de serviço; anon e authenticated não executam essas funções.
import { createHash } from 'node:crypto';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { env } from '@/shared/infrastructure/config/env';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { LIMITE_IP_MINUTO } from '../domain/coleta';
import type { PortasColeta } from '../application/receber-pacote';

const CACHE_MS = 60_000;
let cache: { em: number; dominios: ReadonlySet<string> } | null = null;

async function dominios(): Promise<ReadonlySet<string> | null> {
  if (cache && Date.now() - cache.em < CACHE_MS) return cache.dominios;
  try {
    const { data, error } = await createAdminSupabase().rpc('mkt_web_dominios');
    if (error) throw error;
    cache = { em: Date.now(), dominios: new Set(((data as string[] | null) ?? []).map((d) => d.toLowerCase())) };
    return cache.dominios;
  } catch {
    // banco fora: vale a lista velha, se houver; senão a rota responde 503 e o gravador conta a falha
    return cache?.dominios ?? null;
  }
}

async function coletar(corpo: string, origem: string, ipHash: string): Promise<unknown> {
  const { data, error } = await createAdminSupabase().rpc('mkt_web_coletar', { p_corpo: corpo, p_origem: origem, p_ip_hash: ipHash });
  if (error) throw error;
  return data;
}

function ritmoOk(ip: string): boolean {
  sweepRateLimit();
  return rateLimitOk(ip, 'mkt_web_coleta_', LIMITE_IP_MINUTO, 60);
}

/** sha-256 de (sal secreto + dia + IP), 32 caracteres. O sal sai da chave de serviço (já secreta, só no servidor). */
function hashIp(ip: string): string {
  const dia = new Date().toISOString().slice(0, 10);
  const sal = env.supabase.serviceRoleKey.slice(-24);
  return createHash('sha256').update(`${sal}|${dia}|${ip}`).digest('hex').slice(0, 32);
}

export const portasColeta: PortasColeta = { dominios, coletar, ritmoOk, hashIp };
