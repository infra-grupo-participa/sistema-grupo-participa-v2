// Telas da fase 2 do Tráfego (20261006i) renderizadas em HTML estático com os dados do modo de demonstração (fictícios).
// Prova conteúdo, não geometria.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { demoAlertas, demoClickup, demoProjeto } from '../infrastructure/demo';
import { ClickupVista } from './ClickupPainel';
import { ResumoDiaVista } from './ResumoDia';

const html = (el: Parameters<typeof renderToStaticMarkup>[0]) => renderToStaticMarkup(el).replace(/ /g, ' ');

describe('resumo do dia na Central (demonstração)', () => {
  it('mostra os alertas com a sigla e a frase, sem travessão', () => {
    const r = demoAlertas();
    expect(r.alertas.length).toBeGreaterThan(0);
    const h = html(createElement(ResumoDiaVista, { r, onAbrir: () => {} }));
    expect(h).toContain('o que está pegando fogo');
    expect(h).toContain(r.alertas[0].sigla ?? 'Sem projeto');
    expect(h).toContain('Ver as regras e os limiares');
    expect(h).toContain('Meta Ads desligada (nunca rodou)');
    expect(h).not.toMatch(/[—–]/);
  });
  it('sem alerta e sem a migration', () => {
    const vazio = { ...demoAlertas(), alertas: [], sem_coleta: true, base_pessoas: false };
    const h = html(createElement(ResumoDiaVista, { r: vazio, onAbrir: () => {} }));
    expect(h).toContain('Nada pegando fogo ontem');
    expect(h).toContain('Ainda não há gasto coletado');
    expect(h).toContain('meta de leads e CPL não são avaliados');
    expect(html(createElement(ResumoDiaVista, { r: null, onAbrir: () => {} }))).toContain('20261006i ainda não foi aplicada');
  });
});

describe('ClickUp na vida do projeto (demonstração)', () => {
  const vida = demoProjeto(1)!;
  it('linha do tempo com o gasto e as atividades, e a lista', () => {
    const h = html(createElement(ClickupVista, { dados: demoClickup(1), serie: vida.serie, ate: vida.resumo.dia_ontem }));
    expect(h).toContain('seminario-conjunto-2026-11');
    expect(h).toContain('Exemplo: subir campanhas de captação');
    expect(h).toContain('Barras: gasto do dia');
    expect(h).not.toMatch(/[—–]/);
  });
  it('projeto sem etiqueta e sem a migration', () => {
    expect(html(createElement(ClickupVista, { dados: demoClickup(2), serie: [], ate: '2026-10-04' }))).toContain('não tem etiqueta do ClickUp');
    expect(html(createElement(ClickupVista, { dados: null, serie: [], ate: '2026-10-04' }))).toContain('20261006i ainda não foi aplicada');
  });
});
