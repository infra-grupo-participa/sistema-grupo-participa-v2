'use client';

// Aba 4, Mensageria (dado fictício com selo; auditoria do Victor em 12/10). Cada envio tem um objetivo próprio,
// então o custo é do envio (custo total e custo por mensagem enviada), não de um resultado depois dele: o
// "custo por ingresso" saiu. Cinco canais: API, SMS e ligação (pagos, lado a lado) e grupo e e-mail (sem custo,
// com métricas próprias). Embaixo, a lista de envios no padrão do ATM (`atm/ui/DisparosDetalhe.tsx`), com filtro
// por canal. Toda razão é soma sobre soma do mesmo período; métrica que o canal não mede é "Sem dado", nunca zero.
import { useState } from 'react';
import { EmptyState, KpiCard, SectionCard } from '@/shared/ui/components';
import { dividir, somar, taxa } from '../domain/metricas';
import { CANAIS_DISPARO, CANAL_PAGO } from '../domain/tipos';
import type { CanalDisparo, CanalMensageria, EnvioMensageria, MetricasDisparo, Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { Chip, formatar, Numero, SeloFicticio, Taxa } from './pecas';

/** Rótulo de cada métrica no canal; null = o canal não mede (a linha não aparece). */
interface DefCanal {
  nome: string; curto: string;
  enviados: string; entregues: string | null; lidas: string | null; cliques: string | null; falhas: string | null;
  porEnviado: string;
}
const DEF: Record<CanalDisparo, DefCanal> = {
  api: { nome: 'API (WhatsApp)', curto: 'API', enviados: 'Enviados', entregues: 'Entregues', lidas: 'Lidas', cliques: 'Cliques', falhas: 'Falhas', porEnviado: 'Custo por mensagem enviada' },
  sms: { nome: 'SMS', curto: 'SMS', enviados: 'Enviados', entregues: 'Entregues', lidas: null, cliques: 'Cliques', falhas: 'Falhas', porEnviado: 'Custo por mensagem enviada' },
  ligacao: { nome: 'Ligação', curto: 'Ligação', enviados: 'Discadas', entregues: null, lidas: 'Atendidas', cliques: null, falhas: 'Não atendidas', porEnviado: 'Custo por ligação discada' },
  grupo: { nome: 'Grupo', curto: 'Grupo', enviados: 'Membros alcançados', entregues: null, lidas: null, cliques: 'Cliques no link', falhas: null, porEnviado: '' },
  email: { nome: 'E-mail', curto: 'E-mail', enviados: 'Enviados', entregues: 'Entregues', lidas: 'Abertos', cliques: 'Cliques', falhas: 'Devolvidos', porEnviado: '' },
};
const JANELA: Record<'2h' | '12h' | '24h', string> = { '2h': '+2h', '12h': '+12h', '24h': '+24h' };
const POR_PAGINA = 20;

/** Base das taxas de leitura e clique: entregues quando o canal mede entrega; senão, enviados. */
const baseDe = (c: CanalDisparo, m: MetricasDisparo) => (DEF[c].entregues ? m.entregues : m.enviados);
const nomeBase = (c: CanalDisparo) => (DEF[c].entregues ? 'entregues' : DEF[c].enviados.toLowerCase());

/** As linhas de métrica de um canal (ou de um envio), só as que o canal mede, com a taxa do lado. */
function linhasDe(c: CanalDisparo, m: MetricasDisparo): { r: string; v: Valor; t?: ReturnType<typeof taxa>; sobre?: string }[] {
  const d = DEF[c]; const base = baseDe(c, m);
  const out: { r: string; v: Valor; t?: ReturnType<typeof taxa>; sobre?: string }[] = [{ r: d.enviados, v: m.enviados }];
  if (d.entregues) out.push({ r: d.entregues, v: m.entregues, t: taxa(m.entregues, m.enviados), sobre: d.enviados.toLowerCase() });
  if (d.lidas) out.push({ r: d.lidas, v: m.lidas, t: taxa(m.lidas, base), sobre: nomeBase(c) });
  if (d.cliques) out.push({ r: d.cliques, v: m.cliques, t: taxa(m.cliques, base), sobre: nomeBase(c) });
  if (d.falhas) out.push({ r: d.falhas, v: m.falhas, t: taxa(m.falhas, m.enviados), sobre: d.enviados.toLowerCase() });
  return out;
}

/** "2026-10-12T09:30" (Brasília) → "12/10/2026 09:30". Valor fora do formato aparece como veio. */
function dataHora(v: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}:\d{2})/.exec(v);
  return m ? `${m[3]}/${m[2]}/${m[1]} ${m[4]}` : v;
}

