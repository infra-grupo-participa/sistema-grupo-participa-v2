import { buildGpUser, ehEmailDaEquipe, type GpUser } from '@/shared/domain/auth';
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
    // `auth.users` é compartilhada pelos 7 sistemas do grupo: ter sessão válida NÃO
    // significa ser equipe. Sem perfil → não entra (antes caía num usuário mínimo
    // com cargo `visualizador`, e `podeVer()` libera visualizador em qualquer setor).
    if (!perfil) return null;
    // O sistema interno é só do domínio da equipe.
    if (!ehEmailDaEquipe(perfil.email)) return null;
    // Perfil existe mas ainda não foi liberado por um admin.
    if (perfil.status !== 'ativo') return null;
    return buildGpUser(perfil);
  }
}
