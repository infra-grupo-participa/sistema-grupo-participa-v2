// Recebimentos informados (bloco 5 do Contas a Receber, 28/09/2026). Função PURA, sem I/O.
// Renovações Diamante/Aurum negociadas fora, que o financeiro digitava numa planilha. Agora moram em
// fin.recebimentos_informados; a validação verdadeira é do banco (fn_fin_informado_salvar / fn_fin_informados_importar).
// Aqui só: tipar a lista, e ler o texto colado da planilha (TSV do Google Sheets) para a PRÉVIA.
// z73: o tipo 'contrato_holding_familiar' (CSM Soluções, fora da Hotmart) mora na mesma tabela e vira o BLOCO 7 da
// previsão, com parcela "n de N" e contrato assinado sim/não. A planilha "Contratos Soluções" do financeiro é colada
// aqui também e reconhecida pelo CABEÇALHO (Vencimento · Cliente · Parcela · Valor · Status · Situação do contrato).
//
// PII: o texto colado traz CPF/CNPJ e e-mail de cliente. Nada deste arquivo loga, e nenhum erro repete o identificador.

export type TipoInformado = 'renovacao_diamante' | 'renovacao_aurum' | 'diamante_extra' | 'outro' | 'contrato_holding_familiar';
/** Contrato Holding Familiar (z73): sempre fora da Hotmart; parcela e contrato assinado só valem nele. */
export const TIPO_CONTRATO = 'contrato_holding_familiar' as const;
export const TIPOS_INFORMADO: readonly TipoInformado[] = [
  'renovacao_diamante', 'renovacao_aurum', 'diamante_extra', 'outro', TIPO_CONTRATO,
];
/** Teto do banco para o total de parcelas (CHECK recebimentos_informados_contrato_ck). */
export const PARCELAS_MAX = 60;

export type SituacaoInformado = 'a_receber' | 'realizado_hotmart' | 'baixado_fora' | 'em_atraso_cobrar' | 'arquivado';
/** Ordem dos filtros da lista: o que pede ação primeiro. */
export const SITUACOES_INFORMADO: readonly SituacaoInformado[] = [
  'em_atraso_cobrar', 'a_receber', 'realizado_hotmart', 'baixado_fora', 'arquivado',
];

/** Uma linha de fn_fin_informados_listar(). Identificadores chegam MASCARADOS sem gp_pode_ver_cpf(). */
export interface Informado {
  id: string;
  data_prevista: string | null;
  cliente: string;
  tipo: string;
  valor: number;
  via_hotmart: boolean;
  produtos: string[];
  identificador1: string | null;
  identificador2: string | null;
  acordo_desde: string | null;
  baixa_manual_em: string | null;
  situacao: string;
  recebido_hotmart: number | null;
  acumulado_acordo: number | null;
  valor_provisionado: number | null;
  arquivado_em: string | null;
  motivo_arquivo: string | null;
  atualizado_em: string | null;
  /** z73, só no contrato Holding Familiar (nulos nos outros tipos e no banco sem a z73). */
  parcela_n: number | null;
  parcela_de: number | null;
  contrato_assinado: boolean | null;
}

/**
 * O que vai para fn_fin_informado_salvar(p) e para cada item de fn_fin_informados_importar(p_linhas).
 * Chaves = nomes das colunas (contrato). Identificadores em claro. Chave AUSENTE = não mexer (edição de quem só vê
 * o identificador mascarado: mandar a máscara de volta gravaria lixo).
 */
export interface InformadoEntrada {
  id?: string | null;
  data_prevista: string | null;
  cliente: string;
  tipo: TipoInformado | null;
  valor: number | null;
  via_hotmart: boolean | null;
  produtos: string[];
  identificador1?: string | null;
  identificador2?: string | null;
  acordo_desde: string | null;
  /** Ausente = não mexer (a edição não toca na baixa: ela tem RPC própria). */
  baixa_manual_em?: string | null;
  /** z73, SÓ no tipo contrato_holding_familiar. Nos outros tipos as chaves ficam AUSENTES: o banco limpa o que a linha
   *  herdou na troca de tipo, e recusa (P0001) se vierem preenchidas. */
  parcela_n?: number | null;
  parcela_de?: number | null;
  contrato_assinado?: boolean | null;
}

