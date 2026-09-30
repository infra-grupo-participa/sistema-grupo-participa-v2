import { describe, expect, it } from 'vitest';
import {
  formDaFicha, lerMotivoFila, linkContratoSeguro, montarGradeContratos, normalizarLinhaMensal, normalizarPagamento,
  nomesDiferentesDaFicha, normalizarNome, normalizarSyncStatus, parcelasDoContrato, payloadFicha, podeDesfundir,
  type LinhaMensalContratoHF,
} from './contratos-hf';

/** Linha no formato do contrato de colunas da z93 (numeric como texto, como o PostgREST pode mandar). */
const L = (p: Record<string, unknown>): LinhaMensalContratoHF => normalizarLinhaMensal({
  contrato_id: 'c1', mes: '2026-09-01', nome: 'Ana', email: 'ana@example.com', telefone: null, cidade: 'Goiânia', uf: 'GO',
  cpf_final3: null, origem: 'planilha_drive', transacao_sinal: null, data_assinatura: '2026-08-10', assinado: 'sim',
  fechado_em: '2026-08-12', valor_bruto: '44640.00', valor_liquido: '40000.00', desconto_desc: null, entrada_valor: null,
  entrada_pct: null, link_contrato: 'https://docs.google.com/document/d/abc_1-X/edit', observacao: null, arquivado_em: null,
  esperado: '0', caiu_manual: '0', caiu_hotmart: '0', caiu_hotmart_liquido: '0', caiu: '0', a_receber_etapa: null,
  situacao: null, parcelas: [], ...p,
});

describe('normalização', () => {
  it('numeric em texto vira número; parcelas jsonb em texto é lida', () => {
    const l = L({ esperado: '1000.10', parcelas: JSON.stringify([{ id: 'p1', parcela_n: '2', parcela_de: 5, valor: '1000.10',
      data_prevista: '2026-09-15', situacao: 'baixado_fora', baixa_manual_em: '2026-09-15', transacao_hotmart: 'HP123' }]) });
    expect(l.esperado).toBe(1000.1);
    expect(l.valor_bruto).toBe(44640);
    expect(l.parcelas[0]).toMatchObject({ id: 'p1', parcela_n: 2, parcela_de: 5, valor: 1000.1, transacao_hotmart: 'HP123', etapa: null, observacao: null });
    expect(L({ parcelas: [{ id: 'p', observacao: 'cliente informado na colagem: Maria' }] }).parcelas[0].observacao)
      .toBe('cliente informado na colagem: Maria');
  });
  it('mes NULL fica null (linha de etapa); parcelas inválidas viram []', () => {
    expect(L({ mes: null }).mes).toBeNull();
    expect(L({ parcelas: '{quebrado' }).parcelas).toEqual([]);
    expect(L({ parcelas: null }).parcelas).toEqual([]);
  });
  it('pagamento: sync_erros inteiro, valor numérico', () => {
    const p = normalizarPagamento({ transacao: 'HP1', dia: '2026-09-20', valor: '12052.80', situacao: 'fila', sync_erros: '2' });
    expect(p).toMatchObject({ valor: 12052.8, sync_erros: 2, contrato_id: null, motivo: null });
  });
});

