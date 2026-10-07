'use client';

// Prévia do público: quantas pessoas entram, quem sai e por quê, e a amostra (só o gestor recebe; nome curto e
// e-mail mascarado, vindos assim do banco).
import type { PreviaPublico } from '../../domain/estrategias';
import { FaixaNumeros } from '../comum';

export function PreviaVista({ previa }: { previa: PreviaPublico }) {
  const ex = previa.excluidos;
  return (
    <div className="space-y-3" aria-live="polite">
      <FaixaNumeros
        rotulo="Prévia do público"
        itens={[
          { rotulo: 'Entram', valor: previa.total.toLocaleString('pt-BR') },
          { rotulo: 'Já compraram', valor: ex.jaComprou.toLocaleString('pt-BR') },
          { rotulo: 'Em negociação', valor: ex.emNegociacao.toLocaleString('pt-BR') },
          { rotulo: 'Em outra ação', valor: ex.outraAcao.toLocaleString('pt-BR') },
          { rotulo: 'Opt-out', valor: ex.optOut.toLocaleString('pt-BR') },
        ]}
      />
      {previa.amostra.length > 0 && (
        <div>
          <div className="mb-1 text-xs font-medium text-[var(--fg-2)]">Amostra (dados mascarados)</div>
          <ul className="grid gap-1.5 sm:grid-cols-2">
            {previa.amostra.map((a, i) => (
              <li key={`${a.nome}-${i}`} className="min-w-0 rounded-[var(--r-sm)] border border-[var(--border-faint)] bg-[var(--surface-2)] px-3 py-2">
                <div className="truncate text-sm text-[var(--fg)]">{a.nome}</div>
                <div className="truncate text-xs text-[var(--fg-3)]">
                  {[a.email, a.turma, a.nivel].filter(Boolean).join(' · ') || 'Sem dados extras'}
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
