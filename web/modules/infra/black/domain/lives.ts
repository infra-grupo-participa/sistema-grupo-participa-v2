// Aba "Lives" do dashboard da Black: tipos e contas puras (sem rede, sem React).
// Desenho: DESENHO-ABA-LIVES.md (cérebro do Victor). Contrato das RPCs: docs/dashboard-black/README.md, seção "Aba Lives".
//
// Regras que valem aqui:
// - Valor = number | null. null é "sem dado" (a API ou o CSV não mediu), nunca zero.
// - Razão = soma sobre soma, no mesmo recorte. Aqui as razões são de uma live contra ela mesma (fim ÷ pico) ou do pico
//   de uma live contra o pico da anterior do mesmo tipo.
// - Título é a string exata da fonte. Chat e comentários não têm autor: o desenho aprovado é texto sem nome (o campo nem chega do banco).
import type { Valor } from './tipos';

export type TipoLive = 'consultoria' | 'produto' | 'black';
export type SituacaoLive = 'realizada' | 'ao_vivo' | 'em_breve' | 'a_agendar';
export type OrigemMinuto = 'studio' | 'api';

export const TIPOS_LIVE: readonly TipoLive[] = ['consultoria', 'produto', 'black'];
export const SITUACOES_LIVE: readonly SituacaoLive[] = ['realizada', 'ao_vivo', 'em_breve', 'a_agendar'];
export const ROTULO_TIPO_LIVE: Record<TipoLive, string> = { consultoria: 'Consultoria', produto: 'Produto', black: 'Black' };
export const ROTULO_SITUACAO_LIVE: Record<SituacaoLive, string> = {
  realizada: 'Realizada', ao_vivo: 'Ao vivo', em_breve: 'Em breve', a_agendar: 'A agendar',
};

/** Uma live do cadastro (dados_black_lives), já em camelCase. */
export interface Live {
  videoId: string;
  tipo: TipoLive;
  /** ISO com fuso: horário previsto no cadastro. */
  dataPrevista: string;
  titulo: string | null;
  miniatura: string | null;
  situacao: SituacaoLive;
  agendadaEm: string | null;
  inicio: string | null;
  fim: string | null;
  duracaoSeg: Valor;
  views: Valor; likes: Valor; comentarios: Valor;
  /** Última leitura da API do YouTube para esta live. */
  coletadoEm: string | null;
  espectadoresAgora: Valor;
  /** Os minutos vêm do CSV do Studio (true) ou só da amostra da API (false). */
  temStudio: boolean;
  pico: Valor; picoSeg: Valor; salaCheiaSeg: Valor; ultimoEspectadores: Valor;
  chatTotal: Valor; reacoesTotal: Valor;
  /** Quantas mensagens de chat estão guardadas no banco. */
  chatGuardado: Valor;
}

export interface MinutoLive { seg: number; espectadores: Valor; chat: Valor; reacoes: Valor; origem: OrigemMinuto | null }
export interface MensagemChat { seg: Valor; publicadoEm: string | null; texto: string }
export interface ComentarioLive { publicadoEm: string | null; texto: string; curtidas: Valor; respostas: Valor }
export interface FotoLive { coletadoEm: string; views: Valor; likes: Valor; comentarios: Valor }
export interface DetalheLive { minutos: MinutoLive[]; chat: MensagemChat[]; comentarios: ComentarioLive[]; fotos: FotoLive[] }

/** Resultado de uma ação de escrita da aba (importar, cadastrar, remover): o dado, ou o erro já em português. */
export interface ResultadoLiveAcao<T> { data: T | null; erro: string | null }

export const DETALHE_VAZIO: DetalheLive = { minutos: [], chat: [], comentarios: [], fotos: [] };

/** Prévia ou resultado da importação do CSV do Studio (dados_black_live_importar). */
export interface PreviaImportacao {
  linhas: Valor; pico: Valor; picoSeg: Valor; duracaoSeg: Valor;
  /** Só na resposta com p_confirmar: linhas studio que já existiam, quantas mudam e se gravou. */
  existentes: Valor; alteradas: Valor; gravado: boolean | null;
}

