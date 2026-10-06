// Telas da 20261006j renderizadas em HTML estático com os dados do modo de demonstração (fictícios). Prova conteúdo.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { demoChecklist, demoConfig, demoListasCadastro, demoModelos, demoPrevias } from '../infrastructure/demo';
import { TabelaModelos } from './ModelosPainel';
import { ChecklistVista, GeradorCampanha, PreviaVista } from './MontagemProjeto';

const html = (el: Parameters<typeof renderToStaticMarkup>[0]) => renderToStaticMarkup(el).replace(/ /g, ' ');

describe('checklist de montagem e gerador (demonstração)', () => {
  it('checklist com o progresso, os automáticos e o manual do SendFlow, sem travessão', () => {
    const h = html(createElement(ChecklistVista, { c: demoChecklist(7), onMarcar: () => {} }));
    expect(h).toMatch(/\d+ de \d+ prontos/);
    expect(h).toContain('Contas de anúncio vinculadas');
    expect(h).toContain('Automação de ingresso no grupo do WhatsApp configurada no SendFlow');
    expect(h).not.toMatch(/[—–]/);
    expect(html(createElement(ChecklistVista, { c: null }))).toContain('20261006j ainda não foi aplicada');
  });
  it('gerador mostra a linha de UTM do Meta com as macros', () => {
    const h = html(createElement(GeradorCampanha, { sigla: 'LPEXA26', listas: demoListasCadastro(), config: demoConfig(), paginas: [], gestoresProjeto: ['RS'] }));
    expect(h).toContain('utm_source=metaads&amp;utm_campaign={{campaign.name}}|{{campaign.id}}');
    expect(h).toContain('{{placement}}');
    expect(h).not.toMatch(/[—–]/);
  });
  it('checklist agrupado por momento e com o caminho para resolver', () => {
    const h = html(createElement(ChecklistVista, { c: demoChecklist(7), onMarcar: () => {}, onAcao: () => {}, onNovoItem: () => {} }));
    expect(h).toContain('Antes de subir as campanhas');
    expect(h).toContain('Encerramento');
    expect(h).toContain('Cadastrar páginas');
    expect(h).toContain('Campanhas esperadas');
    expect(h).toContain('(do modelo)');
  });
  it('modelos: tabela com o selo de rascunho e o padrão; prévia com fases, campanhas e checklist', () => {
    const h = html(createElement(TabelaModelos, { modelos: demoModelos(), listas: demoListasCadastro(), config: demoConfig(), onEditar: () => {}, onDuplicar: () => {}, onAtivar: () => {} }));
    expect(h).toContain('Exemplo: Palestra Aurum');
    expect(h).toContain('Rascunho a validar');
    expect(h).toContain('Duplicar');
    expect(h).not.toMatch(/[—–]/);
    const p = html(createElement(PreviaVista, { p: demoPrevias(7)![0] }));
    expect(p).toContain('Campanhas esperadas');
    expect(p).toContain('Rascunho a validar');
    expect(p).not.toMatch(/[—–]/);
  });
});
