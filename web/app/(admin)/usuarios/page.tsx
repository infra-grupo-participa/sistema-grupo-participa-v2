import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima } from '@/shared/domain/auth';
import { UsuariosClient } from '@/modules/usuarios/ui/UsuariosClient';

export const dynamic = 'force-dynamic';

export default async function UsuariosPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!ehAdminOuAcima(user)) redirect('/');
  return <UsuariosClient meuCargo={user.cargo} />;
}
