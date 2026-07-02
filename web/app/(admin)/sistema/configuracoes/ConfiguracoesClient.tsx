'use client';

import { useState } from 'react';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { useTheme } from '@/shared/ui/shell/use-theme';
import type { GpUser } from '@/shared/domain/auth';
import { SectionCard, Input, Button, Toggle, Badge, Toast, useFlash } from '@/shared/ui/components';

export function ConfiguracoesClient({ user }: { user: GpUser }) {
  const { theme, toggle } = useTheme();
  const [nome, setNome] = useState(user.nome);
  const [avatar, setAvatar] = useState(user.avatarUrl || '');
  const [busy, setBusy] = useState(false);
  const { toast, flash } = useFlash();

  async function salvar() {
    setBusy(true);
    const supabase = createBrowserSupabase();
    const { error } = await supabase.from('perfis').update({ nome: nome.trim(), avatar_url: avatar.trim() || null, atualizado_em: new Date().toISOString() }).eq('id', user.id);
    setBusy(false);
    flash(error ? 'Erro ao salvar.' : 'Perfil atualizado!');
  }

  return (
    <div className="max-w-lg">
      <h1 className="text-2xl font-bold text-[var(--fg)] mb-4">Configurações</h1>

      <SectionCard title="Meu perfil">
        <div className="space-y-3">
          <label className="block">
            <span className="text-xs text-[var(--fg-3)]">Nome</span>
            <Input value={nome} onChange={(e) => setNome(e.target.value)} className="mt-1" />
          </label>
          <label className="block">
            <span className="text-xs text-[var(--fg-3)]">Avatar (URL)</span>
            <Input value={avatar} onChange={(e) => setAvatar(e.target.value)} className="mt-1" />
          </label>
          <div className="flex items-center justify-between gap-2 text-xs text-[var(--fg-3)]">
            <span>E-mail: {user.email}</span>
            <Badge tone="accent">{user.cargo}</Badge>
          </div>
          <Button onClick={salvar} disabled={busy} className="w-full">{busy ? 'Salvando…' : 'Salvar'}</Button>
        </div>
      </SectionCard>

      <SectionCard
        className="mt-4"
        title="Tema"
        subtitle="Claro ou escuro (salvo no navegador)"
        right={<Toggle checked={theme === 'dark'} onChange={toggle} label={theme === 'dark' ? 'Escuro' : 'Claro'} />}
      >
        <span className="sr-only">Alternar tema</span>
      </SectionCard>
      <Toast>{toast}</Toast>
    </div>
  );
}