// ─── Conversão da lista (numeric do PostgREST pode chegar como texto) ──────
const numOuNull = (v: unknown): number | null => (v == null || v === '' ? null : Number.isFinite(Number(v)) ? Number(v) : null);
const dia = (v: unknown): string | null => (v == null || v === '' ? null : String(v).slice(0, 10));
const txt = (v: unknown): string | null => (v == null ? null : String(v));
const intOuNull = (v: unknown): number | null => {
  const n = numOuNull(v);
  return n != null && Number.isInteger(n) ? n : null;
};
const boolOuNull = (v: unknown): boolean | null =>
  (v === true || v === 'true' || v === 't' ? true : v === false || v === 'false' || v === 'f' ? false : null);

function lerLista(v: unknown): string[] {
  if (Array.isArray(v)) return v.filter((x) => x != null).map(String);
  if (typeof v === 'string' && v.startsWith('{') && v.endsWith('}')) {
    return v.slice(1, -1).split(',').map((x) => x.replace(/^"|"$/g, '').trim()).filter(Boolean);
  }
  return [];
}

export function normalizarInformado(r: Record<string, unknown>): Informado {
  return {
    id: String(r.id ?? ''),
    data_prevista: dia(r.data_prevista),
    cliente: String(r.cliente ?? ''),
    tipo: String(r.tipo ?? ''),
    valor: numOuNull(r.valor) ?? 0,
    via_hotmart: r.via_hotmart === true || r.via_hotmart === 'true' || r.via_hotmart === 't',
    produtos: lerLista(r.produtos),
    identificador1: txt(r.identificador1),
    identificador2: txt(r.identificador2),
    acordo_desde: dia(r.acordo_desde),
    baixa_manual_em: dia(r.baixa_manual_em),
    situacao: String(r.situacao ?? ''),
    recebido_hotmart: numOuNull(r.recebido_hotmart),
    acumulado_acordo: numOuNull(r.acumulado_acordo),
    valor_provisionado: numOuNull(r.valor_provisionado),
    arquivado_em: txt(r.arquivado_em),
    motivo_arquivo: txt(r.motivo_arquivo),
    atualizado_em: txt(r.atualizado_em),
    parcela_n: intOuNull(r.parcela_n),
    parcela_de: intOuNull(r.parcela_de),
    contrato_assinado: boolOuNull(r.contrato_assinado),
  };
}

/** Lista na ordem da planilha: data prevista, depois cliente. Sem data vai para o fim. */
export function ordenarInformados(xs: Informado[]): Informado[] {
  return [...xs].sort((a, b) => (a.data_prevista ?? '9999').localeCompare(b.data_prevista ?? '9999')
    || a.cliente.localeCompare(b.cliente, 'pt-BR'));
}

/** Identificador que veio mascarado do banco (CPF ···1234; e-mail a***@dominio). Não pode voltar numa escrita. */
export function identificadorMascarado(v: string | null | undefined): boolean {
  return !!v && /[·*•]/.test(v);
}

/**
 * Máscara local para a PRÉVIA do texto colado (a tela não reexibe CPF/e-mail em claro): e-mail → a***@dominio;
 * resto → ···últimos 4 caracteres alfanuméricos.
 */
export function mascararLocal(v: string | null | undefined): string {
  if (!v) return '—';
  const s = v.trim();
  const at = s.indexOf('@');
  if (at > 0) return `${s[0]}***${s.slice(at)}`;
  const so = s.replace(/[^0-9a-z]/gi, '');
  return `···${so.slice(-4)}`;
}

// ─── Leitura de campos da planilha ─────────────────────────────────────────
const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

/** dd/mm/aaaa (ou d/m/aaaa, ou aaaa-mm-dd) → YYYY-MM-DD. Vazio → null. Inválido → undefined. */
export function lerDataBR(v: string): string | null | undefined {
  const s = v.trim();
  if (!s) return null;
  let y: number; let m: number; let d: number;
  const br = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  const isoM = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (br) { d = Number(br[1]); m = Number(br[2]); y = Number(br[3]); } else if (isoM) { y = Number(isoM[1]); m = Number(isoM[2]); d = Number(isoM[3]); } else return undefined;
  const t = new Date(Date.UTC(y, m - 1, d));
  if (t.getUTCFullYear() !== y || t.getUTCMonth() !== m - 1 || t.getUTCDate() !== d) return undefined;
  return t.toISOString().slice(0, 10);
}

