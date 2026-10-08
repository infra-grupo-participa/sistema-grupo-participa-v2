// OAuth 2.1 mínimo do MCP do Comercial (para o claude.ai conectar). Domínio puro: sem Next, sem Supabase, sem crypto.
//
// Por que próprio e não o OAuth do Supabase Auth: lá a tela de consentimento = Site URL do projeto + caminho, e o Site
// URL é de outro sistema do grupo (sip.timeholdingbrasil.com.br). Detalhes: docs/projetos/comercial/mcp.md §5.
//
// Regras (todas também conferidas no banco, migration 20261008150823):
//   - cliente público (sem segredo), registrado dinamicamente (RFC 7591) com redirect na LISTA FECHADA abaixo;
//   - authorization code + PKCE S256 obrigatório; código de uso único, 5 min, só hash no banco;
//   - access token = token gpc_ comum (1 h) em crm.mcp_token; refresh gpr_ rotativo (30 d, teto 180 d);
//   - consentimento explícito na tela /oauth/autorizar, só para quem é do Comercial.

export const ESCOPOS_OAUTH = ['ler', 'operar'] as const;
export type EscopoOAuth = (typeof ESCOPOS_OAUTH)[number];
export const VALIDADE_ACCESS_S = 3600;

/** Callbacks oficiais do Claude (claude.ai, app do celular e Claude Desktop usam o mesmo). */
export const REDIRECTS_CLAUDE = ['https://claude.ai/api/mcp/auth_callback', 'https://claude.com/api/mcp/auth_callback'] as const;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CHALLENGE = /^[A-Za-z0-9_-]{43}$/;
const VERIFIER = /^[A-Za-z0-9\-._~]{43,128}$/;
const CODIGO = /^[0-9a-f]{64}$/;
const REFRESH = /^gpr_[0-9a-f]{64}$/;

/**
 * Redirect aceito: os callbacks do Claude (exatos) ou loopback http (Claude Code e Claude Desktop local abrem um
 * servidor em localhost numa porta qualquer — RFC 8252 §7.3). Nada de outro host: é o que impede um "cliente" falso
 * de receber o código de alguém do time.
 */
export function redirectPermitido(uri: unknown): boolean {
  if (typeof uri !== 'string' || uri.length > 300) return false;
  if ((REDIRECTS_CLAUDE as readonly string[]).includes(uri)) return true;
  let u: URL;
  try {
    u = new URL(uri);
  } catch {
    return false;
  }
  if (u.protocol !== 'http:' || u.username || u.password || u.hash) return false;
  return u.hostname === 'localhost' || u.hostname === '127.0.0.1' || u.hostname === '[::1]';
}

export type ErroOAuth = { ok: false; erro: string; descricao: string };

export interface Registro {
  ok: true;
  nome: string;
  redirects: string[];
}

/** Pedido de registro dinâmico (RFC 7591). Método de autenticação: sempre 'none' (cliente público + PKCE). */
export function validarRegistro(corpo: unknown): Registro | ErroOAuth {
  if (!corpo || typeof corpo !== 'object' || Array.isArray(corpo)) {
    return { ok: false, erro: 'invalid_client_metadata', descricao: 'Corpo precisa ser objeto JSON.' };
  }
  const c = corpo as Record<string, unknown>;
  const uris = c.redirect_uris;
  if (!Array.isArray(uris) || uris.length < 1 || uris.length > 5 || !uris.every((u) => typeof u === 'string')) {
    return { ok: false, erro: 'invalid_redirect_uri', descricao: 'redirect_uris: de 1 a 5 URLs.' };
  }
  if (!uris.every(redirectPermitido)) {
    return { ok: false, erro: 'invalid_redirect_uri', descricao: 'Só o Claude (claude.ai/claude.com) ou localhost podem se registrar.' };
  }
  const grants = c.grant_types;
  if (grants !== undefined && (!Array.isArray(grants) || !grants.every((g) => g === 'authorization_code' || g === 'refresh_token'))) {
    return { ok: false, erro: 'invalid_client_metadata', descricao: 'grant_types aceitos: authorization_code, refresh_token.' };
  }
  const tipos = c.response_types;
  if (tipos !== undefined && (!Array.isArray(tipos) || !tipos.every((t) => t === 'code'))) {
    return { ok: false, erro: 'invalid_client_metadata', descricao: 'response_types aceito: code.' };
  }
  const nome = typeof c.client_name === 'string' && c.client_name.trim() ? c.client_name.trim().slice(0, 100) : 'Cliente MCP';
  return { ok: true, nome, redirects: Array.from(new Set(uris as string[])) };
}

export interface PedidoAutorizacao {
  clienteId: string;
  redirectUri: string;
  challenge: string;
  state: string | null;
  /** O que o cliente pediu (a pessoa confirma na tela). Sem scope = ler + operar. */
  escopos: EscopoOAuth[];
}

