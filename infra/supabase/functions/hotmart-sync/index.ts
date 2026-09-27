// hotmart-sync — espelha a Hotmart (API oficial, SÓ LEITURA) em fin.hotmart_transacoes.
//
// 27/09/2026 — pedido do João: financeiro do HM a partir da fonte oficial (bruto,
// juros, taxa, líquido, tentativas recusadas, boletos, reembolsos).
//
// Só chamadas GET na Hotmart. Nada de reembolso/cancelamento/cupom.
// Não escreve em public.compras nem em cs.* — só no schema fin (camada nova).
//
// Chamada: POST com header `x-sync-chave` (= Vault `fin_hotmart_sync_chave`).
//   body {}                 → processa a fila (backfill pendente)
//   body {"rotina": true}   → enfileira os últimos 3 dias de cada produto e processa
// Quem chama é o pg_cron (via pg_net). Credenciais só no Vault, lidas pelo Postgres.
import postgres from "npm:postgres@3.4.4";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const API = "https://developers.hotmart.com";
const TOKEN_URL = "https://api-sec-vlc.hotmart.com/security/oauth/token";
const ORCAMENTO_MS = 110_000; // limite de parede da Edge Function é 150 s
const STATUS = [
  "APPROVED", "COMPLETE", "CANCELLED", "PRINTED_BILLET", "WAITING_PAYMENT", "REFUNDED",
  "PARTIALLY_REFUNDED", "CHARGEBACK", "PROTESTED", "EXPIRED", "BLOCKED", "OVERDUE",
  "NO_FUNDS", "UNDER_ANALISYS", "STARTED",
];

type Item = Record<string, any>;

let tokenCache: { token: string; expira: number } | null = null;

// Credenciais em cache no isolate (10 min): chamada sem chave não abre conexão no
// banco a cada request — sem isso, uma enxurrada anônima esgotaria o pool (pentest 27/09).
let credCache: { basic: string; chave: string; ate: number } | null = null;
async function credenciais(): Promise<{ basic: string; chave: string }> {
  if (credCache && credCache.ate > Date.now()) return credCache;
  const [r] = await sql`select basic, chave_sync from fin.hotmart_credenciais()`;
  credCache = { basic: r.basic, chave: r.chave_sync, ate: Date.now() + 600_000 };
  return credCache;
}

async function token(basic: string): Promise<string> {
  if (tokenCache && tokenCache.expira > Date.now() + 120_000) return tokenCache.token;
  const [id, secret] = atob(basic).split(":");
  const q = new URLSearchParams({ grant_type: "client_credentials", client_id: id, client_secret: secret });
  const r = await fetch(`${TOKEN_URL}?${q}`, {
    method: "POST",
    headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/json" },
  });
  if (!r.ok) throw new Error(`token Hotmart HTTP ${r.status}`);
  const d = await r.json();
  tokenCache = { token: d.access_token, expira: Date.now() + d.expires_in * 1000 };
  return tokenCache.token;
}

