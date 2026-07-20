'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { normalizeCargo, type Cargo } from '@/shared/domain/auth';
import { CARGO_META, USER_STATUS, cargosGrantaveis, podeEditarUsuario } from '../domain/cargos';
import {
  LGPD_ACESSO,
  MODULOS,
  NIVEIS_BASE,
  type NivelBase,
  type NivelBaseMeta,
  estadoDoPerfil,
  niveisBaseGrantaveis,
  perfilDoEstado,
} from '../domain/catalogo-acessos';
import {
  Badge,
  Button,
  DataTable,
  Drawer,
  EmptyState,
  FilterSelect,
  Input,
  SearchInput,
  SkeletonRows,
  Td,
  Th,
  Thead,
  Toast,
  Toolbar,
  Tr,
  useFlash,
} from '@/shared/ui/components';
import { fetchJson } from '@/shared/ui/fetch-json';

interface PerfilRow {
  id: string; nome: string | null; email: string | null; cargo: string | null; status: string | null;
  funcoes: string[] | null; pode_ver_cpf_completo: boolean | null; areas: string[] | null; time: string | null;
}

const statusTone: Record<string, 'success' | 'warning' | 'danger' | 'neutral'> = { ativo: 'success', pendente: 'warning', negado: 'danger' };

function Codigo({ children }: { children: React.ReactNode }) {
  return <code className="rounded-[var(--r-sm)] bg-[var(--surface-2)] px-1 text-[11px] text-[var(--fg-3)] tabular">{children}</code>;
}

function CopyLinkBox({ link }: { link: string }) {
  const [copied, setCopied] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* clipboard bloqueado — o campo já permite copiar manualmente */
    }
  }
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3 space-y-2">
      <p className="text-xs text-[var(--fg-3)]">Envie este link para a pessoa. Ela cria a senha e já entra no sistema.</p>
      <div className="flex gap-2">
        <Input readOnly value={link} onFocus={(e) => e.currentTarget.select()} className="flex-1 text-xs" />
        <Button type="button" size="sm" onClick={copy}>{copied ? 'Copiado!' : 'Copiar'}</Button>
      </div>
    </div>
  );
}

