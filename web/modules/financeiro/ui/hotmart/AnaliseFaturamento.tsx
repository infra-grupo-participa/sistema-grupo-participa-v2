'use client';

// Aba "Análise" do Faturamento (27/09/2026). Substitui o painel "Cruzar com" ("não ficou muito maneiro"). Quatro
// leituras escolhidas pelo João: dinheiro já contratado, previsão com faixa, dependência de eventos, crescimento real.
// Contas em domain/faturamento-analise.ts (puras, testadas); aqui só desenho. Barras em HTML (sem SVG esticado).
import { useMemo } from 'react';
import { DataTable, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import { serieHotmart, type DiaHotmart, type FamiliaHotmart } from '../../domain/hotmart';
import {
  agruparContratado, crescimentoReal, dependenciaEventos, mesesFechados, preverComFaixa,
  type FaturamentoAcao, type LinhaContratado, type MesContratado, type MesPrevisto, type MesValor,
} from '../../domain/faturamento-analise';
import { hojeSaoPaulo } from '../../domain/prorata-hm';
import { Erro, useCarga } from './comum';
import { compacto, tetoRedondo } from './GraficoLinha';

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const mesCurto = (k: string) => `${MESES[Number(k.slice(5, 7)) - 1]}/${k.slice(2, 4)}`;
const pct = (v: number | null | undefined, casas = 0) =>
  v == null || !Number.isFinite(v) ? '—' : `${v >= 0 ? '+' : ''}${v.toLocaleString('pt-BR', { maximumFractionDigits: casas })}%`;
const fracao = (v: number) => `${Math.round(v * 100)}%`;
const corVar = (v: number | null | undefined) => (v == null ? 'text-[var(--fg-3)]' : v >= 0 ? 'text-[var(--green)]' : 'text-[var(--red)]');

export function AnaliseFaturamento({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const hoje = hojeSaoPaulo();
  const { dados: dias, erro } = useCarga<DiaHotmart[]>(() => repo.loadHotmartFaturamento(familia, '2019-01-01', hoje), [familia, hoje]);
  const { dados: contr, erro: erroC } = useCarga<LinhaContratado[]>(() => repo.loadContratado(familia), [familia]);
  const { dados: acoes, erro: erroA } = useCarga<FaturamentoAcao[]>(() => repo.loadFaturamentoPorAcao(familia), [familia]);

  const calc = useMemo(() => {
    if (!dias) return null;
    const serie = serieHotmart(dias).map((d) => ({ dia: d.dia, bruto: d.bruto, vendas: d.vendas }));
    const hist = mesesFechados(serie, hoje);
    const parcial = serie.filter((d) => d.dia.startsWith(hoje.slice(0, 7))).reduce((s, d) => s + d.bruto, 0);
    const [y, m, d] = hoje.split('-').map(Number);
    const decorrido = d / new Date(Date.UTC(y, m, 0)).getUTCDate();
    return { serie, hist, parcial, prev: preverComFaixa(hist, parcial, decorrido), cresc: crescimentoReal(hist, serie, hoje) };
  }, [dias, hoje]);
  const contratado = useMemo(() => agruparContratado(contr ?? []), [contr]);
  const dep = useMemo(() => (calc && acoes ? dependenciaEventos(calc.serie, acoes, hoje) : null), [calc, acoes, hoje]);

  if (erro) return <Erro msg={erro} />;
  if (!calc) return <Loading label="Calculando…" minHeight={200} />;
  const { hist, prev, cresc } = calc;
  const totContr = contratado.reduce((s, m) => s + m.total, 0);
  const riscoContr = contratado.reduce((s, m) => s + m.emRisco, 0);
  const contrPorMes = new Map(contratado.map((m) => [m.chave, m.total]));
  const proxPrev = prev?.meses[0];

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Kpi rotulo="Já contratado · 12 meses" valor={contr ? fmtBRL(totContr) : '…'}
          detalhe={contr ? <span className={riscoContr > 0 ? 'text-[var(--red)]' : ''}>{fmtBRL(riscoContr)} em risco</span> : null} />
        <Kpi rotulo={proxPrev ? `Previsão · ${mesCurto(proxPrev.chave)}` : 'Previsão'} valor={proxPrev ? fmtBRL(proxPrev.provavel) : '—'}
          detalhe={proxPrev ? `${compacto(proxPrev.conservador)} a ${compacto(proxPrev.otimista)}` : 'histórico curto'} />
        <Kpi rotulo="Faturamento em dias de ação" valor={dep ? fracao(dep.emAcao) : acoes ? '—' : '…'}
          detalhe={dep ? `em ${fracao(dep.diasEmAcao)} dos dias · dia comum ${compacto(dep.diaComum)}` : null} />
        <Kpi rotulo="12 meses vs. 12 anteriores" valor={<span className={corVar(cresc.doze?.pct)}>{pct(cresc.doze?.pct)}</span>}
          detalhe={cresc.yoy ? <>{mesCurto(cresc.yoy.chave)} vs. ano anterior <span className={corVar(cresc.yoy.pct)}>{pct(cresc.yoy.pct)}</span></> : null} />
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <SectionCard title="Previsão com faixa">
          {!prev ? <p className="text-xs text-[var(--fg-3)]">Menos de 6 meses fechados.</p> : (
            <>
              <GraficoPrevisao hist={hist.slice(-12)} meses={prev.meses} contratado={contrPorMes} />
              <DataTable minWidth={400}>
                <Thead><Th>Mês</Th><Th>Conservador</Th><Th>Provável</Th><Th>Otimista</Th><Th>Já contratado</Th></Thead>
                <tbody>
                  {prev.meses.map((m) => (
                    <Tr key={m.chave}>
                      <Td className="whitespace-nowrap">
                        {mesCurto(m.chave)}
                        {m.parcial != null && <span className="ml-1.5 text-[10px] text-[var(--fg-3)]">entrou {compacto(m.parcial)}</span>}
                      </Td>
                      <Td className="tabular text-[var(--fg-2)]">{fmtBRL(m.conservador)}</Td>
                      <Td className="tabular font-semibold">{fmtBRL(m.provavel)}</Td>
                      <Td className="tabular text-[var(--fg-2)]">{fmtBRL(m.otimista)}</Td>
                      <Td className="tabular text-[var(--fg-3)]">{contrPorMes.get(m.chave) ? fmtBRL(contrPorMes.get(m.chave)!) : '—'}</Td>
                    </Tr>
                  ))}
                </tbody>
              </DataTable>
              <p className="mt-2 text-[11px] text-[var(--fg-3)]">
                Modelo: {prev.modelo.nome} · erro médio {fracao(prev.erro)} em {prev.testes} testes · faixa = 8 em cada 10 meses testados
              </p>
            </>
          )}
        </SectionCard>

        <SectionCard title="Dinheiro já contratado">
          {erroC ? <Erro msg={erroC} /> : !contr ? <Loading label="Carregando…" minHeight={120} /> : !contratado.length
            ? <p className="text-xs text-[var(--fg-3)]">Nenhuma parcela ou assinatura a entrar.</p> : (
              <>
                <GraficoContratado meses={contratado} />
                <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-[var(--fg-3)]">
                  <Legenda cor="var(--accent)" texto={`Parcelas Hotmart ${compacto(contratado.reduce((s, m) => s + m.parcelado, 0))}`} />
                  <Legenda cor="var(--cyan)" texto={`Assinaturas (3 meses) ${compacto(contratado.reduce((s, m) => s + m.assinatura, 0))}`} />
                  {contratado.some((m) => m.combinado > 0) && <Legenda cor="var(--yellow)" texto={`Saldo com data no board ${compacto(contratado.reduce((s, m) => s + m.combinado, 0))}`} />}
                  <Legenda cor="var(--red)" texto={`Em risco (parcela aberta ou 45+ dias sem pagar) ${compacto(riscoContr)}`} risco />
                </div>
              </>
            )}
        </SectionCard>

        <SectionCard title="Dependência de eventos">
          {erroA ? <Erro msg={erroA} /> : !acoes ? <Loading label="Carregando…" minHeight={120} /> : !dep
            ? <p className="text-xs text-[var(--fg-3)]">Sem ação cadastrada para esta família.</p> : (
              <>
                <div className="mb-3 grid grid-cols-3 gap-2 text-center">
                  <Mini rotulo="em dias de ação" valor={fracao(dep.emAcao)} />
                  <Mini rotulo="10% melhores dias" valor={fracao(dep.top10)} />
                  <Mini rotulo="dia comum (média)" valor={compacto(dep.diaComum)} />
                </div>
                <DataTable minWidth={560}>
                  <Thead><Th>Ação</Th><Th>Período</Th><Th>Bruto</Th><Th>Por dia</Th><Th>× dia comum</Th></Thead>
                  <tbody>
                    {dep.acoes.map((a) => (
                      <Tr key={`${a.acao}-${a.inicio}`}>
                        <Td className="max-w-[220px] font-medium"><span className="block truncate" title={a.acao}>{a.acao}</span></Td>
                        <Td className="whitespace-nowrap text-[11px] text-[var(--fg-3)]">{fmtData(a.inicio)} · {a.dias}d</Td>
                        <Td className="tabular font-semibold">{fmtBRL(a.bruto)}</Td>
                        <Td className="tabular text-[var(--fg-2)]">{compacto(a.porDia)}</Td>
                        <Td><Vezes v={a.vezesDiaComum} max={Math.max(...dep.acoes.map((x) => x.vezesDiaComum ?? 0))} /></Td>
                      </Tr>
                    ))}
                  </tbody>
                </DataTable>
                <p className="mt-2 text-[11px] text-[var(--fg-3)]">{fmtData(dep.de)} a {fmtData(dep.ate)} · {fmtBRL(dep.total)}</p>
              </>
            )}
        </SectionCard>

        <SectionCard title="Crescimento real">
          <div className="grid gap-2 sm:grid-cols-2">
            <Linha rotulo={cresc.yoy ? `${mesCurto(cresc.yoy.chave)} vs. ${mesCurto(`${Number(cresc.yoy.chave.slice(0, 4)) - 1}${cresc.yoy.chave.slice(4)}`)}` : 'Último mês vs. ano anterior'}
              valor={cresc.yoy ? pct(cresc.yoy.pct) : '—'} v={cresc.yoy?.pct}
              sub={cresc.yoy ? `${compacto(cresc.yoy.atual)} × ${compacto(cresc.yoy.anterior)}` : undefined} />
            <Linha rotulo={cresc.mesAteHoje ? `Mês até dia ${cresc.mesAteHoje.dia} vs. ano anterior` : 'Mês até hoje vs. ano anterior'}
              valor={cresc.mesAteHoje ? pct(cresc.mesAteHoje.pct) : '—'} v={cresc.mesAteHoje?.pct}
              sub={cresc.mesAteHoje ? `${compacto(cresc.mesAteHoje.atual)} × ${compacto(cresc.mesAteHoje.anterior)}` : undefined} />
            <Linha rotulo="12 meses vs. 12 anteriores" valor={pct(cresc.doze?.pct)} v={cresc.doze?.pct}
              sub={cresc.doze ? `${compacto(cresc.doze.atual)} × ${compacto(cresc.doze.anterior)}` : undefined} />
            <Linha rotulo="Tendência dos últimos 12 meses" valor={cresc.tendencia ? `${cresc.tendencia.porMes >= 0 ? '+' : '−'}${compacto(Math.abs(cresc.tendencia.porMes))}/mês` : '—'}
              v={cresc.tendencia?.porMes}
              sub={cresc.tendencia ? `${pct(cresc.tendencia.pctMedia, 1)} da média ao mês · reta explica ${fracao(cresc.tendencia.r2)}` : undefined} />
            <Linha rotulo="Ticket médio 12 meses" valor={cresc.ticket ? fmtBRL(cresc.ticket.atual) : '—'} v={cresc.ticket?.pct}
              sub={cresc.ticket ? `${pct(cresc.ticket.pct)} vs. ${fmtBRL(cresc.ticket.anterior)}` : undefined} />
          </div>
          {cresc.movel12.length >= 2 && <Movel12 pontos={cresc.movel12.slice(-24)} />}
        </SectionCard>
      </div>
    </div>
  );
}

function Kpi({ rotulo, valor, detalhe }: { rotulo: string; valor: React.ReactNode; detalhe: React.ReactNode }) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] px-4 py-3">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className="tabular mt-0.5 text-xl font-bold text-[var(--fg)]">{valor}</div>
      {detalhe && <div className="mt-0.5 text-[11px] tabular text-[var(--fg-3)]">{detalhe}</div>}
    </div>
  );
}

