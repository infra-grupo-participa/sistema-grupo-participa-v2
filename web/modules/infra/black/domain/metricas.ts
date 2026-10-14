// Métricas do dashboard da Black. Regra única: razão = soma sobre soma, numerador e denominador no MESMO
// recorte e só nas linhas em que os dois são conhecidos. Sem dado (null) nunca vira zero.
import { FASES, ISCAS, PROFISSOES_MQL } from './tipos';
import type { Anuncio, Campanha, Conjunto, DesempenhoDia, Fase, FiltroCanal, FiltroFunil, Funil, LinhaPerfil, ReguaCpl, TrafegoBlack, Valor } from './tipos';

/** Divisão segura: null ou zero no denominador = null (sem dado), null no numerador = null. */
export function dividir(num: Valor, den: Valor): Valor {
  if (num === null || den === null || den === 0) return null;
  return num / den;
}

export interface Soma { valor: Valor; conhecidos: number; total: number }
/** Soma dos valores conhecidos. Todos null = null (sem dado). `conhecidos < total` = soma parcial (a tela avisa). */
export function somar(valores: readonly Valor[]): Soma {
  let s = 0; let k = 0;
  for (const v of valores) if (v !== null) { s += v; k += 1; }
  return { valor: k === 0 ? null : s, conhecidos: k, total: valores.length };
}

/** Uma taxa com o que entrou na conta (a dica da tela mostra numerador e denominador). */
export interface Taxa { valor: Valor; num: Valor; den: Valor; nota: string | null }
export const taxa = (num: Valor, den: Valor, nota: string | null = null): Taxa => ({ valor: dividir(num, den), num, den, nota });

/** Funis da captação: só eles têm view de página, connect rate e conversão da página. O C1 é distribuição. */
export const FUNIS_CAPTACAO: readonly Funil[] = ['consultoria', 'iscas', 'c3'];
export const ehCaptacao = (f: Funil | null | undefined) => f === 'consultoria' || f === 'iscas' || f === 'c3';

// ─── Índice do tráfego ─────────────────────────────────────────────────────────────────────────────────────
export interface IndiceTrafego {
  campanha: Map<string, Campanha>;
  conjunto: Map<string, Conjunto>;
  anuncio: Map<string, Anuncio>;
  /** anúncio → campanha (pelo conjunto). */
  campanhaDoAnuncio: (anuncioId: string) => Campanha | null;
  conjuntoDoAnuncio: (anuncioId: string) => Conjunto | null;
}
export function indexar(t: Pick<TrafegoBlack, 'campanhas' | 'conjuntos' | 'anuncios'>): IndiceTrafego {
  const campanha = new Map(t.campanhas.map((c) => [c.id, c]));
  const conjunto = new Map(t.conjuntos.map((c) => [c.id, c]));
  const anuncio = new Map(t.anuncios.map((a) => [a.id, a]));
  const conjuntoDoAnuncio = (id: string) => { const a = anuncio.get(id); return a ? conjunto.get(a.conjuntoId) ?? null : null; };
  const campanhaDoAnuncio = (id: string) => { const c = conjuntoDoAnuncio(id); return c ? campanha.get(c.campanhaId) ?? null : null; };
  return { campanha, conjunto, anuncio, campanhaDoAnuncio, conjuntoDoAnuncio };
}

// ─── Agregado de desempenho ────────────────────────────────────────────────────────────────────────────────
export interface Agregado {
  gasto: number; impressoes: number;
  cliques: Soma; lpv: Soma; p50: Soma; p75: Soma; thruplay: Soma;
  /** Σ LPV e Σ cliques só nas linhas em que os DOIS são conhecidos (base do connect rate). */
  parLpv: { lpv: number; cliques: number; linhas: number };
  /** Impressões só das linhas com cliques conhecidos (base do CTR) e com vídeo 75% conhecido. */
  impressoesComCliques: number; impressoesComVideo: number;
  /** Gasto só das linhas com cliques conhecidos (base do CPC). */
  gastoComCliques: number;
  linhas: number;
}
export function agregar(dias: readonly DesempenhoDia[]): Agregado {
  let gasto = 0; let impressoes = 0; let pl = 0; let pc = 0; let pn = 0; let ic = 0; let iv = 0; let gc = 0;
  for (const d of dias) {
    gasto += d.gasto; impressoes += d.impressoes;
    if (d.cliquesLink !== null) { ic += d.impressoes; gc += d.gasto; }
    if (d.videoP75 !== null) iv += d.impressoes;
    if (d.landingPageViews !== null && d.cliquesLink !== null) { pl += d.landingPageViews; pc += d.cliquesLink; pn += 1; }
  }
  return {
    gasto, impressoes,
    cliques: somar(dias.map((d) => d.cliquesLink)),
    lpv: somar(dias.map((d) => d.landingPageViews)),
    p50: somar(dias.map((d) => d.videoP50)),
    p75: somar(dias.map((d) => d.videoP75)),
    thruplay: somar(dias.map((d) => d.thruplay)),
    parLpv: { lpv: pl, cliques: pc, linhas: pn },
    impressoesComCliques: ic, impressoesComVideo: iv, gastoComCliques: gc,
    linhas: dias.length,
  };
}

