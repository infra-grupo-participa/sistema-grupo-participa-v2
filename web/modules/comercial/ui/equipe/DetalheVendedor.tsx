'use client';

// Detalhe do vendedor (ficha larga): funil pessoal × time, atividades por tipo e por horário, cadência, tempo em
// cada etapa, perdidos por motivo, vendas por produto/funil, carteira atual, conversas sem resposta, posição no
// time e anotações de 1:1. Cálculo todo em performance.ts; aqui só apresentação.
import Link from 'next/link';
import { useMemo, useState } from 'react';
import { AvatarInicial, Button, Card, Drawer, ProgressBar, SectionTitle, Textarea } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { ICONE_ATIVIDADE, ROTULO_ATIVIDADE } from '../../domain/catalogo';
import type { Contato } from '../../domain/types';
import { Aviso, FaixaNumeros, NotaRodape, Segmentado, Vazio } from '../comum';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import { tempoNaEtapa } from '../../domain/regras';
import {
  atividadesPorTipo, cadenciaCumprida, carteira, conversasSemResposta, CRITERIOS, DIAS_SEMANA, FAIXAS_HORA, funilPessoal, mapaCalor,
  perdidosDoVendedor, posicoesNoTime, tempoPorEtapaComparado, vendasAgrupadas, type BaseEquipe, type CriterioRanking,
  type IndicadoresVendedor, type Selo,
} from './performance';
import { infoCriterio, INFO_EQUIPE } from './textos';
import { Delta, fmtMin, fmtPct, SeloBadge } from './visuais';
import type { Intervalo } from '../inicio/metricas-painel';

