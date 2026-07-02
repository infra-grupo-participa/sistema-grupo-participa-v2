'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { normalizeCargo, type Cargo } from '@/shared/domain/auth';
import { CARGO_META, SETOR_META, USER_STATUS, cargosGrantaveis, podeEditarUsuario } from '../domain/cargos';
import {
  Badge,
  Button,
  DataTable,
  Drawer,
  EmptyState,
  FilterSelect,
  Input,
  SearchInput,
  Td,
  Th,
  Thead,
  Toast,
  Toggle,
  Toolbar,
  Tr,
  useFlash,
} from '@/shared/ui/components';
import { fetchJson } from '@/shared/ui/fetch-json';

interface PerfilRow {
  id: string; nome: string | null; email: string | null; cargo: string | null; status: string | null;
  nivel_hierarquia: string | null; eh_dev: boolean | null; pode_ver_cpf_completo: boolean | null; areas: string[] | null; time: string | null;
}

const statusTone: Record<string, 'success' | 'warning' | 'danger' | 'neutral'> = { ativo: 'success', pendente: 'warning', negado: 'danger' };

export function UsuariosClient({ meuCargo }: { meuCargo: Cargo }) {
  const [users, setUsers] = useState<PerfilRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [editId, setEditId] = useState<string | null>(null);
  const [inviteOpen, setInviteOpen] = useState(false);
  const { toast, flash } = useFlash();
  const grantaveis = cargosGrantaveis(meuCargo);

  const reload = useCallback(async () => {
    const r = await fetchJson<{ usuarios?: PerfilRow[] }>('/api/admin/usuarios', { credentials: 'include' });
    setUsers(r.json?.usuarios ?? []);
  }, []);
  useEffect(() => { (async () => { await reload(); setLoading(false); })(); }, [reload]);

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
        {grantaveis.length > 0 && <Button onClick={() => setInviteOpen(true)} className="ml-auto">Convidar usuário</Button>}
      </div>

      <Toolbar className="mb-3">
        <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar nome ou e-mail…" />
      </Toolbar>

      <DataTable>
        <Thead>
          <Th>Usuário</Th>
          <Th>Cargo</Th>
          <Th>Status</Th>
          <Th> </Th>
        </Thead>
        <tbody>
          {filtered.map((u) => {
            const cargo = normalizeCargo(u);
            const editavel = podeEditarUsuario(meuCargo, cargo);
            const st = u.status || 'pendente';
            return (
              <Tr key={u.id}>
                <Td><div className="text-[var(--fg)] font-medium">{u.nome || '—'}</div><div className="text-[var(--fg-3)] text-xs">{u.email}</div></Td>
                <Td className="text-[var(--fg-2)]">{CARGO_META[cargo].label}</Td>
                <Td><Badge tone={statusTone[st] || 'neutral'} dot>{st}</Badge></Td>
                <Td className="text-right">{editavel && <Button variant="ghost" size="sm" onClick={() => setEditId(u.id)}>editar</Button>}</Td>
              </Tr>
            );
          })}
          {!filtered.length && !loading && (
            <tr><td colSpan={4} className="p-0"><EmptyState title="Nenhum usuário." /></td></tr>
          )}
        </tbody>
      </DataTable>

      {editing && <EditDrawer u={editing} meuCargo={meuCargo} onClose={() => setEditId(null)} onSaved={async (m) => { flash(m); setEditId(null); await reload(); }} />}
      {inviteOpen && <InviteDrawer grantaveis={grantaveis} onClose={() => setInviteOpen(false)} onSaved={async (m) => { flash(m); setInviteOpen(false); await reload(); }} />}
      <Toast>{toast}</Toast>
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
    const r = await fetchJson<{ ok?: boolean; error?: string }>('/api/admin/usuarios', {
      method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: u.id, fields: { cargo, status, areas, pode_ver_cpf_completo: cpf } }),
    });
    setBusy(false);
    onSaved(r.json?.ok ? 'Usuário atualizado!' : (r.json?.error || (r.status === 0 ? 'Sem conexão — tente novamente.' : 'Falhou.')));
  }
  const showSetores = cargo === 'gestor' || cargo === 'operador';

  return (
    <Drawer
      onClose={onClose}
      width="max-w-sm"
      title={u.nome || u.email}
      badges={<Badge tone={statusTone[status] || 'neutral'} dot>{status}</Badge>}
    >
      <div className="space-y-3">
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Cargo</span>
          <FilterSelect value={cargo} onChange={(e) => setCargo(e.target.value as Cargo)} className="mt-1">
            {cargoOpts.map((c) => <option key={c} value={c}>{CARGO_META[c].label}</option>)}
          </FilterSelect>
          <span className="text-xs text-[var(--fg-3)]">{CARGO_META[cargo].description}</span>
        </label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Status</span>
          <FilterSelect value={status} onChange={(e) => setStatus(e.target.value)} className="mt-1">
            {USER_STATUS.map((s) => <option key={s} value={s}>{s}</option>)}
          </FilterSelect>
        </label>
        {showSetores && (
          <div><span className="text-xs text-[var(--fg-3)]">Setores</span>
            <div className="mt-1 space-y-1">
              {Object.entries(SETOR_META).map(([k, m]) => (
                <label key={k} className="flex items-center gap-2 text-sm text-[var(--fg)]">
                  <input type="checkbox" className="accent-[var(--accent)]" checked={areas.includes(k)} onChange={(e) => setAreas((a) => (e.target.checked ? [...a, k] : a.filter((x) => x !== k)))} />{m.label}
                </label>
              ))}
            </div>
          </div>
        )}
        <Toggle checked={cpf} onChange={setCpf} label="Pode ver CPF completo (LGPD)" />
        <Button onClick={save} disabled={busy} className="w-full">{busy ? 'Salvando…' : 'Salvar'}</Button>
      </div>
    </Drawer>
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
    const r = await fetchJson<{ ok?: boolean; error?: string }>('/api/admin/usuarios', {
      method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, nome, cargo }),
    });
    setBusy(false);
    if (r.json?.ok) onSaved('Convite enviado!');
    else setErr(r.json?.error || (r.status === 0 ? 'Sem conexão — tente novamente.' : 'Falhou.'));
  }

  return (
    <Drawer onClose={onClose} width="max-w-sm" title="Convidar usuário">
      <div className="space-y-3">
        <label className="block"><span className="text-xs text-[var(--fg-3)]">E-mail</span><Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="mt-1" /></label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Nome</span><Input value={nome} onChange={(e) => setNome(e.target.value)} className="mt-1" /></label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Cargo</span>
          <FilterSelect value={cargo} onChange={(e) => setCargo(e.target.value as Cargo)} className="mt-1">
            {grantaveis.map((c) => <option key={c} value={c}>{CARGO_META[c].label}</option>)}
          </FilterSelect>
        </label>
        {err && <p className="text-sm text-[var(--red)]">{err}</p>}
        <Button onClick={invite} disabled={busy || !email} className="w-full">{busy ? 'Enviando…' : 'Enviar convite'}</Button>
      </div>
    </Drawer>
  );
}
