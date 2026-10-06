// Marketing > Tráfego: MODO DE DEMONSTRAÇÃO (só desenvolvimento local). Contas, campanhas, gasto, verba e leads
// INVENTADOS, em memória, para ver a tela sem dado real e antes da coleta Meta/Google existir. Nunca é usado em
// produção: trafego-data.ts só liga com NEXT_PUBLIC_TRAFEGO_DEMO=1 E NODE_ENV diferente de 'production', e a tela mostra
// a faixa "Dados de demonstração". Recarregar a página volta ao começo.
// O que vem da semente real: os 4 projetos e os gestores da 20261005m, os objetivos (20261005m + CARRINHO e AQUECIMENTO
// da 20261005p) e as listas da 20261005p (plataformas, status, fases, objetivo → fase). Todo o resto é ficção: projetos externos "… Exemplo", contas "Conta Exemplo",
// ids 0000…, descrições de campanha "EXEMPLO", números gerados.
import { traduzirCampanha } from '../../projetos/domain/campanha';
import { faseDaCampanha } from '../domain/fases';
import { comKpis, tipoDaSubarea } from '../domain/kpis';
import type {
  Campanha, ConfigTrafego, Conta, Dono, FaseProjeto, LinhaResumo, Resposta, Subarea, VidaProjeto,
} from '../domain/tipos';

