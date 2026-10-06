// Marketing > Tráfego: MODO DE DEMONSTRAÇÃO (só desenvolvimento local). Contas, campanhas, gasto, verba e leads
// INVENTADOS, em memória, para ver a tela sem dado real e antes da coleta Meta/Google existir. Nunca é usado em
// produção: trafego-data.ts só liga com NEXT_PUBLIC_TRAFEGO_DEMO=1 E NODE_ENV diferente de 'production', e a tela mostra
// a faixa "Dados de demonstração". Recarregar a página volta ao começo.
// O que vem da semente real: os 4 projetos e os gestores da 20261005m, os objetivos (20261005m + CARRINHO e AQUECIMENTO
// da 20261006g + ANTECIPAÇÃO da 20261006e) e as listas da 20261006g (plataformas, status, fases, objetivo → fase) e da 20261006j (unidades, tipos de
// lançamento e regras, os 2 especialistas internos semeados, UTM do Meta) e da 20261006l (os 9 modelos de exemplo, rascunho). Todo o resto é
// ficção: projetos "… Exemplo", contas "Conta Exemplo", "Especialista Exemplo", ids 0000…, descrições de campanha
// "EXEMPLO", números gerados. Os projetos reais da semente ficam sem unidade, tipo de lançamento e contas (não estão em fonte).
import { traduzirCampanha } from '../../projetos/domain/campanha';
import { calcularAlertas, type ProjetoEntrada } from '../domain/alertas';
import {
  PROJETO_FORM_VAZIO, lancamentoAutomatico, montarChecklist, nomeTemSigla, periodoProjeto, periodoReceita, validarCadastro,
  type Especialista, type ItemProjeto, type ListasCadastro, type ProjetoCadastro, type ProjetoForm,
} from '../domain/cadastro';
import { filtrarEtiquetas, type BuscaEtiquetas, type EtiquetaClickup } from '../domain/etiquetas';
import { faseDaCampanha } from '../domain/fases';
import {
  modelosDoProjeto, previaModelo, somaPct, validarModelo, type Esperada, type Modelo, type Momento, type PreviaModelo, type RefData,
} from '../domain/modelos';
import { comKpis } from '../domain/kpis';
import type {
  Campanha, Checklist, ClickupProjeto, ConfigTrafego, Conta, Dono, FaseProjeto, LinhaResumo, ProdutoHotmart, ProdutoVisto,
  Regra, Resposta, ResumoDia, Subarea, TarefaClickup, Tipo, VidaProjeto,
} from '../domain/tipos';
import { ordenarContas, unidadesDoDono } from '../domain/tipos';

