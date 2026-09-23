import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { publicEnv } from '@/shared/infrastructure/config/env';
import { ehEmailDaEquipe } from '@/shared/domain/auth';
import { PLACA_SESSION_COOKIE } from '@/shared/infrastructure/http/session-cookie';
import { isUuid } from '@/shared/infrastructure/http/validation';

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
 * O que um CANDIDATO de placa pode abrir. Fora disto, ele volta ao formulário.
 *
 * 🔴 Candidato NÃO é usuário do sistema: ele não tem login, é identificado por
 * um token UUID no link e está ali para tocar UM processo — o dele. Sem esta
 * lista, quem tem o cookie da placa podia digitar `/login` e ficar tentando
 * entrar (foi o chamado de 21/09: o candidato insistia numa tela que nunca
 * seria dele), ou bater em `/relatorios/placas` e ser devolvido ao login —
 * convite para tentar de novo, em vez de voltar ao lugar certo.
 *
 * 🔑 `/login` fica DE FORA de propósito: é a tela que o candidato não deve
 * alcançar. `/auth/confirm` e `/definir-senha` também — são do fluxo de conta
 * da EQUIPE, não do candidato.
 *
 * 🔴 `/modelos` É DO CANDIDATO. O botão "Gerar declaração preenchida" (passo 5
 * do formulário) abre `/modelos/declaracao-template.html` em aba nova. O
 * matcher do Proxy só isenta imagens (`svg|png|jpg|jpeg|gif|webp|ico`) — um
 * `.html` em `public/` ATRAVESSA o Proxy como qualquer página. Sem esta
 * entrada, o candidato clicava no botão e caía de volta no próprio formulário:
 * foi o chamado do Renan (23/09), regressão nascida em c8d78b9, o commit que
 * tentava justamente resolver o caso dele.
 *
 * ⚠️ Arquivo novo em `public/` que NÃO seja imagem e precise ser aberto pelo
 * candidato precisa entrar aqui. O teste `proxy-dominio.test.ts` tranca este
 * caso; a regra geral não se descobre sozinha.
 */
const ROTAS_DO_CANDIDATO = [
  '/solicitar-placa',
  '/agendar-entrevista',
  '/modelos',
  '/api/cep',
  '/api/placa',
  '/api/agenda',
];

function ehRotaDoCandidato(pathname: string): boolean {
  return ROTAS_DO_CANDIDATO.some((p) => pathname === p || pathname.startsWith(p + '/'));
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

  // ── Candidato de placa fica no processo dele ──────────────────────────────
  // 🔑 Quem tem `gp_placa_session` é um CANDIDATO: sem login, identificado por
  // token UUID, ali para tocar UM processo. Se ele sair do formulário — por
  // link antigo, histórico do navegador ou digitando a URL — volta ao próprio
  // formulário, em vez de ver a tela de login (que nunca será dele) ou uma
  // recusa que convida a tentar de novo.
  //
  // 🔴 A EQUIPE TEM PRECEDÊNCIA. A checagem exige `!sessaoValida`: alguém da
  // equipe que tenha preenchido uma placa de teste carrega o cookie no mesmo
  // navegador, e sem essa condição ficaria presa no formulário, trancada para
  // fora do próprio sistema.
  //
  // 🔑 Isto NÃO é a fronteira de segurança — é roteamento. O que impede o
  // candidato de LER dado interno é a trava de domínio (abaixo), o
  // `getCurrentUser()` de cada rota e a RLS (`public.gp_eh_equipe()`). Aqui
  // só se decide para onde ele volta. Por isso basta o formato do token: um
  // cookie forjado com UUID aleatório não abre nada — cai no formulário, que
  // vai recusar o token inexistente.
  //
  // 🔑 VÁLVULA DE ESCAPE: `/login?equipe=1`. Quem da equipe já preencheu uma
  // placa de teste carrega o cookie; no dia em que a sessão dele expirar, sem
  // esta saída ele bateria em `/login`, seria mandado ao formulário e não teria
  // como voltar a entrar — preso para fora do próprio sistema, sem pista do
  // porquê. A válvula não enfraquece nada: `/login` já é público, e quem chega
  // lá ainda enfrenta as três camadas de domínio. É roteamento, não permissão.
  const tokenPlaca = request.cookies.get(PLACA_SESSION_COOKIE)?.value ?? '';
  const pedeTelaDaEquipe = pathname === '/login' && request.nextUrl.searchParams.has('equipe');
  const ehCandidato = !sessaoValida && isUuid(tokenPlaca.trim()) && !pedeTelaDaEquipe;

  if (ehCandidato && !ehRotaDoCandidato(pathname)) {
    // API fora do escopo dele responde 401 — redirecionar quebraria o fetch.
    if (pathname.startsWith('/api/')) {
      return NextResponse.json({ error: 'Não autorizado.' }, { status: 401 });
    }
    const url = request.nextUrl.clone();
    url.pathname = '/solicitar-placa';
    url.search = '';
    // Sem `?token=` na URL: o cookie `httpOnly` já identifica a sessão, e
    // reescrever o token na barra de endereço o exporia em histórico,
    // `Referer` e print de tela — é a credencial do processo.
    return NextResponse.redirect(url);
  }

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
