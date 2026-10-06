// Marketing > Tráfego: cadastro do projeto (evento) e gerador de nome de campanha e UTM. Domínio puro.
//
// O banco é quem manda (migration 20261006j): mkt.unidades, mkt.tipos_lancamento, mkt.lancamento_regras,
// mkt.especialistas, mkt_trafego.utm_parametros. As listas chegam por parâmetro (trafego_cadastro_listas); aqui ficam as
// regras da tela, as mesmas do banco:
//   - tipo interno ou externo; unidade do tipo (interno: CSM ou Escritório; externo: Aurum ou Diamantes);
//   - tipo de lançamento só entre os que valem para a unidade; unidade com um só (Aurum: palestra) preenche sozinho;
//   - especialista interno da lista; externo cadastrado na hora pelo nome;
//   - período de captação e do evento, cada um com início e fim (ou nenhum); o projeto inteiro vai do começo mais cedo ao
//     fim mais tarde; a captação é o padrão da fase de captação; a receita sem período próprio do produto vai do início
//     da captação ao fim do evento (periodoReceita; PROVISÓRIO, a confirmar pelo Victor);
//   - etiqueta do ClickUp no formato da chave única do gp-operacoes (minúsculas, números e hífen; edição com data termina
//     em -aaaa-mm: aviso, não recusa).

import { traduzirCampanha, type ListasCampanha } from '../../projetos/domain/campanha';
import { CODIGO_PAGINA_RE, ETIQUETA_RE, SIGLA_RE, normalizarSigla } from '../../projetos/domain/projetos';
import { marcarCriadas, type Esperada, type ModeloResumo, type Momento } from './modelos';
import type { AcaoChecklist, Checklist, ItemChecklist, Tipo } from './tipos';

export interface Unidade { codigo: string; tipo: Tipo; nome: string; descricao: string | null }
export interface TipoLancamento { codigo: string; nome: string }
export interface Especialista { id: number; nome: string; tipo: Tipo; unidade: string | null }
export interface ParametroUtm { parametro: string; valor: string }

/** O que public.trafego_cadastro_listas devolve. */
export interface ListasCadastro {
  unidades: Unidade[];
  tipos_lancamento: TipoLancamento[];
  /** unidade → tipos de lançamento que valem (na ordem da lista). */
  regras: Record<string, string[]>;
  especialistas: Especialista[];
  objetivos: string[];
  /** plataforma → parâmetros de URL (Meta: as macros oficiais). */
  utm: Record<string, ParametroUtm[]>;
  /** Modelos de lançamento (20261006l): para o "Aplicar modelo" e a aba de modelos. */
  modelos: ModeloResumo[];
  /** Etiquetas reais dos spaces do ClickUp (vazia = sem coleta: a tela pede texto). */
  etiquetas_clickup: string[];
}

export interface SugestaoCampanha { id: number; nome: string; plataforma: string; conta_id: number; conta: string; status_plataforma: string | null }

/** O que public.trafego_projeto_cadastro devolve. "linha" (20261005m) continua vindo, mas a tela não mostra nem pede mais
 *  (revisão do Victor, 06/10/2026: o nome do projeto basta). */
export interface ProjetoCadastro {
  id: number; sigla: string; nome: string; linha: string; etiqueta_clickup: string | null; inicio: string | null; fim: string | null;
  captacao_inicio: string | null; captacao_fim: string | null; evento_inicio: string | null; evento_fim: string | null;
  ativo: boolean; tipo: Tipo | null; unidade: string | null; tipo_lancamento: string | null; especialista_id: number | null;
  especialista_nome: string | null; status: string | null; gestores: string[]; contas: number[];
  paginas: { codigo: string; nome: string }[]; sugestoes: SugestaoCampanha[]; fases_planejadas: number;
  /** Modelo aplicado (20261006l); nulo = nenhum. */
  modelo: { id: number | null; nome: string; aplicado_em: string } | null;
  /** Quantos modelos ativos valem para o tipo de lançamento e a unidade do projeto. */
  modelos_disponiveis: number;
  /** Campanhas esperadas do projeto (vieram do modelo). O gerador oferece. */
  esperadas: Esperada[];
}