const hoje = (n = 0) => {
  const d = new Date(Date.now() + n * 86400000);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const ONTEM = hoje(-1);
// status que não entram no resumo do dia (mkt_trafego.status_projeto.entra_no_resumo_dia = false, 20261006i)
const FORA_DO_RESUMO = new Set(['em_planejamento', 'inativo', 'encerrado']);

const GESTORES = [{ sigla: 'CF', nome: 'Caio Fábio' }, { sigla: 'RS', nome: 'Renan Schwarz' }, { sigla: 'EF', nome: 'Emmanuel Fernandes' }];
const OBJETIVOS = ['LEADS', 'VENDAS', 'REMARKETING', 'LEMBRETE', 'DISTRIBUIÇÃO', 'CARRINHO', 'AQUECIMENTO', 'ANTECIPAÇÃO'];
const OBJETIVO_FASE: Record<string, string> = {
  LEADS: 'captacao', VENDAS: 'captacao', LEMBRETE: 'lembrete', REMARKETING: 'remarketing', CARRINHO: 'abertura_carrinho', AQUECIMENTO: 'aquecimento',
  ANTECIPAÇÃO: 'antecipacao',
};
const CONFIG: ConfigTrafego = {
  plataformas: [{ codigo: 'meta', nome: 'Meta Ads' }, { codigo: 'google', nome: 'Google Ads' }],
  status: [{ codigo: 'em_planejamento', nome: 'Em planejamento' }, { codigo: 'ativo', nome: 'Ativo' }, { codigo: 'pausado', nome: 'Pausado' },
    { codigo: 'inativo', nome: 'Inativo' }, { codigo: 'encerrado', nome: 'Encerrado' }],
  fases: [
    { codigo: 'aquecimento', nome: 'Aquecimento' }, { codigo: 'antecipacao', nome: 'Antecipação' }, { codigo: 'captacao', nome: 'Captação' }, { codigo: 'lembrete', nome: 'Lembrete' },
    { codigo: 'remarketing', nome: 'Remarketing' }, { codigo: 'abertura_carrinho', nome: 'Abertura de carrinho' },
  ],
  gestores: GESTORES,
  base_pessoas: true,
  base_web: true,
  objetivo_fase: OBJETIVO_FASE,
  dia_ontem: ONTEM,
};

interface ProjetoDemo {
  id: number; sigla: string; nome: string; linha: string; ativo: boolean; etiqueta_clickup: string | null;
  tipo: Tipo | null; unidade: string | null; tipo_lancamento: string | null; especialista_id: number | null;
  inicio: string | null; fim: string | null; captacao_inicio: string | null; captacao_fim: string | null; evento_inicio: string | null; evento_fim: string | null;
}
const pd = (x: Partial<ProjetoDemo> & Pick<ProjetoDemo, 'id' | 'sigla' | 'nome' | 'linha'>): ProjetoDemo => ({
  ativo: true, etiqueta_clickup: null, tipo: null, unidade: null, tipo_lancamento: null, especialista_id: null,
  inicio: null, fim: null, captacao_inicio: null, captacao_fim: null, evento_inicio: null, evento_fim: null, ...x,
});
const PROJETOS: ProjetoDemo[] = [
  // semente real (20261005m): interno sem unidade (CSM ou Escritório não está em fonte); SEMSET26 sem tipo
  pd({ id: 1, sigla: 'PB26', nome: 'Patrimônio Brasil 2026', linha: 'Patrimônio Brasil', etiqueta_clickup: 'seminario-conjunto-2026-11', tipo: 'interno' }),
  pd({ id: 2, sigla: 'HT33', nome: 'Holding Total 33', linha: 'Holding Total', tipo: 'interno' }),
  pd({ id: 3, sigla: 'SEMSET26', nome: 'Seminário setembro 2026', linha: 'Seminário', etiqueta_clickup: 'sem-set-2026' }),
  pd({ id: 4, sigla: 'BF26', nome: 'Black Friday 2026', linha: 'Black Friday', etiqueta_clickup: 'black-friday-2026-10', tipo: 'interno' }),
  // fictícios
  pd({ id: 5, sigla: 'DEXA26', nome: 'Seminário Diamante Exemplo', linha: 'Exemplo', tipo: 'externo', unidade: 'diamantes', tipo_lancamento: 'lancamento_classico', especialista_id: 3 }),
  pd({ id: 6, sigla: 'AEXA26', nome: 'Palestra Aurum Exemplo', linha: 'Exemplo', tipo: 'externo', unidade: 'aurum', tipo_lancamento: 'palestra' }),
  pd({ id: 7, sigla: 'LPEXA26', nome: 'Lançamento Pago Exemplo', linha: 'Exemplo', etiqueta_clickup: 'lancamento-pago-exemplo-2026-10', tipo: 'interno', unidade: 'csm',
    tipo_lancamento: 'lancamento_pago', captacao_inicio: hoje(-8), captacao_fim: hoje(12), evento_inicio: hoje(15), evento_fim: hoje(17), inicio: hoje(-8), fim: hoje(17) }),
];
const subareaDe = (p: ProjetoDemo): Subarea | null => (p.tipo === 'interno' ? 'interno' : p.unidade === 'aurum' ? 'aurum' : p.unidade === 'diamantes' ? 'diamante' : null);
// contas de anúncio dos projetos fictícios (os reais ficam sem)
const PROJETO_CONTAS = new Map<number, number[]>([[5, [3]], [7, [1]]]);
// páginas: as 4 do PB26 da semente real
const PAGINAS = new Map<number, { codigo: string; nome: string }[]>([[1, [{ codigo: 'ak1', nome: 'AK1' }]]]);
const N_PAGINAS: Record<number, number> = { 1: 4 };

interface Plan { status: string | null; gestores: string[]; verba_maxima: number | null; verba_diaria: number | null; meta_leads: number | null; meta_receita: number | null; meta_cpl: number | null; meta_pct_mql: number | null; obs: string | null }
const PLAN = new Map<number, Plan>([
  [1, { status: 'ativo', gestores: ['RS', 'CF'], verba_maxima: 20000, verba_diaria: 500, meta_leads: 2000, meta_receita: null, meta_cpl: 10, meta_pct_mql: 30, obs: null }],
  [2, { status: 'ativo', gestores: ['CF'], verba_maxima: 15000, verba_diaria: 400, meta_leads: null, meta_receita: 60000, meta_cpl: null, meta_pct_mql: null, obs: null }],
  [4, { status: 'pausado', gestores: ['CF'], verba_maxima: 8000, verba_diaria: null, meta_leads: 500, meta_receita: null, meta_cpl: null, meta_pct_mql: null, obs: null }],
  [6, { status: 'em_planejamento', gestores: ['EF'], verba_maxima: null, verba_diaria: null, meta_leads: null, meta_receita: null, meta_cpl: null, meta_pct_mql: null, obs: 'Projeto fictício em planejamento: fica fora do resumo do dia.' }],
  [5, { status: 'ativo', gestores: ['EF'], verba_maxima: 3000, verba_diaria: 100, meta_leads: 300, meta_receita: null, meta_cpl: 8, meta_pct_mql: null, obs: 'Projeto fictício do modo de demonstração.' }],
  [7, { status: 'ativo', gestores: ['RS'], verba_maxima: 9000, verba_diaria: 300, meta_leads: null, meta_receita: null, meta_cpl: null, meta_pct_mql: null, obs: 'Projeto fictício do modo de demonstração.' }],
]);

interface FaseDemo { id: number; projeto_id: number; fase: string; verba: number | null; inicio: string | null; fim: string | null; obs: string | null }
let FASES: FaseDemo[] = [
  { id: 1, projeto_id: 1, fase: 'aquecimento', verba: 4000, inicio: hoje(-25), fim: hoje(-11), obs: null },
  { id: 2, projeto_id: 1, fase: 'captacao', verba: 14000, inicio: hoje(-10), fim: hoje(15), obs: null },
  { id: 3, projeto_id: 1, fase: 'lembrete', verba: 2000, inicio: hoje(16), fim: hoje(20), obs: null },
  { id: 4, projeto_id: 5, fase: 'captacao', verba: 3000, inicio: hoje(-12), fim: hoje(8), obs: null },
];

const CONTAS: Conta[] = [
  { id: 1, plataforma: 'meta', conta_externa: '000000000000001', nome: 'Conta Exemplo Grupo (Meta)', dono: 'grupo', cliente: null, moeda: 'BRL', ativa: true, obs: null, campanhas: 0, unidade: 'csm', principal: true },
  { id: 2, plataforma: 'google', conta_externa: '0000000001', nome: 'Conta Exemplo Grupo (Google)', dono: 'grupo', cliente: null, moeda: 'BRL', ativa: true, obs: null, campanhas: 0, unidade: 'csm', principal: false },
  { id: 3, plataforma: 'meta', conta_externa: '000000000000002', nome: 'Conta Exemplo Diamante', dono: 'diamante', cliente: 'Diamante Exemplo', moeda: 'BRL', ativa: true, obs: null, campanhas: 0, unidade: 'diamantes', principal: false },
  { id: 4, plataforma: 'meta', conta_externa: '000000000000003', nome: 'Conta Exemplo Escritório', dono: 'grupo', cliente: null, moeda: 'BRL', ativa: true, obs: null, campanhas: 0, unidade: 'escritorio', principal: true },
  { id: 5, plataforma: 'meta', conta_externa: '000000000000004', nome: 'Conta Exemplo Inativa', dono: 'grupo', cliente: null, moeda: 'BRL', ativa: false, obs: 'Exemplo de conta cadastrada e inativa (fora da seleção e da coleta).', campanhas: 0, unidade: 'csm', principal: false },
];

interface CampDemo { id: number; plataforma: string; conta_id: number; nome: string; status: string; projeto_manual_id: number | null; fase_manual: string | null }
const camp = (id: number, plataforma: string, conta_id: number, nome: string, status: string): CampDemo =>
  ({ id, plataforma, conta_id, nome, status, projeto_manual_id: null, fase_manual: null });
const CAMPS: CampDemo[] = [
  camp(1, 'meta', 1, 'RS | PB26 | LEADS | EXEMPLO PÚBLICO FRIO | AK1', 'ACTIVE'),
  camp(2, 'meta', 1, 'RS | PB26 | AQUECIMENTO | EXEMPLO VÍDEO', 'PAUSED'),
  camp(3, 'google', 2, 'CF | PB26 | LEADS | EXEMPLO PESQUISA', 'ENABLED'),
  camp(4, 'meta', 1, 'CF | HT33 | VENDAS | EXEMPLO INGRESSO', 'ACTIVE'),
  camp(5, 'meta', 1, 'cf | bf26 | remarketing | exemplo', 'PAUSED'),
  camp(6, 'meta', 3, 'EF | DEXA26 | LEADS | EXEMPLO SEMINÁRIO', 'ACTIVE'),
  camp(7, 'meta', 1, 'Campanha exemplo fora do padrão', 'ACTIVE'),
  camp(8, 'meta', 3, 'EF | XYZ26 | LEADS | EXEMPLO PROJETO SEM CADASTRO', 'ACTIVE'),
  camp(9, 'meta', 1, 'CF | PB26 | DISTRIBUIÇÃO | EXEMPLO CONTEÚDO', 'ACTIVE'),
  camp(10, 'meta', 1, 'RS | LPEXA26 | VENDAS | EXEMPLO INGRESSO', 'ACTIVE'),
  camp(11, 'meta', 3, 'RS | LPEXA26 | VENDAS | EXEMPLO CONTA DE FORA', 'ACTIVE'),
  camp(12, 'meta', 1, 'lpexa26 exemplo remarketing sem padrão', 'PAUSED'),
  // o exemplo de nome da revisão do Victor (06/10/2026): descrição de 5 partes; ANTECIPAÇÃO entrou na lista (fase antecipação)
  camp(13, 'meta', 1, 'CF | BF26 | ANTECIPAÇÃO | EXEMPLO TEASER | META | PQ | ABO | THRUPLAY', 'ACTIVE'),
  camp(14, 'meta', 1, 'CF | BF26 | LEADS | EXEMPLO | VÁRIAS PARTES', 'PAUSED'),
  camp(15, 'meta', 1, 'XX | EXEMPLO', 'PAUSED'),
];
// por campanha: [dias para trás, gasto base por dia, CPM base, CTR base em %, leads da plataforma por 100 reais]
const PERFIL: Record<number, [number, number, number, number, number]> = {
  1: [10, 420, 18, 1.4, 9], 2: [15, 160, 12, 0.9, 5], 3: [12, 90, 40, 3.1, 6], 4: [20, 380, 22, 1.1, 0],
  5: [8, 60, 15, 0.7, 0], 6: [12, 140, 14, 1.2, 10], 7: [5, 50, 20, 1, 4], 9: [6, 40, 9, 0.8, 0],
  10: [8, 250, 16, 1.3, 0], 11: [3, 30, 18, 1, 0],
};
// page views da Web (visitas vindas da campanha; fictício: ~72% dos cliques no link) e ~30% delas viram lead,
// só dos projetos com "Web"
const COM_WEB = new Set([1, 5]);
// leads e MQL da "base de pessoas" (fictícios)
const LEADS: Record<number, { leads: number; mql: number }> = { 1: { leads: 640, mql: 170 }, 2: { leads: 0, mql: 0 }, 4: { leads: 35, mql: 4 }, 5: { leads: 140, mql: 22 } };

interface Dia { campanha_id: number; dia: string; gasto: number; impressoes: number; cliques_link: number; cliques_total: number; leads: number | null }
const DIAS: Dia[] = [];
for (const [cid, [n, base, cpmBase, ctrBase, lpc]] of Object.entries(PERFIL)) {
  for (let i = 1; i <= n; i++) {
    const osc = 0.75 + ((Number(cid) * 7 + i * 13) % 10) / 20; // 0,75 a 1,20, determinístico
    const gasto = Math.round(base * osc * 100) / 100;
    const impressoes = Math.round((gasto / cpmBase) * 1000);
    const link = Math.round(impressoes * ctrBase / 100);
    DIAS.push({ campanha_id: Number(cid), dia: hoje(-i), gasto, impressoes, cliques_link: link, cliques_total: Math.round(link * 1.3), leads: lpc ? Math.round(gasto / 100 * lpc) : null });
  }
}

let seq = 100;
const projeto = (id: number | null) => PROJETOS.find((p) => p.id === id) ?? null;

function lerCampanha(c: CampDemo): Campanha {
  const t = traduzir(c.nome);
  const pNome = PROJETOS.find((p) => p.sigla === t.projeto)?.id ?? null;
  const pid = c.projeto_manual_id ?? pNome;
  const dias = DIAS.filter((d) => d.campanha_id === c.id);
  const soma = (k: 'gasto' | 'impressoes' | 'cliques_link' | 'cliques_total') => (dias.length ? Math.round(dias.reduce((a, d) => a + d[k], 0) * 100) / 100 : null);
  const conta = CONTAS.find((x) => x.id === c.conta_id)!;
  return {
    id: c.id, plataforma: c.plataforma, conta_id: c.conta_id, conta: conta.nome, moeda: conta.moeda, campanha_externa: `00000000000${c.id}`,
    nome: c.nome, status_plataforma: c.status, fora_padrao: !t.padrao, erros: t.erros, avisos: t.avisos, gestor: t.gestor, objetivo: t.objetivo,
    descricao: t.descricao, pagina: t.pagina, projeto_lido: t.projeto, campos: t.campos, projeto_id: pid, projeto_sigla: projeto(pid)?.sigla ?? null, projeto_manual: c.projeto_manual_id != null,
    fase: faseDaCampanha(t.objetivo, c.fase_manual, OBJETIVO_FASE), fase_manual: c.fase_manual, fase_objetivo: faseDaCampanha(t.objetivo, null, OBJETIVO_FASE),
    gasto: soma('gasto'), impressoes: soma('impressoes'), cliques_link: soma('cliques_link'), cliques_total: soma('cliques_total'),
    leads_plataforma: dias.some((d) => d.leads != null) ? dias.reduce((a, d) => a + (d.leads ?? 0), 0) : null,
    ultimo_dia: dias.length ? dias.map((d) => d.dia).sort().at(-1)! : null,
  };
}

const campanhas = () => CAMPS.map(lerCampanha);
const traduzir = (nome: string) => traduzirCampanha(nome, { gestores: GESTORES.map((g) => g.sigla), objetivos: OBJETIVOS, projetos: PROJETOS.map((p) => p.sigla) });

function linha(p: ProjetoDemo): LinhaResumo {
  const cs = campanhas().filter((c) => c.projeto_id === p.id);
  const ids = new Set(cs.map((c) => c.id));
  const dias = DIAS.filter((d) => ids.has(d.campanha_id));
  const pl = PLAN.get(p.id);
  const tem = dias.length > 0;
  const soma = (xs: number[]) => Math.round(xs.reduce((a, b) => a + b, 0) * 100) / 100;
  const porPlat: Record<string, number> = {};
  for (const c of cs) if (c.gasto != null) porPlat[c.plataforma] = soma([porPlat[c.plataforma] ?? 0, c.gasto]);
  const fs = FASES.filter((f) => f.projeto_id === p.id);
  const l = LEADS[p.id];
  const ck = demoChecklist(p.id);
  return comKpis({
    projeto_id: p.id, sigla: p.sigla, nome: p.nome, subarea: subareaDe(p), tipo: p.tipo, projeto_ativo: p.ativo,
    etiqueta_clickup: p.etiqueta_clickup, inicio: p.inicio, fim: p.fim,
    unidade: p.unidade, unidade_nome: UNIDADES.find((u) => u.codigo === p.unidade)?.nome ?? null, tipo_lancamento: p.tipo_lancamento,
    tipo_lancamento_nome: TIPOS.find((t) => t.codigo === p.tipo_lancamento)?.nome ?? null,
    especialista: ESPECIALISTAS.find((e) => e.id === p.especialista_id)?.nome ?? null, contas_projeto: PROJETO_CONTAS.get(p.id) ?? [],
    captacao_inicio: p.captacao_inicio, captacao_fim: p.captacao_fim, evento_inicio: p.evento_inicio, evento_fim: p.evento_fim,
    checklist_feitos: ck?.feitos ?? null, checklist_total: ck?.total ?? null,
    status: pl?.status ?? null, status_nome: CONFIG.status.find((s) => s.codigo === pl?.status)?.nome ?? null,
    gestores: pl?.gestores ?? [], gestores_campanhas: [...new Set(cs.map((c) => c.gestor).filter((g): g is string => !!g))].sort(),
    ...receitaDemo(p.id), receita_aplica: p.tipo !== 'externo',
    ...(p.tipo === 'externo' ? { receita: null, receita_liquida: null, receita_liquido_estimado: null, receita_compras: null, receita_outras_moedas: null, receita_sem_valor: null } : {}),
    investido: tem ? soma(dias.map((d) => d.gasto)) : null, por_plataforma: tem ? porPlat : null, moedas: [...new Set(cs.map((c) => c.moeda))],
    verba_maxima: pl?.verba_maxima ?? null, verba_diaria: pl?.verba_diaria ?? null,
    verba_fases: soma(fs.map((f) => f.verba ?? 0)), fases: fs.length,
    impressoes: tem ? soma(dias.map((d) => d.impressoes)) : null,
    cliques_link: tem ? soma(dias.map((d) => d.cliques_link)) : null, cliques_total: tem ? soma(dias.map((d) => d.cliques_total)) : null,
    page_views: tem && COM_WEB.has(p.id) ? Math.round(soma(dias.map((d) => d.cliques_link)) * 0.72) : null,
    leads_pagina: tem && COM_WEB.has(p.id) ? Math.round(soma(dias.map((d) => d.cliques_link)) * 0.72 * 0.3) : null,
    leads_plataforma: tem && dias.some((d) => d.leads != null) ? soma(dias.map((d) => d.leads ?? 0)) : null,
    leads: l?.leads ?? 0, mql: l?.mql ?? 0,
    gasto_ontem: tem ? soma(dias.filter((d) => d.dia === ONTEM).map((d) => d.gasto)) : null, dia_ontem: ONTEM,
    ultimo_dia: tem ? dias.map((d) => d.dia).sort().at(-1)! : null,
    meta_leads: pl?.meta_leads ?? null, meta_receita: pl?.meta_receita ?? null, meta_cpl: pl?.meta_cpl ?? null, meta_pct_mql: pl?.meta_pct_mql ?? null,
    obs: pl?.obs ?? null, campanhas: cs.length, campanhas_fora_padrao: cs.filter((c) => c.fora_padrao).length,
    pct_verba: null, cpl: null, ctr: null, cpc: null, cpm: null, pct_mql: null, connect_rate: null, conversao_pagina: null, ritmo_ontem: null,
  });
}

export const demoConfig = (): ConfigTrafego => ({ ...structuredClone(CONFIG), campanhas_fora_padrao: campanhas().filter((c) => c.fora_padrao).length });
export const demoResumo = (): LinhaResumo[] => PROJETOS.map(linha);
export const demoContas = (): Conta[] => ordenarContas(CONTAS.map((c) => ({ ...c, campanhas: CAMPS.filter((x) => x.conta_id === c.id).length })));

export function demoCampanhas(projetoId: number | null, semProjeto: boolean, foraPadrao: boolean): Campanha[] {
  return campanhas().filter((c) => (projetoId == null || c.projeto_id === projetoId) && (!semProjeto || c.projeto_id == null) && (!foraPadrao || c.fora_padrao));
}

export function demoProjeto(id: number): VidaProjeto | null {
  const p = projeto(id);
  if (!p) return null;
  const cs = demoCampanhas(id, false, false);
  // uma linha por fase planejada OU com campanha nela (id null = sem planejamento), na ordem da lista
  const fases: FaseProjeto[] = CONFIG.fases.flatMap((x) => {
    const plano = FASES.find((f) => f.projeto_id === id && f.fase === x.codigo) ?? null;
    const dela = cs.filter((c) => c.fase === x.codigo);
    if (!plano && dela.length === 0) return [];
    const g = dela.filter((c) => c.gasto != null).map((c) => c.gasto!);
    return [{
      id: plano?.id ?? null, fase: x.codigo, nome: x.nome, verba: plano?.verba ?? null, inicio: plano?.inicio ?? null, fim: plano?.fim ?? null,
      obs: plano?.obs ?? null, gasto: g.length ? Math.round(g.reduce((a, b) => a + b, 0) * 100) / 100 : null, campanhas: dela.length,
    }];
  });
  const semFase = cs.filter((c) => c.fase == null && c.gasto != null);
  const ids = new Set(cs.map((c) => c.id));
  const porDia = new Map<string, { dia: string; gasto: number; impressoes: number; cliques_link: number; leads_plataforma: number | null }>();
  for (const d of DIAS.filter((x) => ids.has(x.campanha_id))) {
    const a = porDia.get(d.dia) ?? { dia: d.dia, gasto: 0, impressoes: 0, cliques_link: 0, leads_plataforma: null };
    a.gasto = Math.round((a.gasto + d.gasto) * 100) / 100; a.impressoes += d.impressoes; a.cliques_link += d.cliques_link;
    if (d.leads != null) a.leads_plataforma = (a.leads_plataforma ?? 0) + d.leads;
    porDia.set(d.dia, a);
  }
  return {
    resumo: linha(p), fases,
    gasto_sem_fase: semFase.length ? Math.round(semFase.reduce((a, c) => a + (c.gasto ?? 0), 0) * 100) / 100 : null,
    campanhas_sem_fase: cs.filter((c) => c.fase == null).length,
    serie: [...porDia.values()].sort((a, b) => a.dia.localeCompare(b.dia)), campanhas: cs,
  };
}

const NADA = ' (modo de demonstração: só em memória)';

export function demoSalvarPlanejamento(p: Record<string, unknown>): Resposta {
  const id = Number(p.projeto_id);
  if (!projeto(id)) return { ok: false, msg: 'Projeto não encontrado.' };
  const n = (k: string) => (p[k] === '' || p[k] == null ? null : Number(p[k]));
  PLAN.set(id, {
    status: 'status' in p ? (p.status as string) || null : PLAN.get(id)?.status ?? null,
    gestores: Array.isArray(p.gestores) ? (p.gestores as string[]) : PLAN.get(id)?.gestores ?? [], verba_maxima: n('verba_maxima'), verba_diaria: n('verba_diaria'),
    meta_leads: n('meta_leads'), meta_receita: n('meta_receita'), meta_cpl: n('meta_cpl'), meta_pct_mql: n('meta_pct_mql'), obs: (p.obs as string) || null,
  });
  return { ok: true, msg: `Planejamento de ${projeto(id)!.sigla} salvo${NADA}.`, avisos: [] };
}

export function demoSalvarFase(p: Record<string, unknown>): Resposta {
  const pid = Number(p.projeto_id);
  const fase = String(p.fase ?? '');
  if (FASES.some((f) => f.projeto_id === pid && f.fase === fase && f.id !== Number(p.id))) return { ok: false, msg: 'Este projeto já tem esta fase.' };
  const v = { projeto_id: pid, fase, verba: p.verba === '' || p.verba == null ? null : Number(p.verba), inicio: (p.inicio as string) || null, fim: (p.fim as string) || null, obs: (p.obs as string) || null };
  if (v.inicio && v.fim && v.fim < v.inicio) return { ok: false, msg: 'O fim não pode ser antes do início.' };
  if (p.id) FASES = FASES.map((f) => (f.id === Number(p.id) ? { ...f, ...v } : f));
  else FASES.push({ id: ++seq, ...v });
  return { ok: true, msg: `Fase salva${NADA}.`, avisos: [] };
}

export function demoApagarFase(id: number): Resposta {
  FASES = FASES.filter((f) => f.id !== id);
  return { ok: true, msg: `Planejamento da fase apagado; as campanhas continuam na fase${NADA}.` };
}

export function demoSalvarConta(p: Record<string, unknown>): Resposta {
  const v = { plataforma: String(p.plataforma), conta_externa: String(p.conta_externa ?? '').replace(/^act_/i, ''), nome: String(p.nome ?? ''), dono: p.dono as Dono, cliente: (p.cliente as string) || null, moeda: String(p.moeda || 'BRL'), ativa: p.ativa !== false, obs: (p.obs as string) || null,
    unidade: (p.unidade as string) || null, principal: !!p.principal };
  if (v.unidade && !unidadesDoDono(v.dono).includes(v.unidade)) return { ok: false, msg: 'Unidade não combina com o dono da conta (Grupo: CSM ou Escritório; Aurum; Diamantes).' };
  if (v.nome.trim().length < 2) return { ok: false, msg: 'Informe o nome da conta.' };
  if (CONTAS.some((c) => c.plataforma === v.plataforma && c.conta_externa === v.conta_externa && c.id !== Number(p.id))) return { ok: false, msg: 'Esta conta já está cadastrada.' };
  if (p.id) Object.assign(CONTAS.find((c) => c.id === Number(p.id))!, v);
  else CONTAS.push({ id: ++seq, campanhas: 0, ...v });
  return { ok: true, msg: `Conta ${v.nome} salva${NADA}.` };
}

export function demoAjustarCampanha(p: { id: number; projeto_id?: number | null; fase?: string | null }): Resposta {
  const c = CAMPS.find((x) => x.id === p.id);
  if (!c) return { ok: false, msg: 'Campanha não encontrada.' };
  if (p.fase && !CONFIG.fases.some((f) => f.codigo === p.fase)) return { ok: false, msg: 'Fase fora da lista.' };
  if ('projeto_id' in p) c.projeto_manual_id = p.projeto_id ?? null;
  if ('fase' in p) c.fase_manual = p.fase || null;
  return { ok: true, msg: `Campanha ajustada${NADA}.` };
}

// ─── Fase 2 (20261006i): resumo do dia, produtos da Hotmart e ClickUp. Tudo fictício ("Exemplo", ids 000…). ─────────
// Os limiares são os mesmos da migration (mkt_trafego.alerta_regras; confirmados pelo Victor em 06/10/2026; a 8ª regra é da 20261006j).
const REGRAS_DEMO: Regra[] = [
  { codigo: 'acima_verba_diaria', nome: 'Acima da verba diária', ligada: true, limiar: 0, unidade: 'pct', gravidade: 'alta', descricao: 'Gasto de ontem acima da verba diária + limiar %.' },
  { codigo: 'cpl_acima_meta', nome: 'CPL acima da meta', ligada: true, limiar: 0, unidade: 'pct', gravidade: 'alta', descricao: 'CPL acima da meta de CPL + limiar %.' },
  { codigo: 'leads_abaixo_meta', nome: 'Abaixo da meta de leads para a data', ligada: true, limiar: 20, unidade: 'pct', gravidade: 'alta', descricao: 'Leads abaixo do esperado para ontem em mais de limiar %.' },
  { codigo: 'ritmo_fase', nome: 'Ritmo da fase fora do planejado', ligada: true, limiar: 20, unidade: 'pct', gravidade: 'media', descricao: 'Gasto da fase em andamento fora do esperado em mais de limiar %.' },
  { codigo: 'verba_perto_fim', nome: '% da verba perto do fim', ligada: true, limiar: 90, unidade: 'pct', gravidade: 'media', descricao: '% da verba máxima já investido maior ou igual ao limiar.' },
  { codigo: 'fora_padrao', nome: 'Campanhas fora do padrão', ligada: true, limiar: 7, unidade: 'dias', gravidade: 'media', descricao: 'Campanhas fora do padrão que gastaram nos últimos limiar dias.' },
  { codigo: 'sem_fase', nome: 'Campanhas sem fase', ligada: true, limiar: 7, unidade: 'dias', gravidade: 'media', descricao: 'Campanhas sem fase que gastaram nos últimos limiar dias.' },
  { codigo: 'conta_fora_projeto', nome: 'Campanha do projeto em conta de fora', ligada: true, limiar: 7, unidade: 'dias', gravidade: 'media', descricao: 'Campanha com a sigla do projeto que gastou nos últimos limiar dias numa conta que não é do projeto.' },
  { codigo: 'checklist_incompleto', nome: 'Em captação com checklist incompleto', ligada: true, limiar: 0, unidade: 'dias', gravidade: 'media', descricao: 'Projeto em captação com item do checklist de "antes de subir as campanhas" pendente, a partir de limiar dias do início da captação.' },
];

interface ProdutoDemo { id: number; projeto_id: number; conta: string; produto_id: string; oferta_codigo: string | null; de: string | null; ate: string | null; obs: string | null }
let PRODUTOS: ProdutoDemo[] = [
  { id: 1, projeto_id: 1, conta: 'academy', produto_id: '0000001', oferta_codigo: null, de: hoje(-25), ate: null, obs: 'Ingresso Exemplo' },
];
// receita fictícia de cada produto de exemplo no período
const RECEITA_PRODUTO: Record<string, { receita: number; liquida: number; compras: number }> = {
  'academy/0000001': { receita: 18450, liquida: 17520, compras: 123 }, 'escritorio/0000002': { receita: 4200, liquida: 3990, compras: 6 },
};
const VISTOS: ProdutoVisto[] = [
  { conta: 'academy', produto_id: '0000001', nome: 'Ingresso Exemplo', aprovadas: 123, ultima: ONTEM,
    ofertas: [{ codigo: 'ex0001', pagas: 100, ultima: ONTEM }, { codigo: 'ex0002', pagas: 23, ultima: hoje(-4) }] },
  { conta: 'escritorio', produto_id: '0000002', nome: 'Produto Exemplo 2', aprovadas: 6, ultima: hoje(-3), ofertas: [{ codigo: 'ex0003', pagas: 6, ultima: hoje(-3) }] },
];

function receitaDemo(projetoId: number): Pick<LinhaResumo, 'receita' | 'receita_liquida' | 'receita_liquido_estimado' | 'receita_compras' | 'receita_outras_moedas' | 'receita_sem_valor' | 'receita_vinculos' | 'receita_sem_periodo' | 'receita_fonte'> {
  const vs = PRODUTOS.filter((v) => v.projeto_id === projetoId);
  const p = projeto(projetoId);
  const comPeriodo = vs.filter((v) => v.de != null || p?.captacao_inicio != null || p?.inicio != null); // vínculo sem "de" usa a captação até o fim do evento
  const soma = (k: 'receita' | 'liquida' | 'compras') => comPeriodo.reduce((a, v) => a + (RECEITA_PRODUTO[`${v.conta}/${v.produto_id}`]?.[k] ?? 0), 0);
  return {
    receita: comPeriodo.length ? soma('receita') : null, receita_liquida: comPeriodo.length ? soma('liquida') : null,
    receita_liquido_estimado: vs.length ? 0 : null, receita_compras: vs.length ? soma('compras') : null,
    receita_outras_moedas: vs.length ? 0 : null, receita_sem_valor: vs.length ? 0 : null,
    receita_vinculos: vs.length, receita_sem_periodo: vs.length - comPeriodo.length, receita_fonte: true,
  };
}

export function demoAlertas(): ResumoDia {
  const cs = campanhas();
  const ultimo = (id: number) => DIAS.filter((d) => d.campanha_id === id && d.gasto > 0).map((d) => d.dia).sort().at(-1) ?? null;
  const ent = (c: Campanha) => ({ fora_padrao: c.fora_padrao, fase: c.fase, ultimoGasto: ultimo(c.id) });
  const projetos: ProjetoEntrada[] = PROJETOS.map((p) => {
    const doProj = cs.filter((c) => c.projeto_id === p.id);
    const st = PLAN.get(p.id)?.status;
    return {
      linha: linha(p),
      entra: p.ativo && !FORA_DO_RESUMO.has(st ?? ''),
      fases: FASES.filter((f) => f.projeto_id === p.id).map((f) => {
        const ids = new Set(doProj.filter((c) => c.fase === f.fase).map((c) => c.id));
        const g = DIAS.filter((d) => ids.has(d.campanha_id) && f.inicio != null && d.dia >= f.inicio && d.dia <= ONTEM).reduce((a, d) => a + d.gasto, 0);
        return { fase: f.fase, nome: CONFIG.fases.find((x) => x.codigo === f.fase)?.nome ?? f.fase, verba: f.verba, inicio: f.inicio, fim: f.fim, gastoAteOntem: Math.round(g * 100) / 100 };
      }),
      campanhas: doProj.map(ent),
      contasProjeto: PROJETO_CONTAS.get(p.id) ?? [],
      campanhasDaSigla: cs.filter((c) => traduzir(c.nome).projeto === p.sigla).map((c) => ({ ...ent(c), conta_id: c.conta_id, conta: c.conta })),
      pendentesAntes: demoChecklist(p.id)?.pendentes_antes ?? [],
    };
  });
  return {
    dia: ONTEM, sem_coleta: false, base_pessoas: true, projetos_avaliados: projetos.filter((x) => x.entra).length,
    alertas: calcularAlertas(ONTEM, REGRAS_DEMO, projetos, cs.filter((c) => c.projeto_id == null).map(ent)),
    regras: structuredClone(REGRAS_DEMO), coletas: {},
  };
}

export function demoProdutos(projetoId: number): ProdutoHotmart[] {
  const p = projeto(projetoId);
  const pr = p ? periodoReceita(p) : { inicio: null, fim: null };
  return PRODUTOS.filter((v) => v.projeto_id === projetoId).map((v) => ({
    ...v, projeto_sigla: p?.sigla ?? '', produto_nome: VISTOS.find((x) => x.conta === v.conta && x.produto_id === v.produto_id)?.nome ?? null, de_efetivo: v.de ?? pr.inicio, ate_efetivo: v.ate ?? pr.fim,
  }));
}

export const demoProdutosVistos = (): ProdutoVisto[] => structuredClone(VISTOS);

export function demoSalvarProduto(p: Record<string, unknown>): Resposta {
  const pid = Number(p.projeto_id);
  if (!projeto(pid)) return { ok: false, msg: 'Projeto não encontrado.' };
  const conta = String(p.conta ?? '').trim();
  if (!['academy', 'escritorio'].includes(conta)) return { ok: false, msg: 'Escolha a conta da Hotmart.' };
  const prod = String(p.produto_id ?? '').trim();
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(prod)) return { ok: false, msg: 'Id do produto na Hotmart inválido (só letras, números, - e _).' };
  const v = { projeto_id: pid, conta, produto_id: prod, oferta_codigo: (p.oferta_codigo as string)?.trim() || null, de: (p.de as string) || null, ate: (p.ate as string) || null, obs: (p.obs as string) || null };
  if (v.de && v.ate && v.ate < v.de) return { ok: false, msg: 'O fim não pode ser antes do início.' };
  if (PRODUTOS.some((x) => x.projeto_id === pid && x.conta === conta && x.produto_id === prod && x.oferta_codigo === v.oferta_codigo && x.id !== Number(p.id))) {
    return { ok: false, msg: 'Este produto (conta e oferta) já está ligado a este projeto.' };
  }
  if (p.id) PRODUTOS = PRODUTOS.map((x) => (x.id === Number(p.id) ? { ...x, ...v } : x));
  else PRODUTOS.push({ id: ++seq, ...v });
  const avisos = [...(v.de || projeto(pid)?.captacao_inicio || projeto(pid)?.inicio ? [] : ['sem_periodo']), ...(VISTOS.some((x) => x.conta === conta && x.produto_id === prod) ? [] : ['produto_sem_compras'])];
  return { ok: true, msg: `Produto ${prod} ligado${NADA}.`, avisos };
}

