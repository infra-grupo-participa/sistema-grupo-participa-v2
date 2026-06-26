import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { publicEnv } from '@/shared/infrastructure/config/env';

/**
 * Client Supabase para o servidor (Server Components, Route Handlers, Server Actions).
 * Roda com o JWT do usuário (cookies) → RLS aplica as regras do sistema legado.
 * Use por padrão; reserve o admin client para operações privilegiadas explícitas.
 */
export async function createServerSupabase() {
  const cookieStore = await cookies();
  return createServerClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch {
          // Chamado de Server Component — ok quando o proxy renova a sessão.
        }
      },
    },
  });
}
