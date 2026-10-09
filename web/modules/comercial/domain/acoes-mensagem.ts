// Ações na mensagem da conversa (migration 20261009153515): copiar, responder citando, editar e apagar para todos.
// Regras puras, ESPELHO de crm.mensagem_acao_motivo / crm_responder_mensagem (o banco confere de novo e manda).
// Limites do WhatsApp: editar até 15 min depois do envio; apagar para todos até ~2 dias (48 h).
// O número oficial (API Cloud via Infobip) não tem editar nem apagar; citação no oficial não foi confirmada na doc da
// Infobip, então "Responder citando" fica só no número por QR (Evolution, campo `quoted`).
import type { Mensagem, SessaoComercial } from './types';

export const LIMITE_EDITAR_MIN = 15;
export const LIMITE_APAGAR_H = 48;
export const MOTIVO_OFICIAL = 'O WhatsApp oficial não permite editar ou apagar mensagem enviada';

export type AcaoMensagem = 'copiar' | 'responder' | 'editar' | 'apagar';
export interface EstadoAcao { ok: boolean; motivo: string | null }

type MensagemAcao = Pick<Mensagem, 'direcao' | 'em' | 'status' | 'autorId' | 'tipo' | 'texto'> &
  Partial<Pick<Mensagem, 'externa' | 'apagadaEm' | 'agendadaPara' | 'envio'>>;

export interface ContextoAcao {
  /** Provedor do número da mensagem. */
  provedor: 'infobip' | 'evolution' | null;
  sessao: Pick<SessaoComercial, 'vendedorId' | 'papel'> | null;
  /** Pode escrever para este contato (crm.pode_escrever_pessoa espelhado na tela). */
  podeEscrever: boolean;
  agora: Date;
}

const ok: EstadoAcao = { ok: true, motivo: null };
const nao = (motivo: string): EstadoAcao => ({ ok: false, motivo });

function minutosDesde(iso: string, agora: Date): number {
  const t = new Date(iso).getTime();
  return Number.isNaN(t) ? Infinity : (agora.getTime() - t) / 60000;
}

/** Já saiu no WhatsApp (o provedor aceitou)? Agendada/na fila/falhou ainda não. */
export function jaSaiu(m: Pick<Mensagem, 'status' | 'direcao'> & Partial<Pick<Mensagem, 'envio'>>): boolean {
  return m.direcao === 'saida' && !m.envio && (m.status === 'enviada' || m.status === 'entregue' || m.status === 'lida');
}

/** Editar/apagar: dono da mensagem (quem enviou) ou gestor; mensagem do celular/Clint só o gestor. */
function podeMexer(m: MensagemAcao, sessao: ContextoAcao['sessao']): boolean {
  if (!sessao || sessao.papel === 'leitor') return false;
  if (sessao.papel === 'gestor') return true;
  return !m.externa && !!m.autorId && m.autorId === sessao.vendedorId;
}

/** O que cada ação do menu da mensagem pode fazer agora, com o motivo quando não pode. */
export function acoesDaMensagem(m: MensagemAcao, ctx: ContextoAcao): Record<AcaoMensagem, EstadoAcao> {
  const apagada = !!m.apagadaEm;
  const copiar = apagada || !m.texto.trim() ? nao('Sem texto para copiar.') : ok;

  let responder: EstadoAcao = ok;
  if (apagada) responder = nao('Mensagem apagada.');
  else if (!ctx.podeEscrever) responder = nao(ctx.sessao?.papel === 'leitor' ? 'Acesso só de leitura.' : 'Este contato não é seu.');
  else if (ctx.provedor !== 'evolution') responder = nao('Responder citando só no número por QR.');
  else if (m.direcao === 'saida' && !jaSaiu(m)) responder = nao('A mensagem ainda não saiu no WhatsApp.');

  const editar = motivoEditarApagar(m, ctx, 'editar');
  const apagar = motivoEditarApagar(m, ctx, 'apagar');
  return { copiar, responder, editar, apagar };
}

function motivoEditarApagar(m: MensagemAcao, ctx: ContextoAcao, tipo: 'editar' | 'apagar'): EstadoAcao {
  if (m.direcao !== 'saida') return nao('Só mensagem enviada por nós.');
  if (ctx.provedor === 'infobip') return nao(MOTIVO_OFICIAL);
  if (ctx.provedor !== 'evolution') return nao('Número da mensagem desconhecido.');
  if (m.apagadaEm) return nao('Mensagem já apagada.');
  if (!ctx.podeEscrever || !podeMexer(m, ctx.sessao)) return nao('Só quem enviou (ou o gestor).');
  if (!jaSaiu(m)) return nao('A mensagem ainda não saiu no WhatsApp.');
  const min = minutosDesde(m.em, ctx.agora);
  if (tipo === 'editar') {
    if (m.tipo && m.tipo !== 'texto') return nao('Só mensagem de texto pode ser editada.');
    if (min > LIMITE_EDITAR_MIN) return nao(`O WhatsApp só deixa editar até ${LIMITE_EDITAR_MIN} min depois do envio.`);
  } else if (min > LIMITE_APAGAR_H * 60) {
    return nao('O WhatsApp só deixa apagar para todos até 2 dias depois do envio.');
  }
  return ok;
}

/** Trecho da mensagem citada para o bloco acima da resposta (uma linha). */
export function trechoCitado(texto: string | null | undefined, max = 90): string {
  const t = String(texto ?? '').replace(/\s+/g, ' ').trim();
  if (!t) return 'Mensagem';
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}
