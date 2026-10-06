import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';

export const dynamic = 'force-dynamic';

/**
 * Gate do departamento Comercial, no SERVIDOR, para todas as rotas /comercial/**.
 * Admin e dev sempre; gestor/vendedor do Comercial só com a flag NEXT_PUBLIC_COMERCIAL_VENDEDORES (padrão
 * desligada) — regra em `podeVerDepartamento`/`ehDoComercial`, espelho de `crm.eh_comercial()`. Cada page repete a
 * regra (layout e page renderizam em paralelo no Next). A fronteira de dado é a RLS do schema crm.
 */
export default async function ComercialLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'comercial', ACESSO_DEPARTAMENTOS)) redirect('/');
  return <>{children}</>;
}