function Mini({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="rounded-[var(--r-md)] bg-[var(--surface-2)] px-2 py-2">
      <div className="tabular text-base font-bold text-[var(--fg)]">{valor}</div>
      <div className="text-[10px] text-[var(--fg-3)]">{rotulo}</div>
    </div>
  );
}

function Linha({ rotulo, valor, v, sub }: { rotulo: string; valor: string; v: number | null | undefined; sub?: string }) {
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2">
      <div className="text-[11px] text-[var(--fg-3)]">{rotulo}</div>
      <div className={`tabular text-base font-bold ${corVar(v)}`}>{valor}</div>
      {sub && <div className="text-[10px] tabular text-[var(--fg-4)]">{sub}</div>}
    </div>
  );
}

function Legenda({ cor, texto, risco }: { cor: string; texto: string; risco?: boolean }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="h-2.5 w-2.5 rounded-sm" aria-hidden
        style={risco ? { background: `repeating-linear-gradient(45deg, ${cor} 0 2px, transparent 2px 4px)`, border: `1px solid ${cor}` } : { background: cor }} />
      {texto}
    </span>
  );
}

function Vezes({ v, max }: { v: number | null; max: number }) {
  if (v == null) return <span className="text-[var(--fg-4)]">—</span>;
  return (
    <span className="flex items-center gap-2">
      <span className="h-1.5 w-16 overflow-hidden rounded-full bg-[var(--surface-2)]">
        <span className="block h-full rounded-full bg-[var(--accent)]" style={{ width: `${Math.min(100, (v / Math.max(max, 1)) * 100)}%` }} />
      </span>
      <span className="tabular text-xs font-semibold">{v.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}×</span>
    </span>
  );
}

