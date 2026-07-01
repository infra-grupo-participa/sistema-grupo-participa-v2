'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { parsePlacasConfig, type PlacasConfig, type PlacasConfigKey } from '../../domain/config';

// Camada de dados das CONFIGURAÇÕES de placas (browser, sessão do usuário → RLS).

const db = () => createBrowserSupabase();

/** Lê todas as chaves de config e devolve o bundle normalizado. */
export async function loadPlacasConfig(): Promise<PlacasConfig> {
  const { data } = await db().from('thb_placas_config').select('key, value');
  const raw: Record<string, unknown> = {};
  for (const row of (data as { key: string; value: unknown }[]) ?? []) raw[row.key] = row.value;
  return parsePlacasConfig(raw);
}

/** Grava (upsert) o valor de uma chave de config. */
export async function savePlacasConfig(key: PlacasConfigKey, value: unknown): Promise<boolean> {
  const { error } = await db()
    .from('thb_placas_config')
    .upsert({ key, value, updated_at: new Date().toISOString() }, { onConflict: 'key' });
  return !error;
}