export const cpm = (a: Agregado): Valor => dividir(a.gasto * 1000, a.impressoes);
/** CPC = gasto ÷ cliques no link, só nas linhas com cliques conhecidos (mesma base do CTR). */
export const cpc = (a: Agregado): Valor => (a.cliques.valor === null ? null : dividir(a.gastoComCliques, a.cliques.valor));
export const ctr = (a: Agregado): Taxa => taxa(a.cliques.valor, a.cliques.valor === null ? null : a.impressoesComCliques);
/** Custo por visualização = gasto ÷ ThruPlay (métrica de vídeo do Meta). */
export const custoPorVisualizacao = (a: Agregado): Valor => dividir(a.gasto, a.thruplay.valor);
export const taxaVideo75 = (a: Agregado): Taxa => taxa(a.p75.valor, a.p75.valor === null ? null : a.impressoesComVideo);

/**
 * Connect rate = Σ LPV ÷ Σ cliques no link, SÓ consultoria, iscas e C3, só nas linhas com as duas métricas.
 * O C1 nunca entra (distribuição, sem view de página). Linha sem LPV (ex.: Google) fica fora e vira nota.
 */
export function connectRate(dias: readonly DesempenhoDia[], idx: IndiceTrafego): Taxa {
  const cap = dias.filter((d) => ehCaptacao(idx.campanhaDoAnuncio(d.anuncioId)?.funil));
  if (cap.length === 0) return taxa(null, null, 'Só existe em C2 e C3 (o C1 é distribuição).');
  const a = agregar(cap);
  const fora = cap.length - a.parLpv.linhas;
  const nota = fora > 0 ? `${fora} linha(s) sem view de página ficaram fora da conta (Google sem LPV).` : null;
  return a.parLpv.linhas === 0 ? taxa(null, null, nota) : taxa(a.parLpv.lpv, a.parLpv.cliques, nota);
}

/** Leads pagos: só tráfego pago entra no CPL (orgânico, base por API e legado ficam fora). */
export const ehPago = (l: LinhaPerfil) => l.origem === 'pago';

/**
 * Conversão da página = inscrições pagas ÷ Σ LPV, mesma regra do connect rate: só anúncios de C2/C3 que têm LPV
 * conhecida no recorte; as inscrições contadas são as desses mesmos anúncios.
 */
export function conversaoPagina(dias: readonly DesempenhoDia[], leads: readonly LinhaPerfil[], idx: IndiceTrafego): Taxa {
  const comLpv = new Set<string>();
  let lpv = 0;
  for (const d of dias) {
    if (!ehCaptacao(idx.campanhaDoAnuncio(d.anuncioId)?.funil) || d.landingPageViews === null) continue;
    comLpv.add(d.anuncioId); lpv += d.landingPageViews;
  }
  if (comLpv.size === 0) return taxa(null, null, 'Sem view de página no recorte.');
  const inscricoes = leads.filter((l) => ehPago(l) && l.anuncioId !== null && comLpv.has(l.anuncioId)).length;
  return taxa(inscricoes, lpv);
}

/** CPL = gasto de tráfego do recorte ÷ leads pagos do mesmo recorte. */
export const cpl = (gasto: Valor, leadsPagos: Valor): Valor => dividir(gasto, leadsPagos);

/** Farol pela régua do Caio (CPL por conjunto: meta R$ 15, teto R$ 20). */
export type Farol = 'verde' | 'amarelo' | 'vermelho' | 'sem';
/** Sem régua cadastrada (fonte real hoje), não há farol: 'sem'. */
export function farolCpl(valor: Valor, regua: ReguaCpl | null): Farol {
  if (valor === null || regua === null) return 'sem';
  if (valor <= regua.meta) return 'verde';
  if (valor <= regua.teto) return 'amarelo';
  return 'vermelho';
}

