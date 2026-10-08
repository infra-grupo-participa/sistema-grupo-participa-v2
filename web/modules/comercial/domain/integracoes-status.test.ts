import { describe, expect, it } from 'vitest';
import {
  haQuanto, JANELA_EVENTO_MIN, rotuloJanela, situacaoIntegracao, type FatosIntegracao, type NumeroWhatsappVivo,
} from './integracoes-status';

const agora = new Date('2026-10-08T18:00:00Z');
const minAtras = (m: number) => new Date(agora.getTime() - m * 60_000).toISOString();
const f = (p: Partial<FatosIntegracao> = {}): FatosIntegracao => ({
  chave: 'hotmart', ligada: true, configurada: true, ultimoEventoEm: minAtras(10), eventos24h: 3, erroRecente: null, ...p,
});
const num = (p: Partial<NumeroWhatsappVivo> = {}): NumeroWhatsappVivo => ({
  id: 'n1', nome: 'Comercial', provedor: 'infobip', status: 'conectado', statusEm: null, statusMotivo: null, final: '5211',
  ativo: true, principal: true, recebe: true, envia: true, ultimaMensagemEm: minAtras(5), mensagens24h: 2, falhas24h: 0, ...p,
});

describe('situacaoIntegracao', () => {
  it('sem linha do banco = em breve (Manychat, Instagram)', () => {
    expect(situacaoIntegracao('manychat', undefined, agora).estado).toBe('em_breve');
    expect(situacaoIntegracao('hotmart', undefined, agora).estado).toBe('em_breve');
  });
  it('chave desligada vence tudo', () => {
    expect(situacaoIntegracao('hotmart', f({ ligada: false, configurada: false }), agora).estado).toBe('desligada');
  });
  it('ligada sem credencial = não configurada', () => {
    expect(situacaoIntegracao('hotmart', f({ configurada: false }), agora).estado).toBe('nao_configurada');
  });
  it('evento dentro da janela = conectada; fora = ligada sem eventos', () => {
    expect(situacaoIntegracao('hotmart', f({ ultimoEventoEm: minAtras(23 * 60) }), agora)).toEqual({ estado: 'conectada', motivo: null });
    const s = situacaoIntegracao('hotmart', f({ ultimoEventoEm: minAtras(25 * 60) }), agora);
    expect(s.estado).toBe('sem_eventos');
    expect(s.motivo).toMatch(/24 h/);
  });
  it('janela por fonte: ActiveCampaign 6 h, Respondi 48 h', () => {
    expect(situacaoIntegracao('activecampaign', f({ ultimoEventoEm: minAtras(7 * 60) }), agora).estado).toBe('sem_eventos');
    expect(situacaoIntegracao('respondi', f({ ultimoEventoEm: minAtras(30 * 60) }), agora).estado).toBe('conectada');
  });
  it('nunca recebeu evento = ligada sem eventos (Unnichat hoje)', () => {
    const s = situacaoIntegracao('unnichat', f({ ultimoEventoEm: null, eventos24h: 0 }), agora);
    expect(s).toEqual({ estado: 'sem_eventos', motivo: 'Nenhum evento recebido ainda.' });
  });
  it('data inválida não vira conectada', () => {
    expect(situacaoIntegracao('slack', f({ ultimoEventoEm: 'lixo' }), agora).estado).toBe('sem_eventos');
  });
  it('WhatsApp precisa de número conectado do mesmo provedor', () => {
    const fx = f({ chave: 'infobip' });
    expect(situacaoIntegracao('infobip', fx, agora, [num()]).estado).toBe('conectada');
    expect(situacaoIntegracao('infobip', fx, agora, [num({ status: 'desconectado' })]).motivo).toBe('Nenhum número conectado.');
    expect(situacaoIntegracao('infobip', fx, agora, [num({ ativo: false })]).estado).toBe('sem_eventos');
    expect(situacaoIntegracao('evolution', f({ chave: 'evolution' }), agora, [num()]).estado).toBe('sem_eventos');
    expect(situacaoIntegracao('infobip', fx, agora, []).estado).toBe('sem_eventos');
  });
  it('erro recente não muda o selo (aparece à parte)', () => {
    expect(situacaoIntegracao('hotmart', f({ erroRecente: { texto: 'x', em: null } }), agora).estado).toBe('conectada');
  });
  it('toda janela é positiva', () => {
    expect(Object.values(JANELA_EVENTO_MIN).every((m) => m > 0)).toBe(true);
  });
});

describe('textos', () => {
  it('rotuloJanela', () => {
    expect(rotuloJanela(24 * 60)).toBe('24 h');
    expect(rotuloJanela(48 * 60)).toBe('2 dias');
    expect(rotuloJanela(6 * 60)).toBe('6 h');
    expect(rotuloJanela(45)).toBe('45 min');
  });
  it('haQuanto', () => {
    expect(haQuanto(null, agora)).toBe('nunca');
    expect(haQuanto('lixo', agora)).toBe('nunca');
    expect(haQuanto(new Date(agora.getTime() + 60_000).toISOString(), agora)).toBe('agora');
    expect(haQuanto(new Date(agora.getTime() - 20_000).toISOString(), agora)).toBe('há 20 s');
    expect(haQuanto(minAtras(12), agora)).toBe('há 12 min');
    expect(haQuanto(minAtras(180), agora)).toBe('há 3 h');
    expect(haQuanto(minAtras(25 * 60), agora)).toBe('há 1 dia');
    expect(haQuanto(minAtras(3 * 24 * 60), agora)).toBe('há 3 dias');
  });
});
