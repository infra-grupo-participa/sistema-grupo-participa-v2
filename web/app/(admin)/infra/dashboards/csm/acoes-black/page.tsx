import { redirect } from 'next/navigation';
import { getCurrentUser, getCurrentUserAccess } from '@/shared/composition/server-container';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { temCapacidade } from '@/shared/domain/departamentos';
import type { Metadata } from 'next';
import { DashboardAcoesBlackClient } from '@/modules/infra/acoes/ui/DashboardAcoesBlackClient';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = { title: 'Ações de Renovação da Black Friday | Grupo Participa' };

export default async function AcoesBlackPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  const acesso = ACESSO_DEPARTAMENTOS.acessoV2 ? user?.acesso : await getCurrentUserAccess();
  return <DashboardAcoesBlackClient isMaster={acesso?.master === true} podeVerContato={temCapacidade(user, 'contato.ver', ACESSO_DEPARTAMENTOS)} />;
}
