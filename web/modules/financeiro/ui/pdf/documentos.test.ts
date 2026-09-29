import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { createElement } from 'react';
import { describe, expect, it } from 'vitest';
import { renderToBuffer } from '@react-pdf/renderer';
import { aplicarNivel, prepararParaPdf } from '@/shared/ui/pdf/nivel';
import { DocumentoPdf } from '@/shared/ui/pdf/DocumentoPdf';
import { recorteParaEmissao } from '@/shared/ui/pdf/gerar-pdf';
import { contarPaginasPdf } from '@/shared/ui/pdf/bytes-pdf';
import { larguraUtil, layoutTabela, linhasCabecalho, linhasCelula, textoCelula } from '@/shared/ui/pdf/paginar';
import { createRequire } from 'node:module';
import type { NivelPii, RascunhoRelatorio, SecaoPdf } from '@/shared/ui/pdf/modelo';
import type { ContaReceber } from '../../domain/types';
import type { AceleraParaHM, BoardHotmart, DivergenciaHotmart, IdentidadeRevisao, PessoaHotmart, ProrataHM } from '../../domain/hotmart';
import { COLUNAS_PADRAO, COLUNAS_RELATORIO, montarRelatorio } from '../../application/montar-relatorio';
import {
  NIVEIS_RELATORIO, PII_COLUNA_BOARD,
  rascunhoAcelera, rascunhoCarteira, rascunhoConciliacao, rascunhoIdentidade, rascunhoPessoas, rascunhoProrata, rascunhoReceber,
  recorteAcelera, recorteCarteira, recorteConciliacao, recortePessoas, recorteProrata,
} from './documentos';
import { montarContasReceber } from '../../application/carregar-contas-receber';
import { normalizarLinhaReceber } from '../../domain/contas-receber';

// ─── Fixtures com dado pessoal reconhecível ───────────────────────────────────
// Os literais abaixo NÃO podem aparecer no documento fora do nível completo.
const PII = {
  nome: 'Mariana Teixeira', nome2: 'Otávio Ramalho',
  email: 'mariana.teixeira@exemplo.com', email2: 'otavio@exemplo.com',
  tel: '(11) 98888-7777', cpf: '39053344705', cnpj: '11222333000181',
};
// 'HP123' = código de transação Hotmart da fixture de conciliação (pseudônimo do comprador).
const FRAGMENTOS_PII = [PII.nome, PII.nome2, PII.email, PII.email2, '98888', '4705', '0181', 'Mariana', 'Otávio', 'teixeira', 'otavio@', 'HP123'];

function conta(over: Partial<ContaReceber> = {}): ContaReceber {
  return {
    contato_hm_id: 'c1', comprador_id: 'p1', aluno_id: null,
    nome: PII.nome, email: PII.email, telefone: PII.tel, documento: PII.cpf,
    turma: 'T39', turma_origem: null, canal: 'HT ATM', publico: null, tags: null,
    estagio_nome: null, estagio_aba: null, estagio_id: null,
    produto: 'Holding Masters',
    vendedor: null, reuniao_em: null, reuniao_resultado: null, entrevista_em: null, entrevista_resultado: null, obs_comercial: null,
    intencao_pagamento: null, intencao_pagamento_obs: null, reuniao_motivo_tipo: null, reuniao_retomar_em: null,
    solicitou_cancelamento: false,
    sinal_bruto: null, sinal_liquido: null, sinal_taxas: null, sinal_pago_em: null, sinal_metodo: null, sinal_transacao: null,
    saldo_pago_bruto: 0, saldo_pago_liquido: 0, saldo_taxas: 0, saldo_pago_em: null, saldo_metodo: null, saldo_lancamentos: 0,
    total_pago_bruto: 300, total_pago_liquido: 287, pacote: 15000, pacote_regra: null, divergencia_regra: null,
    credito: null, saldo_a_pagar: 14700, pago_pct: 2,
    vencimento: '2026-10-05', acordo: null, pagamento_meio: null, pagamento_forma: null, pagamento_parcelas: null,
    parcelas_pagas: null, parcelas_contratadas: null, valor_parcela: null, dias_atraso: null,
    oferta_codigo: null, oferta_valor: null, oferta_link: null, oferta_recorrente: null, oferta_enviada_em: null,
    cancelamento_em: null, cancelamento_motivo: null, cancelamento_efetivado_em: null, quitado_em: null,
    reembolso_em: null, reembolso_status: null, reembolso_valor: null,
    ultimo_pagamento_em: null, situacao_ativacao: null, status_financeiro: 'sem_acordo',
    ultima_cobranca_em: null, cobrancas_total: 0, remarcacoes: 0,
    ...over,
  };
}

