import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import type { Autenticacao, PortaMcp, SessaoMcp } from '../application/mcp-servidor';

// Adapter Supabase do MCP do Comercial.
// - autenticar: public.crm_mcp_autenticar (só service_role). Troca o hash do token por perfil/papel/escopos e aplica
//   o kill-switch e o limite. Não age em nome de ninguém.
// - rpc: public.crm_mcp_rpc (só service_role, migration 20261008150823). A função confere o token de novo, monta as
//   claims do DONO (sub, email, gp_canal='mcp'), faz SET LOCAL ROLE authenticated e só então chama a MESMA
//   public.crm_* da tela. RLS, guardas, escrita_ligada e o registro (autor_tipo='mcp') são os da tela. Lista fechada de
//   RPCs e parâmetros pelos nomes da assinatura viva. Substitui o JWT HS256 assinado aqui (dispensa o segredo legado).

const CODIGOS = new Set(['desligado', 'token', 'perfil', 'limite', 'ferramenta']);

export class SupabaseMcpAdapter implements PortaMcp {
  private readonly db = createAdminSupabase();

  async autenticar(hashToken: string, ferramenta: string | null): Promise<Autenticacao> {
    const { data, error } = await this.db.rpc('crm_mcp_autenticar', { p_hash: hashToken, p_ferramenta: ferramenta });
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
    const { data, error } = await this.db.rpc('crm_mcp_rpc', { p_token: sessao.tokenId, p_rpc: rpc, p_params: params });
    return { data, error: error ? { message: error.message, code: error.code } : null };
  }
}
