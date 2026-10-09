// Canais de WhatsApp do CRM (migration 20261008152212): o número oficial (Infobip, API) e os números conectados por QR
// (Evolution API). Regras puras, sem React nem Supabase. Doc: docs/projetos/comercial/whatsapp-qr-evolution.md

export type ProvedorCanal = 'infobip' | 'evolution';
export type StatusCanal = 'desconectado' | 'aguardando_qr' | 'conectado' | 'banido';

export interface CanalWhatsapp {
  id: string;
  provedor: ProvedorCanal;
  nome: string;
  /** Só os 4 últimos dígitos (null = ainda não leu o QR). */
  final: string | null;
  status: StatusCanal;
  statusEm: string | null;
  statusMotivo: string | null;
  conectadoEm: string | null;
  recebe: boolean;
  envia: boolean;
  donoId: string | null;
  /** Número padrão do CRM (disparos e templates): sempre o oficial. */
  padrao: boolean;
}

export interface PainelCanais {
  evolutionLigado: boolean;
  envioLigado: boolean;
  limiteMinuto: number;
  limiteHora: number;
  novosHora: number;
  canais: CanalWhatsapp[];
}

export const ROTULO_STATUS_CANAL: Record<StatusCanal, string> = {
  conectado: 'Conectado',
  aguardando_qr: 'Aguardando QR',
  desconectado: 'Desconectado',
  banido: 'Bloqueado pelo WhatsApp',
};

export type TomStatus = 'success' | 'warning' | 'neutral' | 'danger';
export const TOM_STATUS_CANAL: Record<StatusCanal, TomStatus> = {
  conectado: 'success', aguardando_qr: 'warning', desconectado: 'neutral', banido: 'danger',
};

/** Rótulo curto do número para selo e filtro: "Clint 4276" / "Oficial · 5211". */
export function rotuloCanal(c: Pick<CanalWhatsapp, 'nome' | 'final'> | null | undefined): string {
  if (!c) return 'Número removido';
  return c.final ? `${c.nome} · ${c.final}` : c.nome;
}

/** Sem janela de 24 h nem template: número conectado por QR é WhatsApp normal. */
export function semJanela(c: Pick<CanalWhatsapp, 'provedor'> | null | undefined): boolean {
  return c?.provedor === 'evolution';
}

/** Por que o CRM não envia por este número agora (null = envia). Espelho de crm_enviar_mensagem. */
export function bloqueioEnvio(c: CanalWhatsapp | null | undefined, painel: Pick<PainelCanais, 'evolutionLigado' | 'envioLigado'> | null): string | null {
  if (!c) return null;
  if (c.provedor !== 'evolution') return null;
  if (painel && !painel.evolutionLigado) return 'WhatsApp por QR desligado no CRM.';
  if (painel && !painel.envioLigado) return 'Envio de WhatsApp desligado.';
  if (!c.envia) return 'Este número não envia pelo CRM.';
  if (c.status !== 'conectado') return 'Número desconectado: o gestor reconecta em Configurações.';
  return null;
}

/**
 * Por qual número responder: o escolhido na tela; senão o da conversa mais recente; senão o padrão. É o mesmo critério
 * do banco quando a tela não manda canal.
 */
export function canalDeResposta(escolhido: string | null, daConversa: string | null, canais: CanalWhatsapp[]): CanalWhatsapp | null {
  const porId = (id: string | null) => (id ? canais.find((c) => c.id === id) ?? null : null);
  return porId(escolhido) ?? porId(daConversa) ?? canais.find((c) => c.padrao) ?? null;
}

/** Nome do número novo: 2 a 80 caracteres. */
export function validarNomeCanal(nome: string): string | null {
  const n = nome.trim();
  if (n.length < 2) return 'Dê um nome ao número (ex.: "Clint 4276").';
  if (n.length > 80) return 'Nome longo demais (máximo 80).';
  return null;
}

/** Enquanto espera o QR, a tela pergunta de novo a cada X ms; para depois de Y tentativas (o QR expira). */
export const QR_INTERVALO_MS = 3000;
export const QR_MAX_TENTATIVAS = 100; // ~5 min

// ── Evolution API (servidor) ──

export const INSTANCIA_RE = /^crm-[a-z0-9-]{3,40}$/;

/** Webhook por instância: Edge crm-evolution-webhook com a instância na query (a chave vai no header). */
export function urlWebhookEvolution(supabaseUrl: string, instancia: string): string {
  return `${supabaseUrl.replace(/\/+$/, '')}/functions/v1/crm-evolution-webhook?i=${encodeURIComponent(instancia)}`;
}

