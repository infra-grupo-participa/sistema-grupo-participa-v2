// Payloads no formato exato que as RPCs da migration 20261005s devolvem (jsonb_build_object em camelCase).
import { describe, expect, it } from 'vitest';
import {
  FormatoInesperado, mapAgrupadores, mapAtividades, mapBuscaPorLink, mapConfig, mapContatos, mapDashboards, mapEventos,
  mapFunis, mapJornada, mapLog, mapMotivosPerda, mapNegocios, mapNotificacoes, mapOfertas, mapOfertasOrfas, mapPainel,
  mapPreferencias, mapProdutosHotmart, mapSessao, mapVendedores, mensagemErroRpc,
  mapConversas, mapFichas, mapFilas, mapLinks, mapMensagens, mapTemplates, mapWhatsappStatus,
} from './mapeamento-supabase';
import type { PreferenciasNotificacao } from '../domain/types';

const U1 = '11111111-1111-1111-1111-111111111111';
const U2 = '22222222-2222-2222-2222-222222222222';

describe('erros e formato', () => {
  it('42501 mostra a mensagem do banco (sem acesso nunca vira zero)', () => {
    expect(mensagemErroRpc('crm_negocios', { code: '42501', message: 'Sem acesso ao Comercial.' })).toBe('Sem acesso ao Comercial.');
  });
  it('função inexistente explica que a migration não foi aplicada', () => {
    expect(mensagemErroRpc('crm_funis', { code: 'PGRST202', message: 'Could not find the function' })).toMatch(/crm_funis.*migration/);
  });
  it('erro genérico cita a RPC', () => {
    expect(mensagemErroRpc('crm_log', { message: 'timeout' })).toBe('Não foi possível carregar do banco (crm_log): timeout.');
  });
  it('lista que veio null ou objeto é erro, não lista vazia', () => {
    expect(() => mapNegocios(null)).toThrow(FormatoInesperado);
    expect(() => mapContatos({})).toThrow(/crm_contatos/);
    expect(mapNegocios([])).toEqual([]);
  });
  it('config null (crm.config sem linha) é erro', () => {
    expect(() => mapConfig(null)).toThrow(FormatoInesperado);
  });
});

describe('sessão, config, vendedores, agrupadores, motivos', () => {
  it('crm_sessao', () => {
    expect(mapSessao({ vendedorId: U1, papel: 'gestor' })).toEqual({ vendedorId: U1, papel: 'gestor' });
    expect(() => mapSessao({ vendedorId: U1, papel: 'admin' })).toThrow();
  });
  it('crm_config descarta escritaLigada e mantém limite null', () => {
    expect(mapConfig({ horarioContato: '', limiteNegociosAbertos: null, escritaLigada: false }))
      .toEqual({ horarioContato: '', limiteNegociosAbertos: null });
  });
  it('crm_vendedores', () => {
    expect(mapVendedores([{ id: U1, nome: 'Jonathan', sigla: 'JO', papel: 'gestor', ativo: true, percentual: 40, disparaApi: false }]))
      .toEqual([{ id: U1, nome: 'Jonathan', sigla: 'JO', papel: 'gestor', ativo: true, percentual: 40, disparaApi: false }]);
  });
  it('crm_agrupadores (produto = chave da linha)', () => {
    expect(mapAgrupadores([{ id: U1, nome: 'Holding Total', produto: 'ht', ordem: 1 }, { id: U2, nome: 'Solto', produto: null, ordem: 7 }]))
      .toEqual([{ id: U1, nome: 'Holding Total', produto: 'ht', ordem: 1 }, { id: U2, nome: 'Solto', produto: null, ordem: 7 }]);
  });
  it('crm_motivos_perda', () => {
    const [m] = mapMotivosPerda([{ key: 'nao_e_o_momento', label: 'Não é o momento', reativa: true, bloqueia: false, alertaGestor: false, nota: 'Volta para reativação', sistema: true, ativo: true }]);
    expect(m).toEqual({ key: 'nao_e_o_momento', label: 'Não é o momento', reativa: true, bloqueia: false, alertaGestor: false, nota: 'Volta para reativação', sistema: true, ativo: true });
  });
});

