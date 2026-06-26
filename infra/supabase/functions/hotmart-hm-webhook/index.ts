import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("PROJECT_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SERVICE_ROLE_KEY")!;
const SLACK_WEBHOOK_HM = Deno.env.get("SLACK_WEBHOOK_ATIVACAO") ?? "";
const HOTMART_HOTTOK = Deno.env.get("HOTMART_HOTTOK") ?? "";
const PRODUTO_ATIVACAO = "Holding Masters";

// Statuses que indicam compra já aprovada/concluída — não devem ser sobrescritos por eventos de carrinho
const FINAL_STATUSES = new Set(["APPROVED", "COMPLETE"]);

type TurmaRow = {
  id: number;
  codigo: string;
  sale_start_at: string | null;
  sale_end_at: string | null;
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

function resolvePlanFromOffer(offerCode: string | null): string {
  const map: Record<string, string> = {
    "c648tnjg": "5k",
    "mjxnji3e": "12k",
    "ifrvfqsm": "5k", // downsell → trata como 5k
  };
  if (!offerCode) return "5k";
  return map[offerCode.trim().toLowerCase()] ?? "5k";
}

function isRenovacao(purchase: Record<string, unknown>, productId: string): boolean {
  if (productId === "3507214") return true;
  return (purchase.is_subscription === true) && (Number(purchase.recurrency_number ?? 1) > 1);
}

// Resolve turma HM ativa na data da compra
async function resolveTurmaAtiva(
  db: ReturnType<typeof createClient>,
  purchaseMs: number | null,
): Promise<TurmaRow | null> {
  const purchaseISO = purchaseMs ? new Date(purchaseMs).toISOString() : new Date().toISOString();

  const { data, error } = await db
    .from("thb_turmas")
    .select("id, codigo, sale_start_at, sale_end_at")
    .eq("tipo", "thb")
    .not("sale_start_at", "is", null)
    .lte("sale_start_at", purchaseISO)
    .order("sale_start_at", { ascending: false })
    .limit(10);

  if (error) {
    console.error("Erro ao buscar turma ativa:", error);
    return null;
  }

  const rows = (data ?? []) as TurmaRow[];

  // Prefere turma com carrinho ainda aberto (sale_end_at NULL ou >= dataCompra)
  const aberta = rows.find((t) => !t.sale_end_at || t.sale_end_at >= purchaseISO);
  if (aberta) return aberta;

  // Fallback: turma mais recente que começou antes da compra
  return rows[0] ?? null;
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

async function syncThbAluno(
  db: ReturnType<typeof createClient>,
  compradorId: string,
  buyer: Record<string, unknown>,
  turmaId: number | null,
  isRen: boolean,
): Promise<string | null> {
  const email = String(buyer.email ?? "").trim().toLowerCase();
  if (!email) return null;

  const { data: existingAluno } = await db
    .from("thb_alunos")
    .select("id, comprador_id, turma_id, nome, telefone, documento, cidade, estado, bairro, cep, endereco_logradouro, endereco_numero, endereco_complemento, hotmart_ucode, tipo_documento")
    .ilike("email", email)
    .limit(1)
    .maybeSingle();

  const address = buyer.address as Record<string, unknown> | undefined;
  const doc = buyer.document as string | undefined;
  const now = new Date().toISOString();

  if (existingAluno) {
    const updates: Record<string, unknown> = { atualizado_em: now };
    if (!existingAluno.comprador_id) updates.comprador_id = compradorId;
    // Renovação não muda turma — só compra nova atribui turma
    if (!isRen && !existingAluno.turma_id && turmaId) updates.turma_id = turmaId;
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
    return existingAluno.id;
  }

  const { data: newAluno, error } = await db
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
      turma_id: isRen ? null : (turmaId ?? null),
      fonte: "webhook_hotmart_hm",
      importado_em: now,
      atualizado_em: now,
    })
    .select("id")
    .single();

  if (error) {
    console.error("Erro ao criar thb_aluno via webhook HM:", error);
    return null;
  }
  return newAluno.id;
}

