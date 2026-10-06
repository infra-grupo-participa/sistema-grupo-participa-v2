// Marketing > Web: os painéis de cada aba. Só desenham o que recebem (sem estado, sem busca): WebClient.tsx carrega.
import {
  Badge, CopyField, DataTable, EmptyState, KpiCard, ProgressBar, SectionCard, Td, Th, Thead, Tr, type Tone,
} from '@/shared/ui/components';
import {
  apelidoSecao, codigoCurto, compararTaxas, duracao, faixaVital, maiorPerda, msVital, nomeOrigem, num, pct, ROTULO_FAIXA, ROTULO_NIVEL,
  taxa, type Faixa, type Vital,
} from '../domain/analise';
import { diaCurto } from '../domain/periodo';
import { linhaDoGravador } from '../domain/coleta';
import {
  APARELHO, MOTIVO_RECUSA, NOME_ERRO_FORA,
  type Formulario, type Funil, type Instalacao, type Leitura, type LinhaPagina, type Origem, type Problemas, type Velocidade, type Visao,
} from '../domain/tipos';

export const SEM_DADOS = 'Sem dados ainda: a coleta começa na virada.';
const SEM_DADOS_DICA = 'O gravador ainda não está nas páginas deste projeto. O passo a passo da virada está em docs/central-de-dados.md (seção Web).';

/** barra horizontal simples (fração de 0 a 1) com rótulo à direita */
function Barra({ fracao, rotulo, tone = 'accent' }: { fracao: number; rotulo: string; tone?: 'accent' | 'green' | 'yellow' | 'red' | 'info' }) {
  return (
    <div className="flex items-center gap-2 min-w-[140px]">
      <div className="flex-1"><ProgressBar value={Math.max(0, Math.min(100, fracao * 100))} tone={tone} ariaLabel={rotulo} /></div>
      <span className="text-xs tabular text-[var(--fg-2)] w-14 text-right">{rotulo}</span>
    </div>
  );
}

const TOM_FAIXA: Record<Faixa, Tone> = { bom: 'success', melhorar: 'warning', ruim: 'danger' };
function SeloVital({ v, valor }: { v: Vital; valor: number | null }) {
  const f = faixaVital(v, valor);
  const texto = v === 'cls' ? (valor == null ? '–' : valor.toLocaleString('pt-BR', { maximumFractionDigits: 3 })) : msVital(valor);
  if (!f) return <span className="text-[var(--fg-3)]">{texto}</span>;
  return <span title={ROTULO_FAIXA[f]}><Badge tone={TOM_FAIXA[f]}>{texto}</Badge></span>;
}

function Vazio({ titulo = SEM_DADOS, dica = SEM_DADOS_DICA }: { titulo?: string; dica?: string }) {
  return <EmptyState title={titulo} hint={dica} icon="globe" />;
}

