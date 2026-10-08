// Credenciais da Evolution API — SÓ servidor. env (EVOLUTION_API_URL/KEY) tem prioridade; vazio = Vault
// (evolution_api_url/_key) via RPC public.crm_evolution_credenciais (execute só service_role; migration 20261008…).
// Chamar SÓ depois de autorizar o gestor. O valor fica em cache em memória por alguns minutos; nunca é logado nem
// devolvido ao browser. Doc: docs/projetos/comercial/whatsapp-qr-evolution.md
import { env } from '@/shared/infrastructure/config/env';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { escolherCredenciais, type CredenciaisEvolution } from '../domain/canais-whatsapp';

const CACHE_OK_MS = 5 * 60_000;
const CACHE_VAZIO_MS = 30_000;

type Cofre = { url: string | null; chave: string | null } | null;
let cache: { valor: Cofre; ate: number } | null = null;

async function lerVault(): Promise<Cofre> {
  const agora = Date.now();
  if (cache && cache.ate > agora) return cache.valor;
  const { data, error } = await createAdminSupabase().rpc('crm_evolution_credenciais');
  if (error) return null; // falha não entra no cache (tenta de novo na próxima chamada); mensagem não é logada
  const linha = (Array.isArray(data) ? data[0] : data) as { url?: unknown; api_key?: unknown } | null | undefined;
  const valor: Cofre = linha
    ? { url: typeof linha.url === 'string' ? linha.url : null, chave: typeof linha.api_key === 'string' ? linha.api_key : null }
    : null;
  cache = { valor, ate: agora + (valor?.url && valor?.chave ? CACHE_OK_MS : CACHE_VAZIO_MS) };
  return valor;
}

/** null = Evolution não configurada (nem env nem Vault). */
export async function credenciaisEvolution(): Promise<CredenciaisEvolution | null> {
  const r = await escolherCredenciais(env.evolution.url, env.evolution.apiKey, lerVault);
  return r ? { base: r.base, chave: r.chave } : null;
}
