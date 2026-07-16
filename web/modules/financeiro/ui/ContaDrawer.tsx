'use client';

import { useEffect, useMemo, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { Cobranca, CompraHistorico, ContaReceber, Lancamento, ReguaPasso } from '../domain/types';
import { ehReserva, mascararDoc, saldoEfetivo, statusLabel, statusTone } from '../domain/financeiro';
import { proximaAcao } from '../domain/cobranca';
import { loadCobrancas, loadComprasAluno, loadExtrato, registrarCobranca, salvarAcordo } from './financeiro-data';
import {
  AvatarInicial, Badge, Button, DataTable, Drawer, EmptyState, FilterSelect, Input, Loading,
  ProgressBar, Row, Tabs, Td, Th, Thead, Tr,
} from '@/shared/ui/components';
import { fmtBRL, fmtData, fmtDataHora } from '@/shared/ui/format';

type TabKey = 'resumo' | 'comercial' | 'acordo' | 'cobranca' | 'extrato' | 'compras';
type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';
type Act = (fn: () => Promise<{ ok: boolean; msg?: string }>) => Promise<void>;

const FORMAS = ['À vista', 'Parcelado', 'Boleto', 'Pix', 'Cartão'];

const CAT_TONE: Record<string, Tone> = {
  sinal: 'accent',
  saldo: 'success',
  mensalidade: 'info',
  compra_cheia: 'warning',
};
const catLabel = (c: string) => {
  const s = c.replace(/_/g, ' ');
  return s.charAt(0).toUpperCase() + s.slice(1);
};

export function ContaDrawer({ conta: c, regua, canEdit, canVerDoc, onClose, act, initialTab = 'resumo' }: {
  conta: ContaReceber;
  regua: ReguaPasso[];
  canEdit: boolean;
  canVerDoc: boolean;
  onClose: () => void;
  act: Act;
  /** Aba inicial — a fila do dia abre direto em "Cobrança". */
  initialTab?: TabKey;
}) {
  const [tab, setTab] = useState<TabKey>(initialTab);
  const cancelada = c.status_financeiro === 'cancelado' || c.status_financeiro === 'reembolsado' || c.status_financeiro === 'cancelamento_solicitado';

  return (
    <Drawer
      width="max-w-3xl"
      onClose={onClose}
      avatar={<AvatarInicial nome={c.nome} />}
      title={c.nome || '—'}
      subtitle={c.email}
      badges={
        <>
          <Badge tone="accent">{c.produto}</Badge>
          <Badge tone="neutral">{c.canal}</Badge>
          <Badge tone={statusTone(c.status_financeiro)} dot>{statusLabel(c.status_financeiro)}</Badge>
          {/* Reserva de vaga: pagou só o sinal — ainda não é aluno em pagamento. */}
          {ehReserva(c) && !cancelada && <Badge tone="warning">Reserva de vaga</Badge>}
        </>
      }
    >
      <Tabs
        tabs={[{ k: 'resumo', l: 'Resumo' }, { k: 'comercial', l: 'Comercial' }, { k: 'acordo', l: 'Acordo' }, { k: 'cobranca', l: 'Cobrança' }, { k: 'extrato', l: 'Extrato' }, { k: 'compras', l: 'Compras' }]}
        active={tab}
        onChange={(k) => setTab(k as TabKey)}
      />

      {tab === 'resumo' && (
        <div className="space-y-4">
          {ehReserva(c) && !cancelada && (
            <div className="rounded-[var(--r-md)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] p-3 text-sm flex items-center gap-1.5">
              <Icon name="alert" size={14} className="text-[var(--yellow)] shrink-0" />
              <span className="text-[var(--fg-2)]">
                <strong className="text-[var(--yellow)]">Reserva de vaga</strong> — só sinal pago, saldo em aberto. Pode não converter em aluno.
              </span>
            </div>
          )}
          {c.status_financeiro === 'incalculavel' && (
            <div className="rounded-[var(--r-md)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] p-3 text-sm flex items-center gap-1.5">
              <Icon name="alert" size={14} className="text-[var(--yellow)] shrink-0" />
              <span className="text-[var(--fg-2)]">
                <strong className="text-[var(--yellow)]">Saldo a calcular</strong> — aluno da base sem insumo de crédito.
              </span>
            </div>
          )}
          {cancelada && (
            <div className="rounded-[var(--r-md)] border border-[var(--red-border)] bg-[var(--red-subtle)] p-3 text-sm">
              <div className="font-semibold text-[var(--red)] flex items-center gap-1.5">
                <Icon name="alert" size={14} /> {statusLabel(c.status_financeiro)}
              </div>
              <div className="text-[var(--fg-2)] mt-1 space-y-0.5">
                {c.cancelamento_motivo && <div>Motivo: {c.cancelamento_motivo}</div>}
                {c.cancelamento_em && <div>Solicitado em: {fmtData(c.cancelamento_em)}</div>}
                {c.cancelamento_efetivado_em && <div>Efetivado em: {fmtData(c.cancelamento_efetivado_em)}</div>}
                {c.reembolso_em && <div>Reembolso: {fmtData(c.reembolso_em)}{c.reembolso_valor != null ? ` · ${fmtBRL(c.reembolso_valor)}` : ''}{c.reembolso_status ? ` · ${c.reembolso_status}` : ''}</div>}
              </div>
            </div>
          )}

          <div className="grid sm:grid-cols-2 sm:gap-x-6">
            <Row k="Turma" v={c.turma} />
            <Row k="Canal" v={c.canal} />
            <Row k="Público" v={c.publico} />
            <Row k="Estágio (ativação)" v={c.estagio_nome ? `${c.estagio_nome}${c.estagio_aba ? ` · ${c.estagio_aba}` : ''}` : null} />
            <Row k="Pacote" v={fmtBRL(c.pacote)} />
            {c.divergencia_regra != null && c.divergencia_regra !== 0 && (
              <Row
                k="Divergência da régua"
                v={
                  <span className={`font-semibold ${c.divergencia_regra > 0 ? 'text-[var(--yellow)]' : 'text-[var(--red)]'}`}>
                    {fmtBRL(c.divergencia_regra)} · {c.divergencia_regra > 0 ? 'cobrando a mais' : 'dinheiro na mesa'}
                  </span>
                }
              />
            )}
            <Row
              k="Sinal"
              v={c.sinal_bruto != null
                ? [fmtBRL(c.sinal_bruto), `líq. ${fmtBRL(c.sinal_liquido)}`, c.sinal_pago_em ? fmtData(c.sinal_pago_em) : null, c.sinal_metodo].filter(Boolean).join(' · ')
                : null}
            />
            <Row
              k="Saldo pago"
              v={c.saldo_pago_bruto > 0
                ? `${fmtBRL(c.saldo_pago_bruto)} · líq. ${fmtBRL(c.saldo_pago_liquido)} · ${c.saldo_lancamentos} ${c.saldo_lancamentos === 1 ? 'lançamento' : 'lançamentos'}`
                : '—'}
            />
            <Row
              k="Saldo a pagar"
              v={
                // saldoEfetivo: resíduo de centavos das 12x (< R$ 1) não aparece como dívida.
                <span className={c.status_financeiro === 'vencido' ? 'text-[var(--red)] font-semibold' : undefined}>
                  {c.saldo_a_pagar == null ? fmtBRL(null) : fmtBRL(saldoEfetivo(c))}
                </span>
              }
            />
            {c.credito != null && c.credito > 0 && <Row k="Crédito (pró-rata)" v={fmtBRL(c.credito)} />}
            <Row
              k="% pago"
              v={
                <span className="inline-flex items-center gap-2 w-40">
                  <ProgressBar value={c.pago_pct ?? 0} tone={c.pago_pct != null && c.pago_pct >= 100 ? 'green' : 'accent'} showLabel />
                </span>
              }
            />
            <Row
              k="Parcelas"
              v={c.parcelas_contratadas != null
                ? `${c.parcelas_pagas ?? 0}/${c.parcelas_contratadas}${c.valor_parcela != null ? ` · ${fmtBRL(c.valor_parcela)} cada` : ''}`
                : null}
            />
            <Row k="Último pagamento" v={c.ultimo_pagamento_em ? fmtData(c.ultimo_pagamento_em) : null} />
            <Row k="Documento" v={mascararDoc(c.documento, canVerDoc)} />
            <Row k="Telefone" v={c.telefone} />
          </div>
        </div>
      )}

      {tab === 'comercial' && <ComercialTab c={c} />}

      {tab === 'acordo' && <AcordoTab c={c} canEdit={canEdit} act={act} />}

      {tab === 'cobranca' && <CobrancaTab c={c} regua={regua} canEdit={canEdit} act={act} />}

      {tab === 'extrato' && <ExtratoTab compradorId={c.comprador_id} />}

      {tab === 'compras' && <ComprasTab compradorId={c.comprador_id} />}
    </Drawer>
  );
}

// ── Comercial (espelho read-only do card da ativação) ────────────────────────

const REUNIAO_TONE: Record<string, Tone> = {
  'Realizada/pago': 'success',
  Realizada: 'info',
  Agendada: 'accent',
  'Aguardando retorno': 'warning',
};

function ComercialTab({ c }: { c: ContaReceber }) {
  const estagio = c.estagio_nome ? `${c.estagio_nome}${c.estagio_aba ? ` · ${c.estagio_aba}` : ''}` : null;
  const reuniao = c.reuniao_em || c.reuniao_resultado
    ? [c.reuniao_em ? fmtDataHora(c.reuniao_em) : null, c.reuniao_resultado].filter(Boolean).join(' · ')
    : null;
  const entrevista = c.entrevista_em || c.entrevista_resultado
    ? [c.entrevista_em ? fmtDataHora(c.entrevista_em) : null, c.entrevista_resultado].filter(Boolean).join(' · ')
    : null;
  const negociado = c.pagamento_forma
    ? [c.pagamento_forma, c.pagamento_parcelas != null ? `${c.pagamento_parcelas}x` : null, c.pagamento_meio].filter(Boolean).join(' · ')
    : null;
  const vazio = !c.vendedor && !estagio && !reuniao && !entrevista && !negociado && !c.obs_comercial;

  if (vazio) {
    return <EmptyState title="Sem dados do comercial" hint="Nada foi registrado no card da ativação para este aluno." icon="clipboard" />;
  }

  return (
    <div className="space-y-4">
      <p className="text-xs text-[var(--fg-3)]">
        O que foi combinado com o comercial — espelhado do sistema de ativação, somente leitura.
      </p>
      <div className="grid sm:grid-cols-2 sm:gap-x-6">
        <Row k="Vendedor responsável" v={c.vendedor} />
        <Row k="Estágio (kanban)" v={estagio} />
        <Row
          k="Reunião"
          v={reuniao ? (
            <span className="inline-flex flex-wrap items-center gap-2">
              {c.reuniao_em && <span className="tabular">{fmtDataHora(c.reuniao_em)}</span>}
              {c.reuniao_resultado && <Badge tone={REUNIAO_TONE[c.reuniao_resultado] ?? 'neutral'}>{c.reuniao_resultado}</Badge>}
            </span>
          ) : null}
        />
        <Row k="Entrevista" v={entrevista} />
        <Row k="Forma negociada" v={negociado} />
      </div>
      {c.obs_comercial && (
        <div>
          <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-1">Observações do comercial</div>
          <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3 text-sm text-[var(--fg-2)] whitespace-pre-wrap">{c.obs_comercial}</div>
        </div>
      )}
    </div>
  );
}

// ── Acordo ──────────────────────────────────────────────────────────────────

function AcordoTab({ c, canEdit, act }: { c: ContaReceber; canEdit: boolean; act: Act }) {
  const [venc, setVenc] = useState(c.vencimento ? c.vencimento.slice(0, 10) : '');
  const [forma, setForma] = useState(c.pagamento_forma ?? '');
  const [meio, setMeio] = useState(c.pagamento_meio ?? '');
  const [parcelas, setParcelas] = useState(c.pagamento_parcelas != null ? String(c.pagamento_parcelas) : '');
  const [obs, setObs] = useState(c.acordo ?? '');

  const salvar = () =>
    act(() => salvarAcordo(c.contato_hm_id, {
      vencimento: venc || null,
      acordo: obs.trim() || null,
      meio: meio.trim() || null,
      forma: forma || null,
      parcelas: parcelas.trim() ? Number(parcelas) : null,
    }));

  // Valor legado gravado fora da lista fixa continua selecionável.
  const formas = c.pagamento_forma && !FORMAS.includes(c.pagamento_forma) ? [c.pagamento_forma, ...FORMAS] : FORMAS;

  return (
    <div className="space-y-4">
      {!canEdit ? (
        <div className="grid sm:grid-cols-2 sm:gap-x-6">
          <Row k="Data de vencimento" v={c.vencimento ? fmtData(c.vencimento) : 'a combinar'} />
          <Row k="Forma" v={c.pagamento_forma} />
          <Row k="Meio" v={c.pagamento_meio} />
          <Row k="Parcelas" v={c.pagamento_parcelas != null ? String(c.pagamento_parcelas) : null} />
          <Row k="Observação do acordo" v={c.acordo} />
        </div>
      ) : (
        <div className="space-y-3">
          <div className="grid sm:grid-cols-2 gap-3">
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Data de vencimento</span>
              <Input type="date" value={venc} onChange={(e) => setVenc(e.target.value)} className="mt-1" />
            </label>
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Forma</span>
              <FilterSelect value={forma} onChange={(e) => setForma(e.target.value)} className="mt-1">
                <option value="">— sem forma —</option>
                {formas.map((f) => <option key={f} value={f}>{f}</option>)}
              </FilterSelect>
            </label>
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Meio</span>
              <Input value={meio} onChange={(e) => setMeio(e.target.value)} placeholder="Ex.: link da oferta, boleto avulso…" className="mt-1" />
            </label>
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Parcelas</span>
              <Input type="number" min={1} value={parcelas} onChange={(e) => setParcelas(e.target.value)} className="mt-1" />
            </label>
          </div>
          <label className="block">
            <span className="text-xs text-[var(--fg-3)]">Observação do acordo (o que foi combinado com o aluno)</span>
            <textarea
              value={obs}
              onChange={(e) => setObs(e.target.value)}
              rows={3}
              placeholder="Ex.: paga o saldo à vista dia 20/07 via Pix…"
              className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]"
            />
          </label>
          <Button onClick={salvar}><Icon name="check" size={14} /> Salvar acordo</Button>
        </div>
      )}

      {c.oferta_codigo && <OfertaSugerida c={c} />}
    </div>
  );
}

