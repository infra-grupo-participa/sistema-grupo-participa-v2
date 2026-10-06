// Telas da fase 2 do Tráfego (20261006i) renderizadas em HTML estático com os dados do modo de demonstração (fictícios).
// Prova conteúdo, não geometria.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { demoAlertas, demoClickup, demoProjeto, demoReceita, demoResumo } from '../infrastructure/demo';
import { tituloReceita } from './formato';
import { ReceitaNiveis } from './ProdutosHotmart';
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
    expect(html(createElement(ResumoDiaVista, { r: null, onAbrir: () => {} }))).toContain('Não foi possível carregar');
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
    expect(html(createElement(ClickupVista, { dados: null, serie: [], ate: '2026-10-04' }))).toContain('Não foi possível carregar');
  });
});

describe('receita do projeto por nível (decisão do Victor, 06/10/2026; demonstração)', () => {
  it('PB26: quebra por nível, estimada à parte, vendas em disputa e a explicação', () => {
    const resumo = demoResumo().find((l) => l.sigla === 'PB26')!;
    const h = html(createElement(ReceitaNiveis, { resumo, rec: demoReceita(1) }));
    expect(h).toContain('1. Oferta exclusiva (certa)');
    expect(h).toContain('2. SCK com o projeto (certa)');
    expect(h).toContain('3. Lead do projeto (provável)');
    expect(h).toContain('4. Estimada, só produto + período (à parte, não soma)');
    expect(h).toContain('Vendas em disputa (1)');
    expect(h).toContain('LPEXA26, PB26');
    expect(h).toContain('seminario-conjunto-2026-11 ou pb26');
    expect(h).not.toContain('Sem oferta exclusiva, a receita é só estimada');
    expect(h).not.toMatch(/[—–]/);
  });
  it('produto ligado sem oferta exclusiva: o aviso grande', () => {
    const resumo = demoResumo().find((l) => l.sigla === 'PB26')!;
    const rec = { ...demoReceita(1)!, sem_oferta_exclusiva: true, ofertas_exclusivas: 0, disputas: [], disputas_total: 0 };
    const h = html(createElement(ReceitaNiveis, { resumo, rec }));
    expect(h).toContain('Sem oferta exclusiva, a receita é só estimada');
    expect(h).toContain('criar na Hotmart uma oferta');
  });
  it('tooltip da coluna Receita da Central com a quebra', () => {
    const t = tituloReceita(demoResumo().find((l) => l.sigla === 'PB26')!);
    expect(t.split('\n')[0]).toBe('Receita do projeto = níveis 1 a 3.');
    expect(t).toContain('Em disputa com outro projeto (não somam): 1 venda(s)');
  });
});