// ─── Visão geral ─────────────────────────────────────────────────────────────────────────────────────────────────────
export function PainelVisao({ v }: { v: Visao }) {
  const k = v.kpis;
  if (!k.sessoes) {
    return (
      <SectionCard>
        <Vazio dica={v.coleta.ligada ? 'A coleta deste projeto está ligada, mas nenhuma visita chegou no período.' : SEM_DADOS_DICA} />
      </SectionCard>
    );
  }
  const maior = Math.max(1, ...v.serie.map((d) => d.sessoes));
  return (
    <div className="space-y-4">
      <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Visitas" value={num(k.sessoes)} hint={`${num(k.visitantes)} navegadores diferentes`} title="Sessões no período, sem visitas de teste" />
        <KpiCard label="Engajaram" value={pct(k.engajadas, k.sessoes)} hint={`Rejeição ${pct(k.sessoes - k.engajadas, k.sessoes)}`} bar="green"
          title="Ficou 10 s com a página na tela, ou clicou, ou disparou evento, ou abriu outra página" />
        <KpiCard label="Leads" value={num(k.leads)} hint={`Taxa ${pct(k.leads, k.sessoes)} das visitas`} bar="purple" title="Visitas que dispararam um evento de lead do contrato do funil" />
        <KpiCard label="Tempo na tela" value={duracao(k.visivel_ms_medio)} hint={`${k.paginas_por_sessao.toLocaleString('pt-BR')} páginas por visita`} bar="gray" />
        <KpiCard label="De anúncio" value={pct(k.de_anuncio, k.sessoes)} hint="com UTM, fbclid ou gclid" bar="gray" />
        <KpiCard label="Com clique de raiva" value={pct(k.com_raiva, k.sessoes)} hint={`${num(k.com_raiva)} visitas`} bar="yellow" />
        <KpiCard label="Com erro da página" value={pct(k.com_erro, k.sessoes)} hint={`${num(k.com_erro)} visitas`} bar="red" />
        <KpiCard label="Resultados" value={Object.keys(k.resultados).length ? Object.entries(k.resultados).map(([r, n]) => `${r}: ${num(n)}`).join(' · ') : '–'}
          hint="pela régua do contrato (ex.: MQL)" bar="gray" />
      </div>
      <SectionCard title="Visitas por dia" subtitle="Barras = visitas; o número de leads aparece embaixo de cada dia.">
        <div className="flex items-end gap-1 h-40 overflow-x-auto" role="img" aria-label="Visitas por dia">
          {v.serie.map((d) => (
            <div key={d.dia} className="flex flex-col items-center justify-end h-full min-w-[22px] flex-1" title={`${diaCurto(d.dia)}: ${num(d.sessoes)} visitas, ${num(d.leads)} leads`}>
              <div className="w-full rounded-t-[var(--r-sm)] bg-[var(--accent)]" style={{ height: `${Math.max(2, (d.sessoes / maior) * 100)}%` }} />
              <div className="mt-1 text-[10px] tabular text-[var(--fg-3)]">{diaCurto(d.dia)}</div>
              <div className="text-[10px] tabular text-[var(--fg-2)]">{num(d.leads)}</div>
            </div>
          ))}
        </div>
      </SectionCard>
    </div>
  );
}

// ─── Páginas ─────────────────────────────────────────────────────────────────────────────────────────────────────────
export function PainelPaginas({ linhas }: { linhas: LinhaPagina[] }) {
  if (!linhas.length) return <SectionCard><Vazio /></SectionCard>;
  const comEntrada = linhas.filter((l) => l.entradas >= 30).sort((a, b) => taxa(b.entradas_lead, b.entradas) - taxa(a.entradas_lead, a.entradas));
  const melhor = comEntrada[0];
  const segunda = comEntrada[1];
  const cmp = melhor && segunda ? compararTaxas(segunda.entradas_lead, segunda.entradas, melhor.entradas_lead, melhor.entradas) : null;
  return (
    <SectionCard title="Páginas" subtitle="Uma linha por caminho. Página sem cadastro aparece pelo caminho (cadastre em Marketing > Projetos e páginas).">
      <DataTable minWidth={980}>
        <Thead><Th>Página</Th><Th>Vistas</Th><Th>Entradas</Th><Th>Rejeição</Th><Th>Lead (entrada)</Th><Th>Saída rápida</Th><Th>Rolagem média</Th><Th>Tempo médio</Th><Th>LCP p75</Th></Thead>
        <tbody>
          {linhas.map((l) => (
            <Tr key={l.dominio + l.caminho}>
              <Td>
                <div className="font-medium">{l.nome ?? <span className="text-[var(--fg-3)]">sem cadastro</span>}{l.codigo && <span className="ml-1 font-mono text-xs">({l.codigo})</span>}</div>
                <div className="font-mono text-xs text-[var(--fg-3)] break-all">{l.dominio}{l.caminho}</div>
              </Td>
              <Td>{num(l.visualizacoes)}</Td>
              <Td>{num(l.entradas)}</Td>
              <Td>{pct(l.rejeicoes, l.entradas)}</Td>
              <Td>{pct(l.entradas_lead, l.entradas)}</Td>
              <Td>{pct(l.saidas_rapidas, l.visualizacoes)}</Td>
              <Td><Barra fracao={l.rolagem_media / 100} rotulo={`${l.rolagem_media}%`} /></Td>
              <Td>{duracao(l.visivel_ms_medio)}</Td>
              <Td><SeloVital v="lcp" valor={l.lcp_p75} /></Td>
            </Tr>
          ))}
        </tbody>
      </DataTable>
      {cmp && (
        <p className="mt-3 text-sm text-[var(--fg-2)]">
          Lead por entrada: <b>{melhor.caminho}</b> {pct(melhor.entradas_lead, melhor.entradas)} x <b>{segunda.caminho}</b> {pct(segunda.entradas_lead, segunda.entradas)}.{' '}
          <Badge tone={cmp.nivel === 'forte' ? 'success' : cmp.nivel === 'provavel' ? 'warning' : 'neutral'}>{ROTULO_NIVEL[cmp.nivel]}</Badge>
        </p>
      )}
    </SectionCard>
  );
}