/** O formulário da tela (texto; vazio = sem valor). */
export interface ProjetoForm {
  id?: number; sigla: string; nome: string; etiqueta_clickup: string;
  /** Início e fim de antes (sem separação). Só reenviados; com período novo, o banco recalcula. */
  inicio: string; fim: string;
  captacao_inicio: string; captacao_fim: string; evento_inicio: string; evento_fim: string; ativo: boolean;
  tipo: '' | Tipo; unidade: string; tipo_lancamento: string; especialista_id: number | null; especialista_nome: string;
  status: string; gestores: string[]; contas: number[];
}

export const PROJETO_FORM_VAZIO: ProjetoForm = {
  sigla: '', nome: '', etiqueta_clickup: '', inicio: '', fim: '', captacao_inicio: '', captacao_fim: '', evento_inicio: '',
  evento_fim: '', ativo: true, tipo: '', unidade: '', tipo_lancamento: '',
  especialista_id: null, especialista_nome: '', status: '', gestores: [], contas: [],
};

export function formDoCadastro(c: ProjetoCadastro): ProjetoForm {
  return {
    id: c.id, sigla: c.sigla, nome: c.nome, etiqueta_clickup: c.etiqueta_clickup ?? '', inicio: c.inicio ?? '',
    fim: c.fim ?? '', captacao_inicio: c.captacao_inicio ?? '', captacao_fim: c.captacao_fim ?? '', evento_inicio: c.evento_inicio ?? '',
    evento_fim: c.evento_fim ?? '', ativo: c.ativo, tipo: c.tipo ?? '', unidade: c.unidade ?? '', tipo_lancamento: c.tipo_lancamento ?? '',
    especialista_id: c.especialista_id, especialista_nome: '', status: c.status ?? '', gestores: [...c.gestores], contas: [...c.contas],
  };
}

export const unidadesDoTipo = (l: ListasCadastro, tipo: '' | Tipo) => (tipo ? l.unidades.filter((u) => u.tipo === tipo) : []);

/** Tipos de lançamento que valem para a unidade (vazio sem unidade). */
export function lancamentosDaUnidade(l: ListasCadastro, unidade: string): TipoLancamento[] {
  const cods = l.regras[unidade] ?? [];
  return cods.map((c) => l.tipos_lancamento.find((t) => t.codigo === c)).filter((t): t is TipoLancamento => !!t);
}

/** Unidade com um tipo só (Aurum: palestra): o código, que a tela mostra fixo. Senão null. */
export function lancamentoAutomatico(l: ListasCadastro, unidade: string): string | null {
  const t = lancamentosDaUnidade(l, unidade);
  return t.length === 1 ? t[0].codigo : null;
}

/** Ajusta o formulário quando muda tipo ou unidade: limpa o que deixou de valer e preenche o automático. */
export function ajustarForm(l: ListasCadastro, f: ProjetoForm): ProjetoForm {
  const x = { ...f };
  if (x.unidade && !unidadesDoTipo(l, x.tipo).some((u) => u.codigo === x.unidade)) x.unidade = '';
  const validos = lancamentosDaUnidade(l, x.unidade).map((t) => t.codigo);
  if (x.tipo_lancamento && !validos.includes(x.tipo_lancamento)) x.tipo_lancamento = '';
  const auto = lancamentoAutomatico(l, x.unidade);
  if (auto) x.tipo_lancamento = auto;
  if (x.especialista_id != null && !l.especialistas.some((e) => e.id === x.especialista_id && e.tipo === x.tipo)) x.especialista_id = null;
  if (x.tipo === 'interno') x.especialista_nome = '';
  return x;
}

