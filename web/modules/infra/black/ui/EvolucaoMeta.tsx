'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { agregar, connectRate, cpc, cpm, ctr, ehCaptacao, ehEntresafraCampanha, filtrarDias, filtrarLinhas } from '../domain/metricas';
import { INICIO_CAPTACAO, SEMENTE_LEADS, projetarRitmo, type PontoRitmo } from '../domain/ritmo';
import { cplCaptacao, conversaoPagina, leadsDoTrafego, taxaMql } from '../domain/numeros';
import { diaDe } from '../domain/recorte';
import type { Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { formatar } from './pecas';

const fmtDia = (dia: string) => `${dia.slice(8, 10)}/${dia.slice(5, 7)}`;
const diasEntre = (de: string, ate: string) => {
  if (de > ate) return [];
  const out: string[] = [];
  for (let d = de; d <= ate; ) { out.push(d); const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + 1); d = x.toISOString().slice(0, 10); }
  return out;
};

export type LinhaEvolucaoMeta = PontoRitmo;

function serieDiaria(cardId: string, d: DadosTela): LinhaEvolucaoMeta[] {
  const hoje = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d.agora);
  const ate = d.periodo.ate < hoje ? d.periodo.ate : hoje;
  const datas = diasEntre(INICIO_CAPTACAO, ate);
  if (datas.length === 0) return [];
  const filtro = { funil: d.recorte.funil, canal: d.recorte.canal };
  const linhasTodas = filtrarLinhas(d.linhasTodas.filter((l) => !l.teste && l.pagina !== 'consultoria_respondi'), filtro);
  const diasTodos = filtrarDias(d.diasTodos, d.idx, filtro);
  const campanhasCap = d.trafego.campanhas.filter((c) => !ehEntresafraCampanha(c) && c.fase !== 'remarketing' && !/REMARKETING/i.test(c.nome)
    && (c.etapa === 'C2' || c.etapa === 'C3' || (c.etapa === undefined && ehCaptacao(c.funil)))
    && (d.recorte.canal === 'todos' || c.canal === d.recorte.canal)
    && (d.recorte.funil === 'todos' || (d.recorte.funil === 'c2' ? c.funil === 'consultoria' || c.funil === 'iscas' || c.funil === 'c3' : c.funil === d.recorte.funil)));
  const idsCampanha = new Set(campanhasCap.map((c) => c.id));
  const serieGastoDisponivel = Array.isArray(d.trafego.gastoCampanhasDiario) && idsCampanha.size > 0;
  const gastoPorDia = (ateDia: string): Valor => {
    if (!serieGastoDisponivel) return null;
    return d.trafego.gastoCampanhasDiario!.filter((x) => idsCampanha.has(x.campanhaId) && x.dia >= INICIO_CAPTACAO && x.dia <= ateDia)
      .reduce((s, x) => s + x.gasto, 0);
  };
  const gastoDiario = (dia: string): Valor => {
    if (!serieGastoDisponivel) return null;
    return d.trafego.gastoCampanhasDiario!.filter((x) => idsCampanha.has(x.campanhaId) && x.dia === dia).reduce((s, x) => s + x.gasto, 0);
  };
  const capLinhas = linhasTodas.filter((l) => l.campanhaId !== null && idsCampanha.has(l.campanhaId));
  const pagos = capLinhas.filter((l) => l.origem === 'pago');
  const primeiraDataPorPessoa = (ls: typeof linhasTodas) => {
    const out = new Map<string, string>();
    for (const l of ls) { const dia = diaDe(l.criadoEm); if (!out.has(l.pessoaId) || dia < out.get(l.pessoaId)!) out.set(l.pessoaId, dia); }
    return out;
  };
  const primeiraDataLeads = primeiraDataPorPessoa(linhasTodas);
  const metaFixa: Valor = cardId === 'cpl' ? (d.config.cplAlvoMedio ?? d.config.reguaCpl?.meta ?? null)
    : cardId === 'cpm' ? d.config.metas.cpm : cardId === 'ctr' ? d.config.metas.ctr : cardId === 'cpc' ? d.config.metas.cpc
      : cardId === 'connect' ? d.config.metas.connectRate : cardId === 'conv' ? d.config.metas.conversaoPagina
        : cardId === 'mql-percentual' ? d.config.metas.mql : null;
  const metaFinal: Valor = cardId === 'leads' ? d.config.metaLeads : cardId === 'investimento-captacao' ? d.config.previstoPorFase.captacao : null;
  const linhasAte = (dia: string) => linhasTodas.filter((l) => diaDe(l.criadoEm) >= INICIO_CAPTACAO && diaDe(l.criadoEm) <= dia);
  const trafegoAte = (dia: string) => diasTodos.filter((x) => x.dia >= INICIO_CAPTACAO && x.dia <= dia);
  const capTraffic = (dia: string, cumulativo: boolean) => {
    const ds = cumulativo ? trafegoAte(dia) : diasTodos.filter((x) => x.dia === dia);
    return ds.filter((x) => idsCampanha.has(d.idx.campanhaDoAnuncio(x.anuncioId)?.id ?? ''));
  };
  const calc = (dia: string, cumulativo: boolean): Valor => {
    if (cardId === 'leads') {
      if (d.perfilSemDado) return null;
      const datas = primeiraDataLeads;
      const vals = cumulativo ? [...datas.values()].filter((x) => x >= INICIO_CAPTACAO && x <= dia) : [...datas.values()].filter((x) => x === dia);
      const seed = d.recorte.funil === 'todos' && d.recorte.canal === 'todos' ? SEMENTE_LEADS : 0;
      return cumulativo ? seed + vals.length : vals.length;
    }
    if (cardId === 'investimento-captacao') return cumulativo ? gastoPorDia(dia) : gastoDiario(dia);
    if (cardId === 'cpl') {
      if (!serieGastoDisponivel) return null;
      const rows = cumulativo ? pagos.filter((l) => diaDe(l.criadoEm) >= INICIO_CAPTACAO && diaDe(l.criadoEm) <= dia) : pagos.filter((l) => diaDe(l.criadoEm) === dia);
      return cplCaptacao(cumulativo ? gastoPorDia(dia) : gastoDiario(dia), leadsDoTrafego(rows, d.idx)).valor;
    }
    const traffic = capTraffic(dia, cumulativo);
    const lines = cumulativo ? linhasAte(dia) : linhasTodas.filter((l) => diaDe(l.criadoEm) === dia);
    const a = agregar(traffic);
    if (cardId === 'cpm') return traffic.length ? cpm(a) : null;
    if (cardId === 'ctr') return ctr(a).valor;
    if (cardId === 'cpc') return traffic.length ? cpc(a) : null;
    if (cardId === 'connect') return connectRate(traffic, d.idx).valor;
    if (cardId === 'conv') return conversaoPagina(traffic, lines, d.idx).valor;
    if (cardId === 'mql-percentual') return taxaMql(lines).valor;
    return null;
  };

  if (cardId === 'leads' || cardId === 'investimento-captacao') {
    const realizados = new Map<string, Valor>(datas.map((dia) => [dia, calc(dia, false)]));
    return projetarRitmo({ hoje, meta: metaFinal, realizados, semente: cardId === 'leads' && d.recorte.funil === 'todos' && d.recorte.canal === 'todos' ? SEMENTE_LEADS : 0 }).pontos.filter((p) => p.dia <= ate);
  }
  let acumulado: Valor = null;
  return datas.map((dia) => {
    const realizado = calc(dia, false);
    acumulado = calc(dia, true);
    return { dia, realizado, metaDia: metaFixa, acumulado, metaAcumulada: null };
  });
}

