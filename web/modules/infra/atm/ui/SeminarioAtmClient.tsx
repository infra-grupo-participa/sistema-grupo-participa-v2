'use client';

import { LinkVoltar } from '@/shared/ui/departamentos/LinkVoltar';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Card, KpiCard, SectionCard, EmptyState, Tabs, idsAba } from '@/shared/ui/components';
import {
  carregarAtmCanais,
  carregarAtmComparecimento,
  carregarAtmDisparosLista,
  carregarAtmGrupo,
  carregarAtmLeads,
  carregarAtmPosLive,
  carregarAtmPreCheckout,
  carregarAtmResumo,
  carregarAtmSerie,
  carregarAtmSvVendas,
  carregarAtmTrafego,
  desmarcarAtmTeste,
  marcarAtmTeste,
  trafegoAtmSemDado,
  type DisparoDetalheAtm,
  type DadosTrafegoAtm,
  type Resultado,
} from '../infrastructure/atm-data';
import { CANAIS_DISPARO_ATM, METRICAS_RESUMO_ATM, metricaDoCardAtm, modalDoCardAtm, montarAvisosTesteAtm, type DashboardAtm, type LeadAtm, type ModalFunilAtm, type NumeroGrupoAtm, type PessoaPreCheckoutAtm, type ResumoAtm } from '../domain/dashboard';
import type { RegistroAtm } from '../domain/registro';
import type { VendaSessaoViabilidade } from '../domain/sessao-viabilidade';
import { dataPtBr, datasDoPeriodo, type PresetPeriodoAtm } from '../domain/periodo';
import { DisparosDetalhe } from './DisparosDetalhe';
import { HistoricoAtm } from './HistoricoAtm';
import { TrafegoAtm } from './TrafegoAtm';
import { ModalLeadsAtm, ModalPreCheckoutAtm, ModalVendasAtm } from './ModaisFunilAtm';
import { ModalEvolucaoIngressoGrupo } from '@/modules/infra/ingresso-grupo/ui/ModalEvolucaoIngressoGrupo';
import { chaveListaAtm, criarCarregadorListasAtm } from './carregador-listas';
import { useListaAtm } from './useListaAtm';
import { AJUDA_EQUIPE, CARDS_COMPARECIMENTO } from '../domain/comparecimento';