const ALT = 150;

/** Últimos 12 meses fechados (barras) + 3 meses previstos (faixa conservador–otimista, traço no provável). */
function GraficoPrevisao({ hist, meses, contratado }: { hist: MesValor[]; meses: MesPrevisto[]; contratado: Map<string, number> }) {
  const teto = tetoRedondo(Math.max(...hist.map((m) => m.bruto), ...meses.map((m) => m.otimista), 1));
  const h = (v: number) => `${(v / teto) * 100}%`;
  return (
    <div className="mb-3 flex gap-2">
      <div className="relative w-14 shrink-0 whitespace-nowrap text-right text-[10px] tabular text-[var(--fg-4)]" style={{ height: ALT }} aria-hidden>
        {[1, 0.5, 0].map((f) => (
          <span key={f} className="absolute right-0 -translate-y-1/2" style={{ top: `${(1 - f) * 100}%` }}>{f === 0 ? '0' : compacto(teto * f)}</span>
        ))}
      </div>
      <div className="min-w-0 flex-1">
        <div className="relative flex items-end gap-1 border-b border-[var(--border)]" style={{ height: ALT }}>
          <div className="pointer-events-none absolute inset-x-0 top-1/2 border-t border-dashed border-[var(--border)]" aria-hidden />
          {hist.map((m) => (
            <div key={m.chave} className="relative h-full flex-1" title={`${mesCurto(m.chave)}: ${fmtBRL(m.bruto)}`}>
              <div className="absolute inset-x-0 bottom-0 rounded-t-[3px] bg-[var(--accent)] opacity-70" style={{ height: h(m.bruto) }} />
            </div>
          ))}
          <div className="mx-0.5 h-full border-l border-dashed border-[var(--fg-4)]" aria-hidden />
          {meses.map((m) => {
            const c = contratado.get(m.chave) ?? 0;
            return (
              <div key={m.chave} className="relative h-full flex-1"
                title={`${mesCurto(m.chave)}: provável ${fmtBRL(m.provavel)} · ${fmtBRL(m.conservador)} a ${fmtBRL(m.otimista)}${c ? ` · contratado ${fmtBRL(c)}` : ''}`}>
                <div className="absolute inset-x-0 rounded-[3px] border border-[var(--accent-border)] bg-[var(--accent-subtle)]"
                  style={{ bottom: h(m.conservador), height: `max(2px, ${h(m.otimista - m.conservador)})` }} />
                {m.parcial != null && m.parcial > 0 && (
                  <div className="absolute inset-x-1 bottom-0 rounded-t-[3px] bg-[var(--accent)]" style={{ height: h(m.parcial) }} />
                )}
                <div className="absolute inset-x-0 h-0.5 bg-[var(--accent)]" style={{ bottom: h(m.provavel) }} />
                {c > 0 && <div className="absolute inset-x-0 border-t-2 border-dotted border-[var(--green)]" style={{ bottom: h(c) }} />}
              </div>
            );
          })}
        </div>
        <div className="mt-1 flex gap-1 text-[9px] text-[var(--fg-4)]">
          {hist.map((m, i) => <span key={m.chave} className="flex-1 overflow-visible whitespace-nowrap text-center">{(hist.length - 1 - i) % 3 === 0 ? mesCurto(m.chave) : ''}</span>)}
          <span className="mx-0.5" />
          {meses.map((m) => <span key={m.chave} className="flex-1 overflow-visible whitespace-nowrap text-center font-semibold text-[var(--fg-3)]">{mesCurto(m.chave)}</span>)}
        </div>
        <div className="mt-1.5 flex flex-wrap gap-x-3 text-[10px] text-[var(--fg-3)]">
          <span>▮ realizado</span><span className="text-[var(--accent)]">▭ faixa · — provável</span>
          <span className="text-[var(--green)]">┈ já contratado</span>
        </div>
      </div>
    </div>
  );
}

