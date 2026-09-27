'use client';

// Aba "Faturamento Diário" do financeiro (27/09/2026) — a fonte oficial do dinheiro.
//
// Lê o espelho da API da Hotmart (schema fin, sincronizado de hora em hora pela
// Edge Function hotmart-sync). SÓ LEITURA: nada aqui altera o board, os cards ou o
// que o financeiro já mostra. Bruto (valor da oferta) × líquido (o que fica para o produtor).
//
// Extraído de ui/Hotmart.tsx: as demais visões (Pessoas, Mesma pessoa?, Ofertas,
// Conciliação) saíram desta aba e vivem em ui/hotmart/*.
import { useEffect, useMemo, useState } from 'react';
import { DataTable, EmptyState, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import {
  QUEM_DIVIDE, REGRA_TAXA_HOTMART, resumirHotmart, ROTULO_FAMILIA, serieHotmart,
  type DiaHotmart, type FamiliaHotmart, type FunilHotmart, type SyncHotmart,
} from '../domain/hotmart';
import { Erro, isoDiasAtras, PERIODOS, SyncSelo, useCarga, Variacao } from './hotmart/comum';

export function FaturamentoDiario({ repo }: { repo: FinanceiroRepository }) {
  const [familia, setFamilia] = useState<FamiliaHotmart>('HM');
  const [sync, setSync] = useState<{ s: SyncHotmart; atrasado: boolean } | null>(null);

  useEffect(() => {
    repo.loadHotmartSync()
      .then((s) => setSync(s ? {
        s,
        // Rotina roda de hora em hora: mais de 3 h sem atualizar é sincronização parada.
        atrasado: !!s.ultima_atualizacao && Date.now() - new Date(s.ultima_atualizacao).getTime() > 3 * 3_600_000,
      } : null))
      .catch(() => setSync(null));
  }, [repo]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        {(['HM', 'AURUM', 'ACELERA'] as FamiliaHotmart[]).map((f) => (
          <button
            key={f}
            type="button"
            aria-pressed={familia === f}
            onClick={() => setFamilia(f)}
            className={`rounded-[var(--r-md)] border px-3 py-1.5 text-xs font-semibold disabled:opacity-50 ${familia === f ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}
          >
            {ROTULO_FAMILIA[f]}
          </button>
        ))}
        <SyncSelo sync={sync} />
      </div>

      <VisaoFaturamento repo={repo} familia={familia} />
    </div>
  );
}

// ─── Faturamento ────────────────────────────────────────────────────────────
function VisaoFaturamento({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const [intervalo, setIntervalo] = useState<{ de: string; ate: string; preset: number | null }>(
    { de: isoDiasAtras(29), ate: isoDiasAtras(0), preset: 30 });
  const { dados, erro } = useCarga<DiaHotmart[]>(
    () => repo.loadHotmartFaturamento(familia, intervalo.de, intervalo.ate), [familia, intervalo.de, intervalo.ate]);
  const resumo = useMemo(() => resumirHotmart(dados ?? []), [dados]);
  const serie = useMemo(() => serieHotmart(dados ?? []), [dados]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-1.5">
        {PERIODOS.map((p) => (
          <button key={p.dias} type="button" aria-pressed={intervalo.preset === p.dias}
            onClick={() => setIntervalo({ de: isoDiasAtras(p.dias - 1), ate: isoDiasAtras(0), preset: p.dias })}
            className={`rounded-[var(--r-sm)] border px-2.5 py-1 text-xs ${intervalo.preset === p.dias ? 'border-[var(--accent)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}>
            {p.rotulo}
          </button>
        ))}
        <span className="ml-2 text-xs text-[var(--fg-3)]">ou de</span>
        <input type="date" aria-label="Data inicial" value={intervalo.de} max={intervalo.ate}
          onChange={(e) => e.target.value && setIntervalo({ ...intervalo, de: e.target.value, preset: null })}
          className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs" />
        <span className="text-xs text-[var(--fg-3)]">até</span>
        <input type="date" aria-label="Data final" value={intervalo.ate} min={intervalo.de}
          onChange={(e) => e.target.value && setIntervalo({ ...intervalo, ate: e.target.value, preset: null })}
          className="rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs" />
      </div>
      {erro ? <Erro msg={erro} /> : !dados ? <Loading label="Carregando faturamento…" minHeight={200} /> : (
        <>
          <PorFunil repo={repo} familia={familia} de={intervalo.de} ate={intervalo.ate} />
          <SectionCard title="Dia a dia"
            subtitle={`Dia da aprovação do pagamento (horário de São Paulo); recusas e boletos contam no dia do pedido; dia sem venda aparece como R$ 0. Taxa da Hotmart: ${REGRA_TAXA_HOTMART[familia]}${resumo.taxaPct != null ? ` (${(resumo.taxaPct * 100).toFixed(2)}% do bruto no período)` : ''}. Juros são pagos pelo cliente e ficam com a Hotmart.${resumo.repasses > 0 ? ` Coprodução/afiliados: ${QUEM_DIVIDE[familia]}.` : ''}`}>
            {!serie.length ? <EmptyState title="Nenhuma movimentação no período" icon="trending-up" /> : (
              <DataTable minWidth={1100}>
                <Thead>
                  <Th>Dia</Th><Th>Vendas</Th><Th>Bruto</Th><Th>Taxa Hotmart</Th>
                  {resumo.repasses > 0 && <Th>Coprodução / afiliados</Th>}
                  <Th>Líquido</Th><Th>vs. dia anterior</Th><Th>Acumulado</Th><Th>Juros (cliente)</Th>
                  <Th>Reembolsos</Th><Th>Recusados</Th><Th>Boletos</Th>
                </Thead>
                <tbody>
                  {/* Total do período selecionado — primeira linha, antes dos dias (pedido do João, 27/09). */}
                  <Tr className="bg-[var(--surface-2)] font-semibold">
                    <Td className="whitespace-nowrap text-[var(--fg)]">Total do período</Td>
                    <Td className="tabular">{resumo.vendas}</Td>
                    <Td className="tabular">{fmtBRL(resumo.valorOferta)}</Td>
                    <Td className="tabular text-[var(--fg-2)]">{fmtBRL(resumo.taxa)}</Td>
                    {resumo.repasses > 0 && <Td className="tabular text-[var(--fg-2)]">{fmtBRL(resumo.repasses)}</Td>}
                    <Td className="whitespace-nowrap tabular text-[var(--green)]">
                      {fmtBRL(resumo.liquido)}
                      {resumo.margem != null && <span className="ml-1 text-[10px] font-normal text-[var(--fg-3)]">{(resumo.margem * 100).toFixed(1)}%</span>}
                    </Td>
                    <Td className="text-[var(--fg-4)]">—</Td>
                    <Td className="text-[var(--fg-4)]">—</Td>
                    <Td className="tabular text-[var(--fg-2)]">{resumo.juros ? fmtBRL(resumo.juros) : '—'}</Td>
                    <Td className="whitespace-nowrap tabular">{resumo.estornos > 0 ? <span className="text-[var(--red)]">{resumo.estornos} · {fmtBRL(resumo.valorEstornado)}</span> : '—'}</Td>
                    <Td className="tabular text-[var(--fg-2)]">{resumo.recusadas || '—'}</Td>
                    <Td className="tabular text-[var(--fg-2)]">{serie.reduce((a, d) => a + d.boletos, 0) || '—'}</Td>
                  </Tr>
                  {[...serie].reverse().map((d) => (
                    <Tr key={d.dia} className={d.preenchido ? 'opacity-60' : undefined}>
                      <Td className="whitespace-nowrap tabular">
                        {fmtData(d.dia)}
                        {d.preenchido && <span className="ml-1.5 text-[10px] font-medium text-[var(--fg-3)]">sem venda</span>}
                      </Td>
                      <Td className="tabular">{d.vendas}</Td>
                      <Td className="tabular font-semibold">{fmtBRL(d.bruto)}</Td>
                      <Td className="tabular text-[var(--fg-2)]">{fmtBRL(d.taxa)}</Td>
                      {resumo.repasses > 0 && <Td className="tabular text-[var(--fg-2)]">{d.repasses > 0 ? fmtBRL(d.repasses) : '—'}</Td>}
                      <Td className="tabular font-semibold text-[var(--green)]">
                        {fmtBRL(d.liquido)}
                        {d.liquidoEstimado > 0 && <span className="ml-1 text-[10px] text-[var(--fg-3)]" title="Sem comissão na API: líquido = oferta − taxa">≈</span>}
                      </Td>
                      <Td><Variacao pct={d.variacaoDiaAnterior} /></Td>
                      <Td className="tabular text-[var(--fg-3)]">{fmtBRL(d.acumulado)}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.juros ? fmtBRL(d.juros) : '—'}</Td>
                      <Td className="tabular">{d.estornos > 0 ? <span className="text-[var(--red)]">{d.estornos} · {fmtBRL(d.valorEstornado)}</span> : '—'}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.recusadas || '—'}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.boletos || '—'}</Td>
                    </Tr>
                  ))}
                </tbody>
              </DataTable>
            )}
          </SectionCard>
        </>
      )}
    </div>
  );
}

