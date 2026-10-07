// Quem vê o calendário da empresa: toda a equipe (espelha public.gp_eh_equipe(), a guarda da RPC).
// Usuário de outro sistema que divide o login (rede, metodo, workbook...) não é equipe.
import { ehEmailDaEquipe, type GpUser } from '@/shared/domain/auth/gp-user';

export function podeVerCalendario(user: Pick<GpUser, 'email' | 'status'> | null | undefined): boolean {
  return !!user && user.status === 'ativo' && ehEmailDaEquipe(user.email);
}
