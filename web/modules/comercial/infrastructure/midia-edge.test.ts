// Regras puras da Edge crm-whatsapp-enviar (download da mídia recebida e envio de anexo). Sem rede.
import { describe, expect, it } from 'vitest';
import {
  caminhoRecebido, extensaoDoMime, mimeBase, mimeSeguro, nomeDoContentDisposition, pedidoMidiaInfobip, saidaComArquivo, urlDownloadInfobip,
} from '../../../../infra/supabase/functions/crm-whatsapp-enviar/midia';

const BASE = 'https://8k6q23.api-us.infobip.com';

describe('urlDownloadInfobip', () => {
  it('a chave só vai para o host configurado', () => {
    expect(urlDownloadInfobip('https://8k6q23.api-us.infobip.com/whatsapp/1/senders/5521987545211/media/abc-1', BASE))
      .toBe(`${BASE}/whatsapp/1/senders/5521987545211/media/abc-1`);
    // outro subdomínio da Infobip: reaproveita só o caminho, com o host configurado
    expect(urlDownloadInfobip('https://api.infobip.com/whatsapp/1/senders/5521987545211/media/abc', BASE))
      .toBe(`${BASE}/whatsapp/1/senders/5521987545211/media/abc`);
  });
  it('recusa host fora da Infobip, http, caminho fora de /whatsapp e ..', () => {
    expect(urlDownloadInfobip('https://evil.com/whatsapp/1/senders/1/media/a', BASE)).toBeNull();
    expect(urlDownloadInfobip('https://infobip.com.evil.com/whatsapp/1/media/a', BASE)).toBeNull();
    expect(urlDownloadInfobip('http://x.api.infobip.com/whatsapp/1/media/a', BASE)).toBeNull();
    expect(urlDownloadInfobip('https://x.api.infobip.com/sms/1/logs', BASE)).toBeNull();
    expect(urlDownloadInfobip('https://x.api.infobip.com/whatsapp/../sms/1', BASE)).toBeNull();
    expect(urlDownloadInfobip(null, BASE)).toBeNull();
  });
});

describe('mime e extensão', () => {
  it('voz do WhatsApp vira .ogg', () => {
    expect(mimeBase('audio/ogg; codecs=opus')).toBe('audio/ogg');
    expect(extensaoDoMime('audio/ogg; codecs=opus')).toBe('ogg');
    expect(extensaoDoMime('application/x-desconhecido')).toBe('bin');
  });
  it('tipo perigoso é servido como download', () => {
    expect(mimeSeguro('text/html')).toBe('application/octet-stream');
    expect(mimeSeguro('image/svg+xml')).toBe('application/octet-stream');
    expect(mimeSeguro('image/jpeg')).toBe('image/jpeg');
  });
  it('caminho <conversa>/<mensagem>.<ext>', () => {
    expect(caminhoRecebido('c1', 'm1', 'application/pdf')).toBe('c1/m1.pdf');
  });
});

describe('nomeDoContentDisposition', () => {
  it('filename* e filename, sem barra', () => {
    expect(nomeDoContentDisposition("attachment; filename*=UTF-8''contrato%20social.pdf")).toBe('contrato social.pdf');
    expect(nomeDoContentDisposition('attachment; filename="a/b.pdf"')).toBe('a_b.pdf');
    expect(nomeDoContentDisposition(null)).toBeNull();
  });
});

describe('pedidoMidiaInfobip', () => {
  const base = { de: '5521987545211', para: '5521999990001', mensagem_id: 'm1' };
  it('imagem com legenda', () => {
    expect(pedidoMidiaInfobip({ ...base, tipo: 'imagem', legenda: 'Segue', midia_nome: null }, 'https://s/x')).toEqual({
      caminho: '/whatsapp/1/message/image',
      corpo: { from: '5521987545211', to: '5521999990001', messageId: 'm1', callbackData: 'm1', content: { mediaUrl: 'https://s/x', caption: 'Segue' } },
    });
  });
  it('PDF sem legenda leva o nome', () => {
    const p = pedidoMidiaInfobip({ ...base, tipo: 'documento', legenda: null, midia_nome: 'Proposta.pdf' }, 'https://s/y');
    expect(p.caminho).toBe('/whatsapp/1/message/document');
    expect(p.corpo.content).toEqual({ mediaUrl: 'https://s/y', filename: 'Proposta.pdf' });
  });
  it('áudio (20261007s) vai para /message/audio, sem legenda', () => {
    const p = pedidoMidiaInfobip({ ...base, tipo: 'audio', legenda: 'ignorada', midia_nome: null }, 'https://s/z.ogg');
    expect(p).toEqual({
      caminho: '/whatsapp/1/message/audio',
      corpo: { from: '5521987545211', to: '5521999990001', messageId: 'm1', callbackData: 'm1', content: { mediaUrl: 'https://s/z.ogg' } },
    });
  });
  it('só imagem, documento e áudio levam arquivo na saída', () => {
    expect(['imagem', 'documento', 'audio', 'texto', 'template', 'video'].map(saidaComArquivo)).toEqual([true, true, true, false, false, false]);
  });
});