export function demoApagarProduto(id: number): Resposta {
  PRODUTOS = PRODUTOS.filter((x) => x.id !== id);
  return { ok: true, msg: `Vínculo apagado${NADA}.` };
}

const iso = (n: number, h = 15) => `${hoje(n)}T${String(h).padStart(2, '0')}:00:00.000Z`;
const tarefa = (id: string, nome: string, status: string, x: Partial<TarefaClickup>): TarefaClickup =>
  ({ id, nome, status, criada_em: null, atualizada_em: null, inicio: null, prazo: null, concluida_em: null, responsaveis: [], url: null, ...x });
const TAREFAS: Record<number, TarefaClickup[]> = {
  1: [
    tarefa('demo4', 'Exemplo: revisar a verba da captação', 'em andamento', { criada_em: iso(-2), inicio: iso(-1), prazo: iso(2), responsaveis: ['Responsável Exemplo'] }),
    tarefa('demo3', 'Exemplo: aumentar o orçamento do público frio', 'concluído', { criada_em: iso(-5), concluida_em: iso(-3), responsaveis: ['Responsável Exemplo'] }),
    tarefa('demo2', 'Exemplo: trocar criativos do aquecimento', 'concluído', { criada_em: iso(-9), concluida_em: iso(-6) }),
    tarefa('demo1', 'Exemplo: subir campanhas de captação', 'concluído', { criada_em: iso(-12), prazo: iso(-10), concluida_em: iso(-10), responsaveis: ['Outro Exemplo'] }),
  ],
};