function formatBrDate(ms: number | null | undefined): string {
  if (!ms) return "-";
  const d = new Date(ms);
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

async function notifySlack(payload: {
  nome: string;
  email: string;
  telefone: string | null;
  nomeProduto: string;
  plano: string;
  turma: string | null;
  dataCompraMs: number | null;
  renovacao: boolean;
  valor: number | null;
  moeda: string;
  origem: string | null;
}) {
  if (!SLACK_WEBHOOK_HM) return;

  const dataFormatada = formatBrDate(payload.dataCompraMs);
  const valorFormatado = payload.valor != null
    ? new Intl.NumberFormat("pt-BR", { style: "currency", currency: payload.moeda || "BRL" }).format(payload.valor)
    : "-";
  const origemLabel = payload.origem || "Não identificada";

  const produtoLabel = payload.renovacao ? "Holding Masters — Renovação" : "Holding Masters";

  const response = await fetch(SLACK_WEBHOOK_HM, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      text: payload.renovacao ? "Renovação: Holding Masters" : "Nova compra: Holding Masters",
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: `*Nome:* ${payload.nome}\n*E-mail:* ${payload.email}\n*Telefone:* ${payload.telefone ?? "-"}\n*Produto:* ${produtoLabel}\n*Valor:* ${valorFormatado}\n*Origem:* ${origemLabel}\n*Data da compra:* ${dataFormatada}`,
          },
        },
        { type: "divider" },
      ],
    }),
  });

  if (!response.ok) {
    console.error("Falha ao notificar Slack HM:", response.status, await response.text());
  }
}

async function handleRenovacao(
  db: ReturnType<typeof createClient>,
  data: Record<string, unknown>,
) {
  const buyer = data.buyer as Record<string, unknown>;
  const purchase = data.purchase as Record<string, unknown>;
  const product = data.product as Record<string, unknown>;
  const producer = data.producer as Record<string, unknown> | undefined;

  if (!buyer?.email || !purchase?.transaction) return { ok: false, reason: "incomplete_payload" };

  const offer = purchase.offer as Record<string, unknown> | undefined;
  const offerCode = String(offer?.code ?? "") || null;
  const purchaseMs = purchaseTimestampMs(purchase);
  const plano = resolvePlanFromOffer(offerCode);
  const now = new Date().toISOString();
  const trackingParamsRen = purchase.tracking as Record<string, unknown> | undefined;
  const origemRen = String(
    purchase.checkout_origin ?? trackingParamsRen?.source_sck ?? trackingParamsRen?.utm_source ?? ""
  ).trim() || null;

  const compradorId = await upsertComprador(db, buyer);
  if (!compradorId) return { ok: false, reason: "comprador_error" };

  await syncThbAluno(db, compradorId, buyer, null, true);

  // Upsert compra da renovação
  const payment = purchase.payment as Record<string, unknown>;
  const price = purchase.price as Record<string, unknown>;
  const { data: compraRow, error: compraError } = await db
    .from("compras")
    .upsert({
      comprador_id: compradorId,
      hotmart_transaction: purchase.transaction,
      produto_id: String(product?.id ?? ""),
      produto_nome: product?.name ?? null,
      produto_ucode: product?.ucode ?? null,
      oferta_codigo: offerCode,
      moeda: (price?.currency_code as string) ?? "BRL",
      preco: price?.value ?? null,
      preco_original: (purchase.original_offer_price as Record<string, unknown>)?.value ?? null,
      cupom: (purchase.coupon as Record<string, unknown>)?.code ?? null,
      metodo_pagamento: payment?.type ?? null,
      parcelas: payment?.installments_number ?? 1,
      motivo_recusa: payment?.refusal_reason ?? null,
      status: purchase.status,
      hotmart_event: "PURCHASE_APPROVED",
      is_assinatura: true,
      numero_recorrencia: purchase.recurrency_number ?? null,
      produtor_nome: producer?.name ?? null,
      produtor_ucode: producer?.ucode ?? null,
      data_compra: msToISO(purchase.order_date as number),
      data_aprovacao: msToISO(purchase.approved_date as number),
      atualizado_em: now,
    }, { onConflict: "hotmart_transaction" })
    .select("id")
    .single();

  if (compraError) {
    console.error("Erro upsert compra renovação:", compraError);
    return { ok: false, reason: "compra_error" };
  }

  // Atualiza ativação existente com data de renovação — não muda compra_id (manter referência original)
  const { data: existingActivation } = await db
    .from("ativacoes")
    .select("id, compras!inner(comprador_id)")
    .eq("compras.comprador_id", compradorId)
    .like("produto_ativacao", "Holding Masters%")
    .limit(1)
    .maybeSingle();

  if (existingActivation?.id) {
    await db
      .from("ativacoes")
      .update({
        hm_renovado_em: now,
        hm_plano: plano,
        ultima_movimentacao: now,
      })
      .eq("id", existingActivation.id);
  } else {
    // Aluno renovou mas nunca teve ativação — cria nova (hm_renovado_em null, pois não há "anterior")
    await db.from("ativacoes").insert({
      compra_id: compraRow.id,
      produto_ativacao: PRODUTO_ATIVACAO,
      status: "pendente",
      hm_status: "fazer_onboarding",
      hm_plano: plano,
      hm_renovado_em: null,
      is_socio: false,
      ultima_movimentacao: now,
    });
  }

  const priceRen = purchase.price as Record<string, unknown>;
  await notifySlack({
    nome: String(buyer.name ?? "Sem nome"),
    email: String(buyer.email ?? ""),
    telefone: normalizePhone(buyer.checkout_phone as string),
    nomeProduto: String(product?.name ?? PRODUTO_ATIVACAO),
    plano,
    turma: null,
    dataCompraMs: (purchase.approved_date as number) || purchaseMs || null,
    renovacao: true,
    valor: (priceRen?.value as number) ?? null,
    moeda: (priceRen?.currency_code as string) ?? "BRL",
    origem: origemRen,
  });

  return { ok: true, reason: "renovacao" };
}

