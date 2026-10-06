// Marketing > Web: os painéis da fase 2 (migration 20261005q): Fluxo, Melhorias (achados, testes A/B), laboratório do
// Google (na aba Velocidade), leads na base de pessoas (na Visão geral) e connect rate (na aba Origem). Só desenham o
// que recebem; o mapa de calor (canvas) e o Comparar (escolhas) ficam em MapaCalor.tsx e Comparar.tsx.
import Link from 'next/link';
import { Badge, DataTable, EmptyState, KpiCard, ProgressBar, SectionCard, Td, Th, Thead, Tr, type Tone } from '@/shared/ui/components';
import { codigoCurto, faixaVital, msVital, num, pct, ROTULO_NIVEL, taxa, type Nivel } from '../domain/analise';
import { analisar, NOME_TIPO, textoGanho, type AbaWeb, type Achado } from '../domain/achados';
import { destinosPorOrigem, rotuloCaminho, textoCaminho } from '../domain/fluxo';
import { gruposAB, lerAB, ROTULO_VEREDITO, EFEITO_PADRAO } from '../domain/testes-ab';
import { diaCurto } from '../domain/periodo';
import type { Connect, Fluxo, Lab, LeadsPessoas, Melhorias } from '../domain/tipos';
import { SEM_DADOS } from './paineis';

const SEM_DADOS_DICA = 'O gravador ainda não está nas páginas deste projeto. O passo a passo da virada está em docs/central-de-dados.md (seção Web).';
const Vazio = ({ titulo = SEM_DADOS, dica = SEM_DADOS_DICA }: { titulo?: string; dica?: string }) => <EmptyState title={titulo} hint={dica} icon="globe" />;

export const TOM_NIVEL: Record<Nivel, Tone> = { forte: 'success', provavel: 'warning', fraco: 'neutral' };

function Barra({ fracao, rotulo, tone = 'accent' }: { fracao: number; rotulo: string; tone?: 'accent' | 'green' | 'yellow' | 'red' | 'info' }) {
  return (
    <div className="flex items-center gap-2 min-w-[140px]">
      <div className="flex-1"><ProgressBar value={Math.max(0, Math.min(100, fracao * 100))} tone={tone} ariaLabel={rotulo} /></div>
      <span className="text-xs tabular text-[var(--fg-2)] w-14 text-right">{rotulo}</span>
    </div>
  );
}

// ─── Fluxo ───────────────────────────────────────────────────────────────────────────────────────────────────────────
export function PainelFluxo({ f }: { f: Fluxo }) {
  if (!f.sessoes) return <SectionCard><Vazio /></SectionCard>;
  const origens = destinosPorOrigem(f);
  return (
    <div className="space-y-4">
      <div className="grid gap-3 grid-cols-2 lg:grid-cols-3">
        <KpiCard label="Visitas" value={num(f.sessoes)} />
        <KpiCard label="Viram uma página só" value={pct(f.uma_pagina, f.sessoes)} hint={`${num(f.uma_pagina)} visitas`} bar="yellow" />
        <KpiCard label="Páginas por visita" value={Number(f.passos_medio).toLocaleString('pt-BR')} hint="recarregar a mesma página não conta" bar="gray" />
      </div>
      <SectionCard title="Entradas e saídas por página" subtitle="Vistas = visitas que passaram pela página. Saída = a última página da visita.">
        <DataTable minWidth={720}>
          <Thead><Th>Página</Th><Th>Vistas</Th><Th>Entradas</Th><Th>Saídas</Th><Th>Saem por aqui</Th><Th>Visitas com lead</Th></Thead>
          <tbody>{f.paginas.map((p) => (
            <Tr key={p.caminho}>
              <Td><span className="text-sm">{rotuloCaminho(p.caminho, f.nomes)}</span></Td>
              <Td>{num(p.vistas)}</Td><Td>{num(p.entradas)}</Td><Td>{num(p.saidas)}</Td>
              <Td><Barra fracao={taxa(p.saidas, p.vistas)} rotulo={pct(p.saidas, p.vistas, 0)} tone="red" /></Td>
              <Td>{pct(p.leads, p.vistas)}</Td>
            </Tr>
          ))}</tbody>
        </DataTable>
      </SectionCard>
      <SectionCard title="De onde para onde" subtitle="De cada página, para onde a visita foi em seguida (ou se saiu do site).">
        <div className="grid gap-4 md:grid-cols-2">
          {origens.map((o) => (
            <div key={o.de} className="rounded-[var(--r-md)] border border-[var(--border)] p-3">
              <div className="mb-2 text-sm font-medium">{rotuloCaminho(o.de, f.nomes)} <span className="text-[var(--fg-3)] tabular">({num(o.total)})</span></div>
              <div className="space-y-1">{o.destinos.map((d) => (
                <div key={d.para} className="flex items-center gap-2 text-xs">
                  <span className="w-40 truncate" title={d.para}>→ {rotuloCaminho(d.para, f.nomes)}</span>
                  <Barra fracao={d.fatia} rotulo={pct(d.n, o.total, 0)} tone={d.para === '(saiu)' ? 'red' : 'accent'} />
                </div>
              ))}</div>
            </div>
          ))}
        </div>
      </SectionCard>
      <SectionCard title="Caminhos mais comuns" subtitle="A visita inteira, até 5 páginas.">
        <DataTable minWidth={560}>
          <Thead><Th>Caminho</Th><Th>Visitas</Th><Th>Lead</Th></Thead>
          <tbody>{f.caminhos.map((c) => (
            <Tr key={c.passos.join('>') + c.mais}><Td><span className="text-sm">{textoCaminho(c.passos, c.mais, f.nomes)}</span></Td><Td>{num(c.n)}</Td><Td>{pct(c.leads, c.n)}</Td></Tr>
          ))}</tbody>
        </DataTable>
      </SectionCard>
    </div>
  );
}

