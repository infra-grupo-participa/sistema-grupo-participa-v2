import { describe, expect, it } from 'vitest';
import {
  LIMITE_IMAGEM, LIMITE_PDF, avisoMidia, caminhoAnexo, ehOggOpus, fmtTamanho, legendaDaMensagem, nomeArquivo, tipoMidia, uploadSobrou, validarAnexo,
} from './midia';
import type { MidiaMensagem } from './types';

const ok = (x: Partial<MidiaMensagem> = {}): MidiaMensagem => ({ status: 'ok', caminho: 'c/m.jpg', mime: 'image/jpeg', tamanho: 1000, nome: null, ...x });

describe('tipoMidia', () => {
  it('só com arquivo e tipo de mídia', () => {
    expect(tipoMidia({ tipo: 'imagem', midia: ok() })).toBe('imagem');
    expect(tipoMidia({ tipo: 'audio', midia: ok({ status: 'pendente', caminho: null }) })).toBe('audio');
    expect(tipoMidia({ tipo: 'texto', midia: ok() })).toBeNull();
  });
  it('mensagem antiga "[imagem]" sem arquivo continua texto', () => {
    expect(tipoMidia({ tipo: 'imagem', midia: null })).toBeNull();
    expect(tipoMidia({ tipo: 'imagem' })).toBeNull();
  });
});

describe('legendaDaMensagem', () => {
  it('tira o rótulo quando o arquivo aparece', () => {
    expect(legendaDaMensagem({ tipo: 'imagem', midia: ok(), texto: '[imagem] foto da proposta' })).toBe('foto da proposta');
    expect(legendaDaMensagem({ tipo: 'audio', midia: ok(), texto: '[áudio]' })).toBe('');
    expect(legendaDaMensagem({ tipo: 'video', midia: ok(), texto: '[vídeo] olha' })).toBe('olha');
  });
  it('legenda do vendedor fica igual', () => {
    expect(legendaDaMensagem({ tipo: 'imagem', midia: ok(), texto: 'Segue a proposta' })).toBe('Segue a proposta');
  });
  it('documento enviado sem legenda: o nome não repete', () => {
    expect(legendaDaMensagem({ tipo: 'documento', midia: ok({ nome: 'Proposta.pdf' }), texto: '[documento] Proposta.pdf' })).toBe('');
  });
  it('mensagem antiga sem arquivo mostra o texto como veio', () => {
    expect(legendaDaMensagem({ tipo: 'imagem', midia: null, texto: '[imagem]' })).toBe('[imagem]');
  });
});

describe('fmtTamanho', () => {
  it('B, KB e MB em pt-BR', () => {
    expect(fmtTamanho(12)).toBe('12 B');
    expect(fmtTamanho(850 * 1024)).toBe('850 KB');
    expect(fmtTamanho(1.25 * 1048576)).toBe('1,3 MB');
    expect(fmtTamanho(null)).toBe('');
  });
});

describe('nomeArquivo', () => {
  it('usa o nome; sem nome, o tipo + extensão do caminho', () => {
    expect(nomeArquivo({ tipo: 'documento', midia: ok({ nome: 'contrato.pdf' }) })).toBe('contrato.pdf');
    expect(nomeArquivo({ tipo: 'audio', midia: ok({ caminho: 'c/m.ogg' }) })).toBe('audio.ogg');
  });
});

describe('avisoMidia', () => {
  it('grande demais e falha avisam; ok e pendente não', () => {
    expect(avisoMidia(ok({ status: 'grande_demais', caminho: null, tamanho: 30 * 1048576 }))).toContain('30 MB');
    expect(avisoMidia(ok({ status: 'falhou', caminho: null }))).toMatch(/Não foi possível/);
    expect(avisoMidia(ok())).toBeNull();
    expect(avisoMidia(ok({ status: 'pendente', caminho: null }))).toBeNull();
  });
});

describe('ehOggOpus', () => {
  it('áudio do WhatsApp', () => {
    expect(ehOggOpus('audio/ogg; codecs=opus')).toBe(true);
    expect(ehOggOpus('audio/mpeg')).toBe(false);
    expect(ehOggOpus(null)).toBe(false);
  });
});

describe('validarAnexo', () => {
  it('aceita JPG/PNG/WebP até 5 MB e PDF até 16 MB', () => {
    expect(validarAnexo({ type: 'image/png', size: 10, name: 'a.png' })).toMatchObject({ ok: true, tipo: 'imagem', ext: 'png' });
    expect(validarAnexo({ type: 'application/pdf', size: LIMITE_PDF, name: 'p.pdf' })).toMatchObject({ ok: true, tipo: 'documento', ext: 'pdf' });
  });
  it('recusa outro tipo, vazio e grande demais', () => {
    expect(validarAnexo({ type: 'image/gif', size: 10, name: 'a.gif' })).toEqual({ ok: false, msg: 'Só imagem (JPG, PNG, WebP) ou PDF.' });
    expect(validarAnexo({ type: 'text/html', size: 10, name: 'x.html' }).ok).toBe(false);
    expect(validarAnexo({ type: 'image/jpeg', size: 0, name: 'a.jpg' })).toEqual({ ok: false, msg: 'Arquivo vazio.' });
    expect(validarAnexo({ type: 'image/jpeg', size: LIMITE_IMAGEM + 1, name: 'a.jpg' })).toEqual({ ok: false, msg: 'Arquivo grande demais (máximo 5 MB).' });
    expect(validarAnexo({ type: 'application/pdf', size: LIMITE_PDF + 1, name: 'a.pdf' })).toEqual({ ok: false, msg: 'Arquivo grande demais (máximo 16 MB).' });
  });
  it('nome sem barra nem controle; sem nome usa padrão', () => {
    const v = validarAnexo({ type: 'application/pdf', size: 5, name: '../x/\u0001p.pdf' });
    expect(v.ok && v.nome).toBe('.._x__p.pdf');
    const s = validarAnexo({ type: 'application/pdf', size: 5, name: '' });
    expect(s.ok && s.nome).toBe('documento.pdf');
  });
});

describe('caminhoAnexo', () => {
  it('formato que a policy do Storage aceita', () => {
    expect(caminhoAnexo('u-1', 'abc', 'pdf')).toBe('envio/u-1/abc.pdf');
  });
});

describe('uploadSobrou', () => {
  it('recusado ou repetido = apagar o upload; enviado = manter', () => {
    expect(uploadSobrou({ ok: false })).toBe(true);
    expect(uploadSobrou({ ok: true, repetida: true })).toBe(true);
    expect(uploadSobrou({ ok: true })).toBe(false);
    expect(uploadSobrou({ ok: true, repetida: false })).toBe(false);
  });
});
