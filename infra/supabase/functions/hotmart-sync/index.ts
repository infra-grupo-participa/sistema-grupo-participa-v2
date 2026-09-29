// hotmart-sync — espelha a Hotmart (API oficial, SÓ LEITURA) em fin.hotmart_transacoes.
//
// 27/09/2026 — pedido do João: financeiro do HM a partir da fonte oficial (bruto,
// juros, taxa, líquido, tentativas recusadas, boletos, reembolsos).
// 29/09/2026 (v9) — multi-conta: 'academy' (Academy) e 'escritorio' (Soluções), cadastradas em fin.hotmart_contas
// (migration 20260930z89, ver CONTRATO no fim dela). Credencial e token POR conta; cada linha da fila, do catálogo e
// do espelho leva a conta. Código de transação que já existe em OUTRA conta vai para fin.hotmart_transacoes_colisao
// (nunca sobrescreve a outra conta). Exige a z89 aplicada.
//
// Só chamadas GET na Hotmart. Nada de reembolso/cancelamento/cupom.
// Não escreve em public.compras nem em cs.* — só no schema fin (camada nova).
//
// Chamada: POST com header `x-sync-chave` (= Vault `fin_hotmart_sync_chave`, a mesma para todas as contas).
//   body {}                 → processa a fila (backfill pendente), cada janela com o token da conta dela
//   body {"rotina": true}   → enfileira uma janela '*' (todos os produtos) dos últimos 3 dias por conta ativa e processa
//   body {"catalogo": true, "conta"?: "academy"}
//                           → grava a lista de TODOS os produtos da conta (sem conta: de todas as ativas) em
//                             fin.hotmart_catalogo e as ofertas dos produtos com sincroniza = true em fin.ofertas
// Quem chama é o pg_cron (via pg_net). Credenciais só no Vault, lidas pelo Postgres.
import postgres from "npm:postgres@3.4.4";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const API = "https://developers.hotmart.com";
const TOKEN_URL = "https://api-sec-vlc.hotmart.com/security/oauth/token";
const ORCAMENTO_MS = 110_000; // limite de parede da Edge Function é 150 s
const CRED_TTL_MS = 600_000;
const STATUS = [
  "APPROVED", "COMPLETE", "CANCELLED", "PRINTED_BILLET", "WAITING_PAYMENT", "REFUNDED",
  "PARTIALLY_REFUNDED", "CHARGEBACK", "PROTESTED", "EXPIRED", "BLOCKED", "OVERDUE",
  "NO_FUNDS", "UNDER_ANALISYS", "STARTED",
];

type Item = Record<string, any>;
// Conta Hotmart com a credencial (Basic) já lida do Vault. O Basic fica aqui para renovar o token no meio de uma
// janela longa (401 na varredura geral, 27/09).
type Conta = { conta: string; basic: string };

// Credenciais em cache no isolate (10 min): chamada sem chave não abre conexão no
// banco a cada request — sem isso, uma enxurrada anônima esgotaria o pool (pentest 27/09).
// A chave x-sync-chave é uma só; o Basic e o token são POR conta (o isolate atende requests concorrentes).
let chaveCache: { chave: string; ate: number } | null = null;
const basicCache = new Map<string, { basic: string | null; ate: number }>();
const tokenCache = new Map<string, { token: string; expira: number }>();

async function chaveSync(): Promise<string> {
  if (chaveCache && chaveCache.ate > Date.now()) return chaveCache.chave;
  // p_conta null → basic null; a chave vem do Vault independente da conta.
  const [r] = await sql`select chave_sync from fin.hotmart_credenciais_conta(null)`;
  chaveCache = { chave: r?.chave_sync ?? "", ate: Date.now() + CRED_TTL_MS };
  return chaveCache.chave;
}

// basic NULL = conta inativa/inexistente (ou segredo ausente no Vault) → quem chama pula a conta.
async function credencialConta(conta: string): Promise<Conta | null> {
  const c = basicCache.get(conta);
  if (c && c.ate > Date.now()) return c.basic ? { conta, basic: c.basic } : null;
  const [r] = await sql`select basic, chave_sync from fin.hotmart_credenciais_conta(${conta})`;
  const basic: string | null = r?.basic ?? null;
  basicCache.set(conta, { basic, ate: Date.now() + CRED_TTL_MS });
  if (r?.chave_sync) chaveCache = { chave: r.chave_sync, ate: Date.now() + CRED_TTL_MS };
  return basic ? { conta, basic } : null;
}

// Contas ativas com credencial; as sem credencial vão para `puladas`.
async function contasProntas(filtro?: string): Promise<{ prontas: Conta[]; puladas: string[] }> {
  const ativas = await sql`select conta from fin.hotmart_contas where ativa order by conta`;
  const prontas: Conta[] = [];
  const puladas: string[] = [];
  for (const { conta } of ativas) {
    if (filtro && conta !== filtro) continue;
    const c = await credencialConta(conta);
    if (c) prontas.push(c);
    else puladas.push(conta);
  }
  return { prontas, puladas };
}