// ─── Melhorias: achados e testes A/B ─────────────────────────────────────────────────────────────────────────────────
const ROTULO_ABA: Record<AbaWeb, string> = {
  paginas: 'Páginas', origem: 'Origem e UTMs', velocidade: 'Velocidade', leitura: 'Rolagem e leitura', problemas: 'Cliques e erros',
  formulario: 'Formulário', calor: 'Mapa de calor',
};

function CartaoAchado({ a, nomePagina }: { a: Achado; nomePagina?: string }) {
  const ganho = textoGanho(a.ganho);
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] p-3 space-y-1.5">
      <div className="flex flex-wrap items-center gap-2 text-xs">
        <Badge tone={TOM_NIVEL[a.confianca]}>{ROTULO_NIVEL[a.confianca]}</Badge>
        <span className="text-[var(--fg-3)]">{NOME_TIPO[a.tipo]}{nomePagina ? ` · ${nomePagina}` : ''}</span>
        {ganho && <span className="ml-auto text-[var(--fg-2)]" title={`Teto de leads por semana se o problema for consertado (${a.base ?? ''})`}>{ganho} leads/semana</span>}
      </div>
      <div className="text-sm font-medium text-[var(--fg)]">{a.titulo}</div>
      <div className="text-xs text-[var(--fg-2)]">{a.numeros}</div>
      <div className="text-xs"><b>O que fazer:</b> {a.fazer}</div>
      {a.dica && <div className="text-[11px] text-[var(--fg-3)]">{a.dica}</div>}
      <div className="text-[11px] text-[var(--fg-3)]">Conferir em: {a.ver.map((v) => ROTULO_ABA[v]).join(' · ')}</div>
    </div>
  );
}

export function PainelAchados({ m }: { m: Melhorias }) {
  if (!m.atual.sessoes) return <SectionCard><Vazio /></SectionCard>;
  const periodo = `de ${diaCurto(m.de)} a ${diaCurto(m.ate)}`;
  const r = analisar(m.atual, m.antes, periodo);
  const nome = (id: number) => m.atual.paginas.find((p) => p.pagina_id === id)?.nome;
  return (
    <div className="space-y-4">
      <SectionCard title="Achados automáticos" subtitle={`As regras do Radar (oportunidades.ts do Luiz), sobre ${r.paginas} página(s) com 20 visitas ou mais, ${periodo}; rejeição comparada com ${diaCurto(m.antes_de)} a ${diaCurto(m.antes_ate)}. Os de selo "pode ser acaso" ficam no fim.`}>
        {!r.oportunidades.length ? <p className="text-sm text-[var(--fg-3)]">Nenhum achado com os números do período (as regras pedem amostra mínima: 30 entradas de cada lado, em geral).</p> : (
          <div className="space-y-3">{r.oportunidades.map((a) => <CartaoAchado key={a.id} a={a} nomePagina={nome(a.pagina_id)} />)}</div>
        )}
      </SectionCard>
      {r.aprendizados.length > 0 && (
        <SectionCard title="Aprendizados" subtitle="O que os números ensinam sobre quem converte (sem ganho estimado).">
          <div className="space-y-3">{r.aprendizados.map((a) => <CartaoAchado key={a.id} a={a} nomePagina={nome(a.pagina_id)} />)}</div>
        </SectionCard>
      )}
    </div>
  );
}

