import { describe, expect, it } from 'vitest';
import { baseFicticia, RELOGIO_PADRAO } from '../infrastructure/fixtures/gerador';
import { CONFIG_BLACK } from '../infrastructure/fixtures/catalogo';
import { cplPorEtapa, cplRemarketing, indexar, pessoasUnicas } from './metricas';
import { calcularJornada, espessura, NO, NOS, noApagado, resumoDoNo, SETAS } from './jornada';

const b = baseFicticia();
const idx = indexar(b);
const agora = new Date(RELOGIO_PADRAO);
const mapa = calcularJornada({ dias: b.dias, linhas: b.linhas, linhasDoFunil: b.linhas, idx, config: CONFIG_BLACK, agora, mensageria: null });
const valor = (id: string, rotulo: string) => mapa[id].find((m) => m.rotulo === rotulo)?.valor;

describe('jornada', () => {
  it('toda seta liga nós que existem; ids únicos', () => {
    expect(NO.size).toBe(NOS.length);
    for (const s of SETAS) { expect(NO.has(s.de), s.de).toBe(true); expect(NO.has(s.para), s.para).toBe(true); }
  });
  it('textos do fluxograma do Arthur preservados (amostra literal)', () => {
    expect(NO.get('cortes')!.sub).toEqual(['4 por live, no YouTube e impulsionados']);
    expect(NO.get('lista')!.titulo).toBe('Lista do Método Perfeito');
    expect(NO.get('base-da-casa')!.sub).toEqual(['cerca de 189 mil leads']);
    expect(NO.get('live')!.sub).toEqual(['03/11 · 19h30 · YouTube + fake live no Insta']);
  });
  it('CPL dos nós = CPL por etapa do placar (mesma atribuição por campanha)', () => {
    const etapas = cplPorEtapa(b.dias, b.linhas, idx);
    expect(valor('pagina-isca', 'CPL')).toBeCloseTo(etapas.find((e) => e.chave === 'iscas')!.cpl.valor!, 6);
    expect(valor('aplicacao-consultoria', 'CPL')).toBeCloseTo(etapas.find((e) => e.chave === 'consultoria')!.cpl.valor!, 6);
    expect(valor('captacao-direta', 'CPL')).toBeCloseTo(etapas.find((e) => e.chave === 'c3')!.cpl.valor!, 6);
    expect(valor('remarketing', 'CPL')).toBeCloseTo(cplRemarketing(b.dias, b.linhas, idx).valor!, 6);
  });
  it('lista conta pessoas únicas; nó sem fonte não vira zero', () => {
    expect(valor('lista', 'Pessoas')).toBe(pessoasUnicas(b.linhas));
    expect(mapa.central).toEqual([]);
    expect(mapa.regua).toEqual([]);
    expect(valor('live', 'Presença')).toBeNull();
    expect(valor('live', 'Vendas')).toBeNull();
  });
  it('C1 não tem CPL nem connect rate', () => {
    expect(mapa.cortes.some((m) => m.rotulo === 'CPL' || m.rotulo === 'Connect rate')).toBe(false);
    expect(valor('cortes', 'Custo por visualização')).not.toBeNull();
  });
  it('filtro de funil apaga só os nós de outro funil; cadeia comum nunca apaga', () => {
    expect(noApagado(NO.get('cortes')!, 'iscas')).toBe(true);
    expect(noApagado(NO.get('pagina-isca')!, 'iscas')).toBe(false);
    expect(noApagado(NO.get('remarketing')!, 'c3')).toBe(false);
    expect(noApagado(NO.get('lista')!, 'c1')).toBe(false);
    expect(NOS.every((n) => !noApagado(n, 'todos'))).toBe(true);
  });
  it('espessura de 2 a 14 px pela raiz do volume; resumo segue a ordem do nó', () => {
    expect(espessura(null, 100)).toBe(2);
    expect(espessura(100, 100)).toBe(14);
    expect(espessura(25, 100)).toBe(8);
    expect(resumoDoNo(NO.get('pagina-isca')!, mapa['pagina-isca']).map((m) => m.rotulo)).toEqual(['Leads pagos', 'CPL', 'Conversão da página']);
  });
});
