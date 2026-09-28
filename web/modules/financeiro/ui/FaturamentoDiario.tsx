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
import {
  agruparFaturamento, resumirHotmart, ROTULO_FAMILIA, serieHotmart,
  type DiaHotmart, type FamiliaHotmart, type FunilHotmart, type GranularidadeFaturamento, type PeriodoFaturamento, type SyncHotmart,
} from '../domain/hotmart';
import { Erro, isoDiasAtras, PERIODOS, SyncSelo, useCarga, Variacao } from './hotmart/comum';
import { GraficoLinha } from './hotmart/GraficoLinha';
import { alinharAnterior, intervaloAnterior, mediaMovel, projetarPeriodoAtual } from '../domain/faturamento-analise';
import { hojeSaoPaulo } from '../domain/prorata-hm';

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

  // Painel de cruzamentos (27/09): camadas ligáveis, ponto fixado por clique e projeção pelo ritmo.
  const [camadas, setCamadas] = useState({ anterior: false, media: false, vendas: false });
  const [fixado, setFixado] = useState<string | null>(null);
  const ant = intervaloAnterior(intervalo.de, intervalo.ate);
  const { dados: dadosAnt } = useCarga<DiaHotmart[] | null>(
    () => (camadas.anterior ? repo.loadHotmartFaturamento(familia, ant.de, ant.ate) : Promise.resolve(null)),
    [familia, ant.de, ant.ate, camadas.anterior]);
  const anterior = useMemo(
    () => (camadas.anterior && dadosAnt ? alinharAnterior(periodos, agruparFaturamento(serieHotmart(dadosAnt), visao)) : null),
    [camadas.anterior, dadosAnt, periodos, visao]);
  const media = useMemo(
    () => (camadas.media ? mediaMovel(periodos.map((p) => p.bruto), visao === 'dia' ? 7 : 3) : null),
    [camadas.media, periodos, visao]);
  const projecao = useMemo(
    () => projetarPeriodoAtual(serie.map((d) => ({ dia: d.dia, bruto: d.bruto })), visao, hojeSaoPaulo(), intervalo.ate),
    [serie, visao, intervalo.ate]);
  const idxFixado = fixado ? periodos.findIndex((p) => p.chave === fixado) : -1;

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
            <button key={v.g} type="button" aria-pressed={visao === v.g} onClick={() => escolherVisao(v)}
              className={`px-3 py-1.5 text-xs font-semibold ${visao === v.g ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
              {v.rotulo}
            </button>
          ))}
        </div>
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
          {pontos.length >= 2 ? (
            <div>
              <GraficoLinha
                pontos={pontos}
                titulo={`Faturamento ${nomeVisao.toLowerCase()} · ${ROTULO_FAMILIA[familia]} · ${fmtData(intervalo.de)} a ${fmtData(intervalo.ate)}`}
                camadas={{ anterior, media, vendas: camadas.vendas }}
                selecionado={idxFixado >= 0 ? idxFixado : null}
                onSelecionar={(i) => setFixado(i == null ? null : periodos[i]?.chave ?? null)}
              />
              <PainelCruzamentos
                camadas={camadas} onCamadas={setCamadas} carregandoAnterior={camadas.anterior && !dadosAnt}
                projecao={projecao}
                fixado={idxFixado >= 0 ? {
                  rotulo: rotulos(periodos[idxFixado].chave, visao).rotulo, p: periodos[idxFixado],
                  anterior: anterior?.[idxFixado] ?? null,
                  mediaPeriodo: resumo.valorOferta / Math.max(1, periodos.length),
                  total: resumo.valorOferta,
                } : null}
                onLimpar={() => setFixado(null)}
                unidade={unidade}
              />
            </div>
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

/** Painel embaixo do gráfico: liga/desliga camadas, projeção pelo ritmo e o detalhe do período clicado. */
function PainelCruzamentos({ camadas, onCamadas, carregandoAnterior, projecao, fixado, onLimpar, unidade }: {
  camadas: { anterior: boolean; media: boolean; vendas: boolean };
  onCamadas: (c: { anterior: boolean; media: boolean; vendas: boolean }) => void;
  carregandoAnterior: boolean;
  projecao: ReturnType<typeof projetarPeriodoAtual>;
  fixado: { rotulo: string; p: PeriodoFaturamento; anterior: number | null; mediaPeriodo: number; total: number } | null;
  onLimpar: () => void;
  unidade: string;
}) {
  const chip = (k: keyof typeof camadas, rotulo: string, cor: string) => (
    <button type="button" aria-pressed={camadas[k]} onClick={() => onCamadas({ ...camadas, [k]: !camadas[k] })}
      className={`inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border px-2.5 py-1 text-xs transition-colors ${camadas[k] ? 'border-[var(--accent)] bg-[var(--accent-subtle)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
      <span className="h-0.5 w-3.5 rounded" style={{ background: cor }} aria-hidden />{rotulo}
    </button>
  );
  const pct = (a: number, b: number) => (b > 0 ? ((a - b) / b) * 100 : null);
  const vsAnt = fixado && fixado.anterior != null ? pct(fixado.p.bruto, fixado.anterior) : null;
  const vsMedia = fixado ? pct(fixado.p.bruto, fixado.mediaPeriodo) : null;
  const sinal = (v: number | null) => (v == null ? '—' : `${v >= 0 ? '+' : ''}${v.toLocaleString('pt-BR', { maximumFractionDigits: 0 })}%`);
  return (
    <div className="mt-2 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Cruzar com</span>
        {chip('anterior', carregandoAnterior ? 'Período anterior…' : 'Período anterior', 'var(--fg-3)')}
        {chip('media', 'Média móvel', 'var(--cyan)')}
        {chip('vendas', 'Quantidade de vendas', 'var(--fg-4)')}
      </div>
      <div className="mt-3 grid gap-2 sm:grid-cols-2">
        {projecao ? (
          <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2">
            <div className="text-[11px] text-[var(--fg-3)]">Projeção {projecao.alvo === 'mes' ? 'do mês' : 'do ano'} no ritmo atual</div>
            <div className="tabular text-lg font-bold text-[var(--fg)]">{fmtBRL(projecao.projetado)}</div>
            <div className="text-[11px] tabular text-[var(--fg-3)]">
              {fmtBRL(projecao.parcial)} até hoje · {Math.round(projecao.decorrido * 100)}% do {projecao.alvo === 'mes' ? 'mês' : 'ano'} decorrido
            </div>
          </div>
        ) : (
          <div className="rounded-[var(--r-md)] border border-dashed border-[var(--border)] px-3 py-2 text-[11px] text-[var(--fg-4)]">
            Projeção aparece quando o período termina hoje.
          </div>
        )}
        {fixado ? (
          <div className="rounded-[var(--r-md)] border border-[var(--accent-border)] bg-[var(--accent-subtle)] px-3 py-2">
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-[11px] font-semibold text-[var(--fg)]">{fixado.rotulo}</span>
              <button type="button" onClick={onLimpar} className="text-[11px] text-[var(--fg-3)] hover:text-[var(--fg)]">limpar</button>
            </div>
            <div className="tabular text-lg font-bold text-[var(--fg)]">{fmtBRL(fixado.p.bruto)}</div>
            <div className="grid grid-cols-2 gap-x-3 text-[11px] tabular text-[var(--fg-2)]">
              <span>líquido {fmtBRL(fixado.p.liquido)}</span>
              <span>{fixado.p.vendas} venda{fixado.p.vendas === 1 ? '' : 's'}</span>
              <span>ticket médio {fixado.p.vendas ? fmtBRL(fixado.p.bruto / fixado.p.vendas) : '—'}</span>
              <span>{fixado.total > 0 ? `${((fixado.p.bruto / fixado.total) * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}% do total` : '—'}</span>
              <span>vs. média por {unidade} {sinal(vsMedia)}</span>
              <span>vs. período anterior {fixado.anterior == null ? (camadas.anterior ? '—' : 'ligue acima') : sinal(vsAnt)}</span>
            </div>
          </div>
        ) : (
          <div className="rounded-[var(--r-md)] border border-dashed border-[var(--border)] px-3 py-2 text-[11px] text-[var(--fg-4)]">
            Clique num ponto do gráfico para comparar aquele {unidade}.
          </div>
        )}
      </div>
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
