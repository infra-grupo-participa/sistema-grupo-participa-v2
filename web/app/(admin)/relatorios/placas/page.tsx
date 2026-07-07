import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeVer, temFuncao } from '@/shared/domain/auth';
import { redirect } from 'next/navigation';
import { RelatorioPlacasClient } from '@/modules/placas/ui/admin/RelatorioPlacasClient';

export const dynamic = 'force-dynamic';

export default async function RelatorioPlacasPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  // Modelo aberto v2: qualquer autenticado vê (3.2.1). Operar o fluxo exige placas.operar (3.2.2)
  // — hm_liberar (3.2.3) não dá edição do fluxo de auditoria.
  if (!podeVer(user, 'placas')) redirect('/');
  return <RelatorioPlacasClient canEdit={ehAdminOuAcima(user) || temFuncao(user, 'placas.operar')} />;
}