/** Erro do formulário antes de chamar o banco (o banco confere de novo e recusa combinação inválida). */
export function validarCadastro(l: ListasCadastro, f: ProjetoForm): string | null {
  if (!SIGLA_RE.test(normalizarSigla(f.sigla))) return 'Sigla inválida: letras maiúsculas seguidas de 2 a 4 dígitos (ex.: PB26, HT33, SEMSET26).';
  if (f.nome.trim().length < 2) return 'Informe o nome do projeto.';
  if (f.inicio && f.fim && f.fim < f.inicio) return 'O fim não pode ser antes do início.';
  if (!!f.captacao_inicio !== !!f.captacao_fim || !!f.evento_inicio !== !!f.evento_fim) {
    return 'Preencha início e fim do período (captação e evento), ou deixe os dois em branco.';
  }
  if (f.captacao_inicio && f.captacao_fim < f.captacao_inicio) return 'Captação: o fim não pode ser antes do início.';
  if (f.evento_inicio && f.evento_fim < f.evento_inicio) return 'Evento: o fim não pode ser antes do início.';
  const etq = f.etiqueta_clickup.trim().toLowerCase();
  if (etq && !ETIQUETA_RE.test(etq)) return 'Etiqueta do ClickUp fora do formato da chave: minúsculas, números e hífen, sem acento (ex.: black-friday-2026-10).';
  if (!f.tipo) return 'Escolha se o projeto é interno ou externo.';
  const us = unidadesDoTipo(l, f.tipo);
  if (!us.some((u) => u.codigo === f.unidade)) return `Escolha a unidade do projeto ${f.tipo}: ${us.map((u) => u.nome).join(' ou ')}.`;
  const lt = lancamentosDaUnidade(l, f.unidade);
  if (f.tipo_lancamento && !lt.some((t) => t.codigo === f.tipo_lancamento)) {
    return `Tipo de lançamento não vale para esta unidade. Vale: ${lt.map((t) => t.nome).join(', ')}.`;
  }
  if (f.especialista_id != null && !l.especialistas.some((e) => e.id === f.especialista_id && e.tipo === f.tipo)) {
    return `Especialista fora da lista do projeto ${f.tipo}.`;
  }
  if (f.tipo === 'interno' && f.especialista_nome.trim()) return 'Especialista interno: escolha da lista.';
  return null;
}

/** Aviso (não recusa): edição com data e etiqueta sem -aaaa-mm no fim (chave única do gp-operacoes). */
export const etiquetaSemAnoMes = (etiqueta: string, fim: string) =>
  !!etiqueta.trim() && !!fim && !/-[0-9]{4}-[0-9]{2}$/.test(etiqueta.trim().toLowerCase());

export const ROTULO_AVISO_CADASTRO: Record<string, string> = {
  etiqueta_sem_ano_mes: 'A etiqueta não termina em -aaaa-mm (a chave única de uma edição com data termina no ano-mês).',
  especialista_cadastrado: 'Especialista novo cadastrado.',
  fases_acima_de_100: 'A soma do % da verba das fases do modelo passou de 100.',
};

// ─── Gerador de nome de campanha e UTM ──────────────────────────────────────────────────────────────────────────────
export interface NomeCampanhaEntrada { gestor: string; sigla: string; objetivo: string; descricao: string; pagina: string }

/** As partes da descrição livre: separadas por "|", aparadas, em maiúsculas (ex.: "teaser | meta | pq" → TEASER, META, PQ). */
export const partesDescricao = (descricao: string) => descricao.split('|').map((x) => x.replace(/\s+/g, ' ').trim().toUpperCase());

/**
 * Monta o nome no padrão GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA (página opcional) e confere pela mesma tradução
 * do banco. A DESCRIÇÃO pode ter várias partes separadas por "|" (revisão de 06/10/2026), ex.: TEASER | META | PQ | ABO.
 * Sem página escolhida, a última parte da descrição não pode ter cara de código de página (AK1), senão o nome seria lido
 * com página. Retorna o nome canônico ou os erros.
 */
