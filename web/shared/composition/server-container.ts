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

/** Atalho memoizado por request: usuário canônico autenticado (ou null).
 *  Tolerante a falha de infraestrutura (env ausente/Supabase fora) → null,
 *  para a página redirecionar ao login em vez de estourar 500. */
export const getCurrentUser = cache(async (): Promise<GpUser | null> => {
  try {
    const { getCurrentUser } = await serverContainer();
    return await getCurrentUser.execute();
  } catch {
    return null;
  }
});
