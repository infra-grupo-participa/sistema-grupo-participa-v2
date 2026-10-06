import { describe, expect, it } from 'vitest';
import { FERRAMENTAS, acharFerramenta, diaSp, ferramentasDoEscopo, instante, limitesDoDia } from './mcp-ferramentas';
import { lerPedido, negociarVersao, VERSAO_PADRAO } from './mcp-protocolo';

const U1 = '11111111-1111-4111-8111-111111111111';
const U2 = '22222222-2222-4222-8222-222222222222';
const f = (n: string) => acharFerramenta(n)!;

describe('mcp: catálogo', () => {
  it('7 de leitura + 3 de escrita, nomes válidos para o MCP e para crm.mcp_chamada', () => {
    expect(FERRAMENTAS.filter((x) => x.escopo === 'ler')).toHaveLength(7);
    expect(FERRAMENTAS.filter((x) => x.escopo === 'operar').map((x) => x.name).sort())
      .toEqual(['comercial_adicionar_nota', 'comercial_criar_atividade', 'comercial_mover_etapa']);
    for (const x of FERRAMENTAS) {
      expect(x.name).toMatch(/^[a-z_]{3,60}$/);
      expect(x.annotations.readOnlyHint).toBe(x.escopo === 'ler');
      expect(!!x.escrita).toBe(x.escopo === 'operar');
    }
  });
  it('fora de propósito não existe: ganho, perda, transferência, disparo, exportação', () => {
    const nomes = FERRAMENTAS.map((x) => x.name).join(' ');
    expect(nomes).not.toMatch(/ganho|perdido|transferir|disparo|exportar|funil_salvar|oferta/);
  });
  it('escopo ler esconde as de escrita; ler+operar mostra todas', () => {
    expect(ferramentasDoEscopo(['ler']).every((x) => x.escopo === 'ler')).toBe(true);
    expect(ferramentasDoEscopo(['ler', 'operar'])).toHaveLength(FERRAMENTAS.length);
    expect(ferramentasDoEscopo([])).toHaveLength(0);
  });
  it('toda escrita chama só public.crm_* da F2 (as mesmas RPCs da tela)', () => {
    const rpcs = FERRAMENTAS.flatMap((x) => {
      const v = x.validar({ funil_id: U1, pessoa_id: U1, negocio_id: U1, etapa_id: U2, busca: 'ana', tipo: 'ligacao', titulo: 't', texto: 't', vence_em: '2026-10-06T10:00' });
      return v.ok ? x.plano(v.valor, new Date()).map((c) => c.rpc) : [];
    });
    for (const r of rpcs) expect(r).toMatch(/^crm_[a-z_]+$/);
    expect(rpcs).toEqual(expect.arrayContaining(['crm_criar_atividade', 'crm_adicionar_nota', 'crm_mover_etapa', 'crm_funil_resumo', 'crm_desempenho']));
  });
});

describe('mcp: validação de argumentos', () => {
  it('UUID obrigatório e formato', () => {
    expect(f('comercial_resumo_funil').validar({})).toEqual({ ok: false, msg: 'Informe funil_id.' });
    expect(f('comercial_resumo_funil').validar({ funil_id: 'x' })).toEqual({ ok: false, msg: 'funil_id precisa ser um UUID.' });
    expect(f('comercial_resumo_funil').validar({ funil_id: U1.toUpperCase() })).toEqual({ ok: true, valor: { funil_id: U1 } });
  });
  it('busca de pessoa exige 3+ caracteres e manda limite 20', () => {
    expect(f('comercial_buscar_pessoa').validar({ busca: 'ab' }).ok).toBe(false);
    const v = f('comercial_buscar_pessoa').validar({ busca: '  ana@x.com ' });
    expect(v.ok && f('comercial_buscar_pessoa').plano(v.valor, new Date())).toEqual([{ rpc: 'crm_contatos', params: { p_busca: 'ana@x.com', p_limite: 20 } }]);
  });
  it('criar atividade: tipo do enum, título, vencimento; sem fuso = Brasília', () => {
    const cria = f('comercial_criar_atividade');
    expect(cria.validar({ pessoa_id: U1, tipo: 'fax', titulo: 'x', vence_em: '2026-10-06' }).ok).toBe(false);
    expect(cria.validar({ pessoa_id: U1, tipo: 'ligacao', titulo: '', vence_em: '2026-10-06' }).ok).toBe(false);
    expect(cria.validar({ pessoa_id: U1, tipo: 'ligacao', titulo: 'x', vence_em: 'amanhã' }).ok).toBe(false);
    const v = cria.validar({ pessoa_id: U1, tipo: 'ligacao', titulo: ' Ligar ', vence_em: '2026-10-06T14:00' });
    expect(v.ok && cria.plano(v.valor, new Date())).toEqual([{
      rpc: 'crm_criar_atividade',
      params: { p_negocio: null, p_pessoa: U1, p_tipo: 'ligacao', p_titulo: 'Ligar', p_vence_em: '2026-10-06T17:00:00.000Z' },
    }]);
  });
  it('mover etapa e nota mapeiam para as assinaturas da F2', () => {
    const mv = f('comercial_mover_etapa').validar({ negocio_id: U1, etapa_id: U2 });
    expect(mv.ok && f('comercial_mover_etapa').plano(mv.valor, new Date())).toEqual([{ rpc: 'crm_mover_etapa', params: { p_negocio: U1, p_etapa: U2 } }]);
    const nt = f('comercial_adicionar_nota').validar({ pessoa_id: U1, texto: 'oi' });
    expect(nt.ok && f('comercial_adicionar_nota').plano(nt.valor, new Date())).toEqual([{ rpc: 'crm_adicionar_nota', params: { p_pessoa: U1, p_negocio: null, p_texto: 'oi' } }]);
  });
  it('limites numéricos', () => {
    expect(f('comercial_negocios_por_etapa').validar({ funil_id: U1, limite: 500 }).ok).toBe(false);
    expect(f('comercial_negocios_por_etapa').validar({ funil_id: U1, limite: 1.5 }).ok).toBe(false);
  });
});