// ─── Funil ───────────────────────────────────────────────────────────────────────────────────────────────────────────
export function PainelFunil({ funis }: { funis: Funil[] }) {
  if (!funis.length) {
    return <SectionCard><Vazio titulo="Nenhum funil no contrato deste projeto." dica="O contrato (etapas, eventos de lead) mora em mkt_web.funis." /></SectionCard>;
  }
  return (
    <div className="space-y-4">
      {funis.map((f) => {
        const base = f.etapas[0]?.sessoes ?? 0;
        const pior = maiorPerda(f.etapas);
        return (
          <SectionCard key={f.id} title={f.nome} subtitle="Cada etapa conta as visitas que cumpriram ela e todas as anteriores.">
            {!base ? <Vazio /> : (
              <div className="space-y-2">
                {f.etapas.map((e, i) => (
                  <div key={e.ordem} className={`rounded-[var(--r-md)] p-2 ${i === pior ? 'bg-[var(--surface-3)] border border-[var(--border-strong)]' : ''}`}>
                    <div className="flex items-center justify-between gap-2 text-sm">
                      <span className="font-medium">{e.ordem}. {e.nome}</span>
                      <span className="tabular">{num(e.sessoes)} <span className="text-[var(--fg-3)]">({pct(e.sessoes, base)})</span></span>
                    </div>
                    <Barra fracao={taxa(e.sessoes, base)} rotulo={i === 0 ? '100%' : pct(e.sessoes, f.etapas[i - 1].sessoes, 0)} tone={i === pior ? 'red' : 'accent'} />
                    <div className="mt-0.5 text-[11px] text-[var(--fg-3)] font-mono">{[...e.caminhos, ...e.eventos].join(' · ')}</div>
                    {i === pior && <div className="mt-1 text-xs text-[var(--red)]">Maior perda do funil: só {pct(e.sessoes, f.etapas[i - 1].sessoes)} passam da etapa anterior para esta.</div>}
                  </div>
                ))}
              </div>
            )}
          </SectionCard>
        );
      })}
    </div>
  );
}