describe('crm_funis', () => {
  const funil = {
    id: U1, nome: 'Venda ativa HT', icone: 'kanban', projeto: 'ht34-meteorico', agrupadorId: U2, produto: 'ht', tipo: 'manual',
    eventosHotmart: [],
    etapas: [
      { id: 'e1', nome: 'Fazer primeiro contato', papel: 'primeiro_contato', cor: 'info', slaAtencaoMin: 5, slaCriticoMin: 15, camposObrigatorios: [], criterio: 'O lead respondeu' },
      { id: 'e2', nome: 'Fechado', papel: 'fechado', cor: 'green', slaAtencaoMin: null, slaCriticoMin: null, camposObrigatorios: ['forma_pagamento'], criterio: '' },
    ],
    campanhas: [{ id: 'c1', nome: 'Captação ht34', canal: 'utm', regra: 'utm_campaign = ht34', regraJson: { utm_campaign: 'ht34' }, ativa: true, criadoEm: '2026-10-06T12:00:00+00:00' }],
    distribuicao: null, ativo: true, criadoEm: '2026-10-06T12:00:00+00:00',
  };
  it('etapas, campanhas (sem regraJson) e distribuição geral = null', () => {
    const [f] = mapFunis([funil]);
    expect(f.etapas[1]).toEqual({ id: 'e2', nome: 'Fechado', papel: 'fechado', cor: 'green', slaAtencaoMin: null, slaCriticoMin: null, camposObrigatorios: ['forma_pagamento'], criterio: '' });
    expect(f.campanhas[0]).toEqual({ id: 'c1', nome: 'Captação ht34', canal: 'utm', regra: 'utm_campaign = ht34', ativa: true, criadoEm: '2026-10-06T12:00:00+00:00' });
    expect(f.distribuicao).toBeNull();
    expect(f.projeto).toBe('ht34-meteorico');
  });
  it('distribuição própria vira lista', () => {
    const [f] = mapFunis([{ ...funil, tipo: 'hotmart', eventosHotmart: ['carrinho_abandonado'], distribuicao: [{ vendedorId: U1, percentual: 100 }] }]);
    expect(f.distribuicao).toEqual([{ vendedorId: U1, percentual: 100 }]);
    expect(f.tipo).toBe('hotmart');
    expect(f.eventosHotmart).toEqual(['carrinho_abandonado']);
  });
});

