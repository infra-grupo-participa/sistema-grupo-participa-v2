// Construtor de dashboards: lógica pura de layout (inserir, mover, redimensionar, duplicar, desfazer).
// A grade tem 12 colunas no desktop; a largura do widget é guardada em quartos (1–4) e vira 3/6/9/12 colunas.
import { METRICAS } from '../../domain/metricas';
import type { Dashboard, MetricaKey, SessaoComercial, WidgetPainel } from '../../domain/types';
import { coerente, LARGURAS, validarWidget } from '../inicio/painel-edicao';

export type Largura = WidgetPainel['largura'];
export type Altura = 'normal' | 'alta';

/**
 * Widget de dashboard: o do painel + filtro por vendedor e altura.
 * Campos opcionais: dashboards antigos (e o painel do Início) continuam válidos.
 */
export interface WidgetDash extends WidgetPainel {
  /** Filtro por vendedor (null/ausente = time inteiro). */
  vendedorId?: string | null;
  altura?: Altura;
}

export const LIMITE_WIDGETS_DASH = 24;
export const LIMITE_HISTORICO = 50;

/** Colunas (de 12) que cada largura ocupa no desktop. */
export const COLUNAS_12: Record<Largura, number> = { 1: 3, 2: 6, 3: 9, 4: 12 };

// ── Biblioteca ──

export type GrupoBiblioteca = 'volume' | 'resultado' | 'disciplina' | 'funil';

export const GRUPOS_BIBLIOTECA: { key: GrupoBiblioteca; rotulo: string; metricas: MetricaKey[] }[] = [
  { key: 'volume', rotulo: 'Volume', metricas: ['abordados', 'responderam', 'entraram_contato'] },
  { key: 'resultado', rotulo: 'Resultado', metricas: ['vendas', 'receita', 'conversao'] },
  { key: 'disciplina', rotulo: 'Disciplina', metricas: ['criticos', 'sem_proximo', 'sem_dono', 'atrasadas', 'tempo_primeiro_contato'] },
  { key: 'funil', rotulo: 'Funil', metricas: ['abertos', 'em_negociacao', 'perdidos'] },
];

/** Ícone de cada métrica (nomes do mapa de `shared/ui/icons.tsx`). */
export const ICONE_METRICA: Record<MetricaKey, string> = {
  abordados: 'send', responderam: 'message', entraram_contato: 'inbox', em_negociacao: 'handshake', vendas: 'trophy',
  receita: 'dollar', abertos: 'kanban', criticos: 'flame', sem_proximo: 'calendar', sem_dono: 'user-x', atrasadas: 'clock',
  tempo_primeiro_contato: 'hourglass', conversao: 'target', perdidos: 'x',
};

/** Widget novo a partir de uma métrica da biblioteca, com visual que já faz sentido. */
export function widgetDaMetrica(metrica: MetricaKey, id: string): WidgetDash {
  const def = METRICAS[metrica];
  const temVendedor = def.agrupamentos.includes('vendedor');
  const base: WidgetDash = {
    id, titulo: def.nome, metrica, visual: temVendedor && metrica !== 'sem_dono' ? 'barras' : 'numero', periodo: '7d',
    agrupar: temVendedor ? 'vendedor' : 'nenhum', largura: temVendedor ? 2 : 1, funilId: null, vendedorId: null, altura: 'normal',
  };
  return coerente(base) as WidgetDash;
}

// ── Operações na lista (sempre devolvem lista nova) ──

/** Insere na posição (0 = início; fora do limite = fim). */
export function inserir(lista: WidgetDash[], w: WidgetDash, pos: number = lista.length): WidgetDash[] {
  const p = Math.max(0, Math.min(pos, lista.length));
  return [...lista.slice(0, p), w, ...lista.slice(p)];
}

/**
 * Move o item `de` para o ponto de inserção `ponto` (0..n, contado na lista ANTES de tirar o item).
 * É o que o indicador de soltura mostra: "cai antes do 3º" = ponto 2.
 */
export function moverParaPonto<T>(lista: T[], de: number, ponto: number): T[] {
  if (de < 0 || de >= lista.length) return lista;
  const p = Math.max(0, Math.min(ponto, lista.length));
  const destino = p > de ? p - 1 : p;
  if (destino === de) return lista;
  const out = [...lista];
  const [item] = out.splice(de, 1);
  out.splice(destino, 0, item);
  return out;
}

