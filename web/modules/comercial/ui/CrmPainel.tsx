'use client';

// CRM: um pipeline por vez (ativação, vendas, recuperação de carrinho, recuperação de venda), em quadro (kanban) ou
// lista, com filtro por projeto, responsável e situação. Clique no card abre o negócio (mover etapa, próximo passo,
// responsável, histórico) e dali a ficha da pessoa.
import { useEffect, useMemo, useState } from 'react';
import {
  Badge, Board, Button, DataTable, EmptyState, FilterSelect, Input, Loading, Modal, SectionCard, Tabs, Td, Th, Thead, Tr,
} from '@/shared/ui/components';
import { fmtData, fmtDataHora } from '@/shared/ui/format';
import {
  type ConfigCrm, type Etapa, type Negocio, type Pipeline, type StatusNegocio, agruparPorEtapa, destinosPossiveis, MSG_MOVIMENTO,
  passoAtrasado, validarMovimento,
} from '../domain/crm';
import type { ItemBusca } from '../domain/pessoas';
import {
  buscarPessoas, criarNegocio, editarNegocio, historicoNegocio, listarNegocios, moverNegocio, type LinhaHistorico,
} from '../infrastructure/comercial-data';

const hojeISO = () => new Date().toLocaleDateString('sv-SE');

interface Props {
  config: ConfigCrm;
  versao: number;
  onAbrirPessoa: (id: string) => void;
  flash: (m: string) => void;
  onMudou: () => void;
}

