'use client';

import { useCallback, useEffect, useRef, useState, type CSSProperties } from 'react';
import { DataTable, EmptyState, KpiCard, SectionCard, Tabs, Td, Th, Thead, Tr, idsAba } from '@/shared/ui/components';
import { carregarHistoricoEdicoes } from '../infrastructure/historico-data';
import {
  descreverFonte, ehProvisorio, etapasFunil, formatarHistorico, indicadoresEdicao, METRICAS_HISTORICO, metricaHistorico,
  periodoEdicao, picosAulas, ROTULO_CAMPO_FONTE, SECOES_HISTORICO, SEM_VALOR,
  variacaoPercentualHistorico, type CampoFonteHistorico, type EdicaoHistorico, type FormatoHistorico, type MetricaHistorico,
} from '../domain/historico';

const ABA_COMPARATIVO = 'comparativo';
const ID_ABAS = 'atm-historico';
const CORES_FUNIL = ['var(--accent)', 'var(--cyan)', 'var(--purple)', 'var(--yellow)', 'var(--green)'];

type PropsView = {
  edicoes: EdicaoHistorico[];
  carregando: boolean;
  erro: string | null;
  lidoEm: Date | null;
  onRecarregar: () => void;
};

/** Carrega o histórico da família (RPC `dados_historico_edicoes`) e segura o último dado bom em caso de falha. */
export function HistoricoAtm({ familia }: { familia: string }) {
  const [edicoes, setEdicoes] = useState<EdicaoHistorico[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [lidoEm, setLidoEm] = useState<Date | null>(null);
  const emCurso = useRef(false);

  const carregar = useCallback(async () => {
    if (emCurso.current) return;
    emCurso.current = true;
    try {
      const r = await carregarHistoricoEdicoes(familia);
      if (!r.erro) {
        setEdicoes(r.data);
        setLidoEm(new Date());
      }
      setErro(r.erro);
    } finally {
      emCurso.current = false;
      setCarregando(false);
    }
  }, [familia]);

  useEffect(() => { void carregar(); }, [carregar]);

  return <HistoricoAtmView edicoes={edicoes} carregando={carregando} erro={erro} lidoEm={lidoEm} onRecarregar={() => { setCarregando(true); void carregar(); }} />;
}

/** Parte visual, sem I/O: recebe as edições já ordenadas e em reais. */
export function HistoricoAtmView({ edicoes, carregando, erro, lidoEm, onRecarregar }: PropsView) {
  const [aba, setAba] = useState(ABA_COMPARATIVO);
  const abaAtiva = aba === ABA_COMPARATIVO || edicoes.some((e) => e.chave === aba) ? aba : ABA_COMPARATIVO;
  const desatualizado = erro !== null && edicoes.length > 0;
  const hora = lidoEm ? lidoEm.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' }) : null;
  const idx = edicoes.findIndex((e) => e.chave === abaAtiva);
  const ids = idsAba(ID_ABAS, abaAtiva);

  return <section aria-labelledby="atm-historico-titulo" className="min-w-0 space-y-4">
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h2 id="atm-historico-titulo" className="text-lg font-bold text-[var(--fg)]">Histórico das edições</h2>
        <p className="text-sm text-[var(--fg-2)]">Números fechados de cada Seminário ATM. Taxas, CAC, ROAS e CPL são calculados na tela a partir deles.</p>
      </div>
      <div className="flex items-center gap-3">
        <span className="text-xs text-[var(--fg-3)]" aria-live="polite">{carregando ? 'Lendo…' : hora ? `Lido às ${hora}` : 'aguardando leitura'}</span>
        <button type="button" onClick={onRecarregar} disabled={carregando} className="min-h-10 rounded-[var(--r-md)] border border-[var(--border)] px-4 text-sm text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50">Recarregar</button>
      </div>
    </div>

    {erro && <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]">{erro}{desatualizado && hora ? ` Mostrando a leitura de ${hora}.` : ''}</p>}

    {edicoes.length === 0
      ? <SectionCard><EmptyState title={carregando ? 'Carregando o histórico…' : 'Histórico sem edições'} hint={carregando ? undefined : 'sem dado ainda · as edições aparecem quando o banco devolver o histórico desta família.'} /></SectionCard>
      : <div className={'min-w-0 transition-opacity ' + (desatualizado ? 'opacity-60' : '')}>
        <Tabs idBase={ID_ABAS} label="Visões do histórico" active={abaAtiva} onChange={setAba} tabs={[{ k: ABA_COMPARATIVO, l: 'Comparativo geral' }, ...edicoes.map((e) => ({ k: e.chave, l: e.rotulo }))]} />
        <div key={abaAtiva} role="tabpanel" id={ids.panel} aria-labelledby={ids.tab} tabIndex={0} className="atm-historico-panel-enter min-w-0 focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
          {abaAtiva === ABA_COMPARATIVO || idx < 0
            ? <ComparativoGeral edicoes={edicoes} />
            : <EdicaoDetalhe edicao={edicoes[idx]} anterior={edicoes[idx - 1] ?? null} />}
        </div>
      </div>}
  </section>;
}

function ValorComFonte({ m, e, anterior, grande = false }: { m: MetricaHistorico; e: EdicaoHistorico; anterior: EdicaoHistorico | null; grande?: boolean }) {
  const v = m.valor(e, indicadoresEdicao(e, anterior));
  const prov = ehProvisorio(m, e, anterior);
  const texto = formatarHistorico(v, m.formato);
  return <span title={descreverFonte(m, e, anterior)} className={'relative inline-flex flex-col items-end tabular ' + (texto === SEM_VALOR ? 'text-[var(--fg-3)]' : '')}>
    <span className={grande ? 'font-bold' : ''}>{texto}{prov && <><span aria-hidden="true" className="ml-0.5 text-[var(--yellow)]">*</span><span className="sr-only"> (provisório)</span></>}</span>
    {v === null && m.vazio && <span className="text-[10px] font-normal text-[var(--fg-3)]">{m.vazio}</span>}
  </span>;
}

function ComparativoGeral({ edicoes }: { edicoes: EdicaoHistorico[] }) {
  const destaques = ['leads', 'grupo', 'taxa_grupo', 'pico_d1', 'pre_checkout', 'vendas', 'receita_liquida', 'cac', 'roas', 'cpl'];
  const metricas = destaques.map(metricaHistorico);

  return <div className="space-y-3">
    <div className="grid min-w-0 gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {metricas.map((m, i) => <CartaoComparativo key={m.id} m={m} edicoes={edicoes} style={{ animationDelay: `${i * 45}ms` }} />)}
    </div>
    <SectionCard title="Funil comparativo" subtitle="Cada etapa mostra a escala entre edições; passe o mouse ou foque uma barra para ver passagem e fonte.">
      <FunilComparativo edicoes={edicoes} />
    </SectionCard>
    <details className="min-w-0 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
      <summary className="cursor-pointer font-medium text-[var(--fg)]">Tabela completa do comparativo</summary>
      <div className="mt-3">
        <DataTable minWidth={220 + edicoes.length * 140}>
          <caption className="sr-only">Comparativo geral completo: métricas nas linhas, uma coluna por edição</caption>
          <Thead>
            <Th className="sticky left-0 z-[2] bg-[var(--surface-3)]">Métrica</Th>
            {edicoes.map((e) => <th key={e.chave} scope="col" className="px-3 py-2.5 text-right text-[11px] font-semibold uppercase tracking-[0.06em] whitespace-nowrap">{e.rotulo}</th>)}
          </Thead>
          <tbody>{SECOES_HISTORICO.map((secao) => <SecaoComparativo key={secao} secao={secao} edicoes={edicoes} />)}</tbody>
        </DataTable>
      </div>
    </details>
    <p className="text-xs text-[var(--fg-3)]">Passe o mouse sobre os valores para ver a fonte. <span className="text-[var(--yellow)]">*</span> provisório. {SEM_VALOR} = sem dado na fonte ou divisão por zero. CAC e CPL menores são melhores.</p>
    <FontesDetalhe edicoes={edicoes} />
  </div>;
}

function valorMetrica(m: MetricaHistorico, edicoes: EdicaoHistorico[], indice: number): number | null {
  return m.valor(edicoes[indice], indicadoresEdicao(edicoes[indice], edicoes[indice - 1] ?? null));
}

function CartaoComparativo({ m, edicoes, style }: { m: MetricaHistorico; edicoes: EdicaoHistorico[]; style?: CSSProperties }) {
  const valores = edicoes.map((e, i) => valorMetrica(m, edicoes, i));
  const maximo = Math.max(0, ...valores.filter((v): v is number => v !== null));
  const atual = valores.at(-1) ?? null;
  const anterior = valores.at(-2) ?? null;
  const variacao = variacaoPercentualHistorico(atual, anterior);
  const caiEhBom = m.id === 'cac' || m.id === 'cpl';
  const favorece = variacao === null || variacao === 0 ? null : caiEhBom ? variacao < 0 : variacao > 0;
  const seta = variacao === null ? '' : variacao > 0 ? '↑' : variacao < 0 ? '↓' : '→';
  const cor = favorece === null ? 'text-[var(--fg-3)]' : favorece ? 'text-[var(--green)]' : 'text-[var(--red)]';
  const [foco, setFoco] = useState<string | null>(null);

  return <article style={style} className="atm-historico-card gp-rise min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4 shadow-[var(--shadow-sm)]">
    <div className="flex items-start justify-between gap-2">
      <h3 className="min-w-0 text-sm font-semibold text-[var(--fg)]">{m.rotulo}</h3>
      <span className="shrink-0 text-right text-xs font-semibold tabular" aria-label={variacao === null ? 'Sem variação calculável' : `${seta} ${formatarHistorico(Math.abs(variacao), 'percentual')} contra edição anterior`}>
        {variacao === null ? SEM_VALOR : <span className={cor}>{seta} {formatarHistorico(Math.abs(variacao), 'percentual')}</span>}
        <span className="block font-normal text-[var(--fg-3)]">vs anterior</span>
      </span>
    </div>
    <div className="mt-3 space-y-3">
      {edicoes.map((e, i) => {
        const v = valores[i];
        const anteriorEdicao = edicoes[i - 1] ?? null;
        const prov = ehProvisorio(m, e, anteriorEdicao);
        const largura = v === null || maximo === 0 ? 0 : Math.min(100, Math.max(0, v / maximo * 100));
        const ativo = foco === null || foco === e.chave;
        return <div key={e.chave} onMouseEnter={() => setFoco(e.chave)} onMouseLeave={() => setFoco(null)} onFocus={() => setFoco(e.chave)} onBlur={() => setFoco(null)} className={'min-w-0 rounded-[var(--r-md)] p-2 transition-[opacity,filter,background-color] duration-200 ' + (i === edicoes.length - 1 ? 'border border-[var(--accent-border)] bg-[color-mix(in_srgb,var(--accent)_9%,var(--surface-2))] ' : '') + (ativo ? 'opacity-100' : 'opacity-40')}>
          <div className="flex min-w-0 items-baseline justify-between gap-2">
            <span className="min-w-0 truncate text-xs text-[var(--fg-2)]">{e.rotulo}{i === edicoes.length - 1 ? ' · mais recente' : ''}</span>
            <span title={descreverFonte(m, e, anteriorEdicao)} className="shrink-0 text-right text-sm font-semibold tabular text-[var(--fg)]"><ValorAnimado valor={v} formato={m.formato} />{prov && <span className="ml-0.5 text-[var(--yellow)]" aria-label="provisório">*</span>}</span>
          </div>
          <div className="mt-1 h-2 overflow-hidden rounded-full bg-[var(--surface-3)]" role="progressbar" aria-label={`${m.rotulo}, ${e.rotulo}`} aria-valuemin={0} aria-valuemax={maximo} aria-valuenow={v ?? undefined} aria-valuetext={formatarHistorico(v, m.formato)} title={descreverFonte(m, e, anteriorEdicao)}>
            {v !== null && <span className={'atm-historico-barra block h-full rounded-full ' + (i === edicoes.length - 1 ? 'bg-[var(--accent)]' : 'bg-[color-mix(in_srgb,var(--accent)_55%,var(--surface-3))]')} style={{ width: `${largura}%`, animationDelay: `${i * 70}ms` }} />}
          </div>
          {v === null && m.vazio && <span className="text-[10px] text-[var(--fg-3)]">{m.vazio}</span>}
          {prov && <span className="sr-only">Valor provisório.</span>}
        </div>;
      })}
    </div>
  </article>;
}

function ValorAnimado({ valor, formato }: { valor: number | null; formato: FormatoHistorico }) {
  const [progresso, setProgresso] = useState(1);
  useEffect(() => {
    if (valor === null || valor === 0 || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const inicio = performance.now();
    const duracao = 620;
    let frame = 0;
    const animar = (agora: number) => {
      const t = Math.min(1, (agora - inicio) / duracao);
      setProgresso(1 - (1 - t) ** 3);
      if (t < 1) frame = requestAnimationFrame(animar);
    };
    frame = requestAnimationFrame(animar);
    return () => cancelAnimationFrame(frame);
  }, [valor]);
  return <>{formatarHistorico(valor === null ? null : valor * progresso, formato)}</>;
}

function FunilComparativo({ edicoes }: { edicoes: EdicaoHistorico[] }) {
  const chavesEtapa = ['leads', 'grupo', 'pico_d1', 'pre_checkout', 'vendas'] as const;
  const rotulos = ['Leads', 'Entraram no grupo', 'Pico na live (dia 1)', 'Pré-checkout', 'Vendas'];
  const linhas = edicoes.map((e, i) => ({ e, anterior: edicoes[i - 1] ?? null, etapas: etapasFunil(e) }));
  const maximos = chavesEtapa.map((_, k) => Math.max(0, ...linhas.map((l) => l.etapas[k].valor ?? 0)));
  const [foco, setFoco] = useState<string | null>(null);
  return <div className="space-y-4">
    <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-[var(--fg-2)]">{linhas.map((l, i) => <span key={l.e.chave}><span aria-hidden="true" className="mr-1 inline-block h-2.5 w-2.5 rounded-sm" style={{ background: i === linhas.length - 1 ? 'var(--accent)' : CORES_FUNIL[i % CORES_FUNIL.length] }} />{l.e.rotulo}</span>)}</div>
    {chavesEtapa.map((id, k) => <div key={id} className="min-w-0 border-t border-[var(--border-faint)] pt-3">
      <h4 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-2)]">{rotulos[k]}</h4>
      <div className="space-y-2">{linhas.map(({ e, anterior, etapas }, i) => {
        const etapa = etapas[k];
        const m = metricaHistorico(id);
        const largura = etapa.valor === null || maximos[k] === 0 ? 0 : Math.max(0, etapa.valor / maximos[k] * 100);
        const key = `${id}:${e.chave}`;
        const ativo = foco === null || foco === key;
        const info = `${rotulos[k]} · ${e.rotulo}: ${formatarHistorico(etapa.valor, 'inteiro')}${k > 0 ? ` · ${formatarHistorico(etapa.passagem, 'percentual')} sobre a etapa anterior` : ''} · ${descreverFonte(m, e, anterior)}`;
        return <div key={key} role="group" tabIndex={0} title={info} aria-label={info} onMouseEnter={() => setFoco(key)} onMouseLeave={() => setFoco(null)} onFocus={() => setFoco(key)} onBlur={() => setFoco(null)} className={'atm-historico-interativo min-w-0 rounded-[var(--r-md)] p-2 transition-[opacity,filter,transform,background-color] duration-200 ' + (i === linhas.length - 1 ? 'bg-[color-mix(in_srgb,var(--accent)_8%,transparent)] ' : '') + (ativo ? 'opacity-100' : 'opacity-35')}>
          <div className="flex items-baseline justify-between gap-2 text-xs"><span className="min-w-0 truncate text-[var(--fg-3)]">{e.rotulo}{i === linhas.length - 1 ? ' · mais recente' : ''}</span><span className="shrink-0 font-semibold tabular text-[var(--fg)]"><ValorAnimado valor={etapa.valor} formato="inteiro" />{k > 0 && <span className="ml-2 font-normal text-[var(--fg-3)]">{formatarHistorico(etapa.passagem, 'percentual')}</span>}</span></div>
          <div className="mt-1 h-3 overflow-hidden rounded-full bg-[var(--surface-3)]"><span className="atm-historico-barra block h-full rounded-full" style={{ width: `${largura}%`, background: i === linhas.length - 1 ? 'var(--accent)' : CORES_FUNIL[i % CORES_FUNIL.length], animationDelay: `${k * 90 + i * 45}ms` }} /></div>
        </div>;
      })}</div>
    </div>)}
  </div>;
}

