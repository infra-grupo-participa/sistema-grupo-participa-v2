// Aba Histórico do Seminário ATM: regras puras de cálculo e apresentação.
// Nada aqui é gravado no banco. A RPC `dados_historico_edicoes` devolve só os números medidos;
// razões (CPL, CAC, ROAS, taxas, conversões, retenção e comparativo) são calculadas na tela.
// Regra da casa: razão = soma sobre soma; divisão por zero ou valor ausente = null ("—"), nunca 0.

/** Chaves do campo `fontes` (jsonb) e do array `provisorio` devolvidos pela RPC. */
export type CampoFonteHistorico =
  | 'leads' | 'invest_trafego' | 'invest_disparo' | 'grupo'
  | 'pico_d1' | 'pico_d2' | 'pico_d3'
  | 'vendas' | 'receita_liquida' | 'pre_checkout';

export const ROTULO_CAMPO_FONTE: Record<CampoFonteHistorico, string> = {
  leads: 'Leads',
  invest_trafego: 'Investimento em tráfego',
  invest_disparo: 'Investimento em disparo',
  grupo: 'Ingressos no grupo',
  pico_d1: 'Pico ao vivo dia 1',
  pico_d2: 'Pico ao vivo dia 2',
  pico_d3: 'Pico ao vivo dia 3',
  vendas: 'Vendas',
  receita_liquida: 'Receita líquida',
  pre_checkout: 'Pré-checkout',
};

/** Uma edição do histórico, já com dinheiro em reais (a conversão de centavos é feita na camada de dados). */
export type EdicaoHistorico = {
  chave: string;
  familia: string;
  rotulo: string;
  ordem: number | null;
  dataInicio: string | null;
  dataFim: string | null;
  leads: number | null;
  investTrafego: number | null;
  investDisparo: number | null;
  grupo: number | null;
  picoD1: number | null;
  picoD2: number | null;
  picoD3: number | null;
  vendas: number | null;
  receitaLiquida: number | null;
  preCheckout: number | null;
  fontes: Partial<Record<CampoFonteHistorico, string>>;
  provisorio: string[];
};

export type IndicadoresEdicao = {
  investTotal: number | null;
  cpl: number | null;
  cac: number | null;
  roas: number | null;
  taxaGrupo: number | null;
  conversaoPreCheckout: number | null;
  conversaoGrupo: number | null;
  conversaoLeads: number | null;
  retencaoD2: number | null;
  retencaoD3: number | null;
  comparativoD1: number | null;
  comparativoD2: number | null;
  comparativoD3: number | null;
};

const finito = (v: number | null | undefined): v is number => typeof v === 'number' && Number.isFinite(v);

/** Numerador ÷ denominador. Ausente, não numérico ou denominador zero = null. */
export function razao(numerador: number | null | undefined, denominador: number | null | undefined): number | null {
  if (!finito(numerador) || !finito(denominador) || denominador === 0) return null;
  return numerador / denominador;
}

/** Variação relativa atual ÷ anterior − 1. Sem base anterior ou com base zero = null. */
export function variacaoPercentualHistorico(atual: number | null, anterior: number | null): number | null {
  if (!finito(atual) || !finito(anterior) || anterior === 0) return null;
  return (atual - anterior) / Math.abs(anterior);
}

/** Tráfego + disparo. Se uma das partes não veio da fonte, o total é desconhecido (null): nunca supor zero. */
export function investimentoTotal(e: Pick<EdicaoHistorico, 'investTrafego' | 'investDisparo'>): number | null {
  if (!finito(e.investTrafego) || !finito(e.investDisparo)) return null;
  return e.investTrafego + e.investDisparo;
}

/** Ordena pela `ordem` da RPC (nulos no fim), desempate pela data de início e pela chave. */
export function ordenarEdicoes(lista: EdicaoHistorico[]): EdicaoHistorico[] {
  return [...lista].sort((a, b) => {
    const oa = finito(a.ordem) ? a.ordem : Number.POSITIVE_INFINITY;
    const ob = finito(b.ordem) ? b.ordem : Number.POSITIVE_INFINITY;
    if (oa !== ob) return oa - ob;
    const da = a.dataInicio ?? '';
    const db = b.dataInicio ?? '';
    if (da !== db) return da < db ? -1 : 1;
    return a.chave < b.chave ? -1 : a.chave > b.chave ? 1 : 0;
  });
}

