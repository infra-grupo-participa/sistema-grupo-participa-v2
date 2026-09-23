import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Tranca a trava de domínio do Proxy (21/09/2026).
 *
 * 🔴 POR QUE ESTE TESTE LÊ O FONTE em vez de executar `updateSession`:
 * a função monta um `createServerClient` real e fala com o GoTrue. Testá-la
 * de verdade exigiria mockar `@supabase/ssr` inteiro — e um mock que devolve
 * o usuário que EU escolhi não prova nada sobre a regra: provaria só que o
 * mock funciona. O que precisa ficar trancado aqui é **estrutural**: que a
 * decisão de deixar passar leve o domínio em conta, e que ninguém a remova
 * sem o teste acusar.
 *
 * A regra em si (`ehEmailDaEquipe`) já tem teste de comportamento próprio em
 * `shared/domain/auth/gp-user.test.ts`, com os casos de borda (subdomínio,
 * sufixo, prefixo colado, nulo).
 *
 * O contexto que motivou: `auth.users` é compartilhada pelos 7 sistemas do
 * grupo — 11.057 contas em 21/09/2026, 41 delas da equipe. Sessão válida
 * nunca significou "é equipe".
 */

const FONTE = readFileSync(join(__dirname, 'proxy-session.ts'), 'utf8');

describe('proxy — só o domínio da equipe atravessa', () => {
  it('a decisão de acesso usa ehEmailDaEquipe, não só a existência de sessão', () => {
    expect(FONTE).toContain('ehEmailDaEquipe');
    // A guarda tem de exigir as DUAS coisas: sessão E domínio.
    expect(FONTE).toMatch(/sessaoValida\s*=\s*Boolean\(user\)\s*&&\s*ehEquipe/);
    expect(FONTE).toMatch(/if\s*\(!sessaoValida\s*&&\s*!isPublic\(pathname\)\)/);
  });

  it('não reintroduz a guarda antiga, que só olhava a sessão', () => {
    // `if (!user && !isPublic(...))` era exatamente o furo: qualquer conta
    // do grupo atravessava e a recusa dependia de cada page/route lembrar
    // de chamar getCurrentUser().
    expect(FONTE).not.toMatch(/if\s*\(!user\s*&&\s*!isPublic\(pathname\)\)/);
  });

  it('a regra é importada do domínio — não reescrita aqui', () => {
    // Uma segunda cópia da regra divergiria da do banco (public.gp_eh_equipe)
    // no dia em que uma das duas mudasse.
    expect(FONTE).toContain("from '@/shared/domain/auth'");
    // O domínio pode aparecer em COMENTÁRIO (o porquê da trava), nunca em
    // código: nada de `endsWith('@advmais.com')` ou string comparada aqui.
    const semComentarios = FONTE.replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
    expect(semComentarios).not.toContain('advmais');
  });

  it('o formulário público de placa continua alcançável sem sessão', () => {
    // O fluxo do aluno é identificado por token UUID, não por login. Travar
    // o domínio não pode fechar a porta de quem vem pedir a placa.
    for (const rota of ['/solicitar-placa', '/agendar-entrevista', '/api/placa', '/api/cep', '/api/agenda']) {
      expect(FONTE).toContain(`'${rota}'`);
    }
  });

  it('sessão de não-equipe cai no login com erro, e sem levar o destino junto', () => {
    expect(FONTE).toContain("url.searchParams.set('erro', 'sem_acesso')");
  });

  it('API responde 401 em vez de redirecionar', () => {
    expect(FONTE).toMatch(/pathname\.startsWith\('\/api\/'\)/);
    expect(FONTE).toContain('status: 401');
  });
});

/**
 * Confinamento do candidato de placa (21/09/2026).
 *
 * Pedido do Marcio: quem tem processo de placa, ao sair do formulário, volta
 * para o formulário dele — não vê a tela de login nem alcança outra área.
 */
