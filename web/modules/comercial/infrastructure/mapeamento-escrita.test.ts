// Payloads no formato exato que as RPCs de escrita da migration 20261005t devolvem (crm.res: {ok, msg?, …ids}).
import { describe, expect, it } from 'vitest';
import {
  argsEscrita, mapResultado, mapResultadoComId, mapResultadoNegocio, mapResultadoProjeto, mensagemErroEscrita, semTabela,
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

describe('erro de chamada e métodos sem tabela', () => {
  it('função ausente explica que a F2 não foi aplicada', () => {
    expect(mensagemErroEscrita('crm_mover_etapa', { code: 'PGRST202', message: 'Could not find' })).toMatch(/crm_mover_etapa.*Fase 2/);
  });
  it('sem permissão mostra a mensagem do banco', () => {
    expect(mensagemErroEscrita('crm_mover_etapa', { code: '42501', message: 'permission denied' })).toBe('permission denied');
  });
  it('erro genérico cita a RPC', () => {
    expect(mensagemErroEscrita('crm_salvar_funil', { message: 'timeout' })).toBe('Não foi possível salvar no banco (crm_salvar_funil): timeout.');
  });
  it('método sem tabela não finge que gravou', () => {
    expect(semTabela('Ficha de disparo', 'Fase 4')).toEqual({ ok: false, msg: 'Ficha de disparo ainda não está no banco (entra na Fase 4 do CRM).' });
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
    expect(argsEscrita.salvarFunil(f)).toEqual({ p_funil: f });
    expect(argsEscrita.criarAgrupador('Pasta', null)).toEqual({ p_nome: 'Pasta', p_linha: null });
    expect(argsEscrita.criarProjeto('seminario', 'Sem 05', U1, 'sv')).toEqual({ p_tipo: 'seminario', p_nome: 'Sem 05', p_agrupador: U1, p_linha: 'sv' });
    expect(argsEscrita.excluirDashboard(U1)).toEqual({ p_dashboard: U1 });
  });
});
