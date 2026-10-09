'use client';

// Card do kanban em 3 linhas fixas: quem e quanto; produto e tempo na etapa; próximo passo e dono.
// Urgência num canal só: faixa lateral (vermelha ou amarela) + UM texto escrito. O resto fica neutro.
// A raiz é um <article> arrastável com um botão esticado que abre a ficha; as ações rápidas (conversa,
// agendar, mover) ficam por cima, sem botão dentro de botão. "Mover para…" é a alternativa ao arrastar.
// Travas espelhadas do banco (domain/travas.ts): negócio de outro dono fica só para leitura (sem arrastar, agendar
// nem mover) e a etapa que pede campo vazio aparece desativada com o que falta.
import Link from 'next/link';
import { AvatarInicial } from '@/shared/ui/components';
import { fmtBRL, fmtRelativo } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { ICONE_ATIVIDADE, ROTULO_ATIVIDADE, produto } from '../../domain/catalogo';
import { tempoNaEtapa } from '../../domain/regras';
import type { TravaMover } from '../../domain/travas';
import type { Contato, EtapaFunil, Negocio } from '../../domain/types';
import { Menu, type ItemMenu } from './pecas';
import { useDockConversa } from '../conversas/dock-contexto';
import { quandoCurto, urgenciaDoNegocio } from './regras-funil';

const BOTAO_ACAO = 'grid place-items-center w-7 h-7 [@media(hover:none)]:w-8 [@media(hover:none)]:h-8 rounded-[var(--r-sm)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-4)]';