function pessoa(over: Partial<PessoaHotmart> = {}): PessoaHotmart {
  return {
    pessoa_chave: 'p1', nome: PII.nome, emails: [PII.email], documentos: [PII.cpf], telefone: PII.tel, cidade: 'Goiânia',
    situacao: 'devendo', aviso: null, primeira_compra: '2025-03-10', primeira_oferta: 'Sinal HM', origem: 'sck_x', fluxo: 'sinal',
    produtos: null, ultima_compra_paga: '2026-08-01', compras_pagas: 3, valor_pago: 12000, liquido: 11000, estornos: 0,
    valor_estornado: 0, parcelas_atrasadas: 2, valor_atrasado: 1500, atrasadas_antigas: 0, valor_atrasado_antigo: 0,
    em_aberto: 0, recusadas: 0, ultima_tentativa: null, no_gps: false, turma: 'T40', acesso_ate: null, acesso_hotmart_ate: null,
    cards: 1, contato_hm_id: 'c1', status_card: 'Em dia', saldo_card: null, canal_card: null, solicitou_cancelamento: false,
    sugestoes: 0, cobrado_cliente: 12500, juros: 500, taxa_hotmart: 1000, coproducao: 0, vendas_parceladas: 1, parcelas_max: 12,
    forma_pagamento_principal: 'CREDIT_CARD_VISA',
    ...over,
  };
}

const divergencia = (over: Partial<DivergenciaHotmart> = {}): DivergenciaHotmart => ({
  tipo: 'falta_no_banco', transacao: 'HP123', email: PII.email, status_hotmart: 'APPROVED', status_banco: null,
  valor_hotmart: 997, valor_banco: null, pedido_em: '2026-09-01T12:00:00Z', detalhe: 'Venda paga na Hotmart que o webhook não gravou', ...over,
});

const identidade: IdentidadeRevisao[] = [
  { tipo: 'sugestao', motivo: 'mesmo_telefone', evidencia: '5511988887777', pessoa_a: 'a', emails_a: [PII.email], nomes_a: [PII.nome], pessoa_b: 'b', emails_b: [PII.email2], nomes_b: [PII.nome2], pago_a: 100, pago_b: 200 },
  { tipo: 'revisao', motivo: 'documento compartilhado (escritório)', evidencia: PII.cnpj, pessoa_a: 'c', emails_a: null, nomes_a: null, pessoa_b: null, emails_b: null, nomes_b: null, pago_a: null, pago_b: null },
];

const acelera = (over: Partial<AceleraParaHM> = {}): AceleraParaHM => ({
  pessoa_chave: 'p1', nome: PII.nome, email: PII.email, primeira_acelera: '2025-01-10', acelera_pago: 497, acelera_funil: 'Funil A',
  ja_era_hm: false, subiu: true, primeira_hm_depois: '2025-03-01', dias_ate_subir: 50, hm_pago_depois: 15000, hm_caminho: 'sinal → saldo', tem_card: false, ...over,
});

const prorata = (over: Partial<ProrataHM> = {}): ProrataHM => ({
  pessoa_chave: 'p1', nome: PII.nome, email: PII.email, turma: 'T38', vencimento: '2027-01-31', meses_restantes: 4, pago_no_ciclo: 12000,
  pagamentos_no_ciclo: 12, formas: '12 mensalidades', credito: 4000, diferenca: 26000, ultimo_pagamento: '2026-09-01', tem_card: true,
  contato_hm_id: 'c1', no_gps: false, ...over,
} as ProrataHM);

// ─── Os 6 relatórios, com dado pessoal ───────────────────────────────────────
function seis(): RascunhoRelatorio[] {
  const contas = [conta(), conta({ contato_hm_id: 'c2', nome: PII.nome2, email: PII.email2, status_financeiro: 'vencido', dias_atraso: 10 })];
  const todasColunas = COLUNAS_RELATORIO.map((c) => c.key);
  const ds = montarRelatorio(contas, todasColunas, { canVerDoc: true, hotmartPorCard: null });
  return [
    rascunhoCarteira(ds, contas, recorteCarteira({ turma: 'T39', produto: 'Holding Masters', acao: 'Holding Total ATM (06/07/2026)' })),
    rascunhoPessoas([pessoa(), pessoa({ pessoa_chave: 'p2', nome: PII.nome2, emails: [PII.email2], documentos: [PII.cnpj] })],
      recortePessoas({ familia: 'HM', filtro: null, de: '', ate: '', busca: 'Mariana' })),
    rascunhoConciliacao([divergencia(), divergencia({ tipo: 'valor_diferente', email: PII.email2, transacao: 'HP9' })], recorteConciliacao('HM')),
    rascunhoIdentidade(identidade),
    rascunhoAcelera([acelera(), acelera({ pessoa_chave: 'p2', nome: PII.nome2, email: PII.email2, subiu: false })], recorteAcelera(null)),
    rascunhoProrata([prorata(), prorata({ pessoa_chave: 'p2', nome: PII.nome2, email: PII.email2 })], recorteProrata(null, 'otavio')),
  ];
}