export function montarNomeCampanha(e: NomeCampanhaEntrada, listas: ListasCampanha): { nome: string | null; erros: string[] } {
  const desc = partesDescricao(e.descricao);
  if (desc.some((x) => x === '')) return { nome: null, erros: ['Descrição com parte vazia entre "|".'] };
  if (!e.pagina.trim() && desc.length > 0 && CODIGO_PAGINA_RE.test(desc[desc.length - 1].toLowerCase())) {
    return { nome: null, erros: [`A última parte da descrição (${desc[desc.length - 1]}) tem formato de código de página: escolha em "Página" ou mude o texto.`] };
  }
  const partes = [e.gestor.trim(), e.sigla.trim(), e.objetivo.trim(), ...desc, ...(e.pagina.trim() ? [e.pagina.trim()] : [])];
  const t = traduzirCampanha(partes.join(' | '), listas);
  if (!t.padrao) {
    const rotulo: Record<string, string> = {
      gestor_desconhecido: 'Escolha o gestor.', sigla_invalida: 'Sigla do projeto inválida.', projeto_nao_cadastrado: 'Projeto não cadastrado.',
      objetivo_desconhecido: 'Escolha o objetivo.', descricao_vazia: 'Escreva a descrição.', campo_vazio: 'Descrição com parte vazia entre "|".',
      numero_de_campos: 'Preencha os campos.', vazio: 'Preencha os campos.',
    };
    return { nome: null, erros: t.erros.map((x) => rotulo[x] ?? x) };
  }
  return { nome: t.nomeCanonico, erros: [] };
}

/** A linha de parâmetros de URL (campo "Parâmetros de URL" do anúncio no Meta): p1=v1&p2=v2, na ordem da tabela. */
export const linhaUtm = (parametros: ParametroUtm[]) => parametros.map((p) => `${p.parametro}=${p.valor}`).join('&');

// ─── Sugestões de campanha pela conta e sigla (a mesma regra de public.trafego_projeto_cadastro) ───────────────────
/** A sigla aparece no nome como palavra inteira (ZR28 casa em "zr28 ensaio", não em "zr280"). */
export function nomeTemSigla(nome: string, sigla: string): boolean {
  const n = nome.toUpperCase();
  return new RegExp(`(^|[^A-Z0-9])${sigla}([^A-Z0-9]|$)`).test(n);
}

/** O período do projeto inteiro que o banco grava (gatilho da 20261006j): do começo mais cedo ao fim mais tarde. */
export function periodoProjeto(f: Pick<ProjetoForm, 'inicio' | 'fim' | 'captacao_inicio' | 'captacao_fim' | 'evento_inicio' | 'evento_fim'>): { inicio: string; fim: string } {
  const ini = [f.captacao_inicio, f.evento_inicio].filter(Boolean).sort();
  const fim = [f.captacao_fim, f.evento_fim].filter(Boolean).sort();
  const novo = ini.length + fim.length > 0;
  return { inicio: novo && ini.length ? ini[0] : f.inicio, fim: novo && fim.length ? fim[fim.length - 1] : f.fim };
}

// ─── Checklist de montagem (a mesma regra de mkt_trafego.checklist da 20261006l; o demo e os testes usam isto) ─────
export interface ItemProjeto { id: number; texto: string; momento: Momento; feito_em: string | null; feito_por: string | null; do_modelo: boolean }
export interface EntradaChecklist {
  tipo: Tipo | null;
  contas: number; campanhas: number; foraPadrao: number; semFase: number; produtosHotmart: number; paginas: number;
  etiqueta: string | null; verbaMaxima: number | null; fases: number; metas: (number | null)[];
  /** Nome do modelo aplicado (nulo = nenhum). */
  modelo: string | null;
  esperadas: Esperada[];
  /** Campanhas do projeto: objetivo e código da página. */
  encontradas: { objetivo: string | null; pagina: string | null }[];
  status: string | null; eventoFim: string | null; hoje: string;
}

const ORDEM_MOMENTO: Record<Momento, number> = { antes: 1, durante: 2, encerramento: 3 };

