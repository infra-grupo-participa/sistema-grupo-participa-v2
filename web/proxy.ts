import { type NextRequest } from 'next/server';
import { updateSession } from '@/shared/infrastructure/supabase/proxy-session';

// Next.js 16: "Middleware" passou a se chamar Proxy (mesma funcionalidade).
export async function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    // Tudo exceto assets estáticos, otimização de imagem, a rota de health (diagnóstico) e a coleta da Web
    // (o gravador das páginas, /web/radar-*.js, e a porta /api/web/coletar: públicos, sem sessão, 1 pacote a cada 3 s
    // por visitante; passar pelo Proxy custaria um getUser() no Supabase por pacote).
    '/((?!_next/static|_next/image|favicon.ico|api/health|api/web/coletar|web/radar-|assets/|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)',
  ],
};
