// Arquivos do WhatsApp do CRM (migration 20261007140044): regra pura de exibição e de anexo. Sem React, sem Supabase.
import type { Mensagem, MidiaMensagem } from './types';

export type TipoMidia = 'imagem' | 'audio' | 'documento' | 'video';

const TIPOS_MIDIA: readonly string[] = ['imagem', 'audio', 'documento', 'video'];

/** Tipo de mídia que a mensagem mostra como arquivo; null = mensagem de texto (inclusive as antigas "[imagem]"). */
export function tipoMidia(m: Pick<Mensagem, 'tipo' | 'midia'>): TipoMidia | null {
  if (!m.midia || !m.tipo || !TIPOS_MIDIA.includes(m.tipo)) return null;
  return m.tipo as TipoMidia;
}

const ROTULO = /^\[(imagem|documento|vídeo|video|áudio|audio)\](?:\s+|$)/i;

/**
 * Texto que acompanha o arquivo. O banco guarda "[imagem] legenda" / "[documento] nome.pdf" / "[áudio]": com o arquivo
 * na tela, o rótulo sai. Sem arquivo (mensagem antiga ou falha), o texto fica como veio.
 */
export function legendaDaMensagem(m: Pick<Mensagem, 'tipo' | 'midia' | 'texto'>): string {
  if (!tipoMidia(m)) return m.texto;
  let t = m.texto.replace(ROTULO, '').trim();
  // documento enviado sem legenda: o banco escreve "[documento] <nome>" — o nome já aparece no cartão do arquivo
  if (m.tipo === 'documento' && m.midia?.nome && t === m.midia.nome) t = '';
  return t;
}

/** "1,2 MB", "830 KB", "12 B". null/indefinido = ''. */
export function fmtTamanho(bytes: number | null | undefined): string {
  if (bytes == null || !Number.isFinite(bytes) || bytes < 0) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${Math.round(bytes / 1024).toLocaleString('pt-BR')} KB`;
  return `${(bytes / 1048576).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} MB`;
}

/** Nome para mostrar/baixar o arquivo. */
export function nomeArquivo(m: Pick<Mensagem, 'tipo' | 'midia'>): string {
  const nome = m.midia?.nome?.trim();
  if (nome) return nome;
  const ext = m.midia?.caminho?.match(/\.([a-z0-9]{1,8})$/i)?.[1]?.toLowerCase();
  const base = m.tipo === 'imagem' ? 'imagem' : m.tipo === 'audio' ? 'audio' : m.tipo === 'video' ? 'video' : 'documento';
  return ext ? `${base}.${ext}` : base;
}

/** Aviso quando o arquivo não está disponível (null = disponível ou ainda baixando). */
export function avisoMidia(midia: MidiaMensagem | null | undefined): string | null {
  if (!midia) return null;
  if (midia.status === 'grande_demais') return `Arquivo grande demais para guardar${midia.tamanho ? ` (${fmtTamanho(midia.tamanho)})` : ''}. Peça para o lead reenviar menor.`;
  if (midia.status === 'falhou') return 'Não foi possível baixar este arquivo do WhatsApp.';
  return null;
}

/** Áudio do WhatsApp (ogg/opus) que o navegador pode não tocar. */
export function ehOggOpus(mime: string | null | undefined): boolean {
  return /^audio\/(ogg|opus)/i.test(String(mime ?? ''));
}

// ── Anexo enviado pelo vendedor ──

export const LIMITE_IMAGEM = 5 * 1024 * 1024;
export const LIMITE_PDF = 16 * 1024 * 1024;
export const LIMITE_LEGENDA = 1024;
const EXT_POR_MIME: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf' };

export type AnexoValido = { ok: true; tipo: 'imagem' | 'documento'; ext: string; mime: string; nome: string };
export type AnexoInvalido = { ok: false; msg: string };

/** Barra e caracteres de controle viram "_" (o banco faz o mesmo no nome do PDF). */
function semControle(s: string): string {
  return Array.from(s, (c) => (c === '/' || c === '\\' || c.charCodeAt(0) < 32 ? '_' : c)).join('');
}

/** Mesmas regras de crm_enviar_mensagem (o banco confere de novo): JPG/PNG/WebP até 5 MB, PDF até 16 MB. */
export function validarAnexo(a: { type: string; size: number; name: string }): AnexoValido | AnexoInvalido {
  const mime = String(a.type || '').toLowerCase();
  const ext = EXT_POR_MIME[mime];
  if (!ext) return { ok: false, msg: 'Só imagem (JPG, PNG, WebP) ou PDF.' };
  if (!a.size) return { ok: false, msg: 'Arquivo vazio.' };
  const tipo = ext === 'pdf' ? 'documento' : 'imagem';
  const limite = tipo === 'documento' ? LIMITE_PDF : LIMITE_IMAGEM;
  if (a.size > limite) return { ok: false, msg: `Arquivo grande demais (máximo ${limite / 1048576} MB).` };
  const nome = semControle(a.name || '').trim().slice(0, 120) || (tipo === 'documento' ? 'documento.pdf' : `imagem.${ext}`);
  return { ok: true, tipo, ext, mime, nome };
}

/** Caminho do upload no bucket crm-midia: envio/<meu id>/<uuid>.<ext> (a policy do Storage só aceita este formato). */
export function caminhoAnexo(perfilId: string, uuid: string, ext: string): string {
  return `envio/${perfilId}/${uuid}.${ext}`;
}

/**
 * O arquivo subido para o envio ficou sem mensagem? Envio recusado, ou repetido pela chave de idempotência (a mensagem
 * já usa o arquivo da 1ª tentativa). Aí o upload desta tentativa é apagado do bucket.
 */
export function uploadSobrou(r: { ok: boolean; repetida?: boolean }): boolean {
  return !r.ok || r.repetida === true;
}
