'use client';

// Aba 1, Visão geral: "estamos no caminho?". Só cards, cada card abre o ModalCard com as sub-abas fixas.
// Faixa 1 placar · Faixa 2 investimento · Faixa 3 funil macro (só C2 e C3) · Faixa 4 funis lado a lado + CPL por
// etapa. Razão = soma sobre soma no mesmo recorte; sem dado = "Sem dado", nunca zero.
import { useState, type ReactNode } from 'react';
import { KpiCard, ProgressBar, SectionCard } from '@/shared/ui/components';
import {
  agregar, connectRate, conversaoPagina, cpc, cplDo, cplPlacar, cplPorEtapa, cplRemarketing, cpm, ctr, custoPorVisualizacao,
  dividir, ehCaptacao, farolCpl, filtrarDias, filtrarLinhas, gastoDe, gastoPorFase, ingressoGrupo, pessoasUnicas, somar,
  taxaVideo75, type Taxa as TipoTaxa,
} from '../domain/metricas';
import { FASES, FUNIS, ROTULO_FASE, ROTULO_FUNIL, type DesempenhoDia, type Funil, type LinhaPerfil, type Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { ModalCard, type CardDef, type SubAbaModal } from './ModalCard';
import { BarrasFase } from './graficos';
import { Farol, formatar, moeda, Numero, SeloFicticio, Taxa } from './pecas';

const TODAS: SubAbaModal[] = ['funil', 'canal', 'fase', 'dia', 'criativo', 'perfil'];
const TRAFEGO: SubAbaModal[] = ['funil', 'canal', 'fase', 'dia', 'criativo'];
const capDias = (dias: DesempenhoDia[], d: DadosTela) => dias.filter((x) => ehCaptacao(d.idx.campanhaDoAnuncio(x.anuncioId)?.funil));
const capLinhas = (linhas: LinhaPerfil[]) => linhas.filter((l) => ehCaptacao(l.funil));
const valorTaxa = (t: TipoTaxa): Valor => t.valor;

function Cartao({ onAbrir, titulo, children, cheio = false }: { onAbrir?: () => void; titulo: string; children: ReactNode; cheio?: boolean }) {
  // `cheio`: o card ocupa a altura toda da célula (grade com linhas iguais no funil macro).
  const altura = cheio ? ' h-full [&>*]:h-full' : '';
  if (!onAbrir) return <div className={'min-w-0' + altura}>{children}</div>;
  return (
    <div role="button" tabIndex={0} aria-label={`Abrir detalhe: ${titulo}`} onClick={onAbrir}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onAbrir(); } }}
      className={'atm-historico-card atm-historico-interativo min-w-0 cursor-pointer' + altura + '  rounded-[var(--r-lg)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)]'}>
      {children}
    </div>
  );
}

function tempoAte(alvo: string, agora: Date): string {
  const ms = Date.parse(alvo) - agora.getTime();
  if (!Number.isFinite(ms)) return 'Sem dado';
  if (ms <= 0) return 'Já começou';
  const dias = Math.floor(ms / 86_400_000); const horas = Math.floor((ms % 86_400_000) / 3_600_000);
  return dias > 0 ? `${dias} d ${horas} h` : `${horas} h ${Math.floor((ms % 3_600_000) / 60_000)} min`;
}
const dataHora = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