describe('proxy — candidato de placa fica no processo dele', () => {
  it('o cookie da placa é o sinal, e o token é validado como UUID', () => {
    expect(FONTE).toContain('PLACA_SESSION_COOKIE');
    expect(FONTE).toMatch(/isUuid\(tokenPlaca/);
  });

  it('candidato fora das rotas dele volta ao formulário', () => {
    expect(FONTE).toMatch(/if\s*\(ehCandidato\s*&&\s*!ehRotaDoCandidato\(pathname\)\)/);
    expect(FONTE).toMatch(/url\.pathname\s*=\s*'\/solicitar-placa'/);
  });

  it('🔴 a EQUIPE tem precedência — cookie de placa não prende quem tem sessão', () => {
    // Sem `!sessaoValida`, alguém da equipe que preencheu uma placa de teste
    // no mesmo navegador ficaria trancado para fora do próprio sistema.
    expect(FONTE).toMatch(/ehCandidato\s*=\s*!sessaoValida\s*&&/);
  });

  it('/login NÃO está entre as rotas do candidato — é a tela que ele não deve ver', () => {
    const bloco = FONTE.slice(
      FONTE.indexOf('const ROTAS_DO_CANDIDATO'),
      FONTE.indexOf('function ehRotaDoCandidato'),
    );
    expect(bloco).toContain("'/solicitar-placa'");
    expect(bloco).toContain("'/agendar-entrevista'");
    expect(bloco).not.toContain("'/login'");
    // Fluxo de conta da EQUIPE, não do candidato.
    expect(bloco).not.toContain("'/auth/confirm'");
    expect(bloco).not.toContain("'/definir-senha'");
  });

  it('o redirecionamento não escreve o token na URL', () => {
    // O cookie httpOnly já identifica a sessão. Pôr o token na barra de
    // endereço o exporia em histórico, Referer e print — é a credencial.
    const bloco = FONTE.slice(FONTE.indexOf('if (ehCandidato'), FONTE.indexOf('if (!sessaoValida'));
    expect(bloco).toMatch(/url\.search\s*=\s*''/);
    expect(bloco).not.toMatch(/searchParams\.set\('token'/);
  });

  it('API fora do escopo do candidato responde 401, não redireciona', () => {
    const bloco = FONTE.slice(FONTE.indexOf('if (ehCandidato'), FONTE.indexOf('if (!sessaoValida'));
    expect(bloco).toContain('status: 401');
  });

  it('🔑 existe válvula de escape: /login?equipe=1 não é sequestrado', () => {
    // Alguém da equipe que preencheu placa de teste e teve a sessão expirada
    // ficaria preso fora do próprio sistema, sem pista do porquê.
    expect(FONTE).toMatch(/pedeTelaDaEquipe\s*=\s*pathname === '\/login'/);
    expect(FONTE).toMatch(/&&\s*!pedeTelaDaEquipe/);
  });
});
/**
 * Regressão do botão "Gerar declaração preenchida" (23/09/2026).
 *
 * 🔴 O chamado do Renan: clicava em "Gerar declaração preenchida" (passo 5) e
 * voltava para a tela de comprovação. Causa: o botão abre
 * `/modelos/declaracao-template.html`, um arquivo ESTÁTICO em `public/` — e o
 * matcher do Proxy só isenta imagens, então `.html` atravessa o Proxy como
 * página. Fora de `ROTAS_DO_CANDIDATO`, o candidato era devolvido ao
 * formulário. Nasceu em c8d78b9, o commit que tentava resolver o caso dele.
 *
 * Os dois testes abaixo trancam as DUAS metades: a lista tem `/modelos`, e o
 * matcher de fato deixa o `.html` passar (é por isso que a lista precisa dele).
 */
describe('proxy — o candidato alcança o modelo da declaração', () => {
  it('/modelos está entre as rotas do candidato', () => {
    const bloco = FONTE.slice(
      FONTE.indexOf('const ROTAS_DO_CANDIDATO'),
      FONTE.indexOf('function ehRotaDoCandidato'),
    );
    expect(bloco).toContain("'/modelos'");
  });

  it('🔴 o matcher do Proxy NÃO isenta .html — por isso /modelos precisa da entrada', () => {
    // Se um dia o matcher passar a isentar `.html`, este teste cai e avisa que
    // a entrada acima virou redundante — em vez de ela ficar ali sem motivo.
    const proxy = readFileSync(join(__dirname, '..', '..', '..', 'proxy.ts'), 'utf8');
    // O array tem comentário entre `[` e a string — casa a 1ª string do bloco.
    const bloco = proxy.slice(proxy.indexOf('matcher:'));
    const m = bloco.match(/'([^']+)'/);
    expect(m).not.toBeNull();
    // `split/join`, não `replace`: no replacement do replace a barra tem
    // semântica própria e a troca não acontece.
    const padrao = m![1].split('\\\\').join('\\');
    const matcher = new RegExp('^' + padrao + '$');
    expect(matcher.test('/modelos/declaracao-template.html')).toBe(true);
    // Contraprova: imagem é isenta de verdade, então o regex lido é o certo.
    expect(matcher.test('/logo.png')).toBe(false);
  });

  it('a rota do candidato aceita /modelos e o arquivo dentro dele', () => {
    const ROTAS = ['/solicitar-placa', '/agendar-entrevista', '/modelos', '/api/cep', '/api/placa', '/api/agenda'];
    const ehRota = (p: string) => ROTAS.some((r) => p === r || p.startsWith(r + '/'));
    expect(ehRota('/modelos/declaracao-template.html')).toBe(true);
    // E não abre o sistema interno de tabela: prefixo parecido não passa.
    expect(ehRota('/modelos-internos/segredo')).toBe(false);
    expect(ehRota('/relatorios/placas')).toBe(false);
  });
});

/**
 * 🔴 AS DUAS TRAVAS (23/09/2026, segunda rodada).
 *
 * A primeira correção liberou `/modelos` só em `ROTAS_DO_CANDIDATO` e ficou
 * verde — mas em PRODUÇÃO o redirect continuou. O teste media METADE do
 * Proxy: existem DUAS travas em sequência, e a segunda (`isPublic`) barra
 * ANTES de qualquer cookie existir.
 *
 *   1. `ehCandidato && !ehRotaDoCandidato(...)` → volta ao formulário
 *   2. `!sessaoValida && !isPublic(...)`        → manda para /login
 *
 * O candidato não tem sessão de equipe, então SEMPRE cai na 2ª. Medido com
 * curl na produção: 307 para /login MESMO SEM COOKIE — prova de que a causa
 * não era o bloco do candidato.
 *
 * Estes testes percorrem as duas, na ordem real.
 */
describe('proxy — o modelo da declaração passa pelas DUAS travas', () => {
  const listaDe = (nome: string, fim: string) => {
    const t = FONTE.slice(FONTE.indexOf(nome), FONTE.indexOf(fim));
    return [...t.matchAll(/'([^']+)'/g)].map((m) => m[1]);
  };
  const casa = (lista: string[], p: string) =>
    lista.some((r) => p === r || p.startsWith(r + '/'));

  const PUB = listaDe('const PUBLIC_PREFIXES', 'function isPublic');
  const CAND = listaDe('const ROTAS_DO_CANDIDATO', 'function ehRotaDoCandidato');
  const DECL = '/modelos/declaracao-template.html';

  it('🔴 trava 2 (isPublic): sem ela o candidato vai para /login — foi o bug real', () => {
    expect(casa(PUB, DECL)).toBe(true);
  });

  it('trava 1 (candidato): a rota segue liberada no confinamento', () => {
    expect(casa(CAND, DECL)).toBe(true);
  });

  it('🔑 o candidato SEM sessão atravessa as duas e chega no arquivo', () => {
    // Ordem real do Proxy. `sessaoValida` é false: candidato não é equipe.
    const ehCandidato = true;
    const voltaAoFormulario = ehCandidato && !casa(CAND, DECL);
    const vaiProLogin = !voltaAoFormulario && !casa(PUB, DECL);
    expect(voltaAoFormulario).toBe(false);
    expect(vaiProLogin).toBe(false);
  });

  it('visitante SEM cookie nenhum também alcança (é público)', () => {
    // Produção devolvia 307 neste caso — a prova de que faltava isPublic.
    expect(casa(PUB, DECL)).toBe(true);
  });

  it('liberar /modelos NÃO abriu área interna', () => {
    for (const alvo of ['/relatorios/placas', '/financeiro', '/usuarios', '/sistema/admin-dev']) {
      expect(casa(PUB, alvo)).toBe(false);
      expect(casa(CAND, alvo)).toBe(false);
    }
  });
});