export function PainelTestesAB({ m, hoje }: { m: Melhorias; hoje?: string }) {
  const grupos = gruposAB(m.atual.paginas);
  if (!m.atual.sessoes) return <SectionCard><Vazio /></SectionCard>;
  if (!grupos.length) {
    return (
      <SectionCard>
        <EmptyState title="Nenhum teste A/B no período." icon="globe"
          hint="O teste aparece sozinho quando a página original (ex.: ak1) e uma variação (ak1-b, ak1-c) têm o código da casa em Marketing > Projetos e páginas e receberam visitas." />
      </SectionCard>
    );
  }
  return (
    <div className="space-y-4">
      {grupos.map((g) => (
        <SectionCard key={g.base} title={`Teste ${g.base.toUpperCase()}`}
          subtitle={`Original: ${g.a.nome} (${g.a.caminho}). Conta quem ENTROU por cada versão. Veredito só com a amostra para enxergar ${Math.round(EFEITO_PADRAO * 100)}% de diferença e 7 dias de dado (regra do Radar).`}>
          <DataTable minWidth={900}>
            <Thead><Th>Versão</Th><Th>Entradas</Th><Th>Leads</Th><Th>Taxa</Th><Th>MQL</Th><Th>Diferença</Th><Th>Amostra</Th><Th>Veredito</Th></Thead>
            <tbody>
              <Tr><Td><b>{g.a.nome}</b> <span className="font-mono text-xs">({g.a.codigo})</span></Td><Td>{num(g.a.entradas)}</Td><Td>{num(g.a.leads_entrada)}</Td>
                <Td>{pct(g.a.leads_entrada, g.a.entradas)}</Td><Td>{pct(g.a.mql_entrada, g.a.entradas)}</Td><Td>–</Td><Td>–</Td><Td>original</Td></Tr>
              {g.variacoes.map((v) => {
                const l = lerAB(g.a, v, 'lead', EFEITO_PADRAO, hoje);
                return (
                  <Tr key={v.pagina_id}>
                    <Td><b>{v.nome}</b> <span className="font-mono text-xs">({v.codigo})</span>
                      {l.divisao.desigual && <div className="text-[11px] text-[var(--yellow)]">Divisão desigual: {pct(l.divisao.parteA, 1, 0)} das entradas na original</div>}</Td>
                    <Td>{num(v.entradas)}</Td><Td>{num(v.leads_entrada)}</Td><Td>{pct(v.leads_entrada, v.entradas)}</Td><Td>{pct(v.mql_entrada, v.entradas)}</Td>
                    <Td>{(l.comparacao.relativa >= 0 ? '+' : '') + (l.comparacao.relativa * 100).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}%{' '}
                      <Badge tone={TOM_NIVEL[l.comparacao.nivel]}>{ROTULO_NIVEL[l.comparacao.nivel]}</Badge></Td>
                    <Td>{l.amostra ? `${num(l.menor)} de ${num(l.amostra)}` : 'faltam 50 entradas na original'}
                      {l.diasFaltam != null && l.diasFaltam > 0 && <div className="text-[11px] text-[var(--fg-3)]">uns {l.diasFaltam} dias no ritmo atual</div>}</Td>
                    <Td><Badge tone={l.veredito === 'aguardando' ? 'neutral' : l.veredito === 'sem_diferenca' ? 'warning' : 'success'}>{ROTULO_VEREDITO[l.veredito]}</Badge>
                      <div className="text-[11px] text-[var(--fg-3)]">{l.dias} dia(s) com dado</div></Td>
                  </Tr>
                );
              })}
            </tbody>
          </DataTable>
        </SectionCard>
      ))}
    </div>
  );
}

// ─── Velocidade: o laboratório do Google ─────────────────────────────────────────────────────────────────────────────
const tomNota = (n: number | null): Tone => (n == null ? 'neutral' : n >= 90 ? 'success' : n >= 50 ? 'warning' : 'danger');

