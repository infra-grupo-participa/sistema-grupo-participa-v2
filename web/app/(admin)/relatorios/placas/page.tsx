import { getCurrentUser } from '@/shared/composition/server-container';
import { podeEditar, podeVer } from '@/shared/domain/auth';
import { redirect } from 'next/navigation';
import { RelatorioPlacasClient } from '@/modules/placas/ui/admin/RelatorioPlacasClient';

export const dynamic = 'force-dynamic';

export default async function RelatorioPlacasPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  // Modelo aberto v2: qualquer autenticado vê; edição gated por podeEditar('placas').
  if (!podeVer(user, 'placas')) redirect('/');
  return <RelatorioPlacasClient canEdit={podeEditar(user, 'placas')} />;
}
