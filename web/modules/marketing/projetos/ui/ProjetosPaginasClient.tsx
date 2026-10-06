'use client';

// Marketing > Projetos e páginas: a base compartilhada (tabela de projetos única + páginas de cada projeto).
// Listar, editar e testar um nome de campanha. Só admin/dev (gate no layout, na page e no banco). Projeto NOVO nasce no
// cadastro completo do Tráfego (tipo, unidade, períodos, contas): o botão "Novo projeto" leva para lá (auditoria 06/10/2026).
import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  Badge, Button, DataTable, EmptyState, FilterSelect, Input, Loading, Modal, SectionCard, Td, Th, Thead, Toast, Toggle, Tr, useFlash,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_ERRO } from '../domain/campanha';
import {
  FUNCOES_PAGINA, ROTULO_FUNCAO, ROTULO_TIPO_SUBAREA, normalizarSigla, validarCodigoPagina, validarProjeto,
  type FuncaoPagina, type Pagina, type Projeto,
} from '../domain/projetos';
import {
  listarPaginas, listarProjetos, salvarPagina, salvarProjeto, traduzirNoBanco,
  type PaginaForm, type ProjetoForm, type TraducaoBanco,
} from './projetos-data';

const dataBR = (ymd: string | null) => (ymd ? ymd.split('-').reverse().join('/') : null);

function Campo({ rotulo, dica, children }: { rotulo: string; dica?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">
        {rotulo}{dica && <span className="font-normal text-[var(--fg-3)]"> · {dica}</span>}
      </span>
      {children}
    </label>
  );
}

function Erro({ msg }: { msg: string | null }) {
  if (!msg) return null;
  return <p role="alert" className="text-sm text-[var(--red)]">{msg}</p>;
}

// ─── Projeto ─────────────────────────────────────────────────────────────────────────────────────────────────────────
// O Tráfego abre o cadastro completo ao ver ?novo=1 (TrafegoClient).
const NOVO_PROJETO_URL = '/marketing/trafego?novo=1';

function ModalProjeto({ inicial, onFechar, onSalvo }: { inicial: ProjetoForm; onFechar: () => void; onSalvo: (msg: string) => void }) {
  const [f, setF] = useState<ProjetoForm>(inicial);
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof ProjetoForm>(k: K, v: ProjetoForm[K]) => setF((x) => ({ ...x, [k]: v }));
  const txt = (v: string) => (v.trim() === '' ? null : v);

  async function salvar() {
    const e = validarProjeto(f);
    if (e) { setErro(e); return; }
    setSalvando(true);
    const r = await salvarProjeto({ ...f, sigla: normalizarSigla(f.sigla) });
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }

  return (
    <Modal
      onClose={onFechar}
      title={f.id ? `Editar projeto ${inicial.sigla}` : 'Novo projeto'}
      width="max-w-2xl"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
        <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
      </>}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Sigla de campanha" dica="ex.: PB26, HT33, SEMSET26">
          <Input value={f.sigla} onChange={(e) => set('sigla', e.target.value.toUpperCase())} maxLength={14} autoFocus={!f.id} />
        </Campo>
        <Campo rotulo="Nome">
          <Input value={f.nome} onChange={(e) => set('nome', e.target.value)} maxLength={120} />
        </Campo>
        <Campo rotulo="Tipo/linha" dica="ex.: Patrimônio Brasil">
          <Input value={f.linha} onChange={(e) => set('linha', e.target.value)} maxLength={60} />
        </Campo>
        <div className="grid grid-cols-2 gap-3">
          <Campo rotulo="Edição">
            <Input value={f.edicao ?? ''} onChange={(e) => set('edicao', txt(e.target.value))} maxLength={20} />
          </Campo>
          <Campo rotulo="Ano">
            <Input type="number" value={f.ano ?? ''} onChange={(e) => set('ano', e.target.value ? Number(e.target.value) : null)} />
          </Campo>
        </div>
        <Campo rotulo="Etiqueta do ClickUp" dica="texto exato; vazio se não houver">
          <Input value={f.etiqueta_clickup ?? ''} onChange={(e) => set('etiqueta_clickup', txt(e.target.value))} maxLength={80} />
        </Campo>
        <div className="text-xs text-[var(--fg-3)] self-end pb-2">
          Tipo (interno/externo), unidade, tipo de lançamento, especialista, períodos e contas: em Marketing &gt; Tráfego, botão Projeto.
        </div>
        <Campo rotulo="Início" dica="com captação ou evento no Tráfego, sai deles">
          <Input type="date" value={f.inicio ?? ''} onChange={(e) => set('inicio', e.target.value || null)} />
        </Campo>
        <Campo rotulo="Fim" dica="idem">
          <Input type="date" value={f.fim ?? ''} onChange={(e) => set('fim', e.target.value || null)} />
        </Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação">
            <Input value={f.obs ?? ''} onChange={(e) => set('obs', txt(e.target.value))} maxLength={1000} />
          </Campo>
        </div>
        <Toggle checked={f.ativo} onChange={(v) => set('ativo', v)} label="Ativo" />
      </div>
      <div className="mt-3"><Erro msg={erro} /></div>
    </Modal>
  );
}

