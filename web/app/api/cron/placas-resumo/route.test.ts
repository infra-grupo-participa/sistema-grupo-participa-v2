import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

type Row = Record<string, unknown>;

const ZERO = {
  aguardando_analise: 0,
  docs_aprovados_sem_entrevista: 0,
  entrevistas_hoje: 0,
  entrevistas_sem_desfecho: 0,
  parados_enviado: 0,
  parados_em_auditoria: 0,
  parados_docs_aprovados: 0,
  parados_placa_postada: 0,
  parados_rascunho: 0,
  novos: 0,
};

let contagens: Row = { ...ZERO };
let reivindicaveis: Row[] = [];
let cutucadaAtiva = false;
let envioCandidatoOk: boolean[] = [];
let resumoOk = true;
const rpcCalls: Array<{ fn: string; args: Row }> = [];
const updates: Array<{ patch: Row; filtros: Array<[string, unknown]> }> = [];
const resumos: Array<{ to: unknown; subject: string; html: string }> = [];
const cutucadas: Array<{ tipo: string; to: string; token: string }> = [];

const CHAVE_BANCO = 'a'.repeat(64);

vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({
  createAdminSupabase: () => ({
    rpc: async (fn: string, args: Row) => {
      rpcCalls.push({ fn, args });
      if (fn === 'fn_placas_cron_chave_ok') return { data: args.p_chave === CHAVE_BANCO, error: null };
      if (fn === 'fn_placas_resumo_contagens') return { data: [{ ...contagens }], error: null };
      if (fn === 'fn_placas_cutucada_reivindicar') {
        const out = reivindicaveis.map((r) => ({ ...r }));
        reivindicaveis = []; // idempotente: 2ª chamada não devolve as mesmas linhas
        return { data: out, error: null };
      }
      return { data: null, error: { message: 'rpc desconhecida' } };
    },
    from: () => {
      const reg = { patch: {} as Row, filtros: [] as Array<[string, unknown]> };
      const b = {
        update: (p: Row) => ((reg.patch = p), b),
        eq: (k: string, v: unknown) => (reg.filtros.push([k, v]), b),
        then: (res: (v: unknown) => unknown) => {
          updates.push(reg);
          return Promise.resolve({ data: null, error: null }).then(res);
        },
      };
      return b;
    },
  }),
}));
vi.mock('@/shared/infrastructure/email/mailer', () => ({
  sendMailDetalhado: async (m: { to: unknown; subject: string; html: string }) => {
    resumos.push(m);
    return resumoOk ? { ok: true, id: 'x' } : { ok: false, erro: 'HTTP 500' };
  },
}));
vi.mock('@/modules/placas/infrastructure/supabase-config', () => ({
  readPlacasConfig: async () => ({ email_templates: {}, cutucada_ativa: cutucadaAtiva }),
}));
vi.mock('@/modules/placas/application/enviar-email-placa', () => ({
  enviarEmailPlaca: async (m: { tipo: string; to: string; token: string }) => {
    cutucadas.push(m);
    const ok = envioCandidatoOk.shift() ?? true;
    return { ok, sent: ok };
  },
}));

const { GET, POST } = await import('./route');

let ipSeq = 0;
function req(method: 'GET' | 'POST' = 'POST', secret = 's3cr3t', ip = `10.1.0.${++ipSeq}`) {
  return new NextRequest('https://grupoparticipa.app.br/api/cron/placas-resumo', {
    method,
    headers: { authorization: `Bearer ${secret}`, 'x-forwarded-for': ip },
  });
}
// 01/10/2026 = quinta. 11:00 UTC = 08:00 em SP.
const QUINTA = new Date('2026-10-01T11:00:00Z');
const SEGUNDA = new Date('2026-10-05T11:00:00Z');
const SABADO = new Date('2026-10-03T11:00:00Z');
// Domingo 23h em SP = segunda 02h UTC: o fuso tem que valer, não o UTC.
const DOMINGO_NOITE_SP = new Date('2026-10-05T02:00:00Z');

