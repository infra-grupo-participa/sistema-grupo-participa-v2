import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeEditarArea, podeVerDepartamento } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { WebClient } from '@/modules/marketing/web/ui/WebClient';

export const dynamic = 'force-dynamic';

/**
 * Marketing > Web (o Radar do Luiz dentro da central; migration 20261006f). Só admin e dev, como o Marketing inteiro.
 * A page repete a regra do layout (layout e page renderizam em paralelo no Next); a trava real é a do banco
 * (mkt.pode_ver('mkt_web') nas funções public.mkt_web_*). Código em web/modules/marketing/web/.
 */
export default async function WebPage() {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'marketing', ACESSO_DEPARTAMENTOS)) redirect('/');
  return <WebClient canEdit={podeEditarArea(user, 'marketing', 'web', ACESSO_DEPARTAMENTOS)} />;
}