export function EvolucaoMetaIndicador({ d, cardId, rotulo, formato }: { d: DadosTela; cardId: string; rotulo: string; formato: 'int' | 'brl' | 'pct' }) {
  const pontos = useMemo(() => serieDiaria(cardId, d), [cardId, d]);
  if (pontos.length === 0) return <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-3 text-sm text-[var(--fg-3)]">Sem série diária no período de captação.</p>;
  return <section aria-label={`Evolução diária de ${rotulo}`} className="space-y-2 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
    <h3 className="text-sm font-semibold text-[var(--fg)]">Evolução diária</h3>
    <GraficoDiarioMeta pontos={pontos} formato={formato} rotulo={rotulo} />
    <DataTableMeta pontos={pontos} formato={formato} />
    <p className="text-[10px] text-[var(--fg-3)]">Fonte: dados_black_perfil e dados_black_trafego. A meta dos indicadores de proporção é fixa; leads e investimento usam a régua dinâmica da captação.</p>
  </section>;
}

function DataTableMeta({ pontos, formato }: { pontos: LinhaEvolucaoMeta[]; formato: 'int' | 'brl' | 'pct' }) {
  const temMetaAcumulada = pontos.some((p) => p.metaAcumulada !== null);
  const formatoMeta = formato === 'int' ? 'dec' : formato;
  return <div className="overflow-x-auto"><table className={`w-full ${temMetaAcumulada ? 'min-w-[620px]' : 'min-w-[480px]'} border-collapse text-left text-xs`}><thead><tr className="border-b border-[var(--border)] text-[var(--fg-3)]"><th className="p-2">Dia</th><th className="p-2">Realizado</th><th className="p-2">Meta do dia</th><th className="p-2">Acumulado real</th>{temMetaAcumulada && <th className="p-2">Meta acumulada</th>}</tr></thead><tbody>{pontos.map((p) => <tr key={p.dia} className="border-b border-[var(--border-faint)]"><th scope="row" className="p-2 font-medium text-[var(--fg-2)]">{fmtDia(p.dia)}</th><td className="p-2 tabular text-[var(--fg)]">{formatar(p.realizado, formato)}</td><td className="p-2 tabular text-[var(--fg-2)]">{formatar(p.metaDia, formatoMeta)}</td><td className="p-2 tabular text-[var(--fg)]">{formatar(p.acumulado, formato)}</td>{temMetaAcumulada && <td className="p-2 tabular text-[var(--fg-2)]">{formatar(p.metaAcumulada, formatoMeta)}</td>}</tr>)}</tbody></table></div>;
}

