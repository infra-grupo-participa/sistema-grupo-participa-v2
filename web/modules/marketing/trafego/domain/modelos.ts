// Marketing > Tráfego: MODELOS DE LANÇAMENTO (migration 20261006d). Domínio puro: sem Next, sem Supabase.
//
// Um modelo tem nome livre, tipo de lançamento, as unidades a que se aplica (com um "padrão" por tipo + unidade), fases
// com datas RELATIVAS às do projeto e % da verba máxima, campanhas esperadas, itens do checklist (com o momento) e metas
// padrão opcionais (CPL e % MQL). O banco é quem manda (mkt_trafego.modelo_previa, public.trafego_modelo_aplicar); aqui
// fica a MESMA conta, para a tela, o modo de demonstração e os testes. Mudou lá, muda aqui.

export type Momento = 'antes' | 'durante' | 'encerramento';
export type RefData = 'captacao_inicio' | 'captacao_fim' | 'evento_inicio' | 'evento_fim';

export const ROTULO_MOMENTO: Record<Momento, string> = {
  antes: 'Antes de subir as campanhas',
  durante: 'Durante',
  encerramento: 'Encerramento',
};
export const MOMENTOS: Momento[] = ['antes', 'durante', 'encerramento'];

export const ROTULO_REF: Record<RefData, string> = {
  captacao_inicio: 'início da captação',
  captacao_fim: 'fim da captação',
  evento_inicio: 'início do evento',
  evento_fim: 'fim do evento',
};

export interface ModeloFase {
  fase: string; ordem: number; inicio_ref: RefData | null; inicio_dias: number; fim_ref: RefData | null; fim_dias: number;
  pct_verba: number | null; obs: string | null;
}
export interface ModeloCampanha { objetivo: string; fase: string | null; descricao: string | null; pagina: string | null; ordem?: number }
export interface ModeloItem { texto: string; momento: Momento; ordem?: number }
export interface ModeloUnidade { unidade: string; padrao: boolean }

/** O que public.trafego_modelos_listar devolve (um por modelo). */
export interface Modelo {
  id: number; nome: string; tipo_lancamento: string; tipo_lancamento_nome?: string; ativo: boolean; rascunho: boolean;
  meta_cpl: number | null; meta_pct_mql: number | null; obs: string | null; atualizado_em?: string;
  unidades: ModeloUnidade[]; fases: ModeloFase[]; campanhas: ModeloCampanha[]; itens: ModeloItem[];
}

/** O modelo na lista do cadastro (public.trafego_cadastro_listas). */
export interface ModeloResumo { id: number; nome: string; tipo_lancamento: string; ativo: boolean; rascunho: boolean; unidades: ModeloUnidade[] }

/** Datas do projeto que servem de referência. */
export interface DatasProjeto { captacao_inicio: string | null; captacao_fim: string | null; evento_inicio: string | null; evento_fim: string | null }

