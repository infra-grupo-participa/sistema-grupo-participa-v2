// Grafo da aba Jornada: o mapa "Jornada do lead" do Arthur (Projetos/dashboard-black-friday/
// fluxograma-jornada-arthur.html), com mais espaço e métrica por etapa. Os TEXTOS (kicker, título, linhas de
// baixo, rótulos de seta, título do painel semanal) são os do fluxograma, sem mudar uma letra; a posição foi
// redistribuída para caber os números (mesmas colunas, linhas mais altas). Nó sem fonte de dado mostra
// "Sem dado" com o motivo; nunca zero.
//
// Recorte dos nós pelo que o BANCO devolve (padrão do Caio, 16/10/2026): `linha` e `no` do conjunto, nunca pelo nome.
// Onde cada linha cai (decisões documentadas em docs/dashboard-black/README.md):
//   c1 + distribuicao ........ Assistiu 75%?;  no teaser / manifesto / reels_pago ... Teaser / Manifesto / Reels
//   consultoria .............. Convite e Aplicação da consultoria;  iscas ... Criativo e Página da isca
//   c3 ....................... Captação direta (e Inscrição, pela porta);  remarketing_pagina ... Quem viu e não se cadastrou
//   lembrete e fake_live ..... Lembrete de cada live (fake live em linhas próprias, separada do lembrete)
//   remarketing_live ......... Lembrete da live de 03/11;  carrinho ... Live do Método Perfeito
//   Cortes: o guia não traz campanha nem conjunto de cortes; fica sem dado, com o motivo. pre_captacao: fora de tudo.
import {
  agregar, cpm, ctr, custoPorVisualizacao, taxa, taxaVideo75,
  type IndiceTrafego, type Taxa,
} from './metricas';
import { connectRate, conversaoPagina, cplCaptacao, ingressoGrupoJanela, leadsDoTrafego, leadsPagosUnicos, leadsPessoas } from './numeros';
import { linhaDoLead } from './linha-black';
import type { ConfigBlack, DesempenhoDia, FiltroFunil, Funil, LinhaBlack, LinhaPerfil, MensageriaBlack, NoBlack, Valor } from './tipos';

export type FormatoMetrica = 'int' | 'brl' | 'pct' | 'dec';
export interface MetricaNo { rotulo: string; valor: Valor; formato: FormatoMetrica; taxa?: Taxa; nota?: string }

export type FormaNo = 'caixa' | 'pilula' | 'decisao';
export interface RecorteNo {
  /** Anúncios do nó (pela linha e pelo nó do CONJUNTO que o banco devolve). */
  anuncio: (idx: IndiceTrafego, anuncioId: string) => boolean;
  /** Leads do nó. null = o nó não tem lead (distribuição, lembrete). */
  linha: ((l: LinhaPerfil, idx: IndiceTrafego) => boolean) | null;
  /** C1, teaser e lembretes: métricas de distribuição (sem CPL, sem connect rate). */
  distribuicao?: boolean;
}
export interface DefinicaoNo {
  id: string;
  /** Linha pequena de cima (classe "k" no fluxograma), linha principal ("t") e as de baixo ("s"). */
  kicker: string | null; titulo: string; sub: readonly string[];
  forma: FormaNo; destaque?: boolean;
  x: number; y: number; w: number; h: number;
  /** Funis a que o nó pertence. Vazio = cadeia comum (vale para todos e nunca apaga). */
  funis: readonly Funil[];
  /** Recorte do tráfego e dos leads (abre a gaveta Etapa · Criativos · Perfil). null = sem fonte. */
  recorte: RecorteNo | null;
  /** Motivo do "Sem dado" quando o nó não tem fonte. */
  semFonte?: string;
  /** Métricas que aparecem dentro da caixa (a gaveta mostra todas). */
  resumo?: readonly string[];
}

export interface Seta {
  de: string; para: string; d: string;
  rotulo?: readonly string[]; rotuloX?: number; rotuloY?: number; rotuloGiro?: number;
  tracejada?: boolean;
  volume?: (m: MapaMetricas) => Valor;
}
export interface Painel { x: number; y: number; w: number; h: number; titulo: string; tituloX: number; tituloY: number }
export interface RotuloSolto { texto: string; x: number; y: number }

