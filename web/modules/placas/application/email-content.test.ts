import { describe, expect, it } from 'vitest';
import { getEmailContentByStatus, linkZoomSeguro } from './email-content';

describe('linkZoomSeguro', () => {
  it.each([
    ['https://zoom.us/j/123', 'https://zoom.us/j/123'],
    ['https://us02web.zoom.us/j/123?pwd=a', 'https://us02web.zoom.us/j/123?pwd=a'],
    ['  https://ZOOM.US/j/1 ', 'https://zoom.us/j/1'],
    // ponto fullwidth: o WHATWG URL normaliza para zoom.us real; devolvemos a forma ASCII normalizada
    ['https://zoom．us/j/1', 'https://zoom.us/j/1'],
  ])('aceita %s', (i, o) => expect(linkZoomSeguro(i)).toBe(o));

  it.each([
    'https://zoom.us.evil.com/j/1',
    'https://evil.com/zoom.us',
    'https://evilzoom.us/j/1',
    'http://x.zoom.us/j/1',
    'https://zoom．us.evil.com/j/1',
    'https://zoom.us@evil.com/j/1',
    'https://user:pw@zoom.us/j/1',
    'https://zoom.us:8443/j/1',
    'javascript:alert(1)',
    'nao-e-url',
    '',
    null,
    undefined,
  ])('rejeita %s', (i) => expect(linkZoomSeguro(i as string)).toBeNull());
});

describe('zoom nos e-mails', () => {
  it('agendada: link inseguro cai no acompanhamento', () => {
    const c = getEmailContentByStatus('entrevista_agendada', { zoom_link: 'https://evil.com/zoom.us' }, 'https://t/x');
    expect(c.templateData.cta_link).toBe('https://t/x');
  });
  it('agendada: link zoom válido vira CTA', () => {
    const c = getEmailContentByStatus('entrevista_agendada', { zoom_link: 'https://a.zoom.us/j/1' }, 'https://t/x');
    expect(c.templateData.cta_link).toBe('https://a.zoom.us/j/1');
  });
  it('lembrete: inclui link da sala quando válido', () => {
    const c = getEmailContentByStatus('lembrete_entrevista', { zoom_link: 'https://a.zoom.us/j/1' }, 'https://t/x');
    expect(c.templateData.corpo_extra).toContain('https://a.zoom.us/j/1');
    expect(c.templateData.corpo_extra).not.toContain('foi enviado no e-mail');
  });
  it('lembrete: sem link válido mantém texto antigo', () => {
    const c = getEmailContentByStatus('lembrete_entrevista', { zoom_link: 'http://a.zoom.us/j/1' }, 'https://t/x');
    expect(c.templateData.corpo_extra).toContain('foi enviado no e-mail');
  });
});
