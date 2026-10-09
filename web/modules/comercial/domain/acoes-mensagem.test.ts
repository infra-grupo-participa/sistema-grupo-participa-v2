import { describe, expect, it } from 'vitest';
import { acoesDaMensagem, jaSaiu, MOTIVO_OFICIAL, trechoCitado } from './acoes-mensagem';
import type { Mensagem } from './types';

const AGORA = new Date('2026-10-09T15:00:00Z');
const m = (p: Partial<Mensagem> = {}): Mensagem => ({
  id: 'm1', contatoId: 'c1', canal: 'whatsapp', direcao: 'saida', texto: 'Oi, Ana', em: '2026-10-09T14:55:00Z', status: 'enviada',
  autorId: 'jusy', templateId: null, tipo: 'texto', ...p,
});
const vendedora = { vendedorId: 'jusy', papel: 'vendedor' as const };
const ctx = (p: Partial<Parameters<typeof acoesDaMensagem>[1]> = {}) => ({ provedor: 'evolution' as const, sessao: vendedora, podeEscrever: true, agora: AGORA, ...p });

describe('acoesDaMensagem', () => {
  it('QR, enviada há 5 min pela própria pessoa: tudo liberado', () => {
    const a = acoesDaMensagem(m(), ctx());
    expect(Object.values(a).every((x) => x.ok)).toBe(true);
  });
  it('oficial: editar e apagar desativados com o motivo da API Cloud; responder só no QR', () => {
    const a = acoesDaMensagem(m(), ctx({ provedor: 'infobip' }));
    expect(a.editar).toEqual({ ok: false, motivo: MOTIVO_OFICIAL });
    expect(a.apagar).toEqual({ ok: false, motivo: MOTIVO_OFICIAL });
    expect(a.responder.ok).toBe(false);
    expect(a.copiar.ok).toBe(true);
  });
  it('limites do WhatsApp: editar até 15 min, apagar até 48 h', () => {
    const vinte = acoesDaMensagem(m({ em: '2026-10-09T14:40:00Z' }), ctx());
    expect(vinte.editar.ok).toBe(false);
    expect(vinte.apagar.ok).toBe(true);
    const tresDias = acoesDaMensagem(m({ em: '2026-10-06T14:00:00Z' }), ctx());
    expect(tresDias.apagar.ok).toBe(false);
  });
  it('mensagem de outra pessoa: só o gestor mexe; celular/Clint também só o gestor', () => {
    expect(acoesDaMensagem(m({ autorId: 'outro' }), ctx()).editar.ok).toBe(false);
    expect(acoesDaMensagem(m({ autorId: 'outro' }), ctx({ sessao: { vendedorId: 'g', papel: 'gestor' } })).editar.ok).toBe(true);
    expect(acoesDaMensagem(m({ autorId: null, externa: true }), ctx()).apagar.ok).toBe(false);
    expect(acoesDaMensagem(m(), ctx({ sessao: { vendedorId: 'v', papel: 'leitor' }, podeEscrever: false })).editar.ok).toBe(false);
  });
  it('recebida: só copiar e responder; na fila/agendada ainda não saiu', () => {
    const r = acoesDaMensagem(m({ direcao: 'entrada', status: null, autorId: null }), ctx());
    expect(r.responder.ok).toBe(true);
    expect(r.editar.ok).toBe(false);
    expect(acoesDaMensagem(m({ status: null, envio: 'na_fila' }), ctx()).editar.motivo).toMatch(/ainda não saiu/);
  });
  it('apagada: nada além do aviso; imagem não edita', () => {
    const a = acoesDaMensagem(m({ apagadaEm: AGORA.toISOString() }), ctx());
    expect(a.copiar.ok || a.responder.ok || a.editar.ok || a.apagar.ok).toBe(false);
    expect(acoesDaMensagem(m({ tipo: 'imagem' }), ctx()).editar.ok).toBe(false);
  });
  it('jaSaiu e trechoCitado', () => {
    expect(jaSaiu(m({ status: 'lida' }))).toBe(true);
    expect(jaSaiu(m({ status: null, envio: 'enviando' }))).toBe(false);
    expect(trechoCitado('a  b\nc')).toBe('a b c');
    expect(trechoCitado('x'.repeat(100), 10)).toHaveLength(10);
    expect(trechoCitado('')).toBe('Mensagem');
  });
});
