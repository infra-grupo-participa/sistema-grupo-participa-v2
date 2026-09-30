'use client';

// "Por que está no programa" — topo da aba Programa da ficha. O status vem da lista (fn_aluno_programas_safe,
// já carregada); as evidências saem de fn_aluno_programa_evidencias 1× por ficha: o painel da aba só monta na
// 1ª visita e fica montado ao trocar de aba. Sem cache de módulo (a resposta pode trazer valor em R$).
import { useEffect, useState } from 'react';
import { Button, SectionCard } from '@/shared/ui/components';
import { fmtData } from '@/shared/ui/format';
import {
  ordenarProgramas, rotuloFonte, rotuloMotivo, rotuloPrograma, rotuloStatusPrograma,
  type EvidenciaPrograma, type ProgramaAluno,
} from '../domain/programa-selo';
import { loadEvidenciasPrograma } from './conciliacao-data';
import { SecTitle } from './alunos-ui-bits';

const brl = (v: number) => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

export function AlunoProgramaEvidencias({ alunoId, programa }: { alunoId: string; programa: ProgramaAluno | undefined }) {
  const [ev, setEv] = useState<EvidenciaPrograma[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [tentativa, setTentativa] = useState(0);

  useEffect(() => {
    let vivo = true;
    loadEvidenciasPrograma(alunoId).then((r) => {
      if (!vivo) return;
      if (r.ok) { setEv(r.data); setErro(null); } else setErro(r.erro);
    });
    return () => { vivo = false; };
  }, [alunoId, tentativa]);

  const progs = programa ? ordenarProgramas(programa.programas) : [];
  const temValor = !!ev?.some((e) => e.valor != null);

  return (
    <SectionCard title={<SecTitle icon="check">Por que está no programa</SecTitle>}>
      {progs.length > 0 ? (
        <ul className="mb-2">
          {progs.map((k) => {
            const st = programa!.status_programa[k];
            return (
              <li key={k} className="flex justify-between gap-3 py-1 border-b border-[var(--border-faint)]">
                <span className="text-sm text-[var(--fg)]">{rotuloPrograma(k)}</span>
                <span className={`text-xs ${st === 'a_revisar' ? 'text-[var(--yellow)]' : 'text-[var(--fg-2)]'}`}>{st ? rotuloStatusPrograma(st) : '—'}</span>
              </li>
            );
          })}
        </ul>
      ) : <p className="text-xs text-[var(--fg-3)] mb-2">Nenhum programa identificado.</p>}
      {programa && programa.revisar_motivos.length > 0 && (
        <div className="mb-2">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-1">A revisar</div>
          <ul className="text-xs text-[var(--yellow)] space-y-0.5">
            {programa.revisar_motivos.map((m) => <li key={m}>{rotuloMotivo(m)}</li>)}
          </ul>
        </div>
      )}

      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mt-3 mb-1 pt-1 border-t border-[var(--border-faint)]">Evidências</div>
      {erro ? (
        <div className="flex flex-wrap items-center gap-2" role="alert">
          <p className="text-xs text-[var(--red)]">{erro}</p>
          <Button size="sm" variant="ghost" onClick={() => { setErro(null); setTentativa((t) => t + 1); }}>Tentar de novo</Button>
        </div>
      ) : !ev ? (
        <p className="text-xs text-[var(--fg-3)]" role="status">Carregando evidências…</p>
      ) : !ev.length ? (
        <p className="text-xs text-[var(--fg-3)]">Nenhuma evidência encontrada.</p>
      ) : (
        <table className="w-full text-sm">
          <thead className="sr-only">
            <tr><th>Programa</th><th>Fonte</th><th>Descrição</th><th>Data</th>{temValor && <th>Valor</th>}</tr>
          </thead>
          <tbody>
            {ev.map((e, i) => (
              <tr key={i} className="border-b border-[var(--border-faint)] last:border-0 align-top">
                <td className="py-1 pr-2 text-xs text-[var(--fg-3)] whitespace-nowrap">{e.programa ? rotuloPrograma(e.programa) : '—'}</td>
                <td className="py-1 pr-2 text-xs text-[var(--fg-3)] whitespace-nowrap">{rotuloFonte(e.fonte)}</td>
                <td className="py-1 pr-2 text-[var(--fg)]">{e.descricao}</td>
                <td className="py-1 pr-2 text-xs text-[var(--fg-2)] whitespace-nowrap tabular">{e.data ? fmtData(e.data) : '—'}</td>
                {temValor && <td className="py-1 text-xs text-[var(--fg-2)] whitespace-nowrap tabular text-right">{e.valor != null ? brl(Number(e.valor)) : ''}</td>}
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </SectionCard>
  );
}
