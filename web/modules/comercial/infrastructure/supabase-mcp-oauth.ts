import { createHash, randomBytes } from 'node:crypto';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import type { Cripto, PortaOAuth, ResultadoBanco } from '../application/mcp-oauth';

// Adapter do OAuth do MCP. Service role SÓ nas 3 RPCs executáveis apenas por service_role
// (crm_mcp_oauth_registrar/trocar/renovar, migration 20261008150823). Os textos de token nunca vão ao banco: só hashes.

function lerResultado(data: unknown, error: unknown): ResultadoBanco {
  if (error || !data || typeof data !== 'object') return { ok: false, msg: 'Não foi possível concluir agora.' };
  const r = data as Record<string, unknown>;
  if (r.ok !== true) return { ok: false, msg: String(r.msg ?? 'Pedido recusado.') };
  const escopos = Array.isArray(r.escopos) ? r.escopos.filter((e): e is string => typeof e === 'string') : ['ler'];
  return { ok: true, escopos };
}

export class SupabaseMcpOAuth implements PortaOAuth {
  private readonly db = createAdminSupabase();

  async registrar(nome: string, redirects: string[]) {
    const { data, error } = await this.db.rpc('crm_mcp_oauth_registrar', { p_nome: nome, p_redirects: redirects });
    const r = (data ?? {}) as Record<string, unknown>;
    if (error || r.ok !== true || typeof r.id !== 'string') {
      return { ok: false as const, msg: typeof r.msg === 'string' ? r.msg : 'Não foi possível registrar agora.' };
    }
    return { ok: true as const, id: r.id };
  }

  async trocar(p: Parameters<PortaOAuth['trocar']>[0]) {
    const { data, error } = await this.db.rpc('crm_mcp_oauth_trocar', {
      p_codigo_hash: p.codigoHash, p_cliente: p.clienteId, p_redirect: p.redirectUri, p_challenge: p.challenge,
      p_access_hash: p.accessHash, p_prefixo: p.prefixo, p_refresh_hash: p.refreshHash,
    });
    return lerResultado(data, error);
  }

  async renovar(p: Parameters<PortaOAuth['renovar']>[0]) {
    const { data, error } = await this.db.rpc('crm_mcp_oauth_renovar', {
      p_refresh_hash: p.refreshHash, p_cliente: p.clienteId, p_access_hash: p.accessHash, p_prefixo: p.prefixo,
      p_refresh_novo: p.refreshNovo,
    });
    return lerResultado(data, error);
  }
}

export const criptoNode: Cripto = {
  sha256Hex: (s) => createHash('sha256').update(s).digest('hex'),
  s256: (v) => createHash('sha256').update(v).digest('base64url'),
  aleatorioHex: (n) => randomBytes(n).toString('hex'),
};
