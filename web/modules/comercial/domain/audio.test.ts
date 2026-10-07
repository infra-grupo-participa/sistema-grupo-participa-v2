import { describe, expect, it } from 'vitest';
import { DURACAO_MAX_MS, LIMITE_AUDIO, erroMicrofone, escolherFormato, extAudioPermitida, fmtDuracao, planoAudio, validarAudio } from './audio';

describe('escolherFormato', () => {
  it('prefere ogg/opus, depois webm/opus, depois mp4', () => {
    expect(escolherFormato(() => true)).toBe('audio/ogg;codecs=opus');                          // Firefox
    expect(escolherFormato((m) => m.startsWith('audio/webm'))).toBe('audio/webm;codecs=opus'); // Chrome
    expect(escolherFormato((m) => m.startsWith('audio/mp4'))).toBe('audio/mp4;codecs=mp4a.40.2'); // Safari
    expect(escolherFormato(() => false)).toBe('');
    expect(escolherFormato(() => { throw new Error('x'); })).toBe('');
  });
});

describe('planoAudio', () => {
  it('ogg/opus vai direto como voz', () => {
    expect(planoAudio('audio/ogg; codecs=opus')).toEqual({ acao: 'direto', mime: 'audio/ogg', ext: 'ogg', voz: true });
    expect(planoAudio('audio/ogg')).toMatchObject({ acao: 'direto', voz: true });
    expect(planoAudio('audio/ogg;codecs=vorbis')).toBeNull();
  });
  it('webm/opus é remuxado para ogg', () => {
    expect(planoAudio('audio/webm;codecs=opus')).toEqual({ acao: 'remux', mime: 'audio/ogg', ext: 'ogg', voz: true });
    expect(planoAudio('audio/webm')).toMatchObject({ acao: 'remux' });
    expect(planoAudio('audio/webm;codecs=pcm')).toBeNull();
  });
  it('mp4/aac/mp3 saem como áudio comum', () => {
    expect(planoAudio('audio/mp4;codecs=mp4a.40.2')).toEqual({ acao: 'direto', mime: 'audio/mp4', ext: 'm4a', voz: false });
    expect(planoAudio('audio/aac')).toMatchObject({ mime: 'audio/aac', ext: 'aac' });
    expect(planoAudio('audio/mpeg')).toMatchObject({ mime: 'audio/mpeg', ext: 'mp3' });
  });
  it('desconhecido não envia', () => {
    expect(planoAudio('audio/wav')).toBeNull();
    expect(planoAudio('')).toBeNull();
    expect(planoAudio(null)).toBeNull();
  });
});

describe('validarAudio', () => {
  it('confere vazio, duração e tamanho', () => {
    expect(validarAudio({ tamanho: 0, duracaoMs: 5000 })).toMatchObject({ ok: false });
    expect(validarAudio({ tamanho: 100, duracaoMs: 500 })).toMatchObject({ ok: false, msg: expect.stringMatching(/curto/) });
    expect(validarAudio({ tamanho: 100, duracaoMs: DURACAO_MAX_MS + 5000 })).toMatchObject({ ok: false, msg: expect.stringMatching(/longo/) });
    expect(validarAudio({ tamanho: LIMITE_AUDIO + 1, duracaoMs: 60_000 })).toMatchObject({ ok: false, msg: expect.stringMatching(/16 MB/) });
    expect(validarAudio({ tamanho: 40_000, duracaoMs: DURACAO_MAX_MS })).toEqual({ ok: true });
  });
});

describe('fmtDuracao e erroMicrofone', () => {
  it('formata m:ss', () => {
    expect(fmtDuracao(0)).toBe('0:00');
    expect(fmtDuracao(7_900)).toBe('0:07');
    expect(fmtDuracao(102_000)).toBe('1:42');
    expect(fmtDuracao(DURACAO_MAX_MS)).toBe('5:00');
    expect(fmtDuracao(Number.NaN)).toBe('0:00');
  });
  it('explica a recusa do microfone', () => {
    expect(erroMicrofone('NotAllowedError')).toMatch(/bloqueado/);
    expect(erroMicrofone('NotFoundError')).toMatch(/Nenhum microfone/);
    expect(erroMicrofone('NotReadableError')).toMatch(/em uso/);
    expect(erroMicrofone(undefined)).toMatch(/Não foi possível/);
  });
});

describe('extAudioPermitida', () => {
  it('mesmo par extensão × mime do banco', () => {
    expect(extAudioPermitida('ogg', 'audio/ogg')).toBe(true);
    expect(extAudioPermitida('m4a', 'audio/mp4')).toBe(true);
    expect(extAudioPermitida('mp3', 'audio/mpeg')).toBe(true);
    expect(extAudioPermitida('aac', 'audio/aac')).toBe(true);
    expect(extAudioPermitida('ogg', 'audio/webm')).toBe(false);
    expect(extAudioPermitida('webm', 'audio/webm')).toBe(false);
  });
  it('todo plano de envio passa no banco', () => {
    for (const m of ['audio/ogg;codecs=opus', 'audio/webm;codecs=opus', 'audio/mp4', 'audio/aac', 'audio/mpeg']) {
      const p = planoAudio(m)!;
      expect(extAudioPermitida(p.ext, p.mime)).toBe(true);
    }
  });
});
