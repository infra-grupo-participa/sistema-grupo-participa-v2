// Escritório › Contratos em HTML estático (renderToStaticMarkup, sem navegador). Prova conteúdo, escape do texto do
// cliente, link só como <a> quando seguro, e o que NÃO sai no HTML (botões sem permissão, ações na baixa pela Hotmart).
// Clique, geometria da grade larga e do drawer NÃO se provam aqui: ficam para o Playwright (e2e/financeiro-contratos-hf).
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { ContratosEscritorio, FichaContrato, type AcoesParcela, type RepoContratosEscrita } from './ContratosEscritorio';
import { subAbasVisiveis } from './EscritorioAba';
import type { CacheContratosHF } from '../../application/carregar-contratos-hf';
import {
  montarGradeContratos, normalizarLinhaMensal, normalizarPagamento, type LinhaMensalContratoHF, type PagamentoContratoHF,
} from '../../domain/contratos-hf';

const L = (p: Record<string, unknown>): LinhaMensalContratoHF => normalizarLinhaMensal({
  contrato_id: 'c1', mes: '2026-09-01', nome: 'Ana', email: 'ana@example.com', origem: 'planilha_drive', assinado: 'sim',
  data_assinatura: '2026-08-10', valor_bruto: '44640.00', link_contrato: 'https://docs.google.com/document/d/abc/edit',
  esperado: '0', caiu_manual: '0', caiu_hotmart: '0', caiu: '0', parcelas: [], ...p,
});

const linhas = [
  L({ mes: '2026-09-01', esperado: '1000', caiu_hotmart: '1000', caiu: '1000', situacao: 'baixado_fora', parcelas: [
    { id: 'p1', parcela_n: 1, parcela_de: 3, valor: 1000, data_prevista: '2026-09-10', situacao: 'baixado_fora', baixa_manual_em: '2026-09-10', transacao_hotmart: 'HP999' },
  ] }),
  L({ mes: '2026-10-01', esperado: '2000', caiu_manual: '700', caiu: '700', situacao: 'em_atraso_cobrar', parcelas: [
    { id: 'p2', parcela_n: 2, parcela_de: 3, valor: 2000, data_prevista: '2026-10-01', situacao: 'em_atraso_cobrar' },
  ] }),
  L({ mes: null, esperado: null, caiu_manual: null, caiu_hotmart: null, caiu: null, a_receber_etapa: '3000', situacao: 'a_receber_etapa', parcelas: [
    { id: 'p3', parcela_n: 3, parcela_de: 3, valor: 3000, etapa: 'registros', situacao: 'a_receber_etapa' },
  ] }),
  // Texto do cliente malicioso e link fora da regra do banco.
  L({ contrato_id: 'c2', nome: '<img src=x onerror=alert(1)>', link_contrato: 'javascript:alert(1)', mes: '2026-09-01' }),
  L({ contrato_id: 'c2', nome: '<img src=x onerror=alert(1)>', link_contrato: 'javascript:alert(1)', mes: '2026-10-01' }),
];

const pag = (p: Record<string, unknown>): PagamentoContratoHF => normalizarPagamento({
  transacao: 'HP1', dia: '2026-09-20', valor: '500', nome_hotmart: 'Carla', email_hotmart: 'carla@example.com',
  situacao: 'fila', motivo: 'valor_nao_bate: nenhuma parcela em aberto com esse valor (tolerância R$ 1,00 ou 1%).',
  sync_ultima_em: '2026-09-29T12:25:00Z', sync_erros: 0, sync_mensagem: null, ...p,
});

const cacheCom = (g: LinhaMensalContratoHF[], p: PagamentoContratoHF[]): CacheContratosHF => ({
  disponibilidade: () => 'sim', sondar: vi.fn(async () => 'sim' as const),
  gradeLida: () => g, grade: vi.fn(async () => g), pagamentosLidos: () => p, pagamentos: vi.fn(async () => p), invalidar: vi.fn(),
});

const repoEspiao = (): RepoContratosEscrita => ({
  salvarContratoHf: vi.fn(async () => ({ ok: true })), concluirEtapaParcela: vi.fn(async () => ({ ok: true })),
  desfundirContratoHf: vi.fn(async () => ({ ok: true })), baixarInformado: vi.fn(async () => ({ ok: true })),
  salvarInformado: vi.fn(async () => ({ ok: true })), importarInformados: vi.fn(async () => ({ ok: true, linhas: [] })),
});

const render = (canEdit: boolean, p: PagamentoContratoHF[] = [pag({}), pag({ transacao: 'HP2', situacao: 'baixou_parcela', motivo: null })]) =>
  renderToStaticMarkup(createElement(ContratosEscritorio, { cache: cacheCom(linhas, p), repo: repoEspiao(), canEdit, canVerDoc: false }));

