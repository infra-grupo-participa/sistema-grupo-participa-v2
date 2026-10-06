'use client';

// Relatórios do Comercial: fechamento do dia (playbook, seção 12) e indicadores de funil e equipe (seção 14).
// Toda agregação mora em indicadores.ts / domain/fechamento.ts; aqui só apresentação.
import { useMemo, useState } from 'react';
import {
  Button, Card, FilterSelect, Input, ProgressBar, SectionCard, SectionTitle, Tabs, Toast, Toolbar, idsAba, useFlash,
} from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { etapa as etapaDe, PRODUTOS, rotuloMotivo } from '../../domain/catalogo';
import { calcularFechamento, type LinhaFechamento } from '../../domain/fechamento';
import type {
  Atividade, EventoTimeline, MetricaKey, MotivoPerda, MotivoPerdaConfig, Negocio, ProdutoKey, Vendedor,
} from '../../domain/types';
import { fmtMinutos } from '../configuracoes/configuracao';
import {
  Carregando, combinarDados, EsqueletoLista, FaixaNumeros, NotaRodape, PaginaComercial, Pessoa, ProdutoTag, Segmentado, Vazio,
  useAbaHash, useEquipe,
} from '../comum';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import { repo, useAgora, useDados } from '../repositorio';
import {
  conversaoPorEtapa, fmtDuracao, instanteDoDia, ordenarEquipe, perdidosPorMotivo, rankingEquipe, tempoMedioPorEtapa,
  textoFechamentoSlack, vendasDoDia, ymdLocal, type ColunaEquipe, type OpcaoDia,
} from './indicadores';
import { GradeIndicadores, type ColunaGrade } from './GradeIndicadores';

type Aba = 'fechamento' | 'funil' | 'equipe';
const ABAS: readonly Aba[] = ['fechamento', 'funil', 'equipe'];
const ID_ABAS = 'relatorios-comercial';

/** Definição dos números desta tela que não estão em domain/metricas.ts (fonte do (i)). */
const INFO = {
  conversaoEtapa: {
    nome: 'Conversão por etapa',
    oQueE: 'Quantos negócios de venda ativa chegaram a cada etapa e quantos passaram da etapa anterior.',
    comoConta: 'Barra = % do total que entrou no funil. "% passaram" = chegaram nesta ÷ chegaram na anterior. Ganho conta como tendo passado por todas.',
    paraQue: 'A etapa com a menor passagem é onde o funil vaza: comece por ela.',
  },
  tempoEtapa: {
    nome: 'Tempo médio parado na etapa',
    oQueE: 'Quanto tempo, em média, os negócios abertos estão parados em cada etapa agora.',
    comoConta: 'Média de (agora − entrada na etapa) dos negócios abertos de venda ativa. Estimativa: o tempo real de passagem entra com o backend.',
    paraQue: 'Média acima do prazo crítico pede mutirão naquela etapa.',
  },
  concluidas: {
    nome: 'Atividades concluídas',
    oQueE: 'Atividades que o vendedor concluiu no período.',
    comoConta: 'Data de conclusão dentro do período, do dono da atividade.',
    paraQue: 'Disciplina e esforço. Leia junto com a conversão: muito toque e pouca venda pede revisar abordagem.',
  },
} satisfies Record<string, TextoIndicador>;

const FALHA_DISTRIBUICAO: MotivoPerda = 'ja_atendido_outro_vendedor';

