// Lives FICTÍCIAS do modo demonstração (aba Lives). Em memória, determinísticas, sem rede. Só entra no bundle quando a
// flag NEXT_PUBLIC_BLACK_DEMO=1 está ligada fora de produção (import dinâmico em fonte.ts).
//
// Tudo aqui é inventado de propósito e marcado: títulos com "ZZ" e "FICTÍCIA", ids ZZdemo000NN, texto de chat com "(demo)". Nenhum nome de pessoa real, nenhuma curva real: os picos e as mensagens
// não são de nenhuma live do Marcio.
import type { Resultado } from '../../domain/tipos';
import {
  DETALHE_VAZIO, minutoDe,
  type ComentarioLive, type DetalheLive, type FotoLive, type Live, type MensagemChat, type MinutoLive, type PreviaImportacao,
  type ResultadoLiveAcao, type SituacaoLive, type TipoLive,
} from '../../domain/lives';
import { resumirStudio, type LinhaStudio } from '../../domain/lives-studio';
import { CHAVE_BLACK } from './catalogo';

interface Roteiro {
  videoId: string; tipo: TipoLive; data: string; titulo: string | null; duracaoMin: number;
  pico: number; picoMin: number; fimFrac: number; chatPorMin: number; semente: number;
  /** De onde vêm os minutos da live já realizada. */
  fonte: 'studio' | 'api';
  /** Live que a API do YouTube "não encontrou": aparece como A agendar até a data chegar. */
  aAgendarAteData?: boolean;
}

const ROTEIROS: Roteiro[] = [
  { videoId: 'ZZdemo00001', tipo: 'consultoria', data: '2026-10-06T19:30:00-03:00', titulo: 'ZZ Consultoria ao vivo FICTÍCIA 1 - 06/10', duracaoMin: 95, pico: 318, picoMin: 47, fimFrac: 0.66, chatPorMin: 3, semente: 11, fonte: 'studio' },
  { videoId: 'ZZdemo00002', tipo: 'produto', data: '2026-10-08T19:30:00-03:00', titulo: 'ZZ Produto FICTÍCIO 1 - Primeiro pilar de mentira', duracaoMin: 80, pico: 104, picoMin: 58, fimFrac: 0.4, chatPorMin: 1, semente: 22, fonte: 'studio' },
  { videoId: 'ZZdemo00003', tipo: 'consultoria', data: '2026-10-13T19:30:00-03:00', titulo: 'ZZ Consultoria ao vivo FICTÍCIA 2 - 13/10', duracaoMin: 120, pico: 352, picoMin: 57, fimFrac: 0.22, chatPorMin: 2, semente: 33, fonte: 'studio' },
  { videoId: 'ZZdemo00004', tipo: 'produto', data: '2026-10-15T19:30:00-03:00', titulo: 'ZZ Produto FICTÍCIO 2 - Segundo pilar de mentira', duracaoMin: 90, pico: 141, picoMin: 62, fimFrac: 0.5, chatPorMin: 2, semente: 44, fonte: 'api' },
  { videoId: 'ZZdemo00005', tipo: 'consultoria', data: '2026-10-20T20:00:00-03:00', titulo: 'ZZ Consultoria ao vivo FICTÍCIA 3 - 20/10', duracaoMin: 110, pico: 391, picoMin: 55, fimFrac: 0.58, chatPorMin: 3, semente: 55, fonte: 'studio' },
  { videoId: 'ZZdemo00006', tipo: 'produto', data: '2026-10-22T19:30:00-03:00', titulo: 'ZZ Produto FICTÍCIO 3 - Terceiro pilar de mentira', duracaoMin: 85, pico: 187, picoMin: 60, fimFrac: 0.55, chatPorMin: 2, semente: 66, fonte: 'studio' },
  { videoId: 'ZZdemo00007', tipo: 'consultoria', data: '2026-10-27T20:00:00-03:00', titulo: null, duracaoMin: 105, pico: 446, picoMin: 54, fimFrac: 0.6, chatPorMin: 4, semente: 77, fonte: 'studio', aAgendarAteData: true },
  { videoId: 'ZZdemo00008', tipo: 'produto', data: '2026-10-29T19:30:00-03:00', titulo: 'ZZ Produto FICTÍCIO 4 - Quarto pilar de mentira', duracaoMin: 88, pico: 233, picoMin: 61, fimFrac: 0.52, chatPorMin: 2, semente: 88, fonte: 'studio' },
  { videoId: 'ZZdemo00009', tipo: 'black', data: '2026-11-03T20:00:00-03:00', titulo: 'ZZ Live da Black FICTÍCIA - a revelação de mentira', duracaoMin: 150, pico: 900, picoMin: 70, fimFrac: 0.5, chatPorMin: 6, semente: 99, fonte: 'api' },
];