export function demoClickup(projetoId: number): ClickupProjeto | null {
  const p = projeto(projetoId);
  if (!p) return null;
  return { etiqueta: p.etiqueta_clickup, configurado: true, ultima_coleta: null, tarefas: p.etiqueta_clickup ? structuredClone(TAREFAS[projetoId] ?? []) : [] };
}

// ─── Cadastro do projeto, modelos e checklist (20261006j e 20261006l). Listas = as sementes da migration; o resto fictício. ────────
const UNIDADES = [
  { codigo: 'csm', tipo: 'interno' as const, nome: 'CSM', descricao: 'CSM Academy (o educacional)' },
  { codigo: 'escritorio', tipo: 'interno' as const, nome: 'Escritório', descricao: 'Escritório de advocacia' },
  { codigo: 'aurum', tipo: 'externo' as const, nome: 'Aurum', descricao: null },
  { codigo: 'diamantes', tipo: 'externo' as const, nome: 'Diamantes', descricao: null },
];
const TIPOS = [
  { codigo: 'lancamento_classico', nome: 'Lançamento clássico' }, { codigo: 'lancamento_pago', nome: 'Lançamento pago' },
  { codigo: 'lpsg', nome: 'Lançamento pago semanal gravado (LPSG)' }, { codigo: 'atm', nome: 'ATM' }, { codigo: 'palestra', nome: 'Palestra' },
];
const REGRAS: Record<string, string[]> = {
  csm: ['lancamento_classico', 'lancamento_pago', 'lpsg', 'atm'], escritorio: ['lancamento_classico', 'atm'],
  aurum: ['palestra'], diamantes: ['lancamento_classico', 'lancamento_pago'],
};
const ESPECIALISTAS: Especialista[] = [
  { id: 1, nome: 'Marcio Carvalho de Sá', tipo: 'interno', unidade: null },
  { id: 2, nome: 'Elaine Montenegro', tipo: 'interno', unidade: null },
  { id: 3, nome: 'Especialista Exemplo', tipo: 'externo', unidade: 'diamantes' },
];
const UTM_META = [
  { parametro: 'utm_source', valor: 'metaads' }, { parametro: 'utm_campaign', valor: '{{campaign.name}}|{{campaign.id}}' },
  { parametro: 'utm_medium', valor: '{{adset.name}}|{{adset.id}}' }, { parametro: 'utm_content', valor: '{{ad.name}}|{{ad.id}}' },
  { parametro: 'utm_term', valor: '{{placement}}' },
];
// Modelos de lançamento (20261006l): os 9 exemplos da semente (rascunho, números genéricos), gerados da mesma tabela.
type FaseSemente = [string, number, RefData, number, RefData, number, number];
const FASES_EXEMPLO: Record<string, FaseSemente[]> = {
  lancamento_classico: [['aquecimento', 1, 'captacao_inicio', -7, 'captacao_inicio', -1, 10], ['captacao', 2, 'captacao_inicio', 0, 'captacao_fim', 0, 60],
    ['lembrete', 3, 'evento_inicio', -2, 'evento_inicio', 0, 10], ['remarketing', 4, 'captacao_inicio', 0, 'evento_fim', 0, 10],
    ['abertura_carrinho', 5, 'evento_fim', 0, 'evento_fim', 3, 10]],
  lancamento_pago: [['aquecimento', 1, 'captacao_inicio', -7, 'captacao_inicio', -1, 10], ['captacao', 2, 'captacao_inicio', 0, 'captacao_fim', 0, 60],
    ['lembrete', 3, 'evento_inicio', -2, 'evento_inicio', 0, 10], ['remarketing', 4, 'captacao_inicio', 0, 'evento_fim', 0, 10],
    ['abertura_carrinho', 5, 'evento_fim', 0, 'evento_fim', 3, 10]],
  lpsg: [['captacao', 1, 'captacao_inicio', 0, 'captacao_fim', 0, 70], ['lembrete', 2, 'evento_inicio', -2, 'evento_inicio', 0, 10],
    ['remarketing', 3, 'captacao_inicio', 0, 'evento_fim', 0, 10], ['abertura_carrinho', 4, 'evento_fim', 0, 'evento_fim', 3, 10]],
  atm: [['aquecimento', 1, 'evento_inicio', -7, 'evento_inicio', -1, 30], ['abertura_carrinho', 2, 'evento_inicio', 0, 'evento_fim', 0, 50],
    ['remarketing', 3, 'evento_inicio', 0, 'evento_fim', 0, 20]],
  palestra: [['captacao', 1, 'captacao_inicio', 0, 'captacao_fim', 0, 70], ['lembrete', 2, 'evento_inicio', -2, 'evento_inicio', 0, 20],
    ['remarketing', 3, 'captacao_inicio', 0, 'evento_fim', 0, 10]],
};
const OBJ_DA_FASE = (fase: string, tipo: string) => ({
  captacao: tipo === 'lancamento_pago' || tipo === 'lpsg' ? 'VENDAS' : 'LEADS', aquecimento: 'AQUECIMENTO', antecipacao: 'ANTECIPAÇÃO', lembrete: 'LEMBRETE',
  remarketing: 'REMARKETING', abertura_carrinho: 'CARRINHO',
} as Record<string, string>)[fase];
// Grupo é uma etapa do funil (Victor, 06/10/2026): campanha de lead leva ao grupo de leads, de venda ao grupo de compradores.
const SENDFLOW_LEADS = 'Automação de ingresso no grupo de leads configurada no SendFlow';
const SENDFLOW_COMPRADORES = 'Automação de ingresso no grupo de compradores configurada no SendFlow';
let MODELOS_D: Modelo[] = [];
for (const u of ['csm', 'escritorio', 'aurum', 'diamantes']) {
  for (const t of REGRAS[u]) {
    const fs = FASES_EXEMPLO[t];
    MODELOS_D.push({
      id: MODELOS_D.length + 1, nome: `Exemplo: ${TIPOS.find((x) => x.codigo === t)!.nome} ${UNIDADES.find((x) => x.codigo === u)!.nome}`, tipo_lancamento: t,
      tipo_lancamento_nome: TIPOS.find((x) => x.codigo === t)!.nome, ativo: true, rascunho: true, meta_cpl: null, meta_pct_mql: null,
      obs: 'Modelo de EXEMPLO para editar: fases, datas e percentuais genéricos, não são decisão de ninguém. Validar antes de usar.',
      unidades: [{ unidade: u, padrao: true }],
      fases: fs.map(([fase, ordem, ir, id, fr, fd, pct]) => ({ fase, ordem, inicio_ref: ir, inicio_dias: id, fim_ref: fr, fim_dias: fd, pct_verba: pct, obs: null })),
      campanhas: fs.map(([fase, ordem]) => ({ objetivo: OBJ_DA_FASE(fase, t), fase, descricao: null, pagina: null, ordem })),
      itens: [
        ...(fs.some(([f]) => OBJ_DA_FASE(f, t) === 'LEADS') ? [{ texto: SENDFLOW_LEADS, momento: 'antes' as const, ordem: 1 }] : []),
        ...(fs.some(([f]) => OBJ_DA_FASE(f, t) === 'VENDAS') ? [{ texto: SENDFLOW_COMPRADORES, momento: 'antes' as const, ordem: 2 }] : []),
      ],
    });
  }
}
const PROJETO_MODELO = new Map<number, { id: number | null; nome: string; aplicado_em: string }>();
let ESPERADAS: (Esperada & { projeto_id: number })[] = [];
let ITENS_PROJ: (ItemProjeto & { projeto_id: number })[] = [];

