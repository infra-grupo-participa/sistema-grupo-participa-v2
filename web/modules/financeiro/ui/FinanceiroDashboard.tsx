'use client';

// Dashboard executivo do Financeiro — a condição num relance, de cima para baixo:
// 0. Estado da turma (farol consolidado — a resposta de "como estamos?")
// 1. A foto do dinheiro (recebido / a receber / cobertura)
// 2. Meta da turma (bullets meta vs realizado) + pulso do caixa (sparkline)
// 3. Previsão de recebimento (quando o dinheiro entra)
// 4. Risco: envelhecimento do saldo (aging) + saúde da carteira, lado a lado
// 5. Fazer agora (as 3 ações do operador)
// 6. A receber por canal
import { useMemo } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { ContaReceber, DiaFaturamento, Meta } from '../domain/types';
import {
  agrupar, resumir, statusLabel, statusTone, STATUS_ORDEM, type Gaveta,
} from '../domain/financeiro';
import { AGING_META, distribuicaoAging, preverRecebimento } from '../domain/cobranca';
import {
  CONDICAO_META, condicaoAging, condicaoPrevisibilidade, estadoTurma, metaVsReal,
  type Condicao, type Indicador,
} from '../domain/saude';
import { Card, EmptyState, Loading, ProgressBar, SectionTitle } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';

/** Tom semântico → token de cor (mesma paleta do Badge). */
const TONE_COLOR: Record<ReturnType<typeof statusTone>, string> = {
  neutral: 'var(--fg-3)',
  accent: 'var(--accent)',
  success: 'var(--green)',
  warning: 'var(--yellow)',
  danger: 'var(--red)',
  info: 'var(--info)',
};

const MORTOS = new Set(['cancelado', 'reembolsado']);

/** Cor do token para uma condição — a cor mora no ícone/dot/barra, nunca no texto. */
const condCor = (c: Condicao) => TONE_COLOR[CONDICAO_META[c].tone];