// ─── Origem ──────────────────────────────────────────────────────────────────────────────────────────────────────────
export function PainelOrigem({ o }: { o: Origem }) {
  if (!o.total) return <SectionCard><Vazio /></SectionCard>;
  return (
    <div className="space-y-4">
      <div className="grid gap-3 grid-cols-2 lg:grid-cols-3">
        <KpiCard label="Visitas" value={num(o.total)} />
        <KpiCard label="Com clique do Meta (fbclid)" value={pct(o.cliques_meta, o.total)} hint={num(o.cliques_meta)} bar="accent" />
        <KpiCard label="Com clique do Google (gclid)" value={pct(o.cliques_google, o.total)} hint={num(o.cliques_google)} bar="green" />
      </div>
      <SectionCard title="Plataforma (utm_source)">
        <DataTable minWidth={640}>
          <Thead><Th>Origem</Th><Th>Meio</Th><Th>Visitas</Th><Th>Engajaram</Th><Th>Leads</Th><Th>Taxa de lead</Th></Thead>
          <tbody>{o.fontes.map((f) => (
            <Tr key={f.fonte + (f.meio ?? '')}><Td>{nomeOrigem(f.fonte)}</Td><Td>{f.meio ?? '–'}</Td><Td>{num(f.sessoes)}</Td><Td>{pct(f.engajadas, f.sessoes)}</Td><Td>{num(f.leads)}</Td><Td>{pct(f.leads, f.sessoes)}</Td></Tr>
          ))}</tbody>
        </DataTable>
      </SectionCard>
      <SectionCard title="Campanha (utm_campaign)" subtitle="UTM no formato nome|id (padrão do gp-operacoes), contada pelo id. O nome é traduzido pelo padrão GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA (campo 5 = página).">
        {!o.campanhas.length ? <EmptyState title="Nenhuma visita com utm_campaign no período." /> : (
          <DataTable minWidth={760}>
            <Thead><Th>Campanha</Th><Th>Padrão</Th><Th>Página</Th><Th>Visitas</Th><Th>Leads</Th><Th>Taxa</Th></Thead>
            <tbody>{o.campanhas.map((c) => (
              <Tr key={(c.campanha_id ?? '') + '|' + c.campanha}>
                <Td>
                  <span className="font-mono text-xs break-all">{c.campanha}</span>
                  {c.campanha_id && c.campanha_id !== c.campanha && <span className="block font-mono text-[11px] text-[var(--fg-3)]" title={c.campanha_id}>id {codigoCurto(c.campanha_id)}</span>}
                </Td>
                <Td>{c.padrao == null ? <Badge tone="neutral">Só id</Badge> : <Badge tone={c.padrao ? 'success' : 'warning'}>{c.padrao ? 'No padrão' : 'Fora do padrão'}</Badge>}</Td>
                <Td>{c.pagina ? <span className="font-mono">{c.pagina}</span> : '–'}</Td>
                <Td>{num(c.sessoes)}</Td><Td>{num(c.leads)}</Td><Td>{pct(c.leads, c.sessoes)}</Td>
              </Tr>
            ))}</tbody>
          </DataTable>
        )}
      </SectionCard>
      <SectionCard title="Anúncio (utm_content)" subtitle="O anúncio (criativo) no formato nome|id, padrão do gp-operacoes; contado pelo id.">
        {!o.anuncios.length ? <EmptyState title="Nenhuma visita com utm_content no período." /> : (
          <DataTable minWidth={680}>
            <Thead><Th>Anúncio</Th><Th>Campanha</Th><Th>Visitas</Th><Th>Leads</Th><Th>Taxa</Th></Thead>
            <tbody>{o.anuncios.map((a) => (
              <Tr key={(a.anuncio_id ?? '') + '|' + a.anuncio}>
                <Td>
                  <span className="font-mono text-xs break-all" title={a.anuncio}>{codigoCurto(a.anuncio)}</span>
                  {a.anuncio_id && a.anuncio_id !== a.anuncio && <span className="block font-mono text-[11px] text-[var(--fg-3)]" title={a.anuncio_id}>id {codigoCurto(a.anuncio_id)}</span>}
                </Td>
                <Td><span className="font-mono text-xs break-all">{a.campanha ?? '–'}</span></Td>
                <Td>{num(a.sessoes)}</Td><Td>{num(a.leads)}</Td><Td>{pct(a.leads, a.sessoes)}</Td>
              </Tr>
            ))}</tbody>
          </DataTable>
        )}
      </SectionCard>
      {o.sites.length > 0 && (
        <SectionCard title="Site de onde veio (referrer)">
          <div className="space-y-1">{o.sites.map((s) => (
            <div key={s.site} className="flex items-center gap-3 text-sm"><span className="w-48 truncate font-mono text-xs">{s.site}</span><Barra fracao={taxa(s.sessoes, o.total)} rotulo={num(s.sessoes)} /></div>
          ))}</div>
        </SectionCard>
      )}
    </div>
  );
}

