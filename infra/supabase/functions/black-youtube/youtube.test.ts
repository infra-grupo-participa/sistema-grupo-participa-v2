// Testes de youtube.ts. Rodar: deno test infra/supabase/functions/black-youtube/youtube.test.ts
// Fixtures escritas à mão no formato da YouTube Data API v3 (nenhuma resposta real, nenhum nome de pessoa).
import assert from "node:assert/strict";
import {
  comentariosDaResposta, itemDoVideo, itensDaResposta, mensagensDoChat, segDoMinuto, situacaoDe, urlChat, urlComentarios, urlVideos,
} from "./youtube.ts";

const ENCERRADA = {
  id: "AAAAAAAAAAA",
  snippet: { title: "Live encerrada", liveBroadcastContent: "none", thumbnails: { default: { url: "https://i.ytimg.com/d.jpg" }, high: { url: "https://i.ytimg.com/h.jpg" } } },
  liveStreamingDetails: { actualStartTime: "2026-10-06T22:32:45Z", actualEndTime: "2026-10-07T00:07:26Z", scheduledStartTime: "2026-10-06T22:30:00Z" },
  statistics: { viewCount: "1749", likeCount: "105", commentCount: "3" },
};
const AGENDADA = {
  id: "BBBBBBBBBBB",
  snippet: { title: "Live agendada", liveBroadcastContent: "upcoming", thumbnails: {} },
  liveStreamingDetails: { scheduledStartTime: "2026-10-20T23:00:00Z", activeLiveChatId: "CHAT-1" },
  statistics: { viewCount: "0", likeCount: "0", commentCount: "0" },
};
const NO_AR = {
  id: "CCCCCCCCCCC",
  snippet: { title: "Live no ar", liveBroadcastContent: "live", thumbnails: { maxres: { url: "https://i.ytimg.com/m.jpg" } } },
  liveStreamingDetails: { actualStartTime: "2026-10-15T22:33:00Z", scheduledStartTime: "2026-10-15T22:30:00Z", concurrentViewers: "187", activeLiveChatId: "CHAT-2" },
  statistics: { viewCount: "300", likeCount: "12" },
};

Deno.test("situação: upcoming, live e none", () => {
  assert.equal(situacaoDe("upcoming"), "em_breve");
  assert.equal(situacaoDe("live"), "ao_vivo");
  assert.equal(situacaoDe("none"), "realizada");
});

Deno.test("vídeo encerrado: duração do início real ao fim real, sem espectadores agora, miniatura maior disponível", () => {
  const i = itemDoVideo(ENCERRADA);
  assert.equal(i.situacao, "realizada");
  assert.equal(i.duracao_seg, 5681); // 1h34m41s
  assert.equal(i.espectadores_agora, null);
  assert.equal(i.miniatura, "https://i.ytimg.com/h.jpg");
  assert.deepEqual([i.views, i.likes, i.comentarios], [1749, 105, 3]);
  assert.equal(i.live_chat_id, null);
});

Deno.test("vídeo agendado: sem início, com chat; sem miniatura vira nulo", () => {
  const i = itemDoVideo(AGENDADA);
  assert.equal(i.situacao, "em_breve");
  assert.equal(i.inicio, null);
  assert.equal(i.duracao_seg, null);
  assert.equal(i.miniatura, null);
  assert.equal(i.agendada_em, "2026-10-20T23:00:00.000Z");
  assert.equal(i.live_chat_id, "CHAT-1");
});

Deno.test("vídeo no ar: concurrentViewers vira número; contagem ausente vira nulo (não zero)", () => {
  const i = itemDoVideo(NO_AR);
  assert.equal(i.situacao, "ao_vivo");
  assert.equal(i.espectadores_agora, 187);
  assert.equal(i.comentarios, null);
  assert.equal(i.miniatura, "https://i.ytimg.com/m.jpg");
});

Deno.test("itensDaResposta mantém a ordem pedida e marca o que a API não devolveu", () => {
  const itens = itensDaResposta(["BBBBBBBBBBB", "ZZZZZZZZZZZ", "AAAAAAAAAAA"], { items: [ENCERRADA, AGENDADA] });
  assert.deepEqual(itens.map((i) => [i.video_id, i.encontrado]), [["BBBBBBBBBBB", true], ["ZZZZZZZZZZZ", false], ["AAAAAAAAAAA", true]]);
});

