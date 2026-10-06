import { createHmac } from 'node:crypto';

// JWT curto do DONO do token MCP, para as RPCs crm_* rodarem sob RLS como ele (nunca service role para agir).
// HS256 com o segredo JWT do projeto (env SUPABASE_JWT_SECRET, só servidor). A claim gp_canal='mcp' faz o crm.tg_log
// gravar autor_tipo='mcp' (migration 20261006050132); o usuário não consegue pôr essa claim no JWT da sessão normal.

export const VALIDADE_JWT_MCP_S = 300;

export interface ClaimsMcp {
  iss: string;
  sub: string;
  aud: 'authenticated';
  role: 'authenticated';
  email: string;
  iat: number;
  exp: number;
  is_anonymous: false;
  gp_canal: 'mcp';
  gp_mcp_token: string;
}

const b64url = (b: Buffer | string) => Buffer.from(b).toString('base64url');

export function montarClaimsMcp(
  d: { perfilId: string; email: string; tokenId: string },
  supabaseUrl: string,
  agora: Date = new Date(),
): ClaimsMcp {
  const iat = Math.floor(agora.getTime() / 1000);
  return {
    iss: `${supabaseUrl.replace(/\/+$/, '')}/auth/v1`,
    sub: d.perfilId,
    aud: 'authenticated',
    role: 'authenticated',
    email: d.email,
    iat,
    exp: iat + VALIDADE_JWT_MCP_S,
    is_anonymous: false,
    gp_canal: 'mcp',
    gp_mcp_token: d.tokenId,
  };
}

export function assinarJwtHs256(payload: object, segredo: string): string {
  if (!segredo) throw new Error('Segredo JWT ausente.');
  const cab = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const corpo = b64url(JSON.stringify(payload));
  const assinatura = createHmac('sha256', segredo).update(`${cab}.${corpo}`).digest('base64url');
  return `${cab}.${corpo}.${assinatura}`;
}
