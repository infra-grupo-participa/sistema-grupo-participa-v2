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
//   body {"catalogo": true} → grava a lista de TODOS os produtos da conta em fin.hotmart_catalogo
//                             e as ofertas dos produtos com sincroniza = true em fin.ofertas
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
// Basic da conta, guardado para renovar o token no meio de uma janela longa (401 na varredura geral, 27/09).
let basicAtual = "";

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
  basicAtual = basic;
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
  let atual = tokenCache?.token ?? tk;
  for (let tentativa = 0; tentativa < 4; tentativa++) {
    const r = await fetch(`${API}${path}?${q}`, { headers: { Authorization: `Bearer ${atual}` } });
    if (r.status === 429) { await new Promise((ok) => setTimeout(ok, 5000 * (tentativa + 1))); continue; }
    // Token venceu no meio da janela: pede outro e repete (uma vez por tentativa).
    if (r.status === 401 && basicAtual) { tokenCache = null; atual = await token(basicAtual); continue; }
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

// Oferta da Hotmart (GET /products/{ucode}/offers) → linha de fin.ofertas. Pura: formato diferente vira null,
// o objeto inteiro fica em bruto_json (o chamador aplica sql.json). Sem code, devolve null (item ignorado).
export function ofertaParaLinha(produtoId: string, o: Item) {
  if (!o || o.code == null || String(o.code) === "") return null;
  const v = o.price?.value;
  const preco = v == null || v === "" || !Number.isFinite(Number(v)) ? null : Number(v);
  return {
    oferta_codigo: String(o.code),
    produto_id: produtoId,
    nome: o.name ?? null,
    descricao: o.description ?? null,
    preco,
    moeda: o.price?.currency_code ?? null,
    modo: o.payment_mode ?? null,
    is_main_offer: typeof o.is_main_offer === "boolean" ? o.is_main_offer : null,
    bruto_json: o,
  };
}

const msParaTs = (ms?: number | null) => (ms ? new Date(ms).toISOString() : null);
// Datas da fila são dias de São Paulo.
const inicioDia = (d: string) => new Date(`${d}T00:00:00-03:00`).getTime();
const fimDia = (d: string) => new Date(`${d}T00:00:00-03:00`).getTime() + 86_400_000 - 1;

async function processarJanela(tk: string, j: { produto_id: string; inicio: string; fim: string }) {
  // produto_id '*' = varredura de TODOS os produtos da conta (27/09/2026: "nada fora do sistema"); o produto de cada
  // venda vem do próprio item.
  const base = {
    product_id: j.produto_id === "*" ? undefined : j.produto_id,
    start_date: inicioDia(j.inicio), end_date: fimDia(j.fim),
  };
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
  // Participantes (CPF/CNPJ, telefone e cidade do comprador) — é o que liga e-mails
  // diferentes da mesma pessoa. Guarda só o comprador; dos outros papéis, só o papel.
  // Sem transaction_status a API só devolve venda paga: pede status por status
  // (recusa, reembolso e boleto vencido também têm CPF — é o que liga quem tentou comprar).
  const usuarios: Item[] = [];
  for (const st of STATUS) {
    usuarios.push(...await paginar(tk, "/payments/api/v1/sales/users", { ...base, transaction_status: st }));
  }
  const digitos = (v: unknown) => (v == null ? null : String(v).replace(/\D/g, "") || null);
  for (const u of usuarios) {
    if (!u.transaction) continue;
    const comprador = (u.users ?? []).find((x: Item) => x.role === "BUYER")?.user ?? null;
    const doc = (comprador?.documents ?? [])[0] ?? null;
    const papeis = (u.users ?? []).map((x: Item) => x.role);
    await sql`update fin.hotmart_transacoes set
        comprador_documento = ${digitos(doc?.value)},
        comprador_documento_tipo = ${doc?.type ?? null},
        comprador_telefone = ${digitos(comprador?.cellphone ?? comprador?.phone)},
        comprador_cidade = ${comprador?.address?.city ?? null},
        comprador_uf = ${comprador?.address?.state ?? null},
        participantes = ${sql.json(papeis)},
        atualizado_em = now()
      where transacao = ${u.transaction}`;
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
    if (body?.catalogo) {
      // Catálogo de TODOS os produtos da conta (só leitura) → fin.hotmart_catalogo. Não mexe na fila.
      const tk0 = await token(cred.basic);
      const produtos = await paginar(tk0, "/products/api/v1/products", {});
      for (const p of produtos) {
        if (p.id == null) continue;
        await sql`
          insert into fin.hotmart_catalogo (produto_id, nome, status, formato, ucode, criado_na_hotmart, bruto_json, visto_em)
          values (${String(p.id)}, ${p.name ?? null}, ${p.status ?? null}, ${p.format ?? null}, ${p.ucode ?? null},
                  ${msParaTs(p.created_at)}, ${sql.json(p)}, now())
          on conflict (produto_id) do update set nome = excluded.nome, status = excluded.status, formato = excluded.formato,
            ucode = excluded.ucode, criado_na_hotmart = excluded.criado_na_hotmart, bruto_json = excluded.bruto_json, visto_em = now()`;
      }
      // Produto novo entra INVISÍVEL (A_CLASSIFICAR: nenhuma tela lê e o grafo de identidade exclui) até alguém classificar.
      await sql`
        insert into fin.produtos (produto_id, nome, familia, papel, sincroniza, nota)
        select c.produto_id, c.nome, 'A_CLASSIFICAR', null, false, 'Do catálogo da Hotmart; aguarda classificação.'
          from fin.hotmart_catalogo c
        on conflict (produto_id) do nothing`;
      // Ofertas: uma chamada por produto sincronizado (lista montada antes). Falha de um não derruba os outros.
      const alvos = await sql`
        select p.produto_id, c.ucode from fin.produtos p
          join fin.hotmart_catalogo c on c.produto_id = p.produto_id
         where p.sincroniza = true and c.ucode is not null`;
      let ofertas = 0;
      const ofertasErro: string[] = [];
      for (const a of alvos) {
        try {
          const lista = await paginar(tk0, `/products/api/v1/products/${encodeURIComponent(a.ucode)}/offers`, {});
          const porCodigo = new Map<string, ReturnType<typeof ofertaParaLinha>>();
          for (const o of lista) {
            const l = ofertaParaLinha(a.produto_id, o);
            if (l) porCodigo.set(l.oferta_codigo, l); // dedup: ON CONFLICT não aceita a mesma chave duas vezes no lote
          }
          const linhas = [...porCodigo.values()].map((l) => ({ ...l!, bruto_json: sql.json(l!.bruto_json) }));
          if (!linhas.length) continue;
          await sql`
            insert into fin.ofertas ${sql(linhas)}
            on conflict (oferta_codigo) do update set
              produto_id = excluded.produto_id, nome = excluded.nome, descricao = excluded.descricao, preco = excluded.preco,
              moeda = excluded.moeda, modo = excluded.modo, is_main_offer = excluded.is_main_offer,
              bruto_json = excluded.bruto_json, visto_em = now()`;
          ofertas += linhas.length;
        } catch (e) {
          console.error("hotmart-sync ofertas", a.produto_id, String(e).slice(0, 300));
          ofertasErro.push(String(a.produto_id));
        }
      }
      return new Response(JSON.stringify({ catalogo: produtos.length, ofertas, ofertas_erro: ofertasErro, ms: Date.now() - inicio }), {
        headers: { "Content-Type": "application/json" },
      });
    }
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
