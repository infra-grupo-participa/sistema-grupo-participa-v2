import { describe, expect, it } from 'vitest';
import { FERRAMENTAS, acharFerramenta, diaSp, ferramentasDoEscopo, instante, limitesDoDia } from './mcp-ferramentas';
import { lerPedido, negociarVersao, VERSAO_PADRAO } from './mcp-protocolo';

const U1 = '11111111-1111-4111-8111-111111111111';
const U2 = '22222222-2222-4222-8222-222222222222';
const f = (n: string) => acharFerramenta(n)!;
const VEND = { perfilId: U1, papel: 'vendedor' as const };
const GEST = { perfilId: U2, papel: 'gestor' as const };
const CONSULTAS_WHATSAPP = ['comercial_numeros_whatsapp', 'comercial_templates_whatsapp', 'comercial_situacao_conversa'];

describe('mcp: catálogo', () => {
  it('9 de leitura + 13 no escopo operar (9 escritas + 4 do WhatsApp), nomes válidos para o MCP e para crm.mcp_chamada', () => {
    expect(FERRAMENTAS.filter((x) => x.escopo === 'ler')).toHaveLength(9);
    expect(FERRAMENTAS.filter((x) => x.escopo === 'operar').map((x) => x.name).sort())
      .toEqual(['comercial_adicionar_nota', 'comercial_concluir_atividade', 'comercial_criar_atividade', 'comercial_criar_contato',
        'comercial_editar_contato', 'comercial_enviar_whatsapp', 'comercial_mover_etapa', 'comercial_numeros_whatsapp',
        'comercial_reabrir_atividade', 'comercial_situacao_conversa', 'comercial_tag_adicionar', 'comercial_tag_remover',
        'comercial_templates_whatsapp']);
    for (const x of FERRAMENTAS) {
      expect(x.name).toMatch(/^[a-z_]{3,60}$/);
      expect(x.annotations.readOnlyHint).toBe(x.escopo === 'ler' || CONSULTAS_WHATSAPP.includes(x.name));
      expect(!!x.escrita).toBe(x.escopo === 'operar');
    }
  });
  it('fora de propósito não existe: ganho, perda, transferência, disparo, exportação; o único envio é o 1:1 de WhatsApp', () => {
    const nomes = FERRAMENTAS.map((x) => x.name).filter((n) => n !== 'comercial_enviar_whatsapp').join(' ');
    expect(nomes).not.toMatch(/ganho|perdido|transferir|disparo|enviar|exportar|funil_salvar|oferta|apagar|excluir|massa/);
  });
  it('toda RPC usada está na lista fechada de public.crm_mcp_rpc (migrations 20261008150823 e 20261008222038)', () => {
    const LISTA = ['crm_funis', 'crm_funil_resumo', 'crm_negocios', 'crm_contatos', 'crm_jornada', 'crm_atividades',
      'crm_desempenho', 'crm_mensagens', 'crm_criar_atividade', 'crm_adicionar_nota', 'crm_mover_etapa', 'crm_concluir_atividade',
      'crm_criar_contato', 'crm_editar_contato', 'crm_tags_contato', 'crm_reabrir_atividade',
      'crm_mcp_numeros', 'crm_mcp_templates', 'crm_mcp_situacao_conversa', 'crm_mcp_enviar_whatsapp'];
    const args = { funil_id: U1, pessoa_id: U1, negocio_id: U1, etapa_id: U2, atividade_id: U1, busca: 'ana', tipo: 'ligacao', titulo: 't', texto: 't',
      vence_em: '2026-10-06T10:00', nome: 'Ana Souza', email: 'ana@exemplo.com', tags: ['vip'], contato_id: U1, chave_idempotencia: U2 };
    let planos = 0;
    for (const x of FERRAMENTAS) {
      const v = x.validar(args);
      if (!v.ok) continue;
      for (const c of x.plano(v.valor, new Date())) { expect(LISTA).toContain(c.rpc); planos++; }
    }
    expect(planos).toBeGreaterThanOrEqual(FERRAMENTAS.length);
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
    ]], v.valor, new Date(), VEND);
    expect({ dia: (r.doDia as { id: string }[]).map((x) => x.id), atr: (r.atrasadas as { id: string }[]).map((x) => x.id), con: (r.concluidas as { id: string }[]).map((x) => x.id) })
      .toEqual({ dia: ['b'], atr: ['a'], con: ['d'] });
  });
  it('negócios por etapa: com etapa, busca 1.000 e corta na etapa e no limite', () => {
    const ng = f('comercial_negocios_por_etapa');
    const v = ng.validar({ funil_id: U1, etapa_id: U2, limite: 1 });
    if (!v.ok) throw new Error(v.msg);
    expect(ng.plano(v.valor, new Date())[0].params).toEqual({ p_funil: U1, p_status: 'aberto', p_limite: 1000 });
    const r = ng.resultado([[{ id: 'n1', etapaId: U2 }, { id: 'n2', etapaId: U1 }, { id: 'n3', etapaId: U2 }]], v.valor, new Date(), VEND);
    expect(r.total).toBe(2);
    expect(r.temMais).toBe(true);
    expect((r.negocios as { id: string }[]).map((x) => x.id)).toEqual(['n1']);
  });
  it('negócios: sem funil = todos os funis; apenas_meus filtra pelo dono conectado', () => {
    const ng = f('comercial_negocios_por_etapa');
    const v = ng.validar({ apenas_meus: true });
    if (!v.ok) throw new Error(v.msg);
    expect(ng.plano(v.valor, new Date())[0].params).toEqual({ p_funil: null, p_status: 'aberto', p_limite: 1000 });
    const r = ng.resultado([[{ id: 'n1', donoId: U1 }, { id: 'n2', donoId: U2 }, { id: 'n3', donoId: null }]], v.valor, new Date(), VEND);
    expect((r.negocios as { id: string }[]).map((x) => x.id)).toEqual(['n1']);
  });
  it('sem próximo passo: só abertos sem atividade; vendedor = os dele, gestor = todos; mais parado primeiro', () => {
    const sp = f('comercial_sem_proximo_passo');
    const v = sp.validar({});
    if (!v.ok) throw new Error(v.msg);
    expect(sp.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_negocios', params: { p_funil: null, p_status: 'aberto', p_limite: 1000 } }]);
    const ns = [
      { id: 'a', donoId: U1, proximaAtividade: null, ultimaInteracaoEm: '2026-10-05T10:00:00Z' },
      { id: 'b', donoId: U1, proximaAtividade: { id: 'x', tipo: 'ligacao', titulo: 't', venceEm: '2026-10-09T10:00:00Z' } },
      { id: 'c', donoId: U2, proximaAtividade: null, etapaDesde: '2026-10-01T10:00:00Z' },
      { id: 'd', donoId: U1, proximaAtividade: null, ultimaInteracaoEm: '2026-10-02T10:00:00Z' },
    ];
    const rv = sp.resultado([ns], v.valor, new Date(), VEND);
    expect((rv.negocios as { id: string }[]).map((x) => x.id)).toEqual(['d', 'a']);
    const rg = sp.resultado([ns], v.valor, new Date(), GEST);
    expect((rg.negocios as { id: string }[]).map((x) => x.id)).toEqual(['c', 'd', 'a']);
    expect(sp.validar({ apenas_meus: 'sim' }).ok).toBe(false);
  });
  it('conversa de WhatsApp: só leitura, campos enxutos (sem caminho de mídia nem ids internos)', () => {
    const cw = f('comercial_conversa_whatsapp');
    expect(cw.escopo).toBe('ler');
    const v = cw.validar({ pessoa_id: U1 });
    if (!v.ok) throw new Error(v.msg);
    expect(cw.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_mensagens', params: { p_pessoa: U1, p_limite: 100 } }]);
    const r = cw.resultado([[
      { id: 'm1', direcao: 'entrada', tipo: 'texto', texto: 'Oi', em: '2026-10-06T10:00:00Z', midia: { caminho: 'x/y.jpg' }, autorId: U2 },
      { id: 'm2', direcao: 'saida', tipo: 'texto', texto: 'Olá!', em: '2026-10-06T10:01:00Z', status: 'lida', erro: null },
    ]], v.valor, new Date(), VEND);
    expect(r.mensagens).toEqual([
      { em: '2026-10-06T10:00:00Z', de: 'cliente', tipo: 'texto', texto: 'Oi' },
      { em: '2026-10-06T10:01:00Z', de: 'equipe', tipo: 'texto', texto: 'Olá!', status: 'lida' },
    ]);
    expect(JSON.stringify(r)).not.toContain('caminho');
  });
  it('concluir atividade: escrita, resultado opcional', () => {
    const ca = f('comercial_concluir_atividade');
    expect(ca.escrita).toBe(true);
    const v = ca.validar({ atividade_id: U1, resultado: ' Atendeu ' });
    expect(v.ok && ca.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_concluir_atividade', params: { p_atividade: U1, p_resultado: 'Atendeu' } }]);
    const sem = ca.validar({ atividade_id: U1 });
    expect(sem.ok && ca.plano(sem.valor, new Date())[0].params).toEqual({ p_atividade: U1, p_resultado: null });
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

describe('mcp: contato, tags e reabrir (20261008222038)', () => {
  it('criar contato: nome + telefone ou e-mail; sem dono no pedido', () => {
    const cc = f('comercial_criar_contato');
    expect(cc.validar({ nome: 'Ana' })).toEqual({ ok: false, msg: 'Informe telefone ou e-mail.' });
    expect(cc.validar({ nome: 'A', email: 'a@b.co' }).ok).toBe(false);
    expect(cc.validar({ nome: 'Ana', email: 'nao-e-email' }).ok).toBe(false);
    expect(cc.validar({ nome: 'Ana', telefone: 'abc' }).ok).toBe(false);
    expect(cc.validar({ nome: 'Ana', email: 'a@b.co', dono: U1 }).ok).toBe(true); // campo extra é ignorado (o schema recusa no cliente)
    const v = cc.validar({ nome: ' Ana Souza ', telefone: '(21) 98765-4321' });
    expect(v.ok && cc.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_criar_contato', params: { p_dados: { nome: 'Ana Souza', telefone: '(21) 98765-4321' } } }]);
  });
  it('criar contato repetido: ok=true do banco devolve o existente (nova=false)', () => {
    const cc = f('comercial_criar_contato');
    const v = cc.validar({ nome: 'Ana', email: 'a@b.co' });
    if (!v.ok) throw new Error(v.msg);
    expect(cc.resultado([{ ok: true, msg: 'Esse contato já estava no CRM: abri a ficha dele.', contatoId: U1, nova: false }], v.valor, new Date(), VEND))
      .toMatchObject({ ok: true, contatoId: U1, nova: false });
  });
  it('editar contato: só os campos enviados, chaves da RPC, vazio limpa', () => {
    const ec = f('comercial_editar_contato');
    expect(ec.validar({ pessoa_id: U1 })).toEqual({ ok: false, msg: 'Informe ao menos um campo para mudar.' });
    expect(ec.validar({ pessoa_id: U1, uf: 'São' }).ok).toBe(false);
    expect(ec.validar({ pessoa_id: U1, perfil: 'medico' }).ok).toBe(false);
    const v = ec.validar({ pessoa_id: U1, cidade: ' Niterói ', uf: 'rj', perfil: 'advogado', atua_com_holding: 'comecando', observacao: '' });
    expect(v.ok && ec.plano(v.valor, new Date())).toEqual([{
      rpc: 'crm_editar_contato',
      params: { p_contato: U1, p_dados: { cidade: 'Niterói', uf: 'rj', observacao: '', perfil: 'advogado', atuaComHolding: 'comecando' } },
    }]);
  });
  it('tags: lista de 1 a 30, inválida recusada, adicionar e remover usam a mesma RPC', () => {
    const ta = f('comercial_tag_adicionar');
    const tr = f('comercial_tag_remover');
    expect(ta.validar({ pessoa_id: U1, tags: [] }).ok).toBe(false);
    expect(ta.validar({ pessoa_id: U1, tags: ['🔔'] }).ok).toBe(false);
    expect(ta.validar({ pessoa_id: U1, tags: Array.from({ length: 31 }, (_, i) => `t${i}`) }).ok).toBe(false);
    const v = ta.validar({ pessoa_id: U1, tags: [' Quente Ágora '] });
    expect(v.ok && ta.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_tags_contato', params: { p_pessoa: U1, p_adicionar: ['Quente Ágora'] } }]);
    const r = tr.validar({ pessoa_id: U1, tags: ['[HT] ALUNOS'] });
    expect(r.ok && tr.plano(r.valor, new Date())).toEqual([{ rpc: 'crm_tags_contato', params: { p_pessoa: U1, p_remover: ['[HT] ALUNOS'] } }]);
  });
  it('reabrir atividade', () => {
    const ra = f('comercial_reabrir_atividade');
    expect(ra.validar({}).ok).toBe(false);
    const v = ra.validar({ atividade_id: U1 });
    expect(v.ok && ra.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_reabrir_atividade', params: { p_atividade: U1 } }]);
  });
});

describe('mcp: WhatsApp pelo Claude (20261008233100)', () => {
  const env = f('comercial_enviar_whatsapp');
  it('descrição exige confirmação explícita antes de enviar', () => {
    expect(env.description).toMatch(/^IMPORTANTE: antes de chamar, mostre ao usuário o texto final.*o número e o destinatário e peça confirmação explícita/);
    expect(env.escopo).toBe('operar');
    expect(env.escrita).toBe(true);
    expect(env.inputSchema.required).toEqual(['contato_id', 'chave_idempotencia']);
  });
  it('texto OU template, nunca os dois nem nenhum', () => {
    expect(env.validar({ contato_id: U1, chave_idempotencia: U2 })).toEqual({ ok: false, msg: 'Informe texto OU template (um dos dois).' });
    expect(env.validar({ contato_id: U1, chave_idempotencia: U2, texto: 'oi', template: 'x' }).ok).toBe(false);
    expect(env.validar({ contato_id: U1, chave_idempotencia: U2, texto: '   ' }).ok).toBe(false);
    expect(env.validar({ contato_id: U1, chave_idempotencia: U2, texto: 'x'.repeat(4097) }).ok).toBe(false);
  });
  it('chave_idempotencia obrigatória e UUID', () => {
    expect(env.validar({ contato_id: U1, texto: 'oi' })).toEqual({ ok: false, msg: 'Informe chave_idempotencia.' });
    expect(env.validar({ contato_id: U1, texto: 'oi', chave_idempotencia: 'abc' }).ok).toBe(false);
  });
  it('plano: texto livre com número escolhido', () => {
    const v = env.validar({ contato_id: U1, numero_id: U2, texto: ' Oi João ', chave_idempotencia: U2 });
    expect(v.ok).toBe(true);
    if (!v.ok) return;
    expect(env.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_mcp_enviar_whatsapp',
      params: { p_contato: U1, p_chave: U2, p_canal: U2, p_texto: 'Oi João' } }]);
  });
  it('plano: template sem número (o banco escolhe a conversa mais recente, senão o oficial)', () => {
    const v = env.validar({ contato_id: U1, template: 'boas_vindas', chave_idempotencia: U2 });
    expect(v.ok).toBe(true);
    if (!v.ok) return;
    expect(env.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_mcp_enviar_whatsapp',
      params: { p_contato: U1, p_chave: U2, p_template: 'boas_vindas' } }]);
  });
  it('situação: só contato é obrigatório; número e template opcionais', () => {
    const s = f('comercial_situacao_conversa');
    expect(s.validar({}).ok).toBe(false);
    const v = s.validar({ contato_id: U1, template: 'aula' });
    expect(v.ok).toBe(true);
    if (!v.ok) return;
    expect(s.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_mcp_situacao_conversa', params: { p_contato: U1, p_template: 'aula' } }]);
  });
  it('templates: busca opcional e limite', () => {
    const t = f('comercial_templates_whatsapp');
    const v = t.validar({});
    expect(v.ok).toBe(true);
    if (!v.ok) return;
    expect(t.plano(v.valor, new Date())).toEqual([{ rpc: 'crm_mcp_templates', params: { p_busca: null, p_limite: 50 } }]);
    expect(t.validar({ limite: 500 }).ok).toBe(false);
  });
  it('consultas do WhatsApp só aparecem com o escopo operar', () => {
    const so = ferramentasDoEscopo(['ler']).map((x) => x.name);
    for (const n of [...CONSULTAS_WHATSAPP, 'comercial_enviar_whatsapp']) expect(so).not.toContain(n);
  });
  it('resultado devolve o que o banco mandou (ok incluído)', () => {
    expect(env.resultado([{ ok: true, msg: 'Mensagem na fila', mensagemId: U1 }], {}, new Date(), VEND))
      .toEqual({ ok: true, msg: 'Mensagem na fila', mensagemId: U1 });
    expect(f('comercial_numeros_whatsapp').resultado([null], {}, new Date(), GEST)).toEqual({});
  });
});