export function FinanceiroDashboard({ contas, dias, meta, loading, onDrill, onDrillStatus }: {
  contas: ContaReceber[];
  /** Série do faturamento diário (mais recente primeiro) — alimenta o pulso do caixa. */
  dias: DiaFaturamento[];
  /** Meta da turma selecionada; null = ainda não configurada. */
  meta: Meta | null;
  loading: boolean;
  onDrill: (g: Gaveta) => void;
  /** Statuses sem gaveta própria navegam com o filtro de status aplicado. */
  onDrillStatus?: (s: string) => void;
}) {
  const hojeISO = new Date().toISOString().slice(0, 10);
  const r = useMemo(() => resumir(contas), [contas]);
  const forecast = useMemo(() => preverRecebimento(contas, hojeISO), [contas, hojeISO]);
  const aging = useMemo(() => distribuicaoAging(contas), [contas]);
  const canais = useMemo(() => agrupar(contas, (c) => c.canal), [contas]);
  const estado = useMemo(() => estadoTurma(contas), [contas]);
  const mv = useMemo(() => metaVsReal(contas, meta, hojeISO), [contas, meta, hojeISO]);
  const indAging = useMemo(() => condicaoAging(contas), [contas]);
  const indPrev = useMemo(() => condicaoPrevisibilidade(contas), [contas]);
  // Pulso do caixa: bruto diário dos últimos 14 dias com lançamento, do mais antigo ao mais novo.
  const pulso = useMemo(() => [...dias].sort((a, b) => a.dia.localeCompare(b.dia)).slice(-14), [dias]);
  const porStatus = useMemo(() => {
    const rank = (s: string) => {
      const i = (STATUS_ORDEM as readonly string[]).indexOf(s);
      return i === -1 ? STATUS_ORDEM.length : i;
    };
    return agrupar(contas, (c) => c.status_financeiro).sort((a, b) => rank(a.chave) - rank(b.chave));
  }, [contas]);

  if (loading) return <Loading label="Carregando contas da turma…" />;
  if (!contas.length) return <EmptyState title="Nenhuma conta nesta turma" icon="inbox" />;

  // Barra empilhada só com contas vivas; mortas apagadas no fim da legenda.
  const vivos = porStatus.filter((f) => !MORTOS.has(f.chave));
  const mortos = porStatus.filter((f) => MORTOS.has(f.chave));

  const acoes: { g: Gaveta; label: string; hint: string; n: number; sub: string; color: string; icon: string }[] = [
    { g: 'vencido', label: 'Vencido', hint: 'cobrar já', n: r.vencidoQtd, sub: `${fmtBRL(r.vencido)} em atraso`, color: 'var(--red)', icon: 'alert' },
    { g: 'sem_acordo', label: 'Sem acordo', hint: 'combinar data', n: r.semAcordo, sub: 'sem vencimento definido', color: 'var(--accent)', icon: 'clipboard' },
    { g: 'incalculavel', label: 'A calcular', hint: 'descobrir valor', n: r.incalculavel, sub: 'sem insumo de crédito', color: 'var(--yellow)', icon: 'notebook' },
  ];

  const maxCanal = Math.max(1, ...canais.map((f) => f.aReceber));

  const corEstado = condCor(estado.condicao);

  return (
    <div className="space-y-4">
      {/* Bloco 0 — estado da turma: o primeiro que o olho bate. Ícone + selo + motivo (nunca cor sozinha). */}
      <Card className="p-3.5" style={{ borderLeft: `4px solid ${corEstado}` }}>
        <div className="flex items-center gap-3 min-w-0">
          <span
            className="grid place-items-center w-9 h-9 rounded-[var(--r-md)] shrink-0"
            style={{ background: `color-mix(in srgb, ${corEstado} 14%, transparent)`, color: corEstado }}
          >
            <Icon name={CONDICAO_META[estado.condicao].icon} size={19} />
          </span>
          <div className="min-w-0">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Estado da turma</div>
            <div className="mt-0.5 flex items-center gap-2 flex-wrap">
              <span
                className="inline-flex items-center rounded-[var(--r-pill)] px-2 py-0.5 text-[11px] font-bold text-[var(--fg)]"
                style={{ background: `color-mix(in srgb, ${corEstado} 14%, transparent)` }}
              >
                {estado.titulo}
              </span>
              <span className="text-[12px] text-[var(--fg-2)]">{estado.motivo}</span>
            </div>
          </div>
        </div>
      </Card>

      {/* Bloco 1 — a foto do dinheiro */}
      <Card className="p-4 border-[var(--border-accent)]" style={{ borderTop: '3px solid var(--accent)' }}>
        <div className="grid gap-x-6 gap-y-3.5 sm:grid-cols-3">
          <div className="min-w-0">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Recebido</div>
            <div className="mt-1 text-[22px] font-bold tabular leading-none text-[var(--green)] break-words">{fmtBRL(r.recebidoBruto)}</div>
          </div>
          <div className="min-w-0">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">A receber</div>
            <div className="mt-1 text-[22px] font-bold tabular leading-none text-[var(--accent)] break-words">{fmtBRL(r.aReceber)}</div>
          </div>
          <div className="min-w-0">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Cobertura</div>
            <div className="mt-1 text-[22px] font-bold tabular leading-none text-[var(--fg)]">{r.cobertura.toFixed(1)}%</div>
            <div className="mt-1.5"><ProgressBar value={r.cobertura} tone="accent" height={5} /></div>
            <div className="mt-1 text-[10px] text-[var(--fg-3)]">do contratado ({fmtBRL(r.pacoteTotal)}) já entrou</div>
          </div>
        </div>
        <div className="mt-3 pt-2.5 border-t border-[var(--border-faint)] text-[10px] tabular text-[var(--fg-3)]">
          líquido {fmtBRL(r.recebidoLiquido)} · taxas {fmtBRL(r.taxas)} · {r.alunos} alunos
        </div>
      </Card>

      {/* Bloco 2 — meta da turma (bullets) + pulso do caixa (sparkline), lado a lado */}
      <div className="grid gap-4 lg:grid-cols-3 items-stretch">
        <div className="lg:col-span-2 flex flex-col">
          <SectionTitle>Meta da turma</SectionTitle>
          <Card className="p-4 flex-1">
            {mv.arrecadacao.meta == null && mv.cobertura.meta == null ? (
              <div className="flex items-center gap-2.5 text-[12px] text-[var(--fg-3)]">
                <Icon name="settings" size={14} className="shrink-0" />
                <span>
                  Sem meta para esta turma ainda.{' '}
                  <a href="#configuracoes" className="font-medium text-[var(--accent)] hover:underline">Defina a meta em Configurações</a>
                  {' '}para acompanhar o progresso aqui.
                </span>
              </div>
            ) : (
              <div className="space-y-3.5">
                {mv.arrecadacao.meta != null && (
                  <BulletMeta
                    label="Arrecadação"
                    realizado={fmtBRL(mv.arrecadacao.realizado)}
                    alvo={`meta ${fmtBRL(mv.arrecadacao.meta)}`}
                    ind={mv.arrecadacao.ind}
                  />
                )}
                {mv.cobertura.meta != null && (
                  <BulletMeta
                    label="Cobertura"
                    realizado={`${mv.cobertura.realizado.toFixed(1)}%`}
                    alvo={`meta ${mv.cobertura.meta}%`}
                    ind={mv.cobertura.ind}
                  />
                )}
                {mv.diasParaFechar != null && (
                  <div className="pt-2 border-t border-[var(--border-faint)] text-[10px] text-[var(--fg-3)]">
                    {mv.diasParaFechar > 1 ? `faltam ${mv.diasParaFechar} dias para o fechamento`
                      : mv.diasParaFechar === 1 ? 'falta 1 dia para o fechamento'
                      : mv.diasParaFechar === 0 ? 'o fechamento é hoje'
                      : mv.diasParaFechar === -1 ? 'fechamento vencido há 1 dia'
                      : `fechamento vencido há ${-mv.diasParaFechar} dias`}
                  </div>
                )}
              </div>
            )}
          </Card>
        </div>

        <div className="flex flex-col">
          <SectionTitle>Pulso do caixa</SectionTitle>
          <Card className="p-3.5 flex-1 flex flex-col">
            <PulsoCaixa pulso={pulso} hojeISO={hojeISO} />
          </Card>
        </div>
      </div>

      {/* Bloco 3 — previsão de recebimento: quando o dinheiro entra */}
      <div>
        <SectionTitle right={<Farol cond={indPrev.condicao} nota={indPrev.nota} />}>Previsão de recebimento</SectionTitle>
        <Card className="p-3.5">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3">
            <MiniPrevisao label="Próx. 7 dias" valor={forecast.proximos7} cor="var(--green)" />
            <MiniPrevisao label="Próx. 30 dias" valor={forecast.proximos30} cor="var(--accent)" />
            <MiniPrevisao label="Em risco (vencido)" valor={forecast.emRisco} cor="var(--red)" />
            <MiniPrevisao label="Sem prazo" valor={forecast.semPrazo} cor="var(--fg-3)" />
          </div>
        </Card>
      </div>

      {/* Bloco 4 — risco: aging do saldo (a novidade) + saúde por status, lado a lado */}
      <div className="grid gap-4 lg:grid-cols-2">
        <div>
          <SectionTitle right={<Farol cond={indAging.condicao} nota={indAging.nota} />}>Envelhecimento do saldo</SectionTitle>
          <Card className="p-4">
            {!aging.length ? (
              <EmptyState title="Nada a receber em aberto" icon="check" />
            ) : (
              <>
                <div className="flex h-2.5 rounded-[var(--r-pill)] overflow-hidden bg-[var(--surface-4)]" role="img" aria-label="Distribuição do saldo a receber por faixa de atraso">
                  {aging.map((f) => (
                    <div
                      key={f.bucket}
                      title={`${AGING_META[f.bucket].label} · ${fmtBRL(f.valor)}`}
                      style={{ flexGrow: f.valor, flexBasis: 0, background: TONE_COLOR[AGING_META[f.bucket].tone] }}
                    />
                  ))}
                </div>
                <div className="mt-3 space-y-0.5">
                  {aging.map((f) => (
                    <div key={f.bucket} className="flex items-center gap-2 px-1.5 py-1 min-w-0">
                      <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: TONE_COLOR[AGING_META[f.bucket].tone] }} />
                      <span className="text-[11px] text-[var(--fg-2)] truncate">{AGING_META[f.bucket].label}</span>
                      <span className="ml-auto text-[11px] tabular text-[var(--fg-3)] shrink-0">{f.alunos} {f.alunos === 1 ? 'aluno' : 'alunos'}</span>
                      <span className="text-[11px] font-semibold tabular text-[var(--fg)] shrink-0 w-20 text-right">{fmtBRL(f.valor)}</span>
                    </div>
                  ))}
                </div>
              </>
            )}
          </Card>
        </div>

        <div>
          <SectionTitle>Saúde da carteira</SectionTitle>
          <Card className="p-4">
            <div className="flex h-2.5 rounded-[var(--r-pill)] overflow-hidden bg-[var(--surface-4)]" role="img" aria-label="Distribuição dos alunos por status">
              {vivos.map((f) => (
                <div
                  key={f.chave}
                  title={`${statusLabel(f.chave)} · ${f.alunos}`}
                  style={{ flexGrow: f.alunos, flexBasis: 0, background: TONE_COLOR[statusTone(f.chave)] }}
                />
              ))}
            </div>
            <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-0.5">
              {vivos.map((f) => <LegendaStatus key={f.chave} chave={f.chave} alunos={f.alunos} onClick={onDrillStatus} />)}
              {mortos.map((f) => <LegendaStatus key={f.chave} chave={f.chave} alunos={f.alunos} onClick={onDrillStatus} morta />)}
            </div>
          </Card>
        </div>
      </div>

      {/* Bloco 5 — fazer agora */}
      <div>
        <SectionTitle>Fazer agora</SectionTitle>
        <div className="grid gap-3 sm:grid-cols-3">
          {acoes.map((a) => {
            const vazio = a.n === 0;
            return (
              <button
                key={a.g}
                type="button"
                disabled={vazio}
                onClick={() => onDrill(a.g)}
                className={`text-left rounded-[var(--r-lg)] border bg-[var(--surface-2)] shadow-[var(--shadow-sm)] p-3.5 transition-colors ${vazio ? 'opacity-50 cursor-default border-[var(--border)]' : 'border-[var(--border)] hover:border-[var(--border-strong)] cursor-pointer'}`}
                style={{ borderTopWidth: 3, borderTopColor: vazio ? 'var(--border)' : a.color }}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-2xl font-bold tabular leading-none text-[var(--fg)]">
                      {vazio ? <Icon name="check" size={22} className="text-[var(--green)]" /> : a.n.toLocaleString('pt-BR')}
                    </div>
                    <div className="mt-1.5 text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-2)]">{a.label}</div>
                    <div className="mt-0.5 text-[10px] text-[var(--fg-3)] truncate">{vazio ? 'nada aqui' : a.sub}</div>
                  </div>
                  <span
                    className="grid place-items-center w-7 h-7 rounded-[var(--r-md)] shrink-0"
                    style={{ background: `color-mix(in srgb, ${a.color} 14%, transparent)`, color: a.color }}
                  >
                    <Icon name={a.icon} size={15} />
                  </span>
                </div>
                {!vazio && (
                  <div className="mt-2.5 text-[10px] font-semibold" style={{ color: a.color }}>{a.hint} →</div>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Bloco 6 — a receber por canal */}
      <div>
        <SectionTitle>A receber por canal</SectionTitle>
        <Card className="p-4">
        {canais.length === 0 ? (
          <EmptyState title="Nenhuma conta nesta turma" icon="inbox" />
        ) : (
          <div className="space-y-2.5">
            {canais.map((f) => (
              <div key={f.chave} className="min-w-0">
                <div className="flex items-baseline justify-between gap-3">
                  <span className="text-[13px] text-[var(--fg-2)] truncate">{f.chave}</span>
                  <span className="text-[13px] font-semibold tabular text-[var(--fg)] shrink-0">{fmtBRL(f.aReceber)}</span>
                </div>
                <div className="flex items-center gap-2 mt-1">
                  <div className="flex-1 h-1.5 rounded-[var(--r-pill)] bg-[var(--surface-4)] overflow-hidden">
                    <div className="h-full rounded-[var(--r-pill)] bg-[var(--accent)]" style={{ width: `${(f.aReceber / maxCanal) * 100}%` }} />
                  </div>
                  <span className="text-[10px] text-[var(--fg-3)] tabular shrink-0 w-14 text-right">{f.alunos} {f.alunos === 1 ? 'aluno' : 'alunos'}</span>
                </div>
              </div>
            ))}
          </div>
        )}
        </Card>
      </div>
    </div>
  );
}

/** Farol de condição acessível: dot/ícone colorido + rótulo em texto — nunca cor sozinha. */
function Farol({ cond, nota, comIcone = false }: { cond: Condicao; nota?: string; comIcone?: boolean }) {
  const m = CONDICAO_META[cond];
  const cor = condCor(cond);
  return (
    <span className="inline-flex items-center gap-1.5 shrink-0" title={nota}>
      {comIcone
        ? <Icon name={m.icon} size={12} style={{ color: cor }} />
        : <span className="w-2 h-2 rounded-full" style={{ background: cor }} aria-hidden />}
      <span className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">{m.label}</span>
    </span>
  );
}

/** Onde mora o alvo na barra do bullet — sobra respiro à direita p/ o traço não colar na borda. */
const ALVO_POS = 86;

/** Bullet meta vs realizado: barra na cor da condição + traço do alvo + farol. */
function BulletMeta({ label, realizado, alvo, ind }: {
  label: string; realizado: string; alvo: string; ind: Indicador;
}) {
  const cor = condCor(ind.condicao);
  // ind.pct = % da meta atingida (cap 100). O alvo mora em ALVO_POS% da largura.
  const fill = ((ind.pct ?? 0) / 100) * ALVO_POS;
  return (
    <div className="min-w-0">
      <div className="flex items-baseline justify-between gap-3 flex-wrap">
        <span className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">{label}</span>
        <span className="text-[11px] tabular text-[var(--fg-3)]">
          <span className="text-[13px] font-bold text-[var(--fg)]">{realizado}</span>
          {' '}/ {alvo} · {ind.pct ?? 0}% da meta
        </span>
      </div>
      <div className="mt-1.5 flex items-center gap-2.5">
        <div
          className="relative flex-1 h-2 rounded-[var(--r-pill)] bg-[var(--surface-4)]"
          role="img"
          aria-label={`${label}: ${ind.nota}`}
        >
          <div className="absolute inset-y-0 left-0 rounded-[var(--r-pill)]" style={{ width: `${fill}%`, background: cor }} />
          <div className="absolute -top-0.5 -bottom-0.5 w-0.5 rounded bg-[var(--fg-2)]" style={{ left: `${ALVO_POS}%` }} title={alvo} />
        </div>
        <Farol cond={ind.condicao} nota={ind.nota} comIcone />
      </div>
    </div>
  );
}

/** Card do pulso: "entrou hoje" + seta de tendência (3 dias vs 3 anteriores) + sparkline. */
function PulsoCaixa({ pulso, hojeISO }: { pulso: DiaFaturamento[]; hojeISO: string }) {
  const brutos = pulso.map((d) => d.bruto);
  const entrouHoje = pulso.find((d) => d.dia === hojeISO)?.bruto ?? 0;
  const media = brutos.length ? brutos.reduce((a, b) => a + b, 0) / brutos.length : 0;

  // Tendência: média dos últimos 3 dias vs a dos 3 anteriores. Precisa de 6 pontos.
  let delta: number | null = null;
  let sobe = false;
  if (brutos.length >= 6) {
    const m = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
    const rec = m(brutos.slice(-3));
    const ant = m(brutos.slice(-6, -3));
    sobe = rec >= ant;
    if (ant > 0) delta = ((rec - ant) / ant) * 100;
  }

  return (
    <>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Entrou hoje</div>
          <div className="mt-0.5 text-[18px] font-bold tabular leading-none text-[var(--fg)] break-words">{fmtBRL(entrouHoje)}</div>
        </div>
        {delta != null && (
          <span className="inline-flex items-center gap-1 shrink-0" title="média dos últimos 3 dias vs os 3 anteriores">
            <Icon name={sobe ? 'arrow-up' : 'arrow-down'} size={13} style={{ color: sobe ? 'var(--green)' : 'var(--red)' }} />
            <span className="text-[11px] font-semibold tabular text-[var(--fg-2)]">
              {sobe ? '+' : '−'}{Math.abs(delta).toFixed(0)}%
            </span>
          </span>
        )}
      </div>
      <div className="mt-2 flex-1 flex items-end">
        {brutos.length >= 2 ? (
          <Sparkline valores={brutos} />
        ) : (
          <span className="text-[11px] text-[var(--fg-3)]">Ainda sem série de faturamento suficiente.</span>
        )}
      </div>
      {brutos.length > 0 && (
        <div className="mt-1.5 text-[10px] tabular text-[var(--fg-3)]">
          últimos {brutos.length} {brutos.length === 1 ? 'dia' : 'dias'} com lançamento · média {fmtBRL(media)}/dia
        </div>
      )}
    </>
  );
}

/** Sparkline puro: linha 2px + área sutil + ponto final marcado. Sem eixos nem grid — é pulso, não gráfico. */
function Sparkline({ valores, cor = 'var(--accent)', altura = 44 }: { valores: number[]; cor?: string; altura?: number }) {
  const W = 240, H = 44, PAD = 5;
  const min = Math.min(...valores);
  const max = Math.max(...valores);
  const span = max - min || 1;
  const px = (i: number) => PAD + (i * (W - 2 * PAD)) / (valores.length - 1);
  const py = (v: number) => PAD + (1 - (v - min) / span) * (H - 2 * PAD);
  const pontos = valores.map((v, i) => `${px(i).toFixed(1)} ${py(v).toFixed(1)}`);
  const linha = `M${pontos.join(' L')}`;
  const area = `${linha} L${px(valores.length - 1).toFixed(1)} ${H} L${PAD} ${H} Z`;
  const fimX = px(valores.length - 1).toFixed(1);
  const fimY = py(valores[valores.length - 1]).toFixed(1);
  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      style={{ width: '100%', height: altura, display: 'block' }}
      role="img"
      aria-label="Faturamento bruto por dia — tendência recente"
    >
      <path d={area} fill={cor} opacity={0.08} stroke="none" />
      <path d={linha} fill="none" stroke={cor} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
      {/* Ponto final: traço de comprimento ~0 com cap redondo — círculo perfeito mesmo com o SVG esticado. */}
      <path d={`M${fimX} ${fimY} l0.01 0`} stroke={cor} strokeWidth={6} strokeLinecap="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

/** Mini-KPI da previsão: rótulo pequeno + valor compacto colorido. */
function MiniPrevisao({ label, valor, cor }: { label: string; valor: number; cor: string }) {
  return (
    <div className="min-w-0">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)] truncate">{label}</div>
      <div className="mt-0.5 text-[15px] font-bold tabular leading-tight break-words" style={{ color: valor > 0 ? cor : 'var(--fg-3)' }}>
        {fmtBRL(valor)}
      </div>
    </div>
  );
}

/** Item da legenda da barra empilhada: bolinha, label curto, contagem. */
function LegendaStatus({ chave, alunos, onClick, morta = false }: {
  chave: string; alunos: number; onClick?: (s: string) => void; morta?: boolean;
}) {
  const clicavel = Boolean(onClick);
  return (
    <button
      type="button"
      disabled={!clicavel}
      onClick={() => onClick?.(chave)}
      className={`flex items-center gap-2 rounded-[var(--r-sm)] px-1.5 py-1 text-left min-w-0 transition-colors ${morta ? 'opacity-45' : ''} ${clicavel ? 'hover:bg-[var(--surface-3)] cursor-pointer' : 'cursor-default'}`}
    >
      <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: TONE_COLOR[statusTone(chave)] }} />
      <span className="text-[11px] text-[var(--fg-2)] truncate">{statusLabel(chave)}</span>
      <span className="ml-auto text-[11px] font-semibold tabular text-[var(--fg)] shrink-0">{alunos}</span>
    </button>
  );
}