/** Move para a posição final `para` (índice depois de mover). Usado no "Mover para…". */
export function moverParaPosicao<T>(lista: T[], de: number, para: number): T[] {
  if (de < 0 || de >= lista.length) return lista;
  const p = Math.max(0, Math.min(para, lista.length - 1));
  if (p === de) return lista;
  const out = [...lista];
  const [item] = out.splice(de, 1);
  out.splice(p, 0, item);
  return out;
}

/** Move por id, `delta` posições (setas do teclado). */
export function moverPorDelta<T extends { id: string }>(lista: T[], id: string, delta: number): T[] {
  const i = lista.findIndex((w) => w.id === id);
  if (i < 0) return lista;
  return moverParaPosicao(lista, i, i + delta);
}

/** Ponto de inserção a partir de onde o ponteiro está sobre o alvo (metade esquerda = antes). */
export function pontoDeSoltura(indiceAlvo: number, lado: 'antes' | 'depois'): number {
  return lado === 'antes' ? indiceAlvo : indiceAlvo + 1;
}

/** Soltar no próprio lugar não muda nada (não mostra indicador). */
export function solturaInocua(de: number | null, ponto: number): boolean {
  return de != null && (ponto === de || ponto === de + 1);
}

export function limitarLargura(n: number): Largura {
  return Math.max(1, Math.min(4, Math.round(n))) as Largura;
}

export function redimensionar(lista: WidgetDash[], id: string, largura: number): WidgetDash[] {
  const lg = limitarLargura(largura);
  return lista.map((w) => (w.id === id && w.largura !== lg ? { ...w, largura: lg } : w));
}

export function mudarAltura(lista: WidgetDash[], id: string, altura: Altura): WidgetDash[] {
  return lista.map((w) => (w.id === id ? { ...w, altura } : w));
}

/**
 * Largura ao arrastar a alça: cada quarto da grade andado soma/subtrai 1.
 * `larguraGrade` em px (a grade inteira = 4 quartos).
 */
export function larguraPorArraste(inicial: Largura, dx: number, larguraGrade: number): Largura {
  if (larguraGrade <= 0) return inicial;
  return limitarLargura(inicial + dx / (larguraGrade / 4));
}

/** Atualiza campos de um widget, mantendo visual/agrupamento coerentes com a métrica. */
export function atualizarWidget(lista: WidgetDash[], id: string, p: Partial<WidgetDash>): WidgetDash[] {
  return lista.map((w) => (w.id === id ? (coerente({ ...w, ...p }) as WidgetDash) : w));
}

/** Copia logo depois do original. */
export function duplicarWidget(lista: WidgetDash[], id: string, novoId: string): WidgetDash[] {
  const i = lista.findIndex((w) => w.id === id);
  if (i < 0) return lista;
  const orig = lista[i];
  const titulo = `${orig.titulo} (cópia)`.slice(0, 60);
  return inserir(lista, { ...orig, id: novoId, titulo }, i + 1);
}

export function removerWidget(lista: WidgetDash[], id: string): WidgetDash[] {
  return lista.filter((w) => w.id !== id);
}

/** Classes da grade de 12 (container query: a grade se ajusta ao espaço que sobra, não à tela). Literais para o Tailwind. */
export const SPAN_GRADE: Record<Largura, string> = {
  1: '@xl:col-span-3 @4xl:col-span-3',
  2: '@xl:col-span-6 @4xl:col-span-6',
  3: '@xl:col-span-6 @4xl:col-span-9',
  4: '@xl:col-span-6 @4xl:col-span-12',
};

// ── Desfazer / refazer ──

export interface Historico<T> {
  passado: T[];
  presente: T;
  futuro: T[];
  /** Mudanças seguidas com a mesma chave (ex.: digitar o título) viram um passo só. */
  ultimaChave: string | null;
}

export function criarHistorico<T>(inicial: T): Historico<T> {
  return { passado: [], presente: inicial, futuro: [], ultimaChave: null };
}

export function aplicar<T>(h: Historico<T>, novo: T, chave: string | null = null): Historico<T> {
  if (novo === h.presente) return h;
  if (chave && chave === h.ultimaChave) return { ...h, presente: novo, futuro: [] };
  const passado = [...h.passado, h.presente].slice(-LIMITE_HISTORICO);
  return { passado, presente: novo, futuro: [], ultimaChave: chave };
}

export function desfazer<T>(h: Historico<T>): Historico<T> {
  if (!h.passado.length) return h;
  const anterior = h.passado[h.passado.length - 1];
  return { passado: h.passado.slice(0, -1), presente: anterior, futuro: [h.presente, ...h.futuro], ultimaChave: null };
}

