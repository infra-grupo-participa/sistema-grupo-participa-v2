import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';

export const dynamic = 'force-dynamic';

/**
 * Gate do departamento Comercial, no SERVIDOR, para todas as rotas /comercial/**. Só admin e dev, a mesma regra do
 * Marketing, até os níveis de acesso por departamento serem desenhados. A trava real é a do banco (pessoas.pode_ver nas
 * funções public.pessoas_* e public.crm_*, migration 20261005o); o gancho para liberar uma área é pessoas.config.
 */
export default async function ComercialLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'comercial')) redirect('/');
  return <>{children}</>;
}
