// Payloads no formato exato que as RPCs de escrita da migration 20261005t devolvem (crm.res: {ok, msg?, …ids}).
import { describe, expect, it } from 'vitest';
import {
  argsEscrita, mapResultado, mapResultadoComId, mapResultadoNegocio, mapResultadoProjeto, mensagemErroEscrita,
  mapResultadoFicha, mapResultadoLink, mapResultadoTokenMcp,
} from './mapeamento-escrita';
import { FormatoInesperado } from './mapeamento-supabase';
import type { Funil, PainelPessoa } from '../domain/types';

const U1 = '11111111-1111-1111-1111-111111111111';
const U2 = '22222222-2222-2222-2222-222222222222';

describe('resultado das RPCs de escrita', () => {
  it('ok sem mensagem', () => {
    expect(mapResultado('crm_mover_etapa', { ok: true })).toEqual({ ok: true });
  });
  it('regra violada passa a mensagem do banco (= mock)', () => {
    expect(mapResultado('crm_mover_etapa', { ok: false, msg: 'Preencha antes: Perfil profissional.' }))
      .toEqual({ ok: false, msg: 'Preencha antes: Perfil profissional.' });
  });
  it('kill-switch desligado vira ok:false com a mensagem de manutenção', () => {
    expect(mapResultado('crm_salvar_campos', { ok: false, msg: 'CRM em manutenção: escrita desligada.' }).ok).toBe(false);
  });
  it('formato fora do contrato é erro, nunca sucesso presumido', () => {
    expect(() => mapResultado('crm_mover_etapa', null)).toThrow(FormatoInesperado);
    expect(() => mapResultado('crm_mover_etapa', [])).toThrow(FormatoInesperado);
    expect(() => mapResultado('crm_mover_etapa', { msg: 'x' })).toThrow(/sem "ok"/);
    expect(() => mapResultado('crm_mover_etapa', { ok: 'true' })).toThrow(FormatoInesperado);
  });
  it('id só volta com ok=true', () => {
    expect(mapResultadoComId('crm_salvar_funil', { ok: true, msg: 'Funil criado.', funilId: U1 }, 'funilId'))
      .toEqual({ ok: true, msg: 'Funil criado.', funilId: U1 });
    expect(mapResultadoComId('crm_salvar_funil', { ok: false, msg: 'Dê um nome ao funil.', funilId: U1 }, 'funilId'))
      .toEqual({ ok: false, msg: 'Dê um nome ao funil.' });
  });
  it('criarNegocio devolve negocioId e donoId (null = sem dono)', () => {
    expect(mapResultadoNegocio({ ok: true, negocioId: U1, donoId: U2 })).toEqual({ ok: true, negocioId: U1, donoId: U2 });
    expect(mapResultadoNegocio({ ok: true, negocioId: U1, donoId: null })).toEqual({ ok: true, negocioId: U1, donoId: null });
    expect(mapResultadoNegocio({ ok: false, msg: 'Este contato já tem negócio aberto neste funil.' }))
      .toEqual({ ok: false, msg: 'Este contato já tem negócio aberto neste funil.' });
  });
  it('criarProjeto devolve a lista de funis', () => {
    expect(mapResultadoProjeto({ ok: true, msg: '4 funis criados para HT34.', funilIds: [U1, U2] }))
      .toEqual({ ok: true, msg: '4 funis criados para HT34.', funilIds: [U1, U2] });
  });
});

describe('erro de chamada', () => {
  it('função ausente explica que a migration não foi aplicada', () => {
    expect(mensagemErroEscrita('crm_mover_etapa', { code: 'PGRST202', message: 'Could not find' })).toMatch(/crm_mover_etapa.*migration/);
  });
  it('sem permissão mostra a mensagem do banco', () => {
    expect(mensagemErroEscrita('crm_mover_etapa', { code: '42501', message: 'permission denied' })).toBe('permission denied');
  });
  it('erro genérico cita a RPC', () => {
    expect(mensagemErroEscrita('crm_salvar_funil', { message: 'timeout' })).toBe('Não foi possível salvar no banco (crm_salvar_funil): timeout.');
  });
});

