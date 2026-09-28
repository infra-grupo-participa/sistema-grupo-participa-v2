// Recebimentos informados em HTML estático (renderToStaticMarkup, sem navegador). Prova conteúdo e o que NÃO sai no
// HTML (identificador em claro, botões de escrita sem permissão). Clique, carga ao abrir e recarga após gravar não se
// provam aqui: não há ambiente de DOM no projeto.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { ColarDaPlanilha, Informados, type RepoInformados } from './Informados';
import { ContasAReceber } from './ContasAReceber';
import { Recorrencias } from './Recorrencias';
import { montarContasReceber } from '../../application/carregar-contas-receber';
import type { LinhaReceber } from '../../domain/contas-receber';
import { lerColagem, normalizarInformado } from '../../domain/recebimentos-informados';

const repoEspiao = (): RepoInformados => ({
  loadInformados: vi.fn(async () => []),
  salvarInformado: vi.fn(async () => ({ ok: true })),
  baixarInformado: vi.fn(async () => ({ ok: true })),
  arquivarInformado: vi.fn(async () => ({ ok: true })),
  importarInformados: vi.fn(async () => ({ ok: true, linhas: [] })),
});

const I = (p: Record<string, unknown>) => normalizarInformado({
  id: 'u', data_prevista: '2026-10-05', cliente: 'Cliente', tipo: 'renovacao_diamante', valor: 1000, via_hotmart: false,
  produtos: [], situacao: 'a_receber', ...p,
});
const lista = [
  I({ id: 'a', cliente: 'Cliente A', valor: 18750, via_hotmart: true, produtos: ['Serviço Diamante'], identificador1: '···7735',
    identificador2: 'u***@example.com', recebido_hotmart: 9000, acumulado_acordo: 18750 }),
  I({ id: 'b', cliente: 'Cliente B', tipo: 'renovacao_aurum', situacao: 'em_atraso_cobrar', data_prevista: '2026-09-01' }),
  I({ id: 'c', cliente: 'Cliente C', situacao: 'baixado_fora', baixa_manual_em: '2026-09-20' }),
  I({ id: 'd', cliente: 'Cliente D', situacao: 'arquivado', motivo_arquivo: 'Duplicado na planilha' }),
  I({ id: 'e', cliente: 'Cliente E', situacao: 'realizado_hotmart', via_hotmart: true, produtos: ['Aurum'] }),
];

describe('Informados — sub-seção', () => {
  it('fechada: nenhuma chamada ao banco no render, e a lista não aparece', () => {
    const repo = repoEspiao();
    const html = renderToStaticMarkup(createElement(Informados, { repo, canEdit: true, canVerDoc: false }));
    expect(html).toContain('Recebimentos informados');
    expect(html).toContain('aria-expanded="false"');
    expect(html).not.toContain('Cliente');
    expect(repo.loadInformados).not.toHaveBeenCalled();
  });

  it('aberta: situações com rótulo próprio, arquivado fora do "todos", identificador como veio (mascarado)', () => {
    const html = renderToStaticMarkup(createElement(Informados, { repo: repoEspiao(), canEdit: true, canVerDoc: false, inicial: lista }));
    for (const r of ['A receber', 'Realizado na Hotmart', 'Baixado fora', 'Em atraso — cobrar', 'Arquivado']) expect(html).toContain(r);
    expect(html).toContain('Todos (sem arquivados) <span class="tabular">4</span>');
    expect(html).not.toContain('Cliente D'); // arquivado só no filtro próprio
    expect(html).toContain('···7735');
    expect(html).toContain('u***@example.com');
    expect(html).toMatch(/R\$\s9\.000,00 \/ R\$\s18\.750,00/);
    expect(html).not.toContain('— / —'); // via Hotmart sem número do banco: um traço só
    expect(html).toContain('Renovação Aurum');
    // ordem por data prevista: B (01/09) antes de A (05/10)
    expect(html.indexOf('Cliente B')).toBeLessThan(html.indexOf('Cliente A'));
    expect(html).toContain('Desfazer baixa'); // C tem baixa manual
    expect(html).toContain('>Baixar<');
    expect(html).toContain('Colar da planilha');
    expect(html).not.toMatch(/devendo|carteira/i);
  });

  it('sem permissão de operar: nenhum botão de escrita, aviso de somente leitura', () => {
    const html = renderToStaticMarkup(createElement(Informados, { repo: repoEspiao(), canEdit: false, canVerDoc: false, inicial: lista }));
    for (const b of ['>Editar<', '>Baixar<', 'Desfazer baixa', '>Arquivar<', 'Colar da planilha', '>Novo<']) expect(html).not.toContain(b);
    expect(html).toContain('Somente leitura');
  });

  it('dentro da aba: aparece com repo; sem repo, não', () => {
    const d = montarContasReceber([], '2026-09-28');
    expect(renderToStaticMarkup(createElement(ContasAReceber, { dados: d, repo: repoEspiao(), canEdit: true, canVerDoc: false })))
      .toContain('informados-titulo');
    expect(renderToStaticMarkup(createElement(ContasAReceber, { dados: d }))).not.toContain('informados-titulo');
  });
});