/** "R$ 18.750,00", "18750", "18.750", "18750,5" → número. Vazio → null. Inválido → undefined. */
export function lerValorBR(v: string): number | null | undefined {
  const s = v.replace(/R\$/gi, '').replace(/[\s ]/g, '');
  if (!s) return null;
  let n: string;
  if (/^-?\d{1,3}(\.\d{3})*(,\d+)?$/.test(s) || /^-?\d+(,\d+)?$/.test(s)) n = s.replace(/\./g, '').replace(',', '.');
  else if (/^-?\d+(\.\d{1,2})?$/.test(s)) n = s; // 18750.50 (sem milhar, ponto decimal)
  else return undefined;
  const x = Number(n);
  return Number.isFinite(x) ? Math.round(x * 100) / 100 : undefined;
}

/** Tipo por texto da planilha ("Renovação Diamante", "Renovação Aurum", "Diamante extra", "Outro", "Contrato Holding
 * Familiar") ou pelo código. */
export function lerTipo(v: string): TipoInformado | null | undefined {
  const s = semAcento(v);
  if (!s) return null;
  if ((TIPOS_INFORMADO as readonly string[]).includes(s)) return s as TipoInformado;
  if (s.includes('holding familiar')) return TIPO_CONTRATO;
  const renov = s.includes('renov');
  if (renov && s.includes('diamante')) return 'renovacao_diamante';
  if (renov && s.includes('aurum')) return 'renovacao_aurum';
  if (!renov && s.includes('diamante') && (s.includes('extra') || s.includes('servico'))) return 'diamante_extra';
  if (s === 'outro' || s === 'outros' || s.startsWith('outro ') || s.startsWith('outros ')) return 'outro';
  return undefined;
}

/** S/N, Sim/Não. Vazio → null. Outro texto → undefined. */
export function lerSimNao(v: string): boolean | null | undefined {
  const s = semAcento(v);
  if (!s) return null;
  if (s === 's' || s === 'sim') return true;
  if (s === 'n' || s === 'nao') return false;
  return undefined;
}

/**
 * Parcela "n de N" da planilha Contratos Soluções: "1 de 5", "01 de 05", "1/5", "Parcela 2 de 5". Vazio → null.
 * Formato inválido → undefined. O intervalo (1 ≤ n ≤ N ≤ 60) é conferido à parte (`erroParcela`).
 */
export function lerParcela(v: string): { n: number; de: number } | null | undefined {
  const s = semAcento(v).replace(/^parcela\s*/, '');
  if (!s) return null;
  const m = s.match(/^(\d{1,3})\s*(?:de|\/)\s*(\d{1,3})$/);
  return m ? { n: Number(m[1]), de: Number(m[2]) } : undefined;
}

/** Mesma regra do CHECK do banco: 1 ≤ n ≤ N ≤ 60. null = ok. */
export function erroParcela(n: number, de: number): string | null {
  if (n < 1 || n > de || de > PARCELAS_MAX) return `Parcela fora do intervalo: ${n} de ${de} (1 ≤ parcela ≤ total ≤ ${PARCELAS_MAX}).`;
  return null;
}

/** Status da planilha Contratos Soluções: Pago / Pendente / Entrada, com data opcional ("Pago 12/10/2026"). */
export type StatusContrato = 'pago' | 'pendente' | 'entrada';
/** Vazio → null; texto fora do contrato → undefined. `data`: null = sem data escrita; undefined = data inválida. */
export function lerStatusContrato(v: string): { status: StatusContrato; data: string | null | undefined } | null | undefined {
  const s = semAcento(v);
  if (!s) return null;
  const status: StatusContrato | null = s.startsWith('pago') ? 'pago' : s.startsWith('pendente') ? 'pendente'
    : s.startsWith('entrada') ? 'entrada' : null;
  if (!status) return undefined;
  const d = s.match(/(\d{1,2}\/\d{1,2}\/\d{4}|\d{4}-\d{2}-\d{2})/);
  return { status, data: d ? lerDataBR(d[1]) : null };
}

/** Situação do contrato: "Assinado" → true; "Sem contrato assinado" / "Não assinado" → false. Vazio → null. */
export function lerContratoAssinado(v: string): boolean | null | undefined {
  const s = semAcento(v);
  if (!s) return null;
  if (s.startsWith('sem ') || s.startsWith('nao ') || s === 'nao' || s === 'n') return false;
  if (s === 'assinado' || s === 'contrato assinado' || s === 'sim' || s === 's') return true;
  return undefined;
}

