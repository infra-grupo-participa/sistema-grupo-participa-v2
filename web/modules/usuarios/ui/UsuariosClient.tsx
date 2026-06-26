'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { normalizeCargo, type Cargo } from '@/shared/domain/auth';
import { CARGO_META, SETOR_META, USER_STATUS, cargosGrantaveis, podeEditarUsuario } from '../domain/cargos';

interface PerfilRow {
  id: string; nome: string | null; email: string | null; cargo: string | null; status: string | null;
  nivel_hierarquia: string | null; eh_dev: boolean | null; pode_ver_cpf_completo: boolean | null; areas: string[] | null; time: string | null;
}

const statusColor: Record<string, string> = { ativo: 'var(--green)', pendente: 'var(--yellow)', negado: 'var(--red)' };

export function UsuariosClient({ meuCargo }: { meuCargo: Cargo }) {
  const [users, setUsers] = useState<PerfilRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [editId, setEditId] = useState<string | null>(null);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [toast, setToast] = useState('');
  const grantaveis = cargosGrantaveis(meuCargo);

  const reload = useCallback(async () => {
    const r = await fetch('/api/admin/usuarios', { credentials: 'include' });
    const j = await r.json().catch(() => ({}));
    setUsers(j?.usuarios ?? []);
  }, []);
  useEffect(() => { (async () => { await reload(); setLoading(false); })(); }, [reload]);

  const flash = (m: string) => { setToast(m); setTimeout(() => setToast(''), 3000); };
  const filtered = useMemo(() => {
    const t = q.toLowerCase().trim();
    return users.filter((u) => !t || `${u.nome ?? ''} ${u.email ?? ''}`.toLowerCase().includes(t));
  }, [users, q]);

  const editing = editId ? users.find((u) => u.id === editId) ?? null : null;

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <h1 className="text-2xl font-bold text-[var(--fg)]">Usuários</h1>
        {loading && <span className="text-sm text-[var(--fg-3)]">carregando…</span>}
        {grantaveis.length > 0 && <button onClick={() => setInviteOpen(true)} className="ml-auto px-4 py-2 rounded-[var(--r-md)] bg-[var(--accent)] text-black text-sm font-medium">Convidar usuário</button>}
      </div>
      <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar nome ou e-mail…" className="w-full mb-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />

      <div className="rounded-[var(--r-lg)] border border-[var(--border)] overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-[var(--surface-2)] text-[var(--fg-3)]"><tr>
            <th className="text-left px-3 py-2 font-medium">Usuário</th>
            <th className="text-left px-3 py-2 font-medium">Cargo</th>
            <th className="text-left px-3 py-2 font-medium">Status</th>
            <th className="px-3 py-2"></th>
          </tr></thead>
          <tbody>
            {filtered.map((u) => {
              const cargo = normalizeCargo(u);
              const editavel = podeEditarUsuario(meuCargo, cargo);
              return (
                <tr key={u.id} className="border-t border-[var(--border)]">
                  <td className="px-3 py-2"><div className="text-[var(--fg)] font-medium">{u.nome || '—'}</div><div className="text-[var(--fg-3)] text-xs">{u.email}</div></td>
                  <td className="px-3 py-2 text-[var(--fg-2)]">{CARGO_META[cargo].label}</td>
                  <td className="px-3 py-2"><span className="text-xs font-semibold" style={{ color: statusColor[u.status || 'pendente'] }}>{u.status || 'pendente'}</span></td>
                  <td className="px-3 py-2 text-right">{editavel && <button onClick={() => setEditId(u.id)} className="text-xs text-[var(--accent)]">editar</button>}</td>
                </tr>
              );
            })}
            {!filtered.length && !loading && <tr><td colSpan={4} className="px-3 py-8 text-center text-[var(--fg-3)]">Nenhum usuário.</td></tr>}
          </tbody>
        </table>
      </div>

      {editing && <EditDrawer u={editing} meuCargo={meuCargo} onClose={() => setEditId(null)} onSaved={async (m) => { flash(m); setEditId(null); await reload(); }} />}
      {inviteOpen && <InviteDrawer grantaveis={grantaveis} onClose={() => setInviteOpen(false)} onSaved={async (m) => { flash(m); setInviteOpen(false); await reload(); }} />}
      {toast && <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-[var(--surface-4)] text-[var(--fg)] px-4 py-2 rounded-[var(--r-md)] shadow-[var(--shadow-lg)] text-sm z-[1100]">{toast}</div>}
    </div>
  );
}

