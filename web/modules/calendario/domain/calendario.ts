// Calendário da empresa (home /). Regra pura: sem Next, sem Supabase.
// Datas são sempre 'YYYY-MM-DD' (date do Postgres, sem fuso). Toda conta de dia é feita em UTC
// para não escorregar um dia no fuso do Brasil.

/** Fases de um projeto, na ordem do funil. */
export type Fase = 'captacao' | 'aquecimento' | 'evento' | 'carrinho' | 'replay';

export const FASES: Fase[] = ['captacao', 'aquecimento', 'evento', 'carrinho', 'replay'];

export const ROTULO_FASE: Record<Fase, string> = {
  captacao: 'Captação',
  aquecimento: 'Aquecimento / CPLs',
  evento: 'Evento / live',
  carrinho: 'Carrinho',
  replay: 'Replay / treplay',
};

/** Cor de cada fase (tokens do tema; nunca hex). */
export const COR_FASE: Record<Fase, { forte: string; suave: string; borda: string }> = {
  captacao: { forte: 'var(--info)', suave: 'var(--info-subtle)', borda: 'var(--info-border)' },
  aquecimento: { forte: 'var(--yellow)', suave: 'var(--yellow-subtle)', borda: 'var(--yellow-border)' },
  evento: { forte: 'var(--accent)', suave: 'var(--accent-subtle)', borda: 'var(--accent-border)' },
  carrinho: { forte: 'var(--green)', suave: 'var(--green-subtle)', borda: 'var(--green-border)' },
  replay: { forte: 'var(--purple)', suave: 'var(--purple-subtle)', borda: 'var(--purple-border)' },
};

export interface PeriodoFase {
  fase: Fase;
  inicio: string;
  fim: string;
  /** Replay/treplay só para a equipe: aparece marcado como "interno". */
  interno: boolean;
}

export interface LinkProjeto {
  nome: string;
  url: string;
}

export interface EventoCalendario {
  id: number;
  chave: string | null;
  sigla: string;
  nome: string;
  /** interno | externo */
  tipo: string | null;
  unidade: string | null;
  unidadeNome: string | null;
  tipoLancamento: string | null;
  tipoLancamentoNome: string | null;
  especialista: string | null;
  inicio: string | null;
  fim: string | null;
  fases: PeriodoFase[];
  links: LinkProjeto[];
}

// ─── datas ─────────────────────────────────────────────────────────────────────────────────────────

const YMD = /^(\d{4})-(\d{2})-(\d{2})$/;

export function ehYmd(v: unknown): v is string {
  if (typeof v !== 'string') return false;
  const m = v.match(YMD);
  if (!m) return false;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return d.getUTCFullYear() === +m[1] && d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3];
}