export const VIEWBOX_JORNADA = { largura: 1100, altura: 1900 } as const;

const daLinha = (...linhasOk: LinhaBlack[]) => (idx: IndiceTrafego, id: string) => { const l = idx.linhaDoAnuncio(id); return l !== null && linhasOk.includes(l); };
const doNo = (...nos: NoBlack[]) => (idx: IndiceTrafego, id: string) => { const n = idx.noDoAnuncio(id); return n !== null && nos.includes(n); };
/**
 * Linha do cadastro pelo conjunto (ou campanha) do anúncio que o trouxe. Cadastro na campanha mista (`CAPTAÇÃO | ISCAS`)
 * sem conjunto casado cai pela porta do cadastro; sem anúncio casado, fora de qualquer nó de tráfego.
 */
const linhaDoCadastro = (l: LinhaPerfil, idx: IndiceTrafego): LinhaBlack | null => {
  const x = linhaDoLead(l, idx);
  if (x === 'c2') return l.funil === 'consultoria' ? 'consultoria' : l.funil === 'iscas' ? 'iscas' : 'c2';
  return x ?? null;
};
const leadDaLinha = (...linhasOk: LinhaBlack[]) => (l: LinhaPerfil, idx: IndiceTrafego) => { const x = linhaDoCadastro(l, idx); return x !== null && linhasOk.includes(x); };
const RESUMO_CAPTACAO = ['Leads pagos', 'CPL', 'Conversão da página'] as const;
const RESUMO_DISTRIBUICAO = ['Investimento', 'Impressões', 'Custo por visualização'] as const;

