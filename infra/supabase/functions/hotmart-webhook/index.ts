import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("PROJECT_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SERVICE_ROLE_KEY")!;
const SLACK_WEBHOOK_ATIVACAO = Deno.env.get("SLACK_WEBHOOK_ATIVACAO") ?? "";
const HOTMART_HOTTOK = Deno.env.get("HOTMART_HOTTOK") ?? "";
const PRODUTO_ATIVACAO_PADRAO = "Holding Total";
const HT_ACTIVATION_TYPES = new Set(["ingresso", "vip"]);
const ORDER_BUMP_TYPES = new Set(["ob1", "ob2", "ob3"]);
const ORDER_BUMP_NAMES = [
  "Aula Expressa",
  "Garrafa Holding Total",
  "Tabela de Precificacao do Trabalho com Holding Familiar",
  "Tabela de Precificacao",
];

// Statuses que indicam compra já aprovada/concluída — não devem ser sobrescritos por eventos de carrinho
const FINAL_STATUSES = new Set(["APPROVED", "COMPLETE"]);

type EditionRow = {
  id: number;
  name: string | null;
  display_name: string | null;
  edition_number: number | null;
  event_start_date: string | null;
};

type CatalogEntry = {
  id?: number;
  edition_id?: number | string | null;
  product_id?: string | null;
  offer_code?: string | null;
  product_name?: string | null;
  product_type?: string | null;
  ht_editions?: EditionRow | EditionRow[] | null;
};

function msToISO(ms: number | null | undefined): string | null {
  return ms ? new Date(ms).toISOString() : null;
}

function purchaseTimestampMs(purchase: Record<string, unknown>): number | null {
  const approved = Number(purchase?.approved_date ?? 0);
  if (approved > 0) return approved;
  const ordered = Number(purchase?.order_date ?? 0);
  return ordered > 0 ? ordered : null;
}

function formatLocalDateKey(ms: number | null | undefined): string | null {
  if (!ms) return null;
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(ms));
}

function catalogEdition(catalogEntry: CatalogEntry | null): EditionRow | null {
  const rawEdition = catalogEntry?.ht_editions;
  if (Array.isArray(rawEdition)) return (rawEdition[0] as EditionRow | undefined) ?? null;
  return (rawEdition as EditionRow | null | undefined) ?? null;
}

function inferTipoDocumento(doc: string | null | undefined): string | null {
  if (!doc) return null;
  const clean = doc.replace(/\D/g, "");
  return clean.length === 11 ? "CPF" : clean.length === 14 ? "CNPJ" : null;
}

function normalizePhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  let digits = phone.replace(/\D/g, "");
  if (!digits) return null;
  if (!digits.startsWith("55") && (digits.length === 10 || digits.length === 11)) digits = "55" + digits;
  return digits;
}

function isOrderBumpByName(productName: string | null | undefined): boolean {
  if (!productName) return false;
  const name = productName.toLowerCase();
  return ORDER_BUMP_NAMES.some((item) => name.includes(item.toLowerCase()));
}

