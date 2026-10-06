// Marketing > Mensageria: tipos do contrato do banco e formatação. Domínio puro (sem Next, sem Supabase).
// Contrato: infra/supabase/migrations/20261005n.explain.md + 20261005o.explain.md (preços, custo estimado, integrações). O banco é a fonte da verdade: regra de negócio,
// validação e pendências ficam no SQL. Aqui só rótulo, formatação e a leitura (separar colunas) da planilha.
// Retorno e custo são `number | null`: null = "não lançado". NUNCA tratar null como 0.

export const CANAIS = ['whatsapp_api', 'email', 'sms', 'ligacao', 'grupo'] as const;
export type Canal = (typeof CANAIS)[number];
export const ROTULO_CANAL: Record<Canal, string> = {
  whatsapp_api: 'API WhatsApp',
  email: 'E-mail',
  sms: 'SMS',
  ligacao: 'Ligação',
  grupo: 'Grupo',
};
export const rotuloCanal = (c: string) => ROTULO_CANAL[c as Canal] ?? c;

/** Tipo da API oficial do WhatsApp. Só existe quando canal = whatsapp_api (o banco exige lá e recusa nos outros). */
export const TIPOS = ['utility', 'marketing'] as const;
export type TipoMensagem = (typeof TIPOS)[number];
export const ROTULO_TIPO: Record<TipoMensagem, string> = { utility: 'Utilidade', marketing: 'Marketing' };

export const FINALIDADES = ['mensageria', 'comercial', 'financeiro', 'suporte'] as const;
export type Finalidade = (typeof FINALIDADES)[number];
export const ROTULO_FINALIDADE: Record<Finalidade, string> = {
  mensageria: 'Mensageria', comercial: 'Comercial', financeiro: 'Financeiro', suporte: 'Suporte',
};

export const STATUS_NUMERO = ['ativo', 'aquecendo', 'restrito', 'disponivel'] as const;
export type StatusNumero = (typeof STATUS_NUMERO)[number];
export const ROTULO_STATUS_NUMERO: Record<StatusNumero, string> = {
  ativo: 'Ativo', aquecendo: 'Aquecendo', restrito: 'Restrito', disponivel: 'Disponível',
};

export const API_FERRAMENTA = ['sim', 'futura', 'nao'] as const;
export type ApiFerramenta = (typeof API_FERRAMENTA)[number];
export const ROTULO_API: Record<ApiFerramenta, string> = { sim: 'Sim', futura: 'Em breve', nao: 'Não, registro manual' };

/**
 * Pendências calculadas pelo banco (mkt_mensageria.pendencias_v2, 20261005o), na ordem dele.
 * sem_custo mudou de sentido na 20261005o: nem custo real nem estimado (antes: só custo real vazio).
 */
export const PENDENCIAS = ['sem_custo', 'sem_retorno', 'conferir_zero_leitura', 'sem_preco', 'sem_projeto'] as const;
export type Pendencia = (typeof PENDENCIAS)[number];
export const ROTULO_PENDENCIA: Record<Pendencia, string> = {
  sem_custo: 'Sem custo, nem estimado',
  sem_retorno: 'Sem retorno',
  conferir_zero_leitura: '0 lidas com custo: conferir',
  sem_preco: 'Sem preço cadastrado',
  sem_projeto: 'Sem projeto — classificar',
};
/** Rótulo da pendência; valor novo que o banco passe a mandar aparece cru, nunca some. */
export const rotuloPendencia = (p: string) => ROTULO_PENDENCIA[p as Pendencia] ?? p;

/** Faixa recomendada de capacidade por número (mensagens/dia). Fora dela, a tela só avisa (não é regra do banco). */
export const CAPACIDADE_MIN = 30;
export const CAPACIDADE_MAX = 50;
export const capacidadeForaDaFaixa = (cap: number | null) => cap != null && (cap < CAPACIDADE_MIN || cap > CAPACIDADE_MAX);

