'use client';

import { useMemo, useState } from 'react';
import { DataTable, EmptyState, Modal, SearchInput, Tabs, Td, Th, Thead, Tr } from '@/shared/ui/components';
import type { GrupoPendencia, PessoaPendenciaPresencial } from '../domain/presencial';
import { dataHoraBR, reais, SEM_DADO } from './formato';

export function ModalPendencias({ grupo, linhas, erro, carregando, onClose }: { grupo: GrupoPendencia; linhas: PessoaPendenciaPresencial[] | null; erro: string | null; carregando: boolean; onClose: () => void }) {
  const [aba, setAba] = useState('tabela');
  const [busca, setBusca] = useState('');
  const titulo = grupo === 'nao_pago' ? 'Boletos e Pix não pagos' : 'Compras canceladas';
  const visiveis = useMemo(() => (linhas ?? []).filter((l) => `${l.nome ?? ''} ${l.email} ${l.telefone ?? ''} ${l.categorias}`.toLocaleLowerCase('pt-BR').includes(busca.toLocaleLowerCase('pt-BR'))), [linhas, busca]);
  const categorias = useMemo(() => {
    const totais = new Map<string, number>();
    for (const l of linhas ?? []) for (const categoria of l.categorias.split(',').map((s) => s.trim()).filter(Boolean)) totais.set(categoria, (totais.get(categoria) ?? 0) + 1);
    return [...totais.entries()].sort((a, b) => b[1] - a[1]);
  }, [linhas]);
  return <Modal onClose={onClose} title={titulo} width="max-w-6xl">
    <Tabs tabs={[{ k: 'tabela', l: 'Pessoas' }, { k: 'resumo', l: 'Resumo' }]} active={aba} onChange={setAba} label="Visão das pendências" />
    {carregando ? <p>Carregando pessoas…</p> : <>{erro && <p role="alert" className="mb-3 text-sm text-[var(--fg-2)]">{erro} {linhas !== null && 'Exibindo a última lista carregada.'}</p>}{linhas === null ? !erro && <p role="alert">Não foi possível carregar agora.</p> : aba === 'resumo' ? <div className="space-y-3"><p className="text-sm text-[var(--fg-2)]">Pessoas únicas na lista: {linhas.length.toLocaleString('pt-BR')}. Uma pessoa pode aparecer em mais de uma categoria.</p>{!categorias.length ? <EmptyState title="Sem categorias" /> : <ul className="space-y-2">{categorias.map(([categoria, pessoas]) => <li key={categoria} className="flex justify-between rounded-[var(--r-md)] bg-[var(--surface-2)] px-3 py-2 text-sm"><span>{categoria}</span><strong className="tabular">{pessoas.toLocaleString('pt-BR')}</strong></li>)}</ul>}</div> : <><div className="mb-3"><SearchInput placeholder="Buscar nome, e-mail, telefone ou categoria" value={busca} onChange={(e) => setBusca(e.target.value)} /></div>{visiveis.length === 0 ? <EmptyState title="Nenhuma pessoa para os filtros atuais" /> : <DataTable minWidth={920}><Thead><Th>Último registro</Th><Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Categorias</Th><Th>Transações</Th><Th>Valor bruto da última</Th></Thead><tbody>{visiveis.map((l) => <Tr key={l.email}><Td>{dataHoraBR(l.ultimo_em)}</Td><Td>{l.nome ?? SEM_DADO}</Td><Td>{l.email}</Td><Td>{l.telefone ?? SEM_DADO}</Td><Td>{l.categorias}</Td><Td>{l.transacoes.toLocaleString('pt-BR')}</Td><Td>{reais(l.valor_bruto)}</Td></Tr>)}</tbody></DataTable>}</>}</>}
  </Modal>;
}