export function RelatoriosClient() {
  const agora = useAgora();
  const { vendedores, nomeDe } = useEquipe();
  const rNegocios = useDados(() => repo.negocios());
  const rAtividades = useDados(() => repo.atividades());
  const rEventos = useDados(() => repo.eventos());
  const rMotivos = useDados(() => repo.motivosPerda());
  const carga = combinarDados(rNegocios, rAtividades, rEventos, rMotivos);
  const [aba, setAba] = useAbaHash<Aba>(ABAS, 'fechamento');

  return (
    <PaginaComercial titulo="Relatórios" subtitulo="Fechamento do dia, conversão do funil e desempenho da equipe, com definição exata.">
      <Tabs
        idBase={ID_ABAS}
        label="Relatórios do Comercial"
        active={aba}
        onChange={(k) => setAba(k as Aba)}
        tabs={[{ k: 'fechamento', l: 'Fechamento do dia' }, { k: 'funil', l: 'Funil' }, { k: 'equipe', l: 'Equipe' }]}
      />
      <div role="tabpanel" id={idsAba(ID_ABAS, aba).panel} aria-labelledby={idsAba(ID_ABAS, aba).tab}>
        <Carregando dados={carga.dados} erro={carga.erro} onTentar={carga.onTentar} esqueleto={<EsqueletoRelatorio />}>
          {([negocios, atividades, eventos, motivos]) => aba === 'fechamento' ? (
            <Fechamento negocios={negocios} atividades={atividades} eventos={eventos} motivos={motivos} vendedores={vendedores} nomeDe={nomeDe} agora={agora} />
          ) : aba === 'funil' ? (
            <Funil negocios={negocios} motivos={motivos} agora={agora} />
          ) : (
            <Equipe negocios={negocios} atividades={atividades} vendedores={vendedores} nomeDe={nomeDe} agora={agora} />
          )}
        </Carregando>
      </div>
    </PaginaComercial>
  );
}

/** Esqueleto no formato da tela: faixa de números + lista. */
function EsqueletoRelatorio() {
  return (
    <div aria-busy="true" aria-label="Carregando relatório" className="space-y-4">
      <div className="h-10 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] animate-pulse" />
      <EsqueletoLista linhas={4} />
    </div>
  );
}

// ── #fechamento ──

const OPCOES_DIA = [
  { valor: 'hoje' as OpcaoDia, rotulo: 'Hoje' },
  { valor: 'ontem' as OpcaoDia, rotulo: 'Ontem' },
  { valor: 'data' as OpcaoDia, rotulo: 'Outra data' },
];

/** Colunas do fechamento por vendedor: a mesma definição dos números do topo. */
const COLUNAS_FECHAMENTO: ColunaGrade[] = [
  { k: 'abordados', rotulo: 'Abordados', metrica: 'abordados' },
  { k: 'entraram', rotulo: 'Entraram', metrica: 'entraram_contato' },
  { k: 'responderam', rotulo: 'Responderam', metrica: 'responderam' },
  { k: 'negociacao', rotulo: 'Negociação', metrica: 'em_negociacao' },
  { k: 'vendas', rotulo: 'Vendas', metrica: 'vendas' },
  { k: 'receita', rotulo: 'Receita', metrica: 'receita' },
];

const LINHA_ZERADA: LinhaFechamento = { abordados: 0, entraramEmContato: 0, responderam: 0, emNegociacao: 0, entraramEmNegociacaoHoje: 0, vendas: 0, receita: 0 };

function celulasFechamento(l: LinhaFechamento | undefined) {
  const x = l ?? LINHA_ZERADA;
  return [
    { valor: x.abordados },
    { valor: x.entraramEmContato },
    { valor: x.responderam },
    { valor: x.emNegociacao, sub: `+${x.entraramEmNegociacaoHoje} no dia` },
    { valor: x.vendas },
    { valor: fmtBRL(x.receita) },
  ];
}