const DIA_MS = 86400000;
/** AAAA-MM-DD + n dias (UTC, sem fuso). */
export function somarDias(ymd: string, n: number): string {
  const d = new Date(Date.UTC(Number(ymd.slice(0, 4)), Number(ymd.slice(5, 7)) - 1, Number(ymd.slice(8, 10))) + n * DIA_MS);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

/** A data de referência do projeto + dias (igual mkt_trafego.data_ref). Nula sem referência ou sem a data no projeto. */
export function dataRelativa(ref: RefData | null, dias: number, p: DatasProjeto): string | null {
  const base = ref ? p[ref] : null;
  return base ? somarDias(base, dias || 0) : null;
}

/** "7 dias antes do início da captação", "no fim da captação", "3 dias depois do fim do evento". */
export function textoRelativo(ref: RefData | null, dias: number): string {
  if (!ref) return 'sem data';
  const n = Math.abs(dias || 0);
  if (!n) return `no ${ROTULO_REF[ref]}`;
  return `${n} dia${n > 1 ? 's' : ''} ${dias < 0 ? 'antes do' : 'depois do'} ${ROTULO_REF[ref]}`;
}

export const somaPct = (fases: Pick<ModeloFase, 'pct_verba'>[]) =>
  Math.round(fases.reduce((a, f) => a + (f.pct_verba ?? 0), 0) * 100) / 100;

const CODIGO_PAGINA = /^[a-z]{2}[0-9]{1,3}(-[a-z])?$/;

/** Erro do formulário do modelo antes de chamar o banco (o banco confere de novo). regras = unidade → tipos que valem. */
export function validarModelo(m: Pick<Modelo, 'nome' | 'tipo_lancamento' | 'unidades' | 'fases' | 'campanhas' | 'itens' | 'meta_pct_mql'>,
  regras: Record<string, string[]>, objetivos: string[]): string | null {
  const nome = m.nome.trim();
  if (nome.length < 3 || nome.length > 80) return 'Nome do modelo: de 3 a 80 letras.';
  if (!m.tipo_lancamento) return 'Escolha o tipo de lançamento.';
  if (m.unidades.length === 0) return 'Marque pelo menos uma unidade.';
  const fora = m.unidades.find((u) => !(regras[u.unidade] ?? []).includes(m.tipo_lancamento));
  if (fora) return 'Unidade que não tem este tipo de lançamento (ex.: LPSG só na CSM).';
  const fases = m.fases.map((f) => f.fase);
  if (fases.some((f) => !f)) return 'Escolha a fase de cada linha.';
  if (new Set(fases).size !== fases.length) return 'A mesma fase duas vezes no modelo.';
  if (m.fases.some((f) => f.pct_verba != null && (f.pct_verba < 0 || f.pct_verba > 100))) return '% da verba de cada fase: de 0 a 100.';
  if (m.fases.some((f) => Math.abs(f.inicio_dias) > 365 || Math.abs(f.fim_dias) > 365)) return 'Dias relativos: de -365 a 365.';
  if (m.campanhas.some((c) => !objetivos.includes(c.objetivo))) return 'Objetivo da campanha esperada fora da lista.';
  if (m.campanhas.some((c) => c.pagina && !CODIGO_PAGINA.test(c.pagina.trim().toLowerCase()))) return 'Página da campanha esperada no formato AK1, BL2, AK1-B.';
  const textos = m.itens.map((i) => i.texto.trim().toLowerCase());
  if (textos.some((t) => t.length < 3 || t.length > 200)) return 'Texto de cada item: de 3 a 200 letras.';
  if (new Set(textos).size !== textos.length) return 'O mesmo item duas vezes no modelo.';
  if (m.meta_pct_mql != null && (m.meta_pct_mql < 0 || m.meta_pct_mql > 100)) return '% MQL: de 0 a 100.';
  return null;
}

// ─── Prévia de aplicar no projeto (a mesma conta de mkt_trafego.modelo_previa) ──────────────────────────────────────
export interface FaseAtual { fase: string; verba: number | null; inicio: string | null; fim: string | null }
export interface PreviaFase {
  fase: string; nome: string; ordem: number; pct_verba: number | null; inicio: string | null; fim: string | null; verba: number | null;
  existe: boolean; atual: { verba: number | null; inicio: string | null; fim: string | null } | null; muda: boolean;
  aviso: 'datas_invertidas' | 'sem_data' | null;
}
export interface PreviaModelo {
  modelo: { id: number; nome: string; rascunho: boolean; ativo: boolean };
  verba_maxima: number | null;
  fases: PreviaFase[];
  campanhas: (ModeloCampanha & { ja_existe: boolean })[];
  itens: (ModeloItem & { ja_existe: boolean })[];
  metas: { meta_cpl: number | null; meta_pct_mql: number | null; atual_cpl: number | null; atual_pct_mql: number | null };
  avisos: string[];
  pode_aplicar: boolean;
  /** Só na lista do projeto: é o padrão do tipo + unidade. */
  padrao?: boolean;
}

export const ROTULO_AVISO_PREVIA: Record<string, string> = {
  tipo_diferente: 'O tipo de lançamento do projeto é outro.',
  unidade_diferente: 'O modelo não vale para a unidade do projeto.',
  modelo_inativo: 'Modelo inativo.',
  sem_verba_maxima: 'O projeto não tem verba máxima: as fases nascem sem verba (preencha no Planejamento e aplique de novo confirmando).',
  sem_periodos: 'O projeto não tem período de captação nem do evento: as fases nascem sem data.',
};

const igual = (a: number | null, b: number | null) => (a == null ? b == null : b != null && Math.abs(a - b) < 0.005);

export function previaModelo(m: Modelo, proj: DatasProjeto & { tipo_lancamento: string | null; unidade: string | null },
  verbaMaxima: number | null, fasesAtuais: FaseAtual[], nomeFase: (f: string) => string,
  esperadasAtuais: ModeloCampanha[] = [], itensAtuais: string[] = [], metasAtuais: { meta_cpl: number | null; meta_pct_mql: number | null } = { meta_cpl: null, meta_pct_mql: null }): PreviaModelo {
  const avisos: string[] = [];
  if (proj.tipo_lancamento !== m.tipo_lancamento) avisos.push('tipo_diferente');
  if (!proj.unidade || !m.unidades.some((u) => u.unidade === proj.unidade)) avisos.push('unidade_diferente');
  if (!m.ativo) avisos.push('modelo_inativo');
  if (verbaMaxima == null) avisos.push('sem_verba_maxima');
  if (!proj.captacao_inicio && !proj.evento_inicio) avisos.push('sem_periodos');
  const fases = [...m.fases].sort((a, b) => a.ordem - b.ordem || a.fase.localeCompare(b.fase)).map((f): PreviaFase => {
    const ini = dataRelativa(f.inicio_ref, f.inicio_dias, proj);
    const fim = dataRelativa(f.fim_ref, f.fim_dias, proj);
    const invertida = !!ini && !!fim && fim < ini;
    const verba = verbaMaxima != null && f.pct_verba != null ? Math.round(verbaMaxima * f.pct_verba) / 100 : null;
    const a = fasesAtuais.find((x) => x.fase === f.fase) ?? null;
    const muda = !!a && ((verba != null && !igual(verba, a.verba)) || (!invertida && ini != null && ini !== a.inicio) || (!invertida && fim != null && fim !== a.fim));
    return {
      fase: f.fase, nome: nomeFase(f.fase), ordem: f.ordem, pct_verba: f.pct_verba, inicio: invertida ? null : ini, fim: invertida ? null : fim, verba,
      existe: !!a, atual: a ? { verba: a.verba, inicio: a.inicio, fim: a.fim } : null, muda,
      aviso: invertida ? 'datas_invertidas' : (f.inicio_ref && !ini) || (f.fim_ref && !fim) ? 'sem_data' : null,
    };
  });
  const chave = (c: ModeloCampanha) => `${c.objetivo}|${c.descricao ?? ''}|${c.pagina ?? ''}`;
  const jaEsp = new Set(esperadasAtuais.map(chave));
  const jaItem = new Set(itensAtuais.map((t) => t.trim().toLowerCase()));
  return {
    modelo: { id: m.id, nome: m.nome, rascunho: m.rascunho, ativo: m.ativo }, verba_maxima: verbaMaxima, fases,
    campanhas: m.campanhas.map((c) => ({ ...c, ja_existe: jaEsp.has(chave(c)) })),
    itens: m.itens.map((i) => ({ ...i, ja_existe: jaItem.has(i.texto.trim().toLowerCase()) })),
    metas: { meta_cpl: m.meta_cpl, meta_pct_mql: m.meta_pct_mql, atual_cpl: metasAtuais.meta_cpl, atual_pct_mql: metasAtuais.meta_pct_mql },
    avisos, pode_aplicar: !avisos.some((a) => ['tipo_diferente', 'unidade_diferente', 'modelo_inativo'].includes(a)),
  };
}

/** Resumo do que aplicar faria: criadas, que mudariam (só confirmando) e iguais. */
export function contarPrevia(p: PreviaModelo) {
  return {
    novas: p.fases.filter((f) => !f.existe).length,
    mudam: p.fases.filter((f) => f.existe && f.muda).length,
    iguais: p.fases.filter((f) => f.existe && !f.muda).length,
    campanhas: p.campanhas.filter((c) => !c.ja_existe).length,
    itens: p.itens.filter((i) => !i.ja_existe).length,
  };
}

// ─── Campanhas esperadas × encontradas (a mesma regra de mkt_trafego.checklist) ─────────────────────────────────────
export interface Esperada { id: number; objetivo: string; fase: string | null; descricao: string | null; pagina: string | null; criada?: boolean }

/**
 * Por objetivo (e página, se a esperada tiver): a n-ésima esperada está criada se o projeto tem pelo menos n campanhas
 * com aquele objetivo (e página). Ordem das esperadas = a da lista.
 */
export function marcarCriadas(esperadas: Esperada[], campanhas: { objetivo: string | null; pagina: string | null }[]): Esperada[] {
  const vistos = new Map<string, number>();
  return esperadas.map((e) => {
    const k = `${e.objetivo}|${e.pagina ?? ''}`;
    const n = (vistos.get(k) ?? 0) + 1;
    vistos.set(k, n);
    const achadas = campanhas.filter((c) => c.objetivo === e.objetivo && (e.pagina == null || c.pagina === e.pagina)).length;
    return { ...e, criada: n <= achadas };
  });
}

// ─── Formulário do modelo (texto; vazio = sem valor) ────────────────────────────────────────────────────────────────
export const MODELO_VAZIO = (tipo = ''): Modelo => ({
  id: 0, nome: '', tipo_lancamento: tipo, ativo: true, rascunho: false, meta_cpl: null, meta_pct_mql: null, obs: null,
  unidades: [], fases: [], campanhas: [], itens: [],
});

/** O que vai para public.trafego_modelo_salvar. */
export function paraSalvar(m: Modelo) {
  return {
    ...(m.id ? { id: m.id } : {}), nome: m.nome.trim(), tipo_lancamento: m.tipo_lancamento, ativo: m.ativo, rascunho: m.rascunho,
    meta_cpl: m.meta_cpl ?? '', meta_pct_mql: m.meta_pct_mql ?? '', obs: m.obs ?? '',
    unidades: m.unidades.map((u) => ({ unidade: u.unidade, padrao: u.padrao })),
    fases: m.fases.map((f, i) => ({ ...f, ordem: i + 1, pct_verba: f.pct_verba ?? '' })),
    campanhas: m.campanhas.map((c, i) => ({ objetivo: c.objetivo, fase: c.fase ?? '', descricao: c.descricao ?? '', pagina: c.pagina ?? '', ordem: i + 1 })),
    itens: m.itens.map((x, i) => ({ texto: x.texto.trim(), momento: x.momento, ordem: i + 1 })),
  };
}

/** Modelos que valem para o projeto: ativos, do tipo e da unidade dele, o padrão primeiro, rascunho depois. */
export function modelosDoProjeto<T extends Pick<Modelo, 'nome' | 'ativo' | 'rascunho' | 'tipo_lancamento' | 'unidades'>>(
  ms: T[], tipo: string | null, unidade: string | null): (T & { padrao: boolean })[] {
  if (!tipo || !unidade) return [];
  return ms
    .filter((m) => m.ativo && m.tipo_lancamento === tipo && m.unidades.some((u) => u.unidade === unidade))
    .map((m) => ({ ...m, padrao: m.unidades.some((u) => u.unidade === unidade && u.padrao) }))
    .sort((a, b) => Number(b.padrao) - Number(a.padrao) || Number(a.rascunho) - Number(b.rascunho) || a.nome.localeCompare(b.nome));
}
