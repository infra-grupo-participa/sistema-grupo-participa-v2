'use client';

// Aba 4, Mensageria (correção 1 do plano: dado fictício com selo, pedido do Victor em 12/10). Por canal (API,
// SMS, ligação): enviados, entregues, cliques ou atendidas, custo, custo por clique e quantos viraram ingresso
// no grupo ou presença. Embaixo, a régua de API do grupo (+2h, +12h, +24h) contra o ingresso. Toda razão é soma
// sobre soma do mesmo período; sem fonte, "Sem dado" (nunca zero).
import { EmptyState, KpiCard, SectionCard } from '@/shared/ui/components';
import { dividir, somar, taxa } from '../domain/metricas';
import type { CanalMensageria, Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { formatar, Numero, SeloFicticio, Taxa } from './pecas';

const ROTULO: Record<CanalMensageria['canal'], { nome: string; acao: string }> = {
  api: { nome: 'API (WhatsApp)', acao: 'Cliques' },
  sms: { nome: 'SMS', acao: 'Cliques' },
  ligacao: { nome: 'Ligação', acao: 'Atendidas' },
};
const JANELA: Record<'2h' | '12h' | '24h', string> = { '2h': '+2h', '12h': '+12h', '24h': '+24h' };

export function AbaMensageria({ d }: { d: DadosTela }) {
  const m = d.mensageria;
  if (d.mensageriaSemDado || !m || m.canais.length === 0) {
    return <EmptyState title="Sem dado de mensageria" hint="A fonte de disparos (API, SMS, ligação) ainda não está ligada a este dashboard." />;
  }
  const soma = (f: (c: CanalMensageria) => Valor) => somar(m.canais.map(f)).valor;
  const enviados = soma((c) => c.enviados);
  const custo = soma((c) => c.custo);
  const ingresso = soma((c) => c.viraramIngresso);
  const presenca = soma((c) => c.viraramPresenca);

  return (
    <div className="space-y-4">
      <p className="flex flex-wrap items-center gap-2 text-xs text-[var(--fg-3)]">
        <SeloFicticio>dado fictício</SeloFicticio>
        Números de demonstração, só para validar o desenho da aba. Período do seletor.
      </p>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard label="Enviados" value={formatar(enviados, 'int')} bar="accent" hint="Soma dos três canais" />
        <KpiCard label="Custo" value={formatar(custo, 'brl')} bar="yellow" hint="Soma dos três canais" />
        <KpiCard label="Viraram ingresso" value={formatar(ingresso, 'int')} bar="green" hint={`Custo por ingresso ${formatar(dividir(custo, ingresso), 'brl')}`} />
        <KpiCard label="Viraram presença" value={formatar(presenca, 'int')} bar="purple" hint={`Custo por presença ${formatar(dividir(custo, presenca), 'brl')}`} />
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        {m.canais.map((c, i) => {
          const r = ROTULO[c.canal];
          const linhas: { r: string; v: React.ReactNode }[] = [
            { r: 'Enviados', v: <Numero valor={c.enviados} formato="int" animado={false} /> },
            { r: 'Entregues', v: <Taxa taxa={taxa(c.entregues, c.enviados)} /> },
            { r: r.acao, v: <Taxa taxa={taxa(c.cliquesOuAtendidas, c.entregues)} /> },
            { r: 'Custo', v: <Numero valor={c.custo} formato="brl" animado={false} /> },
            { r: c.canal === 'ligacao' ? 'Custo por atendida' : 'Custo por clique', v: <Numero valor={dividir(c.custo, c.cliquesOuAtendidas)} formato="brl" animado={false} /> },
            { r: 'Viraram ingresso', v: <Numero valor={c.viraramIngresso} formato="int" animado={false} /> },
            { r: 'Viraram presença', v: <Numero valor={c.viraramPresenca} formato="int" animado={false} /> },
          ];
          return (
            <section key={c.canal} aria-label={r.nome} className="atm-historico-card min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3" style={{ animationDelay: `${i * 60}ms` }}>
              <h3 className="text-sm font-semibold text-[var(--fg)]">{r.nome}</h3>
              <dl className="mt-2 divide-y divide-[var(--border-faint)] text-sm">
                {linhas.map((l) => (
                  <div key={l.r} className="flex items-baseline justify-between gap-3 py-1.5">
                    <dt className="text-[var(--fg-2)]">{l.r}</dt><dd className="text-right text-[var(--fg)]">{l.v}</dd>
                  </div>
                ))}
              </dl>
              <p className="mt-2 text-[11px] text-[var(--fg-3)]">Entregues sobre enviados; {r.acao.toLowerCase()} sobre entregues.</p>
            </section>
          );
        })}
      </div>

      <SectionCard title="Régua de API do grupo" subtitle="Mensagens enviadas em cada janela depois do cadastro e quantos entraram no grupo depois dela.">
        {m.regua.length === 0
          ? <p className="text-sm text-[var(--fg-3)]">Sem dado da régua no período.</p>
          : <Regua regua={m.regua} />}
      </SectionCard>
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
