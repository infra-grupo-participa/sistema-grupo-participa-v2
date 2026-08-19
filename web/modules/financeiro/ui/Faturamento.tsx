'use client';

// Faturamento diário — mantido sobre o mesmo caso de uso/RPC de antes
// (fn_fin_faturamento_diario inalterada), só reescrito na arquitetura nova.
import { DataTable, EmptyState, KpiCard, Loading, SectionCard, Th, Thead, Td, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FaturamentoCarregado } from '../application/carregar-faturamento';

export function Faturamento({ dados, loading }: { dados: FaturamentoCarregado | null; loading: boolean }) {
  if (loading || !dados) return <Loading label="Carregando faturamento…" minHeight={240} />;
  const { dias, resumo } = dados;

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-2.5">
        <KpiCard label="Bruto no período" value={fmtBRL(resumo.bruto)} bar="accent" />
        <KpiCard label="Líquido no período" value={fmtBRL(resumo.liquido)} bar="green" hint={`taxas ${fmtBRL(resumo.taxas)}`} />
        <KpiCard label="Média diária" value={fmtBRL(resumo.media)} bar="purple" hint={`${resumo.dias} dia(s) com lançamento`} />
        <KpiCard label="Melhor dia" value={resumo.melhorDia ? fmtBRL(resumo.melhorDia.bruto) : '—'} bar="gray" hint={resumo.melhorDia ? fmtData(resumo.melhorDia.dia) : undefined} />
      </div>

      <SectionCard title="Regime de caixa" subtitle="O que entrou por dia de pagamento, mais antigo primeiro">
        {!dias.length ? (
          <EmptyState title="Nenhum lançamento no período" icon="trending-up" />
        ) : (
          <DataTable>
            <Thead>
              <Th>Dia</Th>
              <Th>Lançamentos</Th>
              <Th>Bruto</Th>
              <Th>Líquido</Th>
              <Th>Acumulado</Th>
              <Th>Alunos</Th>
            </Thead>
            <tbody>
              {[...dias].reverse().map((d) => (
                <Tr key={d.dia}>
                  <Td className="tabular text-[var(--fg)]">{fmtData(d.dia)}</Td>
                  <Td className="tabular text-[var(--fg-2)]">{d.lancamentos}</Td>
                  <Td className="tabular font-semibold text-[var(--green)]">{fmtBRL(d.bruto)}</Td>
                  <Td className="tabular text-[var(--fg-2)]">{fmtBRL(d.liquido)}</Td>
                  <Td className="tabular text-[var(--fg-3)]">{fmtBRL(d.acumulado)}</Td>
                  <Td className="tabular text-[var(--fg-2)]">{d.alunos}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>
    </div>
  );
}