export type LeituraAutorizacao =
  | { ok: true; pedido: PedidoAutorizacao }
  /** `voltar` = dá para devolver o erro ao cliente pelo redirect (depois de conferir que o redirect é do cliente). */
  | { ok: false; descricao: string; voltar: { redirectUri: string; erro: string; state: string | null } | null };

const recursoIgual = (a: string, b: string) => a.replace(/\/+$/, '') === b.replace(/\/+$/, '');

/** Lê os parâmetros de GET /oauth/autorizar (RFC 6749 §4.1.1 + PKCE + RFC 8707). */
export function lerPedidoAutorizacao(q: Record<string, string | undefined>, recurso: string): LeituraAutorizacao {
  const clienteId = q.client_id ?? '';
  const redirectUri = q.redirect_uri ?? '';
  if (!UUID.test(clienteId) || !redirectPermitido(redirectUri)) {
    return { ok: false, descricao: 'Pedido de conexão inválido (cliente ou endereço de retorno).', voltar: null };
  }
  const state = q.state && q.state.length <= 500 ? q.state : null;
  const voltar = (erro: string, descricao: string): LeituraAutorizacao => ({ ok: false, descricao, voltar: { redirectUri, erro, state } });
  if (q.response_type !== 'code') return voltar('unsupported_response_type', 'Só response_type=code.');
  if (q.code_challenge_method !== 'S256' || !CHALLENGE.test(q.code_challenge ?? '')) {
    return voltar('invalid_request', 'PKCE S256 obrigatório.');
  }
  if (q.resource && !recursoIgual(q.resource, recurso)) return voltar('invalid_target', 'Recurso desconhecido.');
  const pedidos = (q.scope ?? '').split(/\s+/).filter(Boolean);
  const escopos: EscopoOAuth[] = pedidos.length === 0 || pedidos.includes('operar') ? ['ler', 'operar'] : ['ler'];
  return { ok: true, pedido: { clienteId: clienteId.toLowerCase(), redirectUri, challenge: q.code_challenge as string, state, escopos } };
}

/** URL de volta ao cliente com os parâmetros na query (preserva a query que o redirect já tiver). */
export function urlDeRetorno(redirectUri: string, params: Record<string, string | null | undefined>): string {
  const u = new URL(redirectUri);
  for (const [k, v] of Object.entries(params)) if (v) u.searchParams.set(k, v);
  return u.toString();
}

export type PedidoToken =
  | { ok: true; tipo: 'codigo'; codigo: string; clienteId: string; redirectUri: string; verificador: string }
  | { ok: true; tipo: 'refresh'; refresh: string; clienteId: string }
  | ErroOAuth;

/** Corpo de POST /api/oauth/token (form-urlencoded ou JSON, já virado objeto de strings). */
export function lerPedidoToken(f: Record<string, string | undefined>): PedidoToken {
  const clienteId = (f.client_id ?? '').toLowerCase();
  if (!UUID.test(clienteId)) return { ok: false, erro: 'invalid_client', descricao: 'client_id ausente ou inválido.' };
  if (f.grant_type === 'authorization_code') {
    if (!CODIGO.test(f.code ?? '')) return { ok: false, erro: 'invalid_grant', descricao: 'Código inválido.' };
    if (!redirectPermitido(f.redirect_uri)) return { ok: false, erro: 'invalid_grant', descricao: 'redirect_uri inválido.' };
    if (!VERIFIER.test(f.code_verifier ?? '')) return { ok: false, erro: 'invalid_grant', descricao: 'code_verifier inválido.' };
    return { ok: true, tipo: 'codigo', codigo: f.code as string, clienteId, redirectUri: f.redirect_uri as string, verificador: f.code_verifier as string };
  }
  if (f.grant_type === 'refresh_token') {
    if (!REFRESH.test(f.refresh_token ?? '')) return { ok: false, erro: 'invalid_grant', descricao: 'refresh_token inválido.' };
    return { ok: true, tipo: 'refresh', refresh: f.refresh_token as string, clienteId };
  }
  return { ok: false, erro: 'unsupported_grant_type', descricao: 'Use authorization_code ou refresh_token.' };
}

/** RFC 9728: metadados do recurso protegido (o /api/mcp). */
export function metadadosRecurso(base: string) {
  return {
    resource: `${base}/api/mcp`,
    authorization_servers: [base],
    scopes_supported: [...ESCOPOS_OAUTH],
    bearer_methods_supported: ['header'],
    resource_name: 'CRM Comercial — Grupo Participa',
  };
}

/** RFC 8414: metadados do servidor de autorização. */
export function metadadosServidor(base: string) {
  return {
    issuer: base,
    authorization_endpoint: `${base}/oauth/autorizar`,
    token_endpoint: `${base}/api/oauth/token`,
    registration_endpoint: `${base}/api/oauth/registrar`,
    scopes_supported: [...ESCOPOS_OAUTH],
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code', 'refresh_token'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none'],
    authorization_response_iss_parameter_supported: true,
  };
}
