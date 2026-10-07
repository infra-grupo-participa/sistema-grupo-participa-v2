import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { acessoComercial } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';

export const dynamic = 'force-dynamic';

/**
 * Gate do departamento Comercial, no SERVIDOR, para todas as rotas /comercial/**.
 * Entra quem vê o CRM (`podeVerDepartamento`: admin e dev; com a flag NEXT_PUBLIC_COMERCIAL_VENDEDORES também gestor/
 * vendedor do Comercial) OU quem pede estratégia (função `comercial.solicitar_estrategia`, 07/10/2026). Este segundo grupo
 * só abre /comercial/estrategias: toda outra page do Comercial repete `podeVerDepartamento` e devolve para a home
 * (layout e page renderizam em paralelo no Next). A fronteira de dado é a RLS/guarda do schema crm.
 */
export default async function ComercialLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!acessoComercial(user, ACESSO_DEPARTAMENTOS)) redirect('/');
  return <>{children}</>;
}
