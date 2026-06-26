import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const HOTMART_HOTTOK = Deno.env.get("HOTMART_HOTTOK") ?? "";

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

function normalizePhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  let digits = phone.replace(/\D/g, "");
  if (!digits) return null;
  if (!digits.startsWith("55") && (digits.length === 10 || digits.length === 11)) digits = "55" + digits;
  return digits;
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
  if (lower.includes("comercial") || lower.includes("vendas") || lower.includes("sdv") || lower.includes("sdr")) return "Comercial";
  if (lower.includes("gpt") || lower.includes("chatbot") || lower.includes("ia") || lower.includes("whatsapp bot")) return "GPT / Automação";
  if (lower.includes("hotmart") && (lower.includes("marketplace") || lower.includes("club"))) return "Hotmart Marketplace";
  if (lower.includes("indicacao") || lower.includes("indicação") || lower.includes("referral")) return "Indicação";
  if (lower.includes("direto") || lower.includes("direct")) return "Acesso Direto";

  // Nenhuma regra bateu — retorna a string bruta truncada para não poluir o Slack
  return sck.length > 80 ? sck.substring(0, 80) + "…" : sck;
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
  if (event !== "PURCHASE_APPROVED") {
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
  const isRenovacao = channel === "HM"
    && (
      productId === "3507214"
      || (purchase.is_subscription === true && Number(purchase.recurrency_number ?? 1) > 1)
    );
  const produtoLabel = isRenovacao
    ? "Holding Masters — Renovação"
    : (CHANNEL_LABEL[channel] ?? productName);

  // origem de checkout: origin.sck > checkout_origin > tracking.source_sck > tracking.utm_source
  const originObj = purchase.origin as Record<string, unknown> | undefined;
  const trackingParams = purchase.tracking as Record<string, unknown> | undefined;
  const rawSck = String(
    originObj?.sck ?? purchase.checkout_origin ?? trackingParams?.source_sck ?? trackingParams?.utm_source ?? ""
  ).trim();
  const origem = rawSck ? resolveOrigemLabel(rawSck) : null;

  // Endereço do comprador (quando disponível no payload).
  const address = buyer.address as Record<string, unknown> | undefined;
  const cidade = address?.city ? String(address.city).trim() : null;
  const estado = address?.state ? String(address.state).trim().substring(0, 2).toUpperCase() : null;

  const telefone = normalizePhone(buyer.checkout_phone as string);

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
  });

  return new Response(JSON.stringify({ ok: true, channel }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
