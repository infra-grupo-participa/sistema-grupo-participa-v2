import { createClient } from '@supabase/supabase-js';
import { publicEnv } from '@/shared/infrastructure/config/env';

/**
 * Client Supabase que fala com o banco COMO o dono de um JWT já assinado (anon key + Authorization: Bearer <jwt>).
 * RLS e auth.uid() valem como na tela. Só servidor; hoje usado pelo MCP do Comercial (/api/mcp).
 */
export function createJwtSupabase(jwt: string) {
  return createClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
}
