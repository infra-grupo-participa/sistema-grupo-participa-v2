import { describe, expect, it } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import * as demo from '../infrastructure/demo';
import {
  PainelFormulario, PainelFunil, PainelInstalacao, PainelLeitura, PainelOrigem, PainelPaginas, PainelProblemas, PainelVelocidade, PainelVisao,
  SEM_DADOS,
} from './paineis';
import type { Visao } from '../domain/tipos';

const DE = '2026-09-29';
const ATE = '2026-10-05';
const html = (el: ReturnType<typeof createElement>) => renderToStaticMarkup(el);

describe('telas da Web renderizam com os dados de demonstração', () => {
  it('visão geral: números e uma barra por dia', () => {
    const h = html(createElement(PainelVisao, { v: demo.demoVisao(DE, ATE) }));
    expect(h).toContain('Visitas');
    expect(h).toContain('Leads');
    expect(h.match(/title="\d{2}\/\d{2}: /g)?.length).toBe(7);
  });
  it('páginas, funil, origem, velocidade', () => {
    expect(html(createElement(PainelPaginas, { linhas: demo.demoPaginas(DE, ATE) }))).toContain('patrimoniobrasil.com.br/ak1/');
    const f = html(createElement(PainelFunil, { funis: demo.demoFunil(DE, ATE) }));
    expect(f).toContain('Maior perda do funil');
    expect(f).toContain('Abriu o formulário');
    const o = html(createElement(PainelOrigem, { o: demo.demoOrigem(DE, ATE) }));
    expect(o).toContain('Instagram · Meta Ads');
    expect(o).toContain('Fora do padrão');
    expect(html(createElement(PainelVelocidade, { v: demo.demoVelocidade(DE, ATE) }))).toContain('LCP p75 por dia');
  });
  it('leitura, cliques e erros, formulário, instalação', () => {
    const l = html(createElement(PainelLeitura, { l: demo.demoLeitura() }));
    expect(l).toContain('O caminho padrão');            // apelido da seção "padrao"
    expect(html(createElement(PainelProblemas, { p: demo.demoProblemas() }))).toContain('Script do app do Facebook (Android)');
    expect(html(createElement(PainelFormulario, { f: demo.demoFormulario() }))).toContain('Onde param');
    const i = html(createElement(PainelInstalacao, { i: demo.demoInstalacao(), base: 'https://grupoparticipa.app.br' }));
    expect(i).toContain('https://grupoparticipa.app.br/web/radar-v1.js');
    expect(i).toContain('data-projeto=&quot;PB26&quot;');
  });
});

describe('estado vazio claro antes da virada', () => {
  const vazio: Visao = {
    kpis: { sessoes: 0, visitantes: 0, engajadas: 0, leads: 0, visivel_ms_medio: 0, paginas_por_sessao: 0, com_raiva: 0, com_erro: 0, de_anuncio: 0, resultados: {} },
    serie: [], coleta: { ligada: false, pausada: false, ultimo_pacote: null },
  };
  it('todas as abas dizem "sem dados ainda: a coleta começa na virada"', () => {
    const telas = [
      html(createElement(PainelVisao, { v: vazio })),
      html(createElement(PainelPaginas, { linhas: [] })),
      html(createElement(PainelOrigem, { o: { total: 0, cliques_meta: 0, cliques_google: 0, fontes: [], campanhas: [], anuncios: [], sites: [] } })),
      html(createElement(PainelVelocidade, { v: { paginas: [], serie: [] } })),
      html(createElement(PainelLeitura, { l: { visualizacoes: 0, rolagem: { chegou_25: 0, chegou_50: 0, chegou_75: 0, chegou_100: 0, media: 0, media_30s: null, vaivem_medio: null }, secoes: [], ctas: [], mapa: null } })),
      html(createElement(PainelProblemas, { p: { cliques: 0, raiva: 0, mortos: 0, automaticos: 0, sessoes_com_raiva: 0, top_raiva: [], top_mortos: [], mais_clicados: [], erros: 0, sessoes_com_erro: 0, top_erros: [], erros_fora: [] } })),
      html(createElement(PainelFormulario, { f: { medidas: 0, viram: 0, comecaram: 0, enviaram: 0, tempo_mediano_s: null, campos: [], pararam_em: [] } })),
    ];
    for (const t of telas) expect(t).toContain(SEM_DADOS);
  });
});