describe('grade contrato × mês', () => {
  const linhas = [
    L({ mes: '2026-09-01', esperado: '1000.10', caiu_manual: '1000.10', caiu: '1000.10', situacao: 'baixado_fora',
      parcelas: [{ id: 'p1', parcela_n: 1, parcela_de: 3, valor: 1000.1, data_prevista: '2026-09-10', situacao: 'baixado_fora', baixa_manual_em: '2026-09-10' }] }),
    L({ mes: '2026-10-01', esperado: '2000.20', caiu_hotmart: '500.00', caiu: '500.00', situacao: 'a_receber',
      parcelas: [{ id: 'p2', parcela_n: 2, parcela_de: 3, valor: 2000.2, data_prevista: '2026-10-10', situacao: 'a_receber' }] }),
    L({ mes: null, esperado: null, caiu_manual: null, caiu_hotmart: null, caiu: null, a_receber_etapa: '3000.30', situacao: 'a_receber_etapa',
      parcelas: [{ id: 'p3', parcela_n: 3, parcela_de: 3, valor: 3000.3, etapa: 'registros', situacao: 'a_receber_etapa' }] }),
    L({ contrato_id: 'c2', nome: 'Bia', mes: '2026-09-01', esperado: '0.10', caiu_manual: '0.20', caiu: '0.20', situacao: 'baixado_fora' }),
    L({ contrato_id: 'c2', nome: 'Bia', mes: '2026-10-01' }),
  ];
  const g = montarGradeContratos(linhas);

  it('um contrato por ficha, na ordem do SQL; meses em ordem; linha de etapa fora dos meses', () => {
    expect(g.contratos.map((c) => c.ficha.nome)).toEqual(['Ana', 'Bia']);
    expect(g.meses).toEqual(['2026-09-01', '2026-10-01']);
    expect(g.contratos[0].etapa).toMatchObject({ total: 3000.3 });
    expect(g.contratos[1].etapa).toBeNull();
  });
  it('totais por mês e geral somados em centavos (sem 0,30000000000000004); etapa à parte', () => {
    expect(g.totalMes['2026-09-01']).toEqual({ esperado: 1000.2, caiu_manual: 1000.3, caiu_hotmart: 0, caiu: 1000.3 });
    expect(g.totalMes['2026-10-01']).toEqual({ esperado: 2000.2, caiu_manual: 0, caiu_hotmart: 500, caiu: 500 });
    expect(g.total).toEqual({ esperado: 3000.4, caiu_manual: 1000.3, caiu_hotmart: 500, caiu: 1500.3 });
    expect(g.totalEtapa).toBe(3000.3);
    expect(g.contratos[0].total.esperado).toBe(3000.3);
  });
  it('parcelas do contrato: meses + etapa, sem repetir, pela parcela', () => {
    expect(parcelasDoContrato(g.contratos[0]).map((p) => p.id)).toEqual(['p1', 'p2', 'p3']);
  });
  it('sem linhas: grade vazia, totais zero', () => {
    expect(montarGradeContratos([])).toMatchObject({ meses: [], contratos: [], totalEtapa: 0, total: { esperado: 0, caiu: 0 } });
  });
});

describe('link do contrato (mesma regra do banco)', () => {
  it.each([
    'https://docs.google.com/document/d/1AbC_x-9/edit#heading=h.1',
    'https://drive.google.com/file/d/abc/view?usp=sharing',
  ])('aceita %s', (u) => expect(linkContratoSeguro(u)).toBe(u));
  it.each([
    ['javascript', 'javascript:alert(1)'],
    ['http sem s', 'http://docs.google.com/document/d/x'],
    ['subdomínio falso', 'https://docs.google.com.evil.com/x'],
    ['outro host', 'https://evil.com/https://docs.google.com/'],
    ['aspas', 'https://docs.google.com/x"onmouseover="alert(1)'],
    ['espaço', 'https://docs.google.com/x y'],
    ['não ASCII', 'https://docs.google.com/documentação'],
    ['quebra de linha no fim', 'https://docs.google.com/x\n'],
    ['sem barra após o host', 'https://docs.google.com'],
    ['data:', 'data:text/html,<script>alert(1)</script>'],
    ['longo demais', `https://docs.google.com/${'a'.repeat(480)}`],
  ])('recusa (%s)', (_n, u) => expect(linkContratoSeguro(u)).toBeNull());
  it('vazio / null → null', () => {
    expect(linkContratoSeguro(null)).toBeNull();
    expect(linkContratoSeguro('')).toBeNull();
  });
});