export function AbaVisaoGeral({ d }: { d: DadosTela }) {
  const [aberto, setAberto] = useState<CardDef | null>(null);
  const { config, idx, recorte } = d;
  const filtro = { funil: recorte.funil, canal: recorte.canal };
  const abrir = (c: CardDef) => () => setAberto(c);

  // ─── Faixa 1: placar (do início até agora) ──────────────────────────────────────────────────────────────
  const diasAteHoje = filtrarDias(d.diasTodos, idx, filtro);
  const linhasAteAgora = filtrarLinhas(d.linhasTodas, filtro);
  const leadsAteAgora = pessoasUnicas(linhasAteAgora);
  const gastoAteHoje = gastoDe(diasAteHoje);
  const placar = cplPlacar(d.dias, d.linhas, idx);

  const cardLeads: CardDef = { id: 'leads', rotulo: 'Leads (pessoas únicas)', formato: 'int', medir: (_, l) => pessoasUnicas(l), aplica: TODAS,
    dica: 'No detalhe, o recorte é o período escolhido no topo. Uma pessoa com duas portas conta uma vez.' };
  const cardCpl: CardDef = { id: 'cpl', rotulo: 'CPL geral', formato: 'brl', medir: (x, l) => cplPlacar(x, l, idx).valor, aplica: TRAFEGO, menorMelhor: true,
    dica: 'Gasto de captação e remarketing ÷ leads que vieram de anúncio, no mesmo período (regra provisória, BLOQUEIO 3).' };
  const cardGasto: CardDef = { id: 'gasto', rotulo: 'Gasto de tráfego', formato: 'brl', medir: (x) => (x.length ? gastoDe(x) : null), aplica: TRAFEGO,
    dica: 'No detalhe, o recorte é o período escolhido no topo.' };

  // ─── Faixa 2: investimento (período) ────────────────────────────────────────────────────────────────────
  const gastoPeriodo = gastoDe(d.dias);
  const porCanal = (c: 'meta' | 'google') => gastoDe(filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: recorte.funil, canal: c }));
  const disparoAplica = recorte.funil === 'todos' && recorte.canal === 'todos';
  const custoDisparo = d.mensageria ? somar(d.mensageria.canais.map((c) => c.custo)) : null;
  const total = disparoAplica && custoDisparo?.valor != null ? gastoPeriodo + custoDisparo.valor : gastoPeriodo;
  const notaTotal = !disparoAplica ? 'Disparo não se divide por funil nem canal: fora da soma.'
    : custoDisparo?.valor == null ? 'Custo de disparo sem dado: fora da soma.' : 'Tráfego + disparo (disparo fictício).';
  const fases = gastoPorFase(d.dias, idx);
  const custoCanal = (k: 'api' | 'sms' | 'ligacao') => d.mensageria?.canais.find((c) => c.canal === k)?.custo ?? null;

  // ─── Faixa 3: funil macro (só captação) ─────────────────────────────────────────────────────────────────
  const dCap = capDias(d.dias, d); const lCap = capLinhas(d.linhas);
  const aCap = agregar(dCap);
  const medirCap = (f: (a: ReturnType<typeof agregar>) => Valor) => (x: DesempenhoDia[]) => { const c = capDias(x, d); return c.length ? f(agregar(c)) : null; };
  // Ordem pedida pelo Victor (12/10): Impressões, CPM, Cliques, CTR, CPC, Visualizações, Connect, Inscrições, Conversão, Grupo.
  const cards3: { c: CardDef; valor: ReactNode; hint?: string }[] = [
    { c: { id: 'imp', rotulo: 'Impressões', formato: 'int', medir: medirCap((a) => a.impressoes), aplica: TRAFEGO }, valor: <Numero valor={dCap.length ? aCap.impressoes : null} formato="int" /> },
    { c: { id: 'cpm', rotulo: 'CPM', formato: 'brl', medir: medirCap(cpm), aplica: TRAFEGO, menorMelhor: true, dica: 'Custo por mil impressões: gasto ÷ impressões × 1000.' }, valor: <Numero valor={dCap.length ? cpm(aCap) : null} formato="brl" />, hint: 'Custo por mil impressões.' },
    { c: { id: 'cliques', rotulo: 'Cliques no link', formato: 'int', medir: (x) => agregar(capDias(x, d)).cliques.valor, aplica: TRAFEGO }, valor: <Numero valor={aCap.cliques.valor} formato="int" /> },
    { c: { id: 'ctr', rotulo: 'CTR', formato: 'pct', medir: (x) => valorTaxa(ctr(agregar(capDias(x, d)))), aplica: TRAFEGO, dica: 'Cliques no link ÷ impressões.' }, valor: <Taxa taxa={ctr(aCap)} /> },
    { c: { id: 'cpc', rotulo: 'CPC', formato: 'brl', medir: medirCap(cpc), aplica: TRAFEGO, menorMelhor: true, dica: 'Custo por clique: gasto ÷ cliques no link, só nas linhas com clique medido.' }, valor: <Numero valor={dCap.length ? cpc(aCap) : null} formato="brl" />, hint: 'Custo por clique no link.' },
    { c: { id: 'lpv', rotulo: 'Visualizações da página', formato: 'int', medir: (x) => agregar(capDias(x, d)).lpv.valor, aplica: TRAFEGO }, valor: <Numero valor={aCap.lpv.valor} formato="int" />, hint: aCap.lpv.conhecidos < aCap.lpv.total ? 'Parcial: Google sem LPV.' : undefined },
    { c: { id: 'connect', rotulo: 'Connect rate', formato: 'pct', medir: (x) => valorTaxa(connectRate(x, idx)), aplica: TRAFEGO, dica: 'Σ views da página ÷ Σ cliques, só nas linhas com as duas métricas.' }, valor: <Taxa taxa={connectRate(d.dias, idx)} /> },
    { c: { id: 'insc', rotulo: 'Inscrições', formato: 'int', medir: (_, l) => capLinhas(l).length, aplica: TODAS, dica: 'Cadastros de C2 e C3 (todas as portas).' }, valor: <Numero valor={lCap.length} formato="int" />, hint: `${formatar(lCap.filter((l) => l.origem === 'pago').length, 'int')} de tráfego pago` },
    { c: { id: 'conv', rotulo: 'Conversão da página', formato: 'pct', medir: (x, l) => valorTaxa(conversaoPagina(x, l, idx)), aplica: TRAFEGO, dica: 'Inscrições pagas ÷ views da página, dos mesmos anúncios.' }, valor: <Taxa taxa={conversaoPagina(d.dias, d.linhas, idx)} /> },
    { c: { id: 'grupo', rotulo: 'Grupo em 48h', formato: 'pct', medir: (_, l) => valorTaxa(ingressoGrupo(capLinhas(l), 48, d.agora)), aplica: TODAS, dica: 'Pessoas únicas com a janela de 48h já fechada.' }, valor: <Taxa taxa={ingressoGrupo(lCap, 48, d.agora)} /> },
  ];

  // ─── Faixa 4: funis lado a lado ─────────────────────────────────────────────────────────────────────────
  const diasCanal = filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: 'todos', canal: recorte.canal });
  const linhasCanal = filtrarLinhas(d.linhasPeriodoSemFiltro, { funil: 'todos', canal: recorte.canal });
  const etapas = [...cplPorEtapa(d.dias, d.linhas, idx), { chave: 'remarketing', rotulo: 'Remarketing', nivel: 'etapa' as const, funil: 'c3' as Funil, cpl: cplRemarketing(d.dias, d.linhas, idx) }];

  return (
    <div className="space-y-5">
      <section aria-labelledby="vg-placar">
        <h2 id="vg-placar" className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Placar</h2>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <KpiCard label="Até a live" value={tempoAte(config.liveEm, d.agora)} hint={`Live em ${dataHora(config.liveEm)}`} bar="purple" />
          <Cartao titulo={cardLeads.rotulo} onAbrir={abrir(cardLeads)}>
            <KpiCard label="Leads contra a meta" bar="accent" title={config.fontes.plano}
              value={<><Numero valor={leadsAteAgora} formato="int" /> <span className="text-sm font-normal text-[var(--fg-3)]">de {formatar(config.metaLeads, 'int')}</span></>}
              hint={`Pessoas únicas do início até agora. ${formatar(dividir(leadsAteAgora, config.metaLeads), 'pct')} da meta.`} />
            <div className="-mt-2 px-4 pb-3"><ProgressBar value={(leadsAteAgora / config.metaLeads) * 100} ariaLabel={`${formatar(leadsAteAgora, 'int')} de ${formatar(config.metaLeads, 'int')} leads`} valueNow={leadsAteAgora} valueMin={0} valueMax={config.metaLeads} /></div>
          </Cartao>
          <Cartao titulo={cardCpl.rotulo} onAbrir={abrir(cardCpl)}>
            <KpiCard label="CPL geral" bar={placar.valor === null ? 'gray' : placar.valor <= config.cplAlvoMedio ? 'green' : 'red'}
              value={<span className="inline-flex items-center gap-2"><Numero valor={placar.valor} formato="brl" falta="sem leads pagos no recorte" /><Farol farol={farolCpl(placar.valor, config.reguaCpl)} /></span>}
              hint={`Gasto de captação e remarketing ÷ leads que vieram de anúncio: ${moeda(placar.gasto)} ÷ ${formatar(placar.leadsPagos, 'int')}. Alvo ${moeda(config.cplAlvoMedio)}.`} />
          </Cartao>
          <Cartao titulo={cardGasto.rotulo} onAbrir={abrir(cardGasto)}>
            <KpiCard label="Verba contra o orçamento" bar="yellow"
              value={<><Numero valor={gastoAteHoje} formato="brl" /> <span className="text-sm font-normal text-[var(--fg-3)]">de {moeda(config.orcamentoTotal)}</span></>}
              hint={`Tráfego do início até hoje. ${formatar(dividir(gastoAteHoje, config.orcamentoTotal), 'pct')} do orçamento.`} />
            <div className="-mt-2 px-4 pb-3"><ProgressBar value={(gastoAteHoje / config.orcamentoTotal) * 100} tone="yellow" ariaLabel={`${moeda(gastoAteHoje)} de ${moeda(config.orcamentoTotal)}`} /></div>
          </Cartao>
        </div>
      </section>

      <section aria-labelledby="vg-invest">
        <h2 id="vg-invest" className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Investimento no período</h2>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <KpiCard label="Total" value={<Numero valor={total} formato="brl" />} hint={notaTotal} bar="accent" />
          <Cartao titulo="Tráfego" onAbrir={abrir(cardGasto)}>
            <KpiCard label="Tráfego" value={<Numero valor={d.dias.length ? gastoPeriodo : null} formato="brl" />} hint={`Meta ${moeda(porCanal('meta'))} · Google ${moeda(porCanal('google'))}`} bar="accent" />
          </Cartao>
          <Cartao titulo="Disparo" onAbrir={() => d.irPara({ aba: 'mensageria' })}>
            <KpiCard label="Disparo" bar="purple"
              value={<span className="inline-flex flex-wrap items-center gap-2"><Numero valor={custoDisparo?.valor ?? null} formato="brl" falta="custo de disparo" />{d.mensageria && <SeloFicticio />}</span>}
              hint={`API ${moeda(custoCanal('api'))} · SMS ${moeda(custoCanal('sms'))} · Ligação ${moeda(custoCanal('ligacao'))}`} />
          </Cartao>
        </div>
        <SectionCard className="mt-3" title="Por fase" subtitle={`Gasto do período contra o previsto por fase (fonte: ${config.fontes.plano ?? "sem fonte"}). Passe o mouse na barra para ver o valor.`}>
          <BarrasFase formato="brl" itens={FASES.map((f) => ({ fase: f, rotulo: ROTULO_FASE[f], valor: fases.porFase[f], previsto: config.previstoPorFase[f] }))} />
          {fases.semFase > 0 && <p className="mt-2 text-xs text-[var(--fg-3)]">Campanhas sem fase: {moeda(fases.semFase)} (fora das barras).</p>}
        </SectionCard>
      </section>

      <section aria-labelledby="vg-funil">
        <h2 id="vg-funil" className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funil macro</h2>
        <p className="mb-2 text-xs text-[var(--fg-3)]">Só C2 e C3. C1 fora (distribuição).</p>
        {recorte.funil === 'c1' ? (
          <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">O C1 é distribuição: não tem página, inscrição nem connect rate. Veja os funis lado a lado abaixo.</p>
        ) : (
          <>
            <ol className="grid auto-rows-fr grid-cols-2 gap-3 md:grid-cols-5">
              {cards3.map(({ c, valor, hint }) => (
                <li key={c.id} className="min-w-0"><Cartao cheio titulo={c.rotulo} onAbrir={abrir(c)}><KpiCard label={c.rotulo} value={valor} hint={hint} /></Cartao></li>
              ))}
            </ol>
            <div className="mt-3 grid auto-rows-fr grid-cols-2 gap-3 md:grid-cols-5">
              <Cartao cheio titulo="Presença na live"><KpiCard label="Presença na live" value={<Numero valor={d.marcos?.presencaLive ?? null} formato="int" falta="presença da live ainda sem fonte" />} bar="gray" /></Cartao>
              <Cartao cheio titulo="Vendas"><KpiCard label="Vendas" value={<Numero valor={d.marcos?.vendas ?? null} formato="int" falta="vendas ainda sem fonte" />} bar="gray" /></Cartao>
            </div>
          </>
        )}
      </section>

      <section aria-labelledby="vg-lado">
        <h2 id="vg-lado" className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funis lado a lado</h2>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {FUNIS.map((f) => {
            const df = filtrarDias(diasCanal, idx, { funil: f, canal: 'todos' });
            const lf = filtrarLinhas(linhasCanal, { funil: f, canal: 'todos' });
            const apagado = recorte.funil !== 'todos' && recorte.funil !== f;
            return (
              <SectionCard key={f} title={ROTULO_FUNIL[f]} className={apagado ? 'opacity-40' : ''}
                right={<button type="button" className="text-xs text-[var(--accent)] underline-offset-2 hover:underline" onClick={() => d.irPara({ funil: f })}>Filtrar</button>}>
                {f === 'c1' ? <ColunaC1 d={d} dias={df} /> : <ColunaCaptacao d={d} dias={df} linhas={lf} />}
              </SectionCard>
            );
          })}
        </div>

        <SectionCard className="mt-3" title="CPL por etapa" subtitle={`Fase de captação; remarketing à parte. Farol: meta ${moeda(config.reguaCpl.meta)}, teto ${moeda(config.reguaCpl.teto)}.`}>
          <ul className="divide-y divide-[var(--border-faint)]">
            <LinhaC1 dias={filtrarDias(d.dias, idx, { funil: 'c1', canal: 'todos' })} />
            {etapas.map((e) => (
              <li key={e.chave} className={'flex flex-wrap items-center gap-x-3 gap-y-0.5 py-2 text-sm ' + (e.nivel === 'etapa' ? '' : 'pl-4')}>
                <Farol farol={farolCpl(e.cpl.valor, config.reguaCpl)} />
                <span className={'min-w-0 flex-1 break-words ' + (e.nivel === 'etapa' ? 'font-semibold text-[var(--fg)]' : 'text-[var(--fg-2)]')}>{e.rotulo}</span>
                <span className="text-xs text-[var(--fg-3)]">{moeda(e.cpl.gasto)} ÷ {formatar(e.cpl.leadsPagos, 'int')}</span>
                <span className="w-24 text-right"><Numero valor={e.cpl.valor} formato="brl" animado={false} /></span>
              </li>
            ))}
          </ul>
        </SectionCard>
      </section>

      <ModalCard d={d} card={aberto} onClose={() => setAberto(null)} />
    </div>
  );
}

