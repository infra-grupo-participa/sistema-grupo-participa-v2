import { SolicitarPlacaClient } from '@/modules/placas/ui/SolicitarPlacaClient';
import { isUuid } from '@/shared/infrastructure/http/validation';

export const dynamic = 'force-dynamic';

export default async function SolicitarPlacaPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token } = await searchParams;
  const initialToken = token && isUuid(token) ? token.toLowerCase() : '';
  return <SolicitarPlacaClient initialToken={initialToken} />;
}