describe('fila de conferência', () => {
  it('prefixo estável → rótulo; frase do banco preservada', () => {
    expect(lerMotivoFila('valor_nao_bate: nenhuma parcela em aberto com esse valor (tolerância R$ 1,00 ou 1%).'))
      .toEqual({ rotulo: 'Valor não bate', frase: 'nenhuma parcela em aberto com esse valor (tolerância R$ 1,00 ou 1%).' });
    expect(lerMotivoFila('mais_de_um_contrato: o comprador está em 2 fichas vivas (fundir ou arquivar antes).').rotulo).toBe('Mais de um contrato');
    expect(lerMotivoFila('sem_contrato: nenhuma ficha viva deste comprador.').rotulo).toBe('Sem contrato');
  });
  it('prefixo desconhecido: texto cru (não disfarça); vazio: traço', () => {
    expect(lerMotivoFila('novo_motivo: algo')).toEqual({ rotulo: 'novo_motivo: algo', frase: null });
    expect(lerMotivoFila(null)).toEqual({ rotulo: '—', frase: null });
  });
  it('status da sincronização (RPC própria, 1 linha): inteiros; nunca rodou = tudo nulo; sem linha = igual', () => {
    expect(normalizarSyncStatus([{ ultima_em: '2026-09-29T12:25:00Z', fichas: '3', baixas: 2, desfeitas: 0, erros: '1', mensagem: 'falhou' }]))
      .toEqual({ ultima_em: '2026-09-29T12:25:00Z', fichas: 3, baixas: 2, desfeitas: 0, erros: 1, mensagem: 'falhou' });
    const nulo = { ultima_em: null, fichas: null, baixas: null, desfeitas: null, erros: null, mensagem: null };
    expect(normalizarSyncStatus([{ ultima_em: null, fichas: null, baixas: null, desfeitas: null, erros: null, mensagem: null }])).toEqual(nulo);
    expect(normalizarSyncStatus([])).toEqual(nulo);
  });
});

describe('ficha → fn_fin_contrato_hf_salvar', () => {
  const ficha = montarGradeContratos([L({})]).contratos[0].ficha;

  it('sem mudança: nada vai ao banco', () => {
    expect(payloadFicha(formDaFicha(ficha), ficha)).toEqual({ p: null, erros: ['Nada mudou.'] });
  });
  it('só as chaves que mudaram; valor como texto com ponto', () => {
    const f = { ...formDaFicha(ficha), valor_bruto: 'R$ 45.000,50', assinado: 'nao' as const };
    expect(payloadFicha(f, ficha)).toEqual({ p: { id: 'c1', valor_bruto: '45000.50', assinado: 'nao' }, erros: [] });
  });
  it('apagar link e data vai como null', () => {
    const f = { ...formDaFicha(ficha), link_contrato: '  ', data_assinatura: '' };
    expect(payloadFicha(f, ficha).p).toEqual({ id: 'c1', link_contrato: null, data_assinatura: null });
  });
  it('recusa local: link fora do Google, valor zero, data inválida', () => {
    const f = { ...formDaFicha(ficha), link_contrato: 'javascript:alert(1)', valor_liquido: '0', data_assinatura: '31/02/2026' };
    const r = payloadFicha(f, ficha);
    expect(r.p).toBeNull();
    expect(r.erros).toHaveLength(3);
  });
  it('desfundir só na ficha da planilha com sinal fundido e viva', () => {
    expect(podeDesfundir({ ...ficha, transacao_sinal: 'HP1' })).toBe(true);
    expect(podeDesfundir({ ...ficha, transacao_sinal: null })).toBe(false);
    expect(podeDesfundir({ ...ficha, transacao_sinal: 'HP1', origem: 'hotmart_sinal' })).toBe(false);
    expect(podeDesfundir({ ...ficha, transacao_sinal: 'HP1', arquivado_em: '2026-09-01T00:00:00Z' })).toBe(false);
  });
});

describe('colagem dentro da ficha', () => {
  it('mesma normalização do banco: minúsculas, sem acento, espaços colapsados', () => {
    expect(normalizarNome('  João   da SILVA ')).toBe('joao da silva');
    expect(normalizarNome(null)).toBe('');
  });
  it('nomes diferentes do da ficha: acento, caixa e espaço não contam; sem repetir; na ordem', () => {
    expect(nomesDiferentesDaFicha(['Ana Lúcia', 'ana  lucia', 'ANA LÚCIA'], 'Ana Lucia')).toEqual([]);
    expect(nomesDiferentesDaFicha(['Ana Lúcia', ' Maria ', 'maria', 'Bia'], 'Ana Lucia')).toEqual(['Maria', 'Bia']);
    expect(nomesDiferentesDaFicha(['Ana'], null)).toEqual(['Ana']);
  });
});
