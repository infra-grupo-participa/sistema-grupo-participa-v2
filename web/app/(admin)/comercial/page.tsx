import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { acessoComercial } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { InicioClient } from '@/modules/comercial/ui/inicio/InicioClient';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  const acesso = acessoComercial(user, ACESSO_DEPARTAMENTOS);
  // Quem só pede estratégia entra direto na tela dele (o cartão da home e o menu apontam para /comercial).
  if (acesso === 'estrategias') redirect('/comercial/estrategias');
  if (acesso !== 'completo') redirect('/');
  return <InicioClient />;
}
