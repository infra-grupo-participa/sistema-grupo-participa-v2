// z73 — Contratos Holding Familiar como bloco 7: seção pela coluna `certeza` (não pelo número do bloco), totais, Base
// auditável/CSV/PDF/Visão geral, e em Recebimentos informados o tipo novo (formulário, filtro por tipo e a colagem da
// planilha "Contratos Soluções"). HTML estático (renderToStaticMarkup, sem navegador): prova conteúdo e soma, não
// geometria nem clique.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { GradeContasReceber } from './ContasAReceber';
import { ColarDaPlanilha, FormularioInformado, Informados, type RepoInformados } from './Informados';
import { csvBaseAuditavel, opcoesBase } from './base-auditavel';
import { rotuloBloco } from './rotulos-receber';
import { montarContasReceber } from '../../application/carregar-contas-receber';
import {
  GRUPO_CONTRATO_ASSINADO, GRUPO_CONTRATO_SEM_ASSINATURA, normalizarLinhaReceber, secaoDaLinha, secaoDoGrupo,
} from '../../domain/contas-receber';
import { alertasReceber, proximas4Semanas, resumirPrevistoRealizado, normalizarPrevistoRealizado } from '../../domain/visao-receber';
import {
  AVISO_ENTRADA, entradaDoFormulario, ERRO_CONTRATO_NA_PLANILHA_INFORMADOS, formDeInformado, lerColagem, lerContratoAssinado,
  lerParcela, lerStatusContrato, lerTipo, normalizarInformado, TIPO_CONTRATO, type Informado,
} from '../../domain/recebimentos-informados';
import { rascunhoReceber } from '../pdf/documentos';

const DIR = '4. Receita de vendas (Direta de clientes)';

// Linhas como o banco devolve (contrato do bloco 7 da z73), pelo mesmo caminho do repositório.
const bruto: Record<string, unknown>[] = [
  { bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29', valor: '100', situacao: 'a_receber',
    certeza: 'certo', centro_custo: '1. Receita de vendas (Hotmart)' },
  { bloco: 7, grupo: GRUPO_CONTRATO_ASSINADO, componente: 'cheio', data_caixa: '2026-10-05', valor: '1000', valor_bruto: '1000',
    fator: '1', situacao: 'a_receber', origem_dia: '2026-10-05', ref: 'uuid-a', rotulo: 'Família Andrade', certeza: 'certo',
    centro_custo: DIR, tratamento: 'Parcela 2 de 5 · contrato assinado · 100%' },
  { bloco: 7, grupo: GRUPO_CONTRATO_SEM_ASSINATURA, componente: 'cheio', data_caixa: '2026-10-06', valor: '400', valor_bruto: '800',
    fator: '0.5', situacao: 'a_receber', origem_dia: '2026-10-06', ref: 'uuid-b', rotulo: 'Família Borges', certeza: 'estimado',
    centro_custo: DIR, tratamento: 'Parcela 1 de 3 · sem contrato assinado · 50%', cenario: 'conservador' },
  { bloco: 7, grupo: GRUPO_CONTRATO_ASSINADO, componente: 'cheio', data_caixa: null, valor: '700', valor_bruto: '700', fator: '1',
    situacao: 'em_atraso_fora', origem_dia: '2026-09-01', ref: 'uuid-c', rotulo: 'Família Costa', certeza: 'certo', centro_custo: DIR,
    tratamento: 'Parcela 4 de 5 · contrato assinado · Em atraso: cobrar (vencido há mais de 5 dias)' },
  { bloco: 7, grupo: GRUPO_CONTRATO_ASSINADO, componente: 'cheio', data_caixa: null, valor: '500', valor_bruto: '500', fator: '1',
    situacao: 'realizada', origem_dia: '2026-09-20', ref: 'uuid-d', rotulo: 'Família Dias', certeza: 'certo', centro_custo: DIR,
    tratamento: 'contrato assinado · Baixado fora da Hotmart' },
];
const linhas = bruto.map(normalizarLinhaReceber);
const dados = montarContasReceber(linhas, '2026-09-28', 'conservador');
const g = dados.grade;