/** Barras empilhadas por mês: parcelas, assinaturas e saldo combinado; o que está em risco hachurado por cima. */
function GraficoContratado({ meses }: { meses: MesContratado[] }) {
  const teto = tetoRedondo(Math.max(...meses.map((m) => m.total), 1));
  const h = (v: number) => `${(v / teto) * 100}%`;
  return (
    <div className="flex gap-2">
      <div className="relative w-14 shrink-0 whitespace-nowrap text-right text-[10px] tabular text-[var(--fg-4)]" style={{ height: ALT }} aria-hidden>
        {[1, 0.5, 0].map((f) => (
          <span key={f} className="absolute right-0 -translate-y-1/2" style={{ top: `${(1 - f) * 100}%` }}>{f === 0 ? '0' : compacto(teto * f)}</span>
        ))}
      </div>
      <div className="min-w-0 flex-1">
        <div className="relative flex items-end gap-1.5 border-b border-[var(--border)]" style={{ height: ALT }}>
          <div className="pointer-events-none absolute inset-x-0 top-1/2 border-t border-dashed border-[var(--border)]" aria-hidden />
          {meses.map((m) => (
            <div key={m.chave} className="relative flex h-full flex-1 flex-col justify-end"
              title={`${mesCurto(m.chave)}: ${fmtBRL(m.total)} (parcelas ${fmtBRL(m.parcelado)} · assinaturas ${fmtBRL(m.assinatura)}${m.combinado ? ` · board ${fmtBRL(m.combinado)}` : ''}) · em risco ${fmtBRL(m.emRisco)}`}>
              {m.combinado > 0 && <div className="bg-[var(--yellow)]" style={{ height: h(m.combinado) }} />}
              {m.assinatura > 0 && <div className="bg-[var(--cyan)]" style={{ height: h(m.assinatura) }} />}
              <div className="relative rounded-b-[2px] bg-[var(--accent)]" style={{ height: h(m.parcelado) }}>
                {m.emRisco > 0 && (
                  <div className="absolute inset-x-0 bottom-0 border-t border-[var(--red)]"
                    style={{ height: `${(m.emRisco / Math.max(m.parcelado, 1)) * 100}%`, background: 'repeating-linear-gradient(45deg, var(--red) 0 2px, transparent 2px 5px)' }} />
                )}
              </div>
            </div>
          ))}
        </div>
        <div className="mt-1 flex gap-1.5 text-[9px] text-[var(--fg-4)]">
          {meses.map((m, i) => <span key={m.chave} className="flex-1 overflow-visible whitespace-nowrap text-center">{i % 2 === 0 ? mesCurto(m.chave) : ''}</span>)}
        </div>
      </div>
    </div>
  );
}

