import { describe, expect, it } from 'vitest';
import { atenderMcp, mensagemDeErroRpc, type Autenticacao, type PortaMcp, type SessaoMcp } from './mcp-servidor';

const U1 = '11111111-1111-4111-8111-111111111111';
const U2 = '22222222-2222-4222-8222-222222222222';
const HASH = 'a'.repeat(64);

function porta(auth: Autenticacao, rpcs: Record<string, { data?: unknown; error?: { message: string; code?: string } }> = {}) {
  const chamadas: { rpc: string; params: Record<string, unknown>; sessao: SessaoMcp }[] = [];
  const autenticacoes: (string | null)[] = [];
  const p: PortaMcp = {
    autenticar: async (_h, ferramenta) => { autenticacoes.push(ferramenta); return auth; },
    rpc: async (sessao, rpc, params) => {
      chamadas.push({ rpc, params, sessao });
      const r = rpcs[rpc] ?? { data: null };
      return { data: r.data ?? null, error: r.error ?? null };
    },
  };
  return { p, chamadas, autenticacoes };
}

const sessao = (escopos: string[]): Autenticacao => ({
  ok: true, sessao: { tokenId: 't1', perfilId: U1, email: 'v@advmais.com', papel: 'vendedor', escopos },
});
const call = (name: string, args: unknown, id: number | string = 1) => ({ jsonrpc: '2.0', id, method: 'tools/call', params: { name, arguments: args } });

describe('atenderMcp: autenticação e protocolo', () => {
  it('token recusado → 401 com WWW-Authenticate; perfil → 403; desligado → 503; falha → 502', async () => {
    for (const [codigo, status] of [['token', 401], ['perfil', 403], ['desligado', 503], ['falha', 502]] as const) {
      const { p } = porta({ ok: false, codigo, msg: 'x' });
      const r = await atenderMcp({ jsonrpc: '2.0', id: 1, method: 'tools/list' }, HASH, p);
      expect(r.status).toBe(status);
      expect(r.autenticar ?? false).toBe(codigo === 'token');
    }
  });
  it('initialize negocia versão e anuncia tools; notificação → 202', async () => {
    const { p } = porta(sessao(['ler']));
    const r = await atenderMcp({ jsonrpc: '2.0', id: 0, method: 'initialize', params: { protocolVersion: '2025-03-26' } }, HASH, p);
    expect(r.status).toBe(200);
    expect(r.corpo).toMatchObject({ id: 0, result: { protocolVersion: '2025-03-26', capabilities: { tools: { listChanged: false } } } });
    expect((await atenderMcp({ jsonrpc: '2.0', method: 'notifications/initialized' }, HASH, p)).status).toBe(202);
  });
  it('tools/list respeita o escopo; initialize/list não contam no limite (ferramenta null)', async () => {
    const { p, autenticacoes } = porta(sessao(['ler']));
    const r = await atenderMcp({ jsonrpc: '2.0', id: 1, method: 'tools/list' }, HASH, p);
    const nomes = ((r.corpo as { result: { tools: { name: string }[] } }).result.tools).map((t) => t.name);
    expect(nomes).not.toContain('comercial_mover_etapa');
    expect(nomes).toContain('comercial_resumo_funil');
    expect(autenticacoes).toEqual([null]);
  });
  it('método desconhecido → -32601; lote → 400', async () => {
    const { p } = porta(sessao(['ler']));
    expect((await atenderMcp({ jsonrpc: '2.0', id: 1, method: 'resources/list' }, HASH, p)).corpo).toMatchObject({ error: { code: -32601 } });
    expect((await atenderMcp([], HASH, p)).status).toBe(400);
  });
});