describe('bloco 7 — seção pela coluna certeza', () => {
  it('secaoDaLinha: certeza manda; sem ela, o número do bloco', () => {
    expect(secaoDaLinha({ bloco: 7, certeza: 'estimado' })).toBe('estimado');
    expect(secaoDaLinha({ bloco: 7, certeza: 'certo' })).toBe('certo');
    expect(secaoDaLinha({ bloco: 3, certeza: null })).toBe('estimado');
    expect(secaoDaLinha({ bloco: 8, certeza: 'informativo' })).toBe('certo'); // fora do contrato: cai no bloco
  });
  it('secaoDoGrupo (fotos, sem certeza): bloco 7 pelo grupo; grupo desconhecido do 7 não vira certo', () => {
    expect(secaoDoGrupo(7, GRUPO_CONTRATO_ASSINADO)).toBe('certo');
    expect(secaoDoGrupo(7, GRUPO_CONTRATO_SEM_ASSINATURA)).toBe('estimado');
    expect(secaoDoGrupo(7, 'Outro nome')).toBe('estimado');
    expect(secaoDoGrupo(5, null)).toBe('certo');
  });
  it('grade: os 2 grupos em seções diferentes; subtotal por (bloco, seção); só a_receber soma', () => {
    expect(g.linhas.filter((l) => l.bloco === 7).map((l) => [l.grupo, l.secao, l.total, l.brutoTotal])).toEqual([
      [GRUPO_CONTRATO_ASSINADO, 'certo', 1000, 1000],
      [GRUPO_CONTRATO_SEM_ASSINATURA, 'estimado', 400, 800],
    ]);
    expect(g.blocos.map((b) => [b.bloco, b.secao, b.total])).toEqual([[1, 'certo', 100], [7, 'certo', 1000], [7, 'estimado', 400]]);
    expect(g.certoTotal).toBe(1100);
    expect(g.estimadoTotal).toBe(400);
    expect(g.total).toBe(1500);
    expect(g.brutoTotal).toBe(1900);
  });
  it('HTML da grade: "7. Contratos Holding Familiar" no certo E no estimado, cada um com o seu grupo', () => {
    const html = renderToStaticMarkup(createElement(GradeContasReceber, { grade: g, selecionada: null, onSelecionar: () => {} }));
    const iEst = html.indexOf('Estimado');
    const certo = html.slice(0, iEst);
    const est = html.slice(iEst);
    expect(certo).toContain('7. Contratos Holding Familiar');
    expect(certo).toContain(GRUPO_CONTRATO_ASSINADO);
    expect(certo).not.toContain(GRUPO_CONTRATO_SEM_ASSINATURA);
    expect(est).toContain('7. Contratos Holding Familiar');
    expect(est).toContain(GRUPO_CONTRATO_SEM_ASSINATURA);
    expect(est).toMatch(/bruto R\$\s800,00/); // esperado 400 com o bruto embaixo (fator 50%)
    expect(html).toContain('Subtotal certo');
    expect(html).toContain('Subtotal estimado');
  });
});

describe('bloco 7 — Visão geral, Base auditável, CSV, PDF', () => {
  it('4 semanas: assinado no certo, sem assinatura no estimado', () => {
    const q = proximas4Semanas(linhas, '2026-09-28');
    expect([q.certo, q.estimado, q.total]).toEqual([1100, 400, 1500]);
  });
  it('alertas: contrato em atraso conta em "informados a cobrar"', () => {
    expect(alertasReceber(linhas, dados.recorrencias).informadosACobrar).toEqual({ n: 1, valor: 700 });
  });
  it('previsto × realizado: grupo sem assinatura vai ao estimado previsto; assinado ao certo', () => {
    const pr = resumirPrevistoRealizado([
      { linha: 'semana', semana_de: '2026-10-05', semana_ate: '2026-10-11', foto_em: '2026-10-05T09:11:00Z', bloco: 7,
        grupo: GRUPO_CONTRATO_ASSINADO, previsto: 1000, realizado: 1000 },
      { linha: 'semana', semana_de: '2026-10-05', semana_ate: '2026-10-11', foto_em: '2026-10-05T09:11:00Z', bloco: 7,
        grupo: GRUPO_CONTRATO_SEM_ASSINATURA, previsto: 400, realizado: 0 },
    ].map(normalizarPrevistoRealizado));
    expect(pr.semanas[0]).toMatchObject({ certoPrevisto: 1000, certoRealizado: 1000, estimadoPrevisto: 400 });
  });
  it('Base auditável: filtro de bloco e CSV com "7. Contratos Holding Familiar"; sem dado pessoal troca o cliente', () => {
    expect(rotuloBloco(7)).toBe('Contratos Holding Familiar');
    expect(opcoesBase(linhas).blocos).toEqual([1, 7]);
    const completo = csvBaseAuditavel(linhas, g.semanas, 'completo', 'Conservador');
    expect(completo).toContain('7. Contratos Holding Familiar');
    expect(completo).toContain('Família Andrade');
    const anon = csvBaseAuditavel(linhas, g.semanas, 'sem_dado_pessoal', 'Conservador');
    expect(anon).not.toContain('Família');
    expect(anon).toContain('Pessoa 1');
  });
  it('PDF: coluna por (bloco, seção) — bloco 7 dividido em certo e estimado, somas iguais às da tela', () => {
    const doc = rascunhoReceber(dados);
    const s = doc.secoes.find((x) => x.titulo.startsWith('Semana × bloco'))!;
    const cols = s.colunas.map((c) => [c.chave, c.rotulo]);
    expect(cols).toContainEqual(['b7c', '7. Contratos Holding Familiar (certo)']);
    expect(cols).toContainEqual(['b7e', '7. Contratos Holding Familiar (estimado)']);
    expect(cols).toContainEqual(['b1', '1. Vendas já realizadas']);
    expect(s.total?.b7c).toMatch(/1\.000,00$/);
    expect(s.total?.b7e).toMatch(/400,00$/);
    expect(s.total?.estimado).toMatch(/400,00$/);
  });
});