export const NOS: readonly DefinicaoNo[] = [
  { id: 'publico-frio', kicker: null, titulo: 'Público frio', sub: [], forma: 'pilula', x: 430, y: 20, w: 240, h: 46, funis: ['c1'], recorte: null },
  { id: 'manifesto', kicker: 'C1', titulo: 'Manifesto', sub: ['um capítulo por segunda'], forma: 'caixa', x: 35, y: 110, w: 230, h: 120, funis: ['c1'], recorte: { anuncio: doNo('manifesto'), linha: null, distribuicao: true }, resumo: RESUMO_DISTRIBUICAO },
  { id: 'teaser', kicker: 'C1', titulo: 'Teaser', sub: ['distribuído separado'], forma: 'caixa', x: 295, y: 110, w: 230, h: 120, funis: ['c1'], recorte: { anuncio: doNo('teaser'), linha: null, distribuicao: true }, resumo: RESUMO_DISTRIBUICAO },
  { id: 'reels', kicker: 'C1 · orgânico', titulo: 'Reels do Marcio', sub: ['quem consome 75% entra no C2'], forma: 'caixa', x: 555, y: 110, w: 230, h: 120, funis: ['c1'], recorte: { anuncio: doNo('reels_pago'), linha: null, distribuicao: true }, resumo: RESUMO_DISTRIBUICAO },
  { id: 'cortes', kicker: 'C1 · novo', titulo: 'Cortes das consultorias', sub: ['4 por live, no YouTube e impulsionados'], forma: 'caixa', destaque: true, x: 815, y: 110, w: 230, h: 120, funis: ['c1'], recorte: null, semFonte: 'O guia do Caio (15/10) não traz campanha nem conjunto de cortes; aguardando o nome com o Caio. Nada é somado aqui enquanto isso.' },
  { id: 'assistiu-75', kicker: null, titulo: 'Assistiu 75%?', sub: [], forma: 'decisao', x: 450, y: 262, w: 200, h: 112, funis: ['c1'], recorte: { anuncio: daLinha('c1', 'distribuicao'), linha: null, distribuicao: true }, resumo: ['Vídeo 75%', 'Taxa de 75%'] },
  { id: 'segue-c1', kicker: null, titulo: 'segue vendo C1', sub: [], forma: 'pilula', x: 170, y: 298, w: 154, h: 40, funis: ['c1'], recorte: null },
  { id: 'base-da-casa', kicker: null, titulo: 'Base da casa', sub: ['cerca de 189 mil leads'], forma: 'pilula', x: 800, y: 274, w: 240, h: 104, funis: ['c3'], recorte: null, resumo: ['Tamanho da base', 'Já na base e cadastrados'] },
  { id: 'convite-consultoria', kicker: 'C2 · novo', titulo: 'Convite para a consultoria', sub: ['criativos a pedir ao Marcio'], forma: 'caixa', destaque: true, x: 70, y: 430, w: 240, h: 120, funis: ['consultoria'], recorte: { anuncio: daLinha('consultoria'), linha: leadDaLinha('consultoria') }, resumo: ['Investimento', 'Cliques', 'CTR'] },
  { id: 'criativo-isca', kicker: 'C2 · ver links', titulo: 'Criativo de isca', sub: ['Checkup · Futurômetro · Fluxograma'], forma: 'caixa', x: 430, y: 430, w: 240, h: 120, funis: ['iscas'], recorte: { anuncio: daLinha('iscas'), linha: leadDaLinha('iscas') }, resumo: ['Investimento', 'Cliques', 'CTR'] },
  { id: 'aplicacao-consultoria', kicker: 'Respondi · ver link', titulo: 'Aplicação da consultoria', sub: ['formulário; página ainda não existe'], forma: 'caixa', x: 70, y: 620, w: 240, h: 120, funis: ['consultoria'], recorte: { anuncio: daLinha('consultoria'), linha: leadDaLinha('consultoria') }, resumo: ['Aplicações', 'CPL', 'Conversão da página'] },
  { id: 'pagina-isca', kicker: 'Página · entrega a isca', titulo: 'Página da isca', sub: ['nome, e-mail e WhatsApp'], forma: 'caixa', x: 430, y: 620, w: 240, h: 120, funis: ['iscas'], recorte: { anuncio: daLinha('iscas'), linha: leadDaLinha('iscas') }, resumo: RESUMO_CAPTACAO },
  { id: 'captacao-direta', kicker: 'C3 · ver criativos', titulo: 'Captação direta', sub: ['convite direto para o Método Perfeito'], forma: 'caixa', x: 800, y: 620, w: 240, h: 120, funis: ['c3'], recorte: { anuncio: daLinha('c3'), linha: leadDaLinha('c3') }, resumo: RESUMO_CAPTACAO },
  { id: 'remarketing', kicker: 'Remarketing · C2 e C3', titulo: 'Quem viu e não se cadastrou', sub: ['anúncio curto e direto', 'da isca ou da inscrição,', 'sem conteúdo novo'], forma: 'caixa', destaque: true, x: 70, y: 810, w: 240, h: 150, funis: ['consultoria', 'iscas', 'c3'], recorte: { anuncio: daLinha('remarketing_pagina'), linha: leadDaLinha('remarketing_pagina') }, resumo: ['Leads pagos', 'CPL'] },
  { id: 'central', kicker: 'Novo · obrigado de tudo', titulo: 'Central do Método Perfeito', sub: ['live de 03/11 e calendário', 'consultorias, Pilares, teasers e manifestos', 'convite para baixar o app', 'link do grupo'], forma: 'caixa', destaque: true, x: 430, y: 810, w: 240, h: 150, funis: ['consultoria', 'iscas'], recorte: null, semFonte: 'Página nova, ainda sem medição.' },
  { id: 'inscricao', kicker: 'Página', titulo: 'Inscrição', sub: ['timeholdingbrasil.com.br/metodo-perfeito'], forma: 'caixa', x: 800, y: 810, w: 240, h: 150, funis: ['c3'], recorte: { anuncio: daLinha('c3'), linha: (l) => l.porta === 'inscricao_direta' }, resumo: ['Inscrições', 'Pagas', 'Fora do tráfego'] },
  { id: 'lista', kicker: 'Ponto de encontro', titulo: 'Lista do Método Perfeito', sub: ['uma pessoa, uma régua', 'reconhecida por e-mail ou pelos 8 últimos dígitos'], forma: 'caixa', destaque: true, x: 380, y: 1000, w: 340, h: 140, funis: [], recorte: { anuncio: () => true, linha: () => true }, resumo: ['Pessoas', 'Cadastros', 'Da meta de 15 mil'] },
  { id: 'grupos', kicker: 'WhatsApp · ver links', titulo: 'Grupos por profissão', sub: ['em silêncio até 31/10'], forma: 'caixa', x: 70, y: 1190, w: 240, h: 132, funis: [], recorte: { anuncio: () => false, linha: () => true }, resumo: ['Em 2h', 'Em 24h', 'Em 48h'] },
  { id: 'regua', kicker: 'API · ver mensageria', titulo: 'Régua do aquecimento', sub: ['boas-vindas e convites da semana'], forma: 'caixa', x: 430, y: 1190, w: 240, h: 132, funis: [], recorte: null, semFonte: 'Mensageria por API: sem fonte ligada.', resumo: ['Enviados', 'Entregues', 'Custo'] },
  { id: 'lembrete', kicker: 'Tráfego', titulo: 'Lembrete de cada live', sub: ['é amanhã · é hoje · ao vivo'], forma: 'caixa', x: 800, y: 1190, w: 240, h: 132, funis: [], recorte: { anuncio: daLinha('lembrete'), linha: null, distribuicao: true }, resumo: [...RESUMO_DISTRIBUICAO, 'Fake live · Investimento'] },
  // Ciclo semanal (painel "Toda semana · 13 a 29/10"): sem fonte por etapa nesta versão.
  { id: 'seg', kicker: 'Segunda · API', titulo: 'Consultoria é amanhã', sub: ['e convite para aplicar'], forma: 'caixa', x: 70, y: 1416, w: 210, h: 100, funis: [], recorte: null, semFonte: 'Sem fonte por dia da semana.' },
  { id: 'ter', kicker: 'Terça · 19h30 · YouTube', titulo: 'Consultoria ao vivo', sub: ['a dor da semana em casos', '+ fake live no Insta'], forma: 'caixa', destaque: true, x: 320, y: 1416, w: 210, h: 100, funis: [], recorte: null, semFonte: 'Presença nas lives: sem fonte ainda.' },
  { id: 'qua', kicker: 'Quarta · API', titulo: 'O Pilar é amanhã', sub: ['o produto da semana'], forma: 'caixa', x: 570, y: 1416, w: 210, h: 100, funis: [], recorte: null, semFonte: 'Sem fonte por dia da semana.' },
  { id: 'qui', kicker: 'Quinta · 19h30 · YouTube', titulo: 'Live do Pilar', sub: ['o produto que resolve', '+ fake live no Insta'], forma: 'caixa', destaque: true, x: 820, y: 1416, w: 210, h: 100, funis: [], recorte: null, semFonte: 'Presença nas lives: sem fonte ainda.' },
  // Reta final.
  { id: 'carga', kicker: '01 e 02/11 · Grupo', titulo: 'Carga de mensagens', sub: ['faltam 2 dias · falta 1 dia'], forma: 'caixa', x: 70, y: 1640, w: 240, h: 80, funis: [], recorte: null, semFonte: 'Sem fonte por mensagem do grupo.' },
  { id: 'lembrete-final', kicker: 'A partir de 27/10 · Tráfego', titulo: 'Lembrete da live de 03/11', sub: ['todo dia até a hora da live'], forma: 'caixa', x: 800, y: 1640, w: 240, h: 80, funis: [], recorte: { anuncio: daLinha('remarketing_live'), linha: null, distribuicao: true }, resumo: RESUMO_DISTRIBUICAO },
  { id: 'live', kicker: null, titulo: 'Live do Método Perfeito', sub: ['03/11 · 19h30 · YouTube + fake live no Insta'], forma: 'pilula', destaque: true, x: 400, y: 1760, w: 300, h: 112, funis: [], recorte: { anuncio: daLinha('carrinho'), linha: null, distribuicao: true }, resumo: ['Investimento', 'Presença', 'Vendas'] },
];
export const NO = new Map(NOS.map((n) => [n.id, n]));