// ─── Ordem e vizinhança ────────────────────────────────────────────────────────────────────────────────────────

export const porData = (a: Live, b: Live) => Date.parse(a.dataPrevista) - Date.parse(b.dataPrevista) || a.videoId.localeCompare(b.videoId);

/** Lives do mesmo tipo antes da data de `live`, da mais recente para a mais antiga. */
function anterioresDoTipo(lives: readonly Live[], live: Live): Live[] {
  const t = Date.parse(live.dataPrevista);
  return lives.filter((l) => l.tipo === live.tipo && l.videoId !== live.videoId && Date.parse(l.dataPrevista) < t)
    .sort((a, b) => porData(b, a));
}

/** A live anterior do mesmo tipo que tem pico medido (a base da comparação). null = não há. */
export function anteriorComPico(lives: readonly Live[], live: Live): Live | null {
  return anterioresDoTipo(lives, live).find((l) => l.pico !== null) ?? null;
}

/** Última live realizada do mesmo tipo com minutos medidos (cinza por baixo da curva ao vivo). */
export function ultimaRealizadaDoTipo(lives: readonly Live[], live: Live): Live | null {
  return anterioresDoTipo(lives, live).find((l) => l.situacao === 'realizada' && l.pico !== null) ?? null;
}

/** Pico ÷ pico da anterior do mesmo tipo (13/10 contra 06/10 = 342 ÷ 363 = 94,2%). null = sem as duas pontas. */
export function picoContraAnterior(lives: readonly Live[], live: Live): { razao: number; num: number; den: number; contra: Live } | null {
  const ant = anteriorComPico(lives, live);
  if (!ant || live.pico === null || ant.pico === null || ant.pico === 0) return null;
  return { razao: live.pico / ant.pico, num: live.pico, den: ant.pico, contra: ant };
}

/** Último minuto ÷ pico: quanto da sala ainda estava lá no fim. null = falta uma ponta. */
export function fimEmPctDoPico(live: Pick<Live, 'ultimoEspectadores' | 'pico'>): number | null {
  if (live.ultimoEspectadores === null || live.pico === null || live.pico === 0) return null;
  return live.ultimoEspectadores / live.pico;
}

/** Minuto (0 = primeiro) de um segundo da live. */
export const minutoDe = (seg: number) => Math.floor(seg / 60);

// ─── Marcos da curva ───────────────────────────────────────────────────────────────────────────────────────────

export interface MarcoCurva { seg: number; minuto: number; espectadores: number }
export interface QuedaCurva { deSeg: number; ateSeg: number; deMinuto: number; ateMinuto: number; de: number; ate: number; perda: number }
export interface MarcosCurva { pico: MarcoCurva | null; salaCheia: MarcoCurva | null; quedas: QuedaCurva[] }

/** Fração do pico que define "sala cheia": o primeiro minuto com 90% do pico ou mais. */
export const FRACAO_SALA_CHEIA = 0.9;
/** Janela da queda, em minutos: a maior perda entre um minuto e o seguinte ou o subsequente. */
export const JANELA_QUEDA_MIN = 2;
export const QUEDAS_MARCADAS = 2;

/**
 * Marcos automáticos da curva minuto a minuto (só minutos com espectadores medidos entram):
 * - pico: o primeiro minuto com o maior valor;
 * - sala cheia: o primeiro minuto com 90% do pico ou mais;
 * - quedas: as 2 maiores perdas absolutas dentro de uma janela de até 2 minutos, sem se sobrepor.
 */
