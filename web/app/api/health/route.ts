import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

// Diagnóstico público — NÃO expõe valores, só presença (boolean) das env vars.
export function GET() {
  const has = (k: string) => Boolean(process.env[k] && String(process.env[k]).length > 0);
  return NextResponse.json({
    ok: true,
    node: process.version,
    env: process.env.NODE_ENV,
    vars: {
      NEXT_PUBLIC_SUPABASE_URL: has('NEXT_PUBLIC_SUPABASE_URL'),
      NEXT_PUBLIC_SUPABASE_ANON_KEY: has('NEXT_PUBLIC_SUPABASE_ANON_KEY'),
      SUPABASE_SERVICE_ROLE_KEY: has('SUPABASE_SERVICE_ROLE_KEY'),
      RESEND_API_KEY: has('RESEND_API_KEY'),
      GROQ_API_KEY: has('GROQ_API_KEY'),
      ZOOM_CLIENT_ID: has('ZOOM_CLIENT_ID'),
      NEXT_PUBLIC_APP_URL: has('NEXT_PUBLIC_APP_URL'),
    },
    time: new Date().toISOString(),
  });
}
