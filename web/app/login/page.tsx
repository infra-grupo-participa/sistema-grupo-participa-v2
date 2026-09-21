'use client';

import { Suspense, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { ehEmailDaEquipe } from '@/shared/domain/auth';
import { Card, Input, Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';

// Mensagem única para credencial inválida E domínio recusado: a tela não revela
// qual dos dois foi, nem qual é o domínio da equipe.
const ERRO_CREDENCIAL = 'E-mail ou senha inválidos.';
const AVISO_RECUPERACAO = 'Se o e-mail existir, enviamos as instruções de recuperação.';

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const redirect = params.get('redirect') || '/';

  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  // 🔑 `?erro=sem_acesso` vem do proxy quando a sessão é válida mas NÃO é da
  // equipe (conta de aluno/lead — `auth.users` é compartilhada pelos 7
  // sistemas). Sem esta mensagem a pessoa cairia num laço mudo: entra, é
  // devolvida ao login, tenta de novo. A frase não cita o domínio — dizer
  // qual é transforma a tela em oráculo para quem tenta adivinhar login
  // (mesma razão da recusa genérica em `entrar`, commit 6d89d22).
  const [erro, setErro] = useState<string | null>(
    params.get('erro') === 'sem_acesso'
      ? 'Esta conta não tem acesso ao sistema interno. Use a conta corporativa da equipe.'
      : null,
  );
  const [info, setInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function entrar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setInfo(null);
    setLoading(true);
    // `auth.users` é compartilhada pelos 7 sistemas do grupo: a credencial de um
    // aluno autentica aqui também. A checagem vem ANTES de `signInWithPassword` —
    // e-mail de fora nem chega ao servidor, não cria sessão e a senha não sai do
    // navegador. Mensagem idêntica à de credencial inválida, de propósito: dizer
    // "domínio errado" entregaria a quem está tentando qual domínio procurar.
    if (!ehEmailDaEquipe(email)) {
      setLoading(false);
      setErro(ERRO_CREDENCIAL);
      return;
    }
    const supabase = createBrowserSupabase();
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: senha });
    setLoading(false);
    if (error) {
      setErro(ERRO_CREDENCIAL);
      return;
    }
    router.push(redirect);
    router.refresh();
  }

  async function recuperar() {
    if (!email.trim()) {
      setErro('Informe o e-mail para recuperar a senha.');
      return;
    }
    setErro(null);
    // Fora do domínio: responde o mesmo texto neutro, sem disparar e-mail nenhum.
    // Assim a tela não serve de oráculo para descobrir quem é da equipe.
    if (!ehEmailDaEquipe(email)) {
      setInfo(AVISO_RECUPERACAO);
      return;
    }
    const supabase = createBrowserSupabase();
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/login`,
    });
    setInfo(error ? null : AVISO_RECUPERACAO);
    if (error) setErro('Não foi possível enviar a recuperação agora.');
  }

  return (
    <div className="relative min-h-dvh grid place-items-center overflow-hidden bg-[var(--surface-0)] p-4">
      {/* Brilho de fundo sutil, herdando o accent — dá profundidade sem imagem externa. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-60"
        style={{ background: 'radial-gradient(60% 45% at 50% 0%, color-mix(in srgb, var(--accent) 18%, transparent), transparent 70%)' }}
      />
      <Card as="form" onSubmit={entrar} className="relative w-full max-w-sm p-7 shadow-[var(--shadow-lg)] gp-rise">
        <div className="flex flex-col items-center text-center">
          <span
            className="grid h-12 w-12 place-items-center rounded-[var(--r-lg)] text-[var(--accent)]"
            style={{ background: 'color-mix(in srgb, var(--accent) 14%, transparent)' }}
          >
            <Icon name="lock" size={22} />
          </span>
          <h1 className="mt-4 text-xl font-bold text-[var(--fg)]">Grupo Participa</h1>
          <p className="mt-1 text-sm text-[var(--fg-3)]">Acesso ao sistema interno</p>
        </div>

        <label className="mt-7 block text-sm font-medium text-[var(--fg-2)]">E-mail</label>
        <Input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoComplete="email"
          placeholder="seu e-mail corporativo"
          required
          className="mt-1.5"
        />

        <label className="mt-4 block text-sm font-medium text-[var(--fg-2)]">Senha</label>
        <Input
          type="password"
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
          autoComplete="current-password"
          placeholder="••••••••"
          required
          revealable
          className="mt-1.5"
        />

        {erro && <p role="alert" className="mt-3 flex items-center gap-1.5 text-sm text-[var(--red)]"><Icon name="alert" size={14} />{erro}</p>}
        {info && <p role="status" className="mt-3 flex items-center gap-1.5 text-sm text-[var(--green)]"><Icon name="check" size={14} />{info}</p>}

        <Button type="submit" disabled={loading} className="mt-6 w-full">
          {loading ? 'Entrando…' : 'Entrar'}
        </Button>

        <button
          type="button"
          onClick={recuperar}
          className="mt-3 w-full text-center text-sm text-[var(--fg-3)] transition-colors hover:text-[var(--fg)]"
        >
          Esqueci minha senha
        </button>
      </Card>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