export function marcosDaCurva(minutos: readonly MinutoLive[]): MarcosCurva {
  const m = minutos.filter((x): x is MinutoLive & { espectadores: number } => x.espectadores !== null).sort((a, b) => a.seg - b.seg);
  if (m.length === 0) return { pico: null, salaCheia: null, quedas: [] };
  let melhor = m[0];
  for (const x of m) if (x.espectadores > melhor.espectadores) melhor = x;
  const marco = (x: { seg: number; espectadores: number }): MarcoCurva => ({ seg: x.seg, minuto: minutoDe(x.seg), espectadores: x.espectadores });
  const limite = melhor.espectadores * FRACAO_SALA_CHEIA;
  const cheia = m.find((x) => x.espectadores >= limite) ?? null;

  const candidatas: QuedaCurva[] = [];
  for (let i = 0; i < m.length; i++) {
    let escolhida: QuedaCurva | null = null;
    for (let j = i + 1; j < m.length && m[j].seg - m[i].seg <= JANELA_QUEDA_MIN * 60; j++) {
      const perda = m[i].espectadores - m[j].espectadores;
      if (perda > 0 && (!escolhida || perda > escolhida.perda)) {
        escolhida = {
          deSeg: m[i].seg, ateSeg: m[j].seg, deMinuto: minutoDe(m[i].seg), ateMinuto: minutoDe(m[j].seg),
          de: m[i].espectadores, ate: m[j].espectadores, perda,
        };
      }
    }
    if (escolhida) candidatas.push(escolhida);
  }
  candidatas.sort((a, b) => b.perda - a.perda || a.deSeg - b.deSeg);
  const quedas: QuedaCurva[] = [];
  for (const c of candidatas) {
    if (quedas.length >= QUEDAS_MARCADAS) break;
    if (quedas.every((q) => c.ateSeg < q.deSeg || c.deSeg > q.ateSeg)) quedas.push(c);
  }
  quedas.sort((a, b) => a.deSeg - b.deSeg);
  return { pico: marco(melhor), salaCheia: cheia ? marco(cheia) : null, quedas };
}

// ─── Séries ────────────────────────────────────────────────────────────────────────────────────────────────────

export interface PontoEvolucao {
  videoId: string; tipo: TipoLive; dataPrevista: string; titulo: string | null; situacao: SituacaoLive;
  pico: Valor;
  /** Pico ÷ pico da anterior do mesmo tipo. null = primeira do tipo ou sem pico. */
  contraAnterior: number | null;
}

/** Um ponto por live, na ordem do calendário. */
export function pontosDeEvolucao(lives: readonly Live[]): PontoEvolucao[] {
  return [...lives].sort(porData).map((l) => ({
    videoId: l.videoId, tipo: l.tipo, dataPrevista: l.dataPrevista, titulo: l.titulo, situacao: l.situacao, pico: l.pico,
    contraAnterior: picoContraAnterior(lives, l)?.razao ?? null,
  }));
}

/** Quanto falta (ou quanto passou) até um instante. */
export interface Contagem { dias: number; horas: number; minutos: number; segundos: number; passou: boolean; totalSeg: number }
export function contagemRegressiva(agoraMs: number, alvoIso: string): Contagem | null {
  const alvo = Date.parse(alvoIso);
  if (!Number.isFinite(alvo)) return null;
  const falta = Math.floor((alvo - agoraMs) / 1000);
  const abs = Math.abs(falta);
  return {
    dias: Math.floor(abs / 86_400), horas: Math.floor((abs % 86_400) / 3600), minutos: Math.floor((abs % 3600) / 60), segundos: abs % 60,
    passou: falta < 0, totalSeg: falta,
  };
}

/** Curva da live atual contra a anterior do mesmo tipo, minuto a minuto (a anterior termina onde acabou). */
export interface PontoComparativo { minuto: number; atual: Valor; anterior: Valor }
export function curvaComparativa(atual: readonly MinutoLive[], anterior: readonly MinutoLive[]): PontoComparativo[] {
  const a = new Map(atual.map((x) => [minutoDe(x.seg), x.espectadores]));
  const b = new Map(anterior.map((x) => [minutoDe(x.seg), x.espectadores]));
  const ultimo = Math.max(-1, ...a.keys(), ...b.keys());
  const saida: PontoComparativo[] = [];
  for (let i = 0; i <= ultimo; i++) saida.push({ minuto: i, atual: a.get(i) ?? null, anterior: b.get(i) ?? null });
  return saida;
}

/** No último minuto medido da live atual: quanto ela está acima ou abaixo da anterior no mesmo minuto. */
export function posicaoContraAnterior(pontos: readonly PontoComparativo[]): { minuto: number; atual: number; anterior: number; diferenca: number } | null {
  for (let i = pontos.length - 1; i >= 0; i--) {
    const p = pontos[i];
    if (p.atual !== null && p.anterior !== null) return { minuto: p.minuto, atual: p.atual, anterior: p.anterior, diferenca: p.atual - p.anterior };
    if (p.atual !== null) return null;
  }
  return null;
}

