'use client';

// Corpo da aba "Trajetória" da ficha do aluno. Monta só quando a aba é aberta pela 1ª vez (1 RPC por aluno) e
// depois fica montado, oculto, ao trocar de aba; o resultado fica guardado por aluno_id no módulo — a ficha
// remonta a cada troca de aluno (key={id} em AlunosClient), então cache em estado local seria perdido ao
// reabrir. Agrupamento em marcos e filtro de dimensão são no cliente (domain/trajetoria-marcos.ts), sem query.
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Button, FilterSelect, Loading } from '@/shared/ui/components';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { TrajetoriaMarcos } from '@/shared/ui/timeline';
import type { LinhaTrajetoriaAluno } from '../domain/trajetoria-aluno';
import { faixaJornada, mesAno, type FaixaJornada } from '../domain/trajetoria-marcos';
import { loadTrajetoriaAluno } from './alunos-data';
import { OPCOES_DIMENSAO, marcosFiltrados, paraMarcosVisuais, pontosDaRegua } from './trajetoria-aluno-itens';

const cache = new Map<string, LinhaTrajetoriaAluno[]>();

// O logout é router.push (não recarrega a página): sem isto, o próximo usuário da mesma máquina veria o R$ que
// ficou em cache de quem vê o financeiro.
if (typeof window !== 'undefined') {
  createBrowserSupabase().auth.onAuthStateChange((ev) => {
    if (ev === 'SIGNED_OUT' || ev === 'SIGNED_IN') cache.clear();
  });
}

// Salvar a ficha não remonta o drawer (key = id do aluno): quem salvou avisa, e o corpo montado busca de novo.
const ouvintes = new Set<(alunoId: string) => void>();
export function invalidarTrajetoria(alunoId: string) {
  cache.delete(alunoId);
  ouvintes.forEach((f) => f(alunoId));
}

export function CorpoTrajetoria({ alunoId }: { alunoId: string }) {
  const [linhas, setLinhas] = useState<LinhaTrajetoriaAluno[] | null>(() => cache.get(alunoId) ?? null);
  const [erro, setErro] = useState<string | null>(null);
  const [tentativa, setTentativa] = useState(0);

  useEffect(() => {
    if (cache.has(alunoId)) return;
    let vivo = true;
    loadTrajetoriaAluno(alunoId)
      .then((l) => { cache.set(alunoId, l); if (vivo) setLinhas(l); })
      .catch((e: unknown) => { if (vivo) setErro(e instanceof Error ? e.message : 'Não foi possível carregar a trajetória.'); });
    return () => { vivo = false; };
  }, [alunoId, tentativa]);

  useEffect(() => {
    const ouvir = (id: string) => { if (id === alunoId) setTentativa((t) => t + 1); };
    ouvintes.add(ouvir);
    return () => { ouvintes.delete(ouvir); };
  }, [alunoId]);

  const tentarDeNovo = useCallback(() => { setErro(null); setTentativa((t) => t + 1); }, []);

  if (erro) {
    return (
      <div className="flex flex-wrap items-center gap-2" role="alert">
        <p className="text-xs text-[var(--red)]">{erro}</p>
        <Button size="sm" variant="ghost" onClick={tentarDeNovo}>Tentar de novo</Button>
      </div>
    );
  }
  if (!linhas) return <Loading label="Carregando trajetória…" minHeight={100} />;
  if (!linhas.length) return <p className="text-xs text-[var(--fg-3)]">Nenhum registro de trajetória para este aluno.</p>;

  return <TrajetoriaEmMarcos linhas={linhas} />;
}

const hojeLocal = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

export function TrajetoriaEmMarcos({ linhas }: { linhas: LinhaTrajetoriaAluno[] }) {
  const [dimensao, setDimensao] = useState<string | null>(null);
  const hoje = useMemo(() => hojeLocal(), []);
  const marcos = useMemo(() => marcosFiltrados(linhas, dimensao), [linhas, dimensao]);
  const visuais = useMemo(() => paraMarcosVisuais(marcos), [marcos]);
  const faixa = useMemo(() => faixaJornada(linhas, hoje), [linhas, hoje]);
  const regua = useMemo(() => pontosDaRegua(marcos, hoje), [marcos, hoje]);
  const contagem = useMemo(() => {
    const c = new Map<string, number>();
    for (const l of linhas) c.set(l.dimensao, (c.get(l.dimensao) ?? 0) + 1);
    return c;
  }, [linhas]);

  return (
    <TrajetoriaMarcos
      marcos={visuais}
      faixa={<TextoFaixa f={faixa} />}
      regua={regua}
      rotuloLista="Trajetória do aluno"
      vazio="Nenhum registro nesta dimensão."
      ferramentas={(
        <label className="flex items-center gap-2 text-[11px] text-[var(--fg-3)]">
          <span className="sr-only">Filtrar por dimensão</span>
          <FilterSelect
            value={dimensao ?? ''}
            onChange={(e) => setDimensao(e.target.value || null)}
            className="h-8 py-0 text-xs"
          >
            <option value="">Todas as dimensões ({linhas.length})</option>
            {OPCOES_DIMENSAO.map((o) => {
              const n = contagem.get(o.chave) ?? 0;
              return <option key={o.chave} value={o.chave} disabled={n === 0}>{o.rotulo} ({n})</option>;
            })}
          </FilterSelect>
        </label>
      )}
    />
  );
}

/** "No time desde mar/2022 · 3 anos e 6 meses · 4 compras · 1 saída · 1 volta". Última saída sem volta depois:
 *  "Entrou em mar/2022 · saiu em jan/2024 · 1 ano e 10 meses" (fato da trajetória; não afirma o status atual). */
function TextoFaixa({ f }: { f: FaixaJornada }) {
  const n = (v: number, um: string, varios: string) => `${v} ${v === 1 ? um : varios}`;
  const inferido = f.desdeInferido ? ' (1º registro)' : '';
  const desde = !f.desde
    ? 'Sem data de entrada'
    : f.fora ? `Entrou em ${mesAno(f.desde)}${inferido} · saiu em ${mesAno(f.ate)}` : `No time desde ${mesAno(f.desde)}${inferido}`;
  return (
    <p>
      <span
        className="font-semibold text-[var(--fg)]"
        title={f.desdeInferido ? 'Sem registro de entrada no THB: data do 1º registro da trajetória.' : undefined}
      >
        {desde}
      </span>
      {f.duracao && <> · {f.duracao}</>}
      {' · '}{n(f.compras, 'compra', 'compras')}
      {' · '}<span className={f.saidas ? 'text-[var(--red)]' : undefined}>{n(f.saidas, 'saída', 'saídas')}</span>
      {' · '}<span className={f.voltas ? 'text-[var(--green)]' : undefined}>{n(f.voltas, 'volta', 'voltas')}</span>
    </p>
  );
}