describe('atenderMcp: ferramentas', () => {
  it('leitura roda como o dono do token e conta a ferramenta no limite', async () => {
    const { p, chamadas, autenticacoes } = porta(sessao(['ler']), { crm_funil_resumo: { data: { funilId: U1, etapas: [] } } });
    const r = await atenderMcp(call('comercial_resumo_funil', { funil_id: U1 }), HASH, p);
    expect(autenticacoes).toEqual(['comercial_resumo_funil']);
    expect(chamadas).toEqual([{ rpc: 'crm_funil_resumo', params: { p_funil: U1 }, sessao: expect.objectContaining({ perfilId: U1 }) }]);
    expect(r.corpo).toMatchObject({ result: { isError: false, structuredContent: { funilId: U1 } } });
  });
  it('token só "ler" não escreve (nem chama o banco)', async () => {
    const { p, chamadas } = porta(sessao(['ler']));
    const r = await atenderMcp(call('comercial_mover_etapa', { negocio_id: U1, etapa_id: U2 }), HASH, p);
    expect(r.corpo).toMatchObject({ result: { isError: true } });
    expect(chamadas).toHaveLength(0);
  });
  it('escrita recusada pelo banco (ok:false) vira erro da ferramenta com a mensagem do banco', async () => {
    const { p } = porta(sessao(['ler', 'operar']), { crm_mover_etapa: { data: { ok: false, msg: 'CRM em manutenção: escrita desligada.' } } });
    const r = await atenderMcp(call('comercial_mover_etapa', { negocio_id: U1, etapa_id: U2 }), HASH, p);
    expect(r.corpo).toMatchObject({ result: { isError: true, content: [{ text: 'CRM em manutenção: escrita desligada.' }] } });
  });
  it('escrita aceita devolve o {ok:true,…} do banco', async () => {
    const { p } = porta(sessao(['ler', 'operar']), { crm_adicionar_nota: { data: { ok: true, notaId: U2 } } });
    const r = await atenderMcp(call('comercial_adicionar_nota', { pessoa_id: U1, texto: 'Ligou e pediu proposta' }), HASH, p);
    expect(r.corpo).toMatchObject({ result: { isError: false, structuredContent: { ok: true, notaId: U2 } } });
  });
  it('argumento inválido não chama o banco; ferramenta desconhecida → -32602', async () => {
    const { p, chamadas } = porta(sessao(['ler']));
    expect((await atenderMcp(call('comercial_resumo_funil', { funil_id: 'x' }), HASH, p)).corpo).toMatchObject({ result: { isError: true } });
    expect((await atenderMcp(call('apagar_tudo', {}), HASH, p)).corpo).toMatchObject({ error: { code: -32602 } });
    expect(chamadas).toHaveLength(0);
  });
  it('limite estourado em tools/call vira erro da ferramenta (200)', async () => {
    const { p } = porta({ ok: false, codigo: 'limite', msg: 'Limite de 60 chamadas por minuto. Tente em instantes.' });
    const r = await atenderMcp(call('comercial_listar_funis', {}), HASH, p);
    expect(r.status).toBe(200);
    expect(r.corpo).toMatchObject({ result: { isError: true } });
  });
  it('erro do banco não vaza detalhe', async () => {
    const { p } = porta(sessao(['ler']), { crm_funis: { error: { message: 'permission denied for function crm_funis', code: '42501' } } });
    const r = await atenderMcp(call('comercial_listar_funis', {}), HASH, p);
    expect(r.corpo).toMatchObject({ result: { isError: true, content: [{ text: 'Sem acesso a este dado do Comercial.' }] } });
    expect(mensagemDeErroRpc({ message: 'Sem acesso ao Comercial.', code: '42501' })).toBe('Sem acesso ao Comercial.');
    expect(mensagemDeErroRpc({ message: 'relation x does not exist', code: '42P01' })).toBe('Não foi possível consultar o CRM agora.');
    expect(mensagemDeErroRpc({ message: 'Token do MCP inválido, revogado ou expirado.', code: '28000' })).toMatch(/Conecte de novo/);
  });
  it('"sem próximo passo" usa a pessoa conectada (sessão do token) para "os meus"', async () => {
    const { p, chamadas } = porta(sessao(['ler']), {
      crm_negocios: { data: [{ id: 'n1', donoId: U1, proximaAtividade: null }, { id: 'n2', donoId: U2, proximaAtividade: null }] },
    });
    const r = await atenderMcp(call('comercial_sem_proximo_passo', {}), HASH, p);
    expect(chamadas[0].sessao.tokenId).toBe('t1');
    expect(r.corpo).toMatchObject({ result: { structuredContent: { apenasMeus: true, total: 1, negocios: [{ id: 'n1' }] } } });
  });
});

describe('atenderMcp: WhatsApp pelo Claude (20261008233100)', () => {
  const envio = { contato_id: U1, texto: 'Oi João', chave_idempotencia: U2 };
  it('token só "ler" não envia nem lista números (nem chama o banco)', async () => {
    const { p, chamadas } = porta(sessao(['ler']));
    expect((await atenderMcp(call('comercial_enviar_whatsapp', envio), HASH, p)).corpo).toMatchObject({ result: { isError: true } });
    expect((await atenderMcp(call('comercial_numeros_whatsapp', {}), HASH, p)).corpo).toMatchObject({ result: { isError: true } });
    expect(chamadas).toHaveLength(0);
  });
  it('recusa do banco (janela fechada) vira erro com a mensagem clara', async () => {
    const msg = 'Janela de 24 h fechada neste número: precisa template. Veja comercial_templates_whatsapp.';
    const { p, chamadas } = porta(sessao(['ler', 'operar']), { crm_mcp_enviar_whatsapp: { data: { ok: false, msg } } });
    const r = await atenderMcp(call('comercial_enviar_whatsapp', envio), HASH, p);
    expect(chamadas).toEqual([{ rpc: 'crm_mcp_enviar_whatsapp', params: { p_contato: U1, p_chave: U2, p_texto: 'Oi João' },
      sessao: expect.objectContaining({ tokenId: 't1' }) }]);
    expect(r.corpo).toMatchObject({ result: { isError: true, content: [{ text: msg }] } });
  });
  it('envio aceito devolve a mensagem na fila', async () => {
    const { p } = porta(sessao(['ler', 'operar']), { crm_mcp_enviar_whatsapp: { data: { ok: true, mensagemId: U1, msg: 'Mensagem na fila de envio (enviada pelo Claude).' } } });
    const r = await atenderMcp(call('comercial_enviar_whatsapp', envio), HASH, p);
    expect(r.corpo).toMatchObject({ result: { isError: false, structuredContent: { ok: true, mensagemId: U1 } } });
  });
  it('contato falso: "Contato não encontrado." do banco chega ao Claude', async () => {
    const { p } = porta(sessao(['ler', 'operar']), { crm_mcp_situacao_conversa: { data: { ok: false, msg: 'Contato não encontrado.' } } });
    const r = await atenderMcp(call('comercial_situacao_conversa', { contato_id: U1 }), HASH, p);
    expect(r.corpo).toMatchObject({ result: { isError: true, content: [{ text: 'Contato não encontrado.' }] } });
  });
});