export function SecaoLab({ lab }: { lab: Lab | null }) {
  if (!lab) return null;
  const comTeste = lab.paginas.filter((p) => p.ultimo);
  return (
    <SectionCard title="Teste do Google (laboratório)"
      subtitle="PageSpeed Insights, 1 vez por dia, das páginas ativas com a coleta ligada. Laboratório = uma máquina do Google simulando um celular ou computador; a velocidade real das visitas está acima.">
      {!lab.ligado && <p className="mb-2 text-sm text-[var(--yellow)]">A rotina do Google está desligada (mkt_web.config: pagespeed).</p>}
      {!comTeste.length ? (
        <p className="text-sm text-[var(--fg-3)]">{lab.coleta ? 'Nenhum teste ainda: a rotina roda às 06:40.' : 'Nenhum teste: a rotina só mede projeto com a coleta ligada (começa na virada).'}</p>
      ) : (
        <DataTable minWidth={900}>
          <Thead><Th>Página</Th><Th>Aparelho</Th><Th>Nota</Th><Th>LCP</Th><Th>TBT</Th><Th>CLS</Th><Th>O que mais pesa</Th><Th>Quando</Th></Thead>
          <tbody>{comTeste.map((p) => {
            const u = p.ultimo!;
            const delta = u.nota != null && p.anterior_nota != null ? u.nota - p.anterior_nota : null;
            return (
              <Tr key={p.pagina_id + p.estrategia}>
                <Td><span className="text-sm">{p.nome}</span> <span className="font-mono text-xs text-[var(--fg-3)]">{p.caminho}</span></Td>
                <Td>{p.estrategia === 'mobile' ? 'Celular' : 'Computador'}</Td>
                <Td>{u.erro ? <span className="text-xs text-[var(--red)]">falhou ({u.erro})</span> : <><Badge tone={tomNota(u.nota)}>{u.nota ?? '–'}</Badge>
                  {delta != null && delta !== 0 && <span className="ml-1 text-[11px] text-[var(--fg-3)]">{delta > 0 ? '+' : ''}{delta}</span>}</>}</Td>
                <Td><span className={faixaVital('lcp', u.lcp_ms) === 'ruim' ? 'text-[var(--red)]' : ''}>{msVital(u.lcp_ms)}</span></Td>
                <Td>{msVital(u.tbt_ms)}</Td>
                <Td>{u.cls == null ? '–' : Number(u.cls).toLocaleString('pt-BR', { maximumFractionDigits: 3 })}</Td>
                <Td><span className="text-xs">{u.oportunidades[0] ? `${u.oportunidades[0].titulo} (${msVital(u.oportunidades[0].ms)})` : '–'}</span></Td>
                <Td><span className="text-xs">{new Date(u.medido_em).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}</span></Td>
              </Tr>
            );
          })}</tbody>
        </DataTable>
      )}
    </SectionCard>
  );
}

// ─── Visão geral: lead ligado à pessoa ───────────────────────────────────────────────────────────────────────────────
export function SecaoLeads({ l }: { l: LeadsPessoas | null }) {
  if (!l) return null;
  return (
    <SectionCard title="Leads na base de pessoas"
      subtitle="A Web não guarda dado pessoal: o navegador do lead recebe só a referência opaca da base única de pessoas (Comercial).">
      {!l.leads_web ? <p className="text-sm text-[var(--fg-3)]">{SEM_DADOS}</p> : (
        <div className="space-y-3">
          <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
            <KpiCard label="Leads da Web" value={num(l.leads_web)} hint={`${num(l.navegadores_lead)} navegadores`} bar="purple" />
            <KpiCard label="Ligados a uma pessoa" value={pct(l.com_ref, l.navegadores_lead)} hint={`${num(l.com_ref)} navegadores com a referência`} bar="accent" />
            <KpiCard label="Viraram MQL" value={l.base && l.mql != null ? num(l.mql) : '–'} hint={l.base && l.pessoas ? `${pct(l.mql ?? 0, l.pessoas)} das ${num(l.pessoas)} pessoas` : 'pela base de pessoas'} bar="green" />
            <KpiCard label="Não MQL" value={l.base && l.nao_mql != null ? num(l.nao_mql) : '–'} bar="gray" />
          </div>
          {!l.base && <p className="text-xs text-[var(--fg-3)]">A base de pessoas (migration 20261005o) ainda não está aplicada: MQL e fichas aparecem depois.</p>}
          {l.base && l.pode_abrir && l.lista.length > 0 && (
            <details className="text-sm">
              <summary className="cursor-pointer text-[var(--fg-2)]">Últimos leads do período ({l.lista.length}): abrir a ficha no Comercial</summary>
              <DataTable minWidth={520}>
                <Thead><Th>Referência</Th><Th>Resultado</Th><Th>Ficha</Th></Thead>
                <tbody>{l.lista.map((p) => (
                  <Tr key={p.ref}>
                    <Td><span className="font-mono text-xs">{p.ref.slice(0, 11)}…</span></Td>
                    <Td>{p.mql ? <Badge tone="success">MQL</Badge> : p.nao_mql ? <Badge tone="neutral">Não MQL</Badge> : '–'}</Td>
                    <Td><Link href={`/comercial?pessoa=${encodeURIComponent(p.pessoa_id)}`} className="text-xs font-semibold text-[var(--accent)] hover:underline">Abrir ficha</Link></Td>
                  </Tr>
                ))}</tbody>
              </DataTable>
            </details>
          )}
        </div>
      )}
    </SectionCard>
  );
}

