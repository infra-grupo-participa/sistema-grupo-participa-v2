'use client';

// Trajetória em marcos — só apresentação (sem repositório, sem query). Linha vertical com um nó por marco; clicar
// no marco abre a lista dos registros que o compõem (disclosure: botão com aria-expanded + aria-controls).
// Quem usa agrupa e formata (ex.: modules/alunos/domain/trajetoria-marcos.ts). Não substitui a LinhaDoTempo
// (lista plana do financeiro), que continua como está.
import { useId, useState, type ReactNode } from 'react';
import { Icon } from '@/shared/ui/icons';

/** Cor só onde significa algo: alerta (saída/estorno), positivo (volta), início (entrada). */
export type TomMarcoVisual = 'neutro' | 'inicio' | 'alerta' | 'positivo';

export interface SubItemMarco {
  id: string;
  /** Já formatado (dd/mm/aaaa). */
  quando: string;
  titulo: string;
  detalhe?: string | null;
  /** Já formatado. Ausente/null = nada é mostrado. */
  valor?: string | null;
  situacao?: string | null;
  /** Vai só no tooltip (regra e fonte, para a equipe conferir). */
  nota?: string | null;
}

export interface MarcoVisual {
  id: string;
  titulo: string;
  /** Já formatado: "12/03/2022" ou "mar/2022 a set/2026". */
  quando: string;
  resumo?: string | null;
  /** Já formatado. Ausente/null = nada é mostrado. */
  valor?: string | null;
  tom: TomMarcoVisual;
  /** Nome do ícone em shared/ui/icons. */
  icone: string;
  /** Capítulo (bloco de registros agrupados) ou marco próprio. Muda só o rótulo da contagem. */
  capitulo?: boolean;
  itens: SubItemMarco[];
}

export interface PontoRegua {
  id: string;
  /** 0..1 */
  pos: number;
  tom: TomMarcoVisual;
  rotulo: string;
}

const NO: Record<TomMarcoVisual, string> = {
  neutro: 'border-[var(--border-strong)] bg-[var(--surface-2)] text-[var(--fg-2)]',
  inicio: 'border-[var(--border-accent)] bg-[var(--accent-subtle)] text-[var(--accent)]',
  alerta: 'border-[var(--red-border)] bg-[var(--red-subtle)] text-[var(--red)]',
  positivo: 'border-[var(--green-border)] bg-[var(--green-subtle)] text-[var(--green)]',
};
const PONTO: Record<TomMarcoVisual, string> = {
  neutro: 'bg-[var(--fg-3)]',
  inicio: 'bg-[var(--accent)]',
  alerta: 'bg-[var(--red)]',
  positivo: 'bg-[var(--green)]',
};

