'use client';

// Linha densa da agenda: ícone do tipo, título, uma linha de meta (contato · produto · etapa · cadência · dono)
// e o "quando" à direita. Sem fundo colorido: só o tempo de atraso fica em vermelho.
import Link from 'next/link';
import { useState } from 'react';
import { Badge, Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ICONE_ATIVIDADE, ROTULO_ATIVIDADE, produto as produtoDe } from '../../domain/catalogo';
import { fmtDataHora } from '@/shared/ui/format';
import type { Atividade, Contato, Negocio } from '../../domain/types';
import { tempoDesde, toquesDoDia } from './agenda';
import { ResultadosRapidos } from './ProximoPasso';

const hora = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' });

export function LinhaAgenda({ a, c, n, dono, motivoPerda = null, atrasada, agora, onAbrir, onConcluir }: {
  a: Atividade; c: Contato | undefined; n: Negocio | undefined;
  /** Rótulo do motivo (do cadastro) quando o negócio foi perdido. */
  motivoPerda?: string | null;
  /** Nome do dono (null = não mostrar, a lista já é só minha). */
  dono: string | null;
  atrasada: boolean; agora: Date;
  onAbrir?: () => void;
  /** Ausente = sem permissão (lead que não é seu não se toca) ou já concluída. */
  onConcluir?: (resultado: string) => Promise<boolean> | void;
}) {
  const [concluindo, setConcluindo] = useState(false);
  const feita = !!a.concluidaEm;
  const nome = c?.nome ?? '—';

  const meta: React.ReactNode[] = [];
  if (n) meta.push(produtoDe(n.produto).nome);
  if (n && n.status === 'aberto') meta.push(n.etapaNome);
  if (a.cadenciaDia) meta.push(<span key="cad" title="Toques do dia na cadência padrão">{toquesDoDia(a.cadenciaDia) ?? `dia ${a.cadenciaDia} da cadência`}</span>);
  if (dono) meta.push(dono);
  if (feita && a.resultado) meta.push(a.resultado);
  if (motivoPerda) meta.push(<span key="mot" title="Motivo da perda">{motivoPerda}</span>);

  const quando = feita
    ? { txt: `feita ${hora(a.concluidaEm!)}`, title: fmtDataHora(a.concluidaEm) }
    : atrasada
      ? { txt: `venceu ${tempoDesde(a.venceEm, agora)}`, title: `Venceu em ${fmtDataHora(a.venceEm)}` }
      : { txt: hora(a.venceEm), title: fmtDataHora(a.venceEm) };

  return (
    <li className="px-3 py-2">
      <div className="flex items-start gap-3">
        <Icon name={ICONE_ATIVIDADE[a.tipo]} size={16} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
        <span className="sr-only">{ROTULO_ATIVIDADE[a.tipo]}:</span>
        <div className="flex-1 min-w-0">
          <div className={`text-sm truncate ${feita ? 'text-[var(--fg-3)] line-through' : 'text-[var(--fg)] font-medium'}`}>{a.titulo}</div>
          <div className="mt-0.5 flex flex-wrap items-center gap-x-1.5 text-xs text-[var(--fg-3)] min-w-0">
            {onAbrir ? (
              <button type="button" onClick={onAbrir} title="Abrir a ficha do negócio" className="font-medium text-[var(--fg-2)] hover:text-[var(--fg)] hover:underline cursor-pointer truncate max-w-[220px]">
                {nome}
              </button>
            ) : (
              <span className="font-medium text-[var(--fg-2)] truncate max-w-[220px]" title="Sem negócio vinculado">{nome}</span>
            )}
            {meta.map((m, i) => <span key={i} className="inline-flex items-center gap-1.5"><span aria-hidden>·</span>{m}</span>)}
            {n && n.status !== 'aberto' && (
              <Badge tone={n.status === 'ganho' ? 'success' : 'danger'}>{n.status === 'ganho' ? 'Ganho' : 'Perdido'}</Badge>
            )}
          </div>
        </div>
        <span title={quando.title} className={`shrink-0 pt-0.5 text-xs tabular ${atrasada && !feita ? 'text-[var(--red)] font-semibold' : 'text-[var(--fg-3)]'}`}>
          {quando.txt}
        </span>
        <div className="shrink-0 flex items-center gap-1">
          {!feita && c && (
            <Link
              href={`/comercial/conversas?contato=${c.id}`}
              title={`Conversar com ${nome}`}
              aria-label={`Conversar com ${nome}`}
              className="grid place-items-center w-8 h-8 rounded-[var(--r-md)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]"
            >
              <Icon name="message" size={15} />
            </Link>
          )}
          {onConcluir && !feita && !concluindo && (
            <Button size="sm" variant="ghost" onClick={() => setConcluindo(true)} aria-label={`Concluir: ${a.titulo}`}>
              <Icon name="check" size={14} /> Concluir
            </Button>
          )}
        </div>
      </div>
      {concluindo && onConcluir && (
        <div className="mt-2 pl-7">
          <ResultadosRapidos
            onEscolher={async (res) => { const ok = await onConcluir(res); if (ok !== false) setConcluindo(false); }}
            onCancelar={() => setConcluindo(false)}
          />
        </div>
      )}
    </li>
  );
}