function GraficoDiarioMeta({ pontos, formato, rotulo }: { pontos: LinhaEvolucaoMeta[]; formato: 'int' | 'brl' | 'pct'; rotulo: string }) {
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(700);
  const [hover, setHover] = useState<number | null>(null);
  useEffect(() => {
    const el = box.current; if (!el) return;
    const ro = new ResizeObserver(([e]) => setWidth(Math.max(320, Math.round(e.contentRect.width)))); ro.observe(el); return () => ro.disconnect();
  }, []);
  const h = 210; const left = 62; const right = 12; const top = 16; const bottom = 30; const w = width - left - right;
  const vals = pontos.flatMap((p) => [p.realizado, p.metaDia]).filter((v): v is number => v !== null && Number.isFinite(v));
  if (vals.length === 0) return <p className="text-sm text-[var(--fg-3)]">Sem dado.</p>;
  const max = Math.max(1, ...vals); const y = (v: number) => top + (h - top - bottom) * (1 - v / max); const x = (i: number) => left + (pontos.length < 2 ? w / 2 : i * w / (pontos.length - 1));
  const line = (k: 'realizado' | 'metaDia') => pontos.map((p, i) => p[k] === null ? null : `${x(i)},${y(p[k]!)}`).filter(Boolean).join(' ');
  const step = Math.max(1, Math.ceil(pontos.length / 7));
  return <div ref={box} className="relative overflow-hidden" onMouseLeave={() => setHover(null)} onMouseMove={(e) => { const r = box.current?.getBoundingClientRect(); if (!r) return; const i = Math.round(((e.clientX - r.left - left) / Math.max(1, w)) * (pontos.length - 1)); setHover(Math.max(0, Math.min(pontos.length - 1, i))); }}>
    <svg viewBox={`0 0 ${width} ${h}`} className="block w-full" role="img" aria-label={`${rotulo}: realizado diário e meta diária`}>
      <line x1={left} x2={width - right} y1={h - bottom} y2={h - bottom} stroke="var(--border)" />
      {pontos.map((p, i) => (i % step === 0 || i === pontos.length - 1) && <text key={p.dia} x={x(i)} y={h - 8} fontSize="10" textAnchor="middle" fill="var(--fg-3)">{fmtDia(p.dia)}</text>)}
      {hover !== null && <line x1={x(hover)} x2={x(hover)} y1={top} y2={h - bottom} stroke="var(--border-strong)" strokeDasharray="3 3" />}
      <polyline points={line('metaDia')} fill="none" stroke="var(--fg-3)" strokeDasharray="5 4" strokeWidth="2" />
      <polyline points={line('realizado')} fill="none" stroke="var(--accent)" strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" />
      {hover !== null && <g><circle cx={x(hover)} cy={y(pontos[hover].realizado ?? pontos[hover].metaDia ?? 0)} r="4" fill="var(--accent)" /></g>}
    </svg>
    <div className="flex flex-wrap gap-x-4 text-[10px] text-[var(--fg-3)]"><span><span className="mr-1 inline-block h-0.5 w-3 align-middle bg-[var(--accent)]" />Realizado diário</span><span><span className="mr-1 inline-block h-0.5 w-3 align-middle border-t border-dashed border-[var(--fg-3)]" />Meta do dia</span></div>
    {hover !== null && <p role="status" className="text-[11px] text-[var(--fg-2)]">{fmtDia(pontos[hover].dia)} · realizado {formatar(pontos[hover].realizado, formato)} · meta {formatar(pontos[hover].metaDia, formato === 'int' ? 'dec' : formato)} · acumulado {formatar(pontos[hover].acumulado, formato)}</p>}
  </div>;
}
