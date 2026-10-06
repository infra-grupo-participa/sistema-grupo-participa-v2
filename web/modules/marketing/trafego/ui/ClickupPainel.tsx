'use client';

// Atividades do ClickUp na vida do projeto (decisão de 05/10/2026: ficam na tela), pela etiqueta do projeto, junto do
// gasto diário numa linha do tempo. Lê public.trafego_clickup (migration 20261005r), o espelho que a rotina
// trafego-clickup grava (só leitura no ClickUp).
import { useEffect, useState } from 'react';
import { Badge, DataTable, EmptyState, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { montarLinhaDoTempo, marcoDaTarefa } from '../domain/linha-do-tempo';
import type { ClickupProjeto, DiaSerie } from '../domain/tipos';
import { carregarClickup } from '../infrastructure/trafego-data';
import { SEM_DADO, dataBR, reais } from './formato';

const ROTULO_MARCO = { concluida: 'concluída', prazo: 'prazo', inicio: 'início', criada: 'criada' } as const;
const dataIso = (v: string | null) => (v ? new Date(v).toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : SEM_DADO);

function LinhaDoTempo({ serie, dados, ate }: { serie: DiaSerie[]; dados: ClickupProjeto; ate: string }) {
  const { dias, maxGasto, fora } = montarLinhaDoTempo(serie, dados.tarefas, ate);
  if (dias.length === 0) return null;
  return (
    <figure className="mb-4">
      <div className="flex h-36 items-end gap-px" role="img" aria-label={`Gasto diário e atividades do ClickUp de ${dataBR(dias[0].dia)} a ${dataBR(dias.at(-1)!.dia)}`}>
        {dias.map((d) => {
          const h = d.gasto != null && maxGasto > 0 ? Math.max(2, Math.round((d.gasto / maxGasto) * 100)) : 0;
          const titulo = [`${dataBR(d.dia)}: ${d.gasto == null ? 'sem gasto coletado' : reais(d.gasto)}`, ...d.tarefas.map((t) => `• ${t.nome}`)].join('\n');
          return (
            <div key={d.dia} className="relative flex h-full flex-1 flex-col justify-end" title={titulo}>
              {d.tarefas.length > 0 && (
                <span className="absolute left-1/2 top-0 grid h-4 min-w-4 -translate-x-1/2 place-items-center rounded-full bg-[var(--purple)] px-1 text-[10px] font-semibold text-white">
                  {d.tarefas.length}
                </span>
              )}
              <div className="w-full rounded-t-sm bg-[var(--accent)]" style={{ height: `${h * 0.82}%`, minHeight: h ? 2 : 0 }} />
            </div>
          );
        })}
      </div>
      <figcaption className="mt-1 flex justify-between text-[11px] text-[var(--fg-3)]">
        <span>{dataBR(dias[0].dia)}</span>
        <span>Barras: gasto do dia (maior: {reais(maxGasto)}). Bolinhas: atividades do ClickUp no dia (passe o mouse).{fora ? ` ${fora} fora da janela.` : ''}</span>
        <span>{dataBR(dias.at(-1)!.dia)}</span>
      </figcaption>
    </figure>
  );
}

export function ClickupPainel({ projetoId, serie, ate, versao }: { projetoId: number; serie: DiaSerie[]; ate: string; versao: number }) {
  const [dados, setDados] = useState<ClickupProjeto | null | undefined>(undefined);

  useEffect(() => {
    let vivo = true;
    carregarClickup(projetoId).then((x) => { if (vivo) setDados(x); });
    return () => { vivo = false; };
  }, [projetoId, versao]);

  if (dados === undefined) return null;
  return <ClickupVista dados={dados} serie={serie} ate={ate} />;
}

/** O painel em si (sem carregar), para testar a renderização. */
export function ClickupVista({ dados, serie, ate }: { dados: ClickupProjeto | null; serie: DiaSerie[]; ate: string }) {
  if (dados === null) {
    return <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar as atividades (sem acesso, ou a migration 20261005r ainda não foi aplicada).</p>;
  }
  if (!dados.etiqueta) {
    return <p className="text-sm text-[var(--fg-2)]">Este projeto não tem etiqueta do ClickUp cadastrada (em Marketing &gt; Projetos e páginas): sem atividades.</p>;
  }
  return (
    <div>
      <p className="mb-3 text-xs text-[var(--fg-3)]">
        Tarefas com a etiqueta <span className="font-mono text-[var(--fg)]">{dados.etiqueta}</span>, lidas do ClickUp (só leitura).{' '}
        {!dados.configurado ? 'A leitura do ClickUp ainda não está ligada (falta o token e o workspace).'
          : dados.ultima_coleta ? `Última leitura: ${new Date(dados.ultima_coleta.em).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' })}${dados.ultima_coleta.ok ? '' : ' (falhou)'}.`
          : 'Ainda não houve leitura.'}
      </p>
      <LinhaDoTempo serie={serie} dados={dados} ate={ate} />
      {dados.tarefas.length === 0 ? (
        <EmptyState title="Nenhuma atividade com esta etiqueta" hint="As tarefas aparecem depois da leitura diária do ClickUp." />
      ) : (
        <DataTable minWidth={760}>
          <Thead><Th>Atividade</Th><Th>Status</Th><Th>Responsáveis</Th><Th>Na linha do tempo</Th><Th>Prazo</Th><Th>Concluída</Th></Thead>
          <tbody>
            {dados.tarefas.map((t) => {
              const m = marcoDaTarefa(t);
              return (
                <Tr key={t.id}>
                  <Td>{t.url ? <a href={t.url} target="_blank" rel="noopener noreferrer" className="text-[var(--accent)] hover:underline">{t.nome}</a> : t.nome}</Td>
                  <Td>{t.status ? <Badge tone={t.concluida_em ? 'success' : 'neutral'}>{t.status}</Badge> : SEM_DADO}</Td>
                  <Td>{t.responsaveis.length ? t.responsaveis.join(', ') : SEM_DADO}</Td>
                  <Td>{m ? `${dataBR(m.dia)} (${ROTULO_MARCO[m.tipo]})` : SEM_DADO}</Td>
                  <Td>{dataIso(t.prazo)}</Td>
                  <Td>{dataIso(t.concluida_em)}</Td>
                </Tr>
              );
            })}
          </tbody>
        </DataTable>
      )}
    </div>
  );
}
