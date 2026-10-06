'use client';

// Aba "Jornada" da ficha: tudo o que a pessoa fez com a casa, em blocos por lançamento (mais recente primeiro).
// Cada bloco diz como ela chegou DAQUELA vez (UTM da entrada), se comprou/reembolsou e a linha do tempo dos pontos.
import { useMemo, useState } from 'react';
import { Badge, Button, Timeline, type TimelineEntry } from '@/shared/ui/components';
import { fmtBRL, fmtData, fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { ICONE_TIPO_JORNADA, ROTULO_FONTE, ROTULO_TIPO_JORNADA, agruparPorLancamento, type BlocoLancamento } from '../../domain/jornada';
import type { Funil, PontoJornada, TipoPontoJornada } from '../../domain/types';
import { Chip, ProdutoTag, Vazio } from '../comum';
import { alternadosPara, blocoAberto, chaveBloco, filtrarBlocos, paresUtm, tiposPresentes } from './ficha-contato';

const TOM_PONTO: Partial<Record<TipoPontoJornada, TimelineEntry['tone']>> = {
  inscricao: 'info', compra: 'green', reembolso: 'red', checkout: 'yellow', negocio: 'purple', conversa: 'info',
};
/** Pontos em que o valor importa (preço do checkout, compra, reembolso). */
const COM_VALOR: TipoPontoJornada[] = ['checkout', 'compra', 'reembolso', 'negocio'];

export function AbaJornada({ pontos, funis, onAbrirNegocio }: {
  pontos: PontoJornada[];
  funis: Funil[];
  onAbrirNegocio: (id: string) => void;
}) {
  const [tipos, setTipos] = useState<TipoPontoJornada[]>([]);
  const [alternados, setAlternados] = useState<Set<string>>(() => new Set());

  const blocos = useMemo(() => agruparPorLancamento(pontos), [pontos]);
  const presentes = useMemo(() => tiposPresentes(pontos), [pontos]);
  const visiveis = useMemo(() => filtrarBlocos(blocos, tipos), [blocos, tipos]);
  const chaves = visiveis.map(chaveBloco);
  const todosAbertos = chaves.every((k, i) => blocoAberto(i, k, alternados));

  if (!pontos.length) {
    return <Vazio titulo="Sem histórico" hint="Inscrições, compras, negócios e conversas da pessoa aparecem aqui." icone="clock" />;
  }

  const alternarTipo = (t: TipoPontoJornada) => setTipos((ts) => (ts.includes(t) ? ts.filter((x) => x !== t) : [...ts, t]));
  const alternarBloco = (k: string) => setAlternados((s) => {
    const n = new Set(s);
    if (n.has(k)) n.delete(k); else n.add(k);
    return n;
  });

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Filtrar por tipo de ponto">
        <Chip ativo={tipos.length === 0} onClick={() => setTipos([])}>Tudo</Chip>
        {presentes.map(({ tipo, n }) => (
          <Chip key={tipo} ativo={tipos.includes(tipo)} onClick={() => alternarTipo(tipo)} icone={ICONE_TIPO_JORNADA[tipo]}>
            {ROTULO_TIPO_JORNADA[tipo]} <span className="tabular text-[var(--fg-3)]">{n}</span>
          </Chip>
        ))}
        {visiveis.length > 1 && (
          <Button size="sm" variant="link" className="ml-auto" onClick={() => setAlternados(alternadosPara(!todosAbertos, chaves))}>
            {todosAbertos ? 'Recolher tudo' : 'Expandir tudo'}
          </Button>
        )}
      </div>

      {visiveis.length === 0 ? (
        <Vazio titulo="Nada com esse filtro" hint="Escolha outros tipos ou volte para Tudo." icone="sliders" />
      ) : (
        <ol className="space-y-3">
          {visiveis.map((b, i) => (
            <BlocoJornada
              key={chaveBloco(b)}
              b={b}
              funis={funis}
              aberto={blocoAberto(i, chaveBloco(b), alternados)}
              onAlternar={() => alternarBloco(chaveBloco(b))}
              onAbrirNegocio={onAbrirNegocio}
            />
          ))}
        </ol>
      )}
    </div>
  );
}

