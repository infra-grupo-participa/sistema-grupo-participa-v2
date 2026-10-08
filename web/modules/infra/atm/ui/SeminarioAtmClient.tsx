'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { KpiCard, SectionCard, EmptyState, ConfirmDialog } from '@/shared/ui/components';
import { Modal } from '@/shared/ui/components/Modal';
import {
  carregarAtmCanais,
  carregarAtmComparecimento,
  carregarAtmGrupo,
  carregarAtmLeads,
  carregarAtmPosLive,
  carregarAtmResumo,
  carregarAtmSerie,
  desmarcarAtmTeste,
  marcarAtmTeste,
  type Resultado,
} from '../infrastructure/atm-data';
import { CANAIS_DISPARO_ATM, METRICAS_RESUMO_ATM, montarAvisosTesteAtm, type DashboardAtm, type LeadAtm, type NumeroGrupoAtm } from '../domain/dashboard';
import type { RegistroAtm } from '../domain/registro';
import { dataPtBr, datasDoPeriodo, type PresetPeriodoAtm } from '../domain/periodo';
import { RoscaCategorias } from '@/modules/infra/dados/ui/viz/RoscaCategorias';

type Linha = Record<string, unknown>;
type PedidoAtualizacao = { periodo: ReturnType<typeof datasDoPeriodo>; detalhado: boolean; modal: boolean; isMaster: boolean };
type PropsModalLeads = {
  open: boolean;
  onClose: () => void;
  result: Resultado<LeadAtm[]>;
  grupo: Resultado<NumeroGrupoAtm[]>;
  serie: Linha[];
  periodoLabel: string;
  isMaster: boolean;
  onToggleLead: (lead: LeadAtm, teste: boolean) => Promise<string | null>;
  onToggleGrupo: (grupo: NumeroGrupoAtm, teste: boolean) => Promise<string | null>;
};

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
function valor(v: unknown): number | null { if (v == null || v === '') return null; const n = Number(v); return Number.isFinite(n) ? n : null; }
function formatar(v: number, tipo: string) {
  if (tipo === 'moeda') return moeda.format(v);
  if (tipo === 'percentual') return v.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) + '%';
  if (tipo === 'multiplicador') return v.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) + 'x';
  return inteiro.format(v);
}
function dataHora(iso: string | null) { return iso ? new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : 'Não lançado'; }

function GraficoLeads({ rows }: { rows: Linha[] }) {
  if (!rows.length) return <EmptyState title="Sem evolução de leads" hint="sem dado ainda" />;
  const nums = rows.map((r) => valor(r.leads) ?? 0);
  const max = Math.max(1, ...nums);
  const width = Math.max(360, rows.length * 38);
  return <div className="overflow-x-auto"><svg width={width} height="190" viewBox={'0 0 ' + width + ' 190'} role="img" aria-label="Evolução diária de leads">
    {rows.map((r, i) => { const x = i * 38 + 8; const n = nums[i]; const h = n / max * 130; return <g key={String(r.dia)}><rect x={x} y={145 - h} width="22" height={h} rx="3" fill="var(--accent)" /><text x={x + 11} y="166" textAnchor="middle" fontSize="9" fill="var(--fg-3)">{String(r.dia).slice(5)}</text><title>{String(r.dia) + ': ' + n}</title></g>; })}
  </svg></div>;
}

