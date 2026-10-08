'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { KpiCard, SectionCard, EmptyState } from '@/shared/ui/components/Card';
import { Modal } from '@/shared/ui/components/Modal';
import { carregarAtmCanais, carregarAtmComparecimento, carregarAtmLeads, carregarAtmPosLive, carregarAtmResumo, carregarAtmSerie, type Resultado } from '../infrastructure/atm-data';
import { CANAIS_DISPARO_ATM, METRICAS_RESUMO_ATM, type DashboardAtm, type LeadAtm } from '../domain/dashboard';
import type { RegistroAtm } from '../domain/registro';

type Linha = Record<string, unknown>;
const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
function valor(v: unknown): number | null { if (v == null || v === '') return null; const n = Number(v); return Number.isFinite(n) ? n : null; }
function formatar(v: number, tipo: string) {
  if (tipo === 'moeda') return moeda.format(v);
  if (tipo === 'percentual') return v.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) + '%';
  if (tipo === 'multiplicador') return v.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) + 'x';
  return inteiro.format(v);
}
function SemDado() { return <span className="text-[11px] text-[var(--fg-3)]">sem dado ainda</span>; }

function GraficoLeads({ rows }: { rows: Linha[] }) {
  if (!rows.length) return <EmptyState title="Sem evolução de leads" hint="sem dado ainda" />;
  const nums = rows.map((r) => valor(r.leads) ?? 0);
  const max = Math.max(1, ...nums);
  const width = Math.max(360, rows.length * 38);
  return <div className="overflow-x-auto"><svg width={width} height="190" viewBox={'0 0 ' + width + ' 190'} role="img" aria-label="Evolução diária de leads">
    {rows.map((r, i) => { const x = i * 38 + 8; const n = nums[i]; const h = n / max * 130; return <g key={String(r.dia)}><rect x={x} y={145 - h} width="22" height={h} rx="3" fill="var(--accent)" /><text x={x + 11} y="166" textAnchor="middle" fontSize="9" fill="var(--fg-3)">{String(r.dia).slice(5)}</text><title>{String(r.dia) + ': ' + n}</title></g>; })}
  </svg></div>;
}

function ModalLeads({ open, onClose, result, serie, carregarSerie, carregarLeads }: { open: boolean; onClose: () => void; result: Resultado<LeadAtm[]>; serie: Linha[]; carregarSerie: () => void; carregarLeads: () => void }) {
  const [aba, setAba] = useState('Leads');
  useEffect(() => { if (open) { carregarLeads(); carregarSerie(); } }, [open, carregarLeads, carregarSerie]);
  const distribuicoes = useMemo(() => {
    const campos: [keyof LeadAtm, string][] = [['entrouGrupo', 'Entrou no grupo?'], ['aluno', 'É aluno?'], ['utmSource', 'utm_source'], ['estado', 'Estado'], ['listaOrigem', 'Lista de origem'], ['seminarioOrigem', 'Seminário de origem']];
    return campos.map(([campo, nome]) => ({ nome, valores: Object.entries(result.data.reduce<Record<string, number>>((a, l) => { const k = String(l[campo] ?? 'Não identificado'); a[k] = (a[k] ?? 0) + 1; return a; }, {})) }));
  }, [result.data]);
  return <Modal open={open} onClose={onClose} title="Leads do Seminário ATM" width="max-w-6xl">
    <div className="mb-4 flex flex-wrap gap-2">{['Leads', 'Evolução', 'Resumo'].map((x) => <button key={x} onClick={() => setAba(x)} className={'rounded-[var(--r-md)] px-3 py-2 text-sm ' + (aba === x ? 'bg-[var(--accent)] text-black font-semibold' : 'bg-[var(--surface-3)] text-[var(--fg-2)]')}>{x}</button>)}<span className="ml-auto self-center text-xs text-[var(--fg-3)]">{result.data.length} leads</span></div>
    {result.erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{result.erro}</p>}
    {result.semDado && <p className="mb-3"><SemDado /></p>}
    {aba === 'Evolução' ? <GraficoLeads rows={serie} /> : aba === 'Resumo' ? <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{distribuicoes.map((g) => <div key={g.nome} className="rounded-[var(--r-md)] border border-[var(--border)] p-3"><h3 className="mb-2 text-sm font-semibold">{g.nome}</h3>{g.valores.length ? g.valores.map(([k, n]) => <div key={k} className="flex justify-between py-1 text-xs"><span>{k}</span><b>{n}</b></div>) : <SemDado />}</div>)}</div> : result.data.length ? <div className="max-h-[65vh] overflow-auto"><table className="w-full text-sm"><thead className="sticky top-0 bg-[var(--surface-3)]"><tr>{['Data', 'Nome', 'E-mail', 'Telefone', 'Entrou no grupo?', 'É aluno?', 'utm_source', 'Estado', 'Lista de origem', 'Seminário de origem'].map((h) => <th key={h} className="p-2 text-left text-xs">{h}</th>)}</tr></thead><tbody>{result.data.map((l) => <tr key={l.id} className="border-t border-[var(--border)]"><td className="p-2 whitespace-nowrap">{l.dataHora ? new Date(l.dataHora).toLocaleString('pt-BR') : 'Não lançado'}</td><td className="p-2">{l.nome ?? 'Não lançado'}</td><td className="p-2">{l.email ?? 'Não lançado'}</td><td className="p-2">{l.telefone ?? 'Não lançado'}</td><td className="p-2">{l.entrouGrupo == null ? 'Sem dado' : l.entrouGrupo ? 'Sim' : 'Não'}</td><td className="p-2">{l.aluno == null ? 'Sem dado' : l.aluno ? 'Sim' : 'Não'}</td><td className="p-2">{l.utmSource ?? 'Não lançado'}</td><td className="p-2">{l.estado ?? 'Não lançado'}</td><td className="p-2">{l.listaOrigem ?? 'Não lançado'}</td><td className="p-2">{l.seminarioOrigem ?? 'Não lançado'}</td></tr>)}</tbody></table></div> : <EmptyState title="Sem leads para exibir" hint="sem dado ainda" />}
  </Modal>;
}

