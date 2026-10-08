// "Nova conversa" na caixa: escolher o número, a pessoa e começar. Regras puras, ESPELHO de crm_enviar_mensagem
// (o banco continua mandando): número que envia e está conectado, número por QR com dono só para o dono ou o gestor,
// leitor não escreve, opt-out bloqueia, contato sem telefone não recebe WhatsApp, D6 (crm.pode_escrever_pessoa) e a
// janela de 24 h do oficial (fora dela, só template).
import { bloqueioEnvio, type CanalWhatsapp, type PainelCanais } from './canais-whatsapp';
import { MSG_SOMENTE_LEITURA, motivoSemEscrita, somenteLeitura } from './travas';
import type { Contato, Conversa, Negocio, SessaoComercial } from './types';

type Quem = Pick<SessaoComercial, 'vendedorId' | 'papel'> | null | undefined;

/** "Oficial" (Infobip, API) ou "QR" (Evolution). */
export function rotuloProvedor(c: Pick<CanalWhatsapp, 'provedor'>): 'Oficial' | 'QR' {
  return c.provedor === 'evolution' ? 'QR' : 'Oficial';
}

/** Este número pode abrir conversa agora, para quem pergunta? null = pode. */
export function bloqueioCanalNovaConversa(c: CanalWhatsapp, painel: Pick<PainelCanais, 'evolutionLigado' | 'envioLigado'> | null, quem: Quem): string | null {
  if (somenteLeitura(quem)) return MSG_SOMENTE_LEITURA;
  if (painel && !painel.envioLigado) return 'Envio de WhatsApp desligado.';
  if (!c.envia) return 'Este número não envia pelo CRM.';
  if (c.status !== 'conectado') return 'Número desconectado: o gestor reconecta em Configurações.';
  const b = bloqueioEnvio(c, painel);
  if (b) return b;
  if (c.provedor === 'evolution' && c.donoId && c.donoId !== quem?.vendedorId && quem?.papel !== 'gestor') {
    return 'Este número é de outra pessoa.';
  }
  return null;
}

/** Números oferecidos no passo "Número": só os conectados que enviam e que esta pessoa pode usar. */
export function canaisParaNovaConversa(canais: CanalWhatsapp[], painel: Pick<PainelCanais, 'evolutionLigado' | 'envioLigado'> | null, quem: Quem): CanalWhatsapp[] {
  return canais.filter((c) => !bloqueioCanalNovaConversa(c, painel, quem));
}

/** Com um número só, ele já vem escolhido; com vários, quem escolhe é o vendedor. */
export function canalInicialNovaConversa(disponiveis: Pick<CanalWhatsapp, 'id'>[]): string | null {
  return disponiveis.length === 1 ? disponiveis[0].id : null;
}

/**
 * Janela de 24 h DO NÚMERO escolhido. `janelaAteEm` da lista é o da pessoa (último lead em qualquer número): se ela
 * nunca conversou por este número, a janela dele está fechada.
 */
export function janelaDoCanal(conversa: Pick<Conversa, 'janelaAteEm' | 'canais'> | null | undefined, canalId: string | null | undefined): string | null {
  if (!conversa?.janelaAteEm) return null;
  if (canalId && conversa.canais && !conversa.canais.includes(canalId)) return null;
  return conversa.janelaAteEm;
}

export type ModoEnvio = 'livre' | 'template';

/** QR: texto livre sempre. Oficial: texto livre só com a janela de 24 h aberta; fora dela, template aprovado. */
export function modoEnvio(c: Pick<CanalWhatsapp, 'provedor'>, janelaAteEm: string | null, agora: Date): ModoEnvio {
  if (c.provedor === 'evolution') return 'livre';
  const fim = janelaAteEm ? new Date(janelaAteEm).getTime() : NaN;
  return fim > agora.getTime() ? 'livre' : 'template';
}

/** Por que não dá para começar a conversa com esta pessoa (ordem = do banco). null = pode. */
export function bloqueioPessoaNovaConversa(
  c: Pick<Contato, 'donoId' | 'optOut' | 'telefone'>, negociosDaPessoa: Pick<Negocio, 'donoId'>[], quem: Quem, nomeDe: (id: string | null) => string,
): string | null {
  if (somenteLeitura(quem)) return MSG_SOMENTE_LEITURA;
  const d6 = motivoSemEscrita(c, negociosDaPessoa, quem, nomeDe);
  if (d6) return d6;
  if (c.optOut) return 'Este contato pediu para não receber contato. Nenhuma mensagem sai para ele.';
  if (!c.telefone) return 'Contato sem telefone: cadastre o WhatsApp na ficha antes.';
  return null;
}

/** Aviso discreto do número por QR (limites anti-ban do banco). */
export function avisoLimiteQr(p: Pick<PainelCanais, 'limiteMinuto' | 'limiteHora' | 'novosHora'> | null): string {
  const min = p?.limiteMinuto ?? 15;
  const hora = p?.limiteHora ?? 200;
  const novos = p?.novosHora ?? 20;
  return `Número por QR: conversa 1 a 1, sem disparo em massa. Limite de ${min} mensagens por minuto, ${hora} por hora e ${novos} contatos novos por hora.`;
}
