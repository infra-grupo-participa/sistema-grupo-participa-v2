import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

type Row = Record<string, unknown>;
let table: Row[] = [];
let sendResults: boolean[] = [];
const sent: string[] = [];
const extras: Array<Record<string, unknown> | undefined> = [];
const queryLog: string[] = [];

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
    gte: (k: string, v: unknown) => (queryLog.push(`gte ${k} ${v}`), b),
    lte: (k: string, v: unknown) => (queryLog.push(`lte ${k} ${v}`), b),
    or: (v: string) => (queryLog.push(`or ${v}`), b),
    order: () => b,
    limit: (n: number) => (queryLog.push(`limit ${n}`), b),
    then: (res: (v: unknown) => unknown) => Promise.resolve(run()).then(res),
  };
  return b;
}
const CHAVE_BANCO = 'a'.repeat(64);
const rpcCalls: string[] = [];
vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({
  createAdminSupabase: () => ({
    from: () => builder(),
    rpc: async (_fn: string, args: { p_chave: string }) => {
      rpcCalls.push(args.p_chave);
      return { data: args.p_chave === CHAVE_BANCO, error: null };
    },
  }),
}));
vi.mock('@/modules/placas/application/enviar-email-placa', () => ({
  enviarEmailPlaca: async (m: { to: string; extra?: Record<string, unknown> }) => {
    sent.push(m.to);
    extras.push(m.extra);
    const ok = sendResults.shift() ?? true;
    return { ok, sent: ok };
  },
}));
vi.mock('@/modules/placas/domain/agendamento', () => ({
  buildSlotStart: () => new Date(Date.now() + 4 * 60 * 60 * 1000),
}));

const { GET, POST } = await import('./route');

let ipSeq = 0;
function req(method: 'GET' | 'POST', secret = 's3cr3t', ip = `10.0.0.${++ipSeq}`) {
  return new NextRequest('https://grupoparticipa.app.br/api/cron/interview-reminder', {
    method,
    headers: { authorization: `Bearer ${secret}`, 'x-forwarded-for': ip },
  });
}
function row(id: string): Row {
  return { id, token: `${id}-tok`, nome: id, email: `${id}@x.com`, entrevista_data: '2026-10-01', entrevista_hora: '20:00', entrevista_link: `https://us02web.zoom.us/j/${id}`, auditoria_step: 2, reminder_sent_at: null };
}

beforeEach(() => {
  process.env.CRON_SECRET = 's3cr3t';
  table = [row('a'), row('b')];
  sendResults = [];
  sent.length = 0;
  extras.length = 0;
  queryLog.length = 0;
  rpcCalls.length = 0;
});

describe('cron interview-reminder', () => {
  it('POST existe, exige o mesmo Bearer', async () => {
    expect((await POST(req('POST', 'errado'))).status).toBe(401);
    expect((await POST(req('POST'))).status).toBe(200);
  });

  it('sem env CRON_SECRET, aceita a chave do Vault conferida no banco', async () => {
    delete process.env.CRON_SECRET;
    expect((await POST(req('POST', CHAVE_BANCO))).status).toBe(200);
    expect((await POST(req('POST', 'b'.repeat(64)))).status).toBe(401);
  });

  it('lixo fora do formato não chega a consultar o banco', async () => {
    delete process.env.CRON_SECRET;
    expect((await GET(req('GET', 'qualquer'))).status).toBe(401);
    expect((await GET(req('GET', ''))).status).toBe(401);
    expect(rpcCalls).toHaveLength(0);
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

  it('todas as tentativas falharam → HTTP 500 (vigia só vê o status)', async () => {
    sendResults = [false, false];
    const res = await GET(req('GET'));
    expect(res.status).toBe(500);
    expect(await res.json()).toMatchObject({ ok: false, enviados: 0, falhas: 2 });
    expect(table.every((r) => r.reminder_sent_at === null)).toBe(true);
  });

  it('passa a sala (entrevista_link) como extra.zoom_link', async () => {
    await GET(req('GET'));
    expect(extras[0]).toMatchObject({ zoom_link: 'https://us02web.zoom.us/j/a', entrevista_hora: '20:00' });
  });

  it('corta no SQL por data (SP) e limita o lote a 50', async () => {
    await GET(req('GET'));
    expect(queryLog).toContain('limit 50');
    expect(queryLog.some((q) => /^gte entrevista_data \d{4}-\d{2}-\d{2}$/.test(q))).toBe(true);
    expect(queryLog.some((q) => /^lte entrevista_data \d{4}-\d{2}-\d{2}$/.test(q))).toBe(true);
    expect(queryLog.some((q) => /^or entrevista_data\.gt\.[\d-]+,entrevista_hora\.gte\."\d{2}:\d{2}"$/.test(q))).toBe(true);
  });

  it('rate limit por IP antes da RPC; Bearer da env não é limitado', async () => {
    delete process.env.CRON_SECRET;
    const codes: number[] = [];
    for (let i = 0; i < 12; i++) codes.push((await POST(req('POST', 'b'.repeat(64), '203.0.113.9'))).status);
    expect(codes.slice(0, 10).every((c) => c === 401)).toBe(true);
    expect(codes.slice(10)).toEqual([429, 429]);
    expect(rpcCalls).toHaveLength(10);
    process.env.CRON_SECRET = 's3cr3t';
    for (let i = 0; i < 12; i++) expect((await POST(req('POST', 's3cr3t', '203.0.113.9'))).status).not.toBe(429);
  });
});
