import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { AppShell } from '@/shared/ui/shell/AppShell';

/** Layout autenticado. O proxy já barra anônimos; aqui garantimos o usuário canônico. */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  return <AppShell user={user}>{children}</AppShell>;
}
