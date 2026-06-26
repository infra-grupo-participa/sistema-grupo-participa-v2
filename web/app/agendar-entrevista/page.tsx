import { AgendarEntrevistaClient } from '@/modules/placas/ui/AgendarEntrevistaClient';
import { isUuid } from '@/shared/infrastructure/http/validation';

export const dynamic = 'force-dynamic';

export default async function AgendarEntrevistaPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token } = await searchParams;
  const initialToken = token && isUuid(token) ? token.toLowerCase() : '';
  return <AgendarEntrevistaClient initialToken={initialToken} />;
}
