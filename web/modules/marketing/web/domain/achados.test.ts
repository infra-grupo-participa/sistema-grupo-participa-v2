import { describe, expect, it } from 'vitest';
import { analisar, ordemDosAchados, textoGanho, type Achado } from './achados';
import type { BaseMelhorias, LeituraMelhorias, PaginaMelhorias } from './tipos';

// Números INVENTADOS só para cruzar os limiares das regras do Radar (oportunidades.ts do Luiz).
const pagina = (x: Partial<PaginaMelhorias> = {}): PaginaMelhorias => ({
  pagina_id: 1, codigo: 'ak1', nome: 'AK1', funcao: 'captura', caminho: '/ak1/', visitas: 1000, sessoes: 1000, leads: 100, mql: 30, dias: 7,
  entradas: 1000, rejeicoes: 400, leads_entrada: 100, mql_entrada: 30, ...x,
});
const base = (paginas: PaginaMelhorias[], leituras: LeituraMelhorias[] = []): BaseMelhorias => ({ sessoes: 1000, leads: 100, dias: 7, paginas, leituras });
const leitura = (x: Partial<LeituraMelhorias> = {}): LeituraMelhorias => ({
  pagina_id: 1, visitas: 1000, medidas: 1000, medidas_lead: 100, medidas_mql: 30, secoes: [], primeiro_cta: [], ctas: [], leads_com_botao: 0,
  form: { viram: 0, abriram: 0, comecaram: 0, enviaram: 0, campos: [] }, ...x,
});
const tipos = (r: { oportunidades: Achado[]; aprendizados: Achado[] }) => [...r.oportunidades, ...r.aprendizados].map((a) => a.tipo);

