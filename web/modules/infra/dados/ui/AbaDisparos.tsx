import { DataTable, EmptyState, Td, Th, Thead, Tr } from '@/shared/ui/components';
import type { DisparoPresencial } from '../domain/presencial';
import { centavos, dataBR, inteiro, percentual, SEM_DADO } from './formato';

export function AbaDisparos({ linhas, erro, carregando }: { linhas: DisparoPresencial[] | null; erro: string | null; carregando: boolean }) {
  if (carregando) return <p>Carregando disparos…</p>;
  if (erro) return <p role="alert">{erro}</p>;
  if (linhas === null) return <p role="alert">Não foi possível carregar agora.</p>;
  if (!linhas.length) return <EmptyState title="Nenhum disparo ligado a este projeto" />;
  return <DataTable minWidth={1150}><Thead><Th>Dia</Th><Th>Nome</Th><Th>Canal</Th><Th>Ferramenta</Th><Th>Enviadas (tamanho da lista)</Th><Th>Entregues</Th><Th>Lidas</Th><Th>Cliques</Th><Th>Falhas</Th><Th>Custo</Th><Th>Entrega</Th><Th>Leitura</Th><Th>Cliques</Th></Thead><tbody>{linhas.map((d) => <Tr key={d.disparo_id}><Td>{dataBR(d.dia)}</Td><Td>{d.nome}</Td><Td>{d.canal ?? SEM_DADO}</Td><Td>{d.ferramenta ?? SEM_DADO}</Td><Td>{inteiro(d.tamanho_lista)}</Td><Td>{inteiro(d.entregues)}</Td><Td>{inteiro(d.lidas)}</Td><Td>{inteiro(d.cliques)}</Td><Td>{inteiro(d.falhas)}</Td><Td>{centavos(d.custo_centavos)}</Td><Td>{percentual(d.entrega_pct)}</Td><Td>{percentual(d.leitura_pct)}</Td><Td>{percentual(d.clique_pct)}</Td></Tr>)}</tbody></DataTable>;
}
