'use client';

// Faturamento diário — mantido sobre o mesmo caso de uso/RPC de antes
// (fn_fin_faturamento_diario inalterada), só reescrito na arquitetura nova.
//
// Redesign 2026-08-19: mini-métricas por linha (variação vs. dia anterior,
// posição vs. média móvel 7d) + sparkline da série + tratamento explícito de
// dias sem lançamento (comMetricas() preenche a lacuna com zero — ver
// domain/financeiro.ts para a decisão de não deixar a média mentir).
import { DataTable, EmptyState, KpiCard, Loading, SectionCard, Sparkline, Th, Thead, Td, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FaturamentoCarregado } from '../application/carregar-faturamento';
import type { DiaComMetricas } from '../domain/financeiro';

export function Faturamento({ dados, loading }: { dados: FaturamentoCarregado | null; loading: boolean }) {
  if (loading || !dados) return <Loading label="Carregando faturamento…" minHeight={240} />;
  const { dias, resumo } = dados;
  const serie = dias.map((d) => d.bruto);
  const diasPreenchidos = dias.filter((d) => d.preenchido).length;

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-2.5">
        <KpiCard label="Bruto no período" value={fmtBRL(resumo.bruto)} bar="accent" />
        <KpiCard label="Líquido no período" value={fmtBRL(resumo.liquido)} bar="green" hint={`taxas ${fmtBRL(resumo.taxas)}`} />
        <KpiCard label="Média diária" value={fmtBRL(resumo.media)} bar="purple" hint={`${resumo.dias} dia(s) com lançamento`} />
        <KpiCard label="Melhor dia" value={resumo.melhorDia ? fmtBRL(resumo.melhorDia.bruto) : '—'} bar="gray" hint={resumo.melhorDia ? fmtData(resumo.melhorDia.dia) : undefined} />
      </div>

      <SectionCard
        title="Regime de caixa"
        subtitle="O que entrou por dia de pagamento, mais antigo primeiro"
        right={diasPreenchidos > 0 ? (
          <span className="inline-flex items-center gap-1.5 rounded-[var(--r-sm)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] px-2 py-1 text-[11px] font-medium text-[var(--yellow)]">
            <Icon name="alert" size={12} />
            {diasPreenchidos} dia(s) sem lançamento no período — mostrados como R$ 0 explícito, não omitidos da média
          </span>
        ) : undefined}
      >
        {!dias.length ? (
          <EmptyState title="Nenhum lançamento no período" icon="trending-up" />
        ) : (
          <DataTable>
            <Thead>
              <Th>Dia</Th>
              <Th>Lançamentos</Th>
              <Th>Bruto</Th>
              <Th>Líquido</Th>
              <Th>vs. dia anterior</Th>
              <Th>vs. média 7d</Th>
              <Th>Série</Th>
              <Th>Acumulado</Th>
              <Th>Alunos</Th>
            </Thead>
            <tbody>
              {[...dias].reverse().map((d, i) => {
                // sparkline mostra os até 14 dias mais recentes ATÉ este ponto (série reversa: i cresce p/ trás no tempo).
                const idxOriginal = dias.length - 1 - i;
                const janela = serie.slice(Math.max(0, idxOriginal - 13), idxOriginal + 1);
                return <LinhaDia key={d.dia} dia={d} janela={janela} />;
              })}
            </tbody>
          </DataTable>
        )}
      </SectionCard>
    </div>
  );
}

function LinhaDia({ dia: d, janela }: { dia: DiaComMetricas; janela: number[] }) {
  return (
    <Tr className={d.preenchido ? 'opacity-60' : undefined}>
      <Td className="tabular text-[var(--fg)]">
        {fmtData(d.dia)}
        {d.preenchido && <span className="ml-1.5 text-[10px] font-medium text-[var(--yellow)]">sem lançamento</span>}
      </Td>
      <Td className="tabular text-[var(--fg-2)]">{d.lancamentos}</Td>
      <Td className="tabular font-semibold text-[var(--green)]">{fmtBRL(d.bruto)}</Td>
      <Td className="tabular text-[var(--fg-2)]">{fmtBRL(d.liquido)}</Td>
      <Td><VariacaoDia pct={d.variacaoDiaAnterior} /></Td>
      <Td><VsMedia pct={d.vsMedia7d} /></Td>
      <Td><Sparkline valores={janela} tone="var(--accent)" /></Td>
      <Td className="tabular text-[var(--fg-3)]">{fmtBRL(d.acumulado)}</Td>
      <Td className="tabular text-[var(--fg-2)]">{d.alunos}</Td>
    </Tr>
  );
}

/** Seta + percentual vs. dia anterior — verde alta, vermelho queda (token semântico, nunca âmbar). */
function VariacaoDia({ pct }: { pct: number | null }) {
  if (pct == null) return <span className="text-[11px] text-[var(--fg-4)]">—</span>;
  const subiu = pct >= 0;
  return (
    <span className={`inline-flex items-center gap-1 text-[11px] font-semibold tabular ${subiu ? 'text-[var(--green)]' : 'text-[var(--red)]'}`}>
      <Icon name={subiu ? 'arrow-up' : 'arrow-down'} size={12} />
      {Math.abs(pct).toFixed(0)}%
    </span>
  );
}

/** Posição vs. média móvel de 7 dias — texto + barra fina proporcional ao desvio (cap ±100%). */
function VsMedia({ pct }: { pct: number | null }) {
  if (pct == null) return <span className="text-[11px] text-[var(--fg-4)]">—</span>;
  const acima = pct >= 0;
  const largura = Math.min(100, Math.abs(pct));
  return (
    <div className="flex items-center gap-1.5 min-w-[72px]">
      <span className={`text-[11px] font-medium tabular shrink-0 ${acima ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}`}>
        {acima ? '+' : '−'}{Math.abs(pct).toFixed(0)}%
      </span>
      <div className="flex-1 h-1.5 rounded-[var(--r-pill)] bg-[var(--surface-3)] overflow-hidden" aria-hidden="true">
        <div
          className={`h-full rounded-[var(--r-pill)] ${acima ? 'bg-[var(--green)]' : 'bg-[var(--fg-4)]'}`}
          style={{ width: `${largura}%` }}
        />
      </div>
    </div>
  );
}