describe('classe de dado pessoal: os 6 relatórios', () => {
  const niveisSemPii: NivelPii[] = ['sem_dado_pessoal', 'so_numeros'];

  for (const r of seis()) {
    for (const nivel of niveisSemPii.filter((x) => r.niveisPermitidos.includes(x))) {
      it(`${r.tipo} · ${nivel}: nenhuma coluna pessoal e nenhum dado pessoal no documento`, () => {
        const out = aplicarNivel(r, nivel);
        for (const s of out.secoes) {
          const pessoais = s.colunas.filter((c) => c.pii !== 'nenhuma').map((c) => c.rotulo);
          expect(pessoais, `${r.tipo}/${s.titulo}`).toEqual([]);
        }
        const tudo = JSON.stringify(out);
        for (const f of FRAGMENTOS_PII) expect(tudo, `${r.tipo} vazou "${f}"`).not.toContain(f);
      });
    }

    it(`${r.tipo} · completo: documento nunca sai cru`, () => {
      const tudo = JSON.stringify(aplicarNivel(r, 'completo'));
      expect(tudo).not.toContain(PII.cpf);
      expect(tudo).not.toContain(PII.cnpj);
      expect(tudo).not.toMatch(/\d{11}/);
    });
  }

  it('so_numeros não tem nenhuma linha de pessoa em nenhum dos relatórios que aceitam o nível', () => {
    for (const r of seis().filter((x) => x.niveisPermitidos.includes('so_numeros'))) {
      const out = aplicarNivel(r, 'so_numeros');
      expect(out.secoes.every((s) => s.tipo === 'resumo'), r.tipo).toBe(true);
      expect(out.kpis?.length, r.tipo).toBeGreaterThan(0);
    }
  });

  it('"Mesma pessoa?" só aceita completo; os outros 5 aceitam os 3 níveis', () => {
    expect(NIVEIS_RELATORIO.identidade).toEqual(['completo']);
    for (const t of ['board', 'pessoas', 'conciliacao', 'acelera', 'prorata'] as const) {
      expect(NIVEIS_RELATORIO[t]).toEqual(['completo', 'sem_dado_pessoal', 'so_numeros']);
    }
    const id = seis().find((r) => r.tipo === 'identidade')!;
    expect(() => aplicarNivel(id, 'sem_dado_pessoal')).toThrow();
  });

  it('conciliação: código da transação Hotmart (HP…) é pessoal — só sai no nível completo', () => {
    const r = seis().find((x) => x.tipo === 'conciliacao')!;
    const det = r.secoes.find((s) => s.tipo === 'detalhe')!;
    expect(det.colunas.find((c) => c.chave === 'transacao')?.pii).toBe('identificacao');
    for (const nivel of ['sem_dado_pessoal', 'so_numeros'] as const) {
      const out = aplicarNivel(r, nivel);
      expect(out.secoes.flatMap((s) => s.colunas.map((c) => c.chave)), nivel).not.toContain('transacao');
      const tudo = JSON.stringify(out);
      expect(tudo, nivel).not.toContain('HP123');
      expect(tudo, nivel).not.toContain('HP9');
    }
    expect(JSON.stringify(aplicarNivel(r, 'completo'))).toContain('HP123');
  });

  it('toda coluna de COLUNAS_RELATORIO (Carteira do board) tem classe de dado pessoal declarada', () => {
    const semClasse = COLUNAS_RELATORIO.map((c) => c.key).filter((k) => !(k in PII_COLUNA_BOARD));
    expect(semClasse).toEqual([]);
  });
});

