// Rate limit em memória (janela fixa) — porta de api_rate_limit_or_fail.
// O legado usava arquivos em /tmp; na Hostinger Node web app roda um processo único
// persistente, então um Map em memória reproduz a mesma semântica (window_start + count).

interface Bucket {
  windowStart: number;
  count: number;
}

const store = new Map<string, Bucket>();

/**
 * Retorna true se DENTRO do limite, false se estourou (deve responder 429).
 * @param key    identificador (ex.: IP, ou IP+rota)
 * @param prefix namespace do limite (ex.: 'gp_cep_rate_')
 */
export function rateLimitOk(key: string, prefix: string, limit = 20, windowSeconds = 300): boolean {
  const now = Math.floor(Date.now() / 1000);
  const id = prefix + key;
  let bucket = store.get(id);
  if (!bucket || now - bucket.windowStart >= windowSeconds) {
    bucket = { windowStart: now, count: 0 };
  }
  bucket.count += 1;
  store.set(id, bucket);
  return bucket.count <= limit;
}

// Limpeza periódica preguiçosa para não vazar memória em janelas longas.
let lastSweep = 0;
export function sweepRateLimit(maxAgeSeconds = 3600): void {
  const now = Math.floor(Date.now() / 1000);
  if (now - lastSweep < 600) return;
  lastSweep = now;
  for (const [id, bucket] of store) {
    if (now - bucket.windowStart > maxAgeSeconds) store.delete(id);
  }
}
