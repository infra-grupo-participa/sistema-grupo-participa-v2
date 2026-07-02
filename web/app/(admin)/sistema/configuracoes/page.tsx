import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ConfiguracoesClient } from './ConfiguracoesClient';

export const dynamic = 'force-dynamic';

export default async function ConfiguracoesPage() {
  // Sem gate de cargo por design: a página edita apenas o próprio perfil (nome/avatar/tema);
  // o enforcement real é o RLS de `perfis` (update restrito à própria linha + grants de coluna).
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  return <ConfiguracoesClient user={user} />;
}
