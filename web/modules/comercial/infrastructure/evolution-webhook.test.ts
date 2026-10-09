// Normalização do webhook da Evolution API v2 (Edge crm-evolution-webhook). Telefones fictícios. Sem rede.
import { describe, expect, it } from 'vitest';
import {
  bytesDoBase64, caminhoArquivo, celularBr, conteudo, desembrulhar, mimeSeguro, nomeEvento, normalizarConexao,
  normalizarMensagem, normalizarQr, normalizarWebhook, telefoneDoJid,
} from '../../../../infra/supabase/functions/crm-evolution-webhook/normalizar';

const TEL = '5521900000001';
const msg = (extra: Record<string, unknown> = {}, key: Record<string, unknown> = {}) => ({
  key: { remoteJid: `${TEL}@s.whatsapp.net`, fromMe: false, id: '3EB0A1B2C3D4E5F6', ...key },
  pushName: 'Lead Teste',
  message: { conversation: 'Oi, quero saber do curso' },
  messageType: 'conversation',
  messageTimestamp: 1760000000,
  ...extra,
});

describe('nomeEvento', () => {
  it('aceita as três grafias da Evolution', () => {
    expect(nomeEvento('messages.upsert')).toBe('messages.upsert');
    expect(nomeEvento('MESSAGES_UPSERT')).toBe('messages.upsert');
    expect(nomeEvento('messages-upsert')).toBe('messages.upsert');
  });
});

describe('telefoneDoJid', () => {
  it('conversa individual vira só dígitos', () => {
    expect(telefoneDoJid({ remoteJid: `${TEL}@s.whatsapp.net` })).toEqual({ telefone: TEL, motivo: null });
    expect(telefoneDoJid({ remoteJid: `${TEL}:12@s.whatsapp.net` }).telefone).toBe(TEL);
  });
  it('ignora grupo, status, lista de transmissão e canal', () => {
    expect(telefoneDoJid({ remoteJid: '120363000000000000@g.us' }).motivo).toBe('grupo');
    expect(telefoneDoJid({ remoteJid: 'status@broadcast' }).motivo).toBe('broadcast');
    expect(telefoneDoJid({ remoteJid: '123@broadcast' }).motivo).toBe('broadcast');
    expect(telefoneDoJid({ remoteJid: '120363@newsletter' }).motivo).toBe('canal');
  });
  it('@lid usa o telefone alternativo; sem ele, ignora', () => {
    expect(telefoneDoJid({ remoteJid: '1234567890@lid', remoteJidAlt: `${TEL}@s.whatsapp.net` }).telefone).toBe(TEL);
    expect(telefoneDoJid({ remoteJid: '1234567890@lid', senderPn: `${TEL}@s.whatsapp.net` }).telefone).toBe(TEL);
    expect(telefoneDoJid({ remoteJid: '1234567890@lid' })).toEqual({ telefone: null, motivo: 'lid_sem_telefone' });
  });
});

describe('celularBr', () => {
  it('JID antigo de celular sem o 9 ganha o 9', () => expect(celularBr('552190000001')).toBe('5521990000001'));
  it('fixo, 13 dígitos e estrangeiro ficam iguais', () => {
    expect(celularBr('552133334444')).toBe('552133334444');
    expect(celularBr(TEL)).toBe(TEL);
    expect(celularBr('14155550100')).toBe('14155550100');
  });
});

describe('conteudo', () => {
  it('texto simples e estendido', () => {
    expect(conteudo({ conversation: 'oi' })).toMatchObject({ tipo: 'texto', texto: 'oi' });
    expect(conteudo({ extendedTextMessage: { text: 'link' } })).toMatchObject({ tipo: 'texto', texto: 'link' });
  });
  it('mídias com legenda, mime e nome', () => {
    expect(conteudo({ imageMessage: { caption: 'foto', mimetype: 'image/jpeg' } })).toMatchObject({ tipo: 'imagem', texto: 'foto', mime: 'image/jpeg', midia: true });
    expect(conteudo({ audioMessage: { mimetype: 'audio/ogg; codecs=opus', ptt: true } })).toMatchObject({ tipo: 'audio', midia: true });
    expect(conteudo({ documentMessage: { fileName: 'proposta.pdf', mimetype: 'application/pdf' } })).toMatchObject({ tipo: 'documento', arquivo: 'proposta.pdf' });
    expect(conteudo({ videoMessage: { mimetype: 'video/mp4' } })).toMatchObject({ tipo: 'video' });
  });
  it('figurinha, localização, contato e botão', () => {
    expect(conteudo({ stickerMessage: {} })).toMatchObject({ tipo: 'figurinha', midia: false });
    expect(conteudo({ locationMessage: {} })).toMatchObject({ tipo: 'localizacao' });
    expect(conteudo({ contactMessage: {} })).toMatchObject({ tipo: 'contato' });
    expect(conteudo({ buttonsResponseMessage: { selectedDisplayText: 'Quero' } })).toMatchObject({ tipo: 'botao', texto: 'Quero' });
  });
  it('reação, apagar/editar e voto não viram mensagem', () => {
    expect(conteudo({ reactionMessage: { text: '👍' } })).toEqual({ ignorar: 'reacao' });
    expect(conteudo({ protocolMessage: { type: 0 } })).toEqual({ ignorar: 'protocolo' });
    expect(conteudo({ editedMessage: {} })).toEqual({ ignorar: 'protocolo' });
  });
  it('desconhecido vira "outro" (não some)', () => expect(conteudo({ algoNovo: {} })).toMatchObject({ tipo: 'outro' }));
});

