// Webhook próprio da Remoção de Acessos (pedido do Victor, 16/09/2026).
//
// A Hotmart manda reembolso, chargeback e protesto do Holding Masters para cá.
// Toda a regra mora no banco (public.ra_receber_hotmart): aqui só conferimos o
// hottok e repassamos o payload. Não grava compra, não mexe no financeiro e não
// avisa o canal do time — isso continua no hotmart-events-webhook.
//
// Deploy com verify_jwt = false (a Hotmart não manda JWT; a trava é o hottok).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const HOTMART_HOTTOK = Deno.env.get("HOTMART_HOTTOK") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

serve(async (req) => {
  if (req.method === "GET") return new Response("OK", { status: 200 });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!HOTMART_HOTTOK || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("remocao-acessos-webhook: segredos ausentes");
    return json({ ok: false, reason: "server_misconfigured" }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, reason: "invalid_json" }, 400);
  }

  const recebido = typeof body.hottok === "string" ? body.hottok : req.headers.get("x-hotmart-hottok");
  if (recebido !== HOTMART_HOTTOK) return json({ ok: false, reason: "invalid_hottok" }, 401);
  delete body.hottok; // o segredo não vai para o log do banco

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase.rpc("ra_receber_hotmart", { p_payload: body });
  if (error) {
    // 500 de propósito: a Hotmart reenvia, e o caso não se perde.
    console.error("ra_receber_hotmart falhou:", error.message);
    return json({ ok: false, reason: "db_error" }, 500);
  }
  console.log("remocao-acessos-webhook:", JSON.stringify(data));
  return json(data);
});
