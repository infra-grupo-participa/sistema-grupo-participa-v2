import { type NextRequest } from 'next/server';
import { updateSession } from '@/shared/infrastructure/supabase/proxy-session';

// Next.js 16: "Middleware" passou a se chamar Proxy (mesma funcionalidade).
export async function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    // Tudo exceto assets estáticos e otimização de imagem.
    '/((?!_next/static|_next/image|favicon.ico|assets/|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)',
  ],
};