function gerador(semente: number): () => number {
  let a = semente >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Curva completa de uma live fictícia: sobe rápido, chega ao pico, cai com um buraco no meio da descida. */
function curvaCompleta(r: Roteiro): MinutoLive[] {
  const rnd = gerador(r.semente);
  const buraco = Math.min(r.duracaoMin - 3, r.picoMin + Math.max(6, Math.round((r.duracaoMin - r.picoMin) * 0.4)));
  const saida: MinutoLive[] = [];
  for (let i = 0; i < r.duracaoMin; i++) {
    let v: number;
    if (i <= r.picoMin) v = r.pico * (0.04 + 0.7 * (1 - Math.exp(-i / 9)) + 0.26 * (i / r.picoMin));
    else v = r.pico - (r.pico - r.pico * r.fimFrac) * ((i - r.picoMin) / Math.max(1, r.duracaoMin - 1 - r.picoMin));
    if (i >= buraco) v -= r.pico * 0.1 * Math.min(2, i - buraco + 1) / 2 + (i > buraco + 1 ? 0 : 0);
    v *= 1 + (rnd() - 0.5) * 0.04;
    const e = i === r.picoMin ? r.pico : Math.max(1, Math.min(r.pico - 1, Math.round(v)));
    const sorteado = Math.round(rnd() * r.chatPorMin * 2 * (i < 12 ? 1.8 : 1));
    const chat = i === r.picoMin ? Math.max(sorteado, 3) : sorteado; // o minuto do pico sempre tem conversa, para a demo mostrar o filtro
    const reacoes = rnd() < 0.08 ? 1 + Math.floor(rnd() * 3) : 0;
    saida.push({ seg: i * 60, espectadores: e, chat, reacoes, origem: r.fonte });
  }
  return saida;
}

const TEXTOS_CHAT = [
  'Boa noite, pessoal (demo)', 'Quando abre a oferta? (demo)', 'O áudio está ok aqui (demo)', 'Pode repetir esse ponto? (demo)',
  'Excelente explicação (demo)', 'Qual é o valor? (demo)', 'Chegou agora, perdi algo? (demo)', 'Obrigada pela aula (demo)',
];

function chatDe(minutos: readonly MinutoLive[], semente: number): MensagemChat[] {
  const rnd = gerador(semente * 7);
  const out: MensagemChat[] = [];
  for (const m of minutos) {
    for (let k = 0; k < (m.chat ?? 0) && out.length < 5000; k++) {
      out.push({
        seg: m.seg + Math.floor(rnd() * 60), publicadoEm: null,
        texto: TEXTOS_CHAT[Math.floor(rnd() * TEXTOS_CHAT.length)],
      });
    }
  }
  return out.sort((a, b) => (a.seg ?? 0) - (b.seg ?? 0));
}

function resumoDe(minutos: readonly MinutoLive[]) {
  const m = minutos.filter((x) => x.espectadores !== null);
  if (m.length === 0) return { pico: null, picoSeg: null, salaCheiaSeg: null, ultimo: null, chat: null, reacoes: null };
  let pico = m[0];
  for (const x of m) if ((x.espectadores as number) > (pico.espectadores as number)) pico = x;
  const cheia = m.find((x) => (x.espectadores as number) >= (pico.espectadores as number) * 0.9);
  const soma = (f: (x: MinutoLive) => number | null) => minutos.reduce((s, x) => s + (f(x) ?? 0), 0);
  return {
    pico: pico.espectadores as number, picoSeg: pico.seg, salaCheiaSeg: cheia?.seg ?? null, ultimo: m[m.length - 1].espectadores as number,
    chat: soma((x) => x.chat), reacoes: soma((x) => x.reacoes),
  };
}

const DEMO_COMENTARIOS: ComentarioLive[] = [
  { publicadoEm: null, texto: 'Comentário fictício de demonstração, só para mostrar a lista.', curtidas: 2, respostas: 0 },
  { publicadoEm: null, texto: 'Outro comentário fictício, sem relação com nenhuma live real.', curtidas: 0, respostas: 1 },
  { publicadoEm: null, texto: 'Terceiro comentário fictício (demo).', curtidas: null, respostas: null },
];

export interface LivesDemo {
  lives(chave: string): Resultado<Live[]>;
  detalhe(chave: string, videoId: string): Resultado<DetalheLive>;
  importar(chave: string, videoId: string, linhas: readonly LinhaStudio[], confirmar: boolean): ResultadoLiveAcao<PreviaImportacao>;
  cadastrar(chave: string, videoId: string, tipo: TipoLive, dataPrevista: string): ResultadoLiveAcao<{ videoId: string }>;
  remover(chave: string, videoId: string): ResultadoLiveAcao<{ videoId: string }>;
}

const SEM_CHAVE = (chave: string) => `Projeto ${chave} não existe no modo demonstração.`;

export function criarLivesDemo(agora: Date): LivesDemo {
  const agoraMs = agora.getTime();
  const curvas = new Map(ROTEIROS.map((r) => [r.videoId, curvaCompleta(r)]));
  /** Linhas do Studio importadas nesta sessão (em memória). */
  const importadas = new Map<string, MinutoLive[]>();
  const cadastradas: Roteiro[] = [];
  const removidas = new Set<string>();

  const todos = () => [...ROTEIROS, ...cadastradas].filter((r) => !removidas.has(r.videoId));
  const inicioMs = (r: Roteiro) => Date.parse(r.data);
  const fimMs = (r: Roteiro) => inicioMs(r) + r.duracaoMin * 60_000;

  function situacaoDe(r: Roteiro): SituacaoLive {
    if (r.aAgendarAteData && agoraMs < inicioMs(r)) return 'a_agendar';
    if (agoraMs < inicioMs(r)) return 'em_breve';
    return agoraMs < fimMs(r) ? 'ao_vivo' : 'realizada';
  }

  /** Minutos que a tela enxerga agora: a curva toda (realizada), o começo dela (ao vivo) ou nada. */
  function minutosDe(r: Roteiro): MinutoLive[] {
    const imp = importadas.get(r.videoId);
    if (imp) return imp;
    const completa = curvas.get(r.videoId);
    if (!completa) return [];
    const s = situacaoDe(r);
    if (s === 'realizada') return completa;
    if (s === 'ao_vivo') return completa.slice(0, Math.max(1, Math.floor((agoraMs - inicioMs(r)) / 60_000) + 1)).map((m) => ({ ...m, origem: 'api' as const }));
    return [];
  }

  function liveDe(r: Roteiro): Live {
    const situacao = situacaoDe(r);
    const minutos = minutosDe(r);
    const resumo = resumoDe(minutos);
    const temStudio = minutos.length > 0 && minutos[0].origem === 'studio';
    const decorrido = Math.max(0, Math.floor((Math.min(agoraMs, fimMs(r)) - inicioMs(r)) / 1000));
    const real = situacao === 'realizada' || situacao === 'ao_vivo';
    const chatGuard = real ? chatDe(minutos, r.semente).length : null;
    return {
      videoId: r.videoId, tipo: r.tipo, dataPrevista: r.data, titulo: situacao === 'a_agendar' ? null : r.titulo, miniatura: null, situacao,
      agendadaEm: situacao === 'a_agendar' ? null : r.data, inicio: real ? r.data : null,
      fim: situacao === 'realizada' ? new Date(fimMs(r)).toISOString() : null,
      duracaoSeg: real ? (situacao === 'realizada' ? r.duracaoMin * 60 : decorrido) : null,
      views: real ? Math.round(r.pico * 4.9 * (decorrido / (r.duracaoMin * 60) > 1 ? 1 : decorrido / (r.duracaoMin * 60))) : null,
      likes: real ? Math.round(r.pico * 0.28) : null, comentarios: real ? DEMO_COMENTARIOS.length : null,
      coletadoEm: real ? new Date(Math.min(agoraMs, fimMs(r))).toISOString() : null,
      espectadoresAgora: situacao === 'ao_vivo' ? resumo.ultimo : null,
      temStudio, pico: resumo.pico, picoSeg: resumo.picoSeg, salaCheiaSeg: resumo.salaCheiaSeg, ultimoEspectadores: resumo.ultimo,
      chatTotal: resumo.chat, reacoesTotal: resumo.reacoes, chatGuardado: chatGuard,
    };
  }

  return {
    lives(chave) {
      if (chave !== CHAVE_BLACK) return { data: [], semDado: true, erro: SEM_CHAVE(chave) };
      return { data: todos().map(liveDe), semDado: false, erro: null };
    },
    detalhe(chave, videoId) {
      if (chave !== CHAVE_BLACK) return { data: DETALHE_VAZIO, semDado: true, erro: SEM_CHAVE(chave) };
      const r = todos().find((x) => x.videoId === videoId);
      if (!r) return { data: DETALHE_VAZIO, semDado: true, erro: 'Dashboard ou identificador não encontrado neste evento.' };
      const minutos = minutosDe(r);
      const real = situacaoDe(r) === 'realizada' || situacaoDe(r) === 'ao_vivo';
      const horas = Math.max(1, Math.min(12, Math.round((Math.min(agoraMs, fimMs(r)) - inicioMs(r)) / 3_600_000) + 2));
      const fotos: FotoLive[] = real
        ? Array.from({ length: horas }, (_, i) => {
          const f = (i + 1) / horas;
          return { coletadoEm: new Date(inicioMs(r) + i * 3_600_000).toISOString(), views: Math.round(r.pico * 4.9 * f), likes: Math.round(r.pico * 0.28 * f), comentarios: Math.min(DEMO_COMENTARIOS.length, i + 1) };
        })
        : [];
      return {
        data: { minutos, chat: real ? chatDe(minutos, r.semente) : [], comentarios: real ? DEMO_COMENTARIOS : [], fotos },
        semDado: minutos.length === 0, erro: null,
      };
    },
    importar(chave, videoId, linhas, confirmar) {
      if (chave !== CHAVE_BLACK) return { data: null, erro: SEM_CHAVE(chave) };
      if (!todos().some((r) => r.videoId === videoId)) return { data: null, erro: 'Esta live não está cadastrada neste evento.' };
      const resumo = resumirStudio(linhas);
      if (!resumo) return { data: null, erro: 'O banco recusou os dados (link, data ou arquivo fora do padrão). Confira e tente de novo.' };
      const atuais = importadas.get(videoId) ?? [];
      const novos: MinutoLive[] = linhas.map((l) => ({ seg: l.seg, espectadores: l.espectadores, chat: l.chat ?? 0, reacoes: l.reacoes ?? 0, origem: 'studio' }));
      const iguais = atuais.length === novos.length && atuais.every((a, i) => a.seg === novos[i].seg && a.espectadores === novos[i].espectadores && a.chat === novos[i].chat && a.reacoes === novos[i].reacoes);
      const alteradas = iguais ? 0 : Math.max(novos.length, atuais.length);
      if (confirmar && !iguais) importadas.set(videoId, novos);
      return {
        data: { linhas: resumo.linhas, pico: resumo.pico, picoSeg: resumo.picoSeg, duracaoSeg: resumo.duracaoSeg, existentes: atuais.length, alteradas, gravado: confirmar && !iguais },
        erro: null,
      };
    },
    cadastrar(chave, videoId, tipo, dataPrevista) {
      if (chave !== CHAVE_BLACK) return { data: null, erro: SEM_CHAVE(chave) };
      if (ROTEIROS.some((r) => r.videoId === videoId && !removidas.has(videoId)) || cadastradas.some((r) => r.videoId === videoId)) {
        return { data: { videoId }, erro: null };
      }
      removidas.delete(videoId);
      cadastradas.push({ videoId, tipo, data: dataPrevista, titulo: null, duracaoMin: 90, pico: 100, picoMin: 45, fimFrac: 0.5, chatPorMin: 1, semente: 5, fonte: 'api', aAgendarAteData: true });
      return { data: { videoId }, erro: null };
    },
    remover(chave, videoId) {
      if (chave !== CHAVE_BLACK) return { data: null, erro: SEM_CHAVE(chave) };
      if (!todos().some((r) => r.videoId === videoId)) return { data: null, erro: 'Esta live não está cadastrada neste evento.' };
      removidas.add(videoId);
      return { data: { videoId }, erro: null };
    },
  };
}

export { minutoDe };