export function refazer<T>(h: Historico<T>): Historico<T> {
  if (!h.futuro.length) return h;
  const [proximo, ...resto] = h.futuro;
  return { passado: [...h.passado, h.presente], presente: proximo, futuro: resto, ultimaChave: null };
}

/** Fecha o passo atual: a próxima mudança com a mesma chave vira passo novo (ex.: saiu do campo). */
export function fecharPasso<T>(h: Historico<T>): Historico<T> {
  return h.ultimaChave ? { ...h, ultimaChave: null } : h;
}

// ── Dashboards ──

export function widgetsMudaram(a: WidgetDash[], b: WidgetDash[]): boolean {
  return JSON.stringify(a) !== JSON.stringify(b);
}

/** Erro que impede salvar, ou null. */
export function validarDashboard(nome: string, widgets: WidgetDash[]): string | null {
  if (!nome.trim()) return 'Dê um nome ao dashboard.';
  if (nome.trim().length > 60) return 'Nome com no máximo 60 caracteres.';
  if (widgets.length > LIMITE_WIDGETS_DASH) return `No máximo ${LIMITE_WIDGETS_DASH} widgets por dashboard.`;
  for (const w of widgets) {
    const e = validarWidget(w);
    if (e) return `${w.titulo.trim() || METRICAS[w.metrica].nome}: ${e}`;
    if (!LARGURAS.includes(w.largura)) return 'Largura entre 1 e 4.';
  }
  return null;
}

/** Só o dono e o gestor editam (o compartilhado os outros só veem). */
export function podeEditarDashboard(d: Pick<Dashboard, 'donoId'>, sessao: SessaoComercial | null): boolean {
  return !!sessao && (d.donoId === sessao.vendedorId || sessao.papel === 'gestor');
}

/** Meus primeiro, depois os compartilhados por outras pessoas; cada grupo por nome. */
export function separarDashboards(lista: Dashboard[], euId: string | null): { meus: Dashboard[]; compartilhados: Dashboard[] } {
  const porNome = (a: Dashboard, b: Dashboard) => a.nome.localeCompare(b.nome, 'pt-BR');
  return {
    meus: lista.filter((d) => d.donoId === euId).sort(porNome),
    compartilhados: lista.filter((d) => d.donoId !== euId).sort(porNome),
  };
}

/** "Cópia de X", "Cópia de X (2)"… sem repetir nome existente. */
export function nomeDeCopia(nome: string, existentes: string[]): string {
  const base = `Cópia de ${nome}`.slice(0, 55);
  const usados = new Set(existentes.map((n) => n.trim().toLowerCase()));
  if (!usados.has(base.toLowerCase())) return base;
  for (let i = 2; i < 100; i++) {
    const c = `${base} (${i})`;
    if (!usados.has(c.toLowerCase())) return c;
  }
  return base;
}

/** Ids novos para todos os widgets (ao duplicar dashboard ou aplicar modelo). */
export function renovarIds(widgets: WidgetDash[], prefixo: string): WidgetDash[] {
  return widgets.map((w, i) => ({ ...w, id: `${prefixo}-${i + 1}` }));
}

// ── Modelos prontos ──

export type ModeloKey = 'gestor' | 'meu_dia' | 'funil_perdas' | 'recuperacao';

type Def = [titulo: string, metrica: MetricaKey, visual: WidgetDash['visual'], periodo: WidgetDash['periodo'], agrupar: WidgetDash['agrupar'], largura: Largura, altura?: Altura];