/** Produtos da Hotmart numa célula: separados por ; , | ou quebra de linha. */
export function lerProdutos(v: string): string[] {
  return v.split(/[;,|\n]/).map((x) => x.trim()).filter(Boolean);
}

// ─── TSV do Google Sheets ──────────────────────────────────────────────────
/**
 * Células separadas por TAB, linhas por quebra. Célula com quebra/aspas/TAB vem entre aspas, com "" como aspas
 * literal (é assim que o Sheets copia). Linha 100% vazia é descartada.
 */
export function lerTSV(texto: string): string[][] {
  const out: string[][] = [];
  let linha: string[] = [];
  let cel = '';
  let aspas = false;
  let inicioCel = true;
  const s = texto.replace(/\r\n?/g, '\n');
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (aspas) {
      if (ch === '"') {
        if (s[i + 1] === '"') { cel += '"'; i++; } else aspas = false;
      } else cel += ch;
      continue;
    }
    if (ch === '"' && inicioCel) { aspas = true; inicioCel = false; continue; }
    if (ch === '\t') { linha.push(cel); cel = ''; inicioCel = true; continue; }
    if (ch === '\n') { linha.push(cel); out.push(linha); linha = []; cel = ''; inicioCel = true; continue; }
    cel += ch;
    inicioCel = false;
  }
  if (cel !== '' || linha.length) { linha.push(cel); out.push(linha); }
  return out.filter((l) => l.some((c) => c.trim() !== ''));
}

/** Colunas da planilha, nesta ordem. */
export const COLUNAS_PLANILHA = [
  'Data prevista', 'Cliente', 'Tipo', 'Valor informado', 'Via Hotmart? S/N', 'Produto na Hotmart',
  'Identificador 1', 'Identificador 2', 'Acordo a partir de', 'Baixa manual',
] as const;

/** Teto do banco (fn_fin_informados_importar). */
export const TETO_IMPORTACAO = 500;

export interface LinhaColada {
  /** Linha no texto colado (1 = primeira linha não vazia, cabeçalho incluído). */
  n: number;
  entrada: InformadoEntrada;
  /** Erros de leitura (formato). Vazio = pode ir à prévia do banco. Nunca repetem o identificador. */
  erros: string[];
  /** Avisos que NÃO travam a gravação, mas pedem conferência (ex.: "Entrada" tratada como paga). Ausente = nenhum. */
  avisos?: string[];
}

/** 'informados' = as 10 colunas da planilha de renovações (COLUNAS_PLANILHA); 'contratos' = planilha Contratos Soluções. */
export type FormatoColagem = 'informados' | 'contratos';

export interface Colagem {
  linhas: LinhaColada[];
  cabecalhoIgnorado: boolean;
  /** Erro da colagem inteira (vazia, acima do teto, cabeçalho de contratos sem coluna obrigatória). */
  erroGeral: string | null;
  /** Ausente = 'informados'. */
  formato?: FormatoColagem;
}

/** Colunas da planilha "Contratos Soluções" (z73). A ordem não importa: o cabeçalho diz onde cada uma está. */
export const COLUNAS_CONTRATOS = ['Vencimento', 'Cliente', 'Parcela', 'Valor', 'Status', 'Situação do contrato'] as const;
export const AVISO_ENTRADA = 'Entrada tratada como paga — confirme';

type ColunaContrato = 'vencimento' | 'cliente' | 'parcela' | 'valor' | 'status' | 'situacao';
const COLUNA_CONTRATO: Record<ColunaContrato, (s: string) => boolean> = {
  vencimento: (s) => s.startsWith('vencimento'),
  cliente: (s) => s === 'cliente' || s.startsWith('cliente '),
  parcela: (s) => s.startsWith('parcela'),
  valor: (s) => s.startsWith('valor'),
  status: (s) => s === 'status' || s.startsWith('status '),
  situacao: (s) => s.startsWith('situacao'),
};

/**
 * Cabeçalho da planilha Contratos Soluções: reconhecido por Vencimento + Parcela + Situação (do contrato). Devolve a
 * posição de cada coluna encontrada; null = não é esse cabeçalho.
 */
