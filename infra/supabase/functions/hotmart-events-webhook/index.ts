import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const HOTMART_HOTTOK = Deno.env.get("HOTMART_HOTTOK") ?? "";

// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são injetados automaticamente em toda
// Edge Function do Supabase. service_role é interno/confiável aqui (não é a
// credencial do app, que é scoped) — usado só para persistir a compra.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const SLACK_WEBHOOKS: Record<string, string> = {
  HT:      Deno.env.get("SLACK_WEBHOOK_EVENTS_HT")      ?? "",
  HM:      Deno.env.get("SLACK_WEBHOOK_EVENTS_HM")      ?? "",
  HMAIS:   Deno.env.get("SLACK_WEBHOOK_EVENTS_HMAIS")   ?? "",
  CLINICA: Deno.env.get("SLACK_WEBHOOK_EVENTS_CLINICA") ?? "",
  ETHB:    Deno.env.get("SLACK_WEBHOOK_EVENTS_ETHB")    ?? "",
  IMERSAO: Deno.env.get("SLACK_WEBHOOK_EVENTS_IMERSAO") ?? "",
};

// Mapeamento product_id → chave do canal
const PRODUCT_CHANNEL: Record<string, string> = {
  "1560865": "HT",      // Holding Total (ingresso)
  "2414291": "HT",      // VIP - Holding Total
  "5064314": "HM",      // Holding Masters
  "3507214": "HM",      // Holding - Holding Masters
  "6990981": "HMAIS",   // Holding Mais
  "5682989": "CLINICA", // Clínica de Holding Familiar
  "5951389": "ETHB",    // Encontro do Time Holding Brasil
  "1667133": "IMERSAO", // Imersão em Holding Familiar
};

// Nomes legíveis por canal
const CHANNEL_LABEL: Record<string, string> = {
  HT:      "Holding Total",
  HM:      "Holding Masters",
  HMAIS:   "Holding Mais",
  CLINICA: "Clínica em Holding Familiar - Porto Alegre",
  ETHB:    "Encontro do Time Holding Brasil",
  IMERSAO: "Imersão em Holding Familiar - Porto Alegre",
};

function normalizeStr(s: string): string {
  return s.toLowerCase()
    .normalize("NFD")
    .replace(/\p{Mn}/gu, "")
    .replace(/[^\p{L}\p{N}\s]/gu, " "); // descarta chars corrompidos (ex: encoding Latin-1)
}

function resolveChannel(productId: string, productName: string): string | null {
  if (PRODUCT_CHANNEL[productId]) return PRODUCT_CHANNEL[productId];

  const name = normalizeStr(productName);
  if (name.includes("holding total")) return "HT";
  if (name.includes("holding masters")) return "HM";
  if (name.includes("holding mais") || name.includes("hmais")) return "HMAIS";
  if (name.includes("clinica") || (name.includes("cl") && name.includes("nica"))) return "CLINICA";
  if (name.includes("encontro do time") || name.includes("ethb")) return "ETHB";
  if (name.includes("imersao") || (name.includes("imers") && name.includes("holding"))) return "IMERSAO";

  return null;
}

// Tenta extrair o telefone do payload. Hotmart pode mandar em vários formatos:
//   - buyer.checkout_phone (string já formatada)
//   - buyer.phone (string)
//   - buyer.phone_local_code + buyer.phone_number (DDD + número separados)
//   - buyer.documents.phone (raro, contexto B2B)
function extractPhone(buyer: Record<string, unknown>): string | null {
  const candidates: Array<string | null | undefined> = [
    buyer.checkout_phone as string,
    buyer.phone as string,
  ];

  const localCode = buyer.phone_local_code as string | undefined;
  const phoneNumber = buyer.phone_number as string | undefined;
  if (localCode && phoneNumber) candidates.push(`${localCode}${phoneNumber}`);

  for (const raw of candidates) {
    const normalized = normalizePhone(raw);
    if (normalized) return normalized;
  }
  return null;
}

function normalizePhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  let digits = phone.replace(/\D/g, "");
  if (!digits) return null;
  if (!digits.startsWith("55") && (digits.length === 10 || digits.length === 11)) digits = "55" + digits;
  return digits;
}

// Extrai o documento (CPF/CNPJ) do payload da Hotmart. Vários caminhos possíveis.
function extractDocumento(buyer: Record<string, unknown>): string | null {
  const raw = (buyer.document ?? buyer.documento ?? buyer.cpf ?? buyer.cnpj) as string | undefined;
  if (!raw) return null;
  const clean = String(raw).replace(/\D/g, "");
  return clean.length >= 11 ? clean : null;
}

// Infere tipo do documento pelo tamanho (CPF=11, CNPJ=14).
function inferTipoDocumento(doc: string | null | undefined): string | null {
  if (!doc) return null;
  const clean = doc.replace(/\D/g, "");
  return clean.length === 11 ? "CPF" : clean.length === 14 ? "CNPJ" : null;
}

// True se a cidade for Porto Alegre OU o telefone (normalizado p/ 55DDD...) tiver DDD 51.
function isPortoAlegre(city: string | null | undefined, phone: string | null): boolean {
  const cityNorm = city ? normalizeStr(city).trim() : "";
  if (cityNorm === "porto alegre") return true;
  // phone vem como 55 + DDD + número; DDD 51 = Porto Alegre / região metropolitana.
  if (phone && phone.startsWith("55") && phone.substring(2, 4) === "51") return true;
  return false;
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

// Converte epoch (ms) para ISO. Retorna null se ausente/inválido.
function msToIso(ms: number | null | undefined): string | null {
  if (!ms) return null;
  const d = new Date(Number(ms));
  return isNaN(d.getTime()) ? null : d.toISOString();
}

// Lê um valor numérico que a Hotmart pode mandar plano (value: 12) ou aninhado
// (value: { value: 12, currency_value: "BRL" }). Retorna null se não for número.
function readAmount(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  const nested = (v as Record<string, unknown> | null)?.value;
  if (typeof nested === "number" && Number.isFinite(nested)) return nested;
  return null;
}

// Deriva o valor LÍQUIDO do produtor e a TAXA da Hotmart a partir de
// data.commissions[]. O PURCHASE_APPROVED traz um array de comissões, cada uma
// com source/commission_type ∈ {PRODUCER, COPRODUCER, AFFILIATE, MARKETPLACE…}.
//   líquido do produtor = soma das entradas PRODUCER (o que de fato entra pra empresa)
//   taxa Hotmart        = bruto − líquido
// Defensivo: se o array não vier (ou não houver PRODUCER), devolve null/null — o
// webhook grava só o bruto, exatamente como antes (nunca piora o dado existente).
function extractComissao(
  data: Record<string, unknown>,
  gross: number | null,
): { valorLiquido: number | null; taxaProcessamento: number | null } {
  const commissions = data?.commissions;
  if (!Array.isArray(commissions) || commissions.length === 0) {
    return { valorLiquido: null, taxaProcessamento: null };
  }
  let produtor = 0;
  let achouProdutor = false;
  for (const c of commissions as Array<Record<string, unknown>>) {
    const src = String(c.source ?? c.commission_type ?? "").toUpperCase();
    const v = readAmount(c.value);
    if (v == null) continue;
    if (src === "PRODUCER") {
      produtor += v;
      achouProdutor = true;
    }
  }
  if (!achouProdutor) return { valorLiquido: null, taxaProcessamento: null };
  const liquido = Math.round(produtor * 100) / 100;
  const taxa = gross != null ? Math.round((gross - liquido) * 100) / 100 : null;
  return { valorLiquido: liquido, taxaProcessamento: taxa };
}

// Arquiva o payload bruto do evento (best-effort, não-fatal) via RPC SECURITY
// DEFINER. Fonte de verdade para conferência e backfill de líquido/taxa.
async function logHotmartEvento(
  evento: string,
  transacao: string | null,
  email: string | null,
  payload: Record<string, unknown>,
): Promise<void> {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) return;
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await supabase.rpc("fn_log_hotmart_evento", {
      p_evento: evento,
      p_transacao: transacao,
      p_email: email,
      p_payload: payload,
    });
    if (error) console.error("[DB] falha ao arquivar evento Hotmart:", error.message);
  } catch (e) {
    console.error("[DB] exceção em logHotmartEvento:", e instanceof Error ? e.message : e);
  }
}

