'use client';

// Seção "Trajetória" da ficha do aluno. Sempre aberta (regra do Marcio: nada atrás de clique); carrega quando a
// ficha abre (1 RPC por abertura) e guarda por aluno_id
// no módulo — a ficha remonta a cada troca de aluno (key={id} em AlunosClient), então cache em estado local
// seria perdido ao reabrir. Filtro de dimensão é no cliente, dentro da LinhaDoTempo.
import { useCallback, useEffect, useState } from 'react';
import { Button, Loading, SectionCard } from '@/shared/ui/components';
import { fmtData } from '@/shared/ui/format';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { LinhaDoTempo, NumeroResumo } from '@/shared/ui/timeline';
import { resumirTrajetoriaAluno, type LinhaTrajetoriaAluno } from '../domain/trajetoria-aluno';
import { loadTrajetoriaAluno } from './alunos-data';
import { DIMENSOES_CHIPS, paraItensLinhaDoTempo } from './trajetoria-aluno-itens';
import { SecTitle } from './alunos-ui-bits';

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

export function TrajetoriaAluno({ alunoId }: { alunoId: string }) {
  return (
    <SectionCard title={<SecTitle icon="calendar-days">Trajetória</SecTitle>}>
      <CorpoTrajetoria alunoId={alunoId} />
    </SectionCard>
  );
}

function CorpoTrajetoria({ alunoId }: { alunoId: string }) {
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

  const r = resumirTrajetoriaAluno(linhas);
  return (
    <LinhaDoTempo
      itens={paraItensLinhaDoTempo(linhas)}
      dimensoes={DIMENSOES_CHIPS}
      rotuloLista="Trajetória do aluno"
      vazio="Nenhum registro de trajetória para este aluno."
      resumo={(
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <NumeroResumo
            rotulo="Entrada no THB"
            valor={r.entradaThb ? fmtData(r.entradaThb) : '—'}
            dica={r.entradaInferida ? 'Sem registro de entrada no THB: data do 1º registro da trajetória.' : undefined}
          />
          <NumeroResumo rotulo="Compras" valor={String(r.compras)} />
          <NumeroResumo rotulo="Saídas · voltas" valor={`${r.saidas} · ${r.voltas}`} />
          <NumeroResumo rotulo="Eventos" valor={String(r.eventos)} />
        </div>
      )}
    />
  );
}
