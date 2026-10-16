// Métricas do dashboard da Black. Regra única: razão = soma sobre soma, numerador e denominador no MESMO
// recorte e só nas linhas em que os dois são conhecidos. Sem dado (null) nunca vira zero.
import {
  leadNoFunil, linhaDaCampanha, linhaDoConjunto, linhaDoLead, linhaEhCaptacao, linhaNoFunil, noDoConjunto,
} from './linha-black';
import { PROFISSOES_MQL } from './tipos';
import type {
  Anuncio, Campanha, Conjunto, DesempenhoDia, FiltroCanal, FiltroFunil, Funil, LinhaBlack, LinhaPerfil, NoBlack, ReguaCpl, TrafegoBlack, Valor,
} from './tipos';

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

/** Funis das colunas da tela (Consultoria, Iscas e C3). Quem decide o que é captação é a LINHA (linha-black.ts), não o funil. */
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
  /** Linha do banco do anúncio (a do conjunto; no `c2` o conjunto separa iscas de consultoria). null = Sem classificação. */
  linhaDoAnuncio: (anuncioId: string) => LinhaBlack | null;
  linhaDoConjuntoPorId: (conjuntoId: string) => LinhaBlack | null;
  noDoAnuncio: (anuncioId: string) => NoBlack | null;
  /** O anúncio conta nas métricas de captação (Iscas, Consultoria, C3 e remarketing da página; pré-captação fora). */
  anuncioEhCaptacao: (anuncioId: string) => boolean;
}
export function indexar(t: Pick<TrafegoBlack, 'campanhas' | 'conjuntos' | 'anuncios'>): IndiceTrafego {
  const campanha = new Map(t.campanhas.map((c) => [c.id, c]));
  const conjunto = new Map(t.conjuntos.map((c) => [c.id, c]));
  const anuncio = new Map(t.anuncios.map((a) => [a.id, a]));
  const conjuntoDoAnuncio = (id: string) => { const a = anuncio.get(id); return a ? conjunto.get(a.conjuntoId) ?? null : null; };
  const campanhaDoAnuncio = (id: string) => { const c = conjuntoDoAnuncio(id); return c ? campanha.get(c.campanhaId) ?? null : null; };
  const linhaDoAnuncio = (id: string): LinhaBlack | null => {
    const cj = conjuntoDoAnuncio(id);
    return cj ? linhaDoConjunto(cj, campanha.get(cj.campanhaId)) : null;
  };
  const linhaDoConjuntoPorId = (id: string): LinhaBlack | null => {
    const cj = conjunto.get(id);
    return cj ? linhaDoConjunto(cj, campanha.get(cj.campanhaId)) : null;
  };
  const noDoAnuncio = (id: string): NoBlack | null => {
    const cj = conjuntoDoAnuncio(id);
    return cj ? noDoConjunto(cj, campanha.get(cj.campanhaId)) : null;
  };
  return {
    campanha, conjunto, anuncio, campanhaDoAnuncio, conjuntoDoAnuncio, linhaDoAnuncio, linhaDoConjuntoPorId, noDoAnuncio,
    anuncioEhCaptacao: (id: string) => linhaEhCaptacao(linhaDoAnuncio(id)),
  };
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
 * Connect rate = Σ LPV ÷ Σ cliques no link, só nos anúncios de captação (predicado único: iscas, consultoria, C3 e
 * remarketing da página), só nas linhas com as duas métricas. O C1, o lembrete e a fake live nunca entram (distribuição,
 * sem view de página). Linha sem LPV (ex.: Google) fica fora e vira nota.
 */
export function connectRate(dias: readonly DesempenhoDia[], idx: IndiceTrafego): Taxa {
  const cap = dias.filter((d) => idx.anuncioEhCaptacao(d.anuncioId));
  if (cap.length === 0) return taxa(null, null, 'Só existe em captação (o C1 é distribuição).');
  const a = agregar(cap);
  const fora = cap.length - a.parLpv.linhas;
  const nota = fora > 0 ? `${fora} linha(s) sem view de página ficaram fora da conta (Google sem LPV).` : null;
  return a.parLpv.linhas === 0 ? taxa(null, null, nota) : taxa(a.parLpv.lpv, a.parLpv.cliques, nota);
}

/** Leads pagos: só tráfego pago entra no CPL (orgânico, base por API e legado ficam fora). */
export const ehPago = (l: LinhaPerfil) => l.origem === 'pago';

/**
 * Conversão da página = inscrições pagas ÷ Σ LPV, mesma regra do connect rate: só anúncios de captação que têm LPV
 * conhecida no recorte; as inscrições contadas são as desses mesmos anúncios.
 */
export function conversaoPagina(dias: readonly DesempenhoDia[], leads: readonly LinhaPerfil[], idx: IndiceTrafego): Taxa {
  const comLpv = new Set<string>();
  let lpv = 0;
  for (const d of dias) {
    if (!idx.anuncioEhCaptacao(d.anuncioId) || d.landingPageViews === null) continue;
    comLpv.add(d.anuncioId); lpv += d.landingPageViews;
  }
  if (comLpv.size === 0) return taxa(null, null, 'Sem view de página no recorte.');
  const inscricoes = pessoasUnicas(leads.filter((l) => ehPago(l) && l.anuncioId !== null && comLpv.has(l.anuncioId)));
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

/** Regra do servidor: ignora envios sem profissão antes de escolher o mais recente. */
export function enviosMaisRecentesComProfissaoPorPessoa(linhas: readonly LinhaPerfil[]): LinhaPerfil[] {
  return enviosMaisRecentesPorPessoa(linhas.filter((linha) => linha.profissao !== null));
}

/** Regra B do Victor (13/10/2026): profissão do envio mais recente, uma pessoa por linha. */
export function mqlDoRecorte(linhas: readonly LinhaPerfil[]): Taxa {
  const ultimos = enviosMaisRecentesComProfissaoPorPessoa(linhas);
  const pessoas = new Set(linhas.map((linha) => linha.pessoaId));
  return taxa(ultimos.filter(ehMqlPorProfissao).length, pessoas.size,
    'Regra B: profissão do envio mais recente ÷ pessoas únicas do recorte.');
}

/** Linhas mais recentes das pessoas classificadas como MQL pela regra B. */
export function enviosMqlMaisRecentes(linhas: readonly LinhaPerfil[]): LinhaPerfil[] {
  return enviosMaisRecentesComProfissaoPorPessoa(linhas).filter(ehMqlPorProfissao);
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

/** Desempenho do funil e do canal escolhidos, pela LINHA do conjunto do anúncio (C2 = consultoria + iscas). Pré-captação sai sempre. */
export function filtrarDias(dias: readonly DesempenhoDia[], idx: IndiceTrafego, f: FiltroBase): DesempenhoDia[] {
  return dias.filter((d) => {
    const c = idx.campanhaDoAnuncio(d.anuncioId);
    if (!c) return false;
    return linhaNoFunil(f.funil, idx.linhaDoAnuncio(d.anuncioId)) && (f.canal === 'todos' || c.canal === f.canal);
  });
}

/**
 * Cadastros do funil e do canal. Com `idx`, o cadastro que casou com um anúncio entra pela LINHA do conjunto dele (a mesma
 * dos dias de tráfego); sem anúncio casado vale a porta. Com canal escolhido, quem não veio de tráfego (canal null) sai.
 */
export function filtrarLinhas(linhas: readonly LinhaPerfil[], f: FiltroBase, idx: IndiceTrafego): LinhaPerfil[] {
  if (f.funil === 'todos' && f.canal === 'todos') return [...linhas];
  return linhas.filter((l) => leadNoFunil(f.funil, l, idx) && (f.canal === 'todos' || l.canal === f.canal));
}

export const gastoDe = (dias: readonly DesempenhoDia[]) => dias.reduce((s, d) => s + d.gasto, 0);

export interface Cpl { gasto: Valor; leadsPagos: number; valor: Valor }
/** CPL de um recorte: dias e linhas JÁ filtrados pelo mesmo critério. */
export function cplDo(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[]): Cpl {
  const gasto = dias.length ? gastoDe(dias) : null;
  const leadsPagos = pessoasUnicas(linhas.filter(ehPago));
  return { gasto, leadsPagos, valor: cpl(gasto, leadsPagos) };
}

/**
 * Gasto de UMA campanha somando os anúncios cujo conjunto está na linha. É o único jeito de separar consultoria de
 * iscas dentro da campanha `c2`; só existe desde `anuncioDesde` (dias por anúncio). null = sem linha de anúncio.
 */
export function gastoCampanhaPorConjunto(dias: readonly DesempenhoDia[], idx: IndiceTrafego, campanhaId: string,
  pertence: (l: LinhaBlack | null) => boolean = () => true): Valor {
  let soma = 0; let k = 0;
  for (const d of dias) {
    if (idx.campanhaDoAnuncio(d.anuncioId)?.id !== campanhaId || !pertence(idx.linhaDoAnuncio(d.anuncioId))) continue;
    soma += d.gasto; k += 1;
  }
  return k === 0 ? null : soma;
}

/**
 * Gasto das campanhas de uma linha. Campanha inteira na linha: gasto da campanha (dias_campanha, desde 01/09).
 * Campanha `c2` diante de uma linha só (Consultoria ou Iscas): soma dos anúncios do conjunto (desde `anuncioDesde`).
 * Diante das duas (C2, Todos, captação): gasto da campanha. Sem gasto conhecido da campanha, ela fica fora da soma.
 * `porCampanha` guarda o que entrou, para a lista de campanhas da etapa fechar com o total.
 */
export function gastoDasLinhas(dias: readonly DesempenhoDia[], gastoCampanhas: readonly { campanhaId: string; gasto: number }[] | undefined,
  idx: IndiceTrafego, pertence: (l: LinhaBlack | null) => boolean, aceita: (c: Campanha) => boolean = () => true):
  { gasto: Valor; porCampanha: Map<string, number> } {
  const doBanco = new Map((gastoCampanhas ?? []).map((x) => [x.campanhaId, x.gasto]));
  const porCampanha = new Map<string, number>();
  for (const c of idx.campanha.values()) {
    if (!aceita(c)) continue;
    const lc = linhaDaCampanha(c);
    let g: Valor;
    if (lc === 'c2' && !(pertence('iscas') && pertence('consultoria'))) {
      if (!pertence('iscas') && !pertence('consultoria')) continue;
      g = gastoCampanhaPorConjunto(dias, idx, c.id, pertence);
    } else if (lc === 'c2' || pertence(lc)) {
      g = gastoCampanhas ? doBanco.get(c.id) ?? null : gastoCampanhaPorConjunto(dias, idx, c.id);
    } else continue;
    if (g !== null) porCampanha.set(c.id, g);
  }
  const gasto = porCampanha.size ? [...porCampanha.values()].reduce((s, x) => s + x, 0) : null;
  return { gasto, porCampanha };
}

/**
 * Cadastros atribuídos a campanhas de captação (predicado único: iscas, consultoria, C3 e remarketing da página; pré-captação
 * fora), no mesmo recorte de funil e canal do CPL. O cadastro entra pela linha do CONJUNTO do anúncio que o trouxe.
 * Resposta da consultoria (pagina consultoria_respondi) não é cadastro novo e fica fora.
 */
export function linhasCaptacao(linhas: readonly LinhaPerfil[], idx: IndiceTrafego,
  filtro: FiltroBase = { funil: 'todos', canal: 'todos' }): LinhaPerfil[] {
  return linhas.filter((l) => {
    if (l.pagina === 'consultoria_respondi') return false;
    const linha = linhaDoLead(l, idx);
    if (linha === undefined || !linhaEhCaptacao(linha) || !linhaNoFunil(filtro.funil, linha)) return false;
    const cj = l.conjuntoId ? idx.conjunto.get(l.conjuntoId) : undefined;
    const c = l.campanhaId ? idx.campanha.get(l.campanhaId) : cj ? idx.campanha.get(cj.campanhaId) : undefined;
    return c !== undefined && (filtro.canal === 'todos' || c.canal === filtro.canal);
  });
}

/** CPL geral: campanhas de captação (predicado único) e só leads pagos atribuídos a elas. */
export function cplPlacar(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego,
  gastoCampanhas?: readonly { campanhaId: string; gasto: number }[],
  filtro: FiltroBase = { funil: 'todos', canal: 'todos' }): Cpl {
  const { gasto } = gastoDasLinhas(dias, gastoCampanhas, idx, (l) => linhaEhCaptacao(l) && linhaNoFunil(filtro.funil, l),
    (c) => filtro.canal === 'todos' || c.canal === filtro.canal);
  const leadsPagos = pessoasUnicas(linhasCaptacao(linhas, idx, filtro).filter(ehPago));
  return { gasto, leadsPagos, valor: cpl(gasto, leadsPagos) };
}

export interface LinhaCplEtapa {
  chave: string; rotulo: string; nivel: 'etapa' | 'isca' | 'conjunto'; funil: Funil | null; linha: LinhaBlack; cpl: Cpl;
  /** Gasto de cada campanha que entrou na linha da etapa (soma = gasto da linha). Só nas linhas de nível `etapa`. */
  campanhas?: { id: string; gasto: number }[];
}
/**
 * CPL por etapa, tudo pela LINHA do banco: Consultoria, Iscas (e cada isca), Remarketing da página, C3 (e cada conjunto).
 * Gasto da etapa ÷ leads pagos atribuídos aos mesmos conjuntos. Rótulo do conjunto = nome exato da fonte.
 */
export function cplPorEtapa(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego,
  gastoCampanhas?: readonly { campanhaId: string; gasto: number }[]): LinhaCplEtapa[] {
  const leadsDe = (pertence: (l: LinhaBlack | null) => boolean, conjuntoOk?: (cj: Conjunto | undefined) => boolean) => linhas.filter((l) => {
    if (l.pagina === 'consultoria_respondi' || !ehPago(l)) return false;
    const linha = linhaDoLead(l, idx);
    if (linha === undefined || !pertence(linha)) return false;
    return !conjuntoOk || conjuntoOk(l.conjuntoId ? idx.conjunto.get(l.conjuntoId) : undefined);
  });
  const etapa = (linha: LinhaBlack): { cpl: Cpl; campanhas: { id: string; gasto: number }[] } => {
    const g = gastoDasLinhas(dias, gastoCampanhas, idx, (l) => l === linha);
    const leadsPagos = pessoasUnicas(leadsDe((l) => l === linha));
    return { cpl: { gasto: g.gasto, leadsPagos, valor: cpl(g.gasto, leadsPagos) },
      campanhas: [...g.porCampanha].map(([id, gasto]) => ({ id, gasto })) };
  };
  // Nível conjunto e isca: só dias por anúncio (o gasto de campanha não separa conjunto).
  const porConjunto = (linha: LinhaBlack, conjuntoOk: (cj: Conjunto | undefined) => boolean): Cpl => {
    const ds = dias.filter((d) => idx.linhaDoAnuncio(d.anuncioId) === linha && conjuntoOk(idx.conjuntoDoAnuncio(d.anuncioId) ?? undefined));
    const leadsPagos = pessoasUnicas(leadsDe((l) => l === linha, conjuntoOk));
    const gasto = ds.length ? gastoDe(ds) : null;
    return { gasto, leadsPagos, valor: cpl(gasto, leadsPagos) };
  };
  const linhaEtapa = (chave: string, rotulo: string, linha: LinhaBlack, funil: Funil | null): LinhaCplEtapa => {
    const e = etapa(linha);
    return { chave, rotulo, nivel: 'etapa', funil, linha, cpl: e.cpl, campanhas: e.campanhas };
  };
  const out: LinhaCplEtapa[] = [
    linhaEtapa('consultoria', 'Consultoria', 'consultoria', 'consultoria'),
    linhaEtapa('iscas', 'Iscas', 'iscas', 'iscas'),
  ];
  for (const isca of ['Fluxograma', 'Futurômetro', 'Checkup'] as const) {
    const calculo = porConjunto('iscas', (cj) => cj?.isca === isca);
    if ((calculo.gasto ?? 0) > 0 || calculo.leadsPagos > 0) out.push({ chave: `isca:${isca}`, rotulo: isca, nivel: 'isca', funil: 'iscas', linha: 'iscas', cpl: calculo });
  }
  out.push(linhaEtapa('remarketing_pagina', 'Remarketing da página', 'remarketing_pagina', null));
  out.push(linhaEtapa('c3', 'C3', 'c3', 'c3'));
  const conjuntosC3 = new Map<string, string>();
  for (const d of dias) {
    const cj = idx.conjuntoDoAnuncio(d.anuncioId);
    if (cj && idx.linhaDoAnuncio(d.anuncioId) === 'c3') conjuntosC3.set(cj.id, cj.nome);
  }
  for (const [id, nome] of conjuntosC3) {
    out.push({ chave: `conjunto:${id}`, rotulo: nome, nivel: 'conjunto', funil: 'c3', linha: 'c3', cpl: porConjunto('c3', (cj) => cj?.id === id) });
  }
  return out;
}
