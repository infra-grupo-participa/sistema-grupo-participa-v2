// "midia" do jsonb de crm.mensagem_json (migration 20261007140044) → MidiaMensagem. Puro e testado.
import type { MidiaMensagem, StatusMidia } from '../domain/types';

const STATUS: readonly StatusMidia[] = ['pendente', 'ok', 'grande_demais', 'falhou'];
const CAMINHO = /^[A-Za-z0-9/_.-]{1,300}$/;

/** Formato inesperado vira null (a mensagem continua aparecendo como texto). Caminho só com status ok. */
export function mapMidia(x: unknown): MidiaMensagem | null {
  if (!x || typeof x !== 'object' || Array.isArray(x)) return null;
  const o = x as Record<string, unknown>;
  const status = STATUS.find((s) => s === o.status);
  if (!status) return null;
  const caminho = status === 'ok' && typeof o.caminho === 'string' && CAMINHO.test(o.caminho) && !o.caminho.includes('..') ? o.caminho : null;
  const tamanho = typeof o.tamanho === 'number' && Number.isFinite(o.tamanho) && o.tamanho >= 0 ? o.tamanho : null;
  return {
    status: status === 'ok' && !caminho ? 'falhou' : status,
    caminho,
    mime: typeof o.mime === 'string' && o.mime ? o.mime : null,
    tamanho,
    nome: typeof o.nome === 'string' && o.nome.trim() ? o.nome : null,
  };
}