/** Indicadores da edição. `anterior` = edição imediatamente antes na ordem (para o comparativo da mesma aula). */
export function indicadoresEdicao(e: EdicaoHistorico, anterior: EdicaoHistorico | null = null): IndicadoresEdicao {
  const investTotal = investimentoTotal(e);
  return {
    investTotal,
    cpl: razao(investTotal, e.leads),
    cac: razao(investTotal, e.vendas),
    roas: razao(e.receitaLiquida, investTotal),
    taxaGrupo: razao(e.grupo, e.leads),
    conversaoPreCheckout: razao(e.vendas, e.preCheckout),
    conversaoGrupo: razao(e.vendas, e.grupo),
    conversaoLeads: razao(e.vendas, e.leads),
    retencaoD2: razao(e.picoD2, e.picoD1),
    retencaoD3: razao(e.picoD3, e.picoD2),
    comparativoD1: razao(e.picoD1, anterior?.picoD1),
    comparativoD2: razao(e.picoD2, anterior?.picoD2),
    comparativoD3: razao(e.picoD3, anterior?.picoD3),
  };
}

// ---------- Formatação pt-BR ----------

export type FormatoHistorico = 'inteiro' | 'moeda' | 'percentual' | 'multiplicador';

const fmtInteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const fmtMoeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
const fmtPercentual = new Intl.NumberFormat('pt-BR', { style: 'percent', minimumFractionDigits: 1, maximumFractionDigits: 1 });
const fmtMultiplicador = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const SEM_VALOR = '—';

/** Valor ausente = "—". Percentual recebe fração (0,269 = 26,9%). */
export function formatarHistorico(v: number | null | undefined, formato: FormatoHistorico): string {
  if (!finito(v)) return SEM_VALOR;
  if (formato === 'moeda') return fmtMoeda.format(v);
  if (formato === 'percentual') return fmtPercentual.format(v);
  if (formato === 'multiplicador') return fmtMultiplicador.format(v) + 'x';
  return fmtInteiro.format(v);
}

/** "2026-07-14" → "14/07/2026". Texto fora do padrão volta como veio. */
export function dataCurtaHistorico(iso: string | null): string | null {
  if (!iso) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : iso;
}

export function periodoEdicao(e: Pick<EdicaoHistorico, 'dataInicio' | 'dataFim'>): string | null {
  const ini = dataCurtaHistorico(e.dataInicio);
  const fim = dataCurtaHistorico(e.dataFim);
  if (ini && fim) return ini === fim ? ini : `${ini} a ${fim}`;
  return ini ?? fim;
}

// ---------- Métricas do comparativo geral (linhas da tabela) ----------

export type SecaoMetricaHistorico = 'Captação' | 'Aulas' | 'Vendas' | 'Eficiência';

export type MetricaHistorico = {
  id: string;
  rotulo: string;
  secao: SecaoMetricaHistorico;
  formato: FormatoHistorico;
  /** Campos da fonte que entram no número (para o tooltip e o aviso de provisório). */
  campos: CampoFonteHistorico[];
  /** Fórmula em texto, só para métricas calculadas na tela. */
  formula?: string;
  /** Usa a mesma aula da edição anterior. */
  usaAnterior?: boolean;
  destaque?: boolean;
  /** Texto curto mostrado junto do "—" quando o valor é nulo (ex.: sem dia 3). */
  vazio?: string;
  valor: (e: EdicaoHistorico, i: IndicadoresEdicao) => number | null;
};

