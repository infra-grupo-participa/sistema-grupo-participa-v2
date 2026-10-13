import { notFound, redirect } from 'next/navigation';
import { getCurrentUser, getCurrentUserAccess } from '@/shared/composition/server-container';
import { podeVerDepartamento, temCapacidade } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { buscarDashboard } from '@/modules/infra/dados/domain/registro';
import { DashboardPresencialClient } from '@/modules/infra/dados/ui/DashboardPresencialClient';
import { DashboardBlackClient } from '@/modules/infra/black/ui/DashboardBlackClient';
import { lerRecorte } from '@/modules/infra/black/domain/recorte';

export const dynamic = 'force-dynamic';

type Busca = Record<string, string | string[] | undefined>;

export default async function DashboardCsmPage({ params, searchParams }: { params: Promise<{ chave: string }>; searchParams: Promise<Busca> }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'infra', ACESSO_DEPARTAMENTOS)) redirect('/');
  if (ACESSO_DEPARTAMENTOS.acessoV2 && !temCapacidade(user, 'financeiro.ver', ACESSO_DEPARTAMENTOS)) redirect('/infra/dashboards/csm');
  const { chave } = await params;
  const dashboard = buscarDashboard(chave);
  if (!dashboard) notFound();
  const acesso = ACESSO_DEPARTAMENTOS.acessoV2 ? user?.acesso : await getCurrentUserAccess();
  if (dashboard.modelo === 'jornada-captacao') {
    const busca = await searchParams;
    const relogio = typeof busca.relogio === 'string' ? busca.relogio : null;
    return <DashboardBlackClient chave={dashboard.chave} titulo={dashboard.titulo} relogio={relogio} recorteInicial={lerRecorte(busca)} isMaster={acesso?.master === true} />;
  }
  return <DashboardPresencialClient chave={dashboard.chave} isMaster={acesso?.master === true} />;
}
