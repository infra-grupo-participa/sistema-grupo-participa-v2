'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { NivelBadge, DataTable, Thead, Th, Tr, Td, EmptyState, Drawer, Tabs, Badge, Button, Card, Toolbar, SearchInput, Input } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
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
  enqueueTranscricao,
  pollTranscricaoJob,
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

      <div className="flex items-end gap-2 mb-4">
        <div className="flex-1">
          <Tabs
            tabs={[{ k: 'biblioteca', l: 'Biblioteca' }, { k: 'cursos', l: 'Cursos' }, { k: 'tags', l: 'Tags' }]}
            active={tab}
            onChange={(k) => { setTab(k as Tab); window.location.hash = k; }}
          />
        </div>
        <a href="/depoimentos/biblioteca" className="px-4 py-2 text-sm text-[var(--accent)] whitespace-nowrap">Para Copy →</a>
      </div>

      {tab === 'biblioteca' && (
        <>
          <Toolbar className="mb-3">
            <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar aluno, e-mail, profissão…" />
          </Toolbar>
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
                  <Td className="text-sm">{r.video_url || r.transcript || r.foto_url ? (
                    <span className="inline-flex items-center gap-1.5 text-[var(--fg-3)]">
                      {r.video_url && <Icon name="film" size={15} />}
                      {r.transcript && <Icon name="file" size={15} />}
                      {r.foto_url && <Icon name="camera" size={15} />}
                    </span>
                  ) : <span className="text-[var(--fg-3)]">—</span>}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
          {!filtered.length && !loading && <EmptyState title="Nenhum depoimento" icon="depoimentos" />}
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
  const [trMsg, setTrMsg] = useState('');
  const [trBusy, setTrBusy] = useState(false);

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

  // Enfileira a transcrição da pasta do Drive; o worker (faster-whisper) processa.
  async function transcrever() {
    if (!d?.drive_folder_url) { setTrMsg('Informe a URL da pasta do Drive e salve antes.'); return; }
    setTrBusy(true); setTrMsg('Enfileirando transcrição…');
    const r = await enqueueTranscricao(d.drive_folder_url);
    if (!r.ok || !r.job) { setTrBusy(false); setTrMsg(r.error || 'Falha ao enfileirar.'); return; }
    const jobId = r.job.id;
    let tries = 0;
    const tick = async () => {
      const job = await pollTranscricaoJob(jobId);
      tries += 1;
      if (!job) { setTrBusy(false); setTrMsg('Não foi possível consultar o job.'); return; }
      if (job.status === 'completed') {
        if (job.transcript) {
          setTranscript(job.transcript);
          await saveDepoimento(id, { transcript: job.transcript });
        }
        setTrBusy(false);
        setTrMsg(`Transcrição concluída (${job.audios_succeeded}/${job.source_audios_count} áudios).`);
        load();
        return;
      }
      if (job.status === 'error' || job.status === 'failed') { setTrBusy(false); setTrMsg(job.error_message || 'Falha na transcrição.'); return; }
      setTrMsg(job.status === 'processing' ? 'Transcrevendo (worker)…' : 'Na fila, aguardando worker…');
      if (tries < 120) setTimeout(tick, 5000); // ~10min de polling
      else { setTrBusy(false); setTrMsg('Ainda processando — reabra mais tarde para ver o resultado.'); }
    };
    setTimeout(tick, 3000);
  }

  const hlTone = d.highlights_status === 'ok' ? 'success' : d.highlights_status === 'erro' ? 'danger' : d.highlights_status === 'limite_diario' ? 'warning' : 'neutral';
  return (
    <Drawer
      onClose={onClose}
      title="Depoimento"
      badges={<Badge tone={hlTone} dot>{d.highlights_status === 'ok' ? 'Highlights prontos' : d.highlights_status === 'processando' ? 'Processando…' : d.highlights_status === 'erro' ? 'Erro nos highlights' : d.highlights_status === 'limite_diario' ? 'Limite diário' : 'Sem highlights'}</Badge>}
    >
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
          {canEdit && (
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button variant="ghost" size="sm" onClick={() => persist({ transcript: transcript || null }, 'Transcrição salva.')} disabled={busy}>Salvar transcrição</Button>
              <Button variant="subtle" size="sm" onClick={transcrever} disabled={trBusy || !d.drive_folder_url} title={d.drive_folder_url ? 'Transcreve os áudios da pasta do Drive (worker)' : 'Informe a pasta do Drive primeiro'}>
                {trBusy ? 'Transcrevendo…' : <><Icon name="mic" size={14} /> Transcrever pela pasta do Drive</>}
              </Button>
              {trMsg && <span className="text-xs text-[var(--fg-3)]">{trMsg}</span>}
            </div>
          )}
        </div>

        <Card className="p-3">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-semibold text-[var(--fg)]">Highlights (IA)</span>
            {canEdit && <Button size="sm" onClick={gerar} disabled={busy}>{d.highlights_status === 'ok' ? 'Regerar' : 'Gerar highlights'}</Button>}
          </div>
          {hlMsg && <p className="text-xs text-[var(--fg-3)] mb-2">{hlMsg}</p>}
          {d.gancho && <Copyable label="Gancho" value={d.gancho} />}
          {d.resumo && <Copyable label="Resumo" value={d.resumo} />}
          {d.objecao && <Copyable label="Objeção vencida" value={d.objecao} />}
          {d.antes_depois && <Copyable label="Antes → Depois" value={`Antes: ${d.antes_depois.antes}\nDepois: ${d.antes_depois.depois}`} />}
          {hls.map((h, i) => <Copyable key={i} label={h.tipo} value={h.texto} />)}
          {!d.gancho && !hls.length && d.highlights_status !== 'ok' && <p className="text-xs text-[var(--fg-3)]">Transcreva e gere os highlights para extrair gancho, resumo e trechos prontos para copy.</p>}
        </Card>
    </Drawer>
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
        <Input value={v} onChange={(e) => setV(e.target.value)} readOnly={!onSave} className="flex-1" />
        {onSave && <Button variant="ghost" size="sm" onClick={() => onSave(v)}><Icon name="check" size={14} /></Button>}
      </div>
    </label>
  );
}

function Copyable({ label, value }: { label: string; value: string }) {
  return (
    <div className="mb-2 p-2 rounded-[var(--r-md)] bg-[var(--surface-2)]">
      <div className="flex items-center justify-between">
        <span className="text-[10px] uppercase tracking-wide text-[var(--accent)] font-semibold">{label}</span>
        <Button variant="link" size="sm" onClick={() => navigator.clipboard?.writeText(value)}>copiar</Button>
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
        <Toolbar className="mb-4">
          <Input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome do curso" className="w-auto" />
          <Input value={slug} onChange={(e) => setSlug(e.target.value)} placeholder="slug" className="w-auto" />
          <Button onClick={async () => { if (nome && slug && (await saveCurso({ name: nome, slug }))) { flash('Curso criado.'); setNome(''); setSlug(''); reload(); } }}>Adicionar</Button>
        </Toolbar>
      )}
      <div className="space-y-2">
        {cursos.map((c) => (
          <Card key={c.id} className="flex items-center justify-between p-3">
            <div><span className="text-[var(--fg)] font-medium">{c.name}</span> <span className="text-xs text-[var(--fg-3)]">/{c.slug}{!c.active && ' · inativo'}</span></div>
            {canEdit && <Button variant="danger" size="sm" onClick={async () => { if (confirm('Excluir curso?') && (await deleteCurso(c.id))) { flash('Excluído.'); reload(); } }}>excluir</Button>}
          </Card>
        ))}
        {!cursos.length && <EmptyState title="Nenhum curso" icon="cursos" />}
      </div>
    </div>
  );
}

