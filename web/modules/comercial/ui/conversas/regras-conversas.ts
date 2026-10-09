// Regras puras da caixa de conversas: tempo esperando resposta, janela de 24 h, template e dia.
// Sem React e sem relógio próprio: "agora" entra como parâmetro (testável).
import { contaNaFila } from '../../domain/atendimento';
import { etapa } from '../../domain/catalogo';
import type { Conversa, Mensagem } from '../../domain/types';

/**
 * Horário de contato com lead (proposta do playbook: seg a sex 8h–20h, sáb 9h–13h).
 * Minutos desde a meia-noite, por dia da semana (0 = domingo). null = sem expediente.
 */
export const HORARIO_CONTATO: Record<number, [number, number] | null> = {
  0: null,
  1: [8 * 60, 20 * 60], 2: [8 * 60, 20 * 60], 3: [8 * 60, 20 * 60], 4: [8 * 60, 20 * 60], 5: [8 * 60, 20 * 60],
  6: [9 * 60, 13 * 60],
};

/** Minutos de horário comercial entre duas datas (hora local). Teto de 31 dias. */
export function minutosUteis(de: Date, ate: Date, horario = HORARIO_CONTATO): number {
  if (ate.getTime() <= de.getTime()) return 0;
  let total = 0;
  let dia = new Date(de.getFullYear(), de.getMonth(), de.getDate());
  for (let i = 0; i < 31 && dia.getTime() < ate.getTime(); i++) {
    const w = horario[dia.getDay()];
    if (w) {
      const ini = new Date(dia.getFullYear(), dia.getMonth(), dia.getDate(), 0, w[0]).getTime();
      const fim = new Date(dia.getFullYear(), dia.getMonth(), dia.getDate(), 0, w[1]).getTime();
      total += Math.max(0, Math.min(fim, ate.getTime()) - Math.max(ini, de.getTime()));
    }
    dia = new Date(dia.getFullYear(), dia.getMonth(), dia.getDate() + 1);
  }
  return Math.floor(total / 60000);
}

export type NivelEspera = 'ok' | 'atencao' | 'critico';

// Mesmo alerta do primeiro contato no funil: 5 min atenção, 15 min crítico.
const ATENCAO_MIN = etapa('primeiro_contato').slaAtencaoMin ?? 5;
const CRITICO_MIN = etapa('primeiro_contato').slaCriticoMin ?? 15;

/**
 * Lead esperando resposta: só quando a última mensagem é dele.
 * O nível conta só minutos em horário comercial; `minutos` é o tempo corrido (para exibir).
 */
export function esperaResposta(
  ultima: Pick<Mensagem, 'direcao' | 'em'>,
  agora: Date,
): { minutos: number; minutosUteis: number; nivel: NivelEspera } | null {
  if (ultima.direcao !== 'entrada') return null;
  const de = new Date(ultima.em);
  if (Number.isNaN(de.getTime())) return null;
  const minutos = Math.max(0, Math.floor((agora.getTime() - de.getTime()) / 60000));
  const uteis = minutosUteis(de, agora);
  const nivel: NivelEspera = uteis >= CRITICO_MIN ? 'critico' : uteis >= ATENCAO_MIN ? 'atencao' : 'ok';
  return { minutos, minutosUteis: uteis, nivel };
}

const PESO_ESPERA: Record<NivelEspera, number> = { critico: 0, atencao: 1, ok: 2 };

/**
 * Ordem da caixa: responda primeiro quem espera há mais tempo.
 * 1) lead esperando com alerta crítico, 2) com alerta de atenção (nos dois, quem espera há mais tempo
 * em horário comercial primeiro; empate, mais não lidas), 3) o resto pela última mensagem, mais recente primeiro.
 * Não muda a lista recebida.
 */
export function ordenarConversas<T extends Pick<Conversa, 'naoLidas'> & Partial<Pick<Conversa, 'atendimento'>> & { ultimaMensagem: Pick<Mensagem, 'direcao' | 'em'> }>(lista: readonly T[], agora: Date): T[] {
  const chave = lista.map((cv) => {
    // em espera / encerrada não é "esperando resposta" (20261009153515)
    const e = contaNaFila(cv) ? esperaResposta(cv.ultimaMensagem, agora) : null;
    const nivel: NivelEspera = e?.nivel ?? 'ok';
    const t = new Date(cv.ultimaMensagem.em).getTime();
    return { cv, peso: PESO_ESPERA[nivel], uteis: e?.minutosUteis ?? 0, t: Number.isNaN(t) ? 0 : t };
  });
  chave.sort((a, b) => {
    if (a.peso !== b.peso) return a.peso - b.peso;
    if (a.peso < 2) {
      if (a.uteis !== b.uteis) return b.uteis - a.uteis;
      if (a.cv.naoLidas !== b.cv.naoLidas) return b.cv.naoLidas - a.cv.naoLidas;
    }
    return b.t - a.t;
  });
  return chave.map((k) => k.cv);
}

