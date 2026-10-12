import { describe, expect, it } from 'vitest';
import { CHAVE_BLACK } from './fixtures/catalogo';
import { modoDemo } from './fonte';
import { fonteSupabaseBlack } from './fonte-supabase';

describe('escolha da fonte', () => {
  it('modo demonstração só com flag "1" e fora de produção', () => {
    expect(modoDemo('production', '1')).toBe(false);
    expect(modoDemo('development', '1')).toBe(true);
    expect(modoDemo('development', 'true')).toBe(false);
    expect(modoDemo('development', undefined)).toBe(false);
    expect(modoDemo(undefined, '1')).toBe(true);
  });
  it('fonte real: semDado em tudo, sem dado inventado', async () => {
    const p = { de: '2026-10-12', ate: '2026-10-20' };
    const r = await Promise.all([
      fonteSupabaseBlack.config(CHAVE_BLACK), fonteSupabaseBlack.trafego(CHAVE_BLACK, p), fonteSupabaseBlack.perfil(CHAVE_BLACK, p),
      fonteSupabaseBlack.leads(CHAVE_BLACK, ['x']), fonteSupabaseBlack.mensageria(CHAVE_BLACK, p), fonteSupabaseBlack.marcos(CHAVE_BLACK),
    ]);
    expect(r.every((x) => x.semDado)).toBe(true);
    expect((await fonteSupabaseBlack.trafego(CHAVE_BLACK, p)).data.dias).toEqual([]);
  });
});