function paraUtc(ymd: string): Date {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function deUtc(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function somarDias(ymd: string, n: number): string {
  const d = paraUtc(ymd);
  d.setUTCDate(d.getUTCDate() + n);
  return deUtc(d);
}

export function ymdDe(ano: number, mes1a12: number, dia: number): string {
  return deUtc(new Date(Date.UTC(ano, mes1a12 - 1, dia)));
}

/** Hoje em São Paulo ('YYYY-MM-DD'). Fuso fixo: servidor e navegador dão o mesmo dia (sem erro de hidratação). */
export function hojeSaoPaulo(agora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(agora);
}

export function diasEntre(de: string, ate: string): number {
  return Math.round((paraUtc(ate).getTime() - paraUtc(de).getTime()) / 86400000);
}

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

export function rotuloMes(ano: number, mes1a12: number): string {
  return `${MESES[mes1a12 - 1]} de ${ano}`;
}

/** "09/11" ou "09/11 a 11/11"; ano só quando difere do de referência. */
export function rotuloPeriodo(inicio: string, fim: string, anoRef?: number): string {
  const f = (ymd: string) => {
    const [y, m, d] = ymd.split('-');
    return anoRef != null && Number(y) !== anoRef ? `${d}/${m}/${y}` : `${d}/${m}`;
  };
  return inicio === fim ? f(inicio) : `${f(inicio)} a ${f(fim)}`;
}

// ─── normalização do retorno da RPC ────────────────────────────────────────────────────────────────

function texto(v: unknown): string | null {
  return typeof v === 'string' && v.trim() ? v.trim() : null;
}

function normalizarFase(v: unknown): PeriodoFase | null {
  if (!v || typeof v !== 'object') return null;
  const o = v as Record<string, unknown>;
  const fase = o.fase as Fase;
  if (!FASES.includes(fase) || !ehYmd(o.inicio)) return null;
  const fim = ehYmd(o.fim) && o.fim >= o.inicio ? o.fim : o.inicio;
  // Replay/treplay é sempre interno (pedido do Arthur): o rótulo não depende do banco lembrar.
  return { fase, inicio: o.inicio, fim, interno: fase === 'replay' || o.interno === true };
}

function normalizarLink(v: unknown): LinkProjeto | null {
  if (!v || typeof v !== 'object') return null;
  const o = v as Record<string, unknown>;
  const url = texto(o.url);
  if (!url || !/^https:\/\//i.test(url)) return null;
  return { nome: texto(o.nome) ?? url, url };
}

/** Linha crua de public.calendario_eventos → EventoCalendario. Linha sem id/nome é descartada. */
export function normalizarEvento(raw: unknown): EventoCalendario | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  const id = Number(r.id);
  const nome = texto(r.nome);
  if (!Number.isFinite(id) || !nome) return null;
  const fases = (Array.isArray(r.fases) ? r.fases : [])
    .map(normalizarFase)
    .filter((f): f is PeriodoFase => f !== null)
    .sort((a, b) => a.inicio.localeCompare(b.inicio) || FASES.indexOf(a.fase) - FASES.indexOf(b.fase));
  const links = (Array.isArray(r.links) ? r.links : []).map(normalizarLink).filter((l): l is LinkProjeto => l !== null);
  const inicio = fases.length ? fases.reduce((m, f) => (f.inicio < m ? f.inicio : m), fases[0].inicio) : null;
  const fim = fases.length ? fases.reduce((m, f) => (f.fim > m ? f.fim : m), fases[0].fim) : null;
  return {
    id,
    chave: texto(r.chave),
    sigla: texto(r.sigla) ?? nome.slice(0, 6),
    nome,
    tipo: texto(r.tipo),
    unidade: texto(r.unidade),
    unidadeNome: texto(r.unidade_nome),
    tipoLancamento: texto(r.tipo_lancamento),
    tipoLancamentoNome: texto(r.tipo_lancamento_nome),
    especialista: texto(r.especialista),
    inicio,
    fim,
    fases,
    links,
  };
}

/** Especialista ou, sem ele, a marca/unidade (CSM, Escritório, Aurum, Diamantes). */
export function rotuloQuem(e: EventoCalendario): string | null {
  if (e.especialista && e.unidadeNome) return `${e.especialista} · ${e.unidadeNome}`;
  return e.especialista ?? e.unidadeNome;
}

// ─── filtros ───────────────────────────────────────────────────────────────────────────────────────

export interface Filtro {
  /** código de mkt.tipos_lancamento, ou '' = todos */
  tipoLancamento: string;
  /** código de mkt.unidades, ou '' = todas */
  unidade: string;
}

export const FILTRO_VAZIO: Filtro = { tipoLancamento: '', unidade: '' };

export function filtrar(eventos: EventoCalendario[], f: Filtro): EventoCalendario[] {
  return eventos.filter(
    (e) => (!f.tipoLancamento || e.tipoLancamento === f.tipoLancamento) && (!f.unidade || e.unidade === f.unidade),
  );
}

export interface OpcaoFiltro {
  valor: string;
  rotulo: string;
}

/** Opções dos filtros a partir dos próprios eventos (sem lista fixa que envelhece). */
export function opcoesFiltro(eventos: EventoCalendario[]): { tipos: OpcaoFiltro[]; unidades: OpcaoFiltro[] } {
  const tipos = new Map<string, string>();
  const unidades = new Map<string, string>();
  for (const e of eventos) {
    if (e.tipoLancamento) tipos.set(e.tipoLancamento, e.tipoLancamentoNome ?? e.tipoLancamento);
    if (e.unidade) unidades.set(e.unidade, e.unidadeNome ?? e.unidade);
  }
  const ord = (m: Map<string, string>) =>
    [...m].map(([valor, rotulo]) => ({ valor, rotulo })).sort((a, b) => a.rotulo.localeCompare(b.rotulo, 'pt-BR'));
  return { tipos: ord(tipos), unidades: ord(unidades) };
}

// ─── grade do mês ──────────────────────────────────────────────────────────────────────────────────

export interface MarcaDia {
  eventoId: number;
  sigla: string;
  nome: string;
  fase: Fase;
  interno: boolean;
  /** a fase começa neste dia (ou a semana começa no meio da fase) — mostra o rótulo */
  comeca: boolean;
  /** a fase termina neste dia */
  termina: boolean;
}

export interface DiaGrade {
  data: string;
  dia: number;
  doMes: boolean;
  hoje: boolean;
  marcas: MarcaDia[];
}

/**
 * Grade de 6 semanas (segunda a domingo) do mês, com as fases que cobrem cada dia.
 * Sempre 42 dias, para a altura do bloco não pular de um mês para outro.
 */
export function montarGradeMes(ano: number, mes1a12: number, eventos: EventoCalendario[], hoje: string): DiaGrade[][] {
  const primeiro = ymdDe(ano, mes1a12, 1);
  const dow = paraUtc(primeiro).getUTCDay(); // 0 = domingo
  const recuo = (dow + 6) % 7; // segunda = 0
  const inicioGrade = somarDias(primeiro, -recuo);
  const fimGrade = somarDias(inicioGrade, 41);

  const periodos = eventos.flatMap((e) =>
    e.fases
      .filter((f) => f.inicio <= fimGrade && f.fim >= inicioGrade)
      .map((f) => ({ e, f })),
  );
  // ordem estável: quem começa antes fica em cima; empate pela ordem do funil
  periodos.sort(
    (a, b) => a.f.inicio.localeCompare(b.f.inicio) || FASES.indexOf(a.f.fase) - FASES.indexOf(b.f.fase) || a.e.id - b.e.id,
  );

  const semanas: DiaGrade[][] = [];
  for (let s = 0; s < 6; s++) {
    const semana: DiaGrade[] = [];
    for (let d = 0; d < 7; d++) {
      const data = somarDias(inicioGrade, s * 7 + d);
      const [y, m, dd] = data.split('-').map(Number);
      semana.push({
        data,
        dia: dd,
        doMes: y === ano && m === mes1a12,
        hoje: data === hoje,
        marcas: periodos
          .filter(({ f }) => f.inicio <= data && f.fim >= data)
          .map(({ e, f }) => ({
            eventoId: e.id,
            sigla: e.sigla,
            nome: e.nome,
            fase: f.fase,
            interno: f.interno,
            comeca: f.inicio === data || d === 0,
            termina: f.fim === data,
          })),
      });
    }
    semanas.push(semana);
  }
  return semanas;
}

// ─── próximos eventos ──────────────────────────────────────────────────────────────────────────────

export interface ItemProximo {
  evento: EventoCalendario;
  /** fase em andamento hoje (a mais adiantada no funil), se houver */
  faseAtual: PeriodoFase | null;
  /** próxima fase que ainda vai começar */
  proximaFase: PeriodoFase | null;
  /** dias até a próxima fase começar (0 = hoje) */
  diasAteProxima: number | null;
}

/** Projetos que ainda não acabaram, do mais próximo ao mais distante. */
export function proximosEventos(eventos: EventoCalendario[], hoje: string, limite = 8): ItemProximo[] {
  return eventos
    .filter((e) => e.fim != null && e.fim >= hoje)
    .map((e) => {
      const emCurso = e.fases.filter((f) => f.inicio <= hoje && f.fim >= hoje);
      const faseAtual = emCurso.length
        ? emCurso.reduce((a, b) => (FASES.indexOf(b.fase) > FASES.indexOf(a.fase) ? b : a))
        : null;
      const proximaFase = e.fases.find((f) => f.inicio > hoje) ?? null;
      return {
        evento: e,
        faseAtual,
        proximaFase,
        diasAteProxima: proximaFase ? diasEntre(hoje, proximaFase.inicio) : null,
      };
    })
    .sort((a, b) => {
      const ka = a.faseAtual ? hoje : a.proximaFase?.inicio ?? a.evento.inicio ?? '9999';
      const kb = b.faseAtual ? hoje : b.proximaFase?.inicio ?? b.evento.inicio ?? '9999';
      return ka.localeCompare(kb) || a.evento.nome.localeCompare(b.evento.nome, 'pt-BR');
    })
    .slice(0, limite);
}

/** Projetos ativos do cadastro sem nenhuma data (o Marketing ainda não preencheu). */
export function semData(eventos: EventoCalendario[]): EventoCalendario[] {
  return eventos.filter((e) => e.fases.length === 0);
}

// ─── janela de carga ───────────────────────────────────────────────────────────────────────────────

/** Janela que a tela pede ao banco: do 1º dia do mês anterior ao último dia de 3 meses à frente (< 400 dias). */
export function janelaCarga(ano: number, mes1a12: number): { de: string; ate: string } {
  const de = ymdDe(ano, mes1a12 - 1, 1);
  const ate = somarDias(ymdDe(ano, mes1a12 + 4, 1), -1);
  return { de, ate };
}

/** O mês pedido cabe na janela já carregada? (para não chamar o banco de novo) */
export function mesNaJanela(ano: number, mes1a12: number, janela: { de: string; ate: string }): boolean {
  const ini = ymdDe(ano, mes1a12, 1);
  const fim = somarDias(ymdDe(ano, mes1a12 + 1, 1), -1);
  // a grade mostra até 6 dias antes/depois do mês; basta o mês em si estar dentro
  return ini >= janela.de && fim <= janela.ate;
}

export function mesSeguinte(ano: number, mes1a12: number, delta: number): { ano: number; mes: number } {
  const d = new Date(Date.UTC(ano, mes1a12 - 1 + delta, 1));
  return { ano: d.getUTCFullYear(), mes: d.getUTCMonth() + 1 };
}
