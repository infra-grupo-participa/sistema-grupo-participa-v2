import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { parsePlacasConfig, type PlacasConfig } from '../domain/config';

// Leitura server-side das configurações de placas (usa admin client — ignora RLS).
// Consumida pela rota de e-mail e pela page pública do formulário.

/** Lê o bundle completo de config (server). Nunca lança — devolve defaults em erro. */
export async function readPlacasConfig(): Promise<PlacasConfig> {
  try {
    const { data } = await createAdminSupabase().from('thb_placas_config').select('key, value');
    const raw: Record<string, unknown> = {};
    for (const row of (data as { key: string; value: unknown }[]) ?? []) raw[row.key] = row.value;
    return parsePlacasConfig(raw);
  } catch {
    return parsePlacasConfig(null);
  }
}
