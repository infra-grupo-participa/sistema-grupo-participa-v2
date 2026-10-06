// Quando uma notificação vira aviso no desktop. Lógica pura (testável).
import type { GatilhoNotificacao, PreferenciasNotificacao } from '../../domain/types';

export const ROTULO_GATILHO: Record<GatilhoNotificacao, string> = {
  lead_novo: 'Lead novo atribuído a mim',
  lead_respondeu: 'Lead respondeu no WhatsApp',
  prazo_estourado: 'Prazo da etapa estourado',
  venda_aprovada: 'Venda aprovada na Hotmart',
  ficha_para_aprovar: 'Ficha de disparo para aprovar (gestor)',
  atividade_vencendo: 'Atividade vence em 30 minutos',
};

/** "HH:MM" → minutos do dia. */
function minutos(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

/** Dentro do silêncio? Aceita janela que vira a noite (20:00 → 08:00). */
export function emSilencio(p: Pick<PreferenciasNotificacao, 'silencioInicio' | 'silencioFim'>, agora: Date): boolean {
  if (!p.silencioInicio || !p.silencioFim) return false;
  const ini = minutos(p.silencioInicio);
  const fim = minutos(p.silencioFim);
  const t = agora.getHours() * 60 + agora.getMinutes();
  if (ini === fim) return false;
  return ini < fim ? t >= ini && t < fim : t >= ini || t < fim;
}

/** Vira aviso no desktop? Precisa: desktop ligado, gatilho ligado, fora do silêncio. */
export function deveAvisarNoDesktop(p: PreferenciasNotificacao, gatilho: GatilhoNotificacao, agora: Date): boolean {
  return p.desktop && !!p.gatilhos[gatilho] && !emSilencio(p, agora);
}

/** Aviso dentro da tela: vale o gatilho e o silêncio, independente do aviso no desktop estar ligado. */
export function deveAvisarNaTela(p: PreferenciasNotificacao, gatilho: GatilhoNotificacao, agora: Date): boolean {
  return !!p.gatilhos[gatilho] && !emSilencio(p, agora);
}
