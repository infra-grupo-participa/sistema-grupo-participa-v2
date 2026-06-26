import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeEditar, temFuncao } from '@/shared/domain/auth';
import { DepoimentosClient } from '@/modules/depoimentos/ui/DepoimentosClient';

export const dynamic = 'force-dynamic';

export default async function DepoimentosPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!ehAdminOuAcima(user)) redirect('/'); // depoimentos é adminOnly
  const canEdit = ehAdminOuAcima(user) || podeEditar(user, 'depoimentos') || temFuncao(user, 'depoimentos.moderador');
  return <DepoimentosClient canEdit={canEdit} />;
}