function EditDrawer({ u, meuCargo, onClose, onSaved }: { u: PerfilRow; meuCargo: Cargo; onClose: () => void; onSaved: (m: string) => void }) {
  const grantaveis = cargosGrantaveis(meuCargo);
  const atual = normalizeCargo(u);
  const cargoOpts = grantaveis.includes(atual) ? grantaveis : [...grantaveis, atual];
  const [cargo, setCargo] = useState<Cargo>(atual);
  const [status, setStatus] = useState(u.status || 'pendente');
  const [areas, setAreas] = useState<string[]>(u.areas || []);
  const [cpf, setCpf] = useState(!!u.pode_ver_cpf_completo);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    const r = await fetch('/api/admin/usuarios', {
      method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: u.id, fields: { cargo, status, areas, pode_ver_cpf_completo: cpf } }),
    });
    const j = await r.json().catch(() => ({}));
    setBusy(false);
    onSaved(j?.ok ? 'Usuário atualizado!' : (j?.error || 'Falhou.'));
  }
  const showSetores = cargo === 'gestor' || cargo === 'operador';

  return (
    <div className="fixed inset-0 z-[1000] flex justify-end">
      <button aria-label="Fechar" onClick={onClose} className="absolute inset-0 bg-black/50" />
      <div className="relative w-full max-w-sm h-full overflow-y-auto bg-[var(--surface-1)] border-l border-[var(--border)] p-5 space-y-3">
        <div className="flex justify-between"><h2 className="text-lg font-bold text-[var(--fg)]">{u.nome || u.email}</h2><button onClick={onClose} className="text-[var(--fg-3)]">✕</button></div>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Cargo</span>
          <select value={cargo} onChange={(e) => setCargo(e.target.value as Cargo)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]">
            {cargoOpts.map((c) => <option key={c} value={c}>{CARGO_META[c].label}</option>)}
          </select>
          <span className="text-xs text-[var(--fg-3)]">{CARGO_META[cargo].description}</span>
        </label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Status</span>
          <select value={status} onChange={(e) => setStatus(e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]">
            {USER_STATUS.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </label>
        {showSetores && (
          <div><span className="text-xs text-[var(--fg-3)]">Setores</span>
            <div className="mt-1 space-y-1">
              {Object.entries(SETOR_META).map(([k, m]) => (
                <label key={k} className="flex items-center gap-2 text-sm text-[var(--fg)]">
                  <input type="checkbox" checked={areas.includes(k)} onChange={(e) => setAreas((a) => (e.target.checked ? [...a, k] : a.filter((x) => x !== k)))} />{m.label}
                </label>
              ))}
            </div>
          </div>
        )}
        <label className="flex items-center gap-2 text-sm text-[var(--fg)]"><input type="checkbox" checked={cpf} onChange={(e) => setCpf(e.target.checked)} />Pode ver CPF completo (LGPD)</label>
        <button onClick={save} disabled={busy} className="w-full py-2 rounded-[var(--r-md)] bg-[var(--accent)] text-black font-semibold disabled:opacity-60">{busy ? 'Salvando…' : 'Salvar'}</button>
      </div>
    </div>
  );
}

function InviteDrawer({ grantaveis, onClose, onSaved }: { grantaveis: Cargo[]; onClose: () => void; onSaved: (m: string) => void }) {
  const [email, setEmail] = useState('');
  const [nome, setNome] = useState('');
  const [cargo, setCargo] = useState<Cargo>(grantaveis[grantaveis.length - 1] || 'visualizador');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');

  async function invite() {
    setBusy(true); setErr('');
    const r = await fetch('/api/admin/usuarios', {
      method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, nome, cargo }),
    });
    const j = await r.json().catch(() => ({}));
    setBusy(false);
    if (j?.ok) onSaved('Convite enviado!');
    else setErr(j?.error || 'Falhou.');
  }

  return (
    <div className="fixed inset-0 z-[1000] flex justify-end">
      <button aria-label="Fechar" onClick={onClose} className="absolute inset-0 bg-black/50" />
      <div className="relative w-full max-w-sm h-full bg-[var(--surface-1)] border-l border-[var(--border)] p-5 space-y-3">
        <div className="flex justify-between"><h2 className="text-lg font-bold text-[var(--fg)]">Convidar usuário</h2><button onClick={onClose} className="text-[var(--fg-3)]">✕</button></div>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">E-mail</span><input type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" /></label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Nome</span><input value={nome} onChange={(e) => setNome(e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" /></label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Cargo</span>
          <select value={cargo} onChange={(e) => setCargo(e.target.value as Cargo)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]">
            {grantaveis.map((c) => <option key={c} value={c}>{CARGO_META[c].label}</option>)}
          </select>
        </label>
        {err && <p className="text-sm text-[var(--red)]">{err}</p>}
        <button onClick={invite} disabled={busy || !email} className="w-full py-2 rounded-[var(--r-md)] bg-[var(--accent)] text-black font-semibold disabled:opacity-60">{busy ? 'Enviando…' : 'Enviar convite'}</button>
      </div>
    </div>
  );
}