export function montarChecklist(e: EntradaChecklist, itens: ItemProjeto[]): Checklist {
  const comCamp = e.campanhas > 0;
  const esperadas = marcarCriadas(e.esperadas, e.encontradas);
  const criadas = esperadas.filter((x) => x.criada).length;
  const a = (codigo: string, texto: string, momento: Momento, acao: AcaoChecklist, aplica: boolean, ok: boolean, detalhe: string | null = null): ItemChecklist =>
    ({ codigo, texto, momento, acao, aplica, ok: aplica && ok, detalhe });
  const automaticos = [
    a('contas', 'Contas de anúncio vinculadas', 'antes', 'projeto', true, e.contas > 0),
    a('etiqueta', 'Etiqueta do ClickUp preenchida', 'antes', 'projeto', true, !!e.etiqueta),
    a('paginas', 'Páginas do projeto cadastradas', 'antes', 'paginas', true, e.paginas > 0),
    a('hotmart', 'Produtos da Hotmart vinculados', 'antes', 'hotmart', e.tipo !== 'externo', e.produtosHotmart > 0),
    a('modelo', 'Modelo de lançamento aplicado', 'antes', 'modelo', true, !!e.modelo, e.modelo),
    a('verba', 'Verba máxima preenchida', 'antes', 'planejamento', true, e.verbaMaxima != null),
    a('fases', 'Fases planejadas', 'antes', 'fases', true, e.fases > 0),
    a('metas', 'Metas preenchidas (leads, receita ou CPL)', 'antes', 'planejamento', true, e.metas.some((m) => m != null)),
    a('campanhas', 'Campanhas com a sigla encontradas', 'durante', 'gerador', true, comCamp, `${e.campanhas} campanha(s)`),
    a('campanhas_esperadas', 'Campanhas esperadas criadas', 'durante', 'gerador', esperadas.length > 0, criadas === esperadas.length, `${criadas} de ${esperadas.length}`),
    a('fora_padrao', 'Nenhuma campanha fora do padrão', 'durante', 'campanhas', comCamp, e.foraPadrao === 0, e.foraPadrao > 0 ? `${e.foraPadrao} fora do padrão` : null),
    a('fases_campanhas', 'Fase de cada campanha definida', 'durante', 'campanhas', comCamp, e.semFase === 0, e.semFase > 0 ? `${e.semFase} sem fase` : null),
    a('encerrado', 'Status encerrado depois do fim do evento', 'encerramento', 'planejamento', !!e.eventoFim && e.eventoFim < e.hoje,
      e.status === 'encerrado' || e.status === 'inativo'),
  ];
  const manuais: ItemChecklist[] = [...itens]
    .sort((x, y) => ORDEM_MOMENTO[x.momento] - ORDEM_MOMENTO[y.momento] || x.id - y.id)
    .map((i) => ({ id: i.id, texto: i.texto, momento: i.momento, aplica: true, ok: !!i.feito_em, marcado_em: i.feito_em, marcado_por: i.feito_por, do_modelo: i.do_modelo }));
  const todos = [...automaticos, ...manuais];
  return {
    automaticos, manuais, feitos: todos.filter((x) => x.aplica && x.ok).length, total: todos.filter((x) => x.aplica).length,
    esperadas: esperadas.map((x) => ({ ...x, criada: !!x.criada })), modelo: e.modelo ? { id: null, nome: e.modelo, aplicado_em: '' } : null,
    pendentes_antes: todos.filter((x) => x.aplica && !x.ok && x.momento === 'antes').map((x) => x.texto),
  };
}

/** Itens do checklist agrupados por momento (a tela mostra nessa ordem). */
export function porMomento(c: Checklist): { momento: Momento; itens: ItemChecklist[] }[] {
  return (['antes', 'durante', 'encerramento'] as Momento[]).map((m) => ({
    momento: m, itens: [...c.automaticos, ...c.manuais].filter((i) => (i.momento ?? 'antes') === m),
  }));
}

type Periodos = { inicio: string | null; fim: string | null; captacao_inicio: string | null; captacao_fim: string | null; evento_inicio: string | null; evento_fim: string | null };
/**
 * Período padrão da RECEITA quando o produto da Hotmart não tem período próprio (a mesma regra de
 * mkt_trafego.periodo_receita, 20261006j): do início da captação até o fim do evento, para pegar a abertura de carrinho.
 * PROVISÓRIO (Victor, 06/10/2026, a confirmar depois): trocar aqui e na função do banco.
 */
export function periodoReceita(p: Periodos): { inicio: string | null; fim: string | null } {
  const temNovo = !!(p.captacao_inicio || p.evento_inicio);
  return {
    inicio: p.captacao_inicio || p.evento_inicio || p.inicio,
    fim: temNovo ? (p.evento_fim || p.captacao_fim) : p.fim,
  };
}
