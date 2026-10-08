// Excluir conversa (ex.: mensagem de teste). Regras puras, ESPELHO de public.crm_excluir_conversa
// (migration 20261008190613; o banco continua mandando): só o gestor de verdade (crm.config.gestores) exclui; leitor e
// vendedor, não. Motivo obrigatório de 5 a 300 caracteres. A exclusão é lógica: some do CRM para todos, nada muda no
// WhatsApp do cliente. Mensagem nova do mesmo telefone depois disso abre conversa nova.
import type { Conversa, SessaoComercial } from './types';

type Quem = Pick<SessaoComercial, 'papel'> | null | undefined;

export const MOTIVO_MIN = 5;
export const MOTIVO_MAX = 300;

/** Só o gestor do Comercial vê o "Excluir conversa" (o leitor vê tudo, mas não altera). */
export function podeExcluirConversa(quem: Quem): boolean {
  return quem?.papel === 'gestor';
}

/** null = motivo ok. */
export function erroMotivoExclusao(motivo: string): string | null {
  const m = motivo.trim();
  if (m.length < MOTIVO_MIN) return `Escreva o motivo (mínimo ${MOTIVO_MIN} caracteres).`;
  if (m.length > MOTIVO_MAX) return `Motivo longo demais (máximo ${MOTIVO_MAX} caracteres).`;
  return null;
}

/** Aviso do modal de confirmação. */
export function avisoExclusao(mensagens: number): string {
  const n = mensagens === 1 ? 'a 1 mensagem' : `as ${mensagens.toLocaleString('pt-BR')} mensagens`;
  return `A conversa e ${n} somem do CRM para todos. Não apaga nada no WhatsApp do cliente.`;
}

export interface ConversaExcluivel {
  id: string;
  canalId: string | null;
}

/** Conversas (uma por número) que o gestor pode excluir no contato aberto, a mais recente primeiro. */
export function conversasExcluiveis(c: Pick<Conversa, 'conversas'> | null | undefined): ConversaExcluivel[] {
  return (c?.conversas ?? []).filter((x) => !!x.id);
}

/** Mensagens carregadas que pertencem à conversa desse número (para o número do aviso). */
export function mensagensDoCanal(mensagens: { canalId?: string | null }[], canalId: string | null): number {
  return mensagens.filter((m) => (m.canalId ?? null) === canalId).length;
}

/** Caminho de arquivo no bucket crm-midia que o servidor aceita apagar (o mesmo CHECK de crm.mensagem.midia_caminho). */
export function caminhoMidiaValido(c: unknown): c is string {
  return typeof c === 'string' && c.length > 0 && c.length <= 300 && /^[A-Za-z0-9/_.-]+$/.test(c)
    && !c.split('/').some((p) => p === '' || p === '.' || p === '..');
}
