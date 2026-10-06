'use client';

// Aba "Histórico" da ficha do aluno: alterações feitas por pedido aprovado (pa_historico_aluno), mais recente
// primeiro. O texto já vem pronto do banco (nomes, "aprovado por", documento mascarado por pa_pode_ver_doc()).
// Como a Trajetória: 1 RPC na 1ª abertura da aba, cache por aluno no módulo (a ficha remonta a cada aluno).
import { useCallback, useEffect, useState } from 'react';
import { Button, Loading, SectionCard } from '@/shared/ui/components';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { fmtDataHora } from '@/shared/ui/format';
import type { ItemHistoricoAluno } from '../domain/pedidos-alteracao';
import { SecTitle } from './alunos-ui-bits';
import { historicoAluno } from './pedidos-alteracao-data';

const cache = new Map<string, ItemHistoricoAluno[]>();

// Logout é router.push (não recarrega): o próximo usuário da mesma máquina não herda o cache (documento sem máscara).
if (typeof window !== 'undefined') {
  createBrowserSupabase().auth.onAuthStateChange((ev) => {
    if (ev === 'SIGNED_OUT' || ev === 'SIGNED_IN') cache.clear();
  });
}

/** Pedido aprovado na mesma sessão muda o histórico de até 3 pessoas (titular, quem sai, quem entra): zera tudo. */
export function limparHistoricoAluno() {
  cache.clear();
}

export function HistoricoAluno({ alunoId }: { alunoId: string }) {
  const [itens, setItens] = useState<ItemHistoricoAluno[] | null>(() => cache.get(alunoId) ?? null);
  const [erro, setErro] = useState<string | null>(null);
  const [tentativa, setTentativa] = useState(0);

  useEffect(() => {
    if (cache.has(alunoId)) return;
    let vivo = true;
    historicoAluno(alunoId)
      .then((l) => { cache.set(alunoId, l); if (vivo) setItens(l); })
      .catch((e: unknown) => { if (vivo) setErro(e instanceof Error ? e.message : 'Não foi possível carregar o histórico de alterações.'); });
    return () => { vivo = false; };
  }, [alunoId, tentativa]);

  const tentarDeNovo = useCallback(() => { setErro(null); setTentativa((t) => t + 1); }, []);

  if (erro) {
    return (
      <div className="flex flex-wrap items-center gap-2" role="alert">
        <p className="text-xs text-[var(--red)]">{erro}</p>
        <Button size="sm" variant="ghost" onClick={tentarDeNovo}>Tentar de novo</Button>
      </div>
    );
  }
  if (!itens) return <Loading label="Carregando histórico…" minHeight={100} />;
  if (!itens.length) return <p className="text-xs text-[var(--fg-3)]">Nenhuma alteração por pedido registrada ainda.</p>;

  return (
    <SectionCard
      title={<SecTitle icon="clipboard">Alterações por pedido</SecTitle>}
      subtitle={`${itens.length} ${itens.length === 1 ? 'registro' : 'registros'}, do mais recente para o mais antigo`}
    >
      <ol className="divide-y divide-[var(--border-faint)]" aria-label="Histórico de alterações por pedido">
        {itens.map((h, i) => (
          <li key={`${h.pedido_id}-${h.papel}-${i}`} className="grid grid-cols-[130px_1fr] gap-3 py-2 text-sm">
            <span className="text-xs text-[var(--fg-3)] tabular pt-0.5">
              <time dateTime={h.em}>{fmtDataHora(h.em)}</time>
              <span className="block">Pedido nº {h.pedido_id}</span>
            </span>
            <span className="text-[var(--fg)] break-words min-w-0">{h.texto}</span>
          </li>
        ))}
      </ol>
    </SectionCard>
  );
}
