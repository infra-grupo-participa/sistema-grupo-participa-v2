// Regras puras do envio pela Evolution (Edge crm-evolution-enviar). Telefones fictícios. Sem rede.
import { describe, expect, it } from 'vitest';
import {
  baseEvolution, classificar, erroDaResposta, idDaResposta, jidDaBusca, jidEvolution, pausaMs, pedidoAcao, pedidoEvolution, quotedEvolution,
  type AcaoEvolution, type FilaEvolution,
} from '../../../../infra/supabase/functions/crm-evolution-enviar/evolution';

const base: FilaEvolution = {
  mensagem_id: 'm1', instancia: 'crm-clint-ab12cd', para: '5521900000001', tipo: 'texto', texto: 'Olá',
  midia_caminho: null, midia_nome: null, midia_mime: null, legenda: null,
};

describe('baseEvolution', () => {
  it('só https sem caminho', () => {
    expect(baseEvolution('https://wa.grupoparticipa.app.br')).toBe('https://wa.grupoparticipa.app.br');
    expect(baseEvolution('https://wa.grupoparticipa.app.br/')).toBe('https://wa.grupoparticipa.app.br');
    expect(baseEvolution('http://wa.grupoparticipa.app.br')).toBeNull();
    expect(baseEvolution('https://wa.grupoparticipa.app.br/x?y=1')).toBeNull();
    expect(baseEvolution('https://u:p@wa.grupoparticipa.app.br')).toBeNull();
    expect(baseEvolution(null)).toBeNull();
  });
});

describe('pedidoEvolution', () => {
  it('texto', () => {
    expect(pedidoEvolution(base, null)).toEqual({ caminho: '/message/sendText/crm-clint-ab12cd', corpo: { number: '5521900000001', text: 'Olá' } });
  });
  it('imagem com legenda e documento com nome', () => {
    expect(pedidoEvolution({ ...base, tipo: 'imagem', midia_mime: 'image/png', legenda: 'veja' }, 'https://x/a.png')).toEqual({
      caminho: '/message/sendMedia/crm-clint-ab12cd',
      corpo: { number: '5521900000001', mediatype: 'image', media: 'https://x/a.png', mimetype: 'image/png', caption: 'veja' },
    });
    expect(pedidoEvolution({ ...base, tipo: 'documento', midia_mime: 'application/pdf', midia_nome: 'proposta.pdf' }, 'https://x/a.pdf')?.corpo)
      .toMatchObject({ mediatype: 'document', fileName: 'proposta.pdf' });
  });
  it('áudio vai como áudio de voz', () => {
    expect(pedidoEvolution({ ...base, tipo: 'audio' }, 'https://x/a.ogg')).toEqual({
      caminho: '/message/sendWhatsAppAudio/crm-clint-ab12cd', corpo: { number: '5521900000001', audio: 'https://x/a.ogg' },
    });
  });
  it('recusa sem arquivo, instância fora do padrão, telefone inválido ou tipo sem suporte', () => {
    expect(pedidoEvolution({ ...base, tipo: 'imagem' }, null)).toBeNull();
    expect(pedidoEvolution({ ...base, instancia: '../admin' }, null)).toBeNull();
    expect(pedidoEvolution({ ...base, para: '123' }, null)).toBeNull();
    expect(pedidoEvolution({ ...base, tipo: 'template' }, null)).toBeNull();
  });
});

describe('resposta da Evolution', () => {
  it('id da mensagem enviada', () => {
    expect(idDaResposta({ key: { id: '3EB0ABCDEF', fromMe: true } })).toBe('3EB0ABCDEF');
    expect(idDaResposta({ key: { id: '<script>' } })).toBeNull();
    expect(idDaResposta(null)).toBeNull();
  });
  it('número sem WhatsApp e erro sem telefone no texto', () => {
    expect(erroDaResposta(400, { status: 400, response: { message: [{ exists: false, jid: 'x', number: '5521900000001' }] } }))
      .toBe('Este número não tem WhatsApp.');
    expect(erroDaResposta(400, { response: { message: ['Falhou para 5521900000001'] } })).toBe('Evolution HTTP 400: Falhou para ***');
    expect(erroDaResposta(401, {})).toMatch(/chave/);
    expect(erroDaResposta(404, {})).toMatch(/Instância/);
  });
  it('classificação: nunca reenvia o que pode ter saído', () => {
    expect(classificar(201)).toBe('ok');
    expect(classificar(429)).toBe('reenfileirar');
    expect(classificar(500)).toBe('incerta');
    expect(classificar(0)).toBe('incerta');
    expect(classificar(400)).toBe('falhou');
  });
  it('pausa entre mensagens do mesmo número: 1,2 s a 2,4 s', () => {
    expect(pausaMs(0)).toBe(1200);
    expect(pausaMs(1)).toBe(2400);
    expect(pausaMs(5)).toBe(2400);
  });
});

