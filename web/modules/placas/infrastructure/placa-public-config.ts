import { unstable_cache } from 'next/cache';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';

// Dados públicos do formulário /solicitar-placa lidos no SERVIDOR e cacheados (1 h):
//  - turmas THB (public.thb_turmas, tipo='thb');
//  - link de WhatsApp da Secretaria (gps.whatsapp_secretaria()).
// Cache: cada leitura é uma entrada separada do Data Cache do Next — a falha de uma não derruba a
// outra. Falha LANÇA dentro da função cacheada (unstable_cache não guarda exceção), então erro
// nunca fica 1 h em cache; quem chama recebe null e aplica o fallback.
// O número da Secretaria nunca é logado: só vira o href do botão.

export const PLACA_PUBLIC_CACHE_TAG = 'placa-public-config';
const REVALIDATE_S = 3600;
export const MENSAGEM_AJUDA_WHATSAPP = 'Olá, preciso de ajuda com minha solicitação de placa';

/** Chave de ordenação "natural" de código de turma: T9 < T17 < T17R < T29 < T29.2 < T30. */
function chaveTurma(codigo: string): [number, number, string] {
  const m = /^T(\d+)(?:\.(\d+))?(.*)$/i.exec(codigo.trim());
  if (!m) return [Number.MAX_SAFE_INTEGER, 0, codigo];
  return [Number(m[1]), m[2] ? Number(m[2]) : 0, m[3] ?? ''];
}

/** Códigos únicos, não vazios, em ordem numérica. */
export function ordenarTurmas(codigos: Array<string | null | undefined>): string[] {
  const unicos = Array.from(new Set(codigos.map((c) => String(c ?? '').trim()).filter(Boolean)));
  return unicos.sort((a, b) => {
    const [na, sa, xa] = chaveTurma(a);
    const [nb, sb, xb] = chaveTurma(b);
    return na - nb || sa - sb || xa.localeCompare(xb);
  });
}

/** Link wa.me com mensagem pronta. Número inválido/ausente → null (o botão não é renderizado). */
export function montarLinkWhatsapp(numero: unknown, mensagem = MENSAGEM_AJUDA_WHATSAPP): string | null {
  if (typeof numero !== 'string' && typeof numero !== 'number') return null;
  let d = String(numero).replace(/\D/g, '');
  if (d.length === 10 || d.length === 11) d = `55${d}`; // DDD + número sem DDI
  if (!/^55\d{10,11}$/.test(d)) return null;
  return `https://wa.me/${d}?text=${encodeURIComponent(mensagem)}`;
}

const lerTurmasCache = unstable_cache(
  async (): Promise<string[]> => {
    const { data, error } = await createAdminSupabase().from('thb_turmas').select('codigo').eq('tipo', 'thb');
    if (error) throw new Error('thb_turmas indisponível');
    const turmas = ordenarTurmas(((data as { codigo: string | null }[]) ?? []).map((r) => r.codigo));
    if (!turmas.length) throw new Error('thb_turmas vazio'); // lista vazia não é cacheada
    return turmas;
  },
  ['placa-public-turmas-v1'],
  { revalidate: REVALIDATE_S, tags: [PLACA_PUBLIC_CACHE_TAG] },
);

const lerAjudaCache = unstable_cache(
  async (): Promise<string | null> => {
    const { data, error } = await createAdminSupabase().schema('gps').rpc('whatsapp_secretaria');
    if (error) throw new Error('whatsapp_secretaria indisponível');
    // Número não configurado é resultado válido (cacheia null); só erro de leitura não é cacheado.
    return montarLinkWhatsapp(data);
  },
  ['placa-public-ajuda-v1'],
  { revalidate: REVALIDATE_S, tags: [PLACA_PUBLIC_CACHE_TAG] },
);

export interface PlacaPublicConfig {
  /** null = leitura falhou → a page usa a lista fixa. */
  turmas: string[] | null;
  /** null = sem número (ou falha) → botão de ajuda não aparece. */
  ajudaHref: string | null;
}

/** Nunca lança. Até 2 consultas ao banco, só em cache frio (no máximo 1×/h por instância). */
export async function readPlacaPublicConfig(): Promise<PlacaPublicConfig> {
  const [turmas, ajudaHref] = await Promise.all([
    lerTurmasCache().catch(() => null),
    lerAjudaCache().catch(() => null),
  ]);
  return { turmas, ajudaHref };
}
