import { notFound, redirect } from 'next/navigation';
import { getCurrentUser, getCurrentUserAccess } from '@/shared/composition/server-container';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { podeVerDepartamento, temCapacidade } from '@/shared/domain/departamentos';
import { buscarAtm } from '@/modules/infra/atm/domain/registro';
import { SeminarioAtmClient } from '@/modules/infra/atm/ui/SeminarioAtmClient';

export const dynamic = 'force-dynamic';

export default async function SeminarioAtmPage({ params }: { params: Promise<{ chave: string }> }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'infra', ACESSO_DEPARTAMENTOS)) redirect('/');
  if (ACESSO_DEPARTAMENTOS.acessoV2 && !temCapacidade(user, 'financeiro.ver', ACESSO_DEPARTAMENTOS)) redirect('/infra/dashboards/escritorio');
  const { chave } = await params;
  const projeto = buscarAtm(chave);
  if (!projeto) notFound();
  const acesso = ACESSO_DEPARTAMENTOS.acessoV2 ? user?.acesso : await getCurrentUserAccess();
  return <SeminarioAtmClient projeto={projeto} isMaster={acesso?.master === true} />;
}
