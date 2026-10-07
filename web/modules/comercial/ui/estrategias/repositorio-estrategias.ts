'use client';

// Fonte das Estratégias: mesma chave da do CRM (NEXT_PUBLIC_COMERCIAL_FONTE=supabase → banco; senão demonstração).
import { publicEnv } from '@/shared/infrastructure/config/env';
import type { EstrategiasRepository } from '../../application/estrategias-ports';
import { MockEstrategiasRepository } from '../../infrastructure/mock-estrategias';
import { SupabaseEstrategiasRepository } from '../../infrastructure/supabase-estrategias.repository';

export const repoEstrategias: EstrategiasRepository = publicEnv.comercialFonte === 'supabase'
  ? new SupabaseEstrategiasRepository()
  : new MockEstrategiasRepository();