export function colunasDeContratos(cabecalho: string[]): Partial<Record<ColunaContrato, number>> | null {
  const cels = cabecalho.map(semAcento);
  const pos: Partial<Record<ColunaContrato, number>> = {};
  for (const k of Object.keys(COLUNA_CONTRATO) as ColunaContrato[]) {
    const i = cels.findIndex(COLUNA_CONTRATO[k]);
    if (i !== -1) pos[k] = i;
  }
  return pos.vencimento != null && pos.parcela != null && pos.situacao != null ? pos : null;
}

const ehCabecalho = (l: string[]) => lerDataBR(l[0] ?? '') === undefined && /data/i.test(l[0] ?? '');

/** Mesmo texto do P0001 do banco (z63): sem gp_pode_ver_cpf() não se cria, troca nem apaga identificador. */
export const SEM_PERMISSAO_IDENTIFICADOR = 'Sem permissão para informar CPF/e-mail.';

/**
 * `podeVerDoc` = gp_pode_ver_cpf() do usuário. Sem ele, linha com Identificador 1/2 preenchido é erro local (não vai
 * ao banco) e nenhuma entrada leva as chaves identificador1/2.
 */
export function lerColagem(texto: string, { podeVerDoc, hojeISO }: { podeVerDoc: boolean; hojeISO?: string }): Colagem {
  const tabela = lerTSV(texto);
  const contratos = tabela.length > 0 ? colunasDeContratos(tabela[0]) : null;
  if (contratos) return lerColagemContratos(tabela, contratos, hojeISO);
  const cabecalhoIgnorado = tabela.length > 0 && ehCabecalho(tabela[0]);
  const corpo = cabecalhoIgnorado ? tabela.slice(1) : tabela;
  if (corpo.length === 0) return { linhas: [], cabecalhoIgnorado, erroGeral: 'Nada para importar: cole as linhas da planilha.' };
  if (corpo.length > TETO_IMPORTACAO) {
    return { linhas: [], cabecalhoIgnorado, erroGeral: `São ${corpo.length} linhas; o limite é ${TETO_IMPORTACAO} por importação.` };
  }
  const linhas = corpo.map((cels, i): LinhaColada => {
    const n = i + 1 + (cabecalhoIgnorado ? 1 : 0);
    const erros: string[] = [];
    const c = (k: number) => (cels[k] ?? '').trim();
    if (cels.length > COLUNAS_PLANILHA.length) erros.push(`${cels.length} colunas; a planilha tem ${COLUNAS_PLANILHA.length}.`);

    const data = lerDataBR(c(0));
    if (data === undefined) erros.push('Data prevista inválida (use dd/mm/aaaa).');
    else if (data === null) erros.push('Data prevista vazia.');
    const cliente = c(1);
    if (!cliente) erros.push('Cliente vazio.');
    const tipo = lerTipo(c(2));
    if (tipo === undefined) erros.push('Tipo não reconhecido (Renovação Diamante, Renovação Aurum, Diamante extra ou Outro).');
    else if (tipo === null) erros.push('Tipo vazio.');
    // Esta planilha não tem parcela nem contrato assinado (obrigatório no banco): contrato vem pela Contratos Soluções.
    else if (tipo === TIPO_CONTRATO) erros.push(ERRO_CONTRATO_NA_PLANILHA_INFORMADOS);
    const valor = lerValorBR(c(3));
    if (valor === undefined) erros.push('Valor informado inválido.');
    else if (valor === null) erros.push('Valor informado vazio.');
    else if (valor <= 0) erros.push('Valor informado precisa ser maior que zero.');
    const via = lerSimNao(c(4));
    if (via === undefined) erros.push('Via Hotmart? deve ser S ou N.');
    else if (via === null) erros.push('Via Hotmart? vazio (S ou N).');
    const produtos = lerProdutos(c(5));
    if (via === true && produtos.length === 0) erros.push('Via Hotmart = S exige o produto na Hotmart.');
    const acordo = lerDataBR(c(8));
    if (acordo === undefined) erros.push('Acordo a partir de: data inválida (use dd/mm/aaaa).');
    const baixa = lerDataBR(c(9));
    if (baixa === undefined) erros.push('Baixa manual: data inválida (use dd/mm/aaaa).');
    if (!podeVerDoc && (c(6) || c(7))) erros.push(SEM_PERMISSAO_IDENTIFICADOR);

    const entrada: InformadoEntrada = {
      data_prevista: data ?? null,
      cliente,
      tipo: tipo ?? null,
      valor: valor ?? null,
      via_hotmart: via ?? null,
      produtos,
      acordo_desde: acordo ?? null,
      baixa_manual_em: baixa ?? null,
    };
    if (podeVerDoc) { entrada.identificador1 = c(6) || null; entrada.identificador2 = c(7) || null; }
    return { n, erros, entrada };
  });
  return { linhas, cabecalhoIgnorado, erroGeral: null };
}

