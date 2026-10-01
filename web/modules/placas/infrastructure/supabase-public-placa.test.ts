import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';

const logSystemEvent = vi.hoisted(() => vi.fn(async (_ev: unknown) => {}));
vi.mock('@/shared/infrastructure/observability/system-events', () => ({ logSystemEvent, snippet: (v: unknown) => String(v) }));
vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({ createAdminSupabase: () => ({}) }));

import { SupabasePublicPlaca, logFunilPlacaAgendado, logFunilPlacaAprovado, logFunilPlacaSubmit } from './supabase-public-placa';

beforeEach(() => logSystemEvent.mockClear());

describe('updateByToken', () => {
  const dbCom = (error: unknown) =>
    ({ from: () => ({ update: () => ({ eq: async () => ({ error }) }) }) }) as unknown as SupabaseClient;

  it('sucesso: { ok: true } sem evento', async () => {
    expect(await new SupabasePublicPlaca(dbCom(null)).updateByToken('t', { nome: 'x' })).toEqual({ ok: true });
    expect(logSystemEvent).not.toHaveBeenCalled();
  });

  it('erro do banco: propaga code/message e registra evento', async () => {
    const r = await new SupabasePublicPlaca(dbCom({ code: '23514', message: 'check violado' })).updateByToken('t', { nivel: 'x' });
    expect(r).toEqual({ ok: false, error: { code: '23514', message: 'check violado' } });
    expect(logSystemEvent).toHaveBeenCalledWith(expect.objectContaining({ tipo: 'error', fonte: 'form_publico_placa' }));
    expect(JSON.stringify(logSystemEvent.mock.calls)).not.toContain('"token"');
  });
});

describe('promoteToAluno', () => {
  it('exceção não vaza, mas vira evento', async () => {
    const db = {
      from: () => {
        throw new Error('rede caiu');
      },
    } as unknown as SupabaseClient;
    await expect(new SupabasePublicPlaca(db).promoteToAluno('t', { email: 'a@b.com' })).resolves.toBeUndefined();
    expect(logSystemEvent).toHaveBeenCalledWith(expect.objectContaining({ tipo: 'error', titulo: expect.stringContaining('Exceção') }));
    const log = JSON.stringify(logSystemEvent.mock.calls);
    expect(log).not.toContain('"token"');
    expect(log).not.toContain('a@b.com');
  });

  it('erro devolvido pelo banco no update é registrado', async () => {
    const db = {
      from: () => ({
        select: () => ({ eq: () => ({ limit: () => ({ maybeSingle: async () => ({ data: { id: 's1' } }) }) }) }),
        update: () => ({ eq: async () => ({ error: { code: '42501', message: 'permission denied' } }) }),
      }),
      rpc: async () => ({ data: [] }),
    } as unknown as SupabaseClient;
    await new SupabasePublicPlaca(db).promoteToAluno('t', { email: 'a@b.com' });
    expect(logSystemEvent).toHaveBeenCalledWith(
      expect.objectContaining({ tipo: 'error', detalhe: expect.objectContaining({ etapa: 'central_match_nenhum', code: '42501' }) }),
    );
    expect(logSystemEvent).toHaveBeenCalledWith(expect.objectContaining({ detalhe: expect.objectContaining({ solicitacao_id: 's1' }) }));
    const log = JSON.stringify(logSystemEvent.mock.calls);
    expect(log).not.toContain('"token"');
    expect(log).not.toContain('a@b.com');
  });
});

describe('eventos do funil', () => {
  it.each([
    ['submit', logFunilPlacaSubmit],
    ['aprovado', logFunilPlacaAprovado],
    ['agendado', logFunilPlacaAgendado],
  ] as const)('%s grava evento business em funil_placa', async (etapa, fn) => {
    await fn({ solicitacao_id: 's1', aluno_id: 'a1', detalhe: { nivel: 'ouro' } });
    expect(logSystemEvent).toHaveBeenCalledWith({
      tipo: 'business',
      fonte: 'funil_placa',
      titulo: expect.any(String),
      detalhe: { nivel: 'ouro', etapa, solicitacao_id: 's1' },
      aluno_id: 'a1',
    });
  });
});
