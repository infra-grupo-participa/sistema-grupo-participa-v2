import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

// Simula public.pessoas_registrar_lead: devolve o que a fila de respostas mandar (padrão: ok).
// Todo dado pessoal aqui é fictício (domínio .invalid, telefone 55 11 90000-0000).
const SEGREDO = 'c'.repeat(48);
type Chamada = { fn: string; args: Record<string, unknown> };
const chamadas: Chamada[] = [];
let resposta: { data: unknown; error: unknown } = { data: { ok: true, ref: 'x', como: 'novo', revisao: false }, error: null };

vi.mock('@/shared/infrastructure/supabase/admin-client', () => ({
  createAdminSupabase: () => ({
    rpc: async (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      return resposta;
    },
  }),
}));

const { POST } = await import('./route');

// IPs públicos de documentação (203.0.113.0/24): um por requisição, para o limite por IP não interferir.
let ipSeq = 0;
function req(corpo: unknown, opts: { chave?: string | null; bruto?: string; tipoConteudo?: string; xff?: string } = {}) {
  const headers: Record<string, string> = {
    'content-type': opts.tipoConteudo ?? 'application/json',
    'x-forwarded-for': opts.xff ?? `203.0.113.${(++ipSeq % 250) + 1}`,
  };
  const chave = opts.chave === undefined ? SEGREDO : opts.chave;
  if (chave !== null) headers.authorization = `Bearer ${chave}`;
  return new NextRequest('https://grupoparticipa.app.br/api/captura/lead', {
    method: 'POST',
    headers,
    body: opts.bruto ?? JSON.stringify(corpo),
  });
}

const valido = {
  chave_evento: 'clinica-miami-2026-12',
  tipo: 'pre_checkout',
  nome: 'Pessoa Ficticia',
  email: 'Pessoa.Ficticia@Exemplo.invalid',
  telefone: '5511900000000',
  utm_source: 'meta',
  utm_medium: 'cpc',
  utm_campaign: 'clinica-miami-2026-12',
  utm_content: 'miami',
  utm_term: 'teste',
  sck: 'sck-ficticio',
  xcod: 'xcod-ficticio',
  pagina_origem: 'https://clinica.timeholdingbrasil.com.br/miami/?email=x@exemplo.invalid#topo',
  data: '07/10/2026',
  hora: '12:00:00',
};

beforeEach(() => {
  chamadas.length = 0;
  resposta = { data: { ok: true, ref: 'x', como: 'novo', revisao: false }, error: null };
  process.env.CAPTURA_LEAD_SECRET = SEGREDO;
});
afterEach(() => {
  delete process.env.CAPTURA_LEAD_SECRET;
  vi.restoreAllMocks();
});

