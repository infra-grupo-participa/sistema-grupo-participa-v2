'use client';

import { useState } from 'react';
import type { MetricaAtm, LeadGrupoAtm } from '@/modules/infra/atm/domain/dashboard';
import type { EstadoListaAtm } from '@/modules/infra/atm/ui/carregador-listas';
import { ConfirmDialog, EmptyState, Loading, DataTable, Td, Th, Thead, Tr, Modal } from '@/shared/ui/components';

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const origemLabel: Record<LeadGrupoAtm['origem'], string> = {
  lista_disparo: 'Lista do disparo',
  base_leads: 'Base de leads',
  nao_encontrado: 'Não encontrado',
};
const texto = (valor: string | null) => valor ?? '';
const dataHora = (valor: string | null) => valor
  ? new Date(valor).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' })
  : '';
const simNaoVazio = (valor: boolean | null) => valor === null ? '' : valor ? 'Sim' : 'Não';

export function ModalIngressoGrupoAcao({
  open, onClose, nomeAcao, card, lista, podeVerContato,
  demonstracao, isMaster = false, onMarcarTeste,
}: {
  open: boolean;
  onClose: () => void;
  nomeAcao: string;
  card: MetricaAtm;
  lista: EstadoListaAtm<LeadGrupoAtm> | null;
  podeVerContato: boolean;
  demonstracao: boolean;
  /** Marcar número como teste (15/10/2026): só master. O número sai da lista e do ingresso da ação. */
  isMaster?: boolean;
  onMarcarTeste?: (linha: LeadGrupoAtm) => Promise<string | null>;
}) {
  const [alvo, setAlvo] = useState<LeadGrupoAtm | null>(null);
  const [salvando, setSalvando] = useState<string | null>(null);
  const [erroAcao, setErroAcao] = useState<string | null>(null);
  const comAcao = isMaster && !!onMarcarTeste && !demonstracao;
  const marcar = async (linha: LeadGrupoAtm) => {
    if (salvando || !onMarcarTeste) return;
    setAlvo(null); setSalvando(linha.foneGrupo); setErroAcao(null);
    const erro = await onMarcarTeste(linha);
    setSalvando(null);
    if (erro) setErroAcao(erro);
  };
  const dados = lista?.data;
  const erro = Boolean(lista?.erro && dados !== null);
  const conteudo = !podeVerContato
    ? <EmptyState title="Lista de participantes restrita" hint="Você não tem permissão para ver os contatos. Peça a permissão contato.ver. Os indicadores continuam disponíveis." />
    : !lista || lista.fase === 'carregando'
      ? <Loading />
      : lista.fase === 'semPermissao'
        ? <EmptyState title="Lista de participantes restrita" hint="Você não tem permissão para ver os contatos. Peça a permissão contato.ver." />
        : lista.fase === 'naoPublicada'
          ? <EmptyState title="Lista de entradas ainda não publicada" hint="A lista será carregada quando a RPC estiver disponível." />
          : lista.data === null
            ? <p role="alert" className="rounded border border-[var(--yellow)]/40 p-3 text-sm text-[var(--yellow)]">{lista.erro ?? 'Falha ao carregar a lista. Tente atualizar.'}</p>
            : lista.data.length === 0
              ? <EmptyState title="Nenhuma entrada no grupo" hint="Não há números únicos retornados para este evento." />
              : <DataTable minWidth={1050} fixed>
                <Thead><Th className="w-[130px]">Nome</Th><Th className="w-[185px]">E-mail</Th><Th className="w-[135px]">Telefone</Th><Th className="w-[75px]">Turma</Th><Th className="w-[100px]">Instrução</Th><Th className="w-[130px]">Origem</Th><Th className="w-[170px]">Entrada no grupo</Th><Th className="w-[125px]">Situação</Th>{comAcao && <Th className="w-[150px]">Teste</Th>}</Thead>
                <tbody>{lista.data.map((linha) => <Tr key={linha.foneGrupo}>
                  <Td className="break-words">{texto(linha.nome)}</Td><Td className="break-all">{texto(linha.email)}</Td><Td className="break-all tabular">{linha.telefone ?? linha.foneGrupo}</Td>
                  <Td className="break-words">{texto(linha.turma)}</Td><Td className="break-words">{texto(linha.instrucao)}</Td><Td className="break-words">{origemLabel[linha.origem]}</Td>
                  <Td className="whitespace-nowrap">{dataHora(linha.entrouEm)}{linha.entradaAproximada ? <span className="ml-1 text-[var(--fg-3)]">(data aproximada)</span> : null}</Td>
                  <Td className="text-xs">{linha.noGrupo !== null && <div>No grupo: {simNaoVazio(linha.noGrupo)}</div>}{linha.saiuEm && <div className="text-[var(--fg-3)]">Saiu em {dataHora(linha.saiuEm)}</div>}</Td>
                  {comAcao && <Td><button type="button" disabled={salvando === linha.foneGrupo} onClick={() => { setErroAcao(null); setAlvo(linha); }} className="min-h-9 rounded-[var(--r-md)] border border-[var(--border)] px-2 text-xs font-medium text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50">{salvando === linha.foneGrupo ? 'Salvando…' : 'Marcar como teste'}</button></Td>}
                </Tr>)}</tbody>
              </DataTable>;

  return <Modal open={open} onClose={onClose} title={`Ingresso no grupo · ${nomeAcao}`} width="max-w-6xl">
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div role="tablist" aria-label="Detalhes do ingresso no grupo">
          <button type="button" role="tab" aria-selected="true" className="min-h-10 rounded-[var(--r-md)] bg-[var(--accent)] px-3 text-xs font-semibold text-black">Leads</button>
        </div>
        <p className="text-sm text-[var(--fg-2)]">Entradas únicas: <strong className="tabular text-[var(--fg)]">{card.semDado ? 'Sem dado' : inteiro.format(card.valor)}</strong></p>
      </div>
      {!podeVerContato && <p role="note" className="text-xs text-[var(--fg-3)]">Os indicadores continuam disponíveis para seu usuário.</p>}
      {demonstracao && <p role="note" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-2 text-xs text-[var(--yellow)]">Dados de demonstração fictícios. Nenhum contato real é exibido.</p>}
      {erroAcao && <p role="alert" className="text-xs text-[var(--red)]">{erroAcao}</p>}
      {erro && <p role="status" className="text-xs text-[var(--yellow)]">A leitura da lista falhou. Os últimos dados carregados foram mantidos.</p>}
      <div role="tabpanel" aria-label="Leads que entraram no grupo" className="max-h-[65vh] overflow-auto">{conteudo}</div>
      <p className="text-[11px] text-[var(--fg-3)]">Uma linha por número único que entrou no grupo. Nome e contato só aparecem para quem tem permissão de ver contatos.</p>
    </div>
    {alvo && <ConfirmDialog title="Marcar número do grupo como teste" confirmLabel="Marcar como teste" cancelLabel="Cancelar" onCancel={() => setAlvo(null)} onConfirm={() => void marcar(alvo)} message={`Esta marcação vale só para esta ação da Black. O número ${alvo.telefone ?? alvo.foneGrupo} sai da lista e deixa de contar no ingresso no grupo e nos leads dela. Se o número for lead, dá para desfazer em "Desmarcar teste" no modal de Leads, com "incluir testes" ligado; se não for, só pelo time de dados. Quer continuar?`} />}
  </Modal>;
}