function OfertaSugerida({ c }: { c: ContaReceber }) {
  const [copiado, setCopiado] = useState(false);
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-2">Oferta sugerida</div>
      <div className="flex flex-wrap items-center gap-3">
        <span className="text-sm font-semibold text-[var(--fg)] tabular">{c.oferta_codigo}</span>
        <span className="text-sm text-[var(--fg-2)] tabular">{fmtBRL(c.oferta_valor)}</span>
        {c.oferta_recorrente != null && <Badge tone={c.oferta_recorrente ? 'info' : 'neutral'}>{c.oferta_recorrente ? 'Recorrente' : 'À vista'}</Badge>}
        {c.oferta_enviada_em && <span className="text-xs text-[var(--fg-3)]">enviada em {fmtData(c.oferta_enviada_em)}</span>}
        {c.oferta_link && (
          <Button
            size="sm"
            variant="subtle"
            className="ml-auto"
            onClick={() => { navigator.clipboard?.writeText(c.oferta_link!); setCopiado(true); setTimeout(() => setCopiado(false), 2000); }}
          >
            <Icon name={copiado ? 'check' : 'copy'} size={13} /> {copiado ? 'Copiado!' : 'Copiar link'}
          </Button>
        )}
      </div>
    </div>
  );
}

// ── Cobrança (régua) ────────────────────────────────────────────────────────