// ─── Velocidade ──────────────────────────────────────────────────────────────────────────────────────────────────────
export function PainelVelocidade({ v }: { v: Velocidade }) {
  if (!v.paginas.some((p) => p.n > 0)) return <SectionCard><Vazio /></SectionCard>;
  return (
    <div className="space-y-4">
      <SectionCard title="Velocidade real (p75)" subtitle="75% das visitas foram iguais ou melhores. Régua do Google: LCP até 2,5 s, INP até 200 ms, CLS até 0,1.">
        <DataTable minWidth={860}>
          <Thead><Th>Página</Th><Th>Aparelho</Th><Th>Medidas</Th><Th>LCP</Th><Th>INP</Th><Th>CLS</Th><Th>FCP</Th><Th>TTFB</Th><Th>LCP bom</Th><Th>Peso</Th></Thead>
          <tbody>{v.paginas.map((p) => (
            <Tr key={p.caminho + p.dispositivo}>
              <Td><span className="font-mono text-xs">{p.caminho}</span></Td>
              <Td>{APARELHO[p.dispositivo] ?? p.dispositivo}</Td>
              <Td>{num(p.n)}</Td>
              <Td><SeloVital v="lcp" valor={p.lcp_p75} /></Td>
              <Td><SeloVital v="inp" valor={p.inp_p75} /></Td>
              <Td><SeloVital v="cls" valor={p.cls_p75 == null ? null : Number(p.cls_p75)} /></Td>
              <Td>{msVital(p.fcp_p75)}</Td>
              <Td>{msVital(p.ttfb_p75)}</Td>
              <Td>{pct(p.lcp_bom, p.n, 0)}</Td>
              <Td>{p.peso_kb_mediano == null ? '–' : `${num(p.peso_kb_mediano)} KB`}</Td>
            </Tr>
          ))}</tbody>
        </DataTable>
      </SectionCard>
      <SectionCard title="LCP p75 por dia" subtitle="Cor da barra = faixa do Google: verde bom (até 2,5 s), amarelo precisa melhorar, vermelho ruim (acima de 4 s).">
        <div className="flex items-end gap-1 h-36 overflow-x-auto" role="img" aria-label="LCP por dia">
          {v.serie.map((d) => {
            const f = faixaVital('lcp', d.lcp_p75);
            const cor = f === 'ruim' ? 'var(--red)' : f === 'melhorar' ? 'var(--yellow)' : 'var(--green)';
            return (
              <div key={d.dia} className="flex flex-col items-center justify-end h-full min-w-[22px] flex-1" title={`${diaCurto(d.dia)}: ${msVital(d.lcp_p75)} (${num(d.n)} medidas)`}>
                <div className="w-full rounded-t-[var(--r-sm)]" style={{ height: `${Math.min(100, ((d.lcp_p75 ?? 0) / 6000) * 100)}%`, background: cor }} />
                <div className="mt-1 text-[10px] tabular text-[var(--fg-3)]">{diaCurto(d.dia)}</div>
              </div>
            );
          })}
        </div>
      </SectionCard>
    </div>
  );
}

