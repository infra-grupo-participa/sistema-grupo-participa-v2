// Ofertas a confirmar (z82): renderiza o bloco (HTML estático, sem navegador) e confere a JUNÇÃO
// RPC crua → normalizarOfertaFila → tela. Prova conteúdo, não geometria nem clique.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { FilaOfertasEvento } from './FilaOfertasEvento';
import { normalizarOfertaFila, type OfertaFila } from '../../domain/fila-ofertas';

// Linhas como fn_fin_fila_ofertas devolve (bigint e datas em texto).
const cru: Record<string, unknown>[] = [
  { oferta_codigo: 'k9x2abcd', oferta_nome: '2º Encontro — lote 1', produto_id: '123', produto_nome: 'Encontro do THB', n_vendas: 37,
    primeira_venda: '2026-09-01', ultima_venda: '2026-09-20', sugestao_evento_id: '412', sugestao_evento: '2º Encontro do THB',
    proposta_evento: null, sinais: { n_com_sck: 0 }, criado_em: '2026-09-29T10:00:00+00:00' },
  { oferta_codigo: 'zz77semnome', oferta_nome: null, produto_id: '999', produto_nome: 'Clínica POA', n_vendas: 4,
    primeira_venda: '2026-09-10', ultima_venda: '2026-09-10', sugestao_evento_id: null, sugestao_evento: null,
    proposta_evento: { nome: 'Clínica POA', categoria: 'clinica', carrinho_inicio: '2026-09-10', venda_ate: '2026-09-25' },
    sinais: {}, criado_em: '2026-09-29T10:00:00+00:00' },
];

function render(inicial: OfertaFila[]) {
  const repo = { carregarFilaOfertas: vi.fn(), decidirOferta: vi.fn() };
  const html = renderToStaticMarkup(createElement(FilaOfertasEvento, { repo, inicial, candidatos: null, erroCandidatos: null }));
  return { html, repo };
}

describe('FilaOfertasEvento — junção RPC → tela', () => {
  const itens = cru.map(normalizarOfertaFila);

  it('lista renderiza com N no título, produto, vendas e período', () => {
    const { html, repo } = render(itens);
    expect(html).toContain('Ofertas a confirmar (2)');
    expect(html).toContain('2º Encontro — lote 1');
    expect(html).toContain('Encontro do THB');
    expect(html).toContain('>37<');
    expect(html).toContain('01/09/2026 a 20/09/2026');
    expect(html).toContain('>10/09/2026<'); // 1ª = última: uma data só
    expect(repo.carregarFilaOfertas).not.toHaveBeenCalled(); // `inicial` = nenhuma chamada
    expect(repo.decidirOferta).not.toHaveBeenCalled();
  });

  it('sugestão aparece como evento sugerido e no botão "Confirmar em …"; sem sugestão, sem esse botão', () => {
    const { html } = render(itens);
    expect(html).toContain('Confirmar em 2º Encontro do THB');
    expect(html.match(/Confirmar em /g)).toHaveLength(1);
    expect(html).toContain('sem sugestão');
  });

  it('as outras 3 ações existem em toda linha; sem nome da oferta mostra o código', () => {
    const { html } = render(itens);
    expect(html.match(/Outro evento…/g)).toHaveLength(2);
    expect(html.match(/>Criar evento</g)).toHaveLength(2);
    expect(html.match(/>Não é de evento</g)).toHaveLength(2);
    expect(html).toContain('zz77semnome');
  });

  it('N = 0 esconde o bloco inteiro', () => {
    expect(render([]).html).toBe('');
  });

  it('sem jargão técnico na tela', () => {
    const { html } = render(itens);
    for (const j of ['oferta_codigo', 'resolvedor', 'sck', 'sinais', 'proposta']) expect(html).not.toContain(j);
  });
});
