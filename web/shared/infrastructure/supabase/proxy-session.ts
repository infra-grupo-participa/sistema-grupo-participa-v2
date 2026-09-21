import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { publicEnv } from '@/shared/infrastructure/config/env';
import { ehEmailDaEquipe } from '@/shared/domain/auth';

// Rotas públicas (sem sessão). Fluxos de placa são acessados por token UUID.
const PUBLIC_PREFIXES = [
  '/login',
  '/auth/confirm', // valida o token do link de acesso (sem sessão ainda)
  '/definir-senha', // cria a senha logo após o /auth/confirm
  '/solicitar-placa',
  '/agendar-entrevista',
  '/api/cep',
  '/api/placa',
  '/api/agenda',
  '/api/cron', // autenticação própria via Bearer CRON_SECRET (cron não tem sessão)
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

  // 🔴 `auth.users` é COMPARTILHADA pelos 7 sistemas do grupo. Medido em
  // 21/09/2026: 11.057 contas ativas, das quais apenas 41 são @advmais.com.
  // Ter sessão válida NUNCA significou ser equipe — significa apenas ter
  // comprado algo do grupo. Sem esta linha, o proxy deixava qualquer aluno,
  // lead ou inscrito do CNHF atravessar a porta do sistema interno, e a
  // recusa dependia de cada page.tsx/route.ts lembrar de chamar
  // `getCurrentUser()`. Hoje todos chamam (varrido: 0 arquivos sem checagem),
  // mas "todos lembram hoje" não é fronteira — é coincidência mantida à mão.
  //
  // 🔑 Defesa em profundidade, três camadas independentes:
  //   1. tela de login recusa fora do domínio ANTES de autenticar (...6d89d22)
  //   2. ESTA: o proxy trata sessão de não-equipe como ausência de sessão
  //   3. `GetCurrentUser` (servidor) + `public.gp_eh_equipe()` na RLS
  // A camada 3 é a que vale; esta impede que a 3 seja a ÚNICA.
  //
  // ⚠️ Conferido antes de aplicar: os 21 perfis ativos dev/admin são TODOS
  // @advmais.com — ninguém legítimo é derrubado. A regra vive em
  // `ehEmailDaEquipe` (`@/shared/domain/auth`), que já espelha a função
  // `public.gp_eh_equipe()` do banco: um lugar só, testado.
  const ehEquipe = ehEmailDaEquipe(user?.email);
  const sessaoValida = Boolean(user) && ehEquipe;

  if (!sessaoValida && !isPublic(pathname)) {
    // APIs autenticadas respondem 401 JSON; páginas redirecionam para o login.
    if (pathname.startsWith('/api/')) {
      return NextResponse.json({ error: 'Não autorizado.' }, { status: 401 });
    }
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    // 🔑 Sessão de não-equipe NÃO leva `?redirect=`: ela não vai "voltar para
    // onde estava" depois de entrar — não há para onde voltar. E carregar o
    // destino pretendido de volta ao login só serviria para insistir.
    if (user && !ehEquipe) {
      url.searchParams.set('erro', 'sem_acesso');
    } else {
      url.searchParams.set('redirect', pathname);
    }
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