// ─── Rolagem e leitura ───────────────────────────────────────────────────────────────────────────────────────────────
export function PainelLeitura({ l }: { l: Leitura }) {
  if (!l.visualizacoes) return <SectionCard><Vazio /></SectionCard>;
  const r = l.rolagem;
  const totalSeg = l.secoes.reduce((s, x) => s + x.segundos, 0);
  return (
    <div className="space-y-4">
      <SectionCard title="Até onde rolam" subtitle={`${num(l.visualizacoes)} páginas vistas. Rolagem média ${r.media}%${r.media_30s != null ? `; nos primeiros 30 s, ${r.media_30s}%` : ''}.`}>
        <div className="space-y-1.5">
          {([['25%', r.chegou_25], ['50%', r.chegou_50], ['75%', r.chegou_75], ['100% (fim)', r.chegou_100]] as const).map(([rot, n]) => (
            <div key={rot} className="flex items-center gap-3 text-sm"><span className="w-24 text-[var(--fg-2)]">Chegou a {rot}</span><Barra fracao={taxa(n, l.visualizacoes)} rotulo={pct(n, l.visualizacoes, 0)} /></div>
          ))}
        </div>
        {r.vaivem_medio != null && <p className="mt-2 text-xs text-[var(--fg-3)]">Vai e vem médio: {Number(r.vaivem_medio).toLocaleString('pt-BR')} (quem sobe e desce procurando algo).</p>}
      </SectionCard>
      <SectionCard title="Leitura por seção" subtitle="Segundos com a seção na linha de leitura (meio da tela), na ordem da página.">
        {!l.secoes.length ? <EmptyState title="Nenhuma seção medida (a página tem <section> ou data-secao?)." /> : (
          <DataTable minWidth={620}>
            <Thead><Th>Seção</Th><Th>Viram</Th><Th>Tempo médio de quem viu</Th><Th>Parte do tempo</Th></Thead>
            <tbody>{l.secoes.map((s) => (
              <Tr key={s.secao}>
                <Td><span title={`No código da página: "${s.secao}"`}>{apelidoSecao(s.secao)}</span></Td>
                <Td><Barra fracao={taxa(s.viram, s.medidas)} rotulo={pct(s.viram, s.medidas, 0)} /></Td>
                <Td>{duracao(s.viram ? (s.segundos / s.viram) * 1000 : 0)}</Td>
                <Td>{pct(s.segundos, totalSeg, 0)}</Td>
              </Tr>
            ))}</tbody>
          </DataTable>
        )}
      </SectionCard>
      <SectionCard title="Botões (data-cta)" subtitle="Quantos viram o botão na tela e quantas vezes clicaram.">
        {!l.ctas.length ? <EmptyState title="Nenhum botão com data-cta medido." /> : (
          <DataTable minWidth={560}>
            <Thead><Th>Botão</Th><Th>Viram</Th><Th>Cliques</Th><Th>Cliques por quem viu</Th></Thead>
            <tbody>{l.ctas.map((c) => (
              <Tr key={c.cta}><Td><span className="font-mono text-xs">{c.cta}</span></Td><Td><Barra fracao={taxa(c.viram, c.medidas)} rotulo={pct(c.viram, c.medidas, 0)} /></Td><Td>{num(c.cliques)}</Td><Td>{pct(c.cliques, c.viram)}</Td></Tr>
            ))}</tbody>
          </DataTable>
        )}
      </SectionCard>
    </div>
  );
}

// ─── Cliques e erros ─────────────────────────────────────────────────────────────────────────────────────────────────
function TabelaCliques({ linhas, sessoes = true }: { linhas: { seletor: string; texto: string; n: number; sessoes?: number }[]; sessoes?: boolean }) {
  if (!linhas.length) return <p className="text-sm text-[var(--fg-3)]">Nenhum.</p>;
  return (
    <DataTable minWidth={560}>
      <Thead><Th>Elemento</Th><Th>Texto</Th><Th>Cliques</Th>{sessoes && <Th>Visitas</Th>}</Thead>
      <tbody>{linhas.map((c) => (
        <Tr key={c.seletor}><Td><span className="font-mono text-xs break-all">{c.seletor}</span></Td><Td>{c.texto || '–'}</Td><Td>{num(c.n)}</Td>{sessoes && <Td>{num(c.sessoes)}</Td>}</Tr>
      ))}</tbody>
    </DataTable>
  );
}

