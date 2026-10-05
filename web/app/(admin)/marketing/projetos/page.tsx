import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { ProjetosPaginasClient } from '@/modules/marketing/projetos/ui/ProjetosPaginasClient';

export const dynamic = 'force-dynamic';

/**
 * Marketing > Projetos e páginas (base compartilhada: mkt.projetos e mkt.paginas, migration 20261005m).
 * Só admin e dev, como o Marketing inteiro. A page repete a regra do layout (layout e page renderizam em paralelo
 * no Next); a trava real é a do banco (mkt.pode_ver nas funções public.mkt_*).
 */
export default async function ProjetosPaginasPage() {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'marketing')) redirect('/');
  return <ProjetosPaginasClient />;
}