function cand(id: string): Row {
  return { id, token: `${id}-tok`, nome: `Nome ${id}`, email: `${id}@x.com`, carimbo: '2026-10-01T11:00:00.123456+00:00' };
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(QUINTA);
  process.env.CRON_SECRET = 's3cr3t';
  process.env.ADMIN_EMAIL = 'equipe@grupoparticipa.app.br';
  contagens = { ...ZERO };
  reivindicaveis = [];
  cutucadaAtiva = false;
  envioCandidatoOk = [];
  resumoOk = true;
  rpcCalls.length = 0;
  updates.length = 0;
  resumos.length = 0;
  cutucadas.length = 0;
});
afterEach(() => {
  vi.useRealTimers();
});

describe('cron placas-resumo — autenticação', () => {
  it('Bearer errado → 401; GET e POST aceitam o mesmo Bearer', async () => {
    expect((await POST(req('POST', 'errado'))).status).toBe(401);
    expect((await GET(req('GET'))).status).toBe(200);
    expect((await POST(req('POST'))).status).toBe(200);
  });

  it('sem env CRON_SECRET aceita a chave do Vault; lixo fora do formato não chega à RPC', async () => {
    delete process.env.CRON_SECRET;
    expect((await POST(req('POST', CHAVE_BANCO))).status).toBe(200);
    expect((await POST(req('POST', 'b'.repeat(64)))).status).toBe(401);
    const antes = rpcCalls.filter((c) => c.fn === 'fn_placas_cron_chave_ok').length;
    expect((await POST(req('POST', 'qualquer'))).status).toBe(401);
    expect(rpcCalls.filter((c) => c.fn === 'fn_placas_cron_chave_ok').length).toBe(antes);
  });

  it('rate-limit por IP antes da RPC (11ª tentativa sem env → 429)', async () => {
    delete process.env.CRON_SECRET;
    const ip = '10.9.9.9';
    for (let i = 0; i < 10; i++) expect((await POST(req('POST', 'x', ip))).status).toBe(401);
    expect((await POST(req('POST', 'x', ip))).status).toBe(429);
  });
});

describe('cron placas-resumo — resumo', () => {
  it('fim de semana (sábado) → 200 pulado, sem consultar contagens', async () => {
    vi.setSystemTime(SABADO);
    const r = await POST(req());
    expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ ok: true, pulado: 'fim_de_semana' });
    expect(rpcCalls.some((c) => c.fn === 'fn_placas_resumo_contagens')).toBe(false);
  });

  it('domingo 23h em SP (já segunda em UTC) ainda é fim de semana', async () => {
    vi.setSystemTime(DOMINGO_NOITE_SP);
    expect(await (await POST(req())).json()).toMatchObject({ pulado: 'fim_de_semana' });
  });

  it('tudo zero → nada_pendente, sem e-mail', async () => {
    const r = await POST(req());
    expect(r.status).toBe(200);
    expect(await r.json()).toMatchObject({ ok: true, enviado: false, motivo: 'nada_pendente', contagens: ZERO });
    expect(resumos).toHaveLength(0);
  });

  it('só rascunho parado não dispara e-mail da equipe', async () => {
    contagens = { ...ZERO, parados_rascunho: 7 };
    expect(await (await POST(req())).json()).toMatchObject({ enviado: false, motivo: 'nada_pendente' });
    expect(resumos).toHaveLength(0);
  });

  it('com pendência envia a ADMIN_EMAIL só com números + link /educacional/placas', async () => {
    contagens = { ...ZERO, aguardando_analise: 3, entrevistas_hoje: 2, parados_rascunho: 5 };
    const r = await POST(req());
    const body = await r.json();
    expect(r.status).toBe(200);
    expect(body).toMatchObject({ ok: true, enviado: true, contagens: { aguardando_analise: 3, entrevistas_hoje: 2 } });
    expect(resumos).toHaveLength(1);
    expect(resumos[0].to).toEqual(['equipe@grupoparticipa.app.br']);
    expect(resumos[0].html).toContain('/educacional/placas');
    expect(resumos[0].html).not.toMatch(/token=|@x\.com/);
    expect(rpcCalls.find((c) => c.fn === 'fn_placas_resumo_contagens')?.args).toEqual({ p_horas_novos: 24 });
  });

  it('segunda-feira: novos cobrem 72h (fim de semana)', async () => {
    vi.setSystemTime(SEGUNDA);
    contagens = { ...ZERO, novos: 1 };
    await POST(req());
    expect(rpcCalls.find((c) => c.fn === 'fn_placas_resumo_contagens')?.args).toEqual({ p_horas_novos: 72 });
    expect(resumos[0].html).toContain('últimas 72h');
  });

  it('ADMIN_EMAIL ausente com pendência → 500 claro, nada enviado', async () => {
    delete process.env.ADMIN_EMAIL;
    contagens = { ...ZERO, aguardando_analise: 1 };
    const r = await POST(req());
    expect(r.status).toBe(500);
    expect(await r.json()).toMatchObject({ ok: false, enviado: false, erro: 'ADMIN_EMAIL ausente ou inválido' });
    expect(resumos).toHaveLength(0);
  });

  it('falha do Resend no resumo → 500 para o vigia', async () => {
    resumoOk = false;
    contagens = { ...ZERO, entrevistas_sem_desfecho: 1 };
    expect((await POST(req())).status).toBe(500);
  });
});

