import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { acessoComercial } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { RegistroClient } from '@/modules/comercial/ui/registro/RegistroClient';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (acessoComercial(user, ACESSO_DEPARTAMENTOS) !== 'completo') redirect('/');
  return <RegistroClient />;
}