type Linha = Record<string, unknown>;
type PedidoAtualizacao = { periodo: ReturnType<typeof datasDoPeriodo>; detalhado: boolean };

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
function valor(v: unknown): number | null { if (v == null || v === '') return null; const n = Number(v); return Number.isFinite(n) ? n : null; }
function formatar(v: number, tipo: string) {
  if (tipo === 'moeda') return moeda.format(v);
  if (tipo === 'percentual') return v.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) + '%';
  if (tipo === 'multiplicador') return v.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) + 'x';
  return inteiro.format(v);
}
/** Dica (tooltip) dos cards do funil que têm fonte ou regra a explicar. */
const TITULO_CARD: Partial<Record<keyof ResumoAtm, string>> = {
  preCheckout: 'dados_atm_resumo.pre_checkout_pessoas · clique para ver a lista',
  vendas: 'dados_atm_resumo.vendas · clique para ver a lista',
  ingressosGrupo: 'dados_atm_resumo.grupo_entradas · clique para ver a evolução diária',
  percentualIngressoGrupo: 'dados_atm_resumo.grupo_pct = membros únicos no grupo ÷ leads × 100 · clique para ver a evolução diária',
  conversaoPreCheckout: 'dados_atm_resumo.conversao_pre_checkout_pct = compradores distintos ÷ pré-checkout × 100',
};
export function SeminarioAtmClient({ projeto, isMaster = false, podeVerContato = false, mostrarAvisoTeste = false }: { projeto: RegistroAtm; isMaster?: boolean; podeVerContato?: boolean; mostrarAvisoTeste?: boolean }) {
  const [resumo, setResumo] = useState<DashboardAtm | null>(null);
  const [serie, setSerie] = useState<Linha[]>([]);
  const [canais, setCanais] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [disparosDetalhe, setDisparosDetalhe] = useState<Resultado<DisparoDetalheAtm[]>>({ data: [], semDado: true, erro: null });
  const [trafego, setTrafego] = useState<Resultado<DadosTrafegoAtm>>({ data: trafegoAtmSemDado(), semDado: true, erro: null });
  const [comparecimento, setComparecimento] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [posLive, setPosLive] = useState<Resultado<Linha[]>>({ data: [], semDado: true, erro: null });
  const [canalAtivo, setCanalAtivo] = useState('whatsapp_api');
  // Modal aberto (Leads, Pré-checkout ou Vendas). Cada um lê a sua lista sozinho, fora do refresh grande da página
  // (correção de 13/10/2026: antes a lista de leads esperava o refresh inteiro e o modal abria em "0 leads · indisponível").
  const [modal, setModal] = useState<ModalFunilAtm | null>(null);
  const [periodoSelecionado, setPeriodoSelecionado] = useState<PresetPeriodoAtm>('evento');
  const [incluirTeste, setIncluirTeste] = useState(isMaster);
  const [versaoListas, setVersaoListas] = useState(0);
  const [listas] = useState(criarCarregadorListasAtm);
  const [atualizado, setAtualizado] = useState<Date | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [atualizando, setAtualizando] = useState(false);
  const emCurso = useRef(false);
  const pedidoPendente = useRef<PedidoAtualizacao | null>(null);
  const atualizarRef = useRef<(detalhado?: boolean) => Promise<void>>(async () => {});
  const periodoAtual = useRef<PresetPeriodoAtm>('evento');
  const [abaPrincipal, setAbaPrincipal] = useState<'edicao' | 'trafego' | 'historico'>('edicao');
  // O histórico só é lido na primeira vez que a aba é aberta; depois fica montado para não reler a cada troca.
  const [historicoAberto, setHistoricoAberto] = useState(false);
  const trocarAbaPrincipal = (k: string) => { const aba = k === 'historico' ? 'historico' : k === 'trafego' ? 'trafego' : 'edicao'; if (aba === 'historico') setHistoricoAberto(true); setAbaPrincipal(aba); };
  const idsEdicao = idsAba('atm-principal', 'edicao');
  const idsTrafego = idsAba('atm-principal', 'trafego');
  const idsHistorico = idsAba('atm-principal', 'historico');

  const atualizar = useCallback(async (detalhado = false) => {
    const pedido: PedidoAtualizacao = { periodo: datasDoPeriodo(periodoSelecionado), detalhado };
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
            carregarAtmDisparosLista(projeto.chave, atual.periodo).then((result) => { if (!result.semDado) { setDisparosDetalhe(result); teveLeitura = true; } else if (result.erro) setDisparosDetalhe((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }),
            carregarAtmTrafego(projeto.chave, atual.periodo).then((result) => { if (!result.semDado) { setTrafego(result); teveLeitura = true; } else if (result.erro) setTrafego((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }),
            carregarAtmComparecimento(projeto.chave).then((result) => { if (!result.semDado) { setComparecimento(result); teveLeitura = true; } else if (result.erro) setComparecimento((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }),
            carregarAtmPosLive(projeto.chave).then((result) => { if (!result.semDado) { setPosLive(result); teveLeitura = true; } else if (result.erro) setPosLive((prev) => ({ ...prev, erro: result.erro })); if (result.erro) erros.push(result.erro); }),
          ];
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
  }, [periodoSelecionado, projeto.chave]);

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
    void atualizarRef.current(true);
  }, [periodoSelecionado]);

  // Listas dos modais: chave = (RPC, evento, período, incluir teste). Mudar o período com o modal aberto muda a chave e
  // dispara a leitura; reabrir mostra a última lista da chave na hora e revalida. Só masters pedem as linhas de teste.
  const periodoLista = useMemo(() => datasDoPeriodo(periodoSelecionado), [periodoSelecionado]);
  const comTeste = isMaster && incluirTeste;
  const chaveDe = (rpc: string, periodo: typeof periodoLista | null, aberto: boolean) => (aberto ? chaveListaAtm(rpc, projeto.chave, periodo, comTeste) : null);
  const listaLeads = useListaAtm<LeadAtm>(listas, chaveDe('dados_atm_leads', periodoLista, modal === 'leads' && podeVerContato), () => carregarAtmLeads(projeto.chave, periodoLista, comTeste), versaoListas);
  const grupoPeriodo = useListaAtm<NumeroGrupoAtm>(listas, chaveDe('dados_atm_grupo_numeros', periodoLista, modal === 'leads' && podeVerContato), () => carregarAtmGrupo(projeto.chave, periodoLista, comTeste), versaoListas);
  // Pré-checkout e Vendas cruzam com o grupo do evento inteiro (quem está ou esteve no grupo, qualquer que seja o período).
  const grupoEvento = useListaAtm<NumeroGrupoAtm>(listas, chaveDe('dados_atm_grupo_numeros', null, (modal === 'preCheckout' || modal === 'vendas') && podeVerContato), () => carregarAtmGrupo(projeto.chave, undefined, comTeste), versaoListas);
  const listaPreCheckout = useListaAtm<PessoaPreCheckoutAtm>(listas, chaveDe('dados_atm_pre_checkout', periodoLista, modal === 'preCheckout' && podeVerContato), () => carregarAtmPreCheckout(projeto.chave, periodoLista, comTeste), versaoListas);
  const listaVendas = useListaAtm<VendaSessaoViabilidade>(listas, chaveDe('dados_atm_sv_vendas', null, modal === 'vendas' && podeVerContato), () => carregarAtmSvVendas(projeto.chave, comTeste), versaoListas);

  const atualizarTudo = async () => { setVersaoListas((v) => v + 1); await atualizar(true); };
  /** Depois de marcar/desmarcar teste: relê as listas abertas (o que se espera) e o resumo dos cards (por trás). */
  const depoisDaMarcacao = (result: { erro: string | null }): string | null => {
    if (result.erro) return result.erro;
    setVersaoListas((v) => v + 1);
    void atualizar(true);
    return null;
  };
  const SO_MASTER = 'Só masters podem marcar ou desmarcar testes.';
  const toggleLead = async (lead: LeadAtm, teste: boolean): Promise<string | null> => {
    if (!isMaster) return SO_MASTER;
    return depoisDaMarcacao(teste ? await marcarAtmTeste(projeto.chave, lead.email, lead.telefone) : await desmarcarAtmTeste(projeto.chave, lead.email, lead.telefone));
  };
  const toggleGrupo = async (numero: NumeroGrupoAtm, teste: boolean): Promise<string | null> => {
    if (!isMaster) return SO_MASTER;
    return depoisDaMarcacao(teste ? await marcarAtmTeste(projeto.chave, null, numero.foneKey) : await desmarcarAtmTeste(projeto.chave, null, numero.foneKey));
  };
  // Pré-checkout: marca pelo e-mail; só sem e-mail vai o telefone (o ramo de telefone do banco casa pelos 8 últimos dígitos).
  const togglePessoa = async (pessoa: PessoaPreCheckoutAtm, teste: boolean): Promise<string | null> => {
    if (!isMaster) return SO_MASTER;
    const telefone = pessoa.email ? null : pessoa.telefone;
    return depoisDaMarcacao(teste ? await marcarAtmTeste(projeto.chave, pessoa.email, telefone) : await desmarcarAtmTeste(projeto.chave, pessoa.email, telefone));
  };
  // Vendas: só pelo e-mail da venda (o ramo de telefone do banco não consulta vendas).
  const toggleVenda = async (venda: VendaSessaoViabilidade, teste: boolean): Promise<string | null> => {
    if (!isMaster) return SO_MASTER;
    if (!venda.email) return 'Esta venda não tem e-mail: a marcação é feita pelo e-mail.';
    return depoisDaMarcacao(teste ? await marcarAtmTeste(projeto.chave, venda.email, null) : await desmarcarAtmTeste(projeto.chave, venda.email, null));
  };

  const linhasResumo = useMemo(() => METRICAS_RESUMO_ATM.map((m) => ({ ...m, metrica: metricaDoCardAtm(resumo?.resumo, m.chave) })), [resumo]);
  // Resumo ainda não lido na primeira carga: o card diz que está carregando em vez de "Não lançado".
  const carregandoResumo = resumo === null && atualizando;
  const abrirCard = (chave: keyof ResumoAtm) => { const alvo = modalDoCardAtm(chave); if (alvo) setModal(alvo); };
  const canal = canais.data.find((x) => x.canal === canalAtivo);
  const sessao = comparecimento.data[0];
  const ciclo = (nome: string) => posLive.data.find((x) => x.ciclo === nome);
  const renderVal = (v: unknown, tipo: string) => { const n = valor(v); return n == null ? 'Não lançado' : formatar(n, tipo); };
  const intervalo = resumo?.periodo.de && resumo.periodo.ate ? `${dataPtBr(resumo.periodo.de)} a ${dataPtBr(resumo.periodo.ate)}` : 'sem dado ainda';
  const alertasTeste = montarAvisosTesteAtm(resumo?.periodo);
  const investimentoTotal = resumo?.resumo.investimentoTotal;
  const custoDisparoInvestimento = resumo?.resumo.custoDisparo;
  const custoTrafegoInvestimento = resumo?.resumo.custoTrafego;
  // Período aplicado para o eixo da Evolução e o recorte das vendas: as datas pedidas; no "período do evento" (datas nulas),
  // as que o resumo devolveu (início e fim do cadastro do evento, a mesma janela que o banco usa no card).
  const periodoModal = { de: periodoLista.p_de ?? resumo?.periodo.de ?? null, ate: periodoLista.p_ate ?? resumo?.periodo.ate ?? null };
  const comumModal = { onClose: () => setModal(null), periodoLabel: intervalo, periodo: periodoModal, isMaster, incluirTeste: comTeste, onIncluirTeste: setIncluirTeste };

  return <div className="max-w-7xl space-y-5">
    <header><LinkVoltar href="/infra/dashboards/escritorio" para="Soluções" /><div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dashboards / Soluções / Seminário ATM</div><h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{projeto.rotulo}</h1><p className="mt-1 text-sm text-[var(--fg-2)]">Chave {projeto.chave} · {atualizado ? 'atualizado às ' + atualizado.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : 'aguardando leitura'}</p></header>
    <Tabs idBase="atm-principal" label="Seções do dashboard" active={abaPrincipal} onChange={trocarAbaPrincipal} tabs={[{ k: 'edicao', l: 'Esta edição' }, { k: 'trafego', l: 'Tráfego' }, { k: 'historico', l: 'Histórico' }]} />
    <div role="tabpanel" id={idsEdicao.panel} aria-labelledby={idsEdicao.tab} hidden={abaPrincipal !== 'edicao'} className="space-y-5">
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
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <Card className="min-w-0 overflow-hidden p-4" style={{ borderLeft: '4px solid var(--accent)' }}>
        <div className="truncate text-xs font-medium uppercase tracking-wide text-[var(--fg-3)]">Investimento geral</div>
        <div className="mt-1 break-words text-lg font-bold tabular leading-tight tracking-[-0.01em] text-[var(--fg)]">{!investimentoTotal || investimentoTotal.semDado ? 'Sem dado' : formatar(investimentoTotal.valor, 'moeda')}</div>
        {(!investimentoTotal || investimentoTotal.semDado) && <div className="mt-1 text-[11px] text-[var(--fg-3)]">sem dado ainda</div>}
        <div className="mt-3 space-y-2 border-t border-[var(--border)] pt-3 text-xs">
          <div className="flex items-center justify-between gap-2"><span className="text-[var(--fg-3)]">Disparo</span><strong className="tabular text-[var(--fg)]">{!custoDisparoInvestimento || custoDisparoInvestimento.semDado ? 'Sem dado' : moeda.format(custoDisparoInvestimento.valor)}</strong></div>
          <div className="flex items-center justify-between gap-2"><span className="text-[var(--fg-3)]">Tráfego</span><strong className="tabular text-[var(--fg)]">{!custoTrafegoInvestimento || custoTrafegoInvestimento.semDado ? 'Sem dado' : moeda.format(custoTrafegoInvestimento.valor)}</strong></div>
        </div>
      </Card>
      {linhasResumo.map((m) => <button key={m.chave} type="button" onClick={() => abrirCard(m.chave)} className="text-left"><KpiCard label={m.rotulo} value={m.metrica.semDado ? (carregandoResumo ? 'Carregando…' : 'Não lançado') : formatar(m.metrica.valor, m.formato)} hint={m.metrica.semDado && !carregandoResumo ? 'sem dado ainda' : undefined} bar={m.chave === 'vendas' ? 'green' : 'accent'} title={TITULO_CARD[m.chave] ? `${TITULO_CARD[m.chave]} · ${intervalo}` : undefined} /></button>)}
    </div>
    <SectionCard title="Evolução diária" subtitle={`Leads, grupo, pré-checkout, vendas, faturamento e custo. ${intervalo}`}>
      {serie.length ? <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="text-left text-xs text-[var(--fg-3)]">{['Dia', 'Leads', 'Ingresso no grupo', 'Saídas', 'Pré-checkout', 'Vendas', 'Faturamento bruto', 'Custo disparo'].map((x) => <th key={x} className="p-2">{x}</th>)}</tr></thead><tbody>{serie.map((r) => <tr key={String(r.dia)} className="border-t border-[var(--border)]">{['dia', 'leads', 'grupo_entradas', 'grupo_saidas', 'pre_checkout', 'vendas', 'receita_bruta', 'custo_disparo_centavos'].map((k) => <td key={k} className="p-2">{k === 'dia' ? String(r[k] ?? '') : renderVal(k === 'custo_disparo_centavos' && valor(r[k]) != null ? (valor(r[k]) ?? 0) / 100 : r[k], k === 'receita_bruta' || k === 'custo_disparo_centavos' ? 'moeda' : 'inteiro')}</td>)}</tr>)}</tbody></table></div> : <EmptyState title="Sem série disponível" hint="sem dado ainda" />}
    </SectionCard>
    <SectionCard title="Disparos" subtitle="Totais por canal no período selecionado.">
      <div className="mb-4 flex flex-wrap gap-2">{CANAIS_DISPARO_ATM.map((c) => { const key = c.canal === 'api' ? 'whatsapp_api' : c.canal; return <button key={c.canal} onClick={() => setCanalAtivo(key)} className={'rounded-[var(--r-md)] px-3 py-2 text-sm ' + (canalAtivo === key ? 'bg-[var(--accent)] text-black font-semibold' : 'bg-[var(--surface-3)] text-[var(--fg-2)]')}>{c.rotulo}</button>; })}</div>
      {canais.erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{canais.erro}</p>}
      {canal ? <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{[['Disparos', 'disparos'], ['Enviados', 'enviados'], ['Entregues', 'entregues'], ['Lidas / atendidas', 'lidas'], ['Cliques', 'cliques'], ['Falhas', 'falhas'], ['Custo', 'custo_centavos']].map(([label, key]) => { const n = valor(canal[key]); const money = key === 'custo_centavos'; return <KpiCard key={key} label={label} value={n == null ? 'Não lançado' : formatar(money ? n / 100 : n, money ? 'moeda' : 'inteiro')} hint={n == null || canais.semDado ? 'sem dado ainda' : undefined} />; })}</div> : <EmptyState title="Sem dados para este canal" hint="sem dado ainda" />}
      <DisparosDetalhe result={disparosDetalhe} canal={canalAtivo} />
    </SectionCard>
    <SectionCard title="Comparecimento" subtitle="Dados por sessão, conforme cadastro no banco. Este bloco considera o evento inteiro.">
      {comparecimento.erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{comparecimento.erro}</p>}
      {comparecimento.data.length ? <><div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{CARDS_COMPARECIMENTO.map((c) => { const n = valor(sessao?.[c.chave]); return <KpiCard key={c.chave} label={c.rotulo} value={renderVal(n, c.tipo)} hint={n == null ? 'sem dado ainda' : c.ajuda} />; })}</div><p className="mt-3 text-sm text-[var(--fg-3)]">{AJUDA_EQUIPE}</p></> : <EmptyState title="Comparecimento ainda não lançado" hint="sem dado ainda" />}
    </SectionCard>
    <SectionCard title="Pós-live" subtitle="Vendas e conversão em ciclos separados. Este bloco considera o evento inteiro.">
      {posLive.erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{posLive.erro}</p>}
      {posLive.data.length ? <div className="grid gap-4 md:grid-cols-2">{(['aberto', 'fechado'] as const).map((nome) => { const p = ciclo(nome); return <div key={nome} className="rounded-[var(--r-md)] border border-[var(--border)] p-4"><h3 className="font-semibold capitalize">Ciclo {nome}</h3><div className="mt-3 grid grid-cols-2 gap-3"><KpiCard label="Vendas" value={renderVal(p?.vendas, 'inteiro')} hint={p?.vendas == null ? 'sem dado ainda' : undefined} /><KpiCard label="Conversão" value={renderVal(p?.conversao_pct, 'percentual')} hint={p?.conversao_pct == null ? 'sem dado ainda' : undefined} /></div></div>; })}</div> : <EmptyState title="Pós-live sem dados" hint="sem dado ainda" />}
    </SectionCard>
    <ModalEvolucaoIngressoGrupo open={modal === 'grupo'} onClose={() => setModal(null)} titulo={`% ingresso no grupo · evolução diária · ${projeto.rotulo}`} serie={serie.length ? { data: serie, erro } : atualizando ? { data: null, carregando: true } : erro ? { data: null, erro } : { data: [] }} />
    <ModalLeadsAtm {...comumModal} open={modal === 'leads'} card={metricaDoCardAtm(resumo?.resumo, 'leads')} lista={listaLeads} grupo={podeVerContato ? grupoPeriodo : null} podeVerContato={podeVerContato} onToggleLead={toggleLead} onToggleGrupo={toggleGrupo} />
    <ModalPreCheckoutAtm {...comumModal} open={modal === 'preCheckout'} card={metricaDoCardAtm(resumo?.resumo, 'preCheckout')} lista={listaPreCheckout} grupo={grupoEvento} podeVerContato={podeVerContato} onTogglePessoa={togglePessoa} />
    <ModalVendasAtm {...comumModal} open={modal === 'vendas'} card={metricaDoCardAtm(resumo?.resumo, 'vendas')} lista={listaVendas} grupo={grupoEvento} podeVerContato={podeVerContato} vendasTeste={resumo?.periodo.vendasTeste ?? null} onToggleVenda={toggleVenda} linkRetorno={projeto.retornoSvUrl} />
    </div>
    <div role="tabpanel" id={idsTrafego.panel} aria-labelledby={idsTrafego.tab} hidden={abaPrincipal !== 'trafego'}>
      {abaPrincipal === 'trafego' && <TrafegoAtm result={trafego} />}
    </div>
    <div role="tabpanel" id={idsHistorico.panel} aria-labelledby={idsHistorico.tab} hidden={abaPrincipal !== 'historico'}>
      {historicoAberto && <HistoricoAtm familia={projeto.familia} />}
    </div>
  </div>;
}