export const PAINEIS: readonly Painel[] = [
  { x: 40, y: 1370, w: 1020, h: 220, titulo: 'Toda semana · 13 a 29/10', tituloX: 60, tituloY: 1580 },
];
export const ROTULOS_SOLTOS: readonly RotuloSolto[] = [
  { texto: 'próxima semana: nova dor, nova consultoria, novo produto', x: 720, y: 1560 },
];

export type MapaMetricas = Record<string, MetricaNo[]>;

const vol = (id: string, rotulo: string) => (m: MapaMetricas) => m[id]?.find((x) => x.rotulo === rotulo)?.valor ?? null;

export const SETAS: readonly Seta[] = [
  { de: 'publico-frio', para: 'manifesto', d: 'M550 66 V88 H150 V106' },
  { de: 'publico-frio', para: 'teaser', d: 'M410 88 V106' },
  { de: 'publico-frio', para: 'reels', d: 'M670 88 V106' },
  { de: 'publico-frio', para: 'cortes', d: 'M550 88 H930 V106' },
  { de: 'cortes', para: 'assistiu-75', d: 'M150 230 V246 H930 V230 M410 230 V246 M670 230 V246 M550 246 V258', volume: vol('cortes', 'Impressões') },
  { de: 'assistiu-75', para: 'segue-c1', d: 'M450 318 H328', rotulo: ['não'], rotuloX: 372, rotuloY: 308 },
  { de: 'assistiu-75', para: 'convite-consultoria', d: 'M550 374 V400 H190 V426', rotulo: ['sim'], rotuloX: 562, rotuloY: 394, volume: vol('assistiu-75', 'Vídeo 75%') },
  { de: 'assistiu-75', para: 'criativo-isca', d: 'M550 400 V426', volume: vol('assistiu-75', 'Vídeo 75%') },
  { de: 'criativo-isca', para: 'captacao-direta', d: 'M670 470 H860 V616', rotulo: ['viu 50 a 75%', 'e não se cadastrou'], rotuloX: 765, rotuloY: 450 },
  { de: 'base-da-casa', para: 'captacao-direta', d: 'M920 378 V616' },
  { de: 'convite-consultoria', para: 'aplicacao-consultoria', d: 'M190 550 V616', volume: vol('convite-consultoria', 'Cliques') },
  { de: 'criativo-isca', para: 'pagina-isca', d: 'M550 550 V616', rotulo: ['clicou'], rotuloX: 562, rotuloY: 590, volume: vol('criativo-isca', 'Cliques') },
  { de: 'pagina-isca', para: 'central', d: 'M550 740 V806', volume: vol('pagina-isca', 'Leads pagos') },
  { de: 'captacao-direta', para: 'inscricao', d: 'M920 740 V806', volume: vol('captacao-direta', 'Leads pagos') },
  { de: 'aplicacao-consultoria', para: 'central', d: 'M190 740 V770 H400 V860 H426', volume: vol('aplicacao-consultoria', 'Aplicações') },
  { de: 'remarketing', para: 'pagina-isca', d: 'M310 885 H372 V680 H426', rotulo: ['volta'], tracejada: true, rotuloX: 318, rotuloY: 876 },
  { de: 'central', para: 'lista', d: 'M550 960 V996', rotulo: ['isca e aplicação já inscrevem'], rotuloX: 562, rotuloY: 982 },
  { de: 'inscricao', para: 'lista', d: 'M920 960 V1070 H724', volume: vol('inscricao', 'Inscrições') },
  { de: 'lista', para: 'captacao-direta', d: 'M720 1100 H1075 V680 H1044', rotulo: ['inscrito sai do C2, C3 e remarketing'], tracejada: true, rotuloX: 1062, rotuloY: 890, rotuloGiro: -90 },
  { de: 'lista', para: 'grupos', d: 'M550 1140 V1165 H190 V1186', volume: vol('lista', 'Pessoas') },
  { de: 'lista', para: 'regua', d: 'M550 1165 V1186' },
  { de: 'lista', para: 'lembrete', d: 'M550 1165 H920 V1186' },
  { de: 'regua', para: 'seg', d: 'M550 1322 V1350 H175 V1412', rotulo: ['API'], rotuloX: 565, rotuloY: 1344 },
  { de: 'regua', para: 'qua', d: 'M550 1350 H675 V1412' },
  { de: 'lembrete', para: 'ter', d: 'M920 1322 V1362 H425 V1412', rotulo: ['lembretes'], rotuloX: 935, rotuloY: 1356 },
  { de: 'lembrete', para: 'qui', d: 'M920 1362 H925 V1412' },
  { de: 'seg', para: 'ter', d: 'M280 1466 H316' },
  { de: 'ter', para: 'qua', d: 'M530 1466 H566' },
  { de: 'qua', para: 'qui', d: 'M780 1466 H816' },
  { de: 'qui', para: 'seg', d: 'M925 1516 V1540 H175 V1520', tracejada: true },
  { de: 'grupos', para: 'carga', d: 'M70 1256 H44 V1680 H66' },
  { de: 'lembrete', para: 'lembrete-final', d: 'M1040 1256 H1080 V1680 H1044' },
  { de: 'manifesto', para: 'live', d: 'M550 1590 V1756', rotulo: ['02/11 · capítulo 5', 'do manifesto'], rotuloX: 562, rotuloY: 1640 },
  { de: 'carga', para: 'live', d: 'M310 1680 H360 V1816 H396' },
  { de: 'lembrete-final', para: 'live', d: 'M800 1680 H740 V1816 H704' },
];