export const METRICAS_HISTORICO: MetricaHistorico[] = [
  { id: 'leads', rotulo: 'Leads', secao: 'Captação', formato: 'inteiro', campos: ['leads'], valor: (e) => e.leads },
  { id: 'invest_trafego', rotulo: 'Investimento em tráfego', secao: 'Captação', formato: 'moeda', campos: ['invest_trafego'], valor: (e) => e.investTrafego },
  { id: 'invest_disparo', rotulo: 'Investimento em disparo', secao: 'Captação', formato: 'moeda', campos: ['invest_disparo'], valor: (e) => e.investDisparo },
  { id: 'invest_total', rotulo: 'Investimento total', secao: 'Captação', formato: 'moeda', campos: ['invest_trafego', 'invest_disparo'], formula: 'Investimento em tráfego + Investimento em disparo', valor: (_e, i) => i.investTotal },
  { id: 'grupo', rotulo: 'Ingressos no grupo', secao: 'Captação', formato: 'inteiro', campos: ['grupo'], valor: (e) => e.grupo },
  { id: 'taxa_grupo', rotulo: 'Taxa de ingresso no grupo', secao: 'Captação', formato: 'percentual', campos: ['grupo', 'leads'], formula: 'Ingressos no grupo ÷ Leads', valor: (_e, i) => i.taxaGrupo },
  { id: 'pico_d1', rotulo: 'Pico ao vivo dia 1', secao: 'Aulas', formato: 'inteiro', campos: ['pico_d1'], valor: (e) => e.picoD1 },
  { id: 'pico_d2', rotulo: 'Pico ao vivo dia 2', secao: 'Aulas', formato: 'inteiro', campos: ['pico_d2'], valor: (e) => e.picoD2 },
  { id: 'pico_d3', rotulo: 'Pico ao vivo dia 3', secao: 'Aulas', formato: 'inteiro', campos: ['pico_d3'], vazio: 'sem dia 3', valor: (e) => e.picoD3 },
  { id: 'retencao_d2', rotulo: 'Retenção dia 2 ÷ dia 1', secao: 'Aulas', formato: 'percentual', campos: ['pico_d2', 'pico_d1'], formula: 'Pico do dia 2 ÷ Pico do dia 1 da mesma edição', valor: (_e, i) => i.retencaoD2 },
  { id: 'retencao_d3', rotulo: 'Retenção dia 3 ÷ dia 2', secao: 'Aulas', formato: 'percentual', campos: ['pico_d3', 'pico_d2'], formula: 'Pico do dia 3 ÷ Pico do dia 2 da mesma edição', vazio: 'sem dia 3', valor: (_e, i) => i.retencaoD3 },
  { id: 'comparativo_d1', rotulo: 'Dia 1 contra a edição anterior', secao: 'Aulas', formato: 'percentual', campos: ['pico_d1'], usaAnterior: true, formula: 'Pico do dia 1 ÷ Pico do dia 1 da edição anterior', valor: (_e, i) => i.comparativoD1 },
  { id: 'comparativo_d2', rotulo: 'Dia 2 contra a edição anterior', secao: 'Aulas', formato: 'percentual', campos: ['pico_d2'], usaAnterior: true, formula: 'Pico do dia 2 ÷ Pico do dia 2 da edição anterior', valor: (_e, i) => i.comparativoD2 },
  { id: 'comparativo_d3', rotulo: 'Dia 3 contra a edição anterior', secao: 'Aulas', formato: 'percentual', campos: ['pico_d3'], usaAnterior: true, formula: 'Pico do dia 3 ÷ Pico do dia 3 da edição anterior', valor: (_e, i) => i.comparativoD3 },
  { id: 'vendas', rotulo: 'Vendas', secao: 'Vendas', formato: 'inteiro', campos: ['vendas'], valor: (e) => e.vendas },
  { id: 'receita_liquida', rotulo: 'Receita líquida', secao: 'Vendas', formato: 'moeda', campos: ['receita_liquida'], valor: (e) => e.receitaLiquida },
  { id: 'pre_checkout', rotulo: 'Pré-checkout', secao: 'Vendas', formato: 'inteiro', campos: ['pre_checkout'], valor: (e) => e.preCheckout },
  { id: 'conversao_pre_checkout', rotulo: 'Conversão sobre o pré-checkout', secao: 'Vendas', formato: 'percentual', campos: ['vendas', 'pre_checkout'], formula: 'Vendas ÷ Pré-checkout', destaque: true, valor: (_e, i) => i.conversaoPreCheckout },
  { id: 'conversao_grupo', rotulo: 'Conversão sobre o grupo', secao: 'Vendas', formato: 'percentual', campos: ['vendas', 'grupo'], formula: 'Vendas ÷ Ingressos no grupo', valor: (_e, i) => i.conversaoGrupo },
  { id: 'conversao_leads', rotulo: 'Conversão sobre os leads', secao: 'Vendas', formato: 'percentual', campos: ['vendas', 'leads'], formula: 'Vendas ÷ Leads', valor: (_e, i) => i.conversaoLeads },
  { id: 'cac', rotulo: 'CAC', secao: 'Eficiência', formato: 'moeda', campos: ['invest_trafego', 'invest_disparo', 'vendas'], formula: 'Investimento total ÷ Vendas', valor: (_e, i) => i.cac },
  { id: 'roas', rotulo: 'ROAS', secao: 'Eficiência', formato: 'multiplicador', campos: ['receita_liquida', 'invest_trafego', 'invest_disparo'], formula: 'Receita líquida ÷ Investimento total', valor: (_e, i) => i.roas },
  { id: 'cpl', rotulo: 'CPL', secao: 'Eficiência', formato: 'moeda', campos: ['invest_trafego', 'invest_disparo', 'leads'], formula: 'Investimento total ÷ Leads', valor: (_e, i) => i.cpl },
];