export function AbaMensageria({ d }: { d: DadosTela }) {
  const m = d.mensageria;
  const [filtro, setFiltro] = useState<CanalDisparo | 'todos'>('todos');
  const [limite, setLimite] = useState(POR_PAGINA);
  if (d.mensageriaSemDado || !m || m.canais.length === 0) {
    return <EmptyState title="Sem dado de mensageria" hint="A fonte de disparos (API, SMS, ligação, grupo e e-mail) ainda não está ligada a este dashboard." />;
  }
  const canal = (k: CanalDisparo) => m.canais.find((c) => c.canal === k) ?? null;
  const pagos = m.canais.filter((c) => CANAL_PAGO[c.canal]);
  const semCusto = m.canais.filter((c) => !CANAL_PAGO[c.canal]);
  const custo = somar(pagos.map((c) => c.custo)).valor;
  // Custo por mensagem enviada: soma do custo ÷ soma dos enviados, só nos canais pagos (mesmo conjunto dos dois lados).
  const enviadosPagos = somar(pagos.map((c) => c.enviados)).valor;
  const envios = m.canais.reduce((t, c) => t + c.envios, 0);
  const lista = filtro === 'todos' ? m.envios : m.envios.filter((e) => e.canal === filtro);
  const trocar = (f: CanalDisparo | 'todos') => { setFiltro(f); setLimite(POR_PAGINA); };

  return (
    <div className="space-y-4">
      <p className="flex flex-wrap items-center gap-2 text-xs text-[var(--fg-3)]">
        <SeloFicticio>dado fictício</SeloFicticio>
        Números, títulos e copys de demonstração, só para validar o desenho da aba. Período do seletor.
      </p>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard label="Envios" value={formatar(envios, 'int')} bar="accent" hint="Disparos feitos no período, nos cinco canais" />
        <KpiCard label="Mensagens enviadas" value={formatar(somar(m.canais.map((c) => c.enviados)).valor, 'int')} bar="cyan" hint="Inclui discadas da ligação e membros alcançados no grupo" />
        <KpiCard label="Custo total" value={formatar(custo, 'brl')} bar="yellow" hint="API, SMS e ligação. Grupo e e-mail não têm custo por envio." />
        <KpiCard label="Custo por mensagem enviada" value={formatar(dividir(custo, enviadosPagos), 'brl')} bar="purple"
          hint={`${formatar(custo, 'brl')} ÷ ${formatar(enviadosPagos, 'int')} enviadas nos canais pagos`} />
      </div>

      <SectionCard title="Canais pagos, lado a lado" subtitle="Custo do envio: total e por mensagem enviada. Taxas sobre a base indicada em cada linha.">
        <div className="grid gap-3 md:grid-cols-3">
          {(['api', 'sms', 'ligacao'] as const).map((k, i) => <CartaoCanal key={k} c={canal(k)} k={k} i={i} onVer={() => trocar(k)} />)}
        </div>
      </SectionCard>

      <SectionCard title="Canais sem custo" subtitle="Grupo e e-mail não têm custo por envio; cada um com as métricas que mede.">
        <div className="grid gap-3 md:grid-cols-2">
          {(['grupo', 'email'] as const).map((k, i) => <CartaoCanal key={k} c={canal(k)} k={k} i={i} onVer={() => trocar(k)} />)}
        </div>
        {semCusto.length === 0 && <p className="mt-2 text-xs text-[var(--fg-3)]">Sem envio de grupo nem de e-mail no período.</p>}
      </SectionCard>

      <SectionCard title="Envios" subtitle="Cada disparo com título, objetivo, data e hora (Brasília), tamanho da base, copy, enviados, custo e as métricas do canal.">
        <div role="group" aria-label="Filtrar por canal" className="flex flex-wrap gap-2">
          <Chip ativo={filtro === 'todos'} onClick={() => trocar('todos')}>Todos ({formatar(m.envios.length, 'int')})</Chip>
          {CANAIS_DISPARO.map((k) => {
            const n = m.envios.filter((e) => e.canal === k).length;
            return <Chip key={k} ativo={filtro === k} onClick={() => trocar(k)}>{DEF[k].curto} ({formatar(n, 'int')})</Chip>;
          })}
        </div>
        <div className="mt-3 space-y-2">
          {lista.length === 0
            ? <EmptyState title="Nenhum envio neste canal no período" />
            : lista.slice(0, limite).map((e) => <Envio key={e.id} e={e} />)}
        </div>
        {lista.length > limite && (
          <button type="button" onClick={() => setLimite((l) => l + POR_PAGINA)}
            className="gp-press mt-3 rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]">
            Mostrar mais ({formatar(lista.length - limite, 'int')} restantes)
          </button>
        )}
      </SectionCard>

      <SectionCard title="Régua de API do grupo" subtitle="Mensagens enviadas em cada janela depois do cadastro e quantos entraram no grupo depois dela.">
        {m.regua.length === 0
          ? <p className="text-sm text-[var(--fg-3)]">Sem dado da régua no período.</p>
          : <Regua regua={m.regua} />}
      </SectionCard>
    </div>
  );
}

