// Carga sintética de webhooks no formato do ActiveCampaign (x-www-form-urlencoded).
// Uso: CRM_WEBHOOK_SECRET=... deno run --allow-net --allow-env infra/scripts/carga-webhook-ac.ts \
//        --url <url> --total 200 --por-segundo 20 [--prefixo carga-teste] [--sei-que-e-producao]
// O segredo vem SÓ da env CRM_WEBHOOK_SECRET (header x-webhook-secret); nunca é impresso.
// Para sozinho se >5% de respostas não-200 numa janela de 10 s.
import { parseArgs } from "jsr:@std/cli@1/parse-args";

const a = parseArgs(Deno.args, {
  string: ["url", "total", "por-segundo", "prefixo"],
  boolean: ["sei-que-e-producao"],
  default: { prefixo: "carga-teste" },
});
const fim = (msg: string): never => {
  console.error(msg);
  Deno.exit(2);
};
const url = a.url ?? fim("faltou --url");
const total = Number(a.total);
const porSeg = Number(a["por-segundo"] ?? 10);
const prefixo = a.prefixo as string;
if (!Number.isInteger(total) || total < 1) fim("--total inválido");
if (!(porSeg > 0)) fim("--por-segundo inválido");
if (total > 500 && url.includes("supabase.co") && !a["sei-que-e-producao"]) {
  fim("RECUSADO: --total > 500 contra supabase.co exige --sei-que-e-producao");
}
const segredo = Deno.env.get("CRM_WEBHOOK_SECRET") ?? "";

const JANELA_MS = 10_000, LIMITE = 0.05, MIN_AMOSTRA = 20;
const porStatus = new Map<string, number>();
const lat: number[] = [];
const janela: { t: number; ok: boolean }[] = [];
let enviados = 0, parou = false;

const pad = (n: number) => String(n).padStart(2, "0");
function agora() {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

async function um(i: number) {
  const corpo = new URLSearchParams({
    type: "subscribe",
    date_time: agora(),
    "contact[id]": `${prefixo}-${i}`,
    "contact[email]": `${prefixo}+${i}@exemplo.invalid`,
    "contact[first_name]": `Carga${i}`,
    list: "1",
    tag: "carga-teste",
  });
  const t0 = performance.now();
  let chave: string;
  try {
    const r = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", ...(segredo ? { "x-webhook-secret": segredo } : {}) },
      body: corpo,
    });
    await r.body?.cancel();
    chave = String(r.status);
  } catch {
    chave = "erro_rede";
  }
  const ms = performance.now() - t0;
  lat.push(ms);
  porStatus.set(chave, (porStatus.get(chave) ?? 0) + 1);
  const agoraMs = Date.now();
  janela.push({ t: agoraMs, ok: chave === "200" });
  while (janela.length && janela[0].t < agoraMs - JANELA_MS) janela.shift();
  if (janela.length >= MIN_AMOSTRA && janela.filter((x) => !x.ok).length / janela.length > LIMITE) parou = true;
}

const pend: Promise<void>[] = [];
const inicio = performance.now();
for (let i = 1; i <= total && !parou; i++) {
  pend.push(um(i));
  enviados++;
  const alvo = inicio + (i / porSeg) * 1000;
  const espera = alvo - performance.now();
  if (espera > 0) await new Promise((r) => setTimeout(r, espera));
}
await Promise.all(pend);

const pct = (p: number) => {
  if (!lat.length) return "n/a";
  const s = [...lat].sort((x, y) => x - y);
  return `${s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)].toFixed(0)} ms`;
};
if (parou) console.error(`PARADO: >${LIMITE * 100}% não-200 em janela de ${JANELA_MS / 1000}s (mínimo ${MIN_AMOSTRA} amostras)`);
console.log(`enviados: ${enviados} de ${total}`);
console.log(`status: ${JSON.stringify(Object.fromEntries([...porStatus].sort()))}`);
console.log(`latência p50=${pct(50)} p95=${pct(95)} p99=${pct(99)}`);
if (parou) Deno.exit(1);