export const ERRO_CONTRATO_NA_PLANILHA_INFORMADOS =
  'Contrato Holding Familiar: cole pela planilha Contratos Soluções, com o cabeçalho (ela traz parcela e situação do contrato).';

/**
 * Planilha "Contratos Soluções" (z73), já reconhecida pelo cabeçalho (linha 1, sempre ignorada). Tudo vira
 * contrato_holding_familiar, fora da Hotmart, sem produto e sem identificador.
 *   Parcela "n de N" → parcela_n / parcela_de (vazia = não parcelado).
 *   Status: Pago → baixa_manual_em = vencimento (ou a data escrita no Status); Pendente → sem baixa;
 *           Entrada → como Pago, com aviso na prévia (AVISO_ENTRADA).
 *   Situação do contrato: Assinado → true; Sem contrato assinado → false (obrigatória).
 * Baixa depois de hoje o banco recusa: aqui vira erro local com o caminho (escrever a data no Status). `hojeISO` ausente
 * = essa conferência fica só no banco.
 */
function lerColagemContratos(tabela: string[][], pos: Partial<Record<ColunaContrato, number>>, hojeISO?: string): Colagem {
  const base = { cabecalhoIgnorado: true, formato: 'contratos' as const };
  const faltam = (Object.keys(COLUNA_CONTRATO) as ColunaContrato[]).filter((k) => pos[k] == null);
  if (faltam.length) {
    const nomes: Record<ColunaContrato, string> = {
      vencimento: 'Vencimento', cliente: 'Cliente', parcela: 'Parcela', valor: 'Valor', status: 'Status', situacao: 'Situação do contrato',
    };
    return { ...base, linhas: [], erroGeral: `Planilha Contratos Soluções sem a coluna: ${faltam.map((k) => nomes[k]).join(', ')}.` };
  }
  const corpo = tabela.slice(1);
  if (corpo.length === 0) return { ...base, linhas: [], erroGeral: 'Nada para importar: cole as linhas da planilha.' };
  if (corpo.length > TETO_IMPORTACAO) {
    return { ...base, linhas: [], erroGeral: `São ${corpo.length} linhas; o limite é ${TETO_IMPORTACAO} por importação.` };
  }
  const linhas = corpo.map((cels, i): LinhaColada => {
    const n = i + 2;
    const erros: string[] = [];
    const avisos: string[] = [];
    const c = (k: ColunaContrato) => (cels[pos[k]!] ?? '').trim();

    const venc = lerDataBR(c('vencimento'));
    if (venc === undefined) erros.push('Vencimento inválido (use dd/mm/aaaa).');
    else if (venc === null) erros.push('Vencimento vazio.');
    const cliente = c('cliente');
    if (!cliente) erros.push('Cliente vazio.');
    const parc = lerParcela(c('parcela'));
    if (parc === undefined) erros.push('Parcela inválida (use "1 de 5").');
    else if (parc) { const e = erroParcela(parc.n, parc.de); if (e) erros.push(e); }
    const valor = lerValorBR(c('valor'));
    if (valor === undefined) erros.push('Valor inválido.');
    else if (valor === null) erros.push('Valor vazio.');
    else if (valor <= 0) erros.push('Valor precisa ser maior que zero.');
    const st = lerStatusContrato(c('status'));
    if (st === undefined) erros.push('Status não reconhecido (Pago, Pendente ou Entrada).');
    else if (st === null) erros.push('Status vazio (Pago, Pendente ou Entrada).');
    else if (st.data === undefined) erros.push('Status: data inválida (use dd/mm/aaaa).');
    const assinado = lerContratoAssinado(c('situacao'));
    if (assinado === undefined) erros.push('Situação do contrato não reconhecida (Assinado ou Sem contrato assinado).');
    else if (assinado === null) erros.push('Situação do contrato vazia (Assinado ou Sem contrato assinado).');

    let baixa: string | null = null;
    if (st && st.status !== 'pendente') {
      if (st.status === 'entrada') avisos.push(AVISO_ENTRADA);
      baixa = st.data ?? venc ?? null;
      if (baixa && hojeISO && baixa > hojeISO) {
        erros.push(`Status ${st.status === 'pago' ? 'Pago' : 'Entrada'} com baixa depois de hoje (${baixa.split('-').reverse().join('/')}): escreva a data do pagamento no Status (ex.: Pago 12/10/2026).`);
      }
    }

    const entrada: InformadoEntrada = {
      data_prevista: venc ?? null,
      cliente,
      tipo: TIPO_CONTRATO,
      valor: valor ?? null,
      via_hotmart: false,
      produtos: [],
      acordo_desde: null,
      baixa_manual_em: baixa,
      parcela_n: parc ? parc.n : null,
      parcela_de: parc ? parc.de : null,
      contrato_assinado: assinado ?? null,
    };
    return { n, erros, avisos, entrada };
  });
  return { ...base, linhas, erroGeral: null };
}