function SecaoComparativo({ secao, edicoes }: { secao: string; edicoes: EdicaoHistorico[] }) {
  const metricas = METRICAS_HISTORICO.filter((m) => m.secao === secao);
  return <>
    <tr className="border-t border-[var(--border)]"><th scope="colgroup" colSpan={edicoes.length + 1} className="bg-[var(--surface-2)] px-3 pb-1 pt-4 text-left text-[11px] font-semibold uppercase tracking-wider text-[var(--accent)]"><span className="sticky left-3">{secao}</span></th></tr>
    {metricas.map((m) => {
      const fundo = m.destaque ? 'bg-[color-mix(in_srgb,var(--accent)_14%,var(--surface-2))]' : 'bg-[var(--surface-2)]';
      return <Tr key={m.id} className={m.destaque ? fundo + ' font-semibold' : ''}>
        <th scope="row" className={'sticky left-0 z-[1] px-3 py-2.5 text-left text-sm font-medium text-[var(--fg-2)] ' + fundo}>
          <span className={m.destaque ? 'text-[var(--fg)]' : ''}>{m.rotulo}</span>
          {m.destaque && <span className="ml-2 rounded-full border border-[var(--accent-border)] px-2 py-0.5 text-[10px] uppercase text-[var(--accent)]">principal</span>}
        </th>
        {edicoes.map((e, i) => <Td key={e.chave} className={'text-right ' + (m.destaque ? 'text-[var(--accent)]' : 'text-[var(--fg)]')}><ValorComFonte m={m} e={e} anterior={edicoes[i - 1] ?? null} grande={m.destaque} /></Td>)}
      </Tr>;
    })}
  </>;
}

