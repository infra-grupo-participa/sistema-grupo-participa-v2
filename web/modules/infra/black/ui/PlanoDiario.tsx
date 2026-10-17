'use client';

// Meta contra realizado por dia e segmento (pedido do Arthur, 16/10/2026): pop-up do card "Investimento total" com
// a aba Tabela e a aba Gráfico, e o parágrafo do topo dos Alertas. Uma leitura da RPC dados_black_plano_diario,
// guardada por chave para o modal e os Alertas não lerem duas vezes no mesmo minuto.
import { useEffect, useMemo, useState } from 'react';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { EmptyState, Modal, Tabs } from '@/shared/ui/components';
import { agruparPorDia, fracaoDoDia, mapearPlano, pctDaMeta, resumoAjusteDoDia, segmentosDoPeriodo, type DiaPlano } from '../domain/plano-diario';
import type { Valor } from '../domain/tipos';

type Estado = { dias: DiaPlano[] | null; erro: string | null };
const cache = new Map<string, { em: number; promessa: Promise<Estado> }>();

function lerPlano(chave: string): Promise<Estado> {
  const c = cache.get(chave);
  if (c && Date.now() - c.em < 60_000) return c.promessa;
  const promessa = (async (): Promise<Estado> => {
    const { data, error } = await createBrowserSupabase().rpc('dados_black_plano_diario', { p_chave: chave });
    if (error) return { dias: null, erro: error.code === 'PGRST202' ? 'Plano diário ainda não cadastrado no banco.' : 'Não foi possível ler o plano diário agora.' };
    return { dias: agruparPorDia(mapearPlano(data)), erro: null };
  })();
  cache.set(chave, { em: Date.now(), promessa });
  return promessa;
}

export function usePlanoDiario(chave: string, ativo = true): Estado & { lendo: boolean } {
  const [estado, setEstado] = useState<Estado & { lendo: boolean }>({ dias: null, erro: null, lendo: ativo });
  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    void lerPlano(chave).then((e) => { if (vivo) setEstado({ ...e, lendo: false }); });
    return () => { vivo = false; };
  }, [chave, ativo]);
  return estado;
}

const brl = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const int = new Intl.NumberFormat('pt-BR');
const fmtDia = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const fmtPct = (v: Valor) => (v === null ? '-' : `${Math.round(v)}%`);
const corPct = (v: Valor) => (v === null ? 'text-[var(--fg-3)]' : v >= 90 ? 'text-[var(--green)]' : v >= 70 ? 'text-[var(--yellow)]' : 'text-[var(--red)]');