async function syncThbAluno(
  db: ReturnType<typeof createClient>,
  compradorId: string,
  buyer: Record<string, unknown>,
): Promise<void> {
  const email = String(buyer.email ?? "").trim().toLowerCase();
  if (!email) return;

  const { data: existingAluno } = await db
    .from("thb_alunos")
    .select("id, comprador_id, nome, telefone, documento, cidade, estado, bairro, cep, endereco_logradouro, endereco_numero, endereco_complemento, hotmart_ucode, tipo_documento")
    .ilike("email", email)
    .limit(1)
    .maybeSingle();

  const address = buyer.address as Record<string, unknown> | undefined;
  const doc = buyer.document as string | undefined;
  const now = new Date().toISOString();

  if (existingAluno) {
    const updates: Record<string, unknown> = { atualizado_em: now };
    if (!existingAluno.comprador_id) updates.comprador_id = compradorId;
    if (!existingAluno.nome && buyer.name) updates.nome = buyer.name;
    if (!existingAluno.telefone && buyer.checkout_phone) updates.telefone = normalizePhone(buyer.checkout_phone as string);
    if (!existingAluno.documento && doc) { updates.documento = doc; updates.tipo_documento = inferTipoDocumento(doc); }
    if (!existingAluno.hotmart_ucode && buyer.ucode) updates.hotmart_ucode = buyer.ucode;
    if (address) {
      if (!existingAluno.cidade && address.city) updates.cidade = address.city;
      if (!existingAluno.estado && address.state) updates.estado = String(address.state).substring(0, 2);
      if (!existingAluno.bairro && address.neighborhood) updates.bairro = address.neighborhood;
      if (!existingAluno.cep && address.zip_code) updates.cep = address.zip_code;
      if (!existingAluno.endereco_logradouro && address.address) updates.endereco_logradouro = address.address;
      if (!existingAluno.endereco_numero && address.number) updates.endereco_numero = address.number;
      if (!existingAluno.endereco_complemento && address.complement) updates.endereco_complemento = address.complement;
    }
    if (Object.keys(updates).length > 1) {
      await db.from("thb_alunos").update(updates).eq("id", existingAluno.id);
    }
  } else {
    const { error } = await db
      .from("thb_alunos")
      .insert({
        id: crypto.randomUUID(),
        nome: buyer.name ?? null,
        email: buyer.email ?? null,
        telefone: normalizePhone(buyer.checkout_phone as string),
        documento: (buyer.document as string) ?? null,
        endereco_logradouro: address?.address ?? null,
        endereco_numero: address?.number ?? null,
        endereco_complemento: address?.complement ?? null,
        bairro: address?.neighborhood ?? null,
        cidade: address?.city ?? null,
        estado: address?.state ? String(address.state).substring(0, 2) : null,
        cep: address?.zip_code ?? null,
        pais: address?.country ?? null,
        comprador_id: compradorId,
        fonte: "webhook_hotmart_ht",
        importado_em: now,
        atualizado_em: now,
      });
    if (error) console.error("Erro ao criar thb_aluno via webhook HT:", error);
  }
}

async function upsertComprador(
  db: ReturnType<typeof createClient>,
  buyer: Record<string, unknown>,
): Promise<string | null> {
  const address = buyer.address as Record<string, unknown> | undefined;
  const doc = buyer.document as string | undefined;
  const { data, error } = await db
    .from("compradores")
    .upsert({
      hotmart_ucode: buyer.ucode,
      nome: buyer.name,
      email: buyer.email,
      telefone: normalizePhone(buyer.checkout_phone as string),
      documento: doc ?? null,
      tipo_documento: inferTipoDocumento(doc),
      endereco_logradouro: address?.address ?? null,
      endereco_numero: address?.number ?? null,
      endereco_complemento: address?.complement ?? null,
      endereco_bairro: address?.neighborhood ?? null,
      endereco_cidade: address?.city ?? null,
      endereco_estado: address?.state ?? null,
      endereco_cep: address?.zip_code ?? null,
      endereco_pais: address?.country ?? null,
      atualizado_em: new Date().toISOString(),
    }, { onConflict: "email" })
    .select("id")
    .single();

  if (error) {
    console.error("Erro upsert comprador:", error);
    return null;
  }
  return data.id;
}

async function resolveCatalogEntry(
  db: ReturnType<typeof createClient>,
  productId: string,
  offerCode: string | null,
  purchaseMs: number | null,
) {
  const { data, error } = await db
    .from("ht_product_catalog")
    .select("id, edition_id, product_id, offer_code, product_name, product_type, ht_editions(id, name, display_name, edition_number, event_start_date)")
    .eq("product_id", productId);

  if (error) {
    console.error("Erro ao consultar ht_product_catalog:", error);
    return null;
  }

  const normalizedOffer = String(offerCode ?? "").trim().toLowerCase();
  const rows = ((data ?? []) as CatalogEntry[]).slice();
  const localDateKey = formatLocalDateKey(purchaseMs);

  const sortByEditionStartDesc = (list: CatalogEntry[]) =>
    list.sort((left, right) => {
      const leftDate = catalogEdition(left)?.event_start_date ?? "";
      const rightDate = catalogEdition(right)?.event_start_date ?? "";
      if (leftDate === rightDate) return Number(right.edition_id ?? 0) - Number(left.edition_id ?? 0);
      return rightDate.localeCompare(leftDate);
    });

  const inWindow = (row: CatalogEntry) => {
    if (!localDateKey) return true;
    const edition = catalogEdition(row);
    return !!edition?.event_start_date && edition.event_start_date <= localDateKey;
  };

  const exact = rows.filter((row) => String(row.offer_code ?? "").trim().toLowerCase() === normalizedOffer);
  const generic = rows.filter((row) => !row.offer_code);
  const candidates = exact.length ? exact : generic.length ? generic : rows;
  const datedCandidates = candidates.filter(inWindow);
  const ranked = sortByEditionStartDesc(datedCandidates.length ? datedCandidates : candidates);
  return ranked[0] ?? null;
}