export function TrajetoriaMarcos({ marcos, faixa, regua, ferramentas, vazio = 'Nenhum registro.', rotuloLista = 'Trajetória' }: {
  marcos: MarcoVisual[];
  /** Linha-resumo do topo (texto já montado). */
  faixa?: ReactNode;
  /** Mini-régua horizontal: pontos já posicionados (0..1) e rótulos das pontas. */
  regua?: { pontos: PontoRegua[]; de: string; ate: string } | null;
  /** Slot à esquerda do "Expandir tudo" (ex.: filtro). */
  ferramentas?: ReactNode;
  vazio?: string;
  rotuloLista?: string;
}) {
  const base = useId();
  const [abertos, setAbertos] = useState<Set<string>>(() => new Set());
  const todosAbertos = marcos.length > 0 && marcos.every((m) => abertos.has(m.id));
  const alternar = (id: string) => setAbertos((s) => {
    const n = new Set(s);
    if (n.has(id)) n.delete(id); else n.add(id);
    return n;
  });

  return (
    <div className="space-y-3">
      {faixa && <div className="text-xs text-[var(--fg-2)]">{faixa}</div>}
      {regua && regua.pontos.length > 0 && <Regua {...regua} />}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-0">{ferramentas}</div>
        {marcos.length > 0 && (
          <button
            type="button"
            onClick={() => setAbertos(todosAbertos ? new Set() : new Set(marcos.map((m) => m.id)))}
            className="text-xs font-medium text-[var(--accent)] hover:underline"
          >
            {todosAbertos ? 'Recolher tudo' : 'Expandir tudo'}
          </button>
        )}
      </div>
      {marcos.length === 0 ? (
        <p className="text-xs text-[var(--fg-3)]">{vazio}</p>
      ) : (
        <ol aria-label={rotuloLista} className="relative">
          {/* Fio da jornada: atrás dos nós (centro do nó de 28px = 14px). Dentro do <ol>, não aumenta a área rolável. */}
          <span aria-hidden className="absolute bottom-3 left-[13.5px] top-3 w-px bg-[var(--border-strong)]" />
          {marcos.map((m) => {
            const aberto = abertos.has(m.id);
            const painel = `${base}-${m.id}`;
            return (
              <li key={m.id} className="relative pb-2 pl-10 last:pb-0">
                <span aria-hidden className={`absolute left-0 top-1 grid h-7 w-7 place-items-center rounded-full border ${NO[m.tom]}`}>
                  <Icon name={m.icone} size={14} />
                </span>
                <button
                  type="button"
                  aria-expanded={aberto}
                  aria-controls={painel}
                  onClick={() => alternar(m.id)}
                  className="flex min-h-[36px] w-full items-start gap-2 rounded-[var(--r-sm)] px-1.5 py-1 text-left hover:bg-[var(--surface-2)]"
                >
                  <span className="min-w-0 flex-1">
                    <span className="flex flex-wrap items-baseline gap-x-2">
                      <span className={`text-sm font-semibold [overflow-wrap:anywhere] ${m.tom === 'alerta' ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>{m.titulo}</span>
                      <span className="tabular text-[11px] text-[var(--fg-3)]">{m.quando}</span>
                      {m.valor != null && <span className="tabular text-[11px] text-[var(--fg-2)]">{m.valor}</span>}
                    </span>
                    {m.resumo && <span className="block text-[11px] text-[var(--fg-2)] [overflow-wrap:anywhere]">{m.resumo}</span>}
                  </span>
                  <span className="flex shrink-0 items-center gap-1 pt-0.5 text-[11px] text-[var(--fg-3)]">
                    <span className="tabular">{m.itens.length}</span>
                    <span className="sr-only">{m.itens.length === 1 ? 'registro' : 'registros'}</span>
                    <Icon name={aberto ? 'chevron-up' : 'chevron-down'} size={14} />
                  </span>
                </button>
                <ul id={painel} hidden={!aberto} aria-label={`Registros: ${m.titulo}`} className="ml-1.5 mt-1 space-y-1 border-l border-[var(--border)] pl-3">
                  {m.itens.map((s) => (
                    <li key={s.id} className="text-[11px]" title={s.nota ?? undefined}>
                      <div className="flex flex-wrap items-baseline gap-x-2">
                        <span className="tabular text-[var(--fg-3)]">{s.quando}</span>
                        <span className="font-medium text-[var(--fg)] [overflow-wrap:anywhere]">{s.titulo}</span>
                        {s.valor != null && <span className="tabular text-[var(--fg-2)]">{s.valor}</span>}
                        {s.situacao && <span className="text-[var(--fg-3)]">· {s.situacao}</span>}
                      </div>
                      {s.detalhe && <div className="text-[var(--fg-2)] [overflow-wrap:anywhere]">{s.detalhe}</div>}
                    </li>
                  ))}
                </ul>
              </li>
            );
          })}
        </ol>
      )}
    </div>
  );
}

/** Régua horizontal: um ponto por marco principal no tempo. Pontos presos a [0,1] e com folga lateral (px-1.5 >
 *  meio ponto), para o ponto da ponta não vazar a largura do pai. */
function Regua({ pontos, de, ate }: { pontos: PontoRegua[]; de: string; ate: string }) {
  return (
    <div className="px-1.5" role="img" aria-label={`Linha do tempo de ${de} a ${ate}: ${pontos.map((p) => p.rotulo).join('; ')}`}>
      <div className="relative h-4">
        <span aria-hidden className="absolute inset-x-0 top-1/2 h-px bg-[var(--border-strong)]" />
        {pontos.map((p) => (
          <span
            key={p.id}
            aria-hidden
            title={p.rotulo}
            className={`absolute top-1/2 h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full ring-2 ring-[var(--surface-1)] ${PONTO[p.tom]}`}
            style={{ left: `${Math.min(1, Math.max(0, p.pos)) * 100}%` }}
          />
        ))}
      </div>
      <div className="flex justify-between text-[10px] text-[var(--fg-3)] tabular">
        <span>{de}</span>
        <span>{ate}</span>
      </div>
    </div>
  );
}
