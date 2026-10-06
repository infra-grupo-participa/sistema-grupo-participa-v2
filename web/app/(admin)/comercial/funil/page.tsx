import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { FunilClient } from '@/modules/comercial/ui/funil/FunilClient';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!podeVerDepartamento(user, 'comercial')) redirect('/');
  return <FunilClient />;
}
