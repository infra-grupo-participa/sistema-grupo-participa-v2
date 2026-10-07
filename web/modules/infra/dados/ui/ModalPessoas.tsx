'use client';

import { useMemo, useState } from 'react';
import { ConfirmDialog, DataTable, EmptyState, FilterSelect, Modal, SearchInput, Tabs, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { agrupar, aplicarFiltros, alternarFiltro, rotuloFiltro, type CampoFiltro, type Filtro } from '../application/filtro-cruzado';
import type { LeadPresencial, VendaPresencial } from '../domain/presencial';
import { dataBR, dataHoraBR, SEM_DADO } from './formato';
import { BarrasHorizontais } from './viz/BarrasHorizontais';

type Pessoa = LeadPresencial | VendaPresencial;
const camposLeads: { campo: CampoFiltro; titulo: string }[] = [
  { campo: 'comprou', titulo: 'Comprou' }, { campo: 'instrucao', titulo: 'Instrução' },
  { campo: 'turma', titulo: 'Turma' }, { campo: 'utm_source', titulo: 'UTM source' },
];
const camposVendas: { campo: CampoFiltro; titulo: string }[] = [
  { campo: 'status_grupo', titulo: 'Status' }, { campo: 'instrucao', titulo: 'Instrução' },
  { campo: 'turma', titulo: 'Turma' }, { campo: 'estado', titulo: 'Estado' },
  { campo: 'entrou_grupo', titulo: 'Entrou no grupo' },
];

export function ModalPessoas({ tipo, linhas, erro, carregando, onClose, isMaster = false, onToggleTeste }: { tipo: 'leads' | 'vendas'; linhas: Pessoa[] | null; erro: string | null; carregando: boolean; onClose: () => void; isMaster?: boolean; onToggleTeste?: (pessoaId: string, teste: boolean) => Promise<string | null> }) {
  const [aba, setAba] = useState('tabela');
  const [busca, setBusca] = useState('');
  const [filtros, setFiltros] = useState<Filtro[]>([]);
  const [status, setStatus] = useState('pago');
  const [alvoTeste, setAlvoTeste] = useState<LeadPresencial | null>(null);
  const [marcandoTeste, setMarcandoTeste] = useState(false);
  const [erroTeste, setErroTeste] = useState<string | null>(null);
  const vendas = tipo === 'vendas';
  const campos = vendas ? camposVendas : camposLeads;
  const base = useMemo(() => (linhas ?? []).filter((linha) => !vendas || status === 'todos' || ('status_grupo' in linha && linha.status_grupo === status)), [linhas, vendas, status]);
  const baseResumo = useMemo(() => vendas ? base : base.filter((linha) => !('teste' in linha && linha.teste === true)), [base, vendas]);
  const visiveis = useMemo(() => aplicarFiltros(base, filtros).filter((linha) => `${linha.nome ?? ''} ${linha.email} ${linha.telefone ?? ''}`.toLocaleLowerCase('pt-BR').includes(busca.toLocaleLowerCase('pt-BR'))), [base, filtros, busca]);
  const aplicarTeste = async (lead: LeadPresencial, teste: boolean) => {
    const pessoaId = lead.pessoa_id;
    if (!pessoaId || !onToggleTeste) return;
    setMarcandoTeste(true); setErroTeste(null);
    const erroAcao = await onToggleTeste(pessoaId, teste);
    setMarcandoTeste(false);
    if (erroAcao) setErroTeste(erroAcao);
    setAlvoTeste(null);
  };
  return <Modal onClose={onClose} title={vendas ? 'Vendas' : 'Pré-checkout'} width="max-w-6xl">
    <Tabs tabs={[{ k: 'tabela', l: vendas ? 'Vendas' : 'Leads' }, { k: 'resumo', l: 'Resumo' }]} active={aba} onChange={setAba} label="Visão do modal" />
    {carregando ? <p>Carregando…</p> : erro ? <p role="alert">{erro}</p> : linhas === null ? <p role="alert">Não foi possível carregar agora.</p> : <>
      <div className="mb-3 flex flex-wrap gap-2">{filtros.map((f) => <button key={f.campo} type="button" onClick={() => setFiltros(filtros.filter((x) => x.campo !== f.campo))} className="rounded-full border border-[var(--accent)] px-3 py-1 text-xs text-[var(--accent)]">{f.campo}: {rotuloFiltro(f.campo, f.valor === '__null__' ? null : f.valor)} ×</button>)}</div>
      {aba === 'resumo' ? <div className="grid gap-3 sm:grid-cols-2">{campos.map(({ campo, titulo }) => <BarrasHorizontais key={campo} titulo={titulo} barras={agrupar(baseResumo, campo, filtros)} selecionado={filtros.find((f) => f.campo === campo)?.valor} onSelect={(valor) => setFiltros((atual) => alternarFiltro(atual, campo, valor))} />)}</div> : <>
        {erroTeste && <p role="alert" className="mb-3 text-sm text-[var(--red)]">{erroTeste}</p>}
        <div className="mb-3 flex flex-wrap gap-2"><SearchInput placeholder="Buscar nome, e-mail ou telefone" value={busca} onChange={(e) => setBusca(e.target.value)} />{vendas && <FilterSelect aria-label="Status" value={status} onChange={(e) => { setStatus(e.target.value); setFiltros((f) => f.filter((x) => x.campo !== 'status_grupo')); }}><option value="pago">Pago</option><option value="todos">Todos os status</option><option value="estornado">Estornado</option><option value="atrasado">Atrasado</option><option value="em_aberto">Em aberto</option><option value="recusado">Recusado</option><option value="expirado">Expirado</option><option value="outro">Outro</option></FilterSelect>}</div>
        {visiveis.length === 0 ? <EmptyState title="Nenhuma linha para os filtros atuais" /> : <DataTable minWidth={isMaster && !vendas ? 1240 : 1050}><Thead><Th>Data</Th><Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th>{vendas ? <><Th>Estado</Th><Th>Instrução</Th><Th>Turma</Th><Th>Entrou no grupo</Th></> : <><Th>UTM source</Th><Th>UTM medium</Th><Th>UTM campaign</Th><Th>UTM content</Th><Th>UTM term</Th><Th>Instrução</Th><Th>Comprou</Th><Th>Turma</Th>{isMaster && <Th>Ação</Th>}</>}</Thead><tbody>{visiveis.map((linha, i) => {
          const lead = !vendas && 'utm_source' in linha ? linha as LeadPresencial : null;
          return <Tr key={vendas && 'transacao' in linha ? linha.transacao : linha.email + i} className={lead?.teste === true ? 'opacity-50' : ''}><Td>{vendas && 'dia_pedido' in linha ? dataBR(linha.dia_aprovado ?? linha.dia_pedido) : 'primeiro_em' in linha ? dataHoraBR(linha.primeiro_em) : SEM_DADO}</Td><Td>{linha.nome ?? SEM_DADO}{lead?.teste === true && <span className="ml-2 rounded-full border border-[var(--border)] px-2 py-0.5 text-[10px] uppercase tracking-wide">teste</span>}</Td><Td>{linha.email}</Td><Td>{linha.telefone ?? SEM_DADO}</Td>{vendas && 'estado' in linha ? <><Td>{linha.estado ?? SEM_DADO}</Td><Td>{linha.instrucao ?? 'Sem registro de aluno ativo'}</Td><Td>{linha.turma ?? 'Sem registro de aluno ativo'}</Td><Td>{rotuloFiltro('entrou_grupo', linha.entrou_grupo)}</Td></> : lead ? <><Td>{lead.utm_source ?? SEM_DADO}</Td><Td>{lead.utm_medium ?? SEM_DADO}</Td><Td>{lead.utm_campaign ?? SEM_DADO}</Td><Td>{lead.utm_content ?? SEM_DADO}</Td><Td>{lead.utm_term ?? SEM_DADO}</Td><Td>{lead.instrucao ?? 'Sem registro de aluno ativo'}</Td><Td>{lead.comprou ? 'Sim' : 'Não'}</Td><Td>{lead.turma ?? 'Sem registro de aluno ativo'}</Td>{isMaster && <Td>{lead.pessoa_id && <button type="button" disabled={marcandoTeste} onClick={() => { setErroTeste(null); setAlvoTeste(lead); if (lead.teste === true) void aplicarTeste(lead, false); }} className="whitespace-nowrap rounded border border-[var(--border)] px-2 py-1 text-xs font-medium text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50">{marcandoTeste && alvoTeste?.pessoa_id === lead.pessoa_id ? 'Salvando…' : lead.teste === true ? 'Desmarcar teste' : 'Marcar como teste'}</button>}</Td>}</> : null}</Tr>;
        })}</tbody></DataTable>}
      </>}
    </>}
    {alvoTeste && alvoTeste.teste !== true && <ConfirmDialog title="Marcar como teste" confirmLabel="Marcar como teste" cancelLabel="Cancelar" onCancel={() => setAlvoTeste(null)} onConfirm={() => void aplicarTeste(alvoTeste, true)} message="Esta marcação vale para o sistema todo. A pessoa deixará de contar nos indicadores e listas que excluem testes. Quer continuar?" />}
  </Modal>;
}
