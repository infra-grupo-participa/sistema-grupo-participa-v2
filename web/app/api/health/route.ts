import { NextResponse } from 'next/server';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehDev } from '@/shared/domain/auth';
import { env as configEnv } from '@/shared/infrastructure/config/env';

export const dynamic = 'force-dynamic';

// Health check: público responde só {ok:true}. O mapa de env vars (presença, nunca valores)
// ajuda a mapear a superfície do sistema — restrito a dev logado.
export async function GET() {
  const user = await getCurrentUser().catch(() => null);
  if (!user || !ehDev(user)) {
    // Versão publicada: só o commit curto e a hora do build (confirma se o deploy da main entrou no ar).
    return NextResponse.json({ ok: true, versao: configEnv.build.commit, publicado_em: configEnv.build.em });
  }
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
      CRON_SECRET: has('CRON_SECRET'),
    },
    time: new Date().toISOString(),
  });
}
