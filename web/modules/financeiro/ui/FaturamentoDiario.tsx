'use client';

// Faturamento Diário do HM — a "planilha que se atualiza dia após dia".
// Regime de caixa: uma linha por dia com pagamento, mais recente no topo.
import { useMemo, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { DiaFaturamento } from '../domain/types';
import { comAcumulado, resumirFaturamento } from '../domain/financeiro';
import { exportarExcelFaturamento } from './faturamento-export';
import {
  Button, DataTable, EmptyState, KpiCard, SkeletonRows, Td, Th, Thead, Tr,
} from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';

export function FaturamentoDiario({ dias, loading, turma }: {
  dias: DiaFaturamento[];
  loading: boolean;
  turma: string | null;
}) {
  const hojeISO = new Date().toISOString().slice(0, 10);
  const linhas = useMemo(() => comAcumulado(dias), [dias]);
  const r = useMemo(() => resumirFaturamento(dias, hojeISO), [dias, hojeISO]);
  const melhorDia = dias.length > 1 ? r.melhorDia?.dia ?? null : null;

  const tot = useMemo(() => {
    const soma = (f: (d: DiaFaturamento) => number) => dias.reduce((a, d) => a + f(d), 0);
    return {
      lancamentos: soma((d) => d.lancamentos),
      bruto: soma((d) => d.bruto),
      liquido: soma((d) => d.liquido),
      taxas: soma((d) => d.taxas),
      sinal: soma((d) => d.sinal ?? 0),
      saldo: soma((d) => d.saldo ?? 0),
      mensalidade: soma((d) => d.mensalidade ?? 0),
      compraCheia: soma((d) => d.compra_cheia ?? 0),
    };
  }, [dias]);

  const [exportando, setExportando] = useState(false);
  const exportar = async () => {
    setExportando(true);
    try {
      await exportarExcelFaturamento(linhas, turma);
    } finally {
      setExportando(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <KpiCard label="Entrou hoje" bar="green" value={loading ? '—' : fmtBRL(r.hoje?.bruto ?? 0)} hint={fmtData(hojeISO)} />
        <KpiCard label="Total no período" bar="accent" value={loading ? '—' : fmtBRL(r.bruto)} hint={loading ? undefined : `líquido ${fmtBRL(r.liquido)} · taxas ${fmtBRL(r.taxas)}`} />
        <KpiCard label="Média/dia" bar="accent" value={loading ? '—' : fmtBRL(r.media)} hint={loading ? undefined : `${r.dias} ${r.dias === 1 ? 'dia' : 'dias'} com lançamento`} />
        <KpiCard label="Melhor dia" bar="purple" value={loading ? '—' : fmtBRL(r.melhorDia?.bruto ?? null)} hint={!loading && r.melhorDia ? fmtData(r.melhorDia.dia) : undefined} />
      </div>

      {!loading && !dias.length ? (
        <EmptyState title="Sem faturamento no período" icon="wallet" />
      ) : (
        <>
          <div className="flex items-center justify-end gap-3">
            <span className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{dias.length} {dias.length === 1 ? 'dia' : 'dias'}</span>
            <Button variant="ghost" size="sm" onClick={exportar} disabled={exportando || loading || !linhas.length} title="Exportar a planilha diária (.xlsx)">
              <Icon name="download" size={14} /> {exportando ? 'Gerando…' : 'Exportar Excel'}
            </Button>
          </div>

          <DataTable>
            <Thead>
              <Th>Dia</Th>
              <Th className="text-right">Lançamentos</Th>
              <Th className="text-right">Bruto</Th>
              <Th className="text-right">Líquido</Th>
              <Th className="text-right">Taxas</Th>
              <Th className="text-right">Sinal</Th>
              <Th className="text-right">Saldo</Th>
              <Th className="text-right">Mensalidade</Th>
              <Th className="text-right">Compra cheia</Th>
              <Th className="text-right">Acumulado</Th>
              <Th className="text-right">Alunos</Th>
            </Thead>
            <tbody>
              {loading
                ? <SkeletonRows avatar={false} cols={[70, 40, 70, 70, 56, 56, 56, 56, 56, 80, 32]} />
                : linhas.map((d) => {
                  const ehHoje = d.dia === hojeISO;
                  const ehMelhor = d.dia === melhorDia;
                  return (
                    <Tr
                      key={d.dia}
                      className={ehHoje ? 'bg-[var(--accent-subtle)]' : ehMelhor ? 'bg-[var(--surface-3)]' : ''}
                      style={ehHoje ? { boxShadow: 'inset 3px 0 0 var(--accent)' } : undefined}
                    >
                      <Td className="whitespace-nowrap">
                        <span className={`tabular text-xs ${ehHoje ? 'font-semibold text-[var(--fg)]' : 'text-[var(--fg-2)]'}`}>{fmtData(d.dia)}</span>
                        {ehHoje && <span className="ml-2 text-[10px] font-semibold uppercase tracking-wide text-[var(--accent)]">hoje</span>}
                        {ehMelhor && !ehHoje && <span className="ml-2 text-[10px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">melhor dia</span>}
                      </Td>
                      <Td className="tabular text-xs text-right text-[var(--fg-3)]">{d.lancamentos}</Td>
                      <Td className={`tabular text-xs text-right font-semibold ${ehMelhor ? 'text-[var(--green)]' : 'text-[var(--fg)]'}`}>{fmtBRL(d.bruto)}</Td>
                      <Td className="tabular text-xs text-right text-[var(--fg-2)]">{fmtBRL(d.liquido)}</Td>
                      <Td className="tabular text-xs text-right text-[var(--fg-3)]">{fmtBRL(d.taxas)}</Td>
                      <Td className="tabular text-xs text-right text-[var(--fg-2)]">{fmtBRL(d.sinal)}</Td>
                      <Td className="tabular text-xs text-right text-[var(--fg-2)]">{fmtBRL(d.saldo)}</Td>
                      <Td className="tabular text-xs text-right text-[var(--fg-2)]">{fmtBRL(d.mensalidade)}</Td>
                      <Td className="tabular text-xs text-right text-[var(--fg-2)]">{fmtBRL(d.compra_cheia)}</Td>
                      <Td className="tabular text-xs text-right font-semibold text-[var(--fg)]">{fmtBRL(d.acumulado)}</Td>
                      <Td className="tabular text-xs text-right text-[var(--fg-3)]">{d.alunos}</Td>
                    </Tr>
                  );
                })}
            </tbody>
            {!loading && linhas.length > 0 && (
              <tfoot>
                <tr className="border-t border-[var(--border)] bg-[var(--surface-3)] text-xs">
                  <td className="px-3 py-2 font-semibold text-[var(--fg-2)]">Total</td>
                  <td className="px-3 py-2 tabular text-right font-semibold text-[var(--fg-2)]">{tot.lancamentos}</td>
                  <td className="px-3 py-2 tabular text-right font-semibold text-[var(--fg)]">{fmtBRL(tot.bruto)}</td>
                  <td className="px-3 py-2 tabular text-right font-semibold text-[var(--fg)]">{fmtBRL(tot.liquido)}</td>
                  <td className="px-3 py-2 tabular text-right font-semibold text-[var(--fg-3)]">{fmtBRL(tot.taxas)}</td>
                  <td className="px-3 py-2 tabular text-right font-semibold text-[var(--fg-2)]">{fmtBRL(tot.sinal)}</td>
                  <td className="px-3 py-2 tabular text-right font-semibold text-[var(--fg-2)]">{fmtBRL(tot.saldo)}</td>
                  <td className="px-3 py-2 tabular text-right font-semibold text-[var(--fg-2)]">{fmtBRL(tot.mensalidade)}</td>
                  <td className="px-3 py-2 tabular text-right font-semibold text-[var(--fg-2)]">{fmtBRL(tot.compraCheia)}</td>
                  <td className="px-3 py-2 text-right text-[var(--fg-3)]">—</td>
                  <td className="px-3 py-2 text-right text-[var(--fg-3)]">—</td>
                </tr>
              </tfoot>
            )}
          </DataTable>
        </>
      )}
    </div>
  );
}