export function CardNegocio({ n, c, agora, nomeDe, etapas, leitura, travaPara, onAbrir, onAbrirPessoa, onAgendar, onMover, onCopiarTelefone, arrastavel, onArrastar }: {
  n: Negocio;
  c: Contato | undefined;
  agora: Date;
  nomeDe: (id: string | null) => string;
  /** Etapas do funil, para o menu "Mover para…". */
  etapas: EtapaFunil[];
  /** Motivo de só leitura (negócio de outro dono / sem dono para vendedor). null = pode mexer. */
  leitura: string | null;
  /** Trava de cada etapa destino (dono, ganho, campos obrigatórios). */
  travaPara: (etapaId: string) => TravaMover;
  onAbrir: () => void;
  /** Abre a ficha da pessoa (dados, jornada, todos os negócios). */
  onAbrirPessoa?: () => void;
  onAgendar: () => void;
  onMover: (etapaId: string) => void;
  onCopiarTelefone: (tel: string) => void;
  arrastavel: boolean;
  /** Avisa o kanban do card que está sendo arrastado (null ao soltar). */
  onArrastar?: (negocioId: string | null) => void;
}) {
  const dock = useDockConversa();
  const aberto = n.status === 'aberto';
  const mexe = aberto && !leitura;
  const prox = n.proximaAtividade;
  const urg = urgenciaDoNegocio(n, agora);
  const corUrg = urg ? (urg.tom === 'red' ? 'var(--red)' : 'var(--yellow)') : null;
  const nome = c?.nome ?? 'Contato sem nome';
  const dono = n.donoId ? nomeDe(n.donoId) : null;

  const itensMenu: ItemMenu[] = [
    { rotulo: 'Abrir negócio', icone: 'file', onEscolher: onAbrir },
    ...(onAbrirPessoa ? [{ rotulo: 'Ficha da pessoa', icone: 'user', onEscolher: onAbrirPessoa }] : []),
    ...(c?.telefone ? [{ rotulo: 'Copiar telefone', icone: 'copy', onEscolher: () => onCopiarTelefone(c.telefone!) }] : []),
    ...(mexe ? [
      { rotulo: 'Mover para', grupo: true },
      ...etapas.map((e): ItemMenu => {
        const t = travaPara(e.id);
        return {
          rotulo: e.nome,
          ativo: e.id === n.etapaId,
          desativado: !t.permitido,
          dica: e.papel === 'fechado' ? 'só pela Hotmart' : t.faltam.length ? `falta ${t.faltam.length === 1 ? t.faltam[0] : `${t.faltam.length} campos`}` : undefined,
          titulo: t.faltam.length ? t.motivo ?? undefined : undefined,
          icone: t.faltam.length ? 'lock' : undefined,
          onEscolher: () => onMover(e.id),
        };
      }),
    ] : aberto && leitura ? [
      { rotulo: 'Somente leitura', grupo: true },
      { rotulo: 'Só o dono ou o gestor mexe', icone: 'lock', desativado: true, titulo: leitura },
    ] : []),
  ];

  // Tempo na etapa: vira o texto de urgência quando o prazo da etapa estourou.
  const tempoEtapa = urg && (urg.motivo === 'sla_critico' || urg.motivo === 'sla_atencao')
    ? <span className="font-medium" style={{ color: corUrg! }}>{urg.texto}</span>
    : <span>{tempoNaEtapa(n.etapaDesde, agora)} nesta etapa</span>;

  return (
    <article
      draggable={arrastavel && mexe}
      onDragStart={(e) => {
        e.dataTransfer.setData('text/negocio', n.id);
        e.dataTransfer.effectAllowed = 'move';
        onArrastar?.(n.id);
      }}
      onDragEnd={() => onArrastar?.(null)}
      aria-label={`${nome}, ${fmtValorCurto(n.valor)}${urg ? `, ${urg.texto}` : ''}`}
      className={`group relative rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] transition-colors hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] focus-within:border-[var(--border-strong)] ${arrastavel && mexe ? 'md:cursor-grab md:active:cursor-grabbing' : ''}`}
      style={{ boxShadow: corUrg ? `inset 3px 0 0 0 ${corUrg}, var(--shadow-sm)` : 'var(--shadow-sm)' }}
    >
      {/* Alvo principal: o card inteiro abre a ficha (teclado: Tab chega aqui, Enter abre). */}
      <button type="button" onClick={onAbrir} aria-label={`Abrir negócio de ${nome}`} className="absolute inset-0 z-0 w-full h-full rounded-[var(--r-md)] cursor-[inherit]" />

      <div className="relative z-[1] pointer-events-none px-3 py-2.5">
        {/* L1: nome + valor */}
        <div className="flex items-baseline justify-between gap-2">
          <span className="text-[13px] font-semibold text-[var(--fg)] truncate">{nome}</span>
          <span className="text-[13px] font-semibold tabular text-[var(--fg)] shrink-0">{fmtValorCurto(n.valor)}</span>
        </div>

        {/* L2: produto · tempo na etapa */}
        <div className="mt-0.5 flex items-center gap-1.5 text-xs text-[var(--fg-3)] min-w-0">
          <span className="truncate">{produto(n.produto).nome}</span>
          {aberto && <><span aria-hidden>·</span><span className="shrink-0">{tempoEtapa}</span></>}
        </div>

        {/* L3: próximo passo + dono */}
        <div className="mt-2 flex items-center justify-between gap-2 min-h-5 text-xs">
          {n.status === 'ganho' ? (
            <span className="flex items-center gap-1.5 text-[var(--green)]"><Icon name="check" size={13} /> Pago {fmtRelativo(n.fechadoEm).label}</span>
          ) : prox ? (
            <span className="flex items-center gap-1.5 min-w-0 text-[var(--fg-2)]" title={`${ROTULO_ATIVIDADE[prox.tipo]}: ${prox.titulo}`}>
              <Icon name={ICONE_ATIVIDADE[prox.tipo]} size={13} className="shrink-0 text-[var(--fg-3)]" />
              <span className="sr-only">{ROTULO_ATIVIDADE[prox.tipo]}:</span>
              {urg?.motivo === 'atrasada'
                ? <span className="truncate font-medium text-[var(--red)]">{urg.texto}</span>
                : <span className="truncate">{quandoCurto(prox.venceEm, agora)}</span>}
            </span>
          ) : (
            <span className={`flex items-center gap-1.5 ${urg?.motivo === 'sem_proximo' ? 'font-medium text-[var(--red)]' : 'text-[var(--fg-3)]'}`}>
              <Icon name="calendar" size={13} className="shrink-0" /> Sem próximo passo
            </span>
          )}

          <span className="flex items-center gap-1.5 shrink-0">
            {aberto && leitura && (
              <span title={leitura} className="inline-flex text-[var(--fg-3)]"><Icon name="lock" size={12} /><span className="sr-only">Somente leitura: {leitura}</span></span>
            )}
            {urg?.motivo === 'sem_dono' && <span className="font-medium text-[var(--red)]">Sem dono</span>}
            {dono ? (
              <span title={`Dono: ${dono}`} className="inline-flex"><AvatarInicial nome={dono} size={20} /><span className="sr-only">Dono: {dono}</span></span>
            ) : (
              <span role="img" aria-label="Sem dono" title="Sem dono" className="grid place-items-center w-5 h-5 rounded-full border border-dashed border-[var(--border-strong)] text-[11px] font-semibold text-[var(--fg-3)]">?</span>
            )}
          </span>
        </div>

        {/* Ações rápidas: aparecem no hover/foco (sempre visíveis no toque) sobre o canto do valor. */}
        <div className="pointer-events-auto absolute top-1.5 right-1.5 flex items-center gap-0.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-0.5 shadow-[var(--shadow-sm)] opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 [@media(hover:none)]:opacity-100 [@media(hover:none)]:static [@media(hover:none)]:mt-2 [@media(hover:none)]:w-fit [@media(hover:none)]:ml-auto transition-opacity">
          {c && (
            <Link href={`/comercial/conversas?contato=${encodeURIComponent(c.id)}`} draggable={false} aria-label={`Conversar com ${nome}`} title="Conversa" className={BOTAO_ACAO}
                  onClick={dock ? (e) => { if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return; e.preventDefault(); e.stopPropagation(); dock.abrir(c.id); } : undefined}>
              <Icon name="message" size={14} />
            </Link>
          )}
          {mexe && (
            <button type="button" draggable={false} onClick={onAgendar} aria-label={`Agendar próximo passo de ${nome}`} title="Agendar próximo passo" className={BOTAO_ACAO}>
              <Icon name="calendar" size={14} />
            </button>
          )}
          <Menu
            rotulo={`Mais ações de ${nome}`}
            itens={itensMenu}
            classeGatilho={BOTAO_ACAO}
            gatilho={<span aria-hidden className="text-base leading-none">⋯</span>}
          />
        </div>
      </div>
    </article>
  );
}

/** R$ 30 mil, R$ 1,2 mil, R$ 297. */
export function fmtValorCurto(v: number): string {
  if (v >= 1000) return `R$ ${(v / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mil`;
  return fmtBRL(v);
}