export function demoListasCadastro(): ListasCadastro {
  return structuredClone({
    unidades: UNIDADES, tipos_lancamento: TIPOS, regras: REGRAS, especialistas: ESPECIALISTAS, objetivos: [...OBJETIVOS].sort(),
    utm: { meta: UTM_META }, etiquetas_clickup: [],
    modelos: MODELOS_D.map(({ id, nome, tipo_lancamento, ativo, rascunho, unidades }) => ({ id, nome, tipo_lancamento, ativo, rascunho, unidades })),
  });
}

// Etiquetas do ClickUp da demonstração: as 4 citadas na revisão do Victor (vistas no painel de KPIs) e as dos projetos da
// semente; as fontes são de exemplo.
const ETIQUETAS_DEMO: EtiquetaClickup[] = [
  ...['seminario-atm', 'seminario-conjunto', 'seminario-conjunto-2026-11', 'seminario-zanella'].map((etiqueta) => ({ etiqueta, fontes: ['kpi'] })),
  { etiqueta: 'seminario-conjunto-2026-11', fontes: ['trafego'] }, { etiqueta: 'black-friday-2026-10', fontes: ['trafego'] },
  { etiqueta: 'sem-set-2026', fontes: ['kpi'] },
];
export function demoBuscarEtiquetas(busca: string): BuscaEtiquetas {
  return { etiquetas: filtrarEtiquetas(ETIQUETAS_DEMO, busca), fonte_kpi: true };
}