// ─── Recebimentos informados: tipo Contrato Holding Familiar ───────────────
const CAB = 'Vencimento\tCliente\tParcela\tValor\tStatus\tSituação do contrato';

describe('planilha Contratos Soluções (colagem)', () => {
  it('leitores: parcela "1 de 5", status, situação, tipo', () => {
    expect(lerParcela('1 de 5')).toEqual({ n: 1, de: 5 });
    expect(lerParcela('Parcela 02 de 05')).toEqual({ n: 2, de: 5 });
    expect(lerParcela('3/10')).toEqual({ n: 3, de: 10 });
    expect(lerParcela('')).toBeNull();
    expect(lerParcela('um de cinco')).toBeUndefined();
    expect(lerStatusContrato('Pago')).toEqual({ status: 'pago', data: null });
    expect(lerStatusContrato('Pago 12/10/2026')).toEqual({ status: 'pago', data: '2026-10-12' });
    expect(lerStatusContrato('Pendente')).toEqual({ status: 'pendente', data: null });
    expect(lerStatusContrato('Entrada')).toEqual({ status: 'entrada', data: null });
    expect(lerStatusContrato('Cancelado')).toBeUndefined();
    expect(lerContratoAssinado('Assinado')).toBe(true);
    expect(lerContratoAssinado('Sem contrato assinado')).toBe(false);
    expect(lerContratoAssinado('')).toBeNull();
    expect(lerTipo('Contrato Holding Familiar')).toBe(TIPO_CONTRATO);
  });

  const texto = [
    CAB,
    '10/09/2026\tFamília Andrade\t1 de 5\tR$ 1.000,00\tPago\tAssinado',
    '10/10/2026\tFamília Andrade\t2 de 5\tR$ 1.000,00\tPendente\tAssinado',
    '15/09/2026\tFamília Borges\t1 de 3\t800\tEntrada\tSem contrato assinado',
    '20/09/2026\tFamília Costa\t\t500\tPago 22/09/2026\tAssinado',
  ].join('\n');
  const c = lerColagem(texto, { podeVerDoc: false, hojeISO: '2026-09-28' });

  it('reconhecida pelo cabeçalho; tudo vira contrato, fora da Hotmart, sem identificador', () => {
    expect(c.formato).toBe('contratos');
    expect(c.cabecalhoIgnorado).toBe(true);
    expect(c.erroGeral).toBeNull();
    expect(c.linhas.map((l) => l.n)).toEqual([2, 3, 4, 5]);
    expect(c.linhas.every((l) => l.erros.length === 0)).toBe(true);
    for (const l of c.linhas) {
      expect(l.entrada).toMatchObject({ tipo: TIPO_CONTRATO, via_hotmart: false, produtos: [], acordo_desde: null });
      expect('identificador1' in l.entrada).toBe(false);
    }
  });
  it('Pago → baixa no vencimento; Pendente → sem baixa; Entrada → baixa + aviso; data no Status vence o vencimento', () => {
    expect(c.linhas.map((l) => l.entrada.baixa_manual_em)).toEqual(['2026-09-10', null, '2026-09-15', '2026-09-22']);
    expect(c.linhas.map((l) => l.avisos)).toEqual([[], [], [AVISO_ENTRADA], []]);
  });
  it('parcela e situação do contrato', () => {
    expect(c.linhas.map((l) => [l.entrada.parcela_n, l.entrada.parcela_de, l.entrada.contrato_assinado])).toEqual([
      [1, 5, true], [2, 5, true], [1, 3, false], [null, null, true],
    ]);
  });
  it('colunas em outra ordem: o cabeçalho diz onde cada uma está', () => {
    const x = lerColagem('Cliente\tValor\tVencimento\tSituação do contrato\tStatus\tParcela\nFamília E\t300\t01/11/2026\tAssinado\tPendente\t2 de 2', { podeVerDoc: true });
    expect(x.linhas[0].erros).toEqual([]);
    expect(x.linhas[0].entrada).toMatchObject({ cliente: 'Família E', valor: 300, data_prevista: '2026-11-01', parcela_n: 2, parcela_de: 2 });
  });
  it('erros locais: parcela fora do intervalo, situação vazia, Pago com baixa depois de hoje, coluna faltando', () => {
    const x = lerColagem([CAB, '10/12/2026\tF\t6 de 5\t100\tPago\t'].join('\n'), { podeVerDoc: true, hojeISO: '2026-09-28' });
    expect(x.linhas[0].erros).toEqual([
      'Parcela fora do intervalo: 6 de 5 (1 ≤ parcela ≤ total ≤ 60).',
      'Situação do contrato vazia (Assinado ou Sem contrato assinado).',
      'Status Pago com baixa depois de hoje (10/12/2026): escreva a data do pagamento no Status (ex.: Pago 12/10/2026).',
    ]);
    const semStatus = lerColagem('Vencimento\tCliente\tParcela\tValor\tSituação do contrato\n01/10/2026\tF\t1 de 1\t10\tAssinado', { podeVerDoc: true });
    expect(semStatus.erroGeral).toBe('Planilha Contratos Soluções sem a coluna: Status.');
  });
  it('planilha de renovações com tipo "Contrato Holding Familiar": erro local (não tem parcela nem situação)', () => {
    const x = lerColagem('20/10/2026\tC\tContrato Holding Familiar\t10\tN\t\t\t\t\t', { podeVerDoc: true });
    expect(x.formato).toBeUndefined();
    expect(x.linhas[0].erros).toContain(ERRO_CONTRATO_NA_PLANILHA_INFORMADOS);
  });
  it('prévia: colunas do contrato, aviso da Entrada, sem colunas de Hotmart', () => {
    const html = renderToStaticMarkup(createElement(ColarDaPlanilha, {
      repo: { importarInformados: async () => ({ ok: true, linhas: [] }) }, canVerDoc: false, onGravado: () => {},
      inicial: { colagem: c, previa: c.linhas.map((_, i) => ({ linha: i + 1, ok: true, erro: null, id: null })) },
    }));
    expect(html).toContain('Planilha Contratos Soluções reconhecida pelo cabeçalho');
    expect(html).toContain('1 de 5');
    expect(html).toContain('sem contrato assinado');
    expect(html).toContain(`Avisos: ${AVISO_ENTRADA}`);
    expect(html).toContain('1 linha com aviso: confira antes de gravar.');
    expect(html).not.toContain('Produto na Hotmart</th>');
    expect(html).toContain('Gravar 4 linhas');
  });
});

