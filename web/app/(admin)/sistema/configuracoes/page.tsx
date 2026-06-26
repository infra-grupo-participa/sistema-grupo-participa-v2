import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ConfiguracoesClient } from './ConfiguracoesClient';

export const dynamic = 'force-dynamic';

export default async function ConfiguracoesPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  return <ConfiguracoesClient user={user} />;
}