async function handlePurchaseApproved(
  db: ReturnType<typeof createClient>,
  data: Record<string, unknown>,
) {
  const buyer = data.buyer as Record<string, unknown>;
  const purchase = data.purchase as Record<string, unknown>;
  const product = data.product as Record<string, unknown>;
  const producer = data.producer as Record<string, unknown> | undefined;

  if (!buyer?.email || !purchase?.transaction) return { ok: false, reason: "incomplete_payload" };

  // Detecta renovação antes de qualquer outra lógica
  if (isRenovacao(purchase, String(product?.id ?? ""))) {
    return await handleRenovacao(db, data);
  }

  const offer = purchase.offer as Record<string, unknown> | undefined;
  const offerCode = String(offer?.code ?? "") || null;
  const purchaseMs = purchaseTimestampMs(purchase);
  const plano = resolvePlanFromOffer(offerCode);
  const trackingParams = purchase.tracking as Record<string, unknown> | undefined;
  const origem = String(
    purchase.checkout_origin ?? trackingParams?.source_sck ?? trackingParams?.utm_source ?? ""
  ).trim() || null;

  // Resolve turma ativa na data da compra
  const turma = await resolveTurmaAtiva(db, purchaseMs);
  if (!turma) console.warn("Nenhuma turma HM ativa encontrada para a compra — aluno ficará sem turma");

  const compradorId = await upsertComprador(db, buyer);
  if (!compradorId) return { ok: false, reason: "comprador_error" };

  await syncThbAluno(db, compradorId, buyer, turma?.id ?? null, false);

  const payment = purchase.payment as Record<string, unknown>;
  const price = purchase.price as Record<string, unknown>;
  const { data: compraRow, error: compraError } = await db
    .from("compras")
    .upsert({
      comprador_id: compradorId,
      hotmart_transaction: purchase.transaction,
      produto_id: String(product?.id ?? ""),
      produto_nome: product?.name ?? null,
      produto_ucode: product?.ucode ?? null,
      oferta_codigo: offerCode,
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

  const now = new Date().toISOString();

  // Busca ativação existente pela compra_id primeiro (cobre caso de cart event prévio)
  // Fallback: busca pelo comprador (cobre upgrade de plano — mesmo comprador, nova compra)
  let existingActivation: { id: string; hm_status: string | null } | null = null;

  const { data: byCompra } = await db
    .from("ativacoes")
    .select("id, hm_status")
    .eq("compra_id", compraRow.id)
    .limit(1)
    .maybeSingle();

  if (byCompra?.id) {
    existingActivation = byCompra;
  } else {
    const { data: byComprador } = await db
      .from("ativacoes")
      .select("id, hm_status, compras!inner(comprador_id)")
      .eq("compras.comprador_id", compradorId)
      .like("produto_ativacao", "Holding Masters%")
      .limit(1)
      .maybeSingle();
    if (byComprador?.id) existingActivation = byComprador;
  }

  if (!existingActivation?.id) {
    // Nenhuma ativação prévia — criar nova
    const { error: activationError } = await db.from("ativacoes").insert({
      compra_id: compraRow.id,
      produto_ativacao: PRODUTO_ATIVACAO,
      status: "pendente",
      hm_status: "fazer_onboarding",
      hm_plano: plano,
      is_socio: false,
      ultima_movimentacao: now,
    });
    if (activationError) {
      console.error("Erro insert ativacao HM:", activationError);
      return { ok: false, reason: "ativacao_error" };
    }
    await notifySlack({
      nome: String(buyer.name ?? "Sem nome"),
      email: String(buyer.email ?? ""),
      telefone: normalizePhone(buyer.checkout_phone as string),
      nomeProduto: String(product?.name ?? PRODUTO_ATIVACAO),
      plano,
      turma: turma?.codigo ?? null,
      dataCompraMs: (purchase.approved_date as number) || purchaseMs || null,
      renovacao: false,
      valor: (price?.value as number) ?? null,
      moeda: (price?.currency_code as string) ?? "BRL",
      origem,
    });
  } else {
    // Ativação existente — atualizar com dados completos da aprovação
    // Seta hm_status para "fazer_onboarding" apenas se ainda estava sem status
    const updatePayload: Record<string, unknown> = {
      compra_id: compraRow.id,
      produto_ativacao: PRODUTO_ATIVACAO,
      hm_plano: plano,
      ultima_movimentacao: now,
    };
    if (!existingActivation.hm_status) {
      updatePayload.hm_status = "fazer_onboarding";
    }
    const { error: updateError } = await db
      .from("ativacoes")
      .update(updatePayload)
      .eq("id", existingActivation.id);
    if (updateError) console.error("Erro update ativacao HM:", updateError);

    // Notifica Slack apenas se ativação estava sem status (primeira aprovação real)
    if (!existingActivation.hm_status) {
      await notifySlack({
        nome: String(buyer.name ?? "Sem nome"),
        email: String(buyer.email ?? ""),
        telefone: normalizePhone(buyer.checkout_phone as string),
        nomeProduto: String(product?.name ?? PRODUTO_ATIVACAO),
        plano,
        turma: turma?.codigo ?? null,
        dataCompraMs: (purchase.approved_date as number) || purchaseMs || null,
        renovacao: false,
        valor: (price?.value as number) ?? null,
        moeda: (price?.currency_code as string) ?? "BRL",
        origem,
      });
    }
  }

  return { ok: true };
}

async function handleStatusUpdate(
  db: ReturnType<typeof createClient>,
  data: Record<string, unknown>,
  newStatus: string,
) {
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

  // Propaga cancelamento/reembolso para ativacoes (ambos hm_status e ht_status)
  const cancelStatuses = new Set(["CANCELLED", "REFUNDED", "CHARGEBACK"]);
  if (compraRow?.id && cancelStatuses.has(newStatus)) {
    const { error: atErr } = await db
      .from("ativacoes")
      .update({
        hm_status: "cancelado",
        ht_status: "cancelado",
        ultima_movimentacao: new Date().toISOString(),
      })
      .eq("compra_id", compraRow.id);
    if (atErr) console.error(`Erro ao cancelar ativacao HM para compra ${compraRow.id}:`, atErr);
  }

  return { ok: true };
}

async function handleCartEvent(
  db: ReturnType<typeof createClient>,
  data: Record<string, unknown>,
  status: string,
) {
  const buyer = data.buyer as Record<string, unknown>;
  const purchase = data.purchase as Record<string, unknown>;
  const product = data.product as Record<string, unknown>;
  if (!buyer?.email) return { ok: true, reason: "no_email" };

  const compradorId = await upsertComprador(db, buyer);
  if (!compradorId) return { ok: false, reason: "comprador_error" };

  const payment = purchase.payment as Record<string, unknown> | undefined;
  const price = purchase.price as Record<string, unknown> | undefined;
  const offer = purchase.offer as Record<string, unknown> | undefined;
  const transaction = purchase.transaction as string | undefined;
  if (!transaction) return { ok: true, reason: "no_transaction" };

  const now = new Date().toISOString();
  const hotmart_event = `PURCHASE_${status}`;
  const offerCode = String(offer?.code ?? "") || null;
  const plano = resolvePlanFromOffer(offerCode);
  const purchaseMs = purchaseTimestampMs(purchase);

  // Resolve turma desde o cart event para já associar ao aluno
  const turma = await resolveTurmaAtiva(db, purchaseMs);

  await syncThbAluno(db, compradorId, buyer, turma?.id ?? null, false);

  // Verifica se já existe compra aprovada/concluída — eventos de carrinho não devem regredir o status
  const { data: existingCompra } = await db
    .from("compras")
    .select("id, status")
    .eq("hotmart_transaction", transaction)
    .limit(1)
    .maybeSingle();

  const alreadyFinal = existingCompra?.status && FINAL_STATUSES.has(String(existingCompra.status));

  if (!alreadyFinal) {
    await db
      .from("compras")
      .upsert({
        comprador_id: compradorId,
        hotmart_transaction: transaction,
        produto_id: String(product?.id ?? ""),
        produto_nome: String(product?.name ?? ""),
        oferta_codigo: offerCode,
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
    const { error: insErr } = await db.from("ativacoes").insert({
      compra_id: compraId,
      produto_ativacao: PRODUTO_ATIVACAO,
      status: "pendente",
      hm_status: "fazer_onboarding",
      hm_plano: plano,
      is_socio: false,
      ultima_movimentacao: now,
    });
    if (insErr) console.error("Erro insert ativacao HM (cart event):", insErr);
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
    case "PURCHASE_WAITING_PAYMENT":
      result = await handleCartEvent(db, data, "WAITING_PAYMENT");
      break;
    case "PURCHASE_BILLET_PRINTED":
      result = await handleCartEvent(db, data, "BILLET_PRINTED");
      break;
    case "PURCHASE_OUT_OF_SHOPPING_CART":
      result = await handleCartEvent(db, data, "OUT_OF_SHOPPING_CART");
      break;
    case "PURCHASE_PROTEST":
      result = await handleStatusUpdate(db, data, "PROTEST");
      break;
    case "PURCHASE_EXPIRED":
      result = await handleStatusUpdate(db, data, "EXPIRED");
      break;
    case "CLUB_FIRST_ACCESS":
      await notifySlack({
        nome: String((data?.buyer as Record<string, unknown>)?.name ?? "Sem nome"),
        email: String((data?.buyer as Record<string, unknown>)?.email ?? ""),
        telefone: normalizePhone((data?.buyer as Record<string, unknown>)?.checkout_phone as string),
        nomeProduto: PRODUTO_ATIVACAO,
        plano: "—",
        turma: null,
        dataCompraMs: null,
        renovacao: false,
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