// ─── Ingresso no grupo (pessoas únicas, janelas maduras) ───────────────────────────────────────────────────
export const JANELAS_GRUPO = [2, 12, 24, 48] as const;
export type JanelaGrupo = (typeof JANELAS_GRUPO)[number];
const HORA = 3_600_000;

/**
 * Ingresso no grupo em até `horas` depois do primeiro cadastro da pessoa. Denominador = pessoas cuja janela
 * já fechou em `agora` (não pune quem se cadastrou há 1 hora); numerador = dessas, quem entrou dentro da janela.
 * Quem já estava no grupo antes do cadastro conta como dentro.
 */
/** MQL = profissão do envio mais recente da pessoa, como dados_black_grupo (regra B). */
export const ehMqlPorProfissao = (l: LinhaPerfil): boolean => l.profissao !== null && PROFISSOES_MQL.has(l.profissao);

/** Retorna um envio por pessoa, escolhido pela maior data de criação; empate preserva a primeira linha recebida. */
export function enviosMaisRecentesPorPessoa(linhas: readonly LinhaPerfil[]): LinhaPerfil[] {
  const maisRecentes = new Map<string, LinhaPerfil>();
  for (const linha of linhas) {
    const atual = maisRecentes.get(linha.pessoaId);
    if (!atual || Date.parse(linha.criadoEm) > Date.parse(atual.criadoEm)) maisRecentes.set(linha.pessoaId, linha);
  }
  return [...maisRecentes.values()];
}

/** Regra B do Victor (13/10/2026): profissão do envio mais recente, uma pessoa por linha. */
export function mqlDoRecorte(linhas: readonly LinhaPerfil[]): Taxa {
  const ultimos = enviosMaisRecentesPorPessoa(linhas);
  return taxa(ultimos.filter(ehMqlPorProfissao).length, ultimos.length,
    'Regra B: profissão do envio mais recente ÷ pessoas únicas do recorte.');
}

/** Linhas mais recentes das pessoas classificadas como MQL pela regra B. */
export function enviosMqlMaisRecentes(linhas: readonly LinhaPerfil[]): LinhaPerfil[] {
  return enviosMaisRecentesPorPessoa(linhas).filter(ehMqlPorProfissao);
}

/**
 * Ingresso no grupo geral: pessoas únicas que entraram no grupo, em qualquer data, ÷ pessoas únicas do recorte
 * (os leads gerais, não só os MQL). Sem janela de horas, diferente de `ingressoGrupo`.
 */
export function ingressoGrupoGeral(linhas: readonly LinhaPerfil[]): Taxa {
  const todas = new Set<string>(); const entrou = new Set<string>();
  for (const l of linhas) { todas.add(l.pessoaId); if (l.entrouGrupoEm) entrou.add(l.pessoaId); }
  return taxa(entrou.size, todas.size, 'Pessoas únicas que entraram no grupo ÷ pessoas únicas do recorte (todos os leads).');
}

export function ingressoGrupo(linhas: readonly LinhaPerfil[], horas: number, agora: Date): Taxa {
  const pessoas = new Map<string, { criado: number; entrou: number | null }>();
  for (const l of linhas) {
    const c = Date.parse(l.criadoEm);
    const e = l.entrouGrupoEm ? Date.parse(l.entrouGrupoEm) : null;
    const p = pessoas.get(l.pessoaId);
    if (!p) pessoas.set(l.pessoaId, { criado: c, entrou: e });
    else { p.criado = Math.min(p.criado, c); if (e !== null) p.entrou = p.entrou === null ? e : Math.min(p.entrou, e); }
  }
  let den = 0; let num = 0;
  const limite = agora.getTime();
  for (const p of pessoas.values()) {
    if (p.criado + horas * HORA > limite) continue;
    den += 1;
    if (p.entrou !== null && p.entrou - p.criado <= horas * HORA) num += 1;
  }
  return taxa(num, den, `Pessoas únicas com a janela de ${horas}h já fechada.`);
}

/** Pessoas únicas (um lead com duas portas conta uma vez). */
export const pessoasUnicas = (linhas: readonly LinhaPerfil[]) => new Set(linhas.map((l) => l.pessoaId)).size;