describe('contatos, negócios, atividades', () => {
  it('crm_contatos com dado mascarado e utm', () => {
    const [c] = mapContatos([{
      id: U1, nome: 'Ana Barros', email: 'a***@gmail.com', telefone: '•••• 4321', cidade: 'Goiânia', uf: 'GO',
      perfil: 'advogado', atuaComHolding: 'comecando', donoId: null, tags: ['quente'],
      utm: { source: 'instagram', medium: null, campaign: 'ht33', content: null, sck: null },
      score: null, ehAluno: true, optOut: false, criadoEm: '2026-10-01T10:00:00+00:00',
    }]);
    expect(c).toEqual({
      id: U1, nome: 'Ana Barros', email: 'a***@gmail.com', telefone: '•••• 4321', cidade: 'Goiânia', uf: 'GO',
      perfil: 'advogado', atuaComHolding: 'comecando', donoId: null, tags: ['quente'],
      utm: { source: 'instagram', medium: null, campaign: 'ht33', content: null, sck: null },
      score: null, ehAluno: true, optOut: false, criadoEm: '2026-10-01T10:00:00+00:00',
    });
  });

  const neg = {
    id: U2, contatoId: U1, produto: 'hm', origem: 'venda_ativa', funilId: 'f1', campanhaId: null, etapaId: 'e1',
    etapaNome: 'Negociar', etapa: 'negociar', sla: { atencaoMin: 4320, criticoMin: 10080 }, status: 'aberto', donoId: U1,
    valor: 30000.5, campos: { objecao_principal: 'preco' }, motivoPerda: null, criadoEm: '2026-10-01T10:00:00+00:00',
    etapaDesde: '2026-10-02T10:00:00+00:00', fechadoEm: null,
    proximaAtividade: { id: 'a1', tipo: 'ligacao', titulo: 'Ligar', venceEm: '2026-10-07T13:00:00+00:00' },
    ultimaInteracaoEm: null,
  };
  it('crm_negocios com sla e próxima atividade', () => {
    const [n] = mapNegocios([neg]);
    expect(n.sla).toEqual({ atencaoMin: 4320, criticoMin: 10080 });
    expect(n.valor).toBe(30000.5);
    expect(n.campos).toEqual({ objecao_principal: 'preco' });
    expect(n.proximaAtividade).toEqual({ id: 'a1', tipo: 'ligacao', titulo: 'Ligar', venceEm: '2026-10-07T13:00:00+00:00' });
  });
  it('etapa sem alerta (sla null) e sem próxima atividade', () => {
    const [n] = mapNegocios([{ ...neg, sla: null, proximaAtividade: null, status: 'perdido', motivoPerda: 'sem_interesse', fechadoEm: '2026-10-05T10:00:00+00:00' }]);
    expect(n.sla).toBeNull();
    expect(n.proximaAtividade).toBeNull();
    expect(n.motivoPerda).toBe('sem_interesse');
  });
  it('crm_atividades', () => {
    expect(mapAtividades([{ id: 'a1', negocioId: null, contatoId: U1, donoId: U2, tipo: 'tarefa', titulo: 'Mandar material', venceEm: '2026-10-07T13:00:00+00:00', concluidaEm: null, resultado: null, cadenciaDia: 2 }]))
      .toEqual([{ id: 'a1', negocioId: null, contatoId: U1, donoId: U2, tipo: 'tarefa', titulo: 'Mandar material', venceEm: '2026-10-07T13:00:00+00:00', concluidaEm: null, resultado: null, cadenciaDia: 2 }]);
  });
});

describe('eventos, jornada, log', () => {
  it('crm_eventos (contatoId vem por último no jsonb)', () => {
    expect(mapEventos([{ id: 'log-9', negocioId: U2, tipo: 'etapa', titulo: 'Moveu para Negociar', detalhe: 'negociar', em: '2026-10-06T12:00:00+00:00', autorId: U1, contatoId: U1 }]))
      .toEqual([{ id: 'log-9', contatoId: U1, negocioId: U2, tipo: 'etapa', titulo: 'Moveu para Negociar', detalhe: 'negociar', em: '2026-10-06T12:00:00+00:00', autorId: U1 }]);
  });
  it('crm_jornada: compra com sck e inscrição com utm', () => {
    const pts = mapJornada([
      { id: 'hm-HP123', contatoId: U1, tipo: 'compra', em: '2026-09-20T10:00:00+00:00', titulo: 'Compra aprovada · Holding Total', detalhe: 'oferta abc · PIX', fonte: 'hotmart', lancamento: null, produto: 'ht', utm: { sck: 'jo-ht' }, valor: 297, negocioId: null },
      { id: 'or-1', contatoId: U1, tipo: 'inscricao', em: '2026-09-10T10:00:00+00:00', titulo: 'Inscrição · HT33', detalhe: null, fonte: 'formulario', lancamento: 'ht33', produto: null, utm: { source: 'ig', medium: null, campaign: 'ht33', content: null }, valor: null, negocioId: null },
    ]);
    expect(pts[0].utm).toEqual({ source: null, medium: null, campaign: null, content: null, sck: 'jo-ht' });
    expect(pts[0].valor).toBe(297);
    expect(pts[1].utm?.campaign).toBe('ht33');
    expect(pts[1].valor).toBeNull();
  });
  it('crm_jornada: utm null fica null', () => {
    const [p] = mapJornada([{ id: 'gr-1', contatoId: U1, tipo: 'grupo', em: '2026-09-01T10:00:00+00:00', titulo: 'Entrou no grupo', detalhe: null, fonte: 'sendflow', lancamento: null, produto: null, utm: null, valor: null, negocioId: null }]);
    expect(p.utm).toBeNull();
  });
  it('crm_log com mudanças', () => {
    const [l] = mapLog([{ id: '42', em: '2026-10-06T12:00:00+00:00', autorId: null, acao: 'moveu_etapa', entidade: 'negocio', entidadeId: U2, resumo: 'Moveu Ana de Qualificar para Negociar', mudancas: [{ campo: 'etapa', antes: 'Qualificar', depois: 'Negociar' }], contatoId: U1 }]);
    expect(l).toEqual({ id: '42', em: '2026-10-06T12:00:00+00:00', autorId: null, acao: 'moveu_etapa', entidade: 'negocio', entidadeId: U2, contatoId: U1, resumo: 'Moveu Ana de Qualificar para Negociar', mudancas: [{ campo: 'etapa', antes: 'Qualificar', depois: 'Negociar' }] });
  });
});

