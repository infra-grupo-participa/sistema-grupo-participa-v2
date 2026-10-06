import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { TrafegoClient } from '@/modules/marketing/trafego/ui/TrafegoClient';

export const dynamic = 'force-dynamic';

/**
 * Marketing > Tráfego: a Central do Tráfego (etapa 1; migration 20261005p). Só admin e dev, como o Marketing inteiro.
 * A page repete a regra do layout (layout e page renderizam em paralelo no Next); a trava real é a do banco
 * (mkt.pode_ver('mkt_trafego') nas funções public.trafego_*). Código em web/modules/marketing/trafego/.
 */
export default async function TrafegoPage() {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'marketing')) redirect('/');
  return <TrafegoClient />;
}
