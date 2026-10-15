import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';

export const dynamic = 'force-dynamic';

/**
 * Gate do departamento Financeiro, no SERVIDOR, para todas as rotas /financeiro/** (15/10/2026: o módulo Contas a
 * Receber virou o departamento). `podeVerDepartamento('financeiro')` é a régua do módulo: v1 = `podeVerFinanceiro`
 * (visualizador NÃO); v2 = capacidade `financeiro.ver`. A sidebar e a home escondem/bloqueiam o cartão com a mesma
 * regra. Toda page daqui repete a regra (layout e page renderizam em paralelo no Next) e o banco é a fronteira
 * (gp_pode_ver_financeiro / RLS).
 */
export default async function FinanceiroLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!podeVerDepartamento(user, 'financeiro', ACESSO_DEPARTAMENTOS)) redirect('/');
  return <>{children}</>;
}