// ─── Resultado da importação (prévia do banco) ─────────────────────────────
export interface ResultadoLinhaImportacao {
  linha: number;
  ok: boolean;
  erro: string | null;
  id: string | null;
}

export function normalizarResultadoImportacao(r: Record<string, unknown>): ResultadoLinhaImportacao {
  return {
    linha: Number(r.linha ?? 0) || 0,
    ok: r.ok === true || r.ok === 'true' || r.ok === 't',
    erro: r.erro == null || r.erro === '' ? null : String(r.erro),
    id: r.id == null ? null : String(r.id),
  };
}

/**
 * Casa o resultado do banco com as linhas enviadas. `linha` é a posição no array enviado; o contrato não diz se
 * começa em 0 ou 1: menor `linha` = 0 → base 0, senão base 1. Linha enviada sem resultado fica `null` (a tela
 * trata como não conferida e não libera a gravação).
 */
export function casarResultado(enviadas: number, res: ResultadoLinhaImportacao[]): (ResultadoLinhaImportacao | null)[] {
  const out: (ResultadoLinhaImportacao | null)[] = new Array(enviadas).fill(null);
  if (res.length === 0) return out;
  const base = Math.min(...res.map((r) => r.linha)) === 0 ? 0 : 1;
  for (const r of res) {
    const i = r.linha - base;
    if (i >= 0 && i < enviadas) out[i] = r;
  }
  return out;
}

/** Prévia liberada para gravar: nada com erro de leitura, e o banco conferiu TODAS as linhas como ok. */
export function previaGravavel(linhas: LinhaColada[], res: (ResultadoLinhaImportacao | null)[] | null): boolean {
  return !!res && linhas.length > 0 && res.length === linhas.length
    && linhas.every((l) => l.erros.length === 0) && res.every((r) => r?.ok === true);
}

// ─── Formulário criar/editar ───────────────────────────────────────────────
export interface FormInformado {
  data_prevista: string;
  cliente: string;
  tipo: string;
  valor: string;
  via_hotmart: '' | 'S' | 'N';
  produtos: string;
  identificador1: string;
  identificador2: string;
  acordo_desde: string;
  /** z73, só no contrato Holding Familiar. Texto do campo (vazio = sem parcela). */
  parcela_n: string;
  parcela_de: string;
  contrato_assinado: '' | 'S' | 'N';
}

const fmtValorForm = (v: number) => v.toFixed(2).replace('.', ',');

/**
 * Valores iniciais. Identificador mascarado (ou de quem não vê documento) começa VAZIO: a máscara nunca vai para o
 * campo, para não voltar ao banco como se fosse o dado.
 */
export function formDeInformado(i: Informado | null, podeVerDoc: boolean): FormInformado {
  const ident = (v: string | null) => (v && podeVerDoc && !identificadorMascarado(v) ? v : '');
  return {
    data_prevista: i?.data_prevista ?? '',
    cliente: i?.cliente ?? '',
    tipo: i?.tipo ?? '',
    valor: i ? fmtValorForm(i.valor) : '',
    via_hotmart: i ? (i.via_hotmart ? 'S' : 'N') : '',
    produtos: i?.produtos.join('; ') ?? '',
    identificador1: ident(i?.identificador1 ?? null),
    identificador2: ident(i?.identificador2 ?? null),
    acordo_desde: i?.acordo_desde ?? '',
    parcela_n: i?.parcela_n != null ? String(i.parcela_n) : '',
    parcela_de: i?.parcela_de != null ? String(i.parcela_de) : '',
    contrato_assinado: i?.contrato_assinado == null ? '' : i.contrato_assinado ? 'S' : 'N',
  };
}

