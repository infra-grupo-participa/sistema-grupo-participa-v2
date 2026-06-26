import { createBrowserClient } from '@supabase/ssr';
import { publicEnv } from '@/shared/infrastructure/config/env';

/**
 * Client Supabase para o browser (Client Components).
 * Anon key (pública por design, protegida por RLS). Herda a sessão via cookies,
 * então o RLS do banco continua sendo a fonte de verdade de permissão.
 */
export function createBrowserSupabase() {
  return createBrowserClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey);
}