/** Árvore de códigos: nível-base + módulos (3.x) + LGPD (4.1). */
function CatalogoAcessos({
  niveis, base, setBase, areas, setAreas, funcoes, setFuncoes, lgpd, setLgpd,
}: {
  niveis: NivelBaseMeta[];
  base: NivelBase; setBase: (b: NivelBase) => void;
  areas: string[]; setAreas: React.Dispatch<React.SetStateAction<string[]>>;
  funcoes: string[]; setFuncoes: React.Dispatch<React.SetStateAction<string[]>>;
  lgpd: boolean; setLgpd: (v: boolean) => void;
}) {
  const lgpdImplicito = base === 'dev' || base === 'geral';
  return (
    <div className="space-y-3">
      <div>
        <span className="text-xs text-[var(--fg-3)]">Nível de acesso</span>
        <div className="mt-1 space-y-1.5">
          {niveis.map((n) => (
            <label key={n.valor} className="flex items-start gap-2 text-sm text-[var(--fg)] cursor-pointer">
              <input type="radio" name="nivel-base" className="mt-1 accent-[var(--accent)]" checked={base === n.valor} onChange={() => setBase(n.valor)} />
              <span>
                <span className="inline-flex items-center gap-1.5"><Codigo>{n.codigo}</Codigo><span className="font-medium">{n.label}</span></span>
                <span className="block text-[11px] text-[var(--fg-4)]">{n.descricao}</span>
              </span>
            </label>
          ))}
        </div>
      </div>

      {base === 'modulos' && (
        <div className="rounded-[var(--r-lg)] border border-[var(--border)] p-2.5 space-y-3">
          {MODULOS.map((m) => {
            const verObrigatorio = m.acoes.some((a) => funcoes.includes(a.funcao)); // operar implica ver
            return (
              <div key={m.codigo}>
                <div className="flex items-center gap-1.5 text-sm font-medium text-[var(--fg)]"><Codigo>{m.codigo}</Codigo>{m.label}</div>
                <div className="mt-1 ml-1 space-y-1">
                  <label className="flex items-center gap-2 text-sm text-[var(--fg-2)] cursor-pointer">
                    <input
                      type="checkbox" className="accent-[var(--accent)]"
                      checked={areas.includes(m.setor) || verObrigatorio}
                      disabled={verObrigatorio}
                      onChange={(e) => setAreas((a) => (e.target.checked ? [...new Set([...a, m.setor])] : a.filter((x) => x !== m.setor)))}
                    />
                    <span className="inline-flex items-center gap-1.5"><Codigo>{m.verCodigo}</Codigo>{m.verLabel}</span>
                  </label>
                  {m.acoes.map((a) => (
                    <label key={a.codigo} className="flex items-center gap-2 text-sm text-[var(--fg-2)] cursor-pointer">
                      <input
                        type="checkbox" className="accent-[var(--accent)]"
                        checked={funcoes.includes(a.funcao)}
                        onChange={(e) => {
                          setFuncoes((f) => (e.target.checked ? [...new Set([...f, a.funcao])] : f.filter((x) => x !== a.funcao)));
                          if (e.target.checked) setAreas((ar) => [...new Set([...ar, m.setor])]);
                        }}
                      />
                      <span className="inline-flex items-center gap-1.5"><Codigo>{a.codigo}</Codigo>{a.label}</span>
                    </label>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <label className="flex items-center gap-2 text-sm text-[var(--fg)] cursor-pointer">
        <input type="checkbox" className="accent-[var(--accent)]" checked={lgpd || lgpdImplicito} disabled={lgpdImplicito} onChange={(e) => setLgpd(e.target.checked)} />
        <span className="inline-flex items-center gap-1.5"><Codigo>{LGPD_ACESSO.codigo}</Codigo>{LGPD_ACESSO.label}</span>
      </label>
    </div>
  );
}

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
          {loading && !filtered.length && <SkeletonRows rows={4} cols={[72, 64, 48]} />}
          {filtered.map((u) => {
            const cargo = normalizeCargo(u);
            const editavel = podeEditarUsuario(meuCargo, cargo);
            const st = u.status || 'pendente';
            return (
              <Tr key={u.id}>
                <Td><div className="text-[var(--fg)] font-medium truncate">{u.nome || '—'}</div><div className="text-[var(--fg-3)] text-xs truncate">{u.email}</div></Td>
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
      {inviteOpen && <InviteDrawer grantaveis={grantaveis} onClose={() => setInviteOpen(false)} reload={reload} flash={flash} />}
      <Toast>{toast}</Toast>
    </div>
  );
}

function EditDrawer({ u, meuCargo, onClose, onSaved }: { u: PerfilRow; meuCargo: Cargo; onClose: () => void; onSaved: (m: string) => void }) {
  const souDev = meuCargo === 'dev';
  const inicial = useMemo(() => estadoDoPerfil(u), [u]);
  const niveis = useMemo(() => {
    const base = niveisBaseGrantaveis(cargosGrantaveis(meuCargo));
    if (base.some((n) => n.valor === inicial.base)) return base;
    const atual = NIVEIS_BASE.find((n) => n.valor === inicial.base);
    return atual ? [...base, atual] : base;
  }, [meuCargo, inicial.base]);

  const [base, setBase] = useState<NivelBase>(inicial.base);
  const [areas, setAreas] = useState<string[]>(inicial.areas);
  const [funcoes, setFuncoes] = useState<string[]>(inicial.funcoes);
  const [lgpd, setLgpd] = useState<boolean>(inicial.lgpd);
  const [status, setStatus] = useState(u.status || 'pendente');
  const [nome, setNome] = useState(u.nome || '');
  const [time, setTime] = useState(u.time || '');
  const [busy, setBusy] = useState(false);
  const [linking, setLinking] = useState(false);
  const [accessLink, setAccessLink] = useState('');
  const [linkErr, setLinkErr] = useState('');

  async function gerarLink() {
    setLinking(true); setLinkErr(''); setAccessLink('');
    const r = await fetchJson<{ ok?: boolean; error?: string; link?: string }>('/api/admin/usuarios/link', {
      method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: u.id }),
    });
    setLinking(false);
    if (r.json?.ok && r.json.link) setAccessLink(r.json.link);
    else setLinkErr(r.json?.error || (r.status === 0 ? 'Sem conexão — tente novamente.' : 'Falhou.'));
  }

  async function save() {
    setBusy(true);
    const campos = perfilDoEstado({ base, areas, funcoes, lgpd }, { areas: u.areas, funcoes: u.funcoes });
    const fields: Record<string, unknown> = {
      cargo: campos.cargo, status, areas: campos.areas, funcoes: campos.funcoes, pode_ver_cpf_completo: campos.pode_ver_cpf_completo,
    };
    if (souDev) { fields.nome = nome; fields.time = time; }
    const r = await fetchJson<{ ok?: boolean; error?: string }>('/api/admin/usuarios', {
      method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: u.id, fields }),
    });
    setBusy(false);
    onSaved(r.json?.ok ? 'Usuário atualizado!' : (r.json?.error || (r.status === 0 ? 'Sem conexão — tente novamente.' : 'Falhou.')));
  }

  return (
    <Drawer onClose={onClose} width="max-w-sm" title={u.nome || u.email} badges={<Badge tone={statusTone[status] || 'neutral'} dot>{status}</Badge>}>
      <div className="space-y-3">
        {souDev && (
          <>
            <label className="block"><span className="text-xs text-[var(--fg-3)]">Nome</span>
              <Input value={nome} onChange={(e) => setNome(e.target.value)} className="mt-1" />
            </label>
            <label className="block"><span className="text-xs text-[var(--fg-3)]">Equipe / time</span>
              <Input value={time} onChange={(e) => setTime(e.target.value)} placeholder="Ex.: Ativação" className="mt-1" />
            </label>
          </>
        )}

        <CatalogoAcessos
          niveis={niveis} base={base} setBase={setBase}
          areas={areas} setAreas={setAreas} funcoes={funcoes} setFuncoes={setFuncoes}
          lgpd={lgpd} setLgpd={setLgpd}
        />

        <label className="block"><span className="text-xs text-[var(--fg-3)]">Status</span>
          <FilterSelect value={status} onChange={(e) => setStatus(e.target.value)} className="mt-1">
            {USER_STATUS.map((s) => <option key={s} value={s}>{s}</option>)}
          </FilterSelect>
        </label>

        <Button onClick={save} disabled={busy} className="w-full">{busy ? 'Salvando…' : 'Salvar'}</Button>

        <div className="pt-3 border-t border-[var(--border)] space-y-2">
          <p className="text-xs text-[var(--fg-3)]">Acesso: gere um link para a pessoa criar/redefinir a senha e entrar.</p>
          {accessLink ? (
            <CopyLinkBox link={accessLink} />
          ) : (
            <Button variant="ghost" onClick={gerarLink} disabled={linking} className="w-full">{linking ? 'Gerando…' : 'Gerar link de acesso'}</Button>
          )}
          {linkErr && <p className="text-sm text-[var(--red)]">{linkErr}</p>}
        </div>
      </div>
    </Drawer>
  );
}

function InviteDrawer({ grantaveis, onClose, reload, flash }: { grantaveis: Cargo[]; onClose: () => void; reload: () => Promise<void>; flash: (m: string) => void }) {
  const niveis = useMemo(() => niveisBaseGrantaveis(grantaveis), [grantaveis]);
  const [email, setEmail] = useState('');
  const [nome, setNome] = useState('');
  const [base, setBase] = useState<NivelBase>(niveis.find((n) => n.valor === 'visualizador')?.valor ?? niveis[niveis.length - 1]?.valor ?? 'visualizador');
  const [areas, setAreas] = useState<string[]>([]);
  const [funcoes, setFuncoes] = useState<string[]>([]);
  const [lgpd, setLgpd] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [link, setLink] = useState('');

  async function invite() {
    setBusy(true); setErr('');
    const campos = perfilDoEstado({ base, areas, funcoes, lgpd }, { areas: [], funcoes: [] });
    const r = await fetchJson<{ ok?: boolean; error?: string; link?: string }>('/api/admin/usuarios', {
      method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, nome, cargo: campos.cargo, areas: campos.areas, funcoes: campos.funcoes, pode_ver_cpf_completo: campos.pode_ver_cpf_completo }),
    });
    setBusy(false);
    if (r.json?.ok && r.json.link) {
      setLink(r.json.link);
      flash('Usuário criado! Copie o link abaixo.');
      await reload();
    } else {
      setErr(r.json?.error || (r.status === 0 ? 'Sem conexão — tente novamente.' : 'Falhou.'));
    }
  }

  return (
    <Drawer onClose={onClose} width="max-w-sm" title="Convidar usuário">
      <div className="space-y-3">
        {link ? (
          <>
            <div className="text-sm text-[var(--fg)]">{nome || email}</div>
            <CopyLinkBox link={link} />
            <Button variant="ghost" onClick={onClose} className="w-full">Concluir</Button>
          </>
        ) : (
          <>
            <label className="block"><span className="text-xs text-[var(--fg-3)]">E-mail</span><Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="mt-1" /></label>
            <label className="block"><span className="text-xs text-[var(--fg-3)]">Nome</span><Input value={nome} onChange={(e) => setNome(e.target.value)} className="mt-1" /></label>
            <CatalogoAcessos
              niveis={niveis} base={base} setBase={setBase}
              areas={areas} setAreas={setAreas} funcoes={funcoes} setFuncoes={setFuncoes}
              lgpd={lgpd} setLgpd={setLgpd}
            />
            {err && <p className="text-sm text-[var(--red)]">{err}</p>}
            <Button onClick={invite} disabled={busy || !email} className="w-full">{busy ? 'Criando…' : 'Criar e gerar link'}</Button>
          </>
        )}
      </div>
    </Drawer>
  );
}
