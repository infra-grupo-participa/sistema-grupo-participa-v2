// Telas da 20261006a renderizadas em HTML estático com os dados do modo de demonstração (fictícios). Prova conteúdo.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { demoChecklist, demoConfig, demoListasCadastro } from '../infrastructure/demo';
import { ChecklistVista, GeradorCampanha } from './MontagemProjeto';

const html = (el: Parameters<typeof renderToStaticMarkup>[0]) => renderToStaticMarkup(el).replace(/ /g, ' ');

describe('checklist de montagem e gerador (demonstração)', () => {
  it('checklist com o progresso, os automáticos e o manual do SendFlow, sem travessão', () => {
    const h = html(createElement(ChecklistVista, { c: demoChecklist(7), onMarcar: () => {} }));
    expect(h).toMatch(/\d+ de \d+ prontos/);
    expect(h).toContain('Contas de anúncio vinculadas');
    expect(h).toContain('Automação de ingresso no grupo do WhatsApp configurada no SendFlow');
    expect(h).not.toMatch(/[—–]/);
    expect(html(createElement(ChecklistVista, { c: null }))).toContain('20261006a ainda não foi aplicada');
  });
  it('gerador mostra a linha de UTM do Meta com as macros', () => {
    const h = html(createElement(GeradorCampanha, { sigla: 'LPEXA26', listas: demoListasCadastro(), config: demoConfig(), paginas: [], gestoresProjeto: ['RS'] }));
    expect(h).toContain('utm_source=metaads&amp;utm_campaign={{campaign.name}}|{{campaign.id}}');
    expect(h).toContain('{{placement}}');
    expect(h).not.toMatch(/[—–]/);
  });
});