describe('mapeadores', () => {
  it('lista vazia: documento válido, detalhe sem linha e com texto de vazio, KPIs zerados', () => {
    const r = rascunhoPessoas([], recortePessoas({ familia: 'HM', filtro: 'devendo', de: '', ate: '', busca: '' }));
    const det = r.secoes.find((s) => s.tipo === 'detalhe')!;
    expect(det.linhas).toEqual([]);
    expect(det.vazio).toBeTruthy();
    expect(det.total).toBeUndefined();
    expect(r.kpis?.[0]).toEqual({ rotulo: 'Pessoas', valor: '0' });
    expect(rascunhoConciliacao([], recorteConciliacao('HM')).secoes[1].linhas).toEqual([]);
    expect(rascunhoAcelera([], recorteAcelera(null)).kpis?.find((k) => k.rotulo === 'Média de dias até subir')?.valor).toBe('—');
  });

  it('formata moeda e data como a tela (pt-BR)', () => {
    const r = rascunhoPessoas([pessoa()], []);
    const c = r.secoes[1].linhas[0].celulas;
    expect(c.pago).toMatch(/^R\$\s12\.000$/);
    expect(c.primeira).toBe('10/03/2025');
    expect(c.situacao).toBe('Devendo');
    expect(c.documento).toBe('CPF ···4705');
    expect(c.atraso).toMatch(/^2 · R\$\s1\.500$/);
    const pr = rascunhoProrata([prorata()], []).secoes[0].linhas[0].celulas;
    expect(pr.credito).toMatch(/^R\$\s4\.000,00$/);
    expect(pr.vence).toBe('31/01/2027');
  });

  it('carteira: células vêm de formatarCelulaTela e o total soma as colunas de moeda', () => {
    const contas = [conta(), conta({ contato_hm_id: 'c2', total_pago_bruto: 700 })];
    const ds = montarRelatorio(contas, ['nome', 'status', 'total_pago_bruto'], { canVerDoc: false, hotmartPorCard: null });
    const det = rascunhoCarteira(ds, contas, recorteCarteira({ turma: null, produto: 'Aurum', acao: null })).secoes[1];
    expect(det.linhas[0].celulas.total_pago_bruto).toMatch(/^R\$\s300,00$/);
    expect(det.total?.total_pago_bruto).toMatch(/^R\$\s1\.000,00$/);
    expect(det.colunas.find((c) => c.chave === 'nome')?.pii).toBe('identificacao');
  });

  it('texto do filtro: família, situação, período e busca (marcada como pessoal)', () => {
    expect(recortePessoas({ familia: 'HM', filtro: 'devendo', de: '2026-01-01', ate: '', busca: ' Ana ', semCard: true })).toEqual([
      { rotulo: 'Família', valor: 'Holding Masters' },
      { rotulo: 'Base', valor: 'pagaram na Hotmart e não estão no board' },
      { rotulo: 'Situação', valor: 'Devendo' },
      { rotulo: '1ª compra', valor: '01/01/2026 a hoje' },
      { rotulo: 'Busca', valor: '"Ana"', pii: true },
    ]);
    // Carteira: produto e ação que encolheram a lista sempre declarados (pentest 28/09).
    expect(recorteCarteira({ turma: null, produto: 'Holding Masters', acao: 'Holding Total ATM (06/07/2026)' })).toEqual([
      { rotulo: 'Produto', valor: 'Holding Masters' },
      { rotulo: 'Ação', valor: 'Holding Total ATM (06/07/2026)' },
      { rotulo: 'Turma', valor: 'Todas' },
      { rotulo: 'Base', valor: 'recorte atual do board' },
    ]);
    expect(recorteCarteira({ turma: null, produto: 'Aurum', acao: null }).slice(0, 2)).toEqual([
      { rotulo: 'Produto', valor: 'Aurum' },
      { rotulo: 'Ação', valor: 'todas as ações' },
    ]);
    expect(recorteAcelera('sem_card')).toEqual([{ rotulo: 'Filtro', valor: 'Subiram sem card' }]);
    expect(recorteProrata('vence60', '')).toEqual([{ rotulo: 'Filtro', valor: 'Vence em até 60 dias' }]);
  });

  it('carteira: produto e ação vão no cabeçalho em todo nível e no recorte gravado na emissão', () => {
    const contas = [conta()];
    const r = rascunhoCarteira(montarRelatorio(contas, COLUNAS_PADRAO, { canVerDoc: false, hotmartPorCard: null }), contas,
      recorteCarteira({ turma: null, produto: 'Holding Masters', acao: 'Holding Total ATM (06/07/2026)' }));
    for (const nivel of r.niveisPermitidos) {
      expect(aplicarNivel(r, nivel).recorte.slice(0, 2), nivel).toEqual(['Produto: Holding Masters', 'Ação: Holding Total ATM (06/07/2026)']);
    }
    expect(recorteParaEmissao(r)).toEqual({
      filtros: ['Produto: Holding Masters', 'Ação: Holding Total ATM (06/07/2026)', 'Turma: Todas', 'Base: recorte atual do board'],
    });
  });

  it('busca livre sai como "termo omitido" fora do nível completo', () => {
    const r = rascunhoProrata([prorata()], recorteProrata(null, 'Mariana'));
    expect(aplicarNivel(r, 'completo').recorte).toContain('Busca: "Mariana"');
    expect(aplicarNivel(r, 'sem_dado_pessoal').recorte).toContain('Busca: termo omitido');
  });

  it('identidade: telefone da evidência e documento em revisão saem mascarados', () => {
    const out = aplicarNivel(rascunhoIdentidade(identidade), 'completo');
    expect(out.secoes[0].linhas[0].celulas.evidencia).toBe('···7777');
    expect(out.secoes[1].linhas[0].celulas.documento).toBe('···0181');
  });
});

