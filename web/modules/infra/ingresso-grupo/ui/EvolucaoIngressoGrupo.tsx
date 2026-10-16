'use client';

import { useMemo } from 'react';
import { GraficoLinha } from '@/modules/infra/black/ui/graficos';
import { formatar } from '@/modules/infra/black/ui/pecas';
import { DataTable, EmptyState, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import {
  pontosEvolucaoIngresso, resumoEvolucaoIngresso, rotuloDiaCompleto, rotuloDiaCurto, temFonteDeGrupo,
  type PontoEvolucaoIngresso,
} from '../domain/evolucao';

/** Estado da série diária que o dashboard entrega ao modal. `data` nulo = ainda sem leitura bem-sucedida. */
export type EstadoSerieIngresso = {
  data: ReadonlyArray<Record<string, unknown>> | null;
  carregando?: boolean;
  erro?: string | null;
};

const semDado = (n: number | null) => (n === null ? '—' : formatar(n, 'int'));
const pctTexto = (p: number | null) => (p === null ? '—' : formatar(p / 100, 'pct'));

/**
 * Evolução diária do ingresso no grupo: PADRÃO de todo card de ingresso no grupo (Victor, 16/10/2026).
 * Gráfico de % ingresso (acumulado) e de entradas por dia, mais a tabela por data.
 * Regra: % ingresso = membros únicos no grupo ÷ leads, soma sobre soma do início do período até o dia (igual ao card).
 * Ausência de dado aparece como "—", nunca como 0.
 */
export function EvolucaoIngressoGrupo({ serie }: { serie: EstadoSerieIngresso }) {
  const pontos = useMemo<PontoEvolucaoIngresso[]>(() => (serie.data ? pontosEvolucaoIngresso(serie.data) : []), [serie.data]);
  const resumo = resumoEvolucaoIngresso(pontos);

  if (serie.data === null) {
    if (serie.carregando) return <Loading />;
    return <p role="alert" className="rounded border border-[var(--yellow)]/40 p-3 text-sm text-[var(--yellow)]">{serie.erro ?? 'Não foi possível carregar a evolução diária. Tente atualizar.'}</p>;
  }
  if (pontos.length === 0) {
    return <EmptyState title="Sem dias no período" hint="A série diária não trouxe nenhum dia para o período escolhido." />;
  }
  if (!temFonteDeGrupo(pontos)) {
    return <EmptyState title="Sem fonte de grupo para este projeto" hint="O grupo deste projeto ainda não está ligado a uma fonte de entradas, então não há evolução diária para mostrar." />;
  }

  return <div className="space-y-3">
    {serie.erro && <p role="status" className="text-xs text-[var(--yellow)]">A última atualização falhou. Os dados abaixo são os últimos carregados.</p>}
    <p className="text-sm text-[var(--fg-2)]">
      Período: <strong className="tabular text-[var(--fg)]">{semDado(resumo.entradas)}</strong> entradas únicas ÷ <strong className="tabular text-[var(--fg)]">{semDado(resumo.leads)}</strong> leads = <strong className="tabular text-[var(--fg)]">{pctTexto(resumo.pct)}</strong>
    </p>
    <div className="grid gap-3 lg:grid-cols-2">
      <section aria-label="% ingresso no grupo por dia">
        <h3 className="mb-1 text-xs font-semibold text-[var(--fg-2)]">% ingresso no grupo (acumulado)</h3>
        <GraficoLinha rotuloSerie="% ingresso no grupo" formato="pct" pontos={pontos.map((p) => ({ chave: p.dia, rotulo: rotuloDiaCurto(p.dia), valor: p.pct === null ? null : p.pct / 100 }))} />
      </section>
      <section aria-label="Entradas no grupo por dia">
        <h3 className="mb-1 text-xs font-semibold text-[var(--fg-2)]">Entradas únicas por dia</h3>
        <GraficoLinha rotuloSerie="Entradas no dia" formato="int" pontos={pontos.map((p) => ({ chave: p.dia, rotulo: rotuloDiaCurto(p.dia), valor: p.entradasDia }))} />
      </section>
    </div>
    <div className="max-h-[40vh] overflow-auto">
      <DataTable minWidth={560}>
        <Thead><Th>Data</Th><Th>Entradas no dia</Th><Th>Entradas acumuladas</Th><Th>Leads acumulados</Th><Th>% ingresso no grupo</Th></Thead>
        <tbody>{pontos.map((p) => <Tr key={p.dia}>
          <Td className="whitespace-nowrap">{rotuloDiaCompleto(p.dia)}</Td>
          <Td className="tabular">{semDado(p.entradasDia)}</Td>
          <Td className="tabular">{semDado(p.entradasAcumuladas)}</Td>
          <Td className="tabular">{semDado(p.leadsAcumulados)}</Td>
          <Td className="tabular">{pctTexto(p.pct)}</Td>
        </Tr>)}</tbody>
      </DataTable>
    </div>
    <p className="text-[11px] text-[var(--fg-3)]">Uma linha por dia. % ingresso no grupo = membros únicos que entraram no grupo ÷ leads, somados do início do período até o dia, com o mesmo critério do card. Dia sem leitura aparece como traço (—).</p>
  </div>;
}