// ─── Recorte por funil e canal, e CPL por etapa ────────────────────────────────────────────────────────────
export interface FiltroBase { funil: FiltroFunil; canal: FiltroCanal }

/** A campanha da Entresafra não participa de nenhum gasto ou métrica de tráfego deste dashboard. */
export function ehEntresafraCampanha(c: Campanha | null | undefined): boolean {
  return !!c && (c.subtipo?.toLocaleUpperCase('pt-BR') === 'ENTRESAFRA' || /\bENTRESAFRA\b/i.test(c.nome));
}

/** Linhas de desempenho do funil e do canal escolhidos (pela campanha do anúncio). */
export function filtrarDias(dias: readonly DesempenhoDia[], idx: IndiceTrafego, f: FiltroBase): DesempenhoDia[] {
  return dias.filter((d) => {
    const c = idx.campanhaDoAnuncio(d.anuncioId);
    if (!c || ehEntresafraCampanha(c)) return false;
    return (f.funil === 'todos' || c.funil === f.funil) && (f.canal === 'todos' || c.canal === f.canal);
  });
}

/** Cadastros do funil e do canal. Com canal escolhido, quem não veio de tráfego (canal null) sai. */
export function filtrarLinhas(linhas: readonly LinhaPerfil[], f: FiltroBase): LinhaPerfil[] {
  if (f.funil === 'todos' && f.canal === 'todos') return [...linhas];
  return linhas.filter((l) => (f.funil === 'todos' || l.funil === f.funil) && (f.canal === 'todos' || l.canal === f.canal));
}

export const gastoDe = (dias: readonly DesempenhoDia[]) => dias.reduce((s, d) => s + d.gasto, 0);

export interface Cpl { gasto: Valor; leadsPagos: number; valor: Valor }
/** CPL de um recorte: dias e linhas JÁ filtrados pelo mesmo critério. */
export function cplDo(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[]): Cpl {
  const gasto = dias.length ? gastoDe(dias) : null;
  const leadsPagos = linhas.filter(ehPago).length;
  return { gasto, leadsPagos, valor: cpl(gasto, leadsPagos) };
}

/** CPL geral: campanhas de C2/C3 em captação, sem remarketing, e só leads pagos atribuídos a elas. */
export function cplPlacar(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego,
  gastoCampanhas?: readonly { campanhaId: string; gasto: number }[],
  filtro: FiltroBase = { funil: 'todos', canal: 'todos' }): Cpl {
  const elegivel = (c: Campanha | null) => c !== null && !ehEntresafraCampanha(c) && c.fase !== 'remarketing'
    && !/REMARKETING/i.test(c.nome)
    && (c.etapa === 'C2' || c.etapa === 'C3' || (c.etapa === undefined && c.fase === 'captacao' && ehCaptacao(c.funil)));
  const passaFunil = (c: Campanha) => filtro.funil === 'todos' || c.funil === filtro.funil
    || (filtro.funil === 'iscas' && c.funil === 'c3' && c.subtipo === 'ISCA');
  const candidatas = [...idx.campanha.values()].filter((c) => elegivel(c) && passaFunil(c)
    && (filtro.canal === 'todos' || c.canal === filtro.canal));
  const campanhas = new Set(candidatas.map((c) => c.id));
  const l = linhas.filter((x) => x.campanhaId !== null && campanhas.has(x.campanhaId));
  if (gastoCampanhas) {
    const gastos = gastoCampanhas.filter((x) => campanhas.has(x.campanhaId));
    const gasto = gastos.length ? gastos.reduce((s, x) => s + x.gasto, 0) : null;
    const leadsPagos = l.filter(ehPago).length;
    return { gasto, leadsPagos, valor: cpl(gasto, leadsPagos) };
  }
  const d = dias.filter((x) => { const c = idx.campanhaDoAnuncio(x.anuncioId); return c !== null && campanhas.has(c.id); });
  return cplDo(d, l);
}

export interface LinhaCplEtapa { chave: string; rotulo: string; nivel: 'etapa' | 'isca' | 'conjunto'; funil: Funil; cpl: Cpl }
/**
 * CPL por etapa (decisão do Victor, 12/10): consultoria; iscas no geral e por isca; C3 no geral e por conjunto.
 * Só campanhas da fase de captação (o remarketing tem linha própria). Gasto da etapa ÷ leads pagos atribuídos às
 * mesmas campanhas/conjuntos. Rótulo do conjunto = nome exato da fonte.
 */
