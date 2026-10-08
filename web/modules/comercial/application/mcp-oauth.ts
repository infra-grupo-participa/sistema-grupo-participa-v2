// Casos de uso do OAuth do MCP do Comercial: registrar cliente e emitir/renovar token. Sem Next, sem Supabase.
// Regras de formato em ../domain/mcp-oauth.ts; regra de estado (uso único, PKCE, revogação, kill-switch) no banco.

import { lerPedidoToken, validarRegistro, VALIDADE_ACCESS_S } from '../domain/mcp-oauth';

export type ResultadoBanco = { ok: true; escopos: string[] } | { ok: false; msg: string };

export interface PortaOAuth {
  registrar(nome: string, redirects: string[]): Promise<{ ok: true; id: string } | { ok: false; msg: string }>;
  trocar(p: {
    codigoHash: string; clienteId: string; redirectUri: string; challenge: string;
    accessHash: string; prefixo: string; refreshHash: string;
  }): Promise<ResultadoBanco>;
  renovar(p: { refreshHash: string; clienteId: string; accessHash: string; prefixo: string; refreshNovo: string }): Promise<ResultadoBanco>;
}

export interface Cripto {
  sha256Hex(s: string): string;
  /** base64url(sha256(verifier)) — PKCE S256. */
  s256(verificador: string): string;
  aleatorioHex(bytes: number): string;
}

export interface RespostaOAuth {
  status: number;
  corpo: Record<string, unknown>;
}

const erro = (status: number, codigo: string, descricao: string): RespostaOAuth => ({
  status, corpo: { error: codigo, error_description: descricao },
});

export async function registrarCliente(corpo: unknown, porta: PortaOAuth, agora: Date = new Date()): Promise<RespostaOAuth> {
  const r = validarRegistro(corpo);
  if (!r.ok) return erro(400, r.erro, r.descricao);
  const b = await porta.registrar(r.nome, r.redirects);
  if (!b.ok) return erro(400, 'invalid_client_metadata', b.msg);
  return {
    status: 201,
    corpo: {
      client_id: b.id,
      client_id_issued_at: Math.floor(agora.getTime() / 1000),
      client_name: r.nome,
      redirect_uris: r.redirects,
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
    },
  };
}

export async function emitirToken(form: Record<string, string | undefined>, porta: PortaOAuth, cripto: Cripto): Promise<RespostaOAuth> {
  const p = lerPedidoToken(form);
  if (!p.ok) return erro(400, p.erro, p.descricao);

  const access = `gpc_${cripto.aleatorioHex(32)}`;
  const refresh = `gpr_${cripto.aleatorioHex(32)}`;
  const comum = { clienteId: p.clienteId, accessHash: cripto.sha256Hex(access), prefixo: access.slice(0, 12) };

  const r = p.tipo === 'codigo'
    ? await porta.trocar({
      ...comum,
      codigoHash: cripto.sha256Hex(p.codigo),
      redirectUri: p.redirectUri,
      challenge: cripto.s256(p.verificador),
      refreshHash: cripto.sha256Hex(refresh),
    })
    : await porta.renovar({ ...comum, refreshHash: cripto.sha256Hex(p.refresh), refreshNovo: cripto.sha256Hex(refresh) });

  if (!r.ok) return erro(400, 'invalid_grant', r.msg);
  return {
    status: 200,
    corpo: { access_token: access, token_type: 'Bearer', expires_in: VALIDADE_ACCESS_S, refresh_token: refresh, scope: r.escopos.join(' ') },
  };
}