export const LIMITE_DIAS = 366;
export const DIAS_PADRAO = 30;

// ─── Formatos do contrato ───────────────────────────────────────────────────────────────────────────────────────────

export interface Resultado { ok: boolean; msg: string; id?: number; erros?: { campo: string; msg: string }[] }

export interface Disparo {
  id: number;
  enviado_em: string;
  /** null só em linha da integração sem [SIGLA] cadastrada na campanha (pendência sem_projeto). */
  projeto_id: number | null;
  projeto: string | null;
  canal: string;
  ferramenta_id: number;
  ferramenta: string;
  numero_id: number | null;
  numero: string | null;
  tipo: string | null;
  copy_texto: string | null;
  copy_link: string | null;
  publico_lista: string;
  publico_origem: string | null;
  tamanho_lista: number;
  entregues: number | null;
  lidas: number | null;
  cliques: number | null;
  falhas: number | null;
  custo_centavos: number | null;
  disparado_por: string;
  retorno_em: string | null;
  origem: string;
  origem_sistema: string | null;
  id_externo: string | null;
  importacao_id: number | null;
  atualizado_em: string;
  pendencias: string[];
  /** 20261005o. Nome da campanha na origem (integração). */
  campanha?: string | null;
  /** 20261005o. Custo pelo preço vigente no dia do envio; vem mesmo quando há custo real. */
  custo_estimado_centavos?: number | null;
  /** 20261005o. Ausente = banco ainda na 20261005n. */
  custo_fonte?: CustoFonte | null;
}

/** real = lançado (prevalece) · estimado = pelo preço · sem_preco = sem real e sem preço · null = falta entregues. */
export type CustoFonte = 'real' | 'estimado' | 'sem_preco';

export interface Totais {
  qtd: number;
  tamanho: number | null;
  entregues: number | null;
  lidas: number | null;
  cliques: number | null;
  falhas: number | null;
  custo_centavos: number | null;
  com_custo: number;
  sem_custo: number;
  sem_retorno: number;
  conferir_zero_leitura: number;
  // 20261005o (opcionais: o banco na 20261005n não manda)
  custo_estimado_centavos?: number | null;
  com_estimativa?: number;
  custo_total_centavos?: number | null;
  sem_preco?: number;
  sem_projeto?: number;
}

export interface TotalCanal {
  canal: string;
  qtd: number;
  tamanho: number | null;
  entregues: number | null;
  lidas: number | null;
  cliques: number | null;
  falhas: number | null;
  custo_centavos: number | null;
  sem_custo: number;
  custo_estimado_centavos?: number | null;
  custo_total_centavos?: number | null;
  sem_preco?: number;
  sem_projeto?: number;
}

export type ListaDisparos =
  | { ok: true; de: string; ate: string; limite: number; truncado: boolean; linhas: Disparo[]; totais: Totais; por_canal: TotalCanal[] }
  | { ok: false; msg: string };

export interface Numero {
  id: number;
  numero: string;
  projeto_id: number | null;
  projeto: string | null;
  frente: string | null;
  responsavel: string;
  finalidade: string;
  ferramenta_id: number | null;
  ferramenta: string | null;
  capacidade_dia: number | null;
  status: string;
  status_desde: string;
  arquivado_em: string | null;
  consumo_hoje: number;
  acima_da_capacidade: boolean;
  atualizado_em: string;
}

export interface Ferramenta {
  id: number;
  nome: string;
  api: string;
  custo_mensal_centavos: number | null;
  responsavel: string | null;
  ativa: boolean;
  obs: string | null;
  atualizado_em: string;
}

export interface ItemHistorico {
  id: number;
  acao: string;
  em: string;
  por: string | null;
  por_nome: string | null;
  /** 20261005o: 'api:<fonte>' quando a mudança veio da integração. */
  por_api?: string | null;
  antes: Record<string, unknown> | null;
  depois: Record<string, unknown> | null;
}