export function demoCadastro(id: number): ProjetoCadastro | null {
  const p = projeto(id);
  if (!p) return null;
  const contas = PROJETO_CONTAS.get(id) ?? [];
  const pl = PLAN.get(id);
  return {
    id: p.id, sigla: p.sigla, nome: p.nome, linha: p.linha, etiqueta_clickup: p.etiqueta_clickup, inicio: p.inicio, fim: p.fim,
    captacao_inicio: p.captacao_inicio, captacao_fim: p.captacao_fim, evento_inicio: p.evento_inicio, evento_fim: p.evento_fim, ativo: p.ativo,
    tipo: p.tipo, unidade: p.unidade, tipo_lancamento: p.tipo_lancamento, especialista_id: p.especialista_id,
    especialista_nome: ESPECIALISTAS.find((e) => e.id === p.especialista_id)?.nome ?? null, status: pl?.status ?? null, gestores: [...(pl?.gestores ?? [])],
    contas: [...contas], paginas: structuredClone(PAGINAS.get(id) ?? []),
    sugestoes: CAMPS.map(lerCampanha).filter((c) => c.projeto_id == null && contas.includes(c.conta_id) && nomeTemSigla(c.nome, p.sigla))
      .map((c) => ({ id: c.id, nome: c.nome, plataforma: c.plataforma, conta_id: c.conta_id, conta: c.conta, status_plataforma: c.status_plataforma })),
    modelo: PROJETO_MODELO.get(id) ?? null,
    modelos_disponiveis: modelosDoProjeto(MODELOS_D, p.tipo_lancamento, p.unidade).length,
    esperadas: ESPERADAS.filter((e) => e.projeto_id === id).map((e) => ({ id: e.id, objetivo: e.objetivo, fase: e.fase, descricao: e.descricao, pagina: e.pagina })),
    fases_planejadas: FASES.filter((f) => f.projeto_id === id).length,
  };
}

