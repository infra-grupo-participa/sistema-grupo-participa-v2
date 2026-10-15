// black-youtube: coleta da aba "Lives" do Dashboard da Black Friday (migration 20261015220000; cron em 20261015220100).
// Quem chama: o cron black-youtube, todo minuto, pelo ops.cron_post, com o header x-sync-chave (= Vault dados_black_youtube_chave).
// O cron só dispara quando dados.black_live_pede_chamada() é verdadeira: a cada 10 minutos, e todo minuto enquanto alguma live
// está na janela (15 min antes do horário previsto até 3 h depois, ou enquanto a última leitura disse "ao_vivo").
// A Edge entra no banco como postgres (SUPABASE_DB_URL) e só usa as funções internas dados.black_live_*.
// Chave da YouTube Data API: Vault dados_black_youtube_api_key (lida por dados.black_youtube_credenciais). Nunca no código,
// nunca em log, nunca na resposta. Rotas usadas: videos.list, commentThreads.list e liveChat/messages. Nada de search.
//
// O que faz em cada chamada:
//   1. videos.list das lives ativas (todas a cada 10 min; fora desse minuto, só as que estão na janela): título, miniatura,
//      situação, horários, views, likes, comentários e, no ar, concurrentViewers. Grava em black_lives e uma foto por hora.
//   2. No ar (ou que acabou de sair do ar): grava o espectador do minuto (origem api) e lê o chat com o pageToken guardado.
//   3. Uma vez por hora por live (menos as agendadas, que não têm comentário): commentThreads (comentários do vídeo).
// Sem autor: chat e comentários guardam só o texto (nem displayName). Texto apagado 90 dias depois da Black (20261015230000).
// Trava de concorrência: advisory lock de sessão; rodada que encontra outra em andamento responde {"ocupado":true} sem chamar a API.
import postgres from "npm:postgres@3.4.4";
import {
  comentariosDaResposta, type ComentarioVideo, type ItemVideo, itensDaResposta, mensagensDoChat, type MensagemChat, segDoMinuto,
  urlChat, urlComentarios, urlVideos,
} from "./youtube.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const ORCAMENTO_MS = 100_000; // não começa leitura nova depois disso (a Edge morre em 150 s)
const PEDIDO_MAX_MS = 15_000;
const CRED_TTL_MS = 600_000;
const PAGINAS_CHAT_MAX = 3; // 3 x 2000 mensagens por minuto é muito além do que uma sala dessas escreve
const PAGINAS_COMENTARIOS_MAX = 3;
const TRAVA_ID = 20261015; // chave do advisory lock da coleta da Black (só esta Edge usa)

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });

function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

let credCache: { chave: string | null; apiKey: string | null; ate: number } | null = null;
async function credenciais() {
  if (credCache && credCache.ate > Date.now()) return credCache;
  const [r] = await sql`select chave, api_key from dados.black_youtube_credenciais()`;
  credCache = { chave: r?.chave ?? null, apiKey: r?.api_key ?? null, ate: Date.now() + CRED_TTL_MS };
  return credCache;
}

interface Alvo {
  video_id: string;
  situacao: string;
  na_janela: boolean;
  live_chat_id: string | null;
  chat_page_token: string | null;
  comentarios_devidos: boolean;
}

/** GET na API; devolve o corpo ou o status. Nunca registra a URL (leva a chave) nem o corpo de erro. */
async function ler(url: string): Promise<{ ok: true; corpo: unknown } | { ok: false; status: number }> {
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(PEDIDO_MAX_MS) });
    if (!r.ok) {
      await r.body?.cancel();
      return { ok: false, status: r.status };
    }
    return { ok: true, corpo: await r.json() };
  } catch {
    return { ok: false, status: 0 };
  }
}

async function lerChat(item: ItemVideo, alvo: Alvo, ate: number, apiKey: string) {
  const chatId = item.live_chat_id ?? alvo.live_chat_id;
  if (!chatId || !item.inicio) return { chatId, mensagens: null as MensagemChat[] | null, token: null as string | null, falha: chatId ? null : "sem chat" };
  // o token só vale para o mesmo chat; se o chat mudou, começa do zero (o banco também zera)
  let token = chatId === alvo.live_chat_id ? alvo.chat_page_token : null;
  const mensagens: MensagemChat[] = [];
  for (let p = 0; p < PAGINAS_CHAT_MAX && Date.now() < ate; p++) {
    const r = await ler(urlChat(chatId, apiKey, token));
    if (!r.ok) return { chatId, mensagens: mensagens.length ? mensagens : null, token: p > 0 ? token : null, falha: `HTTP ${r.status}`, parcial: p > 0 };
    // deno-lint-ignore no-explicit-any
    const corpo = r.corpo as any;
    const itens = Array.isArray(corpo?.items) ? corpo.items : [];
    mensagens.push(...mensagensDoChat(corpo, item.inicio));
    if (typeof corpo?.nextPageToken === "string") token = corpo.nextPageToken;
    if (itens.length < 2000) break; // página não cheia: não há mais nada agora
  }
  return { chatId, mensagens, token, falha: null };
}

async function lerComentarios(videoId: string, ate: number, apiKey: string): Promise<{ itens: ComentarioVideo[]; falha: string | null }> {
  const itens: ComentarioVideo[] = [];
  let pagina: string | null = null;
  for (let p = 0; p < PAGINAS_COMENTARIOS_MAX && Date.now() < ate; p++) {
    const r = await ler(urlComentarios(videoId, apiKey, pagina));
    if (!r.ok) return { itens, falha: `HTTP ${r.status}` }; // 403 = comentários desligados no vídeo
    // deno-lint-ignore no-explicit-any
    const corpo = r.corpo as any;
    itens.push(...comentariosDaResposta(corpo));
    pagina = typeof corpo?.nextPageToken === "string" ? corpo.nextPageToken : null;
    if (!pagina) break;
  }
  return { itens, falha: null };
}

