import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';

export const dynamic = 'force-dynamic';

export default async function InfraLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  return <>{children}</>;
}
