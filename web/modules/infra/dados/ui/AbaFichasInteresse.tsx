import { DataTable, EmptyState, Td, Th, Thead, Tr } from '@/shared/ui/components';
import type { FichaInteresseMiami } from '../domain/presencial';
import { dataHoraBR, SEM_DADO } from './formato';

function ListaFichas({ linhas, comprou }: { linhas: FichaInteresseMiami[]; comprou: boolean }) {
  const pessoas = linhas.filter((linha) => linha.comprou === comprou);
  const titulo = comprou ? 'Preencheram e compraram' : 'Preencheram e NÃO compraram';
  if (!pessoas.length) return <EmptyState title={`Nenhuma ficha em “${titulo}”`} />;
  return <DataTable minWidth={1900}>
    <Thead><Th>Respondido em</Th><Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Turma</Th><Th>Passaporte</Th><Th>Visto</Th><Th>Planos</Th><Th>Comprou passagem</Th><Th>Data da passagem</Th><Th>Confirma pré-venda</Th><Th>Deseja programa</Th><Th>Compra</Th><Th>Status da compra</Th><Th>Transação</Th><Th>Compra em</Th><Th>Casou por</Th></Thead>
    <tbody>{pessoas.map((linha) => <Tr key={linha.resposta_uuid} className={comprou ? '' : 'bg-amber-500/10'}>
      <Td>{dataHoraBR(linha.respondido_em)}</Td><Td>{linha.nome ?? SEM_DADO}</Td><Td>{linha.email ?? SEM_DADO}</Td><Td>{linha.telefone ?? SEM_DADO}</Td>
      <Td>{linha.turma ?? SEM_DADO}</Td><Td>{linha.passaporte ?? SEM_DADO}</Td><Td>{linha.visto ?? SEM_DADO}</Td><Td>{linha.planos ?? SEM_DADO}</Td>
      <Td>{linha.comprou_passagem ?? SEM_DADO}</Td><Td>{linha.data_passagem ?? SEM_DADO}</Td><Td>{linha.confirma_pre_venda ?? SEM_DADO}</Td><Td>{linha.deseja_programa ?? SEM_DADO}</Td>
      <Td className={!comprou ? 'font-semibold text-amber-700 dark:text-amber-300' : ''}>{comprou ? 'Comprou' : 'NÃO comprou'}</Td>
      <Td>{linha.compra_status ?? SEM_DADO}</Td><Td>{linha.compra_transacao ?? SEM_DADO}</Td><Td>{dataHoraBR(linha.compra_em)}</Td><Td>{linha.casou_por ?? SEM_DADO}</Td>
    </Tr>)}</tbody>
  </DataTable>;
}

export function AbaFichasInteresse({ linhas, erro, carregando }: { linhas: FichaInteresseMiami[] | null; erro: string | null; carregando: boolean }) {
  if (carregando) return <p className="pt-4">Carregando fichas de interesse…</p>;
  if (erro && linhas === null) return <p role="alert" className="pt-4">{erro}</p>;
  if (linhas === null) return <p role="alert" className="pt-4">Não foi possível carregar agora.</p>;
  const naoCompraram = linhas.filter((linha) => !linha.comprou).length;
  const compraram = linhas.length - naoCompraram;
  return <div className="space-y-5 pt-4">
    {erro && <p role="alert" className="text-sm text-[var(--fg-2)]">{erro} Exibindo os últimos dados carregados.</p>}
    <div>
      <h2 className="text-lg font-semibold text-[var(--fg)]">Fichas de interesse</h2>
      <p className="mt-1 text-sm text-[var(--fg-2)]">Fichas comparadas às transações pagas das ofertas sju5pawn e mjzv4v0s. O casamento usa e-mail ou telefone.</p>
    </div>
    <section className="rounded-[var(--r-lg)] border border-amber-500/40 bg-amber-500/10 p-4" aria-labelledby="interesse-sem-compra">
      <h3 id="interesse-sem-compra" className="font-semibold text-[var(--fg)]">Preencheram e NÃO compraram · {naoCompraram.toLocaleString('pt-BR')}</h3>
      <p className="mb-4 mt-1 text-sm text-[var(--fg-2)]">Lista destacada para acompanhamento do time. Inclui fichas sem transação e transações não pagas.</p>
      <ListaFichas linhas={linhas} comprou={false} />
    </section>
    <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4" aria-labelledby="interesse-com-compra">
      <h3 id="interesse-com-compra" className="mb-4 font-semibold text-[var(--fg)]">Preencheram e compraram · {compraram.toLocaleString('pt-BR')}</h3>
      <ListaFichas linhas={linhas} comprou />
    </section>
  </div>;
}
