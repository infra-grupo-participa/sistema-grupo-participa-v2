import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { createElement } from 'react';
import { describe, expect, it } from 'vitest';
import { renderToBuffer } from '@react-pdf/renderer';
import { aplicarNivel } from '@/shared/ui/pdf/nivel';
import { DocumentoPdf } from '@/shared/ui/pdf/DocumentoPdf';
import { contarPaginasPdf } from '@/shared/ui/pdf/gerar-pdf';
import { caracteresPorLinha, larguraColunas } from '@/shared/ui/pdf/paginar';
import type { NivelPii, RascunhoRelatorio } from '@/shared/ui/pdf/modelo';
import type { ContaReceber } from '../../domain/types';
import type { AceleraParaHM, DivergenciaHotmart, IdentidadeRevisao, PessoaHotmart, ProrataHM } from '../../domain/hotmart';
import { COLUNAS_PADRAO, COLUNAS_RELATORIO, montarRelatorio } from '../../application/montar-relatorio';
import {
  NIVEIS_RELATORIO, PII_COLUNA_BOARD,
  rascunhoAcelera, rascunhoCarteira, rascunhoConciliacao, rascunhoIdentidade, rascunhoPessoas, rascunhoProrata,
  recorteAcelera, recorteCarteira, recorteConciliacao, recortePessoas, recorteProrata,
} from './documentos';

// ─── Fixtures com dado pessoal reconhecível ───────────────────────────────────
// Os literais abaixo NÃO podem aparecer no documento fora do nível completo.
const PII = {
  nome: 'Mariana Teixeira', nome2: 'Otávio Ramalho',
  email: 'mariana.teixeira@exemplo.com', email2: 'otavio@exemplo.com',
  tel: '(11) 98888-7777', cpf: '39053344705', cnpj: '11222333000181',
};
const FRAGMENTOS_PII = [PII.nome, PII.nome2, PII.email, PII.email2, '98888', '4705', '0181', 'Mariana', 'Otávio', 'teixeira', 'otavio@'];

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
    rascunhoCarteira(ds, contas, recorteCarteira('T39')),
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
    const det = rascunhoCarteira(ds, contas, recorteCarteira(null)).secoes[1];
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
    expect(recorteCarteira(null)[0]).toEqual({ rotulo: 'Turma', valor: 'Todas' });
    expect(recorteAcelera('sem_card')).toEqual([{ rotulo: 'Filtro', valor: 'Subiram sem card' }]);
    expect(recorteProrata('vence60', '')).toEqual([{ rotulo: 'Filtro', valor: 'Vence em até 60 dias' }]);
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
  // Carteira com as colunas PADRÃO (9). Com as 25 marcadas, a data quebra em 2 linhas
  // ("10/02/" + "2025"): continua legível, é o limite de 25 colunas numa folha A4.
  it('coluna de data comporta dd/mm/aaaa sem quebrar', () => {
    const contas = [conta()];
    const padrao = rascunhoCarteira(montarRelatorio(contas, COLUNAS_PADRAO, { canVerDoc: false, hotmartPorCard: null }), contas, []);
    for (const r of [padrao, ...seis().filter((x) => x.tipo !== 'board')]) {
      for (const s of r.secoes) {
        const larguras = larguraColunas(s);
        s.colunas.forEach((c, i) => {
          if (c.tipo === 'data') expect(caracteresPorLinha(larguras[i]), `${r.tipo}/${c.rotulo}`).toBeGreaterThanOrEqual(10);
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