// ─── Chat e comentários ────────────────────────────────────────────────────────────────────────────────────────

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/** Mensagens do minuto escolhido (null = todas) que contêm o texto buscado (sem diferenciar acento nem caixa). */
export function filtrarChat(chat: readonly MensagemChat[], minuto: number | null, busca: string): MensagemChat[] {
  const q = semAcento(busca.trim());
  return chat.filter((m) => {
    if (minuto !== null && (m.seg === null || minutoDe(m.seg) !== minuto)) return false;
    return q === '' || semAcento(m.texto).includes(q);
  });
}

export function filtrarComentarios(comentarios: readonly ComentarioLive[], busca: string): ComentarioLive[] {
  const q = semAcento(busca.trim());
  return q === '' ? [...comentarios] : comentarios.filter((c) => semAcento(c.texto).includes(q));
}

/** Mensagens por minuto, a partir do chat guardado (para a faixa quando o CSV não existe). */
export function mensagensPorMinuto(chat: readonly MensagemChat[]): Map<number, number> {
  const m = new Map<number, number>();
  for (const x of chat) if (x.seg !== null) m.set(minutoDe(x.seg), (m.get(minutoDe(x.seg)) ?? 0) + 1);
  return m;
}

/** Soma de uma coluna ignorando null; todos null = null (nunca 0 por ausência). */
export function somaOuNull(valores: readonly Valor[]): Valor {
  let tem = false; let s = 0;
  for (const v of valores) if (v !== null) { tem = true; s += v; }
  return tem ? s : null;
}

// ─── Texto de tempo ────────────────────────────────────────────────────────────────────────────────────────────

/** 5687 s -> "1h34m47s". null = "Sem dado". */
export function duracaoTexto(seg: Valor): string {
  if (seg === null) return 'Sem dado';
  const h = Math.floor(seg / 3600); const m = Math.floor((seg % 3600) / 60); const s = Math.floor(seg % 60);
  return h > 0 ? `${h}h${String(m).padStart(2, '0')}m${String(s).padStart(2, '0')}s` : `${m}m${String(s).padStart(2, '0')}s`;
}

/** Minuto 48 -> "48 min" (posição na live, 0 = primeiro minuto). */
export const minutoTexto = (seg: Valor) => (seg === null ? 'Sem dado' : `min ${minutoDe(seg)}`);

/** A live entra na lista só se tiver identificador e data válidos. */
export function liveValida(l: Pick<Live, 'videoId' | 'dataPrevista'>): boolean {
  return /^[A-Za-z0-9_-]{11}$/.test(l.videoId) && Number.isFinite(Date.parse(l.dataPrevista));
}

/**
 * Extrai o id de 11 caracteres de um link do YouTube (watch?v=, youtu.be/, live/, embed/, shorts/) ou aceita o id puro.
 * Qualquer outra coisa = null (nunca adivinha).
 */
export function idDoYoutube(entrada: string): string | null {
  const t = entrada.trim();
  if (/^[A-Za-z0-9_-]{11}$/.test(t)) return t;
  let url: URL;
  try { url = new URL(/^https?:\/\//i.test(t) ? t : `https://${t}`); } catch { return null; }
  const host = url.hostname.replace(/^www\.|^m\./, '').toLowerCase();
  if (host !== 'youtube.com' && host !== 'youtu.be' && host !== 'music.youtube.com') return null;
  const ok = (v: string | undefined | null) => (v && /^[A-Za-z0-9_-]{11}$/.test(v) ? v : null);
  if (host === 'youtu.be') return ok(url.pathname.split('/')[1]);
  const v = url.searchParams.get('v');
  if (v) return ok(v);
  const partes = url.pathname.split('/').filter(Boolean);
  if (['live', 'embed', 'shorts', 'v'].includes(partes[0] ?? '')) return ok(partes[1]);
  return null;
}
