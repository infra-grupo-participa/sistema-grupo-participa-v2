import { describe, expect, it } from 'vitest';
import { HOSTS_REDE, safeHttpUrl } from './url-segura';

describe('safeHttpUrl', () => {
  it('aceita http(s) sem lista de hosts', () => {
    expect(safeHttpUrl('https://exemplo.com.br/x')).toBe('https://exemplo.com.br/x');
    expect(safeHttpUrl('http://exemplo.com')).toBe('http://exemplo.com');
  });
  it('recusa esquema perigoso', () => {
    expect(safeHttpUrl('javascript:alert(1)')).toBeNull();
    expect(safeHttpUrl('data:text/html,<script>1</script>')).toBeNull();
    expect(safeHttpUrl('vbscript:x')).toBeNull();
    expect(safeHttpUrl('//instagram.com/x')).toBeNull();
  });
  it('recusa vazio, nulo e texto que não é URL', () => {
    expect(safeHttpUrl(null)).toBeNull();
    expect(safeHttpUrl('')).toBeNull();
    expect(safeHttpUrl('instagram.com/fulana')).toBeNull();
  });
  it('com allowlist, aceita o host e subdomínio', () => {
    expect(safeHttpUrl('https://instagram.com/fulana', HOSTS_REDE.instagram)).toBe('https://instagram.com/fulana');
    expect(safeHttpUrl('https://www.instagram.com/fulana?igsh=abc', HOSTS_REDE.instagram)).toBe('https://www.instagram.com/fulana?igsh=abc');
    expect(safeHttpUrl('https://youtu.be/abc', HOSTS_REDE.youtube)).toBe('https://youtu.be/abc');
  });
  it('com allowlist, recusa host de fora e disfarces', () => {
    expect(safeHttpUrl('https://evil.example/?facebook.com/x', HOSTS_REDE.facebook)).toBeNull();
    expect(safeHttpUrl('https://facebook.com.evil.example/x', HOSTS_REDE.facebook)).toBeNull();
    expect(safeHttpUrl('https://evilfacebook.com/x', HOSTS_REDE.facebook)).toBeNull();
    expect(safeHttpUrl('https://facebook.com@evil.example/x', HOSTS_REDE.facebook)).toBeNull();
    expect(safeHttpUrl('https://instagram.com:8443/x', HOSTS_REDE.instagram)).toBeNull();
  });
  it('remove quebra de linha antes de validar', () => {
    expect(safeHttpUrl('https://instagram.com/\nfulana', HOSTS_REDE.instagram)).toBe('https://instagram.com/fulana');
  });
});
