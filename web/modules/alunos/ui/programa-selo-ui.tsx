'use client';

// Programa e selo de nível na lista de alunos: carga (1× por abertura da lista), filtros e célula.
import { useEffect, useMemo, useState } from 'react';
import { MultiSelect } from '@/shared/ui/components';
import {
  FILTRO_A_REVISAR, PROGRAMA_ATIVO, ROTULO_SELO, aRevisar, ordenarProgramas, rotuloPrograma, rotuloStatusPrograma,
  textoSelo, type ProgramaAluno, type SeloNivel,
} from '../domain/programa-selo';
import { loadNivelSelo, loadProgramasSafe } from './conciliacao-data';

export interface DadosProgramaSelo {
  programas: Map<string, ProgramaAluno>;
  selos: Map<string, SeloNivel>;
  /** Alguma das duas RPCs falhou: a coluna e os filtros somem, a lista segue. */
  erro: boolean;
  carregado: boolean;
}

const VAZIO: DadosProgramaSelo = { programas: new Map(), selos: new Map(), erro: false, carregado: false };

/** fn_aluno_programas_safe + fn_aluno_nivel_selo em paralelo, 1× quando `ativo` vira true. */
export function useProgramaSelo(ativo: boolean): DadosProgramaSelo {
  const [d, setD] = useState<DadosProgramaSelo>(VAZIO);
  useEffect(() => {
    if (!ativo || !PROGRAMA_ATIVO) return;
    let vivo = true;
    Promise.all([loadProgramasSafe(), loadNivelSelo()]).then(([p, s]) => {
      if (!vivo) return;
      setD({
        programas: new Map(p.ok ? p.data.map((x) => [x.aluno_id, x]) : []),
        selos: new Map(s.ok ? s.data.map((x) => [x.aluno_id, x]) : []),
        erro: !p.ok || !s.ok,
        carregado: true,
      });
    });
    return () => { vivo = false; };
  }, [ativo]);
  return d;
}

/** Filtros "Programa" (com "A revisar") e "Comprovação do nível". Opções só do que existe na base carregada. */
export function FiltrosProgramaSelo({ dados, programa, comprovacao, onPrograma, onComprovacao }: {
  dados: DadosProgramaSelo;
  programa: string[];
  comprovacao: string[];
  onPrograma: (v: string[]) => void;
  onComprovacao: (v: string[]) => void;
}) {
  const progOpts = useMemo(() => {
    const presentes = new Set<string>();
    let revisar = false;
    for (const p of dados.programas.values()) {
      p.programas.forEach((x) => presentes.add(x));
      if (aRevisar(p)) revisar = true;
    }
    return [
      ...ordenarProgramas([...presentes]).map((k) => ({ value: k, label: rotuloPrograma(k) })),
      ...(revisar ? [{ value: FILTRO_A_REVISAR, label: 'A revisar' }] : []),
    ];
  }, [dados.programas]);
  const seloOpts = useMemo(() => {
    const presentes = new Set([...dados.selos.values()].map((s) => s.selo).filter(Boolean) as string[]);
    return Object.keys(ROTULO_SELO).filter((k) => presentes.has(k)).map((k) => ({ value: k, label: ROTULO_SELO[k] }));
  }, [dados.selos]);
  if (!dados.carregado) return null;
  if (dados.erro) return <span className="text-xs text-[var(--fg-3)]" role="status">Programa e comprovação indisponíveis no momento.</span>;
  return (
    <>
      <MultiSelect values={programa} onChange={onPrograma} placeholder="Todos os programas" options={progOpts} />
      <MultiSelect values={comprovacao} onChange={onComprovacao} placeholder="Comprovação do nível" options={seloOpts} />
    </>
  );
}

/** Célula Programa: um nome por programa; status diferente de confirmado vai por extenso ao lado. */
export function CelulaPrograma({ p }: { p: ProgramaAluno | undefined }) {
  if (!p || !p.programas.length) return <span className="text-[var(--fg-3)]">—</span>;
  return (
    <div className="flex flex-col gap-0.5 text-[var(--fg-2)]">
      {ordenarProgramas(p.programas).map((k) => {
        const st = p.status_programa[k];
        return (
          <span key={k} className="whitespace-nowrap">
            {rotuloPrograma(k)}
            {st && st !== 'confirmado' && (
              <span className={`text-[11px] ml-1 ${st === 'a_revisar' ? 'text-[var(--yellow)]' : 'text-[var(--fg-3)]'}`}>· {rotuloStatusPrograma(st).toLowerCase()}</span>
            )}
          </span>
        );
      })}
    </div>
  );
}

/** Linha do selo sob o nível: "Ouro · comprovado Platina". Sem comprovação em amarelo (texto, não só cor). */
export function LinhaSelo({ nivel, s }: { nivel: string | null; s: SeloNivel | undefined }) {
  const t = textoSelo(nivel, s);
  if (!t) return null;
  return <div className={`text-[11px] mt-0.5 whitespace-nowrap ${s?.selo === 'nao_comprovado' ? 'text-[var(--yellow)]' : 'text-[var(--fg-3)]'}`}>{t}</div>;
}
