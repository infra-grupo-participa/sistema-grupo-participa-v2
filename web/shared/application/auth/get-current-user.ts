import { buildGpUser, type GpUser } from '@/shared/domain/auth';
import type { AuthGateway, ProfileRepository } from './ports';

/**
 * Caso de uso: resolve o usuário canônico autenticado.
 * Depende só dos ports — não conhece Supabase nem Next.
 */
export class GetCurrentUser {
  constructor(
    private readonly auth: AuthGateway,
    private readonly profiles: ProfileRepository,
  ) {}

  async execute(): Promise<GpUser | null> {
    const authUser = await this.auth.getAuthUser();
    if (!authUser) return null;

    const perfil = await this.profiles.findById(authUser.id);
    if (!perfil) {
      // Sessão válida sem perfil → usuário mínimo (cargo visualizador via fallback).
      return buildGpUser({ id: authUser.id, email: authUser.email });
    }
    return buildGpUser(perfil);
  }
}