/** "12 min", "3 h", "2 dias". */
export function duracaoCurta(min: number): string {
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h} h`;
  const d = Math.floor(h / 24);
  return `${d} ${d === 1 ? 'dia' : 'dias'}`;
}

/** Quanto falta para a janela de 24 h fechar. null = fechada. */
export function janelaRestante(janelaAteEm: string | null, agora: Date): { minutos: number; rotulo: string } | null {
  if (!janelaAteEm) return null;
  const min = Math.floor((new Date(janelaAteEm).getTime() - agora.getTime()) / 60000);
  if (!(min > 0)) return null;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return { minutos: min, rotulo: h ? `${h}h${m ? ` ${String(m).padStart(2, '0')}min` : ''}` : `${m} min` };
}

/** Preenche {{variavel}} do template. Devolve o texto e as variáveis que ficaram sem valor. */
export function preencherTemplate(texto: string, vars: Record<string, string | null | undefined>): { texto: string; faltando: string[] } {
  const faltando: string[] = [];
  const out = texto.replace(/\{\{\s*(\w+)\s*\}\}/g, (bruto, nome: string) => {
    const v = vars[nome];
    if (v == null || !String(v).trim()) {
      if (!faltando.includes(nome)) faltando.push(nome);
      return bruto;
    }
    return String(v);
  });
  return { texto: out, faltando };
}

/** Chave do dia local (AAAA-MM-DD) para agrupar mensagens. */
export function chaveDia(iso: string): string {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Separador por dia: "Hoje", "Ontem" ou a data por extenso. */
export function rotuloDia(iso: string, agora: Date): string {
  const d = new Date(iso);
  const zero = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const dias = Math.round((zero(agora) - zero(d)) / 86400000);
  if (dias === 0) return 'Hoje';
  if (dias === 1) return 'Ontem';
  return d.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long' });
}

/** Primeiro nome, para a mensagem sair pelo nome do lead (playbook). */
export function primeiroNome(nome: string | null | undefined): string {
  const n = String(nome ?? '').trim();
  // Marcador da base ("(sem nome)") não é nome: sem primeiro nome, a tela fala "o lead".
  if (/^\(.*\)$/.test(n)) return '';
  return n.split(/\s+/)[0] ?? '';
}

/** Playbook: mensagem sem emoji. */
export function temEmoji(texto: string): boolean {
  return /\p{Extended_Pictographic}/u.test(texto);
}

export interface ResumoCaixa {
  /** Conversas cuja última mensagem é do lead (esperando a nossa resposta). */
  esperando: number;
  /** Das que esperam, as que passaram do alerta crítico em horário comercial. */
  criticas: number;
  /** Mensagens do lead ainda não lidas, somadas. */
  naoLidas: number;
  /** Conversas sem dono atribuído. */
  semDono: number;
}

/** Números da caixa para a faixa do topo. Não depende da ordem nem do filtro de busca. Só conversa aberta espera. */
export function resumoCaixa(lista: readonly (Pick<Conversa, 'naoLidas' | 'atribuidaA' | 'ultimaMensagem'> & Partial<Pick<Conversa, 'atendimento'>>)[], agora: Date): ResumoCaixa {
  let esperando = 0;
  let criticas = 0;
  let naoLidas = 0;
  let semDono = 0;
  for (const cv of lista) {
    // em espera / encerrada sai da fila de "sem resposta" e do alerta de SLA (20261009153515)
    const e = contaNaFila(cv) ? esperaResposta(cv.ultimaMensagem, agora) : null;
    if (e) {
      esperando += 1;
      if (e.nivel === 'critico') criticas += 1;
    }
    naoLidas += cv.naoLidas;
    if (!cv.atribuidaA) semDono += 1;
  }
  return { esperando, criticas, naoLidas, semDono };
}

/**
 * Trava de envio (mensagem, anexo, áudio): só UM envio em voo por vez (duplo clique / Ctrl+Enter repetido não duplica)
 * e a chave de idempotência do banco (crm_enviar_mensagem p_chave) se mantém enquanto o MESMO conteúdo é reenviado sem
 * sucesso — retry depois de rede instável devolve a mensagem que já foi, em vez de mandar outra. Deu certo (ou mudou o
 * conteúdo) = chave nova na próxima.
 */
export interface TravaEnvio {
  /** Chave para este envio; null = já há um em voo (ignorar o clique). */
  comecar(conteudo: string): string | null;
  terminar(ok: boolean): void;
  emVoo(): boolean;
}

export function criarTravaEnvio(gerar: () => string = () => crypto.randomUUID()): TravaEnvio {
  let voando = false;
  let assinatura: string | null = null;
  let chave: string | null = null;
  return {
    comecar(conteudo) {
      if (voando) return null;
      voando = true;
      if (!chave || conteudo !== assinatura) { assinatura = conteudo; chave = gerar(); }
      return chave;
    },
    terminar(ok) {
      voando = false;
      if (ok) { chave = null; assinatura = null; }
    },
    emVoo: () => voando,
  };
}
