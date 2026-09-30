// Recebimentos informados em HTML estático (renderToStaticMarkup, sem navegador). Prova conteúdo e o que NÃO sai no
// HTML (identificador em claro, botões de escrita sem permissão). Clique, carga ao abrir e recarga após gravar não se
// provam aqui: não há ambiente de DOM no projeto.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { ColarDaPlanilha, FormularioInformado, Informados, type RepoInformados } from './Informados';
import { ContasAReceber } from './ContasAReceber';
import { Recorrencias } from './Recorrencias';
import { montarContasReceber } from '../../application/carregar-contas-receber';
import type { LinhaReceber } from '../../domain/contas-receber';
import { formDeInformado, lerColagem, normalizarInformado } from '../../domain/recebimentos-informados';

const VE = { podeVerDoc: true };

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
  it('sem acordeão (a sub-aba já é o conteúdo): título simples e "carregando"; o render não consulta (carga no efeito)', () => {
    const repo = repoEspiao();
    const html = renderToStaticMarkup(createElement(Informados, { repo, canEdit: true, canVerDoc: false }));
    expect(html).toContain('<h2 id="informados-titulo" class="text-sm font-semibold text-[var(--fg)]">Recebimentos informados</h2>');
    expect(html).not.toContain('aria-expanded="false"');
    expect(html).not.toMatch(/[▸▾]/);
    expect(html).toContain('Carregando recebimentos informados');
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

  it('recebido_hotmart NULL (quem não vê CPF, z63): "— / acumulado", não some nem vira zero', () => {
    const html = renderToStaticMarkup(createElement(Informados, {
      repo: repoEspiao(), canEdit: false, canVerDoc: false,
      inicial: [I({ id: 'f', cliente: 'Cliente F', via_hotmart: true, produtos: ['Aurum'], recebido_hotmart: null, acumulado_acordo: 18750 })],
    }));
    expect(html).toMatch(/>— \/ R\$\s18\.750,00</);
    expect(html).not.toMatch(/R\$\s0,00 \/ R\$\s18\.750,00/);
  });

  it('sem permissão de operar: nenhum botão de escrita, aviso de somente leitura', () => {
    const html = renderToStaticMarkup(createElement(Informados, { repo: repoEspiao(), canEdit: false, canVerDoc: false, inicial: lista }));
    for (const b of ['>Editar<', '>Baixar<', 'Desfazer baixa', '>Arquivar<', 'Colar da planilha', '>Novo<']) expect(html).not.toContain(b);
    expect(html).toContain('Somente leitura');
  });

  it('z93: linha com transacao_hotmart = "Baixado pela Hotmart", filtro próprio e NENHUM botão (o banco recusa com P0001)', () => {
    const auto = I({ id: 'h', cliente: 'Cliente H', tipo: 'contrato_holding_familiar', situacao: 'baixado_fora',
      baixa_manual_em: '2026-09-20', transacao_hotmart: 'HP123', contrato_id: 'c1' });
    const html = renderToStaticMarkup(createElement(Informados, { repo: repoEspiao(), canEdit: true, canVerDoc: false, inicial: [auto] }));
    expect(html).toContain('Baixado pela Hotmart');
    expect(html).toContain('Baixado pela Hotmart <span class="tabular">1</span>');
    expect(html).toContain('Baixado fora <span class="tabular">0</span>');
    expect(html).toContain('Baixa automática');
    for (const b of ['>Editar<', 'Desfazer baixa', '>Arquivar<', '>Baixar<']) expect(html).not.toContain(b);
    // Baixa manual (sem transacao_hotmart) continua com as ações e o rótulo "Baixado fora".
    const manual = renderToStaticMarkup(createElement(Informados, { repo: repoEspiao(), canEdit: true, canVerDoc: false, inicial: [
      I({ id: 'm', cliente: 'Cliente M', situacao: 'baixado_fora', baixa_manual_em: '2026-09-20' })] }));
    expect(manual).toContain('Desfazer baixa');
    expect(manual).toContain('>Editar<');
    expect(manual).not.toContain('Baixa automática');
  });

  it('z93: observacao (nome colado diferente do da ficha) aparece sob o cliente, escapada', () => {
    const html = renderToStaticMarkup(createElement(Informados, { repo: repoEspiao(), canEdit: false, canVerDoc: false, inicial: [
      I({ id: 'o', cliente: 'João da Silva', tipo: 'contrato_holding_familiar', contrato_id: 'c1', observacao: 'cliente informado na colagem: <b>Maria</b>' })] }));
    expect(html).toContain('cliente informado na colagem: &lt;b&gt;Maria&lt;/b&gt;');
  });

  it('dentro da sub-aba "Recebimentos informados": aparece com repo; sem repo, não', () => {
    const d = montarContasReceber([], '2026-09-28');
    expect(renderToStaticMarkup(createElement(ContasAReceber, { dados: d, repo: repoEspiao(), canEdit: true, canVerDoc: false, sub: 'informados' })))
      .toContain('informados-titulo');
    expect(renderToStaticMarkup(createElement(ContasAReceber, { dados: d, sub: 'informados' }))).not.toContain('informados-titulo');
  });
});