function Fechamento({ negocios, atividades, eventos, motivos, vendedores, nomeDe, agora }: {
  negocios: Negocio[]; atividades: Atividade[]; eventos: EventoTimeline[]; motivos: MotivoPerdaConfig[]; vendedores: Vendedor[];
  nomeDe: (id: string | null) => string; agora: Date;
}) {
  const [opcao, setOpcao] = useState<OpcaoDia>('hoje');
  const [ymd, setYmd] = useState(() => ymdLocal(new Date()));
  const { toast, flash } = useFlash();
  const dia = instanteDoDia(opcao, ymd, agora);
  // Base pequena: recalcula a cada render (o relógio anda a cada 30 s e as atrasadas acompanham).
  const f = calcularFechamento(negocios, atividades, eventos, dia);
  const vendas = vendasDoDia(negocios, dia);
  const ids = vendedores.map((v) => v.id);
  const texto = textoFechamentoSlack({ fechamento: f, vendas, dia, nomeDe, vendedorIds: ids, motivos });

  async function copiar() {
    try {
      await navigator.clipboard.writeText(texto);
      flash('Fechamento copiado. Cole no #comercial.');
    } catch {
      flash('Não foi possível copiar. Selecione o texto da prévia.');
    }
  }

  const t = f.total;
  const linhasVend = vendedores.filter((v) => f.porVendedor[v.id] || v.papel === 'vendedor');
  const atrasadas = Object.entries(f.alertas.atrasadasPorVendedor).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]);
  const perdidos = (Object.entries(f.alertas.perdidosPorMotivo) as [MotivoPerda, number][]).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]);
  const totalAtrasadas = atrasadas.reduce((s, [, n]) => s + n, 0);
  const totalPerdidos = perdidos.reduce((s, [, n]) => s + n, 0);
  // Falha de processo = motivo que avisa o gestor (de fábrica: "já atendido por outro vendedor").
  const avisaGestor = new Set<MotivoPerda>([FALHA_DISTRIBUICAO, ...motivos.filter((m) => m.alertaGestor).map((m) => m.key)]);
  const falha = perdidos.filter(([m]) => avisaGestor.has(m)).reduce((s, [, n]) => s + n, 0);

  return (
    <div className="space-y-4">
      <Toolbar>
        <Segmentado rotulo="Dia do fechamento" opcoes={OPCOES_DIA} valor={opcao} onChange={setOpcao} />
        {opcao === 'data' && (
          <Input type="date" value={ymd} max={ymdLocal(agora)} onChange={(e) => setYmd(e.target.value)} aria-label="Data do fechamento" className="!w-auto" />
        )}
        <span className="text-sm text-[var(--fg-2)] capitalize">
          {dia.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long' })}
        </span>
        <span className="text-[11px] text-[var(--fg-3)]">CRM em dia até 18h45 · fechamento às 19h no #comercial</span>
        <span className="flex-1" />
        <Button size="sm" onClick={copiar}><Icon name="copy" size={14} /> Copiar para o Slack</Button>
      </Toolbar>

      <div>
        <FaixaNumeros itens={[
          { rotulo: 'Abordados', valor: t.abordados, metrica: 'abordados' },
          { rotulo: 'Entraram em contato', valor: t.entraramEmContato, metrica: 'entraram_contato' },
          { rotulo: 'Responderam', valor: t.responderam, metrica: 'responderam' },
          { rotulo: 'Em negociação', valor: <>{t.emNegociacao} <span className="font-normal text-[var(--fg-3)]">(+{t.entraramEmNegociacaoHoje})</span></>, metrica: 'em_negociacao' },
          { rotulo: 'Vendas', valor: <>{t.vendas} <span className="font-normal text-[var(--fg-3)]">· {fmtBRL(t.receita)}</span></>, metrica: 'vendas' },
        ]} />
        {opcao !== 'hoje' && (
          <NotaRodape className="mt-1.5">
            &quot;Em negociação&quot;, &quot;sem próxima atividade&quot; e &quot;sem dono&quot; são retrato de agora: o histórico diário desses números entra com o backend.
          </NotaRodape>
        )}
      </div>

      <div>
        <SectionTitle>Por vendedor</SectionTitle>
        <GradeIndicadores
          rotulo="Fechamento por vendedor"
          primeira="Vendedor"
          colunas={COLUNAS_FECHAMENTO}
          linhas={[
            ...linhasVend.map((v) => ({ id: v.id, cabeca: <Pessoa nome={v.nome} size={24} />, celulas: celulasFechamento(f.porVendedor[v.id]) })),
            { id: 'total', cabeca: 'Total', celulas: celulasFechamento(t), total: true },
          ]}
        />
        <NotaRodape className="mt-1.5">O total inclui o que caiu sem dono (por isso pode passar da soma das linhas). Entre parênteses no topo: quantos entraram em negociação no dia.</NotaRodape>
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <div className="min-w-0">
          <SectionTitle right={<InfoIndicador metrica="vendas" />}>Vendas por produto</SectionTitle>
          {vendas.length ? (
            <Card>
              <ul className="divide-y divide-[var(--border-faint)]">
                {vendas.map((v) => (
                  <li key={`${v.produto}-${v.donoId}`} className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-3">
                    <span className="min-w-0 flex items-center gap-2">
                      <ProdutoTag k={v.produto} />
                      <span className="text-xs text-[var(--fg-3)]">{nomeDe(v.donoId)}</span>
                    </span>
                    <span className="flex items-baseline gap-3 tabular">
                      <span className="text-xs text-[var(--fg-3)]">{v.quantidade} {v.quantidade === 1 ? 'venda' : 'vendas'}</span>
                      <span className="text-sm font-semibold text-[var(--fg)]">{fmtBRL(v.valor)}</span>
                    </span>
                  </li>
                ))}
              </ul>
            </Card>
          ) : (
            <Card><Vazio titulo="Nenhuma venda no dia" hint="Venda conta quando a Hotmart aprova o pagamento." icone="wallet" /></Card>
          )}
        </div>

        <div className="min-w-0">
          <SectionTitle>Alertas do dia</SectionTitle>
          <Card className="divide-y divide-[var(--border-faint)]">
            <LinhaAlerta
              rotulo="Sem próxima atividade" metrica="sem_proximo" valor={f.alertas.semProximaAtividade} alerta={f.alertas.semProximaAtividade > 0}
              meta="Meta: zero. Negócio sem próximo passo com data vira perdido."
            />
            <LinhaAlerta
              rotulo="Leads sem dono" metrica="sem_dono" valor={f.alertas.semDono} alerta={f.alertas.semDono > 0}
              meta="Meta: zero. Caixa de não atribuídos zerada."
            />
            <LinhaAlerta
              rotulo="Atividades atrasadas" metrica="atrasadas" valor={totalAtrasadas} alerta={totalAtrasadas > 0}
              meta={atrasadas.length ? atrasadas.map(([id, n]) => `${nomeDe(id)} ${n}`).join(' · ') : 'Meta: zero. Nenhuma atrasada.'}
            />
            <LinhaAlerta
              rotulo="Perdidos do dia" metrica="perdidos" valor={totalPerdidos} alerta={falha > 0}
              rotuloAlerta="falha de processo no dia"
              meta={perdidos.length
                ? perdidos.map(([m, n]) => `${rotuloMotivo(m, motivos)} ${n}${avisaGestor.has(m) ? ' (falha de processo)' : ''}`).join(' · ')
                : 'Nenhum perdido no dia.'}
            />
          </Card>
        </div>
      </div>

      <SectionCard title="Mensagem para o Slack" subtitle="Prévia em texto simples, pronta para colar no #comercial às 19h.">
        <pre className="whitespace-pre-wrap break-words rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3 text-xs leading-relaxed text-[var(--fg-2)] font-mono max-h-80 overflow-y-auto">{texto}</pre>
      </SectionCard>
      <Toast>{toast}</Toast>
    </div>
  );
}

