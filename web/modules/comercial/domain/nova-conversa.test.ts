import { describe, expect, it } from 'vitest';
import type { CanalWhatsapp } from './canais-whatsapp';
import {
  avisoLimiteQr, bloqueioCanalNovaConversa, bloqueioPessoaNovaConversa, canaisParaNovaConversa, canalInicialNovaConversa,
  janelaDoCanal, modoEnvio, rotuloProvedor,
} from './nova-conversa';

const canal = (p: Partial<CanalWhatsapp>): CanalWhatsapp => ({
  id: 'qr', provedor: 'evolution', nome: 'Clint', final: '4276', status: 'conectado', statusEm: null, statusMotivo: null,
  conectadoEm: null, recebe: true, envia: true, donoId: null, padrao: false, ...p,
});
const oficial = canal({ id: 'of', provedor: 'infobip', nome: 'Comercial oficial', final: '5211', padrao: true });
const qr = canal({});
const painel = { evolutionLigado: true, envioLigado: true };
const vendedor = { vendedorId: 'v1', papel: 'vendedor' as const };
const gestor = { vendedorId: 'g1', papel: 'gestor' as const };
const leitor = { vendedorId: 'l1', papel: 'leitor' as const };
const nomeDe = (id: string | null) => (id === 'v2' ? 'Ana' : id ?? 'sem dono');
const agora = new Date('2026-10-08T12:00:00Z');

describe('qual número pode abrir conversa', () => {
  it('conectado e com envio: oficial e QR', () => {
    expect(canaisParaNovaConversa([oficial, qr], painel, vendedor).map((c) => c.id)).toEqual(['of', 'qr']);
  });
  it('fora: sem envio, desconectado, QR desligado, envio geral desligado', () => {
    expect(bloqueioCanalNovaConversa(canal({ envia: false }), painel, vendedor)).toMatch(/não envia/);
    expect(bloqueioCanalNovaConversa(canal({ status: 'aguardando_qr' }), painel, vendedor)).toMatch(/desconectado/);
    expect(bloqueioCanalNovaConversa(canal({ status: 'banido' }), painel, vendedor)).toMatch(/desconectado/);
    expect(bloqueioCanalNovaConversa(qr, { evolutionLigado: false, envioLigado: true }, vendedor)).toMatch(/QR desligado/);
    expect(bloqueioCanalNovaConversa(oficial, { evolutionLigado: true, envioLigado: false }, vendedor)).toMatch(/Envio/);
  });
  it('QR com dono: só o dono ou o gestor', () => {
    const deAna = canal({ donoId: 'v2' });
    expect(bloqueioCanalNovaConversa(deAna, painel, vendedor)).toMatch(/outra pessoa/);
    expect(bloqueioCanalNovaConversa(deAna, painel, gestor)).toBeNull();
    expect(bloqueioCanalNovaConversa(canal({ donoId: 'v1' }), painel, vendedor)).toBeNull();
  });
  it('leitor não abre conversa', () => {
    expect(canaisParaNovaConversa([oficial, qr], painel, leitor)).toEqual([]);
  });
  it('um número só já vem escolhido', () => {
    expect(canalInicialNovaConversa([qr])).toBe('qr');
    expect(canalInicialNovaConversa([oficial, qr])).toBeNull();
    expect(canalInicialNovaConversa([])).toBeNull();
  });
  it('rótulo do provedor', () => {
    expect(rotuloProvedor(oficial)).toBe('Oficial');
    expect(rotuloProvedor(qr)).toBe('QR');
  });
});

describe('template obrigatório ou não', () => {
  const aberta = '2026-10-08T20:00:00Z';
  it('QR: sempre texto livre', () => {
    expect(modoEnvio(qr, null, agora)).toBe('livre');
  });
  it('oficial: livre só com a janela aberta', () => {
    expect(modoEnvio(oficial, aberta, agora)).toBe('livre');
    expect(modoEnvio(oficial, null, agora)).toBe('template');
    expect(modoEnvio(oficial, '2026-10-08T11:00:00Z', agora)).toBe('template');
  });
  it('janela é do número: pessoa que só falou pelo QR tem a do oficial fechada', () => {
    expect(janelaDoCanal({ janelaAteEm: aberta, canais: ['qr'] }, 'of')).toBeNull();
    expect(janelaDoCanal({ janelaAteEm: aberta, canais: ['qr', 'of'] }, 'of')).toBe(aberta);
    expect(janelaDoCanal(null, 'of')).toBeNull();
    expect(janelaDoCanal({ janelaAteEm: aberta }, 'of')).toBe(aberta);
  });
});

describe('bloqueios da pessoa', () => {
  const pessoa = { donoId: 'v1', optOut: false, telefone: '5511987654321' };
  it('dono do contato começa', () => {
    expect(bloqueioPessoaNovaConversa(pessoa, [], vendedor, nomeDe)).toBeNull();
  });
  it('D6: vendedor não puxa contato de outro; gestor pode', () => {
    const deAna = { ...pessoa, donoId: 'v2' };
    expect(bloqueioPessoaNovaConversa(deAna, [], vendedor, nomeDe)).toMatch(/Lead de Ana/);
    expect(bloqueioPessoaNovaConversa(deAna, [], gestor, nomeDe)).toBeNull();
    // dono de algum negócio da pessoa também escreve (crm.pode_escrever_pessoa)
    expect(bloqueioPessoaNovaConversa(deAna, [{ donoId: 'v1' }], vendedor, nomeDe)).toBeNull();
  });
  it('sem dono: só o gestor', () => {
    expect(bloqueioPessoaNovaConversa({ ...pessoa, donoId: null }, [], vendedor, nomeDe)).toMatch(/sem dono/);
    expect(bloqueioPessoaNovaConversa({ ...pessoa, donoId: null }, [], gestor, nomeDe)).toBeNull();
  });
  it('opt-out bloqueia até o gestor', () => {
    expect(bloqueioPessoaNovaConversa({ ...pessoa, optOut: true }, [], gestor, nomeDe)).toMatch(/não receber contato/);
  });
  it('sem telefone não recebe WhatsApp', () => {
    expect(bloqueioPessoaNovaConversa({ ...pessoa, telefone: null }, [], vendedor, nomeDe)).toMatch(/sem telefone/);
  });
  it('leitor não escreve', () => {
    expect(bloqueioPessoaNovaConversa(pessoa, [], leitor, nomeDe)).toBe('Acesso só de leitura.');
  });
});

describe('aviso do QR', () => {
  it('mostra os limites do painel', () => {
    expect(avisoLimiteQr({ limiteMinuto: 15, limiteHora: 200, novosHora: 20 })).toMatch(/15 mensagens por minuto, 200 por hora e 20 contatos novos/);
    expect(avisoLimiteQr(null)).toMatch(/sem disparo em massa/);
  });
});