export interface ResultadoImportacao {
  ok: boolean;
  msg: string;
  erros: { linha: number; campo: string; msg: string }[];
  erros_total?: number;
  validas: number;
  total: number;
  duplicadas_banco?: number[];
  duplicadas_lote?: number[];
  importacao_id?: number;
}

// ─── Dinheiro ───────────────────────────────────────────────────────────────────────────────────────────────────────

const BRL = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** Centavos (inteiro do banco) → "R$ 1.234,56". null = não lançado → null (a tela mostra o selo, nunca "R$ 0,00"). */
export function fmtCentavos(c: number | null | undefined): string | null {
  return c == null ? null : BRL.format(c / 100);
}

/** Centavos → texto para o campo de edição ("1234,56"); null → "". */
export function centavosParaCampo(c: number | null | undefined): string {
  if (c == null) return '';
  const r = Math.floor(c / 100);
  const ct = String(c % 100).padStart(2, '0');
  return `${r},${ct}`;
}

/**
 * Reais digitados ("1.234,56", "12,5", "R$ 90", "12.50") → centavos.
 * Vazio → null (não lançado). Formato que não dá para ler → undefined (quem chama decide o que dizer).
 */
export function reaisParaCentavos(s: string | null | undefined): number | null | undefined {
  const v = (s ?? '').trim().replace(/^R\$\s*/i, '');
  if (v === '') return null;
  let m = v.match(/^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?$/);
  if (!m) m = v.match(/^(\d+)(?:\.(\d{1,2}))$/);
  if (!m) return undefined;
  const reais = Number(m[1].replace(/\./g, ''));
  const cent = m[2] ? Number(m[2].padEnd(2, '0')) : 0;
  const total = reais * 100 + cent;
  return Number.isSafeInteger(total) ? total : undefined;
}

/** Inteiro ≥ 0 digitado ("1234" ou "1.234"). Vazio → null. Inválido → undefined. */
export function inteiroDigitado(s: string | null | undefined): number | null | undefined {
  const v = (s ?? '').trim();
  if (v === '') return null;
  if (/^\d{1,9}$/.test(v)) return Number(v);
  if (/^\d{1,3}(\.\d{3}){1,2}$/.test(v)) return Number(v.replace(/\./g, ''));
  return undefined;
}

export const fmtNum = (n: number) => n.toLocaleString('pt-BR');

// ─── Datas (sempre no horário de São Paulo, como o banco) ───────────────────────────────────────────────────────────

const FUSO = 'America/Sao_Paulo';
const PARTES = new Intl.DateTimeFormat('en-CA', {
  timeZone: FUSO, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
});

/** Instante (ISO com fuso) → data 'AAAA-MM-DD' e hora 'HH:mm' em São Paulo. */
export function partesSP(iso: string | Date): { data: string; hora: string } {
  const d = typeof iso === 'string' ? new Date(iso) : iso;
  const p = Object.fromEntries(PARTES.formatToParts(d).map((x) => [x.type, x.value]));
  return { data: `${p.year}-${p.month}-${p.day}`, hora: `${p.hour}:${p.minute}` };
}

/** Hoje em São Paulo, 'AAAA-MM-DD'. */
export const hojeSP = (agora: Date = new Date()) => partesSP(agora).data;

/** 'AAAA-MM-DD' ± dias, sem fuso. */
export function somarDias(ymd: string, dias: number): string {
  const [y, m, d] = ymd.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + dias));
  return t.toISOString().slice(0, 10);
}

/** Período padrão: os últimos 30 dias, hoje incluído. */
export const periodoPadrao = (hoje: string) => ({ de: somarDias(hoje, -(DIAS_PADRAO - 1)), ate: hoje });

export const dataBR = (ymd: string) => `${ymd.slice(8, 10)}/${ymd.slice(5, 7)}/${ymd.slice(0, 4)}`;