export function SeminarioAtmClient({ projeto }: { projeto: RegistroAtm }) {
  const [resumo, setResumo] = useState<DashboardAtm | null>(null);
  const [serie, setSerie] = useState<Linha[]>([]);
  const [leads, setLeads] = useState<Resultado<LeadAtm[]>>({ data: [], semDado: true, erro: null });
  const [canais, setCanais] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [comparecimento, setComparecimento] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [posLive, setPosLive] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [canalAtivo, setCanalAtivo] = useState('whatsapp_api');
  const [modal, setModal] = useState(false);
  const [atualizado, setAtualizado] = useState<Date | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const emCurso = useRef(false);
  const atualizar = useCallback(async () => {
    if (emCurso.current) return;
    emCurso.current = true;
    try {
      const [r, s] = await Promise.all([carregarAtmResumo(projeto.chave), carregarAtmSerie(projeto.chave)]);
      if (!r.semDado) setResumo(r.data);
      if (!s.semDado) setSerie(s.data);
      setErro(r.erro || s.erro);
      if (!r.semDado || !s.semDado) setAtualizado(new Date());
    } finally { emCurso.current = false; }
  }, [projeto.chave]);
  const atualizarLeads = useCallback(async () => { const r = await carregarAtmLeads(projeto.chave); if (!r.semDado) setLeads(r); }, [projeto.chave]);
  const atualizarSerie = useCallback(async () => { const r = await carregarAtmSerie(projeto.chave); if (!r.semDado) setSerie(r.data); }, [projeto.chave]);
  useEffect(() => {
    void atualizar();
    const timer = window.setInterval(() => { if (document.visibilityState === 'visible') void atualizar(); }, 60_000);
    const vis = () => { if (document.visibilityState === 'visible') void atualizar(); };
    document.addEventListener('visibilitychange', vis);
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', vis); };
  }, [atualizar]);
  useEffect(() => {
    void carregarAtmCanais(projeto.chave).then(setCanais);
    void carregarAtmComparecimento(projeto.chave).then(setComparecimento);
    void carregarAtmPosLive(projeto.chave).then(setPosLive);
  }, [projeto.chave]);

  const linhasResumo = useMemo(() => METRICAS_RESUMO_ATM.map((m) => ({ ...m, metrica: resumo?.resumo[m.chave] ?? { valor: 0, semDado: true } })), [resumo]);
  const canal = canais.data.find((x) => x.canal === canalAtivo) ?? canais.data.find((x) => x.canal === 'whatsapp_api');
  const sessao = comparecimento.data[0];
  const ciclo = (nome: string) => posLive.data.find((x) => x.ciclo === nome);
  const renderVal = (v: unknown, tipo: string) => { const n = valor(v); return n == null ? 'Não lançado' : formatar(n, tipo); };
  return <div className="max-w-7xl space-y-5">
    <header><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dashboards / Escritório / Seminário ATM</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{projeto.rotulo}</h1><p className="mt-1 text-sm text-[var(--fg-2)]">Chave {projeto.chave} · {atualizado ? 'atualizado às ' + atualizado.toLocaleTimeString('pt-BR') : 'aguardando leitura'}</p></header>
    {erro && <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]">{erro}</p>}
    {resumo?.semDado && <p className="text-xs text-[var(--fg-3)]">sem dado ainda · os dados aparecem quando as funções do banco e os dados do projeto estiverem disponíveis.</p>}
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{linhasResumo.map((m) => <button key={m.chave} type="button" onClick={() => { if (m.chave === 'leads') setModal(true); }} className="text-left"><KpiCard label={m.rotulo} value={formatar(m.metrica.valor, m.formato)} hint={m.metrica.semDado ? 'sem dado ainda' : undefined} bar={m.chave === 'vendas' ? 'green' : 'accent'} /></button>)}</div>
    <SectionCard title="Evolução diária" subtitle="Leads, grupo, pré-checkout, vendas, faturamento e custo.">
      {serie.length ? <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="text-left text-xs text-[var(--fg-3)]">{['Dia', 'Leads', 'Ingresso no grupo', 'Saídas', 'Pré-checkout', 'Vendas', 'Faturamento bruto', 'Custo disparo'].map((x) => <th key={x} className="p-2">{x}</th>)}</tr></thead><tbody>{serie.map((r) => <tr key={String(r.dia)} className="border-t border-[var(--border)]">{['dia', 'leads', 'grupo_entradas', 'grupo_saidas', 'pre_checkout', 'vendas', 'receita_bruta', 'custo_disparo_centavos'].map((k) => <td key={k} className="p-2">{k === 'dia' ? String(r[k] ?? '') : renderVal(k === 'custo_disparo_centavos' && valor(r[k]) != null ? (valor(r[k]) ?? 0) / 100 : r[k], k === 'receita_bruta' || k === 'custo_disparo_centavos' ? 'moeda' : 'inteiro')}</td>)}</tr>)}</tbody></table></div> : <EmptyState title="Sem série disponível" hint="sem dado ainda" />}
    </SectionCard>
    <SectionCard title="Disparos" subtitle="Totais por canal.">
      <div className="mb-4 flex flex-wrap gap-2">{CANAIS_DISPARO_ATM.map((c) => { const key = c.canal === 'api' ? 'whatsapp_api' : c.canal; return <button key={c.canal} onClick={() => setCanalAtivo(key)} className={'rounded-[var(--r-md)] px-3 py-2 text-sm ' + (canalAtivo === key ? 'bg-[var(--accent)] text-black font-semibold' : 'bg-[var(--surface-3)] text-[var(--fg-2)]')}>{c.rotulo}</button>; })}</div>
      {canal ? <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{[['Disparos', 'disparos'], ['Enviados', 'enviados'], ['Entregues', 'entregues'], ['Lidas / atendidas', 'lidas'], ['Cliques', 'cliques'], ['Falhas', 'falhas'], ['Custo', 'custo_centavos']].map(([label, key]) => { const n = valor(canal[key]); const money = key === 'custo_centavos'; return <KpiCard key={key} label={label} value={n == null ? 'Não lançado' : formatar(money ? n / 100 : n, money ? 'moeda' : 'inteiro')} hint={n == null || canais.semDado ? 'sem dado ainda' : undefined} />; })}</div> : <EmptyState title="Sem dados para este canal" hint="sem dado ainda" />}
    </SectionCard>
    <SectionCard title="Comparecimento" subtitle="Dados por sessão, conforme cadastro no banco.">
      {comparecimento.data.length ? <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{[['Pico de audiência', 'pico_audiencia', 'inteiro'], ['Comparecimento do grupo', 'presentes_grupo', 'inteiro'], ['Comparecimento dos leads', 'presentes_leads', 'inteiro'], ['Total de leads', 'total_leads', 'inteiro'], ['Total no grupo', 'total_grupo', 'inteiro'], ['Pessoas da equipe na sala', 'equipe_na_sala', 'inteiro'], ['Vendas', 'vendas', 'inteiro'], ['Conversão', 'conversao_pct', 'percentual'], ['Conversão no grupo', 'conversao_grupo_pct', 'percentual'], ['Conversão sobre o pico', 'conversao_pico_pct', 'percentual']].map(([label, key, tipo]) => { const n = valor(sessao?.[key]); return <KpiCard key={key} label={label} value={renderVal(n, tipo)} hint={n == null ? 'sem dado ainda' : undefined} />; })}</div> : <EmptyState title="Comparecimento ainda não lançado" hint="sem dado ainda" />}
    </SectionCard>
    <SectionCard title="Pós-live" subtitle="Vendas e conversão em ciclos separados.">
      {posLive.data.length ? <div className="grid gap-4 md:grid-cols-2">{(['aberto', 'fechado'] as const).map((nome) => { const p = ciclo(nome); return <div key={nome} className="rounded-[var(--r-md)] border border-[var(--border)] p-4"><h3 className="font-semibold capitalize">Ciclo {nome}</h3><div className="mt-3 grid grid-cols-2 gap-3"><KpiCard label="Vendas" value={renderVal(p?.vendas, 'inteiro')} hint={p?.vendas == null ? 'sem dado ainda' : undefined} /><KpiCard label="Conversão" value={renderVal(p?.conversao_pct, 'percentual')} hint={p?.conversao_pct == null ? 'sem dado ainda' : undefined} /></div></div>; })}</div> : <EmptyState title="Pós-live sem dados" hint="sem dado ainda" />}
    </SectionCard>
    <ModalLeads open={modal} onClose={() => setModal(false)} result={leads} serie={serie} carregarSerie={atualizarSerie} carregarLeads={atualizarLeads} />
  </div>;
}
