// Domínio puro dos highlights de depoimento — porta da normalização de processar-highlights.php.

export type HighlightTipo = 'citacao' | 'objecao' | 'transformacao' | 'gancho';
export interface Highlight {
  texto: string;
  tipo: HighlightTipo;
}
export interface AntesDepois {
  antes: string;
  depois: string;
}
export interface HighlightsResult {
  highlights: Highlight[];
  objecao: string | null;
  antes_depois: AntesDepois | null;
  gancho: string | null;
  resumo: string | null;
  metricas: string[];
}

const cut = (s: string, n: number) => Array.from(String(s ?? '').trim()).slice(0, n).join('');

/** Normaliza a saída JSON do Groq nos limites/whitelist exatos do legado. */
export function parseGroqHighlights(parsed: Record<string, unknown> | null): HighlightsResult {
  const out: HighlightsResult = { highlights: [], objecao: null, antes_depois: null, gancho: null, resumo: null, metricas: [] };
  if (!parsed || typeof parsed !== 'object') return out;

  for (const hl of (Array.isArray(parsed.highlights) ? parsed.highlights : []) as unknown[]) {
    if (!hl || typeof hl !== 'object') continue;
    const texto = String((hl as Record<string, unknown>).texto ?? '').trim();
    if (!texto) continue;
    const tipoRaw = String((hl as Record<string, unknown>).tipo ?? 'citacao').toLowerCase().trim();
    const tipo = (['citacao', 'objecao', 'transformacao', 'gancho'].includes(tipoRaw) ? tipoRaw : 'citacao') as HighlightTipo;
    out.highlights.push({ texto: cut(texto, 320), tipo });
    if (out.highlights.length >= 8) break;
  }

  const objecao = cut(String(parsed.objecao ?? ''), 400);
  const gancho = cut(String(parsed.gancho ?? ''), 280);
  const resumo = cut(String(parsed.resumo ?? ''), 280);
  out.objecao = objecao || null;
  out.gancho = gancho || null;
  out.resumo = resumo || null;

  const ad = parsed.antes_depois;
  if (ad && typeof ad === 'object') {
    const antes = String((ad as Record<string, unknown>).antes ?? '').trim();
    const depois = String((ad as Record<string, unknown>).depois ?? '').trim();
    if (antes || depois) out.antes_depois = { antes: cut(antes, 400), depois: cut(depois, 400) };
  }

  for (const m of (Array.isArray(parsed.metricas) ? parsed.metricas : []) as unknown[]) {
    const texto = cut(String(m ?? ''), 200);
    if (texto) out.metricas.push(texto);
    if (out.metricas.length >= 6) break;
  }
  return out;
}

/** Transcrição apta a gerar highlights? (>= 80 chars, porta da guarda do legado). */
export function transcriptApto(transcript: string | null | undefined): boolean {
  const t = String(transcript ?? '').trim();
  return t.length >= 80;
}
