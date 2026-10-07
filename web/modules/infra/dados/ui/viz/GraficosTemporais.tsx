import { EmptyState } from '@/shared/ui/components';
import { numero, type SerieVendasPresencial, type VendaHoraPresencial } from '../../domain/presencial';
import { dataBR, percentual, reais } from '../formato';

function LinhaTempo({ titulo, linhas, cor, formatar }: { titulo: string; linhas: { dia: string; valor: number | null }[]; cor: string; formatar: (n: number) => string }) {
  if (!linhas.some((l) => l.valor !== null)) return <div><h4 className="mb-2 text-xs font-semibold text-[var(--fg-2)]">{titulo}</h4><EmptyState title="Sem dados para este gráfico" /></div>;
  const maximo = Math.max(1, ...linhas.map((l) => l.valor ?? 0));
  const largura = Math.max(440, (linhas.length - 1) * 28 + 64);
  const altura = 150;
  const ponto = (l: { valor: number | null }, i: number) => ({ x: 30 + i * (largura - 60) / Math.max(1, linhas.length - 1), y: altura - (l.valor ?? 0) / maximo * (altura - 20) });
  return <div className="min-w-0"><h4 className="mb-2 text-xs font-semibold text-[var(--fg-2)]">{titulo}</h4><div className="overflow-x-auto"><svg width={largura} height={altura + 34} viewBox={`0 0 ${largura} ${altura + 34}`} role="img" aria-label={titulo}>
    <line x1="30" y1={altura} x2={largura - 30} y2={altura} stroke="var(--border)" />
    {linhas.slice(1).map((l, i) => { const anterior = linhas[i]; if (anterior.valor === null || l.valor === null) return null; const a = ponto(anterior, i), b = ponto(l, i + 1); return <line key={`${anterior.dia}-${l.dia}`} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke={cor} strokeWidth="2.5" />; })}
    {linhas.map((l, i) => { if (l.valor === null) return null; const p = ponto(l, i); return <circle key={l.dia} cx={p.x} cy={p.y} r="3.5" fill={cor}><title>{`${dataBR(l.dia)}: ${formatar(l.valor)}`}</title></circle>; })}
    {linhas.map((l, i) => i % Math.max(1, Math.ceil(linhas.length / 8)) === 0 || i === linhas.length - 1 ? <text key={l.dia} x={ponto(l, i).x} y={altura + 18} textAnchor="middle" fontSize="10" fill="var(--fg-3)">{dataBR(l.dia).slice(0, 5)}</text> : null)}
  </svg></div></div>;
}

export function GraficosSerieVendas({ linhas }: { linhas: SerieVendasPresencial[] }) {
  if (!linhas.length) return <EmptyState title="Sem vendas na série" />;
  return <div className="grid gap-4 xl:grid-cols-2">
    <section className="space-y-4 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4 xl:col-span-2"><h3 className="text-sm font-semibold text-[var(--fg)]">Vendas e receita acumuladas por dia</h3><div className="grid gap-4 xl:grid-cols-2"><LinhaTempo titulo="Vendas acumuladas" linhas={linhas.map((l) => ({ dia: l.dia, valor: l.vendas_acumuladas }))} cor="var(--green)" formatar={(n) => `${n.toLocaleString('pt-BR')} vendas`} /><LinhaTempo titulo="Receita bruta acumulada" linhas={linhas.map((l) => ({ dia: l.dia, valor: numero(l.receita_acumulada) }))} cor="var(--accent)" formatar={reais} /></div></section>
    <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4 xl:col-span-2"><h3 className="mb-1 text-sm font-semibold text-[var(--fg)]">Conversão por dia</h3><p className="mb-3 text-xs text-[var(--fg-2)]">Vendas do dia ÷ pré-checkout do dia. Dia sem pré-checkout aparece sem ponto.</p><LinhaTempo titulo="Conversão diária" linhas={linhas.map((l) => ({ dia: l.dia, valor: numero(l.conversao_pct) }))} cor="var(--cyan)" formatar={percentual} /></section>
  </div>;
}

export function GraficoVendasHora({ linhas }: { linhas: VendaHoraPresencial[] }) {
  const maximo = Math.max(1, ...linhas.map((l) => l.vendas));
  return <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4"><h3 className="mb-1 text-sm font-semibold text-[var(--fg)]">Vendas por hora do dia</h3><p className="mb-3 text-xs text-[var(--fg-2)]">Hora da aprovação em São Paulo.</p>
    {!linhas.length ? <EmptyState title="Sem dados por hora" /> : <div className="overflow-x-auto"><svg className="min-w-[620px] w-full" height="170" viewBox="0 0 720 170" role="img" aria-label="Vendas por hora do dia">
      <line x1="24" y1="136" x2="704" y2="136" stroke="var(--border)" />
      {linhas.map((l) => { const x = 26 + l.hora * 28, h = l.vendas / maximo * 112; return <g key={l.hora}><rect x={x} y={136 - h} width="19" height={h} rx="2" fill="var(--purple)"><title>{`${String(l.hora).padStart(2, '0')}h: ${l.vendas} vendas, ${reais(l.receita_bruta)}`}</title></rect>{l.hora % 3 === 0 && <text x={x + 9} y="155" textAnchor="middle" fontSize="10" fill="var(--fg-3)">{String(l.hora).padStart(2, '0')}h</text>}</g>; })}
    </svg></div>}
  </section>;
}