function FontesDetalhe({ edicoes }: { edicoes: EdicaoHistorico[] }) {
  const campos = Object.keys(ROTULO_CAMPO_FONTE) as CampoFonteHistorico[];
  return <details className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 text-sm">
    <summary className="cursor-pointer font-medium text-[var(--fg)]">Fonte de cada número</summary>
    <div className="mt-3 grid gap-4 md:grid-cols-2">
      {edicoes.map((e) => <div key={e.chave} className="min-w-0">
        <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">{e.rotulo}</h4>
        <dl className="space-y-1">{campos.map((c) => <div key={c} className="grid grid-cols-[minmax(0,10rem)_minmax(0,1fr)] gap-2">
          <dt className="text-[var(--fg-3)]">{ROTULO_CAMPO_FONTE[c]}</dt>
          <dd className="break-words text-[var(--fg-2)]">{e.fontes[c] ?? 'fonte não informada pelo banco'}{e.provisorio.includes(c) && <span className="ml-1 text-[var(--yellow)]">(provisório)</span>}</dd>
        </div>)}</dl>
      </div>)}
    </div>
  </details>;
}

function EdicaoDetalhe({ edicao: e, anterior }: { edicao: EdicaoHistorico; anterior: EdicaoHistorico | null }) {
  const i = indicadoresEdicao(e, anterior);
  const periodo = periodoEdicao(e);
  const card = (id: string, hint?: string) => {
    const m = metricaHistorico(id);
    const prov = ehProvisorio(m, e, anterior);
    const extra = [hint, prov ? 'provisório' : null].filter(Boolean).join(' · ');
    return <KpiCard key={id} label={m.rotulo} value={formatarHistorico(m.valor(e, i), m.formato)} title={descreverFonte(m, e, anterior)} hint={extra || undefined} bar={id === 'vendas' || id === 'receita_liquida' ? 'green' : 'accent'} />;
  };
  const principal = metricaHistorico('conversao_pre_checkout');
  const provPrincipal = ehProvisorio(principal, e, anterior);
  const camposProv = e.provisorio.map((c) => ROTULO_CAMPO_FONTE[c as CampoFonteHistorico] ?? c);

  return <div className="space-y-4">
    <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
      <h3 className="text-xl font-bold text-[var(--fg)]">{e.rotulo}</h3>
      {periodo && <span className="text-sm text-[var(--fg-2)]">{periodo}</span>}
      {camposProv.length > 0 && <span className="rounded-full border border-[var(--yellow)]/50 px-2 py-0.5 text-xs text-[var(--yellow)]">Provisório: {camposProv.join(', ')}</span>}
    </div>

    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <div title={descreverFonte(principal, e, anterior)} className="gp-rise relative min-w-0 overflow-hidden rounded-[var(--r-lg)] border border-[var(--accent-border)] bg-[color-mix(in_srgb,var(--accent)_10%,var(--surface-2))] p-5 shadow-[var(--highlight-surface),var(--shadow-sm)] col-span-2 lg:row-span-2">
        <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Conversão sobre o pré-checkout · principal</div>
        <div className={'mt-2 text-5xl font-bold tabular leading-none tracking-[-0.03em] ' + (i.conversaoPreCheckout === null ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]')}>{formatarHistorico(i.conversaoPreCheckout, 'percentual')}</div>
        <p className="mt-3 text-sm text-[var(--fg-2)]">{formatarHistorico(e.vendas, 'inteiro')} vendas de {formatarHistorico(e.preCheckout, 'inteiro')} pessoas no pré-checkout{provPrincipal ? ' · provisório' : ''}</p>
        <div className="mt-4 grid grid-cols-2 gap-3 text-sm">
          <div><div className="text-xs text-[var(--fg-3)]">Sobre o grupo</div><div className="font-semibold tabular text-[var(--fg)]">{formatarHistorico(i.conversaoGrupo, 'percentual')}</div></div>
          <div><div className="text-xs text-[var(--fg-3)]">Sobre os leads</div><div className="font-semibold tabular text-[var(--fg)]">{formatarHistorico(i.conversaoLeads, 'percentual')}</div></div>
        </div>
      </div>
      {card('receita_liquida')}
      {card('roas')}
      {card('vendas')}
      {card('cac')}
    </div>

    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
      {card('leads')}
      {card('grupo', `${formatarHistorico(i.taxaGrupo, 'percentual')} dos leads`)}
      {card('taxa_grupo')}
      {card('invest_total', `tráfego ${formatarHistorico(e.investTrafego, 'moeda')} · disparo ${formatarHistorico(e.investDisparo, 'moeda')}`)}
      {card('cpl')}
    </div>

    <div className="grid gap-4 lg:grid-cols-2">
      <SectionCard title="Pico ao vivo por aula" subtitle={anterior ? `Retenção sobre a aula anterior e comparativo com a mesma aula de ${anterior.rotulo}.` : 'Retenção sobre a aula anterior. Primeira edição: sem comparativo.'}>
        <GraficoPicos e={e} anterior={anterior} />
      </SectionCard>
      <SectionCard title="Funil da edição" subtitle="Leads até vendas, com a passagem de uma etapa para a outra.">
        <FunilEdicao e={e} />
      </SectionCard>
    </div>

    <FontesDetalhe edicoes={[e]} />
  </div>;
}

function GraficoPicos({ e, anterior }: { e: EdicaoHistorico; anterior: EdicaoHistorico | null }) {
  const picos = picosAulas(e, anterior);
  const [foco, setFoco] = useState<number | null>(null);
  const max = Math.max(1, ...picos.map((p) => p.valor ?? 0));
  const largura = 360;
  const alturaUtil = 130;
  const base = 160;
  const passo = largura / 3;
  const resumo = picos.map((p) => `dia ${p.dia}: ${p.valor === null ? 'sem dado' : formatarHistorico(p.valor, 'inteiro')}`).join(', ');
  return <div className="min-w-0">
    <svg viewBox={`0 0 ${largura} 185`} className="h-auto w-full max-h-64" role="img" aria-label={`Pico ao vivo por aula, ${resumo}`}>
      <line x1="0" x2={largura} y1={base} y2={base} stroke="var(--border-strong)" />
      {picos.map((p, k) => {
        const x = k * passo + passo / 2;
        const w = passo * 0.52;
        const metrica = metricaHistorico(p.campo);
        const textoFonte = descreverFonte(metrica, e, anterior);
        const textoTooltip = `Dia ${p.dia}: ${formatarHistorico(p.valor, 'inteiro')}; ${p.dia === 1 ? 'primeira etapa' : `${formatarHistorico(p.retencao, 'percentual')} sobre o pico da aula anterior`}; ${textoFonte}`;
        const ativo = foco === null || foco === p.dia;
        if (p.valor === null) {
          return <g key={p.dia} tabIndex={0} role="group" aria-label={textoTooltip} onMouseEnter={() => setFoco(p.dia)} onMouseLeave={() => setFoco(null)} onFocus={() => setFoco(p.dia)} onBlur={() => setFoco(null)} className={'atm-historico-interativo ' + (ativo ? '' : 'opacity-35')}>
            <title>{textoTooltip}</title>
            <rect x={x - w / 2} y={base - 50} width={w} height={50} rx="6" fill="none" stroke="var(--border-strong)" strokeDasharray="4 4" />
            <text x={x} y={base - 22} textAnchor="middle" fontSize="11" fill="var(--fg-3)">{p.dia === 3 ? 'sem dia 3' : 'sem dado'}</text>
            <text x={x} y={base + 18} textAnchor="middle" fontSize="12" fill="var(--fg-2)">Dia {p.dia}</text>
          </g>;
        }
        const h = Math.max(2, (p.valor / max) * alturaUtil);
        return <g key={p.dia} tabIndex={0} role="group" aria-label={textoTooltip} onMouseEnter={() => setFoco(p.dia)} onMouseLeave={() => setFoco(null)} onFocus={() => setFoco(p.dia)} onBlur={() => setFoco(null)} className={'atm-historico-interativo ' + (ativo ? '' : 'opacity-35')}>
          <title>{textoTooltip}</title>
          <rect className="atm-historico-barra" x={x - w / 2} y={base - h} width={w} height={h} rx="6" fill={k === 0 ? 'var(--accent)' : 'color-mix(in srgb, var(--accent) 62%, var(--surface-3))'}><title>{textoTooltip}</title></rect>
          <text x={x} y={base - h - 7} textAnchor="middle" fontSize="15" fontWeight="700" fill="var(--fg)"><ValorAnimado valor={p.valor} formato="inteiro" /></text>
          <text x={x} y={base + 18} textAnchor="middle" fontSize="12" fill="var(--fg-2)">Dia {p.dia}</text>
        </g>;
      })}
    </svg>
    <dl className="mt-2 grid grid-cols-3 gap-2 text-xs">
      {picos.map((p) => <div key={p.dia} className="min-w-0 rounded-[var(--r-md)] bg-[var(--surface-3)] p-2">
        <dt className="font-semibold text-[var(--fg-2)]">Dia {p.dia}</dt>
        <dd className="mt-1 text-[var(--fg-3)]">Retenção <strong className="tabular text-[var(--fg)]" title={p.dia === 1 ? 'Primeira aula: sem aula anterior.' : descreverFonte(metricaHistorico(p.dia === 2 ? 'retencao_d2' : 'retencao_d3'), e, anterior)}>{p.dia === 1 ? SEM_VALOR : formatarHistorico(p.retencao, 'percentual')}</strong></dd>
        <dd className="text-[var(--fg-3)]">Contra a anterior <strong className="tabular text-[var(--fg)]" title={descreverFonte(metricaHistorico(`comparativo_d${p.dia}`), e, anterior)}>{formatarHistorico(p.comparativo, 'percentual')}</strong></dd>
        {p.valor === null && p.dia === 3 && <dd className="text-[var(--fg-3)]">sem dia 3</dd>}
      </div>)}
    </dl>
  </div>;
}

function FunilEdicao({ e }: { e: EdicaoHistorico }) {
  const etapas = etapasFunil(e);
  const [foco, setFoco] = useState<string | null>(null);
  return <ol className="space-y-1" aria-label="Funil da edição">
    {etapas.map((etapa, k) => {
      const largura = etapa.doTotal === null ? 0 : Math.min(100, Math.max(2, etapa.doTotal * 100));
      const cor = CORES_FUNIL[k % CORES_FUNIL.length];
      const m = metricaHistorico(etapa.id);
      return <li key={etapa.id} className="min-w-0">
        {k > 0 && <div className="flex items-center justify-center gap-1 py-1 text-xs text-[var(--fg-3)]">
          <span aria-hidden="true">↓</span>
          <span><strong className="tabular text-[var(--fg-2)]">{formatarHistorico(etapa.passagem, 'percentual')}</strong> da etapa anterior</span>
        </div>}
        <div tabIndex={0} title={`${etapa.rotulo}: ${formatarHistorico(etapa.valor, 'inteiro')}${k > 0 ? ` · ${formatarHistorico(etapa.passagem, 'percentual')} sobre a etapa anterior` : ''} · ${descreverFonte(m, e, null)}`} onMouseEnter={() => setFoco(etapa.id)} onMouseLeave={() => setFoco(null)} onFocus={() => setFoco(etapa.id)} onBlur={() => setFoco(null)} className={'atm-historico-interativo relative h-12 overflow-hidden rounded-[var(--r-md)] bg-[var(--surface-3)] ' + (foco === null || foco === etapa.id ? '' : 'opacity-35')}>
          <div aria-hidden="true" className="atm-historico-funil-bar absolute inset-y-0 left-1/2 -translate-x-1/2 rounded-[var(--r-md)] border" style={{ width: `${largura}%`, borderColor: cor, background: `color-mix(in srgb, ${cor} 28%, transparent)`, animationDelay: `${k * 90}ms` }} />
          <div className="relative flex h-full items-center justify-between gap-2 px-3">
            <span className="min-w-0 truncate text-sm font-medium text-[var(--fg)]">{etapa.rotulo}</span>
            <span className="shrink-0 text-right">
              <span className={'block text-base font-bold tabular leading-tight ' + (etapa.valor === null ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]')}><ValorAnimado valor={etapa.valor} formato="inteiro" /></span>
              {k > 0 && <span className="block text-[10px] text-[var(--fg-3)]">{formatarHistorico(etapa.doTotal, 'percentual')} dos leads</span>}
            </span>
          </div>
        </div>
      </li>;
    })}
  </ol>;
}