async function loadHtEditions(db: ReturnType<typeof createClient>): Promise<EditionRow[]> {
  const { data, error } = await db
    .from("ht_editions")
    .select("id, name, display_name, edition_number, event_start_date")
    .not("event_start_date", "is", null)
    .order("event_start_date", { ascending: true });

  if (error) {
    console.error("Erro ao consultar ht_editions:", error);
    return [];
  }

  return (data ?? []) as EditionRow[];
}

function resolveEditionByDate(editions: EditionRow[], purchaseMs: number | null): EditionRow | null {
  const localDateKey = formatLocalDateKey(purchaseMs);
  if (!localDateKey) return null;

  const candidates = editions
    .filter((edition) => !!edition.event_start_date && edition.event_start_date <= localDateKey)
    .sort((left, right) => {
      const leftDate = left.event_start_date ?? "";
      const rightDate = right.event_start_date ?? "";
      if (leftDate === rightDate) return Number(right.edition_number ?? 0) - Number(left.edition_number ?? 0);
      return rightDate.localeCompare(leftDate);
    });

  return candidates[0] ?? null;
}

/** Fallback: edição mais recente pelo edition_number, independente de data */
function resolveLatestEdition(editions: EditionRow[]): EditionRow | null {
  if (!editions.length) return null;
  return [...editions].sort((a, b) => Number(b.edition_number ?? 0) - Number(a.edition_number ?? 0))[0];
}

function catalogEditionLabel(catalogEntry: CatalogEntry | null): string {
  const edition = catalogEdition(catalogEntry);
  return String(edition?.display_name ?? edition?.name ?? `HT ${catalogEntry?.edition_id ?? ""}`).trim() || "Holding Total";
}

function isCatalogOrderBump(catalogEntry: CatalogEntry | null): boolean {
  return ORDER_BUMP_TYPES.has(String(catalogEntry?.product_type ?? "").toLowerCase());
}

function isCatalogActivationProduct(catalogEntry: CatalogEntry | null): boolean {
  return HT_ACTIVATION_TYPES.has(String(catalogEntry?.product_type ?? "").toLowerCase());
}

function formatBrDate(isoOrMs: string | number | null | undefined): string {
  if (!isoOrMs) return "-";
  const d = typeof isoOrMs === "number" ? new Date(isoOrMs) : new Date(isoOrMs);
  if (isNaN(d.getTime())) return "-";
  return new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(d);
}

async function notifySlackBuyer(payload: {
  nome: string;
  email: string;
  telefone: string | null;
  dataCompraMs: number | null;
  edicao: string;
  nomeProduto: string;
  valor: number | null;
  moeda: string;
  origem: string | null;
}) {
  if (!SLACK_WEBHOOK_ATIVACAO) return;

  const dataFormatada = formatBrDate(payload.dataCompraMs);
  const valorFormatado = payload.valor != null
    ? new Intl.NumberFormat("pt-BR", { style: "currency", currency: payload.moeda || "BRL" }).format(payload.valor)
    : "-";
  const origemLabel = payload.origem || "Não identificada";

  const produto = `${payload.nomeProduto} | HT${payload.edicao.replace(/\D/g, "")}`;

  const response = await fetch(SLACK_WEBHOOK_ATIVACAO, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      text: `Nova compra: ${produto}`,
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: `*Nome:* ${payload.nome}\n*E-mail:* ${payload.email}\n*Telefone:* ${payload.telefone ?? "-"}\n*Produto:* ${produto}\n*Valor:* ${valorFormatado}\n*Origem:* ${origemLabel}\n*Data da compra:* ${dataFormatada}`,
          },
        },
        { type: "divider" },
      ],
    }),
  });

  if (!response.ok) {
    console.error("Falha ao notificar Slack HT:", response.status, await response.text());
  }
}

