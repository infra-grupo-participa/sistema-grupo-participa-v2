import { NextResponse } from 'next/server';

// Respostas HTTP do OAuth do MCP. CORS aberto (*) de propósito: são endpoints sem cookie (metadados, registro de
// cliente público, troca de código com PKCE). Quem chama do navegador (inspetor MCP) precisa; não há sessão para roubar.

export const CORS_OAUTH = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, MCP-Protocol-Version',
  'Access-Control-Max-Age': '600',
} as const;

export function jsonOAuth(corpo: unknown, status = 200, extra: Record<string, string> = {}) {
  return NextResponse.json(corpo, {
    status,
    headers: { ...CORS_OAUTH, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...extra },
  });
}

export function preflightOAuth() {
  return new NextResponse(null, { status: 204, headers: CORS_OAUTH });
}