function ModalLeads({ open, onClose, result, grupo, serie, periodoLabel, isMaster, onToggleLead, onToggleGrupo }: PropsModalLeads) {
  const [aba, setAba] = useState('Leads');
  const [alvoLead, setAlvoLead] = useState<LeadAtm | null>(null);
  const [alvoGrupo, setAlvoGrupo] = useState<NumeroGrupoAtm | null>(null);
  const [salvando, setSalvando] = useState<string | null>(null);
  const [erroAcao, setErroAcao] = useState<string | null>(null);
  const leadsAtivos = useMemo(() => result.data.filter((lead) => !lead.teste), [result.data]);
  const distribuicoes = useMemo(() => {
    const campos: [keyof LeadAtm, string][] = [['entrouGrupo', 'Entrou no grupo?'], ['aluno', 'É aluno?'], ['utmSource', 'utm_source'], ['estado', 'Estado'], ['listaOrigem', 'Lista de origem'], ['seminarioOrigem', 'Seminário de origem']];
    return campos.map(([campo, nome]) => ({ nome, valores: Object.entries(leadsAtivos.reduce<Record<string, number>>((a, lead) => { const k = String(lead[campo] ?? 'Não identificado'); a[k] = (a[k] ?? 0) + 1; return a; }, {})) }));
  }, [leadsAtivos]);

  const mudarLead = async (lead: LeadAtm, teste: boolean) => {
    if (salvando) return;
    setSalvando(lead.id); setErroAcao(null);
    const erro = await onToggleLead(lead, teste);
    setSalvando(null);
    if (erro) setErroAcao(erro);
    setAlvoLead(null);
  };
  const mudarGrupo = async (numero: NumeroGrupoAtm, teste: boolean) => {
    if (salvando) return;
    setSalvando(numero.foneKey); setErroAcao(null);
    const erro = await onToggleGrupo(numero, teste);
    setSalvando(null);
    if (erro) setErroAcao(erro);
  };

  return <Modal open={open} onClose={onClose} title="Leads do Seminário ATM" width="max-w-6xl">
    <div className="mb-4 flex flex-wrap items-center gap-2">
      {['Leads', 'Grupo', 'Evolução', 'Resumo'].map((nome) => <button key={nome} type="button" onClick={() => setAba(nome)} className={'rounded-[var(--r-md)] px-3 py-2 text-sm ' + (aba === nome ? 'bg-[var(--accent)] text-black font-semibold' : 'bg-[var(--surface-3)] text-[var(--fg-2)]')}>{nome}</button>)}
      <span className="ml-auto self-center text-xs text-[var(--fg-3)]">{inteiro.format(leadsAtivos.length)} leads válidos · {periodoLabel}</span>
    </div>
    {erroAcao && <p role="alert" className="mb-3 rounded border border-[var(--red)]/40 p-3 text-sm text-[var(--red)]">{erroAcao}</p>}
    {aba === 'Evolução' ? <GraficoLeads rows={serie} /> : aba === 'Resumo' ? <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{distribuicoes.map((g) => <RoscaCategorias key={g.nome} titulo={g.nome} rotuloCentro="leads" fatias={g.valores.map(([rotulo, quantidade]) => ({ rotulo, quantidade }))} />)}</div> : aba === 'Grupo' ? <>
      {grupo.erro && <p role="alert" className="mb-3 text-sm text-[var(--yellow)]">{grupo.erro}</p>}
      {grupo.semDado ? <EmptyState title="Números do grupo indisponíveis" hint="sem dado ainda" /> : grupo.data.length === 0 ? <EmptyState title="Nenhum número entrou no grupo neste período" /> : <div className="max-h-[65vh] overflow-auto"><table className="w-full text-sm"><thead className="sticky top-0 bg-[var(--surface-3)]"><tr>{['Entrada', 'Nome', 'Telefone', 'No grupo?', 'É lead?', ...(isMaster ? ['Teste', 'Ação'] : [])].map((h) => <th key={h} className="p-2 text-left text-xs">{h}</th>)}</tr></thead><tbody>{grupo.data.map((numero) => <tr key={numero.foneKey} className={'border-t border-[var(--border)] ' + (numero.teste ? 'opacity-60' : '')}><td className="whitespace-nowrap p-2">{dataHora(numero.entrouEm)}</td><td className="p-2">{numero.nome ?? 'Não lançado'}</td><td className="whitespace-nowrap p-2">{numero.foneKey}</td><td className="p-2">{numero.noGrupo == null ? 'Não lançado' : numero.noGrupo ? 'Sim' : 'Não'}</td><td className="p-2">{numero.ehLead == null ? 'Não lançado' : numero.ehLead ? 'Sim' : 'Não'}</td>{isMaster && <><td className="p-2">{numero.teste ? <span className="rounded-full border border-[var(--border)] px-2 py-0.5 text-[10px] uppercase">teste{numero.testeMotivo === 'equipe' ? ' · equipe' : ''}</span> : 'Não'}</td><td className="p-2"><button type="button" disabled={salvando === numero.foneKey} onClick={() => { setErroAcao(null); if (numero.teste) void mudarGrupo(numero, false); else setAlvoGrupo(numero); }} className="whitespace-nowrap rounded border border-[var(--border)] px-2 py-1 text-xs hover:bg-[var(--surface-3)] disabled:opacity-50">{salvando === numero.foneKey ? 'Salvando…' : numero.teste ? 'Desmarcar teste' : 'Marcar como teste'}</button></td></>}</tr>)}</tbody></table></div>}
    </> : result.erro ? <p role="alert" className="text-sm text-[var(--yellow)]">{result.erro}</p> : result.semDado ? <EmptyState title="Leads indisponíveis" hint="sem dado ainda" /> : aba === 'Leads' ? result.data.length === 0 ? <EmptyState title="Nenhum lead neste período" /> : <div className="max-h-[65vh] overflow-auto"><table className="w-full text-sm"><thead className="sticky top-0 bg-[var(--surface-3)]"><tr>{['Data', 'Nome', 'E-mail', 'Telefone', 'Entrou no grupo?', 'É aluno?', 'utm_source', 'Estado', 'Lista de origem', 'Seminário de origem', ...(isMaster ? ['Teste', 'Ação'] : [])].map((h) => <th key={h} className="p-2 text-left text-xs">{h}</th>)}</tr></thead><tbody>{result.data.map((lead) => <tr key={lead.id} className={'border-t border-[var(--border)] ' + (lead.teste ? 'opacity-60' : '')}><td className="whitespace-nowrap p-2">{dataHora(lead.dataHora)}</td><td className="p-2">{lead.nome ?? 'Não lançado'}</td><td className="p-2">{lead.email ?? 'Não lançado'}</td><td className="whitespace-nowrap p-2">{lead.telefone ?? 'Não lançado'}</td><td className="p-2">{lead.entrouGrupo == null ? 'Sem dado' : lead.entrouGrupo ? 'Sim' : 'Não'}</td><td className="p-2">{lead.aluno == null ? 'Sem dado' : lead.aluno ? 'Sim' : 'Não'}</td><td className="p-2">{lead.utmSource ?? 'Não lançado'}</td><td className="p-2">{lead.estado ?? 'Não lançado'}</td><td className="p-2">{lead.listaOrigem ?? 'Não lançado'}</td><td className="p-2">{lead.seminarioOrigem ?? 'Não lançado'}</td>{isMaster && <><td className="p-2">{lead.teste ? <span className="rounded-full border border-[var(--border)] px-2 py-0.5 text-[10px] uppercase">teste</span> : 'Não'}</td><td className="p-2">{(lead.email || lead.telefone) && <button type="button" disabled={salvando === lead.id} onClick={() => { setErroAcao(null); if (lead.teste) void mudarLead(lead, false); else setAlvoLead(lead); }} className="whitespace-nowrap rounded border border-[var(--border)] px-2 py-1 text-xs hover:bg-[var(--surface-3)] disabled:opacity-50">{salvando === lead.id ? 'Salvando…' : lead.teste ? 'Desmarcar teste' : 'Marcar como teste'}</button>}</td></>}</tr>)}</tbody></table></div> : null}
    {alvoLead && <ConfirmDialog title="Marcar lead como teste" confirmLabel="Marcar como teste" cancelLabel="Cancelar" onCancel={() => setAlvoLead(null)} onConfirm={() => void mudarLead(alvoLead, true)} message="Esta marcação vale para este Seminário ATM. O lead e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?" />}
    {alvoGrupo && <ConfirmDialog title="Marcar número do grupo como teste" confirmLabel="Marcar como teste" cancelLabel="Cancelar" onCancel={() => setAlvoGrupo(null)} onConfirm={() => { const alvo = alvoGrupo; setAlvoGrupo(null); void mudarGrupo(alvo, true); }} message="Esta marcação vale para este Seminário ATM. O número e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?" />}
  </Modal>;
}

