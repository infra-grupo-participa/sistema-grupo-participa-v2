// Formatos de texto da aba Lives. Horário sempre de Brasília (o servidor guarda em UTC).
import type { Live, SituacaoLive, TipoLive } from '../../domain/lives';
import type { Valor } from '../../domain/tipos';

const TZ = 'America/Sao_Paulo';
const F_DIA = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', timeZone: TZ });
const F_HORA = new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: TZ });
const F_SEMANA = new Intl.DateTimeFormat('pt-BR', { weekday: 'short', timeZone: TZ });

export const dataCurta = (iso: string) => F_DIA.format(new Date(iso));
export const horaDe = (iso: string) => F_HORA.format(new Date(iso));
export const semanaDe = (iso: string) => F_SEMANA.format(new Date(iso)).replace('.', '');
/** "ter 06/10 19:30" */
export const quando = (iso: string) => `${semanaDe(iso)} ${dataCurta(iso)} ${horaDe(iso)}`;
export const dataHoraTexto = (iso: string) => `${dataCurta(iso)} ${horaDe(iso)}`;

/** "5 min", "2 h", "1 dia": idade de uma leitura. */
export function idadeTexto(iso: string | null, agoraMs: number): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return null;
  const min = Math.max(0, Math.round((agoraMs - t) / 60_000));
  if (min < 1) return 'agora há pouco';
  if (min < 60) return `há ${min} min`;
  if (min < 60 * 48) return `há ${Math.round(min / 60)} h`;
  return `há ${Math.round(min / 1440)} dias`;
}

/**
 * Posição na live em "m:ss" ou "h:mm:ss". Negativa = mensagem de antes do início da live (o banco guarda seg < 0):
 * "-1:42:57" é 1h42m57s antes de começar.
 */
export function posicaoTexto(seg: number): string {
  const a = Math.abs(Math.trunc(seg));
  const h = Math.floor(a / 3600); const m = Math.floor((a % 3600) / 60); const s = a % 60;
  const t = h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`;
  return seg < 0 ? `-${t}` : t;
}

/** Cor de cada tipo de live: a mesma no cronograma, na evolução e nos cartões. */
export const COR_TIPO: Record<TipoLive, string> = { consultoria: 'var(--cyan)', produto: 'var(--purple)', black: 'var(--accent)' };
export const COR_SITUACAO: Record<SituacaoLive, string> = {
  realizada: 'var(--green)', ao_vivo: 'var(--red)', em_breve: 'var(--fg-3)', a_agendar: 'var(--yellow)',
};
export const DICA_SITUACAO: Record<SituacaoLive, string> = {
  realizada: 'A live já aconteceu.',
  ao_vivo: 'A live está no ar agora.',
  em_breve: 'A live ainda não começou.',
  a_agendar: 'A API do YouTube ainda não encontrou o vídeo desta live.',
};

export const SEM_TITULO = 'Título ainda não disponível na API do YouTube';
export const tituloDe = (l: Pick<Live, 'titulo'>) => l.titulo ?? SEM_TITULO;

/** Percentual com uma casa, vindo de uma fração. null = "Sem dado". */
export const pctDe = (f: number | null) => (f === null ? 'Sem dado' : `${new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(f * 100)}%`);
export const numeroDe = (v: Valor) => (v === null ? 'Sem dado' : new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 }).format(v));