// Extrai cidade/estado tentando várias localizações conhecidas do payload da
// Hotmart. Em produtos cujo checkout NÃO solicita endereço, todos esses caminhos
// virão vazios — isso só se resolve marcando "endereço obrigatório" no painel.
function extractAddress(
  data: Record<string, unknown>,
  buyer: Record<string, unknown>,
  purchase: Record<string, unknown>,
): { cidade: string | null; estado: string | null } {
  const candidates: Array<Record<string, unknown> | undefined> = [
    buyer.address as Record<string, unknown> | undefined,
    purchase.address as Record<string, unknown> | undefined,
    (data?.subscriber as Record<string, unknown> | undefined)?.address as Record<string, unknown> | undefined,
  ];

  for (const addr of candidates) {
    if (!addr) continue;
    const rawCity = (addr.city ?? addr.address_city ?? addr.cidade) as string | undefined;
    const rawState = (addr.state ?? addr.address_state ?? addr.estado ?? addr.uf) as string | undefined;
    const cidade = rawCity ? String(rawCity).trim() : null;
    const estado = rawState ? String(rawState).trim().substring(0, 2).toUpperCase() : null;
    if (cidade || estado) return { cidade, estado };
  }

  // Fallbacks planos: alguns payloads vêm com campos no nível do buyer/purchase.
  const flatCity = (buyer.address_city ?? buyer.city ?? purchase.address_city) as string | undefined;
  const flatState = (buyer.address_state ?? buyer.state ?? buyer.uf ?? purchase.address_state) as string | undefined;
  return {
    cidade: flatCity ? String(flatCity).trim() : null,
    estado: flatState ? String(flatState).trim().substring(0, 2).toUpperCase() : null,
  };
}

// Extrai a string sck (tracking) de vários caminhos possíveis do payload.
function extractSck(purchase: Record<string, unknown>): string {
  const originObj = purchase.origin as Record<string, unknown> | undefined;
  const trackingParams = purchase.tracking as Record<string, unknown> | undefined;
  const raw =
    originObj?.sck
    ?? originObj?.xcod
    ?? purchase.sck
    ?? purchase.checkout_origin
    ?? trackingParams?.source_sck
    ?? trackingParams?.utm_source
    ?? "";
  return String(raw).trim();
}

async function notifySlack(channel: string, payload: {
  nome: string;
  email: string;
  telefone: string | null;
  produto: string;
  valor: number | null;
  moeda: string;
  dataCompraMs: number | null;
  origem: string | null;
  cidade: string | null;
  estado: string | null;
  markPortoAlegre: boolean;
}) {
  const webhookUrl = SLACK_WEBHOOKS[channel];
  if (!webhookUrl) {
    console.warn(`Webhook não configurado para canal: ${channel}`);
    return;
  }

  const dataFormatada = formatBrDate(payload.dataCompraMs);
  const valorFormatado = payload.valor != null
    ? new Intl.NumberFormat("pt-BR", { style: "currency", currency: payload.moeda || "BRL" }).format(payload.valor)
    : "-";
  const origemLabel = payload.origem || "Não identificada";

  // Região exibida em toda compra para permitir filtro na busca do Slack.
  const cidadeLabel = payload.cidade || "-";
  const estadoLabel = payload.estado || "-";
  const regiaoLabel = `${cidadeLabel}${estadoLabel !== "-" ? ` / ${estadoLabel}` : ""}`;

  const response = await fetch(webhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      text: `Nova compra: ${payload.produto}`,
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: `*Nome:* ${payload.nome}\n*E-mail:* ${payload.email}\n*Telefone:* ${payload.telefone ?? "-"}\n*Produto:* ${payload.produto}\n*Valor:* ${valorFormatado}\n*Origem:* ${origemLabel}\n*Região:* ${regiaoLabel}\n*Data da compra:* ${dataFormatada}`,
          },
        },
        { type: "divider" },
      ],
    }),
  });

  if (!response.ok) {
    console.error(`Falha ao notificar Slack (${channel}):`, response.status, await response.text());
  }
}

