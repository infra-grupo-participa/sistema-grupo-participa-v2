import { SolicitarPlacaClient } from '@/modules/placas/ui/SolicitarPlacaClient';
import { isUuid } from '@/shared/infrastructure/http/validation';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { resolveNivelFaixas, resolveFormTextos } from '@/modules/placas/domain/config';

export const dynamic = 'force-dynamic';

export const metadata = {
  title: 'Solicitar Placa — Time Holding Brasil',
  description: 'Solicitação de Placa — Time Holding Brasil',
};

export default async function SolicitarPlacaPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token } = await searchParams;
  const initialToken = token && isUuid(token) ? token.toLowerCase() : '';
  const cfg = await readPlacasConfig();
  const config = {
    niveis: resolveNivelFaixas(cfg.nivel_faixas),
    textos: resolveFormTextos(cfg.form_textos),
  };
  return <SolicitarPlacaClient initialToken={initialToken} config={config} />;
}
''