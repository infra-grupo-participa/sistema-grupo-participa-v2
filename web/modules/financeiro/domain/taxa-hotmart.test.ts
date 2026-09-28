import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  COLUNAS_TAXA_AUDITORIA, COLUNAS_TAXA_DIVERGENCIAS, csvDivergencias, montarAuditoriaTaxa, normalizarDivergencia,
  periodo12MesesTaxa, periodoPadraoTaxa,
} from './taxa-hotmart';
import { validarPeriodoCaixa } from './caixa-hotmart';

const produto = (o: Record<string, unknown>) => ({
  tipo: 'a_vista', produto_id: 'p1', produto_nome: 'Holding Masters', grupo_acordo: '4% + R$ 1,00',
  sem_acordo_especifico: false, parcelas: 1, n_vendas: 10, n_sem_taxa: 0, valor_oferta: '100000.00',
  taxa_real_rs: '4010.00', taxa_esperada_rs: '4010.00', taxa_real_pct: '4.010', taxa_esperada_pct: '4.010',
  n_divergentes: 0, impacto_rs: '0.00', impacto_divergentes_rs: '0.00', taxa_cliente_pct: null, ...o,
});
const parcela = (n: number, o: Record<string, unknown> = {}) => ({
  tipo: 'parcelado', produto_id: null, produto_nome: null, grupo_acordo: null, sem_acordo_especifico: null,
  parcelas: n, n_vendas: 3, n_sem_taxa: 1, valor_oferta: '3000', taxa_real_rs: '160', taxa_esperada_rs: null,
  taxa_real_pct: '5.3', taxa_esperada_pct: null, n_divergentes: null, impacto_rs: null, impacto_divergentes_rs: null,
  taxa_cliente_pct: String(5 + n), ...o,
});

describe('montarAuditoriaTaxa', () => {
  it('separa à vista (ordem do SQL) e parcelado (1..12); numeric em texto vira número', () => {
    const a = montarAuditoriaTaxa([
      produto({}), produto({ produto_id: 'p2', produto_nome: 'Clínica ', grupo_acordo: '5,3% + R$ 1,00', n_vendas: 5 }),
      parcela(2), parcela(1),
    ]);
    expect(a.produtos.map((p) => p.produtoNome)).toEqual(['Holding Masters', 'Clínica']);
    expect(a.produtos[0]).toMatchObject({ valorOferta: 100000, taxaRealPct: 4.01, grupoAcordo: '4% + R$ 1,00' });
    expect(a.parcelas.map((p) => p.parcelas)).toEqual([1, 2]);
    expect(a.parcelas[0]).toMatchObject({ nVendas: 4, taxaClientePct: 6 }); // com e sem taxa informada
  });
  it('resumo: soma vendas, divergentes e impacto só das divergentes; conta sem acordo específico', () => {
    const { resumo } = montarAuditoriaTaxa([
      produto({ n_divergentes: 2, impacto_rs: '30.10', impacto_divergentes_rs: '25.10', n_sem_taxa: 1 }),
      produto({ produto_id: 'p2', sem_acordo_especifico: true, n_vendas: 5, n_divergentes: 1, impacto_divergentes_rs: '-12' }),
    ]);
    expect(resumo).toEqual({ nVendas: 15, nSemTaxa: 1, nDivergentes: 3, impactoDivergentes: 13.1, nProdutos: 2, nSemAcordoEspecifico: 1 });
  });
  it('parcela sem venda: percentual nulo (não 0%)', () => {
    const { parcelas } = montarAuditoriaTaxa([parcela(12, { n_vendas: 0, n_sem_taxa: 0, taxa_cliente_pct: null })]);
    expect(parcelas[0].taxaClientePct).toBeNull();
  });
  it('vazio: resumo zerado', () => {
    expect(montarAuditoriaTaxa([]).resumo.nVendas).toBe(0);
  });
});

describe('período', () => {
  it('padrão = 1º de janeiro do ano corrente até hoje, dentro dos 400 dias', () => {
    const p = periodoPadraoTaxa('2026-12-31');
    expect(p).toEqual({ de: '2026-01-01', ate: '2026-12-31' });
    expect(validarPeriodoCaixa(p.de, p.ate).ok).toBe(true);
  });
  it('12 meses = 365 dias', () => {
    expect(periodo12MesesTaxa('2026-09-28')).toEqual({ de: '2025-09-29', ate: '2026-09-28' });
  });
});

describe('csvDivergencias', () => {
  it('sem dado pessoal, decimal com vírgula, célula perigosa neutralizada', () => {
    const d = normalizarDivergencia({ transacao: 'HP123', dia: '2026-03-02', produto_id: 'p', produto_nome: '=CMD()',
      valor_oferta: '1000', taxa_real: '70.00', taxa_esperada: '54.00', diferenca: '16.00' });
    const [cab, linha] = csvDivergencias([d]).split('\n');
    expect(cab).toBe('Transação;Dia;Produto;Valor da oferta;Taxa cobrada;Taxa do acordo;Diferença');
    expect(linha).toBe("HP123;2026-03-02;'=CMD();1000,00;70,00;54,00;16,00");
    expect(cab).not.toMatch(/nome|e-mail|documento/i);
  });
});

// Contrato com a z70: tsc não vê SQL. RETURNS TABLE = colunas que o front lê.
describe('contrato z70', () => {
  const sql = readFileSync(fileURLToPath(new URL(
    '../../../../infra/supabase/migrations/20260928z70_fin_taxa_hotmart_auditoria.sql', import.meta.url)), 'utf8');
  const colunas = (fn: string) => {
    const i = sql.indexOf(`create function public.${fn}(`);
    expect(i).toBeGreaterThan(-1);
    const trecho = sql.slice(sql.indexOf('returns table (', i) + 'returns table ('.length);
    return trecho.slice(0, trecho.indexOf(')')).split(',').map((c) => c.trim().split(/\s+/)[0]);
  };
  it('fn_fin_taxa_auditoria', () => expect(colunas('fn_fin_taxa_auditoria')).toEqual([...COLUNAS_TAXA_AUDITORIA]));
  it('fn_fin_taxa_divergencias', () => expect(colunas('fn_fin_taxa_divergencias')).toEqual([...COLUNAS_TAXA_DIVERGENCIAS]));
});