const DEF_MODELOS: Record<ModeloKey, { nome: string; descricao: string; icone: string; widgets: Def[] }> = {
  gestor: {
    nome: 'Visão do gestor', icone: 'users',
    descricao: 'Resultado do time, ranking por vendedor e onde a disciplina está falhando.',
    widgets: [
      ['Receita do mês', 'receita', 'numero', 'mes', 'nenhum', 1],
      ['Vendas do mês', 'vendas', 'numero', 'mes', 'nenhum', 1],
      ['Conversão do mês', 'conversao', 'numero', 'mes', 'nenhum', 1],
      ['Prazo crítico agora', 'criticos', 'numero', 'hoje', 'nenhum', 1],
      ['Vendas por vendedor', 'vendas', 'barras', 'mes', 'vendedor', 2, 'alta'],
      ['Abordados por dia', 'abordados', 'linha', '30d', 'dia', 2],
      ['Atividades atrasadas por vendedor', 'atrasadas', 'barras', 'hoje', 'vendedor', 2],
      ['Sem dono agora', 'sem_dono', 'numero', 'hoje', 'nenhum', 1],
      ['Tempo até o primeiro contato', 'tempo_primeiro_contato', 'numero', '7d', 'nenhum', 1],
    ],
  },
  meu_dia: {
    nome: 'Meu dia', icone: 'sun',
    descricao: 'O que precisa de ação hoje: atrasadas, prazo crítico, sem próximo passo e o esforço do dia.',
    widgets: [
      ['Atividades atrasadas', 'atrasadas', 'numero', 'hoje', 'nenhum', 1],
      ['Prazo crítico', 'criticos', 'numero', 'hoje', 'nenhum', 1],
      ['Sem próximo passo', 'sem_proximo', 'numero', 'hoje', 'nenhum', 1],
      ['Em negociação', 'em_negociacao', 'numero', 'hoje', 'nenhum', 1],
      ['Abordados hoje', 'abordados', 'numero', 'hoje', 'nenhum', 1],
      ['Responderam hoje', 'responderam', 'numero', 'hoje', 'nenhum', 1],
      ['Abordados na semana', 'abordados', 'barras', '7d', 'dia', 2],
    ],
  },
  funil_perdas: {
    nome: 'Funil e perdas', icone: 'kanban',
    descricao: 'Onde o negócio está parado e por que se perde venda, por etapa, funil e motivo.',
    widgets: [
      ['Abertos por etapa', 'abertos', 'barras', 'hoje', 'etapa', 2],
      ['Conversão por funil', 'conversao', 'barras', '30d', 'funil', 2],
      ['Perdidos por motivo', 'perdidos', 'pizza', '30d', 'motivo', 2, 'alta'],
      ['Em negociação por produto', 'em_negociacao', 'pizza', 'hoje', 'produto', 2],
      ['Perdidos no mês', 'perdidos', 'numero', 'mes', 'nenhum', 1],
      ['Conversão no mês', 'conversao', 'numero', 'mes', 'nenhum', 1],
    ],
  },
  recuperacao: {
    nome: 'Recuperação', icone: 'refresh',
    descricao: 'Velocidade de resposta e retorno do checkout: quem chegou, quem respondeu e quanto voltou.',
    widgets: [
      ['Tempo até o primeiro contato', 'tempo_primeiro_contato', 'numero', '7d', 'nenhum', 1],
      ['Entraram em contato', 'entraram_contato', 'numero', '7d', 'nenhum', 1],
      ['Responderam', 'responderam', 'numero', '7d', 'nenhum', 1],
      ['Vendas recuperadas', 'vendas', 'numero', '7d', 'nenhum', 1],
      ['Tempo até o primeiro contato por vendedor', 'tempo_primeiro_contato', 'barras', '7d', 'vendedor', 2],
      ['Receita por dia', 'receita', 'linha', '30d', 'dia', 2],
    ],
  },
};

export const MODELOS: { key: ModeloKey; nome: string; descricao: string; icone: string }[] =
  (Object.keys(DEF_MODELOS) as ModeloKey[]).map((key) => ({ key, nome: DEF_MODELOS[key].nome, descricao: DEF_MODELOS[key].descricao, icone: DEF_MODELOS[key].icone }));

/** Widgets do modelo, com ids únicos sob `prefixo`. Sempre coerentes (testado). */
export function widgetsDoModelo(key: ModeloKey, prefixo: string): WidgetDash[] {
  return DEF_MODELOS[key].widgets.map(([titulo, metrica, visual, periodo, agrupar, largura, altura], i) =>
    coerente({ id: `${prefixo}-${i + 1}`, titulo, metrica, visual, periodo, agrupar, largura, funilId: null, vendedorId: null, altura: altura ?? 'normal' } as WidgetDash) as WidgetDash);
}

/** Dashboard ainda não salvo (id vazio: o repositório cria). */
export function dashboardNovo(p: { nome: string; descricao: string; compartilhado: boolean; donoId: string; widgets: WidgetDash[]; agora: string }): Dashboard {
  return {
    id: '', nome: p.nome.trim(), descricao: p.descricao.trim() || null, donoId: p.donoId, compartilhado: p.compartilhado,
    widgets: p.widgets, criadoEm: p.agora, atualizadoEm: p.agora,
  };
}