/** Uma linha da lista de alertas: rótulo (i) · número (vermelho só se viola a meta) · meta/detalhe. */
function LinhaAlerta({ rotulo, metrica, valor, alerta, meta, rotuloAlerta = 'fora da meta' }: {
  rotulo: string; metrica: MetricaKey; valor: number; alerta: boolean; meta: string; rotuloAlerta?: string;
}) {
  return (
    <div className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-0.5 px-4 py-3 sm:grid-cols-[minmax(0,190px)_48px_1fr] sm:items-center">
      <span className="inline-flex min-w-0 items-center gap-1 text-sm text-[var(--fg)]">{rotulo} <InfoIndicador metrica={metrica} /></span>
      <span className={`text-sm font-semibold tabular text-right sm:text-left ${alerta ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>
        {valor}
        {alerta && <span className="sr-only"> ({rotuloAlerta})</span>}
      </span>
      <span className="col-span-2 sm:col-span-1 text-xs text-[var(--fg-3)] min-w-0 break-words">{meta}</span>
    </div>
  );
}

// ── #funil ──

function Funil({ negocios, motivos: cadastro, agora }: { negocios: Negocio[]; motivos: MotivoPerdaConfig[]; agora: Date }) {
  const [prod, setProd] = useState<ProdutoKey | 'todos'>('todos');
  const conversao = useMemo(() => conversaoPorEtapa(negocios, prod), [negocios, prod]);
  const tempos = tempoMedioPorEtapa(negocios, prod, agora);
  const motivos = useMemo(() => perdidosPorMotivo(negocios, prod, cadastro), [negocios, prod, cadastro]);
  const maxMotivo = Math.max(1, ...motivos.map((m) => m.quantidade));
  const totalPerdidos = motivos.reduce((s, m) => s + m.quantidade, 0);
  const falha = motivos.find((m) => m.falhaDistribuicao)?.quantidade ?? 0;

  return (
    <div className="space-y-4">
      <Toolbar>
        <FilterSelect value={prod} onChange={(e) => setProd(e.target.value as ProdutoKey | 'todos')} aria-label="Produto">
          <option value="todos">Todos os produtos</option>
          {PRODUTOS.map((p) => <option key={p.key} value={p.key}>{p.nome}</option>)}
        </FilterSelect>
        <span className="text-xs text-[var(--fg-3)]">Origem &quot;Venda ativa&quot;. Ganho conta como tendo passado por todas as etapas.</span>
      </Toolbar>

      <SectionCard
        title={<>Conversão por etapa <InfoIndicador texto={INFO.conversaoEtapa} className="font-normal" /></>}
        subtitle="Quantos negócios chegaram a cada etapa e quantos passaram da etapa anterior."
      >
        {!conversao[0]?.chegaram ? (
          <Vazio
            titulo="Nenhum negócio neste produto"
            icone="chart"
            acao={prod !== 'todos' ? <Button size="sm" variant="ghost" onClick={() => setProd('todos')}>Ver todos os produtos</Button> : undefined}
          />
        ) : (
          <div className="space-y-3">
            {conversao.map((l) => (
              <div key={l.etapa} className="grid gap-2 sm:grid-cols-[180px_1fr_150px] sm:items-center">
                <div className="text-sm font-medium text-[var(--fg)] truncate" title={etapaDe(l.etapa).criterio ? `Critério para passar: ${etapaDe(l.etapa).criterio}` : undefined}>{etapaDe(l.etapa).label}</div>
                <ProgressBar value={l.doTotal} height={8} ariaLabel={`${l.chegaram} negócios chegaram em ${etapaDe(l.etapa).label}`} valueNow={l.chegaram} valueMax={conversao[0].chegaram} />
                <div className="flex items-baseline justify-between gap-2 text-xs sm:justify-end">
                  <span className="tabular font-semibold text-[var(--fg)]">{l.chegaram}</span>
                  <span className="tabular text-[var(--fg-3)]" title="Passagem da etapa anterior">{l.passagem == null ? 'entrada' : `${Math.round(l.passagem)}% passaram`}</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </SectionCard>

      <div className="grid gap-4 xl:grid-cols-2">
        <div className="min-w-0">
          <SectionTitle right={<InfoIndicador texto={INFO.tempoEtapa} />}>Tempo médio parado na etapa</SectionTitle>
          <Card>
            <ul className="divide-y divide-[var(--border-faint)]">
              {tempos.map((x) => {
                const e = etapaDe(x.etapa);
                const nivel = x.mediaMin == null ? null
                  : e.slaCriticoMin != null && x.mediaMin >= e.slaCriticoMin ? 'critico'
                    : e.slaAtencaoMin != null && x.mediaMin >= e.slaAtencaoMin ? 'atencao' : null;
                return (
                  <li key={x.etapa} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5 px-4 py-2.5">
                    <span className="min-w-0 text-sm text-[var(--fg)]">
                      {e.label}
                      <span className="ml-2 text-xs tabular text-[var(--fg-3)]">{x.abertos} {x.abertos === 1 ? 'aberto' : 'abertos'}</span>
                    </span>
                    <span className="flex items-baseline gap-3 whitespace-nowrap">
                      <span className={`text-sm tabular ${nivel === 'critico' ? 'font-semibold text-[var(--red)]' : nivel === 'atencao' ? 'font-semibold text-[var(--yellow)]' : 'text-[var(--fg)]'}`}>
                        {fmtDuracao(x.mediaMin)}
                        {nivel && <span className="sr-only"> ({nivel === 'critico' ? 'acima do crítico' : 'acima do alerta'})</span>}
                      </span>
                      <span className="text-[11px] tabular text-[var(--fg-3)]" title="Prazo de atenção / crítico da etapa">
                        {e.slaAtencaoMin == null && e.slaCriticoMin == null ? 'sem prazo' : `prazo ${fmtMinutos(e.slaAtencaoMin)} / ${fmtMinutos(e.slaCriticoMin)}`}
                      </span>
                    </span>
                  </li>
                );
              })}
            </ul>
          </Card>
          <NotaRodape className="mt-1.5">Estimativa pelos negócios abertos hoje (desde quando estão na etapa). Amarelo: acima do alerta; vermelho: acima do crítico.</NotaRodape>
        </div>

        <div className="min-w-0">
          <SectionTitle right={(
            <span className="inline-flex items-center gap-1 text-[11px] text-[var(--fg-3)] tabular">{totalPerdidos} perdidos <InfoIndicador metrica="perdidos" /></span>
          )}>Perdidos por motivo</SectionTitle>
          <Card className="p-4">
            {totalPerdidos === 0 ? (
              <Vazio titulo="Nenhum perdido neste recorte" icone="chart" />
            ) : (
              <ul className="space-y-3">
                {motivos.map((m) => {
                  const vermelho = (m.falhaDistribuicao || m.alertaGestor) && m.quantidade > 0;
                  return (
                    <li key={m.motivo} className="grid grid-cols-[1fr_auto] gap-x-3 gap-y-1 items-center">
                      <span className="text-sm truncate text-[var(--fg-2)]" title={m.nota ?? undefined}>
                        {m.rotulo}
                        {m.falhaDistribuicao ? <span className="text-[var(--fg-3)]"> · falha de distribuição</span>
                          : m.alertaGestor ? <span className="text-[var(--fg-3)]"> · avisa o gestor</span> : null}
                        {m.personalizado && <span className="text-[var(--fg-3)]"> · personalizado</span>}
                        {m.desativado && <span className="text-[var(--fg-3)]"> · desativado</span>}
                      </span>
                      <span className="text-sm tabular font-semibold text-[var(--fg)]">{m.quantidade}</span>
                      <div className="col-span-2">
                        <ProgressBar value={(m.quantidade / maxMotivo) * 100} tone={vermelho ? 'red' : 'neutral'} height={4} ariaLabel={`${m.quantidade} perdidos por ${m.rotulo}`} />
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
            <NotaRodape className="mt-4">
              Motivos do cadastro (Configurações, motivos de perda), inclusive os criados pelo gestor. &quot;Já atendido por outro vendedor&quot; é falha de distribuição, não do lead: o gestor trata no mesmo dia.{falha ? ` ${falha} neste recorte.` : ''}
            </NotaRodape>
          </Card>
        </div>
      </div>
    </div>
  );
}

// ── #equipe ──

const PERIODOS: { k: string; l: string; dias: number | null }[] = [
  { k: '7', l: 'Últimos 7 dias', dias: 7 },
  { k: '30', l: 'Últimos 30 dias', dias: 30 },
  { k: 'tudo', l: 'Todo o histórico', dias: null },
];

const COLUNAS: { k: Exclude<ColunaEquipe, 'nome'>; l: string; dir: 'asc' | 'desc'; metrica?: MetricaKey; info?: TextoIndicador }[] = [
  { k: 'vendas', l: 'Vendas', dir: 'desc', metrica: 'vendas' },
  { k: 'receita', l: 'Receita', dir: 'desc', metrica: 'receita' },
  { k: 'conversao', l: 'Conversão', dir: 'desc', metrica: 'conversao' },
  { k: 'abertos', l: 'Abertos', dir: 'desc', metrica: 'abertos' },
  { k: 'concluidas', l: 'Concluídas', dir: 'desc', info: INFO.concluidas },
  { k: 'atrasadas', l: 'Atrasadas', dir: 'desc', metrica: 'atrasadas' },
];

/** Destaque discreto (ícone com title), sem Badge dentro da linha. */
function Destaque({ rotulo }: { rotulo: string }) {
  return (
    <span className="ml-1.5 inline-flex align-middle text-[var(--fg-2)]" title={rotulo}>
      <Icon name="trending-up" size={13} />
      <span className="sr-only">{rotulo}</span>
    </span>
  );
}

function Equipe({ negocios, atividades, vendedores, nomeDe, agora }: {
  negocios: Negocio[]; atividades: Atividade[]; vendedores: Vendedor[]; nomeDe: (id: string | null) => string; agora: Date;
}) {
  const [periodo, setPeriodo] = useState('30');
  const [col, setCol] = useState<ColunaEquipe>('vendas');
  const [dir, setDir] = useState<'asc' | 'desc'>('desc');
  const dias = PERIODOS.find((p) => p.k === periodo)?.dias ?? null;
  const linhas = useMemo(() => {
    const desde = dias == null ? null : new Date(agora.getTime() - dias * 24 * 3600_000);
    return rankingEquipe(vendedores, negocios, atividades, agora, desde)
      .filter((l) => vendedores.find((v) => v.id === l.vendedorId)?.papel === 'vendedor' || l.vendas || l.abertos || l.concluidas);
  }, [vendedores, negocios, atividades, agora, dias]);
  const ordenadas = ordenarEquipe(linhas, col, dir, (id) => nomeDe(id));
  const melhorConv = Math.max(...linhas.map((l) => l.conversao ?? -1));
  const maisVendas = Math.max(...linhas.map((l) => l.vendas));
  const ehMaisVendas = (n: number) => n > 0 && n === maisVendas;
  const ehMelhorConv = (c: number | null) => c != null && c === melhorConv;

  function ordenar(k: ColunaEquipe, padrao: 'asc' | 'desc') {
    if (k === col) setDir(dir === 'asc' ? 'desc' : 'asc');
    else { setCol(k); setDir(padrao); }
  }

  const colunas: ColunaGrade[] = COLUNAS.map((c) => ({
    k: c.k, rotulo: c.l, metrica: c.metrica, info: c.info, ativa: col === c.k, dir, onOrdenar: () => ordenar(c.k, c.dir),
  }));

  return (
    <div className="space-y-4">
      <Toolbar>
        <FilterSelect value={periodo} onChange={(e) => setPeriodo(e.target.value)} aria-label="Período">
          {PERIODOS.map((p) => <option key={p.k} value={p.k}>{p.l}</option>)}
        </FilterSelect>
        {/* Em tela estreita não há cabeçalho clicável: a ordenação vem para cá. */}
        <FilterSelect
          value={`${col}:${dir}`}
          onChange={(e) => { const [k, d] = e.target.value.split(':'); setCol(k as ColunaEquipe); setDir(d as 'asc' | 'desc'); }}
          aria-label="Ordenar por"
          className="lg:hidden"
        >
          <option value="nome:asc">Ordenar: Vendedor</option>
          {COLUNAS.map((c) => <option key={c.k} value={`${c.k}:${c.dir}`}>Ordenar: {c.l}</option>)}
        </FilterSelect>
        <span className="text-xs text-[var(--fg-3)]">Leia a conversão junto com a carga (abertos) e a disciplina (atrasadas).</span>
      </Toolbar>

      {ordenadas.length ? (
        <GradeIndicadores
          rotulo="Ranking da equipe"
          primeira="Vendedor"
          colunas={colunas}
          linhas={ordenadas.map((l) => ({
            id: l.vendedorId,
            cabeca: <Pessoa nome={nomeDe(l.vendedorId)} size={24} />,
            celulas: [
              { valor: <>{l.vendas}{ehMaisVendas(l.vendas) && <Destaque rotulo="Mais vendas no período" />}</> },
              { valor: fmtBRL(l.receita) },
              {
                valor: <>{l.conversao == null ? <span className="text-[var(--fg-3)]">—</span> : `${Math.round(l.conversao)}%`}{ehMelhorConv(l.conversao) && <Destaque rotulo="Melhor conversão no período" />}</>,
                sub: l.encerrados > 0 ? `${l.ganhos} de ${l.encerrados}` : undefined,
              },
              { valor: l.abertos },
              { valor: l.concluidas },
              { valor: l.atrasadas, alerta: l.atrasadas > 0 },
            ],
          }))}
        />
      ) : (
        <Card>
          <Vazio
            titulo="Nenhum vendedor com dado no período"
            icone="users"
            acao={periodo !== 'tudo' ? <Button size="sm" variant="ghost" onClick={() => setPeriodo('tudo')}>Ver todo o histórico</Button> : undefined}
          />
        </Card>
      )}
    </div>
  );
}
