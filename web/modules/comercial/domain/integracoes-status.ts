// Status VIVO das integrações do Comercial (aba Integrações). O banco (`crm_integracoes_status`, migration 20261008180945)
// devolve só fatos: chave ligada, segredo existe, último evento, eventos nas 24 h, erro recente e os números de WhatsApp.
// Aqui fica a regra pura que vira selo. Nada de status fixo no código.

/** Integrações que existem no backend (o banco devolve uma linha para cada). */
export type ChaveIntegracao =
  | 'hotmart' | 'infobip' | 'evolution' | 'activecampaign' | 'unnichat' | 'sendflow' | 'respondi' | 'slack' | 'mcp' | 'clint';

export type EstadoIntegracao = 'conectada' | 'sem_eventos' | 'desligada' | 'nao_configurada' | 'em_breve';

export interface ErroIntegracao {
  texto: string;
  em: string | null;
}

/** Uma linha de `crm_integracoes_status().integracoes`. */
export interface FatosIntegracao {
  chave: string;
  ligada: boolean;
  configurada: boolean;
  ultimoEventoEm: string | null;
  eventos24h: number;
  erroRecente: ErroIntegracao | null;
}

export type StatusNumeroWhatsapp = 'conectado' | 'desconectado' | 'aguardando_qr' | 'banido';

export interface NumeroWhatsappVivo {
  id: string;
  nome: string;
  provedor: 'infobip' | 'evolution';
  status: StatusNumeroWhatsapp;
  statusEm: string | null;
  statusMotivo: string | null;
  /** Só os 4 últimos dígitos (o banco nunca devolve o número inteiro). */
  final: string | null;
  ativo: boolean;
  principal: boolean;
  recebe: boolean;
  envia: boolean;
  ultimaMensagemEm: string | null;
  mensagens24h: number;
  falhas24h: number;
}

export interface PainelIntegracoes {
  geradoEm: string;
  integracoes: FatosIntegracao[];
  numeros: NumeroWhatsappVivo[];
}

/**
 * Janela de "evento recente" por fonte, em minutos: o ritmo REAL de cada uma (medido em 08/10/2026), com folga.
 * ActiveCampaign ≈ 22 mil eventos/dia; Hotmart processa várias vezes ao dia; Respondi sincroniza 1×/dia (09:10);
 * WhatsApp e Slack dependem de conversa/alerta (podem passar um fim de semana quietos); MCP é uso pessoal; Clint é só migração.
 */
export const JANELA_EVENTO_MIN: Record<ChaveIntegracao, number> = {
  activecampaign: 6 * 60,
  hotmart: 24 * 60,
  unnichat: 24 * 60,
  sendflow: 24 * 60,
  respondi: 48 * 60,
  infobip: 72 * 60,
  evolution: 72 * 60,
  slack: 72 * 60,
  mcp: 7 * 24 * 60,
  clint: 30 * 24 * 60,
};

export function ehChaveIntegracao(c: string): c is ChaveIntegracao {
  return c in JANELA_EVENTO_MIN;
}

export interface Situacao {
  estado: EstadoIntegracao;
  /** Por que não está conectada (vazio quando está). */
  motivo: string | null;
}

/**
 * Selo de uma integração.
 * - sem linha do banco (Manychat, Instagram) → em breve;
 * - kill-switch desligado → desligada;
 * - ligada sem segredo no Vault → não configurada;
 * - ligada + configurada + evento dentro da janela da fonte → conectada; fora da janela → ligada, sem eventos recentes.
 * WhatsApp (infobip/evolution): além do evento, precisa de pelo menos 1 número ativo daquele provedor conectado.
 */
export function situacaoIntegracao(
  chave: string,
  f: FatosIntegracao | undefined,
  agora: Date,
  numeros: NumeroWhatsappVivo[] = [],
): Situacao {
  if (!f || !ehChaveIntegracao(chave)) return { estado: 'em_breve', motivo: 'Ainda não existe no backend.' };
  if (!f.ligada) return { estado: 'desligada', motivo: 'Chave da integração desligada no banco.' };
  if (!f.configurada) return { estado: 'nao_configurada', motivo: 'Falta a credencial no cofre (Vault).' };
  if (chave === 'infobip' || chave === 'evolution') {
    const conectados = numeros.filter((n) => n.provedor === chave && n.ativo && n.status === 'conectado').length;
    if (conectados === 0) return { estado: 'sem_eventos', motivo: 'Nenhum número conectado.' };
  }
  const ult = f.ultimoEventoEm ? new Date(f.ultimoEventoEm).getTime() : NaN;
  if (Number.isNaN(ult)) return { estado: 'sem_eventos', motivo: 'Nenhum evento recebido ainda.' };
  const janela = JANELA_EVENTO_MIN[chave];
  if (agora.getTime() - ult > janela * 60_000) {
    return { estado: 'sem_eventos', motivo: `Nenhum evento em ${rotuloJanela(janela)}.` };
  }
  return { estado: 'conectada', motivo: null };
}

export function rotuloJanela(min: number): string {
  if (min % (24 * 60) === 0) {
    const d = min / (24 * 60);
    return d === 1 ? '24 h' : `${d} dias`;
  }
  if (min % 60 === 0) return `${min / 60} h`;
  return `${min} min`;
}

export const ROTULO_ESTADO: Record<EstadoIntegracao, string> = {
  conectada: 'Conectada',
  sem_eventos: 'Ligada, sem eventos recentes',
  desligada: 'Desligada',
  nao_configurada: 'Não configurada',
  em_breve: 'Em breve',
};

export const TOM_ESTADO: Record<EstadoIntegracao, 'success' | 'warning' | 'neutral' | 'danger' | 'info'> = {
  conectada: 'success',
  sem_eventos: 'warning',
  desligada: 'neutral',
  nao_configurada: 'danger',
  em_breve: 'info',
};

export const ROTULO_NUMERO: Record<StatusNumeroWhatsapp, string> = {
  conectado: 'Conectado',
  desconectado: 'Desconectado',
  aguardando_qr: 'Aguardando QR',
  banido: 'Banido',
};

export const TOM_NUMERO: Record<StatusNumeroWhatsapp, 'success' | 'warning' | 'danger'> = {
  conectado: 'success',
  desconectado: 'danger',
  aguardando_qr: 'warning',
  banido: 'danger',
};

/** "agora", "há 40 s", "há 12 min", "há 3 h", "há 2 dias"; null → "nunca". Passado (futuro por relógio torto = "agora"). */
export function haQuanto(iso: string | null | undefined, agora: Date): string {
  if (!iso) return 'nunca';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return 'nunca';
  const s = Math.max(0, Math.floor((agora.getTime() - t) / 1000));
  if (s < 5) return 'agora';
  if (s < 60) return `há ${s} s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `há ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24) return `há ${h} h`;
  const d = Math.floor(h / 24);
  return d === 1 ? 'há 1 dia' : `há ${d} dias`;
}

/** Números de um provedor (ativos primeiro, principal no topo; o banco já ordena, aqui só filtra). */
export function numerosDo(provedor: 'infobip' | 'evolution', numeros: NumeroWhatsappVivo[]): NumeroWhatsappVivo[] {
  return numeros.filter((n) => n.provedor === provedor);
}