/** Espessura da seta: sqrt(volume) normalizado de 2 a 14 px (plano, seção 6). Sem volume = 2 px. */
export function espessura(volume: Valor, maximo: number): number {
  if (volume === null || volume <= 0 || maximo <= 0) return 2;
  return 2 + 12 * Math.sqrt(Math.min(volume, maximo) / maximo);
}

/** Nó apagado pelo filtro de funil (opacidade 0,25, fora do teclado). A cadeia comum nunca apaga. */
export const noApagado = (n: DefinicaoNo, funil: FiltroFunil) => funil !== 'todos' && n.funis.length > 0
  && !(funil === 'c2' ? n.funis.some((f) => f === 'consultoria' || f === 'iscas') : n.funis.includes(funil));

/** Recorta dias e linhas do nó (o que a gaveta da etapa usa). */
export function recortarNo(n: DefinicaoNo, dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego) {
  if (!n.recorte) return { dias: [] as DesempenhoDia[], linhas: [] as LinhaPerfil[] };
  const r = n.recorte;
  const linha = r.linha;
  return {
    dias: dias.filter((d) => r.anuncio(idx, d.anuncioId)),
    linhas: linha ? linhas.filter((l) => linha(l, idx)) : [],
  };
}

const m = (rotulo: string, valor: Valor, formato: FormatoMetrica, extra: Partial<MetricaNo> = {}): MetricaNo => ({ rotulo, valor, formato, ...extra });