export function demoSalvarCadastro(f: ProjetoForm): Resposta & { tipo_lancamento?: string | null } {
  const l = demoListasCadastro();
  const erro = validarCadastro(l, { ...PROJETO_FORM_VAZIO, ...f });
  if (erro) return { ok: false, msg: erro };
  if (PROJETOS.some((p) => p.sigla === f.sigla && p.id !== f.id)) return { ok: false, msg: `Já existe projeto com a sigla ${f.sigla}.` };
  const avisos: string[] = [];
  let esp = f.especialista_id;
  if (esp == null && f.especialista_nome && f.tipo === 'externo') {
    esp = ESPECIALISTAS.find((e) => e.tipo === 'externo' && e.nome.toLowerCase() === f.especialista_nome.toLowerCase())?.id ?? null;
    if (esp == null) { esp = ++seq; ESPECIALISTAS.push({ id: esp, nome: f.especialista_nome, tipo: 'externo', unidade: f.unidade }); avisos.push('especialista_cadastrado'); }
  }
  const periodo = periodoProjeto(f);
  const v: ProjetoDemo = {
    id: f.id ?? ++seq, sigla: f.sigla, nome: f.nome, linha: projeto(f.id ?? null)?.linha ?? f.nome.slice(0, 60), ativo: f.ativo, etiqueta_clickup: f.etiqueta_clickup || null,
    tipo: f.tipo || null, unidade: f.unidade || null, tipo_lancamento: f.tipo_lancamento || lancamentoAutomatico(l, f.unidade), especialista_id: esp,
    inicio: periodo.inicio || null, fim: periodo.fim || null, captacao_inicio: f.captacao_inicio || null, captacao_fim: f.captacao_fim || null,
    evento_inicio: f.evento_inicio || null, evento_fim: f.evento_fim || null,
  };
  const i = PROJETOS.findIndex((p) => p.id === v.id);
  if (i >= 0) PROJETOS[i] = v; else PROJETOS.push(v);
  const pl = PLAN.get(v.id);
  PLAN.set(v.id, { status: f.status || null, gestores: [...f.gestores], verba_maxima: pl?.verba_maxima ?? null, verba_diaria: pl?.verba_diaria ?? null,
    meta_leads: pl?.meta_leads ?? null, meta_receita: pl?.meta_receita ?? null, meta_cpl: pl?.meta_cpl ?? null, meta_pct_mql: pl?.meta_pct_mql ?? null, obs: pl?.obs ?? null });
  PROJETO_CONTAS.set(v.id, [...f.contas]);
  return { ok: true, msg: `Projeto ${v.sigla} salvo${NADA}.`, id: v.id, tipo_lancamento: v.tipo_lancamento, avisos };
}

// ─── Modelos de lançamento (20261006l) ───────────────────────────────────────────────────────────────────────────────
export const demoModelos = (): Modelo[] => structuredClone(MODELOS_D);

export function demoSalvarModelo(m: Modelo): Resposta {
  const erro = validarModelo(m, REGRAS, OBJETIVOS);
  if (erro) return { ok: false, msg: erro };
  if (MODELOS_D.some((x) => x.id !== m.id && x.nome.trim().toLowerCase() === m.nome.trim().toLowerCase())) return { ok: false, msg: 'Já existe modelo com este nome.' };
  const id = m.id || ++seq;
  const v: Modelo = { ...m, id, nome: m.nome.trim(), tipo_lancamento_nome: TIPOS.find((t) => t.codigo === m.tipo_lancamento)?.nome,
    unidades: m.unidades.map((u) => ({ ...u, padrao: m.ativo && u.padrao })) };
  for (const u of v.unidades.filter((x) => x.padrao)) {
    for (const o of MODELOS_D) if (o.id !== id && o.tipo_lancamento === v.tipo_lancamento) o.unidades = o.unidades.map((x) => (x.unidade === u.unidade ? { ...x, padrao: false } : x));
  }
  MODELOS_D = m.id ? MODELOS_D.map((x) => (x.id === id ? v : x)) : [...MODELOS_D, v];
  return { ok: true, msg: `Modelo salvo${NADA}.`, id, avisos: somaPct(v.fases) > 100 ? ['fases_acima_de_100'] : [] };
}

export function demoDuplicarModelo(id: number): Resposta {
  const m = MODELOS_D.find((x) => x.id === id);
  if (!m) return { ok: false, msg: 'Modelo não encontrado.' };
  let nome = `${m.nome.slice(0, 70)} (cópia)`;
  for (let n = 2; MODELOS_D.some((x) => x.nome.toLowerCase() === nome.toLowerCase()); n++) nome = `${m.nome.slice(0, 66)} (cópia ${n})`;
  const v: Modelo = { ...structuredClone(m), id: ++seq, nome, ativo: true, unidades: m.unidades.map((u) => ({ ...u, padrao: false })) };
  MODELOS_D.push(v);
  return { ok: true, msg: `Modelo duplicado: ${nome}${NADA}.`, id: v.id };
}

export function demoAtivarModelo(id: number, ativo: boolean): Resposta {
  const m = MODELOS_D.find((x) => x.id === id);
  if (!m) return { ok: false, msg: 'Modelo não encontrado.' };
  m.ativo = ativo;
  if (!ativo) m.unidades = m.unidades.map((u) => ({ ...u, padrao: false }));
  return { ok: true, msg: `${ativo ? 'Modelo ativado' : 'Modelo inativado (deixou de ser padrão)'}${NADA}.` };
}