describe('mcp: datas em São Paulo (UTC−3)', () => {
  it('instante: data vira meia-noite de Brasília; fim do dia = +24 h; ISO com fuso é respeitado', () => {
    expect(instante('2026-10-06')).toBe('2026-10-06T03:00:00.000Z');
    expect(instante('2026-10-06', true)).toBe('2026-10-07T03:00:00.000Z');
    expect(instante('2026-10-06T10:00:00Z')).toBe('2026-10-06T10:00:00.000Z');
    expect(instante('06/10/2026')).toBeNull();
    expect(instante('2026-02-31')).toBeNull();
    expect(instante('2026-02-30T10:00')).toBeNull();
  });
  it('diaSp e limitesDoDia', () => {
    expect(diaSp(new Date('2026-10-07T02:30:00Z'))).toBe('2026-10-06');
    expect(limitesDoDia('2026-10-06')).toEqual({ inicio: '2026-10-06T03:00:00.000Z', fim: '2026-10-07T03:00:00.000Z' });
  });
  it('desempenho: "ate" em data é inclusivo (vai até o fim do dia)', () => {
    const d = f('comercial_desempenho');
    const v = d.validar({ desde: '2026-10-01', ate: '2026-10-06' });
    expect(v.ok && d.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_desempenho', params: { p_desde: '2026-10-01T03:00:00.000Z', p_ate: '2026-10-07T03:00:00.000Z' } }]);
    const vazio = d.validar({});
    expect(vazio.ok && d.plano(vazio.valor, new Date())).toEqual([{ rpc: 'crm_desempenho', params: {} }]);
  });
});

describe('mcp: resultados', () => {
  it('atividades do dia separa do dia, atrasadas e concluídas', () => {
    const at = f('comercial_atividades_do_dia');
    const v = at.validar({ data: '2026-10-06' });
    if (!v.ok) throw new Error(v.msg);
    expect(at.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_atividades', params: { p_desde: '2026-10-06T03:00:00.000Z', p_limite: 2000 } }]);
    const r = at.resultado([[
      { id: 'a', venceEm: '2026-10-05T12:00:00Z', concluidaEm: null },
      { id: 'b', venceEm: '2026-10-06T12:00:00Z', concluidaEm: null },
      { id: 'c', venceEm: '2026-10-08T12:00:00Z', concluidaEm: null },
      { id: 'd', venceEm: '2026-10-06T12:00:00Z', concluidaEm: '2026-10-06T13:00:00Z' },
    ]], v.valor, new Date());
    expect({ dia: (r.doDia as { id: string }[]).map((x) => x.id), atr: (r.atrasadas as { id: string }[]).map((x) => x.id), con: (r.concluidas as { id: string }[]).map((x) => x.id) })
      .toEqual({ dia: ['b'], atr: ['a'], con: ['d'] });
  });
  it('negócios por etapa: com etapa, busca 500 do funil e corta na etapa e no limite', () => {
    const ng = f('comercial_negocios_por_etapa');
    const v = ng.validar({ funil_id: U1, etapa_id: U2, limite: 1 });
    if (!v.ok) throw new Error(v.msg);
    expect(ng.plano(v.valor, new Date())[0].params).toEqual({ p_funil: U1, p_status: 'aberto', p_limite: 500 });
    const r = ng.resultado([[{ id: 'n1', etapaId: U2 }, { id: 'n2', etapaId: U1 }, { id: 'n3', etapaId: U2 }]], v.valor, new Date());
    expect(r.total).toBe(2);
    expect(r.temMais).toBe(true);
    expect((r.negocios as { id: string }[]).map((x) => x.id)).toEqual(['n1']);
  });
});

describe('mcp: protocolo', () => {
  it('lote é recusado; pedido sem jsonrpc 2.0 é inválido', () => {
    expect(lerPedido([]).ok).toBe(false);
    expect(lerPedido({ method: 'x' }).ok).toBe(false);
    expect(lerPedido({ jsonrpc: '2.0', id: 1, method: 'ping' }).ok).toBe(true);
    expect(lerPedido({ jsonrpc: '2.0', id: 1, method: 'ping', params: [] }).ok).toBe(false);
  });
  it('versão: devolve a pedida se suportada, senão a mais nova', () => {
    expect(negociarVersao('2025-03-26')).toBe('2025-03-26');
    expect(negociarVersao('1999-01-01')).toBe(VERSAO_PADRAO);
  });
});
