'use client';

// Aba 5, Histórico (molde HistoricoAtm do ATM). Régua de dias que "toca" o funil dia a dia (autoplay só sem
// movimento reduzido) e o gráfico do período: investimento por dia em barras, pessoas únicas acumuladas desde o
// início do projeto. O funil do dia é só da
// captação (C2 e C3), como na Visão geral; o investimento e o acumulado seguem o funil e o canal do seletor.
import { useMemo, useState } from 'react';
import { KpiCard, SectionCard } from '@/shared/ui/components';
import { agregar, cpm, ctr, ehCaptacao, ehEntresafraCampanha, filtrarDias, filtrarLinhas, linhasCaptacao, taxa } from '../domain/metricas';
import { connectRate, conversaoPagina } from '../domain/numeros';
import { serieHistorico, type DiaHistorico } from '../domain/historico';
import { diaDe } from '../domain/recorte';
import { FunilTrapezio } from './graficos';
import type { EtapaFunil } from '../domain/criativos';
import type { DadosTela } from './contexto';
import { inteiro, moeda } from './pecas';
import { ResumoLeads } from './ResumoLeads';

const dataCurta = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

export function AbaHistorico({ d }: { d: DadosTela }) {
  const { serie, serieCap } = useMemo(() => {
    const fim = d.diasPeriodo[d.diasPeriodo.length - 1] ?? '';
    const f = { funil: d.recorte.funil, canal: d.recorte.canal };
    const dias = filtrarDias(d.diasTodos, d.idx, f);
    const todas = d.linhasTodas.filter((l) => l.pagina !== 'consultoria_respondi' && diaDe(l.criadoEm) <= fim);
    const linhas = filtrarLinhas(todas, f);
    const linhasCap = linhasCaptacao(linhas, d.idx);
    const diasCap = dias.filter((x) => ehCaptacao(d.idx.campanhaDoAnuncio(x.anuncioId)?.funil));
    const cfg = { inicioCaptacao: d.config.inicioCaptacao, metaLeadsDia: d.config.metaLeadsDia };
    return {
      serie: serieHistorico(dias, linhas, d.diasPeriodo, cfg, todas),
      serieCap: serieHistorico(diasCap, linhasCap, d.diasPeriodo, cfg, todas),
    };
  }, [d.diasTodos, d.linhasTodas, d.idx, d.recorte.funil, d.recorte.canal, d.diasPeriodo, d.config.inicioCaptacao, d.config.metaLeadsDia]);

  const ultimo = serie.length - 1;
  const [escolhido, setEscolhido] = useState<number | null>(null);
  const i = escolhido === null ? ultimo : Math.min(escolhido, ultimo);
  if (serie.length === 0) return <p className="text-sm text-[var(--fg-3)]">Sem dia no período.</p>;
  const dia = serie[i];
  const cap = serieCap[i];
  const modoGeral = d.recorte.historicoModo === 'geral';
  const inicio = d.diasPeriodo[0]; const fim = d.diasPeriodo[d.diasPeriodo.length - 1];
  const filtro = { funil: d.recorte.funil, canal: d.recorte.canal };
  const diasCapPeriodo = filtrarDias(d.diasTodos.filter((x) => x.dia >= inicio && x.dia <= fim), d.idx, filtro)
    .filter((x) => ehCaptacao(d.idx.campanhaDoAnuncio(x.anuncioId)?.funil));
  const linhasPeriodo = filtrarLinhas(d.linhasTodas.filter((l) => diaDe(l.criadoEm) >= inicio && diaDe(l.criadoEm) <= fim && l.pagina !== 'consultoria_respondi'), filtro);
  const linhasCapPeriodo = linhasCaptacao(linhasPeriodo, d.idx);
  const agregadoGeral = agregar(diasCapPeriodo);
  const mqlPagoGeral = d.perfilSemDado ? null : somaConhecida(serieCap.map((x) => x.mqlPagos));
  const mqlPagoBase = d.perfilSemDado ? null : somaConhecida(serieCap.map((x) => x.mqlPagosBase));
  const leadsTotalPeriodo = d.perfilSemDado ? null : somaConhecida(serie.map((x) => x.pessoasNovas));
  const ingressoTotalPeriodo = d.perfilSemDado ? null : somaConhecida(serie.map((x) => x.ingressoGrupo));
  const leadsTrafegoPeriodo = d.perfilSemDado ? null : somaConhecida(serieCap.map((x) => x.leadsPagos));

  return (
    <div className="space-y-4">
      <SectionCard title="Histórico · funil" subtitle={modoGeral ? 'O funil soma o período inteiro com os filtros ativos.' : 'Arraste a régua para ver o funil de cada dia do período.'}>
        <div className="mb-3 inline-flex rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-1" role="group" aria-label="Modo do funil do Histórico">
          {(['dia-a-dia', 'geral'] as const).map((modo) => <button key={modo} type="button" aria-pressed={(modo === 'geral') === modoGeral}
            onClick={() => d.irPara({ historicoModo: modo })}
            className={`min-h-10 rounded-[var(--r-sm)] px-3 text-sm font-semibold ${((modo === 'geral') === modoGeral) ? 'bg-[var(--surface-1)] text-[var(--fg)] shadow-sm' : 'text-[var(--fg-2)] hover:text-[var(--fg)]'}`}>
            {modo === 'dia-a-dia' ? 'Dia a dia' : 'Geral'}
          </button>)}
        </div>
        {modoGeral ? (
          <>
            <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
              <KpiCard label="Leads totais" value={inteiro(leadsTotalPeriodo)} bar="accent" title="Pessoas únicas pela data do primeiro cadastro no período, após filtro de funil e canal." hint={<span>Do tráfego C2/C3: <strong>{inteiro(leadsTrafegoPeriodo)}</strong></span>} />
              <KpiCard label="Ingresso no grupo geral" value={<span>{inteiro(ingressoTotalPeriodo)} · {formatarTaxa(taxa(ingressoTotalPeriodo, leadsTotalPeriodo).valor)}</span>} bar="green" title={`${inteiro(ingressoTotalPeriodo)} pessoas únicas que entraram em algum grupo ÷ ${inteiro(leadsTotalPeriodo)} leads da coorte no período.`} />
              <KpiCard label="Leads acumulados" value={inteiro(d.perfilSemDado ? null : serie[serie.length - 1].pessoasAcumuladas)} bar="green" title="Pessoas únicas de todas as portas acumuladas desde o início." />
            </div>
            <FunilGeral dias={diasCapPeriodo} linhas={linhasCapPeriodo} agregado={agregadoGeral}
              mql={mqlPagoGeral} mqlBase={mqlPagoBase}
              ingresso={ingressoTotalPeriodo} ingressoBase={leadsTotalPeriodo} idx={d.idx} perfilSemDado={d.perfilSemDado} />
            <div className="mt-4"><ResumoLeads linhas={linhasPeriodo} idx={d.idx} grupo={d.grupo.data} compacto semDado={d.perfilSemDado} /></div>
          </>
        ) : <>
        <div className="flex flex-wrap items-center gap-3">
          <label className="flex min-w-0 flex-1 items-center gap-2 text-xs text-[var(--fg-3)]">
            <span className="sr-only">Dia</span>
            <input type="range" min={0} max={ultimo} value={i} onChange={(e) => setEscolhido(Number(e.target.value))}
              aria-valuetext={dataCurta(dia.dia)} className="min-w-0 flex-1 accent-[var(--accent)] max-md:h-11" />
            <span className="w-12 shrink-0 text-right font-semibold tabular text-[var(--fg)]">{dataCurta(dia.dia)}</span>
          </label>
        </div>

        <div className="mt-3 grid grid-cols-2 gap-3 max-sm:grid-cols-1 lg:grid-cols-4">
          <KpiCard label="Investimento do dia" value={moeda(dia.gasto)} bar="yellow" title="No funil e canal selecionados." />
          <KpiCard label="Leads acumulados" value={inteiro(d.perfilSemDado ? null : dia.pessoasAcumuladas)} bar="green" title="Pessoas únicas de todas as portas desde o início; igual ao card Leads contra a meta." />
        </div>

        <FunilDia key={dia.dia} dia={dia} cap={cap} dados={d} />
        <ResumoLeads linhas={filtrarLinhas(d.linhasTodas.filter((l) => diaDe(l.criadoEm) === dia.dia && l.pagina !== 'consultoria_respondi'), filtro)} idx={d.idx} compacto semDado={d.perfilSemDado} />
        </>}
      </SectionCard>

      <SectionCard title="Investimento e leads acumulados" subtitle="Barras: investimento do dia no filtro escolhido. Linha: pessoas únicas de todas as portas acumuladas desde o início.">
        <Grafico serie={serie} ativo={i} onEscolher={setEscolhido} />
      </SectionCard>
    </div>
  );
}