// MESSAGES_EDITED / MESSAGES_DELETE (20261009153515): o contato (ou o celular) editou/apagou — reflete na conversa.
export const EVENTOS_WEBHOOK = ['MESSAGES_UPSERT', 'MESSAGES_EDITED', 'MESSAGES_DELETE', 'CONNECTION_UPDATE', 'QRCODE_UPDATED'] as const;

/** Corpo de POST /webhook/set/{instância} (Evolution v2). base64: o arquivo recebido já vem junto. */
export function corpoWebhookEvolution(url: string, chave: string) {
  return {
    webhook: {
      enabled: true, url, byEvents: false, base64: true,
      headers: { 'x-crm-chave': chave, 'Content-Type': 'application/json' },
      events: [...EVENTOS_WEBHOOK],
    },
  };
}

/** Corpo de POST /instance/create: sem grupos, sem ler mensagem pelo sistema, sem histórico antigo. */
export function corpoCriarInstancia(instancia: string) {
  return {
    instanceName: instancia, integration: 'WHATSAPP-BAILEYS', qrcode: true,
    groupsIgnore: true, readMessages: false, readStatus: false, alwaysOnline: false, rejectCall: false, syncFullHistory: false,
  };
}

/** Base da Evolution: só https, sem caminho (o env não pode virar outro destino). */
export function baseEvolution(url: string | null | undefined): string | null {
  let u: URL;
  try { u = new URL(String(url ?? '').trim()); } catch { return null; }
  if (u.protocol !== 'https:' || u.username || u.password || u.search || u.hash) return null;
  if (u.pathname !== '/' && u.pathname !== '') return null;
  return `${u.protocol}//${u.host}`;
}

type Obj = Record<string, unknown>;
const obj = (v: unknown): Obj | null => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Obj) : null);

/** QR (data URL PNG) da resposta de /instance/connect ou /instance/create. */
export function qrDaResposta(d: unknown): string | null {
  const o = obj(d);
  const b = o?.base64 ?? obj(o?.qrcode)?.base64;
  return typeof b === 'string' && b.length <= 60_000 && /^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(b) ? b : null;
}

/** Estado da resposta de /instance/connectionState: open | close | connecting (outro = null). */
export function estadoDaResposta(d: unknown): 'open' | 'close' | 'connecting' | null {
  const s = obj(obj(d)?.instance)?.state ?? obj(d)?.state;
  return s === 'open' || s === 'close' || s === 'connecting' ? s : null;
}

/** Dono da sessão em /instance/fetchInstances (lista): só dígitos. */
export function numeroDaInstancia(d: unknown, instancia: string): string | null {
  const lista = Array.isArray(d) ? d : [d];
  for (const item of lista) {
    const o = obj(item);
    const nome = o?.name ?? o?.instanceName ?? obj(o?.instance)?.instanceName;
    if (nome !== instancia) continue;
    const jid = o?.ownerJid ?? obj(o?.instance)?.owner;
    if (typeof jid !== 'string') return null;
    const dig = jid.split('@')[0].split(':')[0].replace(/\D/g, '');
    return /^\d{10,15}$/.test(dig) ? dig : null;
  }
  return null;
}

/** URL base + chave global da Evolution, já validadas. */
export type CredenciaisEvolution = { base: string; chave: string };

/** Valida um par URL/chave (https sem caminho; chave com 16+ caracteres). null = incompleto ou inválido. */
export function credenciaisValidas(url: string | null | undefined, chave: string | null | undefined): CredenciaisEvolution | null {
  const base = baseEvolution(url);
  const k = String(chave ?? '').trim();
  return base && k.length >= 16 ? { base, chave: k } : null;
}

/**
 * Prioridade: env do servidor (EVOLUTION_API_URL/KEY) vence o Vault (evolution_api_url/_key). O Vault só é consultado
 * quando o env não traz um par válido. Env parcial (só URL ou só chave) não se mistura com o Vault.
 */
export async function escolherCredenciais(
  envUrl: string, envChave: string, doVault: () => Promise<{ url: string | null; chave: string | null } | null>,
): Promise<(CredenciaisEvolution & { fonte: 'env' | 'vault' }) | null> {
  const doEnv = credenciaisValidas(envUrl, envChave);
  if (doEnv) return { ...doEnv, fonte: 'env' };
  const v = await doVault();
  const doCofre = v ? credenciaisValidas(v.url, v.chave) : null;
  return doCofre ? { ...doCofre, fonte: 'vault' } : null;
}
