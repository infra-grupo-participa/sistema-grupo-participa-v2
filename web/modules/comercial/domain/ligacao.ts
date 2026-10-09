// "Ligar para o lead" (versão leve): tel: (o celular disca; no Mac abre FaceTime/iPhone) e wa.me (ligação de voz pelo
// app do WhatsApp). Telefonia integrada (Infobip Voice, click-to-call) fica para a próxima etapa. Regras puras.

/** Só dígitos, com DDI 55 quando o número é brasileiro sem DDI (10 ou 11 dígitos). null = não dá para discar. */
export function digitosDiscagem(tel: string | null | undefined): string | null {
  const d = String(tel ?? '').replace(/\D/g, '');
  if (d.length === 10 || d.length === 11) return `55${d}`;
  if (d.length >= 12 && d.length <= 15) return d;
  return null;
}

/** Link tel: com +DDI. */
export function linkTel(tel: string | null | undefined): string | null {
  const d = digitosDiscagem(tel);
  return d ? `tel:+${d}` : null;
}

/** Link wa.me (abre a conversa no app; a ligação de voz é pelo app). */
export function linkWhatsapp(tel: string | null | undefined): string | null {
  const d = digitosDiscagem(tel);
  return d ? `https://wa.me/${d}` : null;
}

/** Resultados rápidos da ligação (os mesmos chips do negócio). */
export const RESULTADOS_LIGACAO = ['Atendeu', 'Não atendeu', 'Caixa postal'] as const;

/** Título da atividade "Ligação" que fica no histórico. */
export function tituloLigacao(nome: string | null | undefined, via: 'telefone' | 'whatsapp'): string {
  const n = String(nome ?? '').trim();
  const quem = n && !/^\(.*\)$/.test(n) ? n.split(/\s+/)[0] : 'o lead';
  return `Ligação para ${quem}${via === 'whatsapp' ? ' (WhatsApp)' : ''}`.slice(0, 200);
}
