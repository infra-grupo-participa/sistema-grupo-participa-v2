'use client';

import { memo, useCallback, useDeferredValue, useEffect, useMemo, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { ContaReceber, DiaFaturamento, Meta, Oferta, ReguaPasso, TurmaFin } from '../domain/types';
import {
  FILTROS_VAZIOS, STATUS_ORDEM, contaMorta, ehReserva, filtrar, formaPagamentoLabel, resumir,
  saldoEfetivo, statusLabel, type Filtros,
} from '../domain/financeiro';
import { precisaAcao } from '../domain/cobranca';
import * as data from './financeiro-data';
import { FinanceiroDashboard } from './FinanceiroDashboard';
import { FaturamentoDiario } from './FaturamentoDiario';
import { FilaCobranca } from './FilaCobranca';
import { ConfiguracoesFinanceiro } from './ConfiguracoesFinanceiro';
import { SaudeFinanceiro } from './SaudeFinanceiro';
import { ContaDrawer } from './ContaDrawer';
import { exportarExcelFinanceiro } from './financeiro-export';
import {
  Badge, Button, Checkbox, DataTable, EmptyState, Loading, MultiSelect, ProgressBar,
  SearchInput, SectionCard, SkeletonRows, Td, Th, Thead, Toast, Toolbar, Tr, useFlash,
} from '@/shared/ui/components';
import { fmtBRL, fmtBRLc, fmtData, fmtDesde } from '@/shared/ui/format';

type Tab = 'dashboard' | 'contas' | 'cobranca' | 'ofertas' | 'faturamento' | 'config';
type Gaveta = Filtros['gaveta'];

/** Gavetas da fila — os cards de KPI são o próprio seletor (padrão do piloto Placas). */
const GAVETAS: { key: Gaveta; label: string; icon: string; tone: string }[] = [
  { key: 'todos', label: 'Todos', icon: 'users', tone: 'var(--fg-2)' },
  { key: 'vencido', label: 'Vencido', icon: 'alert', tone: 'var(--red)' },
  { key: 'sem_acordo', label: 'Sem acordo', icon: 'clipboard', tone: 'var(--fg-3)' },
  { key: 'incalculavel', label: 'A calcular', icon: 'notebook', tone: 'var(--yellow)' },
  { key: 'a_receber', label: 'A receber', icon: 'trending-up', tone: 'var(--accent)' },
  { key: 'quitado', label: 'Quitado', icon: 'check', tone: 'var(--green)' },
  { key: 'pediu_cancelamento', label: 'Pediu cancelamento', icon: 'logout', tone: 'var(--yellow)' },
  { key: 'cancelado', label: 'Cancelado', icon: 'x', tone: 'var(--red)' },
];

const SEM_CONTAS: ContaReceber[] = [];
const SEM_DIAS: DiaFaturamento[] = [];

export function FinanceiroClient({ canEdit, canVerDoc }: { canEdit: boolean; canVerDoc: boolean }) {
  const [tab, setTab] = useState<Tab>('dashboard');
  // Contas carimbadas com a turma de origem: `loading` é derivado (carga ≠ turma
  // selecionada), sem setState síncrono em efeito.
  const [carga, setCarga] = useState<{ turma: string | null; contas: ContaReceber[] } | null>(null);
  const [cargaFat, setCargaFat] = useState<{ turma: string | null; dias: DiaFaturamento[] } | null>(null);
  const [turmas, setTurmas] = useState<TurmaFin[]>([]);
  const [ofertas, setOfertas] = useState<Oferta[]>([]);
  const [metas, setMetas] = useState<Meta[]>([]);
  const [turma, setTurma] = useState<string | null>(null);
  // Só carrega contas depois de saber qual é a turma atual (evita carga dupla no mount).
  const [pronto, setPronto] = useState(false);
  const contas = carga && carga.turma === turma ? carga.contas : SEM_CONTAS;
  const loading = !pronto || !carga || carga.turma !== turma;
  const dias = cargaFat && cargaFat.turma === turma ? cargaFat.dias : SEM_DIAS;
  const loadingFat = !pronto || !cargaFat || cargaFat.turma !== turma;
  const [filtros, setFiltros] = useState<Filtros>(FILTROS_VAZIOS);
  const [q, setQ] = useState('');
  // "Só fila": recorte extra sobre a tabela — depende da régua, não cabe no filtrar() puro.
  const [soFila, setSoFila] = useState(false);
  // Recorte de reservas de vaga (só sinal pago) — quem quer ver só aluno de fato oculta.
  const [semReservas, setSemReservas] = useState(false);
  const [regua, setRegua] = useState<ReguaPasso[]>([]);
  const [openId, setOpenId] = useState<string | null>(null);
  // Aba inicial do drawer: a fila do dia abre direto em "Cobrança".
  const [drawerTab, setDrawerTab] = useState<'resumo' | 'cobranca'>('resumo');
  const { toast, flash } = useFlash();

  useEffect(() => {
    (async () => {
      const [ts, ofs, rg, ms] = await Promise.all([data.loadTurmas(), data.loadOfertas(), data.loadRegua(), data.loadMetas()]);
      setTurmas(ts);
      setOfertas(ofs);
      setRegua(rg);
      setMetas(ms);
      // Padrão = TODAS as turmas reunidas. Aluno de turma antiga (T23–T34) que paga
      // agora não pode sumir por trás do filtro da turma atual. Filtra-se depois se quiser.
      setTurma(null);
      setPronto(true);
    })();
    // A sidebar dispara 'hashchange' nativo ao trocar de aba na mesma rota (ver Sidebar.tsx),
    // então basta escutar hashchange/popstate + ler o hash no mount.
    const applyHash = () => {
      const h = window.location.hash.replace('#', '');
      if (h === 'contas-a-receber') setTab('contas');
      else if (h === 'cobranca') setTab('cobranca');
      else if (h === 'ofertas') setTab('ofertas');
      else if (h === 'faturamento') setTab('faturamento');
      else if (h === 'configuracoes') setTab('config');
      else setTab('dashboard');
    };
    applyHash();
    window.addEventListener('hashchange', applyHash);
    window.addEventListener('popstate', applyHash);
    return () => {
      window.removeEventListener('hashchange', applyHash);
      window.removeEventListener('popstate', applyHash);
    };
  }, []);

  useEffect(() => {
    if (!pronto) return;
    let vivo = true;
    data.loadContas(turma).then((cs) => { if (vivo) setCarga({ turma, contas: cs }); });
    data.loadFaturamento(turma).then((ds) => { if (vivo) setCargaFat({ turma, dias: ds }); });
    return () => { vivo = false; };
  }, [turma, pronto]);

  const reload = useCallback(async () => {
    setCarga({ turma, contas: await data.loadContas(turma) });
  }, [turma]);

  const act = useCallback(async (fn: () => Promise<{ ok: boolean; msg?: string }>) => {
    const r = await fn();
    flash(r.msg || (r.ok ? 'Feito!' : 'Falhou.'));
    await reload();
  }, [reload, flash]);

  const irPara = (hash: string) => { window.location.hash = hash; };

  const hojeISO = new Date().toISOString().slice(0, 10);
  // Contas que a régua manda agir hoje — alimenta a gaveta "Cobrar hoje" e a fila.
  const filaSet = useMemo(
    () => new Set(contas.filter((c) => precisaAcao(c, regua, hojeISO)).map((c) => c.contato_hm_id)),
    [contas, regua, hojeISO],
  );
  const filaValor = useMemo(
    () => contas.reduce((a, c) => a + (filaSet.has(c.contato_hm_id) ? saldoEfetivo(c) : 0), 0),
    [contas, filaSet],
  );

  const metaAtual = useMemo(() => metas.find((m) => m.turma === turma) ?? null, [metas, turma]);

  const resumo = useMemo(() => resumir(contas), [contas]);
  const counts = useMemo(() => ({
    todos: contas.length,
    vencido: contas.filter((c) => c.status_financeiro === 'vencido').length,
    sem_acordo: resumo.semAcordo,
    incalculavel: resumo.incalculavel,
    a_receber: contas.filter((c) => saldoEfetivo(c) > 0 && !contaMorta(c)).length,
    quitado: resumo.quitados,
    pediu_cancelamento: resumo.pediuCancelamento,
    cancelado: resumo.cancelados,
  }), [contas, resumo]);
  const gavetaHint: Record<Gaveta, string> = {
    todos: turma ? `turma ${turma}` : 'todas as turmas',
    vencido: `${fmtBRL(resumo.vencido)} em atraso`,
    sem_acordo: 'sem data combinada — agir',
    incalculavel: 'sem insumo — descobrir o valor',
    a_receber: `${fmtBRL(resumo.aReceber)} a perseguir`,
    quitado: 'pacote 100% pago',
    pediu_cancelamento: 'caiu no kanban de cancelamento',
    cancelado: 'cancelado ou reembolsado',
  };

  const canalOpts = useMemo(
    () => Array.from(new Set(contas.map((c) => c.canal).filter(Boolean))).sort((a, b) => a.localeCompare(b, 'pt-BR')),
    [contas],
  );
  const produtoOpts = useMemo(
    () => Array.from(new Set(contas.map((c) => c.produto).filter(Boolean))).sort((a, b) => a.localeCompare(b, 'pt-BR')),
    [contas],
  );

  type SortCol = 'nome' | 'canal' | 'sinal_pago_em' | 'total_pago_bruto' | 'saldo_a_pagar' | 'ultimo_pagamento_em';
  const [sortCol, setSortCol] = useState<SortCol | null>(null);
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const sortBtn = (col: SortCol) => () => {
    if (sortCol === col) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    else { setSortCol(col); setSortDir('asc'); }
  };

  // Busca adiada: digitar não trava a renderização da tabela.
  const dq = useDeferredValue(q);
  const visiveis = useMemo(() => {
    let lista = filtrar(contas, { ...filtros, termo: dq });
    if (soFila) lista = lista.filter((c) => filaSet.has(c.contato_hm_id));
    if (semReservas) lista = lista.filter((c) => !ehReserva(c));
    if (!sortCol) return lista;
    const dir = sortDir === 'asc' ? 1 : -1;
    return [...lista].sort((a, b) => {
      if (sortCol === 'nome') return dir * a.nome.localeCompare(b.nome, 'pt-BR');
      if (sortCol === 'canal') return dir * a.canal.localeCompare(b.canal, 'pt-BR');
      // Datas nulas sempre no fim, independente da direção.
      if (sortCol === 'sinal_pago_em') return dir * String(a.sinal_pago_em ?? '9999').localeCompare(String(b.sinal_pago_em ?? '9999'));
      if (sortCol === 'ultimo_pagamento_em') return dir * String(a.ultimo_pagamento_em ?? '9999').localeCompare(String(b.ultimo_pagamento_em ?? '9999'));
      if (sortCol === 'total_pago_bruto') return dir * ((a.total_pago_bruto ?? -1) - (b.total_pago_bruto ?? -1));
      return dir * ((a.saldo_a_pagar ?? -1) - (b.saldo_a_pagar ?? -1));
    });
  }, [contas, filtros, dq, sortCol, sortDir, soFila, filaSet, semReservas]);

  const temFiltro = filtros.status.length > 0 || filtros.canais.length > 0 || filtros.produtos.length > 0 || filtros.gaveta !== 'todos' || dq.trim().length > 0 || soFila || semReservas;
  const aberta = openId ? contas.find((c) => c.contato_hm_id === openId) ?? null : null;

  const [exportando, setExportando] = useState(false);
  const exportar = useCallback(async () => {
    setExportando(true);
    try {
      // Exporta exatamente o recorte visível: gaveta + filtros + busca + ordenação.
      const n = await exportarExcelFinanceiro(visiveis, turma, canVerDoc);
      flash(n ? `${n} ${n === 1 ? 'conta exportada' : 'contas exportadas'}.` : 'Nenhuma conta na lista para exportar.');
    } catch {
      flash('Não foi possível gerar a planilha.');
    } finally {
      setExportando(false);
    }
  }, [visiveis, turma, canVerDoc, flash]);

  const ofertasOrdenadas = useMemo(() => [...ofertas].sort((a, b) => (b.valor ?? 0) - (a.valor ?? 0)), [ofertas]);
  const turmaAtual = turmas.find((t) => t.turma === turma);
  const nomesTurmas = useMemo(() => turmas.map((t) => t.turma), [turmas]);

  return (
    <div>
      <div className="flex items-start justify-between gap-3 flex-wrap mb-1">
        <h1 className="text-2xl font-bold text-[var(--fg)]">
          {tab === 'dashboard' ? (
            <>Dashboard <span className="text-[var(--accent)]">Financeiro</span></>
          ) : tab === 'contas' ? (
            <>
              Contas a <span className="text-[var(--accent)]">Receber</span>
              <span className="ml-2 align-middle text-xs font-semibold rounded-[var(--r-pill)] bg-[var(--accent-subtle)] text-[var(--accent)] px-2 py-0.5 tabular">{contas.length}</span>
            </>
          ) : tab === 'cobranca' ? (
            <>Fila de <span className="text-[var(--accent)]">Cobrança</span></>
          ) : tab === 'faturamento' ? (
            <>Faturamento <span className="text-[var(--accent)]">Diário</span></>
          ) : tab === 'config' ? (
            <>Configurações do <span className="text-[var(--accent)]">Financeiro</span></>
          ) : (
            <>Mapa de <span className="text-[var(--accent)]">Ofertas</span></>
          )}
        </h1>
        <div className="flex items-center gap-2">
          {tab === 'contas' && (
            <Button variant="ghost" size="sm" onClick={exportar} disabled={exportando || !visiveis.length} title="Exportar a lista visível (.xlsx)">
              <Icon name="download" size={14} /> {exportando ? 'Gerando…' : 'Exportar Excel'}
            </Button>
          )}
          {/* Sem filtro de turma: contas/faturamento sempre mostram TODAS as turmas
              reunidas (turma = null). Segmentação por turma vive só no Config (metas). */}
        </div>
      </div>
      <p className="text-sm text-[var(--fg-3)] mb-4">
        {tab === 'faturamento'
          ? 'Regime de caixa — o que entrou por dia de pagamento'
          : tab === 'cobranca'
          ? 'A fila de trabalho do dia — o que a régua de cobrança manda fazer agora'
          : tab === 'config'
          ? 'Metas por turma e régua de cobrança — o controle do seu jeito'
          : 'Sinal pago na Hotmart + saldo do pacote combinado com o financeiro'}
        {tab !== 'config' && turmaAtual ? ` · turma ${turmaAtual.turma} (${turmaAtual.alunos} alunos)` : ''}
      </p>

      {tab === 'dashboard' ? (
        <FinanceiroDashboard
          contas={contas}
          dias={dias}
          meta={metaAtual}
          loading={loading}
          onDrill={(g) => { setFiltros({ ...FILTROS_VAZIOS, gaveta: g }); setQ(''); irPara('#contas-a-receber'); }}
          onDrillStatus={(s) => { setFiltros({ ...FILTROS_VAZIOS, status: [s] }); setQ(''); irPara('#contas-a-receber'); }}
        />
      ) : tab === 'faturamento' ? (
        <FaturamentoDiario dias={dias} loading={loadingFat} turma={turma} />
      ) : tab === 'cobranca' ? (
        <FilaCobranca
          contas={contas}
          regua={regua}
          loading={loading}
          onAbrir={(id) => { setDrawerTab('cobranca'); setOpenId(id); }}
        />
      ) : tab === 'config' ? (
        <>
          <ConfiguracoesFinanceiro canEdit={canEdit} turmas={nomesTurmas} onReguaSalva={setRegua} />
          <SaudeFinanceiro />
        </>
      ) : tab === 'contas' ? (
        <>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 xl:grid-cols-9 gap-2.5 mb-4" role="tablist" aria-label="Gavetas de contas">
            {GAVETAS.map((g) => (
              <QueueCard
                key={g.key}
                label={g.label}
                hint={gavetaHint[g.key]}
                icon={g.icon}
                tone={g.tone}
                value={counts[g.key]}
                active={filtros.gaveta === g.key && !soFila}
                onClick={() => { setSoFila(false); setFiltros((f) => ({ ...f, gaveta: g.key })); }}
              />
            ))}
            {/* Recorte pela régua: o que exige ação hoje. Ortogonal às gavetas de status. */}
            <QueueCard
              label="Cobrar hoje"
              hint={filaSet.size ? `${fmtBRL(filaValor)} na fila` : 'régua em dia'}
              icon="mail"
              tone="var(--purple)"
              value={filaSet.size}
              active={soFila}
              onClick={() => { setFiltros((f) => ({ ...f, gaveta: 'todos' })); setSoFila((s) => !s); }}
            />
          </div>

          <Toolbar className="mb-3">
            <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar nome, e-mail, telefone, acordo…" />
            <MultiSelect
              values={filtros.status}
              onChange={(v) => setFiltros((f) => ({ ...f, status: v }))}
              placeholder="Todos os status"
              options={STATUS_ORDEM.map((s) => ({ value: s, label: statusLabel(s) }))}
            />
            <MultiSelect
              values={filtros.canais}
              onChange={(v) => setFiltros((f) => ({ ...f, canais: v }))}
              placeholder="Todos os canais"
              options={canalOpts.map((c) => ({ value: c, label: c }))}
            />
            {/* Filtro por produto — hoje só HM, mas pronto p/ outras fontes de receita. */}
            {produtoOpts.length > 1 && (
              <MultiSelect
                values={filtros.produtos}
                onChange={(v) => setFiltros((f) => ({ ...f, produtos: v }))}
                placeholder="Todos os produtos"
                options={produtoOpts.map((p) => ({ value: p, label: p }))}
              />
            )}
            {/* Reserva de vaga (só sinal pago) polui a visão de quem persegue saldo — dá para ocultar. */}
            <Checkbox
              checked={semReservas}
              onChange={setSemReservas}
              label={<span className="whitespace-nowrap">Ocultar reservas de vaga</span>}
            />
            {temFiltro && (
              <Button variant="ghost" size="sm" onClick={() => { setFiltros(FILTROS_VAZIOS); setQ(''); setSoFila(false); setSemReservas(false); }}>Limpar</Button>
            )}
            <span className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{visiveis.length} de {contas.length}</span>
          </Toolbar>

          {/* Layout fixo com min-width: as larguras são respeitadas e a tabela rola
              na horizontal em telas estreitas, em vez de espremer o nome do aluno. */}
          <DataTable fixed minWidth={1300}>
            <Thead>
              <Th sortable active={sortCol === 'nome'} dir={sortDir} onClick={sortBtn('nome')} className="w-[240px]">Aluno</Th>
              <Th sortable active={sortCol === 'canal'} dir={sortDir} onClick={sortBtn('canal')} className="w-[170px]">Origem</Th>
              <Th sortable active={sortCol === 'sinal_pago_em'} dir={sortDir} onClick={sortBtn('sinal_pago_em')} className="w-[95px]">Sinal pago em</Th>
              <Th sortable active={sortCol === 'total_pago_bruto'} dir={sortDir} onClick={sortBtn('total_pago_bruto')} className="w-[160px]">Já pago</Th>
              <Th className="w-[92px]">Parcelas</Th>
              <Th sortable active={sortCol === 'saldo_a_pagar'} dir={sortDir} onClick={sortBtn('saldo_a_pagar')} className="w-[140px]">Falta pagar</Th>
              <Th sortable active={sortCol === 'ultimo_pagamento_em'} dir={sortDir} onClick={sortBtn('ultimo_pagamento_em')} className="w-[115px]">Último pagamento</Th>
              <Th className="w-[130px]">Forma</Th>
              {/* A DATA que o comercial prometeu com o cliente (pagamento_previsto_em);
                  o texto do acordo vai de apoio embaixo. */}
              <Th className="w-[160px]">Promessa de pagto</Th>
            </Thead>
            <tbody>
              {loading && !contas.length
                ? <SkeletonRows cols={[70, 64, 96, 56, 84, 72, 84, 120]} />
                : visiveis.map((c) => <LinhaConta key={c.contato_hm_id} c={c} onOpen={setOpenId} flash={flash} />)}
            </tbody>
          </DataTable>
          {!visiveis.length && !loading && (
            <EmptyState
              title={dq.trim() ? 'Nenhuma conta encontrada na busca' : 'Nenhuma conta nesta gaveta'}
              hint={dq.trim() ? 'Confira a grafia ou limpe a busca.' : 'Selecione outra gaveta acima para ver as demais.'}
              icon="wallet"
            />
          )}
        </>
      ) : (
        <SectionCard
          title="Ofertas de cobrança do saldo"
          subtitle="Ofertas Hotmart usadas para cobrar o saldo do pacote (o que resta depois do sinal de R$ 300). Copie o link da oferta combinada e envie ao aluno."
        >
          {!pronto ? (
            <Loading label="Carregando ofertas…" minHeight={160} />
          ) : !ofertasOrdenadas.length ? (
            <EmptyState title="Nenhuma oferta cadastrada" icon="banknote" />
          ) : (
            <DataTable>
              <Thead>
                <Th>Código</Th>
                <Th>Valor</Th>
                <Th>Tipo</Th>
                <Th>Usos</Th>
                <Th>Link</Th>
              </Thead>
              <tbody>
                {ofertasOrdenadas.map((o) => (
                  <Tr key={o.codigo}>
                    <Td>
                      <span className="font-semibold text-[var(--fg)] tabular">{o.codigo}</span>
                      {!o.ativo && <span className="ml-2 align-middle inline-flex"><Badge tone="danger">Inativa</Badge></span>}
                    </Td>
                    <Td className="tabular text-[var(--fg)]">{fmtBRL(o.valor)}</Td>
                    <Td><Badge tone={o.recorrente ? 'info' : 'neutral'}>{o.recorrente ? 'Recorrente' : 'À vista'}</Badge></Td>
                    <Td className="tabular text-[var(--fg-2)]">{o.usos}</Td>
                    <Td>
                      {o.link ? (
                        <Button size="sm" variant="ghost" onClick={() => { navigator.clipboard?.writeText(o.link); flash('Link copiado.'); }}>
                          <Icon name="copy" size={13} /> Copiar link
                        </Button>
                      ) : '—'}
                    </Td>
                  </Tr>
                ))}
              </tbody>
            </DataTable>
          )}
        </SectionCard>
      )}

      {aberta && (
        <ContaDrawer
          key={aberta.contato_hm_id}
          conta={aberta}
          regua={regua}
          initialTab={drawerTab}
          canEdit={canEdit}
          canVerDoc={canVerDoc}
          onClose={() => { setOpenId(null); setDrawerTab('resumo'); }}
          act={act}
        />
      )}

      <Toast>{toast}</Toast>
    </div>
  );
}

/** Card-gaveta da fila: KPI clicável que filtra a tabela (mesma anatomia do piloto Placas). */
function QueueCard({ label, hint, icon, tone, value, active, onClick }: {
  label: string; hint: string; icon: string; tone: string; value: number; active: boolean; onClick: () => void;
}) {
  return (
    <button
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`text-left rounded-[var(--r-lg)] bg-[var(--surface-2)] shadow-[var(--shadow-sm)] p-3.5 border transition-colors ${active ? 'border-[var(--border-accent)]' : 'border-[var(--border)] hover:border-[var(--border-strong)]'}`}
      style={{ borderTopWidth: 2, borderTopColor: tone }}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-xl font-bold tabular leading-none text-[var(--fg)]">{value.toLocaleString('pt-BR')}</div>
          <div className={`mt-1.5 text-[10px] font-semibold uppercase tracking-wider ${active ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]'}`}>{label}</div>
          <div className="mt-0.5 text-[10px] text-[var(--fg-3)] truncate">{hint}</div>
        </div>
        <span className="grid place-items-center w-7 h-7 rounded-[var(--r-md)] shrink-0" style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}><Icon name={icon} size={15} /></span>
      </div>
    </button>
  );
}

