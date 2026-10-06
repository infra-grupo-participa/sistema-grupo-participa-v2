// Protocolo MCP (JSON-RPC 2.0 sobre Streamable HTTP, modo stateless: 1 POST = 1 mensagem = 1 resposta JSON).
// Domínio puro. Sem SSE, sem sessão (Mcp-Session-Id), sem lote (removido na revisão 2025-06-18 do MCP).

export const VERSOES_MCP = ['2025-06-18', '2025-03-26', '2024-11-05'] as const;
export const VERSAO_PADRAO = VERSOES_MCP[0];

export type IdJsonRpc = string | number | null;

export interface PedidoJsonRpc {
  jsonrpc: '2.0';
  id?: IdJsonRpc;
  method: string;
  params?: Record<string, unknown>;
}

export interface RespostaJsonRpc {
  jsonrpc: '2.0';
  id: IdJsonRpc;
  result?: unknown;
  error?: { code: number; message: string };
}

export const ERRO = {
  parse: -32700,
  pedidoInvalido: -32600,
  metodoInexistente: -32601,
  parametrosInvalidos: -32602,
  interno: -32603,
} as const;

export const respostaOk = (id: IdJsonRpc, result: unknown): RespostaJsonRpc => ({ jsonrpc: '2.0', id, result });
export const respostaErro = (id: IdJsonRpc, code: number, message: string): RespostaJsonRpc => ({
  jsonrpc: '2.0', id, error: { code, message },
});

/** É notificação (sem id): o servidor responde 202 sem corpo. */
export const ehNotificacao = (p: PedidoJsonRpc) => !('id' in p) || p.id === undefined;

export function lerPedido(corpo: unknown): { ok: true; pedido: PedidoJsonRpc } | { ok: false; erro: RespostaJsonRpc } {
  if (Array.isArray(corpo)) {
    return { ok: false, erro: respostaErro(null, ERRO.pedidoInvalido, 'Lote JSON-RPC não é suportado: envie uma mensagem por vez.') };
  }
  if (!corpo || typeof corpo !== 'object') return { ok: false, erro: respostaErro(null, ERRO.pedidoInvalido, 'Pedido inválido.') };
  const p = corpo as Record<string, unknown>;
  const id = p.id;
  const idOk = id === undefined || id === null || typeof id === 'string' || (typeof id === 'number' && Number.isFinite(id));
  if (p.jsonrpc !== '2.0' || typeof p.method !== 'string' || !idOk) {
    return { ok: false, erro: respostaErro(idOk ? ((id as IdJsonRpc) ?? null) : null, ERRO.pedidoInvalido, 'Pedido JSON-RPC 2.0 inválido.') };
  }
  if (p.params !== undefined && (p.params === null || typeof p.params !== 'object' || Array.isArray(p.params))) {
    return { ok: false, erro: respostaErro((id as IdJsonRpc) ?? null, ERRO.parametrosInvalidos, 'params precisa ser objeto.') };
  }
  return { ok: true, pedido: p as unknown as PedidoJsonRpc };
}

/** Versão do protocolo: a pedida pelo cliente, se suportada; senão a mais nova que o servidor fala. */
export function negociarVersao(pedida: unknown): string {
  return typeof pedida === 'string' && (VERSOES_MCP as readonly string[]).includes(pedida) ? pedida : VERSAO_PADRAO;
}

/** Resultado de tools/call: texto (JSON) para qualquer cliente + structuredContent para quem lê objeto. */
export function resultadoFerramenta(dados: Record<string, unknown>, isError = false) {
  return { content: [{ type: 'text', text: JSON.stringify(dados) }], structuredContent: dados, isError };
}

export function erroFerramenta(msg: string) {
  return { content: [{ type: 'text', text: msg }], isError: true };
}
