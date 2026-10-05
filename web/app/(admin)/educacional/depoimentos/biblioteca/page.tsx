import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima } from '@/shared/domain/auth';
import { ParaCopyClient } from '@/modules/depoimentos/ui/ParaCopyClient';

export const dynamic = 'force-dynamic';

export default async function ParaCopyPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!ehAdminOuAcima(user)) redirect('/');
  return <ParaCopyClient />;
}
