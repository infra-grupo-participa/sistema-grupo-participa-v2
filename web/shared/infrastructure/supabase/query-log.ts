/**
 * Loga erro de query descartado por loaders que retornam fallback ([] / null).
 * Sem isso, falha de RLS/rede vira "lista vazia" silenciosa e impossível de diagnosticar.
 */
export function logQueryError(contexto: string, error: { message?: string } | null | undefined): void {
  if (error) console.error(`[supabase] ${contexto}:`, error.message || error);
}