/** "05/10/2026 14:30" no horário de São Paulo. */
export function dataHoraSP(iso: string | null | undefined): string {
  if (!iso) return '—';
  const { data, hora } = partesSP(iso);
  return `${dataBR(data)} ${hora}`;
}

// ─── Histórico ──────────────────────────────────────────────────────────────────────────────────────────────────────

const CARIMBOS = new Set(['atualizado_em', 'atualizado_por', 'criado_em', 'criado_por']);

/** Campos que mudaram entre antes e depois (carimbos de data/autor fora). */
export function camposAlterados(antes: Record<string, unknown> | null, depois: Record<string, unknown> | null) {
  if (!antes || !depois) return [];
  const chaves = new Set([...Object.keys(antes), ...Object.keys(depois)]);
  return [...chaves]
    .filter((k) => !CARIMBOS.has(k) && JSON.stringify(antes[k] ?? null) !== JSON.stringify(depois[k] ?? null))
    .map((k) => ({ campo: k, antes: antes[k] ?? null, depois: depois[k] ?? null }));
}

// ─── Planilha de importação ─────────────────────────────────────────────────────────────────────────────────────────
// O TS só separa colunas e entrega ao banco (mkt_msg_importar). Conversão e validação de cada valor ficam no SQL.

/** Cabeçalho exato do contrato (chaves de cada linha de mkt_msg_importar). */
export const COLUNAS_PLANILHA = [
  'data', 'hora', 'projeto', 'canal', 'ferramenta', 'numero', 'tipo', 'copy_texto', 'copy_link',
  'publico_lista', 'publico_origem', 'tamanho_lista', 'entregues', 'lidas', 'cliques', 'falhas', 'custo', 'disparado_por',
] as const;
export type ColunaPlanilha = (typeof COLUNAS_PLANILHA)[number];
export type LinhaPlanilha = Record<ColunaPlanilha, string | null>;

/**
 * Formato de cada coluna, para explicar no modal de importação. O modelo baixado traz SÓ o cabeçalho: linha de exemplo
 * com projeto e ferramenta reais já virou disparo de verdade quando alguém esquecia de apagar.
 */
export const FORMATO_COLUNA: Record<ColunaPlanilha, string> = {
  data: 'dia do envio, dd/mm/aaaa',
  hora: 'hh:mm, horário de Brasília',
  projeto: 'sigla, igual à de Projetos e páginas',
  canal: 'API WhatsApp, E-mail, SMS, Ligação ou Grupo',
  ferramenta: 'nome igual ao da aba Ferramentas',
  numero: 'com + e país; vazio se não usou número',
  tipo: 'Utilidade ou Marketing, só na API WhatsApp; vazio nos outros canais',
  copy_texto: 'texto enviado (texto, link ou os dois)',
  copy_link: 'link enviado',
  publico_lista: 'nome da lista',
  publico_origem: 'de onde veio a lista (opcional)',
  tamanho_lista: 'quantas pessoas, ex.: 1.234',
  entregues: 'vazio = não lançado; 0 só se foi zero',
  lidas: 'vazio = não lançado',
  cliques: 'vazio = não lançado',
  falhas: 'vazio = não lançado',
  custo: 'reais, ex.: 1.234,56; vazio = não lançado',
  disparado_por: 'quem disparou',
};

/** Modelo para baixar: BOM (o Excel abre os acentos certo) e o cabeçalho exato. Sem linha de exemplo. */
export function modeloCsv(): string {
  return '﻿' + COLUNAS_PLANILHA.join(';') + '\r\n';
}

/**
 * Separa o texto em linhas e células. Aspas duplas protegem `;` e quebra de linha; `""` dentro de aspas = `"`.
 * Devolve cada linha com o número dela no arquivo (1 = primeira linha), para o erro apontar a linha certa.
 */