describe('painel, dashboards, notificações, preferências', () => {
  const widget = { id: 'w1', titulo: 'Vendas', metrica: 'vendas', visual: 'numero', periodo: 'mes', agrupar: 'nenhum', largura: 2, funilId: null };
  it('crm_painel null = não personalizou', () => {
    expect(mapPainel(null)).toBeNull();
    expect(mapPainel({ vendedorId: U1, widgets: [widget] })).toEqual({ vendedorId: U1, widgets: [widget] });
  });
  it('crm_dashboards', () => {
    const [d] = mapDashboards([{ id: U2, nome: 'Semana', descricao: null, donoId: U1, compartilhado: true, widgets: [widget], criadoEm: 'x', atualizadoEm: 'y' }]);
    expect(d.widgets).toEqual([widget]);
    expect(d.compartilhado).toBe(true);
  });
  it('crm_notificacoes (id bigint vem como texto)', () => {
    expect(mapNotificacoes([{ id: '7', vendedorId: U1, gatilho: 'lead_novo', titulo: 'Lead novo', corpo: 'Ana', href: '/comercial/funil', em: 'x', lida: false }]))
      .toEqual([{ id: '7', vendedorId: U1, gatilho: 'lead_novo', titulo: 'Lead novo', corpo: 'Ana', href: '/comercial/funil', em: 'x', lida: false }]);
  });
  const padrao: PreferenciasNotificacao = {
    vendedorId: U1, desktop: false,
    gatilhos: { lead_novo: true, lead_respondeu: true, prazo_estourado: true, venda_aprovada: true, ficha_para_aprovar: true, atividade_vencendo: true },
    silencioInicio: '20:00', silencioFim: '08:00',
  };
  it('crm_preferencias null = padrão', () => {
    expect(mapPreferencias(null, padrao)).toBe(padrao);
  });
  it('crm_preferencias parcial herda os gatilhos que faltam', () => {
    const p = mapPreferencias({ vendedorId: U1, desktop: true, gatilhos: { lead_novo: false }, silencioInicio: null, silencioFim: null }, padrao);
    expect(p.desktop).toBe(true);
    expect(p.gatilhos.lead_novo).toBe(false);
    expect(p.gatilhos.venda_aprovada).toBe(true);
    expect(p.silencioInicio).toBeNull();
  });
});

