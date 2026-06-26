import { createClient } from '@supabase/supabase-js';
import { env, publicEnv } from '@/shared/infrastructure/config/env';

/**
 * Client Supabase com SERVICE_ROLE — IGNORA RLS.
 * NUNCA importar no browser. Usar só em adapters de infraestrutura chamados por casos
 * de uso que JÁ validaram autorização (fluxos públicos de placa por token, e-mail,
 * filas, webhooks) — equivalente ao que o PHP legado fazia com service_role.
 */
export function createAdminSupabase() {
  return createClient(publicEnv.supabaseUrl, env.supabase.serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