export function separarCsv(texto: string, sep: string): { n: number; celulas: string[] }[] {
  const out: { n: number; celulas: string[] }[] = [];
  let linha: string[] = [];
  let cel = '';
  let aspas = false;
  let n = 1;
  let inicio = 1;
  const fechar = () => { linha.push(cel); cel = ''; };
  for (let i = 0; i < texto.length; i++) {
    const c = texto[i];
    if (aspas) {
      if (c === '"' && texto[i + 1] === '"') { cel += '"'; i++; }
      else if (c === '"') aspas = false;
      else { if (c === '\n') n++; cel += c; }
      continue;
    }
    if (c === '"') aspas = true;
    else if (c === sep) fechar();
    else if (c === '\r') { /* CRLF: o \n fecha a linha */ }
    else if (c === '\n') { fechar(); out.push({ n: inicio, celulas: linha }); linha = []; n++; inicio = n; }
    else cel += c;
  }
  if (cel !== '' || linha.length > 0) { fechar(); out.push({ n: inicio, celulas: linha }); }
  return out.filter((l) => l.celulas.some((x) => x.trim() !== ''));
}

export interface PlanilhaLida {
  /** Colunas do contrato que não vieram no cabeçalho. */
  faltando: string[];
  /** Colunas do cabeçalho que o contrato não tem (ignoradas). */
  sobrando: string[];
  linhas: LinhaPlanilha[];
  /** Número da linha no arquivo de cada item de `linhas` (o banco devolve a posição no array, 1 = primeiro). */
  linhaNoArquivo: number[];
}

const normalizarCabecalho = (s: string) => s.trim().toLowerCase().replace(/\s+/g, '_');

/** Lê CSV com `;` (o modelo). Colado do Excel/Planilhas vem com TAB: aceito também. Vazio → null. */
export function lerPlanilha(texto: string): PlanilhaLida {
  const limpo = texto.replace(/^﻿/, '');
  const primeira = limpo.split(/\r?\n/, 1)[0] ?? '';
  const sep = !primeira.includes(';') && primeira.includes('\t') ? '\t' : ';';
  const linhas = separarCsv(limpo, sep);
  if (linhas.length === 0) return { faltando: [...COLUNAS_PLANILHA], sobrando: [], linhas: [], linhaNoArquivo: [] };
  const cab = linhas[0].celulas.map(normalizarCabecalho);
  const idx = new Map<string, number>();
  cab.forEach((c, i) => { if (c && !idx.has(c)) idx.set(c, i); });
  return {
    faltando: COLUNAS_PLANILHA.filter((c) => !idx.has(c)),
    sobrando: cab.filter((c) => c && !(COLUNAS_PLANILHA as readonly string[]).includes(c)),
    linhas: linhas.slice(1).map(({ celulas }) => {
      const o = {} as LinhaPlanilha;
      for (const c of COLUNAS_PLANILHA) {
        const i = idx.get(c);
        const v = i == null ? '' : (celulas[i] ?? '').trim();
        o[c] = v === '' ? null : v;
      }
      return o;
    }),
    linhaNoArquivo: linhas.slice(1).map((l) => l.n),
  };
}

// ─── Custo exibido (20261005o) ──────────────────────────────────────────────────────────────────────────────────────
// O banco decide real/estimado/sem preço (custo_fonte). A tela só escolhe o texto. Nunca vira 0.

export type CustoExibido =
  | { k: 'real'; c: number }
  | { k: 'estimado'; c: number }
  | { k: 'sem_preco' }
  /** Há preço por entregue, mas entregues não foi lançado (a pendência sem_retorno explica). */
  | { k: 'falta_entregues' }
  /** Banco ainda sem custo estimado (20261005n): só o real, vazio = não lançado. */
  | { k: 'nao_lancado' };

export function custoExibido(d: Pick<Disparo, 'custo_centavos' | 'custo_estimado_centavos' | 'custo_fonte'>): CustoExibido {
  if (d.custo_centavos != null) return { k: 'real', c: d.custo_centavos };
  if (d.custo_fonte === 'estimado' && d.custo_estimado_centavos != null) return { k: 'estimado', c: d.custo_estimado_centavos };
  if (d.custo_fonte === 'sem_preco') return { k: 'sem_preco' };
  if (d.custo_fonte === null) return { k: 'falta_entregues' };
  return { k: 'nao_lancado' };
}