function TabelaPlano({ dias, agora }: { dias: DiaPlano[]; agora: Date }) {
  const hoje = agora.toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' });
  const [abertos, setAbertos] = useState<Set<string>>(() => new Set([hoje]));
  const alternar = (dia: string) => setAbertos((s) => { const n = new Set(s); if (n.has(dia)) n.delete(dia); else n.add(dia); return n; });
  return <div className="overflow-x-auto">
    <table className="w-full text-sm">
      <thead><tr className="text-left text-xs text-[var(--fg-3)]">
        {['Dia / segmento', 'Verba meta', 'Verba realizada', '% verba', 'Leads meta', 'Leads realizados', '% leads'].map((c) => <th key={c} className="p-2 whitespace-nowrap">{c}</th>)}
      </tr></thead>
      <tbody>{dias.map((d) => {
        const aberto = abertos.has(d.dia);
        const f = fracaoDoDia(d.dia, agora);
        const ritmo = d.dia === hoje ? ` · ritmo até agora ${brl.format(d.total.verbaMeta * f)} / ${int.format(Math.round(d.total.leadsMeta * f))} leads` : '';
        return [
          <tr key={d.dia} className={`border-t border-[var(--border)] font-semibold ${d.dia === hoje ? 'bg-[var(--accent-subtle)]' : ''}`}>
            <td className="p-2 whitespace-nowrap"><button type="button" onClick={() => alternar(d.dia)} aria-expanded={aberto} className="text-left">
              {aberto ? '−' : '+'} {fmtDia(d.dia)}{d.dia === hoje ? ' (hoje)' : ''}<span className="block text-[10px] font-normal text-[var(--fg-3)]">{ritmo}</span></button></td>
            <td className="p-2 tabular">{brl.format(d.total.verbaMeta)}</td>
            <td className="p-2 tabular">{d.total.verbaReal === null ? 'sem dado' : brl.format(d.total.verbaReal)}</td>
            <td className={`p-2 tabular ${corPct(pctDaMeta(d.total.verbaReal, d.total.verbaMeta))}`}>{fmtPct(pctDaMeta(d.total.verbaReal, d.total.verbaMeta))}</td>
            <td className="p-2 tabular">{int.format(d.total.leadsMeta)}</td>
            <td className="p-2 tabular">{d.total.leadsReal === null ? 'sem dado' : int.format(d.total.leadsReal)}</td>
            <td className={`p-2 tabular ${corPct(pctDaMeta(d.total.leadsReal, d.total.leadsMeta))}`}>{fmtPct(pctDaMeta(d.total.leadsReal, d.total.leadsMeta))}</td>
          </tr>,
          ...(aberto ? d.segmentos.map((s) => <tr key={`${d.dia}-${s.segmento.chave}`} className="border-t border-[var(--border-faint)] text-[var(--fg-2)]">
            <td className="p-2 pl-6 whitespace-nowrap"><span aria-hidden="true" className="mr-2 inline-block h-2.5 w-2.5 rounded-sm align-middle" style={{ background: s.segmento.cor, opacity: s.segmento.opaco ? 0.55 : 1 }} />{s.segmento.rotulo}</td>
            <td className="p-2 tabular">{brl.format(s.verbaMeta)}</td>
            <td className="p-2 tabular">{s.verbaReal === null ? 'sem dado' : brl.format(s.verbaReal)}</td>
            <td className={`p-2 tabular ${corPct(pctDaMeta(s.verbaReal, s.verbaMeta))}`}>{fmtPct(pctDaMeta(s.verbaReal, s.verbaMeta))}</td>
            <td className="p-2 tabular">{int.format(s.leadsMeta)}</td>
            <td className="p-2 tabular">{s.leadsReal === null ? 'sem dado' : int.format(s.leadsReal)}</td>
            <td className={`p-2 tabular ${corPct(pctDaMeta(s.leadsReal, s.leadsMeta))}`}>{fmtPct(pctDaMeta(s.leadsReal, s.leadsMeta))}</td>
          </tr>) : []),
        ];
      })}</tbody>
    </table>
  </div>;
}

