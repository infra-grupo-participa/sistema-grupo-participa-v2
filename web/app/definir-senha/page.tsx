'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { Card, Input, Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';

export default function DefinirSenhaPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [hasSession, setHasSession] = useState(false);
  const [senha, setSenha] = useState('');
  const [confirma, setConfirma] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // A sessão já foi criada pela rota /auth/confirm (verifyOtp) — aqui só confirmamos.
  useEffect(() => {
    (async () => {
      const supabase = createBrowserSupabase();
      const { data } = await supabase.auth.getUser();
      setHasSession(!!data.user);
      setReady(true);
    })();
  }, []);

  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    if (senha.length < 8) {
      setErro('A senha precisa ter ao menos 8 caracteres.');
      return;
    }
    if (senha !== confirma) {
      setErro('As senhas não coincidem.');
      return;
    }
    setLoading(true);
    const supabase = createBrowserSupabase();
    const { error } = await supabase.auth.updateUser({ password: senha });
    setLoading(false);
    if (error) {
      setErro('Não foi possível salvar a senha. O link pode ter expirado — peça um novo.');
      return;
    }
    router.push('/');
    router.refresh();
  }

  return (
    <div className="min-h-dvh grid place-items-center bg-[var(--surface-0)] p-4">
      <Card className="w-full max-w-sm p-7 shadow-[var(--shadow-lg)] gp-rise">
        <div className="flex flex-col items-center text-center">
          <span
            className="grid h-12 w-12 place-items-center rounded-[var(--r-lg)] text-[var(--accent)]"
            style={{ background: 'color-mix(in srgb, var(--accent) 14%, transparent)' }}
          >
            <Icon name="lock" size={22} />
          </span>
          <h1 className="mt-4 text-xl font-bold text-[var(--fg)]">Grupo Participa</h1>
          <p className="mt-1 text-sm text-[var(--fg-3)]">Defina sua senha de acesso</p>
        </div>

        {!ready && <p className="mt-6 text-center text-sm text-[var(--fg-3)]">Validando link…</p>}

        {ready && !hasSession && (
          <div className="mt-6 text-center">
            <p className="text-sm text-[var(--red)]">Link inválido ou expirado.</p>
            <p className="mt-1 text-sm text-[var(--fg-3)]">Peça um novo link de acesso ao administrador.</p>
            <button
              type="button"
              onClick={() => router.push('/login')}
              className="mt-4 w-full text-center text-sm text-[var(--fg-3)] hover:text-[var(--fg)]"
            >
              Ir para o login
            </button>
          </div>
        )}

        {ready && hasSession && (
          <form onSubmit={salvar}>
            <label className="mt-6 block text-sm font-medium text-[var(--fg-2)]">Nova senha</label>
            <Input
              type="password"
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              autoComplete="new-password"
              required
              revealable
              className="mt-1.5"
            />
            <p className="mt-1.5 text-xs text-[var(--fg-3)]">Use ao menos 8 caracteres.</p>

            <label className="mt-4 block text-sm font-medium text-[var(--fg-2)]">Confirmar senha</label>
            <Input
              type="password"
              value={confirma}
              onChange={(e) => setConfirma(e.target.value)}
              autoComplete="new-password"
              required
              revealable
              className="mt-1.5"
            />

            {erro && <p role="alert" className="mt-3 flex items-center gap-1.5 text-sm text-[var(--red)]"><Icon name="alert" size={14} />{erro}</p>}

            <Button type="submit" disabled={loading} className="mt-5 w-full">
              {loading ? 'Salvando…' : 'Salvar e entrar'}
            </Button>
          </form>
        )}
      </Card>
    </div>
  );
}
