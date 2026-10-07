import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';

export const dynamic = 'force-dynamic';

export default async function InfraLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!podeVerDepartamento(user, 'infra', ACESSO_DEPARTAMENTOS)) redirect('/');
  return <>{children}</>;
}