const CANAIS_COBRANCA = [
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'ligacao', label: 'Ligação' },
  { value: 'email', label: 'E-mail' },
  { value: 'outro', label: 'Outro' },
];
const RESULTADOS = [
  { value: 'prometeu_pagar', label: 'Prometeu pagar' },
  { value: 'sem_resposta', label: 'Sem resposta' },
  { value: 'pagou', label: 'Pagou' },
  { value: 'recusou', label: 'Recusou' },
  { value: 'remarcou', label: 'Remarcou' },
  { value: 'outro', label: 'Outro' },
];
const RESULTADO_TONE: Record<string, Tone> = {
  pagou: 'success',
  prometeu_pagar: 'info',
  remarcou: 'warning',
  recusou: 'danger',
  sem_resposta: 'neutral',
};
const canalCobrancaLabel = (v: string | null) => CANAIS_COBRANCA.find((x) => x.value === v)?.label ?? v ?? '—';
const resultadoLabel = (v: string | null) => RESULTADOS.find((x) => x.value === v)?.label ?? v ?? '—';

function CobrancaTab({ c, regua, canEdit, act }: {
  c: ContaReceber; regua: ReguaPasso[]; canEdit: boolean; act: Act;
}) {
  const hojeISO = new Date().toISOString().slice(0, 10);
  const acao = useMemo(() => proximaAcao(c, regua, hojeISO), [c, regua, hojeISO]);

  const [historico, setHistorico] = useState<Cobranca[] | null>(null);
  const [versao, setVersao] = useState(0);
  useEffect(() => {
    let vivo = true;
    loadCobrancas(c.contato_hm_id).then((cs) => { if (vivo) setHistorico(cs); });
    return () => { vivo = false; };
  }, [c.contato_hm_id, versao]);

  const [canal, setCanal] = useState('');
  const [resultado, setResultado] = useState('');
  const [obs, setObs] = useState('');
  const [salvando, setSalvando] = useState(false);

  const registrar = async () => {
    if (!canal || !resultado || salvando) return;
    setSalvando(true);
    try {
      await act(() => registrarCobranca(c.contato_hm_id, canal, resultado, obs.trim() || null));
      setObs('');
      setVersao((v) => v + 1);
    } finally {
      setSalvando(false);
    }
  };

  return (
    <div className="space-y-4">
      {/* Próxima ação segundo a régua */}
      <div className={`rounded-[var(--r-md)] border p-3 ${acao.atrasada ? 'border-[var(--red-border)] bg-[var(--red-subtle)]' : 'border-[var(--border)] bg-[var(--surface-3)]'}`}>
        <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Próxima ação</div>
        <div className="mt-1 flex flex-wrap items-center gap-2">
          <span className={`text-sm font-semibold ${acao.atrasada ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>{acao.titulo}</span>
          {acao.quando && <span className="text-xs tabular text-[var(--fg-2)]">{fmtData(acao.quando)}</span>}
          {acao.atrasada && <Badge tone="danger">atrasada</Badge>}
        </div>
      </div>
      {c.remarcacoes > 0 && (
        <div className="rounded-[var(--r-md)] border border-[var(--yellow-border)] bg-[var(--yellow-subtle)] p-3 text-sm flex items-center gap-1.5">
          <Icon name="alert" size={14} className="text-[var(--yellow)] shrink-0" />
          <span className="text-[var(--fg-2)]">
            <strong className="text-[var(--yellow)]">Promessa remarcada {c.remarcacoes}x</strong> — o vencimento já foi adiado.
          </span>
        </div>
      )}

      {/* Registrar cobrança */}
      {canEdit && (
        <div className="space-y-3">
          <div className="grid sm:grid-cols-2 gap-3">
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Canal</span>
              <FilterSelect value={canal} onChange={(e) => setCanal(e.target.value)} className="mt-1">
                <option value="">— canal —</option>
                {CANAIS_COBRANCA.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </FilterSelect>
            </label>
            <label className="block">
              <span className="text-xs text-[var(--fg-3)]">Resultado</span>
              <FilterSelect value={resultado} onChange={(e) => setResultado(e.target.value)} className="mt-1">
                <option value="">— resultado —</option>
                {RESULTADOS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </FilterSelect>
            </label>
          </div>
          <label className="block">
            <span className="text-xs text-[var(--fg-3)]">Observação</span>
            <textarea
              value={obs}
              onChange={(e) => setObs(e.target.value)}
              rows={2}
              placeholder="Ex.: prometeu pagar sexta via Pix…"
              className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]"
            />
          </label>
          <Button onClick={registrar} disabled={!canal || !resultado || salvando}>
            <Icon name="check" size={14} /> {salvando ? 'Registrando…' : 'Registrar'}
          </Button>
        </div>
      )}

      {/* Histórico */}
      <div>
        <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-1">
          Histórico de cobranças{c.cobrancas_total > 0 ? ` · ${c.cobrancas_total}` : ''}
        </div>
        {historico === null ? (
          <Loading label="Carregando histórico…" minHeight={100} />
        ) : !historico.length ? (
          <EmptyState title="Nenhuma cobrança registrada" hint="O que for registrado aqui vira a memória da régua." icon="mail" />
        ) : (
          <div className="divide-y divide-[var(--border-faint)]">
            {historico.map((h) => (
              <div key={h.id} className="py-2 flex items-start gap-3">
                <div className="text-xs tabular text-[var(--fg-3)] whitespace-nowrap w-[110px] shrink-0">{fmtDataHora(h.quando)}</div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <Badge tone={RESULTADO_TONE[h.resultado ?? ''] ?? 'neutral'}>{resultadoLabel(h.resultado)}</Badge>
                    <span className="text-[11px] text-[var(--fg-3)]">via {canalCobrancaLabel(h.canal)}</span>
                    {h.autor && <span className="text-[11px] text-[var(--fg-3)]">· {h.autor}</span>}
                  </div>
                  {h.obs && <div className="mt-0.5 text-xs text-[var(--fg-2)]">{h.obs}</div>}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Extrato ─────────────────────────────────────────────────────────────────

function ExtratoTab({ compradorId }: { compradorId: string }) {
  const [lancs, setLancs] = useState<Lancamento[] | null>(null);
  const [copiadoTx, setCopiadoTx] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    loadExtrato(compradorId).then((ls) => { if (vivo) setLancs(ls); });
    return () => { vivo = false; };
  }, [compradorId]);

  if (lancs === null) return <Loading label="Carregando extrato…" minHeight={160} />;
  if (!lancs.length) return <EmptyState title="Nenhum lançamento" hint="Nada caiu do webhook para este comprador ainda." icon="receipt" />;

  const soma = (f: (l: Lancamento) => number) => lancs.reduce((a, l) => a + f(l), 0);

  const copiarTx = (tx: string) => {
    navigator.clipboard?.writeText(tx);
    setCopiadoTx(tx);
    setTimeout(() => setCopiadoTx(null), 2000);
  };

  return (
    <div className="space-y-2">
      <p className="text-xs text-[var(--fg-3)]">
        <span className="text-[var(--fg-2)]">Taxa Hotmart</span> = bruto − líquido (retido da empresa).{' '}
        <span className="text-[var(--fg-2)]">Juros parc.</span> = juro que o aluno pagou para parcelar, não é custo da empresa.
      </p>
      <DataTable>
      <Thead>
        <Th>Data</Th>
        <Th>Categoria</Th>
        <Th>Cliente pagou</Th>
        <Th>Bruto</Th>
        <Th>Líquido</Th>
        <Th>Taxa Hotmart</Th>
        <Th>Juros parc.</Th>
        <Th>Método</Th>
        <Th>Parcela</Th>
        <Th>Transação</Th>
        <Th>Status da compra</Th>
      </Thead>
      <tbody>
        {lancs.map((l) => (
          <Tr key={l.id}>
            <Td className="text-xs text-[var(--fg-2)] tabular whitespace-nowrap">{fmtDataHora(l.pago_em)}</Td>
            <Td><Badge tone={CAT_TONE[l.categoria] ?? 'neutral'} dot>{catLabel(l.categoria)}</Badge></Td>
            <Td className="tabular text-[var(--fg-2)]">{fmtBRL(l.valor_bruto + l.juros_parcelamento)}</Td>
            <Td className="tabular text-[var(--fg)]">{fmtBRL(l.valor_bruto)}</Td>
            <Td className="tabular text-[var(--fg-2)]">{fmtBRL(l.valor_liquido)}</Td>
            <Td className="tabular text-[var(--fg-3)]">{fmtBRL(l.taxas)}</Td>
            <Td className="tabular text-[var(--fg-3)]">{l.juros_parcelamento > 0 ? fmtBRL(l.juros_parcelamento) : '—'}</Td>
            <Td className="text-xs text-[var(--fg-2)]">{l.metodo_pagamento || '—'}</Td>
            <Td className="text-xs text-[var(--fg-2)] tabular">{l.parcela != null ? `${l.parcela}ª` : '—'}</Td>
            <Td>
              {l.transacao ? (
                <button
                  type="button"
                  title="Copiar código da transação"
                  onClick={() => copiarTx(l.transacao!)}
                  className="text-xs tabular text-[var(--fg-3)] hover:text-[var(--fg)] hover:underline transition-colors"
                >
                  {copiadoTx === l.transacao ? 'Copiado!' : l.transacao}
                </button>
              ) : '—'}
            </Td>
            <Td className="text-xs text-[var(--fg-2)]">{l.compra_status || '—'}</Td>
          </Tr>
        ))}
      </tbody>
      <tfoot>
        <tr className="border-t border-[var(--border)] bg-[var(--surface-3)]">
          <td className="px-3 py-2.5 text-xs font-semibold text-[var(--fg-2)]" colSpan={2}>Total · {lancs.length} {lancs.length === 1 ? 'lançamento' : 'lançamentos'}</td>
          <td className="px-3 py-2.5 tabular font-semibold text-[var(--fg-2)]">{fmtBRL(soma((l) => l.valor_bruto + l.juros_parcelamento))}</td>
          <td className="px-3 py-2.5 tabular font-semibold text-[var(--fg)]">{fmtBRL(soma((l) => l.valor_bruto))}</td>
          <td className="px-3 py-2.5 tabular font-semibold text-[var(--fg)]">{fmtBRL(soma((l) => l.valor_liquido))}</td>
          <td className="px-3 py-2.5 tabular font-semibold text-[var(--fg-3)]">{fmtBRL(soma((l) => l.taxas))}</td>
          <td className="px-3 py-2.5 tabular font-semibold text-[var(--fg-3)]">{fmtBRL(soma((l) => l.juros_parcelamento))}</td>
          <td colSpan={4} />
        </tr>
      </tfoot>
      </DataTable>
    </div>
  );
}

// ── Compras (ciclo de vida completo na Hotmart) ─────────────────────────────

const MORTO_LABEL: Record<string, string> = {
  EXPIRED: 'Vencido',
  CANCELED: 'Cancelado',
  CANCELLED: 'Cancelado',
  REFUNDED: 'Estornado',
  CHARGEBACK: 'Chargeback',
  PROTESTED: 'Protesto',
};

function compraStatusBadge(cp: CompraHistorico): { tone: Tone; label: string } {
  if (cp.pago) return { tone: 'success', label: 'Pago' };
  if (cp.pendente) return { tone: 'warning', label: /billet|boleto/i.test(cp.metodo_pagamento ?? '') ? 'Boleto gerado' : 'Aguardando' };
  if (cp.morto) return { tone: 'danger', label: MORTO_LABEL[cp.status] ?? cp.status };
  return { tone: 'neutral', label: cp.status };
}

function ComprasTab({ compradorId }: { compradorId: string }) {
  const [compras, setCompras] = useState<CompraHistorico[] | null>(null);
  const [copiadoTx, setCopiadoTx] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    loadComprasAluno(compradorId).then((cs) => { if (vivo) setCompras(cs); });
    return () => { vivo = false; };
  }, [compradorId]);

  if (compras === null) return <Loading label="Carregando compras…" minHeight={160} />;
  if (!compras.length) return <EmptyState title="Nenhuma compra" hint="Nada veio da Hotmart para este comprador." icon="receipt" />;

  const copiarTx = (tx: string) => {
    navigator.clipboard?.writeText(tx);
    setCopiadoTx(tx);
    setTimeout(() => setCopiadoTx(null), 2000);
  };

  return (
    <div className="space-y-2">
      <p className="text-xs text-[var(--fg-3)]">
        Ciclo de vida de todas as compras Hotmart deste aluno — inclui boletos gerados e não pagos.
      </p>
      <DataTable>
      <Thead>
        <Th>Data</Th>
        <Th>Produto</Th>
        <Th>Status</Th>
        <Th>Método</Th>
        <Th>Parcelas</Th>
        <Th>Cliente pagou</Th>
        <Th>Bruto</Th>
        <Th>Líquido</Th>
        <Th>Transação</Th>
      </Thead>
      <tbody>
        {compras.map((cp) => {
          const st = compraStatusBadge(cp);
          return (
            <Tr key={cp.id}>
              <Td className="text-xs text-[var(--fg-2)] tabular whitespace-nowrap">{fmtDataHora(cp.pago ? cp.data_aprovacao : cp.data_compra)}</Td>
              <Td className="text-xs text-[var(--fg)]">{cp.produto_nome || '—'}</Td>
              <Td><Badge tone={st.tone} dot>{st.label}</Badge></Td>
              <Td className="text-xs text-[var(--fg-2)]">{cp.metodo_pagamento || '—'}</Td>
              <Td className="text-xs text-[var(--fg-2)] tabular">{cp.parcelas != null ? `${cp.parcelas}x` : '—'}</Td>
              <Td className="tabular text-[var(--fg-2)]">{fmtBRL(cp.cliente_pagou)}</Td>
              <Td className="tabular text-[var(--fg)]">{fmtBRL(cp.bruto)}</Td>
              <Td className="tabular text-[var(--fg-2)]">{fmtBRL(cp.valor_liquido)}</Td>
              <Td>
                {cp.transacao ? (
                  <button
                    type="button"
                    title="Copiar código da transação"
                    onClick={() => copiarTx(cp.transacao)}
                    className="text-xs tabular text-[var(--fg-3)] hover:text-[var(--fg)] hover:underline transition-colors"
                  >
                    {copiadoTx === cp.transacao ? 'Copiado!' : cp.transacao}
                  </button>
                ) : '—'}
              </Td>
            </Tr>
          );
        })}
      </tbody>
      </DataTable>
    </div>
  );
}
