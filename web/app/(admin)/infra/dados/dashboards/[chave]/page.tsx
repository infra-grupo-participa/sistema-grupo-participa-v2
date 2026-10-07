import { notFound, redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { buscarDashboard } from '@/modules/infra/dados/domain/registro';
import { DashboardPresencialClient } from '@/modules/infra/dados/ui/DashboardPresencialClient';

export const dynamic = 'force-dynamic';

export default async function DashboardPage({ params }: { params: Promise<{ chave: string }> }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'infra')) redirect('/');
  const { chave } = await params;
  const dashboard = buscarDashboard(chave);
  if (!dashboard) notFound();
  return <DashboardPresencialClient chave={dashboard.chave} />;
}