/** Linha da fila — memoizada: digitar na busca não re-renderiza linhas que não mudaram. */
const LinhaConta = memo(function LinhaConta({ c, onOpen, flash }: {
  c: ContaReceber; onOpen: (id: string) => void; flash: (msg: string) => void;
}) {
  const morta = contaMorta(c);
  const quitado = c.status_financeiro === 'quitado';
  const vencido = c.status_financeiro === 'vencido';
  const pediu = c.status_financeiro === 'cancelamento_solicitado';
  const pct = c.pago_pct ?? 0;
  const desde = fmtDesde(c.ultimo_pagamento_em);
  // Forma real do pagamento (Hotmart): prioriza a do saldo; cai no sinal se ainda só pagou o sinal.
  const forma = formaPagamentoLabel(c.saldo_metodo ?? c.sinal_metodo);
  // stopPropagation: o clique de copiar não pode abrir o drawer da linha.
  const copiar = (e: React.MouseEvent, valor: string, oQue: string) => {
    e.stopPropagation();
    navigator.clipboard?.writeText(valor);
    flash(`${oQue} copiado.`);
  };
  return (
    <Tr onClick={() => onOpen(c.contato_hm_id)}>
      {/* Aluno */}
      <Td>
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 min-w-0">
            {/* O nome é prioridade: ocupa o espaço e trunca com reticências; a badge
                encurtada ("Reserva") não rouba mais a linha inteira do nome. */}
            <span className="flex-1 min-w-0 truncate text-[13px] font-medium text-[var(--fg)]" title={c.nome || undefined}>{c.nome || '—'}</span>
            {/* Reserva de vaga: pagou só o sinal — ainda não é aluno em pagamento. */}
            {ehReserva(c) && !morta && <Badge tone="warning">Reserva</Badge>}
          </div>
          <div className="text-[11px] text-[var(--fg-3)] flex items-center gap-2 min-w-0">
            <button type="button" title="Copiar e-mail" onClick={(e) => copiar(e, c.email, 'E-mail')} className="truncate hover:text-[var(--fg)] hover:underline transition-colors">{c.email}</button>
            {c.telefone && (
              <button type="button" title="Copiar telefone" onClick={(e) => copiar(e, c.telefone!, 'Telefone')} className="shrink-0 tabular hover:text-[var(--fg)] hover:underline transition-colors">{c.telefone}</button>
            )}
          </div>
        </div>
      </Td>
      {/* Origem: canal + produto */}
      <Td>
        <div className="flex flex-col gap-1 items-start">
          <span className="inline-flex whitespace-normal"><Badge tone="neutral">{c.canal}</Badge></span>
          <span className="inline-flex whitespace-normal"><Badge tone="accent">{c.produto}</Badge></span>
        </div>
      </Td>
      {/* Sinal pago em */}
      <Td className="text-xs text-[var(--fg-2)] tabular whitespace-nowrap">{fmtData(c.sinal_pago_em)}</Td>
      {/* Já pago: total bruto + barra de progresso do pacote */}
      <Td className="overflow-hidden">
        <div className="text-[13px] tabular font-semibold text-[var(--green)]">{fmtBRLc(c.total_pago_bruto)}</div>
        <div className="mt-1"><ProgressBar value={pct} tone={quitado ? 'green' : 'accent'} height={5} showLabel /></div>
      </Td>
      {/* Parcelas do plano (pagas / contratadas) + valor da parcela */}
      <Td className="overflow-hidden">
        {c.parcelas_contratadas ? (
          <>
            <div className="text-[13px] tabular text-[var(--fg)]">
              <span className="font-semibold">{c.parcelas_pagas ?? 0}</span>
              <span className="text-[var(--fg-3)]">/{c.parcelas_contratadas}</span>
            </div>
            {c.valor_parcela != null && <div className="text-[10px] tabular text-[var(--fg-3)]">{fmtBRLc(c.valor_parcela)}</div>}
          </>
        ) : (
          <span className="text-[var(--fg-3)]">—</span>
        )}
      </Td>
      {/* Falta pagar: saldo perseguível, ou estado quando não há o que perseguir */}
      <Td className="overflow-hidden">
        {morta ? (
          <Badge tone="danger">{statusLabel(c.status_financeiro)}</Badge>
        ) : quitado ? (
          <Badge tone="success">Quitado</Badge>
        ) : c.saldo_a_pagar == null ? (
          <Badge tone="warning">{statusLabel(c.status_financeiro)}</Badge>
        ) : (
          <>
            <div className={`text-[13px] tabular font-semibold ${vencido ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>{fmtBRLc(saldoEfetivo(c))}</div>
            {pediu ? (
              <span className="text-[10px] font-semibold text-[var(--yellow)]">pediu cancelamento</span>
            ) : (c.dias_atraso ?? 0) > 0 ? (
              <span className="text-[10px] font-semibold text-[var(--red)]">{c.dias_atraso}d em atraso</span>
            ) : c.vencimento ? (
              <span className="text-[10px] tabular text-[var(--fg-3)]">vence {fmtData(c.vencimento)}</span>
            ) : (
              <span className="text-[10px] text-[var(--fg-3)]">{statusLabel(c.status_financeiro)}</span>
            )}
          </>
        )}
      </Td>
      {/* Último pagamento (tempo decorrido fino) */}
      <Td className="text-xs text-[var(--fg-2)] tabular whitespace-nowrap"><span title={desde.title}>{desde.label}</span></Td>
      {/* Forma de pagamento real (Hotmart) */}
      <Td className="overflow-hidden">
        {forma === '—' ? <span className="text-[var(--fg-3)]">—</span> : <span className="inline-flex whitespace-normal"><Badge tone="neutral">{forma}</Badge></span>}
      </Td>
      {/* Promessa de pagamento: a DATA que o comercial combinou com o cliente
          (c.vencimento = pagamento_previsto_em). Vermelha se já passou e ainda
          deve. O texto do acordo fica de apoio, truncado, embaixo. */}
      <Td className="overflow-hidden">
        {c.vencimento ? (
          <div
            className={`text-[12px] tabular font-medium ${(c.dias_atraso ?? 0) > 0 ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}
            title={(c.dias_atraso ?? 0) > 0 ? `${c.dias_atraso} dias em atraso` : 'Data prometida pelo cliente'}
          >
            {fmtData(c.vencimento)}
          </div>
        ) : (
          <span className="text-[var(--fg-3)]" title="O comercial ainda não registrou a data prometida">—</span>
        )}
        {c.acordo && <div className="text-[11px] text-[var(--fg-3)] truncate" title={c.acordo}>{c.acordo}</div>}
      </Td>
    </Tr>
  );
});