/** Métricas de distribuição (C1, teaser, lembretes, live): sem CPL e sem connect rate. */
export function metricasDistribuicao(dias: readonly DesempenhoDia[]): MetricaNo[] {
  if (dias.length === 0) return [];
  const a = agregar(dias);
  const v75 = taxaVideo75(a);
  return [
    m('Investimento', a.gasto, 'brl'), m('Impressões', a.impressoes, 'int'), m('CPM', cpm(a), 'brl'),
    m('Vídeo 75%', a.p75.valor, 'int', { taxa: v75 }), m('Custo por visualização', custoPorVisualizacao(a), 'brl', { nota: 'Investimento ÷ ThruPlay' }),
  ];
}

/**
 * Métricas de captação (C2 e C3): tráfego, página e leads. `semDetalhe` é o gasto das campanhas únicas da linha que nenhum
 * anúncio explica (campanha sem linha de anúncio no recorte): a campanha é o dinheiro, então entra no Investimento do nó.
 */
export function metricasCaptacao(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego, rotuloLeads = 'Leads pagos', semDetalhe = 0): MetricaNo[] {
  if (dias.length === 0 && linhas.length === 0 && semDetalhe <= 0) return [];
  const a = agregar(dias);
  const leads = leadsPagosUnicos(linhas);
  const gasto: Valor = dias.length || semDetalhe > 0 ? a.gasto + semDetalhe : null;
  const c = cplCaptacao(gasto, leads);
  const cr = connectRate(dias, idx);
  const conv = conversaoPagina(dias, linhas, idx);
  const t = ctr(a);
  return [
    m('Investimento', gasto, 'brl'), m('Impressões', dias.length ? a.impressoes : null, 'int'),
    m('Cliques', a.cliques.valor, 'int'), m('CTR', t.valor, 'pct', { taxa: t }),
    m('Views da página', a.lpv.valor, 'int'), m('Connect rate', cr.valor, 'pct', { taxa: cr, nota: cr.nota ?? undefined }),
    m(rotuloLeads, leads.valor, 'int'), m('Conversão da página', conv.valor, 'pct', { taxa: conv, nota: conv.nota ?? undefined }),
    m('CPL', c.valor, 'brl', { taxa: c, nota: c.nota ?? undefined }),
  ];
}