const INF = (p: Record<string, unknown>): Informado => normalizarInformado({
  id: 'k', data_prevista: '2026-10-05', cliente: 'Família K', tipo: TIPO_CONTRATO, valor: '1000', via_hotmart: false, produtos: [],
  situacao: 'a_receber', parcela_n: 2, parcela_de: 5, contrato_assinado: true, ...p,
});

describe('formulário e lista: tipo Contrato Holding Familiar', () => {
  it('normalizar: colunas novas; banco sem a z73 → nulos', () => {
    expect(INF({})).toMatchObject({ parcela_n: 2, parcela_de: 5, contrato_assinado: true });
    expect(INF({ parcela_n: '3', parcela_de: '4', contrato_assinado: 'f' })).toMatchObject({ parcela_n: 3, parcela_de: 4, contrato_assinado: false });
    const antigo = normalizarInformado({ id: 'x', cliente: 'C', tipo: 'outro', valor: 1, situacao: 'a_receber' });
    expect([antigo.parcela_n, antigo.parcela_de, antigo.contrato_assinado]).toEqual([null, null, null]);
  });
  it('contrato: via Hotmart falso e produto vazio mesmo com o form trazendo outro; parcela e assinado vão', () => {
    const f = { ...formDeInformado(INF({}), true), via_hotmart: 'S' as const, produtos: 'Holding Masters' };
    const { entrada, erros } = entradaDoFormulario(f, INF({}), true);
    expect(erros).toEqual([]);
    expect(entrada).toMatchObject({ tipo: TIPO_CONTRATO, via_hotmart: false, produtos: [], parcela_n: 2, parcela_de: 5, contrato_assinado: true });
  });
  it('contrato: assinado obrigatório; parcela só as duas juntas e no intervalo', () => {
    const base = formDeInformado(null, true);
    const novo = { ...base, data_prevista: '2026-11-10', cliente: 'F', tipo: TIPO_CONTRATO, valor: '100' };
    expect(entradaDoFormulario(novo, null, true).erros).toEqual(['Informe se o contrato está assinado.']);
    expect(entradaDoFormulario({ ...novo, contrato_assinado: 'N', parcela_n: '2' }, null, true).erros)
      .toEqual(['Informe a parcela e o total de parcelas juntos, em números (ex.: 2 de 5).']);
    expect(entradaDoFormulario({ ...novo, contrato_assinado: 'N', parcela_n: '6', parcela_de: '5' }, null, true).erros)
      .toEqual(['Parcela fora do intervalo: 6 de 5 (1 ≤ parcela ≤ total ≤ 60).']);
    const ok = entradaDoFormulario({ ...novo, contrato_assinado: 'N' }, null, true).entrada!;
    expect(ok).toMatchObject({ parcela_n: null, parcela_de: null, contrato_assinado: false, via_hotmart: false });
  });
  it('trocar de contrato para outro tipo: as chaves do contrato ficam AUSENTES (o banco limpa)', () => {
    const f = { ...formDeInformado(INF({}), true), tipo: 'outro', via_hotmart: 'N' as const };
    const { entrada } = entradaDoFormulario(f, INF({}), true);
    expect(entrada).not.toBeNull();
    expect('parcela_n' in entrada! || 'parcela_de' in entrada! || 'contrato_assinado' in entrada!).toBe(false);
  });
  it('formulário: contrato esconde via Hotmart e produto e mostra parcela e contrato assinado, com rótulo', () => {
    const html = renderToStaticMarkup(createElement(FormularioInformado, {
      form: { original: null, valores: { ...formDeInformado(null, true), tipo: TIPO_CONTRATO }, erros: [] },
      canVerDoc: true, ocupado: false, onMudar: () => {}, onSalvar: () => {}, onCancelar: () => {},
    }));
    expect(html).toContain('Número da parcela');
    expect(html).toContain('Total de parcelas');
    expect(html).toContain('Contrato assinado');
    expect(html).not.toContain('Via Hotmart');
    expect(html).not.toContain('Produto na Hotmart');
    const outro = renderToStaticMarkup(createElement(FormularioInformado, {
      form: { original: null, valores: { ...formDeInformado(null, true), tipo: 'outro' }, erros: [] },
      canVerDoc: true, ocupado: false, onMudar: () => {}, onSalvar: () => {}, onCancelar: () => {},
    }));
    expect(outro).toContain('Via Hotmart');
    expect(outro).not.toContain('Número da parcela');
  });
  it('lista: filtro por tipo com o tipo novo; linha do contrato com parcela e situação do contrato', () => {
    const repo = {} as RepoInformados;
    const html = renderToStaticMarkup(createElement(Informados, {
      repo, canEdit: false, canVerDoc: false,
      inicial: [INF({}), INF({ id: 'm', tipo: 'outro', parcela_n: null, parcela_de: null, contrato_assinado: null })],
    }));
    expect(html).toContain('<option value="contrato_holding_familiar">Contrato Holding Familiar</option>');
    expect(html).toContain('Todos os tipos');
    expect(html).toContain('2 de 5 · assinado');
  });
});