describe('desembrulhar', () => {
  it('efêmera e visualização única chegam ao conteúdo', () => {
    expect(desembrulhar({ ephemeralMessage: { message: { conversation: 'x' } } })).toEqual({ conversation: 'x' });
    expect(desembrulhar({ viewOnceMessageV2: { message: { imageMessage: { mimetype: 'image/jpeg' } } }, base64: 'QUJD' }))
      .toEqual({ imageMessage: { mimetype: 'image/jpeg' }, base64: 'QUJD' });
    expect(desembrulhar({ documentWithCaptionMessage: { message: { documentMessage: { fileName: 'a.pdf' } } } }))
      .toEqual({ documentMessage: { fileName: 'a.pdf' } });
  });
});

describe('normalizarMensagem', () => {
  it('recebida: id, telefone, nome, texto e hora ISO', () => {
    const r = normalizarMensagem(msg());
    expect(r).toEqual({
      evento: {
        evento: 'mensagem', id: '3EB0A1B2C3D4E5F6', fromMe: false, telefone: TEL, nome: 'Lead Teste', tipo: 'texto',
        texto: 'Oi, quero saber do curso', mime: null, arquivo: null, em: new Date(1760000000 * 1000).toISOString(), temMidia: false,
      },
      base64: null,
    });
  });
  it('enviada pelo celular/Clint (fromMe): sem nome do perfil', () => {
    const r = normalizarMensagem(msg({ pushName: 'Você' }, { fromMe: true }));
    expect('evento' in r && r.evento.fromMe).toBe(true);
    expect('evento' in r && r.evento.nome).toBeNull();
  });
  it('mídia com base64 marca temMidia e devolve o arquivo à parte', () => {
    const r = normalizarMensagem(msg({ message: { imageMessage: { caption: 'foto', mimetype: 'image/jpeg' }, base64: 'QUJDRA==' } }));
    expect(r).toMatchObject({ evento: { tipo: 'imagem', temMidia: true, texto: 'foto' }, base64: 'QUJDRA==' });
  });
  it('mídia sem base64: temMidia false (o banco marca "não veio")', () => {
    const r = normalizarMensagem(msg({ message: { audioMessage: { mimetype: 'audio/ogg' } } }));
    expect(r).toMatchObject({ evento: { tipo: 'audio', temMidia: false }, base64: null });
  });
  it('sem id válido ou grupo: ignora', () => {
    expect(normalizarMensagem(msg({}, { id: 'x' }))).toEqual({ ignorar: 'sem_id' });
    expect(normalizarMensagem(msg({}, { remoteJid: '1203@g.us' }))).toEqual({ ignorar: 'grupo' });
    expect(normalizarMensagem({ message: {} })).toEqual({ ignorar: 'sem_key' });
  });
  it('texto longo é cortado em 4.096', () => {
    const r = normalizarMensagem(msg({ message: { conversation: 'a'.repeat(5000) } }));
    expect('evento' in r && r.evento.texto?.length).toBe(4096);
  });
});

describe('normalizarConexao / normalizarQr', () => {
  it('open traz o número do dono da sessão', () => {
    expect(normalizarConexao({ instance: 'crm-x', state: 'open', wuid: '552190000001@s.whatsapp.net', statusReason: 200 }))
      .toEqual({ evento: 'conexao', estado: 'open', numero: '5521990000001', codigo: null, motivo: null });
  });
  it('close leva o código (401 saiu, 403 bloqueado)', () => {
    expect(normalizarConexao({ state: 'close', statusReason: 403 })).toMatchObject({ estado: 'close', codigo: 403, numero: null });
  });
  it('estado desconhecido: null', () => expect(normalizarConexao({ state: 'refused' })).toBeNull());
  it('QR só como data URL PNG', () => {
    expect(normalizarQr({ qrcode: { instance: 'crm-x', base64: 'data:image/png;base64,iVBORw0KGgo=' } }))
      .toEqual({ evento: 'qr', base64: 'data:image/png;base64,iVBORw0KGgo=' });
    expect(normalizarQr({ qrcode: { base64: 'data:text/html;base64,PHNjcmlwdD4=' } })).toBeNull();
  });
  it('limite de QR vira conexão fechada com motivo', () => {
    expect(normalizarQr({ message: 'QR code limit reached, please login again', statusCode: 500 }))
      .toMatchObject({ evento: 'conexao', estado: 'close' });
  });
});