describe('argumentos (nomes p_* da migration 20261005t)', () => {
  it('negócio', () => {
    expect(argsEscrita.moverEtapa(U1, U2)).toEqual({ p_negocio: U1, p_etapa: U2 });
    expect(argsEscrita.criarNegocio(U1, U2)).toEqual({ p_pessoa: U1, p_funil: U2, p_campanha: null });
    expect(argsEscrita.transferirDono(U1, U2, 'pediu')).toEqual({ p_negocio: U1, p_dono: U2, p_motivo: 'pediu' });
    expect(argsEscrita.marcarPerdido(U1, 'pediu_sem_contato', '')).toEqual({ p_negocio: U1, p_motivo: 'pediu_sem_contato', p_nota: '' });
    expect(argsEscrita.salvarCampos(U1, { perfil_profissional: 'advogado' })).toEqual({ p_negocio: U1, p_campos: { perfil_profissional: 'advogado' } });
  });
  it('atividade e nota', () => {
    expect(argsEscrita.criarAtividade({ negocioId: null, contatoId: U1, tipo: 'ligacao', titulo: 'Ligar', venceEm: '2026-10-06T12:00:00.000Z' }))
      .toEqual({ p_negocio: null, p_pessoa: U1, p_tipo: 'ligacao', p_titulo: 'Ligar', p_vence_em: '2026-10-06T12:00:00.000Z' });
    expect(argsEscrita.adicionarNota(U1, null, 'oi')).toEqual({ p_pessoa: U1, p_negocio: null, p_texto: 'oi' });
  });
  it('painel separa perfil e widgets', () => {
    const p: PainelPessoa = { vendedorId: U1, widgets: [] };
    expect(argsEscrita.salvarPainel(p)).toEqual({ p_perfil: U1, p_widgets: [] });
  });
  it('notificações: sem ids = todas; lista vazia = nenhuma', () => {
    expect(argsEscrita.marcarNotificacoesLidas()).toEqual({ p_ids: null });
    expect(argsEscrita.marcarNotificacoesLidas([])).toEqual({ p_ids: [] });
    expect(argsEscrita.marcarNotificacoesLidas(['12'])).toEqual({ p_ids: ['12'] });
  });
  it('funil vai inteiro (o banco repete validarFunil)', () => {
    const f = { id: '', nome: 'X', etapas: [] } as unknown as Funil;
    expect(argsEscrita.salvarFunil(f)).toEqual({ p_funil: { ...f, distribuicao: null } });
    // chave `distribuicao` sempre no JSON (ausente quebrava o crm_salvar_funil antes da 20261006n)
    expect(JSON.parse(JSON.stringify(argsEscrita.salvarFunil(f))).p_funil).toHaveProperty('distribuicao', null);
    const comDist = { ...f, distribuicao: [{ vendedorId: U1, percentual: 100 }] } as Funil;
    expect(argsEscrita.salvarFunil(comDist)).toEqual({ p_funil: comDist });
    expect(argsEscrita.criarAgrupador('Pasta', null)).toEqual({ p_nome: 'Pasta', p_linha: null });
    expect(argsEscrita.criarProjeto('seminario', 'Sem 05', U1, 'sv')).toEqual({ p_tipo: 'seminario', p_nome: 'Sem 05', p_agrupador: U1, p_linha: 'sv' });
    expect(argsEscrita.excluirDashboard(U1)).toEqual({ p_dashboard: U1 });
  });
});