function somaConhecida(valores: (number | null)[]): number {
  return valores.reduce<number>((soma, valor) => soma + (valor ?? 0), 0);
}

function formatarTaxa(valor: number | null): string {
  return valor === null ? 'Sem dado' : new Intl.NumberFormat('pt-BR', { style: 'percent', minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(valor);
}

function FunilGeral({ dias, linhas, agregado, mql, mqlBase, ingresso, ingressoBase, idx, perfilSemDado }: {
  dias: DadosTela['dias']; linhas: DadosTela['linhas']; agregado: ReturnType<typeof agregar>;
  mql: number | null; mqlBase: number | null; ingresso: number | null; ingressoBase: number | null;
  idx: DadosTela['idx'];
  perfilSemDado: boolean;
}) {
  const calculada = conversaoPagina(dias, linhas, idx);
  const conversao = perfilSemDado ? { ...calculada, valor: null, num: null, den: null } : calculada;
  const etapas: EtapaFunil[] = [
    { chave: 'impressoes', rotulo: 'Impressões', valor: dias.length ? agregado.impressoes : null, ponte: null },
    { chave: 'cliques', rotulo: 'Cliques no link', valor: agregado.cliques.valor, ponte: { rotulo: 'CTR', taxa: ctr(agregado) } },
    { chave: 'lpv', rotulo: 'Views da página', valor: agregado.lpv.valor, ponte: { rotulo: 'Connect rate', taxa: connectRate(dias, idx) } },
    { chave: 'leads', rotulo: 'Leads pagos', valor: conversao.num, ponte: { rotulo: 'Conversão da página', taxa: conversao } },
    { chave: 'mql', rotulo: 'MQL entre leads pagos', valor: mqlBase ? mql : null, ponte: { rotulo: '% MQL dos pagos', taxa: taxa(mqlBase ? mql : null, mqlBase || null) } },
    { chave: 'grupo', rotulo: 'Ingresso no grupo · geral', valor: ingressoBase ? ingresso : null, subtexto: `${inteiro(ingresso)}, de ${inteiro(ingressoBase)} leads`, ponte: { rotulo: '% ingresso de todos', taxa: taxa(ingressoBase ? ingresso : null, ingressoBase || null) } },
  ];
  return <section aria-label="Funil geral do período" className="mt-4">
    <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funil geral · filtros ativos</h3>
    <div className="mx-auto max-w-3xl"><FunilTrapezio etapas={etapas} rotulo="Funil geral do período · tráfego C2/C3 e ingresso de todos os leads" /></div>
    <p className="mt-2 text-center text-xs text-[var(--fg-3)]">CPM: {moeda(dias.length ? cpm(agregado) : null)}</p>
  </section>;
}

function FunilDia({ dia, cap, dados }: { dia: DiaHistorico; cap: DiaHistorico; dados: DadosTela }) {
  const dias = dados.diasTodos.filter((x) => x.dia === dia.dia && !ehEntresafraCampanha(dados.idx.campanhaDoAnuncio(x.anuncioId))
    && ehCaptacao(dados.idx.campanhaDoAnuncio(x.anuncioId)?.funil));
  const linhas = linhasCaptacao(dados.linhasTodas.filter((l) => l.pagina !== 'consultoria_respondi' && diaDe(l.criadoEm) === dia.dia), dados.idx);
  const agregado = agregar(dias);
  const inscricoes = conversaoPagina(dias, linhas, dados.idx);
  const etapas: EtapaFunil[] = [
    { chave: 'impressoes', rotulo: 'Impressões', valor: agregado.impressoes, ponte: null },
    { chave: 'cliques', rotulo: 'Cliques no link', valor: agregado.cliques.valor, ponte: { rotulo: 'CTR', taxa: ctr(agregado) } },
    { chave: 'lpv', rotulo: 'Views da página', valor: agregado.lpv.valor, ponte: { rotulo: 'Connect rate', taxa: connectRate(dias, dados.idx) } },
    { chave: 'leads', rotulo: 'Leads pagos', valor: inscricoes.num, ponte: { rotulo: 'Conversão da página', taxa: inscricoes } },
    { chave: 'mql', rotulo: 'MQL entre leads pagos', valor: cap.mqlPagos, ponte: { rotulo: '% MQL dos pagos', taxa: taxa(cap.mqlPagos, cap.mqlPagosBase) } },
    { chave: 'grupo', rotulo: 'Ingresso no grupo · todos os leads', valor: dia.ingressoGrupo, subtexto: `de ${inteiro(dia.pessoasNovas)} leads do dia`, ponte: { rotulo: '% ingresso de todos os leads', taxa: taxa(dia.ingressoGrupo, dia.pessoasNovas) } },
  ];
  return (
    <section aria-label="Funil do dia: tráfego C2/C3 e ingresso de todos os leads" className="mt-4">
      <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funil do dia · tráfego C2/C3 + ingresso geral</h3>
      <div className="mx-auto max-w-3xl"><FunilTrapezio etapas={etapas} rotulo="Funil do dia · tráfego C2/C3 e ingresso de todos os leads" /></div>
      <p className="mt-2 text-center text-xs text-[var(--fg-3)]">CPM: {moeda(cpm(agregado))}</p>
    </section>
  );
}

function Grafico({ serie, ativo, onEscolher }: { serie: DiaHistorico[]; ativo: number; onEscolher: (k: number) => void }) {
  const W = 720; const H = 220; const topo = 12; const base = H - 24; const n = serie.length;
  const larg = W / n;
  const maxG = Math.max(1, ...serie.map((s) => s.gasto));
  const maxP = Math.max(1, ...serie.map((s) => s.pessoasAcumuladas));
  const yP = (v: number) => base - (v / maxP) * (base - topo);
  const x = (k: number) => (k + 0.5) * larg;
  const linhaPessoas = serie.map((s, k) => `${x(k)},${yP(s.pessoasAcumuladas)}`).join(' ');
  const passos = Math.max(1, Math.ceil(n / 8));
  return (
    <figure className="min-w-0">
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img"
        aria-label={`Período de ${dataCurta(serie[0].dia)} a ${dataCurta(serie[n - 1].dia)}. No último dia: investimento ${moeda(serie[n - 1].gasto)}, ${inteiro(serie[n - 1].pessoasAcumuladas)} leads acumulados.`}>
        {serie.map((s, k) => {
          const h = (s.gasto / maxG) * (base - topo) * 0.6;
          const dica = `${dataCurta(s.dia)}: investimento do dia ${moeda(s.gasto)} · ${inteiro(s.pessoasAcumuladas)} leads acumulados`;
          return (
            <g key={s.dia} role="button" tabIndex={0} aria-label={dica} aria-pressed={k === ativo} className="atm-historico-interativo cursor-pointer"
              onMouseEnter={() => onEscolher(k)} onFocus={() => onEscolher(k)}
              onClick={() => onEscolher(k)} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onEscolher(k); } }}>
              <rect x={k * larg} y={topo} width={larg} height={base - topo} fill="transparent" />
              <rect className="atm-historico-barra" x={k * larg + larg * 0.18} width={larg * 0.64} y={base - h} height={h} rx="2"
                fill={k === ativo ? 'var(--accent)' : 'var(--surface-4)'}><title>{dica}</title></rect>
            </g>
          );
        })}
        <line x1="0" x2={W} y1={base} y2={base} stroke="var(--border)" />
        <polyline points={linhaPessoas} fill="none" stroke="var(--cyan)" strokeWidth="2.5" vectorEffect="non-scaling-stroke" />
        <line x1={x(ativo)} x2={x(ativo)} y1={topo} y2={base} stroke="var(--accent)" strokeWidth="1" vectorEffect="non-scaling-stroke" opacity="0.6" />
        {serie.map((s, k) => (k % passos === 0 || k === n - 1) && (
          <text key={`t-${s.dia}`} x={x(k)} y={H - 6} textAnchor="middle" className="fill-[var(--fg-3)] text-[13px]">{dataCurta(s.dia)}</text>
        ))}
      </svg>
      <p role="status" className="mt-2 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2 text-sm text-[var(--fg)]">
        {dataCurta(serie[ativo].dia)} · Investimento do dia: <strong>{moeda(serie[ativo].gasto)}</strong> · Leads acumulados: <strong>{inteiro(serie[ativo].pessoasAcumuladas)}</strong>
      </p>
      <figcaption className="mt-1 flex flex-wrap gap-3 text-xs text-[var(--fg-3)]">
        <span className="inline-flex items-center gap-1"><span aria-hidden="true" className="h-2 w-3 rounded-sm bg-[var(--surface-4)]" />Investimento (máx. {moeda(maxG)})</span>
        <span className="inline-flex items-center gap-1"><span aria-hidden="true" className="h-0.5 w-3 bg-[var(--cyan)]" />Pessoas acumuladas</span>
      </figcaption>
    </figure>
  );
}
