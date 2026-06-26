import type { SupabaseClient } from '@supabase/supabase-js';
import type { AuthGateway, AuthUser } from '@/shared/application/auth/ports';

/** Adapter do port AuthGateway sobre um SupabaseClient com sessão do usuário. */
export class SupabaseAuthGateway implements AuthGateway {
  constructor(private readonly supabase: SupabaseClient) {}

  async getAuthUser(): Promise<AuthUser | null> {
    const {
      data: { user },
    } = await this.supabase.auth.getUser();
    if (!user) return null;
    return { id: user.id, email: user.email ?? null };
  }
}
