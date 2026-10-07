import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeEditarArea, podeVerDepartamento, temCapacidade } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { TrafegoClient } from '@/modules/marketing/trafego/ui/TrafegoClient';
import { TrafegoSemFinanceiro } from '@/modules/marketing/trafego/ui/TrafegoSemFinanceiro';

export const dynamic = 'force-dynamic';

/**
 * Marketing > Tráfego: a Central do Tráfego (etapa 1; migration 20261006g). Só admin e dev, como o Marketing inteiro.
 * A page repete a regra do layout (layout e page renderizam em paralelo no Next); a trava real é a do banco
 * (mkt.pode_ver('mkt_trafego') nas funções public.trafego_*). Código em web/modules/marketing/trafego/.
 */
export default async function TrafegoPage() {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'marketing', ACESSO_DEPARTAMENTOS)) redirect('/');
  const canEdit = podeEditarArea(user, 'marketing', 'trafego', ACESSO_DEPARTAMENTOS);
  if (ACESSO_DEPARTAMENTOS.acessoV2 && !temCapacidade(user, 'financeiro.ver', ACESSO_DEPARTAMENTOS)) return <TrafegoSemFinanceiro canEdit={canEdit} />;
  return <TrafegoClient canEdit={canEdit} />;
}
