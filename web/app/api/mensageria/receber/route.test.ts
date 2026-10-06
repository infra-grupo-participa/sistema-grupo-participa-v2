import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

// Simula o banco: a chave é conferida no Vault por mkt_msg_api_chave_ok (fonte cadastrada + chave certa);
// mkt_msg_api_receber recusa fonte desligada com nao_autorizado.
const CHAVE_OK = 'b'.repeat(64);
const CADASTRADAS = new Set(['unichat', 'sendflow']);
const ATIVAS = new Set(['unichat']); // sendflow existe mas está desligada
type Chamada = { fn: string; args: Record<string, unknown> };
const chamadas: Chamada[] = [];
let erroRpc: unknown = null;

vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({
  createAdminSupabase: () => ({
    rpc: async (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      if (erroRpc) return { data: null, error: erroRpc };
      const chaveCerta = args.p_chave === CHAVE_OK && CADASTRADAS.has(String(args.p_fonte));
      if (fn === 'mkt_msg_api_chave_ok') return { data: chaveCerta, error: null };
      if (!chaveCerta || !ATIVAS.has(String(args.p_fonte))) return { data: { ok: false, erro: 'nao_autorizado' }, error: null };
      if (fn === 'mkt_msg_api_receber') {
        const lote = args.p_lote as unknown[];
        if (lote.length > 1000) return { data: { ok: false, erro: 'lote_grande', limite: 1000 }, error: null };
        return {
          data: { ok: true, status: 'ok', lidos: lote.length, inseridos: lote.length, atualizados: 0, inalterados: 0, recusados: 0, recusas: [] },
          error: null,
        };
      }
      return { data: { ok: true, contagem_fonte: (args.p_ids as unknown[]).length, contagem_log: 0, faltantes_total: 0, faltantes: [] }, error: null };
    },
  }),
}));

const { POST } = await import('./route');

// IPs públicos de documentação (203.0.113.0/24): o clientIp ignora saltos internos (10.x, 192.168.x…).
let ipSeq = 0;
function req(corpo: unknown, opts: { fonte?: string; chave?: string; bruto?: string; xff?: string } = {}) {
  const headers: Record<string, string> = {
    'content-type': 'application/json',
    'x-forwarded-for': opts.xff ?? `203.0.113.${++ipSeq}`,
  };
  if (opts.fonte !== undefined) headers['x-mensageria-fonte'] = opts.fonte;
  if (opts.chave !== undefined) headers.authorization = `Bearer ${opts.chave}`;
  return new NextRequest('https://grupoparticipa.app.br/api/mensageria/receber', {
    method: 'POST',
    headers,
    body: opts.bruto ?? JSON.stringify(corpo),
  });
}
const item = (i: number) => ({ id_externo: `X${i}`, campanha: '[HT33] teste', canal: 'whatsapp_api', tipo: 'marketing' });
const nomes = () => chamadas.map((c) => c.fn);

beforeEach(() => {
  chamadas.length = 0;
  erroRpc = null;
});