export function DetalheVendedor({ vendedorId, nome, base, intervalo, periodo, linha, linhas, time, selos, contatos, onClose }: {
  vendedorId: string;
  nome: string;
  base: BaseEquipe;
  intervalo: Intervalo;
  /** Rótulo do período ("Últimos 7 dias"). */
  periodo: string;
  linha: IndicadoresVendedor;
  linhas: IndicadoresVendedor[];
  /** Ids dos vendedores que formam o time da comparação. */
  time: string[];
  selos: Selo[];
  contatos: Contato[];
  onClose: () => void;
}) {
  const nomeContato = (id: string) => contatos.find((c) => c.id === id)?.nome ?? 'Contato';
  const funil = useMemo(() => funilPessoal(base, vendedorId, intervalo, time), [base, vendedorId, intervalo, time]);
  const porTipo = useMemo(() => atividadesPorTipo(base, vendedorId, intervalo, time), [base, vendedorId, intervalo, time]);
  const calor = useMemo(() => mapaCalor(base, vendedorId, intervalo), [base, vendedorId, intervalo]);
  const cad = cadenciaCumprida(base, vendedorId, intervalo);
  const cadTime = cadenciaCumprida({ ...base, atividades: base.atividades.filter((a) => time.includes(a.donoId)) }, null, intervalo);
  const tempos = tempoPorEtapaComparado(base, vendedorId, time);
  const perdidos = perdidosDoVendedor(base, vendedorId, intervalo, time);
  const cart = carteira(base, vendedorId);
  const semResp = conversasSemResposta(base, vendedorId);
  const posicoes = posicoesNoTime(linhas, vendedorId);
  const [vendasPor, setVendasPor] = useState<'produto' | 'funil'>('produto');
  const vendas = vendasAgrupadas(base, vendedorId, intervalo, vendasPor);

  return (
    <Drawer
      onClose={onClose}
      width="max-w-5xl"
      title={nome}
      subtitle={`Performance · ${periodo} · comparado com a média do time`}
      avatar={<AvatarInicial nome={nome} />}
      badges={selos.length ? <>{selos.map((s) => <SeloBadge key={s.k} selo={s} />)}</> : undefined}
    >
      <div className="space-y-5">
        <FaixaNumeros rotulo={`Resumo de ${nome}`} itens={[
          { rotulo: 'Vendas', valor: linha.vendas, metrica: 'vendas' },
          { rotulo: 'Receita', valor: fmtBRL(linha.receita), metrica: 'receita' },
          { rotulo: 'Conversão', valor: fmtPct(linha.conversao), metrica: 'conversao' },
          { rotulo: 'Carga', valor: linha.abertos, metrica: 'abertos' },
          { rotulo: '1º contato', valor: fmtMin(linha.tempoPrimeiroContatoMin), metrica: 'tempo_primeiro_contato' },
        ]} />

        {/* Posição no time em cada critério. */}
        <section>
          <SectionTitle right={<InfoIndicador texto={INFO_EQUIPE.ranking} />}>Posição no time</SectionTitle>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {(Object.keys(CRITERIOS) as CriterioRanking[]).map((c) => (
              <Card key={c} className="px-3 py-2.5">
                <div className="flex items-center gap-0.5 text-[11px] text-[var(--fg-3)]">{CRITERIOS[c].rotulo} <InfoIndicador texto={infoCriterio(c)} /></div>
                <div className="text-sm font-semibold tabular text-[var(--fg)]">
                  {posicoes[c].posicao == null ? <span className="text-[var(--fg-3)] font-normal">sem base</span> : <>{posicoes[c].posicao}º <span className="font-normal text-[var(--fg-3)]">de {posicoes[c].de}</span></>}
                </div>
              </Card>
            ))}
          </div>
          <NotaRodape className="mt-1.5">Quem mais vende não é necessariamente o melhor vendedor: leia os quatro critérios juntos.</NotaRodape>
        </section>

        <div className="grid gap-5 lg:grid-cols-2">
          <Bloco titulo="Funil pessoal × time" info={INFO_EQUIPE.funilPessoal}>
            {!funil[0]?.chegaram ? (
              <Vazio titulo="Nenhum negócio de venda ativa no período" icone="chart" />
            ) : (
              <ul className="space-y-2.5">
                {funil.map((f) => (
                  <li key={f.etapa} className="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1">
                    <span className="truncate text-sm text-[var(--fg)]">{f.rotulo}</span>
                    <span className="text-xs tabular text-[var(--fg-2)]">
                      <span className="font-semibold text-[var(--fg)]">{f.chegaram}</span>
                      {f.passagem != null && <> · {f.passagem}% passaram</>}
                    </span>
                    <div className="col-span-2 flex items-center gap-3">
                      <div className="flex-1"><ProgressBar value={(f.chegaram / funil[0].chegaram) * 100} tone="info" height={6} ariaLabel={`${f.chegaram} chegaram em ${f.rotulo}`} /></div>
                      {f.passagem != null && <span className="w-28 text-right"><Delta valor={f.passagemTime == null ? null : f.passagem - f.passagemTime} rotulo="vs time" pp /></span>}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </Bloco>

          <Bloco titulo="Tempo parado em cada etapa" info={INFO_EQUIPE.tempoEtapa}>
            <ul className="divide-y divide-[var(--border-faint)]">
              {tempos.map((t) => {
                const acima = t.mediaMin != null && t.mediaTimeMin != null && t.mediaMin > t.mediaTimeMin * 1.5;
                return (
                  <li key={t.etapa} className="flex flex-wrap items-baseline justify-between gap-x-3 py-2 text-sm">
                    <span className="min-w-0 text-[var(--fg)]">{t.rotulo} <span className="text-xs tabular text-[var(--fg-3)]">{t.abertos} {t.abertos === 1 ? 'aberto' : 'abertos'}</span></span>
                    <span className="flex items-baseline gap-2 whitespace-nowrap">
                      <span className={`tabular ${acima ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg)]'}`}>{fmtMin(t.mediaMin)}{acima && <span className="sr-only"> (bem acima do time)</span>}</span>
                      <span className="text-[11px] tabular text-[var(--fg-3)]">time {fmtMin(t.mediaTimeMin)}</span>
                    </span>
                  </li>
                );
              })}
            </ul>
          </Bloco>

          <Bloco titulo="Atividades por tipo" info={INFO_EQUIPE.atividadesTipo}>
            <ul className="space-y-2.5">
              {porTipo.map((t) => {
                const max = Math.max(1, ...porTipo.map((x) => Math.max(x.vendedor, x.mediaTime)));
                return (
                  <li key={t.tipo} className="grid grid-cols-[110px_1fr_auto] items-center gap-3">
                    <span className="inline-flex items-center gap-1.5 text-sm text-[var(--fg-2)]"><Icon name={ICONE_ATIVIDADE[t.tipo]} size={13} className="text-[var(--fg-3)]" />{ROTULO_ATIVIDADE[t.tipo]}</span>
                    <div className="space-y-1">
                      <ProgressBar value={(t.vendedor / max) * 100} tone="info" height={6} ariaLabel={`${nome}: ${t.vendedor}`} />
                      <ProgressBar value={(t.mediaTime / max) * 100} tone="neutral" height={4} ariaLabel={`Média do time: ${t.mediaTime}`} />
                    </div>
                    <span className="text-xs tabular text-[var(--fg-2)] text-right"><span className="font-semibold text-[var(--fg)]">{t.vendedor}</span> · time {t.mediaTime.toLocaleString('pt-BR')}</span>
                  </li>
                );
              })}
            </ul>
            <NotaRodape className="mt-2">Barra cheia: o vendedor. Barra fina: média por vendedor do time.</NotaRodape>
          </Bloco>

          <Bloco titulo="Quando trabalha" info={INFO_EQUIPE.mapaCalor}>
            {calor.total === 0 ? (
              <Vazio titulo="Nenhuma atividade concluída no período" icone="clock" />
            ) : (
              <div role="table" aria-label={`Atividades concluídas por dia e horário: ${calor.total}`} className="grid grid-cols-[36px_repeat(7,minmax(0,1fr))] gap-1 text-[10px]">
                <div role="row" className="contents">
                  <span role="columnheader" />
                  {FAIXAS_HORA.map((f) => <span key={f.rotulo} role="columnheader" className="truncate text-center text-[var(--fg-3)]">{f.rotulo}</span>)}
                </div>
                {DIAS_SEMANA.map((d, i) => (
                  <div key={d} role="row" className="contents">
                    <span role="rowheader" className="self-center text-[var(--fg-3)]">{d}</span>
                    {calor.celulas[i].map((v, j) => (
                      <span
                        key={j}
                        role="cell"
                        title={`${d}, ${FAIXAS_HORA[j].rotulo}: ${v}`}
                        className="relative grid h-6 place-items-center overflow-hidden rounded-[var(--r-sm)] border border-[var(--border-faint)] tabular text-[var(--fg-2)]"
                      >
                        {v > 0 && <span aria-hidden className="absolute inset-0" style={{ background: 'var(--info)', opacity: 0.15 + 0.6 * (v / Math.max(1, calor.max)) }} />}
                        <span className="relative">{v || ''}</span>
                        <span className="sr-only">{v}</span>
                      </span>
                    ))}
                  </div>
                ))}
              </div>
            )}
          </Bloco>

          <Bloco titulo="Cadência cumprida" info={INFO_EQUIPE.cadencia}>
            {cad.previstos === 0 ? (
              <Vazio titulo="Nenhum toque de cadência venceu no período" icone="list-checks" />
            ) : (
              <div className="space-y-3">
                <div className="flex items-baseline justify-between gap-3">
                  <span className={`text-lg font-semibold tabular ${cad.pct != null && cad.pct < 100 ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>{fmtPct(cad.pct)}</span>
                  <Delta valor={cad.pct == null || cadTime.pct == null ? null : cad.pct - cadTime.pct} rotulo="vs time" pp />
                </div>
                <ProgressBar value={cad.pct ?? 0} tone="info" height={6} ariaLabel={`${cad.noPrazo} de ${cad.previstos} toques no prazo`} />
                <ul className="grid grid-cols-3 gap-2 text-xs">
                  <li><span className="block text-[var(--fg-3)]">No prazo</span><span className="font-semibold tabular text-[var(--fg)]">{cad.noPrazo}</span></li>
                  <li><span className="block text-[var(--fg-3)]">Com atraso</span><span className="font-semibold tabular text-[var(--fg)]">{cad.comAtraso}</span></li>
                  <li><span className="block text-[var(--fg-3)]">Pendentes</span><span className={`font-semibold tabular ${cad.pendentes ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>{cad.pendentes}</span></li>
                </ul>
              </div>
            )}
          </Bloco>

          <Bloco titulo="Perdidos por motivo" info={INFO_EQUIPE.perdidosMotivo}>
            {perdidos.length === 0 ? (
              <Vazio titulo="Nenhum perdido no período" icone="chart" />
            ) : (
              <ul className="space-y-2.5">
                {perdidos.map((p) => (
                  <li key={p.motivo} className="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1">
                    <span className="truncate text-sm text-[var(--fg-2)]">{p.rotulo}{p.falha && <span className="text-[var(--fg-3)]"> · falha de processo</span>}</span>
                    <span className="text-xs tabular text-[var(--fg-2)]"><span className="font-semibold text-[var(--fg)]">{p.quantidade}</span> · {p.pct}% <span className="text-[var(--fg-3)]">(time {p.pctTime}%)</span></span>
                    <div className="col-span-2"><ProgressBar value={p.pct} tone={p.falha ? 'red' : 'neutral'} height={4} ariaLabel={`${p.pct}% dos perdidos por ${p.rotulo}`} /></div>
                  </li>
                ))}
              </ul>
            )}
          </Bloco>

          <Bloco
            titulo="Vendas"
            info={INFO_EQUIPE.vendasPor}
            direita={<Segmentado rotulo="Agrupar vendas" valor={vendasPor} onChange={setVendasPor} opcoes={[{ valor: 'produto', rotulo: 'Por produto' }, { valor: 'funil', rotulo: 'Por funil' }]} />}
          >
            {vendas.length === 0 ? (
              <Vazio titulo="Nenhuma venda no período" hint="Venda conta quando a Hotmart aprova o pagamento." icone="wallet" />
            ) : (
              <ul className="divide-y divide-[var(--border-faint)]">
                {vendas.map((v) => (
                  <li key={v.chave} className="flex items-baseline justify-between gap-3 py-2">
                    <span className="min-w-0 truncate text-sm text-[var(--fg)]">{v.rotulo}</span>
                    <span className="flex items-baseline gap-3 whitespace-nowrap tabular">
                      <span className="text-xs text-[var(--fg-3)]">{v.quantidade} {v.quantidade === 1 ? 'venda' : 'vendas'}</span>
                      <span className="text-sm font-semibold text-[var(--fg)]">{fmtBRL(v.valor)}</span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Bloco>

          <Bloco titulo="Carteira atual" info={INFO_EQUIPE.carteira}>
            <ul className="divide-y divide-[var(--border-faint)]">
              {cart.linhas.map((c) => (
                <li key={c.etapa} className="flex flex-wrap items-baseline justify-between gap-x-3 py-2 text-sm">
                  <span className="min-w-0 text-[var(--fg)]">{c.rotulo} <span className="text-xs tabular text-[var(--fg-3)]">{fmtBRL(c.valor)}</span></span>
                  <span className="flex items-baseline gap-2 whitespace-nowrap text-xs tabular">
                    <span className="font-semibold text-[var(--fg)]">{c.abertos}</span>
                    {c.atencao > 0 && <span className="text-[var(--yellow)]">{c.atencao} atenção</span>}
                    {c.criticos > 0 && <span className="font-semibold text-[var(--red)]">{c.criticos} crítico{c.criticos > 1 ? 's' : ''}</span>}
                  </span>
                </li>
              ))}
            </ul>
            {cart.criticos.length > 0 && (
              <div className="mt-3">
                <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Em prazo crítico</p>
                <ul className="mt-1 space-y-1">
                  {cart.criticos.slice(0, 6).map((n) => (
                    <li key={n.id} className="flex items-baseline justify-between gap-3 text-sm">
                      <Link href={`/comercial/funil?negocio=${encodeURIComponent(n.id)}`} className="min-w-0 truncate text-[var(--fg)] hover:underline focus-visible:underline">
                        {nomeContato(n.contatoId)} <span className="text-xs text-[var(--fg-3)]">· {n.etapaNome || n.etapa}</span>
                      </Link>
                      <span className="whitespace-nowrap text-xs tabular text-[var(--red)]">há {tempoNaEtapa(n.etapaDesde, base.agora)}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </Bloco>

          <Bloco titulo="Conversas sem resposta" info={INFO_EQUIPE.semResposta}>
            {semResp.length === 0 ? (
              <Vazio titulo="Nenhum lead esperando resposta" icone="message" />
            ) : (
              <ul className="divide-y divide-[var(--border-faint)]">
                {semResp.slice(0, 8).map((c) => (
                  <li key={c.contatoId} className="py-2">
                    <div className="flex items-baseline justify-between gap-3">
                      <Link href={`/comercial/conversas?contato=${encodeURIComponent(c.contatoId)}`} className="min-w-0 truncate text-sm text-[var(--fg)] hover:underline focus-visible:underline">
                        {nomeContato(c.contatoId)}
                      </Link>
                      <span className={`whitespace-nowrap text-xs tabular ${c.esperaMin > 60 ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>espera {fmtMin(c.esperaMin)}</span>
                    </div>
                    <p className="truncate text-xs text-[var(--fg-3)]">{c.texto}</p>
                  </li>
                ))}
              </ul>
            )}
          </Bloco>

          <AnotacoesUmAUm nome={nome} />
        </div>
      </div>
    </Drawer>
  );
}

/** Bloco com título + (i) + conteúdo em cartão. */
function Bloco({ titulo, info, direita, children }: { titulo: string; info: TextoIndicador; direita?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="min-w-0">
      <SectionTitle right={direita}>
        <span className="inline-flex items-center gap-1">{titulo} <InfoIndicador texto={info} className="font-normal" /></span>
      </SectionTitle>
      <Card className="p-4">{children}</Card>
    </section>
  );
}

/** Anotações de 1:1: só nesta tela por enquanto (gravar entra com o backend). */
function AnotacoesUmAUm({ nome }: { nome: string }) {
  const [texto, setTexto] = useState('');
  const [notas, setNotas] = useState<{ em: string; texto: string }[]>([]);
  const salvar = () => {
    const t = texto.trim();
    if (!t) return;
    setNotas((n) => [{ em: new Date().toISOString(), texto: t }, ...n]);
    setTexto('');
  };
  return (
    <Bloco titulo="Anotações de 1:1" info={INFO_EQUIPE.umAUm}>
      <Aviso tom="info" icone="notebook" className="mb-3">Ficam só nesta tela por enquanto: gravar e ver o histórico entra com o backend.</Aviso>
      <label className="block">
        <span className="sr-only">Anotação do 1:1 com {nome}</span>
        <Textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} placeholder={`O que ficou combinado com ${nome.split(' ')[0]}?`} />
      </label>
      <div className="mt-2 flex justify-end">
        <Button size="sm" variant="primary" onClick={salvar} disabled={!texto.trim()}>Adicionar anotação</Button>
      </div>
      {notas.length > 0 && (
        <ul className="mt-3 space-y-2">
          {notas.map((n) => (
            <li key={n.em} className="rounded-[var(--r-md)] border border-[var(--border-faint)] bg-[var(--surface-2)] px-3 py-2">
              <span className="block text-[11px] tabular text-[var(--fg-3)]">{new Date(n.em).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}</span>
              <span className="block whitespace-pre-wrap text-sm text-[var(--fg-2)]">{n.texto}</span>
            </li>
          ))}
        </ul>
      )}
    </Bloco>
  );
}
