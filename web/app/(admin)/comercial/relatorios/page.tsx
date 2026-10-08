import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { acessoComercial } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { RelatoriosClient } from '@/modules/comercial/ui/relatorios/RelatoriosClient';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  // Só quem vê o CRM (ou o nível de relatórios). Quem só pede estratégia não entra: as RPCs daqui exigem o Comercial (42501).
  const acesso = acessoComercial(user, ACESSO_DEPARTAMENTOS);
  if (acesso !== 'completo' && acesso !== 'relatorios') redirect('/');
  return <RelatoriosClient />;
}
