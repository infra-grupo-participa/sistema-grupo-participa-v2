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