describe('POST /api/mensageria/receber', () => {
  it('ok: confere a chave primeiro, depois grava o lote', async () => {
    const res = await POST(req({ lote: [item(1), item(2)] }, { fonte: 'unichat', chave: CHAVE_OK }));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, lidos: 2, inseridos: 2 });
    expect(chamadas).toEqual([
      { fn: 'mkt_msg_api_chave_ok', args: { p_fonte: 'unichat', p_chave: CHAVE_OK } },
      { fn: 'mkt_msg_api_receber', args: { p_fonte: 'unichat', p_chave: CHAVE_OK, p_lote: [item(1), item(2)] } },
    ]);
  });

  it('chave errada: 401 genérico, só o porteiro é consultado (o corpo nem chega ao banco)', async () => {
    const res = await POST(req({ lote: [item(1)] }, { fonte: 'unichat', chave: 'c'.repeat(64) }));
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ error: 'Não autorizado.' });
    expect(nomes()).toEqual(['mkt_msg_api_chave_ok']);
  });

  it('chave errada com corpo de 6 MB: 401 (a chave é conferida antes de ler o corpo), não 413', async () => {
    const bruto = JSON.stringify({ lote: [{ id_externo: 'x', copy_texto: 'a'.repeat(6 * 1024 * 1024) }] });
    const res = await POST(req(null, { fonte: 'unichat', chave: 'c'.repeat(64), bruto }));
    expect(res.status).toBe(401);
    expect(nomes()).toEqual(['mkt_msg_api_chave_ok']);
  });

  it('fonte desligada (chave certa), desconhecida e chave errada: o mesmo 401', async () => {
    const desligada = await POST(req({ lote: [] }, { fonte: 'sendflow', chave: CHAVE_OK }));
    const errada = await POST(req({ lote: [] }, { fonte: 'unichat', chave: 'c'.repeat(64) }));
    const desconhecida = await POST(req({ lote: [] }, { fonte: 'nao_existe', chave: CHAVE_OK }));
    expect([desligada.status, errada.status, desconhecida.status]).toEqual([401, 401, 401]);
    const corpos = await Promise.all([desligada.json(), errada.json(), desconhecida.json()]);
    expect(corpos[0]).toEqual(corpos[1]);
    expect(corpos[1]).toEqual(corpos[2]);
  });

  it('header fora do formato: 401 sem consultar o banco', async () => {
    for (const r of [
      req({ lote: [] }, { fonte: 'unichat', chave: 'curta' }),
      req({ lote: [] }, { fonte: 'unichat' }),
      req({ lote: [] }, { chave: CHAVE_OK }),
      req({ lote: [] }, { fonte: 'Unichat; drop', chave: CHAVE_OK }),
    ]) {
      expect((await POST(r)).status).toBe(401);
    }
    expect(chamadas).toHaveLength(0);
  });

  it('sem chave válida: 10 tentativas por IP em 10 min; a 11ª é 429 sem consultar o banco', async () => {
    const xff = '198.51.100.7';
    for (let i = 0; i < 10; i++) {
      expect((await POST(req({ lote: [] }, { fonte: 'unichat', chave: 'c'.repeat(64), xff }))).status).toBe(401);
    }
    chamadas.length = 0;
    expect((await POST(req({ lote: [] }, { fonte: 'unichat', chave: CHAVE_OK, xff }))).status).toBe(429);
    expect(chamadas).toHaveLength(0);
  });

  it('X-Forwarded-For forjado não escapa do limite: vale o salto mais à direita não interno', async () => {
    for (let i = 0; i < 10; i++) {
      const xff = `9.9.9.${i}, 198.51.100.8, 10.0.0.1`; // 1º salto inventado pelo cliente; 10.x = proxy interno
      expect((await POST(req({ lote: [] }, { fonte: 'unichat', chave: 'c'.repeat(64), xff }))).status).toBe(401);
    }
    const res = await POST(req({ lote: [] }, { fonte: 'unichat', chave: CHAVE_OK, xff: '1.2.3.4, 198.51.100.8' }));
    expect(res.status).toBe(429);
  });

  it('lote acima de 1.000: 413 (o banco recusa e registra a execução)', async () => {
    const lote = Array.from({ length: 1001 }, (_, i) => ({ id_externo: `G${i}` }));
    const res = await POST(req({ lote }, { fonte: 'unichat', chave: CHAVE_OK }));
    expect(res.status).toBe(413);
    expect(nomes()).toEqual(['mkt_msg_api_chave_ok', 'mkt_msg_api_receber']);
  });

  it('corpo acima de 5 MB com chave certa: 413 sem chamar a gravação', async () => {
    const bruto = JSON.stringify({ lote: [{ id_externo: 'x', copy_texto: 'a'.repeat(5 * 1024 * 1024) }] });
    const res = await POST(req(null, { fonte: 'unichat', chave: CHAVE_OK, bruto }));
    expect(res.status).toBe(413);
    expect(nomes()).toEqual(['mkt_msg_api_chave_ok']);
  });

  it('JSON inválido ou sem "lote"/"reconciliacao": 400 sem gravar', async () => {
    expect((await POST(req(null, { fonte: 'unichat', chave: CHAVE_OK, bruto: '{lote:' }))).status).toBe(400);
    expect((await POST(req({ outra: 1 }, { fonte: 'unichat', chave: CHAVE_OK }))).status).toBe(400);
    expect((await POST(req([item(1)], { fonte: 'unichat', chave: CHAVE_OK }))).status).toBe(400);
    expect(nomes().every((n) => n === 'mkt_msg_api_chave_ok')).toBe(true);
  });

  it('reconciliação: chama mkt_msg_api_reconciliar com dia e ids', async () => {
    const res = await POST(req({ reconciliacao: { dia: '2026-10-04', ids: ['a', 'b'] } }, { fonte: 'unichat', chave: CHAVE_OK }));
    expect(res.status).toBe(200);
    expect(chamadas[1]).toEqual({ fn: 'mkt_msg_api_reconciliar', args: { p_fonte: 'unichat', p_chave: CHAVE_OK, p_dia: '2026-10-04', p_ids: ['a', 'b'] } });
    expect((await POST(req({ reconciliacao: { dia: 'ontem', ids: [] } }, { fonte: 'unichat', chave: CHAVE_OK }))).status).toBe(400);
  });

  it('erro do PostgREST: 502 sem detalhe', async () => {
    erroRpc = { message: 'relation does not exist', code: '42P01' };
    const res = await POST(req({ lote: [item(1)] }, { fonte: 'unichat', chave: CHAVE_OK }));
    expect(res.status).toBe(502);
    expect(JSON.stringify(await res.json())).not.toContain('relation');
  });

  it('com chave válida: limite geral de 120 por minuto por IP', async () => {
    let ultimo = 0;
    for (let i = 0; i < 121; i++) {
      ultimo = (await POST(req({ lote: [] }, { fonte: 'unichat', chave: CHAVE_OK, xff: '198.51.100.9' }))).status;
    }
    expect(ultimo).toBe(429);
  });
});
