import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

const AUTOR = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const ALVO = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const rpc = vi.fn();
const update = vi.fn();
const generateLink = vi.fn();

vi.mock('@/shared/composition/acesso-departamentos', () => ({ ACESSO_DEPARTAMENTOS: { acessoV2: true } }));
vi.mock('@/shared/composition/server-container', () => ({
  getCurrentUser: async () => ({ id: AUTOR, cargo: 'visualizador', acesso: { master: true } }),
}));
vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({
  createAdminSupabase: () => ({
    rpc,
    auth: { admin: { generateLink } },
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { id: ALVO, cargo: 'visualizador' } }) }) }),
      update,
    }),
  }),
}));

const { PATCH, POST } = await import('./route');
const request = (method: 'PATCH' | 'POST', body: Record<string, unknown>) => new NextRequest('https://example.invalid/api/admin/usuarios', {
  method, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
});

beforeEach(() => {
  vi.clearAllMocks();
  rpc.mockResolvedValue({ data: { ok: true, id: ALVO }, error: null });
  update.mockReturnValue({ eq: async () => ({ error: null }) });
  generateLink.mockResolvedValue({ data: { user: { id: ALVO }, properties: { hashed_token: 'token-de-teste' } }, error: null });
});

describe('B2 na rota de Usuários', () => {
  it('PATCH envia autor, alvo e campos à RPC sem atualizado_em', async () => {
    const res = await PATCH(request('PATCH', { id: ALVO, fields: { nome: 'Nome de teste', status: 'ativo' } }));
    expect(res.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith('acesso_perfil_atualizar_como', {
      p_autor: AUTOR, p_id: ALVO, p_patch: { nome: 'Nome de teste', status: 'ativo' },
    });
    expect(update).not.toHaveBeenCalled();
  });

  it('não grava sem autor quando a RPC não está visível', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202' } });
    const res = await PATCH(request('PATCH', { id: ALVO, fields: { status: 'pendente' } }));
    expect(res.status).toBe(503);
    expect(update).not.toHaveBeenCalled();
  });

  it.each([['42501', 403], ['22023', 400], ['P0002', 404]])('traduz %s em HTTP %i sem fallback', async (code, status) => {
    rpc.mockResolvedValue({ data: null, error: { code } });
    const res = await PATCH(request('PATCH', { id: ALVO, fields: { status: 'ativo' } }));
    expect(res.status).toBe(status);
    expect(update).not.toHaveBeenCalled();
    expect((await res.json()).error).toBeTruthy();
  });

  it('POST envia o perfil do convite pela RPC sem campos legados nem timestamp', async () => {
    const res = await POST(request('POST', { email: 'teste@example.invalid', nome: 'Nome de teste' }));
    expect(res.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith('acesso_perfil_atualizar_como', {
      p_autor: AUTOR, p_id: ALVO, p_patch: { nome: 'Nome de teste', status: 'ativo' },
    });
    expect(update).not.toHaveBeenCalled();
  });
});