describe('POST /api/captura/lead', () => {
  it('200: manda à RPC o objeto exato, sem query na página e sem campos desconhecidos', async () => {
    const r = await POST(req(valido));
    expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ ok: true });
    expect(chamadas).toHaveLength(1);
    expect(chamadas[0].fn).toBe('pessoas_registrar_lead');
    expect(chamadas[0].args).toEqual({
      p: {
        chave_evento: 'clinica-miami-2026-12',
        evento: 'pre_checkout',
        nome: 'Pessoa Ficticia',
        email: 'pessoa.ficticia@exemplo.invalid',
        telefone: '5511900000000',
        utm_source: 'meta',
        utm_medium: 'cpc',
        utm_campaign: 'clinica-miami-2026-12',
        utm_content: 'miami',
        utm_term: 'teste',
        sck: 'sck-ficticio',
        xcod: 'xcod-ficticio',
        pagina: 'https://clinica.timeholdingbrasil.com.br/miami/',
        teste: false,
      },
    });
  });

  it('503 sem segredo configurado (fail-closed) e sem chamar o banco', async () => {
    delete process.env.CAPTURA_LEAD_SECRET;
    const r = await POST(req(valido));
    expect(r.status).toBe(503);
    expect(chamadas).toHaveLength(0);
  });

  it('503 com segredo curto demais', async () => {
    process.env.CAPTURA_LEAD_SECRET = 'curto';
    const r = await POST(req(valido, { chave: 'curto' }));
    expect(r.status).toBe(503);
    expect(chamadas).toHaveLength(0);
  });

  it('401 com Bearer errado ou ausente, sem chamar o banco', async () => {
    for (const chave of ['d'.repeat(48), null, SEGREDO + 'x']) {
      const r = await POST(req(valido, { chave }));
      expect(r.status).toBe(401);
      expect(await r.json()).toEqual({ error: 'Não autorizado.' });
    }
    expect(chamadas).toHaveLength(0);
  });

  it('429 depois de 10 falhas de segredo no mesmo IP, mesmo com o segredo certo', async () => {
    const xff = '198.51.100.7';
    for (let i = 0; i < 10; i++) expect((await POST(req(valido, { chave: 'e'.repeat(48), xff }))).status).toBe(401);
    expect((await POST(req(valido, { xff }))).status).toBe(429);
    expect(chamadas).toHaveLength(0);
  });

  it('429 na 21ª chamada autorizada do mesmo IP no mesmo minuto (limite 20/min, condição B1)', async () => {
    const xff = '198.51.100.21';
    for (let i = 0; i < 20; i++) expect((await POST(req(valido, { xff }))).status).toBe(200);
    const r = await POST(req(valido, { xff }));
    expect(r.status).toBe(429);
    expect(chamadas).toHaveLength(20);
    // Outro IP no mesmo minuto não é afetado.
    expect((await POST(req(valido, { xff: '198.51.100.22' }))).status).toBe(200);
  });

  it('400 com Content-Type errado', async () => {
    const r = await POST(req(valido, { tipoConteudo: 'text/plain' }));
    expect(r.status).toBe(400);
    expect(chamadas).toHaveLength(0);
  });

  it('400 com JSON inválido', async () => {
    const r = await POST(req(null, { bruto: '{nao e json' }));
    expect(r.status).toBe(400);
    expect(await r.json()).toEqual({ error: 'JSON inválido.' });
  });

  it('413 com corpo acima de 8 KB', async () => {
    const r = await POST(req({ ...valido, sobra: 'x'.repeat(9000) }));
    expect(r.status).toBe(413);
    expect(chamadas).toHaveLength(0);
  });

  it('400 nas recusas de validação, sem ecoar o valor recebido', async () => {
    const casos: unknown[] = [
      { ...valido, chave_evento: 'Clinica Miami' },
      { ...valido, chave_evento: undefined },
      { ...valido, tipo: 'compra' },
      { ...valido, tipo: undefined },
      { ...valido, email: undefined, telefone: undefined },
      { ...valido, email: 'sem-arroba.invalid' },
      { ...valido, telefone: '123' },
      { ...valido, nome: 'X' },
      { ...valido, utm_source: 42 },
      { ...valido, teste: 'sim' },
      [valido],
    ];
    for (const c of casos) {
      const r = await POST(req(c));
      expect(r.status).toBe(400);
      const txt = JSON.stringify(await r.json());
      expect(txt).not.toContain('sem-arroba');
      expect(txt).not.toContain('Clinica Miami');
    }
    expect(chamadas).toHaveLength(0);
  });

  it('aceita tipo lead e só telefone; teste:true segue para a base', async () => {
    const r = await POST(req({ chave_evento: 'clinica-miami-2026-12', tipo: 'lead', telefone: '55 (11) 90000-0000', teste: true }));
    expect(r.status).toBe(200);
    expect(chamadas[0].args.p).toMatchObject({ evento: 'lead', telefone: '5511900000000', email: null, teste: true });
  });

  it('400 quando a função recusa (ok:false), com a mensagem pública dela', async () => {
    resposta = { data: { ok: false, msg: 'Evento inválido (lead, mql, nao_mql ou cadastro).' }, error: null };
    const r = await POST(req(valido));
    expect(r.status).toBe(400);
    expect(await r.json()).toEqual({ error: 'Evento inválido (lead, mql, nao_mql ou cadastro).' });
  });

  it('502 em erro da RPC, logando só o código (sem dado pessoal)', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {});
    resposta = { data: null, error: { code: '23514', message: 'Failing row contains (pessoa.ficticia@exemplo.invalid, 5511900000000)' } };
    const r = await POST(req(valido));
    expect(r.status).toBe(502);
    expect(await r.json()).toEqual({ error: 'Não foi possível gravar agora.' });
    const logado = JSON.stringify(log.mock.calls);
    expect(logado).toContain('23514');
    expect(logado).not.toContain('exemplo.invalid');
    expect(logado).not.toContain('5511900000000');
    expect(logado).not.toContain('Ficticia');
  });

  it('502 quando a RPC volta 200 sem corpo (HTTP 200 não é sucesso)', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    resposta = { data: null, error: null };
    expect((await POST(req(valido))).status).toBe(502);
  });
});