describe('achados automáticos (regras do Radar)', () => {
  it('nada sem dado; obrigado e página com menos de 20 visitas ficam fora', () => {
    expect(analisar(null, null, 'p').oportunidades).toEqual([]);
    const r = analisar(base([pagina({ funcao: 'obrigado' }), pagina({ pagina_id: 2, sessoes: 19 })]), null, 'p');
    expect(r.paginas).toBe(0);
  });
  it('dobra: celular rejeita 10 pontos a mais que o desktop', () => {
    const pg = pagina({ por_aparelho: [
      { dispositivo: 'mobile', entradas: 600, rejeicoes: 330, leads: 50 }, { dispositivo: 'desktop', entradas: 400, rejeicoes: 140, leads: 50 }] });
    const r = analisar(base([pg]), null, 'de 01/10 a 07/10');
    const a = r.oportunidades.find((x) => x.id.endsWith('dobra-celular'))!;
    expect(a.confianca).toBe('forte');
    expect(a.titulo).toContain('55%');
    expect(a.ganho).toBeGreaterThan(0);
  });
  it('dobra: 9 pontos não basta', () => {
    const pg = pagina({ por_aparelho: [
      { dispositivo: 'mobile', entradas: 600, rejeicoes: 264, leads: 50 }, { dispositivo: 'desktop', entradas: 400, rejeicoes: 140, leads: 50 }] });
    expect(tipos(analisar(base([pg]), null, 'p'))).not.toContain('dobra');
  });
  it('rejeição que subiu contra o período anterior', () => {
    const r = analisar(base([pagina({ rejeicoes: 500 })]), base([pagina({ rejeicoes: 380 })]), 'p');
    expect(r.oportunidades.find((x) => x.id.endsWith('dobra-subiu'))?.titulo).toContain('de 38% para 50%');
  });
  it('promessa do criativo e velocidade', () => {
    const pg = pagina({
      por_criativo: [{ campanha: 'RS | PB26 | LEADS | X | AK1', criativo: '1202', entradas: 300, rejeicoes: 210, leads: 10 }],
      lcp: [{ faixa: 'bom', entradas: 500, rejeicoes: 150, leads: 60 }, { faixa: 'ruim', entradas: 200, rejeicoes: 120, leads: 10 }],
    });
    const t = tipos(analisar(base([pg]), null, 'p'));
    expect(t).toContain('promessa');
    expect(t).toContain('velocidade');
  });
  it('promessa do criativo no formato nome|id (gp-operacoes): título com o nome, dica com nome e id', () => {
    const pg = pagina({
      por_criativo: [{ campanha: 'RS | PB26 | LEADS | X | AK1', criativo: 'CRIATIVO VÍDEO 01', criativo_id: '120200000000000001', entradas: 300, rejeicoes: 210, leads: 10 }],
    });
    const p = analisar(base([pg]), null, 'p').oportunidades.find((x) => x.tipo === 'promessa');
    expect(p?.titulo).toContain('“CRIATIVO VÍDEO 01”');
    expect(p?.dica).toBe('Anúncio (utm_content): CRIATIVO VÍDEO 01 · 120200000000000001; campanha: RS | PB26 | LEADS | X | AK1');
  });
  it('botão que ninguém vê (régua de 60%) e fricção', () => {
    const l = leitura({
      primeiro_cta: [{ dispositivo: 'mobile', medidas: 500, viram: 200, ficaram: 300, ficaram_sem_ver: 150, leads_de_quem_viu: 30 }],
      ctas: [{ cta: 'topo', ordem: 1, medidas: 500, viram: 200, clicaram: 50, leads: 20 }],
    });
    const pg = pagina({ friccao: { com_raiva: 60, com_erro: 10, com_friccao: 70, friccao_leads: 2, sem_friccao: 500, sem_leads: 90 } });
    const r = analisar(base([pg], [l]), null, 'p');
    expect(r.oportunidades.find((x) => x.tipo === 'botao')?.titulo).toContain('40%');
    expect(tipos(r)).toContain('friccao');
  });
  it('seção onde a leitura morre e formulário', () => {
    const s = (secao: string, ordem: number, chegaram: number, viram_lead: number) => ({ secao, ordem, viram: chegaram, chegaram, viram_lead, viram_mql: 0 });
    const l = leitura({
      secoes: [s('topo', 1, 1000, 100), s('padrao', 2, 900, 95), s('caminho', 3, 810, 90), s('especialistas', 4, 300, 70), s('faq', 5, 270, 60)],
      form: { viram: 500, abriram: 300, comecaram: 200, enviaram: 100, campos: [
        { campo: 'nome', ordem: 1, tocaram: 200, focaram: 200, com_erro: 0, pararam: 10 },
        { campo: 'telefone', ordem: 2, tocaram: 180, focaram: 180, com_erro: 40, pararam: 70 }] },
    });
    const r = analisar(base([pagina()], [l]), null, 'p');
    const sec = r.oportunidades.find((x) => x.tipo === 'secao')!;
    expect(sec.titulo).toContain('“O outro caminho”');
    const f = r.oportunidades.find((x) => x.tipo === 'formulario')!;
    expect(f.titulo).toContain('“telefone”');
    expect(f.numeros).toContain('erro de validação em 40');
  });
  it('aprendizados: o que o MQL lê e qual botão converte', () => {
    const l = leitura({
      medidas_lead: 100, medidas_mql: 40,
      secoes: [{ secao: 'topo', ordem: 1, viram: 1000, chegaram: 1000, viram_lead: 100, viram_mql: 40 },
        { secao: 'especialistas', ordem: 2, viram: 400, chegaram: 400, viram_lead: 50, viram_mql: 36 }],
      ctas: [{ cta: 'topo', ordem: 1, medidas: 1000, viram: 600, clicaram: 100, leads: 40 }, { cta: 'final', ordem: 2, medidas: 1000, viram: 200, clicaram: 30, leads: 10 }],
      leads_com_botao: 50,
    });
    const r = analisar(base([pagina()], [l]), null, 'p');
    expect(r.aprendizados.map((a) => a.tipo).sort()).toEqual(['botao_converte', 'mql_le']);
    expect(r.aprendizados.find((a) => a.tipo === 'botao_converte')?.titulo).toContain('80% dos leads clicam no primeiro botão');
  });
  it('ordem: fracos no fim, maior ganho primeiro; texto do ganho', () => {
    const a = (confianca: Achado['confianca'], ganho: number) => ({ confianca, ganho }) as Achado;
    expect([a('fraco', 9), a('forte', 1), a('provavel', 5)].sort(ordemDosAchados).map((x) => x.ganho)).toEqual([5, 1, 9]);
    expect(textoGanho(0.01)).toBe('');
    expect(textoGanho(3.24)).toBe('até 3,2');
  });
});