// Persiste a compra aprovada nas tabelas canônicas public.compradores / public.compras.
// Idempotente (upsert por email / hotmart_transaction) e NÃO-FATAL: qualquer erro é
// logado, nunca lançado — assim uma falha de DB não provoca retry da Hotmart nem
// atrapalha a notificação do Slack. Reusa o modelo existente (não cria compradores_ht).
async function persistPurchase(args: {
  nome: string;
  email: string;
  telefone: string | null;
  documento: string | null;
  cidade: string | null;
  estado: string | null;
  transaction: string;
  productId: string;
  productName: string;
  offerCode: string | null;
  moeda: string;
  valor: number | null;
  status: string;
  isAssinatura: boolean;
  numeroRecorrencia: number | null;
  metodoPagamento: string | null;
  parcelas: number | null;
  valorLiquido: number | null;
  taxaProcessamento: number | null;
  valorCliente: number | null;
  taxaParcelamento: number | null;
  event: string;
  dataCompraIso: string | null;
  dataAprovacaoIso: string | null;
}): Promise<void> {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("[DB] SUPABASE_URL/SERVICE_ROLE_KEY ausentes — persistência ignorada");
    return;
  }
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const agora = new Date().toISOString();

    // 1) Comprador — upsert por email (UNIQUE). Não sobrescreve criado_em.
    // Documento/tipo só são gravados quando presentes (não apaga valor já existente).
    const compradorPayload: Record<string, unknown> = {
      nome: args.nome,
      email: args.email,
      telefone: args.telefone,
      endereco_cidade: args.cidade,
      endereco_estado: args.estado,
      is_manual: false,
      atualizado_em: agora,
    };
    if (args.documento) {
      compradorPayload.documento = args.documento;
      compradorPayload.tipo_documento = inferTipoDocumento(args.documento);
    }

    const { data: comprador, error: cErr } = await supabase
      .from("compradores")
      .upsert(compradorPayload, { onConflict: "email" })
      .select("id")
      .single();

    if (cErr || !comprador) {
      console.error("[DB] falha ao upsert comprador:", cErr?.message ?? cErr);
      return;
    }

    // 2) Compra — upsert por hotmart_transaction (UNIQUE).
    // Guarda anti-rebaixamento: um evento pendente ou tardio (boleto gerado,
    // aguardando) NÃO pode rebaixar uma compra já paga; um estorno/cancelamento
    // (pós-pago) pode. Rank: pendente(1) < pago(2) < pós-pago/estorno(3).
    const rank = (s: string): number => {
      const u = (s || "").toUpperCase();
      if (["REFUNDED", "CHARGEBACK", "PROTESTED", "CANCELED", "DISPUTE"].includes(u)) return 3;
      if (["APPROVED", "COMPLETE", "COMPLETED"].includes(u)) return 2;
      return 1;
    };
    const { data: existente } = await supabase
      .from("compras")
      .select("status, hotmart_event")
      .eq("hotmart_transaction", args.transaction)
      .maybeSingle();
    const aplicaNovo = !existente || rank(args.status) >= rank(existente.status ?? "");
    const statusEfetivo = aplicaNovo ? args.status : existente!.status;
    const eventoEfetivo = aplicaNovo ? args.event : (existente!.hotmart_event ?? args.event);

    const { error: pErr } = await supabase
      .from("compras")
      .upsert(
        {
          comprador_id: comprador.id,
          hotmart_transaction: args.transaction,
          produto_id: args.productId || null,
          produto_nome: args.productName || null,
          oferta_codigo: args.offerCode,
          moeda: args.moeda || "BRL",
          preco: args.valor,
          status: statusEfetivo,
          is_assinatura: args.isAssinatura,
          numero_recorrencia: args.numeroRecorrencia,
          // Campos que um evento tardio sem o dado NÃO pode apagar (só grava se presente):
          ...(args.metodoPagamento != null ? { metodo_pagamento: args.metodoPagamento } : {}),
          ...(args.parcelas != null ? { parcelas: args.parcelas } : {}),
          // Cascata do dinheiro. Condicionais para NÃO sobrescrever com null um valor
          // já enriquecido (CSV Sales / sync / evento anterior):
          //   valor_com_impostos = full_price  → o que o CLIENTE pagou (com juros)
          //   taxa_parcelamento  = juros retidos pela Hotmart (full_price − preço base)
          //   valor_liquido      = comissão PRODUCER (o que de fato recebemos)
          //   taxa_processamento = comissão MARKETPLACE (taxa da Hotmart)
          ...(args.valorCliente != null ? { valor_com_impostos: args.valorCliente } : {}),
          ...(args.taxaParcelamento != null ? { taxa_parcelamento: args.taxaParcelamento } : {}),
          ...(args.valorLiquido != null ? { valor_liquido: args.valorLiquido } : {}),
          ...(args.taxaProcessamento != null ? { taxa_processamento: args.taxaProcessamento } : {}),
          // Datas condicionais: um evento pendente/estorno (sem approved_date) não zera
          // a data de aprovação já registrada.
          ...(args.dataCompraIso ? { data_compra: args.dataCompraIso } : {}),
          ...(args.dataAprovacaoIso ? { data_aprovacao: args.dataAprovacaoIso } : {}),
          hotmart_event: eventoEfetivo,
          atualizado_em: agora,
        },
        { onConflict: "hotmart_transaction" },
      );

    if (pErr) {
      console.error("[DB] falha ao upsert compra:", pErr.message);
      return;
    }

    console.log(`[DB] compra persistida: ${args.transaction} (${args.email})`);
  } catch (e) {
    console.error("[DB] exceção em persistPurchase:", e instanceof Error ? e.message : e);
  }
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
  // Eventos PAGOS contam de verdade: notificam o Slack (métrica), semeiam a esteira
  // e entram na razão financeira. Os demais são apenas HISTÓRICO do ciclo de vida
  // (boleto gerado, aguardando pagamento, vencido, cancelado, estornado) — gravados
  // na ficha do aluno, SEM Slack e SEM contar. Qualquer outro evento é ignorado.
  const EVENTOS_PAGOS = ["PURCHASE_APPROVED", "PURCHASE_COMPLETE", "PURCHASE_COMPLETED"];
  const EVENTOS_HISTORICO = [
    "PURCHASE_BILLET_PRINTED", "PURCHASE_WAITING_PAYMENT", "PURCHASE_EXPIRED",
    "PURCHASE_CANCELED", "PURCHASE_REFUNDED", "PURCHASE_CHARGEBACK",
    "PURCHASE_PROTEST", "PURCHASE_DELAYED",
  ];
  const isAprovado = EVENTOS_PAGOS.includes(event);
  if (!isAprovado && !EVENTOS_HISTORICO.includes(event)) {
    return new Response(JSON.stringify({ ok: true, reason: "event_ignored" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const data = body.data as Record<string, unknown>;
  const buyer = data?.buyer as Record<string, unknown>;
  const purchase = data?.purchase as Record<string, unknown>;
  const product = data?.product as Record<string, unknown>;

  if (!buyer?.email || !purchase?.transaction) {
    return new Response(JSON.stringify({ ok: false, reason: "incomplete_payload" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const productId = String(product?.id ?? "");
  const productName = String(product?.name ?? "");
  const channel = resolveChannel(productId, productName);

  if (!channel) {
    console.log(`Produto não mapeado para nenhum canal: ${productId} (${productName})`);
    return new Response(JSON.stringify({ ok: true, reason: "product_not_mapped" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const price = purchase.price as Record<string, unknown> | undefined;
  const approvedDate = Number(purchase.approved_date ?? 0) || Number(purchase.order_date ?? 0) || null;
  // Parcelamento (HOTMART_INSTALLMENTS ou cartão parcelado) é modelado como
  // assinatura recorrente pela Hotmart, mas NÃO é renovação. Só é renovação o produto
  // de renovação (3507214) ou uma assinatura recorrente que não seja um parcelamento.
  const paymentInfo = purchase.payment as Record<string, unknown> | undefined;
  const ehParcelamento = paymentInfo?.type === "HOTMART_INSTALLMENTS"
    || Number(paymentInfo?.installments_number ?? 1) > 1;
  const isRenovacao = channel === "HM"
    && !ehParcelamento
    && (
      productId === "3507214"
      || (purchase.is_subscription === true && Number(purchase.recurrency_number ?? 1) > 1)
    );
  const produtoLabel = isRenovacao
    ? "Holding Masters — Renovação"
    : (CHANNEL_LABEL[channel] ?? productName);

  const rawSck = extractSck(purchase);
  const origem = rawSck ? resolveOrigemLabel(rawSck) : null;

  // Endereço do comprador. Tenta vários caminhos conhecidos do payload da Hotmart.
  const { cidade, estado } = extractAddress(data, buyer, purchase);

  const telefone = extractPhone(buyer);
  const documento = extractDocumento(buyer);
  const markPortoAlegre = channel === "HT" && isPortoAlegre(cidade, telefone);

  console.log(`[DIAG ${channel}] documento presente:`, documento != null);
  console.log(`[DIAG ${channel}] productId/name:`, productId, "/", productName, "| isRenovacao:", isRenovacao);

  // Slack SÓ em compra aprovada — é a métrica de vendas do time. Boleto gerado,
  // aguardando, vencido ou estornado NÃO notifica (evita inflar/confundir a contagem).
  if (isAprovado) {
    await notifySlack(channel, {
      nome: String(buyer.name ?? "Sem nome"),
      email: String(buyer.email ?? ""),
      telefone,
      produto: produtoLabel,
      valor: (price?.value as number) ?? null,
      moeda: (price?.currency_code as string) ?? "BRL",
      dataCompraMs: approvedDate,
      origem,
      cidade,
      estado,
      markPortoAlegre,
    });
  }

  // [ADICIONADO] Persiste a compra aprovada no banco (compradores/compras).
  // Roda para todos os canais mapeados (base canônica é multi-produto). É a fonte
  // de contatos do workspace de CS; a esteira de CS é semeada por trigger no banco.
  // O documento (CPF/CNPJ) é gravado APENAS no banco — nunca exposto no Slack.
  const offer = purchase.offer as Record<string, unknown> | undefined;
  const payment = purchase.payment as Record<string, unknown> | undefined;
  const grossValue = readAmount(price?.value) ?? (price?.value as number ?? null);
  // Líquido/taxa derivados das commissions do payload (null se ausentes → grava só bruto).
  const { valorLiquido, taxaProcessamento } = extractComissao(data, grossValue);
  // full_price = o que o CLIENTE paga (com juros de parcelamento). No à-vista é igual
  // ao preço base; no parcelado é maior. Os juros (full_price − base) ficam com a
  // Hotmart, não são nossa receita — mas guardamos p/ reconciliar com o painel Hotmart.
  const fullPrice = purchase.full_price as Record<string, unknown> | undefined;
  const valorCliente = readAmount(fullPrice?.value) ?? (typeof fullPrice?.value === "number" ? fullPrice.value : null);
  const taxaParcelamento = (valorCliente != null && grossValue != null && valorCliente > grossValue)
    ? Math.round((valorCliente - grossValue) * 100) / 100
    : null;

  // Arquiva o payload bruto ANTES de persistir a compra: garante material p/ backfill
  // e conferência mesmo que a gravação em compras falhe. Não-fatal.
  await logHotmartEvento(event, String(purchase.transaction), String(buyer.email), body);

  await persistPurchase({
    nome: String(buyer.name ?? "Sem nome"),
    email: String(buyer.email),
    telefone,
    documento,
    cidade,
    estado,
    transaction: String(purchase.transaction),
    productId,
    productName,
    offerCode: offer?.code ? String(offer.code) : null,
    moeda: (price?.currency_code as string) ?? "BRL",
    valor: (price?.value as number) ?? null,
    // Status real do payload; se ausente, deriva do evento (nunca assume "APPROVED"
    // num evento de boleto/pendente).
    status: String(purchase.status ?? (isAprovado ? "APPROVED" : event.replace("PURCHASE_", ""))),
    isAssinatura: purchase.is_subscription === true,
    numeroRecorrencia: purchase.recurrency_number != null ? Number(purchase.recurrency_number) : null,
    metodoPagamento: payment?.type ? String(payment.type) : null,
    parcelas: payment?.installments_number != null ? Number(payment.installments_number) : null,
    valorLiquido,
    taxaProcessamento,
    valorCliente,
    taxaParcelamento,
    event,
    dataCompraIso: msToIso(Number(purchase.order_date ?? 0) || null),
    dataAprovacaoIso: msToIso(Number(purchase.approved_date ?? 0) || null),
  });

  return new Response(JSON.stringify({ ok: true, channel }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

// Classifica a string sck bruta em rótulo legível.
// Formato sck: "s=Metaads|c=...|m=...|co=...|t=...|utm_id=..."
// ou qualquer string livre como "Comercial", "GPT Maker", etc.
function resolveOrigemLabel(sck: string): string {
  const lower = sck.toLowerCase();

  // Extrai o parâmetro s= quando presente (fonte principal)
  const sMatch = sck.match(/(?:^|[|&])s=([^|&]+)/i);
  const fonte = sMatch ? sMatch[1].trim().toLowerCase() : "";

  if (fonte === "metaads" || lower.includes("metaads") || lower.includes("meta ads") || lower.includes("facebook") || lower.includes("instagram")) {
    return "Meta Ads";
  }
  if (fonte === "google" || lower.includes("google") || lower.includes("googleads") || lower.includes("google ads")) {
    return "Google Ads";
  }
  if (lower.includes("youtube")) return "YouTube Ads";
  if (lower.includes("tiktok")) return "TikTok Ads";
  if (lower.includes("organic") || lower.includes("organico") || lower.includes("orgânico")) return "Orgânico";
  if (lower.includes("email") || lower.includes("e-mail")) return "E-mail Marketing";
  if (
    lower.includes("comercial") || lower.includes("vendas") || lower.includes("sdv") || lower.includes("sdr")
    || lower.includes("closer") || lower.includes("reuniao") || lower.includes("reunião")
    || lower.includes("call") || lower.includes("agendou") || lower.includes("fechamento") || lower.includes("consultor")
  ) return "Comercial";
  // "ia" só bate como token isolado (\bia\b). Antes, includes("ia") capturava
  // qualquer palavra com "ia" no meio (reuniao, consultoria, diaria…) e marcava
  // vendas comerciais como GPT por engano.
  if (lower.includes("gpt") || lower.includes("chatbot") || /\bia\b/.test(lower) || lower.includes("whatsapp bot") || lower.includes("automacao") || lower.includes("automação")) return "GPT / Automação";
  if (lower.includes("hotmart") && (lower.includes("marketplace") || lower.includes("club"))) return "Hotmart Marketplace";
  if (lower.includes("indicacao") || lower.includes("indicação") || lower.includes("referral")) return "Indicação";
  if (lower.includes("direto") || lower.includes("direct")) return "Acesso Direto";

  // Nenhuma regra bateu — retorna a string bruta truncada para não poluir o Slack
  return sck.length > 80 ? sck.substring(0, 80) + "…" : sck;
}
