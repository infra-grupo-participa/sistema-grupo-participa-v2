import { DataTable, EmptyState, KpiCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import type { DiamantePresencial } from '../domain/presencial';
import { dataBR, dataHoraBR, inteiro, SEM_DADO } from './formato';

export function AbaDiamantes({ linhas, erro, carregando }: { linhas: DiamantePresencial[] | null; erro: string | null; carregando: boolean }) {
  if (carregando) return <p className="pt-4">Carregando respostas de Diamantes…</p>;
  if (erro && linhas === null) return <p role="alert" className="pt-4">{erro}</p>;
  if (linhas === null) return <p role="alert" className="pt-4">Não foi possível carregar agora.</p>;
  const total = (predicado: (linha: DiamantePresencial) => boolean) => linhas.filter(predicado).length;
  return <div className="space-y-4 pt-4">
    {erro && <p role="alert" className="text-sm text-[var(--fg-2)]">{erro} Exibindo os últimos dados carregados.</p>}
    <div>
      <h2 className="text-lg font-semibold text-[var(--fg)]">Lista Diamantes</h2>
      <p className="mt-1 text-sm text-[var(--fg-2)]">Confirmação de participação, situação da viagem, chegada, retorno, aeroporto, hospedagem e acompanhantes.</p>
    </div>
    {!linhas.length ? <EmptyState title="Nenhuma resposta de Diamantes para esta chave" /> : <>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <KpiCard label="Responderam" value={total((linha) => linha.status === 'respondeu').toLocaleString('pt-BR')} />
        <KpiCard label="Pendentes" value={total((linha) => linha.status === 'pendente').toLocaleString('pt-BR')} />
        <KpiCard label="Fora da lista" value={total((linha) => linha.status === 'fora_da_lista').toLocaleString('pt-BR')} />
      </div>
      <ul className="grid gap-3 sm:grid-cols-3">
        {([
          ['Já estou confirmado(a) e com a viagem organizada.', 'confirmado'],
          ['Estou me organizando para participar, mas ainda não confirmado(a).', 'organizando'],
          ['Já sei que não irei participar.', 'nao_vai'],
        ] as const).map(([situacao, codigo]) => <li key={codigo} className="flex items-start justify-between gap-3 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4 text-sm">
          <span className="text-[var(--fg-2)]">{situacao}</span><strong className="shrink-0 tabular text-[var(--fg)]">{total((linha) => linha.situacao_codigo === codigo).toLocaleString('pt-BR')}</strong>
        </li>)}
      </ul>
      <DataTable minWidth={1900}>
      <Thead><Th>Ordem</Th><Th>Nome da Lista Diamantes</Th><Th>Status</Th><Th>Casamento</Th><Th>Respondido em</Th><Th>Respostas</Th><Th>Nome no formulário</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Grupo</Th><Th>Situação</Th><Th>Chegada</Th><Th>Retorno</Th><Th>Aeroporto</Th><Th>Hospedagem</Th><Th>Acompanhado</Th><Th>Acompanhantes</Th></Thead>
      <tbody>{linhas.map((linha, i) => <Tr key={linha.resposta_uuid ?? `diamante-${linha.lista_ordem ?? 'fora'}-${i}`}>
        <Td>{linha.lista_ordem ?? SEM_DADO}</Td><Td>{linha.lista_nome ?? SEM_DADO}</Td><Td>{linha.status}</Td><Td>{linha.casamento ?? SEM_DADO}</Td>
        <Td>{dataHoraBR(linha.respondido_em)}</Td><Td>{inteiro(linha.n_respostas)}</Td><Td>{linha.nome_formulario ?? SEM_DADO}</Td>
        <Td>{linha.email ?? SEM_DADO}</Td><Td>{linha.telefone ?? SEM_DADO}</Td><Td>{linha.grupo ?? SEM_DADO}</Td><Td>{linha.situacao ?? SEM_DADO}</Td>
        <Td>{linha.chegada_data ? dataBR(linha.chegada_data) : linha.chegada ?? SEM_DADO}</Td><Td>{linha.retorno_data ? dataBR(linha.retorno_data) : linha.retorno ?? SEM_DADO}</Td>
        <Td>{linha.aeroporto ?? SEM_DADO}</Td><Td>{linha.hospedagem ?? SEM_DADO}</Td><Td>{linha.acompanhado ?? SEM_DADO}</Td><Td>{linha.acompanhantes ?? SEM_DADO}</Td>
      </Tr>)}</tbody>
      </DataTable>
    </>}
  </div>;
}
