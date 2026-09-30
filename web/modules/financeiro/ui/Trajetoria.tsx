'use client';

// Trajetória da pessoa com o Time Holding Brasil (fn_fin_trajetoria, 28/09/2026): todo funil em que participou (ingresso)
// ou comprou, na ordem, desde 2019. A turma é a de ORIGEM — quem voltou pelo Programa mantém a turma original.
import { useEffect, useState } from 'react';
import { Loading } from '@/shared/ui/components';
import { LinhaDoTempo, NumeroResumo, type ItemLinhaDoTempo } from '@/shared/ui/timeline';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import { resumirTrajetoria, ROTULO_PAPEL, type PassoTrajetoria } from '../domain/trajetoria';

export function Trajetoria({ repo, email }: { repo: FinanceiroRepository; email: string | null }) {
  const [passos, setPassos] = useState<PassoTrajetoria[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (!email) return;
    let vivo = true;
    repo.loadTrajetoria(email)
      .then((p) => { if (vivo) setPassos(p); })
      .catch((e: unknown) => { if (vivo) setErro(e instanceof Error ? e.message : 'Não foi possível carregar a trajetória.'); });
    return () => { vivo = false; };
  }, [repo, email]);

  if (!email) return <p className="text-xs text-[var(--fg-3)]">Sem e-mail — não dá para montar a trajetória.</p>;
  if (erro) return <p className="text-xs text-[var(--red)]">{erro}</p>;
  if (!passos) return <Loading label="Carregando trajetória…" minHeight={100} />;
  if (!passos.length) return <p className="text-xs text-[var(--fg-3)]">Nenhuma compra desta pessoa na Hotmart.</p>;

  const r = resumirTrajetoria(passos);
  const turma = passos.find((p) => p.turma)?.turma ?? null;
  const itens: ItemLinhaDoTempo[] = r.etapas.map((e) => ({
    id: e.chave,
    dia: e.inicio,
    titulo: e.evento ?? 'Fora de evento',
    tom: e.comprou ? 'success' : e.participou ? 'accent' : 'neutral',
    badges: [
      ...(e.participou ? [{ rotulo: 'participou', tom: 'neutral' as const }] : []),
      ...(e.comprou ? [{ rotulo: 'comprou', tom: 'success' as const }] : []),
    ],
    detalhe: (
      <ul className="mt-0.5 space-y-0.5">
        {e.passos.map((p, i) => (
          <li key={`${p.dia}-${p.oferta}-${i}`} className="flex flex-wrap gap-x-2 text-[11px] text-[var(--fg-2)]">
            <span className="tabular text-[var(--fg-4)]">{fmtData(p.dia)}</span>
            <span>{ROTULO_PAPEL[p.papel]} · {p.produto ?? '—'}</span>
            <span className="tabular">{fmtBRL(p.valor)}{p.parcelas && p.parcelas > 1 ? ` (${p.parcelas}x)` : ''}</span>
            <span className={p.situacao === 'pago' ? 'text-[var(--green)]' : p.situacao === 'estornado' ? 'text-[var(--red)]' : 'text-[var(--yellow)]'}>{p.situacao}</span>
          </li>
        ))}
      </ul>
    ),
  }));
  return (
    <LinhaDoTempo
      itens={itens}
      rotuloLista="Trajetória por evento"
      resumo={(
        <>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <NumeroResumo rotulo="Turma de origem" valor={turma ?? '—'} />
            <NumeroResumo rotulo="1º contato" valor={r.primeiroContato ? fmtData(r.primeiroContato) : '—'} />
            <NumeroResumo rotulo="Funis" valor={`${r.funisParticipou} · comprou em ${r.funisComprou}`} />
            <NumeroResumo rotulo="Pago na vida" valor={fmtBRL(r.totalPago)} />
          </div>
          {r.estornado > 0 && <p className="text-[11px] text-[var(--fg-3)]">Estornado ao longo do tempo: {fmtBRL(r.estornado)}.</p>}
        </>
      )}
    />
  );
}
