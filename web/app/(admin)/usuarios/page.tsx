import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima } from '@/shared/domain/auth';
import { UsuariosClient } from '@/modules/usuarios/ui/UsuariosClient';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';

export const dynamic = 'force-dynamic';

export default async function UsuariosPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (ACESSO_DEPARTAMENTOS.acessoV2 ? !user.acesso?.master : !ehAdminOuAcima(user)) redirect('/');
  return <UsuariosClient meuCargo={user.cargo} acessoV2={ACESSO_DEPARTAMENTOS.acessoV2} />;
}