/** Uma rodada de coleta. Só roda com a trava de concorrência na mão (ver Deno.serve). */
async function coletar(cred: { chave: string | null; apiKey: string | null }): Promise<Response> {
  const apiKey = cred.apiKey!;
  const agora = Date.now();
  const ate = agora + ORCAMENTO_MS;
  const alvos: Alvo[] = (await sql`select dados.black_live_alvos() as a`)[0]?.a ?? [];
  // minuto cheio (UTC % 10 = 0): todas as lives. Nos outros minutos o cron só chama por causa de live na janela.
  const cheio = new Date(agora).getUTCMinutes() % 10 === 0;
  const lidos = alvos.filter((a) => cheio || a.na_janela);
  if (!lidos.length) return json({ lives: 0 });

  const v = await ler(urlVideos(lidos.map((a) => a.video_id), apiKey));
  if (!v.ok) return json({ erro: "videos.list", status: v.status }, 502);
  const itens = itensDaResposta(lidos.map((a) => a.video_id), v.corpo);
  const atualizado = (await sql`select dados.black_live_atualizar(${sql.json(itens as never)}) as r`)[0]?.r;

  const resumo = { lives: itens.length, atualizado, no_ar: 0, mensagens_novas: 0, comentarios: 0, falhas: [] as string[] };
  for (const item of itens) {
    const alvo = lidos.find((a) => a.video_id === item.video_id)!;
    if (!item.encontrado) continue;

    // Espectadores e chat: no ar, ou na chamada em que a live acabou de sair do ar (última leitura do chat)
    const noAr = item.situacao === "ao_vivo";
    const acabou = alvo.situacao === "ao_vivo" && item.situacao === "realizada";
    if ((noAr || acabou) && item.inicio && Date.now() < ate) {
      if (noAr) resumo.no_ar++;
      const seg = noAr && item.espectadores_agora !== null ? segDoMinuto(Date.now(), item.inicio) : null;
      const chat = await lerChat(item, alvo, ate, apiKey);
      if (chat.falha && chat.falha !== "sem chat") resumo.falhas.push(`chat ${item.video_id}: ${chat.falha}`);
      // só avança o estado do chat (id e token) se a leitura deu certo; senão grava só o espectador
      const chatOk = chat.falha === null && chat.chatId;
      if (seg !== null || (chat.mensagens && chat.mensagens.length) || chatOk) {
        const g = (await sql`
          select dados.black_live_gravar_amostra(
            ${item.video_id}::text, ${seg}::integer, ${noAr ? item.espectadores_agora : null}::integer,
            ${chat.mensagens ? sql.json(chat.mensagens as never) : null}::jsonb,
            ${chatOk ? chat.token : null}::text, ${chatOk ? chat.chatId : null}::text) as r`)[0]?.r;
        resumo.mensagens_novas += Number(g?.mensagens_novas ?? 0);
      }
    }

    // Comentários do vídeo: uma vez por hora por live (alvo.comentarios_devidos vem do banco)
    if (alvo.comentarios_devidos && Date.now() < ate) {
      // live agendada não tem comentário (a API devolve 403): só marca a leitura, sem gastar cota
      const c = item.situacao === "em_breve" ? { itens: [] as ComentarioVideo[], falha: null } : await lerComentarios(item.video_id, ate, apiKey);
      if (c.falha) resumo.falhas.push(`comentarios ${item.video_id}: ${c.falha}`);
      // grava mesmo vazio/com falha: marca a leitura e só tenta de novo em uma hora (não gasta cota por minuto)
      const g = (await sql`select dados.black_live_gravar_comentarios(${item.video_id}::text, ${sql.json(c.itens as never)}) as r`)[0]?.r;
      resumo.comentarios += Number(g?.comentarios ?? 0);
    }
  }
  return json(resumo);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erro: "método" }, 405);
  let cred;
  try {
    cred = await credenciais();
  } catch {
    return json({ erro: "banco" }, 503);
  }
  const recebida = req.headers.get("x-sync-chave") ?? "";
  if (!cred.chave || !igual(recebida, cred.chave)) return json({ erro: "chave" }, 401);
  if (!cred.apiKey) return json({ erro: "sem chave do YouTube no Vault" }, 503);

  // Trava de concorrência: o cron dispara todo minuto e a rodada pode passar de 60 s (pedidos de 15 s, até 100 s de orçamento).
  // Duas rodadas ao mesmo tempo gastariam a cota em dobro e leriam o mesmo pageToken do chat. Advisory lock de SESSÃO numa
  // conexão reservada: solta sozinho se a Edge morrer (a conexão cai). Quem não pega a trava sai sem chamar a API.
  let trava;
  let pegou = false;
  try {
    trava = await sql.reserve();
    const [t] = await trava`select pg_try_advisory_lock(${TRAVA_ID}::bigint) as ok`;
    pegou = t?.ok === true;
  } catch {
    trava?.release();
    return json({ erro: "banco" }, 503);
  }
  if (!pegou) {
    trava.release();
    return json({ ocupado: true });
  }
  try {
    return await coletar(cred);
  } finally {
    await trava`select pg_advisory_unlock(${TRAVA_ID}::bigint)`.catch(() => {});
    trava.release();
  }
});
