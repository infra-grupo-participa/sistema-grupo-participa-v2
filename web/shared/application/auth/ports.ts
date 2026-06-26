import type { PerfilData } from '@/shared/domain/auth';

/** Identidade autenticada mínima (vinda do provedor de auth). */
export interface AuthUser {
  id: string;
  email: string | null;
}

/** Port: provedor de autenticação (implementado por adapter Supabase). */
export interface AuthGateway {
  getAuthUser(): Promise<AuthUser | null>;
}

/** Port: leitura de perfis (implementado por adapter Supabase). */
export interface ProfileRepository {
  findById(id: string): Promise<PerfilData | null>;
}