Deno.test("segDoMinuto arredonda para baixo ao minuto e não passa de zero", () => {
  const ini = "2026-10-15T22:33:00Z";
  assert.equal(segDoMinuto(Date.parse("2026-10-15T22:33:59Z"), ini), 0);
  assert.equal(segDoMinuto(Date.parse("2026-10-15T22:35:01Z"), ini), 120);
  assert.equal(segDoMinuto(Date.parse("2026-10-15T22:30:00Z"), ini), 0);
  assert.equal(segDoMinuto(Date.now(), "lixo"), null);
});

Deno.test("chat: só textMessageEvent, seg em segundos desde o início (negativo antes), sem autor", () => {
  const resp = {
    items: [
      { id: "m1", snippet: { type: "textMessageEvent", publishedAt: "2026-10-15T22:33:10Z", textMessageDetails: { messageText: "oi" } }, authorDetails: { displayName: "Fulano de Teste", channelId: "UC-NAO-GUARDAR" } },
      { id: "m2", snippet: { type: "textMessageEvent", publishedAt: "2026-10-15T22:32:50Z", displayMessage: "antes" }, authorDetails: { displayName: "Ciclana de Teste" } },
      { id: "m3", snippet: { type: "superChatEvent", publishedAt: "2026-10-15T22:34:00Z", displayMessage: "R$ 5" }, authorDetails: { displayName: "Outro" } },
      { id: "m4", snippet: { type: "messageDeletedEvent", publishedAt: "2026-10-15T22:34:00Z" } },
      { id: "m5", snippet: { type: "textMessageEvent", publishedAt: "2026-10-15T22:34:00Z", textMessageDetails: { messageText: "" } } },
    ],
  };
  const m = mensagensDoChat(resp, "2026-10-15T22:33:00Z");
  assert.deepEqual(m.map((x) => [x.msg_id, x.seg, x.texto]), [["m1", 10, "oi"], ["m2", -10, "antes"]]);
  assert.deepEqual(Object.keys(m[0]).sort(), ["msg_id", "publicado_em", "seg", "texto"]);
  assert.equal(JSON.stringify(m).includes("UC-NAO-GUARDAR"), false);
  assert.equal(JSON.stringify(m).includes("Fulano de Teste"), false);
});

Deno.test("comentários: texto original, curtidas e respostas; item sem texto é ignorado", () => {
  const resp = {
    items: [
      { snippet: { totalReplyCount: 2, topLevelComment: { id: "c1", snippet: { publishedAt: "2026-10-15T23:00:00Z", textOriginal: "ótima live", textDisplay: "<b>ótima live</b>", authorDisplayName: "Fulano de Teste", likeCount: 4 } } } },
      { snippet: { totalReplyCount: 0, topLevelComment: { id: "c2", snippet: { publishedAt: "2026-10-15T23:01:00Z" } } } },
    ],
  };
  const c = comentariosDaResposta(resp);
  assert.equal(c.length, 1);
  assert.deepEqual([c[0].comment_id, c[0].texto, c[0].curtidas, c[0].respostas], ["c1", "ótima live", 4, 2]);
  assert.deepEqual(Object.keys(c[0]).sort(), ["comment_id", "curtidas", "publicado_em", "respostas", "texto"]);
  assert.equal(JSON.stringify(c).includes("Fulano de Teste"), false);
});

Deno.test("URLs: só as rotas permitidas (nada de search), id e token codificados", () => {
  for (const u of [urlVideos(["A", "B"], "K"), urlComentarios("V", "K", "p=1"), urlChat("C", "K", "t&x")]) {
    assert.equal(u.includes("/search"), false);
    assert.ok(u.startsWith("https://www.googleapis.com/youtube/v3/"));
  }
  assert.ok(urlVideos(["A", "B"], "K").includes("id=A,B"));
  assert.ok(urlChat("C", "K", "t&x").includes("pageToken=t%26x"));
});
