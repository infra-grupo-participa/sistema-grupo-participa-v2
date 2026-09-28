import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  derivarCaixa, diasEntre, normalizarLinhaCaixa, normalizarTotaisCaixa, pegaAntesDaAntecipacao, periodoPadraoCaixa,
  semAntecipacao, somarDias, validarPeriodoCaixa,
} from './caixa-hotmart';

const L = (p: Record<string, unknown>) => normalizarLinhaCaixa({
  dia: '2026-09-01', liquido: '93.70', retido: '9.37', custo_antecipacao: '3.28', entra_rapido: '81.05',
  entra_em: '2026-09-03', retido_a_liberar: '0', libera_em: '2026-10-01', situacao_d2: 'recebido',
  situacao_retido: 'em_garantia', n_vendas: 1, ...p,
});

describe('normalizarLinhaCaixa / normalizarTotaisCaixa', () => {
  it('numeric como texto vira número; datas ficam ISO', () => {
    expect(L({})).toMatchObject({ liquido: 93.7, retido: 9.37, custoAntecipacao: 3.28, entraRapido: 81.05, nVendas: 1,
      entraEm: '2026-09-03', liberaEm: '2026-10-01', situacaoD2: 'recebido', situacaoRetido: 'em_garantia' });
  });
  it('sem premissa (fin.recebimento sem linha): datas nulas e sem situação, mesmo com o else do SQL', () => {
    const l = L({ retido: null, custo_antecipacao: null, entra_rapido: null, entra_em: null, libera_em: null,
      situacao_d2: 'a_receber', situacao_retido: 'em_garantia' });
    expect(l.entraEm).toBeNull();
    expect(l.situacaoD2).toBeNull();
    expect(l.situacaoRetido).toBeNull();
    expect(l.retido).toBe(0);
  });
  it('situação desconhecida vira null', () => {
    expect(L({ situacao_d2: 'x' }).situacaoD2).toBeNull();
  });
  it('totais: linha ausente vira zeros (nunca undefined na tela)', () => {
    expect(normalizarTotaisCaixa(undefined)).toEqual({
      liquido: 0, retido: 0, custoAntecipacao: 0, entraRapido: 0, retidoALiberar: 0, liquidoTotal: 0, nVendas: 0 });
    expect(normalizarTotaisCaixa({ liquido: '10.5', n_vendas: 3 }).liquido).toBe(10.5);
  });
});

describe('semAntecipacao (lido do dado, não da data)', () => {
  it('líquido sem D+2 e sem custo = antes do marco', () => {
    expect(semAntecipacao(L({ entra_rapido: 0, custo_antecipacao: 0, retido: '93.70' }))).toBe(true);
  });
  it('dia com antecipação, ou sem líquido, não', () => {
    expect(semAntecipacao(L({}))).toBe(false);
    expect(semAntecipacao(L({ liquido: 0, entra_rapido: 0, custo_antecipacao: 0 }))).toBe(false);
  });
});

describe('derivarCaixa', () => {
  it('já caiu = D+2 recebido; a cair = D+2 a receber; já liberado = retido − a liberar', () => {
    const linhas = [
      L({}),
      L({ dia: '2026-09-27', situacao_d2: 'a_receber', entra_rapido: '100.10' }),
      L({ dia: '2026-05-10', entra_rapido: 0, custo_antecipacao: 0, situacao_d2: 'recebido' }),
    ];
    const t = normalizarTotaisCaixa({ retido: '120', retido_a_liberar: '20.5' });
    expect(derivarCaixa(linhas, t)).toEqual({ jaCaiuD2: 81.05, aCairD2: 100.1, jaLiberado: 99.5 });
  });
});

describe('período', () => {
  it('validar: datas, invertido e janela de 400 dias (igual à RPC)', () => {
    expect(validarPeriodoCaixa('2026-06-01', '2026-09-28')).toEqual({ ok: true });
    expect(validarPeriodoCaixa('', '2026-09-28')).toEqual({ ok: false, motivo: 'datas' });
    expect(validarPeriodoCaixa('2026-09-28', '2026-09-01')).toEqual({ ok: false, motivo: 'invertido' });
    expect(validarPeriodoCaixa('2025-08-24', '2026-09-28')).toEqual({ ok: true }); // 400 dias: aceita
    expect(validarPeriodoCaixa('2025-08-23', '2026-09-28')).toEqual({ ok: false, motivo: 'janela' }); // 401
  });
  it('padrão: desde 01/06/2026 até hoje; depois de 400 dias, recua o início', () => {
    expect(periodoPadraoCaixa('2026-09-28')).toEqual({ de: '2026-06-01', ate: '2026-09-28' });
    const longe = periodoPadraoCaixa('2027-12-31');
    expect(diasEntre(longe.de, longe.ate)).toBe(400);
    expect(validarPeriodoCaixa(longe.de, longe.ate).ok).toBe(true);
  });
  it('aviso do marco só quando o período começa antes de 01/06/2026', () => {
    expect(pegaAntesDaAntecipacao('2026-05-31')).toBe(true);
    expect(pegaAntesDaAntecipacao('2026-06-01')).toBe(false);
  });
  it('somarDias atravessa mês e ano', () => {
    expect(somarDias('2026-12-31', 1)).toBe('2027-01-01');
    expect(somarDias('2026-03-01', -1)).toBe('2026-02-28');
  });
});

describe('contrato z68', () => {
  const sql = readFileSync(
    fileURLToPath(new URL('../../../../infra/supabase/migrations/20260928z68_fin_caixa_hotmart.sql', import.meta.url)), 'utf8');
  const colunas = (fn: string) => {
    const i = sql.indexOf(`create function public.${fn}(`);
    const ini = sql.indexOf('returns table (', i) + 'returns table ('.length;
    const fim = sql.indexOf('language plpgsql', ini);
    const bloco = sql.slice(ini, sql.lastIndexOf(')', fim));
    return bloco.split(',').map((c) => c.trim().split(/\s+/)[0]);
  };
  it('fn_fin_caixa_hotmart: toda coluna devolvida é lida pelo normalizador', () => {
    expect(colunas('fn_fin_caixa_hotmart')).toEqual([
      'dia', 'liquido', 'retido', 'custo_antecipacao', 'entra_rapido', 'entra_em', 'retido_a_liberar', 'libera_em',
      'situacao_d2', 'situacao_retido', 'n_vendas']);
  });
  it('fn_fin_caixa_hotmart_totais: idem', () => {
    expect(colunas('fn_fin_caixa_hotmart_totais')).toEqual([
      'liquido', 'retido', 'custo_antecipacao', 'entra_rapido', 'retido_a_liberar', 'liquido_total', 'n_vendas']);
  });
  it('janela da RPC = a validada no front', () => {
    expect(sql).toMatch(/p_fim - p_inicio > 400/);
  });
});
