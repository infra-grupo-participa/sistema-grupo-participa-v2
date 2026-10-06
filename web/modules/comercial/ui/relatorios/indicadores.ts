// Agregações dos relatórios do Comercial (playbook, seções 12 e 14). Funções puras, testáveis.
// O fechamento do dia em si vem de domain/fechamento.ts; aqui ficam as visões de funil, equipe e o texto do Slack.
import { ETAPAS, MOTIVOS_PADRAO, produto as produtoDe, rotuloMotivo } from '../../domain/catalogo';
import { funilPorEtapa, mesmoDia, type FechamentoDia, type LinhaFechamento } from '../../domain/fechamento';
import { atividadeAtrasada } from '../../domain/regras';
import type { Atividade, EtapaKey, MotivoPerda, MotivoPerdaConfig, Negocio, ProdutoKey, Vendedor } from '../../domain/types';

// ── Dia do fechamento ──

export type OpcaoDia = 'hoje' | 'ontem' | 'data';

/**
 * Instante de referência do fechamento. Hoje = agora (atrasadas contam até este minuto);
 * dia passado = fim daquele dia (23:59), para as atrasadas refletirem o fechamento dele.
 */
export function instanteDoDia(opcao: OpcaoDia, ymd: string, agora: Date): Date {
  if (opcao === 'hoje') return agora;
  if (opcao === 'ontem') {
    const d = new Date(agora);
    d.setDate(d.getDate() - 1);
    d.setHours(23, 59, 59, 0);
    return d;
  }
  const m = ymd.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return agora;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 23, 59, 59);
  return d.getTime() > agora.getTime() ? agora : d;
}

/** 'YYYY-MM-DD' local (valor do input de data). */
export function ymdLocal(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// ── Vendas do dia por produto e vendedor ──

export interface VendaAgrupada {
  produto: ProdutoKey;
  donoId: string | null;
  quantidade: number;
  valor: number;
}

/** Ganhos do dia agrupados por produto + vendedor (o fechamento base não traz o vendedor por produto). */
export function vendasDoDia(negocios: Negocio[], dia: Date): VendaAgrupada[] {
  const mapa = new Map<string, VendaAgrupada>();
  for (const n of negocios) {
    if (n.status !== 'ganho' || !mesmoDia(n.fechadoEm, dia)) continue;
    const k = `${n.produto}|${n.donoId ?? ''}`;
    const v = mapa.get(k) ?? { produto: n.produto, donoId: n.donoId, quantidade: 0, valor: 0 };
    v.quantidade += 1;
    v.valor += n.valor;
    mapa.set(k, v);
  }
  return [...mapa.values()].sort((a, b) => b.valor - a.valor);
}

// ── Texto do Slack ──

const brl = (n: number) => n.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

export interface DadosTextoSlack {
  fechamento: FechamentoDia;
  vendas: VendaAgrupada[];
  dia: Date;
  nomeDe: (id: string | null) => string;
  /** Ordem dos vendedores no texto. */
  vendedorIds: string[];
  /** Cadastro de motivos (`repo.motivosPerda()`), para nomear os personalizados. */
  motivos?: Pick<MotivoPerdaConfig, 'key' | 'label'>[];
}

/** Mensagem simples para o #comercial às 19h. Sem emoji, sem formatação além de quebras de linha. */
export function textoFechamentoSlack({ fechamento, vendas, dia, nomeDe, vendedorIds, motivos = MOTIVOS_PADRAO }: DadosTextoSlack): string {
  const t = fechamento.total;
  const data = dia.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo', weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric' });
  const l: string[] = [];
  l.push(`Fechamento do Comercial: ${data}`);
  l.push('');
  l.push(`Leads abordados: ${t.abordados}`);
  l.push(`Leads que entraram em contato: ${t.entraramEmContato}`);
  l.push(`Leads que responderam: ${t.responderam}`);
  l.push(`Em negociação: ${t.emNegociacao} (${t.entraramEmNegociacaoHoje} entraram hoje)`);
  l.push(`Vendas: ${t.vendas} (${brl(t.receita)})`);
  for (const v of vendas) {
    l.push(`- ${produtoDe(v.produto).nome}: ${v.quantidade} (${brl(v.valor)}), ${nomeDe(v.donoId)}`);
  }
  l.push('');
  l.push('Por vendedor:');
  for (const id of vendedorIds) {
    const x = fechamento.porVendedor[id];
    if (!x) continue;
    l.push(`- ${nomeDe(id)}: ${linhaCurta(x)}`);
  }
  l.push('');
  l.push('Alertas:');
  const a = fechamento.alertas;
  l.push(`- Negócios sem próxima atividade: ${a.semProximaAtividade} (meta zero)`);
  l.push(`- Leads sem dono: ${a.semDono} (meta zero)`);
  const atr = Object.entries(a.atrasadasPorVendedor).filter(([, n]) => n > 0);
  l.push(`- Atividades atrasadas: ${atr.length ? atr.map(([id, n]) => `${nomeDe(id)} ${n}`).join(', ') : 'nenhuma'}`);
  const perd = Object.entries(a.perdidosPorMotivo).filter(([, n]) => (n ?? 0) > 0) as [MotivoPerda, number][];
  l.push(`- Perdidos do dia: ${perd.length ? perd.map(([m, n]) => `${rotuloMotivo(m, motivos)} ${n}`).join(', ') : 'nenhum'}`);
  return l.join('\n');
}