/** Duas barras por dia (meta e realizado), empilhadas pelos mesmos segmentos e cores. SVG próprio, sem biblioteca. */
function GraficoPlano({ dias, agora }: { dias: DiaPlano[]; agora: Date }) {
  const segs = useMemo(() => segmentosDoPeriodo(dias), [dias]);
  const [foco, setFoco] = useState<string | null>(null);
  const hoje = agora.toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' });
  const max = Math.max(1, ...dias.map((d) => Math.max(d.total.verbaMeta, d.total.verbaReal ?? 0)));
  const L = 56, T = 12, H = 260, larguraDia = 44, W = L + dias.length * larguraDia + 12, barra = 15;
  const y = (v: number) => T + H - (v / max) * H;
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((t) => t * max);
  const pilha = (d: DiaPlano, x: number, campo: 'verbaMeta' | 'verbaReal') => {
    let acc = 0;
    return d.segmentos.map((s) => {
      const v = (campo === 'verbaMeta' ? s.verbaMeta : s.verbaReal) ?? 0;
      if (v <= 0) return null;
      const y0 = y(acc + v), h = y(acc) - y(acc + v); acc += v;
      return <rect key={`${campo}-${s.segmento.chave}`} x={x} y={y0} width={barra} height={Math.max(0, h)} fill={s.segmento.cor}
        opacity={(s.segmento.opaco ? 0.55 : 1) * (campo === 'verbaMeta' ? 0.45 : 1) * (foco && foco !== s.segmento.chave ? 0.25 : 1)}>
        <title>{`${fmtDia(d.dia)} · ${s.segmento.rotulo} · ${campo === 'verbaMeta' ? 'meta' : 'realizado'} ${brl.format(v)}`}</title>
      </rect>;
    });
  };
  return <div>
    <div className="overflow-x-auto">
      <svg width={W} height={T + H + 34} role="img" aria-label="Investimento por dia: meta e realizado, empilhados por segmento">
        {ticks.map((t) => <g key={t}><line x1={L} x2={W - 6} y1={y(t)} y2={y(t)} stroke="var(--border-faint)" />
          <text x={L - 6} y={y(t) + 4} textAnchor="end" fontSize="10" fill="var(--fg-3)">{t >= 1000 ? `${Math.round(t / 1000)} mil` : Math.round(t)}</text></g>)}
        {dias.map((d, i) => {
          const x0 = L + i * larguraDia + 6;
          return <g key={d.dia}>
            {d.dia === hoje && <rect x={x0 - 4} y={T} width={barra * 2 + 10} height={H} fill="var(--accent-subtle)" />}
            {pilha(d, x0, 'verbaMeta')}
            {pilha(d, x0 + barra + 2, 'verbaReal')}
            <text x={x0 + barra} y={T + H + 14} textAnchor="middle" fontSize="10" fill={d.dia === hoje ? 'var(--accent)' : 'var(--fg-3)'}>{fmtDia(d.dia)}</text>
          </g>;
        })}
      </svg>
    </div>
    <p className="mt-1 text-[11px] text-[var(--fg-3)]">Em cada dia: barra clara = meta, barra cheia = realizado. Google em tom mais claro. Passe o mouse para ver o valor.</p>
    <div className="mt-2 flex flex-wrap gap-2">{segs.map((s) => <button key={s.chave} type="button" onMouseEnter={() => setFoco(s.chave)} onMouseLeave={() => setFoco(null)}
      onFocus={() => setFoco(s.chave)} onBlur={() => setFoco(null)} className="flex items-center gap-1.5 rounded-[var(--r-pill)] border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)]">
      <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: s.cor, opacity: s.opaco ? 0.55 : 1 }} />{s.rotulo}</button>)}</div>
  </div>;
}

export function ModalPlanoDiario({ chave, agora, open, onClose }: { chave: string; agora: Date; open: boolean; onClose: () => void }) {
  const { dias, erro, lendo } = usePlanoDiario(chave, open);
  const [aba, setAba] = useState<'tabela' | 'grafico'>('tabela');
  return <Modal open={open} onClose={onClose} width="max-w-6xl" title="Investimento: meta contra realizado por dia e segmento">
    <p className="mb-3 text-xs text-[var(--fg-3)]">Meta do plano diário aprovado (verba em mídia, sem o imposto do Meta). Realizado do Meta pela coleta a cada 30 min; leads pela base oficial da Black, sem testes. Google sem coleta mostra &quot;sem dado&quot;.</p>
    <Tabs idBase="plano-diario" label="Visão do plano" active={aba} onChange={(k) => setAba(k as 'tabela' | 'grafico')} tabs={[{ k: 'tabela', l: 'Tabela' }, { k: 'grafico', l: 'Gráfico' }]} />
    <div className="mt-3">
      {erro ? <EmptyState title={erro} /> : !dias ? <EmptyState title={lendo ? 'Carregando…' : 'Sem dado ainda'} /> : dias.length === 0 ? <EmptyState title="Plano diário vazio" />
        : aba === 'tabela' ? <TabelaPlano dias={dias} agora={agora} /> : <GraficoPlano dias={dias} agora={agora} />}
    </div>
  </Modal>;
}

/** Parágrafo do topo dos Alertas: o que ajustar hoje para cumprir verba e leads. */
export function ResumoAjusteDoDia({ chave, agora, conversaoPagina }: { chave: string; agora: Date; conversaoPagina: Valor }) {
  const { dias, erro } = usePlanoDiario(chave);
  const hoje = agora.toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' });
  const texto = useMemo(() => resumoAjusteDoDia(dias?.find((d) => d.dia === hoje), agora, conversaoPagina), [dias, hoje, agora, conversaoPagina]);
  if (erro || !texto) return null;
  return <p role="status" className="mb-4 rounded-[var(--r-md)] border border-[var(--border-accent)] bg-[var(--accent-subtle)] p-3 text-sm text-[var(--fg)]"><strong>O que ajustar hoje.</strong> {texto}</p>;
}
