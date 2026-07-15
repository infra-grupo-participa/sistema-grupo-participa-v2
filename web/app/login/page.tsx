'use client';

import { Suspense, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { Card, Input, Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const redirect = params.get('redirect') || '/';

  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function entrar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setInfo(null);
    setLoading(true);
    const supabase = createBrowserSupabase();
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: senha });
    setLoading(false);
    if (error) {
      setErro('E-mail ou senha inválidos.');
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
    const supabase = createBrowserSupabase();
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/login`,
    });
    setInfo(error ? null : 'Se o e-mail existir, enviamos as instruções de recuperação.');
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
      <Card as="form" onSubmit={entrar} className="relative w-full max-w-sm p-7 shadow-[var(--shadow-lg)]">
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
          placeholder="voce@grupoparticipa.com.br"
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

        {erro && <p className="mt-3 text-sm text-[var(--red)]">{erro}</p>}
        {info && <p className="mt-3 text-sm text-[var(--green)]">{info}</p>}

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
