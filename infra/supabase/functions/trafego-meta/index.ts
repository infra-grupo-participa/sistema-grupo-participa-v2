// trafego-meta: coleta diária do Meta Ads da Central do Tráfego (migration 20261006i). NASCE DESLIGADA: nenhum cron
// chama esta Edge até o Victor decidir (como ligar: bloco LIGAR da migration e docs/central-de-dados.md, seção Tráfego).
// Quem chama: o cron trafego-meta, pelo ops.cron_post (regra 11 do CLAUDE.md), com o header x-sync-chave
// (= Vault trafego_coleta_chave). A Edge entra no banco como postgres (SUPABASE_DB_URL), pega as contas Meta ativas e o
// token de cada uma (mkt_trafego.meta_contas: Vault meta_ads_token ou o segredo da conta em contas.token_vault), lê a
// Graph API (só leitura) e grava pelas funções de entrada da 20261006g (upsert idempotente: rodar de novo não duplica).
// Corpo opcional: {"dias": n} (dias completos para trás além de hoje; padrão mkt_trafego.coleta_config meta_dias),
// {"so_hoje": true}, ou {"de": "AAAA-MM-DD", "ate": "AAAA-MM-DD"} (recarga, até 92 dias).
// Nunca registra token nem URL; a falha de cada conta vai para mkt_trafego.coletas com um código curto.
import postgres from 'npm:postgres@3.4.4';
import { CAMPOS_DISTRIBUICAO, META_API_VERSAO_PADRAO, coletarMeta, hojeSaoPaulo, lerPaginas, paraDesempenho, periodo, type ContaMeta } from './meta.ts';
import { coletarAnuncios, contasDaFlag } from './anuncios.ts';

const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 2, prepare: false, idle_timeout: 20 });
const ORCAMENTO_MS = 110_000; // não começa conta nova depois disso (a Edge morre em 150 s)
// 20261012120000: a fase de anúncios tem orçamento PRÓPRIO, contado do início da requisição: termina até
// LIMITE_EDGE_MS - RESERVA_REGISTRO_MS (125 s), para sobrar tempo ao coleta_registrar da rodada de campanha e à resposta.
const LIMITE_EDGE_MS = 150_000;
const RESERVA_REGISTRO_MS = 25_000;
// 20261012120000: miniaturas no bucket privado trafego-miniaturas pela Storage API. Sem as duas variáveis (o Supabase
// injeta as duas em toda Edge), as miniaturas não são baixadas (fail-closed); o resto da coleta por anúncio segue.
const SUPABASE_URL = (Deno.env.get('SUPABASE_URL') ?? '').replace(/\/+$/, '');
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });

function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/** Grava a miniatura no bucket privado (a service role fica só aqui, no servidor; nunca vai para o registro). */
async function subirMiniatura(caminho: string, bytes: Uint8Array<ArrayBuffer>, mime: string, ms: number): Promise<void> {
  const alvo = caminho.split('/').map(encodeURIComponent).join('/');
  const r = await fetch(`${SUPABASE_URL}/storage/v1/object/trafego-miniaturas/${alvo}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${SERVICE_ROLE}`, apikey: SERVICE_ROLE, 'Content-Type': mime, 'x-upsert': 'true', 'cache-control': '3600' },
    body: new Blob([bytes], { type: mime }),
    signal: AbortSignal.timeout(Math.max(1, Math.min(15_000, ms))),
  });
  await r.body?.cancel();
  if (!r.ok) throw new Error(`storage_${r.status}`);
}

/**
 * 20261012120000: função de entrada da coleta por anúncio com teto no próprio banco (statement_timeout local à
 * transação): se o prazo da fase acaba, o comando é cancelado no servidor e não segura a conexão do coleta_registrar.
 */
// deno-lint-ignore no-explicit-any
const comTeto = (ms: number, consulta: (tx: any) => Promise<any[]>) =>
  // deno-lint-ignore no-explicit-any
  sql.begin(async (tx: any) => {
    await tx`select set_config('statement_timeout', ${String(Math.max(1, Math.floor(ms)))}, true)`;
    return (await consulta(tx))[0].r;
  });

Deno.serve(async (req) => {
  const inicio = Date.now();
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

  const ate_ms = Date.now() + ORCAMENTO_MS;
  const resultado = await coletarMeta(contas, {
    buscar: (url, init) => fetch(url, { ...init, signal: AbortSignal.timeout(30_000) }),
    versao,
    de: per.de,
    ate: per.ate,
    ate_ms,
    receberCampanhas: async (l) => (await sql`select public.trafego_campanhas_receber(${sql.json(l)}::jsonb) as r`)[0].r,
    receberDesempenho: async (l) => (await sql`select public.trafego_desempenho_receber(${sql.json(l)}::jsonb) as r`)[0].r,
    // 20261009230000: alcance e frequência do período inteiro de cada campanha que gastou
    receberTotais: async (l) => (await sql`select public.trafego_desempenho_total_receber(${sql.json(l)}::jsonb) as r`)[0].r,
  });
  const ok = resultado.contas.every((c) => c.ok) && resultado.puladas === 0;
  const erro = ok ? null : resultado.contas.filter((c) => !c.ok).map((c) => `${c.conta}: ${c.erro}`).join('; ').slice(0, 480) || 'contas puladas';
  // 20261012120000: por conjunto e anúncio, só nas contas da flag meta_anuncio_contas (nula = desligada) que deram ok
  // acima. Fica FORA do ok/erro: falha aqui só aparece em coletas.resultado -> 'anuncios'. Flag nula = saída idêntica.
  const alvo = contasDaFlag(p?.meta_anuncio_contas, contas, resultado.contas);
  const anuncios = alvo.length
    ? await coletarAnuncios(alvo, {
      // o anuncios.ts sempre passa o signal limitado ao que resta da fase; os 30 s aqui são só a rede de segurança
      buscar: (url, init) => fetch(url, { ...init, signal: init?.signal ?? AbortSignal.timeout(30_000) }),
      versao,
      de: per.de,
      ate: per.ate,
      ate_ms: inicio + LIMITE_EDGE_MS - RESERVA_REGISTRO_MS,
      lerPaginas,
      paraDesempenho,
      camposDistribuicao: CAMPOS_DISTRIBUICAO,
      receberConjuntos: (l, ms) => comTeto(ms, (tx) => tx`select public.trafego_conjuntos_receber(${tx.json(l)}::jsonb) as r`),
      receberAnuncios: (l, ms) => comTeto(ms, (tx) => tx`select public.trafego_anuncios_receber(${tx.json(l)}::jsonb) as r`),
      receberDesempenhoAnuncio: (l, ms) =>
        comTeto(ms, (tx) => tx`select public.trafego_desempenho_anuncio_receber(${tx.json(l)}::jsonb) as r`),
      receberMiniaturas: (l, ms) =>
        comTeto(ms, (tx) => tx`select public.trafego_anuncio_miniatura_receber(${tx.json(l)}::jsonb) as r`),
      ...(SUPABASE_URL && SERVICE_ROLE ? { baixar: (url: string, init: RequestInit) => fetch(url, init), subirMiniatura } : {}),
    }).catch(() => ({ erro: 'falha_inesperada' }))
    : null;
  const extra = anuncios ? { anuncios } : {};
  await sql`select mkt_trafego.coleta_registrar('meta', ${ok}, ${sql.json({ ...resultado, versao, contas_lidas: contas.length, ...extra })}::jsonb, ${erro})`;
  return json({ ok, ...resultado, ...extra });
});