async function get(tk: string, path: string, params: Record<string, string | number | undefined>) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") q.set(k, String(v));
  for (let tentativa = 0; tentativa < 4; tentativa++) {
    const r = await fetch(`${API}${path}?${q}`, { headers: { Authorization: `Bearer ${tk}` } });
    if (r.status === 429) { await new Promise((ok) => setTimeout(ok, 5000 * (tentativa + 1))); continue; }
    if (!r.ok) throw new Error(`${path} HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
    return await r.json();
  }
  throw new Error(`${path}: limite de requisições da Hotmart (429) persistente`);
}

async function paginar(tk: string, path: string, params: Record<string, string | number | undefined>) {
  const itens: Item[] = [];
  let pageToken: string | undefined;
  for (let pagina = 0; pagina < 400; pagina++) {
    const d = await get(tk, path, { ...params, max_results: 50, page_token: pageToken });
    itens.push(...(d.items ?? []));
    pageToken = d.page_info?.next_page_token;
    if (!pageToken) break;
  }
  return itens;
}

const msParaTs = (ms?: number | null) => (ms ? new Date(ms).toISOString() : null);
// Datas da fila são dias de São Paulo.
const inicioDia = (d: string) => new Date(`${d}T00:00:00-03:00`).getTime();
const fimDia = (d: string) => new Date(`${d}T00:00:00-03:00`).getTime() + 86_400_000 - 1;

async function processarJanela(tk: string, j: { produto_id: string; inicio: string; fim: string }) {
  const base = { product_id: j.produto_id, start_date: inicioDia(j.inicio), end_date: fimDia(j.fim) };
  let total = 0;
  for (const st of STATUS) {
    const itens = await paginar(tk, "/payments/api/v1/sales/history", { ...base, transaction_status: st });
    for (const it of itens) {
      const p = it.purchase ?? {};
      const linha = {
        transacao: p.transaction,
        produto_id: String(it.product?.id ?? j.produto_id),
        produto_nome: it.product?.name ?? null,
        oferta_codigo: p.offer?.code ?? null,
        oferta_modo: p.offer?.payment_mode ?? null,
        status: p.status ?? st,
        eh_assinatura: p.is_subscription ?? null,
        recorrencia: p.recurrency_number ?? null,
        metodo: p.payment?.method ?? null,
        tipo_pagamento: p.payment?.type ?? null,
        parcelas: p.payment?.installments_number ?? null,
        moeda: p.price?.currency_code ?? null,
        valor_cobrado: p.price?.value ?? null,
        taxa_hotmart: p.hotmart_fee?.total ?? null,
        pedido_em: msParaTs(p.order_date),
        aprovado_em: msParaTs(p.approved_date),
        garantia_ate: msParaTs(p.warranty_expire_date),
        origem_sck: p.tracking?.source_sck ?? null,
        comprador_email: it.buyer?.email ?? null,
        comprador_nome: it.buyer?.name ?? null,
        comprador_ucode: it.buyer?.ucode ?? null,
        bruto_json: sql.json(it),
      };
      if (!linha.transacao) continue;
      await sql`
        insert into fin.hotmart_transacoes ${sql(linha)}
        on conflict (transacao) do update set
          status = excluded.status, produto_nome = excluded.produto_nome, oferta_codigo = excluded.oferta_codigo,
          oferta_modo = excluded.oferta_modo, eh_assinatura = excluded.eh_assinatura, recorrencia = excluded.recorrencia,
          metodo = excluded.metodo, tipo_pagamento = excluded.tipo_pagamento, parcelas = excluded.parcelas,
          moeda = excluded.moeda, valor_cobrado = excluded.valor_cobrado, taxa_hotmart = excluded.taxa_hotmart,
          pedido_em = excluded.pedido_em, aprovado_em = excluded.aprovado_em, garantia_ate = excluded.garantia_ate,
          origem_sck = excluded.origem_sck, comprador_email = excluded.comprador_email,
          comprador_nome = excluded.comprador_nome, comprador_ucode = excluded.comprador_ucode,
          bruto_json = excluded.bruto_json, atualizado_em = now()`;
      total++;
    }
  }
  // Preço (base x juros) e comissões: a API devolve por janela, só de venda paga.
  const precos = await paginar(tk, "/payments/api/v1/sales/price/details", base);
  for (const p of precos) {
    if (!p.transaction) continue;
    await sql`update fin.hotmart_transacoes set
        valor_base = ${p.base?.value ?? null}, juros_parcelamento = ${p.fee?.value ?? 0},
        detalhes_em = now(), atualizado_em = now()
      where transacao = ${p.transaction}`;
  }
  const comissoes = await paginar(tk, "/payments/api/v1/sales/commissions", base);
  for (const c of comissoes) {
    if (!c.transaction) continue;
    const lista = (c.commissions ?? []).map((x: Item) => ({
      papel: x.source, valor: x.commission?.value ?? null, quem: x.user?.name ?? null, ucode: x.user?.ucode ?? null,
    }));
    const liquido = lista.filter((x: Item) => x.papel === "PRODUCER").reduce((s: number, x: Item) => s + (x.valor ?? 0), 0);
    await sql`update fin.hotmart_transacoes set
        comissoes = ${sql.json(lista)}, liquido_produtor = ${liquido},
        detalhes_em = now(), atualizado_em = now()
      where transacao = ${c.transaction}`;
  }
  return total;
}

Deno.serve(async (req) => {
  const inicio = Date.now();
  try {
    const cred = await credenciais();
    if (!cred.chave || req.headers.get("x-sync-chave") !== cred.chave) {
      return new Response(JSON.stringify({ erro: "não autorizado" }), { status: 401 });
    }
    const body = await req.json().catch(() => ({}));
    if (body?.rotina) {
      // Janela móvel de 3 dias: pega mudança de status (boleto pago, reembolso, chargeback).
      await sql`
        insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)
        select produto_id, (now() at time zone 'America/Sao_Paulo')::date - 3,
               (now() at time zone 'America/Sao_Paulo')::date, 'rotina'
          from fin.produtos where sincroniza
        on conflict do nothing`;
    }
    const tk = await token(cred.basic);
    const feitos: Item[] = [];
    while (Date.now() - inicio < ORCAMENTO_MS) {
      const [j] = await sql`
        update fin.hotmart_sync_fila set status = 'processando', tentativas = tentativas + 1, iniciado_em = now()
         where id = (select id from fin.hotmart_sync_fila
                      where status = 'pendente' or (status = 'erro' and tentativas < 3)
                         or (status = 'processando' and iniciado_em < now() - interval '5 minutes' and tentativas < 3)
                      order by (tipo = 'rotina') desc, inicio desc limit 1 for update skip locked)
        returning id, produto_id, inicio::text, fim::text`;
      if (!j) break;
      try {
        const n = await processarJanela(tk, j as any);
        await sql`update fin.hotmart_sync_fila set status = 'feito', itens = ${n}, erro = null, feito_em = now() where id = ${j.id}`;
        feitos.push({ id: j.id, produto: j.produto_id, janela: `${j.inicio}..${j.fim}`, itens: n });
      } catch (e) {
        await sql`update fin.hotmart_sync_fila set status = 'erro', erro = ${String(e).slice(0, 500)} where id = ${j.id}`;
        feitos.push({ id: j.id, erro: String(e).slice(0, 200) });
      }
    }
    const [pend] = await sql`select count(*)::int n from fin.hotmart_sync_fila where status in ('pendente','processando') or (status='erro' and tentativas < 3)`;
    return new Response(JSON.stringify({ feitos, pendentes: pend.n, ms: Date.now() - inicio }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    // Detalhe só no log da função; quem chamou recebe erro genérico.
    console.error("hotmart-sync", String(e).slice(0, 500));
    return new Response(JSON.stringify({ erro: "falha interna" }), { status: 500 });
  }
});
