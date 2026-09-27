'use client';

// "Mapa de alunos" do Board HM (pedido do João, 27/09): todo aluno do início do Programa até hoje, uma linha por
// pessoa, com a diferença entre quem está no Programa e quem é do HM antigo, o passo financeiro de cada um e as filas
// de quem cobrar. SÓ VISUALIZAÇÃO — ninguém é contatado automaticamente; a equipe corre atrás a partir daqui.
import { useMemo, useState } from 'react';
import { Badge, DataTable, EmptyState, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import type { Tone } from '@/shared/ui/components/Badge';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import { celulaCsv } from '../domain/hotmart';
import {
  etapaDe, montarEsteira, ROTULO_ESTEIRA, ROTULO_PROGRAMA, ROTULO_SITUACAO_ALUNO,
  type EtapaEsteira, type MapaAluno, type ProgramaAluno, type SituacaoAluno,
} from '../domain/mapa-alunos';
import { Chip, Erro, useCarga } from './hotmart/comum';

const TOM_SITUACAO: Record<SituacaoAluno, Tone> = {
  quitado: 'success', em_dia: 'info', atrasado: 'danger', so_sinal: 'warning', cancelado: 'neutral', reembolsado: 'neutral', sem_divida: 'neutral',
};
const TOM_PROGRAMA: Record<ProgramaAluno, Tone> = {
  programa: 'success', so_sinal: 'warning', renovacao: 'neutral', hm_antigo: 'neutral', tentou: 'neutral',
};
const COR_ETAPA: Record<EtapaEsteira, string> = {
  so_sinal: 'var(--yellow)', atrasado: 'var(--red)', em_dia: 'var(--blue, var(--accent))', quitado: 'var(--green)', cancelado: 'var(--fg-4)', fora: 'var(--fg-4)',
};
const DICA_ETAPA: Record<EtapaEsteira, string> = {
  so_sinal: 'Reservaram a vaga e não pagaram o restante — fila de recuperação',
  atrasado: 'Parcela vencida na Hotmart ou acordo do board vencido — cobrar',
  em_dia: 'Pagando o saldo em parcelas, sem atraso',
  quitado: 'Pagaram a 1ª metade inteira',
  cancelado: 'Cancelaram ou foram reembolsados',
  fora: 'HM antigo, renovação ou só tentativa — contexto, não cobrança',
};

export function MapaAlunos({ repo, onAbrirCard }: { repo: FinanceiroRepository; onAbrirCard: (contatoHmId: string) => void }) {
  const { dados, erro } = useCarga<MapaAluno[]>(() => repo.loadMapaAlunos(), []);
  const [etapa, setEtapa] = useState<EtapaEsteira | null>('so_sinal');
  const [busca, setBusca] = useState('');
  const [gps, setGps] = useState<'todos' | 'sim' | 'nao'>('todos');
  const [canal, setCanal] = useState('');

  const esteira = useMemo(() => montarEsteira(dados ?? []), [dados]);
  const canais = useMemo(() => [...new Set((dados ?? []).map((a) => a.canal).filter(Boolean) as string[])].sort(), [dados]);
  const termo = busca.trim().toLowerCase();
  const lista = useMemo(() => (dados ?? []).filter((a) =>
    (etapa == null || etapaDe(a) === etapa) &&
    (gps === 'todos' || (gps === 'sim') === a.no_gps) &&
    (!canal || a.canal === canal) &&
    (!termo || (a.nome ?? '').toLowerCase().includes(termo) || (a.emails ?? []).some((e) => e.includes(termo)) ||
      (a.vendedor ?? '').toLowerCase().includes(termo) || (a.turma ?? '').toLowerCase().includes(termo))),
  [dados, etapa, gps, canal, termo]);

  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Montando o mapa de alunos…" minHeight={240} />;

  const totalPessoas = dados.length;
  const noPrograma = dados.filter((a) => a.programa === 'programa').length;
  const liberadas2a = dados.filter((a) => a.segunda_metade_liberada).length;

  return (
    <div className="space-y-4">
      <SectionCard
        title="Esteira do Programa de Implementação Assistida"
        subtitle={`${totalPessoas} pessoas desde o início do Programa (01/2026), cada uma uma vez. "No Programa" = pagou o cheio ou o saldo (${noPrograma}). Clique numa etapa para ver quem está nela.`}
      >
        <div className="grid gap-2 [grid-template-columns:repeat(auto-fill,minmax(160px,1fr))]">
          {esteira.map((e) => {
            const ativo = etapa === e.etapa;
            return (
              <button key={e.etapa} type="button" aria-pressed={ativo} onClick={() => setEtapa(ativo ? null : e.etapa)}
                title={DICA_ETAPA[e.etapa]}
                className={`rounded-[var(--r-md)] border px-3 py-2.5 text-left transition-colors focus-visible:ring-2 ${ativo ? 'border-[var(--accent)] bg-[var(--accent-subtle)]' : 'border-[var(--border)] bg-[var(--surface-2)] hover:bg-[var(--surface-3)]'}`}
                style={{ boxShadow: `inset 3px 0 0 ${COR_ETAPA[e.etapa]}` }}>
                <div className="text-[11px] text-[var(--fg-3)]">{ROTULO_ESTEIRA[e.etapa]}</div>
                <div className="tabular text-xl font-bold text-[var(--fg)]">{e.pessoas}</div>
                <div className="text-[11px] tabular text-[var(--fg-3)]">
                  {e.aReceber > 0 ? <>a receber <strong className="text-[var(--fg-2)]">{fmtBRL(e.aReceber)}</strong></> : <>pago {fmtBRL(e.pago)}</>}
                </div>
              </button>
            );
          })}
        </div>
        <p className="mt-2 text-[11px] text-[var(--fg-4)]">
          Valores da 1ª metade (R$ 15 mil). A 2ª metade só é cobrada quando o parceiro fatura R$ 150 mil — hoje {liberadas2a} {liberadas2a === 1 ? 'parceiro chegou' : 'parceiros chegaram'} lá (honorários contratados no GPS).
        </p>
      </SectionCard>

      <div className="flex flex-wrap items-center gap-2">
        <input type="search" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome, e-mail, vendedor ou turma"
          aria-label="Buscar aluno" className="w-full max-w-xs rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface)] px-3 py-1.5 text-sm" />
        <Chip ativo={gps === 'todos'} onClick={() => setGps('todos')}>GPS: todos</Chip>
        <Chip ativo={gps === 'sim'} onClick={() => setGps('sim')} tom="info">Com acesso ao GPS</Chip>
        <Chip ativo={gps === 'nao'} onClick={() => setGps('nao')}>Sem GPS</Chip>
        <select value={canal} onChange={(e) => setCanal(e.target.value)} aria-label="Filtrar por canal de origem"
          className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1.5 text-xs">
          <option value="">Todos os canais</option>
          {canais.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
        <button type="button" onClick={() => exportarCsv(lista)}
          className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
          Exportar CSV ({lista.length})
        </button>
      </div>

      <SectionCard
        title={`${etapa ? ROTULO_ESTEIRA[etapa] : 'Todos'} · ${lista.length}`}
        subtitle={etapa ? DICA_ETAPA[etapa] : 'Todas as etapas.'}
      >
        {!lista.length ? <EmptyState title="Ninguém neste recorte" /> : (
          <DataTable minWidth={1150}>
            <Thead>
              <Th>Pessoa</Th><Th>Programa · situação</Th><Th>Origem</Th><Th>Pago (Programa)</Th><Th>Falta pagar</Th>
              <Th>Devendo</Th><Th>Último pagamento</Th><Th>Turma · GPS</Th><Th>2ª metade</Th><Th>Responsável</Th>
            </Thead>
            <tbody>
              {lista.slice(0, 600).map((a) => (
                <Tr key={a.pessoa_chave} onClick={a.contato_hm_id ? () => onAbrirCard(a.contato_hm_id!) : undefined}
                  className={a.contato_hm_id ? 'cursor-pointer' : undefined}>
                  <Td className="min-w-[200px]">
                    <div className="font-medium text-[var(--fg)]">{a.nome ?? '—'}</div>
                    <div className="text-[11px] text-[var(--fg-3)] break-all">{a.email ?? '—'}</div>
                    {a.telefone && <div className="text-[11px] tabular text-[var(--fg-4)]">{a.telefone}</div>}
                  </Td>
                  <Td>
                    <div className="flex flex-wrap gap-1">
                      <Badge tone={TOM_PROGRAMA[a.programa]}>{ROTULO_PROGRAMA[a.programa]}</Badge>
                      {!(a.programa === 'so_sinal' && a.situacao === 'so_sinal') && (
                        <Badge tone={TOM_SITUACAO[a.situacao]}>{ROTULO_SITUACAO_ALUNO[a.situacao]}</Badge>
                      )}
                    </div>
                    {a.entrou_programa_em && <div className="mt-0.5 text-[11px] text-[var(--fg-3)]">no Programa desde {fmtData(a.entrou_programa_em)}</div>}
                    {a.veio_do_acelera && <div className="text-[11px] text-[var(--fg-3)]">veio do Acelera</div>}
                  </Td>
                  <Td className="text-[11px]">
                    <div className="text-[var(--fg-2)]">{a.canal ?? '—'}</div>
                    {a.primeira_compra_em && <div className="text-[var(--fg-3)]">1ª compra {fmtData(a.primeira_compra_em)}</div>}
                    {a.origem_sck && <div className="text-[var(--fg-4)] break-all">{a.origem_sck}</div>}
                  </Td>
                  <Td className="tabular">
                    {fmtBRL(a.pago_programa)}
                    {a.sinal_pago > 0 && <div className="text-[11px] text-[var(--fg-3)]">sinal {fmtBRL(a.sinal_pago)}</div>}
                    {a.pago_vida > a.pago_programa && <div className="text-[11px] text-[var(--fg-4)]">na vida {fmtBRL(a.pago_vida)}</div>}
                  </Td>
                  <Td className="tabular font-semibold text-[var(--fg)]">
                    {a.falta_pagar == null ? '—' : a.falta_pagar > 0.5 ? fmtBRL(a.falta_pagar) : <span className="text-[var(--green)]">nada</span>}
                    {!a.contato_hm_id && a.programa === 'so_sinal' && <div className="text-[10px] font-normal text-[var(--fg-4)]">estimado (sem card)</div>}
                  </Td>
                  <Td className="tabular">
                    {a.parcelas_devidas > 0 ? <span className="text-[var(--red)]">{fmtBRL(a.valor_devido)} · {a.parcelas_devidas}p</span> : '—'}
                  </Td>
                  <Td className="tabular text-[var(--fg-2)]">
                    {a.ultimo_pagamento_em ? fmtData(a.ultimo_pagamento_em) : '—'}
                    {a.ultima_tentativa_em && (!a.ultimo_pagamento_em || a.ultima_tentativa_em > a.ultimo_pagamento_em) && (
                      <div className="text-[11px] text-[var(--yellow)]">tentou {fmtData(a.ultima_tentativa_em)}</div>
                    )}
                  </Td>
                  <Td className="text-[11px]">
                    <div className="flex flex-wrap gap-1">
                      {a.turma && <Badge>{a.turma}</Badge>}
                      {a.no_gps && <Badge tone="info">GPS</Badge>}
                      {!a.contato_hm_id && <span className="text-[var(--fg-4)]">sem card</span>}
                    </div>
                  </Td>
                  <Td className="text-[11px] tabular">
                    {a.programa === 'programa'
                      ? a.segunda_metade_liberada
                        ? <Badge tone="warning">liberada</Badge>
                        : <span className="text-[var(--fg-3)]">{fmtBRL(a.honorarios_contratados)} de R$ 150.000</span>
                      : '—'}
                  </Td>
                  <Td className="text-[11px] text-[var(--fg-2)]">{a.vendedor ?? '—'}</Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
        {lista.length > 600 && <p className="mt-2 text-xs text-[var(--fg-3)]">Mostrando 600 de {lista.length}. Use a busca, o canal ou uma etapa para ver o resto (o CSV leva todos).</p>}
      </SectionCard>
    </div>
  );
}

function exportarCsv(lista: MapaAluno[]) {
  const col: [string, (a: MapaAluno) => unknown][] = [
    ['Nome', (a) => a.nome], ['E-mail', (a) => a.email], ['Telefone', (a) => a.telefone],
    ['Programa', (a) => ROTULO_PROGRAMA[a.programa]], ['Situação', (a) => ROTULO_SITUACAO_ALUNO[a.situacao]],
    ['Etapa', (a) => ROTULO_ESTEIRA[etapaDe(a)]], ['No Programa desde', (a) => a.entrou_programa_em],
    ['1ª compra', (a) => a.primeira_compra_em], ['Canal', (a) => a.canal], ['SCK', (a) => a.origem_sck],
    ['Pago no Programa', (a) => a.pago_programa], ['Sinal', (a) => a.sinal_pago], ['Pago na vida (HM)', (a) => a.pago_vida],
    ['Falta pagar (1ª metade)', (a) => a.falta_pagar], ['Devendo', (a) => a.valor_devido], ['Parcelas devidas', (a) => a.parcelas_devidas],
    ['Último pagamento', (a) => a.ultimo_pagamento_em], ['Última tentativa', (a) => a.ultima_tentativa_em],
    ['Turma', (a) => a.turma], ['GPS', (a) => (a.no_gps ? 'sim' : 'não')], ['Card', (a) => (a.contato_hm_id ? 'sim' : 'não')],
    ['Honorários contratados (GPS)', (a) => a.honorarios_contratados], ['2ª metade liberada', (a) => (a.segunda_metade_liberada ? 'sim' : 'não')],
    ['Responsável', (a) => a.vendedor], ['Veio do Acelera', (a) => (a.veio_do_acelera ? 'sim' : 'não')],
  ];
  const linhas = [col.map(([c]) => c).join(';'), ...lista.map((a) => col.map(([, f]) => celulaCsv(f(a))).join(';'))];
  const blob = new Blob(['﻿' + linhas.join('\n')], { type: 'text/csv;charset=utf-8' });
  const el = document.createElement('a');
  el.href = URL.createObjectURL(blob);
  el.download = `mapa-alunos-hm-${new Date().toISOString().slice(0, 10)}.csv`;
  el.click();
  URL.revokeObjectURL(el.href);
}
