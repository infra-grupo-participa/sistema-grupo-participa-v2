import { describe, expect, it } from 'vitest';
import { lerLinkCrm } from './link-crm';

const U = '7fbef102-5b0c-4efa-ad39-c43d2fcd026c';

describe('lerLinkCrm', () => {
  it('conversa e contato → contato; funil → negócio', () => {
    expect(lerLinkCrm(`https://grupoparticipa.app.br/comercial/conversas?contato=${U}`)).toEqual({ ok: true, tipo: 'contato', id: U });
    expect(lerLinkCrm(`https://grupoparticipa.app.br/comercial/contatos?contato=${U.toUpperCase()}`)).toEqual({ ok: true, tipo: 'contato', id: U });
    expect(lerLinkCrm(`https://grupoparticipa.app.br/comercial/funil?negocio=${U}`)).toEqual({ ok: true, tipo: 'negocio', id: U });
    expect(lerLinkCrm(`grupoparticipa.app.br/comercial/funil?f=x&negocio=${U}`)).toEqual({ ok: true, tipo: 'negocio', id: U });
    expect(lerLinkCrm(`<https://grupoparticipa.app.br/comercial/conversas?contato=${U}>`)).toMatchObject({ ok: true });
    expect(lerLinkCrm(`http://localhost:3000/comercial/conversas?contato=${U}`)).toEqual({ ok: true, tipo: 'contato', id: U });
  });
  it('recusa outro domínio, imitação, http em produção, credencial na URL, fora de /comercial e id inválido', () => {
    for (const l of [
      `https://evil.com/comercial/conversas?contato=${U}`,
      `https://grupoparticipa.app.br.evil.com/comercial/conversas?contato=${U}`,
      `https://evilgrupoparticipa.app.br/comercial/conversas?contato=${U}`,
      `http://grupoparticipa.app.br/comercial/conversas?contato=${U}`,
      `https://grupoparticipa.app.br:8443/comercial/conversas?contato=${U}`,
      `https://user:pw@grupoparticipa.app.br/comercial/conversas?contato=${U}`,
      `https://grupoparticipa.app.br/educacional/alunos?contato=${U}`,
      `https://grupoparticipa.app.br/comercial/conversas?contato=123`,
      `https://grupoparticipa.app.br/comercial/conversas?contato=${U}&contato=${U}`,
      `https://grupoparticipa.app.br/comercial/conversas`,
      `javascript:alert(1)`,
      U,
      '',
      null,
      `https://grupoparticipa.app.br/comercial/conversas?contato=${U}&x=${'a'.repeat(500)}`,
    ]) {
      expect(lerLinkCrm(l).ok, String(l)).toBe(false);
    }
  });
});