/** C1 não gera lead: a linha mostra o custo que se aplica a ele (CPM e custo por visualização), sem farol de CPL. */
function LinhaC1({ dias }: { dias: DesempenhoDia[] }) {
  const a = agregar(dias);
  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-0.5 py-2 text-sm">
      <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-full border border-[var(--border-strong)]" />
      <span className="min-w-0 flex-1 break-words">
        <span className="font-semibold text-[var(--fg)]">C1</span>
        <span className="ml-2 text-xs text-[var(--fg-3)]">distribuição, não gera lead: não é CPL</span>
      </span>
      <span className="text-xs text-[var(--fg-3)]">CPM <Numero valor={dias.length ? cpm(a) : null} formato="brl" animado={false} className="text-[var(--fg)]" /></span>
      <span className="text-xs text-[var(--fg-3)]" title="Custo por visualização = gasto ÷ ThruPlay">Por visualização <Numero valor={custoPorVisualizacao(a)} formato="brl" falta="ThruPlay" animado={false} className="text-sm text-[var(--fg)]" /></span>
    </li>
  );
}

function Linha({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return <div className="flex items-baseline justify-between gap-3 py-1 text-sm"><span className="text-[var(--fg-3)]">{rotulo}</span><span className="text-right text-[var(--fg)]">{children}</span></div>;
}

function ColunaC1({ d, dias }: { d: DadosTela; dias: DesempenhoDia[] }) {
  const a = agregar(dias);
  // Alcance e frequência não somam entre campanhas: só com uma campanha C1 no recorte.
  const campanhas = [...new Set(dias.map((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id).filter((x): x is string => Boolean(x)))];
  const total = campanhas.length === 1 ? d.totaisPeriodo.find((t) => t.nivel === 'campanha' && t.id === campanhas[0]) : undefined;
  const falta = campanhas.length > 1 ? 'alcance não soma entre campanhas' : 'alcance do período';
  return (
    <div className="divide-y divide-[var(--border-faint)]">
      <Linha rotulo="Gasto"><Numero valor={dias.length ? a.gasto : null} formato="brl" animado={false} /></Linha>
      <Linha rotulo="Impressões"><Numero valor={dias.length ? a.impressoes : null} formato="int" animado={false} /></Linha>
      <Linha rotulo="Alcance"><Numero valor={total?.alcance ?? null} formato="int" falta={falta} animado={false} /></Linha>
      <Linha rotulo="Frequência"><Numero valor={total?.frequencia ?? null} formato="dec" falta={falta} animado={false} /></Linha>
      <Linha rotulo="CPM"><Numero valor={dias.length ? cpm(a) : null} formato="brl" animado={false} /></Linha>
      <Linha rotulo="Vídeo 75%"><Taxa taxa={taxaVideo75(a)} /></Linha>
      <Linha rotulo="Custo por visualização"><Numero valor={custoPorVisualizacao(a)} formato="brl" falta="ThruPlay" animado={false} /></Linha>
      <p className="pt-1 text-[11px] text-[var(--fg-3)]">Distribuição: sem leads nem página.</p>
    </div>
  );
}

function ColunaCaptacao({ d, dias, linhas }: { d: DadosTela; dias: DesempenhoDia[]; linhas: LinhaPerfil[] }) {
  const c = cplDo(dias, linhas);
  return (
    <div className="divide-y divide-[var(--border-faint)]">
      <Linha rotulo="Gasto"><Numero valor={dias.length ? c.gasto : null} formato="brl" animado={false} /></Linha>
      <Linha rotulo="Cadastros"><Numero valor={linhas.length} formato="int" animado={false} /></Linha>
      <Linha rotulo="Leads pagos"><Numero valor={c.leadsPagos} formato="int" animado={false} /></Linha>
      <Linha rotulo="CPL"><span className="inline-flex items-center gap-1.5"><Numero valor={c.valor} formato="brl" animado={false} /><Farol farol={farolCpl(c.valor, d.config.reguaCpl)} /></span></Linha>
      <Linha rotulo="Conversão da página"><Taxa taxa={conversaoPagina(dias, linhas, d.idx)} /></Linha>
      <Linha rotulo="Grupo em 48h"><Taxa taxa={ingressoGrupo(linhas, 48, d.agora)} /></Linha>
    </div>
  );
}