describe('produtos e ofertas', () => {
  const produto = { produtoId: '123', nomeHotmart: 'Holding Total', conta: 'academy', familia: 'ht', noComercial: true, nomeComercial: 'HT', produtoKey: 'ht', agrupadorId: U1, escada: 'B', sincronizadoEm: '2026-10-05T10:00:00+00:00' };
  const oferta = { codigo: 'abc12', produtoId: '123', nomeHotmart: 'Lote 1', preco: 297, moeda: 'BRL', modo: 'UNIQUE_PAYMENT', principal: true, linkCheckout: 'https://pay.hotmart.com/123?off=abc12', vigente: true, condicao: '12x', validaAte: '2026-10-31', uso: 'carrinho', transacoes: 15, ultimaVendaEm: '2026-10-04T10:00:00+00:00', vistaEm: '2026-10-05T10:00:00+00:00' };
  it('crm_produtos_hotmart (produto sem oferta: sincronizadoEm null vira "")', () => {
    const [p, q] = mapProdutosHotmart([produto, { ...produto, produtoId: '9', noComercial: false, nomeComercial: null, produtoKey: null, agrupadorId: null, escada: null, sincronizadoEm: null, conta: 'escritorio' }]);
    expect(p).toEqual(produto);
    expect(q.sincronizadoEm).toBe('');
    expect(q.conta).toBe('escritorio');
    expect(q.escada).toBeNull();
  });
  it('crm_ofertas', () => {
    expect(mapOfertas([oferta])).toEqual([oferta]);
  });
  it('crm_ofertas_orfas', () => {
    expect(mapOfertasOrfas([{ codigo: 'zz9', produtoId: null, transacoes: 3, ultimaEm: '2026-10-01T10:00:00+00:00' }]))
      .toEqual([{ codigo: 'zz9', produtoId: null, transacoes: 3, ultimaEm: '2026-10-01T10:00:00+00:00' }]);
  });
  it('crm_buscar_por_link: achou e não achou', () => {
    expect(mapBuscaPorLink({ produto, oferta, codigo: 'abc12' })).toEqual({ produto, oferta, codigo: 'abc12' });
    expect(mapBuscaPorLink({ produto: null, oferta: null, codigo: 'naoexiste' })).toEqual({ produto: null, oferta: null, codigo: 'naoexiste' });
    expect(mapBuscaPorLink({ produto: null, oferta: null, codigo: null })).toEqual({ produto: null, oferta: null, codigo: null });
  });
});

describe('mapPaginaContatos', () => {
  it('lê { itens, temMais } da crm_contatos', async () => {
    const { mapPaginaContatos } = await import('./mapeamento-supabase');
    const pg = mapPaginaContatos({ itens: [], temMais: true });
    expect(pg).toEqual({ itens: [], temMais: true });
    expect(() => mapPaginaContatos(null)).toThrow();
  });
});