const hoje = (n = 0) => {
  const d = new Date(Date.now() + n * 86400000);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const ONTEM = hoje(-1);

const GESTORES = [{ sigla: 'CF', nome: 'Caio Fábio' }, { sigla: 'RS', nome: 'Renan Schwarz' }, { sigla: 'EF', nome: 'Emmanuel Fernandes' }];
const OBJETIVOS = ['LEADS', 'VENDAS', 'REMARKETING', 'LEMBRETE', 'DISTRIBUIÇÃO', 'CARRINHO', 'AQUECIMENTO'];
const OBJETIVO_FASE: Record<string, string> = {
  LEADS: 'captacao', VENDAS: 'captacao', LEMBRETE: 'lembrete', REMARKETING: 'remarketing', CARRINHO: 'abertura_carrinho', AQUECIMENTO: 'aquecimento',
};
const CONFIG: ConfigTrafego = {
  plataformas: [{ codigo: 'meta', nome: 'Meta Ads' }, { codigo: 'google', nome: 'Google Ads' }],
  status: [{ codigo: 'ativo', nome: 'Ativo' }, { codigo: 'pausado', nome: 'Pausado' }, { codigo: 'inativo', nome: 'Inativo' }, { codigo: 'encerrado', nome: 'Encerrado' }],
  fases: [
    { codigo: 'aquecimento', nome: 'Aquecimento' }, { codigo: 'captacao', nome: 'Captação' }, { codigo: 'lembrete', nome: 'Lembrete' },
    { codigo: 'remarketing', nome: 'Remarketing' }, { codigo: 'abertura_carrinho', nome: 'Abertura de carrinho' },
  ],
  gestores: GESTORES,
  base_pessoas: true,
  base_web: true,
  objetivo_fase: OBJETIVO_FASE,
  dia_ontem: ONTEM,
};

interface ProjetoDemo { id: number; sigla: string; nome: string; subarea: Subarea | null; ativo: boolean; etiqueta_clickup: string | null }
const PROJETOS: ProjetoDemo[] = [
  { id: 1, sigla: 'PB26', nome: 'Patrimônio Brasil 2026', subarea: 'interno', ativo: true, etiqueta_clickup: 'seminario-conjunto-2026-11' },
  { id: 2, sigla: 'HT33', nome: 'Holding Total 33', subarea: 'interno', ativo: true, etiqueta_clickup: null },
  { id: 3, sigla: 'SEMSET26', nome: 'Seminário setembro 2026', subarea: null, ativo: true, etiqueta_clickup: 'sem-set-2026' },
  { id: 4, sigla: 'BF26', nome: 'Black Friday 2026', subarea: 'interno', ativo: true, etiqueta_clickup: 'black-friday-2026-10' },
  { id: 5, sigla: 'DEXA26', nome: 'Seminário Diamante Exemplo', subarea: 'diamante', ativo: true, etiqueta_clickup: null },
  { id: 6, sigla: 'AEXA26', nome: 'Palestra Aurum Exemplo', subarea: 'aurum', ativo: true, etiqueta_clickup: null },
];

interface Plan { status: string | null; gestores: string[]; verba_maxima: number | null; verba_diaria: number | null; meta_leads: number | null; meta_receita: number | null; meta_cpl: number | null; meta_pct_mql: number | null; obs: string | null }
const PLAN = new Map<number, Plan>([
  [1, { status: 'ativo', gestores: ['RS', 'CF'], verba_maxima: 20000, verba_diaria: 500, meta_leads: 2000, meta_receita: null, meta_cpl: 10, meta_pct_mql: 30, obs: null }],
  [2, { status: 'ativo', gestores: ['CF'], verba_maxima: 15000, verba_diaria: 400, meta_leads: null, meta_receita: 60000, meta_cpl: null, meta_pct_mql: null, obs: null }],
  [4, { status: 'pausado', gestores: ['CF'], verba_maxima: 8000, verba_diaria: null, meta_leads: 500, meta_receita: null, meta_cpl: null, meta_pct_mql: null, obs: null }],
  [5, { status: 'ativo', gestores: ['EF'], verba_maxima: 3000, verba_diaria: 100, meta_leads: 300, meta_receita: null, meta_cpl: 8, meta_pct_mql: null, obs: 'Projeto fictício do modo de demonstração.' }],
]);

interface FaseDemo { id: number; projeto_id: number; fase: string; verba: number | null; inicio: string | null; fim: string | null; obs: string | null }
let FASES: FaseDemo[] = [
  { id: 1, projeto_id: 1, fase: 'aquecimento', verba: 4000, inicio: hoje(-25), fim: hoje(-11), obs: null },
  { id: 2, projeto_id: 1, fase: 'captacao', verba: 14000, inicio: hoje(-10), fim: hoje(15), obs: null },
  { id: 3, projeto_id: 1, fase: 'lembrete', verba: 2000, inicio: hoje(16), fim: hoje(20), obs: null },
  { id: 4, projeto_id: 5, fase: 'captacao', verba: 3000, inicio: hoje(-12), fim: hoje(8), obs: null },
];

const CONTAS: Conta[] = [
  { id: 1, plataforma: 'meta', conta_externa: '000000000000001', nome: 'Conta Exemplo Grupo (Meta)', dono: 'grupo', cliente: null, moeda: 'BRL', ativa: true, obs: null, campanhas: 0 },
  { id: 2, plataforma: 'google', conta_externa: '0000000001', nome: 'Conta Exemplo Grupo (Google)', dono: 'grupo', cliente: null, moeda: 'BRL', ativa: true, obs: null, campanhas: 0 },
  { id: 3, plataforma: 'meta', conta_externa: '000000000000002', nome: 'Conta Exemplo Diamante', dono: 'diamante', cliente: 'Diamante Exemplo', moeda: 'BRL', ativa: true, obs: null, campanhas: 0 },
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
];
// por campanha: [dias para trás, gasto base por dia, CPM base, CTR base em %, leads da plataforma por 100 reais]
const PERFIL: Record<number, [number, number, number, number, number]> = {
  1: [10, 420, 18, 1.4, 9], 2: [15, 160, 12, 0.9, 5], 3: [12, 90, 40, 3.1, 6], 4: [20, 380, 22, 1.1, 0],
  5: [8, 60, 15, 0.7, 0], 6: [12, 140, 14, 1.2, 10], 7: [5, 50, 20, 1, 4], 9: [6, 40, 9, 0.8, 0],
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
  const t = traduzirCampanha(c.nome, { gestores: GESTORES.map((g) => g.sigla), objetivos: OBJETIVOS, projetos: PROJETOS.map((p) => p.sigla) });
  const pNome = PROJETOS.find((p) => p.sigla === t.projeto)?.id ?? null;
  const pid = c.projeto_manual_id ?? pNome;
  const dias = DIAS.filter((d) => d.campanha_id === c.id);
  const soma = (k: 'gasto' | 'impressoes' | 'cliques_link' | 'cliques_total') => (dias.length ? Math.round(dias.reduce((a, d) => a + d[k], 0) * 100) / 100 : null);
  const conta = CONTAS.find((x) => x.id === c.conta_id)!;
  return {
    id: c.id, plataforma: c.plataforma, conta_id: c.conta_id, conta: conta.nome, moeda: conta.moeda, campanha_externa: `00000000000${c.id}`,
    nome: c.nome, status_plataforma: c.status, fora_padrao: !t.padrao, erros: t.erros, avisos: t.avisos, gestor: t.gestor, objetivo: t.objetivo,
    descricao: t.descricao, pagina: t.pagina, projeto_id: pid, projeto_sigla: projeto(pid)?.sigla ?? null, projeto_manual: c.projeto_manual_id != null,
    fase: faseDaCampanha(t.objetivo, c.fase_manual, OBJETIVO_FASE), fase_manual: c.fase_manual, fase_objetivo: faseDaCampanha(t.objetivo, null, OBJETIVO_FASE),
    gasto: soma('gasto'), impressoes: soma('impressoes'), cliques_link: soma('cliques_link'), cliques_total: soma('cliques_total'),
    leads_plataforma: dias.some((d) => d.leads != null) ? dias.reduce((a, d) => a + (d.leads ?? 0), 0) : null,
    ultimo_dia: dias.length ? dias.map((d) => d.dia).sort().at(-1)! : null,
  };
}

const campanhas = () => CAMPS.map(lerCampanha);

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
  return comKpis({
    projeto_id: p.id, sigla: p.sigla, nome: p.nome, subarea: p.subarea, tipo: tipoDaSubarea(p.subarea), projeto_ativo: p.ativo,
    etiqueta_clickup: p.etiqueta_clickup, inicio: null, fim: null,
    status: pl?.status ?? null, status_nome: CONFIG.status.find((s) => s.codigo === pl?.status)?.nome ?? null,
    gestores: pl?.gestores ?? [], gestores_campanhas: [...new Set(cs.map((c) => c.gestor).filter((g): g is string => !!g))].sort(),
    receita: null,
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

export const demoConfig = (): ConfigTrafego => structuredClone(CONFIG);
export const demoResumo = (): LinhaResumo[] => PROJETOS.map(linha);
export const demoContas = (): Conta[] => CONTAS.map((c) => ({ ...c, campanhas: CAMPS.filter((x) => x.conta_id === c.id).length }));

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
    status: (p.status as string) || null,
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
  const v = { plataforma: String(p.plataforma), conta_externa: String(p.conta_externa ?? '').replace(/^act_/i, ''), nome: String(p.nome ?? ''), dono: p.dono as Dono, cliente: (p.cliente as string) || null, moeda: String(p.moeda || 'BRL'), ativa: p.ativa !== false, obs: (p.obs as string) || null };
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
