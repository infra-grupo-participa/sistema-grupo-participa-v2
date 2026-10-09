// Agendar mensagem e lembrete pelo painel da conversa (migration 20261009153515). Regras puras, espelho de
// crm_agendar_mensagem (o banco confere de novo): entre 1 min e 30 dias, texto até 4.096 caracteres, no oficial a
// janela de 24 h precisa estar aberta na hora marcada (senão, template). A fila de envio revalida tudo na hora.

export const AGENDAR_MIN_MS = 60_000;
export const AGENDAR_MAX_DIAS = 30;

/** Valor do <input type="datetime-local"> (hora local, sem segundos). */
export function paraInputLocal(d: Date): string {
  const p = (x: number) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

/** Atalho "Lembrar em 1h": agora + 1 h, minutos arredondados para cima de 5 em 5. */
export function emUmaHora(agora: Date): Date {
  const d = new Date(agora.getTime() + 3_600_000);
  d.setSeconds(0, 0);
  d.setMinutes(Math.ceil(d.getMinutes() / 5) * 5);
  return d;
}

/** Atalho "Amanhã 9h". */
export function amanha9h(agora: Date): Date {
  const d = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate() + 1, 9, 0, 0, 0);
  return d;
}

/** Motivo para não agendar (null = pode). `janelaAteEm` só conta no oficial com texto livre. */
export function motivoNaoAgendar(p: {
  texto: string; quando: Date | null; agora: Date; oficial: boolean; comTemplate: boolean; janelaAteEm: string | null;
}): string | null {
  if (!p.comTemplate && !p.texto.trim()) return 'Escreva a mensagem.';
  if (!p.comTemplate && p.texto.trim().length > 4096) return 'Mensagem longa demais (máximo 4.096 caracteres).';
  if (!p.quando || Number.isNaN(p.quando.getTime())) return 'Escolha data e hora.';
  const ms = p.quando.getTime() - p.agora.getTime();
  if (ms < AGENDAR_MIN_MS) return 'Escolha um horário no futuro.';
  if (ms > AGENDAR_MAX_DIAS * 86_400_000) return `Agende para no máximo ${AGENDAR_MAX_DIAS} dias.`;
  if (p.oficial && !p.comTemplate) {
    const fim = p.janelaAteEm ? new Date(p.janelaAteEm).getTime() : NaN;
    if (!(fim > p.quando.getTime())) return 'A janela de 24 h estará fechada nesse horário: agende um template aprovado ou escolha um horário antes.';
  }
  return null;
}

/** "Agendada para qui., 10/10 às 09:00". */
export function rotuloAgendada(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return 'Agendada';
  const dia = d.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' });
  const hora = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  return `Agendada para ${dia} às ${hora}`;
}

/** Link compartilhável da conversa: sempre o domínio oficial (nunca o Host da requisição). */
export const ORIGEM_APP = 'https://grupoparticipa.app.br';
export function linkDaConversa(contatoId: string): string {
  return `${ORIGEM_APP}/comercial/conversas?contato=${encodeURIComponent(contatoId)}`;
}