export function PainelProblemas({ p }: { p: Problemas }) {
  if (!p.cliques && !p.erros && !p.automaticos) return <SectionCard><Vazio /></SectionCard>;
  return (
    <div className="space-y-4">
      <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Cliques de gente" value={num(p.cliques)} hint={`${num(p.automaticos)} automáticos fora da conta`} bar="gray" />
        <KpiCard label="Cliques de raiva" value={num(p.raiva)} hint={`${num(p.sessoes_com_raiva)} visitas · 3+ cliques em 0,7 s`} bar="yellow" />
        <KpiCard label="Cliques mortos" value={num(p.mortos)} hint="em algo que parece botão e não é" bar="yellow" />
        <KpiCard label="Erros da página" value={num(p.erros)} hint={`${num(p.sessoes_com_erro)} visitas`} bar="red" />
      </div>
      <SectionCard title="Onde clicam com raiva"><TabelaCliques linhas={p.top_raiva} /></SectionCard>
      <SectionCard title="Cliques mortos"><TabelaCliques linhas={p.top_mortos} /></SectionCard>
      <SectionCard title="Mais clicados"><TabelaCliques linhas={p.mais_clicados} sessoes={false} /></SectionCard>
      <SectionCard title="Erros de JavaScript da página">
        {!p.top_erros.length ? <p className="text-sm text-[var(--fg-3)]">Nenhum erro da página no período.</p> : (
          <DataTable minWidth={620}>
            <Thead><Th>Mensagem</Th><Th>Arquivo</Th><Th>Vezes</Th><Th>Visitas</Th></Thead>
            <tbody>{p.top_erros.map((e) => (
              <Tr key={e.mensagem + e.arquivo}><Td><span className="font-mono text-xs break-all">{e.mensagem}</span></Td><Td><span className="font-mono text-xs">{e.arquivo || '–'}</span></Td><Td>{num(e.n)}</Td><Td>{num(e.sessoes)}</Td></Tr>
            ))}</tbody>
          </DataTable>
        )}
      </SectionCard>
      {p.erros_fora.length > 0 && (
        <SectionCard title="Ruído de fora da página" subtitle="Erros do app do Facebook, de extensões e de scripts de outro site. Ficam guardados, mas fora da conta de erro.">
          <div className="space-y-1 text-sm">{p.erros_fora.map((e) => (
            <div key={e.tipo} className="flex justify-between gap-3"><span>{NOME_ERRO_FORA[e.tipo] ?? e.tipo}</span><span className="tabular text-[var(--fg-2)]">{num(e.n)} em {num(e.sessoes)} visitas</span></div>
          ))}</div>
        </SectionCard>
      )}
    </div>
  );
}

// ─── Formulário ──────────────────────────────────────────────────────────────────────────────────────────────────────
export function PainelFormulario({ f }: { f: Formulario }) {
  if (!f.medidas) return <SectionCard><Vazio /></SectionCard>;
  return (
    <div className="space-y-4">
      <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Viram o formulário" value={pct(f.viram, f.medidas)} hint={`${num(f.viram)} de ${num(f.medidas)} páginas vistas`} bar="gray" />
        <KpiCard label="Começaram" value={pct(f.comecaram, f.viram)} hint={`${num(f.comecaram)} de quem viu`} bar="accent" />
        <KpiCard label="Enviaram" value={pct(f.enviaram, f.comecaram)} hint={`${num(f.enviaram)} de quem começou`} bar="green" />
        <KpiCard label="Tempo mediano" value={f.tempo_mediano_s == null ? '–' : `${f.tempo_mediano_s} s`} hint="do primeiro campo ao último" bar="gray" />
      </div>
      <SectionCard title="Campo a campo" subtitle="Só números: o que a pessoa digita nunca é lido nem guardado.">
        <DataTable minWidth={700}>
          <Thead><Th>Campo</Th><Th>Entraram</Th><Th>Focos</Th><Th>Tempo médio</Th><Th>Ficou preenchido</Th><Th>Com erro</Th></Thead>
          <tbody>{f.campos.map((c) => (
            <Tr key={c.campo}><Td><span className="font-mono text-xs">{c.campo}</span></Td><Td>{num(c.entraram)}</Td><Td>{num(c.focos)}</Td><Td>{c.segundos_medio == null ? '–' : `${c.segundos_medio} s`}</Td><Td>{pct(c.preenchidos, c.entraram)}</Td><Td>{pct(c.com_erro, c.entraram)}</Td></Tr>
          ))}</tbody>
        </DataTable>
      </SectionCard>
      <SectionCard title="Onde param" subtitle="Último campo de quem começou e não enviou.">
        {!f.pararam_em.length ? <p className="text-sm text-[var(--fg-3)]">Ninguém parou no meio no período.</p> : (
          <div className="space-y-1">{f.pararam_em.map((p) => {
            const total = f.pararam_em.reduce((s, x) => s + x.n, 0);
            return <div key={p.campo} className="flex items-center gap-3 text-sm"><span className="w-32 font-mono text-xs">{p.campo}</span><Barra fracao={taxa(p.n, total)} rotulo={num(p.n)} tone="red" /></div>;
          })}</div>
        )}
      </SectionCard>
    </div>
  );
}

