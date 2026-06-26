'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { NivelBadge, DataTable, Thead, Th, Tr, Td, EmptyState } from '@/shared/ui/components';
import {
  type Curso,
  type DepoimentoView,
  type Depoimento,
  type Tag,
  deleteCurso,
  deleteTag,
  generateHighlights,
  loadCursos,
  loadDepoimento,
  loadDepoimentosView,
  loadTags,
  saveCurso,
  saveDepoimento,
  saveTag,
} from './depoimentos-data';

type Tab = 'biblioteca' | 'cursos' | 'tags';

export function DepoimentosClient({ canEdit }: { canEdit: boolean }) {
  const [tab, setTab] = useState<Tab>('biblioteca');
  const [rows, setRows] = useState<DepoimentoView[]>([]);
  const [q, setQ] = useState('');
  const [openId, setOpenId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState('');

  const reload = useCallback(async () => setRows(await loadDepoimentosView()), []);
  useEffect(() => {
    (async () => { await reload(); setLoading(false); })();
    const applyHash = () => {
      const h = window.location.hash.replace('#', '');
      setTab(h === 'cursos' ? 'cursos' : h === 'tags' ? 'tags' : 'biblioteca');
    };
    applyHash();
    window.addEventListener('hashchange', applyHash);
    return () => window.removeEventListener('hashchange', applyHash);
  }, [reload]);

  const flash = (m: string) => { setToast(m); setTimeout(() => setToast(''), 3000); };

  const filtered = useMemo(() => {
    const t = q.toLowerCase().trim();
    return rows.filter((r) => !t || `${r.aluno_nome ?? ''} ${r.aluno_email ?? ''} ${r.profissao_resolvida ?? ''}`.toLowerCase().includes(t));
  }, [rows, q]);

  return (
    <div>
      <h1 className="text-2xl font-bold text-[var(--fg)] mb-1">Depoimentos</h1>
      <p className="text-sm text-[var(--fg-3)] mb-4">Biblioteca de depoimentos, cursos e tags. {loading && 'carregando…'}</p>

      <div className="flex gap-2 mb-4 border-b border-[var(--border)]">
        {(['biblioteca', 'cursos', 'tags'] as Tab[]).map((t) => (
          <button key={t} onClick={() => { setTab(t); window.location.hash = t; }} className={`px-4 py-2 text-sm font-medium border-b-2 capitalize ${tab === t ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)]'}`}>{t}</button>
        ))}
        <a href="/depoimentos/biblioteca" className="ml-auto px-4 py-2 text-sm text-[var(--accent)]">Para Copy →</a>
      </div>

      {tab === 'biblioteca' && (
        <>
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar aluno, e-mail, profissão…" className="w-full mb-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
          <DataTable>
            <Thead>
              <Th>Aluno</Th>
              <Th>Nível</Th>
              <Th>Data</Th>
              <Th>Conteúdo</Th>
            </Thead>
            <tbody>
              {filtered.map((r) => (
                <Tr key={r.depoimento_id} onClick={() => setOpenId(r.depoimento_id)}>
                  <Td><div className="text-[var(--fg)] font-medium">{r.aluno_nome || '—'}</div><div className="text-[var(--fg-3)] text-xs">{r.profissao_resolvida || r.aluno_email}</div></Td>
                  <Td><NivelBadge nivel={r.aluno_nivel_resultado} /></Td>
                  <Td className="text-[var(--fg-2)] tabular">{r.testimonial_date ? new Date(r.testimonial_date).toLocaleDateString('pt-BR') : '—'}</Td>
                  <Td className="text-sm">{[r.video_url && '🎬', r.transcript && '📝', r.foto_url && '📷'].filter(Boolean).join(' ') || <span className="text-[var(--fg-3)]">—</span>}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
          {!filtered.length && !loading && <EmptyState title="Nenhum depoimento" icon="💬" />}
        </>
      )}

      {tab === 'cursos' && <CursosTab canEdit={canEdit} flash={flash} />}
      {tab === 'tags' && <TagsTab canEdit={canEdit} flash={flash} />}

      {openId && <DepoimentoDrawer id={openId} canEdit={canEdit} onClose={() => setOpenId(null)} onSaved={async (m) => { flash(m); await reload(); }} />}
      {toast && <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-[var(--surface-4)] text-[var(--fg)] px-4 py-2 rounded-[var(--r-md)] shadow-[var(--shadow-lg)] text-sm z-[1100]">{toast}</div>}
    </div>
  );
}

function DepoimentoDrawer({ id, canEdit, onClose, onSaved }: { id: string; canEdit: boolean; onClose: () => void; onSaved: (m: string) => void }) {
  const [d, setD] = useState<Depoimento | null>(null);
  const [transcript, setTranscript] = useState('');
  const [busy, setBusy] = useState(false);
  const [hlMsg, setHlMsg] = useState('');

  const load = useCallback(async () => {
    const dep = await loadDepoimento(id);
    setD(dep);
    setTranscript(dep?.transcript || '');
  }, [id]);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { load(); }, [load]);

  if (!d) return null;
  const hls = Array.isArray(d.highlights) ? d.highlights : [];

  async function persist(fields: Partial<Depoimento>, msg: string) {
    setBusy(true);
    const r = await saveDepoimento(id, fields);
    setBusy(false);
    if (r.ok) { onSaved(msg); load(); } else setHlMsg(r.msg || 'Erro ao salvar.');
  }

  async function gerar() {
    setBusy(true); setHlMsg('Gerando highlights com IA…');
    const r = await generateHighlights(id);
    setBusy(false);
    setHlMsg(r.ok ? 'Highlights gerados!' : r.code === 'LIMITE_DIARIO' ? (r.mensagem || 'Limite diário atingido.') : (r.mensagem || 'Falha ao gerar.'));
    load();
  }

  return (
    <div className="fixed inset-0 z-[1000] flex justify-end">
      <button aria-label="Fechar" onClick={onClose} className="absolute inset-0 bg-black/50" />
      <div className="relative w-full max-w-lg h-full overflow-y-auto bg-[var(--surface-1)] border-l border-[var(--border)] p-5">
        <div className="flex justify-between mb-3"><h2 className="text-lg font-bold text-[var(--fg)]">Depoimento</h2><button onClick={onClose} className="text-[var(--fg-3)]">✕</button></div>

        <div className="space-y-2 mb-4">
          <Field label="Vídeo (URL)" value={d.video_url} onSave={canEdit ? (v) => persist({ video_url: v || null }, 'Vídeo salvo.') : undefined} />
          <Field label="Foto (URL)" value={d.foto_url} onSave={canEdit ? (v) => persist({ foto_url: v || null }, 'Foto salva.') : undefined} />
          <Field label="@ social" value={d.social_handle} onSave={canEdit ? (v) => persist({ social_handle: v || null }, 'Social salvo.') : undefined} />
          <Field label="Pasta Drive (URL)" value={d.drive_folder_url} onSave={canEdit ? (v) => persist({ drive_folder_url: v || null }, 'Drive salvo.') : undefined} />
          <Field label="Profissão" value={d.profissao} onSave={canEdit ? (v) => persist({ profissao: v || null }, 'Profissão salva.') : undefined} />
        </div>

        <div className="mb-4">
          <div className="text-xs font-semibold text-[var(--fg-3)] mb-1">Transcrição</div>
          <textarea value={transcript} onChange={(e) => setTranscript(e.target.value)} rows={8} readOnly={!canEdit} className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" placeholder="Cole/edite a transcrição aqui…" />
          {canEdit && <button onClick={() => persist({ transcript: transcript || null }, 'Transcrição salva.')} disabled={busy} className="mt-2 px-3 py-1.5 rounded-[var(--r-md)] border border-[var(--border)] text-sm text-[var(--fg-2)]">Salvar transcrição</button>}
        </div>

        <div className="rounded-[var(--r-lg)] border border-[var(--border)] p-3">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-semibold text-[var(--fg)]">Highlights (IA)</span>
            {canEdit && <button onClick={gerar} disabled={busy} className="px-3 py-1.5 rounded-[var(--r-md)] bg-[var(--accent)] text-black text-xs font-semibold disabled:opacity-60">{d.highlights_status === 'ok' ? 'Regerar' : 'Gerar highlights'}</button>}
          </div>
          {hlMsg && <p className="text-xs text-[var(--fg-3)] mb-2">{hlMsg}</p>}
          {d.gancho && <Copyable label="Gancho" value={d.gancho} />}
          {d.resumo && <Copyable label="Resumo" value={d.resumo} />}
          {d.objecao && <Copyable label="Objeção vencida" value={d.objecao} />}
          {d.antes_depois && <Copyable label="Antes → Depois" value={`Antes: ${d.antes_depois.antes}\nDepois: ${d.antes_depois.depois}`} />}
          {hls.map((h, i) => <Copyable key={i} label={h.tipo} value={h.texto} />)}
          {!d.gancho && !hls.length && d.highlights_status !== 'ok' && <p className="text-xs text-[var(--fg-3)]">Transcreva e gere os highlights para extrair gancho, resumo e trechos prontos para copy.</p>}
        </div>
      </div>
    </div>
  );
}

function Field({ label, value, onSave }: { label: string; value: string | null; onSave?: (v: string) => void }) {
  const [v, setV] = useState(value || '');
  // Sincroniza com o valor recarregado do servidor após salvar (fonte externa).
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => setV(value || ''), [value]);
  return (
    <label className="block">
      <span className="text-xs text-[var(--fg-3)]">{label}</span>
      <div className="flex gap-2 mt-1">
        <input value={v} onChange={(e) => setV(e.target.value)} readOnly={!onSave} className="flex-1 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)]" />
        {onSave && <button onClick={() => onSave(v)} className="px-2.5 py-1.5 rounded-[var(--r-md)] border border-[var(--border)] text-xs text-[var(--fg-2)]">✓</button>}
      </div>
    </label>
  );
}

function Copyable({ label, value }: { label: string; value: string }) {
  return (
    <div className="mb-2 p-2 rounded-[var(--r-md)] bg-[var(--surface-2)]">
      <div className="flex items-center justify-between">
        <span className="text-[10px] uppercase tracking-wide text-[var(--accent)] font-semibold">{label}</span>
        <button onClick={() => navigator.clipboard?.writeText(value)} className="text-xs text-[var(--fg-3)] hover:text-[var(--fg)]">copiar</button>
      </div>
      <div className="text-sm text-[var(--fg)] whitespace-pre-wrap">{value}</div>
    </div>
  );
}

function CursosTab({ canEdit, flash }: { canEdit: boolean; flash: (m: string) => void }) {
  const [cursos, setCursos] = useState<Curso[]>([]);
  const [nome, setNome] = useState('');
  const [slug, setSlug] = useState('');
  const reload = useCallback(async () => setCursos(await loadCursos()), []);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { reload(); }, [reload]);
  return (
    <div>
      {canEdit && (
        <div className="flex gap-2 mb-4">
          <input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome do curso" className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
          <input value={slug} onChange={(e) => setSlug(e.target.value)} placeholder="slug" className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
          <button onClick={async () => { if (nome && slug && (await saveCurso({ name: nome, slug }))) { flash('Curso criado.'); setNome(''); setSlug(''); reload(); } }} className="px-4 py-2 rounded-[var(--r-md)] bg-[var(--accent)] text-black text-sm font-medium">Adicionar</button>
        </div>
      )}
      <div className="space-y-2">
        {cursos.map((c) => (
          <div key={c.id} className="flex items-center justify-between p-3 rounded-[var(--r-md)] border border-[var(--border)]">
            <div><span className="text-[var(--fg)] font-medium">{c.name}</span> <span className="text-xs text-[var(--fg-3)]">/{c.slug}{!c.active && ' · inativo'}</span></div>
            {canEdit && <button onClick={async () => { if (confirm('Excluir curso?') && (await deleteCurso(c.id))) { flash('Excluído.'); reload(); } }} className="text-xs text-[var(--red)]">excluir</button>}
          </div>
        ))}
        {!cursos.length && <p className="text-[var(--fg-3)] text-sm">Nenhum curso.</p>}
      </div>
    </div>
  );
}

function TagsTab({ canEdit, flash }: { canEdit: boolean; flash: (m: string) => void }) {
  const [tags, setTags] = useState<Tag[]>([]);
  const [label, setLabel] = useState('');
  const [color, setColor] = useState('#F29725');
  const reload = useCallback(async () => setTags(await loadTags()), []);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { reload(); }, [reload]);
  return (
    <div>
      {canEdit && (
        <div className="flex gap-2 mb-4 items-center">
          <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Tag" className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
          <input type="color" value={color} onChange={(e) => setColor(e.target.value)} className="h-9 w-12 rounded border border-[var(--border)] bg-transparent" />
          <button onClick={async () => { if (label && (await saveTag({ label, color }))) { flash('Tag criada.'); setLabel(''); reload(); } }} className="px-4 py-2 rounded-[var(--r-md)] bg-[var(--accent)] text-black text-sm font-medium">Adicionar</button>
        </div>
      )}
      <div className="flex flex-wrap gap-2">
        {tags.map((t) => (
          <span key={t.id} className="flex items-center gap-2 px-3 py-1.5 rounded-[var(--r-pill)] border border-[var(--border)] text-sm" style={{ color: t.color || 'var(--fg-2)' }}>
            {t.label}
            {canEdit && <button onClick={async () => { if (confirm('Excluir tag?') && (await deleteTag(t.id))) { flash('Excluída.'); reload(); } }} className="text-[var(--red)]">✕</button>}
          </span>
        ))}
        {!tags.length && <p className="text-[var(--fg-3)] text-sm">Nenhuma tag.</p>}
      </div>
    </div>
  );
}
