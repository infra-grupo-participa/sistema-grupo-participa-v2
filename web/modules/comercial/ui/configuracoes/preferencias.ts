// Regras puras da aba #notificacoes: rascunho das preferências, horário de silêncio e o que dizer sobre a
// permissão do navegador. Quem decide se um aviso vai para o desktop é `regras-notificacao.ts`.
import type { GatilhoNotificacao, PreferenciasNotificacao } from '../../domain/types';

export type PermissaoNavegador = NotificationPermission | 'unsupported';

export const SILENCIO_PADRAO = { inicio: '20:00', fim: '08:00' } as const;

const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;
export function horaValida(s: string | null | undefined): boolean {
  return !!s && HORA.test(s);
}

export function alternarGatilho(p: PreferenciasNotificacao, g: GatilhoNotificacao, ligado: boolean): PreferenciasNotificacao {
  return { ...p, gatilhos: { ...p.gatilhos, [g]: ligado } };
}

/** Liga (com o padrão 20h–8h quando não havia horário) ou desliga o silêncio. */
export function definirSilencio(p: PreferenciasNotificacao, ligado: boolean): PreferenciasNotificacao {
  if (!ligado) return { ...p, silencioInicio: null, silencioFim: null };
  return { ...p, silencioInicio: p.silencioInicio ?? SILENCIO_PADRAO.inicio, silencioFim: p.silencioFim ?? SILENCIO_PADRAO.fim };
}

/** Mensagem de erro ou null quando dá para salvar. */
export function validarPreferencias(p: PreferenciasNotificacao): string | null {
  const ini = p.silencioInicio;
  const fim = p.silencioFim;
  if (ini == null && fim == null) return null;
  if (!horaValida(ini) || !horaValida(fim)) return 'Preencha o início e o fim do silêncio (HH:MM).';
  if (ini === fim) return 'Início e fim do silêncio não podem ser iguais.';
  return null;
}

export function preferenciasIguais(a: PreferenciasNotificacao, b: PreferenciasNotificacao): boolean {
  if (a.desktop !== b.desktop || a.silencioInicio !== b.silencioInicio || a.silencioFim !== b.silencioFim) return false;
  const chaves = new Set([...Object.keys(a.gatilhos), ...Object.keys(b.gatilhos)]) as Set<GatilhoNotificacao>;
  return [...chaves].every((k) => !!a.gatilhos[k] === !!b.gatilhos[k]);
}

export interface EstadoPermissao {
  rotulo: string;
  explicacao: string;
  /** Mostra o botão "Permitir neste computador". */
  podePedir: boolean;
  liberada: boolean;
}

export function estadoPermissao(p: PermissaoNavegador): EstadoPermissao {
  switch (p) {
    case 'granted':
      return { rotulo: 'Permitido neste computador', explicacao: 'O navegador mostra os avisos mesmo com a aba em segundo plano.', podePedir: false, liberada: true };
    case 'denied':
      return {
        rotulo: 'Bloqueado pelo navegador',
        explicacao: 'Para liberar: clique no cadeado ao lado do endereço, em Notificações escolha Permitir e recarregue a página.',
        podePedir: false, liberada: false,
      };
    case 'default':
      return { rotulo: 'Ainda não permitido', explicacao: 'O navegador pergunta uma vez. Sem permissão, os avisos ficam só no sino.', podePedir: true, liberada: false };
    default:
      return { rotulo: 'Navegador sem suporte', explicacao: 'Este navegador não mostra avisos no desktop. Use Chrome, Edge, Firefox ou Safari atualizados.', podePedir: false, liberada: false };
  }
}

/** Texto curto do silêncio ("20:00 às 08:00" ou "Desligado"). */
export function textoSilencio(p: Pick<PreferenciasNotificacao, 'silencioInicio' | 'silencioFim'>): string {
  return p.silencioInicio && p.silencioFim ? `${p.silencioInicio} às ${p.silencioFim}` : 'Desligado';
}