describe('cron placas-resumo — cutucada', () => {
  it('flag false (default): não reivindica, não envia, não marca', async () => {
    reivindicaveis = [cand('a')];
    const body = await (await POST(req())).json();
    expect(body.cutucada).toEqual({ ativa: false, reivindicados: 0, enviados: 0, falhas: 0 });
    expect(rpcCalls.some((c) => c.fn === 'fn_placas_cutucada_reivindicar')).toBe(false);
    expect(cutucadas).toHaveLength(0);
    expect(updates).toHaveLength(0);
  });

  it('flag true: reivindica com limite 30, envia tipo cutucada pelo token; 2ª passagem não reenvia', async () => {
    cutucadaAtiva = true;
    reivindicaveis = [cand('a'), cand('b')];
    const b1 = await (await POST(req())).json();
    expect(b1.cutucada).toEqual({ ativa: true, reivindicados: 2, enviados: 2, falhas: 0 });
    expect(rpcCalls.find((c) => c.fn === 'fn_placas_cutucada_reivindicar')?.args).toEqual({ p_limite: 30, p_max_dias: 30 });
    expect(cutucadas.map((c) => [c.tipo, c.to, c.token])).toEqual([
      ['cutucada', 'a@x.com', 'a-tok'],
      ['cutucada', 'b@x.com', 'b-tok'],
    ]);
    const b2 = await (await POST(req())).json();
    expect(b2.cutucada).toMatchObject({ reivindicados: 0, enviados: 0 });
    expect(cutucadas).toHaveLength(2);
    expect(JSON.stringify(b1)).not.toMatch(/@x\.com|-tok|Nome /);
  });

  it('envio falhou: mantém o carimbo (uma vez só, sem reenvio diário)', async () => {
    cutucadaAtiva = true;
    reivindicaveis = [cand('a'), cand('b')];
    envioCandidatoOk = [true, false];
    const r = await POST(req());
    expect(r.status).toBe(200);
    expect((await r.json()).cutucada).toMatchObject({ enviados: 1, falhas: 1 });
    expect(updates).toEqual([]);
  });

  it('todas as cutucadas falharam → 500', async () => {
    cutucadaAtiva = true;
    reivindicaveis = [cand('a')];
    envioCandidatoOk = [false];
    expect((await POST(req())).status).toBe(500);
  });

  it('fim de semana: cutucada também não roda', async () => {
    vi.setSystemTime(SABADO);
    cutucadaAtiva = true;
    reivindicaveis = [cand('a')];
    await POST(req());
    expect(cutucadas).toHaveLength(0);
  });
});
