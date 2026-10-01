'use client';

// Aba "Formulários" da ficha: o que o aluno respondeu no Respondi (questionário inicial, nível,
// inclusão de sócios, cadastro, eventos, pesquisas), mais recente primeiro. Sócio vê também a
// "Inclusão sócios" em que o titular o declarou. 1 RPC (fn_aluno_respondi, só equipe) na 1ª abertura
// da aba; cache por aluno no módulo, como a Trajetória.
import { useEffect, useMemo, useState } from 'react';
import { Badge, Loading, SectionCard } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
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

function Resposta({ r, alunoId, aberta, alternar }: { r: RespostaRespondi; alunoId: string; aberta: boolean; alternar: () => void }) {
  const comoSocio = r.familia === 'socios' && r.dados?.socio_aluno_id === alunoId;
  const itens = useMemo(() => itensResposta(r.respostas), [r.respostas]);
  const corpo = `resp-${r.uuid}`;
  return (
    <li className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] overflow-hidden">
      <button
        type="button"
        onClick={alternar}
        aria-expanded={aberta}
        aria-controls={corpo}
        className="w-full grid grid-cols-[4.5rem_minmax(0,1fr)_auto] items-start gap-3 px-3 py-2.5 text-left hover:bg-[var(--surface-3)] transition-colors"
      >
        <span className="tabular text-xs text-[var(--fg-3)] pt-0.5">{fmtData(r.respondido_em)}</span>
        <span className="min-w-0">
          <span className="block text-sm font-medium text-[var(--fg)] line-clamp-2">{r.formulario}</span>
          <span className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] text-[var(--fg-3)]">
            <Badge>{r.workspace}</Badge>
            {comoSocio && <Badge tone="accent">Declarado como sócio</Badge>}
            <span>{itens.length} {itens.length === 1 ? 'resposta' : 'respostas'}</span>
          </span>
        </span>
        <span className="text-[var(--fg-3)] inline-flex pt-0.5 transition-transform" style={{ transform: aberta ? 'rotate(180deg)' : 'none' }}>
          <Icon name="chevron-down" size={14} />
        </span>
      </button>
      {aberta && (
        <dl id={corpo} className="border-t border-[var(--border-faint)] px-3 py-1 gp-fade-in">
          {itens.length === 0 && <p className="py-2 text-xs text-[var(--fg-3)]">Formulário sem respostas preenchidas.</p>}
          {itens.map((p, i) => (
            <div key={i} className="grid gap-0.5 py-2 border-b border-[var(--border-faint)] last:border-b-0 sm:grid-cols-[minmax(0,2fr)_minmax(0,3fr)] sm:gap-3">
              <dt className="text-xs text-[var(--fg-3)]">{p.q}</dt>
              <dd className="text-sm text-[var(--fg)] break-words whitespace-pre-wrap">{p.v}</dd>
            </div>
          ))}
        </dl>
      )}
    </li>
  );
}

function Filtro({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={ativo}
      className={`h-7 px-2.5 rounded-[var(--r-pill)] border text-xs tabular transition-colors ${
        ativo
          ? 'border-[var(--accent)] text-[var(--fg)] bg-[var(--surface-3)]'
          : 'border-[var(--border)] text-[var(--fg-3)] hover:text-[var(--fg-2)]'
      }`}
    >
      {children}
    </button>
  );
}

export function AlunoAbaFormularios({ alunoId }: { alunoId: string }) {
  const [linhas, setLinhas] = useState<RespostaRespondi[] | null>(() => cache.get(alunoId) ?? null);
  const [erro, setErro] = useState<string | null>(null);
  const [familia, setFamilia] = useState<string | null>(null);
  const [abertasSel, setAbertas] = useState<Set<string> | null>(null);

  useEffect(() => {
    if (cache.has(alunoId)) return;
    let vivo = true;
    loadRespondiAluno(alunoId)
      .then((l) => { cache.set(alunoId, l); if (vivo) setLinhas(l); })
      .catch((e: unknown) => { if (vivo) setErro(e instanceof Error ? e.message : 'Não foi possível carregar os formulários.'); });
    return () => { vivo = false; };
  }, [alunoId]);

  // até o 1º clique, a mais recente vem aberta
  const abertas = abertasSel ?? new Set(linhas?.length ? [linhas[0].uuid] : []);

  const grupos = useMemo(
    () => FAMILIAS.map((f) => ({ ...f, itens: (linhas ?? []).filter((r) => r.familia === f.k) })).filter((g) => g.itens.length > 0),
    [linhas],
  );
  const visiveis = familia ? grupos.filter((g) => g.k === familia) : grupos;
  const nForms = useMemo(() => new Set((linhas ?? []).map((r) => r.formulario)).size, [linhas]);

  const alternar = (uuid: string) => setAbertas(() => {
    const n = new Set(abertas);
    if (n.has(uuid)) n.delete(uuid); else n.add(uuid);
    return n;
  });

  if (erro) return <p className="text-xs text-[var(--red)]" role="alert">{erro}</p>;
  if (!linhas) return <Loading />;
  if (linhas.length === 0) return <p className="text-sm text-[var(--fg-3)]">Nenhum formulário do Respondi ligado a este aluno.</p>;

  return (
    <SectionCard
      title={<SecTitle icon="biblioteca">Formulários do Respondi</SecTitle>}
      subtitle={`${linhas.length} ${linhas.length === 1 ? 'resposta' : 'respostas'} em ${nForms} ${nForms === 1 ? 'formulário' : 'formulários'} · última em ${fmtData(linhas[0].respondido_em)}`}
    >
      {grupos.length > 1 && (
        <div className="flex flex-wrap gap-1.5 mb-3" role="group" aria-label="Filtrar por tipo de formulário">
          <Filtro ativo={!familia} onClick={() => setFamilia(null)}>Todos · {linhas.length}</Filtro>
          {grupos.map((g) => (
            <Filtro key={g.k} ativo={familia === g.k} onClick={() => setFamilia(familia === g.k ? null : g.k)}>{g.l} · {g.itens.length}</Filtro>
          ))}
        </div>
      )}
      <div className="space-y-4">
        {visiveis.map((g) => (
          <section key={g.k} aria-label={g.l}>
            {!familia && grupos.length > 1 && (
              <h4 className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-1.5">{g.l}</h4>
            )}
            <ul className="space-y-2">
              {g.itens.map((r) => (
                <Resposta key={r.uuid} r={r} alunoId={alunoId} aberta={abertas.has(r.uuid)} alternar={() => alternar(r.uuid)} />
              ))}
            </ul>
          </section>
        ))}
      </div>
    </SectionCard>
  );
}