/** Custo do período (totais ou um canal): total = real + estimado. Banco na 20261005n: total = real, estimado nulo. */
export function resumoCusto(t: Pick<Totais, 'custo_centavos' | 'custo_estimado_centavos' | 'custo_total_centavos'>) {
  const total = t.custo_total_centavos === undefined ? t.custo_centavos : t.custo_total_centavos;
  return { total, estimado: t.custo_estimado_centavos ?? null };
}

// ─── Integrações (origem 'api') ─────────────────────────────────────────────────────────────────────────────────────

/** Fontes cadastradas na 20261005o (mkt_mensageria.fontes.chave). Chave nova aparece crua, nunca some. */
export const ROTULO_FONTE: Record<string, string> = {
  activecampaign: 'ActiveCampaign', unichat: 'Unichat', infobip: 'Infobip', sendflow: 'SendFlow', cs_disparos: 'CS Disparos',
};
export const rotuloFonte = (chave: string | null | undefined) => (chave ? ROTULO_FONTE[chave] ?? chave : 'integração');

export const linhaDaApi = (d: Pick<Disparo, 'origem'>) => d.origem === 'api';

/** O que mkt_msg_disparo_salvar aceita mudar numa linha da integração (o resto o banco ignora). */
export const CAMPOS_EDITAVEIS_API = ['projeto', 'tipo', 'custo_centavos'] as const;

// ─── Preços (20261005o) ─────────────────────────────────────────────────────────────────────────────────────────────

export const BASES_COBRANCA = ['entregues', 'tamanho_lista', 'mensalidade'] as const;
export type BaseCobranca = (typeof BASES_COBRANCA)[number];
export const ROTULO_BASE: Record<BaseCobranca, string> = {
  entregues: 'Por mensagem entregue',
  tamanho_lista: 'Por pessoa da lista',
  mensalidade: 'Mensalidade (0 por disparo)',
};
export const rotuloBase = (b: string) => ROTULO_BASE[b as BaseCobranca] ?? b;

export interface Preco {
  id: number;
  ferramenta_id: number;
  ferramenta: string;
  canal: string;
  tipo: string | null;
  base_cobranca: string;
  /** Centavos com até 4 casas (numeric(12,4)). */
  preco_centavos: number | string;
  vigente_desde: string;
  obs: string | null;
  criado_em: string;
  criado_por_nome: string | null;
  anulado_em: string | null;
  anulado_por_nome: string | null;
  anulado_motivo: string | null;
  vigente_hoje: boolean;
}
export interface ListaPrecos { ok: true; hoje: string; precos: Preco[] }

const BRL_PRECO = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 2, maximumFractionDigits: 6 });

/** Centavos com 4 casas → reais legível: 8 → "R$ 0,08"; 6,5 → "R$ 0,065"; 0,36 → "R$ 0,0036". */
export function fmtPrecoCentavos(c: number | string | null | undefined): string | null {
  if (c == null || c === '') return null;
  const n = typeof c === 'number' ? c : Number(String(c).replace(',', '.'));
  return Number.isFinite(n) ? BRL_PRECO.format(n / 100) : null;
}

/**
 * Preço digitado em REAIS ("0,08", "R$ 0,065", "1.5") → centavos em texto, sem conta de ponto flutuante
 * ("8", "6.5"). Vazio → null. Fora do formato (até 4 dígitos inteiros e 6 decimais) → undefined.
 */
export function precoReaisParaCentavos(s: string | null | undefined): string | null | undefined {
  const v = (s ?? '').trim().replace(/^R\$\s*/i, '');
  if (v === '') return null;
  const m = v.match(/^(\d{1,4})(?:[.,](\d{1,6}))?$/);
  if (!m) return undefined;
  const frac = m[2] ?? '';
  const inteiro = Number(m[1]) * 100 + Number(frac.padEnd(2, '0').slice(0, 2));
  const resto = frac.slice(2).replace(/0+$/, '');
  return resto ? `${inteiro}.${resto}` : String(inteiro);
}