/** Topo do anúncio (sem página): investimento, impressões, cliques e CTR. */
function metricasCriativo(dias: readonly DesempenhoDia[], semDetalhe = 0): MetricaNo[] {
  if (dias.length === 0 && semDetalhe <= 0) return [];
  const a = agregar(dias);
  const t = ctr(a);
  return [m('Investimento', a.gasto + semDetalhe, 'brl'), m('Impressões', a.impressoes, 'int'), m('Cliques', a.cliques.valor, 'int'), m('CTR', t.valor, 'pct', { taxa: t })];
}

/**
 * Métricas de cada nó. Nós de funil usam os dados SEM o filtro de funil (o filtro só apaga os outros nós); a
 * cadeia comum (Lista em diante) usa as linhas já filtradas pelo funil escolhido (`linhasDoFunil`).
 * Lista vazia = nó sem dado no período (a tela mostra "Sem dado").
 * A CAMPANHA é o dinheiro (rateio.ts): `dias` chegam com o gasto já rateado pelo gasto da campanha, e `semDetalhe` traz, por
 * linha, o gasto das campanhas únicas sem linha de anúncio (vai inteiro para o nó da linha). Campanha mista (`c2`) sem
 * detalhe não tem nó: aparece como "Sem detalhe por anúncio" no CPL por etapa da Visão geral.
 */