// ─── Origem: connect rate com o Tráfego ──────────────────────────────────────────────────────────────────────────────
const brl = (v: number | null) => (v == null ? '–' : Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }));
const pctN = (v: number | null) => (v == null ? '–' : (v * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + '%');

export function SecaoConnect({ c }: { c: Connect | null }) {
  if (!c) return null;
  return (
    <SectionCard title="Connect rate (com o Tráfego)"
      subtitle="Connect rate = page views ÷ cliques no link da plataforma. Conversão da página = leads ÷ page views. Page view = a entrada na página vinda da campanha (uma por visita).">
      {!c.trafego ? (
        <p className="text-sm text-[var(--fg-3)]">O cruzamento com gasto e cliques aparece quando a base do Tráfego (migration 20261005p) estiver aplicada e coletando.</p>
      ) : !c.campanhas.length ? (
        <p className="text-sm text-[var(--fg-3)]">Nenhuma campanha do projeto com gasto ou visita no período.</p>
      ) : (
        <>
          {!c.cliques_link && <p className="mb-2 text-xs text-[var(--yellow)]">O Tráfego ainda não guarda cliques no link: connect rate fica em branco (não usa o total de cliques).</p>}
          <DataTable minWidth={980}>
            <Thead><Th>Campanha</Th><Th>Página</Th><Th>Gasto</Th><Th>Cliques no link</Th><Th>Page views</Th><Th>Connect rate</Th><Th>Leads</Th><Th>Conversão</Th></Thead>
            <tbody>{c.campanhas.map((x) => (
              <Tr key={x.plataforma + x.campanha_externa}>
                <Td><span className="font-mono text-xs break-all">{x.campanha}</span></Td>
                <Td>{x.pagina ? <span className="font-mono">{x.pagina}</span> : '–'}</Td>
                <Td>{brl(x.gasto)}</Td><Td>{x.cliques_link == null ? '–' : num(x.cliques_link)}</Td><Td>{num(x.page_views)}</Td>
                <Td><b>{pctN(x.connect_rate)}</b></Td><Td>{num(x.leads)}</Td><Td>{pctN(x.conversao)}</Td>
              </Tr>
            ))}</tbody>
          </DataTable>
        </>
      )}
      {c.sem_campanha && c.sem_campanha.page_views > 0 && (
        <p className="mt-2 text-xs text-[var(--fg-3)]">{num(c.sem_campanha.page_views)} page views de {num(c.sem_campanha.campanhas)} utm_campaign que não casam com campanha cadastrada no Tráfego.</p>
      )}
      {c.anuncios.length > 0 && (
        <details className="mt-3 text-sm">
          <summary className="cursor-pointer text-[var(--fg-2)]">Por anúncio (utm_content): só a Web, o Tráfego ainda não guarda clique por anúncio</summary>
          <DataTable minWidth={600}>
            <Thead><Th>Anúncio</Th><Th>Page views</Th><Th>Leads</Th><Th>Conversão</Th></Thead>
            <tbody>{c.anuncios.map((a) => (
              <Tr key={a.anuncio}><Td><span className="font-mono text-xs" title={a.anuncio}>{codigoCurto(a.anuncio)}</span></Td><Td>{num(a.page_views)}</Td><Td>{num(a.leads)}</Td><Td>{pct(a.leads, a.page_views)}</Td></Tr>
            ))}</tbody>
          </DataTable>
        </details>
      )}
    </SectionCard>
  );
}