// Saída de erro (fila, resposta HTTP, console) passa SEMPRE por aqui (pentest 29/09): o erro de rede do fetch do
// token traz a URL inteira, com client_id/client_secret na query. Remove par de credencial em query e header.
export function semSegredo(v: unknown): string {
  return String(v)
    .replace(/(client_secret|client_id|access_token|refresh_token)=[^&\s"')]*/gi, "$1=***")
    .replace(/\b(Basic|Bearer)\s+[A-Za-z0-9._~+\/=-]+/gi, "$1 ***");
}

async function token(c: Conta): Promise<string> {
  const t = tokenCache.get(c.conta);
  if (t && t.expira > Date.now() + 120_000) return t.token;
  const [id, secret] = atob(c.basic).split(":");
  const q = new URLSearchParams({ grant_type: "client_credentials", client_id: id, client_secret: secret });
  // Hotmart documenta a credencial na query do token; fica na URL. O erro de rede NÃO é repassado (a mensagem
  // original contém a URL com o secret) — só o nome da conta.
  let r: Response;
  try {
    r = await fetch(`${TOKEN_URL}?${q}`, {
      method: "POST",
      headers: { Authorization: `Basic ${c.basic}`, "Content-Type": "application/json" },
    });
  } catch {
    throw new Error(`token Hotmart (${c.conta}): falha de rede`);
  }
  if (!r.ok) throw new Error(`token Hotmart (${c.conta}) HTTP ${r.status}`);
  const d = await r.json();
  tokenCache.set(c.conta, { token: d.access_token, expira: Date.now() + d.expires_in * 1000 });
  return d.access_token;
}

async function get(c: Conta, path: string, params: Record<string, string | number | undefined>) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") q.set(k, String(v));
  let atual = await token(c);
  for (let tentativa = 0; tentativa < 4; tentativa++) {
    const r = await fetch(`${API}${path}?${q}`, { headers: { Authorization: `Bearer ${atual}` } });
    if (r.status === 429) { await new Promise((ok) => setTimeout(ok, 5000 * (tentativa + 1))); continue; }
    // Token venceu no meio da janela: pede outro DA MESMA CONTA e repete (uma vez por tentativa).
    if (r.status === 401) { tokenCache.delete(c.conta); atual = await token(c); continue; }
    if (!r.ok) throw new Error(`${path} HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
    return await r.json();
  }
  throw new Error(`${path}: limite de requisições da Hotmart (429) persistente`);
}

async function paginar(c: Conta, path: string, params: Record<string, string | number | undefined>) {
  const itens: Item[] = [];
  let pageToken: string | undefined;
  for (let pagina = 0; pagina < 400; pagina++) {
    const d = await get(c, path, { ...params, max_results: 50, page_token: pageToken });
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

async function processarJanela(c: Conta, j: { produto_id: string; inicio: string; fim: string }) {
  const conta = c.conta;
  // produto_id '*' = varredura de TODOS os produtos da conta (27/09/2026: "nada fora do sistema"); o produto de cada
  // venda vem do próprio item.
  const base = {
    product_id: j.produto_id === "*" ? undefined : j.produto_id,
    start_date: inicioDia(j.inicio), end_date: fimDia(j.fim),
  };
  let total = 0;
  let colisoes = 0;
  for (const st of STATUS) {
    const itens = await paginar(c, "/payments/api/v1/sales/history", { ...base, transaction_status: st });
    for (const it of itens) {
      const p = it.purchase ?? {};
      const linha = {
        transacao: p.transaction,
        conta,
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
      // O WHERE do do-update impede sobrescrever a linha de OUTRA conta com o mesmo código: aí o upsert afeta 0 linhas.
      const r = await sql`
        insert into fin.hotmart_transacoes ${sql(linha)}
        on conflict (transacao) do update set
          status = excluded.status, produto_nome = excluded.produto_nome, oferta_codigo = excluded.oferta_codigo,
          oferta_modo = excluded.oferta_modo, eh_assinatura = excluded.eh_assinatura, recorrencia = excluded.recorrencia,
          metodo = excluded.metodo, tipo_pagamento = excluded.tipo_pagamento, parcelas = excluded.parcelas,
          moeda = excluded.moeda, valor_cobrado = excluded.valor_cobrado, taxa_hotmart = excluded.taxa_hotmart,
          pedido_em = excluded.pedido_em, aprovado_em = excluded.aprovado_em, garantia_ate = excluded.garantia_ate,
          origem_sck = excluded.origem_sck, comprador_email = excluded.comprador_email,
          comprador_nome = excluded.comprador_nome, comprador_ucode = excluded.comprador_ucode,
          bruto_json = excluded.bruto_json, atualizado_em = now()
        where fin.hotmart_transacoes.conta = excluded.conta`;
      if (r.count === 0) {
        await sql`
          insert into fin.hotmart_transacoes_colisao (transacao, conta, bruto)
          values (${linha.transacao}, ${conta}, ${sql.json(it)})
          on conflict (transacao, conta) do update set bruto = excluded.bruto, visto_em = now()`;
        colisoes++;
        continue;
      }
      total++;
    }
  }
  // Preço (base x juros) e comissões: a API devolve por janela, só de venda paga.
  // Todos os updates por transação filtram a conta: código em colisão não recebe dado da outra conta.
  const precos = await paginar(c, "/payments/api/v1/sales/price/details", base);
  for (const p of precos) {
    if (!p.transaction) continue;
    await sql`update fin.hotmart_transacoes set
        valor_base = ${p.base?.value ?? null}, juros_parcelamento = ${p.fee?.value ?? 0},
        detalhes_em = now(), atualizado_em = now()
      where transacao = ${p.transaction} and conta = ${conta}`;
  }
  const comissoes = await paginar(c, "/payments/api/v1/sales/commissions", base);
  for (const cm of comissoes) {
    if (!cm.transaction) continue;
    const lista = (cm.commissions ?? []).map((x: Item) => ({
      papel: x.source, valor: x.commission?.value ?? null, quem: x.user?.name ?? null, ucode: x.user?.ucode ?? null,
    }));
    const liquido = lista.filter((x: Item) => x.papel === "PRODUCER").reduce((s: number, x: Item) => s + (x.valor ?? 0), 0);
    await sql`update fin.hotmart_transacoes set
        comissoes = ${sql.json(lista)}, liquido_produtor = ${liquido},
        detalhes_em = now(), atualizado_em = now()
      where transacao = ${cm.transaction} and conta = ${conta}`;
  }
  // Participantes (CPF/CNPJ, telefone e cidade do comprador) — é o que liga e-mails
  // diferentes da mesma pessoa. Guarda só o comprador; dos outros papéis, só o papel.
  // Sem transaction_status a API só devolve venda paga: pede status por status
  // (recusa, reembolso e boleto vencido também têm CPF — é o que liga quem tentou comprar).
  const usuarios: Item[] = [];
  for (const st of STATUS) {
    usuarios.push(...await paginar(c, "/payments/api/v1/sales/users", { ...base, transaction_status: st }));
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
      where transacao = ${u.transaction} and conta = ${conta}`;
  }
  return { total, colisoes };
}

// Catálogo de TODOS os produtos da conta (só leitura) → fin.hotmart_catalogo. Não mexe na fila.
async function catalogoConta(c: Conta): Promise<number> {
  const produtos = await paginar(c, "/products/api/v1/products", {});
  for (const p of produtos) {
    if (p.id == null) continue;
    // Mesmo produto_id já gravado por OUTRA conta: não sobrescreve (mesma regra das transações).
    await sql`
      insert into fin.hotmart_catalogo (produto_id, conta, nome, status, formato, ucode, criado_na_hotmart, bruto_json, visto_em)
      values (${String(p.id)}, ${c.conta}, ${p.name ?? null}, ${p.status ?? null}, ${p.format ?? null}, ${p.ucode ?? null},
              ${msParaTs(p.created_at)}, ${sql.json(p)}, now())
      on conflict (produto_id) do update set nome = excluded.nome, status = excluded.status, formato = excluded.formato,
        ucode = excluded.ucode, criado_na_hotmart = excluded.criado_na_hotmart, bruto_json = excluded.bruto_json, visto_em = now()
      where fin.hotmart_catalogo.conta = excluded.conta`;
  }
  return produtos.length;
}

Deno.serve(async (req) => {
  const inicio = Date.now();
  try {
    const chave = await chaveSync();
    if (!chave || req.headers.get("x-sync-chave") !== chave) {
      return new Response(JSON.stringify({ erro: "não autorizado" }), { status: 401 });
    }
    const body = await req.json().catch(() => ({}));
    if (body?.catalogo) {
      const filtro = typeof body.conta === "string" && body.conta ? body.conta : undefined;
      const { prontas, puladas } = await contasProntas(filtro);
      let catalogo = 0;
      const porConta: Record<string, number> = {};
      const catalogoErro: string[] = [];
      for (const c of prontas) {
        try {
          porConta[c.conta] = await catalogoConta(c);
          catalogo += porConta[c.conta];
        } catch (e) {
          console.error("hotmart-sync catalogo", c.conta, semSegredo(e).slice(0, 300));
          catalogoErro.push(c.conta);
        }
      }
      // Produto novo entra INVISÍVEL (A_CLASSIFICAR: nenhuma tela lê e o grafo de identidade exclui) até alguém classificar.
      await sql`
        insert into fin.produtos (produto_id, conta, nome, familia, papel, sincroniza, nota)
        select c.produto_id, c.conta, c.nome, 'A_CLASSIFICAR', null, false, 'Do catálogo da Hotmart; aguarda classificação.'
          from fin.hotmart_catalogo c
        on conflict (produto_id) do nothing`;
      // Ofertas: uma chamada por produto sincronizado (lista montada antes), com o token da conta DO PRODUTO.
      // Falha de um não derruba os outros.
      const porNome = new Map(prontas.map((c) => [c.conta, c]));
      const alvos = porNome.size
        ? await sql`
            select p.produto_id, p.conta, c.ucode from fin.produtos p
              join fin.hotmart_catalogo c on c.produto_id = p.produto_id
             where p.sincroniza = true and c.ucode is not null and p.conta in ${sql([...porNome.keys()])}`
        : [];
      let ofertas = 0;
      const ofertasErro: string[] = [];
      for (const a of alvos) {
        try {
          const c = porNome.get(a.conta)!;
          const lista = await paginar(c, `/products/api/v1/products/${encodeURIComponent(a.ucode)}/offers`, {});
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
          console.error("hotmart-sync ofertas", a.produto_id, semSegredo(e).slice(0, 300));
          ofertasErro.push(String(a.produto_id));
        }
      }
      return new Response(JSON.stringify({
        catalogo, por_conta: porConta, contas_puladas: puladas, catalogo_erro: catalogoErro,
        ofertas, ofertas_erro: ofertasErro, ms: Date.now() - inicio,
      }), {
        headers: { "Content-Type": "application/json" },
      });
    }
    if (body?.rotina) {
      // Janela móvel de 3 dias, uma linha '*' por conta ativa: pega mudança de status (boleto pago, reembolso,
      // chargeback) de todos os produtos da conta. Mesmo guarda dos crons 'fin-hotmart-rotina-todos*'.
      await sql`
        insert into fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo, status, tentativas)
        select c.conta, '*', (now() at time zone 'America/Sao_Paulo')::date - 3,
               (now() at time zone 'America/Sao_Paulo')::date, 'rotina', 'pendente', 0
          from fin.hotmart_contas c
         where c.ativa
           and not exists (select 1 from fin.hotmart_sync_fila f
                            where f.conta = c.conta and f.produto_id = '*' and f.tipo = 'rotina'
                              and f.status in ('pendente','processando'))
        on conflict do nothing`;
    }
    // Só pega janela de conta ativa com credencial; janela de conta pulada fica na fila, intacta.
    const { prontas, puladas } = await contasProntas();
    const porNome = new Map(prontas.map((c) => [c.conta, c]));
    const feitos: Item[] = [];
    while (porNome.size && Date.now() - inicio < ORCAMENTO_MS) {
      const [j] = await sql`
        update fin.hotmart_sync_fila set status = 'processando', tentativas = tentativas + 1, iniciado_em = now()
         where id = (select id from fin.hotmart_sync_fila
                      where (status = 'pendente' or (status = 'erro' and tentativas < 3)
                         or (status = 'processando' and iniciado_em < now() - interval '5 minutes' and tentativas < 3))
                        and conta in ${sql([...porNome.keys()])}
                      order by (tipo = 'rotina') desc, inicio desc limit 1 for update skip locked)
        returning id, conta, produto_id, inicio::text, fim::text`;
      if (!j) break;
      try {
        const { total: n, colisoes } = await processarJanela(porNome.get(j.conta)!, j as any);
        await sql`update fin.hotmart_sync_fila set status = 'feito', itens = ${n}, erro = null, feito_em = now() where id = ${j.id}`;
        feitos.push({ id: j.id, conta: j.conta, produto: j.produto_id, janela: `${j.inicio}..${j.fim}`, itens: n, colisoes });
      } catch (e) {
        await sql`update fin.hotmart_sync_fila set status = 'erro', erro = ${semSegredo(e).slice(0, 500)} where id = ${j.id}`;
        feitos.push({ id: j.id, conta: j.conta, erro: semSegredo(e).slice(0, 200) });
      }
    }
    const [pend] = await sql`select count(*)::int n from fin.hotmart_sync_fila where status in ('pendente','processando') or (status='erro' and tentativas < 3)`;
    return new Response(JSON.stringify({ feitos, pendentes: pend.n, contas_puladas: puladas, ms: Date.now() - inicio }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    // Detalhe só no log da função; quem chamou recebe erro genérico.
    console.error("hotmart-sync", semSegredo(e).slice(0, 500));
    return new Response(JSON.stringify({ erro: "falha interna" }), { status: 500 });
  }
});
