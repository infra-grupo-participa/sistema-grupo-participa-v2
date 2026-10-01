import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

type Row = Record<string, unknown>;
let table: Row[] = [];
let sendResults: boolean[] = [];
const sent: string[] = [];

// Fake mínimo do query builder do supabase-js — simula UPDATE ... WHERE ... RETURNING por linha.
function builder() {
  const filters: Array<(r: Row) => boolean> = [];
  let patch: Row | null = null;
  const run = () => {
    const hit = table.filter((r) => filters.every((f) => f(r)));
    if (patch) for (const r of hit) Object.assign(r, patch);
    return { data: hit.map((r) => ({ ...r })), error: null };
  };
  const b = {
    select: () => b,
    update: (p: Row) => ((patch = p), b),
    eq: (k: string, v: unknown) => (filters.push((r) => r[k] === v), b),
    is: (k: string, v: unknown) => (filters.push((r) => (r[k] ?? null) === v), b),
    not: (k: string) => (filters.push((r) => r[k] != null), b),
    then: (res: (v: unknown) => unknown) => Promise.resolve(run()).then(res),
  };
  return b;
}
vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({ createAdminSupabase: () => ({ from: () => builder() }) }));
vi.mock('@/modules/placas/infrastructure/supabase-config', () => ({ readPlacasConfig: async () => ({}) }));
vi.mock('@/shared/infrastructure/email/mailer', () => ({
  sendMail: async (m: { to: string }) => {
    sent.push(m.to);
    return sendResults.shift() ?? true;
  },
}));
vi.mock('@/modules/placas/domain/agendamento', () => ({
  buildSlotStart: () => new Date(Date.now() + 4 * 60 * 60 * 1000),
}));

const { GET, POST } = await import('./route');

function req(method: 'GET' | 'POST', secret = 's3cr3t') {
  return new NextRequest('https://grupoparticipa.app.br/api/cron/interview-reminder', {
    method,
    headers: { authorization: `Bearer ${secret}` },
  });
}
function row(id: string): Row {
  return { id, token: `${id}-tok`, nome: id, email: `${id}@x.com`, entrevista_data: '2026-10-01', entrevista_hora: '20:00', auditoria_step: 2, reminder_sent_at: null };
}

beforeEach(() => {
  process.env.CRON_SECRET = 's3cr3t';
  table = [row('a'), row('b')];
  sendResults = [];
  sent.length = 0;
});

describe('cron interview-reminder', () => {
  it('POST existe, exige o mesmo Bearer', async () => {
    expect((await POST(req('POST', 'errado'))).status).toBe(401);
    expect((await POST(req('POST'))).status).toBe(200);
  });

  it('envia e marca; segunda passagem não reenvia', async () => {
    const r1 = await (await GET(req('GET'))).json();
    expect(r1).toMatchObject({ enviados: 2, falhas: 0 });
    expect(table.every((r) => r.reminder_sent_at)).toBe(true);
    const r2 = await (await POST(req('POST'))).json();
    expect(r2).toMatchObject({ candidatos: 0, enviados: 0 });
    expect(sent).toHaveLength(2);
  });

  it('linha reivindicada por outra execução entre a leitura e o claim não é enviada', async () => {
    // Simula a corrida: a 1ª linha é marcada por "outra execução" logo após a leitura.
    const a = table[0];
    let lidas = false;
    const realFilter = Array.prototype.filter;
    table.filter = function (this: Row[], ...args: Parameters<typeof realFilter>) {
      const out = realFilter.apply(this, args as never) as Row[];
      if (!lidas) {
        lidas = true;
        a.reminder_sent_at = 'outra-execucao';
        return out.map((r) => ({ ...r, reminder_sent_at: null }));
      }
      return out;
    } as typeof table.filter;
    const r = await (await GET(req('GET'))).json();
    expect(r).toMatchObject({ candidatos: 2, enviados: 1, ja_reivindicados: 1 });
    expect(sent).toEqual(['b@x.com']);
  });

  it('falha no envio devolve reminder_sent_at a null', async () => {
    sendResults = [false, true];
    const r = await (await GET(req('GET'))).json();
    expect(r).toMatchObject({ enviados: 1, falhas: 1 });
    expect(table.find((x) => x.id === 'a')?.reminder_sent_at).toBeNull();
    expect(table.find((x) => x.id === 'b')?.reminder_sent_at).toBeTruthy();
  });
});