describe('normalizarWebhook', () => {
  it('messages.upsert com uma mensagem', () => {
    const n = normalizarWebhook({ event: 'messages.upsert', instance: 'crm-clint-4276-ab12cd', data: msg() });
    expect(n.instancia).toBe('crm-clint-4276-ab12cd');
    expect(n.eventos).toHaveLength(1);
    expect(n.ignorados).toEqual([]);
  });
  it('lista de mensagens: grupo fica de fora e o arquivo fica no índice certo', () => {
    const n = normalizarWebhook({
      event: 'MESSAGES_UPSERT', instance: 'crm-a-b1c2d3',
      data: [msg({}, { remoteJid: '1203@g.us' }), msg({ message: { documentMessage: { fileName: 'a.pdf' }, base64: 'QUJD' } }, { id: 'ABCDEF1234' })],
    });
    expect(n.eventos).toHaveLength(1);
    expect(n.arquivos).toEqual({ 0: 'QUJD' });
    expect(n.ignorados).toEqual(['grupo']);
  });
  it('instância fora do padrão do CRM não é aceita como nome', () => {
    expect(normalizarWebhook({ event: 'connection.update', instance: 'teste-joao', data: { state: 'open' } }).instancia).toBeNull();
  });
  it('evento que não usamos fica ignorado', () => {
    expect(normalizarWebhook({ event: 'presence.update', data: {} }).ignorados).toEqual(['evento:presence.update']);
    expect(normalizarWebhook(null).ignorados).toEqual(['corpo']);
  });
});

describe('arquivo', () => {
  it('caminho <conversa>/<mensagem>.<ext> e mime seguro', () => {
    expect(caminhoArquivo('c1', 'm1', 'audio/ogg; codecs=opus')).toBe('c1/m1.ogg');
    expect(caminhoArquivo('c1', 'm1', 'text/html')).toBe('c1/m1.bin');
    expect(mimeSeguro('text/html')).toBe('application/octet-stream');
    expect(mimeSeguro('image/PNG')).toBe('image/png');
  });
  it('tamanho do base64 sem decodificar', () => {
    expect(bytesDoBase64('QUJD')).toBe(3);
    expect(bytesDoBase64('QUJDRA==')).toBe(4);
    expect(bytesDoBase64('QUJDREU=')).toBe(5);
  });
});

// ── Edição e revogação (migration 20261009153515) ──
describe('edição e exclusão vindas do WhatsApp', () => {
  it('messages.upsert com protocolMessage REVOKE vira revogação da key original', () => {
    const n = normalizarWebhook({ event: 'messages.upsert', instance: 'crm-clint-ab12cd', data: msg({ message: { protocolMessage: { key: { id: 'ORIG12345', remoteJid: `${TEL}@s.whatsapp.net` }, type: 'REVOKE' } } }) });
    expect(n.eventos).toEqual([{ evento: 'revogacao', id: 'ORIG12345' }]);
  });
  it('messages.upsert com edição (type 14) vira edição com o texto novo', () => {
    const n = normalizarWebhook({ event: 'messages.upsert', data: msg({ message: { protocolMessage: { key: { id: 'ORIG12345' }, type: 14, editedMessage: { conversation: 'texto novo' } } } }) });
    expect(n.eventos).toEqual([{ evento: 'edicao', id: 'ORIG12345', texto: 'texto novo' }]);
  });
  it('editedMessage embrulhado também', () => {
    const n = normalizarWebhook({ event: 'messages.upsert', data: msg({ message: { editedMessage: { message: { protocolMessage: { key: { id: 'ORIG12345' }, type: 'MESSAGE_EDIT', editedMessage: { extendedTextMessage: { text: 'corrigido' } } } } } } }) });
    expect(n.eventos).toEqual([{ evento: 'edicao', id: 'ORIG12345', texto: 'corrigido' }]);
  });
  it('MESSAGES_EDITED: o corpo é o próprio protocolMessage', () => {
    const n = normalizarWebhook({ event: 'MESSAGES_EDITED', data: { key: { id: 'ORIG12345', remoteJid: `${TEL}@s.whatsapp.net`, fromMe: false }, type: 14, editedMessage: { conversation: 'oi de novo' } } });
    expect(n.eventos).toEqual([{ evento: 'edicao', id: 'ORIG12345', texto: 'oi de novo' }]);
  });
  it('MESSAGES_DELETE: key espalhada vira revogação; grupo fica de fora', () => {
    expect(normalizarWebhook({ event: 'messages.delete', data: { id: 'ORIG12345', remoteJid: `${TEL}@s.whatsapp.net`, fromMe: false, status: 'DELETED' } }).eventos)
      .toEqual([{ evento: 'revogacao', id: 'ORIG12345' }]);
    expect(normalizarWebhook({ event: 'messages.delete', data: { id: 'ORIG12345', remoteJid: '120363000000000000@g.us' } }).eventos).toEqual([]);
  });
  it('edição sem texto e protocolo de outro tipo são ignorados', () => {
    expect(normalizarWebhook({ event: 'messages.upsert', data: msg({ message: { protocolMessage: { key: { id: 'ORIG12345' }, type: 14, editedMessage: {} } } }) }).eventos).toEqual([]);
    expect(normalizarWebhook({ event: 'messages.upsert', data: msg({ message: { protocolMessage: { key: { id: 'ORIG12345' }, type: 3 } } }) }).eventos).toEqual([]);
  });
});
