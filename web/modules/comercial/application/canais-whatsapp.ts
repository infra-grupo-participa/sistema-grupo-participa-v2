// Casos de uso dos números de WhatsApp conectados por QR (servidor). Quem pode: o banco decide (crm_canal_criar /
// crm_canal_portao, só gestor do CRM via crm.eh_gestor). Só DEPOIS do portão o servidor usa a chave global da Evolution
// e a função de serviço (service_role) que guarda QR/estado. Doc: docs/projetos/comercial/whatsapp-qr-evolution.md
import { urlWebhookEvolution } from '../domain/canais-whatsapp';

/** O que o caso de uso precisa da Evolution (implementado por infrastructure/evolution-api.ts). */
export interface ClienteEvolution {
  criar(instancia: string): Promise<{ ok: boolean; qr: string | null; http: number }>;
  configurarWebhook(instancia: string, url: string, chave: string): Promise<boolean>;
  qr(instancia: string): Promise<{ qr: string | null; http: number }>;
  estado(instancia: string): Promise<{ estado: 'open' | 'close' | 'connecting' | null; http: number }>;
  numero(instancia: string): Promise<string | null>;
  sair(instancia: string): Promise<boolean>;
}
type EvolutionApi = ClienteEvolution;

export type ResultadoRpc = { ok: boolean; msg?: string; [k: string]: unknown };

/** Portas para o banco: `usuario` = JWT de quem clicou (RLS/guardas); `servico` = service role (só depois do portão). */
export interface PortasCanais {
  criarCanal(nome: string): Promise<ResultadoRpc>;
  portao(canalId: string, acao: 'conectar' | 'desconectar' | 'ver'): Promise<ResultadoRpc>;
  servico(acao: 'webhook' | 'qr_ler' | 'qr_guardar' | 'estado' | 'desconectado', canalId: string, dados?: Record<string, unknown>): Promise<ResultadoRpc>;
}

export type EstadoConexao = { ok: true; status: string; qr: string | null; final: string | null } | { ok: false; msg: string; http: number };

const erro = (msg: string, http: number): EstadoConexao => ({ ok: false, msg, http });

/** Instância existe e o webhook aponta para a Edge com a chave da instância (idempotente). */
async function garantirInstancia(evo: EvolutionApi, portas: PortasCanais, supabaseUrl: string, canalId: string): Promise<{ instancia: string; qr: string | null } | null> {
  const s = await portas.servico('webhook', canalId);
  const instancia = typeof s.instancia === 'string' ? s.instancia : '';
  const chave = typeof s.webhookChave === 'string' ? s.webhookChave : '';
  if (!s.ok || !instancia || !chave) return null;
  const criada = await evo.criar(instancia);
  if (!criada.ok) return null;
  const webhook = await evo.configurarWebhook(instancia, urlWebhookEvolution(supabaseUrl, instancia), chave);
  if (!webhook) return null;
  return { instancia, qr: criada.qr };
}

/** Novo número: cria no banco (gestor), cria a instância, liga o webhook e devolve o primeiro QR. */
export async function criarNumero(evo: EvolutionApi, portas: PortasCanais, supabaseUrl: string, nome: string): Promise<{ ok: true; canalId: string; qr: string | null } | { ok: false; msg: string; http: number }> {
  const r = await portas.criarCanal(nome);
  if (!r.ok || typeof r.canalId !== 'string') return { ok: false, msg: r.msg ?? 'Não foi possível criar o número.', http: 403 };
  const canalId = r.canalId;
  const g = await garantirInstancia(evo, portas, supabaseUrl, canalId);
  if (!g) return { ok: false, msg: 'Número criado, mas a Evolution não respondeu. Tente "Gerar QR" de novo.', http: 502 };
  let qr = g.qr;
  if (!qr) qr = (await evo.qr(g.instancia)).qr;
  if (qr) await portas.servico('qr_guardar', canalId, { base64: qr });
  return { ok: true, canalId, qr };
}

/**
 * Estado para a tela que espera o QR (chamada a cada 3 s): conectado → grava número e status; senão devolve o QR
 * guardado (o webhook QRCODE_UPDATED atualiza) ou pede um novo à Evolution. `reconectar` também refaz a instância.
 */
export async function estadoConexao(evo: EvolutionApi, portas: PortasCanais, supabaseUrl: string, canalId: string, reconectar: boolean): Promise<EstadoConexao> {
  const p = await portas.portao(canalId, reconectar ? 'conectar' : 'ver');
  if (!p.ok || typeof p.instancia !== 'string') return erro(p.msg ?? 'Sem acesso.', 403);
  const instancia = p.instancia;
  if (reconectar && !(await garantirInstancia(evo, portas, supabaseUrl, canalId))) return erro('A Evolution não respondeu.', 502);

  const e = await evo.estado(instancia);
  if (e.http === 404 && !reconectar) return { ok: true, status: 'desconectado', qr: null, final: null };
  if (e.estado === 'open') {
    const numero = await evo.numero(instancia);
    const r = await portas.servico('estado', canalId, { estado: 'open', numero });
    const status = r.r === 'conectado' ? 'conectado' : 'desconectado';
    return { ok: true, status, qr: null, final: status === 'conectado' && numero ? numero.slice(-4) : null };
  }
  const guardado = await portas.servico('qr_ler', canalId);
  if (guardado.status === 'conectado') return { ok: true, status: 'conectado', qr: null, final: null };
  if (typeof guardado.qr === 'string' && guardado.qr) return { ok: true, status: 'aguardando_qr', qr: guardado.qr, final: null };
  if (!reconectar && guardado.status !== 'aguardando_qr') return { ok: true, status: String(guardado.status ?? 'desconectado'), qr: null, final: null };
  const novo = await evo.qr(instancia);
  if (novo.qr) await portas.servico('qr_guardar', canalId, { base64: novo.qr });
  return { ok: true, status: 'aguardando_qr', qr: novo.qr, final: null };
}

/** Desconecta o aparelho na Evolution e marca no banco. O número continua no celular e na Clint. */
export async function desconectarNumero(evo: EvolutionApi, portas: PortasCanais, canalId: string): Promise<{ ok: true } | { ok: false; msg: string; http: number }> {
  const p = await portas.portao(canalId, 'desconectar');
  if (!p.ok || typeof p.instancia !== 'string') return { ok: false, msg: p.msg ?? 'Sem acesso.', http: 403 };
  const saiu = await evo.sair(p.instancia);
  if (!saiu) return { ok: false, msg: 'A Evolution não confirmou a desconexão. Tente de novo.', http: 502 };
  await portas.servico('desconectado', canalId, { motivo: 'Desconectado pelo gestor.' });
  return { ok: true };
}