describe('Colar da planilha — prévia', () => {
  const CPF = '111.444.777-35';
  const ok = `05/10/2026\tCliente Um\tRenovação Diamante\tR$ 18.750,00\tS\tServiço Diamante\t${CPF}\tum@example.com\t01/09/2026\t`;
  it('erro de formato: linha a linha, sem ir ao banco, gravar desligado; CPF/e-mail colados não reaparecem em claro', () => {
    const colagem = lerColagem(`${ok}\n31/02/2026\tX\tConsultoria\tR$ 1,00\tN\t\t\t\t\t`, VE);
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, { repo: repoEspiao(), canVerDoc: true, onGravado: () => {}, inicial: { colagem, previa: null } }));
    expect(html).toContain('Data prevista inválida');
    expect(html).toContain('Tipo não reconhecido');
    expect(html).toContain('Corrija na planilha e cole de novo');
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Gravar 2 linhas<\/button>/);
    expect(html).not.toContain(CPF);
    expect(html).not.toContain('um@example.com');
    expect(html).toContain('···7735 · u***@example.com');
  });
  it('banco conferiu tudo ok: "Gravar N linhas" liberado', () => {
    const colagem = lerColagem(ok, VE);
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, {
      repo: repoEspiao(), canVerDoc: true, onGravado: () => {}, inicial: { colagem, previa: [{ linha: 1, ok: true, erro: null, id: null }] },
    }));
    expect(html).toMatch(/<button[^>]*>Gravar 1 linha<\/button>/);
    expect(html).not.toMatch(/<button[^>]*disabled=""[^>]*>Gravar 1 linha/);
    expect(html).toContain('>OK<');
  });
  it('banco recusou uma linha: erro do SQL na linha e gravar desligado', () => {
    const colagem = lerColagem(`${ok}\n${ok}`, VE);
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, {
      repo: repoEspiao(), canVerDoc: true, onGravado: () => {},
      inicial: { colagem, previa: [{ linha: 1, ok: true, erro: null, id: null }, { linha: 2, ok: false, erro: 'Linha duplicada.', id: null }] },
    }));
    expect(html).toContain('Linha duplicada.');
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Gravar 2 linhas<\/button>/);
  });
  it('sem permissão de ver CPF: aviso visível; linha com CPF/e-mail é erro local, sem ir ao banco; gravar desligado', () => {
    const semId = '20/10/2026\tCliente Dois\tRenovação Aurum\tR$ 9.000,00\tN\t\t\t\t\t';
    const colagem = lerColagem(`${ok}\n${semId}`, { podeVerDoc: false });
    const repo = repoEspiao();
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, { repo, canVerDoc: false, onGravado: () => {}, inicial: { colagem, previa: null } }));
    expect(html).toContain('Sem permissão para ver CPF: deixe Identificador 1 e 2 vazios');
    expect(html).toContain('Sem permissão para informar CPF/e-mail.');
    expect(html).toContain('Corrija na planilha e cole de novo. Nada foi enviado ao banco.');
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Gravar 2 linhas<\/button>/);
    expect(html).not.toContain(CPF);
    expect(html).not.toContain('um@example.com');
    expect(repo.importarInformados).not.toHaveBeenCalled();
  });
  it('quem vê CPF: sem o aviso de permissão', () => {
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, { repo: repoEspiao(), canVerDoc: true, onGravado: () => {} }));
    expect(html).not.toContain('Sem permissão para ver CPF');
  });
});