function CartaoCanal({ c, k, i, onVer }: { c: CanalMensageria | null; k: CanalDisparo; i: number; onVer: () => void }) {
  const d = DEF[k];
  return (
    <section aria-label={d.nome} className="atm-historico-card flex min-w-0 flex-col rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3" style={{ animationDelay: `${i * 60}ms` }}>
      <div className="flex items-baseline justify-between gap-2">
        <h3 className="text-sm font-semibold text-[var(--fg)]">{d.nome}</h3>
        <span className="text-xs text-[var(--fg-3)]">{c ? `${formatar(c.envios, 'int')} envios` : 'sem envio'}</span>
      </div>
      {!c ? <p className="mt-2 text-sm text-[var(--fg-3)]">Sem envio deste canal no período.</p> : (
        <>
          {CANAL_PAGO[k] && (
            <div className="mt-2 grid grid-cols-2 gap-2">
              <div className="rounded-[var(--r-md)] bg-[var(--surface-1)] p-2">
                <p className="text-[11px] text-[var(--fg-3)]">Custo total</p>
                <p className="text-base font-bold text-[var(--fg)]"><Numero valor={c.custo} formato="brl" animado={false} /></p>
              </div>
              <div className="rounded-[var(--r-md)] bg-[var(--surface-1)] p-2">
                <p className="text-[11px] text-[var(--fg-3)]">{d.porEnviado}</p>
                <p className="text-base font-bold text-[var(--fg)]"><Numero valor={dividir(c.custo, c.enviados)} formato="brl" animado={false} /></p>
              </div>
            </div>
          )}
          <dl className="mt-2 flex-1 divide-y divide-[var(--border-faint)] text-sm">
            {linhasDe(k, c).map((l) => (
              <div key={l.r} className="flex items-baseline justify-between gap-3 py-1.5">
                <dt className="text-[var(--fg-2)]">{l.r}</dt>
                <dd className="text-right text-[var(--fg)]">
                  <Numero valor={l.v} formato="int" animado={false} />
                  {l.t && <span className="ml-2 text-xs text-[var(--fg-3)]"><Taxa taxa={l.t} /></span>}
                </dd>
              </div>
            ))}
            {!CANAL_PAGO[k] && (
              <div className="flex items-baseline justify-between gap-3 py-1.5">
                <dt className="text-[var(--fg-2)]">Custo</dt><dd className="text-right text-[var(--fg-3)]">Sem custo por envio</dd>
              </div>
            )}
          </dl>
        </>
      )}
      <button type="button" onClick={onVer} className="mt-2 self-start text-xs text-[var(--accent)] underline-offset-2 hover:underline">Ver os envios de {d.curto}</button>
    </section>
  );
}

