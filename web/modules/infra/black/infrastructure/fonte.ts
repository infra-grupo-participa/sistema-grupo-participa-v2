// Escolha da fonte do dashboard da Black. Demonstração (dado fictício) só com NEXT_PUBLIC_BLACK_DEMO=1 fora de
// produção; no resto, a fonte real (hoje: semDado em tudo, sem rede).
// O teste `process.env.NODE_ENV !== 'production'` fica INLINE de propósito: o Next troca por constante no
// build de produção e o webpack descarta o import() inteiro, então nenhum byte da base fictícia entra no
// bundle de produção (conferido com grep "Lead Teste" em .next; ver docs/dashboard-black/README.md).
import { modoDemoBlack, publicEnv } from '@/shared/infrastructure/config/env';
import type { FonteDadosBlack } from '../application/ports';
import { fonteSupabaseBlack } from './fonte-supabase';

export const modoDemo = modoDemoBlack;

export async function obterFonte(relogio?: string | null): Promise<FonteDadosBlack> {
  if (process.env.NODE_ENV !== 'production' && publicEnv.blackDemo) {
    const { criarFonteFixtures } = await import('./fixtures/fonte-fixtures');
    return criarFonteFixtures(relogio);
  }
  return fonteSupabaseBlack;
}
