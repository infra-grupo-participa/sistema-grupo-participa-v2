import { beforeEach, describe, expect, it, vi } from 'vitest';

const estado = vi.hoisted(() => ({
  turmas: { data: null as unknown, error: null as unknown },
  rpc: { data: null as unknown, error: null as unknown },
  rpcSchema: '',
}));

vi.mock('next/cache', () => ({ unstable_cache: (fn: (...a: unknown[]) => unknown) => fn }));
vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({
  createAdminSupabase: () => ({
    from: () => ({ select: () => ({ eq: async () => estado.turmas }) }),
    schema: (s: string) => {
      estado.rpcSchema = s;
      return { rpc: async () => estado.rpc };
    },
  }),
}));

import { montarLinkWhatsapp, ordenarTurmas, readPlacaPublicConfig } from './placa-public-config';

describe('ordenarTurmas', () => {
  it('ordena numericamente, com sufixos depois da base e sem duplicar', () => {
    expect(ordenarTurmas(['T10', 'T2', 'T40', 'T39', 'T17R', 'T17', 'T29.2', 'T29', 'T1', 'T2', '', null])).toEqual([
      'T1', 'T2', 'T10', 'T17', 'T17R', 'T29', 'T29.2', 'T39', 'T40',
    ]);
  });
});

describe('montarLinkWhatsapp', () => {
  it('monta wa.me com DDI e mensagem codificada', () => {
    expect(montarLinkWhatsapp('+55 (11) 99999-0000')).toBe(
      'https://wa.me/5511999990000?text=Ol%C3%A1%2C%20preciso%20de%20ajuda%20com%20minha%20solicita%C3%A7%C3%A3o%20de%20placa',
    );
  });
  it('acrescenta 55 quando vem só DDD + número', () => {
    expect(montarLinkWhatsapp('11999990000')).toMatch(/^https:\/\/wa\.me\/5511999990000\?/);
  });
  it('número ausente ou inválido → null', () => {
    expect(montarLinkWhatsapp(null)).toBeNull();
    expect(montarLinkWhatsapp('')).toBeNull();
    expect(montarLinkWhatsapp('123')).toBeNull();
    expect(montarLinkWhatsapp({})).toBeNull();
  });
});

describe('readPlacaPublicConfig', () => {
  beforeEach(() => {
    estado.turmas = { data: [{ codigo: 'T41' }, { codigo: 'T3' }], error: null };
    estado.rpc = { data: '5511999990000', error: null };
  });
  it('lê turmas ordenadas e o link pelo schema gps', async () => {
    const r = await readPlacaPublicConfig();
    expect(r.turmas).toEqual(['T3', 'T41']);
    expect(r.ajudaHref).toMatch(/^https:\/\/wa\.me\/5511999990000\?text=/);
    expect(estado.rpcSchema).toBe('gps');
  });
  it('falha de leitura vira null sem lançar (page aplica o fallback)', async () => {
    estado.turmas = { data: null, error: { message: 'x' } };
    estado.rpc = { data: null, error: { message: 'y' } };
    await expect(readPlacaPublicConfig()).resolves.toEqual({ turmas: null, ajudaHref: null });
  });
  it('turmas vazias também caem no fallback', async () => {
    estado.turmas = { data: [], error: null };
    expect((await readPlacaPublicConfig()).turmas).toBeNull();
  });
});
