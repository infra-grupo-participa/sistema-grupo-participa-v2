import { cache } from 'react';
import { createServerSupabase } from '@/shared/infrastructure/supabase/server-client';
import { SupabaseAuthGateway } from '@/shared/infrastructure/auth/supabase-auth.gateway';
import { SupabaseProfileRepository } from '@/shared/infrastructure/auth/supabase-profile.repository';
import { GetCurrentUser } from '@/shared/application/auth/get-current-user';
import type { GpUser } from '@/shared/domain/auth';

/**
 * Composition root do contexto server. Monta casos de uso com adapters concretos.
 * A presentation pede casos de uso aqui — nunca instancia adapters direto.
 */
export async function serverContainer() {
  const supabase = await createServerSupabase();
  return {
    supabase,
    getCurrentUser: new GetCurrentUser(
      new SupabaseAuthGateway(supabase),
      new SupabaseProfileRepository(supabase),
    ),
  };
}

/** Atalho memoizado por request: usuário canônico autenticado (ou null). */
export const getCurrentUser = cache(async (): Promise<GpUser | null> => {
  const { getCurrentUser } = await serverContainer();
  return getCurrentUser.execute();
});
