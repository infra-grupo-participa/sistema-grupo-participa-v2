import type { NextRequest } from 'next/server';
import { clientIp } from '@/shared/infrastructure/http/security';
import { receberPacote } from '@/modules/marketing/web/application/receber-pacote';
import { portasColeta } from '@/modules/marketing/web/infrastructure/coletor-supabase';

// Marketing > Web: porta pública da coleta (o gravador /web/radar-v1.js manda um pacote a cada 3 s).
// Fora do Proxy de sessão (ver matcher em proxy.ts): não tem login, não renova cookie, não redireciona.
// Barreiras: método, origem = domínio de página cadastrada com a coleta ligada, tamanho (64 KB), robô, limite em memória
// por IP; o banco (public.mkt_web_coletar, chave de serviço) confere de novo e aplica o limite por IP e por sessão.
export const dynamic = 'force-dynamic';

function responder(status: number, corpo: string, origem: string | null): Response {
  const h: Record<string, string> = {
    'Content-Type': 'text/plain; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    Vary: 'Origin',
  };
  if (origem) {
    h['Access-Control-Allow-Origin'] = origem;
    h['Access-Control-Allow-Methods'] = 'POST';
  }
  return new Response(corpo, { status, headers: h });
}

/** lê o corpo com teto, sem acreditar no content-length */
async function lerComTeto(request: Request, limite: number): Promise<string | null> {
  if (!request.body) return '';
  const leitor = request.body.getReader();
  const partes: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    total += value.byteLength;
    if (total > limite) {
      await leitor.cancel().catch(() => {});
      return null;
    }
    partes.push(value);
  }
  const tudo = new Uint8Array(total);
  let i = 0;
  for (const p of partes) { tudo.set(p, i); i += p.byteLength; }
  return new TextDecoder().decode(tudo);
}

export async function POST(request: NextRequest) {
  const cl = request.headers.get('content-length');
  const s = await receberPacote({
    metodo: request.method,
    origem: request.headers.get('origin'),
    tamanhoDeclarado: cl && /^\d+$/.test(cl) ? Number(cl) : null,
    userAgent: request.headers.get('user-agent'),
    ip: clientIp(request),
    lerCorpo: (limite) => lerComTeto(request, limite),
  }, portasColeta);
  return responder(s.status, s.resposta, s.origemPermitida);
}

// O gravador manda text/plain sem cabeçalho próprio (pedido simples, sem pré-voo). Se um navegador perguntar mesmo
// assim, a resposta não libera nada além de POST.
export async function OPTIONS() {
  return new Response(null, { status: 204, headers: { 'Access-Control-Allow-Methods': 'POST', 'Cache-Control': 'no-store' } });
}

export async function GET() {
  return responder(405, 'metodo', null);
}
