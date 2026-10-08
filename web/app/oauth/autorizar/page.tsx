import { redirect } from 'next/navigation';
import { getCurrentUser, serverContainer } from '@/shared/composition/server-container';
import { publicAppBaseUrl } from '@/shared/infrastructure/http/security';
import { lerPedidoAutorizacao, urlDeRetorno } from '@/modules/comercial/domain/mcp-oauth';
import { AutorizarClaudeClient, ErroAutorizacao } from '@/modules/comercial/ui/mcp/AutorizarClaudeClient';

export const dynamic = 'force-dynamic';

// OAuth do MCP — authorization endpoint + tela de consentimento (docs/projetos/comercial/mcp.md §5).
// Sem sessão da equipe: o proxy manda ao login com a query de volta. Aqui: pedido bem formado (domínio) → cliente e
// redirect conferidos no banco + pessoa do Comercial com MCP ligado (crm_mcp_oauth_cliente, JWT da pessoa) → tela.
// Só depois de conferir que o redirect é DO cliente um erro de protocolo volta para ele; antes disso, erro na tela.

type Busca = Record<string, string | string[] | undefined>;

export default async function AutorizarPage({ searchParams }: { searchParams: Promise<Busca> }) {
  const bruto = await searchParams;
  const q = Object.fromEntries(Object.entries(bruto).map(([k, v]) => [k, Array.isArray(v) ? v[0] : v]));

  const user = await getCurrentUser();
  if (!user) redirect(`/login?redirect=${encodeURIComponent(`/oauth/autorizar?${new URLSearchParams(q as Record<string, string>)}`)}`);

  const base = publicAppBaseUrl();
  const lido = lerPedidoAutorizacao(q, `${base}/api/mcp`);
  const clienteId = lido.ok ? lido.pedido.clienteId : q.client_id ?? '';
  const redirectUri = lido.ok ? lido.pedido.redirectUri : lido.voltar?.redirectUri ?? '';
  if (!lido.ok && !lido.voltar) return <ErroAutorizacao msg={lido.descricao} />;

  const { supabase } = await serverContainer();
  const { data, error } = await supabase.rpc('crm_mcp_oauth_cliente', { p_cliente: clienteId, p_redirect: redirectUri });
  const r = (data ?? {}) as { ok?: boolean; msg?: string; nome?: string };
  if (error || r.ok !== true) return <ErroAutorizacao msg={r.msg ?? 'Não foi possível validar o pedido agora.'} />;

  if (!lido.ok) {
    redirect(urlDeRetorno(lido.voltar!.redirectUri, { error: lido.voltar!.erro, error_description: lido.descricao, state: lido.voltar!.state, iss: base }));
  }

  return (
    <AutorizarClaudeClient
      cliente={r.nome ?? 'Claude'}
      email={user.email}
      pedido={lido.pedido}
      emissor={base}
    />
  );
}
