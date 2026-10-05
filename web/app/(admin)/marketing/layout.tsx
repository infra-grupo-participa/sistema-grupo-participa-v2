import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';

export const dynamic = 'force-dynamic';

/**
 * Gate do departamento Marketing, no SERVIDOR, para todas as rotas /marketing/**.
 * Só admin e dev até os níveis de acesso por departamento serem desenhados (decisão do Victor, 05/10/2026):
 * visualizador geral, gestor e operador voltam para o Início. A sidebar e a home escondem/bloqueiam o
 * cartão com a mesma regra (`podeVerDepartamento`).
 *
 * ⚠️ Quando uma área ganhar dado de verdade: a page dela também chama a regra (layout e page renderizam em
 * paralelo no Next) e a RLS das tabelas novas precisa negar o visualizador do mesmo jeito.
 */
export default async function MarketingLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'marketing')) redirect('/');
  return <>{children}</>;
}
