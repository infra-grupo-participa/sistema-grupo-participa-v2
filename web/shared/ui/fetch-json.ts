// fetch de API interno tolerante a falha de rede — nunca rejeita.
// Antes, cada cliente tratava !r.ok mas deixava rejeição de rede (offline/DNS)
// virar unhandled promise rejection dentro de event handlers.

export interface JsonResult<T> {
  ok: boolean;
  status: number; // 0 = falha de rede (sem resposta)
  json: T | null;
}

export async function fetchJson<T = Record<string, unknown>>(input: RequestInfo | URL, init?: RequestInit): Promise<JsonResult<T>> {
  try {
    const r = await fetch(input, init);
    const json = (await r.json().catch(() => null)) as T | null;
    return { ok: r.ok, status: r.status, json };
  } catch {
    return { ok: false, status: 0, json: null };
  }
}
