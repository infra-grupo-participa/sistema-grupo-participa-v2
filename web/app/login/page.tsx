'use client';

import { Suspense, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { Card, Input, Button } from '@/shared/ui/components';

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
    <div className="min-h-dvh grid place-items-center bg-[var(--surface-0)] p-4">
      <Card as="form" onSubmit={entrar} className="w-full max-w-sm p-6">
        <h1 className="text-xl font-bold text-[var(--accent)] text-center">Grupo Participa</h1>
        <p className="mt-1 text-center text-sm text-[var(--fg-3)]">Acesso ao sistema interno</p>

        <label className="mt-6 block text-sm text-[var(--fg-2)]">E-mail</label>
        <Input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoComplete="email"
          required
          className="mt-1"
        />

        <label className="mt-4 block text-sm text-[var(--fg-2)]">Senha</label>
        <Input
          type="password"
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
          autoComplete="current-password"
          required
          className="mt-1"
        />

        {erro && <p className="mt-3 text-sm text-[var(--red)]">{erro}</p>}
        {info && <p className="mt-3 text-sm text-[var(--green)]">{info}</p>}

        <Button type="submit" disabled={loading} className="mt-5 w-full">
          {loading ? 'Entrando…' : 'Entrar'}
        </Button>

        <button
          type="button"
          onClick={recuperar}
          className="mt-3 w-full text-center text-sm text-[var(--fg-3)] hover:text-[var(--fg)]"
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