export function cplPorEtapa(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego,
  gastoCampanhas?: readonly { campanhaId: string; gasto: number }[]): LinhaCplEtapa[] {
  const recorte = (ok: (c: Campanha, cj: Conjunto | null) => boolean, usarGastoCampanhas = true) => {
    const ids = new Set([...idx.campanha.values()].filter((c) => ok(c, null)).map((c) => c.id));
    const ds = dias.filter((d) => {
      const c = idx.campanhaDoAnuncio(d.anuncioId);
      return c !== null && (gastoCampanhas && usarGastoCampanhas ? ids.has(c.id) : ok(c, idx.conjuntoDoAnuncio(d.anuncioId)));
    });
    const ls = linhas.filter((l) => {
      const c = l.campanhaId ? idx.campanha.get(l.campanhaId) : undefined;
      return c !== undefined && ok(c, l.conjuntoId ? idx.conjunto.get(l.conjuntoId) ?? null : null);
    });
    if (!gastoCampanhas || !usarGastoCampanhas) return cplDo(ds, ls);
    const custos = gastoCampanhas.filter((x) => ids.has(x.campanhaId));
    const gasto = custos.length ? custos.reduce((s, x) => s + x.gasto, 0) : null;
    const leadsPagos = ls.filter(ehPago).length;
    return { gasto, leadsPagos, valor: cpl(gasto, leadsPagos) };
  };
  const captacao = (f: Funil) => (c: Campanha) => c.funil === f
    && (c.etapa === 'C2' || c.etapa === 'C3' || (c.etapa === undefined && c.fase === 'captacao'))
    && c.fase !== 'remarketing' && !/REMARKETING/i.test(c.nome) && !ehEntresafraCampanha(c);
  const iscaC3 = (c: Campanha, cj: Conjunto | null) => captacao('c3')(c) && (c.subtipo === 'ISCA' || cj?.isca !== null && cj?.isca !== undefined);
  const out: LinhaCplEtapa[] = [
    { chave: 'consultoria', rotulo: 'Consultoria', nivel: 'etapa', funil: 'consultoria', cpl: recorte(captacao('consultoria')) },
    { chave: 'iscas', rotulo: 'Iscas · C3', nivel: 'etapa', funil: 'iscas', cpl: recorte(iscaC3) },
  ];
  for (const isca of ISCAS) {
    const calculo = recorte((c, cj) => iscaC3(c, cj) && cj?.isca === isca, false);
    if ((calculo.gasto ?? 0) > 0 || calculo.leadsPagos > 0) out.push({ chave: `isca:${isca}`, rotulo: isca, nivel: 'isca', funil: 'iscas', cpl: calculo });
  }
  out.push({ chave: 'c3', rotulo: 'C3', nivel: 'etapa', funil: 'c3', cpl: recorte(captacao('c3')) });
  const conjuntosC3 = new Map<string, string>();
  for (const d of dias) {
    const c = idx.campanhaDoAnuncio(d.anuncioId); const cj = idx.conjuntoDoAnuncio(d.anuncioId);
    if (c && cj && captacao('c3')(c)) conjuntosC3.set(cj.id, cj.nome);
  }
  for (const [id, nome] of conjuntosC3) {
    out.push({ chave: `conjunto:${id}`, rotulo: nome, nivel: 'conjunto', funil: 'c3', cpl: recorte((c, cj) => captacao('c3')(c) && cj?.id === id, false) });
  }
  return out;
}

/** CPL do remarketing (fase 4), para a linha própria ao lado das etapas. */
export function cplRemarketing(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego): Cpl {
  return cplDo(
    dias.filter((d) => idx.campanhaDoAnuncio(d.anuncioId)?.fase === 'remarketing'),
    linhas.filter((l) => (l.campanhaId ? idx.campanha.get(l.campanhaId)?.fase : null) === 'remarketing'),
  );
}

/** Gasto por fase do Caio (fase da campanha). Campanha sem fase fica em `semFase`. */
export function gastoPorFase(dias: readonly DesempenhoDia[], idx: IndiceTrafego): { porFase: Record<Fase, number>; semFase: number } {
  const porFase = Object.fromEntries(FASES.map((f) => [f, 0])) as Record<Fase, number>;
  let semFase = 0;
  for (const d of dias) { const f = idx.campanhaDoAnuncio(d.anuncioId)?.fase; if (f) porFase[f] += d.gasto; else semFase += d.gasto; }
  return { porFase, semFase };
}
