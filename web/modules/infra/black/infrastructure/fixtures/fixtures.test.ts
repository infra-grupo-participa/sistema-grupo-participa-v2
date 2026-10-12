import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { connectRate, cplPorEtapa, indexar } from '../../domain/metricas';
import { CHAVE_BLACK, CONFIG_BLACK } from './catalogo';
import { criarFonteFixtures, relogioDemo } from './fonte-fixtures';
import { baseFicticia, RELOGIO_PADRAO } from './gerador';

const b = baseFicticia();
const idx = indexar(b);

describe('base fictícia', () => {
  it('é reprodutível (mesma semente, mesmos totais)', () => {
    const gasto = b.dias.reduce((s, d) => s + d.gasto, 0);
    expect(b.linhas).toHaveLength(14590);
    expect(Math.round(gasto * 100) / 100).toBe(276000.76);
    expect(new Set(b.linhas.map((l) => l.pessoaId)).size).toBe(14146);
  });
  it('pagos por funil + não pagos = total de cadastros', () => {
    const pagos = b.linhas.filter((l) => l.origem === 'pago');
    const porFunil = ['consultoria', 'iscas', 'c3'].map((f) => pagos.filter((l) => l.funil === f).length);
    const naoPagos = b.linhas.filter((l) => l.origem !== 'pago').length;
    expect(porFunil.reduce((s, n) => s + n, 0) + naoPagos).toBe(b.linhas.length);
    expect(pagos.some((l) => l.funil === 'c1')).toBe(false);
  });
  it('CPL da etapa = gasto da etapa ÷ leads pagos da etapa', () => {
    const iscas = cplPorEtapa(b.dias, b.linhas, idx).find((e) => e.chave === 'iscas')!;
    const anuncios = new Set(b.anuncios.filter((a) => idx.campanhaDoAnuncio(a.id)?.id === 'cp-iscas').map((a) => a.id));
    const gasto = b.dias.filter((d) => anuncios.has(d.anuncioId)).reduce((s, d) => s + d.gasto, 0);
    const pagos = b.linhas.filter((l) => l.origem === 'pago' && l.campanhaId === 'cp-iscas').length;
    expect(iscas.cpl.gasto).toBeCloseTo(gasto, 6);
    expect(iscas.cpl.leadsPagos).toBe(pagos);
    expect(iscas.cpl.valor).toBeCloseTo(gasto / pagos, 6);
  });
  it('C1 sem clique (connect rate sem dado) e Google sem LPV (fica fora, com nota)', () => {
    const c1 = b.dias.filter((d) => idx.campanhaDoAnuncio(d.anuncioId)?.funil === 'c1');
    expect(c1.every((d) => d.cliquesLink === null && d.landingPageViews === null)).toBe(true);
    expect(connectRate(c1, idx).valor).toBeNull();
    const google = b.dias.filter((d) => idx.campanhaDoAnuncio(d.anuncioId)?.canal === 'google');
    expect(google.every((d) => d.landingPageViews === null)).toBe(true);
    expect(connectRate(b.dias, idx).nota).toMatch(/Google sem LPV/);
  });
  it('só dado fictício identificável: nomes Lead Teste, e-mail @exemplo.test, gestor ZZ', () => {
    for (const d of b.detalhes.values()) {
      expect(d.nome).toMatch(/^Lead Teste \d{5}$/);
      expect(d.email).toMatch(/@exemplo\.test$/);
    }
    expect(b.campanhas.every((c) => c.nome.startsWith('ZZ | ') && c.nome.includes('FICTÍCIO'))).toBe(true);
    expect(CONFIG_BLACK.chave).toBe(CHAVE_BLACK);
  });
  it('telefones de borda presentes (vazio, texto, null, +55, sem máscara)', () => {
    const tels = [...b.detalhes.values()].map((d) => d.telefone);
    expect(tels.includes(null)).toBe(true);
    expect(tels.some((t) => t === 'FICTÍCIO sem número')).toBe(true);
    expect(tels.some((t) => t?.startsWith('+55 '))).toBe(true);
    expect(tels.some((t) => t !== null && /^\d{11}$/.test(t))).toBe(true);
    expect(b.linhas.some((l) => l.uf === null)).toBe(true);
  });
});