describe('os 6 relatórios desenham (renderToBuffer)', () => {
  // Geometria da tabela medida com a FONTE REAL (fontkit sobre o Inter embutido, com
  // kerning) — não com a tabela de métrica que a paginação usa: se a métrica errar para
  // baixo, este teste pega. Carteira com as 25 colunas marcadas e valores longos.
  const PUBLICO = path.resolve(__dirname, '../../../../public');
  // fontkit vem com o @react-pdf/renderer (dependência dele, sem tipos): só o necessário.
  type FonteReal = { unitsPerEm: number; layout(t: string): { glyphs: { advanceWidth: number }[] } };
  const fontkit = createRequire(__filename)('fontkit') as { openSync(caminho: string): FonteReal };
  const fontes = {
    400: fontkit.openSync(path.join(PUBLICO, 'fonts/Inter-Regular.ttf')),
    600: fontkit.openSync(path.join(PUBLICO, 'fonts/Inter-SemiBold.ttf')),
  };
  const medirReal = (texto: string, corpo: number, peso: 400 | 600) =>
    (fontes[peso].layout(texto).glyphs.reduce((s, g) => s + g.advanceWidth, 0) * corpo) / fontes[peso].unitsPerEm;

  function carteira(chaves: string[]) {
    const contas = Array.from({ length: 30 }, (_, i) => conta({
      contato_hm_id: `c${i}`, nome: i % 2 ? 'Maria das Graças Oliveira Albuquerque' : PII.nome,
      email: `pessoa.exemplo${i}@dominio-comprido-de-empresa.com.br`, canal: 'Holding Total ATM (06/07/2026)',
      total_pago_bruto: 123456.78 + i, total_pago_liquido: 98765.43, saldo_a_pagar: 14700, pacote: 150000, credito: i % 3 ? null : 1250.5,
      dias_atraso: 1234, solicitou_cancelamento: i % 2 === 0, oferta_codigo: 'k8x2abcd', ultimo_pagamento_em: '2026-09-01',
    }));
    const hp = new Map<string, BoardHotmart>(contas.map((c) => [c.contato_hm_id, {
      pago_bruto: 123456.78, taxa_hotmart: 12345.67, liquido: 111111.11, juros: 9999.9, parcelas_max: 12,
      ultimo_pagamento_em: '2026-08-15', valor_devido: 45000, diverge: true,
    } as unknown as BoardHotmart]));
    const r = rascunhoCarteira(montarRelatorio(contas, chaves, { canVerDoc: true, hotmartPorCard: hp }), contas, []);
    return aplicarNivel(r, 'completo').secoes[1];
  }

  for (const [nome, chaves] of [['25 colunas', COLUNAS_RELATORIO.map((c) => c.key)], ['9 colunas (padrão)', COLUNAS_PADRAO]] as const) {
    it(`carteira ${nome}: nenhum texto passa da largura da coluna; cabeçalho e valor não se partem`, () => {
      const s = carteira([...chaves]);
      expect(s.colunas).toHaveLength(chaves.length);
      const layout = layoutTabela(s);
      expect(layout.larguras.reduce((a, b) => a + b, 0)).toBeLessThanOrEqual(770 + 0.01);
      const excessos: string[] = [];
      const conferir = (onde: string, i: number, linhas: string[], corpo: number, peso: 400 | 600) => {
        for (const l of linhas) {
          const w = medirReal(l, corpo, peso);
          if (w > larguraUtil(layout, i) + 0.01) excessos.push(`${onde} "${l}" ${w.toFixed(1)} > ${larguraUtil(layout, i).toFixed(1)}`);
        }
      };
      s.colunas.forEach((c, i) => {
        const cab = linhasCabecalho(layout, i, c.rotulo);
        conferir(`cabeçalho ${c.rotulo}`, i, cab, layout.corpoTh, 600);
        // palavra do cabeçalho nunca se parte: toda linha é feita de palavras inteiras do rótulo
        expect(cab.join(' ').split(' '), c.rotulo).toEqual(c.rotulo.split(' '));
        for (const [k, l] of s.linhas.entries()) {
          const texto = textoCelula(l.celulas, c, i);
          const linhas = linhasCelula(layout, i, texto);
          conferir(`linha ${k} ${c.rotulo}`, i, linhas, layout.corpo, 400);
          // valor (R$, data, número) só pode ir para a linha de baixo no espaço rígido: "R$" / "123.456,78"
          if (c.tipo !== 'texto') expect(linhas.join(' '), `${c.rotulo}: ${texto}`).toBe(texto);
          // 9 colunas padrão: sobra folha, valor nunca vai para 2 linhas
          if (c.tipo !== 'texto' && chaves.length === COLUNAS_PADRAO.length) expect(linhas, `${c.rotulo}: ${texto}`).toHaveLength(1);
        }
        if (s.total) {
          const tt = textoCelula(s.total, c, i, true);
          const lt = linhasCelula(layout, i, tt, 600);
          conferir(`total ${c.rotulo}`, i, lt, layout.corpo, 600);
          if (c.tipo !== 'texto' && chaves.length === COLUNAS_PADRAO.length) expect(lt, `total ${c.rotulo}: ${tt}`).toHaveLength(1);
        }
      });
      expect(excessos).toEqual([]);
      if (chaves.length === COLUNAS_PADRAO.length) {
        expect(layout.corpo).toBe(7.5); // as 9 padrão não apertam: corpo e espaçamento normais
        expect(layout.padX).toBe(4);
      }
    });
  }

  // Caso medido: Pessoas do HM com 9.228 linhas — o total "R$ 153.309.378" é o que define a
  // largura mínima da coluna e ia para 2 linhas por 0,001 pt de arredondamento.
  // Medido (orquestrador): 695 ms sozinho, 1.855 ms na suíte, 3.991 ms com build rodando ao lado — CPU disputada,
  // não resultado errado (a conta é determinística). Teto próprio para não estourar os 5.000 ms padrão do vitest.
  it('valor que define a largura mínima da coluna cabe numa linha só (Pessoas, 9.228 linhas)', () => {
    const lista = Array.from({ length: 9228 }, (_, i) => pessoa({ pessoa_chave: `p${i}`, valor_pago: 12000 + i, parcelas_atrasadas: i % 4 ? 0 : 2 }));
    const s = aplicarNivel(rascunhoPessoas(lista, []), 'completo').secoes[1];
    const layout = layoutTabela(s);
    s.colunas.forEach((c, i) => {
      if (c.tipo === 'texto' || !s.total) return;
      const tt = textoCelula(s.total, c, i, true);
      expect(linhasCelula(layout, i, tt, 600), `total ${c.rotulo}: ${tt}`).toHaveLength(1);
    });
  }, 20_000);

  it('coluna de data comporta dd/mm/aaaa sem quebrar nos relatórios de colunas fixas', () => {
    const contas = [conta()];
    const padrao = rascunhoCarteira(montarRelatorio(contas, COLUNAS_PADRAO, { canVerDoc: false, hotmartPorCard: null }), contas, []);
    for (const r of [padrao, ...seis().filter((x) => x.tipo !== 'board')]) {
      for (const s of r.secoes) {
        const layout = layoutTabela(s);
        s.colunas.forEach((c, i) => {
          if (c.tipo === 'data') expect(linhasCelula(layout, i, '10/02/2025'), `${r.tipo}/${c.rotulo}`).toHaveLength(1);
        });
      }
    }
  });

  it('cada relatório em cada nível aceito gera %PDF com protocolo', async () => {
    const publico = path.resolve(__dirname, '../../../../public') + path.sep;
    const saida = process.env.PDF_SAIDA;
    if (saida) mkdirSync(saida, { recursive: true });
    for (const r of seis()) {
      for (const nivel of r.niveisPermitidos) {
        const doc = { ...aplicarNivel(r, nivel), protocolo: 'GP-REL-2026-000007', emitidoEm: '2026-09-28T13:00:00Z' };
        const buf = await renderToBuffer(createElement(DocumentoPdf, { doc, recursos: { base: publico } }) as Parameters<typeof renderToBuffer>[0]);
        expect(buf.subarray(0, 5).toString('latin1'), `${r.tipo}/${nivel}`).toBe('%PDF-');
        expect(contarPaginasPdf(new Uint8Array(buf))).toBeGreaterThanOrEqual(1);
        if (saida) writeFileSync(path.join(saida, `${r.tipo}-${nivel}.pdf`), buf);
      }
    }
  }, 60_000);
});