async function handleOrderBump(db: ReturnType<typeof createClient>, data: Record<string, unknown>) {
  const buyer = data.buyer as Record<string, unknown>;
  const purchase = data.purchase as Record<string, unknown>;
  const product = data.product as Record<string, unknown>;
  if (!buyer?.email) return { ok: false, reason: "no_email" };

  const compradorId = await upsertComprador(db, buyer);
  if (!compradorId) return { ok: false, reason: "comprador_error" };

  await syncThbAluno(db, compradorId, buyer);

  const price = purchase.price as Record<string, unknown>;
  const { error } = await db
    .from("tags_produtos")
    .upsert({
      comprador_id: compradorId,
      produto_nome: String(product.name ?? ""),
      hotmart_produto_id: String(product.id ?? ""),
      hotmart_transaction: purchase.transaction as string ?? null,
      preco: price?.value ?? null,
      data_compra: msToISO(purchase.order_date as number),
    }, { onConflict: "hotmart_transaction", ignoreDuplicates: false });

  if (error) {
    console.error("Erro insert tag_produto:", error);
    return { ok: false, reason: "tag_error" };
  }
  return { ok: true, reason: "order_bump" };
}

async function handlePurchaseApproved(db: ReturnType<typeof createClient>, data: Record<string, unknown>) {
  const buyer = data.buyer as Record<string, unknown>;
  const purchase = data.purchase as Record<string, unknown>;
  const product = data.product as Record<string, unknown>;
  const producer = data.producer as Record<string, unknown> | undefined;

  if (!buyer?.email || !purchase?.transaction) return { ok: false, reason: "incomplete_payload" };

  const offer = purchase.offer as Record<string, unknown> | undefined;
  const purchaseMs = purchaseTimestampMs(purchase);
  const trackingParams = purchase.tracking as Record<string, unknown> | undefined;
  const origem = String(
    purchase.checkout_origin ?? trackingParams?.source_sck ?? trackingParams?.utm_source ?? ""
  ).trim() || null;
  const [editions, catalogEntry] = await Promise.all([
    loadHtEditions(db),
    resolveCatalogEntry(db, String(product?.id ?? ""), String(offer?.code ?? "") || null, purchaseMs),
  ]);
  const productName = String(product?.name ?? "");
  const resolvedEdition = resolveEditionByDate(editions, purchaseMs)
    ?? catalogEdition(catalogEntry)
    ?? resolveLatestEdition(editions);

  if (isCatalogOrderBump(catalogEntry) || (!catalogEntry && isOrderBumpByName(productName))) {
    return await handleOrderBump(db, data);
  }
  if (!catalogEntry || !isCatalogActivationProduct(catalogEntry)) {
    console.log(`Produto ignorado para ativacao HT: ${product?.id} (${productName})`);
    return { ok: true, reason: "product_ignored" };
  }

  const compradorId = await upsertComprador(db, buyer);
  if (!compradorId) return { ok: false, reason: "comprador_error" };

  await syncThbAluno(db, compradorId, buyer);

  const payment = purchase.payment as Record<string, unknown>;
  const price = purchase.price as Record<string, unknown>;
  const { data: compraRow, error: compraError } = await db
    .from("compras")
    .upsert({
      comprador_id: compradorId,
      hotmart_transaction: purchase.transaction,
      produto_id: String(product.id ?? ""),
      produto_nome: product.name,
      produto_ucode: product.ucode ?? null,
      oferta_codigo: offer?.code ?? null,
      moeda: (price?.currency_code as string) ?? "BRL",
      preco: price?.value ?? null,
      preco_original: (purchase.original_offer_price as Record<string, unknown>)?.value ?? null,
      cupom: (purchase.coupon as Record<string, unknown>)?.code ?? null,
      metodo_pagamento: payment?.type ?? null,
      parcelas: payment?.installments_number ?? 1,
      motivo_recusa: payment?.refusal_reason ?? null,
      status: purchase.status,
      hotmart_event: "PURCHASE_APPROVED",
      is_assinatura: purchase.is_subscription ?? false,
      numero_recorrencia: purchase.recurrency_number ?? null,
      produtor_nome: producer?.name ?? null,
      produtor_ucode: producer?.ucode ?? null,
      data_compra: msToISO(purchase.order_date as number),
      data_aprovacao: msToISO(purchase.approved_date as number),
      atualizado_em: new Date().toISOString(),
    }, { onConflict: "hotmart_transaction" })
    .select("id")
    .single();

  if (compraError) {
    console.error("Erro upsert compra:", compraError);
    return { ok: false, reason: "compra_error" };
  }

  const editionId = Number(resolvedEdition?.id ?? catalogEntry?.edition_id ?? 0);
  const produtoAtivacao = catalogEntry.product_name ? String(catalogEntry.product_name) : PRODUTO_ATIVACAO_PADRAO;
  const now = new Date().toISOString();

  // Busca ativação existente pela compra_id primeiro (cobre caso de cart event prévio)
  // Fallback: busca pelo comprador (cobre upgrade de plano — mesmo comprador, nova compra)
  let existingActivation: { id: string; ht_status: string | null } | null = null;

  const { data: byCompra } = await db
    .from("ativacoes")
    .select("id, ht_status")
    .eq("compra_id", compraRow.id)
    .limit(1)
    .maybeSingle();

  if (byCompra?.id) {
    existingActivation = byCompra;
  } else {
    const { data: byComprador } = await db
      .from("ativacoes")
      .select("id, ht_status, compras!inner(comprador_id)")
      .eq("compras.comprador_id", compradorId)
      .like("produto_ativacao", "Holding Total%")
      .limit(1)
      .maybeSingle();
    if (byComprador?.id) existingActivation = byComprador;
  }

  if (!existingActivation?.id) {
    // Nenhuma ativação prévia — criar nova
    const { error: activationError } = await db.from("ativacoes").insert({
      compra_id: compraRow.id,
      produto_ativacao: produtoAtivacao || PRODUTO_ATIVACAO_PADRAO,
      status: "pendente",
      ht_edition_id: editionId || null,
      ht_status: "fazer_onboarding",
      is_socio: false,
      ultima_movimentacao: now,
    });
    if (activationError) {
      console.error("Erro insert ativacao HT:", activationError);
      return { ok: false, reason: "ativacao_error" };
    }
    await notifySlackBuyer({
      nome: String(buyer.name ?? "Sem nome"),
      email: String(buyer.email ?? ""),
      telefone: normalizePhone(buyer.checkout_phone as string),
      dataCompraMs: (purchase.approved_date as number) || (purchase.order_date as number) || null,
      edicao: String(resolvedEdition?.display_name ?? resolvedEdition?.name ?? catalogEditionLabel(catalogEntry)),
      nomeProduto: String(product?.name ?? catalogEntry?.product_name ?? PRODUTO_ATIVACAO_PADRAO),
      valor: (price?.value as number) ?? null,
      moeda: (price?.currency_code as string) ?? "BRL",
      origem,
    });
  } else {
    // Ativação existente — atualizar com dados completos da aprovação
    // Sempre seta ht_edition_id e produto_ativacao
    // Seta ht_status para "fazer_onboarding" apenas se ainda não foi movimentado (null ou pendente legado)
    const updatePayload: Record<string, unknown> = {
      compra_id: compraRow.id,
      produto_ativacao: produtoAtivacao || PRODUTO_ATIVACAO_PADRAO,
      ht_edition_id: editionId || null,
      ultima_movimentacao: now,
    };
    if (!existingActivation.ht_status) {
      updatePayload.ht_status = "fazer_onboarding";
    }
    const { error: activationUpdateError } = await db
      .from("ativacoes")
      .update(updatePayload)
      .eq("id", existingActivation.id);
    if (activationUpdateError) console.error("Erro update ativacao HT:", activationUpdateError);

    // Notifica Slack apenas se ativação estava sem status (primeira aprovação real)
    if (!existingActivation.ht_status) {
      await notifySlackBuyer({
        nome: String(buyer.name ?? "Sem nome"),
        email: String(buyer.email ?? ""),
        telefone: normalizePhone(buyer.checkout_phone as string),
        dataCompraMs: (purchase.approved_date as number) || (purchase.order_date as number) || null,
        edicao: String(resolvedEdition?.display_name ?? resolvedEdition?.name ?? catalogEditionLabel(catalogEntry)),
        nomeProduto: String(product?.name ?? catalogEntry?.product_name ?? PRODUTO_ATIVACAO_PADRAO),
        valor: (price?.value as number) ?? null,
        moeda: (price?.currency_code as string) ?? "BRL",
        origem,
      });
    }
  }

  return { ok: true };
}