// ─── Página ──────────────────────────────────────────────────────────────────────────────────────────────────────────
function ModalPagina({ inicial, projetos, onFechar, onSalvo }: {
  inicial: PaginaForm; projetos: Projeto[]; onFechar: () => void; onSalvo: (msg: string) => void;
}) {
  const [f, setF] = useState<PaginaForm>(inicial);
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof PaginaForm>(k: K, v: PaginaForm[K]) => setF((x) => ({ ...x, [k]: v }));

  async function salvar() {
    if (!f.projeto_id) { setErro('Escolha o projeto.'); return; }
    const e = validarCodigoPagina(f.codigo ?? '');
    if (e) { setErro(e); return; }
    if (!f.caminho.trim()) { setErro('Informe o caminho (ex.: /ak1/) ou a URL inteira.'); return; }
    setSalvando(true);
    const r = await salvarPagina({ ...f, codigo: f.codigo?.trim().toLowerCase() || null });
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }

  return (
    <Modal
      onClose={onFechar}
      title={f.id ? 'Editar página' : 'Nova página'}
      width="max-w-2xl"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
        <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
      </>}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Projeto">
          <FilterSelect value={f.projeto_id || ''} onChange={(e) => set('projeto_id', Number(e.target.value))}>
            <option value="">Escolha</option>
            {projetos.map((p) => <option key={p.id} value={p.id}>{p.sigla} · {p.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Código da casa" dica="ak1, bl2, ak1-b; vazio em obrigado/pesquisa">
          <Input value={f.codigo ?? ''} onChange={(e) => set('codigo', e.target.value)} maxLength={8} />
        </Campo>
        <Campo rotulo="Domínio" dica="sem https://">
          <Input value={f.dominio} onChange={(e) => set('dominio', e.target.value)} placeholder="patrimoniobrasil.com.br" />
        </Campo>
        <Campo rotulo="Caminho" dica="ou cole a URL inteira">
          <Input value={f.caminho} onChange={(e) => set('caminho', e.target.value)} placeholder="/ak1/" />
        </Campo>
        <Campo rotulo="Nome">
          <Input value={f.nome} onChange={(e) => set('nome', e.target.value)} maxLength={80} placeholder="vazio = o código ou o caminho" />
        </Campo>
        <Campo rotulo="Função">
          <FilterSelect value={f.funcao} onChange={(e) => set('funcao', e.target.value as FuncaoPagina)}>
            {FUNCOES_PAGINA.map((x) => <option key={x} value={x}>{ROTULO_FUNCAO[x]}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Funil" dica="texto curto, ex.: ak1, bl2">
          <Input value={f.funil ?? ''} onChange={(e) => set('funil', e.target.value || null)} maxLength={40} />
        </Campo>
        <Campo rotulo="Observação">
          <Input value={f.obs ?? ''} onChange={(e) => set('obs', e.target.value || null)} maxLength={1000} />
        </Campo>
        <Toggle checked={f.ativa} onChange={(v) => set('ativa', v)} label="Ativa" />
      </div>
      <div className="mt-3"><Erro msg={erro} /></div>
    </Modal>
  );
}

// ─── Testar nome de campanha ─────────────────────────────────────────────────────────────────────────────────────────
function TestarCampanha() {
  const [nome, setNome] = useState('');
  const [r, setR] = useState<TraducaoBanco | null>(null);
  const [falhou, setFalhou] = useState(false);

  async function testar() {
    if (!nome.trim()) return;
    const x = await traduzirNoBanco(nome);
    setFalhou(!x);
    setR(x);
  }

  return (
    <SectionCard title="Testar nome de campanha" subtitle="GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA (a página só em teste de página).">
      <form className="flex flex-col gap-2 sm:flex-row" onSubmit={(e) => { e.preventDefault(); void testar(); }}>
        <Input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1" className="flex-1" />
        <Button type="submit" size="sm" variant="subtle">Traduzir</Button>
      </form>
      {falhou && <p className="mt-2 text-sm text-[var(--red)]">Não foi possível traduzir (erro de rede ou sem acesso).</p>}
      {r && (
        <div className="mt-3 space-y-2 text-sm">
          <Badge tone={r.padrao ? 'success' : 'danger'}>{r.padrao ? 'No padrão' : 'Fora do padrão'}</Badge>
          {r.nome_canonico && <p className="text-[var(--fg-2)]">Forma canônica: <span className="font-mono text-[var(--fg)]">{r.nome_canonico}</span></p>}
          <dl className="grid grid-cols-2 gap-x-4 gap-y-1 sm:grid-cols-5">
            {([['Gestor', r.gestor], ['Projeto', r.projeto], ['Objetivo', r.objetivo], ['Descrição', r.descricao], ['Página', r.pagina]] as const).map(([k, v]) => (
              <div key={k}><dt className="text-xs text-[var(--fg-3)]">{k}</dt><dd className="text-[var(--fg)] break-words">{v ?? '—'}</dd></div>
            ))}
          </dl>
          {r.erros.length > 0 && <ul className="list-disc pl-5 text-[var(--red)]">{r.erros.map((e) => <li key={e}>{ROTULO_ERRO[e] ?? e}</li>)}</ul>}
          {r.avisos.length > 0 && <p className="text-xs text-[var(--fg-3)]">Avisos: {r.avisos.join(', ')}</p>}
        </div>
      )}
    </SectionCard>
  );
}

// ─── Tela ────────────────────────────────────────────────────────────────────────────────────────────────────────────
export function ProjetosPaginasClient() {
  const router = useRouter();
  const [projetos, setProjetos] = useState<Projeto[] | null>(null);
  const [paginas, setPaginas] = useState<Pagina[] | null>(null);
  const [falhou, setFalhou] = useState(false);
  const [filtro, setFiltro] = useState<number | ''>('');
  const [editProjeto, setEditProjeto] = useState<ProjetoForm | null>(null);
  const [editPagina, setEditPagina] = useState<PaginaForm | null>(null);
  const { toast, flash } = useFlash();

  // `versao` sobe a cada gravação e dispara a recarga (o efeito só assina o resultado da promessa).
  const [versao, setVersao] = useState(0);
  useEffect(() => {
    let vivo = true;
    Promise.all([listarProjetos(), listarPaginas()]).then(([p, g]) => {
      if (!vivo) return;
      setFalhou(!p || !g);
      setProjetos(p ?? []);
      setPaginas(g ?? []);
    });
    return () => { vivo = false; };
  }, [versao]);

  const paginasVisiveis = useMemo(
    () => (paginas ?? []).filter((g) => filtro === '' || g.projeto_id === filtro),
    [paginas, filtro],
  );

  const salvo = (msg: string) => { setEditProjeto(null); setEditPagina(null); flash(msg); setVersao((v) => v + 1); };

  if (!projetos || !paginas) return <Loading />;

  return (
    <div className="max-w-6xl space-y-6">
      <div>
        <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Marketing · base compartilhada</div>
        <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Projetos e páginas</h1>
        <p className="mt-1 text-sm text-[var(--fg-2)]">
          Tabela de projetos única de Web, Tráfego e Mensageria. Projeto = edição; a sigla é a do nome de campanha.
        </p>
      </div>

      {falhou && <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar (erro de rede ou sem acesso).</p>}

      <SectionCard
        title="Projetos"
        subtitle={`${projetos.length} cadastrado(s)`}
        right={<Button size="sm" title="Abre o cadastro completo do projeto no Tráfego (tipo, unidade, períodos e contas)"
          onClick={() => router.push(NOVO_PROJETO_URL)}><Icon name="plus" size={14} /> Novo projeto</Button>}
      >
        {projetos.length === 0 ? <EmptyState title="Nenhum projeto" /> : (
          <DataTable minWidth={900}>
            <Thead>
              <Th>Sigla</Th><Th>Nome</Th><Th>Tipo/linha</Th><Th>Edição/ano</Th><Th>Etiqueta do ClickUp</Th><Th>Tipo</Th><Th>Período</Th><Th>Páginas</Th><Th>Situação</Th>
            </Thead>
            <tbody>
              {projetos.map((p) => (
                <Tr key={p.id} onClick={() => setEditProjeto({ ...p })}>
                  <Td><span className="font-mono font-semibold">{p.sigla}</span></Td>
                  <Td>{p.nome}</Td>
                  <Td>{p.linha}</Td>
                  <Td>{[p.edicao, p.ano].filter(Boolean).join(' / ') || '—'}</Td>
                  <Td>{p.etiqueta_clickup ? <span className="font-mono text-xs">{p.etiqueta_clickup}</span> : '—'}</Td>
                  <Td>{p.subarea_trafego ? ROTULO_TIPO_SUBAREA[p.subarea_trafego] : '—'}</Td>
                  <Td>{p.inicio || p.fim ? `${dataBR(p.inicio) ?? '?'} a ${dataBR(p.fim) ?? '?'}` : '—'}</Td>
                  <Td>{p.paginas}</Td>
                  <Td><Badge tone={p.ativo ? 'success' : 'neutral'}>{p.ativo ? 'Ativo' : 'Inativo'}</Badge></Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>

      <SectionCard
        title="Páginas"
        subtitle="Código da casa (ak1, bl2, ak1-b) = campo 5 do nome de campanha."
        right={
          <div className="flex items-center gap-2">
            <FilterSelect value={filtro} onChange={(e) => setFiltro(e.target.value ? Number(e.target.value) : '')} aria-label="Filtrar por projeto">
              <option value="">Todos os projetos</option>
              {projetos.map((p) => <option key={p.id} value={p.id}>{p.sigla}</option>)}
            </FilterSelect>
            <Button size="sm" disabled={projetos.length === 0} onClick={() => setEditPagina({
              projeto_id: filtro === '' ? 0 : filtro, codigo: null, nome: '', dominio: '', caminho: '', funcao: 'captura', funil: null, ativa: true, obs: null,
            })}><Icon name="plus" size={14} /> Nova página</Button>
          </div>
        }
      >
        {paginasVisiveis.length === 0 ? <EmptyState title="Nenhuma página" /> : (
          <DataTable minWidth={900}>
            <Thead>
              <Th>Projeto</Th><Th>Código</Th><Th>Nome</Th><Th>URL</Th><Th>Função</Th><Th>Funil</Th><Th>Situação</Th>
            </Thead>
            <tbody>
              {paginasVisiveis.map((g) => (
                <Tr key={g.id} onClick={() => setEditPagina({
                  id: g.id, projeto_id: g.projeto_id, codigo: g.codigo, nome: g.nome, dominio: g.dominio, caminho: g.caminho,
                  funcao: g.funcao, funil: g.funil, ativa: g.ativa, obs: g.obs,
                })}>
                  <Td><span className="font-mono">{g.projeto_sigla}</span></Td>
                  <Td>{g.codigo ? <span className="font-mono">{g.codigo}</span> : '—'}</Td>
                  <Td>{g.nome}</Td>
                  <Td><span className="font-mono text-xs break-all">{g.url}</span></Td>
                  <Td>{ROTULO_FUNCAO[g.funcao] ?? g.funcao}</Td>
                  <Td>{g.funil ?? '—'}</Td>
                  <Td><Badge tone={g.ativa ? 'success' : 'neutral'}>{g.ativa ? 'Ativa' : 'Inativa'}</Badge></Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>

      <TestarCampanha />

      {editProjeto && <ModalProjeto inicial={editProjeto} onFechar={() => setEditProjeto(null)} onSalvo={salvo} />}
      {editPagina && <ModalPagina inicial={editPagina} projetos={projetos} onFechar={() => setEditPagina(null)} onSalvo={salvo} />}
      <Toast>{toast}</Toast>
    </div>
  );
}
