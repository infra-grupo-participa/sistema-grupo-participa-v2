import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { hojeSP } from '@/modules/marketing/mensageria/domain/mensageria';
import { MensageriaClient } from '@/modules/marketing/mensageria/ui/MensageriaClient';

export const dynamic = 'force-dynamic';

/**
 * Marketing > Mensageria (schema mkt_mensageria, migration 20261005n). Só admin e dev, como o Marketing inteiro
 * (decisão provisória). A page repete a regra do layout (layout e page renderizam em paralelo no Next); a trava
 * real é a do banco (mkt.pode_ver nas funções public.mkt_msg_*). Nome de quem dispara e "hoje" (São Paulo)
 * saem daqui, uma vez, e descem por prop: nenhuma consulta de identidade no cliente.
 */
export default async function MensageriaPage() {
  const user = await getCurrentUser();
  if (!user || !podeVerDepartamento(user, 'marketing')) redirect('/');
  return <MensageriaClient hoje={hojeSP()} nomeUsuario={user.nome} />;
}