describe('Colar da planilha — prévia', () => {
  const CPF = '111.444.777-35';
  const ok = `05/10/2026\tCliente Um\tRenovação Diamante\tR$ 18.750,00\tS\tServiço Diamante\t${CPF}\tum@example.com\t01/09/2026\t`;
  it('erro de formato: linha a linha, sem ir ao banco, gravar desligado; CPF/e-mail colados não reaparecem em claro', () => {
    const colagem = lerColagem(`${ok}\n31/02/2026\tX\tConsultoria\tR$ 1,00\tN\t\t\t\t\t`);
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, { repo: repoEspiao(), onGravado: () => {}, inicial: { colagem, previa: null } }));
    expect(html).toContain('Data prevista inválida');
    expect(html).toContain('Tipo não reconhecido');
    expect(html).toContain('Corrija na planilha e cole de novo');
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Gravar 2 linhas<\/button>/);
    expect(html).not.toContain(CPF);
    expect(html).not.toContain('um@example.com');
    expect(html).toContain('···7735 · u***@example.com');
  });
  it('banco conferiu tudo ok: "Gravar N linhas" liberado', () => {
    const colagem = lerColagem(ok);
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, {
      repo: repoEspiao(), onGravado: () => {}, inicial: { colagem, previa: [{ linha: 1, ok: true, erro: null, id: null }] },
    }));
    expect(html).toMatch(/<button[^>]*>Gravar 1 linha<\/button>/);
    expect(html).not.toMatch(/<button[^>]*disabled=""[^>]*>Gravar 1 linha/);
    expect(html).toContain('>OK<');
  });
  it('banco recusou uma linha: erro do SQL na linha e gravar desligado', () => {
    const colagem = lerColagem(`${ok}\n${ok}`);
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, {
      repo: repoEspiao(), onGravado: () => {},
      inicial: { colagem, previa: [{ linha: 1, ok: true, erro: null, id: null }, { linha: 2, ok: false, erro: 'Linha duplicada.', id: null }] },
    }));
    expect(html).toContain('Linha duplicada.');
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Gravar 2 linhas<\/button>/);
  });
});

describe('bloco 5 na grade e coberta_informado nas Recorrências', () => {
  const L = (p: Partial<LinhaReceber>): LinhaReceber => ({
    bloco: 5, grupo: 'Renovações Diamante', componente: 'cheio', data_caixa: '2026-10-05', valor: 0,
    situacao: 'a_receber', origem_dia: null, ref: 'u', rotulo: 'Cliente A', produto: null, k: null, detalhe: [], ...p,
  });
  it('bloco 5 com nome próprio e grupos do contrato; coberta não soma e aparece com rótulo', () => {
    const d = montarContasReceber([
      L({ valor: 18750 }), L({ grupo: 'Renovações Aurum', valor: 9000 }),
      L({ bloco: 2, grupo: 'Parcelas a vencer Aurum', ref: 'x|1', rotulo: 'Cliente B', origem_dia: '2026-10-10', data_caixa: '2026-10-12',
        valor: 4000, componente: 'antecipacao', situacao: 'coberta_informado' }),
    ], '2026-09-28');
    expect(d.grade.total).toBe(27750);
    const html = renderToStaticMarkup(createElement(ContasAReceber, { dados: d }));
    expect(html).toContain('5. Recebimentos informados');
    expect(html.indexOf('Renovações Diamante')).toBeLessThan(html.indexOf('Renovações Aurum'));
    const rec = renderToStaticMarkup(createElement(Recorrencias, { cobrancas: d.recorrencias }));
    expect(rec).toContain('Coberta por recebimento informado');
  });
});
