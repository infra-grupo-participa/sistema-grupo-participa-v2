import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima } from '@/shared/domain/auth';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { ParaCopyClient } from '@/modules/depoimentos/ui/ParaCopyClient';

export const dynamic = 'force-dynamic';

export default async function ParaCopyPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!ACESSO_DEPARTAMENTOS.acessoV2 && !ehAdminOuAcima(user)) redirect('/');
  return <ParaCopyClient />;
}