describe('WhatsApp (F4, migration 20261006051434)', () => {
  it('enviarMensagem: template vai como uuid ou null', () => {
    expect(argsEscrita.enviarMensagem(U1, 'oi', null)).toEqual({ p_pessoa: U1, p_texto: 'oi', p_template: null });
    expect(argsEscrita.enviarMensagem(U1, '', U2)).toEqual({ p_pessoa: U1, p_texto: '', p_template: U2 });
    expect(argsEscrita.enviarMensagem(U1, 'oi', '')).toEqual({ p_pessoa: U1, p_texto: 'oi', p_template: null });
    expect(mapResultadoComId('crm_enviar_mensagem', { ok: true, msg: 'Mensagem na fila de envio.', mensagemId: U2 }, 'mensagemId'))
      .toEqual({ ok: true, msg: 'Mensagem na fila de envio.', mensagemId: U2 });
    expect(mapResultado('crm_enviar_mensagem', { ok: false, msg: 'Envio de WhatsApp desligado.' })).toEqual({ ok: false, msg: 'Envio de WhatsApp desligado.' });
  });
  it('conversa lida e decisão da ficha', () => {
    expect(argsEscrita.marcarConversaLida(U1)).toEqual({ p_pessoa: U1 });
    expect(argsEscrita.decidirFicha(U1, false)).toEqual({ p_ficha: U1, p_aprovar: false });
    expect(mapResultado('crm_marcar_conversa_lida', { ok: true, marcadas: 3 })).toEqual({ ok: true });
  });
  it('salvarFicha manda a lista de ids (sem repetidos), sem quantidade/suprimidos, número só em dígitos', () => {
    const f = {
      objetivo: 'Recuperar', produto: 'hm' as const, filtro: 'Negócio perdido de HM · com WhatsApp', destinatarios: [U1, U2, U1],
      quantidade: 3, suprimidos: 1, templateId: U2, numeroEnvio: 'Comercial oficial (API)', agendadoPara: '2026-10-07T13:00:00.000Z',
      link: 'https://pay.hotmart.com/X?off=a&sck=hm-disparo-20261006-whatsapp-jo',
    };
    expect(argsEscrita.salvarFicha(f, true)).toEqual({
      p_ficha: {
        objetivo: 'Recuperar', produto: 'hm', filtro: 'Negócio perdido de HM · com WhatsApp', templateId: U2, numeroEnvio: '',
        agendadoPara: '2026-10-07T13:00:00.000Z', link: f.link, destinatarios: [U1, U2],
      },
      p_enviar_para_aprovacao: true,
    });
    expect(argsEscrita.salvarFicha({ ...f, id: U1, numeroEnvio: '+55 (11) 99999-0000' }, false).p_ficha)
      .toMatchObject({ id: U1, numeroEnvio: '5511999990000' });
  });
  it('resultado da ficha traz a contagem do banco', () => {
    expect(mapResultadoFicha({ ok: true, msg: 'Rascunho salvo.', fichaId: U1, codigo: 'HM-20261006-01', quantidade: 120, suprimidos: 7 }))
      .toEqual({ ok: true, msg: 'Rascunho salvo.', fichaId: U1, codigo: 'HM-20261006-01', quantidade: 120, suprimidos: 7 });
    expect(mapResultadoFicha({ ok: false, msg: 'Seu usuário não opera disparo por API.' })).toEqual({ ok: false, msg: 'Seu usuário não opera disparo por API.' });
    expect(() => mapResultadoFicha(null)).toThrow(/crm_salvar_ficha/);
  });
});

describe('filas e links (F5, migration 20261006044653)', () => {
  it('atualizarItemFila e criarLink', () => {
    expect(argsEscrita.atualizarItemFila(U1, U2, 'em_conversa')).toEqual({ p_fila: U1, p_item: U2, p_status: 'em_conversa' });
    expect(argsEscrita.criarLink(U1, 'hm', 'disparo', 'whatsapp')).toEqual({ p_vendedor: U1, p_produto: 'hm', p_acao: 'disparo', p_canal: 'whatsapp' });
  });
  it('resultado do link traz url e sck só com ok', () => {
    expect(mapResultadoLink({ ok: true, linkId: U1, sck: 'hm-x', url: 'https://pay.hotmart.com?off=a&sck=hm-x' }))
      .toEqual({ ok: true, linkId: U1, sck: 'hm-x', url: 'https://pay.hotmart.com?off=a&sck=hm-x' });
    expect(mapResultadoLink({ ok: false, msg: 'Este link já existe.', url: 'x' })).toEqual({ ok: false, msg: 'Este link já existe.' });
  });
});

describe('Hotmart e MCP (F3 20261006043612, F7 20261006050132)', () => {
  it('argumentos conferidos em pg_proc', () => {
    expect(argsEscrita.reprocessarHotmart('ev:1')).toEqual({ p_chave: 'ev:1' });
    expect(argsEscrita.criarTokenMcp('  Notebook ', ['ler', 'operar'], 30)).toEqual({ p_nome: 'Notebook', p_escopos: ['ler', 'operar'], p_dias: 30 });
    expect(argsEscrita.revogarTokenMcp(U1)).toEqual({ p_id: U1 });
  });
  it('token criado volta inteiro, uma vez', () => {
    const tok = `gpc_${'a'.repeat(64)}`;
    const r = mapResultadoTokenMcp({ ok: true, id: U1, token: tok, prefixo: tok.slice(0, 12), escopos: ['ler'], expiraEm: '2027-01-04T10:00:00+00:00', msg: 'Copie agora: o token não aparece de novo.' });
    expect(r).toMatchObject({ ok: true, id: U1, token: tok, escopos: ['ler'] });
  });
  it('MCP desligado vem como ok:false com a mensagem do banco', () => {
    expect(mapResultadoTokenMcp({ ok: false, msg: 'MCP do Comercial desligado.' })).toEqual({ ok: false, msg: 'MCP do Comercial desligado.' });
  });
  it('ok sem token é formato inesperado', () => {
    expect(() => mapResultadoTokenMcp({ ok: true, id: U1 })).toThrow(FormatoInesperado);
  });
});