describe('grade mês a mês', () => {
  it('meses como colunas, esperado × caiu com H (Hotmart) e M (manual), totais', () => {
    const html = render(true);
    expect(html).toContain('>set/26<');
    expect(html).toContain('>out/26<');
    expect(html).toMatch(/text-\[var\(--cyan\)\]">H R\$\s1\.000</);
    expect(html).toMatch(/text-\[var\(--purple\)\]">M R\$\s700</);
    expect(html).toContain('A receber na etapa');
    expect(html).toContain('Total');
    expect(html).toMatch(/R\$\s3\.000<\/td>/); // total da coluna de etapa no rodapé
  });

  it('em atraso: esperado em vermelho; o texto da ficha é escapado; link só vira <a> se passar na regra do banco', () => {
    const html = render(true);
    expect(html).toMatch(/font-semibold text-\[var\(--red\)\]">R\$\s2\.000/);
    expect(html).not.toContain('<img src=x');
    expect(html).toContain('&lt;img src=x onerror=alert(1)&gt;');
    expect(html).toContain('<a href="https://docs.google.com/document/d/abc/edit" target="_blank" rel="noopener noreferrer"');
    expect(html).not.toContain('href="javascript:');
    expect(html).toContain('javascript:alert(1)</span>'); // vira texto
  });

  it('1ª coluna fixa (sticky, fundo opaco) no cabeçalho, em cada linha e no rodapé', () => {
    const html = render(true);
    const fixas = html.match(/sticky left-0 z-\[2\]/g) ?? [];
    expect(fixas.length).toBe(1 + 2 + 1); // th + 2 contratos + total
    expect(html).toMatch(/<td class="[^"]*sticky left-0[^"]*bg-\[var\(--surface-2\)\][^"]*"><button type="button"/);
  });

  it('concluir etapa: só para quem opera', () => {
    expect(render(true)).toContain('Concluir etapa');
    const leitura = render(false);
    expect(leitura).not.toContain('Concluir etapa');
    expect(leitura).toContain('Somente leitura');
  });
});

describe('fila de conferência e sincronização', () => {
  it('só os da fila, com motivo em português (rótulo + frase do banco)', () => {
    const html = render(true);
    expect(html).toContain('Conferência da Hotmart <span class="font-normal text-[var(--fg-3)]">1</span>');
    expect(html).toContain('Valor não bate');
    expect(html).toContain('nenhuma parcela em aberto com esse valor');
    expect(html).toContain('HP1');
    expect(html).not.toContain('HP2');
    expect(html).toContain('Última sincronização com a Hotmart');
  });
  it('sync com erro: faixa de aviso com a mensagem (escapada)', () => {
    const html = render(true, [pag({ sync_erros: 2, sync_mensagem: 'timeout <b>x</b>' })]);
    expect(html).toContain('role="alert"');
    expect(html).toContain('Sincronização com a Hotmart: 2 erros');
    expect(html).toContain('timeout &lt;b&gt;x&lt;/b&gt;');
  });
  it('fila vazia: diz que não há nada; sem pagamento algum: diz que não há sincronização a mostrar', () => {
    expect(render(true, [pag({ situacao: 'baixou_parcela' })])).toContain('Nenhum pagamento da Hotmart esperando conferência.');
    expect(render(true, [])).toContain('Nenhum pagamento de Holding Familiar na Hotmart ainda.');
  });
});

describe('ficha (drawer)', () => {
  const g = montarGradeContratos(linhas);
  const acoes = (canEdit: boolean): AcoesParcela => ({ acao: null, setAcao: vi.fn(), ocupado: false, canEdit, confirmar: vi.fn(), desfazerBaixa: vi.fn() });
  const ficha = (canEdit: boolean, i = 0) => renderToStaticMarkup(createElement(FichaContrato, {
    c: g.contratos[i], repo: repoEspiao(), canEdit, canVerDoc: false, ocupado: false, aviso: null,
    executar: vi.fn(async () => true), acoes: acoes(canEdit), onClose: vi.fn(),
  }));

  it('baixa pela Hotmart: "Baixado pela Hotmart" e NENHUMA ação; parcela aberta: baixar (Pix); etapa: concluir', () => {
    const html = ficha(true);
    expect(html).toContain('Baixado pela Hotmart');
    expect(html).toContain('Baixa automática');
    expect(html).toContain('Baixar (Pix)');
    expect(html).toContain('Concluir etapa');
    expect(html).not.toContain('Desfazer baixa'); // a única baixada é a automática
    expect(html).toContain('Editar ficha');
    expect(html).toContain('Arquivar');
    expect(html).not.toContain('Desfazer fusão'); // ficha sem sinal fundido
  });
  it('sem permissão de operar: nenhum botão de escrita', () => {
    const html = ficha(false);
    for (const b of ['Editar ficha', 'Arquivar', 'Baixar (Pix)', 'Concluir etapa', 'Nova parcela', 'Colar da planilha']) expect(html).not.toContain(b);
  });
  it('texto do cliente escapado no título', () => {
    expect(ficha(true, 1)).toContain('&lt;img src=x onerror=alert(1)&gt;');
  });
});

describe('sub-aba escondida sem a z93', () => {
  it('Contratos só aparece com a sonda confirmando as RPCs', () => {
    expect(subAbasVisiveis('desconhecida')).toEqual(['funil']);
    expect(subAbasVisiveis('nao')).toEqual(['funil']);
    expect(subAbasVisiveis('sim')).toEqual(['funil', 'contratos']);
  });
});
