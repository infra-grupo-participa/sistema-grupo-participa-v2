'use client';

// Aba "Formulários" da ficha: o que o aluno respondeu no Respondi (questionário inicial, nível,
// inclusão de sócios, cadastro, eventos, pesquisas), mais recente primeiro. Sócio vê também a
// "Inclusão sócios" em que o titular o declarou. 1 RPC (fn_aluno_respondi, só equipe) na 1ª abertura
// da aba; cache por aluno no módulo, como a Trajetória.
import { useEffect, useMemo, useState } from 'react';
import { Badge, Loading, SectionCard } from '@/shared/ui/components';
import { SecTitle } from './alunos-ui-bits';
import { fmtData } from '@/shared/ui/format';
import { itensResposta } from '../domain/respondi-texto';
import { loadRespondiAluno, type RespostaRespondi } from './alunos-data';

const cache = new Map<string, RespostaRespondi[]>();

const FAMILIAS: { k: string; l: string }[] = [
  { k: 'nivel', l: 'Comprovação de nível' },
  { k: 'socios', l: 'Inclusão de sócios' },
  { k: 'questionario_inicial', l: 'Questionário inicial' },
  { k: 'cadastro', l: 'Cadastro' },
  { k: 'evento', l: 'Eventos' },
  { k: 'pesquisa', l: 'Pesquisas' },
  { k: 'outros', l: 'Outros' },
];

function Resposta({ r, alunoId }: { r: RespostaRespondi; alunoId: string }) {
  const comoSocio = r.familia === 'socios' && r.dados?.socio_aluno_id === alunoId;
  const itens = itensResposta(r.respostas);
  return (
    <details className="rounded-[var(--r-sm)] border border-[var(--border)] px-3 py-2">
      <summary className="cursor-pointer flex flex-wrap items-center gap-2 text-sm">
        <span className="tabular text-[var(--fg-3)]">{fmtData(r.respondido_em)}</span>
        <span className="text-[var(--fg-1)]">{r.formulario}</span>
        <Badge>{r.workspace}</Badge>
        {comoSocio && <Badge tone="accent">Declarado como sócio</Badge>}
      </summary>
      <dl className="mt-2 grid gap-1 text-xs">
        {itens.map((p, i) => (
          <div key={i} className="grid grid-cols-[minmax(0,2fr)_minmax(0,3fr)] gap-2">
            <dt className="text-[var(--fg-3)]">{p.q}</dt>
            <dd className="text-[var(--fg-1)] break-words">{p.v}</dd>
          </div>
        ))}
      </dl>
    </details>
  );
}

export function AlunoAbaFormularios({ alunoId }: { alunoId: string }) {
  const [linhas, setLinhas] = useState<RespostaRespondi[] | null>(() => cache.get(alunoId) ?? null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (cache.has(alunoId)) return;
    let vivo = true;
    loadRespondiAluno(alunoId)
      .then((l) => { cache.set(alunoId, l); if (vivo) setLinhas(l); })
      .catch((e: unknown) => { if (vivo) setErro(e instanceof Error ? e.message : 'Não foi possível carregar os formulários.'); });
    return () => { vivo = false; };
  }, [alunoId]);

  const grupos = useMemo(
    () => FAMILIAS.map((f) => ({ ...f, itens: (linhas ?? []).filter((r) => r.familia === f.k) })).filter((g) => g.itens.length > 0),
    [linhas],
  );

  if (erro) return <p className="text-xs text-[var(--red)]" role="alert">{erro}</p>;
  if (!linhas) return <Loading />;
  if (linhas.length === 0) return <p className="text-sm text-[var(--fg-3)]">Nenhum formulário do Respondi ligado a este aluno.</p>;

  return (
    <>
      {grupos.map((g) => (
        <SectionCard key={g.k} title={<SecTitle icon="biblioteca">{`${g.l} · ${g.itens.length}`}</SecTitle>}>
          <div className="space-y-2">
            {g.itens.map((r) => <Resposta key={r.uuid} r={r} alunoId={alunoId} />)}
          </div>
        </SectionCard>
      ))}
    </>
  );
}