export function calcularJornada(args: {
  dias: readonly DesempenhoDia[]; linhas: readonly LinhaPerfil[]; linhasDoFunil: readonly LinhaPerfil[]; idx: IndiceTrafego;
  config: Pick<ConfigBlack, 'baseDaCasa' | 'metaLeads'>; agora: Date; mensageria: MensageriaBlack | null;
  semDetalhe?: Partial<Record<LinhaBlack, number>>;
}): MapaMetricas {
  const { dias, linhas, linhasDoFunil, idx, config, agora, mensageria } = args;
  const sem = (l: LinhaBlack) => args.semDetalhe?.[l] ?? 0;
  const out: MapaMetricas = {};
  for (const n of NOS) out[n.id] = [];
  const rec = (id: string) => recortarNo(NO.get(id)!, dias, linhas, idx);

  for (const id of ['manifesto', 'teaser', 'reels', 'lembrete', 'lembrete-final']) out[id] = metricasDistribuicao(rec(id).dias);
  // Fake live: linha própria, encaixada no nó do lembrete e mostrada separada (não é C1 nem C2, não soma no lembrete).
  const fake = dias.filter((d) => idx.linhaDoAnuncio(d.anuncioId) === 'fake_live');
  if (fake.length) {
    const a = agregar(fake);
    out.lembrete = [...out.lembrete,
      m('Fake live · Investimento', a.gasto, 'brl', { nota: 'Campanhas de live fake (linha fake_live), separadas do lembrete' }),
      m('Fake live · Impressões', a.impressoes, 'int'),
      m('Fake live · Custo por visualização', custoPorVisualizacao(a), 'brl', { nota: 'Investimento ÷ ThruPlay' })];
  }
  const c1 = rec('assistiu-75').dias;
  if (c1.length) {
    const v75 = taxaVideo75(agregar(c1));
    out['assistiu-75'] = [m('Vídeo 75%', v75.num, 'int', { taxa: v75 }), m('Taxa de 75%', v75.valor, 'pct', { taxa: v75 })];
  }
  out['base-da-casa'] = [
    m('Tamanho da base', config.baseDaCasa, 'int', { nota: 'Total das bases da casa (publicos.md)' }),
    m('Já na base e cadastrados', linhas.filter((l) => l.jaNaBase === true).length, 'int'),
  ];
  const cons = rec('convite-consultoria');
  out['convite-consultoria'] = metricasCriativo(cons.dias, sem('consultoria'));
  out['aplicacao-consultoria'] = metricasCaptacao(cons.dias, cons.linhas, idx, 'Aplicações', sem('consultoria'));
  const isc = rec('criativo-isca');
  out['criativo-isca'] = metricasCriativo(isc.dias, sem('iscas'));
  out['pagina-isca'] = metricasCaptacao(isc.dias, isc.linhas, idx, 'Leads pagos', sem('iscas'));
  const c3 = rec('captacao-direta');
  out['captacao-direta'] = metricasCaptacao(c3.dias, c3.linhas, idx, 'Leads pagos', sem('c3'));
  const rmk = rec('remarketing');
  out.remarketing = metricasCaptacao(rmk.dias, rmk.linhas, idx, 'Leads pagos', sem('remarketing_pagina'));
  const ins = rec('inscricao');
  const pessoasInscricao = leadsPessoas(ins.linhas).valor ?? 0;
  const pagosInscricao = leadsDoTrafego(ins.linhas, idx).valor ?? 0;
  out.inscricao = [
    m('Inscrições', pessoasInscricao, 'int'), m('Pagas', pagosInscricao, 'int'),
    m('Fora do tráfego', pessoasInscricao - pagosInscricao, 'int', { nota: 'Orgânico, base por API e grupo legado' }),
  ];
  const pessoas = leadsPessoas(linhasDoFunil).valor ?? 0;
  const daMeta = taxa(pessoas, config.metaLeads);
  out.lista = [
    m('Pessoas', pessoas, 'int', { nota: 'Pessoas únicas (um lead com duas portas conta uma vez)' }),
    m('Cadastros', linhasDoFunil.length, 'int'),
    m('Da meta de 15 mil', daMeta.valor, 'pct', { taxa: daMeta }),
  ];
  out.grupos = ([2, 12, 24, 48] as const).map((h) => {
    const t = ingressoGrupoJanela(linhasDoFunil, h, agora);
    return m(`Ingresso em ${h}h · coorte madura`, t.valor, 'pct', { taxa: t, nota: t.nota ?? undefined });
  });
  const api = mensageria?.canais.find((c) => c.canal === 'api') ?? null;
  if (api) out.regua = [m('Enviados', api.enviados, 'int'), m('Entregues', api.entregues, 'int'), m('Custo', api.custo, 'brl')];
  const live = metricasDistribuicao(rec('live').dias);
  out.live = [...(live.length ? live : [m('Investimento', null, 'brl')]), m('Presença', null, 'int', { nota: 'Sem fonte ainda' }), m('Vendas', null, 'int', { nota: 'Sem fonte ainda' })];
  return out;
}

/** As métricas que cabem dentro da caixa, na ordem do `resumo` do nó. */
export function resumoDoNo(n: DefinicaoNo, metricas: readonly MetricaNo[]): MetricaNo[] {
  if (!n.resumo) return [];
  return n.resumo.map((r) => metricas.find((x) => x.rotulo === r)).filter((x): x is MetricaNo => x !== undefined);
}