export const SECOES_HISTORICO: SecaoMetricaHistorico[] = ['Captação', 'Aulas', 'Vendas', 'Eficiência'];

export function metricaHistorico(id: string): MetricaHistorico {
  const m = METRICAS_HISTORICO.find((x) => x.id === id);
  if (!m) throw new Error(`Métrica de histórico desconhecida: ${id}`);
  return m;
}

/** Algum dos campos usados no número está marcado como provisório na edição (ou na anterior, no comparativo). */
export function ehProvisorio(m: Pick<MetricaHistorico, 'campos' | 'usaAnterior'>, e: EdicaoHistorico, anterior: EdicaoHistorico | null): boolean {
  const marcado = (ed: EdicaoHistorico | null) => !!ed && m.campos.some((c) => ed.provisorio.includes(c));
  return marcado(e) || (m.usaAnterior === true && marcado(anterior));
}

/** Texto do tooltip: fonte de cada campo (string exata do banco), fórmula quando calculado e aviso de provisório. */
export function descreverFonte(m: Pick<MetricaHistorico, 'campos' | 'formula' | 'usaAnterior'>, e: EdicaoHistorico, anterior: EdicaoHistorico | null): string {
  const fonte = (ed: EdicaoHistorico, c: CampoFonteHistorico) => ed.fontes[c] ?? 'fonte não informada pelo banco';
  const partes: string[] = [];
  if (m.formula) partes.push(`Calculado na tela: ${m.formula}.`);
  if (m.usaAnterior) {
    const c = m.campos[0];
    partes.push(`${e.rotulo}: ${fonte(e, c)}.`);
    partes.push(anterior ? `${anterior.rotulo}: ${fonte(anterior, c)}.` : 'Sem edição anterior para comparar.');
  } else if (m.formula) {
    partes.push('Fontes: ' + m.campos.map((c) => `${ROTULO_CAMPO_FONTE[c]}: ${fonte(e, c)}`).join('; ') + '.');
  } else {
    partes.push(`Fonte: ${fonte(e, m.campos[0])}.`);
  }
  if (ehProvisorio(m, e, anterior)) partes.push('Número provisório: pode mudar quando a fonte fechar.');
  return partes.join(' ');
}

// ---------- Funil visual da edição ----------

export type EtapaFunil = {
  id: CampoFonteHistorico;
  rotulo: string;
  valor: number | null;
  /** Etapa ÷ etapa anterior (null na primeira). */
  passagem: number | null;
  /** Etapa ÷ leads. */
  doTotal: number | null;
};

/** Leads → grupo → pico na live (dia 1) → pré-checkout → vendas. Nada de investimento. */
export function etapasFunil(e: EdicaoHistorico): EtapaFunil[] {
  const base: { id: CampoFonteHistorico; rotulo: string; valor: number | null }[] = [
    { id: 'leads', rotulo: 'Leads', valor: e.leads },
    { id: 'grupo', rotulo: 'Entraram no grupo', valor: e.grupo },
    { id: 'pico_d1', rotulo: 'Pico na live (dia 1)', valor: e.picoD1 },
    { id: 'pre_checkout', rotulo: 'Pré-checkout', valor: e.preCheckout },
    { id: 'vendas', rotulo: 'Vendas', valor: e.vendas },
  ];
  return base.map((etapa, i) => ({
    ...etapa,
    passagem: i === 0 ? null : razao(etapa.valor, base[i - 1].valor),
    doTotal: razao(etapa.valor, e.leads),
  }));
}

/** Picos D1 a D3 para o gráfico, com retenção sobre a aula anterior e comparativo com a mesma aula da edição anterior. */
export type PicoAula = { dia: 1 | 2 | 3; campo: CampoFonteHistorico; valor: number | null; retencao: number | null; comparativo: number | null };

export function picosAulas(e: EdicaoHistorico, anterior: EdicaoHistorico | null): PicoAula[] {
  const i = indicadoresEdicao(e, anterior);
  return [
    { dia: 1, campo: 'pico_d1', valor: e.picoD1, retencao: null, comparativo: i.comparativoD1 },
    { dia: 2, campo: 'pico_d2', valor: e.picoD2, retencao: i.retencaoD2, comparativo: i.comparativoD2 },
    { dia: 3, campo: 'pico_d3', valor: e.picoD3, retencao: i.retencaoD3, comparativo: i.comparativoD3 },
  ];
}
