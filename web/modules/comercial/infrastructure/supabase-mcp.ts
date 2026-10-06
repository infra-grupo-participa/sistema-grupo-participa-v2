import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { createJwtSupabase } from '@/shared/infrastructure/supabase/jwt-client';
import { env, publicEnv } from '@/shared/infrastructure/config/env';
import type { Autenticacao, PortaMcp, SessaoMcp } from '../application/mcp-servidor';
import { assinarJwtHs256, montarClaimsMcp } from './mcp-jwt';

// Adapter Supabase do MCP do Comercial.
// - autenticar: service role SÓ para public.crm_mcp_autenticar (executável apenas por service_role). Não age em nome
//   de ninguém: só troca o hash do token por perfil/papel/escopos e aplica o kill-switch e o limite.
// - rpc: client com o JWT CURTO do dono do token (5 min), criado 1× por pedido HTTP. Daí em diante é a RLS.

const CODIGOS = new Set(['desligado', 'token', 'perfil', 'limite', 'ferramenta']);

export class SupabaseMcpAdapter implements PortaMcp {
  private client: ReturnType<typeof createJwtSupabase> | null = null;

  async autenticar(hashToken: string, ferramenta: string | null): Promise<Autenticacao> {
    const { data, error } = await createAdminSupabase().rpc('crm_mcp_autenticar', { p_hash: hashToken, p_ferramenta: ferramenta });
    if (error || !data || typeof data !== 'object') return { ok: false, codigo: 'falha', msg: 'Falha ao validar o token.' };
    const r = data as Record<string, unknown>;
    if (r.ok !== true) {
      const codigo = typeof r.codigo === 'string' && CODIGOS.has(r.codigo) ? r.codigo : 'falha';
      return { ok: false, codigo: codigo as Exclude<Autenticacao, { ok: true }>['codigo'], msg: String(r.msg ?? 'Token recusado.') };
    }
    const papel = r.papel === 'gestor' ? 'gestor' : 'vendedor';
    const escopos = Array.isArray(r.escopos) ? r.escopos.filter((e): e is string => typeof e === 'string') : [];
    return {
      ok: true,
      sessao: { tokenId: String(r.tokenId), perfilId: String(r.perfilId), email: String(r.email), papel, escopos },
    };
  }

  async rpc(sessao: SessaoMcp, rpc: string, params: Record<string, unknown>) {
    if (!this.client) {
      const jwt = assinarJwtHs256(montarClaimsMcp(sessao, publicEnv.supabaseUrl), env.supabase.jwtSecret);
      this.client = createJwtSupabase(jwt);
    }
    const { data, error } = await this.client.rpc(rpc, params);
    return { data, error: error ? { message: error.message, code: error.code } : null };
  }
}