export type SituacaoPreco = 'vigente' | 'futuro' | 'substituido' | 'anulado';
export function situacaoPreco(p: Pick<Preco, 'anulado_em' | 'vigente_hoje' | 'vigente_desde'>, hoje: string): SituacaoPreco {
  if (p.anulado_em) return 'anulado';
  if (p.vigente_hoje) return 'vigente';
  return p.vigente_desde > hoje ? 'futuro' : 'substituido';
}
export function rotuloSituacaoPreco(p: Pick<Preco, 'anulado_em' | 'vigente_hoje' | 'vigente_desde'>, hoje: string): string {
  const s = situacaoPreco(p, hoje);
  if (s === 'anulado') return 'Anulado';
  if (s === 'vigente') return 'Em vigor';
  return s === 'futuro' ? `Começa em ${dataBR(p.vigente_desde)}` : 'Substituído';
}

// ─── Saúde das integrações (20261005o) ──────────────────────────────────────────────────────────────────────────────

export interface FonteSaude {
  chave: string;
  nome: string;
  ferramenta_id: number | null;
  ferramenta: string | null;
  ativa: boolean;
  ativa_desde: string | null;
  intervalo_minutos: number;
  ultima_execucao_em: string | null;
  ultima_execucao_status: string | null;
  ultima_ok_em: string | null;
  atraso_minutos: number | null;
  atrasada: boolean;
  execucoes_7d: number;
  recusas_7d: number;
  inconsistentes_7d: number;
  negadas_7d: number;
  chave_no_vault: boolean;
  vigia_jobname: string;
  ultima_reconciliacao: { dia: string; contagem_fonte: number; contagem_log: number; faltantes_total: number; em: string } | null;
}
export interface SaudeIntegracoes { ok: true; agora: string; fontes: FonteSaude[] }

export const ROTULO_STATUS_EXECUCAO: Record<string, string> = {
  ok: 'deu certo',
  inconsistente: 'chegou com diferença',
  fonte_inativa: 'recusada: integração desligada',
  lote_invalido: 'recusada: formato errado',
};
export const rotuloStatusExecucao = (s: string | null) => (s ? ROTULO_STATUS_EXECUCAO[s] ?? s : '');

/** Minutos → "45 min", "2 h", "3 dias" (arredonda para baixo). */
export function fmtDuracao(min: number): string {
  if (min < 60) return `${Math.max(0, Math.floor(min))} min`;
  if (min < 48 * 60) return `${Math.floor(min / 60)} h`;
  return `${Math.floor(min / 1440)} dias`;
}

/** Tempo entre `em` e `agora` (relógio do servidor), em linguagem leiga: "há 2 h". Vazio → null. */
export function haQuanto(em: string | null | undefined, agora: string): string | null {
  if (!em) return null;
  const min = (new Date(agora).getTime() - new Date(em).getTime()) / 60000;
  return min < 1 ? 'agora há pouco' : `há ${fmtDuracao(min)}`;
}

export type SituacaoFonte = 'desligada' | 'atrasada' | 'aguardando' | 'em_dia';
export function situacaoFonte(f: Pick<FonteSaude, 'ativa' | 'atrasada' | 'ultima_ok_em'>): SituacaoFonte {
  if (!f.ativa) return 'desligada';
  if (f.atrasada) return 'atrasada';
  return f.ultima_ok_em ? 'em_dia' : 'aguardando';
}
export const ROTULO_SITUACAO_FONTE: Record<SituacaoFonte, string> = {
  desligada: 'Desligada', atrasada: 'Atrasada', aguardando: 'Ligada, sem atualização ainda', em_dia: 'Em dia',
};