// Payloads no formato de crm.mensagem_json / crm_conversas / crm_fichas (20261006051434) e crm_filas / crm_links (20261006044653).
describe('WhatsApp (F4)', () => {
  const entrada = { id: U1, contatoId: U2, canal: 'whatsapp', direcao: 'entrada', tipo: 'texto', texto: 'Oi', em: '2026-10-06T10:00:00+00:00', status: null, envio: null, erro: null, autorId: null, templateId: null, fichaId: null };
  const naFila = { ...entrada, id: 'm2', direcao: 'saida', texto: 'Olá', status: null, envio: 'na_fila', autorId: U1 };
  const falhou = { ...entrada, id: 'm3', direcao: 'saida', tipo: 'template', status: 'falhou', erro: 'Número inválido', templateId: U1 };
  it('crm_mensagens: entrada não lida, saída na fila e falha com erro', () => {
    const [a, b, c] = mapMensagens([entrada, naFila, falhou]);
    expect(a).toEqual({ ...entrada, envio: null });
    expect(b).toMatchObject({ direcao: 'saida', status: null, envio: 'na_fila' });
    expect(c).toMatchObject({ status: 'falhou', erro: 'Número inválido', tipo: 'template', templateId: U1 });
    expect(() => mapMensagens([{ ...entrada, direcao: 'x' }])).toThrow(/crm_mensagens/);
    expect(() => mapMensagens(null)).toThrow(FormatoInesperado);
  });
  it('crm_conversas', () => {
    const [c] = mapConversas([{ contatoId: U2, ultimaMensagem: entrada, naoLidas: 2, janelaAteEm: '2026-10-07T10:00:00+00:00', atribuidaA: null }]);
    expect(c).toMatchObject({ contatoId: U2, naoLidas: 2, janelaAteEm: '2026-10-07T10:00:00+00:00', atribuidaA: null });
    expect(c.ultimaMensagem.id).toBe(U1);
    expect(() => mapConversas([{ contatoId: U2, ultimaMensagem: null }])).toThrow(/última mensagem/);
    expect(mapConversas([])).toEqual([]);
  });
  it('crm_templates', () => {
    expect(mapTemplates([{ id: U1, nome: 'boas_vindas', categoria: 'utility', texto: 'Oi {{1}}', aprovado: true, idioma: 'pt_BR', variaveis: 1 }]))
      .toEqual([{ id: U1, nome: 'boas_vindas', categoria: 'utility', texto: 'Oi {{1}}', aprovado: true, idioma: 'pt_BR', variaveis: 1 }]);
  });
  it('crm_fichas: resultado só na enviada, com naFila', () => {
    const base = { id: U1, codigo: 'HM-20261006-01', objetivo: 'X', produto: 'hm', filtro: 'F', quantidade: 10, supressoes: ['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou'], suprimidos: 2, templateId: U2, numeroEnvio: '5511999990000', agendadoPara: '2026-10-07T13:00:00+00:00', operadorId: U1, link: 'https://x', status: 'rascunho', aprovadoPor: null, criadoEm: '2026-10-06T10:00:00+00:00', motivoStatus: null, resultado: null };
    expect(mapFichas([base])).toEqual([base]);
    const [e] = mapFichas([{ ...base, status: 'enviada', resultado: { entregues: 8, lidas: 5, respostas: 1, falhas: 0, naFila: 2 } }]);
    expect(e.resultado).toEqual({ entregues: 8, lidas: 5, respostas: 1, falhas: 0, naFila: 2 });
    expect(() => mapFichas([{ ...base, status: 'outro' }])).toThrow(/crm_fichas/);
  });
  it('crm_whatsapp_status (desligado, sem número)', () => {
    expect(mapWhatsappStatus({ whatsappLigado: false, envioLigado: false, escritaLigada: true, numero: null, templatesAprovados: 0, naFila: 0, falhasHoje: 0, janelaHoras: 24, maxDestinatarios: 2000 }))
      .toEqual({ whatsappLigado: false, envioLigado: false, escritaLigada: true, numero: null, templatesAprovados: 0, naFila: 0, falhasHoje: 0, janelaHoras: 24, maxDestinatarios: 2000 });
    expect(() => mapWhatsappStatus(null)).toThrow(FormatoInesperado);
  });
});

describe('filas e links (F5)', () => {
  const item = { id: U2, contatoId: U1, score: 80, faixa: 'A', sinais: ['carrinho'], status: 'a_abordar', responsavelId: null, alteradoPor: null, alteradoEm: null };
  const fila = { id: U1, nome: 'Imersão SET26', produto: 'hm', criadaEm: '2026-10-01T10:00:00+00:00', ofertaVigente: '12x de 297', ofertaCodigo: 'abc', projeto: 'imersao-set26', encerradaEm: null, itens: [item] };
  it('crm_filas', () => {
    expect(mapFilas([fila])).toEqual([fila]);
    expect(() => mapFilas([{ ...fila, itens: null }])).toThrow(/crm_filas/);
    expect(() => mapFilas([{ ...fila, itens: [{ ...item, faixa: 'Z' }] }])).toThrow(/faixa/);
  });
  it('crm_links', () => {
    const l = { id: U1, vendedorId: U2, produto: 'hm', acao: 'disparo', url: 'https://pay.hotmart.com?off=a&sck=s', sck: 's', canal: 'whatsapp', ofertaCodigo: 'a', projeto: null, conteudo: null, criadoEm: '2026-10-06T10:00:00+00:00', arquivadoEm: null };
    expect(mapLinks([{ ...l, vendas: null, receita: null }])).toEqual([l]);
    expect(() => mapLinks({})).toThrow(/crm_links/);
  });
});
