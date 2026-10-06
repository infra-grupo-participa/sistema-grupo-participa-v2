// Marketing > Web: o caso de uso da rota pública /api/web/coletar. Recebe o pacote do gravador, passa pela
// primeira barreira (domain/coleta.ts) e entrega ao banco. As portas (domínios aceitos, coletar, limite em memória)
// vêm de fora, para testar sem rede.
import { avaliarPedido, corpoValido, LIMITE_BYTES, respostaDoBanco, type RespostaColeta } from '../domain/coleta';

export interface PortasColeta {
  /** domínios aceitos agora (cache curto); null = não deu para saber (banco fora) */
  dominios(): Promise<ReadonlySet<string> | null>;
  /** public.mkt_web_coletar com a chave de serviço */
  coletar(corpo: string, origem: string, ipHash: string): Promise<unknown>;
  /** limite em memória por IP (primeira barreira); true = dentro */
  ritmoOk(ip: string): boolean;
  /** sha-256 do IP com sal secreto do dia (o IP em si nunca vai ao banco) */
  hashIp(ip: string): string;
}

export interface Entrada {
  metodo: string;
  origem: string | null;
  tamanhoDeclarado: number | null;
  userAgent: string | null;
  ip: string;
  /** lê o corpo com teto: devolve null se passou de `limite` bytes */
  lerCorpo(limite: number): Promise<string | null>;
}

export interface Saida { status: number; resposta: RespostaColeta; origemPermitida: string | null }

export async function receberPacote(e: Entrada, portas: PortasColeta): Promise<Saida> {
  const dominios = await portas.dominios();
  if (!dominios) return { status: 503, resposta: 'erro', origemPermitida: null };
  const a = avaliarPedido(e, dominios);
  if (!a.ok) {
    // CORS só para domínio cadastrado: o gravador lê a resposta (pausado) e para
    const origemPermitida = a.resposta === 'pausado' ? e.origem : null;
    return { status: a.status, resposta: a.resposta, origemPermitida };
  }
  const origemPermitida = e.origem;
  if (!portas.ritmoOk(e.ip)) return { status: 429, resposta: 'limite', origemPermitida };
  const corpo = await e.lerCorpo(LIMITE_BYTES);
  if (corpo == null) return { status: 413, resposta: 'tamanho', origemPermitida };
  const ruim = corpoValido(corpo);
  if (ruim) return { status: ruim === 'tamanho' ? 413 : 400, resposta: ruim, origemPermitida };
  let r: RespostaColeta;
  try {
    r = respostaDoBanco(await portas.coletar(corpo, e.origem ?? '', portas.hashIp(e.ip)));
  } catch {
    r = 'erro';
  }
  return { status: r === 'erro' ? 502 : r === 'limite' ? 429 : 200, resposta: r, origemPermitida };
}
