import { SolicitarPlacaClient } from '@/modules/placas/ui/SolicitarPlacaClient';
import { isUuid } from '@/shared/infrastructure/http/validation';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { readPlacaPublicConfig } from '@/modules/placas/infrastructure/placa-public-config';
import { resolveNivelFaixas, resolveFormTextos } from '@/modules/placas/domain/config';
import { TURMAS } from '@/modules/placas/ui/solicitar-placa-constants';

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
  // readPlacasConfig: 1 consulta por carregamento (como antes). readPlacaPublicConfig: cacheada 1 h.
  const [cfg, pub] = await Promise.all([readPlacasConfig(), readPlacaPublicConfig()]);
  const config = {
    niveis: resolveNivelFaixas(cfg.nivel_faixas),
    textos: resolveFormTextos(cfg.form_textos),
    turmas: pub.turmas ?? TURMAS,
    ajudaHref: pub.ajudaHref,
  };
  return <SolicitarPlacaClient initialToken={initialToken} config={config} />;
}