// ── Responder citando, editar e apagar (migration 20261009153515) ──

describe('responder citando', () => {
  it('sendText leva o quoted com a key e o texto da citada', () => {
    const p = pedidoEvolution(base, null, { key_id: 'ABCD1234', from_me: false, texto: 'pergunta', remote_jid: '552190000001@s.whatsapp.net' });
    expect(p?.corpo.quoted).toEqual({ key: { id: 'ABCD1234', fromMe: false, remoteJid: '552190000001@s.whatsapp.net' }, message: { conversation: 'pergunta' } });
  });
  it('sem JID real, usa o telefone da conversa; key inválida não cita', () => {
    expect(quotedEvolution({ key_id: 'ABCD1234', from_me: true, texto: null }, '5521900000001')).toMatchObject({ key: { remoteJid: '5521900000001@s.whatsapp.net', fromMe: true } });
    expect(quotedEvolution({ key_id: 'ABCD1234', from_me: false, texto: null }, '5531990000001')).toMatchObject({ key: { remoteJid: '553190000001@s.whatsapp.net' } });
    expect(quotedEvolution({ key_id: 'x', from_me: true, texto: 'a' }, '5521900000001')).toBeNull();
    expect(pedidoEvolution(base, null, null)?.corpo.quoted).toBeUndefined();
  });
});

describe('editar e apagar para todos', () => {
  const acao: AcaoEvolution = { acao_id: 'a1', tipo: 'editar', instancia: 'crm-clint-ab12cd', telefone: '5521900000001', key_id: 'ABCD1234', texto: ' novo ' };
  it('editar: POST /chat/updateMessage com number = JID real', () => {
    expect(pedidoAcao(acao, '552190000001@s.whatsapp.net')).toEqual({
      metodo: 'POST', caminho: '/chat/updateMessage/crm-clint-ab12cd',
      corpo: { number: '552190000001', text: 'novo', key: { id: 'ABCD1234', remoteJid: '552190000001@s.whatsapp.net', fromMe: true } },
    });
  });
  it('apagar: DELETE /chat/deleteMessageForEveryone (fromMe)', () => {
    expect(pedidoAcao({ ...acao, tipo: 'apagar', texto: null }, null)).toEqual({
      metodo: 'DELETE', caminho: '/chat/deleteMessageForEveryone/crm-clint-ab12cd',
      corpo: { id: 'ABCD1234', remoteJid: '5521900000001@s.whatsapp.net', fromMe: true },
    });
  });
  it('recusa formato fora do esperado', () => {
    expect(pedidoAcao({ ...acao, instancia: 'outra' }, null)).toBeNull();
    expect(pedidoAcao({ ...acao, texto: '  ' }, null)).toBeNull();
    expect(pedidoAcao({ ...acao, tipo: 'reagir' }, null)).toBeNull();
  });
  it('JID real da busca (v2 paginada ou lista)', () => {
    const rec = { key: { id: 'ABCD1234', remoteJid: '552190000001@s.whatsapp.net' } };
    expect(jidDaBusca({ messages: { total: 1, records: [rec] } }, 'ABCD1234')).toBe('552190000001@s.whatsapp.net');
    expect(jidDaBusca([rec], 'ABCD1234')).toBe('552190000001@s.whatsapp.net');
    expect(jidDaBusca([rec], 'OUTRA123')).toBeNull();
    expect(jidDaBusca({ messages: { records: [{ key: { id: 'ABCD1234', remoteJid: '1203@g.us' } }] } }, 'ABCD1234')).toBeNull();
  });
});

describe('jidEvolution (espelho do createJid da Evolution)', () => {
  it('DDD >= 31 com celular 7-9 perde o 9; DDD < 31 mantém', () => {
    expect(jidEvolution('5531990000001')).toBe('553190000001@s.whatsapp.net');
    expect(jidEvolution('5521990000001')).toBe('5521990000001@s.whatsapp.net');
    expect(jidEvolution('5531960000001')).toBe('5531960000001@s.whatsapp.net');
    expect(jidEvolution('14155550100')).toBe('14155550100@s.whatsapp.net');
  });
});