/** O identificador do original não foi entregue ao campo (mascarado/sem permissão): vazio no form = manter. */
export const identificadorOculto = (v: string | null, podeVerDoc: boolean) => !!v && (!podeVerDoc || identificadorMascarado(v));

/**
 * Formulário → p de fn_fin_informado_salvar. Checagem mínima para não mandar lixo; a regra de verdade é do SQL.
 * Sem podeVerDoc: identificador1/2 NUNCA vão no p (o banco recusa criar/trocar/apagar com P0001; o campo fica
 * desabilitado na tela). Edição: identificador oculto e deixado vazio sai do p (chave ausente = manter);
 * baixa_manual_em nunca vai na edição (RPC própria).
 * Contrato Holding Familiar (z73): via_hotmart vai FALSO e produtos vazio (a tela esconde os dois); parcela_n,
 * parcela_de e contrato_assinado vão sempre. Nos outros tipos essas três chaves ficam AUSENTES (o banco limpa o que a
 * linha trazia de quando era contrato, e recusaria se viessem preenchidas).
 */
export function entradaDoFormulario(
  f: FormInformado, original: Informado | null, podeVerDoc: boolean,
): { entrada: InformadoEntrada | null; erros: string[] } {
  const erros: string[] = [];
  const data = lerDataBR(f.data_prevista);
  if (!data) erros.push('Data prevista obrigatória.');
  const cliente = f.cliente.trim();
  if (!cliente) erros.push('Cliente obrigatório.');
  const tipo = (TIPOS_INFORMADO as readonly string[]).includes(f.tipo) ? (f.tipo as TipoInformado) : null;
  if (!tipo) erros.push('Tipo obrigatório.');
  const valor = lerValorBR(f.valor);
  if (valor == null || valor <= 0) erros.push('Valor precisa ser maior que zero.');
  const contrato = tipo === TIPO_CONTRATO;
  const via = contrato ? false : f.via_hotmart === 'S' ? true : f.via_hotmart === 'N' ? false : null;
  if (via == null) erros.push('Informe se é via Hotmart.');
  const produtos = contrato ? [] : lerProdutos(f.produtos);
  if (via === true && produtos.length === 0) erros.push('Via Hotmart exige o produto na Hotmart.');
  let parcela: { n: number; de: number } | null = null;
  let assinado: boolean | null = null;
  if (contrato) {
    const pn = f.parcela_n.trim();
    const pd = f.parcela_de.trim();
    if (pn || pd) {
      if (!/^[0-9]{1,2}$/.test(pn) || !/^[0-9]{1,2}$/.test(pd)) erros.push('Informe a parcela e o total de parcelas juntos, em números (ex.: 2 de 5).');
      else {
        const e = erroParcela(Number(pn), Number(pd));
        if (e) erros.push(e); else parcela = { n: Number(pn), de: Number(pd) };
      }
    }
    assinado = f.contrato_assinado === 'S' ? true : f.contrato_assinado === 'N' ? false : null;
    if (assinado == null) erros.push('Informe se o contrato está assinado.');
  }
  const acordo = lerDataBR(f.acordo_desde);
  if (acordo === undefined) erros.push('Acordo a partir de: data inválida.');
  if (erros.length || !data || valor == null) return { entrada: null, erros };

  const entrada: InformadoEntrada = {
    ...(original ? { id: original.id } : {}),
    data_prevista: data, cliente, tipo, valor, via_hotmart: via, produtos, acordo_desde: acordo ?? null,
  };
  if (contrato) {
    entrada.parcela_n = parcela?.n ?? null;
    entrada.parcela_de = parcela?.de ?? null;
    entrada.contrato_assinado = assinado;
  }
  if (!original) entrada.baixa_manual_em = null;
  if (!podeVerDoc) return { entrada, erros };
  for (const k of ['identificador1', 'identificador2'] as const) {
    const v = f[k].trim();
    if (v) entrada[k] = v;
    else if (!(original && identificadorOculto(original[k], podeVerDoc))) entrada[k] = null;
  }
  return { entrada, erros };
}