export function SeminarioAtmClient({ projeto, isMaster = false, mostrarAvisoTeste = false }: { projeto: RegistroAtm; isMaster?: boolean; mostrarAvisoTeste?: boolean }) {
  const [resumo, setResumo] = useState<DashboardAtm | null>(null);
  const [serie, setSerie] = useState<Linha[]>([]);
  const [leads, setLeads] = useState<Resultado<LeadAtm[]>>({ data: [], semDado: true, erro: null });
  const [grupo, setGrupo] = useState<Resultado<NumeroGrupoAtm[]>>({ data: [], semDado: true, erro: null });
  const [canais, setCanais] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [comparecimento, setComparecimento] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [posLive, setPosLive] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [canalAtivo, setCanalAtivo] = useState('whatsapp_api');
  const [modal, setModal] = useState(false);
  const [periodoSelecionado, setPeriodoSelecionado] = useState<PresetPeriodoAtm>('evento');
  const [atualizado, setAtualizado] = useState<Date | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [atualizando, setAtualizando] = useState(false);
  const emCurso = useRef(false);
  const pedidoPendente = useRef<PedidoAtualizacao | null>(null);
  const atualizarRef = useRef<(detalhado?: boolean) => Promise<void>>(async () => {});
  const modalAtual = useRef(false);
  const periodoAtual = useRef<PresetPeriodoAtm>('evento');

  const atualizar = useCallback(async (detalhado = false) => {
    const pedido: PedidoAtualizacao = { periodo: datasDoPeriodo(periodoSelecionado), detalhado, modal: modalAtual.current, isMaster };
    if (emCurso.current) {
      pedidoPendente.current = { ...pedido, detalhado: pedido.detalhado || pedidoPendente.current?.detalhado === true };
      return;
    }
    emCurso.current = true;
    setAtualizando(true);
    try {
      let proximo: PedidoAtualizacao | null = pedido;
      while (proximo) {
        const atual = proximo;
        proximo = null;
        let teveLeitura = false;
        const erros: string[] = [];
        const [r, s] = await Promise.all([carregarAtmResumo(projeto.chave, atual.periodo), carregarAtmSerie(projeto.chave, atual.periodo)]);
        if (!r.semDado) { setResumo(r.data); teveLeitura = true; }
        if (!s.semDado) { setSerie(s.data); teveLeitura = true; }
        if (r.erro) erros.push(r.erro);
        if (s.erro) erros.push(s.erro);

        if (atual.detalhado) {
          const pedidos: Promise<void>[] = [
            carregarAtmCanais(projeto.chave, atual.periodo).then((result) => { if (!result.semDado) { setCanais(result); teveLeitura = true; } else if (result.erro) setCanais((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }),
            carregarAtmComparecimento(projeto.chave).then((result) => { if (!result.semDado) { setComparecimento(result); teveLeitura = true; } else if (result.erro) setComparecimento((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }),
            carregarAtmPosLive(projeto.chave).then((result) => { if (!result.semDado) { setPosLive(result); teveLeitura = true; } else if (result.erro) setPosLive((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }),
          ];
          if (atual.modal) {
            pedidos.push(carregarAtmLeads(projeto.chave, atual.periodo, atual.isMaster).then((result) => { if (!result.semDado) { setLeads(result); teveLeitura = true; } else if (result.erro) setLeads((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }));
            pedidos.push(carregarAtmGrupo(projeto.chave, atual.periodo, atual.isMaster).then((result) => { if (!result.semDado) { setGrupo(result); teveLeitura = true; } else if (result.erro) setGrupo((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }));
          }
          await Promise.all(pedidos);
        }
        setErro(erros[0] ?? null);
        if (teveLeitura) setAtualizado(new Date());
        proximo = pedidoPendente.current;
        pedidoPendente.current = null;
      }
    } finally {
      emCurso.current = false;
      setAtualizando(false);
    }
  }, [isMaster, periodoSelecionado, projeto.chave]);

  useEffect(() => { atualizarRef.current = atualizar; }, [atualizar]);
  useEffect(() => {
    void atualizarRef.current(true);
    const timer = window.setInterval(() => { if (document.visibilityState === 'visible') void atualizarRef.current(false); }, 60_000);
    const vis = () => { if (document.visibilityState === 'visible') void atualizarRef.current(false); };
    document.addEventListener('visibilitychange', vis);
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', vis); };
  }, [projeto.chave]);
  useEffect(() => {
    if (periodoAtual.current === periodoSelecionado) return;
    periodoAtual.current = periodoSelecionado;
    void atualizarRef.current(modalAtual.current);
  }, [periodoSelecionado]);
  useEffect(() => {
    const abriu = modal && !modalAtual.current;
    modalAtual.current = modal;
    if (abriu) void atualizarRef.current(true);
  }, [modal]);

  const atualizarTudo = async () => { await atualizar(true); };
  const toggleLead = async (lead: LeadAtm, teste: boolean): Promise<string | null> => {
    if (!isMaster) return 'Só masters podem marcar ou desmarcar testes.';
    const result = teste
      ? await marcarAtmTeste(projeto.chave, lead.email, lead.telefone)
      : await desmarcarAtmTeste(projeto.chave, lead.email, lead.telefone);
    if (result.erro) return result.erro;
    await atualizar(true);
    return null;
  };
  const toggleGrupo = async (numero: NumeroGrupoAtm, teste: boolean): Promise<string | null> => {
    if (!isMaster) return 'Só masters podem marcar ou desmarcar testes.';
    const result = teste
      ? await marcarAtmTeste(projeto.chave, null, numero.foneKey)
      : await desmarcarAtmTeste(projeto.chave, null, numero.foneKey);
    if (result.erro) return result.erro;
    await atualizar(true);
    return null;
  };

  const linhasResumo = useMemo(() => METRICAS_RESUMO_ATM.map((m) => ({ ...m, metrica: resumo?.resumo[m.chave] ?? { valor: 0, semDado: true } })), [resumo]);
  const canal = canais.data.find((x) => x.canal === canalAtivo) ?? canais.data.find((x) => x.canal === 'whatsapp_api');
  const sessao = comparecimento.data[0];
  const ciclo = (nome: string) => posLive.data.find((x) => x.ciclo === nome);
  const renderVal = (v: unknown, tipo: string) => { const n = valor(v); return n == null ? 'Não lançado' : formatar(n, tipo); };
  const intervalo = resumo?.periodo.de && resumo.periodo.ate ? `${dataPtBr(resumo.periodo.de)} a ${dataPtBr(resumo.periodo.ate)}` : 'sem dado ainda';
  const alertasTeste = montarAvisosTesteAtm(resumo?.periodo);

  return <div className="max-w-7xl space-y-5">
    <header><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dashboards / Escritório / Seminário ATM</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{projeto.rotulo}</h1><p className="mt-1 text-sm text-[var(--fg-2)]">Chave {projeto.chave} · {atualizado ? 'atualizado às ' + atualizado.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : 'aguardando leitura'}</p></header>
    <div className="flex flex-wrap items-end gap-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
      <label className="grid gap-1 text-xs text-[var(--fg-2)]">Período
        <select aria-label="Período do dashboard" value={periodoSelecionado} onChange={(e) => setPeriodoSelecionado(e.target.value as PresetPeriodoAtm)} className="min-h-10 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] px-3 text-sm text-[var(--fg)]">
          <option value="evento">Período do evento</option><option value="hoje">Hoje</option><option value="ontem">Ontem</option><option value="3d">Últimos 3 dias</option><option value="7d">Últimos 7 dias</option>
        </select>
      </label>
      <p className="pb-2 text-xs text-[var(--fg-3)]">Período aplicado: {intervalo}</p>
      <button type="button" onClick={atualizarTudo} disabled={atualizando} className="min-h-10 rounded-[var(--r-md)] border border-[var(--border)] px-4 text-sm text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50">{atualizando ? 'Atualizando…' : 'Atualizar'}</button>
    </div>
    {erro && <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]">{erro}</p>}
    {resumo?.semDado && <p className="text-xs text-[var(--fg-3)]">sem dado ainda · os dados aparecem quando as funções do banco e os dados do projeto estiverem disponíveis.</p>}
    {mostrarAvisoTeste && alertasTeste.length > 0 && <div role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)]/50 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]"><strong>Registros excluídos por marcação de teste:</strong><ul className="mt-1 list-inside list-disc">{alertasTeste.map((aviso) => <li key={aviso.tipo}>{aviso.tipo === 'leads' ? `${inteiro.format(aviso.quantidade)} leads marcados como teste` : aviso.tipo === 'grupo' ? `${inteiro.format(aviso.quantidade)} números do grupo marcados como teste` : `${inteiro.format(aviso.quantidade)} vendas marcadas como teste, faturamento bruto excluído: ${aviso.receitaBruta == null ? 'não lançado' : moeda.format(aviso.receitaBruta)}`}</li>)}</ul></div>}
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{linhasResumo.map((m) => <button key={m.chave} type="button" onClick={() => { if (m.chave === 'leads') setModal(true); }} className="text-left"><KpiCard label={m.rotulo} value={m.metrica.semDado ? 'Não lançado' : formatar(m.metrica.valor, m.formato)} hint={m.metrica.semDado ? 'sem dado ainda' : undefined} bar={m.chave === 'vendas' ? 'green' : 'accent'} /></button>)}</div>
    <SectionCard title="Evolução diária" subtitle={`Leads, grupo, pré-checkout, vendas, faturamento e custo. ${intervalo}`}>
      {serie.length ? <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="text-left text-xs text-[var(--fg-3)]">{['Dia', 'Leads', 'Ingresso no grupo', 'Saídas', 'Pré-checkout', 'Vendas', 'Faturamento bruto', 'Custo disparo'].map((x) => <th key={x} className="p-2">{x}</th>)}</tr></thead><tbody>{serie.map((r) => <tr key={String(r.dia)} className="border-t border-[var(--border)]">{['dia', 'leads', 'grupo_entradas', 'grupo_saidas', 'pre_checkout', 'vendas', 'receita_bruta', 'custo_disparo_centavos'].map((k) => <td key={k} className="p-2">{k === 'dia' ? String(r[k] ?? '') : renderVal(k === 'custo_disparo_centavos' && valor(r[k]) != null ? (valor(r[k]) ?? 0) / 100 : r[k], k === 'receita_bruta' || k === 'custo_disparo_centavos' ? 'moeda' : 'inteiro')}</td>)}</tr>)}</tbody></table></div> : <EmptyState title="Sem série disponível" hint="sem dado ainda" />}
    </SectionCard>
    <SectionCard title="Disparos" subtitle="Totais por canal no período selecionado.">
      <div className="mb-4 flex flex-wrap gap-2">{CANAIS_DISPARO_ATM.map((c) => { const key = c.canal === 'api' ? 'whatsapp_api' : c.canal; return <button key={c.canal} onClick={() => setCanalAtivo(key)} className={'rounded-[var(--r-md)] px-3 py-2 text-sm ' + (canalAtivo === key ? 'bg-[var(--accent)] text-black font-semibold' : 'bg-[var(--surface-3)] text-[var(--fg-2)]')}>{c.rotulo}</button>; })}</div>
      {canais.erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{canais.erro}</p>}
      {canal ? <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{[['Disparos', 'disparos'], ['Enviados', 'enviados'], ['Entregues', 'entregues'], ['Lidas / atendidas', 'lidas'], ['Cliques', 'cliques'], ['Falhas', 'falhas'], ['Custo', 'custo_centavos']].map(([label, key]) => { const n = valor(canal[key]); const money = key === 'custo_centavos'; return <KpiCard key={key} label={label} value={n == null ? 'Não lançado' : formatar(money ? n / 100 : n, money ? 'moeda' : 'inteiro')} hint={n == null || canais.semDado ? 'sem dado ainda' : undefined} />; })}</div> : <EmptyState title="Sem dados para este canal" hint="sem dado ainda" />}
    </SectionCard>
    <SectionCard title="Comparecimento" subtitle="Dados por sessão, conforme cadastro no banco. Este bloco considera o evento inteiro.">
      {comparecimento.erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{comparecimento.erro}</p>}
      {comparecimento.data.length ? <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{[['Pico de audiência', 'pico_audiencia', 'inteiro'], ['Comparecimento do grupo', 'presentes_grupo', 'inteiro'], ['Comparecimento dos leads', 'presentes_leads', 'inteiro'], ['Total de leads', 'total_leads', 'inteiro'], ['Total no grupo', 'total_grupo', 'inteiro'], ['Pessoas da equipe na sala', 'equipe_na_sala', 'inteiro'], ['Vendas', 'vendas', 'inteiro'], ['Conversão', 'conversao_pct', 'percentual'], ['Conversão no grupo', 'conversao_grupo_pct', 'percentual'], ['Conversão sobre o pico', 'conversao_pico_pct', 'percentual']].map(([label, key, tipo]) => { const n = valor(sessao?.[key]); return <KpiCard key={key} label={label} value={renderVal(n, tipo)} hint={n == null ? 'sem dado ainda' : undefined} />; })}</div> : <EmptyState title="Comparecimento ainda não lançado" hint="sem dado ainda" />}
    </SectionCard>
    <SectionCard title="Pós-live" subtitle="Vendas e conversão em ciclos separados. Este bloco considera o evento inteiro.">
      {posLive.erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{posLive.erro}</p>}
      {posLive.data.length ? <div className="grid gap-4 md:grid-cols-2">{(['aberto', 'fechado'] as const).map((nome) => { const p = ciclo(nome); return <div key={nome} className="rounded-[var(--r-md)] border border-[var(--border)] p-4"><h3 className="font-semibold capitalize">Ciclo {nome}</h3><div className="mt-3 grid grid-cols-2 gap-3"><KpiCard label="Vendas" value={renderVal(p?.vendas, 'inteiro')} hint={p?.vendas == null ? 'sem dado ainda' : undefined} /><KpiCard label="Conversão" value={renderVal(p?.conversao_pct, 'percentual')} hint={p?.conversao_pct == null ? 'sem dado ainda' : undefined} /></div></div>; })}</div> : <EmptyState title="Pós-live sem dados" hint="sem dado ainda" />}
    </SectionCard>
    <ModalLeads open={modal} onClose={() => setModal(false)} result={leads} grupo={grupo} serie={serie} periodoLabel={intervalo} isMaster={isMaster} onToggleLead={toggleLead} onToggleGrupo={toggleGrupo} />
  </div>;
}
