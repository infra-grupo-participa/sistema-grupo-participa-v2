// Áudio gravado pelo computador no CRM (migration 20261007s): formato da gravação, conversão e validação. Regra pura.
// O WhatsApp só mostra como nota de voz o audio/ogg com Opus. Firefox grava ogg/opus direto; Chrome (e Safari novo) gravam
// webm/opus, que viram ogg por remux (ogg-opus.ts, sem reencodar); Safari antigo grava audio/mp4 (AAC), que sai como
// áudio comum (a Infobip aceita). O banco confere tipo e tamanho de novo.

export const LIMITE_AUDIO = 16 * 1024 * 1024;   // teto da Infobip/WhatsApp para áudio
export const DURACAO_MAX_MS = 5 * 60 * 1000;    // a gravação para sozinha em 5 min
export const DURACAO_MIN_MS = 1000;

/** Ordem de preferência no MediaRecorder: ogg/opus (direto) > webm/opus (remux) > mp4/aac (áudio comum). */
export const FORMATOS_GRAVACAO = [
  'audio/ogg;codecs=opus',
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/mp4;codecs=mp4a.40.2',
  'audio/mp4',
  'audio/aac',
] as const;

/** Primeiro formato que o navegador grava; '' = deixa o navegador escolher (decide-se pelo tipo do arquivo depois). */
export function escolherFormato(suporta: (mime: string) => boolean): string {
  for (const f of FORMATOS_GRAVACAO) {
    try { if (suporta(f)) return f; } catch { /* navegador sem isTypeSupported */ }
  }
  return '';
}

export type PlanoAudio = {
  acao: 'direto' | 'remux';
  mime: 'audio/ogg' | 'audio/mp4' | 'audio/aac' | 'audio/mpeg';
  ext: 'ogg' | 'm4a' | 'aac' | 'mp3';
  /** true = chega como nota de voz (ogg/opus) */
  voz: boolean;
};

/** O que fazer com o arquivo gravado, pelo tipo que o MediaRecorder devolveu. null = formato que não dá para enviar. */
export function planoAudio(mimeGravado: string | null | undefined): PlanoAudio | null {
  const m = String(mimeGravado ?? '').toLowerCase().replace(/\s+/g, '');
  const base = m.split(';')[0];
  if (base === 'audio/ogg' || base === 'audio/opus') {
    return /codecs=(?!"?opus)/.test(m) ? null : { acao: 'direto', mime: 'audio/ogg', ext: 'ogg', voz: true };
  }
  if (base === 'audio/webm' || base === 'video/webm') {
    return /codecs=(?!"?opus)/.test(m) ? null : { acao: 'remux', mime: 'audio/ogg', ext: 'ogg', voz: true };
  }
  if (base === 'audio/mp4' || base === 'audio/x-m4a' || base === 'audio/m4a') return { acao: 'direto', mime: 'audio/mp4', ext: 'm4a', voz: false };
  if (base === 'audio/aac') return { acao: 'direto', mime: 'audio/aac', ext: 'aac', voz: false };
  if (base === 'audio/mpeg' || base === 'audio/mp3') return { acao: 'direto', mime: 'audio/mpeg', ext: 'mp3', voz: false };
  return null;
}

/** Extensão × mime aceitos pelo banco (crm_enviar_mensagem confere o mesmo par). */
const MIME_DA_EXT: Record<string, string> = { ogg: 'audio/ogg', m4a: 'audio/mp4', aac: 'audio/aac', mp3: 'audio/mpeg' };

export function extAudioPermitida(ext: string, mime: string): boolean {
  return MIME_DA_EXT[ext] !== undefined && MIME_DA_EXT[ext] === mime;
}

export type AudioInvalido = { ok: false; msg: string };

/** Mesmas regras do banco (tamanho) + duração da gravação. */
export function validarAudio(a: { tamanho: number; duracaoMs: number }): { ok: true } | AudioInvalido {
  if (!a.tamanho || a.tamanho <= 0) return { ok: false, msg: 'A gravação ficou vazia. Grave de novo.' };
  if (a.duracaoMs < DURACAO_MIN_MS) return { ok: false, msg: 'Áudio curto demais. Grave pelo menos 1 segundo.' };
  if (a.duracaoMs > DURACAO_MAX_MS + 2000) return { ok: false, msg: 'Áudio longo demais (máximo 5 minutos).' };
  if (a.tamanho > LIMITE_AUDIO) return { ok: false, msg: 'Áudio grande demais (máximo 16 MB).' };
  return { ok: true };
}

/** 0:07, 1:42, 5:00. */
export function fmtDuracao(ms: number): string {
  const s = Math.max(0, Math.floor((Number.isFinite(ms) ? ms : 0) / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/** Mensagem para a tela quando o navegador recusa o microfone (DOMException.name). */
export function erroMicrofone(nome: string | null | undefined): string {
  switch (nome) {
    case 'NotAllowedError':
    case 'SecurityError':
      return 'Microfone bloqueado. Libere o microfone para este site nas permissões do navegador.';
    case 'NotFoundError':
    case 'OverconstrainedError':
      return 'Nenhum microfone encontrado no computador.';
    case 'NotReadableError':
    case 'AbortError':
      return 'O microfone está em uso por outro programa. Feche-o e tente de novo.';
    default:
      return 'Não foi possível usar o microfone.';
  }
}

export const AVISO_SEM_SUPORTE = 'Este navegador não grava áudio. Use Chrome, Edge, Firefox ou Safari atualizados.';