function Envio({ e }: { e: EnvioMensageria }) {
  const d = DEF[e.canal]; const pago = CANAL_PAGO[e.canal];
  const custo = pago ? formatar(e.custo, 'brl') : 'Sem custo por envio';
  return (
    <details className="group rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)]">
      <summary className="cursor-pointer list-none p-3 marker:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)] sm:p-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className="rounded-full border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)]">{d.curto}</span>
              <time dateTime={e.enviadoEm} className="text-xs text-[var(--fg-3)]">{dataHora(e.enviadoEm)}</time>
              <SeloFicticio />
            </div>
            <p className="mt-2 break-words font-medium text-[var(--fg)]">{e.titulo}</p>
            <p className="mt-0.5 break-words text-xs text-[var(--fg-2)]">Objetivo: {e.objetivo}</p>
          </div>
          <span className="text-xs text-[var(--accent)] group-open:hidden">Ver detalhes</span>
          <span className="hidden text-xs text-[var(--accent)] group-open:inline">Recolher</span>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2 text-xs text-[var(--fg-2)] sm:grid-cols-4">
          <span>Base: <strong className="text-[var(--fg)]">{formatar(e.base, 'int')}</strong></span>
          <span>{d.enviados}: <strong className="text-[var(--fg)]">{formatar(e.enviados, 'int')}</strong></span>
          <span>Custo: <strong className="text-[var(--fg)]">{custo}</strong></span>
          {pago
            ? <span>Por enviada: <strong className="text-[var(--fg)]">{formatar(dividir(e.custo, e.enviados), 'brl')}</strong></span>
            : <span>{d.cliques}: <strong className="text-[var(--fg)]">{formatar(e.cliques, 'int')}</strong></span>}
        </div>
      </summary>
      <div className="border-t border-[var(--border)] p-3 sm:p-4">
        <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
          <Dado r="Data e hora" v={dataHora(e.enviadoEm)} />
          <Dado r="Tamanho da base" v={formatar(e.base, 'int')} />
          {linhasDe(e.canal, e).map((l) => (
            <Dado key={l.r} r={l.r} v={formatar(l.v, 'int')} extra={l.t ? `${formatar(l.t.valor, 'pct')} sobre ${l.sobre}` : undefined} />
          ))}
          <Dado r="Custo" v={custo} />
          {pago && <Dado r={d.porEnviado} v={formatar(dividir(e.custo, e.enviados), 'brl')} extra="cálculo da tela" />}
        </dl>
        <div className="mt-3 rounded-[var(--r-md)] border border-[var(--border)] p-3">
          <h4 className="text-xs font-semibold text-[var(--fg-2)]">Copy</h4>
          <p className="mt-2 whitespace-pre-wrap break-words text-sm text-[var(--fg)]">{e.copy ?? 'Sem dado'}</p>
        </div>
      </div>
    </details>
  );
}

function Dado({ r, v, extra }: { r: string; v: string; extra?: string }) {
  return (
    <div className="min-w-0 rounded-[var(--r-md)] bg-[var(--surface-2)] p-3">
      <dt className="text-xs text-[var(--fg-3)]">{r}</dt>
      <dd className="mt-1 break-words text-sm font-medium text-[var(--fg)]">{v}</dd>
      {extra && <dd className="mt-0.5 text-[11px] text-[var(--fg-3)]">{extra}</dd>}
    </div>
  );
}

function Regua({ regua }: { regua: { janela: '2h' | '12h' | '24h'; enviados: Valor; ingressos: Valor }[] }) {
  const max = Math.max(1, ...regua.map((x) => x.enviados ?? 0));
  return (
    <ol className="space-y-3">
      {regua.map((x) => {
        const t = taxa(x.ingressos, x.enviados);
        return (
          <li key={x.janela}>
            <div className="flex flex-wrap items-baseline justify-between gap-x-3 text-sm">
              <span className="font-semibold text-[var(--fg)]">{JANELA[x.janela]}</span>
              <span className="text-xs text-[var(--fg-2)]">
                <Numero valor={x.enviados} formato="int" animado={false} /> enviados · <Numero valor={x.ingressos} formato="int" animado={false} /> no grupo · <Taxa taxa={t} />
              </span>
            </div>
            <div className="relative mt-1 h-2 overflow-hidden rounded-full bg-[var(--surface-4)]" aria-hidden="true">
              <div className="atm-historico-funil-bar absolute inset-y-0 left-0 rounded-full bg-[var(--surface-3)]" style={{ width: `${((x.enviados ?? 0) / max) * 100}%` }} />
              <div className="atm-historico-funil-bar absolute inset-y-0 left-0 rounded-full bg-[var(--green)]" style={{ width: `${((x.ingressos ?? 0) / max) * 100}%` }} />
            </div>
          </li>
        );
      })}
      <li className="text-[11px] text-[var(--fg-3)]">Barra cinza: enviados. Barra verde: entraram no grupo. Taxa = no grupo ÷ enviados, na mesma janela.</li>
    </ol>
  );
}
