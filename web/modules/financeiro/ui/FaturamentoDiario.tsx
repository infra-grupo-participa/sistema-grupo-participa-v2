'use client';

// Aba "Faturamento" do financeiro (27/09/2026) — a fonte oficial do dinheiro. Visões diária, mensal e anual,
// cada uma com o gráfico de linha no topo e a tabela embaixo.
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
import { FAMILIAS_EM_ORDEM,
  agruparFaturamento, resumirHotmart, ROTULO_FAMILIA, serieHotmart,
  type DiaHotmart, type FamiliaHotmart, type FunilHotmart, type GranularidadeFaturamento, type SyncHotmart,
} from '../domain/hotmart';
import { Erro, isoDiasAtras, PERIODOS, SyncSelo, useCarga, Variacao } from './hotmart/comum';
import { GraficoLinha } from './hotmart/GraficoLinha';

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
        {FAMILIAS_EM_ORDEM.map((f) => (
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
const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const VISOES: { g: GranularidadeFaturamento; rotulo: string; preset: number }[] = [
  { g: 'dia', rotulo: 'Diário', preset: 30 },
  { g: 'mes', rotulo: 'Mensal', preset: 365 },
  { g: 'ano', rotulo: 'Anual', preset: PERIODOS[PERIODOS.length - 1].dias },
];

/** Rótulo completo e curto (eixo) de um período: 27/09/2026 · set/2026 · 2026. */
function rotulos(chave: string, g: GranularidadeFaturamento): { rotulo: string; curto: string } {
  if (g === 'ano') return { rotulo: chave, curto: chave };
  const [y, m, d] = chave.split('-');
  if (g === 'mes') return { rotulo: `${MESES[Number(m) - 1]}/${y}`, curto: `${MESES[Number(m) - 1]}/${y.slice(2)}` };
  return { rotulo: fmtData(chave), curto: `${d}/${m}` };
}

function VisaoFaturamento({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const [visao, setVisao] = useState<GranularidadeFaturamento>('dia');
  const [intervalo, setIntervalo] = useState<{ de: string; ate: string; preset: number | null }>(
    { de: isoDiasAtras(29), ate: isoDiasAtras(0), preset: 30 });
  const { dados, erro } = useCarga<DiaHotmart[]>(
    () => repo.loadHotmartFaturamento(familia, intervalo.de, intervalo.ate), [familia, intervalo.de, intervalo.ate]);
  const resumo = useMemo(() => resumirHotmart(dados ?? []), [dados]);
  const serie = useMemo(() => serieHotmart(dados ?? []), [dados]);
  const periodos = useMemo(() => agruparFaturamento(serie, visao), [serie, visao]);
  const pontos = useMemo(
    () => periodos.map((p) => ({ ...rotulos(p.chave, visao), bruto: p.bruto, liquido: p.liquido, vendas: p.vendas })),
    [periodos, visao]);
  // Funis e Análise viraram a aba "Funis" do menu (limpeza de 28/09) — ui/hotmart/FunisEAnalise.
  const analise = false;

  // Trocar de visão já leva a um período que faz sentido para ela (30 dias / 12 meses / tudo); dá para mudar depois.
  const escolherVisao = (v: (typeof VISOES)[number]) => {
    setVisao(v.g);
    setIntervalo({ de: isoDiasAtras(v.preset - 1), ate: isoDiasAtras(0), preset: v.preset });
  };
  const nomeVisao = VISOES.find((v) => v.g === visao)!.rotulo;
  const cabecalho = visao === 'dia' ? 'Dia' : visao === 'mes' ? 'Mês' : 'Ano';
  const unidade = visao === 'dia' ? 'dia' : visao === 'mes' ? 'mês' : 'ano';

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-1.5">
        <div className="mr-2 flex overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]" role="group" aria-label="Visão do faturamento">
          {VISOES.map((v) => (
            <button key={v.g} type="button" aria-pressed={!analise && visao === v.g} onClick={() => escolherVisao(v)}
              className={`px-3 py-1.5 text-xs font-semibold ${!analise && visao === v.g ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
              {v.rotulo}
            </button>
          ))}
        </div>
        {!analise && <>
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
        </>}
      </div>
      {erro ? <Erro msg={erro} /> : !dados ? <Loading label="Carregando faturamento…" minHeight={200} /> : (
        <>
          {pontos.length >= 2 ? (
            <GraficoLinha
              pontos={pontos}
              titulo={`Faturamento ${nomeVisao.toLowerCase()} · ${ROTULO_FAMILIA[familia]} · ${fmtData(intervalo.de)} a ${fmtData(intervalo.ate)}`}
            />
          ) : pontos.length === 1 ? (
            <p className="text-xs text-[var(--fg-3)]">
              O período escolhido cabe num {unidade} só; o gráfico aparece a partir de dois. Escolha um período maior ou a visão {visao === 'ano' ? 'mensal' : 'diária'}.
            </p>
          ) : null}
          <SectionCard title={visao === 'dia' ? 'Dia a dia' : visao === 'mes' ? 'Mês a mês' : 'Ano a ano'}>
            {!periodos.length ? <EmptyState title="Nenhuma movimentação no período" icon="trending-up" /> : (
              <DataTable minWidth={1100}>
                <Thead>
                  <Th>{cabecalho}</Th><Th>Vendas</Th><Th>Bruto</Th><Th>Taxa Hotmart</Th>
                  {resumo.repasses > 0 && <Th>Coprodução / afiliados</Th>}
                  <Th>Líquido</Th><Th>vs. {unidade} anterior</Th><Th>Acumulado</Th><Th>Juros (cliente)</Th>
                  <Th>Reembolsos</Th><Th>Recusados</Th><Th>Boletos</Th>
                </Thead>
                <tbody>
                  {/* Total do período selecionado — primeira linha (pedido do João, 27/09). */}
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
                  {[...periodos].reverse().map((d) => (
                    <Tr key={d.chave} className={d.vazio ? 'opacity-60' : undefined}>
                      <Td className="whitespace-nowrap tabular">
                        {rotulos(d.chave, visao).rotulo}
                        {d.vazio && <span className="ml-1.5 text-[10px] font-medium text-[var(--fg-3)]">sem venda</span>}
                      </Td>
                      <Td className="tabular">{d.vendas}</Td>
                      <Td className="tabular font-semibold">{fmtBRL(d.bruto)}</Td>
                      <Td className="tabular text-[var(--fg-2)]">{fmtBRL(d.taxa)}</Td>
                      {resumo.repasses > 0 && <Td className="tabular text-[var(--fg-2)]">{d.repasses > 0 ? fmtBRL(d.repasses) : '—'}</Td>}
                      <Td className="tabular font-semibold text-[var(--green)]">
                        {fmtBRL(d.liquido)}
                        {d.liquidoEstimado > 0 && <span className="ml-1 text-[10px] text-[var(--fg-3)]" title="Sem comissão na API: líquido = oferta − taxa">≈</span>}
                      </Td>
                      <Td><Variacao pct={d.variacao} /></Td>
                      <Td className="tabular text-[var(--fg-3)]">{fmtBRL(d.acumulado)}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.juros ? fmtBRL(d.juros) : '—'}</Td>
                      <Td className="whitespace-nowrap tabular">{d.estornos > 0 ? <span className="text-[var(--red)]">{d.estornos} · {fmtBRL(d.valorEstornado)}</span> : '—'}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.recusadas || '—'}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{d.boletos || '—'}</Td>
                    </Tr>
                  ))}
                </tbody>
              </DataTable>
            )}
          </SectionCard>
          <PorFunil repo={repo} familia={familia} de={intervalo.de} ate={intervalo.ate} />
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
    <SectionCard title="Por funil">
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