function linhaCurta(x: LinhaFechamento): string {
  return `abordou ${x.abordados}, entraram ${x.entraramEmContato}, responderam ${x.responderam}, em negociação ${x.emNegociacao} (+${x.entraramEmNegociacaoHoje}), vendas ${x.vendas} (${brl(x.receita)})`;
}

// ── Funil: conversão por etapa ──

export interface LinhaConversao {
  etapa: EtapaKey;
  chegaram: number;
  /** % do total que entrou no funil. */
  doTotal: number;
  /** % que veio da etapa anterior (passagem). null na primeira etapa. */
  passagem: number | null;
}

/** Só "Venda ativa": as origens da Hotmart não passam pelas etapas. */
export function conversaoPorEtapa(negocios: Negocio[], prod: ProdutoKey | 'todos'): LinhaConversao[] {
  const base = negocios.filter((n) => n.origem === 'venda_ativa' && (prod === 'todos' || n.produto === prod));
  const linhas = funilPorEtapa(base, ETAPAS.map((e) => e.key));
  const topo = linhas[0]?.chegaram ?? 0;
  return linhas.map((x, i) => {
    const anterior = i > 0 ? linhas[i - 1].chegaram : null;
    return {
      etapa: x.etapa as EtapaKey,
      chegaram: x.chegaram,
      doTotal: topo ? (x.chegaram / topo) * 100 : 0,
      passagem: anterior == null ? null : anterior ? (x.chegaram / anterior) * 100 : 0,
    };
  });
}

export interface TempoEtapa {
  etapa: EtapaKey;
  abertos: number;
  /** Média de minutos parados na etapa (estimativa pelos abertos). null = ninguém aberto ali. */
  mediaMin: number | null;
}

/**
 * Tempo médio em cada etapa, ESTIMADO pelos negócios abertos (agora − etapaDesde).
 * O histórico de passagem por etapa entra com o backend; até lá é o retrato de quem está parado.
 */
export function tempoMedioPorEtapa(negocios: Negocio[], prod: ProdutoKey | 'todos', agora: Date): TempoEtapa[] {
  return ETAPAS.filter((e) => e.key !== 'fechado').map((e) => {
    const abertos = negocios.filter((n) => n.status === 'aberto' && n.origem === 'venda_ativa' && n.etapa === e.key && (prod === 'todos' || n.produto === prod));
    const mins = abertos.map((n) => (agora.getTime() - new Date(n.etapaDesde).getTime()) / 60000).filter((m) => Number.isFinite(m) && m >= 0);
    return { etapa: e.key, abertos: abertos.length, mediaMin: mins.length ? mins.reduce((s, m) => s + m, 0) / mins.length : null };
  });
}

export interface LinhaMotivo {
  motivo: MotivoPerda;
  rotulo: string;
  nota: string | null;
  quantidade: number;
  /** "Já atendido por outro vendedor" = falha de distribuição. */
  falhaDistribuicao: boolean;
  /** Motivo que avisa o gestor (falha de processo): pinta a barra de vermelho quando há perdido. */
  alertaGestor: boolean;
  /** Criado pelo gestor (fora dos 9 do playbook). */
  personalizado: boolean;
  /** Desativado no cadastro (só aparece se ainda tem perdido no recorte). */
  desativado: boolean;
}

/**
 * Contagem por motivo na ordem do cadastro: todos os ativos (inclusive zerados), os desativados que ainda
 * têm perdido e, no fim, qualquer chave que não esteja mais no cadastro (rótulo pela própria chave).
 */
