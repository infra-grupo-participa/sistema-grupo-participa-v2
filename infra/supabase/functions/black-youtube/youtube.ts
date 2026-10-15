// black-youtube: tradução das respostas da YouTube Data API v3 para o que as funções dados.black_live_* esperam
// (migration 20261015220000). Puro (sem Deno, sem rede, sem banco): testado em youtube.test.ts, com fixtures escritas à mão
// no formato da API (nenhuma resposta real, nenhum nome de pessoa).
// Só entram aqui as rotas videos.list, commentThreads.list e liveChat/messages. Nada de search (100 unidades de cota).

// deno-lint-ignore no-explicit-any
type Json = any;

export type Situacao = "realizada" | "ao_vivo" | "em_breve";

export interface ItemVideo {
  video_id: string;
  encontrado: boolean;
  titulo: string | null;
  miniatura: string | null;
  situacao: Situacao;
  agendada_em: string | null;
  inicio: string | null;
  fim: string | null;
  duracao_seg: number | null;
  views: number | null;
  likes: number | null;
  comentarios: number | null;
  espectadores_agora: number | null;
  live_chat_id: string | null;
}

const API = "https://www.googleapis.com/youtube/v3";

/** a chave vai na URL: quem chama nunca registra a URL (só o status HTTP) */
export const urlVideos = (ids: string[], chave: string) =>
  `${API}/videos?part=snippet,liveStreamingDetails,statistics,status&maxResults=50&id=${ids.map(encodeURIComponent).join(",")}&key=${encodeURIComponent(chave)}`;

export const urlComentarios = (videoId: string, chave: string, pagina?: string | null) =>
  `${API}/commentThreads?part=snippet&maxResults=100&order=time&textFormat=plainText&videoId=${encodeURIComponent(videoId)}` +
  `${pagina ? `&pageToken=${encodeURIComponent(pagina)}` : ""}&key=${encodeURIComponent(chave)}`;

export const urlChat = (liveChatId: string, chave: string, pagina?: string | null) =>
  `${API}/liveChat/messages?part=snippet&maxResults=2000&liveChatId=${encodeURIComponent(liveChatId)}` +
  `${pagina ? `&pageToken=${encodeURIComponent(pagina)}` : ""}&key=${encodeURIComponent(chave)}`;

const inteiro = (v: unknown): number | null => {
  const n = typeof v === "string" ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) && n >= 0 ? Math.trunc(n) : null;
};
const data = (v: unknown): string | null => {
  if (typeof v !== "string") return null;
  const t = Date.parse(v);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
};

/** liveBroadcastContent: upcoming → em_breve, live → ao_vivo, none → realizada */
export function situacaoDe(liveBroadcastContent: unknown): Situacao {
  if (liveBroadcastContent === "live") return "ao_vivo";
  if (liveBroadcastContent === "upcoming") return "em_breve";
  return "realizada";
}

/** miniatura: a maior que a API devolveu, na ordem maxres, standard, high, medium, default */
function miniatura(thumbs: Json): string | null {
  for (const k of ["maxres", "standard", "high", "medium", "default"]) {
    const u = thumbs?.[k]?.url;
    if (typeof u === "string" && u.startsWith("https://")) return u;
  }
  return null;
}

export function itemDoVideo(v: Json): ItemVideo {
  const sn = v?.snippet ?? {};
  const ls = v?.liveStreamingDetails ?? {};
  const st = v?.statistics ?? {};
  const inicio = data(ls.actualStartTime);
  const fim = data(ls.actualEndTime);
  const situacao = situacaoDe(sn.liveBroadcastContent);
  return {
    video_id: String(v.id),
    encontrado: true,
    titulo: typeof sn.title === "string" ? sn.title : null,
    miniatura: miniatura(sn.thumbnails),
    situacao,
    agendada_em: data(ls.scheduledStartTime),
    inicio,
    fim,
    duracao_seg: inicio && fim ? Math.max(0, Math.round((Date.parse(fim) - Date.parse(inicio)) / 1000)) : null,
    views: inteiro(st.viewCount),
    likes: inteiro(st.likeCount),
    comentarios: inteiro(st.commentCount),
    espectadores_agora: situacao === "ao_vivo" ? inteiro(ls.concurrentViewers) : null,
    live_chat_id: typeof ls.activeLiveChatId === "string" ? ls.activeLiveChatId : null,
  };
}

/** o que a API não devolveu (privado, removido, id errado) fica "não encontrado": a função do banco decide o que fazer */
export function itensDaResposta(ids: string[], resposta: Json): ItemVideo[] {
  const achados = new Map<string, ItemVideo>();
  for (const v of resposta?.items ?? []) if (v?.id) achados.set(String(v.id), itemDoVideo(v));
  return ids.map((id) =>
    achados.get(id) ?? {
      video_id: id, encontrado: false, titulo: null, miniatura: null, situacao: "em_breve", agendada_em: null, inicio: null,
      fim: null, duracao_seg: null, views: null, likes: null, comentarios: null, espectadores_agora: null, live_chat_id: null,
    }
  );
}

/** minuto da amostra, em segundos desde o início real da live, arredondado para baixo ao minuto (nunca negativo) */
export function segDoMinuto(agoraMs: number, inicioIso: string): number | null {
  const ini = Date.parse(inicioIso);
  if (Number.isNaN(ini)) return null;
  return Math.max(0, Math.floor((agoraMs - ini) / 60_000) * 60);
}

export interface MensagemChat { msg_id: string; seg: number; publicado_em: string; texto: string }

/**
 * Só mensagem de texto é guardada (textMessageEvent); super chat, entrada de membro, exclusão e afins ficam de fora.
 * seg = segundos desde o início real da live (negativo = antes de começar, fica no banco mas fora da curva).
 * Sem autor: nem displayName, nem channelId, URL do canal ou foto. O desenho aprovado guarda só o texto, e o texto é apagado
 * 90 dias depois da Black (migration 20261015230000).
 */
export function mensagensDoChat(resposta: Json, inicioIso: string): MensagemChat[] {
  const ini = Date.parse(inicioIso);
  if (Number.isNaN(ini)) return [];
  const saida: MensagemChat[] = [];
  for (const it of resposta?.items ?? []) {
    const sn = it?.snippet;
    if (sn?.type !== "textMessageEvent" || !it?.id) continue;
    const quando = Date.parse(sn.publishedAt);
    const texto = sn.textMessageDetails?.messageText ?? sn.displayMessage;
    if (Number.isNaN(quando) || typeof texto !== "string" || texto === "") continue;
    saida.push({
      msg_id: String(it.id),
      seg: Math.floor((quando - ini) / 1000),
      publicado_em: new Date(quando).toISOString(),
      texto,
    });
  }
  return saida;
}

/** Comentário do vídeo, sem autor (mesma regra do chat). */
export interface ComentarioVideo { comment_id: string; publicado_em: string; texto: string; curtidas: number; respostas: number }

export function comentariosDaResposta(resposta: Json): ComentarioVideo[] {
  const saida: ComentarioVideo[] = [];
  for (const th of resposta?.items ?? []) {
    const topo = th?.snippet?.topLevelComment;
    const sn = topo?.snippet;
    const quando = data(sn?.publishedAt);
    const texto = sn?.textOriginal ?? sn?.textDisplay;
    if (!topo?.id || !quando || typeof texto !== "string" || texto === "") continue;
    saida.push({
      comment_id: String(topo.id),
      publicado_em: quando,
      texto,
      curtidas: inteiro(sn.likeCount) ?? 0,
      respostas: inteiro(th.snippet?.totalReplyCount) ?? 0,
    });
  }
  return saida;
}