async function handleStatusUpdate(db: ReturnType<typeof createClient>, data: Record<string, unknown>, newStatus: string) {
  const purchase = data.purchase as Record<string, unknown>;
  if (!purchase?.transaction) return { ok: false, reason: "no_transaction" };

  const eventName = `PURCHASE_${newStatus}`;
  const { data: compraRow, error } = await db
    .from("compras")
    .update({ status: newStatus, hotmart_event: eventName, atualizado_em: new Date().toISOString() })
    .eq("hotmart_transaction", purchase.transaction as string)
    .select("id")
    .maybeSingle();

  if (error) console.error(`Erro ao atualizar status para ${newStatus}:`, error);

  // Propaga cancelamento/reembolso para ativacoes (ambos ht_status e hm_status)
  const cancelStatuses = new Set(["CANCELLED", "REFUNDED", "CHARGEBACK"]);
  if (compraRow?.id && cancelStatuses.has(newStatus)) {
    const { error: atErr } = await db
      .from("ativacoes")
      .update({
        ht_status: "cancelado",
        hm_status: "cancelado",
        ultima_movimentacao: new Date().toISOString(),
      })
      .eq("compra_id", compraRow.id);
    if (atErr) console.error(`Erro ao cancelar ativacao para compra ${compraRow.id}:`, atErr);
  }

  return { ok: true };
}

