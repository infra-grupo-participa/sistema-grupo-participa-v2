import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { ComercialClient } from '@/modules/comercial/ui/ComercialClient';

export const dynamic = 'force-dynamic';

/**
 * Comercial: CRM (ativação, vendas, recuperação de carrinho e de venda) e base única de pessoas (migration 20261005o).
 * Só admin e dev. A page repete a regra do layout (layout e page renderizam em paralelo no Next). Código em
 * web/modules/comercial/.
 */
export default async function ComercialPage() {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'comercial')) redirect('/');
  return <ComercialClient />;
}
