import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';

export const dynamic = 'force-dynamic';

/**
 * Gate do departamento Comercial, no SERVIDOR, para todas as rotas /comercial/**.
 * Só admin e dev enquanto o CRM roda com dados de demonstração. Cada page repete a regra (layout e page
 * renderizam em paralelo no Next). Quando o backend entrar: acesso por setor + RLS negando o visualizador.
 */
export default async function ComercialLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'comercial')) redirect('/');
  return <>{children}</>;
}