async function handleCartEvent(db: ReturnType<typeof createClient>, data: Record<string, unknown>, status: string) {
  const buyer = data.buyer as Record<string, unknown>;
  const purchase = data.purchase as Record<string, unknown>;
  const product = data.product as Record<string, unknown>;
  if (!buyer?.email) return { ok: true, reason: "no_email" };

  const compradorId = await upsertComprador(db, buyer);
  if (!compradorId) return { ok: false, reason: "comprador_error" };

  await syncThbAluno(db, compradorId, buyer);

  const payment = purchase.payment as Record<string, unknown> | undefined;
  const price = purchase.price as Record<string, unknown> | undefined;
  const offer = purchase.offer as Record<string, unknown> | undefined;
  const transaction = purchase.transaction as string | undefined;
  if (!transaction) return { ok: true, reason: "no_transaction" };

  const now = new Date().toISOString();
  const hotmart_event = `PURCHASE_${status}`;

  // Verifica se já existe compra aprovada/concluída — eventos de carrinho não devem regredir o status
  const { data: existingCompra } = await db
    .from("compras")
    .select("id, status")
    .eq("hotmart_transaction", transaction)
    .limit(1)
    .maybeSingle();

  const alreadyFinal = existingCompra?.status && FINAL_STATUSES.has(String(existingCompra.status));

  if (!alreadyFinal) {
    // Insere ou atualiza a compra apenas se ainda não está num status final
    await db
      .from("compras")
      .upsert({
        comprador_id: compradorId,
        hotmart_transaction: transaction,
        produto_id: String(product?.id ?? ""),
        produto_nome: String(product?.name ?? ""),
        oferta_codigo: offer?.code ?? null,
        moeda: (price?.currency_code as string) ?? "BRL",
        preco: price?.value ?? null,
        metodo_pagamento: payment?.type ?? null,
        parcelas: payment?.installments_number ?? 1,
        status,
        hotmart_event,
        data_compra: msToISO(purchase.order_date as number),
        atualizado_em: now,
      }, { onConflict: "hotmart_transaction" })
      .select("id")
      .single();
  }

  // Usa a compra já existente (seja a que acabou de upsert ou a aprovada anterior)
  const compraId = existingCompra?.id ?? (
    await db
      .from("compras")
      .select("id")
      .eq("hotmart_transaction", transaction)
      .limit(1)
      .maybeSingle()
      .then(r => r.data?.id)
  );

  if (!compraId) return { ok: true, reason: "no_compra_id" };

  // Cria ativação se ainda não existe para essa compra
  const { data: existing } = await db
    .from("ativacoes")
    .select("id")
    .eq("compra_id", compraId)
    .limit(1)
    .maybeSingle();

  if (!existing?.id) {
    // Resolve edição para já preencher ht_edition_id
    const purchaseMs = purchaseTimestampMs(purchase);
    const editions = await loadHtEditions(db);
    const resolvedEdition = resolveEditionByDate(editions, purchaseMs) ?? resolveLatestEdition(editions);
    const editionId = Number(resolvedEdition?.id ?? 0);

    const { error: insErr } = await db.from("ativacoes").insert({
      compra_id: compraId,
      produto_ativacao: PRODUTO_ATIVACAO_PADRAO,
      status: "pendente",
      ht_status: "fazer_onboarding",
      ht_edition_id: editionId || null,
      is_socio: false,
      ultima_movimentacao: now,
    });
    if (insErr) console.error("Erro insert ativacao HT (cart event):", insErr);
  }

  return { ok: true };
}

