// Leitura do Google Sheets pela conta de serviço (SHEETS_SA_B64, a mesma das Edges do controle-de-eventos) para a
// mensageria-planilha (migration 20261011120000). Só lê: escopo spreadsheets.readonly. Sem dependência do Deno para
// poder ser testado no vitest do web.

export type ContaServico = { client_email: string; private_key: string; token_uri: string };
export type Aba = { aba: string; valores: string[][] } | { aba: string; erro: string };
type Buscar = (url: string, init?: RequestInit) => Promise<Response>;

// Até a coluna AD e 2.000 linhas: as abas de canal usam até a X (custo) e têm menos de 100 linhas.
export const LIMITE = 'A1:AD2000';

/** 'LIGAÇÃO' → `'LIGAÇÃO'!A1:AD2000` (aspas simples do nome dobradas, como o Sheets exige). */
export function intervalo(aba: string): string {
  return `'${aba.replace(/'/g, "''")}'!${LIMITE}`;
}

function b64url(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemParaBytes(pem: string): Uint8Array {
  const corpo = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s+/g, '');
  const bin = atob(corpo);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function contaDoSegredo(b64: string): ContaServico | null {
  try {
    const sa = JSON.parse(atob(b64));
    return sa?.client_email && sa?.private_key && sa?.token_uri ? sa : null;
  } catch {
    return null;
  }
}

export async function tokenDeAcesso(sa: ContaServico, buscar: Buscar): Promise<string> {
  const agora = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const cab = b64url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = b64url(enc.encode(JSON.stringify({
    iss: sa.client_email, scope: 'https://www.googleapis.com/auth/spreadsheets.readonly',
    aud: sa.token_uri, iat: agora, exp: agora + 3600,
  })));
  const chave = await crypto.subtle.importKey('pkcs8', pemParaBytes(sa.private_key) as BufferSource,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const assinatura = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', chave, enc.encode(`${cab}.${claims}`)));
  const r = await buscar(sa.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${cab}.${claims}.${b64url(assinatura)}`,
    }),
  });
  const j = await r.json().catch(() => ({}));
  // Nunca devolve o corpo da resposta (pode ecoar dado da conta): só o código.
  if (!r.ok || !j?.access_token) throw new Error(`google_token_${r.status}`);
  return j.access_token as string;
}

/**
 * Lê as abas pedidas numa chamada só (values:batchGet, valores formatados como aparecem na tela). Aba que o Google
 * não devolver vira {aba, erro}: o banco trata como cabeçalho não conferido e não poda nada dela.
 */
// 429 do Google = cota por minuto da conta de serviço, que é dividida com outros sistemas (a 1ª rodada automática, em
// 11/10/2026 17:22 UTC, levou 429 nas 4 abas). Espera e tenta de novo; a cota volta no minuto seguinte.
export const ESPERAS_429_MS = [15_000, 30_000]; // cabe no timeout de 60 s do cron
const dormir = (ms: number) => new Promise((ok) => setTimeout(ok, ms));

export async function lerAbas(planilhaId: string, abas: string[], token: string, buscar: Buscar,
                              esperas: number[] = ESPERAS_429_MS, esperar: (ms: number) => Promise<unknown> = dormir): Promise<Aba[]> {
  const qs = new URLSearchParams({ valueRenderOption: 'FORMATTED_VALUE', majorDimension: 'ROWS' });
  for (const a of abas) qs.append('ranges', intervalo(a));
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${encodeURIComponent(planilhaId)}/values:batchGet?${qs}`;
  let r = await buscar(url, { headers: { Authorization: `Bearer ${token}` } });
  for (const ms of esperas) {
    if (r.status !== 429) break;
    await esperar(ms);
    r = await buscar(url, { headers: { Authorization: `Bearer ${token}` } });
  }
  if (!r.ok) return abas.map((aba) => ({ aba, erro: `google_${r.status}` }));
  const j = await r.json().catch(() => null) as { valueRanges?: { range?: string; values?: unknown[][] }[] } | null;
  const ranges = j?.valueRanges ?? [];
  return abas.map((aba, i) => {
    const vr = ranges[i];
    // O Google devolve na mesma ordem dos ranges pedidos; confere o nome por segurança.
    const nome = (vr?.range ?? '').replace(/!.*$/, '').replace(/^'|'$/g, '').replace(/''/g, "'");
    if (!vr || nome !== aba) return { aba, erro: 'aba_nao_veio' };
    return { aba, valores: (vr.values ?? []).map((linha) => linha.map((c) => (c == null ? '' : String(c)))) };
  });
}
