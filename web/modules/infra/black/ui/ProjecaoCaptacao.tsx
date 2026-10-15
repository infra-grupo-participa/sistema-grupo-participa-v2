'use client';

import { useMemo } from 'react';
import { ehEntresafraCampanha } from '../domain/metricas';
import { arredondarInteiroRitmo, FIM_CAPTACAO, INICIO_CAPTACAO, SEMENTE_LEADS, projetarRitmo } from '../domain/ritmo';
import { ehCaptacao } from '../domain/metricas';
import { diaDe } from '../domain/recorte';
import type { Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { formatar, IndicadorMeta, moeda } from './pecas';

function diaEmSaoPaulo(data: Date): string {
  const partes = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(data);
  const get = (tipo: string) => partes.find((p) => p.type === tipo)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function progresso(d: DadosTela) {
  const hoje = diaEmSaoPaulo(d.agora);
  const leads = new Map<string, number>();
  if (!d.perfilSemDado) {
    const primeira = new Map<string, string>();
    for (const linha of d.linhasTodas) {
      if (linha.teste) continue;
      if (linha.pagina === 'consultoria_respondi') continue;
      const dia = diaDe(linha.criadoEm);
      const anterior = primeira.get(linha.pessoaId);
      if (!anterior || dia < anterior) primeira.set(linha.pessoaId, dia);
    }
    for (const dia of primeira.values()) if (dia >= INICIO_CAPTACAO && dia <= FIM_CAPTACAO) leads.set(dia, (leads.get(dia) ?? 0) + 1);
  }

  const campanhas = new Set(d.trafego.campanhas.filter((c) => !ehEntresafraCampanha(c) && c.fase !== 'remarketing'
    && !/REMARKETING/i.test(c.nome) && (c.etapa === 'C2' || c.etapa === 'C3' || (c.etapa === undefined && ehCaptacao(c.funil)))).map((c) => c.id));
  const investimento = new Map<string, number>();
  const temSerieInvestimento = Array.isArray(d.trafego.gastoCampanhasDiario);
  for (const item of d.trafego.gastoCampanhasDiario ?? []) {
    if (!campanhas.has(item.campanhaId) || item.dia < INICIO_CAPTACAO || item.dia > FIM_CAPTACAO) continue;
    investimento.set(item.dia, (investimento.get(item.dia) ?? 0) + item.gasto);
  }

  return {
    leads: projetarRitmo({ hoje, meta: d.config.metaLeads, semente: SEMENTE_LEADS, realizados: d.perfilSemDado ? new Map() : leads }),
    investimento: projetarRitmo({ hoje, meta: d.config.previstoPorFase.captacao, realizados: temSerieInvestimento ? investimento : new Map() }),
    leadsDisponivel: !d.perfilSemDado,
    investimentoDisponivel: temSerieInvestimento,
  };
}

function NumeroRitmo({ valor, brl = false }: { valor: Valor; brl?: boolean }) {
  if (valor === null) return <>Sem dado</>;
  return <>{brl ? moeda(valor) : valor.toLocaleString('pt-BR', { maximumFractionDigits: 0 })}</>;
}

function ResumoRitmo({ titulo, ritmo, meta, disponivel, brl = false }: {
  titulo: string; ritmo: ReturnType<typeof progresso>['leads']; meta: Valor; disponivel: boolean; brl?: boolean;
}) {
  const fmt = (v: Valor, modo: 'normal' | 'cima' = 'normal') => brl ? <NumeroRitmo valor={v} brl /> : <NumeroRitmo valor={arredondarInteiroRitmo(v, modo)} />;
  const cobertura: 'verde' | 'amarelo' | 'vermelho' | 'sem' = ritmo.media === null || ritmo.necessarioPorDia === null
    ? 'sem' : ritmo.necessarioPorDia <= 0 || ritmo.media / ritmo.necessarioPorDia >= 1
      ? 'verde' : ritmo.media / ritmo.necessarioPorDia >= 0.8 ? 'amarelo' : 'vermelho';
  const rotuloCobertura = { verde: 'Ritmo suficiente', amarelo: 'Ritmo perto da meta', vermelho: 'Ritmo abaixo da meta', sem: 'Ritmo sem dado' }[cobertura];
  const corCobertura = { verde: 'var(--green)', amarelo: 'var(--yellow)', vermelho: 'var(--red)', sem: 'var(--fg-3)' }[cobertura];
  return <article className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
    <div className="flex flex-wrap items-baseline justify-between gap-2">
      <h3 className="font-semibold text-[var(--fg)]">{titulo}</h3>
      <span className="text-xs text-[var(--fg-3)]">Meta {meta === null ? 'Sem meta cadastrada' : brl ? moeda(meta) : formatar(meta, 'int')} · <span className="font-medium" style={{ color: corCobertura }}>{rotuloCobertura}</span></span>
    </div>
    {!disponivel ? <p className="mt-3 text-sm text-[var(--fg-3)]">Sem dado para projetar.</p> : <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-2 text-xs sm:grid-cols-3">
      <div><dt className="text-[var(--fg-3)]">Acumulado</dt><dd className="mt-0.5 font-semibold tabular text-[var(--fg)]">{fmt(ritmo.acumuladoHoje)}</dd></div>
      <div><dt className="text-[var(--fg-3)]">Necessário por dia</dt><dd className="mt-0.5 font-semibold tabular text-[var(--fg)]">{fmt(ritmo.necessarioPorDia, 'cima')}</dd></div>
      <div><dt className="text-[var(--fg-3)]">Faltam hoje para bater a meta diária</dt><dd className="mt-0.5 font-semibold tabular text-[var(--fg)]">{fmt(ritmo.faltaHoje, 'cima')}</dd></div>
      <div><dt className="text-[var(--fg-3)]">Média dos dias fechados</dt><dd className="mt-0.5 font-semibold tabular text-[var(--fg)]">{fmt(ritmo.media)}</dd><dd className="mt-0.5 text-[10px] text-[var(--fg-3)]">{ritmo.mediaDias.length ? ritmo.mediaDias.map((d) => `${d.slice(8, 10)}/${d.slice(5, 7)}`).join(', ') : 'sem dias com valor > 0'}</dd></div>
      <div><dt className="text-[var(--fg-3)]">No ritmo de hoje fecha em</dt><dd className="mt-0.5 font-semibold tabular text-[var(--fg)]">{fmt(ritmo.projecao)}</dd>{meta !== null && ritmo.projecao !== null && <dd className="mt-0.5"><IndicadorMeta valor={ritmo.projecao} meta={meta} menorMelhor={brl} formato={brl ? 'brl' : 'int'} compacto /></dd>}</div>
      <div><dt className="text-[var(--fg-3)]">Realizado hoje</dt><dd className="mt-0.5 font-semibold tabular text-[var(--fg)]">{fmt(ritmo.realizadoHoje)}</dd></div>
    </dl>}
  </article>;
}

export function ProjecaoCaptacao({ d }: { d: DadosTela }) {
  const r = useMemo(() => progresso(d), [d]);
  return <details className="mt-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)]">
    <summary className="cursor-pointer list-none px-3 py-3 text-sm font-semibold text-[var(--fg)] marker:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
      Projeção até 03/11 <span className="ml-1 text-xs font-normal text-[var(--fg-3)]">Leads e investimento de captação</span>
    </summary>
    <div className="space-y-3 border-t border-[var(--border)] p-3">
      <p className="text-xs text-[var(--fg-3)]">Meta diária recalcula sobre os dias que faltam a partir de amanhã · projeção usa a média dos últimos 3 dias fechados com valor maior que zero. Leads: inclui semente de 154 anteriores a 12/10. Investimento: orçamento da captação ({d.config.previstoPorFase.captacao === null ? 'Sem meta cadastrada' : moeda(d.config.previstoPorFase.captacao)}). Fonte diária: primeira aparição por pessoa e dias_campanha.</p>
      <div className="grid gap-3 md:grid-cols-2">
        <ResumoRitmo titulo="Leads" ritmo={r.leads} meta={d.config.metaLeads} disponivel={r.leadsDisponivel} />
        <ResumoRitmo titulo="Investimento em captação" ritmo={r.investimento} meta={d.config.previstoPorFase.captacao} disponivel={r.investimentoDisponivel} brl />
      </div>
    </div>
  </details>;
}
