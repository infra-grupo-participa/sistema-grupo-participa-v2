import { getCurrentUser } from '@/shared/composition/server-container';
import { redirect } from 'next/navigation';
import { podeVerRemocao } from '@/modules/remocao-acessos/domain/acesso';
import { RemocaoClient } from '@/modules/remocao-acessos/ui/RemocaoClient';

export const dynamic = 'force-dynamic';

export default async function RemocoesPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  // O que cada pessoa pode marcar é decidido no banco (ra_marcar_item), por item.
  if (!podeVerRemocao(user)) redirect('/');
  return <RemocaoClient />;
}
