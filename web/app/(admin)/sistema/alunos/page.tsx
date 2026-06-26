import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeEditar } from '@/shared/domain/auth';
import { AlunosClient } from '@/modules/alunos/ui/AlunosClient';

export const dynamic = 'force-dynamic';

export default async function AlunosPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  // Base de Alunos é adminOnly (REPORTS.alunos).
  if (!ehAdminOuAcima(user)) redirect('/');
  return <AlunosClient canEdit={ehAdminOuAcima(user) || podeEditar(user, 'centro_controle')} />;
}