function BlocoJornada({ b, funis, aberto, onAlternar, onAbrirNegocio }: {
  b: BlocoLancamento; funis: Funil[]; aberto: boolean; onAlternar: () => void; onAbrirNegocio: (id: string) => void;
}) {
  const produto = b.pontos.find((p) => p.produto)?.produto ?? null;
  const utm = paresUtm(b.entrada?.utm);
  const funisDoLancamento = b.lancamento ? funis.filter((f) => f.projeto === b.lancamento).map((f) => f.nome) : [];
  const periodo = fmtData(b.inicio) === fmtData(b.fim) ? fmtData(b.inicio) : `${fmtData(b.inicio)} a ${fmtData(b.fim)}`;
  const idCorpo = `bloco-${chaveBloco(b)}`;

  const itens: TimelineEntry[] = b.pontos.map((p) => ({
    tone: TOM_PONTO[p.tipo] ?? 'base',
    icon: <Icon name={ICONE_TIPO_JORNADA[p.tipo]} size={10} />,
    title: p.titulo,
    meta: <>{fmtDataHora(p.em)} · {ROTULO_FONTE[p.fonte]}</>,
    body: <CorpoPonto p={p} onAbrirNegocio={onAbrirNegocio} />,
  }));

  return (
    <li className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)]">
      <button
        type="button"
        onClick={onAlternar}
        aria-expanded={aberto}
        aria-controls={idCorpo}
        className="flex w-full items-start justify-between gap-3 rounded-[var(--r-md)] px-3 py-2.5 text-left transition-colors hover:bg-[var(--surface-3)]"
      >
        <span className="min-w-0">
          <span className="flex min-w-0 flex-wrap items-center gap-1.5">
            <span className="truncate text-sm font-semibold text-[var(--fg)]">{b.lancamento ?? 'Fora de lançamento'}</span>
            {produto && <ProdutoTag k={produto} />}
            {b.comprou && <Badge tone="success">Comprou</Badge>}
            {b.reembolsou && <Badge tone="danger">Reembolso</Badge>}
          </span>
          <span className="mt-0.5 block text-xs text-[var(--fg-3)] tabular">
            {periodo} · {b.pontos.length} ponto{b.pontos.length > 1 ? 's' : ''}
            {funisDoLancamento.length > 0 && ` · ${funisDoLancamento.join(', ')}`}
          </span>
        </span>
        <span className="flex shrink-0 items-center gap-2">
          {b.comprou && <span className="text-sm font-semibold tabular text-[var(--fg)]" title="Pago líquido neste lançamento">{fmtBRL(b.valorPago)}</span>}
          <Icon name={aberto ? 'chevron-up' : 'chevron-down'} size={14} className="text-[var(--fg-3)]" />
        </span>
      </button>

      {aberto && (
        <div id={idCorpo} className="border-t border-[var(--border-faint)] px-3 pb-3 pt-2.5">
          {b.lancamento && (
            <div className="mb-3 text-xs">
              <span className="text-[var(--fg-3)]">Como chegou: </span>
              {utm.length ? (
                <span className="break-words text-[var(--fg-2)]">
                  {utm.map((u, i) => (
                    <span key={u.k}>{i > 0 && <span className="text-[var(--fg-4)]"> / </span>}<span className="text-[var(--fg-3)]">{u.k}</span> {u.v}</span>
                  ))}
                </span>
              ) : <span className="text-[var(--fg-3)]">sem UTM registrada</span>}
            </div>
          )}
          <Timeline items={itens} />
        </div>
      )}
    </li>
  );
}

function CorpoPonto({ p, onAbrirNegocio }: { p: PontoJornada; onAbrirNegocio: (id: string) => void }) {
  const utm = p.tipo === 'inscricao' ? paresUtm(p.utm) : [];
  const valor = p.valor != null && COM_VALOR.includes(p.tipo) ? fmtBRL(p.valor) : null;
  if (!p.detalhe && !valor && !utm.length && !p.negocioId) return null;
  return (
    <span className="block space-y-0.5">
      {p.detalhe && (
        <span className="block whitespace-pre-wrap">
          {p.tipo === 'pesquisa' && <span className="text-[var(--fg-3)]">Resposta: </span>}
          {p.detalhe}
        </span>
      )}
      {valor && <span className="block tabular text-[var(--fg)]">{valor}</span>}
      {utm.length > 0 && <span className="block break-words text-[var(--fg-3)]">{utm.map((u) => u.v).join(' / ')}</span>}
      {p.negocioId && (
        <Button size="sm" variant="link" onClick={() => onAbrirNegocio(p.negocioId!)}>Abrir negócio</Button>
      )}
    </span>
  );
}
