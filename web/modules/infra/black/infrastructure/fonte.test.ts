import { describe, expect, it } from 'vitest';
import { modoDemo } from './fonte';

describe('escolha da fonte', () => {
  it('modo demonstração só com flag "1" e fora de produção', () => {
    expect(modoDemo('production', '1')).toBe(false);
    expect(modoDemo('development', '1')).toBe(true);
    expect(modoDemo('development', 'true')).toBe(false);
    expect(modoDemo('development', undefined)).toBe(false);
    expect(modoDemo(undefined, '1')).toBe(true);
  });
  // A fonte real (RPCs simuladas) é testada em fonte-supabase.test.ts.
});
