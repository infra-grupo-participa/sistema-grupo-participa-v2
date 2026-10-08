import { describe, expect, it, vi } from 'vitest';
import { credenciaisValidas, escolherCredenciais } from './canais-whatsapp';

const URL_OK = 'https://wa.grupoparticipa.app.br';
const CHAVE_ENV = 'chave-do-env-0123456789';
const CHAVE_VAULT = 'chave-do-vault-0123456789';

describe('credenciais da Evolution: env > Vault', () => {
  it('env completo vence e nem consulta o Vault', async () => {
    const vault = vi.fn(async () => ({ url: URL_OK, chave: CHAVE_VAULT }));
    const r = await escolherCredenciais(URL_OK, CHAVE_ENV, vault);
    expect(r).toEqual({ base: URL_OK, chave: CHAVE_ENV, fonte: 'env' });
    expect(vault).not.toHaveBeenCalled();
  });

  it('env vazio cai no Vault', async () => {
    const r = await escolherCredenciais('', '', async () => ({ url: URL_OK + '/', chave: CHAVE_VAULT }));
    expect(r).toEqual({ base: URL_OK, chave: CHAVE_VAULT, fonte: 'vault' });
  });

  it('env parcial não se mistura: usa o par do Vault inteiro', async () => {
    const r = await escolherCredenciais(URL_OK, '', async () => ({ url: 'https://outro.exemplo.com', chave: CHAVE_VAULT }));
    expect(r).toEqual({ base: 'https://outro.exemplo.com', chave: CHAVE_VAULT, fonte: 'vault' });
  });

  it('env inválido (http) cai no Vault', async () => {
    const r = await escolherCredenciais('http://wa.grupoparticipa.app.br', CHAVE_ENV, async () => ({ url: URL_OK, chave: CHAVE_VAULT }));
    expect(r?.fonte).toBe('vault');
  });

  it('nada configurado = null (rota responde 503)', async () => {
    expect(await escolherCredenciais('', '', async () => null)).toBeNull();
    expect(await escolherCredenciais('', '', async () => ({ url: URL_OK, chave: null }))).toBeNull();
    expect(await escolherCredenciais('', '', async () => ({ url: null, chave: CHAVE_VAULT }))).toBeNull();
  });

  it('chave curta ou URL com caminho é inválida', () => {
    expect(credenciaisValidas(URL_OK, 'curta')).toBeNull();
    expect(credenciaisValidas(URL_OK + '/api', CHAVE_ENV)).toBeNull();
    expect(credenciaisValidas(` ${URL_OK} `, ` ${CHAVE_ENV} `)).toEqual({ base: URL_OK, chave: CHAVE_ENV });
  });
});