export function CrmPainel({ config, versao, onAbrirPessoa, flash, onMudou }: Props) {
  const pipelines = config.pipelines.filter((p) => p.ativo);
  const [pipeId, setPipeId] = useState<number>(pipelines[0]?.id ?? 0);
  const [projeto, setProjeto] = useState<number | null>(null);
  const [resp, setResp] = useState<string>('');
  const [status, setStatus] = useState<StatusNegocio>('aberto');
  const [modo, setModo] = useState<'quadro' | 'lista'>('quadro');
  const [res, setRes] = useState<{ chave: string; lista: Negocio[] | null } | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);

  const pipe = pipelines.find((p) => p.id === pipeId);
  const semResp = resp === '__sem__';
  const chave = [pipeId, projeto, resp, status, versao].join('|');

  useEffect(() => {
    if (!pipeId) return;
    let vivo = true;
    listarNegocios(pipeId, projeto, resp && !semResp ? resp : null, status).then((l) => {
      if (vivo) setRes({ chave, lista: l });
    });
    return () => { vivo = false; };
  }, [pipeId, projeto, resp, semResp, status, chave]);

  const atual = res?.chave === chave ? res : null;
  const lista = useMemo(() => (atual?.lista ?? []).filter((n) => !semResp || n.responsavel_id == null), [atual, semResp]);
  const negAberto = lista.find((n) => n.id === aberto) ?? null;

  if (!pipe) return <SectionCard><p className="text-sm text-[var(--fg-2)]">Nenhum pipeline ativo.</p></SectionCard>;

  return (
    <div className="space-y-4">
      <Tabs tabs={pipelines.map((p) => ({ k: String(p.id), l: p.nome }))} active={String(pipeId)} onChange={(k) => setPipeId(Number(k))} idBase="pipe" label="Pipelines" />
      {pipe.descricao && <p className="text-sm text-[var(--fg-2)]">{pipe.descricao}</p>}

      <SectionCard>
        <div className="flex flex-wrap items-end gap-3">
          <Campo rotulo="Projeto">
            <FilterSelect value={projeto ?? ''} onChange={(e) => setProjeto(e.target.value ? Number(e.target.value) : null)} aria-label="Projeto">
              <option value="">Todos</option>
              {config.projetos.map((p) => <option key={p.id} value={p.id}>{p.sigla} · {p.nome}</option>)}
            </FilterSelect>
          </Campo>
          <Campo rotulo="Responsável">
            <FilterSelect value={resp} onChange={(e) => setResp(e.target.value)} aria-label="Responsável">
              <option value="">Todos</option>
              <option value="__sem__">Sem responsável</option>
              {config.responsaveis.map((r) => <option key={r.id} value={r.id}>{r.nome}</option>)}
            </FilterSelect>
          </Campo>
          <Campo rotulo="Situação">
            <FilterSelect value={status} onChange={(e) => setStatus(e.target.value as StatusNegocio)} aria-label="Situação">
              <option value="aberto">Em andamento</option>
              <option value="ganho">Ganhos</option>
              <option value="perdido">Perdidos</option>
            </FilterSelect>
          </Campo>
          <Campo rotulo="Ver como">
            <FilterSelect value={modo} onChange={(e) => setModo(e.target.value as 'quadro' | 'lista')} aria-label="Ver como">
              <option value="quadro">Quadro</option>
              <option value="lista">Lista</option>
            </FilterSelect>
          </Campo>
          <div className="ml-auto">
            {config.permissoes.pode_editar && <Button onClick={() => setNovo(true)}>Novo negócio</Button>}
          </div>
        </div>
      </SectionCard>

      {!atual ? <Loading /> : atual.lista == null ? (
        <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar os negócios (erro de rede ou sem acesso).</p>
      ) : lista.length === 0 ? (
        <SectionCard><EmptyState title="Nenhum negócio aqui" hint="Mude os filtros ou crie um negócio a partir de uma pessoa." /></SectionCard>
      ) : modo === 'quadro' ? (
        <Board
          colunas={agruparPorEtapa(pipe.etapas, lista).map((c) => ({ key: String(c.etapa.id), titulo: c.etapa.nome, itens: c.itens }))}
          keyOf={(n) => n.id}
          renderItem={(n) => <CardNegocio n={n} onClick={() => setAberto(n.id)} />}
        />
      ) : (
        <SectionCard className="!p-0">
          <DataTable minWidth={860}>
            <Thead>
              <tr><Th>Pessoa</Th><Th>Etapa</Th><Th>Projeto</Th><Th>Responsável</Th><Th>Próximo passo</Th><Th>Quando</Th><Th>Na etapa desde</Th></tr>
            </Thead>
            <tbody>
              {lista.map((n) => (
                <Tr key={n.id} onClick={() => setAberto(n.id)}>
                  <Td><span className="font-medium text-[var(--fg)]">{n.pessoa ?? 'Sem nome'}</span>{n.eh_aluno && <span className="ml-2"><Badge tone="info">Aluno</Badge></span>}</Td>
                  <Td>{pipe.etapas.find((e) => e.id === n.etapa_id)?.nome}</Td>
                  <Td>{n.projeto ?? '—'}</Td>
                  <Td>{n.responsavel ?? '—'}</Td>
                  <Td>{n.status === 'perdido' ? (n.motivo_perda ?? '—') : (n.proximo_passo ?? '—')}</Td>
                  <Td><DataPasso n={n} /></Td>
                  <Td>{fmtData(n.entrou_etapa_em)}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        </SectionCard>
      )}

      {negAberto && (
        <NegocioModal n={negAberto} pipe={pipe} config={config} onFechar={() => setAberto(null)} flash={flash}
          onMudou={onMudou} onAbrirPessoa={(id) => { setAberto(null); onAbrirPessoa(id); }} />
      )}
      {novo && <NovoNegocioModal config={config} pipelineId={pipe.id} projeto={projeto} onFechar={() => setNovo(false)} flash={flash} onMudou={onMudou} />}
    </div>
  );
}

function Campo({ rotulo, children }: { rotulo: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">{rotulo}</span>
      {children}
    </label>
  );
}

function DataPasso({ n }: { n: Negocio }) {
  if (!n.proximo_passo_em) return <>—</>;
  const atrasado = passoAtrasado(n, hojeISO());
  return <span className={atrasado ? 'text-[var(--red)] font-semibold' : ''}>{fmtData(n.proximo_passo_em + 'T12:00:00')}{atrasado ? ' (atrasado)' : ''}</span>;
}

function CardNegocio({ n, onClick }: { n: Negocio; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick}
      className="w-full text-left rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-2.5 hover:border-[var(--border-strong)] transition-colors">
      <div className="text-sm font-semibold text-[var(--fg)] truncate">{n.pessoa ?? 'Sem nome'}</div>
      <div className="mt-1 flex flex-wrap gap-1">
        {n.projeto && <Badge>{n.projeto}</Badge>}
        {n.eh_aluno && <Badge tone="info">Aluno</Badge>}
        {n.situacao_pessoa === 'revisar' && <Badge tone="warning">Identidade em revisão</Badge>}
      </div>
      {n.status === 'perdido' && n.motivo_perda && <div className="mt-1.5 text-xs text-[var(--fg-2)] line-clamp-2">Motivo: {n.motivo_perda}</div>}
      {n.status !== 'perdido' && n.proximo_passo && <div className="mt-1.5 text-xs text-[var(--fg-2)] line-clamp-2">{n.proximo_passo}</div>}
      <div className="mt-1.5 flex items-center justify-between gap-2 text-[11px] text-[var(--fg-3)]">
        <span className="truncate">{n.responsavel ?? 'Sem responsável'}</span>
        <DataPasso n={n} />
      </div>
    </button>
  );
}

function NegocioModal({ n, pipe, config, onFechar, flash, onMudou, onAbrirPessoa }: {
  n: Negocio; pipe: Pipeline; config: ConfigCrm; onFechar: () => void; flash: (m: string) => void; onMudou: () => void; onAbrirPessoa: (id: string) => void;
}) {
  const etapaAtual = pipe.etapas.find((e) => e.id === n.etapa_id) as Etapa;
  const destinos = etapaAtual ? destinosPossiveis(pipe.etapas, etapaAtual) : [];
  const motivos = config.motivos.filter((m) => m.ativo && (m.pipeline_id == null || m.pipeline_id === pipe.id));
  const [para, setPara] = useState<number | ''>('');
  const [motivo, setMotivo] = useState<number | ''>('');
  const [motivoObs, setMotivoObs] = useState('');
  const [passo, setPasso] = useState(n.proximo_passo ?? '');
  const [passoEm, setPassoEm] = useState(n.proximo_passo_em ?? '');
  const [resp, setResp] = useState(n.responsavel_id ?? '');
  const [proj, setProj] = useState<number | ''>(n.projeto_id ?? '');
  const [hist, setHist] = useState<LinhaHistorico[] | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const pode = config.permissoes.pode_editar;

  useEffect(() => {
    let vivo = true;
    historicoNegocio(n.id).then((h) => { if (vivo) setHist(h ?? []); });
    return () => { vivo = false; };
  }, [n.id, n.etapa_id, n.proximo_passo]);

  const etapaPara = destinos.find((e) => e.id === para);
  const aviso = etapaPara ? validarMovimento(etapaAtual, etapaPara, motivo !== '' || motivoObs.trim() !== '') : null;

  async function mover() {
    if (!etapaPara) return;
    setOcupado(true);
    const r = await moverNegocio(n.id, etapaPara.id, motivo === '' ? null : motivo, motivoObs.trim() || null);
    setOcupado(false);
    flash(r.msg);
    if (r.ok) { setPara(''); setMotivo(''); setMotivoObs(''); onMudou(); }
  }

  async function salvar() {
    setOcupado(true);
    const r = await editarNegocio(n.id, { responsavel_id: resp || null, proximo_passo: passo.trim() || null, proximo_passo_em: passoEm || null, projeto_id: proj === '' ? null : proj });
    setOcupado(false);
    flash(r.msg);
    if (r.ok) onMudou();
  }

  return (
    <Modal onClose={onFechar} title={n.pessoa ?? 'Negócio'} width="max-w-2xl">
      <div className="space-y-4 text-sm">
        <div className="flex flex-wrap items-center gap-2">
          <Badge>{pipe.nome}</Badge>
          <Badge tone={n.status === 'ganho' ? 'success' : n.status === 'perdido' ? 'danger' : 'accent'}>{etapaAtual?.nome}</Badge>
          {n.projeto && <Badge>{n.projeto}</Badge>}
          {n.eh_aluno && <Badge tone="info">Aluno</Badge>}
          <Button variant="link" size="sm" onClick={() => onAbrirPessoa(n.pessoa_id)}>Abrir ficha da pessoa</Button>
        </div>
        {n.status === 'perdido' && <p className="text-[var(--fg-2)]">Motivo da perda: {n.motivo_perda ?? '—'}</p>}

        {pode && (
          <div className="rounded-[var(--r-md)] border border-[var(--border)] p-3 space-y-2">
            <div className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Mover</div>
            <div className="flex flex-wrap items-end gap-2">
              <FilterSelect value={para} onChange={(e) => setPara(e.target.value ? Number(e.target.value) : '')} aria-label="Mover para">
                <option value="">Mover para…</option>
                {destinos.map((e) => <option key={e.id} value={e.id}>{e.nome}{e.tipo === 'ganho' ? ' (ganho)' : e.tipo === 'perdido' ? ' (perdido)' : ''}</option>)}
              </FilterSelect>
              {etapaPara?.tipo === 'perdido' && (
                <>
                  {motivos.length > 0 && (
                    <FilterSelect value={motivo} onChange={(e) => setMotivo(e.target.value ? Number(e.target.value) : '')} aria-label="Motivo da perda">
                      <option value="">Motivo…</option>
                      {motivos.map((m) => <option key={m.id} value={m.id}>{m.nome}</option>)}
                    </FilterSelect>
                  )}
                  <Input value={motivoObs} onChange={(e) => setMotivoObs(e.target.value)} placeholder="Motivo da perda (texto)" maxLength={500} className="min-w-[220px]" />
                </>
              )}
              <Button size="sm" onClick={mover} disabled={!etapaPara || !!aviso || ocupado}>Mover</Button>
            </div>
            {aviso && <p className="text-xs text-[var(--yellow)]">{MSG_MOVIMENTO[aviso]}</p>}
            {destinos.length === 0 && <p className="text-xs text-[var(--fg-3)]">Nenhuma etapa para onde mover.</p>}
          </div>
        )}

        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block sm:col-span-2">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Próximo passo</span>
            <Input value={passo} onChange={(e) => setPasso(e.target.value)} maxLength={500} disabled={!pode} />
          </label>
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Quando</span>
            <Input type="date" value={passoEm} onChange={(e) => setPassoEm(e.target.value)} disabled={!pode} />
          </label>
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Responsável</span>
            <FilterSelect value={resp} onChange={(e) => setResp(e.target.value)} disabled={!pode} aria-label="Responsável">
              <option value="">Sem responsável</option>
              {config.responsaveis.map((r) => <option key={r.id} value={r.id}>{r.nome}</option>)}
            </FilterSelect>
          </label>
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Projeto</span>
            <FilterSelect value={proj} onChange={(e) => setProj(e.target.value ? Number(e.target.value) : '')} disabled={!pode} aria-label="Projeto">
              <option value="">Sem projeto</option>
              {config.projetos.map((p) => <option key={p.id} value={p.id}>{p.sigla}</option>)}
            </FilterSelect>
          </label>
        </div>
        {pode && <div className="flex justify-end"><Button size="sm" variant="subtle" onClick={salvar} disabled={ocupado}>Salvar</Button></div>}

        <div>
          <div className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-1">Histórico</div>
          {hist == null ? <Loading /> : hist.length === 0 ? <p className="text-xs text-[var(--fg-3)]">Sem registros.</p> : (
            <ul className="space-y-1">
              {hist.map((h, i) => (
                <li key={i} className="text-xs text-[var(--fg-2)]">
                  <span className="text-[var(--fg-3)]">{fmtDataHora(h.quando)}</span> · {ROTULO_ACAO[h.acao] ?? h.acao}
                  {(h.de || h.para) && <>: {h.de ?? '—'} → {h.para ?? '—'}</>}
                  {h.por && <> · {h.por}</>}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </Modal>
  );
}

const ROTULO_ACAO: Record<string, string> = {
  criado: 'Criado', etapa: 'Etapa', reaberto: 'Reaberto', responsavel: 'Responsável', proximo_passo: 'Próximo passo', projeto: 'Projeto',
};

/** Novo negócio: achar a pessoa na base (ou o aluno, que vira pessoa por referência) e escolher projeto e responsável. */
export function NovoNegocioModal({ config, pipelineId, projeto, pessoa, onFechar, flash, onMudou }: {
  config: ConfigCrm; pipelineId: number; projeto: number | null; pessoa?: { id: string; nome: string | null };
  onFechar: () => void; flash: (m: string) => void; onMudou: () => void;
}) {
  const [termo, setTermo] = useState('');
  const [achados, setAchados] = useState<ItemBusca[] | null>(null);
  const [escolhida, setEscolhida] = useState<{ id: string; nome: string | null } | null>(pessoa ?? null);
  const [pipe, setPipe] = useState(pipelineId);
  const [proj, setProj] = useState<number | ''>(projeto ?? '');
  const [resp, setResp] = useState('');
  const [passo, setPasso] = useState('');
  const [passoEm, setPassoEm] = useState('');
  const [ocupado, setOcupado] = useState(false);

  async function buscar() {
    if (termo.trim().length < 3) { flash('Digite ao menos 3 letras.'); return; }
    setAchados(null);
    setAchados((await buscarPessoas(termo.trim(), null))?.filter((x) => x.tipo === 'pessoa') ?? []);
  }

  async function criar() {
    if (!escolhida) return;
    setOcupado(true);
    const r = await criarNegocio({ pipeline_id: pipe, pessoa_id: escolhida.id, projeto_id: proj === '' ? null : proj, responsavel_id: resp || null,
      proximo_passo: passo.trim() || null, proximo_passo_em: passoEm || null });
    setOcupado(false);
    flash(r.msg);
    if (r.ok) { onMudou(); onFechar(); }
  }

  return (
    <Modal onClose={onFechar} title="Novo negócio" width="max-w-xl">
      <div className="space-y-3 text-sm">
        {!escolhida ? (
          <>
            <div className="flex gap-2">
              <Input value={termo} onChange={(e) => setTermo(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && buscar()}
                placeholder="Nome, e-mail, telefone ou documento" aria-label="Buscar pessoa" />
              <Button size="sm" onClick={buscar}>Buscar</Button>
            </div>
            <p className="text-xs text-[var(--fg-3)]">Só aparece quem já está na base de pessoas. Aluno que ainda não está: traga pela aba Pessoas.</p>
            {achados && (achados.length === 0 ? <p className="text-xs text-[var(--fg-2)]">Ninguém encontrado.</p> : (
              <ul className="divide-y divide-[var(--border-faint)]">
                {achados.map((a) => (
                  <li key={a.id ?? a.aluno_id} className="py-1.5 flex items-center justify-between gap-2">
                    <span>{a.nome ?? 'Sem nome'} {a.eh_aluno && <Badge tone="info">Aluno {a.turma ?? ''}</Badge>} <span className="text-[var(--fg-3)]">{a.email ?? ''}</span></span>
                    <Button size="sm" variant="ghost" onClick={() => setEscolhida({ id: a.id as string, nome: a.nome })}>Escolher</Button>
                  </li>
                ))}
              </ul>
            ))}
          </>
        ) : (
          <div className="flex items-center justify-between gap-2 rounded-[var(--r-md)] bg-[var(--surface-3)] px-3 py-2">
            <span className="font-semibold">{escolhida.nome ?? 'Sem nome'}</span>
            {!pessoa && <Button size="sm" variant="link" onClick={() => setEscolhida(null)}>Trocar</Button>}
          </div>
        )}
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Pipeline</span>
            <FilterSelect value={pipe} onChange={(e) => setPipe(Number(e.target.value))} aria-label="Pipeline">
              {config.pipelines.filter((p) => p.ativo).map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
            </FilterSelect>
          </label>
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Projeto</span>
            <FilterSelect value={proj} onChange={(e) => setProj(e.target.value ? Number(e.target.value) : '')} aria-label="Projeto">
              <option value="">Sem projeto</option>
              {config.projetos.map((p) => <option key={p.id} value={p.id}>{p.sigla}</option>)}
            </FilterSelect>
          </label>
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Responsável</span>
            <FilterSelect value={resp} onChange={(e) => setResp(e.target.value)} aria-label="Responsável">
              <option value="">Sem responsável</option>
              {config.responsaveis.map((r) => <option key={r.id} value={r.id}>{r.nome}</option>)}
            </FilterSelect>
          </label>
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Próximo passo em</span>
            <Input type="date" value={passoEm} onChange={(e) => setPassoEm(e.target.value)} />
          </label>
          <label className="block sm:col-span-2">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Próximo passo</span>
            <Input value={passo} onChange={(e) => setPasso(e.target.value)} maxLength={500} />
          </label>
        </div>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
          <Button size="sm" onClick={criar} disabled={!escolhida || ocupado}>Criar</Button>
        </div>
      </div>
    </Modal>
  );
}