describe('fonte de demonstração', () => {
  it('relógio: padrão 03/11 18h; ?relogio= dentro do intervalo fixa 23h59 do dia', () => {
    expect(relogioDemo().toISOString()).toBe(new Date(RELOGIO_PADRAO).toISOString());
    expect(relogioDemo('2026-10-20').toISOString()).toBe('2026-10-21T02:59:59.000Z');
    expect(relogioDemo('2026-12-01').toISOString()).toBe(new Date(RELOGIO_PADRAO).toISOString());
    expect(relogioDemo('lixo').toISOString()).toBe(new Date(RELOGIO_PADRAO).toISOString());
  });
  it('corta o período no relógio e não mostra o futuro', async () => {
    const f = criarFonteFixtures('2026-10-20');
    const p = { de: '2026-10-04', ate: '2026-11-03' };
    const t = await f.trafego(CHAVE_BLACK, p);
    expect(t.data.dias.every((d) => d.dia <= '2026-10-20')).toBe(true);
    const l = await f.perfil(CHAVE_BLACK, p);
    expect(l.data.every((x) => x.criadoEm.slice(0, 10) <= '2026-10-20')).toBe(true);
    const limite = f.agora().getTime();
    expect(l.data.every((x) => x.entrouGrupoEm === null || Date.parse(x.entrouGrupoEm) <= limite)).toBe(true);
  });
  it('mensageria: canal = soma dos seus envios; grupo e e-mail sem custo; envios do mais recente ao mais antigo, sem futuro', async () => {
    const f = criarFonteFixtures();
    const m = (await f.mensageria(CHAVE_BLACK, { de: '2026-10-04', ate: '2026-11-03' })).data;
    expect(m.canais.map((c) => c.canal)).toEqual(['api', 'sms', 'ligacao', 'grupo', 'email']);
    for (const c of m.canais) {
      const doCanal = m.envios.filter((e) => e.canal === c.canal);
      expect(c.envios).toBe(doCanal.length);
      expect(c.enviados).toBe(doCanal.reduce((t, e) => t + (e.enviados ?? 0), 0));
      if (c.canal === 'grupo' || c.canal === 'email') expect(doCanal.every((e) => e.custo === null) && c.custo === null).toBe(true);
      else expect(c.custo).toBeCloseTo(doCanal.reduce((t, e) => t + (e.custo ?? 0), 0), 2);
    }
    expect(m.canais.find((c) => c.canal === 'sms')!.lidas).toBeNull();
    expect(m.envios.every((e, i) => i === 0 || m.envios[i - 1].enviadoEm >= e.enviadoEm)).toBe(true);
    expect(m.envios.every((e) => e.titulo && e.objetivo && e.copy)).toBe(true);
    const limite = f.agora().getTime();
    expect(m.envios.every((e) => Date.parse(`${e.enviadoEm}:00-03:00`) <= limite)).toBe(true);
  });
  it('leads: no máximo 50 por chamada; chave errada devolve erro', async () => {
    const f = criarFonteFixtures();
    const ids = b.linhas.slice(0, 80).map((l) => l.leadId);
    expect((await f.leads(CHAVE_BLACK, ids)).data).toHaveLength(50);
    expect((await f.config('outra')).erro).toMatch(/não existe/);
    expect((await f.marcos(CHAVE_BLACK)).semDado).toBe(true);
  });
  it('nenhum arquivo do demo importa o cliente Supabase', () => {
    const pasta = __dirname;
    for (const arq of readdirSync(pasta).filter((a) => a.endsWith('.ts') && !a.endsWith('.test.ts'))) {
      expect(readFileSync(join(pasta, arq), 'utf8')).not.toMatch(/(from|import\()\s*['"][^'"]*supabase/i);
    }
  });
});
