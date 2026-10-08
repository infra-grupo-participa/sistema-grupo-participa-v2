import { publicAppBaseUrl } from '@/shared/infrastructure/http/security';
import { metadadosRecurso } from '@/modules/comercial/domain/mcp-oauth';
import { jsonOAuth, preflightOAuth } from '@/modules/comercial/infrastructure/oauth-http';

// RFC 9728 — metadados do recurso protegido /api/mcp. Atende a raiz e a forma com caminho
// (/.well-known/oauth-protected-resource/api/mcp), que é a que o cliente MCP tenta primeiro. Público (proxy).
export function GET() {
  return jsonOAuth(metadadosRecurso(publicAppBaseUrl()));
}

export const OPTIONS = preflightOAuth;
