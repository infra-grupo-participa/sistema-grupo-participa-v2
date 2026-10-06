// trafego-meta: coleta diária do Meta Ads da Central do Tráfego (migration 20261005r). NASCE DESLIGADA: nenhum cron
// chama esta Edge até o Victor decidir (como ligar: bloco LIGAR da migration e docs/central-de-dados.md, seção Tráfego).
// Quem chama: o cron trafego-meta, pelo ops.cron_post (regra 11 do CLAUDE.md), com o header x-sync-chave
// (= Vault trafego_coleta_chave). A Edge entra no banco como postgres (SUPABASE_DB_URL), pega as contas Meta ativas e o
// token de cada uma (mkt_trafego.meta_contas: Vault meta_ads_token ou o segredo da conta em contas.token_vault), lê a
// Graph API (só leitura) e grava pelas funções de entrada da 20261005p (upsert idempotente: rodar de novo não duplica).
// Corpo opcional: {"dias": n} (dias completos para trás além de hoje; padrão mkt_trafego.coleta_config meta_dias),
// {"so_hoje": true}, ou {"de": "AAAA-MM-DD", "ate": "AAAA-MM-DD"} (recarga, até 92 dias).
// Nunca registra token nem URL; a falha de cada conta vai para mkt_trafego.coletas com um código curto.
import postgres from 'npm:postgres@3.4.4';
import { META_API_VERSAO_PADRAO, coletarMeta, hojeSaoPaulo, periodo, type ContaMeta } from './meta.ts';

const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 2, prepare: false, idle_timeout: 20 });
const ORCAMENTO_MS = 110_000; // não começa conta nova depois disso (a Edge morre em 150 s)

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });

function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ erro: 'método' }, 405);
  let chave: string | null;
  try {
    [{ chave }] = await sql`select mkt_trafego.coleta_chave() as chave`;
  } catch {
    return json({ erro: 'banco' }, 503);
  }
  const recebida = req.headers.get('x-sync-chave') ?? '';
  if (!chave || !igual(recebida, chave)) return json({ erro: 'chave' }, 401);

  const corpo = await req.json().catch(() => ({})) as { dias?: number; so_hoje?: boolean; de?: string; ate?: string };
  const [{ p }] = await sql`select mkt_trafego.coleta_parametros() as p`;
  const versao = /^v\d{1,3}\.\d$/.test(p?.meta_api_versao ?? '') ? p.meta_api_versao : META_API_VERSAO_PADRAO;
  const dias = corpo.so_hoje ? 0 : Number(corpo.dias ?? p?.meta_dias ?? 3);
  const per = periodo(hojeSaoPaulo(new Date()), dias, corpo.de, corpo.ate);
  if (!per) return json({ erro: 'periodo' }, 400);

  const contas: ContaMeta[] = (await sql`select conta_externa, nome, token, token_origem from mkt_trafego.meta_contas()`)
    .map((r) => ({ conta_externa: String(r.conta_externa), nome: String(r.nome), token: r.token ?? null, token_origem: String(r.token_origem) }));

  const resultado = await coletarMeta(contas, {
    buscar: (url, init) => fetch(url, { ...init, signal: AbortSignal.timeout(30_000) }),
    versao,
    de: per.de,
    ate: per.ate,
    ate_ms: Date.now() + ORCAMENTO_MS,
    receberCampanhas: async (l) => (await sql`select public.trafego_campanhas_receber(${JSON.stringify(l)}::jsonb) as r`)[0].r,
    receberDesempenho: async (l) => (await sql`select public.trafego_desempenho_receber(${JSON.stringify(l)}::jsonb) as r`)[0].r,
  });
  const ok = resultado.contas.every((c) => c.ok) && resultado.puladas === 0;
  const erro = ok ? null : resultado.contas.filter((c) => !c.ok).map((c) => `${c.conta}: ${c.erro}`).join('; ').slice(0, 480) || 'contas puladas';
  await sql`select mkt_trafego.coleta_registrar('meta', ${ok}, ${JSON.stringify({ ...resultado, versao, contas_lidas: contas.length })}::jsonb, ${erro})`;
  return json({ ok, ...resultado });
});
