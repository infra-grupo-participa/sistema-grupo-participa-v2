import { notFound, redirect } from 'next/navigation';
import { getCurrentUser, getCurrentUserAccess } from '@/shared/composition/server-container';
import { podeVerDepartamento, temCapacidade } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { buscarDashboard } from '@/modules/infra/dados/domain/registro';
import { DashboardPresencialClient } from '@/modules/infra/dados/ui/DashboardPresencialClient';

export const dynamic = 'force-dynamic';

export default async function DashboardPage({ params }: { params: Promise<{ chave: string }> }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'infra', ACESSO_DEPARTAMENTOS)) redirect('/');
  if (ACESSO_DEPARTAMENTOS.acessoV2 && !temCapacidade(user, 'financeiro.ver', ACESSO_DEPARTAMENTOS)) redirect('/infra/dados/dashboards');
  const { chave } = await params;
  const dashboard = buscarDashboard(chave);
  if (!dashboard) notFound();
  const acesso = ACESSO_DEPARTAMENTOS.acessoV2 ? user?.acesso : await getCurrentUserAccess();
  return <DashboardPresencialClient chave={dashboard.chave} isMaster={acesso?.master === true} />;
}