// ─── 7. Contas a receber (F5) ──────────────────────────────────────────────────
describe('contas a receber (rascunhoReceber)', () => {
  const HOT = '1. Receita de vendas (Hotmart)';
  const DIR = '4. Receita de vendas (Direta de clientes)';
  const DEV = '3. (Devoluções)';
  // Linhas como o banco devolve, pelo mesmo caminho do repositório. Nomes reconhecíveis nos blocos de pessoa (2, 5).
  const bruto: Record<string, unknown>[] = [
    { bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29', valor: '1000', situacao: 'a_receber',
      certeza: 'certo', centro_custo: HOT, tratamento: 'Antecipação D+2 útil', detalhe: [{ transacao: 'HP1', nome: PII.nome2, liquido: 1100 }] },
    { bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'antecipacao', data_caixa: '2026-10-05', valor: '85.74', valor_bruto: '100',
      fator: '0.857375', situacao: 'a_receber', origem_dia: '2026-10-03', ref: 'opaca-A', rotulo: PII.nome, produto: 'Holding Masters',
      certeza: 'certo', centro_custo: HOT, tratamento: 'Perda 5%/mês' },
    { bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'garantia', data_caixa: '2026-11-03', valor: '10', situacao: 'a_receber',
      origem_dia: '2026-10-03', ref: 'opaca-A', rotulo: PII.nome, produto: 'Holding Masters', certeza: 'certo', centro_custo: HOT },
    { bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'cheio', data_caixa: null, valor: '300', situacao: 'realizada',
      origem_dia: '2026-09-01', ref: 'opaca-B', rotulo: 'Bruno Realizado', certeza: 'certo', centro_custo: HOT },
    { bloco: 5, grupo: 'Renovações Diamante', componente: 'cheio', data_caixa: '2026-10-10', valor: '5000', situacao: 'a_receber',
      ref: '11', rotulo: PII.nome2, certeza: 'certo', centro_custo: DIR },
    { bloco: 3, grupo: 'Outros produtos', componente: 'cheio', data_caixa: null, valor: null, valor_bruto: null, situacao: 'sem_base',
      ref: 'vn:outros', rotulo: 'sem base', certeza: 'estimado', centro_custo: HOT, tratamento: 'Sem sugestão medida' },
    { bloco: 3, grupo: 'HM avulso', componente: 'antecipacao', data_caixa: '2026-10-01', valor: '500.50', situacao: 'a_receber',
      ref: 'vn:hm_avulso', rotulo: 'mediana 12 sem', certeza: 'estimado', centro_custo: HOT },
    { bloco: 6, grupo: 'Reserva de reembolso e chargeback', componente: 'reserva', data_caixa: '2026-10-01', valor: '-19.47',
      situacao: 'a_receber', ref: 'reserva', rotulo: 'taxa medida em 9 meses', certeza: 'estimado', centro_custo: DEV },
    { bloco: 8, grupo: 'Informativo: acordos no board', componente: 'cheio', data_caixa: '2026-10-01', valor: '7000',
      situacao: 'informativo', ref: '11', rotulo: 'Pessoa Board', certeza: 'informativo', centro_custo: null },
  ];
  const dados = montarContasReceber(bruto.map(normalizarLinhaReceber), '2026-09-28', 'conservador');
  const r = rascunhoReceber(dados);
  const secao = (doc: { secoes: SecaoPdf[] }, prefixo: string) => doc.secoes.find((s) => s.titulo.startsWith(prefixo))!;

  it('capa: tipo receber, 3 níveis, cenário, corte e horizonte no recorte gravado; KPIs certo e estimado', () => {
    expect(r.tipo).toBe('receber');
    expect(NIVEIS_RELATORIO.receber).toEqual(['completo', 'sem_dado_pessoal', 'so_numeros']);
    expect(r.niveisPermitidos).toEqual(NIVEIS_RELATORIO.receber);
    expect(recorteParaEmissao(r)).toEqual({
      filtros: ['Cenário: Conservador', 'Corte: 28/09/2026', `Horizonte: 28/09/2026 a 30/11/2026 · ${dados.grade.semanas.length} semanas`],
    });
    expect(r.kpis?.find((k) => k.rotulo === 'A receber no período')?.valor).toMatch(/^R\$\s6\.576,77$/);
    expect(r.kpis?.find((k) => k.rotulo === 'Certo')?.valor).toMatch(/^R\$\s6\.095,74$/);
    expect(r.kpis?.find((k) => k.rotulo === 'Estimado')?.valor).toMatch(/^R\$\s481,03$/);
  });

  it('resumo mensal certo × estimado fecha com a grade', () => {
    const s = secao(r, 'Resumo mensal');
    expect(s.linhas.map((l) => l.celulas.mes)).toEqual(['set/2026', 'out/2026', 'nov/2026']);
    expect(s.linhas[1].celulas.certo).toMatch(/^R\$\s5\.085,74$/);
    expect(s.linhas[1].celulas.estimado).toMatch(/^R\$\s481,03$/);
    expect(s.linhas[2].celulas.estimado).toBe(''); // zero = travessão
    expect(s.linhas[2].celulas.acumulado).toMatch(/^R\$\s6\.576,77$/);
    expect(s.total?.total).toMatch(/^R\$\s6\.576,77$/);
  });

  it('por centro de custo × mês: os 3 centros de entrada, total igual ao da grade', () => {
    const s = secao(r, 'Entradas por centro');
    expect(s.colunas.slice(1, 4).map((c) => c.rotulo)).toEqual([HOT, DIR, DEV]);
    expect(s.total?.total).toMatch(/^R\$\s6\.576,77$/);
  });

  it('semana × bloco: uma linha por semana de domain/contas-receber, colunas por bloco, informativo à parte', () => {
    const s = secao(r, 'Semana × bloco');
    expect(s.linhas).toHaveLength(dados.grade.semanas.length);
    expect(s.linhas[0].celulas.semana).toBe('S1');
    expect(s.colunas.map((c) => c.chave)).toEqual(['semana', 'periodo', 'b1', 'b2', 'b3', 'b5', 'b6', 'certo', 'estimado', 'total', 'acumulado', 'info']);
    expect(s.total?.total).toMatch(/^R\$\s6\.576,77$/);
    expect(s.total?.info).toMatch(/^R\$\s7\.000,00$/);
  });

  it('fora da soma: realizada contada, sem base listada', () => {
    const txt = secao(r, 'Fora da soma').linhas.map((l) => l.celulas.situacao);
    expect(txt).toContain('Realizada');
    expect(txt.some((t) => /^Sem base medida: 3\. Outros produtos/.test(t))).toBe(true);
    expect(txt).not.toContain('Sem base medida'); // sem contagem duplicada: o grupo já está listado
  });

  it('anexo: só a_receber; completo com nome; sem dado pessoal = "Pessoa N" estável por contrato; só números sem anexo', () => {
    const anexo = secao(r, 'Anexo');
    expect(anexo.linhas).toHaveLength(6);
    expect(anexo.total?.esperado).toMatch(/^R\$\s6\.576,77$/);
    expect(secao(aplicarNivel(r, 'completo'), 'Anexo').linhas.map((l) => l.celulas.descricao)).toContain(PII.nome);

    const sem = aplicarNivel(r, 'sem_dado_pessoal');
    const a = secao(sem, 'Anexo');
    const desc = a.linhas.map((l) => [l.celulas.bloco, l.celulas.descricao]);
    // bloco 2 (duas linhas do mesmo contrato) = Pessoa 1 nas duas; bloco 5 = Pessoa 2; blocos 1, 3 e 6 mantêm a base
    expect(desc.filter(([b]) => b === '2').map(([, d]) => d)).toEqual(['Pessoa 1', 'Pessoa 1']);
    expect(desc.find(([b]) => b === '5')?.[1]).toBe('Pessoa 2');
    expect(desc.find(([b]) => b === '3')?.[1]).toBe('mediana 12 sem');
    expect(a.colunas.every((c) => c.pii === 'nenhuma')).toBe(true);
    const tudo = JSON.stringify(sem);
    for (const f of FRAGMENTOS_PII) expect(tudo, `vazou "${f}"`).not.toContain(f);

    const so = aplicarNivel(r, 'so_numeros');
    expect(so.secoes.every((s) => s.tipo === 'resumo')).toBe(true);
    expect(JSON.stringify(so)).not.toContain(PII.nome);
  });

  it('acima de 2.000 linhas a receber: só totais, aviso aponta para a planilha (CSV da Base auditável)', () => {
    const muitas = Array.from({ length: 2001 }, (_, i) => normalizarLinhaReceber({
      bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'cheio', data_caixa: '2026-10-05', valor: '10', situacao: 'a_receber',
      origem_dia: '2026-10-05', ref: `c${i}`, rotulo: `Pessoa real ${i}`, centro_custo: HOT,
    }));
    const p = prepararParaPdf(rascunhoReceber(montarContasReceber(muitas, '2026-09-28')), 'completo');
    expect(p.linhasDaLista).toBe(2001);
    expect(p.linhasImpressas).toBe(0);
    expect(p.documento.avisoSoTotais).toMatch(/planilha/);
    expect(JSON.stringify(p.documento)).not.toContain('Pessoa real');
  });

  it('desenha %PDF nos 3 níveis e a data cabe numa linha', async () => {
    for (const s of r.secoes) {
      const layout = layoutTabela(s);
      s.colunas.forEach((c, i) => {
        if (c.tipo === 'data') expect(linhasCelula(layout, i, '10/02/2025'), c.rotulo).toHaveLength(1);
      });
    }
    const publico = path.resolve(__dirname, '../../../../public') + path.sep;
    const saida = process.env.PDF_SAIDA;
    for (const nivel of r.niveisPermitidos) {
      const doc = { ...aplicarNivel(r, nivel), protocolo: 'GP-REL-2026-000008', emitidoEm: '2026-09-28T13:00:00Z' };
      const buf = await renderToBuffer(createElement(DocumentoPdf, { doc, recursos: { base: publico } }) as Parameters<typeof renderToBuffer>[0]);
      expect(buf.subarray(0, 5).toString('latin1'), nivel).toBe('%PDF-');
      expect(contarPaginasPdf(new Uint8Array(buf))).toBeGreaterThanOrEqual(1);
      if (saida) { mkdirSync(saida, { recursive: true }); writeFileSync(path.join(saida, `receber-${nivel}.pdf`), buf); }
    }
  }, 60_000);
});
