'use client';

import { useMemo, useState } from 'react';
import { DataTable, EmptyState, FilterSelect, Modal, SearchInput, Tabs, Td, Th, Thead, Tr } from '@/shared/ui/components';
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

export function ModalPessoas({ tipo, linhas, erro, carregando, onClose }: { tipo: 'leads' | 'vendas'; linhas: Pessoa[] | null; erro: string | null; carregando: boolean; onClose: () => void }) {
  const [aba, setAba] = useState('tabela');
  const [busca, setBusca] = useState('');
  const [filtros, setFiltros] = useState<Filtro[]>([]);
  const [status, setStatus] = useState('pago');
  const vendas = tipo === 'vendas';
  const campos = vendas ? camposVendas : camposLeads;
  const base = useMemo(() => (linhas ?? []).filter((linha) => !vendas || status === 'todos' || ('status_grupo' in linha && linha.status_grupo === status)), [linhas, vendas, status]);
  const visiveis = useMemo(() => aplicarFiltros(base, filtros).filter((linha) => `${linha.nome ?? ''} ${linha.email} ${linha.telefone ?? ''}`.toLocaleLowerCase('pt-BR').includes(busca.toLocaleLowerCase('pt-BR'))), [base, filtros, busca]);
  return <Modal onClose={onClose} title={vendas ? 'Vendas' : 'Pré-checkout'} width="max-w-6xl">
    <Tabs tabs={[{ k: 'tabela', l: vendas ? 'Vendas' : 'Leads' }, { k: 'resumo', l: 'Resumo' }]} active={aba} onChange={setAba} label="Visão do modal" />
    {carregando ? <p>Carregando…</p> : erro ? <p role="alert">{erro}</p> : linhas === null ? <p role="alert">Não foi possível carregar agora.</p> : <>
      <div className="mb-3 flex flex-wrap gap-2">{filtros.map((f) => <button key={f.campo} type="button" onClick={() => setFiltros(filtros.filter((x) => x.campo !== f.campo))} className="rounded-full border border-[var(--accent)] px-3 py-1 text-xs text-[var(--accent)]">{f.campo}: {rotuloFiltro(f.campo, f.valor === '__null__' ? null : f.valor)} ×</button>)}</div>
      {aba === 'resumo' ? <div className="grid gap-3 sm:grid-cols-2">{campos.map(({ campo, titulo }) => <BarrasHorizontais key={campo} titulo={titulo} barras={agrupar(base, campo, filtros)} selecionado={filtros.find((f) => f.campo === campo)?.valor} onSelect={(valor) => setFiltros((atual) => alternarFiltro(atual, campo, valor))} />)}</div> : <>
        <div className="mb-3 flex flex-wrap gap-2"><SearchInput placeholder="Buscar nome, e-mail ou telefone" value={busca} onChange={(e) => setBusca(e.target.value)} />{vendas && <FilterSelect aria-label="Status" value={status} onChange={(e) => { setStatus(e.target.value); setFiltros((f) => f.filter((x) => x.campo !== 'status_grupo')); }}><option value="pago">Pago</option><option value="todos">Todos os status</option><option value="estornado">Estornado</option><option value="atrasado">Atrasado</option><option value="em_aberto">Em aberto</option><option value="recusado">Recusado</option><option value="expirado">Expirado</option><option value="outro">Outro</option></FilterSelect>}</div>
        {visiveis.length === 0 ? <EmptyState title="Nenhuma linha para os filtros atuais" /> : <DataTable minWidth={1050}><Thead><Th>Data</Th><Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th>{vendas ? <><Th>Estado</Th><Th>Instrução</Th><Th>Turma</Th><Th>Entrou no grupo</Th></> : <><Th>UTM source</Th><Th>UTM medium</Th><Th>UTM campaign</Th><Th>UTM content</Th><Th>UTM term</Th><Th>Instrução</Th><Th>Comprou</Th><Th>Turma</Th></>}</Thead><tbody>{visiveis.map((linha, i) => <Tr key={vendas && 'transacao' in linha ? linha.transacao : linha.email + i}><Td>{vendas && 'dia_pedido' in linha ? dataBR(linha.dia_aprovado ?? linha.dia_pedido) : 'primeiro_em' in linha ? dataHoraBR(linha.primeiro_em) : SEM_DADO}</Td><Td>{linha.nome ?? SEM_DADO}</Td><Td>{linha.email}</Td><Td>{linha.telefone ?? SEM_DADO}</Td>{vendas && 'estado' in linha ? <><Td>{linha.estado ?? SEM_DADO}</Td><Td>{linha.instrucao ?? 'Sem registro de aluno ativo'}</Td><Td>{linha.turma ?? 'Sem registro de aluno ativo'}</Td><Td>{rotuloFiltro('entrou_grupo', linha.entrou_grupo)}</Td></> : 'utm_source' in linha ? <><Td>{linha.utm_source ?? SEM_DADO}</Td><Td>{linha.utm_medium ?? SEM_DADO}</Td><Td>{linha.utm_campaign ?? SEM_DADO}</Td><Td>{linha.utm_content ?? SEM_DADO}</Td><Td>{linha.utm_term ?? SEM_DADO}</Td><Td>{linha.instrucao ?? 'Sem registro de aluno ativo'}</Td><Td>{linha.comprou ? 'Sim' : 'Não'}</Td><Td>{linha.turma ?? 'Sem registro de aluno ativo'}</Td></> : null}</Tr>)}</tbody></DataTable>}
      </>}
    </>}
  </Modal>;
}