// ─── Instalação ──────────────────────────────────────────────────────────────────────────────────────────────────────
export function PainelInstalacao({ i, base, onLigar, ocupado }: {
  i: Instalacao; base: string; onLigar?: (projeto: number, ligada: boolean) => void; ocupado?: boolean;
}) {
  return (
    <div className="space-y-4">
      {i.coleta_geral === 'pausada' && (
        <p role="alert" className="text-sm text-[var(--red)]">A coleta inteira está PAUSADA (mkt_web.config: chave coleta). Nenhum projeto grava.</p>
      )}
      {i.projetos.map((p) => (
        <SectionCard key={p.id} title={<span><span className="font-mono">{p.sigla}</span> · {p.nome}</span>}
          subtitle={p.ultimo_pacote ? `Último pacote: ${new Date(p.ultimo_pacote).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' })}` : 'Nenhum pacote recebido ainda.'}
          right={
            <div className="flex items-center gap-2">
              <Badge tone={p.coleta ? 'success' : 'neutral'}>{p.coleta ? 'Coleta ligada' : 'Coleta desligada'}</Badge>
              {onLigar && <button type="button" disabled={ocupado} onClick={() => onLigar(p.id, !p.coleta)}
                className="text-xs font-semibold text-[var(--accent)] hover:underline disabled:opacity-50">{p.coleta ? 'Desligar' : 'Ligar'}</button>}
            </div>
          }>
          <div className="space-y-3 text-sm">
            <CopyField label="Linha do gravador (no <head> de cada página do projeto)" value={linhaDoGravador(p.sigla, base)} />
            <div><span className="text-[var(--fg-3)]">Domínios aceitos:</span>{' '}
              {p.dominios.length ? p.dominios.map((d) => <span key={d} className="font-mono text-xs mr-2">{d}</span>) : <span className="text-[var(--red)]">nenhuma página ativa cadastrada (o coletor recusa tudo)</span>}
            </div>
            <div><span className="text-[var(--fg-3)]">Eventos de lead:</span> <span className="font-mono text-xs">{p.eventos_lead.join(', ') || '–'}</span></div>
            <div><span className="text-[var(--fg-3)]">Funis:</span> {p.funis.length ? p.funis.map((f) => f.nome).join(' · ') : '–'}</div>
          </div>
        </SectionCard>
      ))}
      <SectionCard title="O que a coleta recusou (7 dias)" subtitle={`${i.falhas_7d} falha(s) da própria coleta no período.`}>
        {!i.recusas_7d.length ? <p className="text-sm text-[var(--fg-3)]">Nada recusado.</p> : (
          <div className="space-y-1 text-sm">{i.recusas_7d.map((r) => (
            <div key={r.motivo} className="flex justify-between gap-3"><span>{MOTIVO_RECUSA[r.motivo] ?? r.motivo}</span><span className="tabular">{num(r.vezes)}</span></div>
          ))}</div>
        )}
      </SectionCard>
    </div>
  );
}