/** Soma móvel de 12 meses: a curva sem sazonalidade — sobe = o negócio cresce, não só o mês. */
function Movel12({ pontos }: { pontos: { chave: string; valor: number }[] }) {
  const min = Math.min(...pontos.map((p) => p.valor)), max = Math.max(...pontos.map((p) => p.valor));
  const faixa = Math.max(max - min, 1);
  const ult = pontos.length - 1;
  const coords = pontos.map((p, i) => `${(i / ult) * 100},${36 - ((p.valor - min) / faixa) * 32}`).join(' ');
  return (
    <div className="mt-3">
      <div className="flex items-baseline justify-between text-[11px] text-[var(--fg-3)]">
        <span>Soma dos últimos 12 meses, mês a mês</span>
        <span className="tabular">{compacto(pontos[0].valor)} → <strong className="text-[var(--fg)]">{compacto(pontos[ult].valor)}</strong></span>
      </div>
      <svg viewBox="0 0 100 40" preserveAspectRatio="none" className="mt-1 h-12 w-full" aria-hidden>
        <polyline points={`0,40 ${coords} 100,40`} fill="var(--accent-subtle)" stroke="none" />
        <polyline points={coords} fill="none" stroke="var(--accent)" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
      </svg>
      <div className="flex justify-between text-[9px] text-[var(--fg-4)]"><span>{mesCurto(pontos[0].chave)}</span><span>{mesCurto(pontos[ult].chave)}</span></div>
    </div>
  );
}
