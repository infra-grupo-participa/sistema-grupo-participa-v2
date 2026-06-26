import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { publicEnv } from '@/shared/infrastructure/config/env';

// Rotas públicas (sem sessão). Fluxos de placa são acessados por token UUID.
const PUBLIC_PREFIXES = [
  '/login',
  '/solicitar-placa',
  '/agendar-entrevista',
  '/api/cep',
  '/api/placa',
  '/api/agenda',
];

function isPublic(pathname: string): boolean {
  return PUBLIC_PREFIXES.some((p) => pathname === p || pathname.startsWith(p + '/'));
}

/**
 * Renova a sessão Supabase a cada request e protege rotas autenticadas.
 * Porta da guarda checkAuth()→goLogin() de auth.js para o Proxy do Next 16.
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  // Sem credenciais Supabase → não derruba a request (deixa a página/rota tratar).
  // Evita 500 em cascata quando o build/runtime não recebeu as env vars.
  if (!publicEnv.supabaseUrl || !publicEnv.supabaseAnonKey) {
    return response;
  }

  const supabase = createServerClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { pathname } = request.nextUrl;

  if (!user && !isPublic(pathname)) {
    // APIs autenticadas respondem 401 JSON; páginas redirecionam para o login.
    if (pathname.startsWith('/api/')) {
      return NextResponse.json({ error: 'Não autorizado.' }, { status: 401 });
    }
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    url.searchParams.set('redirect', pathname);
    return NextResponse.redirect(url);
  }

  if (user && pathname === '/login') {
    const url = request.nextUrl.clone();
    url.pathname = '/';
    url.search = '';
    return NextResponse.redirect(url);
  }

  return response;
}