function previaDemo(p: ProjetoDemo, m: Modelo): PreviaModelo {
  const fases = FASES.filter((f) => f.projeto_id === p.id).map((f) => ({ fase: f.fase, verba: f.verba, inicio: f.inicio, fim: f.fim }));
  const pl = PLAN.get(p.id);
  return previaModelo(m, p, pl?.verba_maxima ?? null, fases, (f) => CONFIG.fases.find((x) => x.codigo === f)?.nome ?? f,
    ESPERADAS.filter((e) => e.projeto_id === p.id), ITENS_PROJ.filter((i) => i.projeto_id === p.id).map((i) => i.texto),
    { meta_cpl: pl?.meta_cpl ?? null, meta_pct_mql: pl?.meta_pct_mql ?? null });
}

export function demoPrevias(id: number): PreviaModelo[] | null {
  const p = projeto(id);
  if (!p) return null;
  return modelosDoProjeto(MODELOS_D, p.tipo_lancamento, p.unidade).map((m) => ({ ...previaDemo(p, m), padrao: m.padrao }));
}

export function demoAplicarModelo(id: number, modeloId: number, substituir: boolean): Resposta & Record<string, unknown> {
  const p = projeto(id);
  const m = MODELOS_D.find((x) => x.id === modeloId);
  if (!p || !m) return { ok: false, msg: 'Projeto ou modelo não encontrado.' };
  const v = previaDemo(p, m);
  if (!v.pode_aplicar) return { ok: false, msg: 'Este modelo não vale para o projeto (tipo de lançamento, unidade ou modelo inativo).' };
  let criadas = 0, atualizadas = 0, mantidas = 0;
  for (const f of v.fases) {
    if (!f.existe) { FASES.push({ id: ++seq, projeto_id: id, fase: f.fase, verba: f.verba, inicio: f.inicio, fim: f.fim, obs: `Do modelo ${m.nome}` }); criadas++; }
    else if (f.muda && substituir) {
      FASES = FASES.map((x) => (x.projeto_id === id && x.fase === f.fase ? { ...x, verba: f.verba ?? x.verba, inicio: f.inicio ?? x.inicio, fim: f.fim ?? x.fim } : x));
      atualizadas++;
    } else mantidas++;
  }
  const novasEsp = v.campanhas.filter((c) => !c.ja_existe);
  ESPERADAS.push(...novasEsp.map((c) => ({ id: ++seq, projeto_id: id, objetivo: c.objetivo, fase: c.fase, descricao: c.descricao, pagina: c.pagina })));
  const novosItens = v.itens.filter((i) => !i.ja_existe);
  ITENS_PROJ.push(...novosItens.map((i) => ({ id: ++seq, projeto_id: id, texto: i.texto, momento: i.momento, feito_em: null, feito_por: null, do_modelo: true })));
  if (m.meta_cpl != null || m.meta_pct_mql != null) {
    const pl = PLAN.get(id) ?? { status: null, gestores: [], verba_maxima: null, verba_diaria: null, meta_leads: null, meta_receita: null, meta_cpl: null, meta_pct_mql: null, obs: null };
    PLAN.set(id, { ...pl, meta_cpl: substituir ? (m.meta_cpl ?? pl.meta_cpl) : (pl.meta_cpl ?? m.meta_cpl),
      meta_pct_mql: substituir ? (m.meta_pct_mql ?? pl.meta_pct_mql) : (pl.meta_pct_mql ?? m.meta_pct_mql) });
  }
  PROJETO_MODELO.set(id, { id: m.id, nome: m.nome, aplicado_em: new Date().toISOString() });
  return { ok: true, criadas, atualizadas, mantidas, esperadas: novasEsp.length, itens: novosItens.length,
    msg: `Modelo ${m.nome} aplicado: ${criadas} fase(s) criada(s), ${atualizadas} atualizada(s), ${mantidas} mantida(s) como estavam; ${novasEsp.length} campanha(s) esperada(s) e ${novosItens.length} item(ns) do checklist acrescentado(s)${NADA}.` };
}

export function demoChecklist(id: number): Checklist | null {
  const p = projeto(id);
  if (!p) return null;
  const cs = CAMPS.map(lerCampanha).filter((c) => c.projeto_id === id);
  const pl = PLAN.get(id);
  return montarChecklist({
    tipo: p.tipo, contas: (PROJETO_CONTAS.get(id) ?? []).length, campanhas: cs.length,
    foraPadrao: cs.filter((c) => c.fora_padrao).length, semFase: cs.filter((c) => c.fase == null).length,
    produtosHotmart: PRODUTOS.filter((v) => v.projeto_id === id).length, paginas: N_PAGINAS[id] ?? 0, etiqueta: p.etiqueta_clickup,
    verbaMaxima: pl?.verba_maxima ?? null, fases: FASES.filter((f) => f.projeto_id === id).length,
    metas: [pl?.meta_leads ?? null, pl?.meta_receita ?? null, pl?.meta_cpl ?? null],
    modelo: PROJETO_MODELO.get(id)?.nome ?? null, esperadas: ESPERADAS.filter((e) => e.projeto_id === id),
    encontradas: cs.map((c) => ({ objetivo: c.objetivo, pagina: c.pagina })), status: pl?.status ?? null, eventoFim: p.evento_fim, hoje: hoje(),
  }, ITENS_PROJ.filter((i) => i.projeto_id === id));
}

export function demoMarcarItem(item: number, feito: boolean): Resposta {
  const i = ITENS_PROJ.find((x) => x.id === item);
  if (!i) return { ok: false, msg: 'Item não encontrado.' };
  i.feito_em = feito ? new Date().toISOString() : null;
  i.feito_por = feito ? 'Você (demonstração)' : null;
  return { ok: true, msg: `${feito ? 'Item marcado como pronto' : 'Item desmarcado'}${NADA}.` };
}

export function demoSalvarItem(p: { id?: number; projeto_id: number; texto: string; momento: Momento }): Resposta {
  const texto = p.texto.trim().replace(/\s+/g, ' ');
  if (texto.length < 3 || texto.length > 200) return { ok: false, msg: 'Texto do item: de 3 a 200 letras.' };
  if (ITENS_PROJ.some((x) => x.projeto_id === p.projeto_id && x.id !== p.id && x.texto.toLowerCase() === texto.toLowerCase())) {
    return { ok: false, msg: 'Este item já está no checklist do projeto.' };
  }
  if (p.id) Object.assign(ITENS_PROJ.find((x) => x.id === p.id)!, { texto, momento: p.momento });
  else ITENS_PROJ.push({ id: ++seq, projeto_id: p.projeto_id, texto, momento: p.momento, feito_em: null, feito_por: null, do_modelo: false });
  return { ok: true, msg: `Item do checklist salvo${NADA}.` };
}

export function demoApagarItem(item: number): Resposta {
  if (!ITENS_PROJ.some((x) => x.id === item)) return { ok: false, msg: 'Item não encontrado.' };
  ITENS_PROJ = ITENS_PROJ.filter((x) => x.id !== item);
  return { ok: true, msg: `Item tirado do checklist do projeto${NADA}.` };
}

export function demoApagarEsperada(id: number): Resposta {
  if (!ESPERADAS.some((x) => x.id === id)) return { ok: false, msg: 'Campanha esperada não encontrada.' };
  ESPERADAS = ESPERADAS.filter((x) => x.id !== id);
  return { ok: true, msg: `Campanha esperada tirada do projeto${NADA}.` };
}

// O projeto fictício LPEXA26 já com o modelo de exemplo do lançamento pago na CSM aplicado e o SendFlow (grupo de compradores) marcado.
{
  const m = MODELOS_D.find((x) => x.tipo_lancamento === 'lancamento_pago' && x.unidades.some((u) => u.unidade === 'csm'))!;
  demoAplicarModelo(7, m.id, false);
  const i = ITENS_PROJ.find((x) => x.projeto_id === 7 && x.texto === SENDFLOW_COMPRADORES);
  if (i) { i.feito_em = `${hoje(-1)}T14:00:00.000Z`; i.feito_por = 'Pessoa Exemplo'; }
}