export function perdidosPorMotivo(
  negocios: Negocio[],
  prod: ProdutoKey | 'todos',
  cadastro: MotivoPerdaConfig[] = MOTIVOS_PADRAO,
): LinhaMotivo[] {
  const cont = new Map<MotivoPerda, number>();
  for (const n of negocios) {
    if (n.status !== 'perdido' || !n.motivoPerda) continue;
    if (prod !== 'todos' && n.produto !== prod) continue;
    cont.set(n.motivoPerda, (cont.get(n.motivoPerda) ?? 0) + 1);
  }
  const linhas: LinhaMotivo[] = cadastro
    .filter((m) => m.ativo || cont.has(m.key))
    .map((m) => ({
      motivo: m.key,
      rotulo: m.label,
      nota: m.nota,
      quantidade: cont.get(m.key) ?? 0,
      falhaDistribuicao: m.key === 'ja_atendido_outro_vendedor',
      alertaGestor: m.alertaGestor,
      personalizado: !m.sistema,
      desativado: !m.ativo,
    }));
  const conhecidas = new Set(cadastro.map((m) => m.key));
  for (const [k, q] of cont) {
    if (conhecidas.has(k)) continue;
    linhas.push({
      motivo: k, rotulo: rotuloMotivo(k, cadastro), nota: null, quantidade: q,
      falhaDistribuicao: false, alertaGestor: false, personalizado: true, desativado: false,
    });
  }
  return linhas;
}

/** "12 min", "5 h", "3 dias". */
export function fmtDuracao(min: number | null): string {
  if (min == null) return '—';
  if (min < 60) return `${Math.round(min)} min`;
  const h = min / 60;
  if (h < 24) return `${Math.round(h)} h`;
  const d = Math.round(h / 24);
  return `${d} ${d === 1 ? 'dia' : 'dias'}`;
}

// ── Equipe: ranking ──

export interface LinhaEquipe {
  vendedorId: string;
  vendas: number;
  receita: number;
  ganhos: number;
  encerrados: number;
  /** ganhos / encerrados (%). null = nenhum encerrado no período. */
  conversao: number | null;
  abertos: number;
  concluidas: number;
  atrasadas: number;
}

/**
 * Por vendedor: vendas e receita (ganhos no período), conversão (ganhos ÷ ganhos+perdidos no período),
 * carga (negócios abertos agora), atividades concluídas no período e atrasadas agora.
 * `desde` null = todo o histórico.
 */
export function rankingEquipe(
  vendedores: Vendedor[],
  negocios: Negocio[],
  atividades: Atividade[],
  agora: Date,
  desde: Date | null,
): LinhaEquipe[] {
  const noPeriodo = (iso: string | null) => !!iso && (!desde || new Date(iso).getTime() >= desde.getTime()) && new Date(iso).getTime() <= agora.getTime();
  return vendedores.map((v) => {
    const meus = negocios.filter((n) => n.donoId === v.id);
    const ganhos = meus.filter((n) => n.status === 'ganho' && noPeriodo(n.fechadoEm));
    const perdidos = meus.filter((n) => n.status === 'perdido' && noPeriodo(n.fechadoEm));
    const encerrados = ganhos.length + perdidos.length;
    const minhas = atividades.filter((a) => a.donoId === v.id);
    return {
      vendedorId: v.id,
      vendas: ganhos.length,
      receita: ganhos.reduce((s, n) => s + n.valor, 0),
      ganhos: ganhos.length,
      encerrados,
      conversao: encerrados ? (ganhos.length / encerrados) * 100 : null,
      abertos: meus.filter((n) => n.status === 'aberto').length,
      concluidas: minhas.filter((a) => noPeriodo(a.concluidaEm)).length,
      atrasadas: minhas.filter((a) => atividadeAtrasada(a, agora)).length,
    };
  });
}

export type ColunaEquipe = 'nome' | 'vendas' | 'receita' | 'conversao' | 'abertos' | 'concluidas' | 'atrasadas';

/** Ordena o ranking. Conversão null vai sempre para o fim. */
export function ordenarEquipe(
  linhas: LinhaEquipe[],
  coluna: ColunaEquipe,
  dir: 'asc' | 'desc',
  nomeDe: (id: string) => string,
): LinhaEquipe[] {
  const s = dir === 'asc' ? 1 : -1;
  return [...linhas].sort((a, b) => {
    if (coluna === 'nome') return s * nomeDe(a.vendedorId).localeCompare(nomeDe(b.vendedorId), 'pt-BR');
    const va = a[coluna];
    const vb = b[coluna];
    if (va == null && vb == null) return 0;
    if (va == null) return 1;
    if (vb == null) return -1;
    return s * (va - vb) || nomeDe(a.vendedorId).localeCompare(nomeDe(b.vendedorId), 'pt-BR');
  });
}
