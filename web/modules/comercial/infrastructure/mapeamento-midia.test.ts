import { describe, expect, it } from 'vitest';
import { argsEscrita } from './mapeamento-escrita';
import { mapMidia } from './mapeamento-midia';
import { mapMensagens } from './mapeamento-supabase';

describe('mapMidia', () => {
  it('ok com caminho', () => {
    expect(mapMidia({ status: 'ok', caminho: 'c1/m1.jpg', mime: 'image/jpeg', tamanho: 123, nome: null }))
      .toEqual({ status: 'ok', caminho: 'c1/m1.jpg', mime: 'image/jpeg', tamanho: 123, nome: null });
  });
  it('pendente, grande_demais e falhou sem caminho', () => {
    expect(mapMidia({ status: 'pendente', caminho: 'x/y.jpg' })?.caminho).toBeNull();
    expect(mapMidia({ status: 'grande_demais', tamanho: 30000000 })).toMatchObject({ status: 'grande_demais', tamanho: 30000000 });
  });
  it('ok sem caminho válido vira falhou (nunca monta URL torta)', () => {
    expect(mapMidia({ status: 'ok', caminho: '../segredo' })?.status).toBe('falhou');
    expect(mapMidia({ status: 'ok', caminho: null })?.status).toBe('falhou');
  });
  it('formato inesperado = null', () => {
    expect(mapMidia(null)).toBeNull();
    expect(mapMidia('x')).toBeNull();
    expect(mapMidia({ status: 'outro' })).toBeNull();
  });
});

describe('crm_mensagens com midia', () => {
  it('mensagem antiga (sem midia) continua igual', () => {
    const [m] = mapMensagens([{ id: '1', contatoId: 'p', direcao: 'entrada', tipo: 'imagem', texto: '[imagem]', em: '2026-10-07T10:00:00Z', midia: null }]);
    expect(m.midia).toBeNull();
    expect(m.texto).toBe('[imagem]');
  });
  it('mensagem com arquivo', () => {
    const [m] = mapMensagens([{ id: '1', contatoId: 'p', direcao: 'entrada', tipo: 'audio', texto: '[áudio]', em: '2026-10-07T10:00:00Z',
      midia: { status: 'ok', caminho: 'c/m.ogg', mime: 'audio/ogg', tamanho: 9000, nome: null } }]);
    expect(m.midia).toMatchObject({ status: 'ok', caminho: 'c/m.ogg' });
  });
});

describe('argsEscrita.enviarAnexo', () => {
  it('legenda vazia vira null; template sempre null', () => {
    expect(argsEscrita.enviarAnexo('p1', 'envio/u/x.pdf', '  ', 'Proposta.pdf'))
      .toEqual({ p_pessoa: 'p1', p_texto: null, p_template: null, p_midia: 'envio/u/x.pdf', p_midia_nome: 'Proposta.pdf', p_chave: null });
  });
});

describe('argsEscrita.enviarAudio', () => {
  it('sem legenda, sem nome, sem template', () => {
    expect(argsEscrita.enviarAudio('p1', 'envio/u/x.ogg'))
      .toEqual({ p_pessoa: 'p1', p_texto: null, p_template: null, p_midia: 'envio/u/x.ogg', p_midia_nome: null, p_chave: null });
  });
});
