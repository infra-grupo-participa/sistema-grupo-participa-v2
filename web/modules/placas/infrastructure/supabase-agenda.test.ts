import { describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';

vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({ createAdminSupabase: () => ({}) }));

import { SupabaseAgenda } from './supabase-agenda';

function fakeDb(prevId: string | null, updateError: { code: string } | null = null) {
  const updates: Record<string, unknown>[] = [];
  const db = {
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { zoom_meeting_id: prevId }, error: null }) }) }),
      update: (patch: Record<string, unknown>) => {
        updates.push(patch);
        return { eq: async () => ({ error: updateError }) };
      },
    }),
  };
  return { db: db as unknown as SupabaseClient, updates };
}

const base = { entrevista_data: '2026-10-05', entrevista_hora: '10:00', entrevista_link: 'l', meet_link: 'l' };

describe('SupabaseAgenda.confirm', () => {
  it('zera reminder_sent_at, grava zoom_meeting_id e devolve o id anterior', async () => {
    const { db, updates } = fakeDb('111');
    const r = await new SupabaseAgenda(db).confirm('sol1', { ...base, zoom_meeting_id: '222' });
    expect(r).toEqual({ ok: true, conflict: false, previousMeetingId: '111' });
    expect(updates[0]).toMatchObject({ reminder_sent_at: null, zoom_meeting_id: '222', status: 'docs_aprovados', step_index: 2 });
  });

  it('chamador antigo (sem zoom_meeting_id): não toca a coluna e não manda apagar sala', async () => {
    const { db, updates } = fakeDb('111');
    const r = await new SupabaseAgenda(db).confirm('sol1', base);
    expect(r.previousMeetingId).toBeNull();
    expect('zoom_meeting_id' in updates[0]).toBe(false);
    expect(updates[0].reminder_sent_at).toBeNull();
  });

  it('mesmo id da nova sala: não devolve como anterior', async () => {
    const { db } = fakeDb('222');
    expect((await new SupabaseAgenda(db).confirm('sol1', { ...base, zoom_meeting_id: '222' })).previousMeetingId).toBeNull();
  });

  it('conflito 23505: ok=false, sem previousMeetingId (sala antiga continua válida)', async () => {
    const { db } = fakeDb('111', { code: '23505' });
    expect(await new SupabaseAgenda(db).confirm('sol1', { ...base, zoom_meeting_id: '222' })).toEqual({
      ok: false,
      conflict: true,
      previousMeetingId: null,
    });
  });
});