/** Faturamento por funil (janelas de fin.funis). Só aparece quando a família tem funil cadastrado. */
function PorFunil({ repo, familia, de, ate }: { repo: FinanceiroRepository; familia: FamiliaHotmart; de: string; ate: string }) {
  const { dados, erro } = useCarga<FunilHotmart[]>(() => repo.loadHotmartFunis(familia, de, ate), [familia, de, ate]);
  if (erro) return <Erro msg={erro} />;
  if (!dados || !dados.some((f) => f.funil !== 'Sem funil')) return null;
  const n = (v: unknown) => Number(v ?? 0) || 0;
  return (
    <SectionCard title="Por funil" subtitle="De onde veio cada venda (janela de datas do funil). Juros e parcelamento mostram como o cliente pagou.">
      <DataTable minWidth={1000}>
        <Thead>
          <Th>Funil</Th><Th>Vendas</Th><Th>Compradores</Th><Th>Bruto</Th><Th>Taxa Hotmart</Th><Th>Líquido</Th>
          <Th>Cliente pagou (c/ juros)</Th><Th>Parcelado</Th><Th>Reembolsos</Th><Th>Recusados</Th>
        </Thead>
        <tbody>
          {dados.map((f) => (
            <Tr key={f.funil}>
              <Td className="font-medium">{f.funil}</Td>
              <Td className="tabular">{f.vendas}</Td>
              <Td className="tabular">{f.compradores}</Td>
              <Td className="tabular font-semibold">{fmtBRL(n(f.valor_oferta))}</Td>
              <Td className="tabular text-[var(--fg-2)]">{fmtBRL(n(f.taxa_hotmart))}</Td>
              <Td className="tabular font-semibold text-[var(--green)]">{fmtBRL(n(f.liquido))}</Td>
              <Td className="tabular text-[var(--fg-2)]">{fmtBRL(n(f.cobrado_cliente))}<span className="ml-1 text-[10px] text-[var(--fg-3)]">juros {fmtBRL(n(f.juros))}</span></Td>
              <Td className="tabular text-[var(--fg-2)]">{f.vendas ? `${f.parcelado} de ${f.vendas}` : '—'}{f.parcelas_media ? <span className="ml-1 text-[10px] text-[var(--fg-3)]">média {Number(f.parcelas_media).toFixed(1)}x</span> : null}</Td>
              <Td className="tabular">{f.estornos ? <span className="text-[var(--red)]">{f.estornos} · {fmtBRL(n(f.valor_estornado))}</span> : '—'}</Td>
              <Td className="tabular text-[var(--fg-3)]">{f.recusadas || '—'}</Td>
            </Tr>
          ))}
        </tbody>
      </DataTable>
    </SectionCard>
  );
}
