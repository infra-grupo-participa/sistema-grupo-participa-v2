import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeEditar, temFuncao } from '@/shared/domain/auth';
import { DepoimentosClient } from '@/modules/depoimentos/ui/DepoimentosClient';
import { podeEditarArea } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';

export const dynamic = 'force-dynamic';

export default async function DepoimentosPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!ACESSO_DEPARTAMENTOS.acessoV2 && !ehAdminOuAcima(user)) redirect('/');
  const canEdit = ACESSO_DEPARTAMENTOS.acessoV2 ? podeEditarArea(user, 'educacional', null, ACESSO_DEPARTAMENTOS) : ehAdminOuAcima(user) || podeEditar(user, 'depoimentos') || temFuncao(user, 'depoimentos.moderador');
  return <DepoimentosClient canEdit={canEdit} />;
}