serve(async (req) => {
  if (req.method === "GET") return new Response("OK", { status: 200 });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  if (!HOTMART_HOTTOK) {
    console.error("HOTMART_HOTTOK não configurado nos secrets da Edge Function");
    return new Response(JSON.stringify({ ok: false, reason: "server_misconfigured" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  // Hotmart manda o hottok no corpo (campo top-level "hottok").
  // Compatível também com o header X-Hotmart-Hottok caso a Hotmart mude o formato.
  const receivedFromBody = typeof body.hottok === "string" ? body.hottok : null;
  const receivedFromHeader = req.headers.get("x-hotmart-hottok");
  const received = receivedFromBody ?? receivedFromHeader;
  if (received !== HOTMART_HOTTOK) {
    return new Response(JSON.stringify({ ok: false, reason: "invalid_hottok" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const event = (body.event as string) ?? "";
  const data = body.data as Record<string, unknown>;
  const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  let result: Record<string, unknown> = { ok: true };

  switch (event) {
    case "PURCHASE_APPROVED":
      result = await handlePurchaseApproved(db, data);
      break;
    case "PURCHASE_COMPLETE":
      result = await handleStatusUpdate(db, data, "COMPLETE");
      break;
    case "PURCHASE_CANCELED":
    case "PURCHASE_CANCELLED":
      result = await handleStatusUpdate(db, data, "CANCELLED");
      break;
    case "PURCHASE_REFUNDED":
      result = await handleStatusUpdate(db, data, "REFUNDED");
      break;
    case "PURCHASE_CHARGEBACK":
      result = await handleStatusUpdate(db, data, "CHARGEBACK");
      break;
    case "PURCHASE_OUT_OF_SHOPPING_CART":
      result = await handleCartEvent(db, data, "OUT_OF_SHOPPING_CART");
      break;
    case "PURCHASE_BILLET_PRINTED":
      result = await handleCartEvent(db, data, "BILLET_PRINTED");
      break;
    case "PURCHASE_WAITING_PAYMENT":
      result = await handleCartEvent(db, data, "WAITING_PAYMENT");
      break;
    case "PURCHASE_PROTEST":
      result = await handleStatusUpdate(db, data, "PROTEST");
      break;
    case "PURCHASE_EXPIRED":
      result = await handleStatusUpdate(db, data, "EXPIRED");
      break;
    case "CLUB_FIRST_ACCESS":
      await notifySlackBuyer({
        nome: String((data?.buyer as Record<string, unknown>)?.name ?? "Sem nome"),
        email: String((data?.buyer as Record<string, unknown>)?.email ?? ""),
        telefone: normalizePhone((data?.buyer as Record<string, unknown>)?.checkout_phone as string),
        dataCompraMs: null,
        edicao: "Primeiro acesso ao Club",
        nomeProduto: PRODUTO_ATIVACAO_PADRAO,
        valor: null,
        moeda: "BRL",
        origem: null,
      });
      break;
    default:
      console.log(`Evento nao tratado: ${event}`);
  }

  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