function TagsTab({ canEdit, flash }: { canEdit: boolean; flash: (m: string) => void }) {
  const [tags, setTags] = useState<Tag[]>([]);
  const [label, setLabel] = useState('');
  const [color, setColor] = useState('#F29725'); /* hex-ok: valor inicial do color-picker de tag */
  const reload = useCallback(async () => setTags(await loadTags()), []);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { reload(); }, [reload]);
  return (
    <div>
      {canEdit && (
        <Toolbar className="mb-4">
          <Input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Tag" className="w-auto" />
          <input type="color" value={color} onChange={(e) => setColor(e.target.value)} className="h-9 w-12 rounded-[var(--r-md)] border border-[var(--border)] bg-transparent" />
          <Button onClick={async () => { if (label && (await saveTag({ label, color }))) { flash('Tag criada.'); setLabel(''); reload(); } }}>Adicionar</Button>
        </Toolbar>
      )}
      <div className="flex flex-wrap gap-2">
        {tags.map((t) => (
          <span key={t.id} className="inline-flex items-center gap-2 px-3 py-1.5 rounded-[var(--r-pill)] border border-[var(--border)] text-sm" style={{ color: t.color || 'var(--fg-2)' /* viz-colors: cor da tag definida pelo usuário */ }}>
            {t.label}
            {canEdit && <button onClick={async () => { if (confirm('Excluir tag?') && (await deleteTag(t.id))) { flash('Excluída.'); reload(); } }} className="text-[var(--red)] inline-flex"><Icon name="x" size={13} /></button>}
          </span>
        ))}
        {!tags.length && <EmptyState title="Nenhuma tag" icon="tags" />}
      </div>
    </div>
  );
}