describe('Formulário — tipoFixo (parcela nova na ficha do contrato HF)', () => {
  const html = (tipoFixo?: boolean) => renderToStaticMarkup(createElement(FormularioInformado, {
    form: { original: null, valores: { ...formDeInformado(null, false), tipo: 'contrato_holding_familiar' }, erros: [] },
    canVerDoc: false, ocupado: false, onMudar: () => {}, onSalvar: () => {}, onCancelar: () => {}, tipoFixo,
  }));
  it('padrão (sem a prop): seletor de tipo aparece, como hoje', () => {
    expect(html()).toContain('<span>Tipo</span>');
    expect(html()).toContain('Renovação Aurum');
    expect(html(false)).toContain('Renovação Aurum');
  });
  it('tipoFixo: sem seletor de tipo; campos do contrato seguem (parcela, assinado)', () => {
    const h = html(true);
    expect(h).not.toContain('Renovação Aurum');
    expect(h).not.toContain('<span>Tipo</span>');
    expect(h).toContain('Contrato assinado');
  });
});

describe('Formulário — identificador conforme gp_pode_ver_cpf', () => {
  const orig = I({ id: 'a', via_hotmart: true, produtos: ['Aurum'], identificador1: '···7735', identificador2: null });
  const render = (canVerDoc: boolean, original: typeof orig | null) => renderToStaticMarkup(createElement(FormularioInformado, {
    form: { original, valores: formDeInformado(original, canVerDoc), erros: [] }, canVerDoc, ocupado: false,
    onMudar: () => {}, onSalvar: () => {}, onCancelar: () => {},
  }));
  const inputsIdent = (html: string) => html.match(/<input type="text"[^>]*autoComplete="off"[^>]*>/gi) ?? [];
  it('sem permissão: Identificador 1 e 2 desabilitados, com o texto de ajuda; máscara só no placeholder', () => {
    const html = render(false, orig);
    const ids = inputsIdent(html);
    expect(ids).toHaveLength(2);
    for (const i of ids) expect(i).toContain('disabled=""');
    expect(html.split('Só quem pode ver CPF informa CPF/e-mail').length - 1).toBe(2);
    expect(ids[0]).toContain('placeholder="···7735"');
    expect(ids[0]).toContain('value=""');
    expect(render(false, null)).toContain('Só quem pode ver CPF informa CPF/e-mail'); // criação também
  });
  it('com permissão: campos habilitados, ajuda normal', () => {
    const html = render(true, orig);
    for (const i of inputsIdent(html)) expect(i).not.toContain('disabled');
    expect(html).not.toContain('Só quem pode ver CPF');
    expect(html).toContain('CPF, CNPJ ou e-mail do pagador');
  });
});

describe('bloco 5 na grade e coberta_informado nas Recorrências', () => {
  const L = (p: Partial<LinhaReceber>): LinhaReceber => ({
    bloco: 5, grupo: 'Renovações Diamante', componente: 'cheio', data_caixa: '2026-10-05', valor: 0,
    situacao: 'a_receber', origem_dia: null, ref: 'u', rotulo: 'Cliente A', produto: null, k: null, detalhe: [], projecao: [], pagas: [], fator: 1, certeza: 'certo', centro_custo: null, tratamento: null, cenario: 'base', ...p, valor_bruto: p.valor_bruto ?? p.valor ?? 0,
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
