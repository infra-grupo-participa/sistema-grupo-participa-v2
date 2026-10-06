import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { podeVerDepartamento } from '@/shared/domain/departamentos';
import { EmBreve } from '@/shared/ui/departamentos/EmBreve';

export const dynamic = 'force-dynamic';

/**
 * Social selling (futuro): conectar perfis do Instagram (Marcio, Elaine, outros), ler os comentários e
 * cadastrar a pessoa como lead com um clique. Depende do backend (API do Instagram). Ver docs/projetos/comercial/plano-front.md.
 */
export default async function Page() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  if (!podeVerDepartamento(user, 'comercial')) redirect('/');
  return <EmBreve titulo="Social selling" descricao="Conectar perfis do Instagram, ler os comentários e transformar quem comenta em lead com um clique." ico="share" />;
}
