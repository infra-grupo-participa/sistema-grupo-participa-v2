import { describe, expect, it } from 'vitest';
import {
  baseEvolution, bloqueioEnvio, canalDeResposta, corpoCriarInstancia, corpoWebhookEvolution, estadoDaResposta, numeroDaInstancia,
  qrDaResposta, rotuloCanal, semJanela, urlWebhookEvolution, validarNomeCanal, type CanalWhatsapp,
} from './canais-whatsapp';

const canal = (p: Partial<CanalWhatsapp>): CanalWhatsapp => ({
  id: 'c1', provedor: 'evolution', nome: 'Clint', final: '4276', status: 'conectado', statusEm: null, statusMotivo: null,
  conectadoEm: null, recebe: true, envia: true, donoId: null, padrao: false, ...p,
});
const oficial = canal({ id: 'of', provedor: 'infobip', nome: 'Comercial oficial', final: '5211', padrao: true });
const qr = canal({ id: 'qr' });
const painel = { evolutionLigado: true, envioLigado: true };

describe('rótulos', () => {
  it('nome + 4 finais', () => {
    expect(rotuloCanal(qr)).toBe('Clint · 4276');
    expect(rotuloCanal(canal({ final: null }))).toBe('Clint');
    expect(rotuloCanal(null)).toBe('Número removido');
  });
});

describe('regras de envio', () => {
  it('janela de 24 h só no oficial', () => {
    expect(semJanela(qr)).toBe(true);
    expect(semJanela(oficial)).toBe(false);
  });
  it('bloqueios do número por QR', () => {
    expect(bloqueioEnvio(qr, painel)).toBeNull();
    expect(bloqueioEnvio(oficial, { evolutionLigado: false, envioLigado: true })).toBeNull();
    expect(bloqueioEnvio(qr, { evolutionLigado: false, envioLigado: true })).toMatch(/desligado/);
    expect(bloqueioEnvio(canal({ status: 'aguardando_qr' }), painel)).toMatch(/desconectado/);
    expect(bloqueioEnvio(canal({ envia: false }), painel)).toMatch(/não envia/);
  });
  it('responde pelo escolhido, senão pelo da conversa, senão pelo oficial', () => {
    expect(canalDeResposta('qr', 'of', [oficial, qr])?.id).toBe('qr');
    expect(canalDeResposta(null, 'qr', [oficial, qr])?.id).toBe('qr');
    expect(canalDeResposta(null, null, [oficial, qr])?.id).toBe('of');
    expect(canalDeResposta('sumiu', null, [oficial, qr])?.id).toBe('of');
    expect(canalDeResposta(null, null, [])).toBeNull();
  });
  it('nome do número', () => {
    expect(validarNomeCanal(' ')).toMatch(/nome/);
    expect(validarNomeCanal('Clint 4276')).toBeNull();
    expect(validarNomeCanal('x'.repeat(81))).toMatch(/longo/);
  });
});

describe('Evolution (servidor)', () => {
  it('webhook por instância na Edge, chave no header, 3 eventos, base64', () => {
    expect(urlWebhookEvolution('https://abc.supabase.co/', 'crm-clint-ab12cd'))
      .toBe('https://abc.supabase.co/functions/v1/crm-evolution-webhook?i=crm-clint-ab12cd');
    const c = corpoWebhookEvolution('https://x', 'k'.repeat(64));
    expect(c.webhook).toMatchObject({ enabled: true, byEvents: false, base64: true, headers: { 'x-crm-chave': 'k'.repeat(64) } });
    expect(c.webhook.events).toEqual(['MESSAGES_UPSERT', 'MESSAGES_EDITED', 'MESSAGES_DELETE', 'CONNECTION_UPDATE', 'QRCODE_UPDATED']);
  });
  it('instância nasce sem grupos e sem histórico', () => {
    expect(corpoCriarInstancia('crm-a-b1c2d3')).toMatchObject({ instanceName: 'crm-a-b1c2d3', integration: 'WHATSAPP-BAILEYS', qrcode: true, groupsIgnore: true, syncFullHistory: false });
  });
  it('base só https sem caminho', () => {
    expect(baseEvolution('https://wa.grupoparticipa.app.br/')).toBe('https://wa.grupoparticipa.app.br');
    expect(baseEvolution('http://wa.grupoparticipa.app.br')).toBeNull();
    expect(baseEvolution('https://wa.grupoparticipa.app.br/api')).toBeNull();
    expect(baseEvolution('')).toBeNull();
  });
  it('QR das respostas de connect e create', () => {
    const png = 'data:image/png;base64,iVBORw0KGgo=';
    expect(qrDaResposta({ pairingCode: null, code: '2@abc', base64: png, count: 1 })).toBe(png);
    expect(qrDaResposta({ instance: {}, qrcode: { base64: png } })).toBe(png);
    expect(qrDaResposta({ base64: 'data:text/html;base64,AAAA' })).toBeNull();
    expect(qrDaResposta(null)).toBeNull();
  });
  it('estado e número da instância', () => {
    expect(estadoDaResposta({ instance: { instanceName: 'crm-x', state: 'open' } })).toBe('open');
    expect(estadoDaResposta({ instance: { state: 'refused' } })).toBeNull();
    expect(numeroDaInstancia([{ name: 'crm-outra-aaaaaa', ownerJid: '5521900000002@s.whatsapp.net' },
      { name: 'crm-x-123abc', ownerJid: '5521900000001@s.whatsapp.net' }], 'crm-x-123abc')).toBe('5521900000001');
    expect(numeroDaInstancia([{ name: 'crm-x-123abc', ownerJid: null }], 'crm-x-123abc')).toBeNull();
  });
});
