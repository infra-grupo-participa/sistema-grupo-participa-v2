'use client';

import { useState } from 'react';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { useTheme } from '@/shared/ui/shell/use-theme';
import type { GpUser } from '@/shared/domain/auth';

export function ConfiguracoesClient({ user }: { user: GpUser }) {
  const { theme, toggle } = useTheme();
  const [nome, setNome] = useState(user.nome);
  const [avatar, setAvatar] = useState(user.avatarUrl || '');
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);

  async function salvar() {
    setBusy(true);
    const supabase = createBrowserSupabase();
    const { error } = await supabase.from('perfis').update({ nome: nome.trim(), avatar_url: avatar.trim() || null, atualizado_em: new Date().toISOString() }).eq('id', user.id);
    setBusy(false);
    setMsg(error ? 'Erro ao salvar.' : 'Perfil atualizado!');
    setTimeout(() => setMsg(''), 3000);
  }

  return (
    <div className="max-w-lg">
      <h1 className="text-2xl font-bold text-[var(--fg)] mb-4">Configurações</h1>

      <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-5 space-y-3">
        <div className="text-sm font-semibold text-[var(--fg)]">Meu perfil</div>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Nome</span>
          <input value={nome} onChange={(e) => setNome(e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" /></label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Avatar (URL)</span>
          <input value={avatar} onChange={(e) => setAvatar(e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" /></label>
        <div className="flex justify-between text-xs text-[var(--fg-3)]"><span>E-mail: {user.email}</span><span>Cargo: {user.cargo}</span></div>
        <button onClick={salvar} disabled={busy} className="w-full py-2 rounded-[var(--r-md)] bg-[var(--accent)] text-black font-semibold disabled:opacity-60">{busy ? 'Salvando…' : 'Salvar'}</button>
        {msg && <p className="text-sm text-[var(--green)]">{msg}</p>}
      </div>

      <div className="mt-4 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-5 flex items-center justify-between">
        <div><div className="text-sm font-semibold text-[var(--fg)]">Tema</div><div className="text-xs text-[var(--fg-3)]">Claro ou escuro (salvo no navegador)</div></div>
        <button onClick={toggle} className="px-4 py-2 rounded-[var(--r-md)] border border-[var(--border)] text-sm text-[var(--fg-2)]">{theme === 'dark' ? '☀ Claro' : '☾ Escuro'}</button>
      </div>
    </div>
  );
}
