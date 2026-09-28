'use client';

// Trajetória da pessoa com o Time Holding Brasil (fn_fin_trajetoria, 28/09/2026): todo funil em que participou (ingresso)
// ou comprou, na ordem, desde 2019. A turma é a de ORIGEM — quem voltou pelo Programa mantém a turma original.
import { useEffect, useState } from 'react';
import { Badge, Loading } from '@/shared/ui/components';
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
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <Numero rotulo="Turma de origem" valor={turma ?? '—'} />
        <Numero rotulo="1º contato" valor={r.primeiroContato ? fmtData(r.primeiroContato) : '—'} />
        <Numero rotulo="Funis" valor={`${r.funisParticipou} · comprou em ${r.funisComprou}`} />
        <Numero rotulo="Pago na vida" valor={fmtBRL(r.totalPago)} />
      </div>
      {r.estornado > 0 && <p className="text-[11px] text-[var(--fg-3)]">Estornado ao longo do tempo: {fmtBRL(r.estornado)}.</p>}
      <ol className="relative space-y-2 border-l border-[var(--border)] pl-4">
        {r.etapas.map((e) => (
          <li key={e.chave} className="relative">
            <span aria-hidden className={`absolute -left-[21px] top-1.5 h-2.5 w-2.5 rounded-full ${e.comprou ? 'bg-[var(--green)]' : e.participou ? 'bg-[var(--accent)]' : 'bg-[var(--fg-4)]'}`} />
            <div className="flex flex-wrap items-baseline gap-x-2">
              <span className="text-sm font-semibold text-[var(--fg)]">{e.evento ?? 'Fora de evento'}</span>
              <span className="tabular text-[11px] text-[var(--fg-3)]">{fmtData(e.inicio)}</span>
              {e.participou && <Badge tone="neutral">participou</Badge>}
              {e.comprou && <Badge tone="success">comprou</Badge>}
            </div>
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
          </li>
        ))}
      </ol>
    </div>
  );
}

function Numero({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2">
      <div className="text-[10px] uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className="tabular text-sm font-bold text-[var(--fg)]">{valor}</div>
    </div>
  );
}
