import { publicAppBaseUrl } from '@/shared/infrastructure/http/security';
import { metadadosServidor } from '@/modules/comercial/domain/mcp-oauth';
import { jsonOAuth, preflightOAuth } from '@/modules/comercial/infrastructure/oauth-http';

// RFC 8414 — metadados do servidor de autorização (o próprio app; ver modules/comercial/domain/mcp-oauth.ts). Público.
export function GET() {
  return jsonOAuth(metadadosServidor(publicAppBaseUrl()));
}

export const OPTIONS = preflightOAuth;
